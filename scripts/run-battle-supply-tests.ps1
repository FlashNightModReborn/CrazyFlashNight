[CmdletBinding()]
param([ValidateRange(1, 3600)][int]$TimeoutSeconds = 240, [switch]$SkipCompile)
$focusedRun = @{
    DomainId = 'battle-supply'
    TemplateRelativePath = 'scripts\test-runners\battle-supply\TestLoader.as.template'
    SuiteRelativePaths = @('scripts\类定义\org\flashNight\arki\unit\Action\PickUp\PickupEffectServiceTest.as')
    SuiteFqns = @('org.flashNight.arki.unit.Action.PickUp.PickupEffectServiceTest')
    ExpectedTracePatterns = @('(?m)^PickupEffectServiceTest Tests Passed: 51\r?$', '(?m)^PickupEffectServiceTest Tests Failed: 0\r?$')
    SuccessSummary = '战场即时补给领取回归51/51：白名单前置拒绝、收益四态、同步占用、炼金中性化、Buff 刷新不叠与缓释独立槽'
    TimeoutSeconds = $TimeoutSeconds
    SkipCompile = $SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners\run-focused-testloader.ps1') @focusedRun
