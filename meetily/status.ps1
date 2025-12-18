$ErrorActionPreference = 'Stop'

# Check if meetily process exists by name
try {
  $procs = Get-Process -Name 'meetily' -ErrorAction SilentlyContinue
  $isRunning = ($procs -ne $null -and $procs.Count -gt 0)
} catch {
  $isRunning = $false
}

# Return JSON status
$status = if ($isRunning) { 1 } else { 0 }
$json = @{
  status = $status
} | ConvertTo-Json -Compress

Write-Host $json

