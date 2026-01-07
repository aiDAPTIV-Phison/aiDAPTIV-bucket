$ErrorActionPreference = 'Stop'

Write-Host ">>> SCRIPT STARTED" -ForegroundColor Magenta
Start-Sleep -Seconds 2

# --- 1. Path Definitions ---
$rootDir = $PSScriptRoot
$pythonExe = Join-Path $rootDir "Chat_with_Github\python\python.exe"
$backendDir = Join-Path $rootDir "Chat_with_Github\backend"
$backendScript = Join-Path $backendDir "flow.py" 
$configPath = Join-Path $rootDir "config.txt"

# Log Files
$stdOutLog = Join-Path $rootDir "app.log"
$stdErrLog = Join-Path $rootDir "app.err.log"
$flowOutLog = Join-Path $rootDir "app.flow.out.log"
$flowErrLog = Join-Path $rootDir "app.flow.err.log"

# --- 2. Load Configuration ---
Write-Host ">>> Loading Configuration..." -ForegroundColor Cyan
if (-not (Test-Path $configPath)) {
    New-Item -Path $configPath -ItemType File -Force | Out-Null
}

$configData = @{}
$lines = Get-Content $configPath
foreach ($line in $lines) {
    if ($line -match '^([^=]+)=(.*)$') {
        $key = $matches[1].Trim()
        $value = $matches[2].Trim()
        $configData[$key] = $value
        [System.Environment]::SetEnvironmentVariable($key, $value, "Process")
    }
}

# --- 3 & 4. GitHub Token Logic & Validation Loop ---
$isValid = $false
$githubToken = $configData["GITHUB_PERSONAL_ACCESS_TOKEN"]

do {
    if ([string]::IsNullOrWhiteSpace($githubToken)) {
        Write-Host ">>> GitHub Token is missing or empty in config.txt" -ForegroundColor Yellow
        $githubToken = Read-Host "Please enter your GitHub Personal Access Token (PAT)"
    }

    Write-Host ">>> Validating Token..." -ForegroundColor Cyan
    $validateCode = "import requests; r=requests.get('https://api.github.com/user', headers={'Authorization':f'token $githubToken'}); exit(0 if r.status_code==200 else 1)"
    & $pythonExe -c "$validateCode"
    
    if ($LASTEXITCODE -eq 0) {
        $isValid = $true
        Write-Host ">>> Token Validated Successfully!" -ForegroundColor Green
    } else {
        Write-Host ">>> ERROR: Invalid Token. Please check your PAT and try again." -ForegroundColor Red
        $githubToken = "" # Clear to force re-prompt
    }
} while (-not $isValid)

# --- Update config.txt with Validated Token ---
$configData["GITHUB_PERSONAL_ACCESS_TOKEN"] = $githubToken
if (-not $configData.ContainsKey("GITHUB_TOOLSETS")) {
    $configData["GITHUB_TOOLSETS"] = "repos,issues,pull_requests,actions,code_security,experiments"
}

$newConfigContent = @()
$keysHandled = @()
foreach ($line in $lines) {
    if ($line -match '^([^=]+)=') {
        $key = $matches[1].Trim()
        if ($configData.ContainsKey($key)) {
            $newConfigContent += "$key=$($configData[$key])"
            $keysHandled += $key
            continue
        }
    }
    $newConfigContent += $line
}
foreach ($key in $configData.Keys) {
    if ($key -notin $keysHandled) { $newConfigContent += "$key=$($configData[$key])" }
}
$newConfigContent | Set-Content $configPath

# Set environment variables for the current session
[System.Environment]::SetEnvironmentVariable("GITHUB_PERSONAL_ACCESS_TOKEN", $githubToken, "Process")
[System.Environment]::SetEnvironmentVariable("GITHUB_TOOLSETS", $configData["GITHUB_TOOLSETS"], "Process")

# --- 5. Launch MCP Server ---
Write-Host ">>> Launching MCP Server..." -ForegroundColor Cyan
$mcpDir = Join-Path $rootDir "Chat_with_Github\wins_installer_github_mcp"
$mcpExe = Join-Path $mcpDir "github-mcp-server.exe"

