[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=900)
$ErrorActionPreference='Stop'
$chain='scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Chain'
$run=@{
    DomainId='half-pierce'
    TemplateRelativePath='scripts/test-runners/half-pierce/TestLoader.as.template'
    SuiteRelativePaths=@("$chain/HalfPierceBudgetTest.as")
    SuiteFqns=@('org.flashNight.arki.bullet.BulletComponent.Chain.HalfPierceBudgetTest')
    AdditionalAsRelativePaths=@(
        "$chain/HalfPierceBudget.as",
        'scripts/逻辑/装备函数/GM6_LYNX.as',
        'scripts/逻辑/战斗系统/战斗系统_fs_联弹管理.as'
    )
    ExpectedTracePatterns=@(
        '(?m)^HalfPierceBudgetTest Tests Passed: [1-9][0-9]*\r?$',
        '(?m)^HalfPierceBudgetTest Tests Failed: 0\r?$',
        '(?m)^\[I257_ROW\] gun=SPAS12 scene=dense pair=4 mode=50 view=flash ',
        '(?m)^\[I257_ROW\] gun=XM556-Microgun scene=dense pair=4 mode=50 view=native ',
        '(?m)^\[I257_ROW\] gun=XM556-Microgun scene=close pair=62 mode=50 view=native ',
        '(?m)^\[I257_ROW\] gun=P90 scene=dense pair=4 mode=50 view=flash ',
        '(?m)^\[I257_COMPAT\] view=flash ',
        '(?m)^\[I257_COMPAT\] view=native ',
        '(?m)^\[I257_GM6\] case=0 afterShot=4 kills=front,rear ammo=5,8 reward=3 deep=0',
        '(?m)^\[I257_GM6\] case=1 afterShot=8 kills=front,rear ammo=10,10 reward=5 deep=0',
        '(?m)^\[I257_T181C\] shots=540 controlFront=540 controlRear=0 front=540 rear=',
        '(?m)^\[I257_AMMO\] gun=MP40 bullet=精制普通子弹 tier=25 ',
        '(?m)^\[I257_AMMO\] gun=G11 bullet=普通无壳子弹 tier=50 ',
        '(?m)^\[I257_AMMO\] gun=G111 bullet=纵向联弹-普通无壳子弹 tier=50 ',
        '(?m)^\[I257_AMMO\] gun=Killer 7 bullet=绿色能量普通子弹 tier=50 ',
        '(?m)^\[I359_AMMO\] bullet=精制普通子弹 tier=25\r?$',
        '(?m)^\[I359_AMMO\] bullet=冰冷普通子弹 tier=50\r?$',
        '(?m)^\[I359_AMMO\] bullet=烈焰普通子弹 tier=50\r?$',
        '(?m)^\[I359_AMMO\] bullet=能量普通子弹 tier=50\r?$',
        '(?m)^\[I359_AMMO\] bullet=普通无壳子弹 tier=50\r?$'
    )
    SuccessSummary='Half-pierce credit, real factory, collision queue, damage and timing in Flash'
    TimeoutSeconds=$TimeoutSeconds
    AsyncBehaviorTimeoutSeconds=540
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @run
exit $LASTEXITCODE
