[CmdletBinding()]
param([ValidateRange(1, 3600)][int]$TimeoutSeconds = 240, [switch]$SkipCompile)

$focusedRun = @{
    DomainId = 'pilebunker-m7'
    TemplateRelativePath = 'scripts\test-runners\pilebunker-m7\TestLoader.as.template'
    SuiteRelativePaths = @(
        'scripts\类定义\org\flashNight\arki\unit\UnitComponent\Dressup\EquipmentUtil\PileBunkerClassicTest.as',
        'scripts\类定义\org\flashNight\arki\unit\UnitComponent\Dressup\EquipmentUtil\PileBunkerM7Test.as')
    SuiteFqns = @(
        'org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.PileBunkerClassicTest',
        'org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.PileBunkerM7Test')
    AdditionalAsRelativePaths = @(
        'scripts\逻辑\装备函数\火药燃气液压打桩机.as',
        'scripts\类定义\org\flashNight\arki\unit\UnitComponent\Dressup\EquipmentUtil\PileBunkerClassicController.as',
        'scripts\类定义\org\flashNight\arki\unit\UnitComponent\Dressup\EquipmentUtil\PileBunkerMeleeProjection.as',
        'scripts\逻辑\装备函数\打桩机M7.as',
        'scripts\逻辑\单位函数\单位函数_fs_aka_玩家模板迁移.as',
        'scripts\类定义\org\flashNight\arki\unit\Action\Skill\WeaponSkillInputService.as',
        'scripts\类定义\org\flashNight\arki\unit\Action\Shoot\LongGunSubWeaponCore.as',
        'scripts\类定义\org\flashNight\arki\bullet\BulletComponent\Queue\BulletHitEffectRegistry.as',
        'scripts\逻辑\单位函数\单位函数_fs_装备生命周期配置.as',
        'scripts\类定义\org\flashNight\arki\unit\UnitComponent\Dressup\EquipmentUtil\NamedPosePlayer.as',
        'scripts\类定义\org\flashNight\arki\unit\UnitComponent\Dressup\EquipmentUtil\NamedPoseCodec.as',
        'scripts\类定义\org\flashNight\arki\unit\UnitComponent\Dressup\EquipmentUtil\PileBunkerM7Controller.as',
        'scripts\类定义\org\flashNight\arki\unit\UnitComponent\Dressup\EquipmentUtil\NamedPoseDataStore.as'
    )
    ExpectedTracePatterns = @(
        '(?m)^PileBunkerClassicTest Tests Passed: [1-9][0-9]+\r?$',
        '(?m)^PileBunkerClassicTest Tests Failed: 0\r?$',
        '(?m)^PileBunkerM7Test Tests Passed: [1-9][0-9]+\r?$',
        '(?m)^PileBunkerM7Test Tests Failed: 0\r?$'
    )
    SuccessSummary = '原版与重锤打桩机真实素材、近战及三路玩法回归'
    TimeoutSeconds = $TimeoutSeconds
    AsyncBehaviorTimeoutSeconds = 45
    SkipCompile = $SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners\run-focused-testloader.ps1') @focusedRun
