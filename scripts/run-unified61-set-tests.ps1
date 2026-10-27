[CmdletBinding()]
param([ValidateRange(1, 3600)][int]$TimeoutSeconds = 240, [switch]$SkipCompile)
$focusedRun = @{
    DomainId = 'unified61-set'
    TemplateRelativePath = 'scripts\test-runners\unified61-set\TestLoader.as.template'
    SuiteRelativePaths = @('scripts\类定义\org\flashNight\arki\unit\UnitComponent\Initializer\test\UnifiedType61RuntimeTest.as')
    SuiteFqns = @('org.flashNight.arki.unit.UnitComponent.Initializer.test.UnifiedType61RuntimeTest')
    AdditionalAsRelativePaths = @('scripts\类定义\org\flashNight\arki\unit\UnitComponent\Initializer\UnifiedType61Runtime.as', 'scripts\逻辑\单位函数\单位函数_fs_装备生命周期配置.as', 'scripts\类定义\org\flashNight\arki\unit\Action\Shoot\ReloadManager.as', 'scripts\类定义\org\flashNight\arki\unit\Action\Shoot\WeaponAmmoRuntime.as')
    ExpectedTracePatterns = @('(?m)^UnifiedType61RuntimeTest Tests Passed: 94\r?$', '(?m)^UnifiedType61RuntimeTest Tests Failed: 0\r?$')
    SuccessSummary = '统合61式：五甲门控、缓冲盾与叠盾、星座授权、付费整备、同图换装与生命周期回归'
    TimeoutSeconds = $TimeoutSeconds
    SkipCompile = $SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners\run-focused-testloader.ps1') @focusedRun
