param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"
$script:Assertions = 0

function Read-Utf8([string]$RelativePath) {
    $path = Join-Path $ProjectRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing wiring source: $RelativePath"
    }
    return [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)
}

function Assert-Contains([string]$Text, [string]$Needle, [string]$Label) {
    $script:Assertions++
    if ($Text.IndexOf($Needle, [StringComparison]::Ordinal) -lt 0) {
        throw "$Label missing '$Needle'"
    }
}

function Assert-NotContains([string]$Text, [string]$Needle, [string]$Label) {
    $script:Assertions++
    if ($Text.IndexOf($Needle, [StringComparison]::Ordinal) -ge 0) {
        throw "$Label unexpectedly contains '$Needle'"
    }
}

function Assert-Ordered([string]$Text, [string[]]$Needles, [string]$Label) {
    $cursor = -1
    foreach ($needle in $Needles) {
        $script:Assertions++
        $next = $Text.IndexOf($needle, $cursor + 1, [StringComparison]::Ordinal)
        if ($next -lt 0) { throw "$Label missing/out-of-order '$needle'" }
        $cursor = $next
    }
}

$interaction = Read-Utf8 "scripts\类定义\org\flashNight\arki\unit\UnitComponent\Initializer\ElementComponent\InteractionHandler.as"
$arbiter = Read-Utf8 "scripts\类定义\org\flashNight\arki\unit\UnitComponent\Initializer\ElementComponent\BoxInteractionArbiter.as"
$service = Read-Utf8 "scripts\类定义\org\flashNight\arki\item\LootContainerService.as"
$serviceTest = Read-Utf8 "scripts\类定义\org\flashNight\arki\item\LootContainerServiceTest.as"
$planner = Read-Utf8 "scripts\类定义\org\flashNight\arki\item\LootMaterializationPlanner.as"
$commit = Read-Utf8 "scripts\类定义\org\flashNight\arki\item\LootClaimCommitCoordinator.as"
$dropLuck = Read-Utf8 "scripts\类定义\org\flashNight\arki\item\DropLuckRoller.as"
$map = Read-Utf8 "scripts\逻辑\关卡系统\关卡系统_lsy_地图元件.as"
$callback = Read-Utf8 "scripts\逻辑\关卡系统\关卡系统_lsy_资源箱回调.as"
$scene = Read-Utf8 "scripts\类定义\org\flashNight\arki\scene\SceneManager.as"
$sceneFlow = Read-Utf8 "scripts\逻辑\关卡系统\关卡系统_lsy_场景转换.as"
$restartCleanup = Read-Utf8 "scripts\通信\通信_fs_帧计时器.as"
$server = Read-Utf8 "scripts\类定义\org\flashNight\neur\Server\ServerManager.as"
$ui = Read-Utf8 "scripts\展现\UI交互\UI交互_lsy_UI管理.as"
$inventoryUi = Read-Utf8 "scripts\展现\UI交互\UI交互_lsy_物品栏UI.as"
$inventoryIcon = Read-Utf8 "scripts\类定义\org\flashNight\arki\item\itemIcon\InventoryIcon.as"
$install = Read-Utf8 "scripts\逻辑系统分区\物品系统_WebView.as"
$stage = Read-Utf8 "data\stages\副本任务\夺取材料.xml"

Assert-Ordered $interaction @(
    "ChestSessionService.beginFixture(",
    "LootContainerService.beginFixture(target)",
    "物化Web战利品物品栏(target)",
    "LootContainerService.commitReservedOpen(",
    "InteractionHandler.executePickup(box)"
) "interaction authority order"
Assert-Ordered $interaction @(
    "var deathFunc:Function",
    "LootContainerService.observeDeath(target)",
    "BoxInteractionArbiter.unregister(target)"
) "own-death proof order"
Assert-Contains $interaction 'LootContainerService.abortReservedOpen(target, "materialization_failed")' "materialization abort"
Assert-Contains $interaction "_root.地图元件.回退Web战利品到旧界面(target)" "commit fallback"
Assert-Contains $interaction 'LootContainerService.abortReservedOpen(target, "registration_failed")' "registration abort"
Assert-Ordered $interaction @(
    "if (lootResult.recovery === true)",
    "lootResult.rendererConfirmed === true",
    "_root.地图元件.显示Web战利品旧界面(lootResult)",
    "_root.地图元件.回退Web战利品到旧界面(null)"
) "recovery redisplay requires prior renderer proof or confirm wrapper"

