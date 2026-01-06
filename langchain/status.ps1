$ErrorActionPreference = 'SilentlyContinue'
$pidFile = Join-Path $PSScriptRoot "app.pid"
$isRunning = 0

if (Test-Path $pidFile) {
    $savedPid = Get-Content $pidFile -Raw
    if ($savedPid) {
        # Check if the specific process ID exists and is still a Python process
        $proc = Get-Process -Id $savedPid.Trim()
        if ($proc -and $proc.ProcessName -match "python") {
            $isRunning = 1
        }
    }
}

# Return ONLY clean JSON for UniGetUI/Scoop
@{ status = $isRunning } | ConvertTo-Json -Compress