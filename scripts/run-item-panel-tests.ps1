[CmdletBinding()]
param(
    [ValidateRange(1, 3600)]
    [int]$TimeoutSeconds = 240,
    [switch]$SkipCompile
)

$ErrorActionPreference = 'Stop'
$commonRunner = Join-Path $PSScriptRoot 'test-runners\run-focused-testloader.ps1'
$focusedRun = @{
    DomainId = 'item-panels'
    TemplateRelativePath = 'scripts\test-runners\item-panels\TestLoader.as.template'
    SuiteRelativePaths = @(
        'scripts\类定义\org\flashNight\arki\item\NpcShopPanelServiceTest.as'
        'scripts\类定义\org\flashNight\arki\item\InventoryPanelServiceTest.as'
        'scripts\类定义\org\flashNight\arki\item\CraftingPanelServiceTest.as'
    )
    SuiteFqns = @(
        'org.flashNight.arki.item.NpcShopPanelServiceTest'
        'org.flashNight.arki.item.InventoryPanelServiceTest'
        'org.flashNight.arki.item.CraftingPanelServiceTest'
    )
    AdditionalAsRelativePaths = @(
        'scripts\逻辑系统分区\商店系统_兼容.as'
    )
    ExpectedTracePatterns = @(
        '(?m)^NpcShopPanelServiceTest Tests Passed: 46\r?$'
        '(?m)^NpcShopPanelServiceTest Tests Failed: 0\r?$'
        '(?m)^InventoryPanelServiceTest Tests Passed: 131\r?$'
        '(?m)^InventoryPanelServiceTest Tests Failed: 0\r?$'
        '(?m)^CraftingPanelServiceTest Tests Passed: 27\r?$'
        '(?m)^CraftingPanelServiceTest Tests Failed: 0\r?$'
    )
    SuccessSummary = 'NPC 46/46, Inventory 131/131, Crafting 27/27'
    TimeoutSeconds = $TimeoutSeconds
    SkipCompile = $SkipCompile
}
& $commonRunner @focusedRun
