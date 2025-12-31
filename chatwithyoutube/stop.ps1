$ErrorActionPreference = 'SilentlyContinue'

# Get current PowerShell process ID to exclude it
$currentPID = $PID

# Base directory
$dir = $PSScriptRoot

# List of directories to check
$checkPaths = @(
    $dir
)

# Normalize paths for comparison
$checkPathsLower = $checkPaths | ForEach-Object { $_.ToLower().TrimEnd('\') }

# Get all processes
$allProcs = Get-CimInstance Win32_Process

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

$allProcsToStop = @($procsToStop)
foreach ($proc in $procsToStop) {
    $children = Get-ChildProcesses -ParentPID $proc.ProcessId
    $allProcsToStop += $children
}

# Remove duplicates and exclude current process
$allProcsToStop = $allProcsToStop | Where-Object { $_.ProcessId -ne $currentPID } | Sort-Object -Unique -Property ProcessId

# Stop all found processes
Write-Host "Found $($allProcsToStop.Count) related process(es), stopping..."

foreach ($p in $allProcsToStop) {
    # Double check: skip current process
    if ($p.ProcessId -eq $currentPID) {
        continue
    }
    
    $procInfo = "$($p.Name) (PID: $($p.ProcessId))"
    if ($p.CommandLine) {
        $cmdPreview = $p.CommandLine.Substring(0, [Math]::Min(80, $p.CommandLine.Length))
        $procInfo += " - $cmdPreview"
    }
    Write-Host "Stopping: $procInfo"
    
    try {
        Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
        if (-not $?) {
            & taskkill /F /PID $p.ProcessId 2>&1 | Out-Null
        }
    } catch {
        & taskkill /F /PID $p.ProcessId 2>&1 | Out-Null
    }
}

Write-Host "Done! Stopped $($allProcsToStop.Count) process(es)."