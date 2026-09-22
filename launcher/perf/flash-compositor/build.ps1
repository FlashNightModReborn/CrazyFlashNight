[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
chcp.com 65001 | Out-Null
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$out = Join-Path $repo 'tmp\flash-compositor\bin'
New-Item -ItemType Directory -Force -Path $out | Out-Null
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$vs = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $vs) { throw 'MSVC C++ build tools required' }
$devcmd = Join-Path $vs 'Common7\Tools\VsDevCmd.bat'
$native = Join-Path $repo 'launcher\native\world-compositor\Compositor.cpp'
# Fixed compiler commands in a generated .cmd; no filesystem mutations delegated to cmd.
$commandFile = Join-Path $out 'compile-native.cmd'
$command = @"
@echo off
call "$devcmd" -arch=x64 -host_arch=x64
if errorlevel 1 exit /b %errorlevel%
cl /nologo /std:c++20 /EHsc /O2 /W4 /WX /utf-8 /LD /DUNICODE /D_UNICODE "$native" /Fo"$out\Compositor.obj" /Fe"$out\FlashCompositorNative.dll" /link /INCREMENTAL:NO dcomp.lib d3d11.lib dxgi.lib d3dcompiler.lib windowsapp.lib user32.lib
exit /b %errorlevel%
"@
[IO.File]::WriteAllText($commandFile, $command, [Text.UTF8Encoding]::new($false))
& $env:ComSpec /d /c ('"' + $commandFile + '"')
if ($LASTEXITCODE -ne 0) { throw "Native build failed: $LASTEXITCODE" }
$inputSource=Join-Path $repo 'launcher\native\world-compositor'
$inputCommand=@"
@echo off
call "$devcmd" -arch=x64 -host_arch=x64
if errorlevel 1 exit /b %errorlevel%
cl /nologo /std:c++17 /EHsc /O2 /W4 /WX /MT /utf-8 /LD /DUNICODE /D_UNICODE "$inputSource\InputBridge.cpp" /Fo"$out\InputBridge.obj" /Fe"$out\FlashInputBridge.dll" /link /INCREMENTAL:NO user32.lib gdi32.lib dwmapi.lib
if errorlevel 1 exit /b %errorlevel%
cl /nologo /std:c++17 /EHsc /O2 /W4 /WX /MT /utf-8 /DUNICODE /D_UNICODE "$inputSource\InputBroker.cpp" /Fo"$out\InputBroker.obj" /Fe"$out\FlashInputBroker.exe" /link /INCREMENTAL:NO user32.lib
exit /b %errorlevel%
"@
$inputCommandFile=Join-Path $out 'compile-input.cmd'
[IO.File]::WriteAllText($inputCommandFile,$inputCommand,[Text.UTF8Encoding]::new($false))
& $env:ComSpec /d /c ('"'+$inputCommandFile+'"')
if($LASTEXITCODE -ne 0){throw "Native input build failed: $LASTEXITCODE"}
$sdk = @((Join-Path $env:LOCALAPPDATA 'Microsoft\dotnet\dotnet.exe'), (Join-Path $env:ProgramFiles 'dotnet\dotnet.exe')) |
    Where-Object { Test-Path -LiteralPath $_ } | Where-Object { (& $_ --list-sdks) -match '^10\.0\.300 ' } | Select-Object -First 1
if (-not $sdk) { throw '.NET SDK 10.0.300 required; no installation performed' }
& $sdk build (Join-Path $PSScriptRoot 'FlashCompositorProbe.csproj') -c Release -o $out --nologo
if ($LASTEXITCODE -ne 0) { throw "Managed build failed: $LASTEXITCODE" }
Write-Output "Prototype executable: $out\FlashCompositorProbe.exe"
