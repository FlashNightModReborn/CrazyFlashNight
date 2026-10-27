[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=600)
$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
$run=@{
 DomainId='vertical-chain-damage-probe'
 TemplateRelativePath='scripts/test-runners/vertical-chain-damage-probe/TestLoader.as.template'
 SuiteRelativePaths=@('scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Chain/VerticalChainDamageProbe.as')
 SuiteFqns=@('org.flashNight.arki.bullet.BulletComponent.Chain.VerticalChainDamageProbe')
 AdditionalAsRelativePaths=@('scripts/类定义/org/flashNight/arki/unit/UnitComponent/Initializer/UnifiedType61Runtime.as','scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Queue/BulletQueueProcessor.as','scripts/类定义/org/flashNight/arki/component/Damage/MultiShotDamageHandle.as','scripts/逻辑/战斗系统/战斗系统_fs_联弹管理.as')
 ExpectedTracePatterns=@('(?m)^VerticalChainDamageProbe Checks Passed: [1-9][0-9]*\r?$', '(?m)^VerticalChainDamageProbe Checks Failed: 0\r?$', '(?m)^\[CANNON_RESULT\] case=chest-12-flat-far ', '(?m)^\[CANNON_RESULT\] case=single-pierce-control ')
 SuccessSummary='Read-only diagnostic: chest emission, real chain flight and full production damage pipeline'
 AsyncBehaviorTimeoutSeconds=120
 TimeoutSeconds=$TimeoutSeconds
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @run
exit $LASTEXITCODE