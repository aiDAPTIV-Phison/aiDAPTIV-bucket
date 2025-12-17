$ErrorActionPreference = 'Stop'

$venvDir = Join-Path $PSScriptRoot 'venv_open_webui'
$venvPy = Join-Path $venvDir 'Scripts\python.exe'
$venvCli = Join-Path $venvDir 'Scripts\open-webui.exe'

# Create venv only if it doesn't exist yet
if (-not (Test-Path $venvPy)) {
  python -m venv $venvDir
}

# Start Open WebUI without needing activate (more reliable for Start-Process)
$stdoutLog = Join-Path $PSScriptRoot 'open-webui.log'
$stderrLog = Join-Path $PSScriptRoot 'open-webui.err.log'

if (Test-Path $venvCli) {
  # Prefer the CLI entrypoint (package/CLI name may contain '-', but module names cannot)
  Start-Process `
    -FilePath $venvCli `
    -ArgumentList @('serve') `
    -WorkingDirectory $PSScriptRoot `
    -WindowStyle Hidden `
    -RedirectStandardOutput $stdoutLog `
    -RedirectStandardError $stderrLog
}
else {
  # Fallback: run as a module (module name typically uses '_' instead of '-')
  Start-Process `
    -FilePath $venvPy `
    -ArgumentList @('-m', 'open_webui', 'serve') `
    -WorkingDirectory $PSScriptRoot `
    -WindowStyle Hidden `
    -RedirectStandardOutput $stdoutLog `
    -RedirectStandardError $stderrLog
}