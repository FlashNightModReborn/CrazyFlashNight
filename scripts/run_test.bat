@echo off
chcp 65001 >nul
setlocal

:: 所有路径自动推导，无硬编码
set "SCRIPT_DIR=%~dp0"
set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

:: 定位 Flash CS6 Commands 目录
set "FLASH_CFG_BASE=%LOCALAPPDATA%\Adobe\Flash CS6"
set "COMMANDS_DIR="
for /d %%D in ("%FLASH_CFG_BASE%\*") do (
    if exist "%%D\Configuration\Commands" set "COMMANDS_DIR=%%D\Configuration\Commands"
)
if "%COMMANDS_DIR%"=="" (
    echo [ERROR] 找不到 Flash CS6 Commands 目录
    echo 请先运行 setup_compile_env.bat
    pause
    exit /b 1
)

set "JSFL=%COMMANDS_DIR%\test_publish.jsfl"
set "MARKER=%SCRIPT_DIR%\publish_done.marker"
set "ERROR_MARKER=%SCRIPT_DIR%\publish_error.marker"
set "LOG=%APPDATA%\Macromedia\Flash Player\Logs\flashlog.txt"
set "LOCAL_LOG=%SCRIPT_DIR%\flashlog.txt"

:: Clean
if exist "%MARKER%" del "%MARKER%"
if exist "%ERROR_MARKER%" del "%ERROR_MARKER%"
if exist "%LOG%" del "%LOG%"

:: Trigger JSFL
start "" "%JSFL%"

:: Wait for marker (max 30s)
set /a count=0
:wait
if exist "%MARKER%" goto :done
if exist "%ERROR_MARKER%" goto :error
timeout /t 1 /nobreak >nul
set /a count+=1
if %count% lss 30 goto :wait
echo [TIMEOUT] 30s
goto :end

:done
if exist "%LOG%" (
    copy /y "%LOG%" "%LOCAL_LOG%" >nul
    echo === FLASH TRACE OUTPUT ===
    type "%LOCAL_LOG%"
    echo === END ===
) else (
    echo [INFO] 无 trace 输出
)
del "%MARKER%"
goto :end

:error
echo [ERROR] 编译失败:
type "%ERROR_MARKER%"
del "%ERROR_MARKER%"

:end