foreach ($needle in @(
    "public static function beginFixture",
    "public static function register",
    "public static function abortReservedOpen",
    "public static function commitReservedOpen",
    "public static function observeDeath",
    "public static function handleTargetUnload",
    "public static function activateReservedOpen",
    "public static function requestOpenPanel",
    "public static function canReopenSuspendedTarget",
    "public static function resumeSuspended",
    "public static function releaseSuspendedPauseForClose",
    "public static function handlePanelRecovery",
    "public static function reconcileSocketDetach",
    "public static function reconcileTransportDetach",
    "public static function consumeLegacyFallback",
    "public static function confirmLegacyRenderer",
    "public static function claimLegacyRecoverySlot",
    "public static function hasPendingTransportDetach",
    "public static function attachLegacyRecoveryObserver",
    "public static function guardAnyGridFixture",
    "public static function expireScene"
)) { Assert-Contains $service $needle "loot service lifecycle" }
Assert-Contains $service 'target.unlockPolicy !== "skip"' "three-field rollout marker"
Assert-Contains $service 'sourceRef.containerId !== record.lootContainerId' "loot capability ownership"
Assert-Contains $service 'params.direction !== "loot_to_player"' "one-way claim"
Assert-Contains $service 'params.targetContainerId !== "背包"' "backpack-only destination"
Assert-Contains $service 'STATE_CONSUMED:String = "CONSUMED"' "consumed terminal"
Assert-Contains $service 'STATE_SUSPENDED:String = "LOOT_SUSPENDED"' "suspended authority state"
Assert-Contains $service 'STATE_ABANDONED:String = "ABANDONED"' "abandoned terminal"
Assert-Contains $service 'STATE_EXPIRED:String = "EXPIRED"' "expired terminal"
Assert-NotContains $service 'if (response.snapshots == null) response.snapshots = []' "active success cannot omit snapshots"
Assert-Contains $service 'return failureFor(record, "authority_unavailable")' "snapshot projection failure"

Assert-Contains $map "LootMaterializationPlanner.materialize(target)" "materialization planner delegate"
Assert-Ordered $planner @(
    "target[JOURNAL_FIELD] = journal",
    "if (!initialize(target, journal))",
    "sampleSlots(journal)",
    "buildPlan(journal)",
    "writeInventory(journal)",
    "commitTotalsAndDetachSource(target, journal)",
    "journal.success = true"
) "resumable materialization journal"
Assert-Contains $planner "target.掉落物.length != journal.rawDropsLength" "frozen drop-array length"
Assert-Contains $planner "target.掉落物[sourceIndex] !== journal.rules[sourceIndex].rule" "frozen drop-array identity"
Assert-Contains $planner "rule.总数 > MAX_SAFE_INTEGER" "drop total safe integer"
Assert-Contains $planner "MAX_RANDOM_SPAN:Number = 2147483647" "AVM1 random span bound"
Assert-Contains $planner "journal.luckBonus = luckBonus" "frozen loot luck bonus"
Assert-Contains $planner "journal.prdEngine = prdEngine" "frozen loot PRD engine"
Assert-Contains $planner "DropLuckRoller.rollDropWithContext(" "frozen roll context"
Assert-Contains $dropLuck "public static function rollDropWithContext" "explicit luck/PRD context API"
Assert-Contains $planner 'fail(journal, "item_creation_failed", false)' "retryable item create failure"
Assert-Contains $map "consumeLegacyFallback(target)" "same-inventory legacy recovery"
Assert-Contains $map "创建资源箱图标(" "legacy renderer adapter"
Assert-Contains $map "projection.row, projection.col, true" "legacy renderer claim-only policy"
Assert-NotContains $map "attachLegacyRecoveryObserver()" "service-backed renderer has no synchronous empty observer"

