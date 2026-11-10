[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=300,[switch]$SkipCompile)
$focusedRun=@{
    DomainId='dead-hand'
    TemplateRelativePath='scripts/test-runners/dead-hand/TestLoader.as.template'
    SuiteRelativePaths=@('scripts/类定义/org/flashNight/arki/unit/UnitComponent/Dressup/EquipmentUtil/DeadHandControllerTest.as')
    SuiteFqns=@('org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.DeadHandControllerTest')
    AdditionalAsRelativePaths=@(
        'scripts/逻辑/装备函数/死者之手.as'
        'scripts/类定义/org/flashNight/arki/unit/UnitComponent/Dressup/EquipmentUtil/DeadHandController.as'
        'scripts/类定义/org/flashNight/arki/unit/UnitComponent/Dressup/EquipmentUtil/DeadHandTuning.as'
    )
    ExpectedTracePatterns=@('(?m)^DeadHandControllerTest Tests Passed: 45\r?$','(?m)^DeadHandControllerTest Tests Failed: 0\r?$')
    SuccessSummary='Dead Hand forms, gun-slot reservation, transforms, overload, cooldown, interruption and buff cleanup'
    TimeoutSeconds=$TimeoutSeconds
    SkipCompile=$SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @focusedRun
