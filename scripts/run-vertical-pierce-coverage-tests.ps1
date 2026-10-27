[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=600)
$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
$run=@{
 DomainId='vertical-pierce-coverage'
 TemplateRelativePath='scripts/test-runners/vertical-pierce-coverage/TestLoader.as.template'
 SuiteRelativePaths=@('scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Chain/VerticalPierceCoverageTest.as')
 SuiteFqns=@('org.flashNight.arki.bullet.BulletComponent.Chain.VerticalPierceCoverageTest')
 AdditionalAsRelativePaths=@('scripts/类定义/org/flashNight/arki/unit/UnitComponent/Initializer/UnifiedType61Runtime.as','scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Queue/BulletQueueProcessor.as','scripts/类定义/org/flashNight/arki/component/Damage/MultiShotDamageHandle.as','scripts/逻辑/战斗系统/战斗系统_fs_联弹管理.as')
 ExpectedTracePatterns=@('(?m)^VerticalPierceCoverageTest Checks Passed: [1-9][0-9]*\r?$', '(?m)^VerticalPierceCoverageTest Checks Failed: 0\r?$', '(?m)^\[COVERAGE_RESULT\] case=flat-far ', '(?m)^\[COVERAGE_RESULT\] case=single-pierce-control ')
 SuccessSummary='Vertical piercing coverage continuity, compatible non-horizontal behavior and actual chest spread'
 AsyncBehaviorTimeoutSeconds=120
 TimeoutSeconds=$TimeoutSeconds
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @run
exit $LASTEXITCODE