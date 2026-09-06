param([ValidateSet('api','read','hud','serve')][string]$Command = 'read', [int]$Port = 18765)
$ErrorActionPreference = 'Stop'
$mapProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $mapProjectRoot 'launcher/resolve-dotnet.ps1')
$mapDotnet = Resolve-Cf7Dotnet -ProjectRoot $mapProjectRoot
& $mapDotnet build (Join-Path $PSScriptRoot 'MapWorkbench.csproj') -c Release --nologo -v quiet | Out-Host
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $mapDotnet (Join-Path $PSScriptRoot 'bin/Release/net10.0/MapWorkbench.dll') $Command $mapProjectRoot $Port
exit $LASTEXITCODE
