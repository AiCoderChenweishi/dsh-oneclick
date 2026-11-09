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
