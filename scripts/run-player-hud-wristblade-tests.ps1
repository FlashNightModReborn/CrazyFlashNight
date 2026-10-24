[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=600,[switch]$SkipCompile)
$ErrorActionPreference='Stop'
$focusedRun=@{
    DomainId='player-hud-wristblade'
    TemplateRelativePath='scripts\test-runners\player-hud-wristblade\TestLoader.as.template'
    SuiteRelativePaths=@('scripts\类定义\org\flashNight\arki\hud\PlayerHudWristbladeTest.as')
    SuiteFqns=@('org.flashNight.arki.hud.PlayerHudWristbladeTest')
    AdditionalAsRelativePaths=@(
        'scripts\逻辑\装备函数\剑圣手甲.as'
        'scripts\类定义\org\flashNight\arki\hud\PlayerHudBuffProjection.as'
        'scripts\类定义\org\flashNight\arki\component\Buff\BuffManager.as'
        'scripts\类定义\org\flashNight\arki\component\Buff\Component\EventListenerComponent.as'
    )
    ExpectedTracePatterns=@(
        '(?m)^PlayerHudWristbladeTest Tests Passed: [1-9][0-9]*\r?$'
        '(?m)^PlayerHudWristbladeTest Tests Failed: 0\r?$'
    )
    SuccessSummary='Production wristblade registration, activation, injected corrections and expiry'
    TimeoutSeconds=$TimeoutSeconds
    SkipCompile=$SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners\run-focused-testloader.ps1') @focusedRun
