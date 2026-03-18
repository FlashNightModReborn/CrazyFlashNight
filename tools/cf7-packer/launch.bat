@echo off
chcp 65001 >nul 2>&1
title CF7 Packer
setlocal

set "TOOL_ROOT=%~dp0"
pushd "%TOOL_ROOT%"

call node scripts\ensure-runtime.mjs
if errorlevel 1 (
    echo [X] Runtime preparation failed.
    popd
    pause
    exit /b 1
)

set "ELECTRON_MAIN=%TOOL_ROOT%packages\web\dist\electron\main.cjs"
set "ELECTRON_BIN=%TOOL_ROOT%node_modules\.bin\electron.cmd"

if not exist "%ELECTRON_BIN%" (
    echo [X] Electron launcher not found. Please run npm install again.
    popd
    pause
    exit /b 1
)

if not exist "%ELECTRON_MAIN%" (
    echo [X] Electron main bundle is missing. Please check build logs.
    popd
    pause
    exit /b 1
)

echo Starting CF7 Packer...
call "%ELECTRON_BIN%" "%ELECTRON_MAIN%"
popd
