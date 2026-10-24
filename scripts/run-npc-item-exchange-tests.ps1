[CmdletBinding()]
param(
    [ValidateRange(1, 3600)][int]$TimeoutSeconds = 300,
    [switch]$SkipCompile
)
$ErrorActionPreference = 'Stop'
$commonRunner = Join-Path $PSScriptRoot 'test-runners\run-focused-testloader.ps1'
$focusedRun = @{
    DomainId = 'npc-item-exchange'
    TemplateRelativePath = 'scripts\test-runners\npc-item-exchange\TestLoader.as.template'
    SuiteRelativePaths = @(
        'scripts\类定义\org\flashNight\arki\item\NpcItemExchangeServiceTest.as'
    )
    SuiteFqns = @('org.flashNight.arki.item.NpcItemExchangeServiceTest')
    AdditionalAsRelativePaths = @(
        'scripts\类定义\org\flashNight\arki\item\NpcItemExchangeService.as'
    )
    ExpectedTracePatterns = @(
        '(?m)^NpcItemExchangeServiceTest Tests Passed: 67\r?$',
        '(?m)^NpcItemExchangeServiceTest Tests Failed: 0\r?$'
    )
    SuccessSummary = 'NPC item exchange 67/67 covering grant, gold, overflow, full bag, take, take notice and equipment lowest-level selection'
    TimeoutSeconds = $TimeoutSeconds
    AsyncBehaviorTimeoutSeconds = 90
    SkipCompile = $SkipCompile
}
& $commonRunner @focusedRun
exit $LASTEXITCODE
