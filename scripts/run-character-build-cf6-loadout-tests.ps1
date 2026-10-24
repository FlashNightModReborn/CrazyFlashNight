[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=600,[switch]$SkipCompile,[switch]$ValidateOnly)
$ErrorActionPreference='Stop'
$projectRoot=Split-Path -Parent $PSScriptRoot
$dataPaths=@(
    'tools/cf6-actor-template/actor.fragment.json'
    'data/equipment/equipment_config.xml'
    'data/items/item_sets.xml'
    'data/items/防具_0-19级.xml'
    'data/items/防具_颈部装备.xml'
    'data/items/武器_长枪_突击步枪.xml'
    'data/items/武器_刀_长刀.xml'
)
$before=@{}
foreach($relative in $dataPaths) {
    $before[$relative]=(Get-FileHash -LiteralPath (Join-Path $projectRoot $relative) -Algorithm SHA256).Hash
    Write-Output ('CHARACTER_CF6_INPUT '+(@{path=$relative;sha256=$before[$relative]} | ConvertTo-Json -Compress))
}
$actor=(Get-Content -LiteralPath (Join-Path $projectRoot $dataPaths[0]) -Raw -Encoding UTF8 | ConvertFrom-Json).actor
if($actor.name -ne 'Andy' -or $actor.level -ne 60 -or @($actor.equipment).Count -ne 8) {throw 'Unexpected CF6 actor source shape'}
$docs=@($dataPaths[3..6] | ForEach-Object {[xml](Get-Content -LiteralPath (Join-Path $projectRoot $_) -Raw -Encoding UTF8)})
foreach($row in $actor.equipment) {
    $matches=@($docs | ForEach-Object {$_.SelectNodes('//item') | Where-Object {[string]$_.name -ceq [string]$row.name}})
    if($row.enhancement -ne 11 -or $matches.Count -ne 1) {throw ('Missing/ambiguous actual +11 item: '+$row.name)}
}
$sourcePaths=@(
    'scripts/类定义/org/flashNight/arki/item/CharacterBuildCf6LoadoutTest.as'
    'scripts/类定义/org/flashNight/arki/item/CharacterBuildCf6LoadoutData.as'
    'scripts/test-runners/character-build-cf6-loadout/TestLoader.as.template'
)
foreach($relative in $sourcePaths) {
    $bytes=[IO.File]::ReadAllBytes((Join-Path $projectRoot $relative))
    if($bytes.Length -lt 3 -or [BitConverter]::ToString($bytes,0,3) -ne 'EF-BB-BF') {throw ('Missing AS2 BOM: '+$relative)}
}
if($ValidateOnly) {Write-Output 'CHARACTER_CF6_STATIC_OK actorSlots=8 enhancement=11 sameSourceSlot=8';return}
$focusedRun=@{
    DomainId='character-build-cf6-loadout'
    TemplateRelativePath='scripts/test-runners/character-build-cf6-loadout/TestLoader.as.template'
    SuiteRelativePaths=@('scripts/类定义/org/flashNight/arki/item/CharacterBuildCf6LoadoutTest.as')
    SuiteFqns=@('org.flashNight.arki.item.CharacterBuildCf6LoadoutTest')
    AdditionalAsRelativePaths=@(
        'scripts/类定义/org/flashNight/arki/item/CharacterBuildCf6LoadoutData.as'
        'scripts/类定义/org/flashNight/arki/item/CharacterBuildService.as'
        'scripts/类定义/org/flashNight/arki/item/CharacterBuildServiceTest.as'
        'scripts/类定义/org/flashNight/arki/unit/PlayerStatRefreshCoordinator.as'
        'scripts/类定义/org/flashNight/arki/unit/PlayerStatProjectionTest.as'
        'scripts/类定义/org/flashNight/arki/unit/UnitComponent/Initializer/StaticInitializer.as'
        'scripts/类定义/org/flashNight/arki/unit/UnitComponent/Initializer/DressupInitializer.as'
        'scripts/类定义/org/flashNight/arki/item/ItemUtil.as'
        'scripts/类定义/org/flashNight/arki/item/BaseItem.as'
        'scripts/类定义/org/flashNight/arki/item/EquipmentUtil.as'
        'scripts/类定义/org/flashNight/arki/item/equipment/EquipmentCalculator.as'
        'scripts/类定义/org/flashNight/arki/hud/PlayerHudService.as'
        'scripts/类定义/org/flashNight/gesh/xml/LoadXml/EquipmentConfigLoader.as'
        'scripts/逻辑/单位函数/单位函数_fs_aka_玩家模板迁移.as'
        'scripts/逻辑/单位函数/单位函数_fs_装备生命周期配置.as'
        'scripts/逻辑/装备函数/镜之虎彻.as'
        'scripts/逻辑/装备函数/装备光源.as'
    )
    ExpectedTracePatterns=@(
        '(?m)^CharacterBuildCf6LoadoutTest Tests Passed: 81\r?$'
        '(?m)^CharacterBuildCf6LoadoutTest Tests Failed: 0\r?$'
        '(?m)^CHARACTER_CF6_DATA actor=Andy level=60 slots=8 enhancement=11 items=[1-9][0-9]*\r?$'
        '(?m)^CHARACTER_CF6_LOADOUT .*"label":"finalize","caseName":"loopback"'
        '(?m)^CHARACTER_CF6_LOADOUT .*"label":"finalize","caseName":"distinct"'
        '(?m)^CHARACTER_CF6_LOADOUT .*"label":"unchanged_finalize","caseName":"unchanged"'
        '(?m)^CHARACTER_CF6_LOADOUT .*"label":"finalize","caseName":"loopback_subweapon"'
    )
    SuccessSummary='Actual CF6 +11 loadout and production calculator/lifecycle with two swaps through backpack slot 8'
    TimeoutSeconds=$TimeoutSeconds
    SkipCompile=$SkipCompile
}
try { & (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @focusedRun }
finally {
    foreach($relative in $dataPaths) {
        $after=(Get-FileHash -LiteralPath (Join-Path $projectRoot $relative) -Algorithm SHA256).Hash
        if($after -cne $before[$relative]) {throw ('CF6 source data changed during test: '+$relative)}
    }
}
