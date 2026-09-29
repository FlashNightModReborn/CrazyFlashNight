[CmdletBinding()]
param([int]$TimeoutSeconds=300,[switch]$SkipCompile)
$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
$run=@{
 DomainId='combat-native-closeout'
 TemplateRelativePath='scripts/test-runners/combat-native-closeout/TestLoader.as.template'
 SuiteRelativePaths=@('scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Chain/ChainAggregateTest.as',
  'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Chain/ChainLifecycleTest.as',
  'scripts/类定义/org/flashNight/arki/render/BulletVisualProbeTest.as',
  'scripts/类定义/org/flashNight/arki/render/RayVisualBridgeTest.as',
  'scripts/类定义/org/flashNight/arki/render/RayVfxManagerTest.as',
  'scripts/类定义/org/flashNight/arki/render/CombatFxBridgeTest.as',
  'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Queue/RayPipelineEquivalenceTest.as')
 SuiteFqns=@('org.flashNight.arki.bullet.BulletComponent.Chain.ChainAggregateTest',
  'org.flashNight.arki.bullet.BulletComponent.Chain.ChainLifecycleTest',
  'org.flashNight.arki.render.BulletVisualProbeTest',
  'org.flashNight.arki.render.RayVisualBridgeTest',
  'org.flashNight.arki.render.RayVfxManagerTest',
  'org.flashNight.arki.render.CombatFxBridgeTest',
  'org.flashNight.arki.bullet.BulletComponent.Queue.RayPipelineEquivalenceTest')
 AdditionalAsRelativePaths=@(
  'scripts/逻辑/战斗系统/战斗系统_fs_联弹管理.as',
  'scripts/类定义/org/flashNight/arki/render/ChainVisualBridge.as',
  'scripts/类定义/org/flashNight/arki/render/BulletVisualProbe.as',
  'scripts/类定义/org/flashNight/arki/render/RayVisualBridge.as',
  'scripts/类定义/org/flashNight/arki/render/RayVfxManager.as',
  'scripts/类定义/org/flashNight/arki/render/CombatFxBridge.as',
  'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Chain/ChainUnitManager.as',
  'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Shell/ShellSystem.as'
 )
 ExpectedTracePatterns=@('(?m)^ChainAggregateTest Tests Passed: [1-9][0-9]*\r?$',
  '(?m)^ChainAggregateTest Tests Failed: 0\r?$',
  '(?m)^ChainLifecycleTest Tests Passed: [1-9][0-9]*\r?$',
  '(?m)^ChainLifecycleTest Tests Failed: 0\r?$',
  '(?m)^BulletVisualProbeTest Tests Passed: [1-9][0-9]*\r?$',
  '(?m)^BulletVisualProbeTest Tests Failed: 0\r?$',
  '(?m)^RayVisualBridgeTest Tests Passed: [1-9][0-9]*\r?$',
  '(?m)^RayVisualBridgeTest Tests Failed: 0\r?$',
  '(?m)^CombatFxBridgeTest Tests Passed: [1-9][0-9]*\r?$',
  '(?m)^CombatFxBridgeTest Tests Failed: 0\r?$',
  '(?m)^\[RayEq\] PASS: all [1-9][0-9]* checks equal\r?$',
  '(?m)^===== RayVfxManagerTest 结束: run=[1-9][0-9]*, pass=[1-9][0-9]*, fail=0 =====\r?$')
 SuccessSummary='Native-only projectile ownership, chain lifecycle selection, ray channels and reference renderer, decorative FX and ray gameplay parity'
 TimeoutSeconds=$TimeoutSeconds
 SkipCompile=$SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @run
exit $LASTEXITCODE
