@echo off
chcp 65001 >nul 2>&1
title CF7 数值平衡工具

:: 关键：清除 VSCode 设置的环境变量，否则 Electron 会以 Node 模式运行
set "ELECTRON_RUN_AS_NODE="

set "TOOL_ROOT=%~dp0"
set "ELECTRON_DIR=%TEMP%\cf7-electron-full\dist"
set "ELECTRON_EXE=%ELECTRON_DIR%\electron.exe"
set "ELECTRON_MAIN=%TOOL_ROOT%packages\web\dist\electron\main.cjs"
set "RENDERER_HTML=%TOOL_ROOT%packages\web\dist\renderer\index.html"

:: --- 检查 Electron ---
if not exist "%ELECTRON_EXE%" (
    echo [!] Electron 未安装，正在下载到临时目录...
    echo     来源: cdn.npmmirror.com
    if not exist "%TEMP%\cf7-electron-full" mkdir "%TEMP%\cf7-electron-full"
    pushd "%TEMP%\cf7-electron-full"

    :: 下载 Electron zip
    if not exist electron.zip (
        echo     下载中...（约 110MB）
        powershell -Command "Invoke-WebRequest -Uri 'https://cdn.npmmirror.com/binaries/electron/v33.4.0/electron-v33.4.0-win32-x64.zip' -OutFile 'electron.zip'" 2>nul
    )
    if not exist electron.zip (
        echo [X] 下载失败，请检查网络后重试。
        popd
        pause
        exit /b 1
    )

    :: 解压
    echo     解压中...
    powershell -Command "Expand-Archive -Path 'electron.zip' -DestinationPath 'dist' -Force" 2>nul
    popd

    if not exist "%ELECTRON_EXE%" (
        echo [X] Electron 安装失败。
        pause
        exit /b 1
    )
    echo [OK] Electron 已就绪。
)

:: --- 检查渲染器 ---
if not exist "%RENDERER_HTML%" (
    echo [!] 渲染器未构建，正在构建...
    pushd "%TOOL_ROOT%"
    call npx vite build packages/web
    popd
    if not exist "%RENDERER_HTML%" (
        echo [X] 渲染器构建失败。
        pause
        exit /b 1
    )
    echo [OK] 渲染器已构建。
)

:: --- 检查 Electron 主进程（CJS 打包版）---
if not exist "%ELECTRON_MAIN%" (
    echo [!] 主进程未打包，正在构建...
    pushd "%TOOL_ROOT%"
    call npx esbuild packages/web/src/electron/main.ts --bundle --platform=node --format=cjs --outfile=packages/web/dist/electron/main.cjs --external:electron --banner:js="const __import_meta_url = require('url').pathToFileURL(__filename).href;" --define:import.meta.url=__import_meta_url
    popd
    if not exist "%ELECTRON_MAIN%" (
        echo [X] 主进程打包失败。
        pause
        exit /b 1
    )
    echo [OK] 主进程已打包。
)

:: --- 启动 ---
echo 启动 CF7 数值平衡工具...
start "" "%ELECTRON_EXE%" "%ELECTRON_MAIN%"
