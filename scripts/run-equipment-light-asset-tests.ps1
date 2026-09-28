[CmdletBinding()]
param([ValidateRange(1, 3600)][int]$TimeoutSeconds = 240, [switch]$SkipCompile)
$focusedRun = @{
    DomainId = 'equipment-light-assets'
    TemplateRelativePath = 'scripts/test-runners/equipment-light-assets/TestLoader.as.template'
    SuiteRelativePaths = @('scripts/类定义/org/flashNight/arki/render/EquipmentLightAssetTest.as')
    SuiteFqns = @('org.flashNight.arki.render.EquipmentLightAssetTest')
    AdditionalAsRelativePaths = @('scripts/逻辑/装备函数/装备光源.as', 'scripts/逻辑/单位函数/单位函数_fs_装备生命周期配置.as')
    ExpectedTracePatterns = @(
        '(?m)^EquipmentLightAssetTest Fixtures Completed: 3\r?$',
        '(?m)^EquipmentLightAssetTest Tests Passed: 60\r?$',
        '(?m)^EquipmentLightAssetTest Tests Failed: 0\r?$'
    )
    SuccessSummary = '实际 XML/素材经生产装载器：两把手电枪与激光插件、持枪/换弹/死亡/卸载'
    TimeoutSeconds = $TimeoutSeconds
    SkipCompile = $SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @focusedRun
