@echo off
:: CF7 Animate Kit — one-click launcher (Windows).
:: Double-click to start the Electron cockpit (AN maintenance + .sol inspector).
:: First run auto-installs dependencies and builds; later runs launch directly.
:: Delegates to the web package launcher (which downloads Electron to %TEMP%).
chcp 65001 >nul 2>&1
title CF7 Animate Kit
call "%~dp0packages\web\launch.bat" %*
