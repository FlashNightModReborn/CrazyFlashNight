@echo off
:: ============================================================
:: CF7:FlashNight Bootstrap Build (cl.exe)
:: 复用 miniaudio 的 vcvars64 探测；输出 bootstrap.exe 到 launcher\bin\Release
:: ============================================================
setlocal

set "SCRIPT_DIR=%~dp0"
:: SCRIPT_DIR 末尾带反斜杠，去掉
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
if defined CF7_NATIVE_OUTPUT_DIR (
    set "OUT_DIR=%CF7_NATIVE_OUTPUT_DIR%"
) else (
    set "OUT_DIR=%SCRIPT_DIR%\..\..\bin\Release"
)

if not exist "%OUT_DIR%" mkdir "%OUT_DIR%"

if not defined CF7_VCVARS64 (
    echo [ERROR] Pinned MSVC baseline is not loaded. Run launcher\build.ps1.
    exit /b 1
)
if not defined CF7_MSVC_TOOLS_VERSION exit /b 1
if not defined CF7_WINDOWS_SDK_VERSION exit /b 1
set "VCVARS=%CF7_VCVARS64%"

if exist "%VCVARS%" goto :vcvars_exists
echo [ERROR] selected vcvars64.bat does not exist: %VCVARS%
exit /b 1

:vcvars_exists

if defined CF7_VSWHERE_DIR set "PATH=%CF7_VSWHERE_DIR%;%PATH%"
call "%VCVARS%" %CF7_WINDOWS_SDK_VERSION% -vcvars_ver=%CF7_MSVC_TOOLS_VERSION% >nul
if errorlevel 1 exit /b 1
call "%SCRIPT_DIR%\..\assert-pinned-tools.bat"
if errorlevel 1 exit /b 1

echo [INFO] Compiling bootstrap.rc ^(rc.exe^) -^> bootstrap.res...
pushd "%OUT_DIR%"
rc.exe /nologo /fo bootstrap.res "%SCRIPT_DIR%\bootstrap.rc"
if errorlevel 1 (
    echo [FAIL] bootstrap.rc compilation failed
    popd
    exit /b 1
)

echo [INFO] Compiling bootstrap.cpp ^(cl.exe^)...
:: /Brepro 让 link.exe 写入 IMAGE_FILE_HEADER.TimeDateStamp = 0 + 用源哈希取代 PDB GUID,
:: 让相同源码 → 相同字节产物 (reproducible build); 同源重建后 git status 不会看到 M.
:: 见 launcher/build.ps1 顶部"Reproducible build"备注与 docs/build-reproducibility.md.
cl.exe /nologo /O2 /MT /EHsc /W3 ^
    /source-charset:utf-8 /execution-charset:utf-8 ^
    /DUNICODE /D_UNICODE /D_WIN32_WINNT=0x0A00 ^
    /Fe:bootstrap.exe ^
    "%SCRIPT_DIR%\bootstrap.cpp" ^
    bootstrap.res ^
    /link /SUBSYSTEM:WINDOWS /MANIFESTUAC:level=asInvoker /Brepro ^
    shell32.lib user32.lib kernel32.lib advapi32.lib

set "BUILD_ERR=%ERRORLEVEL%"
:: cl.exe 产生的中间文件清理（bootstrap.obj + bootstrap.res 都在 OUT_DIR）
if exist bootstrap.obj del /f /q bootstrap.obj 2>nul
if exist bootstrap.res del /f /q bootstrap.res 2>nul
popd

if not "%BUILD_ERR%"=="0" (
    echo [FAIL] bootstrap.cpp compilation failed ^(exit %BUILD_ERR%^)
    exit /b 1
)

if not exist "%OUT_DIR%\bootstrap.exe" (
    echo [FAIL] bootstrap.exe not produced
    exit /b 1
)

echo [OK] bootstrap.exe built at %OUT_DIR%\bootstrap.exe
endlocal & exit /b 0
