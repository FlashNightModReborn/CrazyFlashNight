[CmdletBinding()]
param(
    [ValidateRange(1, 3600)]
    [int]$TimeoutSeconds = 240,
    [switch]$SkipCompile
)

$ErrorActionPreference = 'Stop'
$commonRunner = Join-Path $PSScriptRoot 'test-runners\run-focused-testloader.ps1'
$focusedRun = @{
    DomainId = 'armor-break-zombie'
    TemplateRelativePath = 'scripts\test-runners\armor-break-zombie\TestLoader.as.template'
    SuiteRelativePaths = @(
        'scripts\类定义\org\flashNight\arki\unit\UnitAI\Custom\ArmorBreakZombieControllerTest.as'
    )
    SuiteFqns = @(
        'org.flashNight.arki.unit.UnitAI.Custom.ArmorBreakZombieControllerTest'
    )
    AdditionalAsRelativePaths = @(
        'scripts\类定义\org\flashNight\arki\unit\UnitAI\Custom\ArmorBreakZombieController.as'
    )
    ExpectedTracePatterns = @(
        '(?m)^=== ArmorBreakZombieControllerTest result: passed=8 failed=0 ===\r?$'
    )
    SuccessSummary = 'ArmorBreakZombieControllerTest 8/8 assertions'
    TimeoutSeconds = $TimeoutSeconds
    SkipCompile = $SkipCompile
}
& $commonRunner @focusedRun
