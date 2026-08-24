[CmdletBinding()]
param(
    [ValidateRange(1, 3600)]
    [int]$TimeoutSeconds = 240,
    [switch]$SkipCompile
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$rootFacadePath = Join-Path $projectRoot 'scripts\引擎\引擎_鸡蛋_lsy_物品系统.as'
$playerAssetTransactionPath = Join-Path $projectRoot `
    'scripts\类定义\org\flashNight\arki\item\PlayerAssetTransaction.as'
$testLoaderTemplatePath = Join-Path $projectRoot `
    'scripts\test-runners\player-asset-transaction\TestLoader.as.template'
$equipmentTuningPath = Join-Path $projectRoot `
    'scripts\类定义\org\flashNight\arki\item\EquipmentTuningService.as'
$questPath = Join-Path $projectRoot 'scripts\通信\通信_鸡蛋_任务系统.as'
$taskPanelPath = Join-Path $projectRoot `
    'scripts\类定义\org\flashNight\arki\task\TaskPanelService.as'
$npcShopPath = Join-Path $projectRoot 'scripts\逻辑系统分区\商店系统_兼容.as'
$kshopPath = Join-Path $projectRoot 'scripts\逻辑系统分区\商城系统_WebView.as'
$achievementPath = Join-Path $projectRoot `
    'scripts\类定义\org\flashNight\arki\achievement\AchievementService.as'
$craftingPath = Join-Path $projectRoot `
    'scripts\类定义\org\flashNight\arki\item\CraftingPanelService.as'
$itemUtilPath = Join-Path $projectRoot `
    'scripts\类定义\org\flashNight\arki\item\ItemUtil.as'
$drugPath = Join-Path $projectRoot `
    'scripts\类定义\org\flashNight\arki\unit\Action\Skill\DrugInputService.as'
$petPath = Join-Path $projectRoot `
    'scripts\类定义\org\flashNight\arki\merc\PetPanelService.as'
$mercPath = Join-Path $projectRoot `
    'scripts\类定义\org\flashNight\arki\merc\MercPanelService.as'
$persistentPoisonPath = Join-Path $projectRoot `
    'scripts\逻辑\单位函数\单位函数_aka_战宠进阶.as'
$rewardXflScriptPath = Join-Path $projectRoot `
    'flashswf\UI\奖励物品界面\LIBRARY\sprite\奖励物品界面.xml'
$rewardItemXflScriptPath = Join-Path $projectRoot `
    'flashswf\UI\奖励物品界面\LIBRARY\sprite\奖励物品-奖励物品显示块.xml'
$tabletXflScriptPath = Join-Path $projectRoot `
    'flashswf\UI\平板电脑界面\LIBRARY\基建内容整体.xml'

# 独立 XFL/SWF 没有稳定的 scripts/类定义 classpath；时间轴必须只依赖
# asLoader 注入的 _root 门面。这个静态门防止后续生产者再次把事务类版本
# 编进各自资产，形成无法加载或版本漂移。
$forbiddenAssetReferences = & git -C $projectRoot grep -n -E `
    'org\.flashNight\.arki\.item\.(PlayerAssetTransaction|ItemUtil)' -- `
    'flashswf/**/*.xml' 2>$null
$grepExitCode = $LASTEXITCODE
if ($grepExitCode -eq 0) {
    throw ("XFL 资产不得直接调用玩家物资类库；请改用 asLoader _root 门面：`n" +
        ($forbiddenAssetReferences -join "`n"))
}
if ($grepExitCode -ne 1) {
    throw "无法完成 XFL 玩家物资类库边界扫描，git grep exit=$grepExitCode"
}

$rootFacadeSource = Get-Content -LiteralPath $rootFacadePath -Raw -Encoding UTF8
$requiredRootFacadeFunctions = @(
    '开始玩家物资事务',
    '提交玩家物资事务',
    '回滚玩家物资事务',
    '结算玩家物资事务异常',
    '标记玩家物资存档脏',
    '记录玩家物资变化',
    '记录玩家货币变化',
    '捕获玩家物资快照',
    '恢复玩家物资快照',
    '玩家物品是否装备'
)
foreach ($facadeFunction in $requiredRootFacadeFunctions) {
    if ($rootFacadeSource -notmatch ('_root\.' + [regex]::Escape($facadeFunction) +
            '\s*=\s*function\s*\(')) {
        throw "asLoader 缺少玩家物资 XFL 门面函数: _root.$facadeFunction"
    }
}
if ($requiredRootFacadeFunctions.Count -ne 10) {
    throw "玩家物资 root facade 清单漂移: $($requiredRootFacadeFunctions.Count)/10"
}

$playerAssetTransactionSource = Get-Content -LiteralPath `
    $playerAssetTransactionPath -Raw -Encoding UTF8
foreach ($dirtyContractToken in @(
        'public static function markDirtyRequired(saveOwner:Object):Void',
        'if (saveOwner == undefined || saveOwner == null)',
        'saveOwner.dirtyMark = true;',
        'if (saveOwner.dirtyMark !== true)')) {
    if (-not $playerAssetTransactionSource.Contains($dirtyContractToken)) {
        throw "PlayerAssetTransaction 强制 dirty 合同缺失: $dirtyContractToken"
    }
}

$testLoaderTemplateSource = Get-Content -LiteralPath `
    $testLoaderTemplatePath -Raw -Encoding UTF8
$questImportTokens = @(
    'import org.flashNight.arki.task.TaskUtil;',
    'import org.flashNight.gesh.json.LoadJson.TaskDataLoader;',
    'import org.flashNight.gesh.json.LoadJson.TaskTextLoader;'
)
$questIncludeToken = '#include "通信/通信_鸡蛋_任务系统.as"'
foreach ($questImportToken in $questImportTokens) {
    if (([regex]::Matches($testLoaderTemplateSource,
                [regex]::Escape($questImportToken))).Count -ne 1) {
        throw "PlayerAsset focused TestLoader 必须且只能导入一次任务短类名: $questImportToken"
    }
    if ($testLoaderTemplateSource.IndexOf($questImportToken) -gt
            $testLoaderTemplateSource.IndexOf($questIncludeToken)) {
        throw "PlayerAsset focused TestLoader 任务短类名 import 必须先于任务脚本 include"
    }
}
if (([regex]::Matches($testLoaderTemplateSource,
            [regex]::Escape($questIncludeToken))).Count -ne 1) {
    throw 'PlayerAsset focused TestLoader 必须且只能实际 include 一次任务系统脚本'
}

# FinishTask 成功后任务与奖励已经权威提交；列表刷新只能是可降级投影，
# 不能在异常时吞掉 success response 并诱发 Web 重放。
$taskPanelSource = Get-Content -LiteralPath $taskPanelPath -Raw -Encoding UTF8
$finishResponseStart = $taskPanelSource.IndexOf('var finishResponse:Object = {')
$finishResponseEnd = $taskPanelSource.IndexOf('sendResponse(finishResponse);',
    $finishResponseStart)
if ($finishResponseStart -lt 0 -or $finishResponseEnd -le $finishResponseStart) {
    throw 'TaskPanelService 缺少提交后 success response 隔离边界'
}
$finishResponseSource = $taskPanelSource.Substring($finishResponseStart,
    $finishResponseEnd - $finishResponseStart)
foreach ($finishResponseToken in @(
        'success:true', 'finishResponse.tasks = buildTaskList();',
        'catch (finishProjectionError)',
        'finishResponse.refreshDeferred = true;')) {
    if (-not $finishResponseSource.Contains($finishResponseToken)) {
        throw "TaskPanelService 提交后投影隔离合同缺失: $finishResponseToken"
    }
}

# 装备调制在领域权威提交后才投影物资 receipt；即便投影自身异常，也必须
# 丢弃并清理显式 frame，绝不能把已提交装备/材料伪回滚或泄漏给下一事务。
$equipmentTuningSource = Get-Content -LiteralPath $equipmentTuningPath -Raw -Encoding UTF8
$projectionStart = $equipmentTuningSource.IndexOf(
    'private static function publishCommittedMaterialEffects')
$projectionEnd = $equipmentTuningSource.IndexOf(
    'private static function rollbackWornRawCommit', $projectionStart)
if ($projectionStart -lt 0 -or $projectionEnd -le $projectionStart) {
    throw '无法定位 EquipmentTuningService 的已提交物资投影边界'
}
$projectionSource = $equipmentTuningSource.Substring(
    $projectionStart, $projectionEnd - $projectionStart)
if ($projectionSource -notmatch 'PlayerAssetTransaction\.begin\(' -or
        $projectionSource -notmatch 'catch\s*\(' -or
        $projectionSource -notmatch
            'PlayerAssetTransaction\.settleAfterException\(assetTransaction,\s*false\)' -or
        $projectionSource -notmatch 'throw\s+effectProjectionError') {
    throw 'EquipmentTuningService 已提交 receipt 投影缺少异常清帧并原样外抛契约'
}
$equipmentPublishCount = ([regex]::Matches(
    $equipmentTuningSource,
    '\.(publishTransactionChanges|publishTransactionChange|publishValueTransaction|publishWornValueTransaction)\s*\(')).Count
$equipmentDispatchRecoveryCount = ([regex]::Matches(
    $equipmentTuningSource,
    'EventBus\.getInstance\(\)\.createDispatchRecoveryToken\(\)')).Count
if ($equipmentPublishCount -ne 6 -or
        $equipmentDispatchRecoveryCount -ne $equipmentPublishCount) {
    throw ("EquipmentTuningService 已提交事件恢复清单漂移: publish={0}, recovery={1}, expected=6" -f
        $equipmentPublishCount, $equipmentDispatchRecoveryCount)
}

# 冻结所有生产 begin 调用者。新增显式 frame 必须先在这里声明其异常结算合同，
# 避免“正常路径能 commit、异常路径遗留栈顶”的调用点静默增长。
$productionBeginContracts = @(
    @{ Name = 'quest'; Path = $questPath; ExpectedBeginCount = 1; RequiredTokens = @(
        'catch (finishTaskAssetError)', 'settleAfterException(',
        'ItemUtil.capturePlayerAssetSnapshot()',
        'ItemUtil.restorePlayerAssetSnapshot(',
        'var reversibleRewardItems:Array = [];',
        'var progressRewardPlan:Object = progressRewardItems.length > 0',
        'PlayerAssetTransaction.markAuthorityWrite(',
        '_root.提交任务完成状态(taskID, taskData.chain);',
        'restoreTaskClaimState', 'catch (levelProjectionError)',
        'catch (nextTaskProjectionError)',
        'catch (taskCompletionProjectionError)',
        'catch (turnInMessageError)', 'catch (rewardSoundError)',
        'catch (overflowMessageError)', 'catch (taskProjectionError)',
        'catch (dialogueProjectionError)') },
    @{ Name = 'npc-shop'; Path = $npcShopPath; ExpectedBeginCount = 3; RequiredTokens = @(
        'catch (buyAssetError)', 'catch (batchSaleError)', 'catch (tradeAssetError)',
        'settleAfterException(', 'catch (buyMetricError)',
        'catch (batchSaleMetricError)', 'catch (tradeMetricError)',
        'catch (buySoundError)', 'catch (batchSaleSoundError)',
        'catch (tradeSoundError)', 'catch (batchInvalidateError)',
        'catch (tradeInvalidateError)', 'buildPostCommitState = function(',
        'catch (postCommitStateError)', 'refreshDeferred:true',
        'capturePlayerAssetSnapshot()', 'restorePlayerAssetSnapshot(') },
    @{ Name = 'kshop'; Path = $kshopPath; ExpectedBeginCount = 2; RequiredTokens = @(
        'catch (checkoutAssetError)', 'catch (claimAssetError)',
        'settleAfterException(', 'catch (checkoutMetricError)',
        'catch (claimMetricError)', 'catch (checkoutSoundError)',
        'catch (checkoutCatalogError)', 'catch (claimProjectionError)',
        'claimAttemptToken =', 'refreshDeferred = true',
        'capturePlayerAssetSnapshot()', 'restorePlayerAssetSnapshot(') },
    @{ Name = 'achievement'; Path = $achievementPath; ExpectedBeginCount = 1; RequiredTokens = @(
        'var rewardItems:Array = rewardsArr.length > 0',
        'var rewardPreflight:Object = ItemUtil.planRewardAcquire(rewardItems);',
        'ItemUtil.require(rewardPreflight.items) == null',
        'throw new Error("achievement_asset_authority_missing")',
        'var claimedHadOwnValue:Boolean = a.claimed.hasOwnProperty(idStr);',
        'a.claimed[idStr] = 1;',
        'PlayerAssetTransaction.hasAuthorityWrite(',
        'if (claimedHadOwnValue) a.claimed[idStr] = claimedBefore;',
        'else delete a.claimed[idStr];',
        'catch (claimAssetError)', 'PlayerAssetTransaction.settleAfterException(',
        'sendCommittedClaimResponse(callId, deliveredRewards);',
        'catch (claimProjectionError)', 'catch (claimResponseError)',
        'catch (alreadyClaimedResponseError)') },
    @{ Name = 'crafting'; Path = $craftingPath; ExpectedBeginCount = 1; RequiredTokens = @(
        'catch (commitError)', 'PlayerAssetTransaction.settleAfterException(',
        'catch (soundError)', 'procurementPlansExists:procurementPlansExists',
        'ObjectUtil.clone(saveExt.procurementPlans)',
        '_root._saveExt.procurementPlans = ObjectUtil.clone(backup.procurementPlans);',
        'delete _root._saveExt.procurementPlans;',
        'var submitRestored:Boolean = false;',
        'assetTransaction, !submitRestored') },
    @{ Name = 'item-util'; Path = $itemUtilPath; ExpectedBeginCount = 2; RequiredTokens = @(
        'catch (acquireError)', 'recoverAcquireDispatch();',
        'PlayerAssetTransaction.markDirtyRequired(',
        'if(acquireWrote) PlayerAssetTransaction.commit(assetTransaction);',
        'catch (submitError)', 'recoverSubmitDispatch();',
        'if(wrote) PlayerAssetTransaction.commit(assetTransaction);',
        'capturePlayerAssetSnapshot', 'restorePlayerAssetSnapshot',
        'PlayerAssetTransaction.markAuthorityWrite(assetTransaction)',
        'var acquireExact:Boolean = true;',
        'rawCommittedBag != expectedBagCommit',
        'rawCommittedMaterial != Number(value)',
        'return acquireExact;', 'return submitExact;') },
    @{ Name = 'drug'; Path = $drugPath; ExpectedBeginCount = 1; RequiredTokens = @(
        'catch (useError)', 'PlayerAssetTransaction.settleAfterException(',
        'inventory.setIndexes(null)', 'catch (exhaustedMessageError)') },
    @{ Name = 'pet'; Path = $petPath; ExpectedBeginCount = 7; RequiredTokens = @(
        'catch (adoptError)', 'catch (advanceError)', 'catch (expandError)',
        'catch (restoreError)', 'catch (levelError)',
        'catch (deleteAssetError)', 'catch (worldAdoptError)',
        'settleAfterException(', 'catch (adoptMetricError)',
        'catch (advanceMetricError)', 'catch (levelMetricError)',
        'catch (worldAdoptMetricError)', 'catch (petIconRefreshError)',
        'catch (deleteSceneRefreshError)',
        'deleteSceneProjected = _root.战宠UI函数.移除场景宠物槽(',
        'catch (worldNpcCleanupError)', 'catch (worldSceneDeployError)',
        'var worldSceneProjected:Boolean = _root.宠物信息[slot][4] != 1;',
        'worldSceneProjected = controlledHero != undefined',
        '&& _root.战宠UI函数.设置宠物出战(',
        'catch (rebuildError)',
        'PlayerAssetTransaction.rollback(levelTransaction);',
        'PlayerAssetTransaction.commit(levelTransaction);',
        '_root._pendingHire = undefined;',
        'refreshDeferred:deleteRefreshDeferred',
        'refreshDeferred: worldRefreshDeferred',
        'capturePetTransactionState()', 'restorePetTransactionState(') },
    @{ Name = 'merc'; Path = $mercPath; ExpectedBeginCount = 2; RequiredTokens = @(
        'catch (hireError)', 'catch (worldHireError)', 'settleAfterException(',
        'catch (hireMetricError)', 'catch (worldHireMetricError)',
        'catch (worldHireSpawnError)', 'catch (worldHireNpcCleanupError)',
        '_root._pendingHire = undefined;', 'refreshDeferred: worldHireRefreshDeferred',
        'captureMercTransactionState()', 'restoreMercTransactionState(',
        'var companionData:Array = _root.同伴数据;',
        'if (_root.同伴数据 == undefined) _root.同伴数据 = companionData;',
        'var worldCompanionData:Array = _root.同伴数据;',
        '_root.同伴数据 = worldCompanionData;') },
    @{ Name = 'persistent-poison'; Path = $persistentPoisonPath; ExpectedBeginCount = 1;
        RequiredTokens = @(
        'var poisonTransaction:Object =', 'catch (poisonCommitError)',
        'PlayerAssetTransaction.settleAfterException(',
        'poisonTransaction, poisonRestoreResult.preserve === true',
        'PlayerAssetTransaction.commit(poisonTransaction)',
        'if(this.延迟常驻淬毒结算 === true) return;') },
    @{ Name = 'equipment-tuning'; Path = $equipmentTuningPath; ExpectedBeginCount = 1; RequiredTokens = @(
        'catch (effectProjectionError)',
        'PlayerAssetTransaction.settleAfterException(assetTransaction, false)',
        'catch (achievementMetricError)', 'catch (achievementError)',
        'catch (bagInvalidationError)', 'catch (materialPublishError)',
        'catch (bagPublishError)',
        'recoverCommittedDispatch(recoverMaterialDispatch);',
        'recoverCommittedDispatch(recoverBagDispatch);',
        'recoverCommittedDispatch(recoverBagValueDispatch);',
        'recoverCommittedDispatch(recoverWornConversionDispatch);',
        'recoverCommittedDispatch(recoverWornMaterialDispatch);',
        'recoverCommittedDispatch(recoverWornEquipmentDispatch);') }
)

$auditedProductionBeginCount = 0
foreach ($contract in $productionBeginContracts) {
    $source = Get-Content -LiteralPath $contract.Path -Raw -Encoding UTF8
    $beginCount = ([regex]::Matches(
        $source, 'PlayerAssetTransaction\.begin\s*\(')).Count
    if ($beginCount -ne [int]$contract.ExpectedBeginCount) {
        throw ("生产 PlayerAssetTransaction.begin 调用数漂移: {0}, expected={1}, actual={2}" -f
            $contract.Name, $contract.ExpectedBeginCount, $beginCount)
    }
    $auditedProductionBeginCount += $beginCount
    foreach ($token in $contract.RequiredTokens) {
        if (-not $source.Contains($token)) {
            throw ("生产玩家物资异常/可选回调合同缺失: {0} -> {1}" -f
                $contract.Name, $token)
        }
    }
}
if ($auditedProductionBeginCount -ne 22) {
    throw "生产 PlayerAssetTransaction.begin 审计总数漂移: $auditedProductionBeginCount/22"
}
$expectedProductionBeginPaths = @($productionBeginContracts | ForEach-Object {
    [System.IO.Path]::GetFullPath($_.Path).Substring($projectRoot.Length + 1).Replace('\', '/')
} | Sort-Object -Unique)
$observedProductionBeginPaths = @(& git -C $projectRoot -c core.quotepath=false grep `
    -l -E 'PlayerAssetTransaction\.begin' -- 'scripts/**/*.as' 2>$null |
    Where-Object {
        $_ -notmatch 'Test\.as$' -and
        $_ -ne 'scripts/引擎/引擎_鸡蛋_lsy_物品系统.as'
    } | Sort-Object -Unique)
if ($LASTEXITCODE -notin @(0, 1)) {
    throw "无法扫描 production PlayerAssetTransaction.begin 调用者，git grep exit=$LASTEXITCODE"
}
$productionBeginPathDrift = @(Compare-Object `
    -ReferenceObject $expectedProductionBeginPaths `
    -DifferenceObject $observedProductionBeginPaths)
if ($productionBeginPathDrift.Count -gt 0) {
    throw ("production PlayerAssetTransaction.begin 调用者清单漂移：`n" +
        (($productionBeginPathDrift | Out-String).Trim()))
}

# 19 个直接持有领域 authority 的显式 caller 必须在首写前 fail-fast 标脏；
# preserve=true catch 的 receipt 已由逐写 finally 固化，因此异常清理必须先 settle，
# 不能再让 dirty/receipt/索引修复异常把 frame 留给下一事务。装备调制仅投影已提交
# receipt，不在本清单；制作拥有 exact snapshot，保留 restore -> finally settle(false)。
function Get-PlayerAssetRegion {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$StartToken,
        [Parameter(Mandatory = $true)][string]$EndToken
    )
    $source = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $start = $source.IndexOf($StartToken)
    $end = if ($start -lt 0) { -1 } else {
        $source.IndexOf($EndToken, $start + $StartToken.Length)
    }
    if ($start -lt 0 -or $end -le $start) {
        throw "无法定位玩家物资 direct-authority 区域: $StartToken -> $EndToken"
    }
    return $source.Substring($start, $end - $start)
}