Assert-Contains $service 'gameCommands["lootPanelRecovery"]' "connected panel recovery command"
Assert-Contains $service "validatePanelRecoveryEnvelope(params)" "exact panel recovery validation"
Assert-Contains $service 'return localFailure("claim_commit_pending")' "pending claim blocks legacy exposure"
Assert-NotContains $service "record.pendingCommit != null || record.state == STATE_PENDING" "reservation recovery is not claim pending"
Assert-Contains $service "postCommitEffects:null" "post-commit mandatory effect journal"
Assert-Contains $service 'if (record.postCommitEffects != null) return failureFor(record, "commit_pending")' "new claims cannot bypass post-commit gate"
Assert-Contains $service "record.pendingCommit != null || record.postCommitEffects != null" "close blocks both commit phases"
Assert-Contains $interaction "LootContainerService.resumeSuspended(target)" "exact suspended target resumes without rematerialization"
Assert-Contains $interaction "LootContainerService.handleTargetUnload(this)" "suspended anchor unload lifecycle"
Assert-Contains $arbiter "LootContainerService.canReopenSuspendedTarget(target)" "killed exception is authority-scoped"
Assert-Contains $service 'return localFailure("loot_suspended")' "suspend bypasses legacy renderer"
Assert-NotContains $service "markDirty();" "unverified dirty write is forbidden"
Assert-Ordered $commit @(
    'pending.phase = "DESTINATION_APPLIED"',
    "rollbackOrPreservePending",
    'error:"commit_pending", pending:true'
) "claim half-commit preservation"
Assert-Contains $commit "observeDestination(pending)" "claim destination reconciliation"
Assert-Contains $commit "observeSource(pending)" "claim source reconciliation"
Assert-Contains $commit "public static function settleForSceneExpiry" "scene-expiry transaction settlement"
Assert-Contains $commit "hasObservableJournal(pending)" "unexpected failure observable journal gate"

$finalizeStart = $service.IndexOf("private static function finalizeClaim", [StringComparison]::Ordinal)
$finalizeEnd = $service.IndexOf("private static function completePostCommitEffects", $finalizeStart, [StringComparison]::Ordinal)
if ($finalizeStart -lt 0 -or $finalizeEnd -le $finalizeStart) { throw "finalizeClaim function bounds missing" }
$finalizeText = $service.Substring($finalizeStart, $finalizeEnd - $finalizeStart)
Assert-Ordered $finalizeText @(
    "record.pendingCommit = null",
    "record.state = STATE_PENDING",
    "record.operations[operationKey(operationId)] =",
    "record.postCommitEffects = {",
    "retryPostCommitEffects(record)"
) "claim journal precedes mandatory post-commit effects"

$effectsStart = $service.IndexOf("private static function completePostCommitEffects", [StringComparison]::Ordinal)
$effectsEnd = $service.IndexOf("private static function retryPostCommitEffects", $effectsStart, [StringComparison]::Ordinal)
if ($effectsStart -lt 0 -or $effectsEnd -le $effectsStart) { throw "post-commit effects function bounds missing" }
$effectsText = $service.Substring($effectsStart, $effectsEnd - $effectsStart)
Assert-Ordered $effectsText @(
    'injectPostCommitFailure("dirty")',
    "markDirtyVerified()",
    'injectPostCommitFailure("loot_cache")',
    "invalidateLootLeases()",
    'injectPostCommitFailure("destination_cache")',
    "InventoryPanelService.invalidateExternalSlot(",
    "record.postCommitEffects = null",
    "record.state = record.transportDetachNeeded === true ? STATE_PENDING : STATE_ACTIVE",
    "publishPostCommitEvents(effects)"
) "mandatory effects complete before active/events"

