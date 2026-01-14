$ErrorActionPreference = 'Stop'

# Status is determined by whether the service port is listening.
# Streamlit UI is fixed to port 8501 (see app.py).
$port = 8501

function Test-PortListening {
    param(
        [Parameter(Mandatory=$true)][int]$Port
    )

    # Prefer Get-NetTCPConnection (Win10+) then fallback to netstat parsing.
    try {
        $listeners = Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction Stop
        return ($null -ne $listeners -and $listeners.Count -gt 0)
    } catch {
        try {
            $netstat = netstat -ano -p tcp 2>$null
            if (-not $netstat) { return $false }
            $pattern = "LISTENING\s+\d+$"
            foreach ($line in $netstat) {
                # Examples:
                #   TCP    0.0.0.0:8501           0.0.0.0:0              LISTENING       1234
                #   TCP    [::]:8501              [::]:0                 LISTENING       1234
                if ($line -match ":\b$Port\b" -and $line -match $pattern) {
                    return $true
                }
            }
            return $false
        } catch {
            return $false
        }
    }
}

$isRunning = Test-PortListening -Port $port

# Return JSON status (compatible with existing callers)
$status = if ($isRunning) { 1 } else { 0 }
$json = @{ status = $status } | ConvertTo-Json -Compress
Write-Host $json