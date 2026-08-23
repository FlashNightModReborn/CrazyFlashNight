[CmdletBinding()]
param(
    [ValidateRange(1, 3600)]
    [int]$TimeoutSeconds = 240,
    [switch]$SkipCompile
)

$ErrorActionPreference = 'Stop'
$commonRunner = Join-Path $PSScriptRoot 'test-runners\run-focused-testloader.ps1'

$focusedRun = @{
    DomainId = 'managed-longgun'
    TemplateRelativePath = 'scripts\test-runners\managed-longgun\TestLoader.as.template'
    SuiteRelativePaths = @(
        'scripts\类定义\org\flashNight\arki\merc\ManagedLongGunServiceTest.as'
        'scripts\类定义\org\flashNight\arki\unit\UnitComponent\Dressup\DressupReferenceManagerTest.as'
        'scripts\类定义\org\flashNight\neur\Event\EventBusTest.as'
    )
    SuiteFqns = @(
        'org.flashNight.arki.merc.ManagedLongGunServiceTest'
        'org.flashNight.arki.unit.UnitComponent.Dressup.DressupReferenceManagerTest'
        'org.flashNight.neur.Event.EventBusTest'
    )
    AdditionalAsRelativePaths = @(
        'scripts\类定义\org\flashNight\arki\merc\ManagedLongGunService.as'
        'scripts\类定义\org\flashNight\arki\unit\Action\Shoot\ShootInitCore.as'
        'scripts\类定义\org\flashNight\arki\unit\UnitComponent\Initializer\DressupInitializer.as'
        'scripts\类定义\org\flashNight\arki\unit\UnitComponent\Dressup\EquipmentUtil\PlacementVisual.as'
        'scripts\逻辑\装备函数\M134.as'
    )
    ExpectedTracePatterns = @(
        '(?m)^ManagedLongGunServiceTest Tests Passed: 68\r?$'
        '(?m)^ManagedLongGunServiceTest Tests Failed: 0\r?$'
        '(?m)^Result: (?<dressup>[1-9][0-9]*)/\k<dressup> passed, 0 failed  \([0-9]+ ms\)\r?$'
        '(?m)^All tests completed\.\r?$'
    )
    SuccessSummary = 'ManagedLongGunServiceTest 68/68 + DressupReferenceManagerTest + EventBusTest all passed'
    TimeoutSeconds = $TimeoutSeconds
    SkipCompile = $SkipCompile
}
& $commonRunner @focusedRun
