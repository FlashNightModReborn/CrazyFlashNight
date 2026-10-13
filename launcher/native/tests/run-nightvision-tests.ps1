[CmdletBinding()]
param([string]$NativeBuildDirectory)
$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
$nightRoot=Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
if(-not $NativeBuildDirectory){$NativeBuildDirectory=Join-Path $nightRoot 'tmp\night-vision-native-tests'}
$NativeBuildDirectory=[IO.Path]::GetFullPath($NativeBuildDirectory)
New-Item -ItemType Directory -Force -Path $NativeBuildDirectory | Out-Null
& node (Join-Path $nightRoot 'tools/generate-night-vision-structure.mjs') --check
if($LASTEXITCODE -ne 0){throw 'LUT laboratory structure shaders are stale'}
& (Join-Path $nightRoot 'tools\check-runtime-build-env.ps1') -ProjectRoot $nightRoot -Mode Validate
$env:CF7_NATIVE_OUTPUT_DIR=$NativeBuildDirectory
$env:CF7_WORLD_COMPOSITOR_SOURCE_DIR=Join-Path $nightRoot 'launcher\native\world-compositor'
& (Join-Path $env:CF7_WORLD_COMPOSITOR_SOURCE_DIR 'build.bat')
if($LASTEXITCODE -ne 0){throw 'Native compositor build failed'}
$env:CF7_NV_TEST_SOURCE=Join-Path $PSScriptRoot 'NightVisionSelfTest.cpp'
$batch=@'
@echo off
call "%CF7_VCVARS64%" %CF7_WINDOWS_SDK_VERSION% -vcvars_ver=%CF7_MSVC_TOOLS_VERSION% >nul
if errorlevel 1 exit /b 1
cl.exe /nologo /EHsc /O2 /W4 /WX /MT /utf-8 /std:c++20 /DUNICODE /D_UNICODE /I"%CF7_NATIVE_OUTPUT_DIR%" "%CF7_NV_TEST_SOURCE%" /Fo"%CF7_NATIVE_OUTPUT_DIR%\NightVisionSelfTest.obj" /Fe"%CF7_NATIVE_OUTPUT_DIR%\NightVisionSelfTest.exe" /link d3d11.lib dxgi.lib windowsapp.lib
if errorlevel 1 exit /b 1
"%CF7_NATIVE_OUTPUT_DIR%\NightVisionSelfTest.exe"
exit /b %errorlevel%
'@
$batchPath=Join-Path $NativeBuildDirectory 'run-nightvision-selftest.cmd'
[IO.File]::WriteAllText($batchPath,$batch,[Text.UTF8Encoding]::new($false))
& $batchPath
if($LASTEXITCODE -ne 0){throw 'Night vision GPU behavior failed'}
