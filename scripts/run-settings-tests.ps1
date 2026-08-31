[CmdletBinding()]
param(
    [ValidateRange(1, 3600)]
    [int]$TimeoutSeconds = 240,
    [switch]$SkipCompile
)

$ErrorActionPreference = 'Stop'
$commonRunner = Join-Path $PSScriptRoot 'test-runners\run-focused-testloader.ps1'
$focusedRun = @{
    DomainId = 'settings'
    TemplateRelativePath = 'scripts\test-runners\settings\TestLoader.as.template'
    SuiteRelativePaths = @(
        'scripts\类定义\org\flashNight\arki\ui\GameSettingsPanelServiceTest.as'
    )
    SuiteFqns = @(
        'org.flashNight.arki.ui.GameSettingsPanelServiceTest'
    )
    ExpectedTracePatterns = @(
        '(?m)^GameSettingsPanelServiceTest Tests Passed: 47\r?$'
        '(?m)^GameSettingsPanelServiceTest Tests Failed: 0\r?$'
    )
    SuccessSummary = '47/47 assertions'
    TimeoutSeconds = $TimeoutSeconds
    SkipCompile = $SkipCompile
}
& $commonRunner @focusedRun
