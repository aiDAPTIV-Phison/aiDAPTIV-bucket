$ErrorActionPreference = 'Stop'

# Check if VS Code process exists by name
try {
  $procs = Get-Process -Name 'Code' -ErrorAction SilentlyContinue
  $isRunning = ($procs -ne $null -and $procs.Count -gt 0)
} catch {
  $isRunning = $false
}

# Check if Continue extension is installed
$hasContinueExtension = $false
if ($isRunning) {
  try {
    $extensions = & code --list-extensions 2>$null
    $hasContinueExtension = ($extensions -contains 'continue.continue')
  } catch {
    $hasContinueExtension = $false
  }
}

# Return JSON status (1 only if both VS Code is running AND Continue extension is installed)
$status = if ($isRunning -and $hasContinueExtension) { 1 } else { 0 }
$json = @{
  status = $status
} | ConvertTo-Json -Compress

Write-Host $json

