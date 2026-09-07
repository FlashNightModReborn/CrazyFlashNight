[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds = 240, [switch]$SkipCompile)
$ErrorActionPreference = 'Stop'
chcp.com 65001 | Out-Null
$mapFocusedRun = @{
    DomainId = 'map-domain'
    TemplateRelativePath = 'scripts/test-runners/map-domain/TestLoader.as.template'
    SuiteRelativePaths = @('scripts/类定义/org/flashNight/arki/map/MapDomainBridgeTest.as')
    SuiteFqns = @('org.flashNight.arki.map.MapDomainBridgeTest')
    AdditionalAsRelativePaths = @(
        'scripts/类定义/org/flashNight/arki/map/MapDomainBridge.as'
        'scripts/类定义/org/flashNight/arki/map/MapFactsSampler.as'
        'scripts/类定义/org/flashNight/arki/map/MapWorldNpcController.as'
        'scripts/类定义/org/flashNight/arki/map/MapPanelService.as'
    )
    ExpectedTracePatterns = @(
        '(?m)^MapDomainBridgeTest Tests Passed: 26\r?$'
        '(?m)^MapDomainBridgeTest Tests Failed: 0\r?$'
    )
    SuccessSummary = 'MapDomainBridgeTest 26/26'
    TimeoutSeconds = $TimeoutSeconds
    SkipCompile = $SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @mapFocusedRun
