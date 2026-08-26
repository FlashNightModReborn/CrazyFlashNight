[CmdletBinding()]
param(
    [ValidateRange(1, 3600)]
    [int]$TimeoutSeconds = 240,
    [switch]$SkipCompile
)

$ErrorActionPreference = 'Stop'
$commonRunner = Join-Path $PSScriptRoot 'test-runners\run-focused-testloader.ps1'
$focusedRun = @{
    DomainId = 'hit-number'
    TemplateRelativePath = 'scripts\test-runners\hit-number\TestLoader.as.template'
    SuiteRelativePaths = @(
        'scripts\类定义\org\flashNight\arki\component\Damage\DamageManagerTest.as'
    )
    SuiteFqns = @(
        'org.flashNight.arki.component.Damage.DamageManagerTest'
    )
    ExpectedTracePatterns = @(
        '(?m)^HitNumberBurstContract Tests Passed: 9\r?$'
        '(?m)^HitNumberBurstContract Tests Failed: 0\r?$'
    )
    SuccessSummary = 'HitNumberBurstContract 9/9 assertions'
    TimeoutSeconds = $TimeoutSeconds
    SkipCompile = $SkipCompile
}
& $commonRunner @focusedRun
