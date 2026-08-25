[CmdletBinding()]
param(
    [ValidateRange(1, 3600)]
    [int]$TimeoutSeconds = 240,
    [switch]$SkipCompile
)

$ErrorActionPreference = 'Stop'
$commonRunner = Join-Path $PSScriptRoot 'test-runners\run-focused-testloader.ps1'

$focusedRun = @{
    DomainId = 'arena-drop-rules'
    TemplateRelativePath = 'scripts\test-runners\arena-drop-rules\TestLoader.as.template'
    SuiteRelativePaths = @(
        'scripts\类定义\org\flashNight\arki\merc\ArenaDropRuleCatalogTest.as'
    )
    SuiteFqns = @(
        'org.flashNight.arki.merc.ArenaDropRuleCatalogTest'
    )
    AdditionalAsRelativePaths = @(
        'scripts\类定义\org\flashNight\arki\merc\ArenaDropRuleCatalog.as'
        'scripts\类定义\org\flashNight\gesh\xml\LoadXml\ArenaDropRulesLoader.as'
        'scripts\类定义\org\flashNight\arki\item\obtain\ItemObtainIndex.as'
        'scripts\类定义\org\flashNight\gesh\tooltip\builder\ObtainMethodsBuilder.as'
    )
    ExpectedTracePatterns = @(
        '(?m)^ArenaDropRuleCatalogTest Tests Passed: 20\r?$'
        '(?m)^ArenaDropRuleCatalogTest Tests Failed: 0\r?$'
    )
    SuccessSummary = 'ArenaDropRuleCatalogTest 20/20'
    TimeoutSeconds = $TimeoutSeconds
    SkipCompile = $SkipCompile
}
& $commonRunner @focusedRun
