[CmdletBinding()]
param([int]$TimeoutSeconds=240,[switch]$SkipCompile)
$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
$run=@{
 DomainId='ray-scan-geometry'
 TemplateRelativePath='scripts/test-runners/ray-scan-geometry/TestLoader.as.template'
 SuiteRelativePaths=@('scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Queue/RayScanGeometryTest.as')
 SuiteFqns=@('org.flashNight.arki.bullet.BulletComponent.Queue.RayScanGeometryTest')
 AdditionalAsRelativePaths=@(
  'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Queue/BulletQueueProcessor.as',
  'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Collider/RayCollider.as',
  'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Collider/BandRayCollider.as',
  'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Collider/AABBCollider.as',
  'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Collider/CoverageAABBCollider.as',
  'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Collider/PointCollider.as',
  'scripts/类定义/org/flashNight/arki/component/Collider/ICollider.as'
 )
 ExpectedTracePatterns=@(
  '(?m)^RayScanGeometryTest Tests Passed: [1-9][0-9]*\r?$',
  '(?m)^RayScanGeometryTest Tests Failed: 0\r?$',
  '(?m)^\[RAY_SCAN_ORACLE\] pairs=[1-9][0-9]*\|rejected=[1-9][0-9]*\|hits=[1-9][0-9]*\|elapsedMs=[0-9]+\|oracle=unchanged-Ray-and-Band\|comparison=exact\r?$'
 )
 SuccessSummary='Original Ray/Band geometry oracle, strict no-false-negative broad rejection, conservative unknown/invalid fallback, ordered along-ray/flame selection'
 TimeoutSeconds=$TimeoutSeconds
 SkipCompile=$SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @run
exit $LASTEXITCODE