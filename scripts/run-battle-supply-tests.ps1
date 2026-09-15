[CmdletBinding()]
param([ValidateRange(1, 3600)][int]$TimeoutSeconds = 240, [switch]$SkipCompile)
$focusedRun = @{
    DomainId = 'battle-supply'
    TemplateRelativePath = 'scripts\test-runners\battle-supply\TestLoader.as.template'
    SuiteRelativePaths = @('scripts\类定义\org\flashNight\arki\unit\Action\PickUp\PickupEffectServiceTest.as', 'scripts\类定义\org\flashNight\arki\unit\Action\Shoot\AmmoSupplyServiceTest.as', 'scripts\类定义\org\flashNight\arki\item\drug\DrugProhibitionTest.as')
    SuiteFqns = @('org.flashNight.arki.unit.Action.PickUp.PickupEffectServiceTest', 'org.flashNight.arki.unit.Action.Shoot.AmmoSupplyServiceTest', 'org.flashNight.arki.item.drug.DrugProhibitionTest')
    ExpectedTracePatterns = @('(?m)^PickupEffectServiceTest Tests Passed: 59\r?$', '(?m)^PickupEffectServiceTest Tests Failed: 0\r?$', '(?m)^AmmoSupplyServiceTest Tests Passed: 50\r?$', '(?m)^AmmoSupplyServiceTest Tests Failed: 0\r?$', '(?m)^DrugProhibitionTest Tests Passed: 23\r?$', '(?m)^DrugProhibitionTest Tests Failed: 0\r?$')
    SuccessSummary = '战场即时补给回归132/132：领取四态、弹药补满与关卡禁药统一拦截'
    TimeoutSeconds = $TimeoutSeconds
    SkipCompile = $SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners\run-focused-testloader.ps1') @focusedRun
