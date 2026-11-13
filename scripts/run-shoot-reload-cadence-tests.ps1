[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=240,[switch]$SkipCompile)
$ErrorActionPreference='Stop'
$focusedRun=@{
    DomainId='shoot-reload-cadence'
    TemplateRelativePath='scripts/test-runners/shoot-reload-cadence/TestLoader.as.template'
    SuiteRelativePaths=@('scripts/类定义/org/flashNight/arki/unit/Action/Shoot/ShootReloadCadenceTest.as')
    SuiteFqns=@('org.flashNight.arki.unit.Action.Shoot.ShootReloadCadenceTest')
    AdditionalAsRelativePaths=@('scripts/逻辑/单位函数/单位函数_雾人_aka_fs_主动战技.as',
        'scripts/逻辑/装备函数/G1111.as',
        'scripts/类定义/org/flashNight/arki/unit/Action/Shoot/BorrowedLongGunShot.as',
        'scripts/类定义/org/flashNight/arki/unit/Action/Shoot/ShootCore.as',
        'scripts/类定义/org/flashNight/arki/unit/UnitComponent/Routing/StateTransition.as')
    ExpectedTracePatterns=@('(?m)^--- ShootReloadCadenceTest: (?<cadence>[1-9][0-9]*)/\k<cadence> passed, 0 failed ---\r?$')
    SuccessSummary='Reload cancellation preserves firing cadence and unique continuation'
    TimeoutSeconds=$TimeoutSeconds
    SkipCompile=$SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @focusedRun
