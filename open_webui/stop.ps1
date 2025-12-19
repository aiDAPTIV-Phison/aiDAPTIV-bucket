$ErrorActionPreference = 'Stop'

# Stop processes by matching command line patterns

function Stop-ProcessesByCommandLine {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Pattern
  )

  $procs = Get-CimInstance Win32_Process |
    Where-Object {
      $_.CommandLine -and ($_.CommandLine -match $Pattern)
    }

  foreach ($p in $procs) {
    Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
  }

  return $procs
}

# Stop Open WebUI Backend (uvicorn)
Write-Host '[INFO] Stopping Open WebUI Backend...'
$stoppedBackend = Stop-ProcessesByCommandLine -Pattern 'uvicorn.*open_webui\.main:app'
if ($stoppedBackend.Count -eq 0) {
    # Also try to stop by checking for uvicorn in command line
    $stoppedBackend = Stop-ProcessesByCommandLine -Pattern 'uvicorn'
}

# Stop KM Service (api.py)
Write-Host '[INFO] Stopping KM Service...'
$stoppedKM = Stop-ProcessesByCommandLine -Pattern 'uv run.*api\.py'
if ($stoppedKM.Count -eq 0) {
    # Also try to stop by checking for api.py in command line
    $stoppedKM = Stop-ProcessesByCommandLine -Pattern 'api\.py'
}

# Stop any remaining processes by name
try {
    Stop-Process -Name 'uvicorn' -Force -ErrorAction SilentlyContinue
} catch {
    # ignore
}

try {
    Stop-Process -Name 'python' -Force -ErrorAction SilentlyContinue
} catch {
    # ignore - this might stop other python processes too, but it's a fallback
}

Write-Host ("Stopped processes: Open WebUI Backend={0}, KM Service={1}" -f $stoppedBackend.Count, $stoppedKM.Count)

