[CmdletBinding()]
param(
    [ValidateRange(1, 3600)]
    [int]$TimeoutSeconds = 240,
    [switch]$SkipCompile
)

$ErrorActionPreference = 'Stop'
$focused = @{
    DomainId = 'archive-shadow-wire'
    TemplateRelativePath = 'scripts/test-runners/archive-shadow-wire/TestLoader.as.template'
    SuiteRelativePaths = @('scripts/类定义/org/flashNight/neur/Server/test/ArchiveShadowWireTest.as')
    SuiteFqns = @('org.flashNight.neur.Server.test.ArchiveShadowWireTest')
    AdditionalAsRelativePaths = @('scripts/类定义/org/flashNight/neur/Server/ArchiveShadowWire.as')
    ExpectedTracePatterns = @('(?m)^========== ArchiveShadowWireTest END: 6/6 passed, 0 failed ==========\r?$')
    SuccessSummary = 'Archive shadow wire string matches legacy FastJSON on all 6 cases'
    TimeoutSeconds = $TimeoutSeconds
    SkipCompile = $SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @focused
