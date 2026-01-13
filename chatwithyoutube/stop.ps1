$ErrorActionPreference = 'SilentlyContinue'

# Get current PowerShell process ID to exclude it
$currentPID = $PID

# Base directory
$dir = $PSScriptRoot

# List of directories to check
$checkPaths = @(
    $dir,
    (Join-Path $dir 'utils'),
    (Join-Path $dir '.venv')
)

# Normalize paths for comparison
$checkPathsLower = $checkPaths | ForEach-Object { $_.ToLower().TrimEnd('\') }

# Log file (align with start.log style: append)
$logPath = Join-Path $PSScriptRoot "stop.log"

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
Write-Log "Stop requested. ScriptPID=$currentPID" "INFO"
Write-Log "ScriptPath=$scriptPath. PSScriptRoot=$PSScriptRoot" "INFO"
Write-Log "Check paths: $($checkPaths -join ', ')" "INFO"

# Get all processes
$allProcs = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue

# Search for processes in the specified directories
$procsToStop = @()

foreach ($proc in $allProcs) {
    # Skip the current PowerShell process
    if ($proc.ProcessId -eq $currentPID) {
        continue
    }
    
    $procPath = $proc.ExecutablePath
    $procCmdLine = $proc.CommandLine
    $isMatch = $false
    
    # Check if process executable is in any of the check paths
    if ($procPath) {
        $procPathLower = $procPath.ToLower()
        foreach ($checkPath in $checkPathsLower) {
            if ($procPathLower.StartsWith($checkPath + '\') -or $procPathLower -eq $checkPath) {
                $isMatch = $true
                Write-Log "Match found (executable path): PID=$($proc.ProcessId), Name=$($proc.Name), Path=$procPath" "INFO"
                break
            }
        }
    }
    
    # Check if command line contains any of the check paths
    if ($procCmdLine -and -not $isMatch) {
        $cmdLineLower = $procCmdLine.ToLower()
        foreach ($checkPath in $checkPathsLower) {
            if ($cmdLineLower.Contains($checkPath)) {
                $isMatch = $true
                $cmdPreview = $procCmdLine.Substring(0, [Math]::Min(100, $procCmdLine.Length))
                Write-Log "Match found (command line): PID=$($proc.ProcessId), Name=$($proc.Name), CmdLine=$cmdPreview..." "INFO"
                break
            }
        }
    }
    
    # Check process executable location
    if (-not $isMatch) {
        try {
            $procObj = Get-Process -Id $proc.ProcessId -ErrorAction SilentlyContinue
            if ($procObj -and $procObj.Path) {
                $procDir = (Split-Path $procObj.Path -Parent).ToLower().TrimEnd('\')
                foreach ($checkPath in $checkPathsLower) {
                    if ($procDir -and ($procDir -eq $checkPath -or $procDir.StartsWith($checkPath + '\'))) {
                        $isMatch = $true
                        Write-Log "Match found (process directory): PID=$($proc.ProcessId), Name=$($proc.Name), Dir=$procDir" "INFO"
                        break
                    }
                }
            }
        } catch {
            # Ignore errors
        }
    }
    
    # Check process modules (DLLs) loaded from check paths
    if (-not $isMatch) {
        try {
            $procObj = Get-Process -Id $proc.ProcessId -ErrorAction SilentlyContinue
            if ($procObj -and $procObj.Modules) {
                foreach ($module in $procObj.Modules) {
                    if ($module.FileName) {
                        $modulePath = $module.FileName.ToLower()
                        foreach ($checkPath in $checkPathsLower) {
                            if ($modulePath.StartsWith($checkPath + '\') -or $modulePath -eq $checkPath) {
                                $isMatch = $true
                                Write-Log "Match found (loaded module): PID=$($proc.ProcessId), Name=$($proc.Name), Module=$($module.FileName)" "INFO"
                                break
                            }
                        }
                        if ($isMatch) { break }
                    }
                }
            }
        } catch {
            # Ignore errors
        }
    }
    
    if ($isMatch) {
        $procsToStop += $proc
    }
}

Write-Log "Found $($procsToStop.Count) process(es) related to checked directories" "INFO"

# Root PIDs to stop (exclude current script PID)
$rootPids = @($procsToStop | Select-Object -ExpandProperty ProcessId | Where-Object { $_ -and $_ -ne $currentPID } | Sort-Object -Unique)

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

# Stop all found processes
if (-not $rootPids -or $rootPids.Count -eq 0) {
    Write-Log "No related process found in checked directories." "INFO"
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

Write-Log "Found $($rootPids.Count) root process(es) in checked directories. Stopping $($allPidsToStop.Count) PID(s) total (including children)..." "INFO"
Write-Log "PIDs to stop: $($allPidsToStop -join ', ')" "INFO"

function Kill-Pid {
    param([Parameter(Mandatory=$true)][int]$ProcessId)
    
    # Ensure errors are not silently swallowed in this function
    $ErrorActionPreference = 'Continue'

    if ($ProcessId -eq $currentPID) { 
        Write-Log "Skipping current script PID: $ProcessId" "INFO"
        return $false 
    }

    # Check if process exists before attempting to kill
    $gp = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if (-not $gp) {
        Write-Log "Process $ProcessId already terminated (skipping)" "INFO"
        return $true
    }

    # Get friendly process info
    $name = $gp.ProcessName
    $path = $gp.Path
    $label = if ($name) { "$name (PID: $ProcessId)" } else { "PID: $ProcessId" }
    
    Write-Log "Attempting to stop ${label} ..." "INFO"
    if ($path) { Write-Log "Process path: $path" "INFO" }

    # Attempt Stop-Process
    $stopProcessSuccess = $false
    try {
        Stop-Process -Id $ProcessId -Force -ErrorAction Stop
        $stopProcessSuccess = $true
        Write-Log "Stop-Process succeeded for $label" "INFO"
    } catch {
        Write-Log "Stop-Process failed for ${label}: $($_.Exception.Message)" "ERROR"
    }

    # Wait a moment for process to terminate
    Start-Sleep -Milliseconds 300

    # Check if process still exists
    $stillExists = $false
    try {
        $p2 = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
        if ($p2) { 
            $stillExists = $true
        }
    } catch {}

    # Only use taskkill if Stop-Process failed and process still exists
    if ($stillExists -and -not $stopProcessSuccess) {
        Write-Log "Process still running, trying taskkill /F /T /PID $ProcessId ..." "WARN"
        try {
            $tk = & taskkill /F /T /PID $ProcessId 2>&1
            $taskkillExitCode = $LASTEXITCODE
            
            if ($taskkillExitCode -eq 0) {
                Write-Log "taskkill succeeded for $label" "INFO"
                Start-Sleep -Milliseconds 300
            } else {
                Write-Log "taskkill failed with exit code $taskkillExitCode for $label" "ERROR"
            }
        } catch {
            Write-Log "taskkill threw exception for ${label}: $($_.Exception.Message)" "ERROR"
        }
    }

    # Final verification
    Start-Sleep -Milliseconds 200
    $stillExists = $false
    try {
        $p3 = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
        if ($p3) { 
            $stillExists = $true
            Write-Log "FINAL RESULT: Process still running after all attempts: $label" "ERROR"
        }
    } catch {}

    if ($stillExists) {
        return $false
    } else {
        Write-Log "Successfully terminated: $label" "INFO"
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

Write-Log "Done! Stopped $($allPidsToStop.Count) process(es)." "INFO"