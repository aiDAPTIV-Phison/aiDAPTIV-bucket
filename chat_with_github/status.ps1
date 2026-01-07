$ErrorActionPreference = 'SilentlyContinue'

# We check if the Backend Port is listening. 
$backendPort = 8001
$configPath = Join-Path $PSScriptRoot "config.txt"

# Try to read port from config if changed
if (Test-Path $configPath) {
    $line = Get-Content $configPath | Where-Object { $_ -match "BACKEND_PORT=" }
    if ($line) { $backendPort = $line.Split('=')[1].Trim() }
}

$isRunning = 0
try {
    # Check TCP connection on the backend port
    $conn = Get-NetTCPConnection -LocalPort $backendPort -State Listen -ErrorAction Stop
    if ($conn) { $isRunning = 1 }
} catch {
    $isRunning = 0
}

# Return JSON for UniGetUI
@{ status = $isRunning } | ConvertTo-Json -Compress