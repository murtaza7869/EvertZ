#local url to download zip file
#Assign zip file url to local variable

$Url = "https://raw.githubusercontent.com/murtaza7869/EvertZ/main/ProfileList.reg"

$DownloadZipFile = "C:\Windows\Temp\" + $(Split-Path -Path $Url -Leaf)

$ExtractPath = "C:\Windows\Temp\"

Invoke-WebRequest -Uri $Url -OutFile $DownloadZipFile

$ExtractShell = New-Object -ComObject Shell.Application 

$ExtractFiles = $ExtractShell.Namespace($DownloadZipFile).Items() 

$ExtractShell.NameSpace($ExtractPath).CopyHere($ExtractFiles) 
Start-Process -filepath "$env:windir\regedit.exe" -Argumentlist @("/s", "`"C:\Windows\Temp\ProfileList.reg`"")
