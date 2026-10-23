[CmdletBinding()]
param(
    [ValidateRange(1, 3600)][int]$TimeoutSeconds = 360,
    [switch]$SkipCompile
)
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'test-runners\run-focused-testloader.ps1') `
    -DomainId 'player-stat-refresh' `
    -TemplateRelativePath 'scripts\test-runners\player-stat-refresh\TestLoader.as.template' `
    -SuiteRelativePaths @('scripts\类定义\org\flashNight\arki\ui\MeridianGetterRegistrationTest.as', 'scripts\类定义\org\flashNight\neur\Server\test\SaveManagerTest.as', 'scripts\类定义\org\flashNight\arki\item\itemCollection\EquipmentInventoryTest.as', 'scripts\类定义\org\flashNight\arki\item\InventoryPanelServiceTest.as', 'scripts\类定义\org\flashNight\arki\item\CharacterBuildTransactionSpikeTest.as', 'scripts\类定义\org\flashNight\arki\unit\UnitComponent\Initializer\test\RuntimeEquipmentProjectionTest.as', 'scripts\类定义\org\flashNight\arki\item\CharacterBuildServiceTest.as', 'scripts\类定义\org\flashNight\arki\unit\PlayerInfoProviderTest.as', 'scripts\类定义\org\flashNight\arki\unit\PlayerStatProjectionTest.as', 'scripts\类定义\org\flashNight\arki\ui\MeridianPanelServiceTest.as', 'scripts\类定义\org\flashNight\arki\unit\PlayerStatRefreshCoordinatorTest.as', 'scripts\类定义\org\flashNight\arki\unit\PlayerStatProductionAdapterTest.as', 'scripts\类定义\org\flashNight\arki\unit\PlayerStatLifecycleTest.as') `
    -SuiteFqns @('org.flashNight.arki.ui.MeridianGetterRegistrationTest', 'org.flashNight.neur.Server.test.SaveManagerTest', 'org.flashNight.arki.item.itemCollection.EquipmentInventoryTest', 'org.flashNight.arki.item.InventoryPanelServiceTest', 'org.flashNight.arki.item.CharacterBuildTransactionSpikeTest', 'org.flashNight.arki.unit.UnitComponent.Initializer.test.RuntimeEquipmentProjectionTest', 'org.flashNight.arki.item.CharacterBuildServiceTest', 'org.flashNight.arki.unit.PlayerInfoProviderTest', 'org.flashNight.arki.unit.PlayerStatProjectionTest', 'org.flashNight.arki.ui.MeridianPanelServiceTest', 'org.flashNight.arki.unit.PlayerStatRefreshCoordinatorTest', 'org.flashNight.arki.unit.PlayerStatProductionAdapterTest', 'org.flashNight.arki.unit.PlayerStatLifecycleTest') `
    -AdditionalAsRelativePaths @(
        'scripts\类定义\org\flashNight\arki\unit\UnitComponent\Initializer\DressupInitializer.as',
        'scripts\类定义\org\flashNight\arki\unit\Action\Regeneration\HealApplier.as',
        'scripts\类定义\org\flashNight\arki\unit\Action\Regeneration\HealApplierTest.as'
    ) `
    -ExpectedTracePatterns @(
        '(?m)^MeridianGetterRegistrationTest Tests Passed: [1-9][0-9]*\r?$',
        '(?m)^MeridianGetterRegistrationTest Tests Failed: 0\r?$',
        '(?m)^===== HealApplier 汇总: run=(?<healPassed>[1-9][0-9]*) pass=\k<healPassed> fail=0 =====\r?$',
        '(?m)^========== SaveManagerTest END: (?<savePassed>[1-9][0-9]*)/\k<savePassed> passed, 0 failed ==========\r?$',
        '(?m)^EquipmentInventoryTest Tests Passed: [1-9][0-9]*\r?$',
        '(?m)^EquipmentInventoryTest Tests Failed: 0\r?$',
        '(?m)^InventoryPanelServiceTest Tests Passed: [1-9][0-9]*\r?$',
        '(?m)^InventoryPanelServiceTest Tests Failed: 0\r?$',
        '(?m)^CharacterBuildTransactionSpikeTest Tests Passed: [1-9][0-9]*\r?$',
        '(?m)^CharacterBuildTransactionSpikeTest Tests Failed: 0\r?$',
        '(?m)^RuntimeEquipmentProjectionTest Tests Passed: [1-9][0-9]*\r?$',
        '(?m)^RuntimeEquipmentProjectionTest Tests Failed: 0\r?$',
        '(?m)^CharacterBuildServiceTest Tests Passed: [1-9][0-9]*\r?$',
        '(?m)^CharacterBuildServiceTest Tests Failed: 0\r?$',
        '(?m)^PlayerInfoProviderTest Tests Passed: [1-9][0-9]*\r?$',
        '(?m)^PlayerInfoProviderTest Tests Failed: 0\r?$',
        '(?m)^StatInventoryInheritanceReady: function:function:function\r?$',
        '(?m)^PlayerStatProjectionTest Tests Passed: [1-9][0-9]*\r?$',
        '(?m)^PlayerStatProjectionTest Tests Failed: 0\r?$',
        '(?m)^MeridianPanelServiceTest Tests Passed: [1-9][0-9]*\r?$',
        '(?m)^MeridianPanelServiceTest Tests Failed: 0\r?$',
        '(?m)^PlayerStatRefreshCoordinatorTest Tests Passed: [1-9][0-9]*\r?$',
        '(?m)^PlayerStatRefreshCoordinatorTest Tests Failed: 0\r?$',
        '(?m)^PlayerStatProductionAdapterTest Tests Passed: [1-9][0-9]*\r?$',
        '(?m)^PlayerStatProductionAdapterTest Tests Failed: 0\r?$',
        '(?m)^PlayerStatLifecycleTest Tests Passed: [1-9][0-9]*\r?$',
        '(?m)^PlayerStatLifecycleTest Tests Failed: 0\r?$'
    ) `
    -SuccessSummary 'player stat source and projection assertions completed; consult evidence mode' `
    -TimeoutSeconds $TimeoutSeconds -SkipCompile:$SkipCompile
