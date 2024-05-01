@echo off 

setlocal 

set eventid=1074 

echo Fetching shutdown event logs... 

wevtutil qe System /rd:true /f:text /q:"*[System[(EventID=%eventid%)]]" | findstr /i "event user"  

echo Done. 
