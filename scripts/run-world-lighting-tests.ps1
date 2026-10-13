[CmdletBinding()]
param([int]$TimeoutSeconds=240)
$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
$run=@{
 DomainId='world-lighting'
 TemplateRelativePath='scripts/test-runners/world-lighting/TestLoader.as.template'
 SuiteRelativePaths=@('scripts/类定义/org/flashNight/arki/weather/WorldLightingBridgeTest.as','scripts/类定义/org/flashNight/arki/weather/NightVisionUnitTintTest.as')
 SuiteFqns=@('org.flashNight.arki.weather.WorldLightingBridgeTest','org.flashNight.arki.weather.NightVisionUnitTintTest')
 AdditionalAsRelativePaths=@('scripts/类定义/org/flashNight/arki/weather/WorldLightingBridge.as','scripts/类定义/org/flashNight/arki/weather/NightVisionUnitTint.as')
 ExpectedTracePatterns=@('(?m)^WorldLightingBridgeTest Tests Passed: 25\r?$','(?m)^WorldLightingBridgeTest Tests Failed: 0\r?$','(?m)^NightVisionUnitTintTest Tests Passed: 71\r?$','(?m)^NightVisionUnitTintTest Tests Failed: 0\r?$')
 SuccessSummary='World lighting projection and unit tint tests passed'
 TimeoutSeconds=$TimeoutSeconds
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @run
exit $LASTEXITCODE