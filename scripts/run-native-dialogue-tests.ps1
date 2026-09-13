[CmdletBinding()]
param([int]$TimeoutSeconds = 240, [switch]$SkipCompile)
$ErrorActionPreference = 'Stop'
$focusedRun = @{
    DomainId = 'native-dialogue'
    TemplateRelativePath = 'scripts/test-runners/native-dialogue/TestLoader.as.template'
    SuiteRelativePaths = @('scripts/类定义/org/flashNight/arki/dialogue/NativeDialogueServiceTest.as')
    SuiteFqns = @('org.flashNight.arki.dialogue.NativeDialogueServiceTest')
    AdditionalAsRelativePaths = @(
        'scripts/类定义/org/flashNight/arki/dialogue/NativeDialogueService.as'
        'scripts/类定义/org/flashNight/arki/dialogue/NativeDialogueAppearance.as'
        'scripts/类定义/org/flashNight/arki/pause/PauseManager.as'
        'scripts/类定义/org/flashNight/boot/BootSequencer.as'
    )
    ExpectedTracePatterns = @(
        '(?m)^NativeDialogueServiceTest Tests Passed: [1-9]\d*\r?$'
        '(?m)^NativeDialogueServiceTest Tests Failed: 0\r?$'
    )
    SuccessSummary = '原生对白生命周期与暂停责任测试全部通过'
    TimeoutSeconds = $TimeoutSeconds
    SkipCompile = $SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @focusedRun
