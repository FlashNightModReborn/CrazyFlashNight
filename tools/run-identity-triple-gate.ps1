[CmdletBinding()]
param(
    [switch]$CompileAs2,
    [switch]$BootstrapOnly
)

$ErrorActionPreference = 'Stop'

$toolsDir = $PSScriptRoot
$projectRoot = Split-Path -Parent $toolsDir
$launcherDir = Join-Path $projectRoot 'launcher'
$testsProject = Join-Path $launcherDir 'tests\Launcher.Tests.csproj'
$equipmentAs2Runner = Join-Path $projectRoot 'scripts\run-equipment-tuning-tests.ps1'
$kshopAs2Runner = Join-Path $projectRoot 'scripts\run-kshop-checkout-tests.ps1'
$itemPanelsAs2Runner = Join-Path $projectRoot 'scripts\run-item-panel-tests.ps1'
$characterAs2Runner = Join-Path $projectRoot 'scripts\run-character-build-tests.ps1'
$lootAs2Runner = Join-Path $projectRoot 'scripts\run-map-loot-tests.ps1'
$craftingReviewGateRoot = Join-Path $projectRoot 'tmp\identity-triple-gate'
$craftingReviewLeaf = 'crafting-product-review-' + [Guid]::NewGuid().ToString('N')
$craftingReviewTempRoot = Join-Path $craftingReviewGateRoot $craftingReviewLeaf
$craftingReviewRelativeRoot = Join-Path 'tmp\identity-triple-gate' $craftingReviewLeaf
$craftingReviewDataRelativePath = Join-Path $craftingReviewRelativeRoot 'review-data.json'
$craftingReviewCleanupArmed = $false

function Invoke-CheckedNode {
    param(
        [Parameter(Mandatory = $true)][string]$RelativeScript,
        [string[]]$Arguments = @()
    )

    $argumentSummary = if ($Arguments.Count -gt 0) { ' ' + ($Arguments -join ' ') } else { '' }
    Write-Host "[PG-IDENTITY-TRIPLE] node $RelativeScript$argumentSummary"
    & node (Join-Path $projectRoot $RelativeScript) @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "PG-IDENTITY-TRIPLE failed at $RelativeScript (exit=$LASTEXITCODE)"
    }
}

