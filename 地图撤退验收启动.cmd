@echo off
setlocal
chcp 65001 >nul
set "PSModulePath=%USERPROFILE%\Documents\WindowsPowerShell\Modules;%ProgramFiles%\WindowsPowerShell\Modules;%SystemRoot%\System32\WindowsPowerShell\v1.0\Modules"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0automation\start.ps1" -CandidateRoot "%~dp0tmp\runtime-candidates\v2\map-return-ready-v1"
if errorlevel 1 pause
endlocal
