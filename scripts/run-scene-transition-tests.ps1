param([int]$TimeoutSeconds=240,[switch]$SkipCompile)
$ErrorActionPreference='Stop'
$focusedRun=@{
    DomainId='scene-transition'
    TemplateRelativePath='scripts/test-runners/scene-transition/TestLoader.as.template'
    SuiteRelativePaths=@('scripts/类定义/org/flashNight/arki/ui/SceneTransitionServiceTest.as')
    SuiteFqns=@('org.flashNight.arki.ui.SceneTransitionServiceTest')
    AdditionalAsRelativePaths=@('scripts/类定义/org/flashNight/arki/ui/SceneTransitionService.as')
    ExpectedTracePatterns=@('(?m)^SceneTransitionServiceTest Tests Passed: 48\r?$','(?m)^SceneTransitionServiceTest Tests Failed: 0\r?$')
    SuccessSummary='U12 scene-transition AS2 guards passed (48 checks).'
    TimeoutSeconds=$TimeoutSeconds
    SkipCompile=$SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @focusedRun
