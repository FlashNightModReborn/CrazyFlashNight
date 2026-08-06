[CmdletBinding()]
param(
    [ValidateRange(1, 3600)]
    [int]$TimeoutSeconds = 240,
    [ValidateSet('All', 'Shared', 'Crafting', 'Npc')]
    [string]$Suite = 'All',
    [switch]$SkipCompile
)

$ErrorActionPreference = 'Stop'
$commonRunner = Join-Path $PSScriptRoot 'test-runners\run-focused-testloader.ps1'
$projectDir = Split-Path -Parent $PSScriptRoot
if ($Suite -eq 'All' -or $Suite -eq 'Shared') {
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
}
$suiteConfigs = @{
    All = @{
        DomainId = 'item-panels'
        Template = 'scripts\test-runners\item-panels\TestLoader.as.template'
        Paths = @(
            'scripts\类定义\org\flashNight\arki\item\itemCollection\EquipmentInventoryTest.as'
            'scripts\类定义\org\flashNight\arki\item\NpcShopPanelServiceTest.as'
            'scripts\类定义\org\flashNight\arki\item\InventoryPanelServiceTest.as'
            'scripts\类定义\org\flashNight\arki\item\CraftingPanelServiceTest.as'
        )
        Fqns = @(
            'org.flashNight.arki.item.itemCollection.EquipmentInventoryTest'
            'org.flashNight.arki.item.NpcShopPanelServiceTest'
            'org.flashNight.arki.item.InventoryPanelServiceTest'
            'org.flashNight.arki.item.CraftingPanelServiceTest'
        )
        Additional = @('scripts\逻辑系统分区\商店系统_兼容.as')
        Patterns = @(
            '(?m)^EquipmentInventoryTest Tests Passed: 28\r?$'
            '(?m)^EquipmentInventoryTest Tests Failed: 0\r?$'
            '(?m)^InventoryPanelServiceTest Tests Passed: 147\r?$'
            '(?m)^InventoryPanelServiceTest Tests Failed: 0\r?$'
            '(?m)^CraftingPanelServiceTest Tests Passed: 49\r?$'
            '(?m)^CraftingPanelServiceTest Tests Failed: 0\r?$'
            '(?m)^NpcShopPanelServiceTest Tests Passed: 47\r?$'
            '(?m)^NpcShopPanelServiceTest Tests Failed: 0\r?$'
        )
        Summary = 'EquipmentInventory 28/28, Inventory 147/147, Crafting 49/49, NPC 47/47'
    }
    Shared = @{
        DomainId = 'item-panels-shared'
        Template = 'scripts\test-runners\item-panels\TestLoader.shared.as.template'
        Paths = @(
            'scripts\类定义\org\flashNight\arki\item\itemCollection\EquipmentInventoryTest.as'
            'scripts\类定义\org\flashNight\arki\item\InventoryPanelServiceTest.as'
        )
        Fqns = @(
            'org.flashNight.arki.item.itemCollection.EquipmentInventoryTest'
            'org.flashNight.arki.item.InventoryPanelServiceTest'
        )
        Additional = @('scripts\逻辑系统分区\商店系统_兼容.as')
        Patterns = @(
            '(?m)^EquipmentInventoryTest Tests Passed: 28\r?$'
            '(?m)^EquipmentInventoryTest Tests Failed: 0\r?$'
            '(?m)^InventoryPanelServiceTest Tests Passed: 147\r?$'
            '(?m)^InventoryPanelServiceTest Tests Failed: 0\r?$'
        )
        Summary = 'EquipmentInventory 28/28, Inventory 147/147'
    }
    Crafting = @{
        DomainId = 'item-panels-crafting'
        Template = 'scripts\test-runners\item-panels\TestLoader.crafting.as.template'
        Paths = @('scripts\类定义\org\flashNight\arki\item\CraftingPanelServiceTest.as')
        Fqns = @('org.flashNight.arki.item.CraftingPanelServiceTest')
        Additional = @('scripts\逻辑系统分区\商店系统_兼容.as')
        Patterns = @(
            '(?m)^CraftingPanelServiceTest Tests Passed: 49\r?$'
            '(?m)^CraftingPanelServiceTest Tests Failed: 0\r?$'
        )
        Summary = 'Crafting 49/49'
    }
    Npc = @{
        DomainId = 'item-panels-npc'
        Template = 'scripts\test-runners\item-panels\TestLoader.npc.as.template'
        Paths = @('scripts\类定义\org\flashNight\arki\item\NpcShopPanelServiceTest.as')
        Fqns = @('org.flashNight.arki.item.NpcShopPanelServiceTest')
        Additional = @('scripts\逻辑系统分区\商店系统_兼容.as')
        Patterns = @(
            '(?m)^NpcShopPanelServiceTest Tests Passed: 47\r?$'
            '(?m)^NpcShopPanelServiceTest Tests Failed: 0\r?$'
        )
        Summary = 'NPC 47/47'
    }
}
$selected = $suiteConfigs[$Suite]
$focusedRun = @{
    DomainId = $selected.DomainId
    TemplateRelativePath = $selected.Template
    SuiteRelativePaths = $selected.Paths
    SuiteFqns = $selected.Fqns
    AdditionalAsRelativePaths = $selected.Additional
    ExpectedTracePatterns = $selected.Patterns
    SuccessSummary = $selected.Summary
    TimeoutSeconds = $TimeoutSeconds
    SkipCompile = $SkipCompile
}
& $commonRunner @focusedRun
