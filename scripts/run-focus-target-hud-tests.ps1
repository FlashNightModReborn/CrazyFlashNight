[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=600,[switch]$SkipCompile)
$ErrorActionPreference='Stop'
$focusedRun=@{
    DomainId='focus-target-hud'
    TemplateRelativePath='scripts/test-runners/focus-target-hud/TestLoader.as.template'
    SuiteRelativePaths=@('scripts/类定义/org/flashNight/arki/hud/FocusTargetHudTest.as')
    SuiteFqns=@('org.flashNight.arki.hud.FocusTargetHudTest')
    AdditionalAsRelativePaths=@(
        'scripts/类定义/org/flashNight/arki/hud/FocusTargetHudService.as'
        'scripts/类定义/org/flashNight/arki/hud/PlayerHudService.as'
    )
    ExpectedTracePatterns=@(
        '(?m)^FocusTargetHudTest Tests Passed: [1-9][0-9]*\r?$'
        '(?m)^FocusTargetHudTest Tests Failed: 0\r?$'
    )
    SuccessSummary='Target HUD authoritative sampling, exact leases, real MovieClip reuse and opt-in protocol'
    TimeoutSeconds=$TimeoutSeconds
    SkipCompile=$SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @focusedRun
