[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
chcp.com 65001 | Out-Null
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$out = Join-Path $repo 'tmp\flash-compositor\bin'
New-Item -ItemType Directory -Force -Path $out | Out-Null
# Use the same pinned native producer as the production-source G1 fixtures.
# Probe validation and a development candidate must not silently differ by toolchain/linkage.
$nativeShell = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
if (-not $nativeShell) { $nativeShell = (Get-Command powershell -ErrorAction Stop).Source }
# The native producer normalizes process build variables; isolate that environment
# so the following pinned .NET SDK resolver still sees its own managed toolchain.
& $nativeShell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'launcher\native\world-compositor\build-dev.ps1') -OutDir $out
if ($LASTEXITCODE -ne 0) { throw "Native build failed: $LASTEXITCODE" }
. (Join-Path $repo 'launcher\resolve-dotnet.ps1')
$sdk = Resolve-Cf7Dotnet -ProjectRoot $repo
& $sdk build (Join-Path $PSScriptRoot 'FlashCompositorProbe.csproj') -c Release -o $out --nologo
if ($LASTEXITCODE -ne 0) { throw "Managed build failed: $LASTEXITCODE" }
Write-Output "Prototype executable: $out\FlashCompositorProbe.exe"