$rawDirectDirtyPattern = '(?:_root|root)\.存档系统\.dirtyMark\s*=\s*true\s*;'
$itemUtilTransactionRegion = Get-PlayerAssetRegion -Path $itemUtilPath `
    -StartToken 'public static function acquire(' `
    -EndToken 'private static function buildAssetEffectContext'
$itemUtilRequiredDirtyCount = ([regex]::Matches($itemUtilTransactionRegion,
        'PlayerAssetTransaction\.markDirtyRequired\s*\(\s*_root\.存档系统\s*\)')).Count
if ($itemUtilRequiredDirtyCount -ne 4 -or
        $itemUtilTransactionRegion -match $rawDirectDirtyPattern) {
    throw ("ItemUtil acquire/submit 强制 dirty 清单漂移: central={0}/4, raw={1}" -f
        $itemUtilRequiredDirtyCount,
        ([regex]::Matches($itemUtilTransactionRegion, $rawDirectDirtyPattern)).Count)
}

$directAuthorityContracts = @(
    @{ Name='quest'; Path=$questPath; Start='_root.FinishTask = function';
        End='_root.FinishStage = function'; Dirty='PlayerAssetTransaction.markDirtyRequired(';
        FirstWrite='org.flashNight.arki.item.ItemUtil.submit('; Catch='finishTaskAssetError'; DirtyExact=1 },
    @{ Name='achievement'; Path=$achievementPath; Start='public static function handleClaim';
        End='private static function claimResp'; Dirty='PlayerAssetTransaction.markDirtyRequired(';
        FirstWrite='ItemUtil.acquireReward('; Catch='claimAssetError'; DirtyExact=1 },
    @{ Name='crafting'; Path=$craftingPath; Start='private static function executeCommit';
        End='private static function restoreState'; Dirty='PlayerAssetTransaction.markDirtyRequired(';
        FirstWrite='ItemUtil.submit('; Catch=$null; DirtyExact=1 },
    @{ Name='drug'; Path=$drugPath; Start='public static function updateSlot';
        End='public static function syncView'; Dirty='PlayerAssetTransaction.markDirtyRequired(';
        FirstWrite='if (root && root.使用药剂)'; Catch='useError'; DirtyExact=1 },
    @{ Name='npc-buy'; Path=$npcShopPath; Start='NPC商店WebView.executeBuy = function';
        End='NPC商店WebView.validateCollectionSource = function'; Dirty='PlayerAssetTransaction.markDirtyRequired(';
        FirstWrite='ItemUtil.singleAcquire('; Catch='buyAssetError'; DirtyExact=1 },
    @{ Name='npc-batch'; Path=$npcShopPath; Start='NPC商店WebView.executeBatchSell = function';
        End='NPC商店WebView.resolveTradePurchase = function'; Dirty='PlayerAssetTransaction.markDirtyRequired(';
        FirstWrite='bag.remove(String(sellEntry.slot));'; Catch='batchSaleError'; DirtyExact=1 },
    @{ Name='npc-trade'; Path=$npcShopPath; Start='NPC商店WebView.executeTradeCommit = function';
        End='NPC商店WebView.execute = function'; Dirty='PlayerAssetTransaction.markDirtyRequired(';
        FirstWrite='sale.collection.remove(sale.key);'; Catch='tradeAssetError'; DirtyExact=1 },
    @{ Name='kshop-checkout'; Path=$kshopPath; Start='商城WebView.finalizeCheckout = function';
        End='_root.gameCommands["shopCheckoutPreview"]'; Dirty='PlayerAssetTransaction.markDirtyRequired(';
        FirstWrite='ItemUtil.acquire('; Catch='checkoutAssetError'; DirtyExact=1 },
    @{ Name='kshop-claim'; Path=$kshopPath; Start='_root.gameCommands["shopClaim"]';
        End='_root.gameCommands["shopSaveCart"]'; Dirty='PlayerAssetTransaction.markDirtyRequired(';
        FirstWrite='ItemUtil.singleAcquire('; Catch='claimAssetError'; DirtyExact=1 },
    @{ Name='pet-adopt'; Path=$petPath; Start='public static function handleAdopt';
        End='public static function handleDeploy'; Dirty='PlayerAssetTransaction.markDirtyRequired(';
        FirstWrite='_root.金钱 -= price;'; Catch='adoptError'; DirtyExact=1 },
    @{ Name='pet-advance'; Path=$petPath; Start='public static function handleAdvance';
        End='public static function handlePreviewAdvance'; Dirty='PlayerAssetTransaction.markDirtyRequired(';
        FirstWrite='_root.宠物信息[slotIndex][5] = advanceAttrs;'; Catch='advanceError'; DirtyExact=1 },
    @{ Name='pet-expand'; Path=$petPath; Start='public static function handleExpandSlot';
        End='public static function handleRename'; Dirty='PlayerAssetTransaction.markDirtyRequired(';
        FirstWrite='_root.金钱 -= expandCost;'; Catch='expandError'; DirtyExact=1 },
    @{ Name='pet-restore'; Path=$petPath; Start='public static function handleRestoreStamina';
        End='public static function handleLevelUp'; Dirty='PlayerAssetTransaction.markDirtyRequired(';
        FirstWrite='_root.金钱 -= cost;'; Catch='restoreError'; DirtyExact=1 },
    @{ Name='pet-level'; Path=$petPath; Start='public static function levelUpSlot';
        End='public static function handleDelete'; Dirty='PlayerAssetTransaction.markDirtyRequired(';
        FirstWrite='_root.singleSubmit('; Catch='levelError'; DirtyExact=1 },
    @{ Name='pet-delete'; Path=$petPath; Start='public static function handleDelete';
        End='public static function handlePanelOpen'; Dirty='PlayerAssetTransaction.markDirtyRequired(';
        FirstWrite='ManagedLongGunService.withdraw(petInfo);'; Catch='deleteAssetError'; DirtyExact=1 },
    @{ Name='pet-world-adopt'; Path=$petPath; Start='public static function handleWorldAdopt';
        End='private static function sendResponse'; Dirty='PlayerAssetTransaction.markDirtyRequired(';
        FirstWrite='_root.金钱 -= goldPrice;'; Catch='worldAdoptError'; DirtyExact=1 },
    @{ Name='merc-hire'; Path=$mercPath; Start='public static function handleHire(';
        End='public static function handleRevive'; Dirty='PlayerAssetTransaction.markDirtyRequired(';
        FirstWrite='_root.同伴数据 = companionData;'; Catch='hireError'; DirtyExact=1 },
    @{ Name='merc-world-hire'; Path=$mercPath; Start='public static function handleWorldHire(';
        End='private static function spliceFromPool'; Dirty='PlayerAssetTransaction.markDirtyRequired(';
        FirstWrite='_root.同伴数据 = worldCompanionData;'; Catch='worldHireError'; DirtyExact=1 },
    @{ Name='persistent-poison'; Path=$persistentPoisonPath;
        Start='_root.战宠进阶函数.常驻淬毒 = {';
        End='_root.战宠进阶函数.冲腿龙息 = {';
        Dirty='PlayerAssetTransaction.markDirtyRequired('; FirstWrite='_root.金钱 -= poisonCost;';
        Catch='poisonCommitError'; DirtyExact=1 }
)
$auditedDirectDirtyCount = 0
foreach ($contract in $directAuthorityContracts) {
    $region = Get-PlayerAssetRegion -Path $contract.Path `
        -StartToken $contract.Start -EndToken $contract.End
    $dirtyIndex = $region.IndexOf($contract.Dirty)
    $firstWriteIndex = $region.IndexOf($contract.FirstWrite)
    $dirtyCount = ([regex]::Matches(
        $region, [regex]::Escape([string]$contract.Dirty))).Count
    $auditedDirectDirtyCount += $dirtyCount
    if ($dirtyIndex -lt 0 -or $firstWriteIndex -lt 0 -or $dirtyIndex -gt $firstWriteIndex `
            -or $dirtyCount -ne [int]$contract.DirtyExact) {
        throw ("direct-authority dirty-before-write 合同缺失: {0}, dirty={1}, write={2}, count={3}/{4}" -f
            $contract.Name, $dirtyIndex, $firstWriteIndex, $dirtyCount, $contract.DirtyExact)
    }
    if ($region -match $rawDirectDirtyPattern) {
        throw "direct-authority 禁止 raw dirty owner 赋值: $($contract.Name)"
    }
    if ($contract.Catch -ne $null) {
        $catchToken = 'catch (' + [string]$contract.Catch + ')'
        $catchIndex = $region.IndexOf($catchToken)
        $throwIndex = $region.IndexOf('throw ' + [string]$contract.Catch, $catchIndex)
        if ($catchIndex -lt 0 -or $throwIndex -le $catchIndex) {
            throw "无法定位 direct-authority catch: $($contract.Name)"
        }
        $catchBody = $region.Substring($catchIndex, $throwIndex - $catchIndex)
        $settleIndex = $catchBody.IndexOf('settleAfterException(')
        if ($settleIndex -lt 0) {
            throw "direct-authority catch 未结算 frame: $($contract.Name)"
        }
        foreach ($riskyToken in @('dirtyMark', 'recordCurrencyDeltas(', 'setIndexes(')) {
            $riskyIndex = $catchBody.IndexOf($riskyToken)
            if ($riskyIndex -ge 0 -and $riskyIndex -lt $settleIndex) {
                throw "direct-authority catch 在 settle 前执行可抛清理: $($contract.Name) -> $riskyToken"
            }
        }
    }
}
if ($directAuthorityContracts.Count -ne 19) {
    throw "direct-authority caller 审计清单漂移: $($directAuthorityContracts.Count)/19"
}
if ($auditedDirectDirtyCount -ne 19) {
    throw "direct-authority central dirty 调用清单漂移: $auditedDirectDirtyCount/19"
}

