[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=360,[switch]$SkipCompile)
$focusedRun=@{
    DomainId='shield-rush'
    TemplateRelativePath='scripts/test-runners/shield-rush/TestLoader.as.template'
    SuiteRelativePaths=@('scripts/类定义/org/flashNight/arki/unit/Action/Skill/ShieldRushTest.as','scripts/类定义/org/flashNight/arki/render/EquipmentLightTest.as')
    SuiteFqns=@('org.flashNight.arki.unit.Action.Skill.ShieldRushTest','org.flashNight.arki.render.EquipmentLightTest')
    AdditionalAsRelativePaths=@('scripts/逻辑/装备函数/装备光源.as','scripts/类定义/org/flashNight/arki/unit/Action/Skill/SheriffShieldRush.as','scripts/逻辑/单位函数/单位函数_雾人_aka_fs_主动战技.as','scripts/类定义/org/flashNight/arki/render/EquipmentLightBridge.as','scripts/类定义/org/flashNight/arki/unit/UnitComponent/Dressup/EquipmentUtil/EquipmentLightController.as')
    ExpectedTracePatterns=@('(?m)^ShieldRushTest Case: 24\r?$','(?m)^ShieldRushTest Tests Passed: [1-9][0-9]{2,}\r?$','(?m)^ShieldRushTest Tests Failed: 0\r?$','(?m)^ShieldRushTest Lit Frames Checked: [1-9][0-9]{2,}\r?$','(?m)^EquipmentLightTest Tests Passed: 34\r?$','(?m)^EquipmentLightTest Tests Failed: 0\r?$')
    SuccessSummary='Real shotgun XML, F input, complete charge-tier run loops, all-phase facing and lane steering, swept impacts, temporary shield and scoped cleanup'
    AsyncBehaviorTimeoutSeconds=600
    TimeoutSeconds=$TimeoutSeconds
    SkipCompile=$SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @focusedRun
