[CmdletBinding()]
param([int]$TimeoutSeconds=240,[switch]$SkipCompile)
$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
$run=@{
 DomainId='ray-visual'
 TemplateRelativePath='scripts/test-runners/ray-visual/TestLoader.as.template'
 SuiteRelativePaths=@('scripts/类定义/org/flashNight/arki/render/RayVisualBridgeTest.as','scripts/类定义/org/flashNight/arki/render/RayVfxManagerTest.as','scripts/类定义/org/flashNight/arki/render/RayGuardContractTest.as')
 SuiteFqns=@('org.flashNight.arki.render.RayVisualBridgeTest','org.flashNight.arki.render.RayVfxManagerTest','org.flashNight.arki.render.RayGuardContractTest')
 AdditionalAsRelativePaths=@(
  'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Lifecycle/TeslaRayLifecycle.as',
  'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Queue/BulletQueueProcessor.as',
  'scripts/类定义/org/flashNight/arki/unit/Action/Shoot/WeaponFireCore.as',
  'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Config/TeslaRayConfig.as',
  'scripts/类定义/org/flashNight/arki/render/RayVisualBridge.as',
  'scripts/类定义/org/flashNight/arki/render/RayVfxManager.as',
  'scripts/类定义/org/flashNight/arki/render/RayStyleRegistry.as',
  'scripts/类定义/org/flashNight/arki/render/VisualRandom.as',
  'scripts/类定义/org/flashNight/arki/render/renderer/TeslaRenderer.as',
  'scripts/类定义/org/flashNight/arki/render/renderer/PrismRenderer.as',
  'scripts/类定义/org/flashNight/arki/render/renderer/ConvergenceRenderer.as',
  'scripts/类定义/org/flashNight/arki/render/renderer/PhaseResonanceRenderer.as',
  'scripts/类定义/org/flashNight/arki/render/renderer/RadianceRenderer.as',
  'scripts/类定义/org/flashNight/arki/render/renderer/SpectrumRenderer.as',
  'scripts/类定义/org/flashNight/arki/render/renderer/FlameStreamRenderer.as',
  'scripts/类定义/org/flashNight/arki/render/renderer/BaguaRodRenderer.as',
  'scripts/类定义/org/flashNight/arki/render/renderer/PlasmaRenderer.as',
  'scripts/类定义/org/flashNight/arki/render/renderer/ThermalRenderer.as',
  'scripts/类定义/org/flashNight/arki/render/renderer/WaveRenderer.as',
  'scripts/类定义/org/flashNight/arki/render/renderer/VortexRenderer.as'
 )
 ExpectedTracePatterns=@(
  '(?m)^RayGuardContractTest Tests Passed: [1-9][0-9]*\r?$',
  '(?m)^RayGuardContractTest Tests Failed: 0\r?$',
  '(?m)^RayVisualBridgeTest Tests Passed: [1-9][0-9]*\r?$',
  '(?m)^RayVisualBridgeTest Tests Failed: 0\r?$',
  '(?m)^===== RayVfxManagerTest 结束: run=[1-9][0-9]*, pass=[1-9][0-9]*, fail=0 =====\r?$'
 )
 SuccessSummary='Native ray ownership, real source channels, single-projectile admission, ordered coalescing, flame source isolation, lighting and explicit offline Flash reference'
 TimeoutSeconds=$TimeoutSeconds
 SkipCompile=$SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @run
exit $LASTEXITCODE
