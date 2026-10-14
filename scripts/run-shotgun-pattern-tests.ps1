[CmdletBinding()]
param([int]$TimeoutSeconds=300,[switch]$SkipCompile,[switch]$Regression,[switch]$Calibration)
$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
if ($Regression -and $Calibration) { throw 'Run the calibration scene separately from synchronous regression fixtures.' }
# 夹具不能凭旧数值继续通过；绑定当前数据 SHA，并在 focused 执行后复核。
$projectDir=Split-Path -Parent $PSScriptRoot
$profileSuite=Join-Path $projectDir 'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Chain/ShotgunCalibrationTest.as'
$profileText=[IO.File]::ReadAllText($profileSuite,[Text.Encoding]::UTF8)
$dataFiles=@('data/items/武器_长枪_霰弹枪.xml','data/items/武器_手枪_霰弹枪.xml')
$dataHashes=@{}
$expectedProfiles=0
foreach ($relative in $dataFiles) {
 $full=Join-Path $projectDir $relative
 $dataHashes[$relative]=(Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash
 [xml]$xml=[IO.File]::ReadAllText($full,[Text.Encoding]::UTF8)
 foreach ($item in $xml.DocumentElement.item) {
  $b=[string]$item.data.bullet
  if (!$b.StartsWith('横向联弹-') -or $b.Contains('穿刺')) { continue }
  $literal='["{0}",{1},{2},{3}]' -f $item.name,$item.data.split,$item.data.diffusion,$item.data.velocity
  if (!$profileText.Contains($literal)) { throw "Calibration fixture stale: $literal" }
  $expectedProfiles++
 }
}
$actualProfiles=[regex]::Matches($profileText,'\["[^"\r\n]+",[0-9]+,[0-9]+,[0-9]+\]').Count-1 # curveAndBudget 独立 SPAS12
if ($actualProfiles -ne $expectedProfiles) { throw "Calibration profile count mismatch: $actualProfiles / $expectedProfiles" }
Write-Host ("[CALIBRATION_DATA] profiles={0}; current XML SHA256 verified" -f $expectedProfiles)
$run=@{
 DomainId='shotgun-pattern'
 TemplateRelativePath='scripts/test-runners/shotgun-pattern/TestLoader.as.template'
 SuiteRelativePaths=@('scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Chain/ShotgunPatternTest.as')
 SuiteFqns=@('org.flashNight.arki.bullet.BulletComponent.Chain.ShotgunPatternTest')
 AdditionalAsRelativePaths=@(
  'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Chain/ChainGroup.as',
  'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Chain/ChainUnitData.as',
  'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Chain/ChainUnitManager.as',
  'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Chain/ShotgunPattern.as',
  'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Collider/AABBCollider.as',
  'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Collider/PolygonCollider.as',
  'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Lifecycle/BulletLifecycle.as',
  'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Lifecycle/NormalBulletLifecycle.as',
  'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Lifecycle/PierceBulletLifecycle.as',
  'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Lifecycle/PierceBulletProfile.as',
  'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Movement/MissileMovement.as',
  'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Movement/MovementSystem.as',
  'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Queue/BulletQueueProcessor.as',
  'scripts/类定义/org/flashNight/arki/bullet/Factory/BulletFactory.as',
  'scripts/类定义/org/flashNight/arki/component/Damage/DamageCalculator.as',
  'scripts/类定义/org/flashNight/arki/component/Damage/MultiShotDamageHandle.as',
  'scripts/类定义/org/flashNight/arki/render/ChainVisualBridge.as',
  'scripts/类定义/org/flashNight/arki/unit/Action/Shoot/LongGunSubWeaponCore.as',
  'scripts/类定义/org/flashNight/arki/unit/Action/Shoot/ShootInitCore.as',
  'scripts/类定义/org/flashNight/arki/unit/Action/Shoot/WeaponFireCore.as',
  'scripts/类定义/org/flashNight/arki/unit/UnitComponent/Initializer/EventComponent/FireEventComponent.as',
  'scripts/逻辑/战斗系统/战斗系统_fs_联弹管理.as'
 )
 ExpectedTracePatterns=@(
  '(?m)^ShotgunPatternTest Tests Passed: [1-9][0-9]*\r?$',
  '(?m)^ShotgunPatternTest Tests Failed: 0\r?$',
  '(?m)^\[SHOTGUN_COST\] units=4096 ticks=120 boundVisits=240 referenceVisits=240 maxWire=[0-9]+\r?$'
 )
 SuccessSummary='Shotgun finite budget, unique contacts, actual damage chain, natural retirement and bounded reference aggregation'
 TimeoutSeconds=$TimeoutSeconds
 SkipCompile=$SkipCompile
}
if ($Calibration) {
 $run.DomainId='shotgun-calibration'
 $run.TemplateRelativePath='scripts/test-runners/shotgun-pattern/TestLoader.calibration.as.template'
 $run.SuiteRelativePaths=@('scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Chain/ShotgunCalibrationTest.as')
 $run.SuiteFqns=@('org.flashNight.arki.bullet.BulletComponent.Chain.ShotgunCalibrationTest')
 $run.AsyncBehaviorTimeoutSeconds=180
 $run.ExpectedTracePatterns=@(
  '(?m)^ShotgunCalibrationTest Tests Passed: [1-9][0-9]*\r?$',
  '(?m)^ShotgunCalibrationTest Tests Failed: 0\r?$',
  '(?m)^\[SHOTGUN_CALIBRATION\] profiles=30 seeds=8 modes=2 groundModes=2 ages=rangeBounded targets=4 cases=[1-9][0-9]* ',
  '(?m)^\[SHOTGUN_SPAS12_CURVE\] distance:segments=70:10,175:8,280:5,420:2,490:1\r?$'
 )
 $run.SuccessSummary='Paired old production time-decay oracle, exact first-contact eligibility, real damage/dodge/shield and finite distinct-target budget'
}
if ($Regression) {
 $run.DomainId='shotgun-reform-regression'
 $run.TemplateRelativePath='scripts/test-runners/shotgun-pattern/TestLoader.regression.as.template'
 $run.SuiteRelativePaths+=@(
  'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Chain/ChainAggregateTest.as',
  'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Chain/ChainLifecycleTest.as',
  'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Queue/ToughnessVulnerabilityPipelineTest.as'
 )
 $run.SuiteFqns+=@(
  'org.flashNight.arki.bullet.BulletComponent.Chain.ChainAggregateTest',
  'org.flashNight.arki.bullet.BulletComponent.Chain.ChainLifecycleTest',
  'org.flashNight.arki.bullet.BulletComponent.Queue.ToughnessVulnerabilityPipelineTest'
 )
 $run.ExpectedTracePatterns+=@(
  '(?m)^ChainAggregateTest Tests Passed: [1-9][0-9]*\r?$',
  '(?m)^ChainAggregateTest Tests Failed: 0\r?$',
  '(?m)^\[CHAIN_COST\] units=4096 ticks=120 boundVisits=240 scalarAdds=240 ',
  '(?m)^ChainLifecycleTest Tests Passed: [1-9][0-9]*\r?$',
  '(?m)^ChainLifecycleTest Tests Failed: 0\r?$',
  '(?m)^\[LIFECYCLE_MATRIX\] weapons=5 scenarios=6 modes=3 cases=30\r?$',
  '(?m)^=== ToughnessVulnerabilityPipelineTest result: passed=[1-9][0-9]* failed=0 ===\r?$'
 )
 $run.SuccessSummary='Shotgun queue integration plus legacy aggregate/lifecycle, combat damage; calibration and actual projectile assets use independent scenes'
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @run
$testExit=$LASTEXITCODE
foreach ($relative in $dataFiles) {
 if ((Get-FileHash -LiteralPath (Join-Path $projectDir $relative) -Algorithm SHA256).Hash -ne $dataHashes[$relative]) {
  throw "Calibration data changed during run: $relative"
 }
}
exit $testExit
