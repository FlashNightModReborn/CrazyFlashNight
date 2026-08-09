@echo off
REM CF7:ME Audio v2 native DLL build script
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
echo [INFO] Compiling Audio v2 native source closure ...

if not defined CF7_MINIAUDIO_REPRO_SOURCE_DIR goto :missing_source
if not exist "%CF7_MINIAUDIO_REPRO_SOURCE_DIR%\audio-v2-build-inputs.v1.json" goto :missing_manifest
if not exist "%CF7_MINIAUDIO_REPRO_SOURCE_DIR%\build-audio-v2.ps1" goto :missing_compiler

REM Formal workers provide a per-job output directory so a proof build never
REM deletes or overwrites another checkout's launcher\bin\Release.
if defined CF7_NATIVE_OUTPUT_DIR goto :job_output
set "OUTDIR=%~dp0..\bin\Release"
goto :output_ready

:job_output
set "OUTDIR=%CF7_NATIVE_OUTPUT_DIR%"

:output_ready
if not exist "%OUTDIR%" mkdir "%OUTDIR%"

REM The compiler consumes the tracked, ordered build-input manifest. Every
REM source receives a stable object name and all codecs link into one DLL.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%CF7_MINIAUDIO_REPRO_SOURCE_DIR%\build-audio-v2.ps1" ^
  -SourceDirectory "%CF7_MINIAUDIO_REPRO_SOURCE_DIR%" ^
  -OutputDirectory "%OUTDIR%"

if errorlevel 1 (
    echo [FAIL] Audio v2 compilation failed.
    exit /b 1
)

echo [OK] miniaudio.dll built successfully.
endlocal
exit /b 0

:missing_source
echo [FAIL] Canonical Audio v2 source directory is missing. Run launcher\build.ps1.
exit /b 1

:missing_manifest
echo [FAIL] Canonical Audio v2 build input manifest is missing.
exit /b 1

:missing_compiler
echo [FAIL] Canonical Audio v2 compiler is missing.
exit /b 1
