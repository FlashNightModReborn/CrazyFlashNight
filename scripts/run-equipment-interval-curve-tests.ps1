[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=300,[switch]$SkipCompile)
$focusedRun=@{
    DomainId='equipment-interval-curve'
    TemplateRelativePath='scripts/test-runners/equipment-interval-curve/TestLoader.as.template'
    SuiteRelativePaths=@('scripts/类定义/org/flashNight/arki/item/equipment/EquipmentIntervalCurveTest.as')
    SuiteFqns=@('org.flashNight.arki.item.equipment.EquipmentIntervalCurveTest')
    AdditionalAsRelativePaths=@('scripts/类定义/org/flashNight/arki/item/equipment/PropertyOperators.as',
        'scripts/类定义/org/flashNight/gesh/tooltip/builder/UseSwitchStatsBuilder.as')
    ExpectedTracePatterns=@(
        '(?m)^EquipmentIntervalCurveTest Phases: operator,data,composition,presentation,bounds\r?$',
        '(?m)^--- EquipmentIntervalCurveTest: (?<count>[1-9][0-9]*)/\k<count> passed, 0 failed ---\r?$')
    SuccessSummary='真实XML、柔性间隔、机枪独立分支、乘区组合、互斥、说明与射速预览'
    TimeoutSeconds=$TimeoutSeconds
    SkipCompile=$SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @focusedRun
