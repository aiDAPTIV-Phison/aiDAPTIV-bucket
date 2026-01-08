param (
   [string]$svcName = 'W32Time',
   [int]$delay = 5
)
$ErrorActionPreference = 'STOP'
# 檢查是否已為管理員
$wp = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-Not $wp.IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")) {
   $rawCmd = $MyInvocation.Line
   $rawArgs = $rawCmd.Substring($rawCmd.IndexOf('.ps1') + 4)
   # 處理檔案總管右鍵「用 PowerShell 執行」的特殊指令
   if ($rawCmd.StartsWith('if')) { $rawArgs = '' }
   Start-Process Powershell -Verb RunAs -ArgumentList "$PSCommandPath $rawArgs"
   exit
}
 
$ErrorActionPreference = 'SilentlyContinue'

# Get current PowerShell process ID to exclude it
$currentPID = $PID

# Target port to stop (Streamlit default is 8501)
$port = 8501

# Log file (align with start.log style: append)
$logPath = Join-Path $PSScriptRoot "stop.log"

function Test-IsAdmin {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $p = New-Object Security.Principal.WindowsPrincipal($id)
        return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Write-Log {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO'
    )

    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$Level] $ts $Message"
    try {
        Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch {
        # ignore logging errors
    }
    Write-Host $line
}

$scriptPath = $null
try { $scriptPath = $MyInvocation.MyCommand.Path } catch { $scriptPath = $null }
$isAdmin = Test-IsAdmin
Write-Log "Stop requested. Target port=$port. ScriptPID=$currentPID. IsAdmin=$isAdmin" "INFO"
Write-Log "ScriptPath=$scriptPath. PSScriptRoot=$PSScriptRoot" "INFO"

# Get PIDs that are listening on the target port
$pidsToStop = @()
$detectMethod = ""

try {
    # Preferred: available on modern Windows/PowerShell
    $conns = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction Stop
    $pidsToStop = $conns | Select-Object -ExpandProperty OwningProcess -Unique
    $detectMethod = "Get-NetTCPConnection"
} catch {
    # Fallback: parse netstat output
    try {
        $detectMethod = "netstat"
        $netstatLines = & netstat -ano -p tcp 2>$null
        foreach ($line in $netstatLines) {
            # Examples:
            #   TCP    0.0.0.0:8501           0.0.0.0:0              LISTENING       1234
            #   TCP    [::]:8501              [::]:0                 LISTENING       1234
            if ($line -match "^\s*TCP\s+\S+:\b$port\b\s+\S+\s+LISTENING\s+(\d+)\s*$") {
                $pid = 0
                if ([int]::TryParse($matches[1], [ref]$pid)) {
                    $pidsToStop += $pid
                }
            }
        }
        $pidsToStop = $pidsToStop | Sort-Object -Unique
    } catch {
        $pidsToStop = @()
        $detectMethod = "none"
    }
}

# Log detection result
if (-not $detectMethod) { $detectMethod = "unknown" }
if ($pidsToStop -and $pidsToStop.Count -gt 0) {
    Write-Log "Detected listener(s) on port $port via $detectMethod. PID(s)=$($pidsToStop -join ',')" "INFO"
} else {
    Write-Log "No listener detected on port $port via $detectMethod." "INFO"
}

# Root PIDs to stop (exclude current script PID)
$rootPids = @($pidsToStop | Where-Object { $_ -and $_ -ne $currentPID } | Sort-Object -Unique)

# Get all child processes recursively
function Get-ChildProcesses {
    param([int]$ParentPID)
    $children = @()
    $directChildren = Get-CimInstance Win32_Process | Where-Object { $_.ParentProcessId -eq $ParentPID }
    foreach ($child in $directChildren) {
        $children += $child
        $children += Get-ChildProcesses -ParentPID $child.ProcessId
    }
    return $children
}

# Stop all found processes (based on PID, not Win32_Process resolution)
if (-not $rootPids -or $rootPids.Count -eq 0) {
    Write-Log "No process found listening on port $port." "INFO"
    Write-Log "Done! Stopped 0 process(es)." "INFO"
    exit 0
}

