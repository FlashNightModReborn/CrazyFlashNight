[CmdletBinding()]
param(
    [ValidateRange(1, 3600)]
    [int]$TimeoutSeconds = 240,
    [switch]$SkipCompile
)

$ErrorActionPreference = 'Stop'
$commonRunner = Join-Path $PSScriptRoot 'test-runners\run-focused-testloader.ps1'
$projectDir = Split-Path -Parent $PSScriptRoot
$inventoryPanelSource = Get-Content -LiteralPath (
    Join-Path $projectDir `
        'scripts\类定义\org\flashNight\arki\item\InventoryPanelService.as'
) -Raw -Encoding UTF8
$characterBuildSource = Get-Content -LiteralPath (
    Join-Path $projectDir `
        'scripts\类定义\org\flashNight\arki\item\CharacterBuildService.as'
) -Raw -Encoding UTF8
$requestOpenBody = [regex]::Match(
    $inventoryPanelSource,
    'public static function requestOpenWorkbench\(params:Object\):Boolean \{[\s\S]*?private static function executeSnapshot'
).Value
$buildAdmission = [regex]::Match(
    $inventoryPanelSource,
    'if \(view == "build"\) \{[\s\S]*?\}\s*else if'
).Value
$buildSources = [regex]::Matches(
    $buildAdmission,
    'source\s*!=\s*"([^"]+)"'
) | ForEach-Object { $_.Groups[1].Value }
$probeIndex = $requestOpenBody.IndexOf(
    'CharacterBuildService')
$sendIndex = $requestOpenBody.IndexOf(
    'sendSocketMessage')
if (($buildAdmission -notmatch 'profile\s*!=\s*"battlebox"') -or
        (@($buildSources).Count -ne 2) -or
        ((@($buildSources | Sort-Object) -join '|') -ne
            'agent_control|nativehud_equipment') -or
        ($buildAdmission -notmatch
            'CharacterBuildService[\s\S]{0,120}\.canOpenPanel\(\)') -or
        ($probeIndex -lt 0) -or ($sendIndex -le $probeIndex) -or
        ($characterBuildSource -notmatch
            'public static function canOpenPanel\(\):Boolean')) {
    throw 'Build admission must remain exact, call the read-only CharacterBuild readiness probe, and fail before panel_request send.'
}
$focusedRun = @{
    DomainId = 'item-panels'
    TemplateRelativePath = 'scripts\test-runners\item-panels\TestLoader.as.template'
    SuiteRelativePaths = @(
        'scripts\类定义\org\flashNight\arki\item\itemCollection\EquipmentInventoryTest.as'
        'scripts\类定义\org\flashNight\arki\item\NpcShopPanelServiceTest.as'
        'scripts\类定义\org\flashNight\arki\item\InventoryPanelServiceTest.as'
        'scripts\类定义\org\flashNight\arki\item\CraftingPanelServiceTest.as'
    )
    SuiteFqns = @(
        'org.flashNight.arki.item.itemCollection.EquipmentInventoryTest'
        'org.flashNight.arki.item.NpcShopPanelServiceTest'
        'org.flashNight.arki.item.InventoryPanelServiceTest'
        'org.flashNight.arki.item.CraftingPanelServiceTest'
    )
    AdditionalAsRelativePaths = @(
        'scripts\逻辑系统分区\商店系统_兼容.as'
    )
    ExpectedTracePatterns = @(
        '(?m)^EquipmentInventoryTest Tests Passed: 28\r?$'
        '(?m)^EquipmentInventoryTest Tests Failed: 0\r?$'
        '(?m)^NpcShopPanelServiceTest Tests Passed: 46\r?$'
        '(?m)^NpcShopPanelServiceTest Tests Failed: 0\r?$'
        '(?m)^InventoryPanelServiceTest Tests Passed: 138\r?$'
        '(?m)^InventoryPanelServiceTest Tests Failed: 0\r?$'
        '(?m)^CraftingPanelServiceTest Tests Passed: 27\r?$'
        '(?m)^CraftingPanelServiceTest Tests Failed: 0\r?$'
    )
    SuccessSummary = 'EquipmentInventory 28/28, NPC 46/46, Inventory 138/138, Crafting 27/27'
    TimeoutSeconds = $TimeoutSeconds
    SkipCompile = $SkipCompile
}
& $commonRunner @focusedRun
