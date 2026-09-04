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

$characterBuildSource = Get-RepoText `
    'scripts\类定义\org\flashNight\arki\item\CharacterBuildService.as'
$characterBuildTestSource = Get-RepoText `
    'scripts\类定义\org\flashNight\arki\item\CharacterBuildServiceTest.as'
$runtimeProjectionSource = Get-RepoText `
    'scripts\类定义\org\flashNight\arki\unit\UnitComponent\Initializer\RuntimeEquipmentProjection.as'
$runtimeProjectionTestSource = Get-RepoText `
    'scripts\类定义\org\flashNight\arki\unit\UnitComponent\Initializer\test\RuntimeEquipmentProjectionTest.as'
$dressupInitializerSource = Get-RepoText `
    'scripts\类定义\org\flashNight\arki\unit\UnitComponent\Initializer\DressupInitializer.as'
$guitarSource = Get-RepoText 'scripts\逻辑\装备函数\吉他喷火.as'
$deadHandSource = Get-RepoText 'scripts\逻辑\装备函数\死者之手.as'
$guitarActiveSource = $guitarSource.Split(
    @('===== 原始资产代码参考 ====='),
    [System.StringSplitOptions]::None
)[0]
$drugInputSource = Get-RepoText `
    'scripts\类定义\org\flashNight\arki\unit\Action\Skill\DrugInputService.as'
$itemUtilSource = Get-RepoText `
    'scripts\类定义\org\flashNight\arki\item\ItemUtil.as'
$longGunSkillSource = Get-RepoText `
    'scripts\逻辑\单位函数\单位函数_雾人_aka_fs_主动战技.as'
