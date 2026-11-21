[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=300,[switch]$SkipCompile)
$focusedRun=@{
    DomainId='dual-870'
    TemplateRelativePath='scripts/test-runners/dual-870/TestLoader.as.template'
    SuiteRelativePaths=@('scripts/类定义/org/flashNight/arki/unit/UnitComponent/Dressup/EquipmentUtil/Dual870Test.as')
    SuiteFqns=@('org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.Dual870Test')
    AdditionalAsRelativePaths=@('scripts/逻辑/装备函数/双态870.as')
    ExpectedTracePatterns=@('(?m)^Dual870Test Tests Passed: [1-9][0-9]*\r?$','(?m)^Dual870Test Tests Failed: 0\r?$')
    SuccessSummary='Independent Q and equipped F skill, slug velocity and panel, reversible attachment and shared tube'
    TimeoutSeconds=$TimeoutSeconds
    SkipCompile=$SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @focusedRun
