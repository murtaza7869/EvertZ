﻿#local url to download zip file
#Assign zip file url to local variable

$Url = "https://github.com/murtaza7869/EvertZ/raw/main/default.zip"

$DownloadZipFile = "C:\Windows\Temp\" + $(Split-Path -Path $Url -Leaf)

$ExtractPath = "O:\ProfilesFolder\users\"

Invoke-WebRequest -Uri $Url -OutFile $DownloadZipFile

$ExtractShell = New-Object -ComObject Shell.Application 

$ExtractFiles = $ExtractShell.Namespace($DownloadZipFile).Items() 

$ExtractShell.NameSpace($ExtractPath).CopyHere($ExtractFiles) 
