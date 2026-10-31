[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=1200,[switch]$SkipCompile)
$ErrorActionPreference='Stop'
$focusedRun=@{
    DomainId='scene-revive'
    TemplateRelativePath='scripts/test-runners/scene-revive/TestLoader.as.template'
    SuiteRelativePaths=@('scripts/类定义/org/flashNight/arki/scene/StageRunSessionTest.as')
    SuiteFqns=@('org.flashNight.arki.scene.StageRunSessionTest')
    AdditionalAsRelativePaths=@(
        'scripts/类定义/org/flashNight/arki/scene/StageRunSession.as'
        'scripts/类定义/org/flashNight/arki/unit/Action/Huofeng/HuofengRunState.as'
    )
    ExpectedTracePatterns=@(
        '(?m)^StageRunSessionTest Tests Passed: 920\r?$'
        '(?m)^StageRunSessionTest Tests Failed: 0\r?$'
        '(?m)^SceneReviveTest Tests Passed: 61\r?$'
        '(?m)^SceneReviveTest Tests Failed: 0\r?$'
        '(?m)^\[HuofengContractTest\] [1-9][0-9]* passed, 0 failed\r?$'
    )
    SuccessSummary='Stage authority and ordinary-map paid revival, HUD projection, map identity and Huofeng eligibility'
    TimeoutSeconds=$TimeoutSeconds
    SkipCompile=$SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @focusedRun
