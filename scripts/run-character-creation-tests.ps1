[CmdletBinding()]
param(
    [ValidateRange(1, 3600)]
    [int]$TimeoutSeconds = 240,
    [switch]$SkipCompile
)

$ErrorActionPreference = 'Stop'
$commonRunner = Join-Path $PSScriptRoot 'test-runners\run-focused-testloader.ps1'
$focusedRun = @{
    DomainId = 'character-creation'
    TemplateRelativePath = 'scripts\test-runners\character-creation\TestLoader.as.template'
    SuiteRelativePaths = @(
        'scripts\类定义\org\flashNight\neur\Server\test\CharacterCreationServiceTest.as'
    )
    SuiteFqns = @(
        'org.flashNight.neur.Server.test.CharacterCreationServiceTest'
    )
    ExpectedTracePatterns = @(
        '(?m)^CharacterCreationServiceTest Tests Passed: 48\r?$'
        '(?m)^CharacterCreationServiceTest Tests Failed: 0\r?$'
    )
    SuccessSummary = '48/48 assertions'
    TimeoutSeconds = $TimeoutSeconds
    SkipCompile = $SkipCompile
}
& $commonRunner @focusedRun
