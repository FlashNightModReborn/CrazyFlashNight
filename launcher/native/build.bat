@echo off
REM CF7:ME miniaudio native DLL build script
REM Output: launcher\bin\Release\miniaudio.dll

setlocal

if not defined CF7_VCVARS64 goto :missing_baseline
if not defined CF7_MSVC_TOOLS_VERSION goto :missing_baseline
if not defined CF7_WINDOWS_SDK_VERSION goto :missing_baseline
if exist "%CF7_VCVARS64%" goto :pinned_vcvars
echo [FAIL] CF7_VCVARS64 does not exist: %CF7_VCVARS64%
exit /b 1

:pinned_vcvars
if defined CF7_VSWHERE_DIR set "PATH=%CF7_VSWHERE_DIR%;%PATH%"
call "%CF7_VCVARS64%" %CF7_WINDOWS_SDK_VERSION% -vcvars_ver=%CF7_MSVC_TOOLS_VERSION%
if errorlevel 1 exit /b 1
call "%~dp0assert-pinned-tools.bat"
if errorlevel 1 exit /b 1
goto :build

:missing_baseline
echo [FAIL] Pinned MSVC/SDK baseline is not loaded. Run launcher\build.ps1.
exit /b 1

:build
echo [INFO] Compiling miniaudio_bridge.c ...

REM Output to launcher\bin\Release (relative to this script's directory)
set "OUTDIR=%~dp0..\bin\Release"
if not exist "%OUTDIR%" mkdir "%OUTDIR%"

REM /Brepro 让 link.exe 写入 IMAGE_FILE_HEADER.TimeDateStamp = 0 + 用源哈希取代 PDB GUID,
REM 让相同源码 -> 相同字节产物 (reproducible build); 同源重建后 git status 不会看到 M.
cl /O2 /LD /W3 /D_CRT_SECURE_NO_WARNINGS "%~dp0miniaudio_bridge.c" /Fe:"%OUTDIR%\miniaudio.dll" /link /Brepro ole32.lib

if errorlevel 1 (
    echo [FAIL] Compilation failed.
    exit /b 1
)

echo [OK] miniaudio.dll built successfully.
endlocal