$detachStart = $service.IndexOf("private static function continueTransportDetach", [StringComparison]::Ordinal)
$detachEnd = $service.IndexOf("private static function prepareTransportLegacyRecovery", $detachStart, [StringComparison]::Ordinal)
if ($detachStart -lt 0 -or $detachEnd -le $detachStart) { throw "transport detach function bounds missing" }
$detachText = $service.Substring($detachStart, $detachEnd - $detachStart)
Assert-Ordered $detachText @(
    "record.transportDetachNeeded !== true",
    "settleForSceneExpiry(pending)",
    "retryPostCommitEffects(record)",
    "prepareTransportLegacyRecovery(record)",
    'injectTransportHandoffFailure("renderer")',
    "record.legacyRendererConfirmed = true",
    "releaseTransportPauseLease()",
    "record.transportDetachNeeded = false",
    "record.state = STATE_ACTIVE",
    "finishTerminal(record, STATE_CONSUMED"
) "transport detach proves journal/effects/renderer/pause before active or empty terminal"
Assert-Contains $service "transportRendererDone:false" "persisted transport renderer proof"
Assert-Contains $service "transportUnpauseDone:false" "persisted transport pause proof"
Assert-Contains $service "if (record.transportDetachNeeded === true)" "causal query transport retry gate"
Assert-Contains $service "return _root._webPanelPauseLease == undefined" "transport unpause verification"
Assert-Contains $service "private static function reconcileSuspendedTransportDetach" "socket suspend no-renderer path"

$closeStart = $service.IndexOf("private static function executeClose", [StringComparison]::Ordinal)
$closeEnd = $service.IndexOf("private static function executeQuery", $closeStart, [StringComparison]::Ordinal)
if ($closeStart -lt 0 -or $closeEnd -le $closeStart) { throw "executeClose function bounds missing" }
$closeText = $service.Substring($closeStart, $closeEnd - $closeStart)
Assert-Ordered $closeText @(
    "registerSuspendedAnchor(record)",
    "resultState:STATE_SUSPENDED",
    "record.state = STATE_SUSPENDED",
    "record.suspendPauseReleasePending = true",
    "record.authorityRevision++"
) "suspend anchor proof precedes authority mutation"

$terminalStart = $service.IndexOf("private static function finishTerminal", [StringComparison]::Ordinal)
$terminalEnd = $service.IndexOf("private static function handleLegacyRecoveryMutation", $terminalStart, [StringComparison]::Ordinal)
if ($terminalStart -lt 0 -or $terminalEnd -le $terminalStart) { throw "finishTerminal function bounds missing" }
$terminalText = $service.Substring($terminalStart, $terminalEnd - $terminalStart)
Assert-Ordered $terminalText @(
    "record.pendingCommit != null",
    "record.postCommitEffects != null",
    "record.transportDetachNeeded === true",
    'return failureFor(record, "commit_pending")'
) "terminal transition cannot bypass commit work"
Assert-Ordered $terminalText @(
    "releaseSuspendedAnchor(record)",
    "releaseHeldTargetTimeline(record)",
    "record.state = terminalState"
) "terminal unregisters anchor before authored timeline resumes"
Assert-Contains $serviceTest "private static function testPostCommitDirtyRetryGate" "dirty retry directed test"
Assert-Contains $serviceTest "private static function testPostCommitDestinationCacheRetry" "destination cache retry directed test"
Assert-Contains $serviceTest "private static function testTransportDetachRendererRetry" "transport renderer retry directed test"
Assert-Contains $serviceTest "private static function testTransportDetachUnpauseLastItemRetry" "transport unpause/last-item directed test"
Assert-Contains $serviceTest "private static function testSuspendAnchorReopenIdentityAndStaleClose" "suspend/reopen directed test"
Assert-Contains $serviceTest "private static function testSuspendPauseSocketBypass" "suspend socket directed test"
Assert-Contains $serviceTest "private static function testSuspendAnchorFailureIsZeroAuthority" "suspend anchor failure directed test"
Assert-Contains $serviceTest "private static function testSuspendedAnchorUnloadExpires" "suspend unload directed test"

$expireStart = $service.IndexOf("public static function expireScene", [StringComparison]::Ordinal)
$expireEnd = $service.IndexOf("private static function executeSnapshot", $expireStart, [StringComparison]::Ordinal)
if ($expireStart -lt 0 -or $expireEnd -le $expireStart) { throw "expireScene function bounds missing" }
$expireText = $service.Substring($expireStart, $expireEnd - $expireStart)
Assert-Ordered $expireText @(
    "settleForSceneExpiry(pending)",
    "finalizeClaim(record, pending, settled)",
    "retryPostCommitEffects(record)",
    "finishTerminal(record, STATE_EXPIRED"
) "scene cleanup settles claim journal before terminal"

