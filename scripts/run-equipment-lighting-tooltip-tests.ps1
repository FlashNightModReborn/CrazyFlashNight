[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=300,[switch]$SkipCompile)
$focusedRun=@{
    DomainId='equipment-lighting-tooltip'
    TemplateRelativePath='scripts/test-runners/equipment-lighting-tooltip/TestLoader.as.template'
    SuiteRelativePaths=@('scripts/类定义/org/flashNight/gesh/tooltip/test/EquipmentLightingTooltipTest.as','scripts/类定义/org/flashNight/gesh/tooltip/test/BuilderContractTest.as','scripts/类定义/org/flashNight/gesh/tooltip/test/NativeTooltipDocumentTest.as','scripts/类定义/org/flashNight/gesh/tooltip/test/UpgradePathBuilderTest.as')
    SuiteFqns=@('org.flashNight.gesh.tooltip.test.EquipmentLightingTooltipTest','org.flashNight.gesh.tooltip.test.BuilderContractTest','org.flashNight.gesh.tooltip.test.NativeTooltipDocumentTest','org.flashNight.gesh.tooltip.test.UpgradePathBuilderTest')
    AdditionalAsRelativePaths=@('scripts/类定义/org/flashNight/gesh/tooltip/builder/EquipmentLightingInfoBuilder.as','scripts/类定义/org/flashNight/gesh/tooltip/TooltipComposer.as','scripts/类定义/org/flashNight/gesh/tooltip/TooltipTextBuilder.as','scripts/类定义/org/flashNight/gesh/tooltip/builder/ModStatBuilder.as','scripts/类定义/org/flashNight/gesh/tooltip/builder/drug/DrugTooltipComposer.as','scripts/类定义/org/flashNight/gesh/tooltip/builder/UpgradePathBuilder.as','scripts/类定义/org/flashNight/gesh/tooltip/NativeTooltipDocument.as','scripts/类定义/org/flashNight/arki/item/InventoryPanelService.as')
    ExpectedTracePatterns=@('(?m)^EquipmentLightingTooltipTest Tests Passed: 29\r?$','(?m)^EquipmentLightingTooltipTest Tests Failed: 0\r?$','(?m)^--- BuilderContractTest: [1-9]\d*/\d+ passed, 0 failed ---\r?$','(?m)^--- NativeTooltipDocumentTest: [1-9]\d*/\d+ passed, 0 failed ---\r?$','(?m)^--- UpgradePathBuilderTest: [1-9]\d*/\d+ passed, 0 failed ---\r?$')
    SuccessSummary='照明注释：合成后配置、内置/插件、状态条件、去重与共享原生文档；Builder 契约含插条/弹夹取数与 nativeOpt 省略开关'
    TimeoutSeconds=$TimeoutSeconds
    SkipCompile=$SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @focusedRun
