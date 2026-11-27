[CmdletBinding()]
param(
    [ValidateRange(1, 3600)]
    [int]$TimeoutSeconds = 240,
    [switch]$SkipCompile
)

$ErrorActionPreference = 'Stop'
$focusedRun = @{
    DomainId = 'pet-live-combat'
    TemplateRelativePath = 'scripts\test-runners\pet-live-combat\TestLoader.as.template'
    SuiteRelativePaths = @(
        'scripts\类定义\org\flashNight\arki\merc\PetLiveCombatProjectionTest.as'
    )
    SuiteFqns = @(
        'org.flashNight.arki.merc.PetLiveCombatProjectionTest'
    )
    AdditionalAsRelativePaths = @(
        'scripts\类定义\org\flashNight\arki\merc\PetPanelService.as'
        'scripts\类定义\org\flashNight\arki\unit\PlayerInfoProvider.as'
        'scripts\引擎\引擎_lsy_战宠系统.as'
    )
    ExpectedTracePatterns = @(
        '(?m)^PetLiveCombatProjectionTest Tests Passed: 25\r?$'
        '(?m)^PetLiveCombatProjectionTest Tests Failed: 0\r?$'
    )
    SuccessSummary = 'PetLiveCombatProjectionTest 25/25 passed'
    TimeoutSeconds = $TimeoutSeconds
    SkipCompile = $SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners\run-focused-testloader.ps1') @focusedRun