# Expand to include child PIDs
$childProcs = @()
foreach ($procId in $rootPids) {
    Write-Log "Searching for child processes of PID $procId ..." "INFO"
    $children = Get-ChildProcesses -ParentPID $procId
    if ($children -and $children.Count -gt 0) {
        Write-Log "Found $($children.Count) child process(es) for PID $procId" "INFO"
        foreach ($child in $children) {
            Write-Log "  - Child: PID=$($child.ProcessId), Name=$($child.Name)" "INFO"
        }
    } else {
        Write-Log "No child processes found for PID $procId" "INFO"
    }
    $childProcs += $children
}

$allPidsToStop = @($rootPids + ($childProcs | Select-Object -ExpandProperty ProcessId -ErrorAction SilentlyContinue)) |
    Where-Object { $_ -and $_ -ne $currentPID } |
    Sort-Object -Unique

Write-Log "Found $($rootPids.Count) root process(es) listening on port $port. Stopping $($allPidsToStop.Count) PID(s) total (including children)..." "INFO"
Write-Log "PIDs to stop: $($allPidsToStop -join ', ')" "INFO"

function Kill-Pid {
    param([Parameter(Mandatory=$true)][int]$ProcessId)
    
    # Ensure errors are not silently swallowed in this function
    $ErrorActionPreference = 'Continue'

    Write-Log "=== Kill-Pid function called for PID: $ProcessId ===" "INFO"

    if ($ProcessId -eq $currentPID) { 
        Write-Log "Skipping current script PID: $ProcessId" "INFO"
        return $false 
    }

    # Try to get friendly process info (best effort)
    $name = $null
    $path = $null
    try {
        $gp = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
        if ($gp) { 
            $name = $gp.ProcessName 
            $path = $gp.Path
        }
    } catch {
        Write-Log "Could not get process info for PID $ProcessId : $($_.Exception.Message)" "WARN"
    }

    $label = if ($name) { "$name (PID: $ProcessId)" } else { "PID: $ProcessId" }
    Write-Log "Attempting to stop ${label} ..." "INFO"
    if ($path) { Write-Log "Process path: $path" "INFO" }

    # Attempt Stop-Process (may fail without admin)
    $stopProcessSuccess = $false
    try {
        Write-Log "Trying Stop-Process -Id $ProcessId -Force ..." "INFO"
        Stop-Process -Id $ProcessId -Force -ErrorAction Stop
        $stopProcessSuccess = $true
        Write-Log "Stop-Process succeeded for $label" "INFO"
    } catch {
        Write-Log "Stop-Process failed for ${label}: $($_.Exception.Message)" "ERROR"
        Write-Log "Stop-Process error type: $($_.Exception.GetType().FullName)" "ERROR"
    }

    # Always attempt taskkill as stronger fallback; capture output for debugging
    $taskkillSuccess = $false
    try {
        Write-Log "Trying taskkill /F /T /PID $ProcessId ..." "INFO"
        $tk = & taskkill /F /T /PID $ProcessId 2>&1
        $taskkillExitCode = $LASTEXITCODE
        Write-Log "taskkill exit code: $taskkillExitCode" "INFO"
        
        if ($tk) {
            foreach ($line in $tk) {
                Write-Log "taskkill output: $($line.ToString())" "INFO"
            }
        } else {
            Write-Log "taskkill returned no output for $label" "INFO"
        }
        
        if ($taskkillExitCode -eq 0) {
            $taskkillSuccess = $true
            Write-Log "taskkill succeeded for $label" "INFO"
        } else {
            Write-Log "taskkill failed with exit code $taskkillExitCode for $label" "ERROR"
        }
    } catch {
        Write-Log "taskkill threw exception for ${label}: $($_.Exception.Message)" "ERROR"
    }

    # Wait a moment for process to terminate
    Start-Sleep -Milliseconds 500

    # Confirm whether process still exists
    $stillExists = $false
    try {
        $p2 = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
        if ($p2) { 
            $stillExists = $true 
            Write-Log "Process still exists after kill attempts: $label (Name: $($p2.ProcessName))" "ERROR"
        }
    } catch {}

    if ($stillExists) {
        Write-Log "FINAL RESULT: Process still running after all kill attempts: $label" "ERROR"
        return $false
    } else {
        Write-Log "FINAL RESULT: Process terminated successfully: $label" "INFO"
        return $true
    }
}

