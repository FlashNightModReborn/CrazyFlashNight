[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=300,[switch]$SkipCompile)
$run=@{
 DomainId='equipment-light-defense'
 TemplateRelativePath='scripts/test-runners/equipment-light-defense/TestLoader.as.template'
 SuiteRelativePaths=@('scripts/类定义/org/flashNight/arki/render/EquipmentLightDefenseTest.as')
 SuiteFqns=@('org.flashNight.arki.render.EquipmentLightDefenseTest')
 AdditionalAsRelativePaths=@('scripts/类定义/org/flashNight/arki/unit/UnitComponent/Dressup/EquipmentUtil/EquipmentLightDefense.as')
 ExpectedTracePatterns=@('(?m)^EquipmentLightDefenseTest Tests Passed: 23\r?$','(?m)^EquipmentLightDefenseTest Tests Failed: 0\r?$')
 SuccessSummary='战术手电20/25：真实BuffManager、双持、基值恢复与同路径重建隔离'
 TimeoutSeconds=$TimeoutSeconds
 SkipCompile=$SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @run
