param(
    [string]$ScriptDir = $null
)

$ErrorActionPreference = 'Stop'

# Determine script directory - handle all calling scenarios
# When called via & (Join-Path $dir 'status.ps1'), $PSScriptRoot may not be set
# Priority: 1. Parameter, 2. $PSScriptRoot, 3. $MyInvocation paths
$scriptPath = $null
if ($ScriptDir) {
    $scriptPath = $ScriptDir
} elseif ($PSScriptRoot) {
    $scriptPath = $PSScriptRoot
} elseif ($MyInvocation.MyCommand.Path) {
    $scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
} elseif ($MyInvocation.ScriptName) {
    $scriptPath = Split-Path -Parent $MyInvocation.ScriptName
} elseif ($MyInvocation.MyCommand.Definition) {
    $scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
} else {
    # Fallback: use current directory (should not happen, but just in case)
    $scriptPath = (Get-Location).Path
}

# Read port from config.txt
$port = 8080  # Default port
$configFile = Join-Path $scriptPath 'config.txt'
if (Test-Path $configFile) {
    $configContent = Get-Content $configFile
    foreach ($line in $configContent) {
        if ($line -match '^\s*PORT\s*=\s*(\d+)\s*$') {
            $port = [int]$matches[1]
            break
        }
    }
}

# Check if port is accessible with longer timeout
$isRunning = $false
$errorMsg = $null
try {
  $tcpClient = New-Object System.Net.Sockets.TcpClient
  $connection = $tcpClient.BeginConnect('localhost', $port, $null, $null)
  # Increase timeout to 3000ms (3 seconds) for more reliable detection
  $wait = $connection.AsyncWaitHandle.WaitOne(3000, $false)
  
  if ($wait) {
    try {
      $tcpClient.EndConnect($connection)
      $isRunning = $true
    } catch {
      $isRunning = $false
      $errorMsg = "EndConnect failed: $_"
    }
  } else {
    $isRunning = $false
    $errorMsg = "Connection timeout after 3000ms"
  }
  $tcpClient.Close()
} catch {
  $isRunning = $false
  $errorMsg = "Connection failed: $_"
}

# Return JSON status with optional debug info
$status = if ($isRunning) { 1 } else { 0 }
$jsonObj = @{
  status = $status
}

# Add debug info if status check failed (can be removed in production)
if (-not $isRunning -and $env:DEBUG_STATUS -eq '1') {
  $jsonObj['debug'] = @{
    port = $port
    configFile = $configFile
    configExists = (Test-Path $configFile)
    scriptPath = $scriptPath
    error = $errorMsg
  }
}

$json = $jsonObj | ConvertTo-Json -Compress

# Output to stdout (not stderr, so it won't be hidden by 2>$null)
Write-Output $json

