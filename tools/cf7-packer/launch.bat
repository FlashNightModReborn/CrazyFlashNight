@echo off
chcp 65001 >nul 2>&1
title CF7 发行打包工具

set "ELECTRON_RUN_AS_NODE="

set "TOOL_ROOT=%~dp0"
set "ELECTRON_DIR=%TEMP%\cf7-electron-full\dist"
set "ELECTRON_EXE=%ELECTRON_DIR%\electron.exe"
set "ELECTRON_ZIP=%TEMP%\cf7-electron-full\electron.zip"
set "ELECTRON_MAIN=%TOOL_ROOT%packages\web\dist\electron\main.cjs"
set "RENDERER_HTML=%TOOL_ROOT%packages\web\dist\renderer\index.html"
set "ELECTRON_URL=https://cdn.npmmirror.com/binaries/electron/v33.4.0/electron-v33.4.0-win32-x64.zip"
set "CDN_HOST=cdn.npmmirror.com"

if not exist "%TOOL_ROOT%node_modules" (
    echo [!] 首次运行，安装依赖...
    pushd "%TOOL_ROOT%"
    call npm install
    if errorlevel 1 (
        echo [X] npm install 失败，请检查 Node.js 是否已安装。
        popd
        pause
        exit /b 1
    )
    popd
    echo [OK] 依赖安装完成。
)

if not exist "%ELECTRON_EXE%" goto download_electron
goto check_renderer

:download_electron
echo [!] Electron 未安装，正在下载到临时目录...
echo     来源: %CDN_HOST%
if not exist "%TEMP%\cf7-electron-full" mkdir "%TEMP%\cf7-electron-full"

if exist "%ELECTRON_ZIP%" (
    echo     清理上次残留的下载文件...
    del /q "%ELECTRON_ZIP%"
)
if exist "%ELECTRON_DIR%" (
    rmdir /s /q "%ELECTRON_DIR%"
)

echo     通过阿里 DNS 解析国内节点...
set "CDN_IP="
for /f "tokens=*" %%a in ('powershell -Command "(Resolve-DnsName '%CDN_HOST%' -Server 223.5.5.5 -Type A -ErrorAction SilentlyContinue | Where-Object {$_.QueryType -eq 'A'} | Select-Object -First 1).IP4Address" 2^>nul') do set "CDN_IP=%%a"

if defined CDN_IP (
    echo     resolved %CDN_HOST% -^> %CDN_IP%
    echo     下载中... (about 110MB^)
    curl.exe -L --noproxy "*" --resolve "%CDN_HOST%:443:%CDN_IP%" -# --retry 3 --retry-delay 5 -o "%ELECTRON_ZIP%" "%ELECTRON_URL%"
) else (
    echo     DNS 解析失败，使用默认路由下载...
    echo     下载中... (about 110MB^)
    curl.exe -L --noproxy "*" -# --retry 3 --retry-delay 5 -o "%ELECTRON_ZIP%" "%ELECTRON_URL%"
)

if not exist "%ELECTRON_ZIP%" (
    echo [X] 下载失败，请检查网络后重试。
    pause
    exit /b 1
)

echo     解压中...
powershell -Command "Expand-Archive -Path '%ELECTRON_ZIP%' -DestinationPath '%ELECTRON_DIR%' -Force"
if errorlevel 1 (
    echo [X] 解压失败，文件可能损坏，已清理。请重试。
    if exist "%ELECTRON_ZIP%" del /q "%ELECTRON_ZIP%"
    if exist "%ELECTRON_DIR%" rmdir /s /q "%ELECTRON_DIR%"
    pause
    exit /b 1
)

if not exist "%ELECTRON_EXE%" (
    echo [X] Electron 安装失败。
    pause
    exit /b 1
)
echo [OK] Electron 已就绪。

:check_renderer
if not exist "%RENDERER_HTML%" (
    echo [!] 渲染器未构建，正在构建...
    pushd "%TOOL_ROOT%"
    call npx vite build packages/web
    popd
)
if not exist "%RENDERER_HTML%" (
    echo [X] 渲染器构建失败。
    pause
    exit /b 1
)

if not exist "%ELECTRON_MAIN%" (
    echo [!] 主进程未打包，正在构建...
    pushd "%TOOL_ROOT%"
    call npx esbuild packages/web/src/electron/main.ts --bundle --platform=node --format=cjs --outfile=packages/web/dist/electron/main.cjs --external:electron --banner:js="const __import_meta_url = require('url').pathToFileURL(__filename).href;" --define:import.meta.url=__import_meta_url
    copy /y packages\web\src\electron\preload.js packages\web\dist\electron\preload.js >nul
    popd
)
if not exist "%ELECTRON_MAIN%" (
    echo [X] 主进程打包失败。
    pause
    exit /b 1
)

echo 启动 CF7 发行打包工具...
start "" "%ELECTRON_EXE%" "%ELECTRON_MAIN%"
