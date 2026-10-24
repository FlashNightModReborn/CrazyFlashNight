[CmdletBinding()]
param([ValidateRange(1, 3600)][int]$TimeoutSeconds = 240, [switch]$SkipCompile)
$ErrorActionPreference = 'Stop'
chcp.com 65001 | Out-Null

$projectRoot = Split-Path -Parent $PSScriptRoot
$storyPath = Join-Path $projectRoot 'scripts/类定义/org/flashNight/arki/scene/Cf6StoryService.as'
$storySource = Get-Content -LiteralPath $storyPath -Raw -Encoding UTF8
$resolveBody = [regex]::Match($storySource,
    '(?ms)private static function resolvePrepared\(state:Object\):Void \{(.*?)(?=private static function sequenceContinuation)').Value
$finishBody = [regex]::Match($storySource,
    '(?ms)private static function finishSequence\((.*?)(?=^\})').Value
if ($resolveBody -notmatch 'state\.prepared\s*=\s*\[\];' -or
        $resolveBody -match 'state\.prepared\s*=\s*null;' -or
        $finishBody -notmatch 'state\.prepared\s*=\s*null;') {
    throw 'CF6 story preparation must drain into a reusable empty queue and retain terminal cleanup.'
}

$focusedRun = @{
    DomainId = 'cf6-story'
    TemplateRelativePath = 'scripts/test-runners/cf6-story/TestLoader.as.template'
    SuiteRelativePaths = @(
        'scripts/类定义/org/flashNight/arki/scene/BookComicServiceTest.as'
        'scripts/类定义/org/flashNight/arki/scene/Cf6StoryServiceTest.as'
        'scripts/类定义/org/flashNight/arki/scene/Cf6BookRunStoryTest.as'
    )
    SuiteFqns = @(
        'org.flashNight.arki.scene.BookComicServiceTest'
        'org.flashNight.arki.scene.Cf6StoryServiceTest'
        'org.flashNight.arki.scene.Cf6BookRunStoryTest'
    )
    AdditionalAsRelativePaths = @(
        'scripts/类定义/org/flashNight/arki/scene/BookComicService.as'
        'scripts/类定义/org/flashNight/arki/scene/Cf6StoryService.as'
        'scripts/类定义/org/flashNight/arki/scene/BookRunService.as'
        'scripts/类定义/org/flashNight/arki/scene/BookRunRules.as'
        'scripts/类定义/org/flashNight/arki/scene/BookDefinition.as'
        'scripts/类定义/org/flashNight/arki/scene/BookRunClock.as'
        'scripts/类定义/org/flashNight/arki/scene/Cf6MapMechanism.as'
        'scripts/类定义/org/flashNight/arki/scene/Cf6BossEncounter.as'
        'scripts/类定义/org/flashNight/arki/scene/LeeTrialDefinition.as'
        'scripts/类定义/org/flashNight/arki/scene/LeeTrialTelemetry.as'
        'scripts/类定义/org/flashNight/arki/scene/StageReturnFlow.as'
        'scripts/类定义/org/flashNight/arki/audio/AudioBridge.as'
        'scripts/类定义/org/flashNight/arki/ui/SceneTransitionService.as'
        'scripts/类定义/org/flashNight/arki/camera/HorizontalScroller.as'
        'scripts/类定义/org/flashNight/arki/interaction/NativeInteractionContext.as'
        'scripts/类定义/org/flashNight/arki/pause/PauseManager.as'
        'scripts/类定义/org/flashNight/gesh/object/PersistedSnapshot.as'
        'scripts/类定义/org/flashNight/neur/Event/EventBus.as'
        'scripts/类定义/org/flashNight/neur/Server/SaveManager.as'
    )
    ExpectedTracePatterns = @(
        '(?m)^BookComicServiceTest Tests Passed: 45\r?$'
        '(?m)^BookComicServiceTest Tests Failed: 0\r?$'
        '(?m)^Cf6StoryServiceTest Tests Passed: 108\r?$'
        '(?m)^Cf6StoryServiceTest Tests Failed: 0\r?$'
        '(?m)^Cf6BookRunStoryTest Tests Passed: 51\r?$'
        '(?m)^Cf6BookRunStoryTest Tests Failed: 0\r?$'
    )
    SuccessSummary = '204/204 assertions; separate S4-A07/S5-A08/S6-A18 chapter gates, generic sequence preparation and unchanged final outcome lifecycle'
    TimeoutSeconds = $TimeoutSeconds
    SkipCompile = $SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @focusedRun