$drugWriter = [regex]::Match(
    $drugInputSource,
    'public static function updateSlot\([\s\S]*?\r?\n    public static function syncView'
).Value
$submitWriter = [regex]::Match(
    $itemUtilSource,
    'public static function submit\(itemArray:Array,\s*context:Object\):Boolean\{[\s\S]*?public static function singleRequire'
).Value
$grenadeWriter = [regex]::Match(
    $longGunSkillSource,
    '// Fallback: 检查手雷装备栏是否有对应消耗品[\s\S]*?return false;'
).Value
$readinessProbe = [regex]::Match(
    $characterBuildSource,
    'public static function canOpenPanel\(\):Boolean \{[\s\S]*?\r?\n    \}\r?\n\r?\n    /\*\*\r?\n     \* 建立新的观察基线'
).Value
$grenadeDirtyCount = [regex]::Matches(
    $grenadeWriter,
    '存档系统\.dirtyMark\s*=\s*true'
).Count
if (($drugWriter -notmatch
        'var\s+physicalSlot:Number\s*=\s*physicalSlotFor\(activeBank,\s*lane\)') -or
        ($drugWriter -notmatch
        'PlayerAssetTransaction\.markDirtyRequired\(root\.存档系统\)[\s\S]{0,720}inventory\.addValue\(String\(physicalSlot\),\s*-1\)[\s\S]{0,720}PlayerAssetTransaction\.recordEffect\([\s\S]{0,420}PlayerAssetTransaction\.commit\(assetTransaction\)') -or
        ($submitWriter -notmatch 'var wrote:Boolean\s*=\s*false') -or
        ([regex]::Matches($submitWriter, 'wrote\s*=\s*true').Count -ne 3) -or
        ($submitWriter -notmatch 'var dirtyMarked:Boolean\s*=\s*false') -or
        ([regex]::Matches(
            $submitWriter,
            'PlayerAssetTransaction\.markDirtyRequired\(_root\.存档系统\)'
        ).Count -ne 3) -or
        ($submitWriter -notmatch
            'if\(implicitAssetTransaction\) PlayerAssetTransaction\.commit\(assetTransaction\);[\s\S]{0,100}submitCompleted\s*=\s*true;[\s\S]{0,80}return submitExact') -or
        ($submitWriter -notmatch
            'if\(wrote\) PlayerAssetTransaction\.markAuthorityWrite\(assetTransaction\);[\s\S]{0,360}if\(wrote\) PlayerAssetTransaction\.commit\(assetTransaction\)[\s\S]{0,100}else PlayerAssetTransaction\.rollback\(assetTransaction\)') -or
        ($grenadeWriter -notmatch
            'grenadeItem\.value\s*-=\s*1[\s\S]{0,220}dirtyMark\s*=\s*true') -or
        ($grenadeWriter -notmatch
            '装备栏\.remove\("手雷"\)[\s\S]{0,220}dirtyMark\s*=\s*true') -or
        ($grenadeDirtyCount -ne 2) -or
        ($readinessProbe -notmatch 'resolveContainers\s*\(') -or
        ($readinessProbe -notmatch 'scanLoadout\s*\(') -or
        ($readinessProbe -notmatch 'liveContext\s*\(') -or
        ($readinessProbe -match
            '_webPanelPauseLease|_sessionGeneration\s*=|_generationCounter\s*\+\+|_capturedPauseLease\s*=|_active\s*=') -or
        ($characterBuildTestSource -notmatch
            'testDrugInputWriterPersistence\s*\(') -or
        ($characterBuildTestSource -notmatch
            'testItemSubmitWriterPersistence\s*\(') -or
        ($characterBuildTestSource -notmatch
            'testLongGunGrenadeWriterPersistence\s*\(') -or
        ($characterBuildTestSource -notmatch
            'testLootAcquireProjectsOnNewSession\s*\(')) {
    throw 'CharacterBuild writer dirty/readiness static contract or split convergence coverage is incomplete.'
}
$liveBaselineBody = [regex]::Match(
    $characterBuildSource,
    'private static function liveBaselineStatus[\s\S]*?\r?\n    /\*\*\r?\n     \* B0 spike'
).Value
if (($runtimeProjectionSource -notmatch 'function beginCanonical\s*\(') -or
        ($runtimeProjectionSource -notmatch 'function reserveEmptySlotAlias\s*\(') -or
        ($runtimeProjectionSource -notmatch 'function commitSlotAlias\s*\(') -or
        ($runtimeProjectionSource -notmatch 'function releaseAliases\s*\(') -or
        ($runtimeProjectionSource -notmatch 'function buildSemanticSignature\s*\(') -or
        ($dressupInitializerSource -notmatch
            'beginCanonical\(target\)[\s\S]*?updateLifeCycles\(target\)[\s\S]*?completeCanonical\(target\)') -or
        ($dressupInitializerSource -notmatch
            'teardownLifeCycles[\s\S]*?releaseAliases\(target\)') -or
        ($liveBaselineBody -notmatch 'RuntimeEquipmentProjection\.getStatus') -or
        ($liveBaselineBody -match 'validLiveTail|hero\[SLOT_KEYS\[i\]\]\s*!==\s*refs\[i\]') -or
        ($guitarActiveSource -notmatch
            'reserveEmptySlotAlias\(ref, "刀"\)[\s\S]*?commitSlotAlias') -or
        ($guitarActiveSource -match 'target\.刀\s*=\s*target\.长枪') -or
        ($deadHandSource -notmatch
            'reserveEmptySlotAlias\(反射对象, "长枪"\)[\s\S]*?commitSlotAlias') -or
        ($deadHandSource -match '自机\.长枪\s*=\s*自机\.刀') -or
        ($deadHandSource -match '自机\[基础属性名\]') -or
        ($runtimeProjectionTestSource -notmatch 'testForwardAndReverseAliases\s*\(') -or
        ($characterBuildTestSource -notmatch 'testInitialTransientStateDoesNotDirty\s*\(') -or
        ($characterBuildTestSource -notmatch 'testRuntimeSlotAliasStaysClean\s*\(')) {
    throw 'Runtime equipment projection intent, lifecycle ownership, or CharacterBuild dirty-scope contract is incomplete.'
}
Write-Host '[STATIC_PASS] Runtime equipment projection intent and narrow dirty scope'
$registeredActions = [regex]::Matches(
    $characterBuildSource,
    'gameCommands\["(characterBuild[^"]+)"\]\s*='
) | ForEach-Object { $_.Groups[1].Value }
$expectedWebActions = @(
    'characterBuildSnapshot'
    'characterBuildCandidates'
    'characterBuildTooltip'
    'characterBuildEquipEquipment'
    'characterBuildUnequipEquipment'
    'characterBuildEquipDrug'
    'characterBuildUnequipDrug'
    'characterBuildFlushLive'
    'characterBuildStatsSnapshot'
    'characterBuildFinalize'
)
$expectedHostOnlyActions = @(
    'characterBuildRecoverDetach'
)
$expectedActions = @($expectedWebActions + $expectedHostOnlyActions)
$registeredActionSet = @($registeredActions | Sort-Object) -join '|'
$expectedActionSet = @($expectedActions | Sort-Object) -join '|'
if ((@($registeredActions).Count -ne $expectedActions.Count) -or
        ($registeredActionSet -ne $expectedActionSet)) {
    throw 'CharacterBuild actions must be the exact ten Web actions plus one Host-only recovery action.'
}
$characterBuildHostSource = Get-RepoText `
    'launcher\src\Guardian\CharacterBuildTask.cs'
$characterBuildProtocolSource = Get-RepoText `
    'launcher\src\Guardian\CharacterBuildProtocol.cs'