$legacyClaimStart = $service.IndexOf("public static function claimLegacyRecoverySlot", [StringComparison]::Ordinal)
$legacyClaimEnd = $service.IndexOf("public static function hasPendingTransportDetach", $legacyClaimStart, [StringComparison]::Ordinal)
if ($legacyClaimStart -lt 0 -or $legacyClaimEnd -le $legacyClaimStart) { throw "legacy claim adapter bounds missing" }
$legacyClaimText = $service.Substring($legacyClaimStart, $legacyClaimEnd - $legacyClaimStart)
Assert-Ordered $legacyClaimText @(
    "record.inventory !== inventory",
    "record.legacyRendererConfirmed !== true",
    'execute("query", queryParams)',
    'execute("claim", {',
    'direction:"loot_to_player"',
    'targetContainerId:"背包"',
    'claim.error == "commit_pending"',
    'execute("query", queryParams)',
    "completeLegacyRecoveryIfEmpty()"
) "legacy renderer delegates one-way claim and causal reconcile"

$legacyConsumeStart = $service.IndexOf("public static function consumeLegacyFallback", [StringComparison]::Ordinal)
$legacyConsumeEnd = $service.IndexOf("public static function confirmLegacyRenderer", $legacyConsumeStart, [StringComparison]::Ordinal)
if ($legacyConsumeStart -lt 0 -or $legacyConsumeEnd -le $legacyConsumeStart) { throw "legacy consume function bounds missing" }
$legacyConsumeText = $service.Substring($legacyConsumeStart, $legacyConsumeEnd - $legacyConsumeStart)
Assert-Ordered $legacyConsumeText @(
    "_legacyRecovery.pendingCommit != null",
    "_legacyRecovery.postCommitEffects != null",
    "_legacyRecovery.transportDetachNeeded === true",
    'return localFailure("claim_commit_pending")'
) "legacy renderer never re-exposes pending journal/effects"

$legacyGuardStart = $service.IndexOf("public static function guardAnyGridFixture", [StringComparison]::Ordinal)
$legacyGuardEnd = $service.IndexOf("public static function completeLegacyRecoveryIfEmpty", $legacyGuardStart, [StringComparison]::Ordinal)
if ($legacyGuardStart -lt 0 -or $legacyGuardEnd -le $legacyGuardStart) { throw "legacy guard function bounds missing" }
$legacyGuardText = $service.Substring($legacyGuardStart, $legacyGuardEnd - $legacyGuardStart)
Assert-Ordered $legacyGuardText @(
    "var completion:Object = completeLegacyRecoveryIfEmpty()",
    "completion.released !== true",
    'return {handled:true, recovery:false, reason:"claim_commit_pending"',
    'return {handled:false, recovery:false, reason:"recovery_consumed"'
) "empty recovery remains authoritative until completion releases"

$legacyCompletionStart = $service.IndexOf("public static function completeLegacyRecoveryIfEmpty", [StringComparison]::Ordinal)
$legacyCompletionEnd = $service.IndexOf("public static function attachLegacyRecoveryObserver", $legacyCompletionStart, [StringComparison]::Ordinal)
if ($legacyCompletionStart -lt 0 -or $legacyCompletionEnd -le $legacyCompletionStart) { throw "legacy completion function bounds missing" }
$legacyCompletionText = $service.Substring($legacyCompletionStart, $legacyCompletionEnd - $legacyCompletionStart)
Assert-Ordered $legacyCompletionText @(
    "record.pendingCommit != null",
    'execute("query", {',
    "if (remainingCount(record) > 0)",
    "record.postCommitEffects != null",
    "retryPostCommitEffects(record)",
    "finishTerminal(record, STATE_CONSUMED"
) "legacy completion causally settles journal/effects before empty terminal"
Assert-Contains $commit 'consumeFault("resume")' "repeatable pending-query fault point"
Assert-Contains $serviceTest '"resume", "false", 3' "persistent pending journal regression"
Assert-Contains $serviceTest "private static function testSceneTeardownPendingBarrier" "scene teardown pending directed test"
Assert-Contains $serviceTest "private static function testLegacyClaimOnlyServiceAdapter" "legacy claim-only directed test"

