[CmdletBinding()]
param(
    [ValidateRange(1, 3600)]
    [int]$TimeoutSeconds = 240,
    [ValidateRange(1, 3600)]
    [int]$AsyncBehaviorTimeoutSeconds = 45,
    [switch]$SkipCompile
)

$ErrorActionPreference = 'Stop'
chcp.com 65001 | Out-Null

$run = @{
    DomainId = 'explosion-scatter'
    TemplateRelativePath = 'scripts/test-runners/explosion-scatter/TestLoader.as.template'
    SuiteRelativePaths = @(
        'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Lifecycle/ExplosionScatterTest.as'
    )
    SuiteFqns = @(
        'org.flashNight.arki.bullet.BulletComponent.Lifecycle.ExplosionScatterTest'
    )
    AdditionalAsRelativePaths = @(
        'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Lifecycle/ExplosionScatter.as',
        'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Lifecycle/ExplosionScatterProfile.as',
        'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Loader/AttributeLoader.as',
        'scripts/类定义/org/flashNight/arki/bullet/Factory/BulletFactory.as',
        'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Utils/ShootingAngleCalculator.as',
        'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Shell/ShellSystem.as'
    )
    ExpectedTracePatterns = @(
        '(?m)^ExplosionScatterTest Tests Passed: 125\r?$',
        '(?m)^ExplosionScatterTest Tests Failed: 0\r?$',
        '(?m)^ExplosionScatterCase natural-end frames=[0-9]+ blasts=0 children=0\r?$',
        '(?m)^ExplosionScatterCase live-clock elapsedMs=[0-9]+ blasts=1 children=5\r?$'
    )
    SuccessSummary = 'ExplosionScatter profile/InfoLoader, real 3XD/stock bullet wall/ground/unit scatter, piercing children, ms pause-aware lifetime, Lady non-regression, and idempotency'
    TimeoutSeconds = $TimeoutSeconds
    AsyncBehaviorTimeoutSeconds = $AsyncBehaviorTimeoutSeconds
    SkipCompile = $SkipCompile
}

& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @run
exit $LASTEXITCODE
