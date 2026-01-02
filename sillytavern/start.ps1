$ErrorActionPreference = 'Stop'

# Get the directory where this script is located
$scriptDir = $PSScriptRoot
if (-not $scriptDir) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}

# Path to server.js
$serverPath = Join-Path $scriptDir 'server.js'

# Check if server.js exists
if (-not (Test-Path $serverPath)) {
    Write-Error "server.js not found at: $serverPath"
    exit 1
}

# Read port from config.txt or use default
$port = 8000
$configPath = Join-Path $scriptDir 'config.txt'
if (Test-Path $configPath) {
    $configContent = Get-Content $configPath -Raw
    if ($configContent -match 'port[\s=:]+(\d+)') {
        $port = [int]$matches[1]
    }
}

# Check if port is already in use
$portInUse = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue
if ($portInUse) {
    Write-Warning "Port $port is already in use. SillyTavern may already be running."
}

# Log file paths
$stdoutLog = Join-Path $scriptDir 'sillytavern.log'
$stderrLog = Join-Path $scriptDir 'sillytavern.err.log'

# Set working directory
Set-Location $scriptDir

# Set environment variables
$env:NODE_ENV = 'production'

# Start node server.js in background with hidden window
# Use Start-Process with -WindowStyle Hidden and redirect output to log files
try {
    $process = Start-Process `
        -FilePath 'node.exe' `
        -ArgumentList "server.js --port $port" `
        -WorkingDirectory $scriptDir `
        -WindowStyle Hidden `
        -RedirectStandardOutput $stdoutLog `
        -RedirectStandardError $stderrLog `
        -PassThru
    
    if (-not $process) {
        Write-Error "Failed to start SillyTavern process"
        exit 1
    }
    
    # Wait a moment to check if process started successfully
    Start-Sleep -Milliseconds 1000
    if ($process.HasExited -and $process.ExitCode -ne 0) {
        Write-Error "Failed to start SillyTavern. Exit code: $($process.ExitCode). Check logs: $stderrLog"
        exit 1
    }
    
    Write-Host "SillyTavern started successfully (PID: $($process.Id), Port: $port)"
    Write-Host "Logs: $stdoutLog"
    Write-Host "Error logs: $stderrLog"
} catch {
    Write-Error "Failed to start SillyTavern: $_"
    exit 1
}

