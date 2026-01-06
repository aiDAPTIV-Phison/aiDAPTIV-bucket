$ErrorActionPreference = 'Stop'

# Get the directory where this script is located
$scriptDir = $PSScriptRoot
if (-not $scriptDir) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}

# Read port from config.txt or use default
$port = 18006
$configPath = Join-Path $scriptDir 'config.txt'
if (Test-Path $configPath) {
    $configContent = Get-Content $configPath -Raw
    if ($configContent -match 'port[\s=:]+(\d+)') {
        $port = [int]$matches[1]
    }
}

$isRunning = $false

# Method 1: Check if port is listening
try {
    $portConnection = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
    if ($portConnection) {
        $isRunning = $true
    }
} catch {
    # Ignore errors
}

# Method 2: Check if node process is running server.js
if (-not $isRunning) {
    try {
        $nodeProcs = Get-CimInstance Win32_Process |
            Where-Object { 
                $_.Name -eq 'node.exe' -and 
                $_.CommandLine -and 
                $_.CommandLine -like '*server.js*' -and
                ($_.CommandLine -like "*$scriptDir*" -or (Test-Path (Join-Path $scriptDir 'server.js')))
            }
        
        if ($nodeProcs -and $nodeProcs.Count -gt 0) {
            $isRunning = $true
        }
    } catch {
        # Ignore errors
    }
}

# Method 3: Try to connect to the HTTP endpoint as final check
if (-not $isRunning) {
    try {
        $response = Invoke-WebRequest -Uri "http://127.0.0.1:$port" -TimeoutSec 2 -ErrorAction Stop
        if ($response.StatusCode -eq 200 -or $response.StatusCode -eq 404) {
            $isRunning = $true
        }
    } catch {
        # Ignore errors - service is not running
    }
}

# Return JSON status
$status = if ($isRunning) { 1 } else { 0 }
$json = @{
    status = $status
} | ConvertTo-Json -Compress

Write-Host $json

