@echo off
chcp 65001 >nul
setlocal

set "SCRIPT_DIR=%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%compile_test.ps1"
exit /b %ERRORLEVEL%
