$ErrorActionPreference = "Stop"

$batPath = Join-Path $PSScriptRoot "start.bat"
if (-not (Test-Path -LiteralPath $batPath)) {
  Write-Error "start.bat not found：$batPath"
  exit 1
}

Push-Location $PSScriptRoot
try {
  & $batPath @args
  exit $LASTEXITCODE
}
finally {
  Pop-Location
}