Assert-Ordered $callback @(
    "ChestSessionService.handleOpenFrame(target)",
    "LootContainerService.guardAnyGridFixture(target)",
    "具有Web战利品标记(target)",
    "LootContainerService.activateReservedOpen(target)",
    "LootContainerService.requestOpenPanel()",
    "掉落物转换为物品栏(target)"
) "open-frame precedence"
Assert-Ordered $callback @(
    "if (lootGuard.recovery === true)",
    "lootGuard.rendererConfirmed === true",
    "显示Web战利品旧界面(lootGuard)",
    "回退Web战利品到旧界面(null)"
) "root callback recovery redisplay proof gate"
$breakStart = $callback.IndexOf("资源箱破碎脚本", [StringComparison]::Ordinal)
$breakText = $callback.Substring($breakStart)
Assert-Ordered $breakText @(
    "ChestSessionService.handleBreakFrame(target)",
    "具有Web战利品标记(target)",
    "LootContainerService.activateReservedOpen(target)",
    "target.掉落物判定()"
) "break-frame fail-closed precedence"

$sceneRemoveStart = $scene.IndexOf("public function removeGameWorld", [StringComparison]::Ordinal)
$sceneRemoveEnd = $scene.IndexOf("public function dispose", $sceneRemoveStart, [StringComparison]::Ordinal)
if ($sceneRemoveStart -lt 0 -or $sceneRemoveEnd -le $sceneRemoveStart) { throw "SceneManager removeGameWorld bounds missing" }
$sceneRemoveText = $scene.Substring($sceneRemoveStart, $sceneRemoveEnd - $sceneRemoveStart)
Assert-Ordered $sceneRemoveText @(
    'LootContainerService.expireScene("scene_cleanup")',
    "lootExpiry.success !== true",
    "return false",
    "this.active = false",
    "ChestS0SocketBridge.handleSceneUnload()",
    "gameworld.dispatcher.destroy()",
    "gameworld.removeMovieClip()",
    "return true"
) "scene teardown waits for loot expiry before any destructive cleanup"

$rootCleanupStart = $sceneFlow.IndexOf("_root.清除游戏世界组件 = function", [StringComparison]::Ordinal)
$rootCleanupEnd = $sceneFlow.IndexOf("_root.注释结束();", $rootCleanupStart, [StringComparison]::Ordinal)
if ($rootCleanupStart -lt 0 -or $rootCleanupEnd -le $rootCleanupStart) { throw "root scene cleanup bounds missing" }
$rootCleanupText = $sceneFlow.Substring($rootCleanupStart, $rootCleanupEnd - $rootCleanupStart)
Assert-Ordered $rootCleanupText @(
    "if (!SceneManager.instance.removeGameWorld())",
    "_root.淡出动画.stop()",
    "_root.__安排游戏世界清理重试()",
    "return false",
    "CollisionLayerRenderer.clearAll()"
) "fade timeline blocks and retries before root teardown"
Assert-Ordered $sceneFlow @(
    "_root.__安排游戏世界清理重试 = function",
    "_root.帧计时器.添加单次任务",
    "_root.清除游戏世界组件()",
    "_root.淡出动画.play()"
) "scene cleanup retry resumes fade only after success"

$restartStart = $restartCleanup.IndexOf(
    "_root.cleanupForRestart = function():Boolean {", [StringComparison]::Ordinal)
$restartEnd = if ($restartStart -ge 0) {
    $restartCleanup.IndexOf("};", $restartStart, [StringComparison]::Ordinal)
} else {
    -1
}
if ($restartStart -lt 0 -or $restartEnd -le $restartStart) {
    throw "cleanupForRestart function bounds missing"
}
$restartText = $restartCleanup.Substring($restartStart, $restartEnd - $restartStart)
Assert-Ordered $restartText @(
    "_root.cleanupForRestart = function():Boolean {",
    "org.flashNight.arki.item.LootContainerService.expireScene(",
    "if (lootExpiry == null || lootExpiry.success !== true) {",
    "return false;",
    "StageManager.instance.dispose();",
    "StageEventHandler.instance.dispose();",
    "WaveSpawnWheel.instance.dispose();",
    "if (!SceneManager.instance.dispose()) {",
    "WaveSpawner.instance.dispose();",
    "return true;"
) "restart cleanup preflights loot before manager disposal"

$restartExpiry = $restartText.IndexOf(
    "org.flashNight.arki.item.LootContainerService.expireScene(",
    [StringComparison]::Ordinal)
