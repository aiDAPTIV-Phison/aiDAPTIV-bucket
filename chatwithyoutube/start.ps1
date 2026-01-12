param(
  [switch]$Show
)

$ErrorActionPreference = "Stop"

$batPath = Join-Path $PSScriptRoot "start.bat"
if (-not (Test-Path -LiteralPath $batPath)) {
  Write-Error "start.bat not found：$batPath"
  exit 1
}

$logPath = Join-Path $PSScriptRoot "start.log"

# If --show is specified, run normally with visible window
if ($Show) {
  Push-Location $PSScriptRoot
  try {
    & $batPath --show
    exit $LASTEXITCODE
  }
  finally {
    Pop-Location
  }
}
else {
  # Default: start hidden
  Write-Host "Starting service in hidden mode..."
  Write-Host "Log file: $logPath"
  
  $cmd = "set AIDAPTIV_HIDDEN=1 & call `"$batPath`" --show"
  
  $process = Start-Process `
    -WindowStyle Hidden `
    -WorkingDirectory $PSScriptRoot `
    -FilePath "cmd.exe" `
    -ArgumentList @("/c", $cmd) `
    -PassThru
  
  Write-Host "Service started (PID: $($process.Id))"
  Write-Host "Use 'start.ps1 -Show' to run with visible window"
  exit 0
}

