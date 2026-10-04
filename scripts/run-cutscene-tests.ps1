[CmdletBinding()]
param([int]$TimeoutSeconds = 240, [switch]$SkipCompile)
$ErrorActionPreference = 'Stop'
$focusedRun = @{
    DomainId = 'cutscene'
    TemplateRelativePath = 'scripts/test-runners/cutscene/TestLoader.as.template'
    SuiteRelativePaths = @(
        'scripts/类定义/org/flashNight/arki/scene/CutsceneServiceTest.as'
        'scripts/类定义/org/flashNight/arki/scene/CutsceneSkipTest.as'
    )
    SuiteFqns = @('org.flashNight.arki.scene.CutsceneServiceTest', 'org.flashNight.arki.scene.CutsceneSkipTest')
    AdditionalAsRelativePaths = @(
        'scripts/类定义/org/flashNight/arki/scene/CutsceneService.as'
        'scripts/类定义/org/flashNight/arki/pause/PauseManager.as'
        'scripts/类定义/org/flashNight/arki/interaction/NativeInteractionContext.as'
        'scripts/类定义/org/flashNight/arki/dialogue/NativeDialogueService.as'
        'scripts/类定义/org/flashNight/arki/key/KeyManager.as'
        'scripts/类定义/org/flashNight/arki/input/IsolatedInputPolicy.as'
    )
    ExpectedTracePatterns = @(
        '(?m)^CutsceneServiceTest Existing Movies Tested: 16\r?$'
        '(?m)^CutsceneServiceTest Tests Passed: [1-9]\d*\r?$'
        '(?m)^CutsceneServiceTest Tests Failed: 0\r?$'
        '(?m)^CutsceneSkipTest Existing Movies Tested: 16\r?$'
        '(?m)^CutsceneSkipTest Tests Passed: [1-9]\d*\r?$'
        '(?m)^CutsceneSkipTest Tests Failed: 0\r?$'
    )
    SuccessSummary = '过场暂停、交互跳过与现有动画真实收尾测试全部通过'
    TimeoutSeconds = $TimeoutSeconds
    AsyncBehaviorTimeoutSeconds = 60
    SkipCompile = $SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @focusedRun
