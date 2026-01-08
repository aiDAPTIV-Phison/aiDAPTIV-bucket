$ErrorActionPreference = 'SilentlyContinue'
$pidFile = Join-Path $PSScriptRoot "app.pid"
$isRunning = 0

# Check if the pid file exists
if (Test-Path $pidFile) {
    $pidText = (Get-Content $pidFile -Raw).Trim()
    if ($pidText -match '^\d+$') {
        $savedPid = [int]$pidText
        $proc = Get-Process -Id $savedPid -ErrorAction SilentlyContinue
        
        # If a process with the saved PID is currently active
        if ($proc) {
            # Check for any TCP connections listening specifically on Port 7860
            $connection = Get-NetTCPConnection -LocalPort 7860 -State Listen -ErrorAction SilentlyContinue
            
            if ($connection) {
		# We verify if the port owner matches our saved PID.
                if ($connection.OwningProcess -eq $savedPid) {
                    $isRunning = 1
                } else {
		    # If the port is occupied by a different PID, it might be a port conflict, 
                    # or a child/worker process. In most cases for Langflow, if the port
		    # is listening, the service is considered 'Up'.
                    $isRunning = 1
                }
            }
        }
    }
}

# Output the result as a compressed JSON object for UniGetUI to interpret
@{ status = [int]$isRunning } | ConvertTo-Json -Compress