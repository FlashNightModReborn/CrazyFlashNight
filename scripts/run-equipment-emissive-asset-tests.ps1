[CmdletBinding()]
param([ValidateRange(1, 3600)][int]$TimeoutSeconds = 240, [switch]$SkipCompile)
$focusedRun = @{
    DomainId = 'equipment-emissive-assets'
    TemplateRelativePath = 'scripts/test-runners/equipment-emissive-assets/TestLoader.as.template'
    SuiteRelativePaths = @('scripts/类定义/org/flashNight/arki/render/EquipmentEmissiveAssetTest.as')
    SuiteFqns = @('org.flashNight.arki.render.EquipmentEmissiveAssetTest')
    AdditionalAsRelativePaths = @('scripts/逻辑/装备函数/装备光源.as', 'scripts/逻辑/单位函数/单位函数_fs_装备生命周期配置.as')
    ExpectedTracePatterns = @(
        '(?m)^EquipmentEmissiveAssetTest Fixtures Completed: 11\r?$',
        '(?m)^EquipmentEmissiveAssetTest Tests Passed: 185\r?$',
        '(?m)^EquipmentEmissiveAssetTest Tests Failed: 0\r?$'
    )
    SuccessSummary = '实际自发光 XML/SWF、生产装载器与六类真实状态发布'
    TimeoutSeconds = $TimeoutSeconds
    SkipCompile = $SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @focusedRun
