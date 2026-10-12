[CmdletBinding()]
param([int]$TimeoutSeconds=300)
$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
$run=@{
 DomainId='worker-projection'
 TemplateRelativePath='scripts/test-runners/worker-projection/TestLoader.as.template'
 SuiteRelativePaths=@('scripts/类定义/org/flashNight/arki/render/WorkerProjectionTest.as')
 SuiteFqns=@('org.flashNight.arki.render.WorkerProjectionTest')
 AdditionalAsRelativePaths=@(
  'scripts/类定义/org/flashNight/arki/render/WorkerProjectionPolicy.as',
  'scripts/类定义/org/flashNight/arki/render/WorkerProjectionTestHost.as',
  'scripts/类定义/org/flashNight/arki/render/VisualRandom.as',
  'scripts/类定义/org/flashNight/arki/render/BulletVisualProbe.as',
  'scripts/类定义/org/flashNight/arki/render/ChainVisualBridge.as',
  'scripts/类定义/org/flashNight/arki/render/RayVisualBridge.as',
  'scripts/类定义/org/flashNight/arki/render/CombatFxBridge.as',
  'scripts/类定义/org/flashNight/arki/render/SceneLightBridge.as',
  'scripts/类定义/org/flashNight/arki/hud/PlayerHudService.as',
  'scripts/类定义/org/flashNight/arki/corpse/DeathEffectRenderer.as',
  'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Chain/ChainGroup.as',
  'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Chain/ChainUnitManager.as',
  'scripts/逻辑/战斗系统/战斗系统_fs_联弹管理.as'
 )
 ExpectedTracePatterns=@(
  '(?m)^WorkerProjectionTest Tests Passed: [1-9][0-9]*\r?$',
  '(?m)^WorkerProjectionTest Tests Failed: 0\r?$',
  '(?m)^\[WORKER_CHAIN_BOUND\] groupsBorn=45000 unitsBorn=360000 peakLiveGroups=1 peakReserved=8 projectionRows=0 finalGroups=0 '
 )
 SuccessSummary='Actual root EnterFrame installation, full/none Chain authority equality and bounded no-consumer production'
 AsyncBehaviorTimeoutSeconds=600
 TimeoutSeconds=$TimeoutSeconds
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @run
exit $LASTEXITCODE
