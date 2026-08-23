[CmdletBinding()]
param(
    [ValidateRange(1, 3600)]
    [int]$TimeoutSeconds = 240,
    [switch]$SkipCompile
)

$ErrorActionPreference = 'Stop'
$commonRunner = Join-Path $PSScriptRoot 'test-runners\run-focused-testloader.ps1'

$repoRoot = Split-Path -Parent $PSScriptRoot

# 佣兵装备托管一期静态结构门（docs/佣兵装备托管-设计-2026-08-23.md §3-§6）。
$loadoutServicePath = Join-Path $repoRoot 'scripts\类定义\org\flashNight\arki\merc\MercLoadoutService.as'
$loadoutServiceSource = Get-Content -LiteralPath $loadoutServicePath -Raw -Encoding UTF8
if ($loadoutServiceSource -notmatch 'class\s+org\.flashNight\.arki\.merc\.MercLoadoutService\s*\{') {
    throw 'MercLoadoutService must keep the expected fully-qualified class declaration.'
}
foreach ($requiredMethod in @(
        'isWritableSlot', 'hasAnyCustody', 'getLoadoutRevision', 'evaluateItemForSlot',
        'buildLoadoutProjection', 'buildCandidates', 'buildSlotTooltip',
        'deliver', 'replace', 'withdraw', 'buildSpawnLoadout',
        'createRuntimeItem', 'freezeItem')) {
    if ($loadoutServiceSource -notmatch ('public\s+static\s+function\s+' + $requiredMethod + '\s*\(')) {
        throw "MercLoadoutService is missing public static method: $requiredMethod"
    }
}
if ([regex]::Matches($loadoutServiceSource, 'tryTransactionWrite\s*\(').Count -lt 4 -or
    $loadoutServiceSource -notmatch 'createDispatchRecoveryToken' -or
    $loadoutServiceSource -notmatch 'invalidateExternalSlot\("背包"' -or
    $loadoutServiceSource -notmatch 'publishTransactionChange') {
    throw 'MercLoadoutService must keep the ManagedLongGun three-phase transaction and notification-isolation pattern.'
}
if ($loadoutServiceSource -notmatch '手雷') {
    throw 'MercLoadoutService must document the grenade slot exclusion.'
}

$mercPanelPath = Join-Path $repoRoot 'scripts\类定义\org\flashNight\arki\merc\MercPanelService.as'
$mercPanelSource = Get-Content -LiteralPath $mercPanelPath -Raw -Encoding UTF8
if ([regex]::Matches($mercPanelSource,
        '_root\.gameCommands\["mercLoadout(Deliver|Replace|Withdraw|Candidates|Tooltip)"\]').Count -ne 5) {
    throw 'MercPanelService.install must register exactly the five mercLoadout gameCommands.'
}
$dismissStart = $mercPanelSource.IndexOf('public static function handleDismiss(')
$dismissEnd = $mercPanelSource.IndexOf('public static function handleHire(', $dismissStart)
if ($dismissStart -lt 0 -or $dismissEnd -le $dismissStart) {
    throw 'MercPanelService dismiss section is missing or malformed.'
}
$dismissSection = $mercPanelSource.Substring($dismissStart, $dismissEnd - $dismissStart)
$dismissGuard = $dismissSection.IndexOf('MercLoadoutService.hasAnyCustody')
$dismissRemove = $dismissSection.IndexOf('MercSpawner.removeMerc(')
if ($dismissGuard -lt 0 -or $dismissRemove -le $dismissGuard -or
    $dismissSection -notmatch 'custody_not_empty' -or
    $dismissSection -notmatch 'removeResult') {
    throw 'handleDismiss must check hasAnyCustody before removeMerc and honor its result.'
}
$summaryStart = $mercPanelSource.IndexOf('private static function buildMercSummary(')
$summaryEnd = $mercPanelSource.IndexOf('static function buildPersonality(', $summaryStart)
if ($summaryStart -lt 0 -or $summaryEnd -le $summaryStart) {
    throw 'MercPanelService summary section is missing or malformed.'
}
$summarySection = $mercPanelSource.Substring($summaryStart, $summaryEnd - $summaryStart)
if ($summarySection -notmatch 'MercLoadoutService\.buildSpawnLoadout\(merc\)' -or
    $summarySection -notmatch 'loadout:\s+MercLoadoutService\.buildLoadoutProjection\(merc, slotIndex\)' -or
    $summarySection -notmatch 'buildEffectiveSkillView\(merc, spawnLoadout\)' -or
    $summarySection -notmatch 'instanceof BaseItem') {
    throw 'buildMercSummary must project effective equips, expose loadout and feed buildSkills the effective view.'
}
if ($mercPanelSource -notmatch 'inventorySnapshot:\s*InventoryPanelService\.buildExternalSnapshot\("背包", 0, 50\)') {
    throw 'Merc loadout write responses must carry a fresh inventory snapshot.'
}