# Quest 多资源完成必须先交付、再写可恢复奖励、最后写进度/完成状态；升级
# 回调只能位于 commit 之后。任何顺序回退都会重新打开少扣交付物或丢奖励窗口。
$questFinalityRegion = Get-PlayerAssetRegion -Path $questPath `
    -StartToken '_root.FinishTask = function' -EndToken '_root.FinishStage = function'
$questSubmitIndex = $questFinalityRegion.IndexOf(
    'org.flashNight.arki.item.ItemUtil.submit(')
$questAcquireIndex = $questFinalityRegion.IndexOf(
    'org.flashNight.arki.item.ItemUtil.acquire(')
$questExperienceIndex = $questFinalityRegion.IndexOf(
    '_root.经验值 += experienceReward;')
$questCompleteIndex = $questFinalityRegion.IndexOf(
    '_root.提交任务完成状态(taskID, taskData.chain);')
$questCommitIndex = $questFinalityRegion.IndexOf(
    'PlayerAssetTransaction.commit(assetTransaction);')
$questLevelProjectionIndex = $questFinalityRegion.IndexOf(
    '_root.主角是否升级(_root.等级, _root.经验值);')
if ($questSubmitIndex -lt 0 -or $questAcquireIndex -le $questSubmitIndex -or
        $questExperienceIndex -le $questAcquireIndex -or
        $questCompleteIndex -le $questExperienceIndex -or
        $questCommitIndex -le $questCompleteIndex -or
        $questLevelProjectionIndex -le $questCommitIndex -or
        $questFinalityRegion.Contains('ItemUtil.acquireReward(') -or
        $questFinalityRegion.Contains('PlayerAssetTransaction.hasAuthorityWrite(')) {
    throw 'Quest exact finality 顺序漂移：必须 submit -> reversible acquire -> progress -> completion -> commit -> guarded level reconciliation'
}

# 战宠升级阈值函数属于可扩展旧 UI 回调，必须在 begin/dirty/扣石之前完成。
# 否则回调异常会留下已提交升级却没有 success response 的可重放窗口。
$petLevelRegion = Get-PlayerAssetRegion -Path $petPath `
    -StartToken 'public static function levelUpSlot' `
    -EndToken 'public static function handleDelete'
$petLevelBeginIndex = $petLevelRegion.IndexOf('PlayerAssetTransaction.begin(levelContext)')
$petLevelThresholdIndex = $petLevelRegion.LastIndexOf('计算战宠升级所需经验(')
if ($petLevelBeginIndex -lt 0 -or $petLevelThresholdIndex -lt 0 `
        -or $petLevelThresholdIndex -gt $petLevelBeginIndex) {
    throw '战宠升级下一阈值计算未前置到玩家物资 frame/扣石之前'
}

