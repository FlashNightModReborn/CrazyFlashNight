param([int]$TimeoutSeconds=240,[switch]$SkipCompile)
$ErrorActionPreference='Stop'
$focusedRun=@{
    DomainId='scene-transition'
    TemplateRelativePath='scripts/test-runners/scene-transition/TestLoader.as.template'
    SuiteRelativePaths=@('scripts/类定义/org/flashNight/arki/ui/SceneTransitionServiceTest.as','scripts/类定义/org/flashNight/arki/stageSelect/StageSelectChallengeEntryTest.as')
    SuiteFqns=@('org.flashNight.arki.ui.SceneTransitionServiceTest','org.flashNight.arki.stageSelect.StageSelectChallengeEntryTest')
    AdditionalAsRelativePaths=@(
        'scripts/类定义/org/flashNight/arki/ui/SceneTransitionService.as'
        'scripts/类定义/org/flashNight/arki/scene/StageReturnFlow.as'
        'scripts/类定义/org/flashNight/arki/scene/SceneTransitionGuard.as'
        'scripts/类定义/org/flashNight/arki/weather/WorldLightingBridge.as'
    )
    ExpectedTracePatterns=@('(?m)^SceneTransitionServiceTest Tests Passed: 119\r?$','(?m)^SceneTransitionServiceTest Tests Failed: 0\r?$','(?m)^StageSelectChallengeEntryTest Tests Passed: 7\r?$','(?m)^StageSelectChallengeEntryTest Tests Failed: 0\r?$')
    SuccessSummary='U12 scene-transition AS2 guards passed (119 checks + 7 challenge refusal checks).'
    TimeoutSeconds=$TimeoutSeconds
    SkipCompile=$SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @focusedRun