foreach ($procId in $allPidsToStop) {
    Write-Log "Stopping PID $procId ..." "INFO"
    try {
        $ok = Kill-Pid -ProcessId $procId
        if ($ok) {
            Write-Log "Kill result for PID ${procId}: success" "INFO"
        } else {
            Write-Log "Kill result for PID ${procId}: failed (may require Administrator privileges, or process may have restarted)" "WARN"
        }
    } catch {
        Write-Log "Exception when calling Kill-Pid for PID ${procId}: $($_.Exception.Message)" "ERROR"
        Write-Log "Exception type: $($_.Exception.GetType().FullName)" "ERROR"
        Write-Log "Stack trace: $($_.ScriptStackTrace)" "ERROR"
    }
}

# Verify port is no longer listening
try {
    $maxTries = 6
    $stillPids = @()
    for ($i = 1; $i -le $maxTries; $i++) {
        $still = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
        if ($still) {
            $stillPids = $still | Select-Object -ExpandProperty OwningProcess -Unique
            Start-Sleep -Milliseconds 500
        } else {
            $stillPids = @()
            break
        }
    }

    if ($stillPids -and $stillPids.Count -gt 0) {
        Write-Log "WARNING: Port $port still appears to be listening. PID(s)=$($stillPids -join ',')" "WARN"
        Write-Log "Tip: try running PowerShell as Administrator (some processes can't be killed without elevation)." "WARN"
    } else {
        Write-Log "Verified: port $port is not listening." "INFO"
    }
} catch {
    # If Get-NetTCPConnection isn't available, skip verification silently
}

# Additional cleanup: find and kill orphaned Streamlit/uvicorn processes
Write-Log "Searching for orphaned Streamlit/Python processes..." "INFO"
$streamlitProcs = @()
try {
    # Look for processes with "streamlit" in command line
    $allProcs = Get-CimInstance Win32_Process -Filter "Name='python.exe' OR Name='pythonw.exe' OR Name='uv.exe'" -ErrorAction SilentlyContinue
    foreach ($proc in $allProcs) {
        $cmdLine = $proc.CommandLine
        if ($cmdLine -and ($cmdLine -like "*streamlit*" -or $cmdLine -like "*app.py*" -or $cmdLine -like "*uvicorn*")) {
            if ($proc.ProcessId -ne $currentPID) {
                $streamlitProcs += $proc.ProcessId
                Write-Log "Found orphaned process: PID=$($proc.ProcessId), Name=$($proc.Name), CommandLine=$($cmdLine.Substring(0, [Math]::Min(100, $cmdLine.Length)))..." "INFO"
            }
        }
    }
} catch {
    Write-Log "Could not search for orphaned processes: $($_.Exception.Message)" "WARN"
}

if ($streamlitProcs -and $streamlitProcs.Count -gt 0) {
    Write-Log "Found $($streamlitProcs.Count) orphaned Streamlit/Python process(es). Cleaning up..." "INFO"
    foreach ($orphanPid in $streamlitProcs) {
        try {
            $ok = Kill-Pid -ProcessId $orphanPid
            if ($ok) {
                Write-Log "Cleaned up orphaned PID ${orphanPid}: success" "INFO"
            } else {
                Write-Log "Could not clean up orphaned PID ${orphanPid}: failed" "WARN"
            }
        } catch {
            Write-Log "Exception cleaning up orphaned PID ${orphanPid}: $($_.Exception.Message)" "ERROR"
        }
    }
} else {
    Write-Log "No orphaned Streamlit/Python processes found." "INFO"
}

Write-Log "Done! Stopped $($allPidsToStop.Count) process(es) + $($streamlitProcs.Count) orphaned process(es)." "INFO"