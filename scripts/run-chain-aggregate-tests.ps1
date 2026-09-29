[CmdletBinding()]
param([int]$TimeoutSeconds=300,[switch]$SkipCompile,[switch]$Lifecycle)
$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
if ($Lifecycle) {
 $run=@{
  DomainId='chain-aggregate-lifecycle'
  TemplateRelativePath='scripts/test-runners/chain-aggregate/TestLoader.lifecycle.as.template'
  SuiteRelativePaths=@('scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Chain/ChainLifecycleTest.as')
  SuiteFqns=@('org.flashNight.arki.bullet.BulletComponent.Chain.ChainLifecycleTest')
  AdditionalAsRelativePaths=@(
   'scripts/逻辑/战斗系统/战斗系统_fs_联弹管理.as',
   'scripts/类定义/org/flashNight/arki/render/ChainVisualBridge.as',
   'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Chain/ChainUnitManager.as',
   'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Chain/ChainGroup.as',
   'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Chain/ChainUnitData.as'
  )
  ExpectedTracePatterns=@(
   '(?m)^ChainLifecycleTest Tests Passed: [1-9][0-9]*\r?$',
   '(?m)^ChainLifecycleTest Tests Failed: 0\r?$',
   '(?m)^\[LIFECYCLE_MATRIX\] weapons=5 scenarios=6 modes=3 cases=30\r?$',
   '(?m)^\[LIFECYCLE_TIMING\] rounds=18 warmup=2 order=rotated\r?$'
  )
  SuccessSummary='Chain lifecycle A/B/C parity plus real-gatling fill/steady cost lines'
  TimeoutSeconds=$TimeoutSeconds
  SkipCompile=$SkipCompile
 }
} else {
 $run=@{
  DomainId='chain-aggregate'
  TemplateRelativePath='scripts/test-runners/chain-aggregate/TestLoader.as.template'
  SuiteRelativePaths=@('scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Chain/ChainAggregateTest.as')
  SuiteFqns=@('org.flashNight.arki.bullet.BulletComponent.Chain.ChainAggregateTest')
  AdditionalAsRelativePaths=@(
   'scripts/逻辑/战斗系统/战斗系统_fs_联弹管理.as',
   'scripts/类定义/org/flashNight/arki/render/ChainVisualBridge.as',
   'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Chain/ChainUnitManager.as',
   'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Chain/ChainGroup.as',
   'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Chain/ChainUnitData.as'
  )
  ExpectedTracePatterns=@(
   '(?m)^ChainAggregateTest Tests Passed: [1-9][0-9]*\r?$',
   '(?m)^ChainAggregateTest Tests Failed: 0\r?$',
   '(?m)^\[CHAIN_COST\] units=4096 ticks=120 boundVisits=240 scalarAdds=240 ',
   '(?m)^\[CHAIN_MATRIX\] prefixes=6 styles=5 combinations=30 ticksEach=48\r?$',
   '(?m)^\[CHAIN_DECAY_COST\] units=4096 ticks=40 removed=[1-9][0-9]+',
   '(?m)^\[CHAIN_VERTICAL_COST\] units=2048 ticks=120 boundVisits=[0-9]+'
  )
  SuccessSummary='Chain exact behavior, RNG, native-only ownership, production registration and scene retirement'
  TimeoutSeconds=$TimeoutSeconds
  SkipCompile=$SkipCompile
 }
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @run
exit $LASTEXITCODE
