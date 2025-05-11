@REM wsl ip 172.19.45.223 port 5000

@REM add firewall rule 

New-NetFirewallRule -Name "WSL Backend 5000" -DisplayName "WSL Backend 5000" -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 5000

@REM delete rule
Remove-NetFirewallRule -Name "WSL Backend 5000"

@REM port forward
netsh interface portproxy add v4tov4 listenport=5000 listenaddress=0.0.0.0 connectport=5000 connectaddress=172.19.45.223

@REM verify
netsh interface portproxy show v4tov4

@REM delete
netsh interface portproxy delete v4tov4 listenport=5000 listenaddress=0.0.0.0