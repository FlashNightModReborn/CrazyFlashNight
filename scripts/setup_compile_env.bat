@echo off
chcp 65001 >nul
setlocal EnableDelayedExpansion

echo ========================================
echo  Flash CS6 自动化编译环境配置
echo ========================================
echo.

:: ---- 1. 定位项目根目录 ----
set "SCRIPT_DIR=%~dp0"
:: 去掉末尾反斜杠
set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
:: 项目根 = scripts 的上一级
for %%I in ("%SCRIPT_DIR%") do set "PROJECT_DIR=%%~dpI"
set "PROJECT_DIR=%PROJECT_DIR:~0,-1%"
echo [INFO] 项目目录: %PROJECT_DIR%

:: ---- 2. 配置 mm.cfg ----
set "MM_CFG=%USERPROFILE%\mm.cfg"
(
echo ErrorReportingEnable=1
echo TraceOutputFileEnable=1
echo MaxWarnings=0
) > "%MM_CFG%"
echo [OK] mm.cfg: %MM_CFG%

:: ---- 3. 定位 Flash CS6 语言目录 ----
set "FLASH_CFG_BASE=%LOCALAPPDATA%\Adobe\Flash CS6"
set "LANG_DIR="
for /d %%D in ("%FLASH_CFG_BASE%\*") do (
    if exist "%%D\Configuration\Commands" (
        set "LANG_DIR=%%D"
    )
)
if "%LANG_DIR%"=="" (
    echo [ERROR] 找不到 Flash CS6 配置目录，请确认已安装 Flash CS6
    pause
    exit /b 1
)
echo [OK] Flash CS6 配置: %LANG_DIR%

set "COMMANDS_DIR=%LANG_DIR%\Configuration\Commands"

:: ---- 4. 写入项目路径配置 ----
:: 将 Windows 路径转换为 JSFL URI 格式: file:///C|/path/to/project
set "URI_PATH_FILE=%COMMANDS_DIR%\flash_project_path.cfg"
powershell -NoProfile -Command "$project=$env:PROJECT_DIR -replace '\\','/'; $uri='file:///' + $project.Replace(':', [char]124); $enc=[Text.UTF8Encoding]::new($false); [IO.File]::WriteAllText($env:URI_PATH_FILE, $uri + [Environment]::NewLine, $enc)"
echo [OK] 项目路径配置: %COMMANDS_DIR%\flash_project_path.cfg

:: ---- 5. 部署 JSFL 到 Commands 目录 ----
:: compile.jsfl 是动态加载器（固定不变），eval 加载 compile_action.jsfl
:: 如果 Commands 目录下已有 compile.jsfl 则跳过（避免触发 CS6 缓存问题）
if not exist "%COMMANDS_DIR%\compile.jsfl" (
    (
    echo // compile.jsfl - dynamic loader
    echo var _cfg = fl.configURI + "Commands/flash_project_path.cfg";
    echo var _proj = FLfile.read^(_cfg^);
    echo if ^(_proj^) {
    echo 	_proj = _proj.replace^(/[\r\n]+$/^, ""^);
    echo 	var _script = _proj + "/scripts/compile_action.jsfl";
    echo 	if ^(FLfile.exists^(_script^)^) {
    echo 		eval^(FLfile.read^(_script^)^);
    echo 	} else {
    echo 		fl.trace^("[ERROR] not found: " + _script^);
    echo 	}
    echo } else {
    echo 	fl.trace^("[ERROR] no project config"^);
    echo }
    ) > "%COMMANDS_DIR%\compile.jsfl"
    echo [OK] compile.jsfl 已部署（新建）
) else (
    echo [OK] compile.jsfl 已存在（跳过，避免缓存问题）
)

:: ---- 6. 查找 Flash.exe ----
set "FLASH_EXE="

:: 尝试常见路径（快速检查，不做全盘搜索）
for %%P in (
    "C:\Program Files\Adobe\Adobe Flash CS6\Flash.exe"
    "C:\Program Files (x86)\Adobe\Adobe Flash CS6\Flash.exe"
    "%USERPROFILE%\Downloads\adboeflash cs6(1)\Adobe Flash CS6\Flash.exe"
    "D:\qq download\adboeflash cs6(1)\Adobe Flash CS6\Flash.exe"
    "E:\flash\adboeflash cs6(1)\Adobe Flash CS6\Flash.exe"
) do (
    if exist %%P if "!FLASH_EXE!"=="" set "FLASH_EXE=%%~P"
)

:: 未找到则让用户手动输入
if "%FLASH_EXE%"=="" (
    echo [INFO] 未在常见路径找到 Flash.exe
    echo 请输入 Flash.exe 的完整路径（含文件名）:
    set /p "FLASH_EXE="
)

if "%FLASH_EXE%"=="" (
    echo [WARN] 未指定 Flash.exe，跳过计划任务创建
    goto :skip_task
)
if not exist "%FLASH_EXE%" (
    echo [WARN] 路径不存在: %FLASH_EXE%
    echo        跳过计划任务创建
    goto :skip_task
)
echo [OK] Flash.exe: %FLASH_EXE%

