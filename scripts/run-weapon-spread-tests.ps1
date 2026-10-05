[CmdletBinding()]
param([int]$TimeoutSeconds=300,[switch]$SkipCompile)
$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
$run=@{
 DomainId='weapon-spread'
 TemplateRelativePath='scripts/test-runners/weapon-spread/TestLoader.as.template'
 SuiteRelativePaths=@('scripts/类定义/org/flashNight/arki/unit/Action/Shoot/WeaponSpreadRuntimeTest.as')
 SuiteFqns=@('org.flashNight.arki.unit.Action.Shoot.WeaponSpreadRuntimeTest')
 AdditionalAsRelativePaths=@(
  'scripts/类定义/org/flashNight/arki/unit/Action/Shoot/WeaponSpreadRuntime.as',
  'scripts/类定义/org/flashNight/arki/unit/Action/Shoot/WeaponFireCore.as',
  'scripts/类定义/org/flashNight/arki/unit/UnitComponent/Initializer/EventComponent/FireEventComponent.as',
  'scripts/类定义/org/flashNight/arki/bullet/Factory/BulletFactory.as',
  'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Chain/ChainGroup.as',
  'scripts/逻辑/战斗系统/战斗系统_fs_联弹管理.as'
 )
 ExpectedTracePatterns=@(
  '(?m)^WeaponSpreadRuntimeTest Tests Passed: [1-9][0-9]*\r?$',
  '(?m)^WeaponSpreadRuntimeTest Tests Failed: 0\r?$'
 )
 SuccessSummary='Weapon spread commit/window/identity/pause/RNG and frozen vertical chain coverage'
 TimeoutSeconds=$TimeoutSeconds
 SkipCompile=$SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @run
exit $LASTEXITCODE
