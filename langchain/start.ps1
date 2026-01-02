$ErrorActionPreference = 'Stop'

# 1. Define Paths
$appDir = Join-Path $PSScriptRoot "langchain\app"
$pyPath = Join-Path $appDir "python-3.10\python.exe"
$mainPy = Join-Path $appDir "main.py"
$pidFile = Join-Path $PSScriptRoot "app.pid"

$env:LOG_OUTPUT_DIR = $PSScriptRoot

# 2. Parse config.txt
$configPath = Join-Path $PSScriptRoot "config.txt"
if (Test-Path $configPath) {
    Get-Content $configPath | Foreach-Object {
        $name, $value = $_.split('=', 2)
        if ($name -and $value) { [System.Environment]::SetEnvironmentVariable($name.Trim(), $value.Trim(), "Process") }
    }
}

$env:EXAMPLE_DOCS_FILE_DIR = Join-Path $appDir "Example\Files"

# 4. Launch without creating a new window
if (Test-Path $appDir) {
    Set-Location $appDir
    Write-Host "--- Launching Interactive Chat ---" -ForegroundColor Cyan
    
    # We use Start-Info to capture the PID without spawning a new window
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $pyPath
    $psi.Arguments = $mainPy
    $psi.UseShellExecute = $false  # This keeps it in the SAME terminal
    
    $proc = [System.Diagnostics.Process]::Start($psi)
    
    # Save the PID for our status.ps1
    $proc.Id | Out-File $pidFile -Force
    
    # Wait for the process to finish so the window doesn't close instantly
    $proc.WaitForExit()
} else {
    Write-Error "Could not find application directory at: $appDir"
}