$ErrorActionPreference = 'Stop'

# Read configuration from config.txt (corresponding to setup_and_run.bat config reading)
$configFile = Join-Path $PSScriptRoot 'config.txt'
$config = @{}

if (Test-Path $configFile) {
    Write-Host '[INFO] Loading configuration from config.txt...'
    Get-Content $configFile | ForEach-Object {
        if ($_ -match '^\s*([^=]+)=(.*)$') {
            $key = $matches[1].Trim()
            $value = $matches[2].Trim()
            # Replace $dir with actual directory path
            $value = $value -replace '\$dir', $PSScriptRoot
            $config[$key] = $value
        }
    }
    Write-Host '[INFO] Configuration loaded successfully'
} else {
    Write-Error "config.txt not found at $configFile"
    exit 1
}

# Validate required configuration variables
$requiredVars = @('LLM_URL', 'EMBEDDING_URL', 'API_PORT', 'MAX_TOKENS_PER_GROUP', 'LLM_GGUF', 'LLM_MODEL_DIR', 'PORT')
foreach ($var in $requiredVars) {
    if (-not $config.ContainsKey($var)) {
        Write-Error "Required configuration variable $var is missing in config.txt"
        exit 1
    }
}

# Set environment variables
$env:LLM_URL = $config['LLM_URL']
$env:LLM_MODEL_NAME = ''
$env:EMBEDDING_URL = $config['EMBEDDING_URL']
$env:EMBEDDING_MODEL_NAME = ''
$env:API_PORT = $config['API_PORT']
$env:MAX_TOKENS_PER_GROUP = $config['MAX_TOKENS_PER_GROUP']
$env:LLM_GGUF = $config['LLM_GGUF']
$env:LLM_MODEL_DIR = $config['LLM_MODEL_DIR']
$env:OPENAI_API_BASE_URL = $config['LLM_URL']
$env:OPEN_WEBUI_DIR = Join-Path (Join-Path (Join-Path $PSScriptRoot 'backend') 'data') 'parse_txt'
$env:KM_RESULT_DIR = Join-Path (Join-Path $PSScriptRoot 'open-webui') 'km'
$env:KM_SELF_RAG_API_BASE_URL = "http://127.0.0.1:$($config['API_PORT'])"
$env:NPM_CONFIG_STRICT_SSL = 'false'
$env:NODE_TLS_REJECT_UNAUTHORIZED = '0'

$port = $config['PORT']

# Paths for venv
$backendPath = Join-Path $PSScriptRoot 'backend'
$backendVenv = Join-Path $backendPath 'venv_open_webui'
$backendVenvPy = Join-Path $backendVenv 'Scripts\python.exe'
$backendVenvActivate = Join-Path $backendVenv 'Scripts\activate.bat'

$kmPath = Join-Path $PSScriptRoot 'km'
$kmVenv = Join-Path $kmPath 'venv_km'
$kmVenvPy = Join-Path $kmVenv 'Scripts\python.exe'
$kmVenvActivate = Join-Path $kmVenv 'Scripts\activate.bat'

# Verify venvs exist
if (-not (Test-Path $backendVenvPy)) {
    Write-Error "Backend virtual environment not found at $backendVenv"
    exit 1
}

if (-not (Test-Path $kmVenvPy)) {
    Write-Error "KM virtual environment not found at $kmVenv"
    exit 1
}

# Create log directory
$logDir = Join-Path $PSScriptRoot 'logs'
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

$stdoutOpenWebuiLog = Join-Path $logDir 'backend.log'
$stderrOpenWebuiLog = Join-Path $logDir 'backend.err.log'
$stdoutKmLog = Join-Path $logDir 'km.log'
$stderrKmLog = Join-Path $logDir 'km.err.log'

# 5.1. Start Open WebUI backend (corresponding to setup_and_run.bat 799-801)
Write-Host "[INFO] Starting Open WebUI backend on port $port..."

$backendCmd = @"
cd /d "$backendPath" && call "$backendVenvActivate" && set "VIRTUAL_ENV=$backendVenv" && set "LLM_URL=$($env:LLM_URL)" && set "LLM_MODEL_NAME=" && set "EMBEDDING_URL=$($env:EMBEDDING_URL)" && set "EMBEDDING_MODEL_NAME=" && set "API_PORT=$($env:API_PORT)" && set "MAX_TOKENS_PER_GROUP=$($env:MAX_TOKENS_PER_GROUP)" && set "LLM_GGUF=$($env:LLM_GGUF)" && set "LLM_MODEL_DIR=$($env:LLM_MODEL_DIR)" && set "OPENAI_API_BASE_URL=$($env:OPENAI_API_BASE_URL)" && set "OPEN_WEBUI_DIR=$($env:OPEN_WEBUI_DIR)" && set "KM_RESULT_DIR=$($env:KM_RESULT_DIR)" && set "KM_SELF_RAG_API_BASE_URL=$($env:KM_SELF_RAG_API_BASE_URL)" && set "NPM_CONFIG_STRICT_SSL=false" && set "NODE_TLS_REJECT_UNAUTHORIZED=0" && uv run --no-project uvicorn open_webui.main:app --port $port --host 0.0.0.0 --reload
"@

