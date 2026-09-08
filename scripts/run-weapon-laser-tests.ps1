[CmdletBinding()]
param([ValidateRange(1, 3600)][int]$TimeoutSeconds = 240, [switch]$SkipCompile)

$focusedRun = @{
    DomainId = 'weapon-laser'
    TemplateRelativePath = 'scripts\test-runners\weapon-laser\TestLoader.as.template'
    SuiteRelativePaths = @('scripts\类定义\org\flashNight\arki\unit\UnitComponent\Dressup\EquipmentUtil\WeaponLaserSightTest.as')
    SuiteFqns = @('org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.WeaponLaserSightTest')
    AdditionalAsRelativePaths = @(
        'scripts\逻辑\装备函数\枪械激光瞄准.as',
        'scripts\逻辑\装备函数\枪械射击动画.as',
        'scripts\逻辑\装备函数\P90.as',
        'scripts\逻辑\单位函数\单位函数_fs_装备生命周期配置.as'
    )
    ExpectedTracePatterns = @(
        '(?m)^WeaponLaserSightTest Fixtures Completed: 3\r?$',
        '(?m)^WeaponLaserSightTest Tests Passed: 89\r?$',
        '(?m)^WeaponLaserSightTest Tests Failed: 0\r?$'
    )
    SuccessSummary = '89/89，真实手枪、手枪2及长枪素材：激光、弹匣、后坐及卸载'
    TimeoutSeconds = $TimeoutSeconds
    SkipCompile = $SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners\run-focused-testloader.ps1') @focusedRun
