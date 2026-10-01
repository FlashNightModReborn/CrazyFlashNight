[CmdletBinding()]
param([int]$TimeoutSeconds=240)
$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
$run=@{
 DomainId='scene-lighting'
 TemplateRelativePath='scripts/test-runners/scene-lighting/TestLoader.as.template'
 SuiteRelativePaths=@('scripts/类定义/org/flashNight/arki/render/SceneLightBridgeTest.as','scripts/类定义/org/flashNight/arki/render/SceneLightAssetTest.as')
 SuiteFqns=@('org.flashNight.arki.render.SceneLightBridgeTest','org.flashNight.arki.render.SceneLightAssetTest')
 AdditionalAsRelativePaths=@('scripts/类定义/org/flashNight/arki/render/SceneLightBridge.as')
 ExpectedTracePatterns=@('(?m)^SceneLightBridgeTest Tests Passed: 23\r?$','(?m)^SceneLightBridgeTest Tests Failed: 0\r?$','(?m)^SceneLightAssetTest Tests Passed: 7\r?$','(?m)^SceneLightAssetTest Tests Failed: 0\r?$')
 SuccessSummary='Scene light binding tests passed'
 TimeoutSeconds=$TimeoutSeconds
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @run
exit $LASTEXITCODE
