@echo off
rem Same entry as 恢复DSH.cmd, ASCII file name for terminals that cannot type CJK.
setlocal
chcp 65001 >nul 2>nul
set "HERE=%~dp0"
set "PS=powershell.exe -NoProfile -ExecutionPolicy Bypass -File"
if exist "%HERE%oneclick.ps1" goto run
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "try { [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -UseBasicParsing 'https://raw.githubusercontent.com/AiCoderChenweishi/dsh-oneclick/main/oneclick.ps1' -OutFile '%HERE%oneclick.ps1' } catch { Write-Host $_.Exception.Message; exit 1 }"
if not exist "%HERE%oneclick.ps1" goto fail
:run
%PS% "%HERE%oneclick.ps1" %*
if errorlevel 1 goto fail
echo.
echo   All done. Press any key to close.
pause >nul
exit /b 0
:fail
echo.
echo   The restore did not finish. Read the messages above.
pause
exit /b 1
