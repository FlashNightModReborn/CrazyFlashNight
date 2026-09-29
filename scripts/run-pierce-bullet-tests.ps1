[CmdletBinding()]
param([int]$TimeoutSeconds=240,[switch]$SkipCompile)
$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
$run=@{
 DomainId='pierce-bullet'
 TemplateRelativePath='scripts/test-runners/pierce-bullet/TestLoader.as.template'
 SuiteRelativePaths=@('scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Lifecycle/PierceBulletLifecycleTest.as')
 SuiteFqns=@('org.flashNight.arki.bullet.BulletComponent.Lifecycle.PierceBulletLifecycleTest')
 AdditionalAsRelativePaths=@(
  'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Lifecycle/PierceBulletProfile.as',
  'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Lifecycle/PierceBulletLifecycle.as',
  'scripts/类定义/org/flashNight/arki/bullet/Factory/BulletFactory.as'
 )
 ExpectedTracePatterns=@(
  '(?m)^PierceBulletLifecycleTest Tests Passed: [1-9][0-9]*\r?$',
  '(?m)^PierceBulletLifecycleTest Tests Failed: 0\r?$',
  '(?m)^PierceTimeline secondary-repeat-same-tick: .+\r?$',
  '(?m)^PierceTimeline pierce-vanish: .+\r?$'
 )
 SuccessSummary='Piercing profile actual-SWF timeline equivalence, hook ownership and unchanged budget initialization'
 TimeoutSeconds=$TimeoutSeconds
 SkipCompile=$SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @run
exit $LASTEXITCODE
