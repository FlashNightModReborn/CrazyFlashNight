[CmdletBinding()]
param([int]$TimeoutSeconds=240,[switch]$SkipCompile)
$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
$run=@{
 DomainId='blood-visual-bridge'
 TemplateRelativePath='scripts/test-runners/blood-visual-bridge/TestLoader.as.template'
 SuiteRelativePaths=@('scripts/类定义/org/flashNight/arki/render/BloodVisualBridgeTest.as')
 SuiteFqns=@('org.flashNight.arki.render.BloodVisualBridgeTest')
 AdditionalAsRelativePaths=@('scripts/类定义/org/flashNight/arki/render/BloodVisualBridge.as','scripts/类定义/org/flashNight/arki/component/Effect/BitmapEffectRenderer.as')
 ExpectedTracePatterns=@(
  '(?m)^BloodVisualBridgeTest Tests Passed: [1-9][0-9]*\r?$',
  '(?m)^BloodVisualBridgeTest Tests Failed: 0\r?$'
 )
 SuccessSummary='Seeded blood births, no-clip suppression, bounded landing queues and exact layer-zero bitmap variants checked'
 AsyncBehaviorTimeoutSeconds=120
 TimeoutSeconds=$TimeoutSeconds
 SkipCompile=$SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @run
exit $LASTEXITCODE
