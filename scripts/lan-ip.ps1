# Prints this PC's LAN IPv4 address (the one phones on the same Wi-Fi can reach).
$ip = Get-NetIPConfiguration |
    Where-Object { $_.IPv4DefaultGateway -ne $null -and $_.NetAdapter.Status -eq 'Up' } |
    ForEach-Object { $_.IPv4Address.IPAddress } |
    Select-Object -First 1
if ($ip) { Write-Output $ip }
