[CmdletBinding()]
param(
    [ValidateRange(1, 3600)]
    [int]$TimeoutSeconds = 240,
    [switch]$SkipCompile
)

$ErrorActionPreference = 'Stop'
$commonRunner = Join-Path $PSScriptRoot 'test-runners\run-focused-testloader.ps1'
$focusedRun = @{
    DomainId = 'save-storage'
    TemplateRelativePath = 'scripts\test-runners\save-storage\TestLoader.as.template'
    SuiteRelativePaths = @(
        'scripts\类定义\org\flashNight\neur\Server\test\SaveManagerTest.as'
    )
    SuiteFqns = @(
        'org.flashNight.neur.Server.test.SaveManagerTest'
    )
    ExpectedTracePatterns = @(
        '(?m)^========== SaveManagerTest END: ([1-9]\d*)/\1 passed, 0 failed ==========\r?$'
    )
    SuccessSummary = 'SaveManager storage/flow suite, zero failures'
    TimeoutSeconds = $TimeoutSeconds
    SkipCompile = $SkipCompile
}
& $commonRunner @focusedRun
