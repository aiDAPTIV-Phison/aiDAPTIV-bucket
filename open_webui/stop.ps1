$ErrorActionPreference = 'Stop'

$venvDir = Join-Path $PSScriptRoot 'venv_open_webui'
$venvPy = Join-Path $venvDir 'Scripts\python.exe'
$venvCli = Join-Path $venvDir 'Scripts\open-webui.exe'

function Stop-ProcessesByExecutablePath {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ExecutablePath
  )

  if (-not (Test-Path $ExecutablePath)) {
    return @()
  }

  $procs = Get-CimInstance Win32_Process |
    Where-Object { $_.ExecutablePath -and ($_.ExecutablePath -ieq $ExecutablePath) }

  foreach ($p in $procs) {
    Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
  }

  return $procs
}

function Stop-PythonOpenWebUIFallback {
  param(
    [Parameter(Mandatory = $true)]
    [string]$PythonPath
  )

  if (-not (Test-Path $PythonPath)) {
    return @()
  }

  $procs = Get-CimInstance Win32_Process |
    Where-Object {
      $_.ExecutablePath -and ($_.ExecutablePath -ieq $PythonPath) -and
      $_.CommandLine -and ($_.CommandLine -match ' -m\s+open_webui\s+serve(\s|$)')
    }

  foreach ($p in $procs) {
    Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
  }

  return $procs
}

# 1) Prefer stopping the exact open-webui.exe started by start.ps1
$stoppedCli = Stop-ProcessesByExecutablePath -ExecutablePath $venvCli

# 2) Fallback: if start.ps1 used python -m open_webui serve, stop that too
$stoppedPy = Stop-PythonOpenWebUIFallback -PythonPath $venvPy

# 3) As a last resort, stop any remaining open-webui process by name
try {
  Stop-Process -Name 'open-webui' -Force -ErrorAction SilentlyContinue
} catch {
  # ignore
}

Write-Host ("Stopped processes: open-webui.exe={0}, python(open_webui serve)={1}" -f $stoppedCli.Count, $stoppedPy.Count)

