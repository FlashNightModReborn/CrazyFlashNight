[CmdletBinding()]
param(
    [ValidateRange(1, 3600)]
    [int]$TimeoutSeconds = 240,
    [switch]$SkipCompile
)

$ErrorActionPreference = 'Stop'
$commonRunner = Join-Path $PSScriptRoot 'test-runners\run-focused-testloader.ps1'

$focusedRun = @{
    DomainId = 'arena-authority'
    TemplateRelativePath = 'scripts\test-runners\arena-authority\TestLoader.as.template'
    SuiteRelativePaths = @(
        'scripts\类定义\org\flashNight\arki\merc\ArenaPanelAuthorityTest.as'
    )
    SuiteFqns = @(
        'org.flashNight.arki.merc.ArenaPanelAuthorityTest'
    )
    AdditionalAsRelativePaths = @(
        'scripts\类定义\org\flashNight\arki\merc\ArenaPanelService.as'
        'scripts\类定义\org\flashNight\arki\stageSelect\StageSelectPanelService.as'
    )
    ExpectedTracePatterns = @(
        '(?m)^ArenaPanelAuthorityTest Tests Passed: 13\r?$'
        '(?m)^ArenaPanelAuthorityTest Tests Failed: 0\r?$'
    )
    SuccessSummary = 'ArenaPanelAuthorityTest 13/13'
    TimeoutSeconds = $TimeoutSeconds
    SkipCompile = $SkipCompile
}
& $commonRunner @focusedRun
