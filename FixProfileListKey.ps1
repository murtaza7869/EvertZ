Start-Process -filepath "$env:windir\regedit.exe" -Argumentlist @("/s", "`"C:\file.reg`"")
