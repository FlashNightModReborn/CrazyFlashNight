@echo off
setlocal
chcp.com 65001 >nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0automation\dev.ps1" %*
set "CF7_DEV_EXIT=%ERRORLEVEL%"
if "%CF7_DEV_EXIT%"=="0" goto :exit
if "%CF7_NO_PAUSE%"=="1" goto :exit
echo.
echo Local development startup failed with exit code %CF7_DEV_EXIT%.
pause
:exit
exit /b %CF7_DEV_EXIT%
