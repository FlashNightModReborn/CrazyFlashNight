@echo off
setlocal
chcp.com 65001 >nul
set "PSModulePath=%SystemRoot%\System32\WindowsPowerShell\v1.0\Modules"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\run-focus-diagnostic.ps1"
set "CF7_FOCUS_EXIT=%ERRORLEVEL%"
if "%CF7_NO_PAUSE%"=="1" goto :exit
pause
:exit
exit /b %CF7_FOCUS_EXIT%
