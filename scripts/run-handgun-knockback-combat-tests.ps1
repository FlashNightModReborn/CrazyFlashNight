[CmdletBinding()]
param([int]$TimeoutSeconds=300,[switch]$SkipCompile,[switch]$Shotgun,[switch]$ShotgunThreat)
$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
$run=@{
 DomainId='handgun-knockback-combat'
 TemplateRelativePath='scripts/test-runners/handgun-knockback-combat/TestLoader.as.template'
 SuiteRelativePaths=@('scripts/类定义/org/flashNight/arki/unit/Action/Shoot/HandgunKnockbackCombatTest.as')
 SuiteFqns=@('org.flashNight.arki.unit.Action.Shoot.HandgunKnockbackCombatTest')
 AdditionalAsRelativePaths=@(
  'scripts/test-runners/cf6-playtest/PlaytestFixture.as',
  'scripts/类定义/org/flashNight/arki/bullet/Factory/BulletFactory.as',
  'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Queue/BulletQueueProcessor.as',
  'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Lifecycle/BulletLifecycle.as',
  'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Lifecycle/NormalBulletLifecycle.as',
  'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Lifecycle/PierceBulletLifecycle.as',
  'scripts/类定义/org/flashNight/arki/unit/UnitComponent/Status/ImpactStateHandler.as',
  'scripts/类定义/org/flashNight/arki/unit/UnitComponent/Updater/HitUpdater.as',
  'scripts/类定义/org/flashNight/arki/component/StatHandler/ImpactHandler.as',
  'scripts/类定义/org/flashNight/arki/item/EquipmentUtil.as'
 )
 ExpectedTracePatterns=@(
  '(?m)^HandgunKnockbackCombatTest: [1-9][0-9]* passed, 0 failed; [1-9][0-9]* combat cases\r?$',
  '(?m)^HandgunKnockbackCombatTest Tests Passed: [1-9][0-9]*\r?$',
  '(?m)^HandgunKnockbackCombatTest Tests Failed: 0\r?$'
 )
 SuccessSummary='Issue #195 P1/P2 handgun knockback combat matrix: single-shot physics, 1v1 chase, 1v3 squish co-linear multi-hit, pierce ride-along, BlackClaw/GrayGoo mods, and edge cases'
 AsyncBehaviorTimeoutSeconds=180
 TimeoutSeconds=$TimeoutSeconds
 SkipCompile=$SkipCompile
}
if ($Shotgun) {
 $run.DomainId='shotgun-knockback-combat'
 $run.AsyncBehaviorTimeoutSeconds=540
 $run.TemplateRelativePath='scripts/test-runners/handgun-knockback-combat/TestLoader.shotgun.as.template'
 $run.ExpectedTracePatterns = @('(?m)^HandgunKnockbackCombatTest: [1-9][0-9]* passed, 0 failed; 270 combat cases\r?$')
 $run.ExpectedTracePatterns += '(?m)^\[SHOTGUN_HURT_POSES\] a0=[1-9][0-9]* a1=[1-9][0-9]*\r?$'
 foreach ($gun in @('AA12', 'SPAS12', '雷明登870')) {
     foreach ($sample in 0..2) {
         $run.ExpectedTracePatterns += ('(?m)^\[SHOTGUN_CONTACT\] ' + $gun + '\|中距追击\|10\|[^\r\n]+\|' + $sample + '\r?$')
         foreach ($entry in @('后排入线向右', '后排入线向左')) {
             $run.ExpectedTracePatterns += ('(?m)^\[SHOTGUN_CONTACT\] ' + $gun + '\|' + $entry + '\|10\|[1-9][0-9]*,0;[^\r\n]+\|' + $sample + '\r?$')
         }
     }
 }
 $run.SuccessSummary='Three authored shotguns, five knockback settings, six layouts including initially off-axis approaches from either direction, per-shot real segments, positions and actor states'
}
if ($ShotgunThreat) {
 $run.DomainId='shotgun-counterattack'
 $run.AsyncBehaviorTimeoutSeconds=540
 $run.TemplateRelativePath='scripts/test-runners/handgun-knockback-combat/TestLoader.shotgun-threat.as.template'
 $run.ExpectedTracePatterns=@('(?m)^HandgunKnockbackCombatTest: [1-9][0-9]* passed, 0 failed; 225 combat cases\r?$')
 $run.AdditionalAsRelativePaths += 'scripts/逻辑/战斗系统/战斗系统_fs_lsy_aka_重写子弹生成逻辑.as'
 foreach ($gun in @('AA12', 'SPAS12', '雷明登870')) {
     foreach ($sample in 0..2) {
         $run.ExpectedTracePatterns += ('(?m)^\[SHOTGUN_THREAT\] ' + $gun + '\|近身不射对照\|10\|' + $sample + '\|\d+\|\d+\|[1-9][0-9]*\|[^\r\n]+\r?$')
         $run.ExpectedTracePatterns += ('(?m)^\[SHOTGUN_THREAT\] ' + $gun + '\|界外不射对照\|10\|' + $sample + '\|\d+\|-1\|0\|10000\|[^\r\n]+\r?$')
     }
 }
 $run.SuccessSummary='Measured incoming damage before the next legal shot, using the authored guard melee and close/far controls'
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @run
exit $LASTEXITCODE
