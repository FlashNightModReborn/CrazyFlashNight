[CmdletBinding()]
param([switch]$ArenaAutomation)
$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
& node (Join-Path $repo 'tools\fontctl\cli.js') generate --check --project-root $repo
if ($LASTEXITCODE -ne 0) { throw 'Font catalog is stale. Run node tools/fontctl/cli.js generate from the repository root, then retry.' }
$output=Join-Path $repo 'tmp\flash-compositor\game'
$manifestPath=Join-Path $output 'development-pair.json'
if (-not (Test-Path -LiteralPath $manifestPath)) { throw '先运行 build-game.ps1 生成配套开发构建。' }
$manifest=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($entry in $manifest.files) {
    if (-not (Test-Path -LiteralPath $entry.path) -or (Get-FileHash -LiteralPath $entry.path -Algorithm SHA256).Hash -ne $entry.sha256) {
        throw ('开发产物已变化，请重新构建并验证：'+$entry.path)
    }
}
. (Join-Path $repo 'launcher\resolve-dotnet.ps1')
$sdk=Resolve-Cf7Dotnet -ProjectRoot $repo
$previousRoot=$env:DOTNET_ROOT_X64
try {
    $env:DOTNET_ROOT_X64=Split-Path -Parent $sdk
    $gameArgs=@('--project-root',$repo)
    if ($ArenaAutomation) { $gameArgs+='--legacy-http-automation' }
    & (Join-Path $output 'CRAZYFLASHER7MercenaryEmpire.Core.exe') @gameArgs
    $result=$LASTEXITCODE
} finally { $env:DOTNET_ROOT_X64=$previousRoot }
exit $result
