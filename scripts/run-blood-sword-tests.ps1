[CmdletBinding()]
param([ValidateRange(1, 3600)][int]$TimeoutSeconds = 240, [switch]$SkipCompile)
$focusedRun = @{
    DomainId = 'blood-sword'
    TemplateRelativePath = 'scripts\test-runners\blood-sword\TestLoader.as.template'
    SuiteRelativePaths = @('scripts\类定义\org\flashNight\arki\unit\UnitComponent\Dressup\EquipmentUtil\BloodSwordLifecycleTest.as')
    SuiteFqns = @('org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.BloodSwordLifecycleTest')
    AdditionalAsRelativePaths = @('scripts\逻辑\装备函数\血色光剑天秤.as', 'scripts\逻辑\单位函数\单位函数_fs_装备生命周期配置.as')
    ExpectedTracePatterns = @('(?m)^BloodSwordLifecycleTest Tests Passed: 56\r?$', '(?m)^BloodSwordLifecycleTest Tests Failed: 0\r?$')
    SuccessSummary = '56/56，真实血剑素材：两路逐帧自损、发射参数、独立光效和卸载'
    TimeoutSeconds = $TimeoutSeconds
    SkipCompile = $SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners\run-focused-testloader.ps1') @focusedRun