# checkout/交易 durability 必须在显式 frame 内请求，由 commit 隔离保存异常；
# 已提交后直调强存盘会截断 success response 并诱发重放。
$kshopSource = Get-Content -LiteralPath $kshopPath -Raw -Encoding UTF8
$npcShopSource = Get-Content -LiteralPath $npcShopPath -Raw -Encoding UTF8
if (([regex]::Matches($kshopSource,
            'PlayerAssetTransaction\.requestStrongSave\s*\(')).Count -ne 2 -or
        $kshopSource -match '_root\.强制存盘\s*\(') {
    throw 'KShop checkout/claim 强存盘未完整收进显式玩家物资事务'
}
if (([regex]::Matches($npcShopSource,
            'PlayerAssetTransaction\.requestStrongSave\s*\(')).Count -ne 1 -or
        $npcShopSource -match '_root\.强制存盘\s*\(') {
    throw 'NPC trade 强存盘未收进显式玩家物资事务'
}

# 两个独立 XFL 只允许经 facade 建帧，并同样要隔离提交后的声音/消息/刷新投影。
$xflBoundaryContracts = @(
    @{ Name = 'reward-xfl'; Path = $rewardXflScriptPath; RequiredTokens = @(
        '_root.开始玩家物资事务(', '_root.结算玩家物资事务异常(',
        '_root.捕获玩家物资快照()',
        '_root.恢复玩家物资快照(state.assetSnapshot)',
        'function 领取单项(index, batchState)',
        '奖励品[index] = [];', '恢复奖励领取状态(state)',
        'catch(rewardSoundError)', 'catch(rewardMessageError)',
        'catch(rewardRefreshError)', 'catch(singleRewardRefreshError)'); Dirty='_root.标记玩家物资存档脏();';
        FirstWrite='_root.经验值 += 数量;'; Catch='catch(assetError)' },
    @{ Name = 'tablet-xfl'; Path = $tabletXflScriptPath; RequiredTokens = @(
        '_root.开始玩家物资事务(', '_root.结算玩家物资事务异常(',
        '_root.捕获玩家物资快照()',
        '_root.恢复玩家物资快照(assetSnapshot)',
        'if(!infrastructureRestored) return false;',
        'assetTransaction,!submitRestored',
        'assetTransaction,!upgradeRestored',
        'catch(refreshError)'); Dirty='_root.标记玩家物资存档脏();';
        FirstWrite='_root.itemSubmit(itemArr, assetContext)'; Catch='catch(assetError)' }
)
foreach ($contract in $xflBoundaryContracts) {
    $source = Get-Content -LiteralPath $contract.Path -Raw -Encoding UTF8
    if (([regex]::Matches($source, '_root\.开始玩家物资事务\s*\(')).Count -ne 1) {
        throw "独立 XFL 玩家物资事务入口数漂移: $($contract.Name)"
    }
    foreach ($token in $contract.RequiredTokens) {
        if (-not $source.Contains($token)) {
            throw ("独立 XFL 异常/可选投影合同缺失: {0} -> {1}" -f
                $contract.Name, $token)
        }
    }
    $dirtyIndex = $source.IndexOf($contract.Dirty)
    $dirtyCount = ([regex]::Matches(
        $source, [regex]::Escape([string]$contract.Dirty))).Count
    $firstWriteIndex = $source.IndexOf($contract.FirstWrite)
    if ($dirtyIndex -lt 0 -or $dirtyCount -ne 1 -or
            $firstWriteIndex -lt 0 -or $dirtyIndex -gt $firstWriteIndex) {
        throw "独立 XFL dirty-before-write 合同缺失: $($contract.Name)"
    }
    $catchIndex = $source.IndexOf($contract.Catch)
    $throwIndex = $source.IndexOf('throw assetError', $catchIndex)
    if ($catchIndex -lt 0 -or $throwIndex -le $catchIndex) {
        throw "无法定位独立 XFL asset catch: $($contract.Name)"
    }
    $catchBody = $source.Substring($catchIndex, $throwIndex - $catchIndex)
    $settleIndex = $catchBody.IndexOf('_root.结算玩家物资事务异常(')
    if ($settleIndex -lt 0 -or $catchBody.IndexOf('dirtyMark') -ge 0) {
        throw "独立 XFL catch 未先结算 frame: $($contract.Name)"
    }
    if ($source -match $rawDirectDirtyPattern) {
        throw "独立 XFL 禁止 raw dirty owner 赋值: $($contract.Name)"
    }
}