$productionResolver = [regex]::Match(
    $characterBuildHostSource,
    'private static bool TryResolveProductionCommand[\s\S]*?\r?\n        private bool TryNormalizeProductionPayload'
).Value
$mutationResolver = [regex]::Match(
    $characterBuildProtocolSource,
    'internal static bool TryResolveMutationAction[\s\S]*?\r?\n        internal static bool TryNormalizeMutationPayload'
).Value
$combinedResolvers = $productionResolver + "`n" + $mutationResolver
$resolvedWebActions = [regex]::Matches(
    $combinedResolvers,
    'action\s*=\s*"(characterBuild[^"]+)"'
) | ForEach-Object { $_.Groups[1].Value }
$expectedWebCommands = @(
    'snapshot'
    'candidates'
    'tooltip'
    'equipEquipment'
    'unequipEquipment'
    'equipDrug'
    'unequipDrug'
    'flushLive'
    'statsSnapshot'
    'finalize'
)
$resolvedWebCommands = [regex]::Matches(
    $combinedResolvers,
    'case\s+"([^"]+)"'
) | ForEach-Object { $_.Groups[1].Value }
if (($productionResolver -notmatch
        'CharacterBuildProtocol\.TryResolveMutationAction') -or
        (@($resolvedWebActions).Count -ne $expectedWebActions.Count) -or
        ((@($resolvedWebActions | Sort-Object) -join '|') -ne
            (@($expectedWebActions | Sort-Object) -join '|')) -or
        (@($resolvedWebCommands).Count -ne $expectedWebCommands.Count) -or
        ((@($resolvedWebCommands | Sort-Object) -join '|') -ne
            (@($expectedWebCommands | Sort-Object) -join '|'))) {
    throw 'CharacterBuild Web resolver must remain the exact ten-command/ten-action set.'
}
if (($combinedResolvers -match 'RecoverDetach') -or
        ($combinedResolvers -match 'recoverDetach')) {
    throw 'Host-only characterBuildRecoverDetach must not enter the Web command resolver.'
}
if ($characterBuildSource -notmatch
        'characterBuildRecoverDetach"\]\s*=\s*function\(params\)[\s\S]{0,240}handleRecoverDetach') {
    throw 'CharacterBuild Host-only recovery action is not isolated from the Web execute() path.'
}
if (($characterBuildSource -match 'persistenceSucceeded') -or
        ($characterBuildSource -notmatch 'task:"loadout_response"') -or
        ($characterBuildSource -notmatch 'hasPendingChanges\s*\(') -or
        ($characterBuildSource -notmatch 'SaveManager\.getInstance\s*\(') -or
        ($characterBuildSource -notmatch 'ManualCooldownService[\s\S]{0,120}\.FRAME_MS') -or
        ($characterBuildSource -notmatch 'getEffectiveItemData\s*\(\s*item\s*\)') -or
        ($characterBuildSource -notmatch 'typeof\s+item\.getData\s*!=\s*"function"') -or
        ($characterBuildSource -match 'getEffectiveItemData[\s\S]{0,700}getItemData\s*\(') -or
        ($characterBuildSource -notmatch 'pause_lease_missing') -or
        ($characterBuildSource -notmatch 'live_unavailable') -or
        ($characterBuildSource -notmatch 'recoveryState:"authority_absent"')) {
    throw 'CharacterBuild wire/projection/persistence static contract is incomplete.'
}

