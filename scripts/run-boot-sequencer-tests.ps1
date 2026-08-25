[CmdletBinding()]
param(
    [ValidateRange(1, 3600)]
    [int]$TimeoutSeconds = 240,
    [switch]$SkipCompile
)

$ErrorActionPreference = 'Stop'
$commonRunner = Join-Path $PSScriptRoot 'test-runners\run-focused-testloader.ps1'
$projectDir = Split-Path -Parent $PSScriptRoot
$shopCompatPath = Join-Path $projectDir 'scripts\逻辑系统分区\商店系统_兼容.as'
$shopCompatSource = Get-Content -LiteralPath $shopCompatPath -Raw -Encoding UTF8
$shopSchemaStart = $shopCompatSource.IndexOf(
    'if (this.parsedshop.schema !== undefined)')
$shopSchemaEnd = $shopCompatSource.IndexOf(
    'if (parsedShopEntryCount < 1)', $shopSchemaStart)
if ($shopSchemaStart -lt 0 -or $shopSchemaEnd -le $shopSchemaStart) {
    throw 'NPC shop loader lacks a bounded explicit-schema normalization branch.'
}
$shopSchemaBranch = $shopCompatSource.Substring(
    $shopSchemaStart, $shopSchemaEnd - $shopSchemaStart)
foreach ($requiredPattern in @(
        'this\.parsedshop\.schema\s*!==\s*"npc-shop\.v2"',
        'typeof\s+this\.parsedshop\.shopId\s*!=\s*"string"',
        'shopCatalog\s*==\s*null',
        'typeof\s+shopCatalog\s*!=\s*"object"',
        'shopCatalog\s+instanceof\s+Array',
        'this\.shopIdsSeen\[shopIdentityKey\]\s*===\s*true',
        'parsedShopEntryCount\s*=\s*1',
        'legacyCatalogEntryCount\s*<\s*1',
        'this\.shopIdsSeen\[legacyIdentityKey\]\s*===\s*true')) {
    if ($shopSchemaBranch -notmatch $requiredPattern) {
        throw "NPC shop loader fail-closed schema guard is missing: $requiredPattern"
    }
}
if ($shopSchemaBranch -match '\bshopCatalogEntryCount\b') {
    throw 'Explicit npc-shop.v2 single-shop catalogs must allow the authored empty-catalog disabled state.'
}

$disabledShopRelativePath = 'npcs/幸存老兵-暂时停用.json'
$disabledShopPath = Join-Path $projectDir ('data\shops\' + $disabledShopRelativePath)
$disabledShop = Get-Content -LiteralPath $disabledShopPath -Raw -Encoding UTF8 | ConvertFrom-Json
$disabledCatalogProperties = @($disabledShop.catalog.PSObject.Properties)
if (($disabledShop.schema -ne 'npc-shop.v2') -or
        ($disabledShop.shopId -ne '幸存老兵-暂时停用') -or
        ($null -eq $disabledShop.catalog) -or
        ($disabledCatalogProperties.Count -ne 0)) {
    throw 'The authored disabled NPC shop fixture must remain one explicit npc-shop.v2 identity with catalog:{}.'
}
$shopListPath = Join-Path $projectDir 'data\shops\list.xml'
[xml]$shopList = Get-Content -LiteralPath $shopListPath -Raw -Encoding UTF8
$disabledShopReferences = @($shopList.root.shops | Where-Object {
        [string]$_ -eq $disabledShopRelativePath
    })
if ($disabledShopReferences.Count -ne 1) {
    throw 'The authored disabled NPC shop fixture must be referenced exactly once by data/shops/list.xml.'
}

$focusedRun = @{
    DomainId = 'boot-sequencer'
    TemplateRelativePath = 'scripts\test-runners\boot-sequencer\TestLoader.as.template'
    SuiteRelativePaths = @(
        'scripts\类定义\org\flashNight\boot\BootSequencerTest.as'
        'scripts\类定义\org\flashNight\neur\Server\test\BootstrapHandshakeTest.as'
    )
    SuiteFqns = @(
        'org.flashNight.boot.BootSequencerTest'
        'org.flashNight.neur.Server.test.BootstrapHandshakeTest'
    )
    ExpectedTracePatterns = @(
        '(?m)^=== BootSequencerTest: 89 passed, 0 failed ===\r?$'
        '(?m)^========== BootstrapHandshakeTest END: 12/12 passed, 0 failed ==========\r?$'
    )
    SuccessSummary = 'BootSequencerTest 89/89 + BootstrapHandshakeTest 12/12'
    TimeoutSeconds = $TimeoutSeconds
    SkipCompile = $SkipCompile
}
& $commonRunner @focusedRun