Start-Process `
    -FilePath 'cmd.exe' `
    -ArgumentList @('/k', $backendCmd) `
    -WindowStyle Hidden `
    -WorkingDirectory $backendPath `
    -RedirectStandardOutput $stdoutOpenWebuiLog `
    -RedirectStandardError $stderrOpenWebuiLog

# Wait a moment before starting the second service
Start-Sleep -Seconds 3

# 5.2. Start KM service (corresponding to setup_and_run.bat 807-809)
Write-Host "[INFO] Starting KM service on port $($env:API_PORT)..."

$kmCmd = @"
cd /d "$kmPath" && call "$kmVenvActivate" && set "VIRTUAL_ENV=$kmVenv" && set "LLM_URL=$($env:LLM_URL)" && set "LLM_MODEL_NAME=" && set "EMBEDDING_URL=$($env:EMBEDDING_URL)" && set "EMBEDDING_MODEL_NAME=" && set "API_PORT=$($env:API_PORT)" && set "MAX_TOKENS_PER_GROUP=$($env:MAX_TOKENS_PER_GROUP)" && set "LLM_GGUF=$($env:LLM_GGUF)" && set "LLM_MODEL_DIR=$($env:LLM_MODEL_DIR)" && set "OPENAI_API_BASE_URL=$($env:OPENAI_API_BASE_URL)" && set "OPEN_WEBUI_DIR=$($env:OPEN_WEBUI_DIR)" && set "KM_RESULT_DIR=$($env:KM_RESULT_DIR)" && set "KM_SELF_RAG_API_BASE_URL=$($env:KM_SELF_RAG_API_BASE_URL)" && uv run --no-project api.py
"@

Start-Process `
    -FilePath 'cmd.exe' `
    -ArgumentList @('/k', $kmCmd) `
    -WindowStyle Hidden `
    -WorkingDirectory $kmPath `
    -RedirectStandardOutput $stdoutKmLog `
    -RedirectStandardError $stderrKmLog

Write-Host ""
Write-Host "========================================"
Write-Host "Services Started Successfully!"
Write-Host "========================================"
Write-Host ""
Write-Host "Open WebUI: http://127.0.0.1:$port"
Write-Host "KM Service: http://127.0.0.1:$($env:API_PORT)"
Write-Host ""
Write-Host "Two console windows have been opened for each service."
Write-Host "Close those windows to stop the services."
Write-Host ""

# Health check and auto-open browser
$healthUrl = "http://127.0.0.1:$port/health"
$healthUrl2 = "http://127.0.0.1:$($env:API_PORT)/health"
$maxAttempts = 30
$attemptDelay = 2
$attempt = 0
$isHealthy = $false

Write-Host "Waiting for Open WebUI to start..."

while ($attempt -lt $maxAttempts -and -not $isHealthy) {
    Start-Sleep -Seconds $attemptDelay
    $attempt++
    
    try {
        $response = Invoke-WebRequest -Uri $healthUrl -Method Get -TimeoutSec 2 -ErrorAction Stop
        $response2 = Invoke-WebRequest -Uri $healthUrl2 -Method Get -TimeoutSec 2 -ErrorAction Stop
        if ($response.StatusCode -eq 200 -and $response2.StatusCode -eq 200) {
            $isHealthy = $true
            Write-Host "Open WebUI is ready!"
            
            # Open browser with Google Chrome
            $chromePath = (Get-Command chrome -ErrorAction SilentlyContinue).Source
            if (-not $chromePath) {
                $chromePath = "$env:ProgramFiles\Google\Chrome\Application\chrome.exe"
                if (-not (Test-Path $chromePath)) {
                    $programFilesX86 = [Environment]::GetFolderPath('ProgramFilesX86')
                    $chromePath = Join-Path $programFilesX86 "Google\Chrome\Application\chrome.exe"
                }
            }
            
            if (Test-Path $chromePath) {
                Start-Process -FilePath $chromePath -ArgumentList "http://127.0.0.1:$port"
                Write-Host "Browser opened successfully."
            }
            else {
                Write-Warning "Google Chrome not found. Please open http://127.0.0.1:$port manually."
            }
        }
    }
    catch {
        # Service not ready yet, continue waiting
        Write-Host "Attempt ${attempt}/${maxAttempts}: Service not ready yet..."
    }
}

if (-not $isHealthy) {
    Write-Warning "Open WebUI did not become healthy within the timeout period. Please check the logs."
}