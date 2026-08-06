[CmdletBinding()]
param(
    [ValidateRange(1, 3600)]
    [int]$TimeoutSeconds = 240,
    [switch]$SkipCompile
)

$ErrorActionPreference = 'Stop'
$commonRunner = Join-Path $PSScriptRoot 'test-runners\run-focused-testloader.ps1'
$projectDir = Split-Path -Parent $PSScriptRoot

function Get-RepoText([string]$RelativePath) {
    return Get-Content -LiteralPath (Join-Path $projectDir $RelativePath) `
        -Raw -Encoding UTF8
}

$tuningSource = Get-RepoText `
    'scripts\类定义\org\flashNight\arki\item\EquipmentTuningService.as'
$equipmentSource = Get-RepoText `
    'scripts\类定义\org\flashNight\arki\item\itemCollection\EquipmentInventory.as'
$characterSource = Get-RepoText `
    'scripts\类定义\org\flashNight\arki\item\CharacterBuildService.as'
$committedSideEffectsCount = [regex]::Matches(
    $tuningSource,
    'publishCommittedWornSideEffects\s*\('
).Count
$loadoutAllowlist = [regex]::Match(
    $tuningSource,
    'private static var _loadoutAllowedOperations:Object = \{[\s\S]*?\};'
).Value
if (($loadoutAllowlist -match 'convert') -or
        ($loadoutAllowlist -notmatch 'enhance:true') -or
        ($loadoutAllowlist -notmatch 'install_tier:true') -or
        ($loadoutAllowlist -notmatch 'install_mod:true') -or
        ($loadoutAllowlist -notmatch 'replace_mod:true') -or
        ($loadoutAllowlist -notmatch 'detach_mod:true') -or
        ($loadoutAllowlist -notmatch 'detach_all_mods:true') -or
        ($tuningSource -notmatch
            'sourceKind:"loadout"[\s\S]{0,220}expectedLoadoutRevision') -or
        ($tuningSource -notmatch 'inventorySnapshots:\[\]') -or
        ($tuningSource -notmatch
            'commitWornTuningSynchronization\s*\(') -or
        ($committedSideEffectsCount -ne 4)) {
    throw 'Worn tuning must keep its exact loadout source, six-operation allowlist, post snapshot, and empty backpack projection.'
}
if (($equipmentSource -notmatch
        'canApplyWornValueTransaction\s*\(') -or
        ($equipmentSource -notmatch
            'transactionApplyWornValueChanges\s*\(') -or
        ($equipmentSource -notmatch
            'rollbackWornValueTransaction\s*\(') -or
        ($equipmentSource -notmatch
            'publishWornValueTransaction\s*\(') -or
        ($characterSource -notmatch
            'resolveWornTuningSource\s*\(') -or
        ($characterSource -notmatch
            'authorityObserved\s*=\s*true')) {
    throw 'Worn tuning transaction/hook rollback boundary is incomplete.'
}

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
        '(?m)^EquipmentTuningServiceTest Tests Passed: 60\r?$'
        '(?m)^EquipmentTuningServiceTest Tests Failed: 0\r?$'
        '(?m)^InventoryPanelServiceTest Tests Passed: 147\r?$'
        '(?m)^InventoryPanelServiceTest Tests Failed: 0\r?$'
    )
    SuccessSummary = 'Equipment 60/60, Inventory 147/147'
    TimeoutSeconds = $TimeoutSeconds
    SkipCompile = $SkipCompile
}
& $commonRunner @focusedRun
