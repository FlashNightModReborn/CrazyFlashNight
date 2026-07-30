[CmdletBinding()]
param(
    [ValidateRange(1, 3600)]
    [int]$TimeoutSeconds = 240,
    [switch]$SkipCompile
)

$ErrorActionPreference = 'Stop'
$commonRunner = Join-Path $PSScriptRoot 'test-runners\run-focused-testloader.ps1'
$focusedRun = @{
    DomainId = 'hairdresser'
    TemplateRelativePath = 'scripts\test-runners\hairdresser\TestLoader.as.template'
    SuiteRelativePaths = @(
        'scripts\类定义\org\flashNight\arki\ui\HairdresserPanelServiceTest.as'
    )
    SuiteFqns = @(
        'org.flashNight.arki.ui.HairdresserPanelServiceTest'
    )
    ExpectedTracePatterns = @(
        '(?m)^HairdresserPanelServiceTest Tests Passed: 28\r?$'
        '(?m)^HairdresserPanelServiceTest Tests Failed: 0\r?$'
    )
    SuccessSummary = '28/28 assertions'
    TimeoutSeconds = $TimeoutSeconds
    SkipCompile = $SkipCompile
}
& $commonRunner @focusedRun
