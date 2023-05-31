@echo off
setlocal
set "item=C:\ProgramData\Faronics\StorageSpace\FWA\modules\FwaCore.dll"
set "item=%item:\=\\%"

for /f "usebackq delims=" %%a in (`"WMIC DATAFILE WHERE name='%item%' get Version /format:Textvaluelist"`) do (
    for /f "delims=" %%# in ("%%a") do set "%%#"
)

if "%~2" neq "" (
    endlocal & (
        echo %version%
        set %~2=%version%
    )
) else (
    echo %version%
)

if "2.22.2100.805" neq "%version%" (
    Taskkill.exe /F /IM FWAService.exe
    Timeout 600
    sc stop FWASvc
    Timeout 60
    sc start FWASvc
) else (echo "all good")
