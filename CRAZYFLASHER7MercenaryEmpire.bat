@echo off
chcp 65001 >nul 2>&1
setlocal EnableDelayedExpansion

:: ============================================================
:: CRAZYFLASHER7MercenaryEmpire 启动脚本
:: 读取 config.toml 配置并启动 Flash Player 加载 SWF
:: 修改此文件即可调整启动行为，无需重新编译 EXE
:: ============================================================

:: 获取脚本所在目录
set "SCRIPT_DIR=%~dp0"
:: 去掉末尾反斜杠
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

:: 默认值
set "FLASH_PLAYER=Adobe Flash Player 20.exe"
set "SWF_FILE=CRAZYFLASHER7MercenaryEmpire.swf"

:: 读取 config.toml（如果存在）
set "CONFIG_FILE=%SCRIPT_DIR%\config.toml"
if exist "%CONFIG_FILE%" (
    for /f "usebackq tokens=1,* delims==" %%a in ("%CONFIG_FILE%") do (
        :: 去除键的前后空格
        set "KEY=%%a"
        set "VAL=%%b"
        :: 去除值的前后空格和引号
        if defined VAL (
            for /f "tokens=* delims= " %%v in ("!VAL!") do set "VAL=%%v"
            set "VAL=!VAL:"=!"
        )
        if /i "!KEY: =!"=="flashPlayerPath" set "FLASH_PLAYER=!VAL!"
        if /i "!KEY: =!"=="swfPath" set "SWF_FILE=!VAL!"
    )
)

:: 构建完整路径（如果配置中给的是相对路径）
if not exist "%FLASH_PLAYER%" (
    set "FLASH_PLAYER=%SCRIPT_DIR%\%FLASH_PLAYER%"
)
if not exist "%SWF_FILE%" (
    set "SWF_FILE=%SCRIPT_DIR%\%SWF_FILE%"
)

:: 检查 Flash Player
if not exist "%FLASH_PLAYER%" (
    echo [错误] 找不到 Flash Player: %FLASH_PLAYER%
    pause
    exit /b 1
)

:: 检查 SWF 文件
if not exist "%SWF_FILE%" (
    echo [错误] 找不到 SWF 文件: %SWF_FILE%
    pause
    exit /b 1
)

:: 启动 Flash Player
start "" "%FLASH_PLAYER%" "%SWF_FILE%"
