$ErrorActionPreference = 'Stop'

Write-Host "[INFO] Stopping VS Code..."

# Stop all VS Code processes
try {
    $process = Get-Process -Name "Code" -ErrorAction SilentlyContinue
    
    if ($process) {
        # Use taskkill to forcefully terminate all Code.exe processes
        $result = taskkill /IM code.exe /F 2>&1
        
        Write-Host "[INFO] VS Code processes terminated successfully"
        Write-Host $result
    } else {
        Write-Host "[INFO] No VS Code processes found running"
    }
} catch {
    Write-Error "Failed to stop VS Code: $_"
    exit 1
}