[xml]$qualificationWeapons = Get-RepoText `
    'data\items\武器_长枪_突击步枪.xml'
[xml]$qualificationBlade = Get-RepoText `
    'data\items\武器_刀_刀剑.xml'
[xml]$qualificationArmor = Get-RepoText `
    'data\items\防具_0-19级.xml'
[xml]$qualificationMods = Get-RepoText `
    'data\items\equipment_mods\高等材料_通用.xml'
[xml]$qualificationEquipmentConfig = Get-RepoText `
    'data\equipment\equipment_config.xml'
$m4a1 = $qualificationWeapons.SelectSingleNode('//item[name="M4A1"]')
$behemoth = $qualificationWeapons.SelectSingleNode('//item[name="巨兽"]')
$garo = $qualificationBlade.SelectSingleNode('//item[name="远古诛神剑"]')
$desertVest = $qualificationArmor.SelectSingleNode(
    '//item[name="沙漠军装背心"]')
$computerChip = $qualificationMods.SelectSingleNode(
    '//mod[name="电脑芯片"]')
$tierThreeMappings = $qualificationEquipmentConfig.SelectNodes(
    '//TierMapping[@name="三阶"]')
$iceMappings = $qualificationEquipmentConfig.SelectNodes(
    '//TierMapping[@name="墨冰"]')
$fireMappings = $qualificationEquipmentConfig.SelectNodes(
    '//TierMapping[@name="狱火"]')
if (($tierThreeMappings.Count -ne 1) -or
        ([string]$tierThreeMappings[0].key -ne 'data_3') -or
        ($iceMappings.Count -ne 1) -or
        ([string]$iceMappings[0].key -ne 'data_ice') -or
        ($fireMappings.Count -ne 1) -or
        ([string]$fireMappings[0].key -ne 'data_fire') -or
        ($null -eq $m4a1) -or ([string]$m4a1.type -ne '武器') -or
        ([string]$m4a1.use -ne '长枪') -or
        ([int]$m4a1.data.level -ne 10) -or
        ([int]$m4a1.data_ice.level -ne 41) -or
        ([int]$m4a1.data_fire.level -ne 41) -or
        ($null -eq $behemoth) -or ([string]$behemoth.type -ne '武器') -or
        ([string]$behemoth.use -ne '长枪') -or
        ([int]$behemoth.data.level -ne 30) -or
        ([string]$behemoth.inherentTags -notmatch '(^|,)电力(,|$)') -or
        ($null -eq $garo) -or ([string]$garo.name -ne '远古诛神剑') -or
        ([string]$garo.displayname -ne '牙狼剑') -or
        ([string]$garo.icon -ne '远古诛神剑') -or
        ([string]$garo.type -ne '武器') -or
        ([string]$garo.use -ne '刀') -or
        ([string]$garo.actiontype -ne '刀剑') -or
        ([int]$garo.data.level -ne 60) -or
        ($null -eq $desertVest) -or ([string]$desertVest.type -ne '防具') -or
        ([string]$desertVest.use -ne '上装装备') -or
        ([int]$desertVest.data.level -ne 10) -or
        ([int]$desertVest.data_3.level -ne 25) -or
        ($null -eq $computerChip) -or
        ([string]$computerChip.use -notmatch '(^|,)长枪(,|$)') -or
        ([string]$computerChip.requireTags -notmatch '(^|,)电力(,|$)') -or
        ([int]$computerChip.stats.flat.level -ne -3)) {
    throw 'Production XML no longer matches the Character effective-level family fixture.'
}
if (($characterBuildTestSource -notmatch
        'new BaseItem\(\s*"M4A1"[\s\S]{0,160}level:13') -or
        ($characterBuildTestSource -notmatch
            'new BaseItem\(\s*"M4A1"[\s\S]{0,160}tier:"墨冰"') -or
        ($characterBuildTestSource -notmatch
            'new BaseItem\(\s*"M4A1"[\s\S]{0,160}tier:"狱火"') -or
        ($characterBuildTestSource -notmatch
            'new BaseItem\(\s*"巨兽"[\s\S]{0,180}mods:\["电脑芯片"\]') -or
        ($characterBuildTestSource -notmatch
            'new BaseItem\(\s*"远古诛神剑"[\s\S]{0,180}tier:""') -or
        ($characterBuildTestSource -notmatch
            'new BaseItem\(\s*"沙漠军装背心"[\s\S]{0,180}tier:"三阶"') -or
        ($characterBuildTestSource -notmatch
            'ordinary\.getData\(\)\.data\.level\s*==\s*10') -or
        ($characterBuildTestSource -notmatch
            'chipped\.getData\(\)\.data\.level\s*==\s*27') -or
        ($characterBuildTestSource -notmatch
            'garo\.getData\(\)\.data\.level\s*==\s*60') -or
        ($characterBuildTestSource -match
            'level:this\.value\.level')) {
    throw 'Character effective-level coverage must use real BaseItem calculation and fail closed when unbound.'
}
Write-Host '[STATIC_PASS] Character real BaseItem effective-level XML families'

$webViewInstallSource = Get-RepoText 'scripts\逻辑系统分区\物品系统_WebView.as'
if ($webViewInstallSource -notmatch 'CharacterBuildService\.install\s*\(\s*\)') {
    throw 'CharacterBuildService is not installed by 物品系统_WebView.as.'
}

$sceneTransitionSource = Get-RepoText `
    'scripts\逻辑\关卡系统\关卡系统_lsy_场景转换.as'
