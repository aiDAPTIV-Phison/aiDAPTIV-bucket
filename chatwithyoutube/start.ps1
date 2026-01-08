$ErrorActionPreference = "Stop"

$batPath = Join-Path $PSScriptRoot "start.bat"
if (-not (Test-Path -LiteralPath $batPath)) {
  Write-Error "start.bat not found：$batPath"
  exit 1
}

Push-Location $PSScriptRoot
try {
  # Default: start hidden (start.bat will self-relaunch hidden via PowerShell).
  # Use: start.ps1 --show  to keep the console window visible.
  & $batPath @args
  exit $LASTEXITCODE
}
finally {
  Pop-Location
}

