[CmdletBinding()]
param([ValidateRange(1, 3600)][int]$TimeoutSeconds = 180, [switch]$SkipCompile)

$focusedRun = @{
    DomainId = 'weapon-animation'
    TemplateRelativePath = 'scripts\test-runners\weapon-animation\TestLoader.as.template'
    SuiteRelativePaths = @(
        'scripts\类定义\org\flashNight\arki\unit\UnitComponent\Dressup\EquipmentUtil\ShotTimelineTest.as'
        'scripts\类定义\org\flashNight\arki\unit\UnitComponent\Dressup\EquipmentUtil\Qjz171LiveAnimationTest.as'
    )
    SuiteFqns = @(
        'org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.ShotTimelineTest'
        'org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.Qjz171LiveAnimationTest'
    )
    AdditionalAsRelativePaths = @('scripts\逻辑\装备函数\枪械射击动画.as', 'scripts\逻辑\单位函数\单位函数_fs_装备生命周期配置.as')
    ExpectedTracePatterns = @(
        '(?m)^ShotTimelineTest Tests Passed: 37\r?$'
        '(?m)^ShotTimelineTest Tests Failed: 0\r?$'
        '(?m)^Qjz171LiveAnimationTest Tests Passed: 15\r?$'
        '(?m)^Qjz171LiveAnimationTest Tests Failed: 0\r?$'
    )
    SuccessSummary = 'ShotTimelineTest 37/37 + Qjz171LiveAnimationTest 15/15'
    TimeoutSeconds = $TimeoutSeconds
    SkipCompile = $SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners\run-focused-testloader.ps1') @focusedRun