# 同一奖励 SWF 的单项按钮只能委托父时间轴 authority；禁止再次分叉货币/经验/
# itemAcquire、声音或奖励 latch 写序。父级共享函数的 exact/one-shot 契约由上门冻结。
$rewardItemSource = Get-Content -LiteralPath $rewardItemXflScriptPath -Raw -Encoding UTF8
if (-not $rewardItemSource.Contains(
        '_parent._parent.领取单项(_parent.数组id);')) {
    throw '奖励单项按钮未委托父时间轴共享领取 authority'
}
foreach ($forbiddenToken in @('_root.itemAcquire(', '_root.经验值 +=',
        '_root.金钱 +=', '_root.记录玩家货币变化(',
        '_root.播放音效(', '.奖励品[_parent.数组id] =')) {
    if ($rewardItemSource.Contains($forbiddenToken)) {
        throw "奖励单项按钮残留直接资产/投影旁路: $forbiddenToken"
    }
}

$rewardSource = Get-Content -LiteralPath $rewardXflScriptPath -Raw -Encoding UTF8
$rewardSnapshotIndex = $rewardSource.IndexOf('_root.捕获玩家物资快照()')
$rewardBeginIndex = $rewardSource.IndexOf('_root.开始玩家物资事务(')
$rewardSharedStart = $rewardSource.IndexOf('function 领取单项(index, batchState)')
$rewardSharedEnd = $rewardSource.IndexOf('function 一键领取全部()', $rewardSharedStart)
$rewardSharedSource = if ($rewardSharedStart -ge 0 -and $rewardSharedEnd -gt $rewardSharedStart) {
    $rewardSource.Substring($rewardSharedStart, $rewardSharedEnd - $rewardSharedStart)
} else { '' }
$rewardDirtyIndex = $rewardSharedSource.IndexOf('_root.标记玩家物资存档脏();')
$rewardClearIndex = $rewardSharedSource.IndexOf('奖励品[index] = [];')
$rewardAcquireIndex = $rewardSharedSource.IndexOf('_root.itemAcquire([')
$rewardCatchIndex = $rewardSharedSource.IndexOf('catch(assetError)')
$rewardRestoreIndex = $rewardSharedSource.IndexOf(
    '恢复奖励领取状态(state)', $rewardCatchIndex)