:: ---- 7. 生成并导入计划任务 ----
set "TASK_XML=%TEMP%\FlashCS6Task_generated.xml"
(
echo ^<?xml version="1.0" encoding="UTF-16"?^>
echo ^<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task"^>
echo   ^<RegistrationInfo^>
echo     ^<Description^>Launch Flash CS6 without UAC prompt^</Description^>
echo   ^</RegistrationInfo^>
echo   ^<Triggers /^>
echo   ^<Principals^>
echo     ^<Principal id="Author"^>
echo       ^<LogonType^>InteractiveToken^</LogonType^>
echo       ^<RunLevel^>HighestAvailable^</RunLevel^>
echo     ^</Principal^>
echo   ^</Principals^>
echo   ^<Settings^>
echo     ^<MultipleInstancesPolicy^>IgnoreNew^</MultipleInstancesPolicy^>
echo     ^<DisallowStartIfOnBatteries^>false^</DisallowStartIfOnBatteries^>
echo     ^<StopIfGoingOnBatteries^>false^</StopIfGoingOnBatteries^>
echo     ^<ExecutionTimeLimit^>PT0S^</ExecutionTimeLimit^>
echo     ^<Enabled^>true^</Enabled^>
echo   ^</Settings^>
echo   ^<Actions Context="Author"^>
echo     ^<Exec^>
echo       ^<Command^>%FLASH_EXE%^</Command^>
echo     ^</Exec^>
echo   ^</Actions^>
echo ^</Task^>
) > "%TASK_XML%"

schtasks /create /tn "FlashCS6Task" /xml "%TASK_XML%" /f >nul 2>&1
if %errorlevel%==0 (
    echo [OK] 计划任务 FlashCS6Task 已创建
) else (
    echo [WARN] 计划任务创建失败，可能需要管理员权限
    echo        请以管理员身份运行此脚本
)

:: ---- 7b. 生成并导入 CompileTriggerTask ----
:: 注意：必须用 cmd.exe /c start 直接打开 JSFL，不要通过 PowerShell 脚本间接打开
:: 实测 trigger_compile.ps1 在计划任务环境中 Start-Process/explorer.exe 均无法
:: 可靠地将 JSFL 传递给运行中的 Flash 实例
set "TRIGGER_XML=%TEMP%\CompileTriggerTask_generated.xml"
(
echo ^<?xml version="1.0" encoding="UTF-16"?^>
echo ^<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task"^>
echo   ^<RegistrationInfo^>
echo     ^<Description^>Trigger Flash CS6 compile - open JSFL directly^</Description^>
echo   ^</RegistrationInfo^>
echo   ^<Triggers /^>
echo   ^<Principals^>
echo     ^<Principal id="Author"^>
echo       ^<LogonType^>InteractiveToken^</LogonType^>
echo       ^<RunLevel^>HighestAvailable^</RunLevel^>
echo     ^</Principal^>
echo   ^</Principals^>
echo   ^<Settings^>
echo     ^<MultipleInstancesPolicy^>IgnoreNew^</MultipleInstancesPolicy^>
echo     ^<DisallowStartIfOnBatteries^>false^</DisallowStartIfOnBatteries^>
echo     ^<StopIfGoingOnBatteries^>false^</StopIfGoingOnBatteries^>
echo     ^<ExecutionTimeLimit^>PT30S^</ExecutionTimeLimit^>
echo     ^<Enabled^>true^</Enabled^>
echo   ^</Settings^>
echo   ^<Actions Context="Author"^>
echo     ^<Exec^>
echo       ^<Command^>cmd.exe^</Command^>
echo       ^<Arguments^>/c start "" "%COMMANDS_DIR%\compile.jsfl"^</Arguments^>
echo     ^</Exec^>
echo   ^</Actions^>
echo ^</Task^>
) > "%TRIGGER_XML%"

schtasks /create /tn "CompileTriggerTask" /xml "%TRIGGER_XML%" /f >nul 2>&1
if %errorlevel%==0 (
    echo [OK] 计划任务 CompileTriggerTask 已创建
) else (
    echo [WARN] CompileTriggerTask 创建失败，可能需要管理员权限
)

:skip_task

:: ---- 8. 生成 compile_test.sh 的环境信息 ----
set "ENV_FILE=%SCRIPT_DIR%\compile_env.sh"
set "FLASH_LOG=%APPDATA%\Macromedia\Flash Player\Logs\flashlog.txt"
set "FLASH_LOG_SH=%FLASH_LOG:\=/%"
set "COMMANDS_SH=%COMMANDS_DIR:\=/%"
set "SCRIPT_DIR_SH=%SCRIPT_DIR:\=/%"

(
echo #!/bin/bash
echo # Auto-generated by setup_compile_env.bat
echo # 编译环境变量 - 由 compile_test.sh 自动 source
echo FLASH_LOG="%FLASH_LOG_SH%"
echo JSFL_PATH="%COMMANDS_SH%/compile.jsfl"
echo MARKER="%SCRIPT_DIR_SH%/publish_done.marker"
echo ERROR_MARKER="%SCRIPT_DIR_SH%/publish_error.marker"
echo SCRIPTS_DIR="%SCRIPT_DIR_SH%"
) > "%ENV_FILE%"
echo [OK] Shell 环境配置: %ENV_FILE%

echo.
echo ========================================
echo  配置完成！
echo ========================================
echo.
echo 使用方法：
echo   1. 启动 Flash CS6（手动或通过计划任务）
echo   2. 在 Flash 中打开 TestLoader（首次需手动）
echo   3. Agent 执行: bash scripts/compile_test.sh
echo.
pause
