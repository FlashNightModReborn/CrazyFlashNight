param()

$ErrorActionPreference = 'Stop'

$toolsDir = $PSScriptRoot
$projectRoot = Split-Path -Parent $toolsDir
$launcherDir = Join-Path $projectRoot 'launcher'
$testsProject = Join-Path $launcherDir 'tests\Launcher.Tests.csproj'

function Invoke-CheckedNode {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelativeScript,
        [string[]]$Arguments = @()
    )

    $scriptPath = Join-Path $projectRoot $RelativeScript
    Write-Host "[PG-INVENTORY-FAULT] node $RelativeScript $($Arguments -join ' ')"
    & node $scriptPath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "PG-INVENTORY-FAULT failed at $RelativeScript (exit=$LASTEXITCODE)"
    }
}

Push-Location $projectRoot
try {
    Invoke-CheckedNode 'tools\test-panel-runtime.js'
    Invoke-CheckedNode 'tools\validate-panel-contracts.js'
    Invoke-CheckedNode 'tools\test-panel-contracts.js'
    Invoke-CheckedNode 'tools\test-inventory-runtime.js'
    Invoke-CheckedNode 'tools\test-inventory-workbench-modules.js'
    Invoke-CheckedNode 'tools\test-inventory-workbench-lazy-closure.js'
    Invoke-CheckedNode 'launcher\web\modules\loot\dev\test-loot-state.js'
    Invoke-CheckedNode 'launcher\web\modules\loot\dev\run-harness.js'
    Invoke-CheckedNode 'tools\run-equipment-tuning-harness.js'
    Invoke-CheckedNode 'tools\run-skills-harness.js'
Invoke-CheckedNode 'tools\run-character-build-workbench-harness.js'
Invoke-CheckedNode 'tools\test-character-build-item-use.js'
    Invoke-CheckedNode 'tools\run-crafting-harness.js'
    Invoke-CheckedNode 'tools\run-kshop-harness.js'
    Invoke-CheckedNode 'tools\run-npcshop-harness.js'
    Invoke-CheckedNode 'tools\run-hairdresser-harness.js'

    . (Join-Path $launcherDir 'resolve-dotnet.ps1')
    $dotnetPath = Resolve-Cf7Dotnet -ProjectRoot $projectRoot
    Write-Host '[PG-INVENTORY-FAULT] Inventory Host fault/owner tests'
    & $dotnetPath test $testsProject -c Release --no-restore `
        --filter 'FullyQualifiedName~InventoryTaskTests|FullyQualifiedName~InventoryOwnerEnvelopeTests|FullyQualifiedName~PanelRequestOwnerLifecycleTests|FullyQualifiedName~PanelHostVisualRetireTests|FullyQualifiedName~PanelHostSkillInstanceTests|FullyQualifiedName~PanelHostHudCompanionTests|FullyQualifiedName~WebOverlayFormPanelCloseTests|FullyQualifiedName~ShopTaskTests|FullyQualifiedName~NpcShopTaskTests|FullyQualifiedName~CraftingTaskTests|FullyQualifiedName~EquipmentTuningTaskTests|FullyQualifiedName~LootTaskTests|FullyQualifiedName~LootPanelCoordinatorTests|FullyQualifiedName~SkillTaskTests|FullyQualifiedName~HairdresserTaskTests'
    if ($LASTEXITCODE -ne 0) {
        throw "PG-INVENTORY-FAULT Host tests failed (exit=$LASTEXITCODE)"
    }

    Write-Host 'PG-INVENTORY-FAULT PASS'
}
finally {
    Pop-Location
}
