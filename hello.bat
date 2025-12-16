@echo off
powershell -Command "$content1 = 'Write-Host \"Start Service\"'; $content1 | Out-File -FilePath \"%~dp0start-service.ps1\" -Encoding UTF8"
powershell -Command "$content2 = 'Write-Host \"Stop Service\"'; $content2 | Out-File -FilePath \"%~dp0stop-service.ps1\" -Encoding UTF8"
echo Created start-service.ps1 and stop-service.ps1

