[CmdletBinding()]
param(
    [ValidateRange(1, 3600)]
    [int]$TimeoutSeconds = 240,
    [switch]$SkipCompile
)

$ErrorActionPreference = 'Stop'
$commonRunner = Join-Path $PSScriptRoot 'test-runners\run-focused-testloader.ps1'
$focusedRun = @{
    DomainId = 'equipment-tuning'
    TemplateRelativePath = 'scripts\test-runners\equipment-tuning\TestLoader.as.template'
    SuiteRelativePaths = @(
        'scripts\类定义\org\flashNight\arki\item\EquipmentTuningServiceTest.as'
        'scripts\类定义\org\flashNight\arki\item\InventoryPanelServiceTest.as'
    )
    SuiteFqns = @(
        'org.flashNight.arki.item.EquipmentTuningServiceTest'
        'org.flashNight.arki.item.InventoryPanelServiceTest'
    )
    ExpectedTracePatterns = @(
        '(?m)^EquipmentTuningServiceTest Tests Passed: 39\r?$'
        '(?m)^EquipmentTuningServiceTest Tests Failed: 0\r?$'
        '(?m)^InventoryPanelServiceTest Tests Passed: 131\r?$'
        '(?m)^InventoryPanelServiceTest Tests Failed: 0\r?$'
    )
    SuccessSummary = 'Equipment 39/39, Inventory 131/131'
    TimeoutSeconds = $TimeoutSeconds
    SkipCompile = $SkipCompile
}
& $commonRunner @focusedRun
