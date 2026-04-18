@echo off
REM CF7:ME SOL parser native DLL build script (Rust)
REM Output: launcher\bin\Release\sol_parser.dll

setlocal

where cargo >nul 2>&1
if errorlevel 1 (
    echo [FAIL] cargo not found. Install Rust via rustup.
    exit /b 1
)

cd /d "%~dp0"
echo [INFO] Building sol_parser.dll ...

set "OUTDIR=%~dp0..\..\bin\Release"
if not exist "%OUTDIR%" mkdir "%OUTDIR%"

cargo build --release --target x86_64-pc-windows-msvc
if errorlevel 1 (
    echo [FAIL] Cargo build failed.
    exit /b 1
)

copy /Y "target\x86_64-pc-windows-msvc\release\sol_parser.dll" "%OUTDIR%\sol_parser.dll" >nul
if errorlevel 1 (
    echo [FAIL] Could not copy sol_parser.dll to %OUTDIR%.
    exit /b 1
)

echo [OK] sol_parser.dll built successfully.
endlocal