if ($sceneTransitionSource -match '__legacyMaterialOnly') {
    throw 'Scene transition must not retain the retired material-only flag.'
}

$saveManagerSource = Get-RepoText `
    'scripts\类定义\org\flashNight\neur\Server\SaveManager.as'
# R1 Slice 2：三个 strict public 入口（flushNow/flushDurableNow/flushBeforeTransition）
# 分别进入同一私有内核 _strictFlushCore。sv 投影契约钉在内核上，另加防 public
# 级联断言（级联会让一次调用同时计入 legacy 与新 API ingress，裁决 §5.3 兼容 wrapper 门）。
$strictCoreBody = [regex]::Match(
    $saveManagerSource,
    'private function _strictFlushCore\(origin:String, reason:String\):Boolean \{[\s\S]*?\r?\n    \}'
).Value
$flushNowBody = [regex]::Match(
    $saveManagerSource,
    'public function flushNow\(\):Boolean \{[\s\S]*?\r?\n    \}'
).Value
$durableNowBody = [regex]::Match(
    $saveManagerSource,
    'public function flushDurableNow\(reason:String\):Boolean \{[\s\S]*?\r?\n    \}'
).Value
$beforeTransitionBody = [regex]::Match(
    $saveManagerSource,
    'public function flushBeforeTransition\(reason:String\):Boolean \{[\s\S]*?\r?\n    \}'
).Value
$debounceBody = [regex]::Match(
    $saveManagerSource,
    'private function _onDebounceFire\(\):Void \{[\s\S]*?\r?\n    \}'
).Value
if (($strictCoreBody -notmatch
        'pushUiState\("sv:1"\)[\s\S]*?允许存档\s*!==\s*true') -or
        ($strictCoreBody -notmatch
        '允许存档\s*!==\s*true[\s\S]*?pushUiState\("sv:3"\)[\s\S]*?return false') -or
        ($strictCoreBody -notmatch
            '_saveInFlight[\s\S]*?pushUiState\("sv:3"\)[\s\S]*?return false') -or
        ($strictCoreBody -notmatch
            'catch \(saveError\)[\s\S]*?pushUiState\("sv:3"\)[\s\S]*?throw saveError') -or
        ($debounceBody -notmatch
            'catch \(saveError\)[\s\S]*?pushUiState\("sv:3"\)[\s\S]*?throw saveError') -or
        ($saveManagerSource -notmatch
            'pushUiState\(ok \? "sv:2" : "sv:3"\)') -or
        ($flushNowBody -notmatch '_strictFlushCore\("legacyStrict"') -or
        ($flushNowBody -match 'flushDurableNow|flushBeforeTransition|_doSaveAll') -or
        ($durableNowBody -notmatch '_strictFlushCore\("durable"') -or
        ($durableNowBody -match 'flushNow\(|flushBeforeTransition|_doSaveAll') -or
        ($beforeTransitionBody -notmatch '_strictFlushCore\("transition"') -or
        ($beforeTransitionBody -match 'flushNow\(|flushDurableNow|_doSaveAll')) {
    throw 'SaveManager must expose sv:2 only for committed flush, sv:3 for every synchronous failure path, and route every strict public entry through the shared private core without public cascading.'
}
Write-Host '[STATIC_PASS] Safe-exit save outcome projection contract'

$uiManagerSource = Get-RepoText 'scripts\展现\UI交互\UI交互_lsy_UI管理.as'
$uiManagerNormalized = $uiManagerSource -replace "`r`n", "`n"
$lootFenceIndex = $uiManagerNormalized.IndexOf('hasPendingTransportDetach')
$buildFenceIndex = $uiManagerNormalized.IndexOf(
    'CharacterBuildService' + "`n" +
    '            .blocksGenericPauseRelease()')
