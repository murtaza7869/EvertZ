$url = "https://faronics-dfc-canada-production-installers.s3.ca-central-1.amazonaws.com/Custom/Evertz_UpdateServerUrlOnly.exe"
$output = "C:\Windows\temp\Evertz_UpdateServerUrlOnly.exe"
$wc = new-object System.Net.WebClient
$wc.DownloadFile($url, $output)
Start-Process -FilePath "C:\Windows\temp\Evertz_UpdateServerUrlOnly.exe"
