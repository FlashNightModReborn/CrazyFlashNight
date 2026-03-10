@echo off
chcp 65001 >nul
setlocal

set "JSFL=C:\Users\fs\AppData\Local\Adobe\Flash CS6\zh_CN\Configuration\Commands\test_simple.jsfl"
set "MARKER=C:\Users\fs\flash_publish_done.txt"
set "LOG=C:\Users\fs\AppData\Roaming\Macromedia\Flash Player\Logs\flashlog.txt"
set "LOCAL_LOG=%~dp0flashlog.txt"

:: Clean
if exist "%MARKER%" del "%MARKER%"
if exist "%LOG%" del "%LOG%"

:: Trigger JSFL
start "" "%JSFL%"

:: Wait for marker (max 30s)
set /a count=0
:wait
if exist "%MARKER%" goto :done
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
    echo [NO LOG]
)
del "%MARKER%"

:end
