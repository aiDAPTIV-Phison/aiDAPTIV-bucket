$ErrorActionPreference = 'Stop'

# Check if port 8080 is accessible
try {
  $tcpClient = New-Object System.Net.Sockets.TcpClient
  $connection = $tcpClient.BeginConnect('localhost', 8080, $null, $null)
  $wait = $connection.AsyncWaitHandle.WaitOne(1000, $false)
  
  if ($wait) {
    $tcpClient.EndConnect($connection)
    $isRunning = $true
  } else {
    $isRunning = $false
  }
  $tcpClient.Close()
} catch {
  $isRunning = $false
}

# Return JSON status
$status = if ($isRunning) { 1 } else { 0 }
$json = @{
  status = $status
} | ConvertTo-Json -Compress

Write-Host $json