$spawnerPath = Join-Path $repoRoot 'scripts\类定义\org\flashNight\arki\merc\MercSpawner.as'
$spawnerSource = Get-Content -LiteralPath $spawnerPath -Raw -Encoding UTF8
$removeStart = $spawnerSource.IndexOf('public static function removeMerc(')
$removeEnd = $spawnerSource.IndexOf('public static function initIndexCache(', $removeStart)
if ($removeStart -lt 0 -or $removeEnd -le $removeStart) {
    throw 'MercSpawner.removeMerc section is missing or malformed.'
}
$removeSection = $spawnerSource.Substring($removeStart, $removeEnd - $removeStart)
$guardIndex = $removeSection.IndexOf('MercLoadoutService.hasAnyCustody')
$firstWrite = $removeSection.IndexOf('_root.可雇佣兵.push(')
if ($guardIndex -lt 0 -or $firstWrite -le $guardIndex -or
    $removeSection -notmatch 'error:"custody_not_empty"' -or
    $removeSection -notmatch 'return \{success:true\};') {
    throw 'removeMerc must fail closed on any custody before any write and report success explicitly.'
}

$scenePath = Join-Path $repoRoot 'scripts\逻辑\关卡系统\关卡系统_lsy_场景转换.as'
$sceneSource = Get-Content -LiteralPath $scenePath -Raw -Encoding UTF8
if ([regex]::Matches($sceneSource,
        'org\.flashNight\.arki\.merc\.MercLoadoutService\.buildSpawnLoadout\(同伴信息\)').Count -ne 2 -or
    [regex]::Matches($sceneSource, '头部装备:装备解析\.头部装备').Count -ne 2 -or
    [regex]::Matches($sceneSource, '刀:装备解析\.刀').Count -ne 2 -or
    [regex]::Matches($sceneSource, '手雷:同伴信息\[16\]').Count -ne 2) {
    throw 'Both merc attach blocks in 场景转换 must resolve spawn loadout and keep the grenade slot untouched.'
}

# 本 suite 现有循环会把 89 个静态 check 调用展开为 97 次运行时断言；把调用点
# 与下方 trace 期望同时锁住，避免 focused 施工只改测试却遗忘 runner 计数。
$loadoutTestPath = Join-Path $repoRoot 'scripts\类定义\org\flashNight\arki\merc\MercLoadoutServiceTest.as'
$loadoutTestSource = Get-Content -LiteralPath $loadoutTestPath -Raw -Encoding UTF8
$loadoutCheckCallSites = [regex]::Matches(
    $loadoutTestSource, '(?m)^\s*check\s*\(').Count
if ($loadoutCheckCallSites -ne 89) {
    throw "MercLoadoutServiceTest check call-site count drifted: expected 89, actual $loadoutCheckCallSites. Recalculate the 97 runtime assertion contract."
}
if ($loadoutTestSource -notmatch 'class\s+org\.flashNight\.arki\.merc\.MercLoadoutServiceTest\s*\{' -or
    $loadoutTestSource -notmatch 'custody_not_empty' -or
    $loadoutTestSource -notmatch 'buildSpawnLoadout' -or
    $loadoutTestSource -notmatch 'reentry\.error == "busy"') {
    throw 'MercLoadoutServiceTest must cover custody guard, spawn loadout resolution and busy reentry.'
}

$focusedRun = @{
    DomainId = 'merc-loadout'
    TemplateRelativePath = 'scripts\test-runners\merc-loadout\TestLoader.as.template'
    SuiteRelativePaths = @(
        'scripts\类定义\org\flashNight\arki\merc\MercLoadoutServiceTest.as'
    )
    SuiteFqns = @(
        'org.flashNight.arki.merc.MercLoadoutServiceTest'
    )
    AdditionalAsRelativePaths = @(
        'scripts\类定义\org\flashNight\arki\merc\MercLoadoutService.as'
        'scripts\类定义\org\flashNight\arki\merc\MercPanelService.as'
        'scripts\类定义\org\flashNight\arki\merc\MercSpawner.as'
        'scripts\逻辑\关卡系统\关卡系统_lsy_场景转换.as'
    )
    ExpectedTracePatterns = @(
        '(?m)^MercLoadoutServiceTest Tests Passed: 97\r?$'
        '(?m)^MercLoadoutServiceTest Tests Failed: 0\r?$'
    )
    SuccessSummary = 'MercLoadoutServiceTest 97/97 passed'
    TimeoutSeconds = $TimeoutSeconds
    SkipCompile = $SkipCompile
}
& $commonRunner @focusedRun
