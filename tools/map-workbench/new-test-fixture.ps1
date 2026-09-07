[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
chcp.com 65001 | Out-Null
$mapSourceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..')).TrimEnd('\')
$mapFixtureRoot = Join-Path ([IO.Path]::GetPathRoot($mapSourceRoot)) ('cf7-map-ui-fixtures/ui-' + [Guid]::NewGuid().ToString('N'))
$mapPreparedPath = Join-Path $mapSourceRoot 'tmp/map-workbench/map-definition.prepared-v2.json'
$mapCanonicalPath = Join-Path $mapSourceRoot 'data/map/map_definition.json'
if ((Get-Content -LiteralPath $mapCanonicalPath -Raw -Encoding UTF8 | ConvertFrom-Json).version -eq 2) { $mapPreparedPath = $mapCanonicalPath }
if (!(Test-Path -LiteralPath $mapPreparedPath -PathType Leaf)) { throw 'Run migrate-v2.js --prepared after building the CLI first.' }
if (Test-Path -LiteralPath $mapFixtureRoot) { throw 'The fixture target must not already exist.' }
New-Item -ItemType Directory -Path $mapFixtureRoot | Out-Null
$mapLinkedCount = 0
function Add-MapFixtureFile([string]$RelativePath) {
    $source = [IO.Path]::GetFullPath((Join-Path $mapSourceRoot $RelativePath))
    $target = [IO.Path]::GetFullPath((Join-Path $mapFixtureRoot $RelativePath))
    if (!$source.StartsWith($mapSourceRoot + '\',[StringComparison]::OrdinalIgnoreCase) -or !$target.StartsWith($mapFixtureRoot + '\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Fixture path escaped its exact roots.' }
    if (!(Test-Path -LiteralPath $source -PathType Leaf)) { return }
    if ((Get-Item -LiteralPath $source -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw ('Reparse source: '+$source) }
    if (Test-Path -LiteralPath $target) { return }
    New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($target)) -Force | Out-Null
    [IO.File]::Copy($source,$target,$false)
    $script:mapLinkedCount++
}
function Add-MapFixtureTree([string]$RelativePath,[string[]]$Extensions) {
    $folder = Join-Path $mapSourceRoot $RelativePath
    if (!(Test-Path -LiteralPath $folder -PathType Container)) { return }
    $files = & rg --files --hidden $folder
    foreach ($file in $files) {
        if ($Extensions -and $Extensions -notcontains [IO.Path]::GetExtension($file).ToLowerInvariant()) { continue }
        Add-MapFixtureFile $file.Substring($mapSourceRoot.Length + 1)
    }
}
Add-MapFixtureTree 'data/task' @('.json','.xml')
foreach ($file in @('data/infrastructure/infrastructure.xml','data/environment/scene_environment.xml','data/items/asset_source_map.xml','CRAZYFLASHER7MercenaryEmpire.swf','tools/convert-map-assets-webp.py','tools/map-workbench/harness.html')) { Add-MapFixtureFile $file }
Add-MapFixtureTree 'launcher/web/modules' @('.js','.html')
Add-MapFixtureTree 'launcher/web/css' @('.css')
Add-MapFixtureTree 'launcher/web/help' @('.md')
Add-MapFixtureFile 'launcher/web/lib/marked.min.js'
Add-MapFixtureFile 'launcher/web/generated/font-catalog.css'
Add-MapFixtureTree 'launcher/web/assets/map' @('.webp','.png','.json')
Add-MapFixtureTree 'launcher/web/fonts' @()
Add-MapFixtureTree 'launcher/web/assets/fonts' @()
$mapSceneLocator = [xml](Get-Content -LiteralPath (Join-Path $mapSourceRoot 'data/items/asset_source_map.xml') -Raw -Encoding UTF8)
$mapSwfs = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
[void]$mapSwfs.Add('CRAZYFLASHER7MercenaryEmpire.swf')
$mapEnvironments = [xml](Get-Content -LiteralPath (Join-Path $mapSourceRoot 'data/environment/scene_environment.xml') -Raw -Encoding UTF8)
$mapWanted = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
foreach ($environment in $mapEnvironments.DocumentElement.Environment) {
    $scene = [string]$environment.BackgroundURL
    if ($scene) { [void]$mapWanted.Add($(if ($scene.StartsWith('地图-')) { $scene } else { '基地场景-' + $scene })) }
}
foreach ($asset in $mapSceneLocator.DocumentElement.asset) {
    if (!$mapWanted.Contains([string]$asset.id)) { continue }
    foreach ($source in @($asset.swf) + @($asset.source | ForEach-Object { $_.swf })) { if ($source) { [void]$mapSwfs.Add([string]$source) } }
}
foreach ($swf in @($mapSwfs | Where-Object { $_ -and ($_ -eq 'CRAZYFLASHER7MercenaryEmpire.swf' -or $_ -like 'flashswf/levels/*.swf') } | Sort-Object -Unique)) {
    Add-MapFixtureFile $swf
    $stem = $swf.Substring(0,$swf.Length - 4)
    if (Test-Path -LiteralPath (Join-Path $mapSourceRoot ($stem + '/DOMDocument.xml'))) { Add-MapFixtureTree $stem @('.xml','.xfl') }
    else { Add-MapFixtureFile ($stem + '.fla') }
}
# 所有输入均为独立副本；此目录的应用、撤回与来源操作不会修改原项目。
$mapFixtureDefinition = Join-Path $mapFixtureRoot 'data/map/map_definition.json'
New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($mapFixtureDefinition)) -Force | Out-Null
if (Test-Path -LiteralPath $mapFixtureDefinition) { throw 'Fixture definition unexpectedly exists.' }
Copy-Item -LiteralPath $mapPreparedPath -Destination $mapFixtureDefinition
[pscustomobject]@{ fixtureRoot=$mapFixtureRoot; copiedReadFiles=$mapLinkedCount; independentDefinition=$mapFixtureDefinition } | ConvertTo-Json -Compress
