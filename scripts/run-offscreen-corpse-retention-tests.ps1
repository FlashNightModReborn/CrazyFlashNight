[CmdletBinding()]
param(
    [ValidateRange(1, 3600)]
    [int]$TimeoutSeconds = 240,
    [switch]$SkipCompile
)

$ErrorActionPreference = 'Stop'
$staticTest = Join-Path (Split-Path -Parent $PSScriptRoot) `
    'tools\test-offscreen-corpse-retention.ps1'
& $staticTest

$commonRunner = Join-Path $PSScriptRoot 'test-runners\run-focused-testloader.ps1'
$focusedRun = @{
    DomainId = 'offscreen-corpse-retention'
    TemplateRelativePath = 'scripts\test-runners\offscreen-corpse-retention\TestLoader.as.template'
    SuiteRelativePaths = @(
        'scripts\类定义\org\flashNight\arki\corpse\DeathEffectRendererTest.as'
    )
    SuiteFqns = @(
        'org.flashNight.arki.corpse.DeathEffectRendererTest'
    )
    ExpectedTracePatterns = @(
        '(?m)^DeathEffectRendererTest Tests Passed: 15\r?$'
        '(?m)^DeathEffectRendererTest Tests Failed: 0\r?$'
        '(?m)^DeathEffectRendererTest Cases Passed: 7/7\r?$'
    )
    SuccessSummary = '15/15 assertions, 7/7 cases'
    TimeoutSeconds = $TimeoutSeconds
    SkipCompile = $SkipCompile
}
& $commonRunner @focusedRun
