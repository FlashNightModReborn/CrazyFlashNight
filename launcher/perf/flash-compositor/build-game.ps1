[CmdletBinding()]
param([switch]$Run)
$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
& node (Join-Path $repo 'tools\fontctl\cli.js') generate --check --project-root $repo
if ($LASTEXITCODE -ne 0) { throw 'Font catalog is stale. Run node tools/fontctl/cli.js generate from the repository root, then retry.' }
& (Join-Path $PSScriptRoot 'build.ps1')
. (Join-Path $repo 'launcher\resolve-dotnet.ps1')
$sdk=Resolve-Cf7Dotnet -ProjectRoot $repo
$output=Join-Path $repo 'tmp\flash-compositor\game'
& $sdk build (Join-Path $repo 'launcher\CRAZYFLASHER7MercenaryEmpire.csproj') -c Release -o $output --nologo
if ($LASTEXITCODE -ne 0) { throw 'Game development build failed' }
Copy-Item -LiteralPath (Join-Path $repo 'tmp\flash-compositor\bin\FlashCompositorNative.dll') -Destination $output -Force
foreach($inputModule in @('FlashInputBroker.exe','FlashInputBridge.dll')) {
    Copy-Item -LiteralPath (Join-Path $repo ('tmp\flash-compositor\bin\'+$inputModule)) -Destination $output -Force
}
# Reuse the currently deployed audio native dependency; do not rebuild or replace it.
Copy-Item -LiteralPath (Join-Path $repo 'runtime\miniaudio.dll') -Destination $output -Force
$identities=@('CRAZYFLASHER7MercenaryEmpire.Core.exe','CRAZYFLASHER7MercenaryEmpire.Core.dll','FlashCompositorNative.dll','FlashInputBroker.exe','FlashInputBridge.dll') | ForEach-Object {
    [pscustomobject]@{path=(Join-Path $output $_);sha256=(Get-FileHash -LiteralPath (Join-Path $output $_) -Algorithm SHA256).Hash}
}
$identities+= [pscustomobject]@{path=(Join-Path $repo 'scripts\asLoader.swf');sha256=(Get-FileHash -LiteralPath (Join-Path $repo 'scripts\asLoader.swf') -Algorithm SHA256).Hash}
[pscustomobject]@{kind='local-development-pair';createdUtc=[DateTime]::UtcNow.ToString('o');files=@($identities)} |
    ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $output 'development-pair.json') -Encoding UTF8
Write-Output "Development build: $output"
if ($Run) { & (Join-Path $PSScriptRoot 'run-game.ps1'); exit $LASTEXITCODE }
