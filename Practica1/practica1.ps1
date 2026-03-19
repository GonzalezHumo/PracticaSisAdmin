Write-Host "Hostname"
$env:COMPUTERNAME

Write-Host ""
Write-Host "Direccion IP Actual:"
ipconfig | findstr IPv4

Write-Host ""
Write-Host "Espacio En Disco: "
Get-PSDrive C | Select-Object Used, Free