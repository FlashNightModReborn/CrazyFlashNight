[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=600,[switch]$SkipCompile,[switch]$ReferencesOnly)
$focusedRun=@{
    DomainId='dead-hand'
    TemplateRelativePath='scripts/test-runners/dead-hand/TestLoader.as.template'
    SuiteRelativePaths=@(
        'scripts/类定义/org/flashNight/arki/unit/UnitComponent/Dressup/EquipmentUtil/DeadHandControllerTest.as'
        'scripts/类定义/org/flashNight/arki/unit/UnitComponent/Dressup/EquipmentUtil/DeadHandVisualTest.as'
        'scripts/类定义/org/flashNight/arki/unit/UnitComponent/Dressup/DressupReferenceManagerTest.as'
    )
    SuiteFqns=@(
        'org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.DeadHandControllerTest'
        'org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.DeadHandVisualTest'
        'org.flashNight.arki.unit.UnitComponent.Dressup.DressupReferenceManagerTest'
    )
    AdditionalAsRelativePaths=@(
        'scripts/逻辑/装备函数/死者之手.as'
        'scripts/逻辑/功能函数/功能函数_fs_兵器攻击检测.as'
        'scripts/类定义/org/flashNight/arki/unit/UnitComponent/Dressup/EquipmentUtil/DeadHandController.as'
        'scripts/类定义/org/flashNight/arki/unit/UnitComponent/Dressup/EquipmentUtil/DeadHandTuning.as'
        'scripts/类定义/org/flashNight/arki/unit/UnitComponent/Dressup/EquipmentUtil/DeadHandVisual.as'
        'scripts/类定义/org/flashNight/arki/unit/UnitComponent/Dressup/DressupReferenceManager.as'
    )
    ExpectedTracePatterns=@(
        '(?m)^DeadHandControllerTest Tests Passed: 55\r?$'
        '(?m)^DeadHandControllerTest Tests Failed: 0\r?$'
        '(?m)^\[DEAD_HAND_ATTACK\] mode=兵器 energy=105 stage=2 blade=true gun=false grip=\d+ board=16\r?$'
        '(?m)^\[DEAD_HAND_ATTACK\] mode=长枪 energy=105 stage=2 blade=false gun=true grip=46 board=16\r?$'
        '(?m)^DeadHandVisualTest Tests Passed: 52\r?$'
        '(?m)^DeadHandVisualTest Tests Failed: 0\r?$'
        '(?m)^Result: (?<dressup>[1-9][0-9]*)/\k<dressup> passed, 0 failed  \([0-9]+ ms\)\r?$'
    )
    SuccessSummary='Dead Hand forms, overload and real MovieClip pistol/dual-pistol placement isolation and cleanup'
    TimeoutSeconds=$TimeoutSeconds
    SkipCompile=$SkipCompile
}
if ($ReferencesOnly) {
    $focusedRun.TemplateRelativePath='scripts/test-runners/dead-hand/ReferencesLoader.as.template'
    $focusedRun.SuiteRelativePaths=@('scripts/类定义/org/flashNight/arki/unit/UnitComponent/Dressup/DressupReferenceManagerTest.as')
    $focusedRun.SuiteFqns=@('org.flashNight.arki.unit.UnitComponent.Dressup.DressupReferenceManagerTest')
    $focusedRun.AdditionalAsRelativePaths=@('scripts/类定义/org/flashNight/arki/unit/UnitComponent/Dressup/DressupReferenceManager.as')
    $focusedRun.ExpectedTracePatterns=@('(?m)^Result: 127/127 passed, 0 failed  \([0-9]+ ms\)\r?$')
    $focusedRun.SuccessSummary='Dressup placement identity, same-path slot replacement and stale refresh isolation'
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @focusedRun
