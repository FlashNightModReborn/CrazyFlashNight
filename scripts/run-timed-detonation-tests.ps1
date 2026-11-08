[CmdletBinding()]
param([int]$TimeoutSeconds=1200,[int]$AsyncBehaviorTimeoutSeconds=90,[switch]$SkipCompile)
$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
& python -X utf8 -B (Join-Path $PSScriptRoot '../tools/cf6-soldier-assets/build-fixed-test-consumer.py') --firepower-projectiles
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$run=@{
    DomainId='timed-detonation'
    CompileTargetRelativePath='scripts/Cf6FirepowerProjectileHost/Cf6FirepowerProjectileHost.xfl'
    CompileSwfRelativePath='scripts/Cf6FirepowerProjectileHost.swf'
    TemplateRelativePath='scripts/test-runners/timed-detonation/TestLoader.as.template'
    SuiteRelativePaths=@(
        'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Lifecycle/TimedDetonationTest.as',
        'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Lifecycle/TimedDetonationAssetTest.as',
        'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Queue/BulletTargetFilterTest.as'
    )
    SuiteFqns=@(
        'org.flashNight.arki.bullet.BulletComponent.Lifecycle.TimedDetonationTest',
        'org.flashNight.arki.bullet.BulletComponent.Lifecycle.TimedDetonationAssetTest',
        'org.flashNight.arki.bullet.BulletComponent.Queue.BulletTargetFilterTest'
    )
    AdditionalAsRelativePaths=@(
        'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Lifecycle/TimedDetonation.as',
        'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Lifecycle/TimedDetonationProfile.as',
        'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Lifecycle/UnitBulletLifecycle.as',
        'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Loader/AttributeLoader.as',
        'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Queue/BulletQueueProcessor.as',
        'scripts/类定义/org/flashNight/arki/bullet/Factory/BulletFactory.as'
    )
    ExpectedTracePatterns=@(
        '(?m)^TimedDetonationTest Tests Passed: 113\r?$',
        '(?m)^TimedDetonationTest Tests Failed: 0\r?$',
        '(?m)^BulletTargetFilterTest Tests Passed: 17\r?$',
        '(?m)^BulletTargetFilterTest Tests Failed: 0\r?$',
        '(?m)^TimedDetonationAssetTest Tests Passed: 82\r?$',
        '(?m)^TimedDetonationAssetTest Tests Failed: 0\r?$',
        '(?m)^TimedDetonationNativeCase timeout explosions=1 children=4\r?$',
        '(?m)^TimedDetonationNativeCase contact explosions=1 children=0\r?$',
        '(?m)^TimedDetonationNativeCase long-flight explosions=1 children=4\r?$',
        '(?m)^TimedDetonationNativeCase live elapsedMs=[0-9]+ explosions=1 children=4\r?$'
        '(?m)^TimedDetonationCoverage directWidth=[0-9.]+ scatterWidth=[0-9.]+ ratio=[0-9.]+ directHits=[0-9]+ scatterHits=[0-9]+\r?$'
    )
    SuccessSummary='Native AVM1 timer, collision priority, exactly-once detonation and actual FM92/ordinary-grenade factory/queue regression'
    TimeoutSeconds=$TimeoutSeconds
    AsyncBehaviorTimeoutSeconds=$AsyncBehaviorTimeoutSeconds
    SkipCompile=$SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @run
exit $LASTEXITCODE
