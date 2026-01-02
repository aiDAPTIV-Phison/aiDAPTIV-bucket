$ErrorActionPreference = 'Stop'
$pidFile = Join-Path $PSScriptRoot "app.pid"

if (Test-Path $pidFile) {
    $savedPid = Get-Content $pidFile -Raw
    if ($savedPid) {
        Write-Host "Stopping Langchain process (PID: $savedPid)..." -ForegroundColor Yellow
        Stop-Process -Id $savedPid.Trim() -Force -ErrorAction SilentlyContinue
    }
    # Clean up the PID file
    Remove-Item $pidFile -Force
    Write-Host "Process stopped and PID file removed." -ForegroundColor Green
} else {
    Write-Host "No PID file found. App might not be running." -ForegroundColor Gray
}