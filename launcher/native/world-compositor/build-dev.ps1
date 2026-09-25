[CmdletBinding()]
param(
    [ValidateSet('default','selftest','g1fixture','c1fixture')][string]$Target = 'default',
    [string]$OutDir
)
$ErrorActionPreference = 'Stop'
chcp.com 65001 | Out-Null
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
if (-not $OutDir) { $OutDir = Join-Path $repo 'tmp\native-out' }
$OutDir = [IO.Path]::GetFullPath($OutDir)
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
. (Join-Path $repo 'tools\check-runtime-build-env.ps1') -ProjectRoot $repo -Mode Validate
$env:CF7_NATIVE_OUTPUT_DIR = $OutDir
$env:CF7_WORLD_COMPOSITOR_SOURCE_DIR = $PSScriptRoot
& (Join-Path $PSScriptRoot 'build.bat') $Target
if ($LASTEXITCODE -ne 0) { throw "Native development build failed: $LASTEXITCODE" }
if ($Target -eq 'selftest') {
    & (Join-Path $OutDir 'InputBridgeSelfTest.exe')
    if ($LASTEXITCODE -ne 0) { throw "Input bridge self-test failed: $LASTEXITCODE" }
}
