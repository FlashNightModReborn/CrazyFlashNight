@echo off
chcp 65001 >nul
setlocal

set "SCRIPT_DIR=%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%setup_compile_env.ps1" %*
set "EXIT_CODE=%ERRORLEVEL%"

if not "%EXIT_CODE%"=="0" (
    echo.
    echo [ERROR] 环境配置失败，退出码 %EXIT_CODE%
    pause
    exit /b %EXIT_CODE%
)

echo.
echo [OK] 环境配置完成
pause
exit /b 0
