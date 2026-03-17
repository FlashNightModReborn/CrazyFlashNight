@echo off
chcp 65001 >nul 2>&1
title 闪客快打7 更新安装

:: 检测 PowerShell 可用性
where powershell.exe >nul 2>&1
if errorlevel 1 goto no_ps

:: 检测 PowerShell 版本（Win7 SP1 自带 2.0，够用）
powershell.exe -Command "$PSVersionTable.PSVersion.Major" >nul 2>&1
if errorlevel 1 goto no_ps

:: 启动安装脚本（install.ps1 已有 UTF-8 BOM，-File 可正确识别）
powershell.exe -ExecutionPolicy Bypass -File "%~dp0install.ps1"
goto end

:no_ps
echo.
echo  =============================================
echo    错误：未检测到 PowerShell
echo  =============================================
echo.
echo  本更新程序需要 PowerShell 运行。
echo.
echo  Windows 7 用户请安装：
echo    Windows Management Framework 3.0 或更高版本
echo    https://www.microsoft.com/download/details.aspx?id=34595
echo.
echo  Windows 10/11 用户无需额外安装。
echo.
echo  如果您已安装 PowerShell 但仍看到此消息，
echo  请尝试手动运行：
echo    powershell -ExecutionPolicy Bypass -File install.ps1
echo.
pause

:end
