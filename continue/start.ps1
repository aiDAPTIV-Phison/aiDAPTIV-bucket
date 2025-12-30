$ErrorActionPreference = 'Stop'

# Define log file paths
$stdoutLog = Join-Path $PSScriptRoot 'vscode.log'
$stderrLog = Join-Path $PSScriptRoot 'vscode.err.log'

Write-Host "[INFO] Starting VS Code..."

# Start VS Code
try {
    Start-Process `
        -FilePath 'code' `
        -WorkingDirectory $PSScriptRoot `
        -RedirectStandardOutput $stdoutLog `
        -RedirectStandardError $stderrLog
    
    Write-Host "[INFO] VS Code started successfully"
    Write-Host "[INFO] Standard output log: $stdoutLog"
    Write-Host "[INFO] Standard error log: $stderrLog"
} catch {
    Write-Error "Failed to start VS Code: $_"
    exit 1
}

