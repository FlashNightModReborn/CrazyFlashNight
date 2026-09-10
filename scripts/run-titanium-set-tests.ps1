[CmdletBinding()]
param([ValidateRange(1, 3600)][int]$TimeoutSeconds = 240, [switch]$SkipCompile)
$focusedRun = @{
    DomainId = 'titanium-set'
    TemplateRelativePath = 'scripts\test-runners\titanium-set\TestLoader.as.template'
    SuiteRelativePaths = @('scripts\类定义\org\flashNight\arki\unit\UnitComponent\Initializer\test\TitaniumSetRuntimeTest.as')
    SuiteFqns = @('org.flashNight.arki.unit.UnitComponent.Initializer.test.TitaniumSetRuntimeTest')
    AdditionalAsRelativePaths = @('scripts\类定义\org\flashNight\arki\unit\UnitComponent\Initializer\StaticInitializer.as', 'scripts\逻辑\装备函数\P90.as', 'scripts\类定义\org\flashNight\arki\unit\UnitComponent\Dressup\EquipmentUtil\P90EnergyGenerator.as', 'scripts\类定义\org\flashNight\arki\unit\Action\Shoot\WeaponFireCore.as', 'scripts\类定义\org\flashNight\arki\unit\Action\Shoot\ReloadManager.as', 'scripts\逻辑\装备函数\钛合金套装.as', 'scripts\类定义\org\flashNight\arki\unit\UnitComponent\Initializer\TitaniumSetRuntime.as', 'scripts\逻辑\单位函数\单位函数_fs_装备生命周期配置.as')
    ExpectedTracePatterns = @('(?m)^TitaniumSetRuntimeTest Tests Passed: 233\r?$', '(?m)^TitaniumSetRuntimeTest Tests Failed: 0\r?$')
    SuccessSummary = '钛合金血浪回归233/233：破盾血剑、战技联弹与增伤、取消归属、复活与171副射'
    TimeoutSeconds = $TimeoutSeconds
    SkipCompile = $SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners\run-focused-testloader.ps1') @focusedRun
