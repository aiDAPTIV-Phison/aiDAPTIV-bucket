$ErrorActionPreference = 'Stop'

$exePath = Join-Path $PSScriptRoot 'meetily\meetily.exe'

# Start meetily
$stdoutLog = Join-Path $PSScriptRoot 'meetily.log'
$stderrLog = Join-Path $PSScriptRoot 'meetily.err.log'

if (Test-Path $exePath) {
  Start-Process `
    -FilePath $exePath `
    -WorkingDirectory $PSScriptRoot `
    -RedirectStandardOutput $stdoutLog `
    -RedirectStandardError $stderrLog
} else {
  Write-Error "meetily.exe not found at: $exePath"
  exit 1
}

