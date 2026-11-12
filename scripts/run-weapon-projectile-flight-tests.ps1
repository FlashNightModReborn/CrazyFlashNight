[CmdletBinding()]
param([int]$TimeoutSeconds=300,[switch]$SkipCompile,[switch]$Player20,[string]$EvidenceDirectory)
$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
$run=@{
 DomainId='weapon-projectile-flight'
 TemplateRelativePath='scripts/test-runners/weapon-projectile-flight/TestLoader.as.template'
 SuiteRelativePaths=@('scripts/类定义/org/flashNight/arki/unit/Action/Shoot/WeaponProjectileFlightTest.as')
 SuiteFqns=@('org.flashNight.arki.unit.Action.Shoot.WeaponProjectileFlightTest')
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
  'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Chain/ChainUnitManager.as',
  'scripts/逻辑/战斗系统/战斗系统_fs_联弹管理.as'
 )
 ExpectedTracePatterns=@(
  '(?m)^WeaponProjectileFlightTest Tests Passed: [1-9][0-9]*\r?$',
  '(?m)^WeaponProjectileFlightTest Tests Failed: 0\r?$'
 )
 SuccessSummary='Actual bullet assets: vertical object/MC fallback and subweapon missile search/collision/cleanup'
 AsyncBehaviorTimeoutSeconds=60
 TimeoutSeconds=$TimeoutSeconds
 SkipCompile=$SkipCompile
}
if ($Player20) {
    $run.TemplateRelativePath='scripts/test-runners/weapon-projectile-flight/Player20.as.template'
    $run.ExpectedTracePatterns=@('(?m)^WeaponProjectileFlightTest standalone handoff\r?$')
    $run.SuccessSummary='真实弹体飞行测试已为 Flash Player 20 编译'
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @run
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
if ($Player20) {
    $project=Split-Path -Parent $PSScriptRoot
    if (-not $EvidenceDirectory) { $EvidenceDirectory=Join-Path $project ('tmp/projectile-flight/'+[guid]::NewGuid().ToString('N')) }
    & python -B -X utf8 (Join-Path $project 'tools/combat-fx-assets/verify_light_authoring.py') --flight `
        --test-swf (Join-Path $PSScriptRoot 'TestLoader.swf') --compile-trace (Join-Path $PSScriptRoot 'flashlog.txt') --output $EvidenceDirectory
}
exit $LASTEXITCODE
