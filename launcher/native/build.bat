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

if not defined CF7_MINIAUDIO_REPRO_SOURCE_DIR (
    echo [FAIL] Canonical miniaudio source directory is missing. Run launcher\build.ps1.
    exit /b 1
)
if not exist "%CF7_MINIAUDIO_REPRO_SOURCE_DIR%\miniaudio_bridge.c" (
    echo [FAIL] Canonical miniaudio_bridge.c is missing: %CF7_MINIAUDIO_REPRO_SOURCE_DIR%
    exit /b 1
)
if not exist "%CF7_MINIAUDIO_REPRO_SOURCE_DIR%\miniaudio.h" (
    echo [FAIL] Canonical miniaudio.h is missing: %CF7_MINIAUDIO_REPRO_SOURCE_DIR%
    exit /b 1
)

REM Formal workers provide a per-job output directory so a proof build never
REM deletes or overwrites another checkout's launcher\bin\Release.
if defined CF7_NATIVE_OUTPUT_DIR (
    set "OUTDIR=%CF7_NATIVE_OUTPUT_DIR%"
) else (
    set "OUTDIR=%~dp0..\bin\Release"
)
if not exist "%OUTDIR%" mkdir "%OUTDIR%"

REM build.ps1 先把 C/H 规范化为 LF；/experimental:deterministic 使 /pathmap 生效，
REM 消除 checkout 换行、用户目录和仓库绝对路径对编译器确定性种子的影响。
REM linker /Brepro 再固定 PE reproducibility hash。同一源码应在不同 builder 上逐字节一致。
cl /nologo /utf-8 /experimental:deterministic /O2 /LD /W3 /D_CRT_SECURE_NO_WARNINGS ^
  "/pathmap:%CF7_MINIAUDIO_REPRO_SOURCE_DIR%=C:\cf7-runtime-src" ^
  "%CF7_MINIAUDIO_REPRO_SOURCE_DIR%\miniaudio_bridge.c" ^
  /Fo:"%OUTDIR%\miniaudio_bridge.obj" /Fe:"%OUTDIR%\miniaudio.dll" ^
  /link /Brepro ole32.lib

if errorlevel 1 (
    echo [FAIL] Compilation failed.
    exit /b 1
)

echo [OK] miniaudio.dll built successfully.
endlocal
