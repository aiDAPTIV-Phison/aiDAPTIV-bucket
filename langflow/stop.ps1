$ErrorActionPreference = 'Stop'
$pidFile = Join-Path $PSScriptRoot "app.pid"

if (Test-Path $pidFile) {
    $savedPid = (Get-Content $pidFile -Raw).Trim()
    if ($savedPid) {
        Write-Host "Stopping Langflow services (PID: $savedPid)..." -ForegroundColor Yellow
        
        # 1. Kill the Main Process recorded in the PID file
        Stop-Process -Id $savedPid -Force -ErrorAction SilentlyContinue

        # 2. Safety Net: Kill any process still holding the Langflow Port (7860)
        # This catches the 'Worker' processes that Langflow/Uvicorn spawns
        $portProcess = Get-NetTCPConnection -LocalPort 7860 -State Listen -ErrorAction SilentlyContinue
        if ($portProcess) {
            Write-Host "Cleaning up residual worker processes..." -ForegroundColor Gray
            Stop-Process -Id $portProcess.OwningProcess -Force -ErrorAction SilentlyContinue
        }
    }
    
    # Clean up the PID file
    Remove-Item $pidFile -Force
    Write-Host "Langflow stopped and PID file removed." -ForegroundColor Green
} else {
    Write-Host "No PID file found. Langflow might not be running." -ForegroundColor Gray
}