function Invoke-CheckedAs2Runner {
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][string]$Runner,
        [string[]]$RunnerArguments = @()
    )

    Write-Host ('[PG-IDENTITY-TRIPLE] AS2 ' + $Label + ' ' +
        $(if ($CompileAs2) { 'fresh compile/trace' } else { 'tracked static/BOM gate' }))
    $arguments = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $Runner
    ) + $RunnerArguments
    if (-not $CompileAs2) { $arguments += '-SkipCompile' }
    & powershell @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "PG-IDENTITY-TRIPLE AS2 $Label failed (exit=$LASTEXITCODE)"
    }
    if ($CompileAs2) {
        Invoke-CheckedNode 'tools\swf-function-sizes.js' `
            @('scripts\TestLoader.swf', '--max', '60000', '--top', '15')
    }
}

function Invoke-CheckedHostTests {
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][string]$Filter
    )

    Write-Host "[PG-IDENTITY-TRIPLE] Host $Label"
    & $dotnetPath test $testsProject -c Release --no-restore --filter $Filter
    if ($LASTEXITCODE -ne 0) {
        throw "PG-IDENTITY-TRIPLE Host $Label failed (exit=$LASTEXITCODE)"
    }
}

function Write-DomainHeader {
    param([Parameter(Mandatory = $true)][string]$Label)
    Write-Host "[PG-IDENTITY-TRIPLE] ===== $Label ====="
}

if ($BootstrapOnly) {
    if (Test-Path -LiteralPath $craftingReviewTempRoot) {
        throw "PG-IDENTITY-TRIPLE bootstrap generated an existing path: $craftingReviewTempRoot"
    }
    Write-Host "[PG-IDENTITY-TRIPLE] PS bootstrap path: $craftingReviewRelativeRoot"
    Invoke-CheckedNode 'tools\test-crafting-product-review-cleanup.js'
    Write-Host 'PG-IDENTITY-TRIPLE bootstrap PASS (no domain tests executed)'
    return
}

Push-Location -LiteralPath $projectRoot
try {
    . (Join-Path $launcherDir 'resolve-dotnet.ps1')
    $dotnetPath = Resolve-Cf7Dotnet -ProjectRoot $projectRoot

    Write-DomainHeader 'cross-layer preflight'
    Invoke-CheckedNode 'tools\validate-panel-contracts.js'
    Invoke-CheckedNode 'tools\test-panel-contracts.js'
    Invoke-CheckedNode 'tools\validate-equipment-mod-ui.js'
    Invoke-CheckedNode 'tools\audit-web-item-icon-closure.js'
    Invoke-CheckedNode 'tools\test-workbench-canonical-presentation.js'

    Write-DomainHeader '1/5 shared leaf: Inventory + Character + Loot'
    Invoke-CheckedAs2Runner 'shared Inventory projection' $itemPanelsAs2Runner `
        @('-Suite', 'Shared')
    Invoke-CheckedAs2Runner 'Character Build' $characterAs2Runner
    Invoke-CheckedAs2Runner 'Loot' $lootAs2Runner
    Invoke-CheckedHostTests 'shared Inventory/Character/Loot' `
        'FullyQualifiedName~InventoryTaskTests|FullyQualifiedName~InventoryOwnerEnvelopeTests|FullyQualifiedName~CharacterBuildTaskTests|FullyQualifiedName~LootTaskTests|FullyQualifiedName~LootPanelCoordinatorTests'
    Invoke-CheckedNode 'tools\test-inventory-runtime.js'
    Invoke-CheckedNode 'tools\test-inventory-workbench-modules.js'
    Invoke-CheckedNode 'tools\test-inventory-workbench-preparation-menu.js'
    Invoke-CheckedNode 'tools\test-inventory-workbench-lazy-closure.js'
    Invoke-CheckedNode 'tools\test-character-build-session.js'
    Invoke-CheckedNode 'tools\test-character-build-facet-counts.js'
    Invoke-CheckedNode 'tools\test-character-build-projection.js'
    Invoke-CheckedNode 'tools\test-character-build-item-use.js'
    Invoke-CheckedNode 'tools\test-character-build-candidate-tooltip.js'
    Invoke-CheckedNode 'tools\test-character-build-candidate-tuning.js'
    Invoke-CheckedNode 'tools\test-character-build-tuning-capability.js'
    Invoke-CheckedNode 'tools\test-character-build-slot-transition.js'
    Invoke-CheckedNode 'tools\run-character-build-harness.js'
    Invoke-CheckedNode 'tools\run-character-build-workbench-harness.js'
    Invoke-CheckedNode 'launcher\web\modules\loot\dev\test-loot-state.js'
    Invoke-CheckedNode 'launcher\web\modules\loot\dev\run-harness.js'

    Write-DomainHeader '2/5 KShop'
    Invoke-CheckedAs2Runner 'KShop Checkout' $kshopAs2Runner
    Invoke-CheckedHostTests 'KShop' 'FullyQualifiedName~ShopTaskTests'
    Invoke-CheckedNode 'tools\test-kshop-presenters.js'
    Invoke-CheckedNode 'tools\run-kshop-harness.js'

    Write-DomainHeader '3/5 Crafting'
    Invoke-CheckedAs2Runner 'Crafting' $itemPanelsAs2Runner `
        @('-Suite', 'Crafting')
    Invoke-CheckedHostTests 'Crafting' 'FullyQualifiedName~CraftingTaskTests'
    Invoke-CheckedNode 'tools\test-crafting-runtime.js'
    Invoke-CheckedNode 'tools\test-crafting-inspector.js'
    Invoke-CheckedNode 'tools\test-crafting-product-review-cleanup.js'
    if (Test-Path -LiteralPath $craftingReviewTempRoot) {
        throw "PG-IDENTITY-TRIPLE isolated Crafting review path already exists: $craftingReviewTempRoot"
    }
    $craftingReviewCleanupArmed = $true
    Invoke-CheckedNode 'tools\build-crafting-product-review.js' `
        @('--sample', '--output-root', $craftingReviewRelativeRoot)
    Invoke-CheckedNode 'tools\test-crafting-product-review.js' `
        @('--review-data', $craftingReviewDataRelativePath)
    Invoke-CheckedNode 'tools\run-crafting-harness.js'

    Write-DomainHeader '4/5 NPC Shop'
    Invoke-CheckedAs2Runner 'NPC Shop' $itemPanelsAs2Runner `
        @('-Suite', 'Npc')
    Invoke-CheckedHostTests 'NPC Shop' 'FullyQualifiedName~NpcShopTaskTests'
    Invoke-CheckedNode 'tools\test-npcshop-secondary-pages.js'
    Invoke-CheckedNode 'tools\run-npcshop-harness.js'

    Write-DomainHeader '5/5 Equipment Tuning strong-domain reference'
    Invoke-CheckedAs2Runner 'Equipment Tuning' $equipmentAs2Runner
    Invoke-CheckedHostTests 'Equipment Tuning' 'FullyQualifiedName~EquipmentTuningTaskTests'
    Invoke-CheckedNode 'tools\test-equipment-tuning-runtime.js'
    Invoke-CheckedNode 'tools\test-equipment-tuning-model.js'
    Invoke-CheckedNode 'tools\test-equipment-tuning-confirmation.js'
    Invoke-CheckedNode 'tools\test-equipment-tuning-interaction.js'
    Invoke-CheckedNode 'tools\test-equipment-tuning-source-marker.js'
    Invoke-CheckedNode 'tools\run-equipment-tuning-harness.js'
    Invoke-CheckedNode 'tools\equipment-tuning\run-checks.js'

    if ($CompileAs2) {
        Write-Host 'PG-IDENTITY-TRIPLE PASS (AS2 fresh behavior + Host + Web)'
    } else {
        Write-Host 'PG-IDENTITY-TRIPLE PASS (AS2 static only; no fresh Flash behavior claim)'
    }
}
finally {
    try {
        if ($craftingReviewCleanupArmed -and (Test-Path -LiteralPath $craftingReviewTempRoot)) {
            Invoke-CheckedNode 'tools\build-crafting-product-review.js' `
                @('--cleanup-output-root', $craftingReviewRelativeRoot)
        }
    }
    finally {
        Pop-Location
    }
}
