$ErrorActionPreference = 'SilentlyContinue'

function Stop-ProcessByPath {
    param([string]$PathPattern)
    $procs = Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like "*$PathPattern*" }
    foreach ($p in $procs) {
        Write-Host "Stopping process $($p.ProcessId): $($p.CommandLine)" -ForegroundColor Yellow
        Stop-Process -Id $p.ProcessId -Force
    }
}

Write-Host "Stopping Chat_with_Github services..." -ForegroundColor Cyan

# 1. Stop the MCP Server (runs via run_mcp.bat -> python -> github-mcp-server.exe)
# We look for the executable specifically
Get-Process -Name "github-mcp-server" | Stop-Process -Force

# 2. Stop the Backend (Uvicorn running open_webui.main)
Stop-ProcessByPath "open_webui.main:app"

# 3. Stop the MCP Python wrapper (running mcpo)
Stop-ProcessByPath "import mcpo"

Write-Host "All services stopped." -ForegroundColor Green