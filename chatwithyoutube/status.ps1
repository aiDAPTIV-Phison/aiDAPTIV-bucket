$ErrorActionPreference = 'Stop'

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
$procsFound = @()

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
    
    # Check if command line contains app.py (the main application)
    if ($procCmdLine -and -not $isMatch) {
        $cmdLineLower = $procCmdLine.ToLower()
        if ($cmdLineLower.Contains('app.py') -or $cmdLineLower.Contains('uv run app.py')) {
            $isMatch = $true
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
        $procsFound += $proc
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

$allProcsFound = @($procsFound)
foreach ($proc in $procsFound) {
    $children = Get-ChildProcesses -ParentPID $proc.ProcessId
    $allProcsFound += $children
}

# Remove duplicates and exclude current process
$allProcsFound = $allProcsFound | Where-Object { $_.ProcessId -ne $currentPID } | Sort-Object -Unique -Property ProcessId

# Determine if application is running
$isRunning = ($allProcsFound.Count -gt 0)

# Return JSON status
$status = if ($isRunning) { 1 } else { 0 }
$json = @{
    status = $status
} | ConvertTo-Json -Compress

Write-Host $json

