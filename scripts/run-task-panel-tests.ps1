[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds = 240, [switch]$SkipCompile)
$ErrorActionPreference = 'Stop'
chcp.com 65001 | Out-Null
$taskFocusedRun = @{
    DomainId = 'task-panel'
    TemplateRelativePath = 'scripts/test-runners/task-panel/TestLoader.as.template'
    SuiteRelativePaths = @('scripts/类定义/org/flashNight/arki/task/TaskPanelServiceTest.as')
    SuiteFqns = @('org.flashNight.arki.task.TaskPanelServiceTest')
    AdditionalAsRelativePaths = @(
        'scripts/类定义/org/flashNight/arki/task/TaskPanelService.as'
        'scripts/类定义/org/flashNight/arki/task/TaskUtil.as'
        'scripts/类定义/org/flashNight/arki/item/ItemUtil.as'
        'scripts/类定义/org/flashNight/arki/map/MapDomainBridge.as'
        'scripts/类定义/org/flashNight/arki/map/MapPanelService.as'
        'scripts/类定义/LiteJSON.as'
        'scripts/类定义/JSON.as'
    )
    ExpectedTracePatterns = @(
        '(?m)^TaskPanelServiceTest Tests Passed: 15\r?$'
        '(?m)^TaskPanelServiceTest Tests Failed: 0\r?$'
    )
    SuccessSummary = 'TaskPanelServiceTest 15/15'
    TimeoutSeconds = $TimeoutSeconds
    SkipCompile = $SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @taskFocusedRun
