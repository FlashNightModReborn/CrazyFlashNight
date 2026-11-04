[CmdletBinding()]
param([int]$TimeoutSeconds=900,[int]$AsyncBehaviorTimeoutSeconds=120,[switch]$SkipCompile)
$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
$run=@{
    DomainId='high-explosive'
    TemplateRelativePath='scripts/test-runners/high-explosive/TestLoader.as.template'
    SuiteRelativePaths=@('scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Lifecycle/HighExplosiveAssetTest.as')
    SuiteFqns=@('org.flashNight.arki.bullet.BulletComponent.Lifecycle.HighExplosiveAssetTest')
    ExpectedTracePatterns=@('(?m)^HighExplosiveAssetTest result: passed=64 failed=0 cases=13\r?$')
    SuccessSummary='Published high-explosive timeline and production projectile settlement measurement; 13 controlled cases / 64 assertions'
    TimeoutSeconds=$TimeoutSeconds
    AsyncBehaviorTimeoutSeconds=$AsyncBehaviorTimeoutSeconds
    SkipCompile=$SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @run
exit $LASTEXITCODE
