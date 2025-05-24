@echo off
SETLOCAL ENABLEDELAYEDEXPANSION
echo Starting the setup process...

:: Check Node.js installation and update if necessary
echo Checking for Node.js installation...
node -v >nul 2>&1
IF %ERRORLEVEL% EQU 0 (
    echo Node.js is already installed.
    FOR /F "tokens=*" %%i IN ('node -v') DO SET INSTALLED_VERSION=%%i
    echo Current installed version: !INSTALLED_VERSION!
    IF "!INSTALLED_VERSION!"=="v20.12.2" (
        echo Correct version of Node.js v20.12.2 is already installed.
    ) ELSE (
        echo Incorrect version found. Updating to v20.12.2...
        powershell -command "Start-Bitstransfer -Source https://nodejs.org/dist/v20.12.2/node-v20.12.2-x64.msi -Destination %temp%\nodejs-installer.msi"
        echo Download completed. Starting installation...
        msiexec /i %temp%\nodejs-installer.msi /quiet
        echo Node.js has been updated to v20.12.2.
    )
) ELSE (
    echo Node.js is not installed. Installing now...
    powershell -command "Start-Bitstransfer -Source https://nodejs.org/dist/v20.12.2/node-v20.12.2-x64.msi -Destination %temp%\nodejs-installer.msi"
    echo Download completed. Starting installation...
    msiexec /i %temp%\nodejs-installer.msi /quiet
    echo Node.js has been installed.
)

:: Setting up Flash Player trust directory
echo Setting up Flash Player trust directory...

:: Locate the script's current directory
set "current_dir=%~dp0"
echo Current directory: !current_dir!

:: Move up directories to find the 'resources' directory
set "parent_dir=!current_dir!..\"

:find_resources
for %%i in ("!parent_dir!") do set "parent_dir=%%~dpi"
echo Checking: !parent_dir!
if exist "!parent_dir!resources\" (
    set "trust_dir=!parent_dir!resources\"
    echo Trust directory found: !trust_dir!
    goto set_trust
) else (
    if "!parent_dir!"=="\" (
        echo Failed to find the resources directory. Exiting...
        goto error_find_resource
    )
    set "parent_dir=!parent_dir!..\"
    goto find_resources
)

:set_trust
:: Write the trust directory to Flash Player's config
set "flash_trust_file=C:\Windows\SysWOW64\Macromed\Flash\FlashPlayerTrust\"
if not exist "!flash_trust_file!" mkdir "!flash_trust_file!"
echo Writing trust directory to: !flash_trust_file!\project.cfg
echo !trust_dir! > "!flash_trust_file!\project.cfg"
echo Trust settings updated.

echo All done.
goto end

:error_find_resource
echo Setup process encountered an error and could not complete.
:end



@echo off
SETLOCAL ENABLEDELAYEDEXPANSION

:: 记录脚本的运行起始位置
echo Script is running from: "%~dp0"
set "base_dir=%~dp0"

:: 尝试定位到 'Local Server' 目录
:: 假定 'Local Server' 是位于 'resources' 文件夹内部
cd /D "%base_dir%"

:: 寻找含有 'server.js' 的正确目录
echo Searching for the 'Local Server' directory containing server.js...
:find_server_dir
if exist "%base_dir%Local Server\server.js" (
    set "server_dir=%base_dir%Local Server"
    echo Found 'server.js' in: "!server_dir!"
    cd /D "!server_dir!"
    goto start_server
) else (
    echo Not found in: "!base_dir!Local Server"
    set "base_dir=%base_dir%.."
    if not "!base_dir!"=="\" (
        echo Going up one directory to: "!base_dir!"
        goto find_server_dir
    ) else (
        echo Unable to find the 'Local Server' directory with 'server.js' in any parent directories.
        pause
        exit /b
    )
)

:start_server
:: 在确定的目录内启动服务器
if exist "server.js" (
    echo Starting the server...
    node server.js
    if %errorlevel% neq 0 (
        echo Failed to start the server.
        pause
    ) else (
        echo Server has been started successfully.
    )
) else (
    echo Server file 'server.js' not found in the expected directory.
    pause
)

echo Setup process completed.
pause >nul
exit /b