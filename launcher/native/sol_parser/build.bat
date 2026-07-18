@echo off
REM CF7:ME SOL parser native DLL build script (Rust)
REM Output: launcher\bin\Release\sol_parser.dll

setlocal enabledelayedexpansion

if not defined CF7_VCVARS64 (
    echo [FAIL] Pinned MSVC baseline is not loaded. Run launcher\build.ps1.
    exit /b 1
)
if not defined CF7_MSVC_TOOLS_VERSION exit /b 1
if not defined CF7_WINDOWS_SDK_VERSION exit /b 1
if not defined CF7_RUST_TOOLCHAIN exit /b 1
if not defined CF7_CARGO_EXE exit /b 1
if not defined CF7_RUSTC_EXE exit /b 1
if not defined CARGO_ENCODED_RUSTFLAGS exit /b 1

if defined CF7_VSWHERE_DIR set "PATH=%CF7_VSWHERE_DIR%;%PATH%"
call "%CF7_VCVARS64%" %CF7_WINDOWS_SDK_VERSION% -vcvars_ver=%CF7_MSVC_TOOLS_VERSION% >nul
if errorlevel 1 exit /b 1
call "%~dp0..\assert-pinned-tools.bat"
if errorlevel 1 exit /b 1

cd /d "%~dp0"
echo [INFO] Building sol_parser.dll ...

if defined CF7_NATIVE_OUTPUT_DIR (
    set "OUTDIR=%CF7_NATIVE_OUTPUT_DIR%"
) else (
    set "OUTDIR=%~dp0..\..\bin\Release"
)
if not exist "!OUTDIR!" mkdir "!OUTDIR!"

set "CARGO_INCREMENTAL=0"
set "RUSTFLAGS="
set "RUSTC=%CF7_RUSTC_EXE%"
if defined CF7_CARGO_TARGET_DIR (
    set "CARGO_TARGET_DIR=%CF7_CARGO_TARGET_DIR%"
) else (
    set "CARGO_TARGET_DIR=%~dp0target"
)
"%CF7_CARGO_EXE%" clean --release --target x86_64-pc-windows-msvc
if errorlevel 1 exit /b 1
"%CF7_CARGO_EXE%" build --release --locked --target x86_64-pc-windows-msvc
if errorlevel 1 (
    echo [FAIL] Cargo build failed.
    exit /b 1
)

copy /Y "%CARGO_TARGET_DIR%\x86_64-pc-windows-msvc\release\sol_parser.dll" "!OUTDIR!\sol_parser.dll" >nul
if errorlevel 1 (
    echo [FAIL] Could not copy sol_parser.dll to !OUTDIR!.
    exit /b 1
)

echo [OK] sol_parser.dll built successfully.
endlocal
