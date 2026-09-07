param([ValidateSet('api','read','hud','serve','project','catalog','prepare-definition','render-definition','validate-content')][string]$Command = 'read', [int]$Port = 18765, [string]$ProjectRoot)
$ErrorActionPreference = 'Stop'
chcp.com 65001 | Out-Null
$OutputEncoding = [Console]::OutputEncoding = New-Object Text.UTF8Encoding $false
$mapSourceRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$mapProjectRoot = $mapSourceRoot
if ($ProjectRoot) { $mapProjectRoot = [IO.Path]::GetFullPath($ProjectRoot) }
. (Join-Path $mapSourceRoot 'launcher/resolve-dotnet.ps1')
$mapDotnet = Resolve-Cf7Dotnet -ProjectRoot $mapSourceRoot
& $mapDotnet build (Join-Path $PSScriptRoot 'MapWorkbench.csproj') -c Release --nologo -v quiet | Out-Host
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $mapDotnet (Join-Path $PSScriptRoot 'bin/Release/net10.0/MapWorkbench.dll') $Command $mapProjectRoot $Port
exit $LASTEXITCODE