$rewardSettleIndex = $rewardSharedSource.IndexOf(
    '_root.结算玩家物资事务异常(', $rewardCatchIndex)
if ($rewardSnapshotIndex -lt 0 -or $rewardBeginIndex -le $rewardSnapshotIndex -or
        $rewardSharedSource.Length -eq 0 -or $rewardDirtyIndex -lt 0 -or
        $rewardClearIndex -le $rewardDirtyIndex -or
        $rewardAcquireIndex -le $rewardClearIndex -or
        $rewardCatchIndex -lt 0 -or $rewardRestoreIndex -le $rewardCatchIndex -or
        $rewardSettleIndex -le $rewardRestoreIndex) {
    throw '奖励 XFL 未保持 snapshot -> dirty -> one-shot -> acquire -> restore -> settle 顺序'
}

$tabletSource = Get-Content -LiteralPath $tabletXflScriptPath -Raw -Encoding UTF8
$tabletSnapshotIndex = $tabletSource.IndexOf('_root.捕获玩家物资快照()')
$tabletBeginIndex = $tabletSource.IndexOf('_root.开始玩家物资事务(')
$tabletLevelRestoreIndex = $tabletSource.IndexOf('if(!infrastructureRestored) return false;')
$tabletAssetRestoreIndex = $tabletSource.IndexOf(
    '_root.恢复玩家物资快照(assetSnapshot)')
