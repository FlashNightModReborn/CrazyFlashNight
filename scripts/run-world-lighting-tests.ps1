[CmdletBinding()]
param([int]$TimeoutSeconds=240)
$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
$run=@{
 DomainId='world-lighting'
 TemplateRelativePath='scripts/test-runners/world-lighting/TestLoader.as.template'
 SuiteRelativePaths=@('scripts/类定义/org/flashNight/arki/weather/WorldLightingBridgeTest.as')
 SuiteFqns=@('org.flashNight.arki.weather.WorldLightingBridgeTest')
 AdditionalAsRelativePaths=@('scripts/类定义/org/flashNight/arki/weather/WorldLightingBridge.as')
 ExpectedTracePatterns=@('(?m)^WorldLightingBridgeTest Tests Passed: 12\r?$','(?m)^WorldLightingBridgeTest Tests Failed: 0\r?$')
 SuccessSummary='World lighting projection tests passed'
 TimeoutSeconds=$TimeoutSeconds
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @run
exit $LASTEXITCODE
