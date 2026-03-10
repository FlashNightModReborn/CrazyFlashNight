@echo off
chcp 65001 >nul
setlocal

set "MM_CFG=%USERPROFILE%\mm.cfg"

echo 正在配置 Flash Debug 日志...
echo.

(
echo ErrorReportingEnable=1
echo TraceOutputFileEnable=1
echo MaxWarnings=0
) > "%MM_CFG%"

echo 已写入: %MM_CFG%
echo 日志输出位置: %APPDATA%\Macromedia\Flash Player\Logs\flashlog.txt
echo.
echo 配置完成，重启 Flash IDE 后生效。
echo 使用 run_test.bat 可自动编译并查看输出。
pause
