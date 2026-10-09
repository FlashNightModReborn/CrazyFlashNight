[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds = 240, [switch]$SkipCompile)
$ErrorActionPreference = 'Stop'
chcp.com 65001 | Out-Null
$mapFocusedRun = @{
    DomainId = 'map-domain'
    TemplateRelativePath = 'scripts/test-runners/map-domain/TestLoader.as.template'
    SuiteRelativePaths = @('scripts/类定义/org/flashNight/arki/map/MapDomainBridgeTest.as','scripts/类定义/org/flashNight/arki/map/MapSceneObservationTest.as')
    SuiteFqns = @('org.flashNight.arki.map.MapDomainBridgeTest','org.flashNight.arki.map.MapSceneObservationTest')
    AdditionalAsRelativePaths = @(
        'scripts/类定义/org/flashNight/arki/map/MapDomainBridge.as'
        'scripts/类定义/org/flashNight/arki/map/MapFactsSampler.as'
        'scripts/类定义/org/flashNight/arki/map/MapWorldNpcController.as'
        'scripts/类定义/org/flashNight/arki/map/MapPanelService.as'
        'scripts/类定义/org/flashNight/arki/task/TaskUtil.as'
    )
    ExpectedTracePatterns = @(
        '(?m)^MapDomainBridgeTest Tests Passed: 75\r?$'
        '(?m)^MapDomainBridgeTest Tests Failed: 0\r?$'
        '(?m)^MapSceneObservationTest Tests Passed: [1-9][0-9]*\r?$'
        '(?m)^MapSceneObservationTest Tests Failed: 0\r?$'
    )
    SuccessSummary = 'MapDomainBridgeTest 75/75 plus normalized scene observation, freshness and A/B'
    TimeoutSeconds = $TimeoutSeconds
    SkipCompile = $SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @mapFocusedRun
