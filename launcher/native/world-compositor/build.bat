@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
if not defined CF7_NATIVE_OUTPUT_DIR exit /b 1
if not defined CF7_WORLD_COMPOSITOR_SOURCE_DIR exit /b 1
if not defined CF7_VCVARS64 exit /b 1
if not defined CF7_MSVC_TOOLS_VERSION exit /b 1
if not defined CF7_WINDOWS_SDK_VERSION exit /b 1
if defined CF7_VSWHERE_DIR set "PATH=%CF7_VSWHERE_DIR%;%PATH%"
call "%CF7_VCVARS64%" %CF7_WINDOWS_SDK_VERSION% -vcvars_ver=%CF7_MSVC_TOOLS_VERSION% >nul
if errorlevel 1 exit /b 1
call "%SCRIPT_DIR%..\assert-pinned-tools.bat"
if errorlevel 1 exit /b 1
pushd "%CF7_WORLD_COMPOSITOR_SOURCE_DIR%"
if errorlevel 1 exit /b 1
set COMMON=/nologo /EHsc /O2 /W4 /WX /MT /utf-8 /DUNICODE /D_UNICODE /experimental:deterministic "/pathmap:%CF7_WORLD_COMPOSITOR_SOURCE_DIR%=C:\cf7-world-src" "/pathmap:%CF7_NATIVE_OUTPUT_DIR%=C:\cf7-world-out"
rem Shared scene compiled separately: one /Fo cannot name multiple sources.
cl.exe %COMMON% /std:c++20 /c CompositionScene.cpp /Fo"%CF7_NATIVE_OUTPUT_DIR%\CompositionScene.obj"
if errorlevel 1 goto :failed
cl.exe %COMMON% /std:c++20 /LD Compositor.cpp "%CF7_NATIVE_OUTPUT_DIR%\CompositionScene.obj" /Fo"%CF7_NATIVE_OUTPUT_DIR%\Compositor.obj" /Fe"%CF7_NATIVE_OUTPUT_DIR%\FlashCompositorNative.dll" /link /INCREMENTAL:NO /Brepro dcomp.lib d3d11.lib dxgi.lib d3dcompiler.lib windowsapp.lib user32.lib
if errorlevel 1 goto :failed
cl.exe %COMMON% /std:c++17 /LD InputBridge.cpp /Fo"%CF7_NATIVE_OUTPUT_DIR%\InputBridge.obj" /Fe"%CF7_NATIVE_OUTPUT_DIR%\FlashInputBridge.dll" /link /INCREMENTAL:NO /Brepro user32.lib gdi32.lib dwmapi.lib
if errorlevel 1 goto :failed
cl.exe %COMMON% /std:c++17 InputBroker.cpp /Fo"%CF7_NATIVE_OUTPUT_DIR%\InputBroker.obj" /Fe"%CF7_NATIVE_OUTPUT_DIR%\FlashInputBroker.exe" /link /INCREMENTAL:NO /Brepro user32.lib
if errorlevel 1 goto :failed
rem Opt-in self-test target: `build.bat selftest` additionally compiles the
rem bridge's real WindowProc into a standalone harness. It is not part of the
rem runtime closure; default invocation above is unchanged.
if /i "%~1"=="selftest" (
    if not exist "%CF7_NATIVE_OUTPUT_DIR%\selftest" mkdir "%CF7_NATIVE_OUTPUT_DIR%\selftest"
    cl.exe %COMMON% /std:c++17 /DCF7_INPUT_BRIDGE_SELFTEST /c InputBridge.cpp /Fo"%CF7_NATIVE_OUTPUT_DIR%\selftest\InputBridge.obj"
    if errorlevel 1 goto :failed
    cl.exe %COMMON% /std:c++17 /DCF7_INPUT_BRIDGE_SELFTEST /c InputBridgeSelfTest.cpp /Fo"%CF7_NATIVE_OUTPUT_DIR%\selftest\InputBridgeSelfTest.obj"
    if errorlevel 1 goto :failed
    cl.exe %COMMON% /std:c++17 "%CF7_NATIVE_OUTPUT_DIR%\selftest\InputBridge.obj" "%CF7_NATIVE_OUTPUT_DIR%\selftest\InputBridgeSelfTest.obj" /Fe"%CF7_NATIVE_OUTPUT_DIR%\InputBridgeSelfTest.exe" /link /INCREMENTAL:NO /Brepro user32.lib gdi32.lib dwmapi.lib
    if errorlevel 1 goto :failed
)
rem Opt-in G1 fixture target: `build.bat g1fixture` compiles the cross-process
rem target process used by the real-queue revoke/re-admit evidence lane.
rem Fixture-only artifact; never part of the runtime closure or default outputs.
if /i "%~1"=="g1fixture" (
    if not exist "%CF7_NATIVE_OUTPUT_DIR%\g1fixture" mkdir "%CF7_NATIVE_OUTPUT_DIR%\g1fixture"
    cl.exe %COMMON% /std:c++17 g1-fixture\G1Target.cpp /Fo"%CF7_NATIVE_OUTPUT_DIR%\g1fixture\G1Target.obj" /Fe"%CF7_NATIVE_OUTPUT_DIR%\G1Target.exe" /link /INCREMENTAL:NO /Brepro user32.lib gdi32.lib
    if errorlevel 1 goto :failed
)
rem Explicit isolated C1-I scene only; excluded from default runtime outputs.
if /i "%~1"=="c1fixture" (
    cl.exe %COMMON% /std:c++20 /LD input-ownership-fixture\C1Scene.cpp /Fo"%CF7_NATIVE_OUTPUT_DIR%\C1Scene.obj" /Fe"%CF7_NATIVE_OUTPUT_DIR%\C1Scene.dll" /link /INCREMENTAL:NO /Brepro dcomp.lib d3d11.lib dxgi.lib windowsapp.lib user32.lib
    if errorlevel 1 goto :failed
)
popd
endlocal & exit /b 0
:failed
popd
endlocal & exit /b 1
