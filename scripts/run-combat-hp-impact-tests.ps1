[CmdletBinding()]
param(
    [ValidateRange(1, 3600)]
    [int]$TimeoutSeconds = 240,
    [switch]$SkipCompile
)

$ErrorActionPreference = 'Stop'
$commonRunner = Join-Path $PSScriptRoot 'test-runners\run-focused-testloader.ps1'
$focusedRun = @{
    DomainId = 'combat-hp-impact'
    TemplateRelativePath = 'scripts\test-runners\combat-hp-impact\TestLoader.as.template'
    SuiteRelativePaths = @(
        'scripts\类定义\org\flashNight\arki\bullet\BulletComponent\Queue\ToughnessVulnerabilityPipelineTest.as'
    )
    SuiteFqns = @(
        'org.flashNight.arki.bullet.BulletComponent.Queue.ToughnessVulnerabilityPipelineTest'
    )
    ExpectedTracePatterns = @(
        '(?m)^=== ToughnessVulnerabilityPipelineTest result: passed=140 failed=0 ===\r?$'
    )
    SuccessSummary = 'ToughnessVulnerabilityPipelineTest 140/140 assertions'
    TimeoutSeconds = $TimeoutSeconds
    SkipCompile = $SkipCompile
}
& $commonRunner @focusedRun
