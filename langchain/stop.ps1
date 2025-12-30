$ErrorActionPreference = 'Stop'
$pyPath = Join-Path $PSScriptRoot "app\python-3.10\python.exe"

function Stop-ProcessesByPath {
    param([string]$ExecutablePath)
    $procs = Get-CimInstance Win32_Process | Where-Object { $_.ExecutablePath -ieq $ExecutablePath }
    foreach ($p in $procs) { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue }
    return $procs.Count
}

$count = Stop-ProcessesByPath -ExecutablePath $pyPath
Write-Host "Stopped $count processes."