[CmdletBinding()]
param([int]$TimeoutSeconds=300)
$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
$run=@{
 DomainId='worker-trail-geometry'
 TemplateRelativePath='scripts/test-runners/worker-trail-geometry/TestLoader.as.template'
 SuiteRelativePaths=@('scripts/类定义/org/flashNight/arki/render/WorkerTrailGeometryTest.as')
 SuiteFqns=@('org.flashNight.arki.render.WorkerTrailGeometryTest')
 AdditionalAsRelativePaths=@('scripts/类定义/org/flashNight/arki/render/WorkerProjectionPolicy.as',
  'scripts/类定义/org/flashNight/arki/render/WorkerProjectionTestHost.as',
  'scripts/逻辑/战斗系统/战斗系统_fs_联弹管理.as',
  'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Chain/ChainUnitManager.as')
 ExpectedTracePatterns=@('(?m)^WorkerTrailGeometryTest Tests Passed: 2\r?$',
  '(?m)^WorkerTrailGeometryTest Tests Failed: 0\r?$',
  '(?m)^\[WORKER_TRAIL_GEOMETRY\] rows=96 differingRows=0 firstMismatch=-1\r?$')
 SuccessSummary='Full/none actual Flash trail drawing and gameplay collision bounds'
 AsyncBehaviorTimeoutSeconds=120
 TimeoutSeconds=$TimeoutSeconds
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @run
exit $LASTEXITCODE