if ($tabletSnapshotIndex -lt 0 -or $tabletBeginIndex -le $tabletSnapshotIndex -or
        $tabletLevelRestoreIndex -lt 0 -or
        $tabletAssetRestoreIndex -le $tabletLevelRestoreIndex) {
    throw '平板基建 XFL 未保持 snapshot-before-begin / level-before-assets exact restore 顺序'
}
$expectedXflBeginPaths = @($xflBoundaryContracts | ForEach-Object {
    [System.IO.Path]::GetFullPath($_.Path).Substring($projectRoot.Length + 1).Replace('\', '/')
} | Sort-Object -Unique)
$observedXflBeginPaths = @(& git -C $projectRoot -c core.quotepath=false grep `
    -l -E '_root\.开始玩家物资事务' -- 'flashswf/**/*.xml' 2>$null |
    Sort-Object -Unique)
if ($LASTEXITCODE -notin @(0, 1)) {
    throw "无法扫描独立 XFL 玩家物资 begin 调用者，git grep exit=$LASTEXITCODE"
}
$xflBeginPathDrift = @(Compare-Object `
    -ReferenceObject $expectedXflBeginPaths -DifferenceObject $observedXflBeginPaths)
if ($xflBeginPathDrift.Count -gt 0) {
    throw ("独立 XFL 玩家物资 begin 调用者清单漂移：`n" +
        (($xflBeginPathDrift | Out-String).Trim()))
}

$commonRunner = Join-Path $PSScriptRoot 'test-runners\run-focused-testloader.ps1'
$focusedRun = @{
    DomainId = 'player-asset-transaction'
    TemplateRelativePath = 'scripts\test-runners\player-asset-transaction\TestLoader.as.template'
    SuiteRelativePaths = @(
        'scripts\类定义\org\flashNight\arki\item\PlayerAssetTransactionTest.as'
    )
    SuiteFqns = @(
        'org.flashNight.arki.item.PlayerAssetTransactionTest'
    )
    AdditionalAsRelativePaths = @(
        'scripts\类定义\org\flashNight\arki\item\ItemUtil.as'
        'scripts\类定义\org\flashNight\arki\task\TaskPanelService.as'
        'scripts\通信\通信_鸡蛋_任务系统.as'
    )
    ExpectedTracePatterns = @(
        '(?m)^PlayerAssetTransactionTest Tests Passed: 113\r?$'
        '(?m)^PlayerAssetTransactionTest Tests Failed: 0\r?$'
    )
    SuccessSummary = 'PlayerAssetTransactionTest 113/113'
    TimeoutSeconds = $TimeoutSeconds
    SkipCompile = $SkipCompile
}
& $commonRunner @focusedRun
