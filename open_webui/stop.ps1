$ErrorActionPreference = 'Stop'

# Stop all processes related to openwebui path

function Stop-ProcessesByOpenWebUIPath {
  $procs = Get-CimInstance Win32_Process |
    Where-Object {
      $procPath = $_.ExecutablePath
      $procCmdLine = $_.CommandLine
      
      # Check if executable path or command line contains "openwebui" (case-insensitive)
      ($procPath -and $procPath -match 'openwebui') -or
      ($procCmdLine -and $procCmdLine -match 'openwebui')
    }

  $stoppedCount = 0
  foreach ($p in $procs) {
    try {
      Write-Host "[INFO] Stopping process: $($p.Name) (PID: $($p.ProcessId))"
      Stop-Process -Id $p.ProcessId -Force -ErrorAction Stop
      $stoppedCount++
    } catch {
      Write-Host "[WARN] Failed to stop process PID $($p.ProcessId): $_" -ForegroundColor Yellow
    }
  }

  return $stoppedCount
}

# Stop all processes related to openwebui path
Write-Host '[INFO] Stopping all processes related to openwebui path...'
$stoppedCount = Stop-ProcessesByOpenWebUIPath

Write-Host "[INFO] Stopped $stoppedCount process(es) related to openwebui path."