$genericReleaseIndex = $uiManagerNormalized.IndexOf(
    'PauseManager.releaseLease(_root._webPanelPauseLease)')
if (($lootFenceIndex -lt 0) -or ($buildFenceIndex -le $lootFenceIndex) -or
        ($genericReleaseIndex -le $buildFenceIndex) -or
        ($uiManagerSource -match
            'CharacterBuildService\.releasePauseForClose\s*\(')) {
    throw 'webPanelUnpause must keep Loot fence -> CharacterBuild fence -> generic release order.'
}

$openMaterialUi = [regex]::Match(
    $uiManagerSource,
    '_root\.gameCommands\["openMaterialUI"\]\s*=\s*function\(params\)\s*\{(?<body>[\s\S]*?)\r?\n\};'
)
if ((-not $openMaterialUi.Success) -or
        ($openMaterialUi.Groups['body'].Value -notmatch
            'missingOpenRequestId:Boolean[\s\S]*?typeof\(params\.openRequestId\)\s*==\s*"undefined"') -or
        ($openMaterialUi.Groups['body'].Value -notmatch
            'CraftingPanelService\.openMaterialsPanel\(\s*"nativehud_materials"\s*\)') -or
        ($openMaterialUi.Groups['body'].Value -notmatch
            'CraftingPanelService\.openMaterialsPanel\(\s*"nativehud_materials"\s*,\s*params\.openRequestId\s*\)') -or
        ($openMaterialUi.Groups['body'].Value -match
            '__legacyMaterialOnly|物品栏界面|gotoAndStop') -or
        ($uiManagerSource -match
            '_root\.gameCommands\["(?:openEquipUI|warehouse)"\]')) {
    throw 'Web-only material open and retired AS2 equipment/warehouse command contracts are incomplete.'
}
Write-Host '[STATIC_PASS] Web-only material route and retired AS2 equipment/warehouse commands'

$socketRetainBody = [regex]::Match(
    $characterBuildSource,
    'public static function reconcileSocketDetach\(\):Object \{[\s\S]*?\r?\n    \}'
).Value
$exactRecoveryBody = [regex]::Match(
    $characterBuildSource,
    'private static function recoverExactAuthority\(\):Object \{[\s\S]*?\r?\n    \}'
).Value
if (($socketRetainBody -notmatch
        'retainCapturedPause\s*\(\s*"socket_detach"\s*\)') -or
        ($socketRetainBody -match 'settleCapturedPause') -or
        ($exactRecoveryBody -notmatch
            'settleCapturedPause\s*\(\s*"host_recover_detach"\s*\)') -or
        ($characterBuildSource -notmatch
            'public static function blocksGenericPauseRelease\(\):Boolean')) {
    throw 'CharacterBuild detach must retain pause; only Host-only exact recovery may settle it.'
}

