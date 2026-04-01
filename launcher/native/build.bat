@echo off
REM CF7:ME miniaudio native DLL build script
REM Output: launcher\bin\Release\miniaudio.dll

setlocal

REM Auto-detect MSVC environment
if not defined VCINSTALLDIR (
    for %%v in (
        "C:\Program Files\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
        "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat"
        "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
        "C:\Program Files (x86)\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat"
        "C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
    ) do (
        if exist %%v (
            echo [INFO] Found MSVC: %%v
            call %%v
            goto :build
        )
    )
    echo [FAIL] MSVC not found. Install Visual Studio Build Tools 2022.
    exit /b 1
)

:build
echo [INFO] Compiling miniaudio_bridge.c ...

REM Output to launcher\bin\Release (relative to this script's directory)
set "OUTDIR=%~dp0..\bin\Release"
if not exist "%OUTDIR%" mkdir "%OUTDIR%"

cl /O2 /LD /W3 /D_CRT_SECURE_NO_WARNINGS "%~dp0miniaudio_bridge.c" /Fe:"%OUTDIR%\miniaudio.dll" /link ole32.lib

if errorlevel 1 (
    echo [FAIL] Compilation failed.
    exit /b 1
)

echo [OK] miniaudio.dll built successfully.
endlocal
