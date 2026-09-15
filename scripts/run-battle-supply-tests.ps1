[CmdletBinding()]
param([ValidateRange(1, 3600)][int]$TimeoutSeconds = 240, [switch]$SkipCompile)
$focusedRun = @{
    DomainId = 'battle-supply'
    TemplateRelativePath = 'scripts\test-runners\battle-supply\TestLoader.as.template'
    SuiteRelativePaths = @('scripts\类定义\org\flashNight\arki\unit\Action\PickUp\PickupEffectServiceTest.as', 'scripts\类定义\org\flashNight\arki\unit\Action\Shoot\AmmoSupplyServiceTest.as')
    SuiteFqns = @('org.flashNight.arki.unit.Action.PickUp.PickupEffectServiceTest', 'org.flashNight.arki.unit.Action.Shoot.AmmoSupplyServiceTest')
    ExpectedTracePatterns = @('(?m)^PickupEffectServiceTest Tests Passed: 59\r?$', '(?m)^PickupEffectServiceTest Tests Failed: 0\r?$', '(?m)^AmmoSupplyServiceTest Tests Passed: 50\r?$', '(?m)^AmmoSupplyServiceTest Tests Failed: 0\r?$')
    SuccessSummary = '战场即时补给回归109/109：领取四态与弹药补满（scope 四值、alias 去重、tube/镜像、换弹拒领、副武器免费入口）'
    TimeoutSeconds = $TimeoutSeconds
    SkipCompile = $SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners\run-focused-testloader.ps1') @focusedRun