$restartFirstDisposeMatch = [regex]::Match($restartText, '\.dispose\s*\(',
    [Text.RegularExpressions.RegexOptions]::CultureInvariant)
$restartFirstDispose = if ($restartFirstDisposeMatch.Success) {
    $restartFirstDisposeMatch.Index
} else {
    -1
}
$script:Assertions++
if ($restartExpiry -lt 0 -or $restartFirstDispose -lt 0 -or $restartExpiry -ge $restartFirstDispose) {
    throw "restart cleanup must call loot expireScene before every manager dispose"
}

$restartFailure = [regex]::Match($restartText,
    'if \(lootExpiry == null \|\| lootExpiry\.success !== true\) \{[\s\S]*?return false;\s*\}',
    [Text.RegularExpressions.RegexOptions]::CultureInvariant)
$script:Assertions++
if (-not $restartFailure.Success) {
    throw "restart cleanup loot preflight failure block must return false"
}
$script:Assertions++
if ([regex]::IsMatch($restartFailure.Value, '\.dispose\s*\(',
        [Text.RegularExpressions.RegexOptions]::CultureInvariant)) {
    throw "restart cleanup failure cannot cross into manager disposal"
}

$script:Assertions++
if (-not [regex]::IsMatch($restartText, 'return true;\s*$',
        [Text.RegularExpressions.RegexOptions]::CultureInvariant)) {
    throw "restart cleanup success path must end with return true"
}

Assert-Ordered $inventoryUi @(
    "claimOnly:Boolean",
    "资源箱界面.__lootClaimOnly = claimOnly === true",
    "IconFactory.createInventoryLayout(",
    "if (iconList == null)",
    "资源箱界面._visible = true",
    "return true"
) "resource-box renderer persists claim-only policy before becoming visible"
Assert-Ordered $inventoryIcon @(
    "public function Press():Void",
    "if (isLootClaimOnlyView())",
    "LootContainerService.claimLegacyRecoverySlot(",
    "return;",
    "if (this.locked) return"
) "claim-only Press precedes every legacy write path"
Assert-Ordered $inventoryIcon @(
    "public function Release():Void",
    "if (isLootClaimOnlyView()) return",
    "info.container.__lootClaimOnly === true",
    "ItemUtil.moveItemToInventory(this,iconMovieClip.itemIcon)"
) "claim-only source and target consume drag before inventory mutation"
Assert-Ordered $server @(
    "ChestS0SocketBridge.handleSocketClosed()",
    "断线回退Web战利品到旧界面(null)"
) "socket recovery order"
Assert-NotContains $server "PauseManager.releaseLease(_root._webPanelPauseLease)" "socket lifecycle cannot release pause outside loot proof"
Assert-Ordered $map @(
    "断线回退Web战利品到旧界面 = function",
    "LootContainerService.reconcileSocketDetach(target)",
    "reconciled.readyForLegacy === true"
) "map delegates atomic transport recovery"
Assert-Contains $map "reconciled.suspendedNoRenderer === true" "map accepts suspended no-renderer proof"
Assert-Ordered $ui @(
    'gameCommands["webPanelUnpause"]',
    "LootContainerService.releaseSuspendedPauseForClose()",
    "LootContainerService.hasPendingTransportDetach()",
    "PauseManager.releaseLease",
    "回退Web战利品到旧界面(null)"
) "panel detach recovery order"
Assert-Contains $install "LootContainerService.install()" "loot command install"

$rolloutId = [regex]::Matches($stage, "<chestRolloutId>loot-canary-material-5-0-v1</chestRolloutId>").Count
$profile = [regex]::Matches($stage, "<lootFlowProfile>web-loot-v1</lootFlowProfile>").Count
$policy = [regex]::Matches($stage, "<unlockPolicy>skip</unlockPolicy>").Count
$script:Assertions += 3
if ($rolloutId -ne 1 -or $profile -ne 1 -or $policy -ne 1) {
    throw "production canary markers must each occur exactly once"
}
Assert-NotContains $stage "<chestS0FixtureId>" "production stage excludes S0 marker"

Write-Output ("[PASS] map-loot-wiring: {0} assertions" -f $script:Assertions)