$serverManagerSource = Get-RepoText `
    'scripts\类定义\org\flashNight\neur\Server\ServerManager.as'
$detachIndex = $serverManagerSource.IndexOf(
    'CharacterBuildService')
$pendingClearIndex = $serverManagerSource.IndexOf(
    '// 清理所有 pending callback')
if (($detachIndex -lt 0) -or ($pendingClearIndex -le $detachIndex)) {
    throw 'CharacterBuild socket detach reconcile must run before pending callbacks are cleared.'
}

$focusedRun = @{
    DomainId = 'character-build'
    TemplateRelativePath = 'scripts\test-runners\character-build\TestLoader.as.template'
    SuiteRelativePaths = @(
        'scripts\类定义\org\flashNight\neur\Server\test\SaveManagerTest.as'
        'scripts\类定义\org\flashNight\arki\item\itemCollection\EquipmentInventoryTest.as'
        'scripts\类定义\org\flashNight\arki\item\InventoryPanelServiceTest.as'
        'scripts\类定义\org\flashNight\arki\item\CharacterBuildTransactionSpikeTest.as'
        'scripts\类定义\org\flashNight\arki\unit\UnitComponent\Initializer\test\RuntimeEquipmentProjectionTest.as'
        'scripts\类定义\org\flashNight\arki\item\CharacterBuildServiceTest.as'
        'scripts\类定义\org\flashNight\arki\unit\PlayerInfoProviderTest.as'
    )
    SuiteFqns = @(
        'org.flashNight.neur.Server.test.SaveManagerTest'
        'org.flashNight.arki.item.itemCollection.EquipmentInventoryTest'
        'org.flashNight.arki.item.InventoryPanelServiceTest'
        'org.flashNight.arki.item.CharacterBuildTransactionSpikeTest'
        'org.flashNight.arki.unit.UnitComponent.Initializer.test.RuntimeEquipmentProjectionTest'
        'org.flashNight.arki.item.CharacterBuildServiceTest'
        'org.flashNight.arki.unit.PlayerInfoProviderTest'
    )
    AdditionalAsRelativePaths = @(
        'scripts\类定义\org\flashNight\arki\unit\PlayerInfoProvider.as'
        'scripts\类定义\org\flashNight\arki\unit\PlayerInfoSnapshotBuilder.as'
    )
    ExpectedTracePatterns = @(
        '(?m)^========== SaveManagerTest END: (?<savePassed>[1-9][0-9]*)/\k<savePassed> passed, 0 failed ==========\r?$'
        '(?m)^EquipmentInventoryTest Tests Passed: [1-9][0-9]*\r?$'
        '(?m)^EquipmentInventoryTest Tests Failed: 0\r?$'
        '(?m)^InventoryPanelServiceTest Tests Passed: [1-9][0-9]*\r?$'
        '(?m)^InventoryPanelServiceTest Tests Failed: 0\r?$'
        '(?m)^CharacterBuildTransactionSpikeTest Tests Passed: [1-9][0-9]*\r?$'
        '(?m)^CharacterBuildTransactionSpikeTest Tests Failed: 0\r?$'
        '(?m)^RuntimeEquipmentProjectionTest Tests Passed: [1-9][0-9]*\r?$'
        '(?m)^RuntimeEquipmentProjectionTest Tests Failed: 0\r?$'
        '(?m)^CharacterBuildServiceTest Tests Passed: [1-9][0-9]*\r?$'
        '(?m)^CharacterBuildServiceTest Tests Failed: 0\r?$'
        '(?m)^PlayerInfoProviderTest Tests Passed: [1-9][0-9]*\r?$'
        '(?m)^PlayerInfoProviderTest Tests Failed: 0\r?$'
    )
    SuccessSummary = 'SaveManager, EquipmentInventory, InventoryPanelService, transaction spike, RuntimeEquipmentProjection, CharacterBuildService, and PlayerInfoProvider suites completed with zero failures'
    TimeoutSeconds = $TimeoutSeconds
    SkipCompile = $SkipCompile
}
& $commonRunner @focusedRun
