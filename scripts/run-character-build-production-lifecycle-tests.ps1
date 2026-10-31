[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=600,[switch]$SkipCompile)
$ErrorActionPreference='Stop'
$focusedRun=@{
    DomainId='character-build-production-lifecycle'
    TemplateRelativePath='scripts/test-runners/character-build-production-lifecycle/TestLoader.as.template'
    SuiteRelativePaths=@('scripts/类定义/org/flashNight/arki/item/CharacterBuildProductionLifecycleTest.as')
    SuiteFqns=@('org.flashNight.arki.item.CharacterBuildProductionLifecycleTest')
    AdditionalAsRelativePaths=@(
        'scripts/类定义/org/flashNight/arki/item/CharacterBuildService.as'
        'scripts/类定义/org/flashNight/arki/item/CharacterBuildServiceTest.as'
        'scripts/类定义/org/flashNight/arki/item/CharacterBuildHpRecoveryTest.as'
        'scripts/类定义/org/flashNight/arki/unit/PlayerStatRefreshCoordinator.as'
        'scripts/类定义/org/flashNight/arki/unit/PlayerStatProjectionTest.as'
        'scripts/类定义/org/flashNight/arki/unit/PlayerStatItemFixtures.as'
        'scripts/类定义/org/flashNight/arki/unit/UnitComponent/Initializer/StaticInitializer.as'
        'scripts/类定义/org/flashNight/arki/unit/UnitComponent/Initializer/DressupInitializer.as'
        'scripts/逻辑/单位函数/单位函数_fs_aka_玩家模板迁移.as'
        'scripts/逻辑/单位函数/单位函数_fs_装备生命周期配置.as'
    )
    ExpectedTracePatterns=@(
        '(?m)^CharacterBuildProductionLifecycleTest Tests Passed: [1-9][0-9]*\r?$'
        '(?m)^CharacterBuildProductionLifecycleTest Tests Failed: 0\r?$'
        '(?m)^CHARACTER_PRODUCTION_LIFECYCLE .*"label":"finalize"'
        '(?m)^CHARACTER_PRODUCTION_LIFECYCLE .*"label":"mode_wait_ready"'
        '(?m)^CHARACTER_PRODUCTION_LIFECYCLE .*"label":"mode_wait_timeout"'
        '(?m)^CHARACTER_PRODUCTION_LIFECYCLE .*"label":"mode_wait_stale"'
        '(?m)^CHARACTER_PRODUCTION_LIFECYCLE .*"label":"blood_sword_hp_floor"'
        '(?m)^CHARACTER_PRODUCTION_LIFECYCLE .*"label":"numeric_correction_unequip"'
        '(?m)^CHARACTER_PRODUCTION_LIFECYCLE .*"label":"numeric_correction_swap"'
    )
    SuccessSummary='Real CharacterBuild owner and full player-template lifecycle with in-memory domain ports'
    TimeoutSeconds=$TimeoutSeconds
    SkipCompile=$SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @focusedRun
