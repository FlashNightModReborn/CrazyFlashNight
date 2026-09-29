[CmdletBinding()]
param([int]$TimeoutSeconds=240,[switch]$SkipCompile)
$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
$run=@{
 DomainId='bullet-visual'
 TemplateRelativePath='scripts/test-runners/bullet-visual/TestLoader.as.template'
 SuiteRelativePaths=@('scripts/类定义/org/flashNight/arki/render/BulletVisualProbeTest.as')
 SuiteFqns=@('org.flashNight.arki.render.BulletVisualProbeTest')
 AdditionalAsRelativePaths=@(
  'scripts/类定义/org/flashNight/arki/render/BulletVisualProbe.as',
  'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Chain/ChainUnitManager.as'
 )
 ExpectedTracePatterns=@(
  '(?m)^BulletVisualProbeTest Tests Passed: 13\r?$',
  '(?m)^BulletVisualProbeTest Tests Failed: 0\r?$'
 )
 SuccessSummary='Bullet native-only ownership, 1024/1025 capacity, fault reporting and epoch retirement 13/13'
 TimeoutSeconds=$TimeoutSeconds
 SkipCompile=$SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @run
exit $LASTEXITCODE
