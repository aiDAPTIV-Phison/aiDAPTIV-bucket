$ErrorActionPreference = 'Stop'
$pyPath = Join-Path $PSScriptRoot "langchain\app\python-3.10\python.exe"

$procs = Get-CimInstance Win32_Process | Where-Object { $_.ExecutablePath -ieq $pyPath }
$isRunning = ($null -ne $procs)

$status = if ($isRunning) { 1 } else { 0 }
@{ status = $status } | ConvertTo-Json -Compress