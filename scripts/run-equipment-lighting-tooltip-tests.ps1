[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=300,[switch]$SkipCompile)
$focusedRun=@{
    DomainId='equipment-lighting-tooltip'
    TemplateRelativePath='scripts/test-runners/equipment-lighting-tooltip/TestLoader.as.template'
    SuiteRelativePaths=@('scripts/类定义/org/flashNight/gesh/tooltip/test/EquipmentLightingTooltipTest.as','scripts/类定义/org/flashNight/gesh/tooltip/test/NativeTooltipDocumentTest.as')
    SuiteFqns=@('org.flashNight.gesh.tooltip.test.EquipmentLightingTooltipTest','org.flashNight.gesh.tooltip.test.NativeTooltipDocumentTest')
    AdditionalAsRelativePaths=@('scripts/类定义/org/flashNight/gesh/tooltip/builder/EquipmentLightingInfoBuilder.as','scripts/类定义/org/flashNight/gesh/tooltip/TooltipComposer.as','scripts/类定义/org/flashNight/gesh/tooltip/builder/ModStatBuilder.as')
    ExpectedTracePatterns=@('(?m)^EquipmentLightingTooltipTest Tests Passed: 27\r?$','(?m)^EquipmentLightingTooltipTest Tests Failed: 0\r?$','(?m)^--- NativeTooltipDocumentTest: [1-9]\d*/\d+ passed, 0 failed ---\r?$')
    SuccessSummary='照明注释：合成后配置、内置/插件、状态条件、去重与共享原生文档'
    TimeoutSeconds=$TimeoutSeconds
    SkipCompile=$SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @focusedRun
