[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=900,[switch]$SkipCompile)
$ErrorActionPreference='Stop'
$focusedRun=@{
    DomainId='huofeng-contract'
    TemplateRelativePath='scripts/test-runners/huofeng-contract/TestLoader.as.template'
    SuiteRelativePaths=@('scripts/类定义/org/flashNight/arki/unit/Action/Huofeng/HuofengContractTest.as')
    SuiteFqns=@('org.flashNight.arki.unit.Action.Huofeng.HuofengContractTest')
    AdditionalAsRelativePaths=@(
        'scripts/类定义/org/flashNight/arki/component/Damage/UniversalDamageHandleTest.as'
        'scripts/类定义/org/flashNight/arki/component/Damage/DamageHandlersTest.as'
        'scripts/类定义/org/flashNight/arki/component/Buff/BuffManager.as'
        'scripts/类定义/org/flashNight/arki/component/Damage/DamageCalculator.as'
        'scripts/类定义/org/flashNight/arki/unit/Action/Regeneration/HealApplier.as'
    )
    ExpectedTracePatterns=@('(?m)^HuofengStandardDamage Complete\r?$','(?m)^\[HuofengContractTest\] [1-9][0-9]* passed, 0 failed\r?$','(?m)^HuofengContractTest Complete\r?$')
    SuccessSummary='Huofeng native damage pipeline, typed heat labels, read-only Buff status, HP and paid revival contracts'
    TimeoutSeconds=$TimeoutSeconds
    SkipCompile=$SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @focusedRun
