[CmdletBinding()]
param([int]$TimeoutSeconds=300,[switch]$SkipCompile)
$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
$run=@{
 DomainId='weapon-spread-lifecycle'
 TemplateRelativePath='scripts/test-runners/weapon-spread-lifecycle/TestLoader.as.template'
 SuiteRelativePaths=@('scripts/类定义/org/flashNight/arki/unit/Action/Shoot/WeaponSpreadLifecycleTest.as')
 SuiteFqns=@('org.flashNight.arki.unit.Action.Shoot.WeaponSpreadLifecycleTest')
 AdditionalAsRelativePaths=@(
  'scripts/类定义/org/flashNight/arki/bullet/Factory/BulletFactory.as',
  'scripts/类定义/org/flashNight/arki/unit/Action/Shoot/LongGunSubWeaponCore.as',
  'scripts/类定义/org/flashNight/arki/unit/Action/Shoot/WeaponFireCore.as',
  'scripts/类定义/org/flashNight/arki/unit/UnitComponent/Initializer/EventComponent/FireEventComponent.as',
  'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Movement/MovementSystem.as',
  'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Movement/MissileMovement.as',
  'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Collider/AABBCollider.as',
  'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Collider/PolygonCollider.as',
  'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Queue/BulletQueueProcessor.as',
  'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Lifecycle/BulletLifecycle.as',
  'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Lifecycle/NormalBulletLifecycle.as',
  'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Lifecycle/PierceBulletLifecycle.as',
  'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Chain/ChainUnitManager.as',
  'scripts/逻辑/战斗系统/战斗系统_fs_联弹管理.as'
 )
 ExpectedTracePatterns=@(
  '(?m)^WeaponSpreadLifecycleTest Tests Passed: [1-9][0-9]*\r?$',
  '(?m)^WeaponSpreadLifecycleTest Tests Failed: 0\r?$'

 )
 SuccessSummary='Actual bullet assets: fractional-angle spawn/flight and normal/pierce range cleanup'
 AsyncBehaviorTimeoutSeconds=60
 TimeoutSeconds=$TimeoutSeconds
 SkipCompile=$SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @run
exit $LASTEXITCODE
