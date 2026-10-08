[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=240,[switch]$SkipCompile)
$focusedRun=@{
    DomainId='sheriff-baton'
    TemplateRelativePath='scripts/test-runners/sheriff-baton/TestLoader.as.template'
    SuiteRelativePaths=@('scripts/类定义/org/flashNight/arki/unit/UnitComponent/Dressup/EquipmentUtil/SheriffBatonTest.as','scripts/类定义/org/flashNight/arki/unit/UnitComponent/Dressup/EquipmentUtil/SheriffArsenalTest.as','scripts/类定义/org/flashNight/arki/render/EquipmentLightDefenseTest.as')
    SuiteFqns=@('org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.SheriffBatonTest','org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.SheriffArsenalTest','org.flashNight.arki.render.EquipmentLightDefenseTest')
    AdditionalAsRelativePaths=@('scripts/逻辑/装备函数/特勤警棍.as','scripts/逻辑/单位函数/单位函数_fs_装备生命周期配置.as')
    ExpectedTracePatterns=@('(?m)^SheriffBatonTest Tests Passed: 47\r?$','(?m)^SheriffBatonTest Tests Failed: 0\r?$','(?m)^SheriffArsenalTest Tests Passed: 44\r?$','(?m)^SheriffArsenalTest Tests Failed: 0\r?$','(?m)^EquipmentLightDefenseTest Tests Passed: 23\r?$','(?m)^EquipmentLightDefenseTest Tests Failed: 0\r?$')
    SuccessSummary='Actual XML, published 15-frame art, Q edges, attack/defense swap and lifecycle cleanup'
    TimeoutSeconds=$TimeoutSeconds
    SkipCompile=$SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @focusedRun
