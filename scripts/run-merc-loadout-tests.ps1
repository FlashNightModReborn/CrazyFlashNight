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
        'isWritableSlot', 'isEquipLocked', 'hasAnyCustody', 'getLoadoutRevision', 'evaluateItemForSlot',
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

# 本 suite 现有循环会把 117 个静态 check 调用展开为 125 次运行时断言；把调用点
# 与下方 trace 期望同时锁住，避免 focused 施工只改测试却遗忘 runner 计数。
$loadoutTestPath = Join-Path $repoRoot 'scripts\类定义\org\flashNight\arki\merc\MercLoadoutServiceTest.as'
$loadoutTestSource = Get-Content -LiteralPath $loadoutTestPath -Raw -Encoding UTF8
$loadoutCheckCallSites = [regex]::Matches(
    $loadoutTestSource, '(?m)^\s*check\s*\(').Count
if ($loadoutCheckCallSites -ne 117) {
    throw "MercLoadoutServiceTest check call-site count drifted: expected 117, actual $loadoutCheckCallSites. Recalculate the 125 runtime assertion contract."
}
if ($loadoutTestSource -notmatch 'class\s+org\.flashNight\.arki\.merc\.MercLoadoutServiceTest\s*\{' -or
    $loadoutTestSource -notmatch 'custody_not_empty' -or
    $loadoutTestSource -notmatch 'buildSpawnLoadout' -or
    $loadoutTestSource -notmatch 'reentry\.error == "busy"') {
    throw 'MercLoadoutServiceTest must cover custody guard, spawn loadout resolution and busy reentry.'
}

# 数据侧性格配置（mercenaries.json personality → merc[19].性格 → 面板/战斗共用合并语义）。
$personalityTestPath = Join-Path $repoRoot 'scripts\类定义\org\flashNight\arki\merc\MercPersonalityTest.as'
$personalityTestSource = Get-Content -LiteralPath $personalityTestPath -Raw -Encoding UTF8
$personalityCheckCallSites = [regex]::Matches(
    $personalityTestSource, '(?m)^\s*check\s*\(').Count
if ($personalityCheckCallSites -ne 24) {
    throw "MercPersonalityTest check call-site count drifted: expected 24, actual $personalityCheckCallSites."
}
if ($personalityTestSource -notmatch 'class\s+org\.flashNight\.arki\.merc\.MercPersonalityTest\s*\{') {
    throw 'MercPersonalityTest must keep the expected fully-qualified class declaration.'
}

$mercLibraryPath = Join-Path $repoRoot 'scripts\类定义\org\flashNight\arki\merc\MercLibrary.as'
$mercLibrarySource = Get-Content -LiteralPath $mercLibraryPath -Raw -Encoding UTF8
foreach ($requiredMethod in @('normalizePersonality', 'mergePersonalityTraits')) {
    if ($mercLibrarySource -notmatch ('public\s+static\s+function\s+' + $requiredMethod + '\s*\(')) {
        throw "MercLibrary is missing public static method: $requiredMethod"
    }
}
if ($mercLibrarySource -notmatch 'merc\[19\]\.性格\s*=\s*性格配置') {
    throw 'buildMercData must write the normalized personality override into merc[19].性格.'
}

# 战斗侧接线在 publish 注入的 逻辑 文件里，不在本 suite 的运行闭包内，故用源码门钉住
# "合并同一人格引用 → 再重算派生参数" 的顺序，避免只改面板不改 AI。
$unitTemplatePath = Join-Path $repoRoot 'scripts\逻辑\单位函数\单位函数_fs_aka_玩家模板迁移.as'
$unitTemplateSource = Get-Content -LiteralPath $unitTemplatePath -Raw -Encoding UTF8
$aiConfigStart = $unitTemplateSource.IndexOf('_root.配置人形怪AI = function(')
$personalityMerge = $unitTemplateSource.IndexOf(
    'MercLibrary.mergePersonalityTraits(target.personality, target.佣兵参数.性格)', $aiConfigStart)
$personalityRecompute = $unitTemplateSource.IndexOf('_root.计算AI参数(target.personality);', $personalityMerge)
if ($aiConfigStart -lt 0 -or $personalityMerge -lt 0 -or $personalityRecompute -le $personalityMerge) {
    throw '配置人形怪AI must merge 佣兵参数.性格 then recompute 计算AI参数 on the same personality reference.'
}
if ($spawnerSource -notmatch 'MercLibrary\.mergePersonalityTraits\(mc\.personality, mercData\[19\]\.性格\)') {
    throw '待雇 NPC must merge mercData[19].性格 so dialogue and post-hire personality share one source.'
}

# 角斗场对手卡走 MercPanelService.buildPersonality（合并 merc[19].性格），故标准/隐藏对战的
# 敌人侧必须把同一份 性格 挂上 佣兵参数 通道；且只能挂 性格——整份透传 敌人信息[19] 会顺带
# 激活 authored 被动技能，把这条展示同源改动偷渡成角斗场难度变更。
$enemySpawnStart = $sceneSource.IndexOf('_root.加载敌方人物 = function(')
$rosterSpawnStart = $sceneSource.IndexOf('_root.角斗场读取单位参数 = function(')
if ($enemySpawnStart -lt 0 -or $rosterSpawnStart -le $enemySpawnStart) {
    throw '场景转换 enemy-spawn section is missing or malformed.'
}
$enemySpawnSection = $sceneSource.Substring($enemySpawnStart, $rosterSpawnStart - $enemySpawnStart)
if ($enemySpawnSection -notmatch '敌人\.佣兵参数\s*=\s*\{性格:敌人信息\[19\]\.性格\}') {
    throw '加载敌方人物 must carry only merc[19].性格 into 佣兵参数, keeping arena passive skills inert.'
}

$focusedRun = @{
    DomainId = 'merc-loadout'
    TemplateRelativePath = 'scripts\test-runners\merc-loadout\TestLoader.as.template'
    SuiteRelativePaths = @(
        'scripts\类定义\org\flashNight\arki\merc\MercLoadoutServiceTest.as'
        'scripts\类定义\org\flashNight\arki\merc\MercPersonalityTest.as'
    )
    SuiteFqns = @(
        'org.flashNight.arki.merc.MercLoadoutServiceTest'
        'org.flashNight.arki.merc.MercPersonalityTest'
    )
    AdditionalAsRelativePaths = @(
        'scripts\类定义\org\flashNight\arki\merc\MercLibrary.as'
        'scripts\类定义\org\flashNight\arki\merc\MercLoadoutService.as'
        'scripts\类定义\org\flashNight\arki\merc\MercPanelService.as'
        'scripts\类定义\org\flashNight\arki\merc\MercSpawner.as'
        'scripts\逻辑\关卡系统\关卡系统_lsy_场景转换.as'
    )
    ExpectedTracePatterns = @(
        '(?m)^MercLoadoutServiceTest Tests Passed: 125\r?$'
        '(?m)^MercLoadoutServiceTest Tests Failed: 0\r?$'
        '(?m)^MercPersonalityTest Tests Passed: 24\r?$'
        '(?m)^MercPersonalityTest Tests Failed: 0\r?$'
    )
    SuccessSummary = 'MercLoadoutServiceTest 125/125 + MercPersonalityTest 24/24 passed'
    TimeoutSeconds = $TimeoutSeconds
    SkipCompile = $SkipCompile
}
& $commonRunner @focusedRun
