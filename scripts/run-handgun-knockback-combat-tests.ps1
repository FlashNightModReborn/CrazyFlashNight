[CmdletBinding()]
param([int]$TimeoutSeconds=300,[switch]$SkipCompile)
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
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @run
exit $LASTEXITCODE
