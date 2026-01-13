$ErrorActionPreference = 'Stop'

Write-Host ">>> SCRIPT STARTED (Langflow)" -ForegroundColor Magenta
Start-Sleep -Seconds 2

# Path definition
$rootDir = $PSScriptRoot
$langflowDir = Join-Path $rootDir "app"
$pyPath = Join-Path $langflowDir "python\python.exe"
$backendPath = Join-Path $langflowDir "langflow\src\backend\base"
$configPath = Join-Path $rootDir "config.txt"
$pidFile = Join-Path $rootDir "app.pid"

# Define log path
$stdOutLog = Join-Path $rootDir "app.log"
$stdErrLog = Join-Path $rootDir "app.err.log"

# Load Configuration
Write-Host ">>> Loading Config..." -ForegroundColor Cyan
if (Test-Path $configPath) {
    Get-Content $configPath | ForEach-Object {
        if ($_ -match "^\s*[^#]\w+=") {
            $name, $value = $_.split('=', 2)
            $name = $name.Trim()
            $value = $value.Trim()
            [System.Environment]::SetEnvironmentVariable($name, $value, "Process")
        }
    }
}

# Cache sync logic
$flowUuid = "e7e17006-738b-45e4-8184-141f18c86d9a"
$cacheDir = Join-Path $env:LOCALAPPDATA "langflow\langflow\Cache\$flowUuid"
$sourceDocs = Join-Path $langflowDir "docs\$flowUuid"

if (!(Test-Path $cacheDir)) { New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null }
if (Test-Path $sourceDocs) { Copy-Item -Path "$sourceDocs\*" -Destination $cacheDir -Recurse -Force }

# Launch backend
Write-Host ">>> Launching Langflow Backend..." -ForegroundColor Cyan


$env:PYTHONUTF8 = "1"
$env:LANGFLOW_LOAD_FLOWS_PATH = Join-Path $langflowDir "flows"

$uvicornArgs = "-m uvicorn --factory langflow.main:setup_app --host 127.0.0.1 --port 7860 --loop asyncio"

# Start procress and redirect logs
$proc = Start-Process -FilePath $pyPath -ArgumentList $uvicornArgs `
    -WorkingDirectory $backendPath -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput $stdOutLog `
    -RedirectStandardError $stdErrLog

# record PID
$proc.Id | Out-File $pidFile -Force

Write-Host "    Logging to: app.log and app.err.log" -ForegroundColor Gray

# Wait for Port 7860 to be Ready
Write-Host ">>> Waiting for Langflow to initialize on Port 7860..." -ForegroundColor Yellow

$isReady = $false

while (-not $isReady) {
    # Check if the port is listening
    if (Get-NetTCPConnection -LocalPort 7860 -State Listen -ErrorAction SilentlyContinue) {
        $isReady = $true
    } else {
	# Visual heartbeat
        Write-Host "." -NoNewline -ForegroundColor DarkYellow
        Start-Sleep -Seconds 1
        
        # CRITICAL CHECK: Ensure the process didn't die while we were waiting
        if ($null -eq (Get-Process -Id $proc.Id -ErrorAction SilentlyContinue)) {
            Write-Host "`n>>> ERROR: Langflow process died during startup!" -ForegroundColor Red
            Write-Host ">>> Checking app.err.log for details:" -ForegroundColor Red
            if (Test-Path $stdErrLog) { Get-Content $stdErrLog -Tail 5 }
            break
        }
    }
}

if ($isReady) {
    Write-Host ">>> SUCCESS: Langflow is fully loaded and listening on Port 7860!" -ForegroundColor Green
} else {
    # Keep window open if it failed so you can read the error
    Write-Host ">>> SETUP FAILED. Press Enter to exit..." -ForegroundColor Red
    Read-Host
}
