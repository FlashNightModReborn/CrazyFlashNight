[CmdletBinding()]
param(
    [ValidateRange(1, 3600)][int]$TimeoutSeconds = 240,
    [switch]$SkipCompile
)

$ErrorActionPreference = 'Stop'
$focusedRun = @{
    DomainId = 'arena-worker-protocol'
    TemplateRelativePath = 'scripts\test-runners\arena-worker-protocol\TestLoader.as.template'
    SuiteRelativePaths = @('scripts\类定义\org\flashNight\arki\merc\ArenaWorkerProtocolTest.as')
    SuiteFqns = @('org.flashNight.arki.merc.ArenaWorkerProtocolTest')
    AdditionalAsRelativePaths = @(
        'scripts\类定义\org\flashNight\arki\merc\ArenaCalibrationService.as'
        'scripts\类定义\org\flashNight\neur\Server\ServerManager.as'
        'scripts\类定义\org\flashNight\arki\merc\ArenaController.as'
        'scripts\类定义\org\flashNight\arki\scene\StageRunSession.as'
        'scripts\类定义\org\flashNight\arki\ui\SceneTransitionService.as'
        'scripts\类定义\org\flashNight\arki\weather\WorldLightingBridge.as'
    )
    ExpectedTracePatterns = @(
        '(?m)^ArenaWorkerProtocolTest Tests Passed: 52\r?$'
        '(?m)^ArenaWorkerProtocolTest Tests Failed: 0\r?$'
    )
    SuccessSummary = 'Arena Worker 实际入口、冻结身份、迟到回包、派生单位登记与专用揭幕准入 52/52'
    TimeoutSeconds = $TimeoutSeconds
    SkipCompile = $SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners\run-focused-testloader.ps1') @focusedRun
