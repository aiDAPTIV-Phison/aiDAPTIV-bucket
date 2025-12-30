$ErrorActionPreference = 'Stop'

# 1. Define Paths to subfolder
$appDir = Join-Path $PSScriptRoot "langchain\app"
$pyPath = Join-Path $appDir "python-3.10\python.exe"
$mainPy = Join-Path $appDir "main.py"
$stderrLog = Join-Path $appDir "app.err.log"

# This tells Python to put logs in the root ($dir) instead of the app folder
$env:LOG_OUTPUT_DIR = $PSScriptRoot

# 2. Parse config.txt (remains in root)
$configPath = Join-Path $PSScriptRoot "config.txt"
if (Test-Path $configPath) {
    Get-Content $configPath | Foreach-Object {
        $name, $value = $_.split('=', 2)
        if ($name -and $value) { [System.Environment]::SetEnvironmentVariable($name.Trim(), $value.Trim(), "Process") }
    }
}

# 3. Dynamic Docs Path
$env:EXAMPLE_DOCS_FILE_DIR = Join-Path $appDir "Example\Files"

# 4. Launch
# This allows you to SEE the chat while SAVING it to the log file at the same time
if (Test-Path $appDir) {
    Set-Location $appDir
    Write-Host "--- Launching Interactive Chat ---" -ForegroundColor Cyan
    & $pyPath $mainPy
} else {
    Write-Error "Could not find application directory at: $appDir"
}