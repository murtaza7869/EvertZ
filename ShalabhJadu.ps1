Invoke-WmiMethod -ComputerName . -Class FaronicsWebAgent_v1 -Name SendEvent -ArgumentList "B6267655-C0DE-4057-B801-F9FF8612A9C9", 1302
Start-Sleep -Seconds 5
$url = "https://faronics-dfc-canada-production-installers.s3.ca-central-1.amazonaws.com/Custom/Evertz_UpdateServerUrlOnly.exe"
$output = "C:\Windows\temp\Evertz_UpdateServerUrlOnly.exe"
$wc = new-object System.Net.WebClient
$wc.DownloadFile($url, $output)
Start-Process -FilePath "C:\Windows\temp\Evertz_UpdateServerUrlOnly.exe"

