param([int]$TimeoutSeconds=900,[switch]$SkipCompile,[switch]$OwnedReadOnlyHost,[switch]$AutoStopReadOnlyPlayer)
$ErrorActionPreference='Stop'
$focusedRun=@{
    DomainId='stage-intro'
    TemplateRelativePath='scripts/test-runners/stage-intro/TestLoader.as.template'
    SuiteRelativePaths=@('scripts/类定义/org/flashNight/arki/scene/StageIntroServiceTest.as','scripts/类定义/org/flashNight/arki/ui/SceneTransitionServiceTest.as','scripts/类定义/org/flashNight/arki/scene/BookComicServiceTest.as','scripts/类定义/org/flashNight/arki/scene/BookComicSequenceTest.as','scripts/类定义/org/flashNight/arki/scene/Cf6BookRunStoryTest.as','scripts/类定义/org/flashNight/arki/scene/Cf6TutorialTurretServiceTest.as','scripts/类定义/org/flashNight/arki/scene/BookRunRulesTest.as')
    SuiteFqns=@('org.flashNight.arki.scene.StageIntroServiceTest','org.flashNight.arki.ui.SceneTransitionServiceTest','org.flashNight.arki.scene.BookComicServiceTest','org.flashNight.arki.scene.BookComicSequenceTest','org.flashNight.arki.scene.Cf6BookRunStoryTest','org.flashNight.arki.scene.Cf6TutorialTurretServiceTest','org.flashNight.arki.scene.BookRunRulesTest')
    ExpectedTracePatterns=@('(?m)^StageIntroServiceTest Tests Passed: 113\r?$','(?m)^StageIntroServiceTest Tests Failed: 0\r?$','(?m)^SceneTransitionServiceTest Tests Passed: 119\r?$','(?m)^SceneTransitionServiceTest Tests Failed: 0\r?$','(?m)^BookComicServiceTest Tests Passed: 48\r?$','(?m)^BookComicServiceTest Tests Failed: 0\r?$','(?m)^BookComicSequenceTest Tests Passed: 104\r?$','(?m)^BookComicSequenceTest Tests Failed: 0\r?$','(?m)^Cf6BookRunStoryTest Tests Passed: 51\r?$','(?m)^Cf6BookRunStoryTest Tests Failed: 0\r?$','(?m)^Cf6TutorialTurretServiceTest Tests Passed: 122\r?$','(?m)^Cf6TutorialTurretServiceTest Tests Failed: 0\r?$','(?m)^BookRunRulesTest Tests Passed: 218\r?$','(?m)^BookRunRulesTest Tests Failed: 0\r?$')
    SuccessSummary='Stage intro permission and existing transition/comic contracts passed.'
    TimeoutSeconds=$TimeoutSeconds
    SkipCompile=$SkipCompile
    OwnedReadOnlyHost=$OwnedReadOnlyHost
    AutoStopReadOnlyPlayer=$AutoStopReadOnlyPlayer
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @focusedRun
