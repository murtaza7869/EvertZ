#local url to download zip file
#Assign zip file url to local variable

$Url = "http://192.168.0.112/default.zip"

$DownloadZipFile = "C:\Windows\Temp\" + $(Split-Path -Path $Url -Leaf)

$ExtractPath = "C:\users\"

Invoke-WebRequest -Uri $Url -OutFile $DownloadZipFile

$ExtractShell = New-Object -ComObject Shell.Application 

$ExtractFiles = $ExtractShell.Namespace($DownloadZipFile).Items() 

$ExtractShell.NameSpace($ExtractPath).CopyHere($ExtractFiles) 