$ErrorActionPreference = 'Stop'

# Get the directory where this script is located
$scriptDir = $PSScriptRoot
if (-not $scriptDir) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}

# Path to server.js
$serverPath = Join-Path $scriptDir 'server.js'

function Stop-ProcessesByExecutablePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ExecutablePath
    )

    if (-not (Test-Path $ExecutablePath)) {
        return @()
    }

    $procs = Get-CimInstance Win32_Process |
        Where-Object { $_.ExecutablePath -and ($_.ExecutablePath -ieq $ExecutablePath) }

    foreach ($p in $procs) {
        Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
    }

    return $procs
}

# Stop node processes that are running server.js
$stoppedCount = 0

# Method 1: Find processes by command line containing server.js
try {
    $nodeProcs = Get-CimInstance Win32_Process |
        Where-Object { 
            $_.Name -eq 'node.exe' -and 
            $_.CommandLine -and 
            $_.CommandLine -like '*server.js*' -and
            ($_.CommandLine -like "*$scriptDir*" -or (Test-Path $serverPath))
        }
    
    foreach ($proc in $nodeProcs) {
        try {
            Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
            $stoppedCount++
        } catch {
            # Ignore errors
        }
    }
} catch {
    # Ignore errors
}

# Method 2: Stop all node.exe processes as fallback (more aggressive)
# Only do this if we're in the SillyTavern directory to avoid stopping other Node apps
try {
    $remainingProcs = Get-Process -Name 'node' -ErrorAction SilentlyContinue
    if ($remainingProcs) {
        foreach ($proc in $remainingProcs) {
            try {
                $procPath = $proc.Path
                if ($procPath -and (Test-Path $procPath)) {
                    # Check if this process is related to our server.js
                    $procCmdLine = (Get-CimInstance Win32_Process -Filter "ProcessId = $($proc.Id)").CommandLine
                    if ($procCmdLine -and $procCmdLine -like '*server.js*') {
                        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
                        $stoppedCount++
                    }
                }
            } catch {
                # Ignore errors
            }
        }
    }
} catch {
    # Ignore errors
}

# Wait a moment for processes to terminate
Start-Sleep -Seconds 1

Write-Host "Stopped $stoppedCount SillyTavern process(es)"