Write-Host "    Starting MCP process via mcpo..." -ForegroundColor Gray
$mcpArgs = "-c `"import mcpo; mcpo.main()`" --port 8000 -- `"$mcpExe`" stdio"

Start-Process -FilePath $pythonExe -ArgumentList $mcpArgs `
    -WorkingDirectory $mcpDir -WindowStyle Hidden

# Monitor Port 8000
$maxRetries = 30
$retry = 0
$mcpReady = $false
while ($retry -lt $maxRetries) {
    if ($null -ne (Get-NetTCPConnection -LocalPort 8000 -ErrorAction SilentlyContinue)) {
        $mcpReady = $true
        break
    }
    Write-Host "    Waiting for MCP (Port 8000)... ${retry}/${maxRetries}" -ForegroundColor Gray
    Start-Sleep -Seconds 1
    $retry++
}

if (-not $mcpReady) {
    Write-Error "CRITICAL: MCP Server failed to bind to Port 8000."
    Start-Sleep -Seconds 10
    exit 1
}
Start-Sleep -Seconds 2 
Write-Host "    MCP Server is fully operational!" -ForegroundColor Green

# --- 6. Launch Open WebUI Backend ---
Write-Host ">>> Launching Open WebUI Backend..." -ForegroundColor Cyan
$env:PYTHONUTF8 = "1"
$env:DATA_DIR = Join-Path $backendDir "data"
$env:PORT = 8001
$env:CORS_ALLOW_ORIGIN = "http://localhost:5173,http://localhost:8001"
$env:TOOL_SERVER_CONNECTIONS = "[{`"type`": `"openapi`", `"url`": `"http://localhost:8000`", `"spec_type`": `"url`", `"spec`": `"`", `"path`": `"openapi.json`", `"auth_type`": `"none`", `"key`": `"`", `"config`": {`"enable`": true}, `"info`": {`"id`": `"`", `"name`": `"github-server`", `"description`": `"Github MCP Server`"}}]"

Write-Host "    Launching Uvicorn in background..." -ForegroundColor Gray
$uvicornArgs = "-m uvicorn open_webui.main:app --host localhost --port 8001 --workers 1"
Start-Process -FilePath $pythonExe -ArgumentList $uvicornArgs -WorkingDirectory $backendDir -WindowStyle Hidden `
    -RedirectStandardOutput $stdOutLog `
    -RedirectStandardError $stdErrLog

Write-Host "    Waiting 30 seconds for server to be ready..." -ForegroundColor Gray
Start-Sleep -Seconds 30

Write-Host "    Executing flow.py..." -ForegroundColor Cyan
Set-Location $backendDir
$flowProcess = Start-Process -FilePath $pythonExe -ArgumentList "`"$backendScript`"" `
    -WorkingDirectory $backendDir -WindowStyle Hidden -PassThru -Wait `
    -RedirectStandardOutput $flowOutLog `
    -RedirectStandardError $flowErrLog

$flowExitCode = $flowProcess.ExitCode
if ($flowExitCode -ne 0 -and (Test-Path $flowErrLog)) {
    Write-Host "    [Flow Error]: $(Get-Content $flowErrLog -Raw)" -ForegroundColor Red
}

# --- 7. Browser Launch Logic ---
$isSuccessfully = $false
if (Test-Path $flowOutLog) {
    $logContent = Get-Content $flowOutLog -Raw
    if ($logContent -match "Successfully!" -or $logContent -match "is already initialized") {
        $isSuccessfully = $true
    }
}

if ($flowExitCode -eq 0 -and $isSuccessfully) {
    Write-Host ">>> ALL SYSTEMS READY. Opening browser..." -ForegroundColor Green
    Start-Process "http://localhost:8001"
} else {
    Write-Host "`nERROR: Flow script did not report success." -ForegroundColor Red
}

Write-Host ">>> DONE. Closing in 10 seconds..." -ForegroundColor Magenta
Start-Sleep -Seconds 10