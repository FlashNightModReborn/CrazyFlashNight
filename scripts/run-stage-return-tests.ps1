[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds = 240, [switch]$SkipCompile)
$ErrorActionPreference = 'Stop'
chcp.com 65001 | Out-Null
$questReturnRun = @{
    DomainId = 'stage-return'
    TemplateRelativePath = 'scripts/test-runners/stage-return/TestLoader.as.template'
    SuiteRelativePaths = @('scripts/类定义/org/flashNight/arki/scene/StageReturnFlowTest.as')
    SuiteFqns = @('org.flashNight.arki.scene.StageReturnFlowTest')
    AdditionalAsRelativePaths = @('scripts/类定义/org/flashNight/arki/scene/SceneTransitionGuard.as', 'scripts/类定义/org/flashNight/arki/scene/StageReturnFlow.as', 'scripts/类定义/org/flashNight/arki/scene/StageReturnSelection.as', 'scripts/类定义/org/flashNight/arki/scene/StageReturnOptions.as', 'scripts/类定义/org/flashNight/arki/task/TaskDestinationOptions.as', 'scripts/类定义/org/flashNight/arki/task/TaskDeliverySelection.as')
    ExpectedTracePatterns = @('(?m)^StageReturnFlowTest Tests Passed: 119\r?$', '(?m)^StageReturnFlowTest Tests Failed: 0\r?$')
    SuccessSummary = 'StageReturnFlowTest 119/119'
    TimeoutSeconds = $TimeoutSeconds
    SkipCompile = $SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @questReturnRun
