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

:: ============================================================
:: Flash Player 本地信任配置（确保 SWF 可访问网络）
:: 优先用户级目录（无需管理员），失败时提示
:: ============================================================
set "TRUST_FILE_NAME=cf7me.cfg"
set "USER_TRUST_DIR=%APPDATA%\Macromedia\Flash Player\#Security\FlashPlayerTrust"
set "TRUST_OK=0"

:: 检查用户级信任目录
if not exist "%USER_TRUST_DIR%" (
    mkdir "%USER_TRUST_DIR%" 2>nul
)

if exist "%USER_TRUST_DIR%" (
    set "TRUST_FILE=%USER_TRUST_DIR%\%TRUST_FILE_NAME%"
    :: 检查是否已包含当前路径
    if exist "!TRUST_FILE!" (
        findstr /i /x /c:"%SCRIPT_DIR%" "!TRUST_FILE!" >nul 2>&1
        if !errorlevel! equ 0 (
            set "TRUST_OK=1"
        ) else (
            >> "!TRUST_FILE!" echo %SCRIPT_DIR%
            set "TRUST_OK=1"
        )
    ) else (
        > "!TRUST_FILE!" echo %SCRIPT_DIR%
        set "TRUST_OK=1"
    )
)

if "!TRUST_OK!"=="0" (
    echo [警告] 无法配置 Flash Player 信任文件，游戏可能无法连接后端服务。
    echo [警告] 请尝试以管理员身份运行，或手动将以下路径添加到 Flash Player 信任目录：
    echo         %SCRIPT_DIR%
    echo.
)

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
