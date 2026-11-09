@echo off
rem ===========================================================================
rem  DSH one-click restore.
rem  Double-click this file on a fresh Windows machine. It downloads the
rem  restore engine (if only this .cmd was copied) and starts oneclick.ps1.
rem ===========================================================================
setlocal
chcp 65001 >nul 2>nul
title DSH one-click restore
set "HERE=%~dp0"
set "PS=powershell.exe -NoProfile -ExecutionPolicy Bypass -File"

if exist "%HERE%oneclick.ps1" goto run

echo.
echo   oneclick.ps1 not found here; downloading it from GitHub...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$u='https://raw.githubusercontent.com/AiCoderChenweishi/dsh-oneclick/main/oneclick.ps1'; $m='https://gh-proxy.com/'+$u; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; foreach($s in @($u,$m)){ try { Invoke-WebRequest -UseBasicParsing $s -OutFile '%HERE%oneclick.ps1' -TimeoutSec 60; if(Test-Path '%HERE%oneclick.ps1'){ exit 0 } } catch { } }; Write-Host 'download failed (github.com / raw may be blocked here).'; exit 1"
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
echo   If the download failed: open the repository page, download the ZIP,
echo   extract it, and double-click the .cmd next to oneclick.ps1.
pause
exit /b 1
