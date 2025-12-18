$ErrorActionPreference = 'Stop'

$exePath = Join-Path $PSScriptRoot 'meetily\meetily.exe'

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

# Stop meetily.exe by exact executable path
$stopped = Stop-ProcessesByExecutablePath -ExecutablePath $exePath

# As a fallback, stop any remaining meetily process by name
try {
  Stop-Process -Name 'meetily' -Force -ErrorAction SilentlyContinue
} catch {
  # ignore
}

Write-Host ("Stopped processes: meetily.exe={0}" -f $stopped.Count)

