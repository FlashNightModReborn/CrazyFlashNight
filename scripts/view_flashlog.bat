@echo off
chcp 65001 >nul
set "LOG_FILE=%APPDATA%\Macromedia\Flash Player\Logs\flashlog.txt"
set "LOCAL_COPY=%~dp0flashlog.txt"
if exist "%LOG_FILE%" (
    copy /y "%LOG_FILE%" "%LOCAL_COPY%" >nul
    echo 已复制到: %LOCAL_COPY%
) else (
    echo 日志文件不存在: %LOG_FILE%
    echo 请先运行 setup_flash_debug.bat 并在 Flash IDE 中测试。
)
pause
