[CmdletBinding()]
param(
    [ValidateRange(1, 3600)]
    [int]$TimeoutSeconds = 240,
    [switch]$SkipCompile
)

$ErrorActionPreference = 'Stop'
$commonRunner = Join-Path $PSScriptRoot 'test-runners\run-focused-testloader.ps1'
$focusedRun = @{
    DomainId = 'save-storage-probe'
    TemplateRelativePath = 'scripts\test-runners\save-storage-probe\TestLoader.as.template'
    SuiteRelativePaths = @(
        'scripts\类定义\org\flashNight\neur\Server\test\FlashStorageProbeTest.as'
    )
    SuiteFqns = @(
        'org.flashNight.neur.Server.test.FlashStorageProbeTest'
    )
    ExpectedTracePatterns = @(
        '(?m)^FlashStorageProbe ready\r?$'
    )
    SuccessSummary = 'isolated Flash probe ready; disk verification belongs to the host driver'
    TimeoutSeconds = $TimeoutSeconds
    SkipCompile = $SkipCompile
}
& $commonRunner @focusedRun
