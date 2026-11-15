[CmdletBinding()]
param([int]$TimeoutSeconds = 600, [int]$AsyncBehaviorTimeoutSeconds = 60, [switch]$SkipCompile)
$ErrorActionPreference = 'Stop'
chcp.com 65001 | Out-Null
$run = @{
    DomainId = 'small-missile-migration'
    TemplateRelativePath = 'scripts/test-runners/small-missile-migration/TestLoader.as.template'
    SuiteRelativePaths = @('scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Movement/SmallMissileMigrationTest.as')
    SuiteFqns = @('org.flashNight.arki.bullet.BulletComponent.Movement.SmallMissileMigrationTest')
    AdditionalAsRelativePaths = @(
        'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Movement/LoiteringMissileMovement.as',
        'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Movement/MissileMovement.as',
        'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Movement/MovementSystem.as',
        'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Movement/AcceleratedMovement.as',
        'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Movement/Util/MissileConfig.as',
        'scripts/类定义/org/flashNight/gesh/xml/LoadXml/MissileConfigLoader.as',
        'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Loader/InfoLoader.as',
        'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Loader/MovementLoader.as',
        'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Lifecycle/NormalBulletLifecycle.as',
        'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Lifecycle/UnitBulletLifecycle.as',
        'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Queue/BulletQueueProcessor.as',
        'scripts/类定义/org/flashNight/arki/bullet/Factory/BulletFactory.as'
    )
    ExpectedTracePatterns = @(
        '(?m)^SmallMissileMigrationTest Tests Passed: [1-9][0-9]*\r?$',
        '(?m)^SmallMissileMigrationTest Tests Failed: 0\r?$'
    )
    SuccessSummary = 'Actual 小型导弹/毒刺 SWF assets, XML configs, Stinger AcceleratedMovement + UnitBulletLifecycle, and 小型导弹 LoiteringMissileMovement kinematics/loitering/dodge regression'
    AsyncBehaviorTimeoutSeconds = $AsyncBehaviorTimeoutSeconds
    TimeoutSeconds = $TimeoutSeconds
    SkipCompile = $SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @run
exit $LASTEXITCODE
