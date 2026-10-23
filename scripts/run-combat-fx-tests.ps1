[CmdletBinding()]
param([int]$TimeoutSeconds=240,[switch]$SkipCompile)
$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
$run=@{
 DomainId='combat-fx'
 TemplateRelativePath='scripts/test-runners/combat-fx/TestLoader.as.template'
 SuiteRelativePaths=@('scripts/类定义/org/flashNight/arki/render/CombatFxBridgeTest.as', 'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Queue/RayPipelineEquivalenceTest.as')
 SuiteFqns=@('org.flashNight.arki.render.CombatFxBridgeTest', 'org.flashNight.arki.bullet.BulletComponent.Queue.RayPipelineEquivalenceTest')
 AdditionalAsRelativePaths=@(
  'scripts/类定义/org/flashNight/arki/render/CombatFxBridge.as',
  'scripts/类定义/org/flashNight/arki/render/DecalStampQueue.as',
  'scripts/类定义/org/flashNight/arki/render/VisualRandom.as',
  'scripts/类定义/org/flashNight/arki/render/BloodVisualBridge.as',
  'scripts/类定义/org/flashNight/arki/component/Effect/BitmapEffectRenderer.as',
  'scripts/类定义/org/flashNight/arki/component/Effect/BulletEffectHandler.as',
  'scripts/类定义/org/flashNight/arki/component/Effect/EffectSystem.as'
 )
 ExpectedTracePatterns=@(
  '(?m)^CombatFxBridgeTest Tests Passed: 59\r?$',
  '(?m)^CombatFxBridgeTest Tests Failed: 0\r?$',
  '(?m)^\[RayEq\] PASS: all [1-9][0-9]* checks equal\r?$'
 )
 SuccessSummary='Combat effect clocks, RNG, bounded queues and bitmap stamps and native-only decoration, blood feedback, audio replay and full/none/acid, immediate modulo-matched birth audio 59/59 plus ray pipeline equivalence'
 TimeoutSeconds=$TimeoutSeconds
 SkipCompile=$SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @run
exit $LASTEXITCODE
