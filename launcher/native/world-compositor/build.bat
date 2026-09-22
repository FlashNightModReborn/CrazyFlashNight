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
cl.exe %COMMON% /std:c++20 /LD Compositor.cpp /Fo"%CF7_NATIVE_OUTPUT_DIR%\Compositor.obj" /Fe"%CF7_NATIVE_OUTPUT_DIR%\FlashCompositorNative.dll" /link /INCREMENTAL:NO /Brepro dcomp.lib d3d11.lib dxgi.lib d3dcompiler.lib windowsapp.lib user32.lib
if errorlevel 1 goto :failed
cl.exe %COMMON% /std:c++17 /LD InputBridge.cpp /Fo"%CF7_NATIVE_OUTPUT_DIR%\InputBridge.obj" /Fe"%CF7_NATIVE_OUTPUT_DIR%\FlashInputBridge.dll" /link /INCREMENTAL:NO /Brepro user32.lib gdi32.lib dwmapi.lib
if errorlevel 1 goto :failed
cl.exe %COMMON% /std:c++17 InputBroker.cpp /Fo"%CF7_NATIVE_OUTPUT_DIR%\InputBroker.obj" /Fe"%CF7_NATIVE_OUTPUT_DIR%\FlashInputBroker.exe" /link /INCREMENTAL:NO /Brepro user32.lib
if errorlevel 1 goto :failed
popd
endlocal & exit /b 0
:failed
popd
endlocal & exit /b 1
