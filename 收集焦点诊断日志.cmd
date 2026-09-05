@echo off
setlocal
chcp.com 65001 >nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\run-focus-diagnostic.ps1" -CollectOnly
set "CF7_FOCUS_EXIT=%ERRORLEVEL%"
if "%CF7_NO_PAUSE%"=="1" goto :exit
pause
:exit
exit /b %CF7_FOCUS_EXIT%
