@echo off
setlocal

for %%I in ("%~dp0.") do set "CF7_PROJECT_ROOT=%%~fI"
set "CF7_SUBMIT_SCRIPT=%CF7_PROJECT_ROOT%\tools\submit-contribution.ps1"
chcp 65001 >nul

if not exist "%CF7_SUBMIT_SCRIPT%" (
    echo [CF7] Missing submit script: "%CF7_SUBMIT_SCRIPT%"
    set "CF7_EXIT_CODE=2"
    goto :finish
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%CF7_SUBMIT_SCRIPT%" -ProjectRoot "%CF7_PROJECT_ROOT%" -Wait %*
set "CF7_EXIT_CODE=%ERRORLEVEL%"

:finish
if not "%CF7_NO_PAUSE%"=="1" pause
exit /b %CF7_EXIT_CODE%
