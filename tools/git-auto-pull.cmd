@echo off
rem ============================================================
rem  Double-click launcher for git-auto-pull.ps1
rem  (all Chinese messages live in the .ps1, this file is ASCII-only
rem   to avoid console codepage issues)
rem
rem  Usage:
rem    git-auto-pull.cmd               poll every 60s until one success
rem    git-auto-pull.cmd 300           poll every 300s until one success
rem    git-auto-pull.cmd 60 200        poll every 60s, max 200 attempts
rem
rem  Stop: press Ctrl+C or close the window.
rem ============================================================
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0git-auto-pull.ps1" %*
echo.
pause
