import org.flashNight.arki.item.itemCollection.ArrayInventory;
import org.flashNight.arki.item.BaseItem;
import org.flashNight.arki.item.InventoryPanelService;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.item.LootClaimCommitCoordinator;
import org.flashNight.gesh.tooltip.TooltipComposer;
import org.flashNight.gesh.object.ObjectUtil;

/** 持久待领取批次与 reward_inbox Loot 适配器。 */
class org.flashNight.arki.item.RewardInboxService {
    public static var VERSION:Number = 1;
    public static var MAX_OCCURRENCES:Number = 64;
    public static var CLAIM_ROOT_ADMISSION_ENABLED:Boolean = true;
    private static var MAX_RECEIPTS:Number = 128;
    private static var CLAIM_ROOT_SCHEMA_VERSION:Number = 1;
    private static var ACTIVE:String = "LOOT_ACTIVE";
    private static var PENDING:String = "LOOT_COMMIT_PENDING";
    private static var SUSPENDED:String = "LOOT_SUSPENDED";
    private static var CONSUMED:String = "CONSUMED";
    private static var _authority:Object = null;
    private static var _authoritySeq:Number = 0;
    private static var _snapshotSeq:Number = 0;
    private static var _leaseSeq:Number = 0;
    private static var _standardLaneBusyProbe:Function = null;
    private static var _supplySessionToken:String = null;
    private static var _supplyTokenGeneration:Number = 0;
    private static var _rootPersistPending:Boolean = false;
    private static var _rootPersistPendingId:String = "";
    private static var _rootPersistVisibleBefore:Object = null;
    private static var _durableCutProbe:Function = null;
    private static var _durableCutAttemptProbe:Function = null;

    /**
     * 由 LootContainerService 安装的只读探针。保持依赖单向，避免 AS2 编译器在
     * RewardInboxService 与 LootContainerService 互相解析静态方法时生成残缺 ASO。
     */
    public static function setStandardLaneBusyProbe(probe:Function):Void {
        _standardLaneBusyProbe = probe;
    }

    /** durable-cut 观测探针（存盘次数回归门专用）：每次 flushSave 尝试后以
     * (cutName, ok) 回调；探针异常绝不影响存盘裁决，生产永远为 null。 */
    public static function setDurableCutProbe(probe:Function):Void {
        _durableCutProbe = probe;
    }

    /** durable-cut attempt 预通知（语义故障注入专用）：flushSave 在真实调用
     * _root.强制存盘 前以 cutName 回调，使测试能在真实存盘边界按语义名注入
     * 失败；探针异常绝不影响存盘路径，生产永远为 null。 */
    public static function setDurableCutAttemptProbe(probe:Function):Void {
        _durableCutAttemptProbe = probe;
    }

    /** 换档/新档边界必须丢弃仅属于上一角色会话的 Loot authority。 */
    public static function resetSession():Void {
        _authority = null;
        _snapshotSeq = 0;
        _leaseSeq = 0;
        _rootPersistPending = false;
        _rootPersistPendingId = "";
        _rootPersistVisibleBefore = null;
    }

    /** 时间线只获得这个窄 facade，不允许自行拼待领取批次或存档事务。 */
    public static function installRootFacade():Void {
        if (_root == null) return;
        if (_root.奖励待领取系统 == null
                || typeof _root.奖励待领取系统 != "object") {
            _root.奖励待领取系统 = {};
        }
        _root.奖励待领取系统.投送在线补给包 = function(packName:String,
                                                       sourceKey:String):Object {
            return org.flashNight.arki.item.RewardInboxService
                .deliverOnlineSupplyPack(packName, sourceKey);
        };
        _root.奖励待领取系统.在线补给包已投送 = function(sourceKey:String):Boolean {
            return org.flashNight.arki.item.RewardInboxService
                .hasDeliveredOnlineSupplyPack(sourceKey);
        };
        _root.奖励待领取系统.打开待领取界面 = function():Boolean {
            return org.flashNight.arki.item.RewardInboxService
                .requestOpenPanel();
        };
    }

    /**
     * 世界投送点在批次已经持久化后，通过严格 reward authority 请求现役 Loot 面板。
     * 打开失败不回滚奖励；玩家仍可从角色构筑的“待领取”入口继续领取。
     */
    public static function requestOpenPanel():Boolean {
        var authority:Object = materializeAuthority();
        var transport:Object = _root == null ? null : _root.server;
        if (authority == null || transport == null
                || typeof transport.sendTaskWithCallback != "function") {
            return false;
        }
        var callbackObserved:Boolean = false;
        var callbackAccepted:Boolean = false;
        try {
            transport.sendTaskWithCallback(
                "panel_request",
                {panel:"loot", source:"reward_inbox", initData:authority},
                null,
                function(response:Object):Void {
                    callbackObserved = true;
                    callbackAccepted = response != null
                        && response.success === true
                        && response.accepted === true;
                    if (!callbackAccepted && _root != null
                            && typeof _root.最上层发布文字提示 == "function") {
                        _root.最上层发布文字提示(
                            "在线补给已保存，可从角色构筑的待领取入口领取");
                    }
                },
                600
            );
        } catch (panelOpenError) {
            return false;
        }
        return !callbackObserved || callbackAccepted;
    }

    /**
     * 圣诞树在线补给的唯一写入口。sourceKey 只接受固定五档窗口键，并在每次
     * Flash 运行 token 内幂等；每次成功只追加一个补给包物品 occurrence，
     * 并在返回前完成 dirty + 强制存盘。
     */
    public static function deliverOnlineSupplyPack(packName:String,
                                                    sourceKey:String):Object {
        if (!isOnlineSupplyPair(packName, sourceKey)
                || !ItemUtil.isItem(packName)) {
            return {success:false, error:"invalid_supply_delivery"};
        }
        var feature:Object = ensureFeature();
        if (feature == null) return {success:false, error:"service_not_ready"};
        if (inspectRootLane(feature).quarantined === true) {
            return {success:false, error:"reward_lane_quarantined"};
        }
        var sessionPrefix:String = supplySessionPrefix();
        var deliveryKey:String = sessionPrefix + sourceKey;
        if (containsString(feature.supplyKeys, deliveryKey)) {
            return {success:true, duplicate:true,
                batchId:findBatchIdByOperation(feature, deliveryKey)};
        }
        if (remainingCount(feature) >= MAX_OCCURRENCES) {
            return {success:false, error:"reward_inbox_full"};
        }
        var featureBefore:Object = ObjectUtil.clone(feature);
        var dirtyBefore = _root.存档系统 == null
            ? undefined : _root.存档系统.dirtyMark;
        // 旧在线奖励是每次 Flash 运行重置的会话奖励。当前存档
        // 首次投送时只保留本进程 token 的索引，使 supplyKeys 永远最多 5 项。
        if (!containsPrefix(feature.supplyKeys, sessionPrefix)) feature.supplyKeys = [];
        var batchId:String = nextBatchId(feature, "supply");
        feature.batches.push({batchId:batchId, sourceKind:"online_supply",
            sourceItemName:packName, openOperationId:deliveryKey,
            entries:[{entryId:batchId + ".e1", itemName:packName,
                quantity:1, remaining:1}]});
        feature.supplyKeys.push(deliveryKey);
        feature.authorityRevision++;
        if (!markDirty() || !flushSave("supply_delivery")) {
            _root._saveExt.rewardInbox = featureBefore;
            if (_root.存档系统 != null) {
                _root.存档系统.dirtyMark = dirtyBefore;
            }
            return {success:false, error:"commit_pending"};
        }
        return {success:true, duplicate:false, batchId:batchId};
    }

    /** 时间线的只读幂等探针；严格 sourceKey 失配或存档形状异常时 fail-closed。 */
    public static function hasDeliveredOnlineSupplyPack(sourceKey:String):Boolean {
        if (!isOnlineSupplySourceKey(sourceKey) || _root == null
                || _root._saveExt == null || typeof _root._saveExt != "object") {
            return false;
        }
        var feature:Object = _root._saveExt.rewardInbox;
        if (feature == null || typeof feature != "object" || feature.v != VERSION
                || !(feature.supplyKeys instanceof Array)) return false;
        return containsString(feature.supplyKeys, supplySessionPrefix() + sourceKey);
    }

    /** SOL migrate 与 Protocol 2 _applyCore 共用的纯数据 normalizer。 */
    public static function normalizeSaveData(mydata:Object):Object {
        if (mydata == null || mydata.inventory == null
                || mydata.inventory.装备栏 == null) {
            return {ok:false, changed:false, error:"missing_inventory"};
        }
        var changed:Boolean = false;
        if (mydata.ext == null || typeof mydata.ext != "object") {
            mydata.ext = {};
            changed = true;
        }
        var normalized:Object = normalizeFeature(mydata.ext.rewardInbox);
        if (!normalized.ok) return {ok:false, changed:changed, error:normalized.error};
        mydata.ext.rewardInbox = normalized.feature;
        if (normalized.changed) changed = true;

        var grenade:Object = mydata.inventory.装备栏.手雷;
        if (grenade == null || typeof grenade.name != "string") {
            return normalizedResult(normalized, changed);
        }
        var itemName:String = String(grenade.name);
        if (isLegacyTombstone(itemName)) {
            delete mydata.inventory.装备栏.手雷;
            return normalizedResult(normalized, true);
        }
        if (!isLegacyCarrier(itemName)) return normalizedResult(normalized, changed);
        var quantity:Number = Number(grenade.value);
        if (!positiveWhole(quantity)) {
            delete mydata.inventory.装备栏.手雷;
            return normalizedResult(normalized, true);
        }

        var migrationKey:String = "legacy_grenade_slot_recovery";
        if (!containsString(normalized.feature.migrations, migrationKey)) {
            if (remainingCount(normalized.feature) >= MAX_OCCURRENCES) {
                // 禁止截断或丢弃旧槽资产。
                var deferred:Object = normalizedResult(normalized, changed);
                deferred.deferred = true;
                deferred.error = "reward_inbox_full";
                return deferred;
            }
            var batchId:String = nextBatchId(normalized.feature, "legacy");
            normalized.feature.batches.push({
                batchId:batchId,
                sourceKind:"legacy_grenade_slot_recovery",
                sourceItemName:itemName,
                openOperationId:migrationKey,
                entries:[{entryId:batchId + ".e1", itemName:itemName,
                    quantity:quantity, remaining:quantity}]
            });
            normalized.feature.migrations.push(migrationKey);
            normalized.feature.authorityRevision++;
        }
        // 只有批次已存在/已创建时才清理旧槽。
        delete mydata.inventory.装备栏.手雷;
        return normalizedResult(normalized, true);
    }

    /** nested future/malformed root 只隔离 Reward lane，并把诊断传给存档调用方。 */
    private static function normalizedResult(normalized:Object,
                                             changed:Boolean):Object {
        return {ok:true, changed:changed,
            quarantined:normalized != null && normalized.quarantined === true,
            diagnostic:normalized == null ? "" : String(normalized.diagnostic || "")};
    }

    public static function ensureFeature():Object {
        if (_root._saveExt == null || typeof _root._saveExt != "object") {
            _root._saveExt = {};
        }
        var normalized:Object = normalizeFeature(_root._saveExt.rewardInbox);
        if (!normalized.ok) return null;
        _root._saveExt.rewardInbox = normalized.feature;
        return normalized.feature;
    }

    public static function canAppendOccurrenceCount(count:Number):Boolean {
        var feature:Object = ensureFeature();
        return nonNegativeWhole(count) && feature != null
            && inspectRootLane(feature).quarantined !== true
            && remainingCount(feature) + count <= MAX_OCCURRENCES;
    }

    /** RNG 已由 ItemUseService 冻结；本方法只追加 manifest。 */
    public static function appendRewardBatch(sourceItemName:String,
                                             operationId:String,
                                             rolledEntries:Array):Object {
        var feature:Object = ensureFeature();
        if (feature == null) return {success:false, error:"service_not_ready"};
        if (inspectRootLane(feature).quarantined === true) {
            return {success:false, error:"reward_lane_quarantined"};
        }
        if (!(rolledEntries instanceof Array)
                || rolledEntries.length > MAX_OCCURRENCES
                || !canAppendOccurrenceCount(rolledEntries.length)) {
            return {success:false, error:"reward_inbox_full"};
        }
        var batchId:String = nextBatchId(feature, "open");
        var entries:Array = [];
        for (var i:Number = 0; i < rolledEntries.length; i++) {
            var rolled:Object = rolledEntries[i];
            if (rolled == null || typeof rolled.itemName != "string"
                    || !positiveWhole(Number(rolled.quantity))) {
                return {success:false, error:"invalid_reward_pack"};
            }
            entries.push({entryId:batchId + ".e" + String(i + 1),
                itemName:String(rolled.itemName), quantity:Number(rolled.quantity),
                remaining:Number(rolled.quantity)});
        }
        // independent 允许本次 0 个命中；空批次只由 open receipt 记录。
        if (entries.length > 0) {
            feature.batches.push({batchId:batchId, sourceKind:"item_use",
                sourceItemName:sourceItemName, openOperationId:operationId,
                entries:entries});
            feature.authorityRevision++;
        }
        return {success:true, batchId:batchId, entryCount:entries.length};
    }

    public static function recordReceipt(receipt:Object):Boolean {
        var feature:Object = ensureFeature();
        if (feature == null || receipt == null
                || inspectRootLane(feature).quarantined === true
                || typeof receipt.operationId != "string"
                || findReceipt(feature, String(receipt.operationId)) != null) return false;
        feature.receipts.push(receipt);
        while (feature.receipts.length > MAX_RECEIPTS) feature.receipts.shift();
        return true;
    }

    public static function lookupReceipt(operationId:String):Object {
        var feature:Object = ensureFeature();
        return feature == null ? null : findReceipt(feature, operationId);
    }

    public static function inboxSummary():Object {
        var feature:Object = ensureFeature();
        if (feature == null) return null;
        var discovery:Object = rootDiscovery(feature);
        return {v:VERSION,
            batchCount:pendingBatchCount(feature),
            remainingCount:remainingCount(feature), capacity:MAX_OCCURRENCES,
            authorityRevision:Number(feature.authorityRevision),
            recoverableRootOperationId:String(discovery.rootOperationId),
            recoverableRootStatus:String(discovery.rootStatus),
            recoveryRequired:discovery.recoveryRequired === true};
    }

    public static function hasActiveAuthority():Boolean {
        return _authority != null
            && (_authority.state == ACTIVE || _authority.state == PENDING);
    }

    /** 只在现役 Loot lane 空闲时物化，永不覆盖 map/stage authority。 */
    public static function materializeAuthority():Object {
        var feature:Object = ensureFeature();
        if (feature == null) return null;
        var discovery:Object = rootDiscovery(feature);
        // Character Build 的待领取角标会预先物化一次 authority，但此时 Loot
        // 尚未读取 snapshot。若玩家随后继续开礼包，持久 ledger 已扩张，旧的
        // 未打开 authority 不能继续返回，否则 summary 与 authority.remainingCount
        // 会分叉并被 Host 的严格协议拒绝。已经实际服务过 Loot snapshot 的
        // authority 则保持身份稳定，新增批次留到本次面板关闭后再物化。
        if (_authority != null && _authority.state == ACTIVE
                && _authority.opened !== true
                && Number(_authority.featureRevision)
                    != Number(feature.authorityRevision)) {
            _authority = null;
        }
        if (_authority != null && _authority.pendingCommit != null
                && !continuePendingCommit(_authority)) return null;
        if (_authority != null && _authority.pendingPersist != null
                && !finishPendingPersist(_authority)) return null;
        if (remainingCount(feature) <= 0 && discovery.recoveryRequired !== true) return null;
        if (standardLaneBusy()) return null;
        if (_authority != null && _authority.state == ACTIVE) {
            return authorityProjection(_authority);
        }
        if (_authority != null && _authority.state == PENDING) return null;
        var items:Object = {};
        var mappings:Array = [];
        var slot:Number = 0;
        for (var b:Number = 0; b < feature.batches.length; b++) {
            var batch:Object = feature.batches[b];
            if (batch == null || !(batch.entries instanceof Array)) continue;
            for (var e:Number = 0; e < batch.entries.length; e++) {
                var entry:Object = batch.entries[e];
                if (entry == null || !positiveWhole(Number(entry.remaining))) continue;
                var frozen:Object = findFrozenRootEntry(feature, String(entry.entryId));
                var item:Object = frozen != null && frozen.itemData != null
                    ? BaseItem.createFromObject(ObjectUtil.clone(frozen.itemData))
                    : BaseItem.create(String(entry.itemName),
                        Number(entry.remaining), new Date().getTime());
                if (item == null) continue;
                items[String(slot)] = item.toObject();
                mappings[slot] = {batch:batch, entry:entry};
                slot++;
            }
        }
        if (slot <= 0 && discovery.recoveryRequired !== true) return null;
        var capacity:Number = Math.max(8, slot);
        if (capacity > MAX_OCCURRENCES) capacity = MAX_OCCURRENCES;
        _authoritySeq++;
        var stem:String = String(getTimer()) + "." + _authoritySeq;
        _authority = {chestSessionId:"reward." + stem,
            lootContainerId:"reward.inbox." + stem,
            containerEpoch:_authoritySeq, openAttemptSeq:1,
            displayName:"待领取物品", authorityRevision:1,
            featureRevision:Number(feature.authorityRevision), opened:false,
            lastAppliedOperationId:"", closeLease:"close.reward." + stem,
            state:ACTIVE, reason:"", inventory:new ArrayInventory(items, capacity),
            mappings:mappings, operations:{}, pendingCommit:null,
            pendingPersist:null,
            leases:[], leaseRefs:[], leaseVersions:[], leaseSignatures:[],
            recoveryOnly:slot <= 0};
        return authorityProjection(_authority);
    }

    public static function executeLoot(commandName:String, params:Object):Object {
        if (params == null || params.sourceKind !== "reward_inbox") {
            return emptyFailure(params, "invalid_payload");
        }
        var record:Object = _authority;
        if (record == null) { materializeAuthority(); record = _authority; }
        if (record == null) return emptyFailure(params, "authority_unavailable");
        if (!sameIdentity(record, params)) return emptyFailure(params, "invalid_identity");
        if (record.pendingCommit != null && !continuePendingCommit(record)) {
            return commandName == "claim" || commandName == "claimBatch"
                    || commandName == "query"
                ? durableFailureFor(record, durableRequestRootId(commandName, params),
                    "commit_pending")
                : failureFor(record, "commit_pending");
        }
        if (record.pendingPersist != null && !finishPendingPersist(record)) {
            return commandName == "claim" || commandName == "claimBatch"
                    || commandName == "query"
                ? durableFailureFor(record, durableRequestRootId(commandName, params),
                    "commit_pending")
                : failureFor(record, "commit_pending");
        }
        if (commandName == "snapshot") return executeSnapshot(record, params);
        if (commandName == "tooltip") return executeTooltip(record, params);
        if (commandName == "claim") return executeDurableClaim(record, params, false);
        if (commandName == "claimBatch") return executeDurableClaim(record, params, true);
        if (commandName == "close") return executeClose(record, params);
        if (commandName == "query") return executeDurableQuery(record, params);
        return failureFor(record, "unsupported_cmd");
    }

    public static function handlePanelRecovery(params:Object):Object {
        var record:Object = _authority;
        if (record == null || params == null
                || params.sourceKind !== "reward_inbox"
                || !sameIdentity(record, params)
                || Number(params.openAttemptSeq) != record.openAttemptSeq) {
            return {handled:false, recovered:false, reason:"stale_identity"};
        }
        if (record.state == PENDING || record.pendingCommit != null
                || record.pendingPersist != null) {
            return {handled:true, recovered:false, suspended:false,
                reason:"commit_pending"};
        }
        record.state = SUSPENDED;
        record.reason = String(params.reason || "web_open_failed");
        record.closeLease = "";
        record.authorityRevision++;
        invalidateLeases(record);
        return {handled:true, recovered:true, suspended:true, reason:record.reason};
    }

    private static function executeSnapshot(record:Object, params:Object):Object {
        if (record.state != ACTIVE) return failureFor(record, "terminal_state");
        if (!validWindow(params.loot, record.inventory.capacity, true)
                || !validWindow(params.backpack, 50, false)) {
            return failureFor(record, "invalid_payload");
        }
        record.opened = true;
        return withSnapshots(record);
    }

    private static function executeTooltip(record:Object, params:Object):Object {
        if (record.state != ACTIVE) return failureFor(record, "terminal_state");
        if (!validExpectedRevision(record, params)) return failureFor(record, "stale_state");
        var source:Object = validateTooltipSource(record, params.source);
        if (!source.success) return failureFor(record, source.error);
        var tooltip:Object = buildTooltip(source.item);
        if (tooltip == null) return failureFor(record, "tooltip_failed");
        var response:Object = recordResponse(record, true, "");
        response.tooltip = tooltip;
        return response;
    }

    /** Reward claim/claimBatch 的单 durable root 入口。 */
    private static function executeDurableClaim(record:Object, params:Object,
                                                batch:Boolean):Object {
        var feature:Object = ensureFeature();
        var requestedRootId:String = validOperationId(params.operationId)
            ? String(params.operationId) : "";
        if (feature == null) return durableFailureFor(record, requestedRootId,
            "service_not_ready");
        var lane:Object = inspectRootLane(feature);
        if (lane.quarantined === true) {
            return quarantinedLaneResponse(record, feature, String(lane.error));
        }
        var operationId:String = validOperationId(params.operationId)
                && String(params.operationId).length <= 72
            ? String(params.operationId) : "";
        if (operationId == "") return durableFailureFor(record, "",
            "invalid_operation_id");
        if (!hasOwnField(params, "previousTerminalRootOperationId")
                || typeof params.previousTerminalRootOperationId != "string"
                || String(params.previousTerminalRootOperationId).length > 72
                || (String(params.previousTerminalRootOperationId) != ""
                    && !validOperationId(String(params.previousTerminalRootOperationId)))) {
            return durableFailureFor(record, operationId, "invalid_payload");
        }
        var predecessor:String = String(params.previousTerminalRootOperationId);
        var active:Object = feature.activeClaimRoot;
        var terminal:Object = feature.claimRootTerminal;
        var commandKind:String = batch ? "claimBatch" : "claim";

        if (active != null) {
            if (String(active.rootOperationId) != operationId) {
                return exactRootResponse(record, visibleActiveRoot(feature), false,
                    "active_root_conflict", false);
            }
            var duplicateFingerprint:String = fingerprintExistingRequest(
                record, params, batch, active);
            if (String(active.commandKind) != commandKind
                    || predecessor != String(active.previousTerminalRootOperationId)
                    || duplicateFingerprint == ""
                    || duplicateFingerprint != String(active.requestFingerprint)) {
                return exactRootResponse(record, visibleActiveRoot(feature), false,
                    "operation_conflict", false);
            }
            advanceActiveRoot(record, feature);
            var duplicateCurrent:Object = feature.activeClaimRoot != null
                ? visibleActiveRoot(feature) : feature.claimRootTerminal;
            var duplicatePending:Boolean = duplicateCurrent != null
                && duplicateCurrent.rootStatus == "pending";
            return exactRootResponse(record, duplicateCurrent,
                duplicateCurrent != null && duplicateCurrent.rootStatus == "committed",
                _rootPersistPending || duplicatePending ? "commit_pending" : "", false);
        }
        if (terminal != null && String(terminal.rootOperationId) == operationId) {
            var terminalFingerprint:String = fingerprintExistingRequest(
                record, params, batch, terminal);
            if (String(terminal.commandKind) != commandKind
                    || predecessor != String(terminal.previousTerminalRootOperationId)
                    || terminalFingerprint == ""
                    || terminalFingerprint != String(terminal.requestFingerprint)) {
                return exactRootResponse(record, terminal, false,
                    "operation_conflict", false);
            }
            return exactRootResponse(record, terminal,
                terminal.rootStatus == "committed", String(terminal.error || ""), false);
        }
        if (CLAIM_ROOT_ADMISSION_ENABLED !== true) {
            return durableFailureFor(record, operationId, "root_admission_disabled");
        }
        if (record.state != ACTIVE) return durableFailureFor(record, operationId,
            "terminal_state");
        if (!validExpectedRevision(record, params)) return durableFailureFor(record,
            operationId, "stale_state");
        if (params.direction !== "loot_to_player"
                || params.targetContainerId !== "自动") {
            return durableFailureFor(record, operationId, "transfer_forbidden");
        }
        if ((terminal == null && predecessor != "")
                || (terminal != null
                    && predecessor != String(terminal.rootOperationId))) {
            return durableFailureFor(record, operationId, "predecessor_conflict");
        }

        var frozen:Object = freezeRequestedEntries(record, params, batch);
        if (frozen == null || frozen.success !== true) {
            return durableFailureFor(record, operationId, frozen == null
                ? "invalid_payload" : String(frozen.error));
        }
        var root:Object = {
            claimRootSchemaVersion:CLAIM_ROOT_SCHEMA_VERSION,
            rootOperationId:operationId,
            commandKind:commandKind,
            requestFingerprint:String(frozen.fingerprint),
            previousTerminalRootOperationId:predecessor,
            orderedEntries:frozen.entries,
            cursor:0,
            appliedCount:0,
            rootStatus:"pending",
            childOrdinal:0,
            childDescriptor:null,
            result:{appliedEntryIds:[], blockedEntries:[],
                remainingEntryIds:entryIds(frozen.entries)},
            error:"",
            stopReason:""
        };
        root.childDescriptor = prepareRootChild(record, root, 0);
        if (root.childDescriptor == null) {
            root.childDescriptor = decisionDescriptor(root.orderedEntries[0],
                "quarantined", "descriptor_unavailable");
        }

        var dirtyBefore = _root.存档系统 == null
            ? undefined : _root.存档系统.dirtyMark;
        var priorActive:Object = feature.activeClaimRoot;
        var priorTerminal:Object = feature.claimRootTerminal;
        feature.activeClaimRoot = root;
        feature.claimRootTerminal = null;
        feature.authorityRevision++;
        if (!markDirty() || !flushSave("root_admission")) {
            feature.activeClaimRoot = priorActive;
            feature.claimRootTerminal = priorTerminal;
            feature.authorityRevision--;
            if (_root.存档系统 != null) _root.存档系统.dirtyMark = dirtyBefore;
            return durableFailureFor(record, operationId, "commit_pending");
        }
        advanceActiveRoot(record, feature);
        var current:Object = feature.activeClaimRoot != null
            ? visibleActiveRoot(feature) : feature.claimRootTerminal;
        var currentPending:Boolean = current != null && current.rootStatus == "pending";
        return exactRootResponse(record, current,
            current != null && current.rootStatus == "committed",
            _rootPersistPending || currentPending
                ? "commit_pending" : String(current.error || ""), false);
    }

    /** Reward-only exact query；只 forward-complete 已 durable root。 */
    private static function executeDurableQuery(record:Object, params:Object):Object {
        var feature:Object = ensureFeature();
        var requestedRootId:String = validOperationId(params.rootOperationId)
            ? String(params.rootOperationId) : "";
        if (feature == null) return durableFailureFor(record, requestedRootId,
            "service_not_ready");
        var lane:Object = inspectRootLane(feature);
        if (lane.quarantined === true) {
            return quarantinedLaneResponse(record, feature, String(lane.error));
        }
        if (!validOperationId(params.rootOperationId)
                || String(params.rootOperationId).length > 72) {
            return durableFailureFor(record, "", "invalid_root_operation_id");
        }
        var rootId:String = String(params.rootOperationId);
        var hasAck:Boolean = hasOwnField(params, "acknowledgeTerminalRootOperationId");
        var ackId:String = hasAck ? String(params.acknowledgeTerminalRootOperationId) : "";
        if (hasAck && (!validOperationId(params.acknowledgeTerminalRootOperationId)
                || ackId != rootId)) return durableFailureFor(record, rootId,
                    "invalid_terminal_ack");

        var active:Object = feature.activeClaimRoot;
        if (active != null && String(active.rootOperationId) == rootId) {
            if (hasAck) return exactRootResponse(record, visibleActiveRoot(feature), false,
                "invalid_terminal_ack", true);
            advanceActiveRoot(record, feature);
            var current:Object = feature.activeClaimRoot != null
                ? visibleActiveRoot(feature) : feature.claimRootTerminal;
            return exactRootResponse(record, current, true,
                _rootPersistPending ? "commit_pending" : "", true);
        }
        var terminal:Object = feature.claimRootTerminal;
        if (terminal != null && String(terminal.rootOperationId) == rootId) {
            if (hasAck && terminal.discoveryAcknowledged !== true) {
                var beforeTerminal:Object = ObjectUtil.clone(terminal);
                terminal.discoveryAcknowledged = true;
                feature.authorityRevision++;
                if (!markDirty() || !flushSave("terminal_ack")) {
                    feature.claimRootTerminal = beforeTerminal;
                    feature.authorityRevision--;
                    return exactRootResponse(record, beforeTerminal, false,
                        "commit_pending", true);
                }
            }
            return exactRootResponse(record, feature.claimRootTerminal, true, "", true);
        }
        if (isExpiredRootId(feature, rootId)) {
            return notStartedRootResponse(record, rootId, "operation_expired", false);
        }
        if (hasAck) return notStartedRootResponse(record, rootId,
            "invalid_terminal_ack", false);
        return notStartedRootResponse(record, rootId, "", true);
    }

    /**
     * bounded forward completion；任一 durable cut 失败即停止。
     * F1′（存盘风暴止血 ADR 2026-09-03 §3.1）：post(child i) == pre(child i+1)，
     * child i 的完成态与 child i+1 的纯 prepare 桥接进同一次落盘（child_bridge），
     * 末 child 直接折叠进 terminal 一次落盘；bridge flush 返回 true 前严禁执行
     * 下一 child。admission(A+P0) 与 quarantine 的独立强存盘不变，事件发布仍在
     * durable save 之后。
     */
    private static function advanceActiveRoot(record:Object, feature:Object):Boolean {
        var root:Object = feature.activeClaimRoot;
        if (root == null) return true;
        if (_rootPersistPending
                && _rootPersistPendingId == String(root.rootOperationId)) {
            if (!markDirty() || !flushSave("resume_pending")) return false;
            clearRootPersistPending();
        }
        if (root.rootStatus == "quarantined") return true;
        // F5（ADR §3.2）：entryId→ledger entry 索引每次 advance 建一次；
        // 索引持有 entry 引用，pruneCompletedBatches 不使其失效（已 prune 的
        // entry remaining 恒 0，复用只会 fail-closed 进 quarantine）。
        var ledgerIndex:Object = buildLedgerIndex(feature);
        var guard:Number = 0;
        while (root != null && guard < 64) {
            guard++;
            var cursor:Number = Number(root.cursor);
            if (cursor >= root.orderedEntries.length) {
                return finalizeActiveRoot(record, feature, root);
            }
            if (root.childDescriptor == null) {
                // 纯 prepare 只在内存完成：恢复旧格式 durable prefix（cursor 已前进、
                // descriptor 缺失）与崩溃重放都幂等，descriptor 随下一 cut 落盘。
                prepareChildDescriptor(record, root, cursor);
            }
            var descriptor:Object = root.childDescriptor;
            var decision:String = String(descriptor.decision || "");
            var lastChild:Boolean = cursor + 1 >= root.orderedEntries.length;
            if (decision != "") {
                if (decision == "capacity") {
                    var beforeBlocked:Object = shallowRootCutSnapshot(root);
                    root.result.blockedEntries.push({entryId:String(descriptor.entryId),
                        error:String(descriptor.error)});
                    root.cursor = cursor + 1;
                    root.childOrdinal = Number(root.cursor);
                    root.childDescriptor = null;
                    // F5：capacity 保留 remaining（增量维护），不重扫真账簿。
                    if (lastChild) {
                        return finalizeActiveRoot(record, feature, root);
                    }
                    prepareChildDescriptor(record, root, Number(root.cursor));
                    if (!persistRootProgress(root, beforeBlocked, "child_bridge")) return false;
                    continue;
                }
                if (decision == "failed") {
                    root.error = String(descriptor.error);
                    root.stopReason = "child_failed";
                    // F5：failed 保留 remaining（增量维护），不重扫真账簿。
                    return finalizeActiveRoot(record, feature, root);
                }
                return quarantineActiveRoot(feature, root, String(descriptor.error));
            }
            var source:Object = findLiveSourceByEntryId(record, String(descriptor.entryId));
            if (source == null) {
                return quarantineActiveRoot(feature, root, "source_rebind_conflict");
            }
            var rebound:Object = LootClaimCommitCoordinator.rebindDurableDescriptor(
                descriptor, source);
            if (rebound == null || rebound.success !== true) {
                return quarantineActiveRoot(feature, root, rebound == null
                    ? "descriptor_rebind_failed" : String(rebound.error));
            }
            var pending:Object = rebound.pending;
            var applied:Object = LootClaimCommitCoordinator.applyOrReconcile(pending);
            if (applied == null || applied.success !== true) {
                if (applied != null && applied.quarantined === true) {
                    return quarantineActiveRoot(feature, root, String(applied.error));
                }
                return false;
            }
            var beforeApplied:Object = shallowRootCutSnapshot(root);
            if (!markLedgerEntryClaimed(feature, String(descriptor.entryId),
                    ledgerIndex)) {
                return quarantineActiveRoot(feature, root, "source_ledger_conflict");
            }
            record.featureRevision = Number(feature.authorityRevision);
            root.result.appliedEntryIds.push(String(descriptor.entryId));
            removeRootRemainingId(root, String(descriptor.entryId));
            root.appliedCount = Number(root.appliedCount) + 1;
            root.cursor = cursor + 1;
            root.childOrdinal = Number(root.cursor);
            root.childDescriptor = null;
            record.authorityRevision++;
            record.lastAppliedOperationId = String(root.rootOperationId);
            invalidateLeases(record);
            if (lastChild) {
                // 末 child 直接构造 terminal 并与完成态一次落盘，不先存 cursor=N。
                if (!finalizeActiveRoot(record, feature, root)) return false;
                publishCommitted(applied);
                LootClaimCommitCoordinator.publishAfterDurable(pending);
                return true;
            }
            prepareChildDescriptor(record, root, Number(root.cursor));
            if (!persistRootProgress(root, beforeApplied, "child_bridge")) return false;
            publishCommitted(applied);
            LootClaimCommitCoordinator.publishAfterDurable(pending);
        }
        return false;
    }

    /** child 的纯 prepare：只改内存不落盘，descriptor 随相邻 durable cut 同批持久化。 */
    private static function prepareChildDescriptor(record:Object, root:Object,
                                                   ordinal:Number):Void {
        root.childOrdinal = ordinal;
        root.childDescriptor = prepareRootChild(record, root, ordinal);
        if (root.childDescriptor == null) {
            root.childDescriptor = decisionDescriptor(root.orderedEntries[ordinal],
                "quarantined", "descriptor_unavailable");
        }
    }

    private static function finalizeActiveRoot(record:Object, feature:Object,
                                               root:Object):Boolean {
        // F5：remaining 自 admission 起增量维护，此处与 admission/capacity/failed
        // 语义恒等；唯一真账簿重扫保留在 quarantineActiveRoot。
        var blockedCount:Number = root.result.blockedEntries.length;
        var failed:Boolean = String(root.error) != "";
        var resultKind:String;
        var status:String;
        if (failed) {
            resultKind = Number(root.appliedCount) > 0 ? "partial_failed" : "failed";
            status = "terminal_failure";
        } else if (blockedCount <= 0) {
            resultKind = "all_applied";
            status = "committed";
        } else if (Number(root.appliedCount) > 0) {
            resultKind = "partial_applied";
            status = "committed";
            root.stopReason = "capacity_limited";
        } else {
            resultKind = "no_effect_capacity";
            status = "terminal_failure";
            root.error = String(root.result.blockedEntries[0].error);
            root.stopReason = "capacity_limited";
        }
        var terminal:Object = {
            claimRootSchemaVersion:CLAIM_ROOT_SCHEMA_VERSION,
            rootOperationId:String(root.rootOperationId),
            commandKind:String(root.commandKind),
            requestFingerprint:String(root.requestFingerprint),
            previousTerminalRootOperationId:String(root.previousTerminalRootOperationId),
            orderedEntries:ObjectUtil.clone(root.orderedEntries),
            rootStatus:status,
            resultKind:resultKind,
            discoveryAcknowledged:false,
            result:ObjectUtil.clone(root.result),
            appliedCount:Number(root.appliedCount),
            error:String(root.error),
            stopReason:String(root.stopReason)
        };
        feature.activeClaimRoot = null;
        feature.claimRootTerminal = terminal;
        feature.authorityRevision++;
        if (!markDirty() || !flushSave("terminal")) {
            feature.activeClaimRoot = root;
            feature.claimRootTerminal = null;
            feature.authorityRevision--;
            return false;
        }
        clearRootPersistPending();
        record.lastAppliedOperationId = String(root.rootOperationId);
        return true;
    }

    private static function persistRootProgress(root:Object, before:Object,
                                                cutName:String):Boolean {
        if (markDirty() && flushSave(cutName)) {
            clearRootPersistPending();
            return true;
        }
        _rootPersistPending = true;
        _rootPersistPendingId = String(root.rootOperationId);
        _rootPersistVisibleBefore = before;
        return false;
    }

    private static function clearRootPersistPending():Void {
        _rootPersistPending = false;
        _rootPersistPendingId = "";
        _rootPersistVisibleBefore = null;
    }

    private static function freezeRequestedEntries(record:Object, params:Object,
                                                   batch:Boolean):Object {
        var refs:Array = batch ? params.sources : [params.source];
        if (!(refs instanceof Array) || refs.length < 1 || refs.length > 50) {
            return {success:false, error:"invalid_payload"};
        }
        var entries:Array = [];
        var seen:Object = {};
        for (var i:Number = 0; i < refs.length; i++) {
            var checked:Object = validateLootSource(record, refs[i]);
            if (!checked.success) return checked;
            var mapping:Object = checked.mapping;
            if (mapping == null || mapping.entry == null
                    || typeof mapping.entry.entryId != "string"
                    || !positiveWhole(Number(mapping.entry.remaining))
                    || seen["$" + String(mapping.entry.entryId)] === true
                    || typeof checked.item.toObject != "function") {
                return {success:false, error:"invalid_reward_row"};
            }
            var itemData:Object = checked.item.toObject();
            if (itemData == null || String(itemData.name) != String(mapping.entry.itemName)) {
                return {success:false, error:"invalid_reward_row"};
            }
            var entry:Object = {
                entryId:String(mapping.entry.entryId),
                itemName:String(mapping.entry.itemName),
                quantity:Number(mapping.entry.remaining),
                itemData:ObjectUtil.clone(itemData),
                itemSignature:stableRootItemSignature(itemData),
                admissionSlot:Number(checked.slot)
            };
            seen["$" + entry.entryId] = true;
            entries.push(entry);
        }
        return {success:true, entries:entries,
            fingerprint:buildRootFingerprint(batch ? "claimBatch" : "claim", entries)};
    }

    private static function fingerprintExistingRequest(record:Object, params:Object,
                                                      batch:Boolean,
                                                      root:Object):String {
        if (params.direction !== "loot_to_player" || params.targetContainerId !== "自动") {
            return "";
        }
        var refs:Array = batch ? params.sources : [params.source];
        if (!(refs instanceof Array) || root == null
                || !(root.orderedEntries instanceof Array)
                || refs.length != root.orderedEntries.length) return "";
        var entries:Array = [];
        for (var i:Number = 0; i < refs.length; i++) {
            var ref:Object = refs[i];
            if (ref == null || String(ref.containerId) != record.lootContainerId
                    || !whole(Number(ref.slot))) return "";
            var slot:Number = Number(ref.slot);
            var mapping:Object = record.mappings[slot];
            if (mapping == null || mapping.entry == null) return "";
            var frozen:Object = findOrderedRootEntry(root,
                String(mapping.entry.entryId));
            if (frozen == null) return "";
            entries.push(frozen);
        }
        return buildRootFingerprint(batch ? "claimBatch" : "claim", entries);
    }

    private static function buildRootFingerprint(commandKind:String,
                                                 entries:Array):String {
        var value:String = commandKind + "|automatic";
        for (var i:Number = 0; i < entries.length; i++) {
            value += "|" + String(entries[i].entryId) + ":"
                + String(entries[i].itemSignature);
        }
        return value;
    }

    private static function stableRootItemSignature(itemData:Object):String {
        if (itemData == null) return "invalid";
        return String(itemData.name) + "#" + String(itemData.lastUpdate)
            + "#" + ObjectUtil.toJSON(itemData.value, false);
    }

    private static function entryIds(entries:Array):Array {
        var ids:Array = [];
        for (var i:Number = 0; i < entries.length; i++) {
            ids.push(String(entries[i].entryId));
        }
        return ids;
    }

    private static function prepareRootChild(record:Object, root:Object,
                                             ordinal:Number):Object {
        if (root == null || !(root.orderedEntries instanceof Array)
                || ordinal < 0 || ordinal >= root.orderedEntries.length) return null;
        var entry:Object = root.orderedEntries[ordinal];
        var source:Object = findLiveSourceByEntryId(record, String(entry.entryId));
        if (source == null) return decisionDescriptor(entry,
            "quarantined", "source_rebind_conflict");
        var pending:Object = {
            operationId:String(root.rootOperationId) + ".c" + String(ordinal + 1),
            fingerprint:String(root.requestFingerprint) + "|" + String(ordinal),
            sourceSlot:Number(source.slot),
            sourceItem:source.item,
            sourceVersion:source.inventory.getMutationRevision(),
            feedSource:"reward_inbox",
            feedReason:String(root.commandKind) == "claimBatch" ? "claim_batch" : "claim",
            deferFeed:true,
            forwardOnly:true
        };
        var prepared:Object = LootClaimCommitCoordinator.prepare(
            pending, source, classifyItem(source.item));
        if (prepared == null || prepared.success !== true) {
            var errorCode:String = prepared == null
                ? "descriptor_unavailable" : String(prepared.error);
            return decisionDescriptor(entry,
                capacityFailure(errorCode) ? "capacity" : "failed", errorCode);
        }
        var descriptor:Object = LootClaimCommitCoordinator.exportDurableDescriptor(pending);
        if (descriptor == null) return decisionDescriptor(entry,
            "quarantined", "descriptor_unavailable");
        descriptor.entryId = String(entry.entryId);
        descriptor.itemName = String(entry.itemName);
        descriptor.quantity = Number(entry.quantity);
        descriptor.itemSignature = String(entry.itemSignature);
        descriptor.sourceLedgerBefore = Number(entry.quantity);
        descriptor.sourceLedgerAfter = 0;
        return descriptor;
    }

    private static function decisionDescriptor(entry:Object, decision:String,
                                               errorCode:String):Object {
        return {descriptorSchemaVersion:1, entryId:String(entry.entryId),
            itemName:String(entry.itemName), quantity:Number(entry.quantity),
            itemSignature:String(entry.itemSignature), decision:decision,
            error:errorCode, sourceLedgerBefore:Number(entry.quantity),
            sourceLedgerAfter:0, phase:"PREPARED"};
    }

    private static function findLiveSourceByEntryId(record:Object,
                                                    entryId:String):Object {
        if (record == null || !(record.mappings instanceof Array)
                || record.inventory == null) return null;
        for (var slot:Number = 0; slot < record.mappings.length; slot++) {
            var mapping:Object = record.mappings[slot];
            if (mapping == null || mapping.entry == null
                    || String(mapping.entry.entryId) != entryId) continue;
            var item:Object = record.inventory.getItem(String(slot));
            if (item == null) return null;
            return {success:true, containerId:record.lootContainerId,
                inventory:record.inventory, slot:slot, item:item, mapping:mapping};
        }
        return null;
    }

    private static function markLedgerEntryClaimed(feature:Object,
                                                   entryId:String,
                                                   index:Object):Boolean {
        var entry:Object = index != null
            ? index["$" + entryId] : findLedgerEntry(feature, entryId);
        if (entry == null || !positiveWhole(Number(entry.remaining))) return false;
        entry.remaining = 0;
        pruneCompletedBatches(feature);
        feature.authorityRevision++;
        return true;
    }

    private static function findLedgerEntry(feature:Object, entryId:String):Object {
        if (feature == null || !(feature.batches instanceof Array)) return null;
        for (var b:Number = 0; b < feature.batches.length; b++) {
            var batch:Object = feature.batches[b];
            if (batch == null || !(batch.entries instanceof Array)) continue;
            for (var e:Number = 0; e < batch.entries.length; e++) {
                var entry:Object = batch.entries[e];
                if (entry != null && String(entry.entryId) == entryId) return entry;
            }
        }
        return null;
    }

    private static function buildLedgerIndex(feature:Object):Object {
        var index:Object = {};
        if (feature == null || !(feature.batches instanceof Array)) return index;
        for (var b:Number = 0; b < feature.batches.length; b++) {
            var batch:Object = feature.batches[b];
            if (batch == null || !(batch.entries instanceof Array)) continue;
            for (var e:Number = 0; e < batch.entries.length; e++) {
                var entry:Object = batch.entries[e];
                if (entry != null) index["$" + String(entry.entryId)] = entry;
            }
        }
        return index;
    }

    private static function removeRootRemainingId(root:Object, entryId:String):Void {
        var ids:Array = root.result.remainingEntryIds;
        for (var i:Number = 0; i < ids.length; i++) {
            if (String(ids[i]) == entryId) { ids.splice(i, 1); return; }
        }
    }

    /**
     * F5 窄 staged-root 拷贝：persist 失败时的 durable-prefix 只读视图。
     * orderedEntries 自 admission 冻结故共享引用；result 三数组 slice 防后续
     * push/splice 污染视图；标量显式复制。只用于热路径 persistRootProgress
     * 的 visible-before，quarantine 回滚仍用 ObjectUtil.clone 深拷贝。
     */
    private static function shallowRootCutSnapshot(root:Object):Object {
        return {
            claimRootSchemaVersion:Number(root.claimRootSchemaVersion),
            rootOperationId:String(root.rootOperationId),
            commandKind:String(root.commandKind),
            requestFingerprint:String(root.requestFingerprint),
            previousTerminalRootOperationId:String(root.previousTerminalRootOperationId),
            orderedEntries:root.orderedEntries,
            cursor:Number(root.cursor),
            appliedCount:Number(root.appliedCount),
            rootStatus:String(root.rootStatus),
            childOrdinal:Number(root.childOrdinal),
            childDescriptor:root.childDescriptor,
            result:{
                appliedEntryIds:root.result.appliedEntryIds.slice(),
                blockedEntries:root.result.blockedEntries.slice(),
                remainingEntryIds:root.result.remainingEntryIds.slice()
            },
            error:String(root.error),
            stopReason:String(root.stopReason)
        };
    }

    private static function collectRootRemaining(feature:Object, root:Object):Array {
        var ids:Array = [];
        for (var i:Number = 0; i < root.orderedEntries.length; i++) {
            var id:String = String(root.orderedEntries[i].entryId);
            var entry:Object = findLedgerEntry(feature, id);
            if (entry != null && positiveWhole(Number(entry.remaining))) ids.push(id);
        }
        return ids;
    }

    private static function quarantineActiveRoot(feature:Object, root:Object,
                                                 errorCode:String):Boolean {
        var before:Object = ObjectUtil.clone(root);
        root.rootStatus = "quarantined";
        root.error = errorCode;
        root.stopReason = "invariant_conflict";
        root.result.remainingEntryIds = collectRootRemaining(feature, root);
        feature.authorityRevision++;
        if (!markDirty() || !flushSave("quarantine")) {
            feature.activeClaimRoot = before;
            feature.authorityRevision--;
            return false;
        }
        clearRootPersistPending();
        return true;
    }

    private static function exactRootResponse(record:Object, root:Object,
                                              success:Boolean, errorCode:String,
                                              query:Boolean):Object {
        var status:String = root == null ? "not_started" : String(root.rootStatus);
        var response:Object;
        if (status == "pending" || errorCode == "commit_pending") {
            // 跨 cut 混合投影封死（存盘风暴止血 ADR §3.1 Commit 2）：pending /
            // commit_pending 响应的效果可能已在内存收敛但尚未 durable，durable
            // prefix 的 root 视图配新鲜资产快照就是混合投影。此类响应只携带
            // record 标量与 root tuple；Web 保留旧 projection 仅走 exact-query 恢复。
            response = recordResponse(record, true, "");
            response.snapshots = [];
            response.closeLease = "";
        } else if (record != null && record.state == ACTIVE) {
            response = withSnapshots(record);
        } else {
            response = recordResponse(record, true, "");
        }
        if (response == null) response = recordResponse(record, false,
            "authority_unavailable");
        var resultKind:String = "none";
        if (root != null) {
            if (status == "pending") resultKind = "in_progress";
            else if (status == "quarantined") resultKind = "quarantined";
            else resultKind = String(root.resultKind);
        }
        response.success = query ? true : success;
        response.error = errorCode != "" ? errorCode
            : root == null ? "" : String(root.error || "");
        response.rootOperationId = root == null ? "" : String(root.rootOperationId);
        response.rootStatus = status;
        response.resultKind = resultKind;
        response.result = root == null || root.result == null
            ? emptyRootResult() : ObjectUtil.clone(root.result);
        response.appliedCount = root == null ? 0 : Number(root.appliedCount);
        response.stopReason = root == null ? "" : String(root.stopReason || "");
        return response;
    }

    private static function notStartedRootResponse(record:Object, rootId:String,
                                                   errorCode:String,
                                                   query:Boolean):Object {
        var response:Object = exactRootResponse(record, null,
            errorCode == "", errorCode, query);
        response.rootOperationId = rootId;
        return response;
    }

    private static function durableFailureFor(record:Object, rootId:String,
                                              errorCode:String):Object {
        return notStartedRootResponse(record,
            validOperationId(rootId) ? rootId : "", errorCode, false);
    }

    private static function durableRequestRootId(commandName:String,
                                                 params:Object):String {
        if (params == null) return "";
        var candidate = commandName == "query"
            ? params.rootOperationId : params.operationId;
        return validOperationId(candidate) ? String(candidate) : "";
    }

    private static function quarantinedLaneResponse(record:Object, feature:Object,
                                                    errorCode:String):Object {
        var laneRoot:Object = feature.activeClaimRoot != null
            ? feature.activeClaimRoot : feature.claimRootTerminal;
        var response:Object = recordResponse(record, false, errorCode);
        response.rootOperationId = laneRoot != null
                && validOperationId(laneRoot.rootOperationId)
            ? String(laneRoot.rootOperationId) : "";
        response.rootStatus = "quarantined";
        response.resultKind = "quarantined";
        response.result = emptyRootResult();
        response.appliedCount = 0;
        response.stopReason = errorCode;
        return response;
    }

    private static function emptyRootResult():Object {
        return {appliedEntryIds:[], blockedEntries:[], remainingEntryIds:[]};
    }

    private static function visibleActiveRoot(feature:Object):Object {
        if (_rootPersistPending && _rootPersistVisibleBefore != null
                && feature.activeClaimRoot != null
                && _rootPersistPendingId == String(feature.activeClaimRoot.rootOperationId)) {
            return _rootPersistVisibleBefore;
        }
        return feature.activeClaimRoot;
    }

    private static function rootDiscovery(feature:Object):Object {
        if (feature == null) return {rootOperationId:"", rootStatus:"not_started",
            recoveryRequired:false};
        var lane:Object = inspectRootLane(feature);
        if (lane.quarantined === true) {
            var opaque:Object = feature.activeClaimRoot != null
                ? feature.activeClaimRoot : feature.claimRootTerminal;
            return {rootOperationId:opaque != null && validOperationId(opaque.rootOperationId)
                    ? String(opaque.rootOperationId) : "",
                rootStatus:"quarantined", recoveryRequired:true};
        }
        var active:Object = visibleActiveRoot(feature);
        if (active != null) return {rootOperationId:String(active.rootOperationId),
            rootStatus:String(active.rootStatus), recoveryRequired:true};
        var terminal:Object = feature.claimRootTerminal;
        if (terminal != null) return {rootOperationId:String(terminal.rootOperationId),
            rootStatus:String(terminal.rootStatus),
            recoveryRequired:terminal.discoveryAcknowledged !== true};
        return {rootOperationId:"", rootStatus:"not_started", recoveryRequired:false};
    }

    private static function findFrozenRootEntry(feature:Object,
                                                entryId:String):Object {
        var root:Object = feature == null ? null : feature.activeClaimRoot;
        return findOrderedRootEntry(root, entryId);
    }

    private static function findOrderedRootEntry(root:Object,
                                                entryId:String):Object {
        if (root == null || !(root.orderedEntries instanceof Array)) return null;
        for (var i:Number = 0; i < root.orderedEntries.length; i++) {
            if (String(root.orderedEntries[i].entryId) == entryId) {
                return root.orderedEntries[i];
            }
        }
        return null;
    }

    private static function isExpiredRootId(feature:Object, rootId:String):Boolean {
        var current:Object = feature.activeClaimRoot != null
            ? feature.activeClaimRoot : feature.claimRootTerminal;
        return current != null
            && String(current.previousTerminalRootOperationId) == rootId;
    }

    private static function inspectRootLane(feature:Object):Object {
        if (feature == null) return {quarantined:true, error:"missing_reward_feature"};
        var active:Object = feature.activeClaimRoot;
        var terminal:Object = feature.claimRootTerminal;
        if (active != null && terminal != null) {
            return {quarantined:true, error:"multiple_claim_roots"};
        }
        if (active != null && !validActiveClaimRoot(active)) {
            return {quarantined:true, error:"malformed_active_claim_root"};
        }
        if (terminal != null && !validClaimRootTerminal(terminal)) {
            return {quarantined:true, error:"malformed_claim_root_terminal"};
        }
        return {quarantined:false, error:""};
    }

    private static function validActiveClaimRoot(root:Object):Boolean {
        return root != null && typeof root == "object" && !(root instanceof Array)
            && root.claimRootSchemaVersion == CLAIM_ROOT_SCHEMA_VERSION
            && validOperationId(root.rootOperationId)
            && (root.commandKind == "claim" || root.commandKind == "claimBatch")
            && typeof root.requestFingerprint == "string"
            && typeof root.previousTerminalRootOperationId == "string"
            && (String(root.previousTerminalRootOperationId) == ""
                || validOperationId(root.previousTerminalRootOperationId))
            && root.orderedEntries instanceof Array
            && root.orderedEntries.length >= 1 && root.orderedEntries.length <= 50
            && nonNegativeWhole(Number(root.cursor))
            && Number(root.cursor) <= root.orderedEntries.length
            && nonNegativeWhole(Number(root.appliedCount))
            && (root.rootStatus == "pending" || root.rootStatus == "quarantined")
            && validRootResult(root.result);
    }

    private static function validClaimRootTerminal(root:Object):Boolean {
        return root != null && typeof root == "object" && !(root instanceof Array)
            && root.claimRootSchemaVersion == CLAIM_ROOT_SCHEMA_VERSION
            && validOperationId(root.rootOperationId)
            && (root.commandKind == "claim" || root.commandKind == "claimBatch")
            && typeof root.requestFingerprint == "string"
            && typeof root.previousTerminalRootOperationId == "string"
            && (root.rootStatus == "committed" || root.rootStatus == "terminal_failure")
            && (root.discoveryAcknowledged === true
                || root.discoveryAcknowledged === false)
            && nonNegativeWhole(Number(root.appliedCount))
            && validRootResult(root.result);
    }

    private static function validRootResult(result:Object):Boolean {
        return result != null && typeof result == "object"
            && result.appliedEntryIds instanceof Array
            && result.blockedEntries instanceof Array
            && result.remainingEntryIds instanceof Array;
    }

    private static function hasOwnField(value:Object, key:String):Boolean {
        if (value == null || typeof value != "object") return false;
        if (typeof value.hasOwnProperty == "function") return value.hasOwnProperty(key);
        return value[key] != undefined;
    }

    private static function executeClaim(record:Object, params:Object):Object {
        var operationId:String = validOperationId(params.operationId)
            ? String(params.operationId) : "";
        if (operationId == "") return failureFor(record, "invalid_operation_id");
        var fingerprint:String = claimFingerprint(params);
        var prior:Object = record.operations["$" + operationId];
        if (prior != null) {
            return prior.kind == "claim" && prior.fingerprint == fingerprint
                ? withSnapshots(record) : failureFor(record, "operation_conflict");
        }
        if (record.state != ACTIVE) return failureFor(record, "terminal_state");
        if (!validExpectedRevision(record, params)) return failureFor(record, "stale_state");
        if (params.direction !== "loot_to_player"
                || params.targetContainerId !== "自动") {
            return failureFor(record, "transfer_forbidden");
        }
        var source:Object = validateLootSource(record, params.source);
        if (!source.success) return failureFor(record, source.error);
        record.state = PENDING;
        var pending:Object = {operationId:operationId, fingerprint:fingerprint,
            sourceSlot:source.slot, sourceItem:source.item,
            sourceVersion:source.inventory.getMutationRevision(),
            feedSource:"reward_inbox", feedReason:"claim"};
        var committed:Object = LootClaimCommitCoordinator.begin(
            pending, source, classifyItem(source.item));
        if (committed == null || committed.success !== true) {
            if (committed != null && committed.pending === true) {
                pending.persistKind = "claim";
                record.pendingCommit = pending;
                return failureFor(record, "commit_pending");
            }
            record.state = ACTIVE;
            return failureFor(record, committed == null
                ? "commit_pending" : String(committed.error));
        }
        record.pendingPersist = {kind:"claim", operationId:operationId,
            fingerprint:fingerprint, committed:committed,
            sourceSlot:Number(source.slot), sourceMarked:false};
        if (!finishPendingPersist(record)) return failureFor(record, "commit_pending");
        return withSnapshots(record);
    }

    private static function executeClaimBatch(record:Object, params:Object):Object {
        var operationId:String = validOperationId(params.operationId)
                && String(params.operationId).length <= 72
            ? String(params.operationId) : "";
        if (operationId == "") return failureFor(record, "invalid_operation_id");
        var fingerprint:String = batchFingerprint(params);
        var prior:Object = record.operations["$" + operationId];
        if (prior != null) {
            return prior.kind == "claim_batch" && prior.fingerprint == fingerprint
                ? withSnapshots(record) : failureFor(record, "operation_conflict");
        }
        if (record.state != ACTIVE) return failureFor(record, "terminal_state");
        if (!validExpectedRevision(record, params)) return failureFor(record, "stale_state");
        if (params.direction !== "loot_to_player" || params.targetContainerId !== "自动"
                || !(params.sources instanceof Array) || params.sources.length < 1
                || params.sources.length > 50) return failureFor(record, "invalid_payload");
        var sources:Array = [];
        var seen:Object = {};
        for (var i:Number = 0; i < params.sources.length; i++) {
            var checked:Object = validateLootSource(record, params.sources[i]);
            if (!checked.success) return failureFor(record, checked.error);
            if (seen["$" + checked.slot] === true) return failureFor(record, "invalid_payload");
            seen["$" + checked.slot] = true;
            sources.push(checked);
        }
        record.state = PENDING;
        var applied:Number = 0;
        var capacityError:String = "";
        var stoppedError:String = "";
        for (i = 0; i < sources.length; i++) {
            var source:Object = sources[i];
            if (source.inventory.getItem(String(source.slot)) !== source.item) continue;
            var pending:Object = {operationId:operationId + ".b" + i,
                fingerprint:fingerprint + "|" + i, sourceSlot:source.slot,
                sourceItem:source.item,
                sourceVersion:source.inventory.getMutationRevision(),
                feedSource:"reward_inbox", feedReason:"claim_batch"};
            var committed:Object = LootClaimCommitCoordinator.begin(
                pending, source, classifyItem(source.item));
            if (committed == null || committed.success !== true) {
                var errorCode:String = committed == null
                    ? "commit_pending" : String(committed.error);
                if (capacityFailure(errorCode)) { capacityError = errorCode; continue; }
                if (committed != null && committed.pending === true) {
                    pending.persistKind = "claim_batch_part";
                    record.pendingCommit = pending;
                    return failureFor(record, "commit_pending");
                }
                stoppedError = errorCode;
                break;
            }
            record.pendingPersist = {kind:"claim_batch_part",
                operationId:String(pending.operationId),
                fingerprint:String(pending.fingerprint), committed:committed,
                sourceSlot:Number(source.slot), sourceMarked:false};
            if (!finishPendingPersist(record)) {
                return failureFor(record, "commit_pending");
            }
            applied++;
            record.state = PENDING;
        }
        if (applied <= 0) {
            record.state = ACTIVE;
            return failureFor(record, stoppedError != "" ? stoppedError
                : capacityError == "" ? "target_full" : capacityError);
        }
        record.state = ACTIVE;
        record.lastAppliedOperationId = operationId;
        record.operations["$" + operationId] = {kind:"claim_batch",
            fingerprint:fingerprint, appliedCount:applied,
            authorityRevision:record.authorityRevision};
        return withSnapshots(record);
    }

    private static function executeClose(record:Object, params:Object):Object {
        if (!validOperationId(params.operationId)) return failureFor(record, "invalid_operation_id");
        if (params.abandon !== false) return failureFor(record, "abandon_forbidden");
        if (record.state != ACTIVE) return failureFor(record, "terminal_state");
        if (!validExpectedRevision(record, params)
                || String(params.closeLease) != record.closeLease) {
            return failureFor(record, "stale_state");
        }
        record.lastAppliedOperationId = String(params.operationId);
        record.authorityRevision++;
        record.state = record.inventory.size() <= 0 ? CONSUMED : SUSPENDED;
        record.reason = record.state == CONSUMED ? "empty_close" : "user_suspended";
        record.closeLease = "";
        invalidateLeases(record);
        return recordResponse(record, true, "");
    }

    private static function executeQuery(record:Object):Object {
        return record.state == ACTIVE ? withSnapshots(record)
            : recordResponse(record, true, "");
    }

    /** coordinator 的半提交 journal 留在当前 authority，query 只续跑不重放命令。 */
    private static function continuePendingCommit(record:Object):Boolean {
        var pending:Object = record.pendingCommit;
        if (pending == null) return true;
        var resumed:Object = LootClaimCommitCoordinator.resume(pending);
        if (resumed != null && resumed.success === true) {
            record.pendingCommit = null;
            record.pendingPersist = {kind:String(pending.persistKind || "claim"),
                operationId:String(pending.operationId),
                fingerprint:String(pending.fingerprint), committed:resumed,
                sourceSlot:Number(pending.sourceSlot), sourceMarked:false};
            return finishPendingPersist(record);
        }
        if (resumed != null && resumed.rolledBack === true) {
            record.pendingCommit = null;
            record.state = ACTIVE;
            return true;
        }
        record.state = PENDING;
        return false;
    }

    private static function finishPendingPersist(record:Object):Boolean {
        var pending:Object = record.pendingPersist;
        if (pending == null) return true;
        if (pending.sourceMarked !== true) {
            if (!markClaimed(record, Number(pending.sourceSlot))) return false;
            pending.sourceMarked = true;
            record.authorityRevision++;
            record.lastAppliedOperationId = String(pending.operationId);
            record.operations["$" + String(pending.operationId)] = {
                kind:String(pending.kind), fingerprint:String(pending.fingerprint),
                authorityRevision:record.authorityRevision};
        }
        if (!markDirty() || !flushSave("pending_persist")) return false;
        if (pending.committed != null) publishCommitted(pending.committed);
        record.pendingPersist = null;
        record.state = ACTIVE;
        invalidateLeases(record);
        return true;
    }

    private static function markClaimed(record:Object, slot:Number):Boolean {
        var mapping:Object = record.mappings[slot];
        if (mapping == null || mapping.entry == null) return false;
        mapping.entry.remaining = 0;
        var feature:Object = ensureFeature();
        if (feature == null) return false;
        pruneCompletedBatches(feature);
        feature.authorityRevision++;
        record.featureRevision = Number(feature.authorityRevision);
        return true;
    }

    private static function publishCommitted(committed:Object):Void {
        try {
            if (committed.destinationInventory != null) {
                var containerId:String = String(committed.destinationContainerId);
                InventoryPanelService.invalidateExternalSlot(containerId,
                    Number(committed.destinationSlot));
                committed.destinationInventory.publishTransactionChange(
                    Number(committed.destinationSlot), String(committed.destinationEvent));
            }
        } catch (destinationError) { trace("[RewardInboxService] destination event failed"); }
        try {
            if (committed.collection != null
                    && typeof committed.collection.publishTransactionChanges == "function") {
                committed.collection.publishTransactionChanges(committed.collectionChanges);
            }
        } catch (collectionError) { trace("[RewardInboxService] collection event failed"); }
    }

    private static function withSnapshots(record:Object):Object {
        var response:Object = recordResponse(record, true, "");
        response.snapshots = buildSnapshots(record);
        return response.snapshots == null
            ? failureFor(record, "authority_unavailable") : response;
    }

    private static function buildSnapshots(record:Object):Array {
        if (record == null || record.state != ACTIVE) return null;
        var bag:Object = InventoryPanelService.buildExternalSnapshot("背包", 0, 50);
        var drugs:Object = InventoryPanelService.buildExternalSnapshot("药剂栏", 0, 8);
        if (bag == null || drugs == null) return null;
        stripBalanceSummary(bag); stripBalanceSummary(drugs);
        return [buildLootSnapshot(record), bag, drugs];
    }

    private static function buildLootSnapshot(record:Object):Object {
        var inventory:ArrayInventory = record.inventory;
        var version:Number = inventory.getMutationRevision();
        var slots:Array = [];
        for (var slot:Number = 0; slot < inventory.capacity; slot++) {
            var item:Object = inventory.getItem(String(slot));
            var row:Object = {physicalSlot:slot, occupied:item != null,
                slotLease:issueLease(record, slot, item, version)};
            if (item != null) {
                row.item = InventoryPanelService.buildItemProjection(item);
                if (row.item != null) delete row.item.balanceSummary;
            }
            slots.push(row);
        }
        _snapshotSeq++;
        return {containerId:record.lootContainerId, capacity:inventory.capacity,
            accessibleCapacity:inventory.capacity, viewCapacity:inventory.capacity,
            filterKey:"all", pageSizeHint:inventory.capacity, locked:false,
            snapshotSeq:_snapshotSeq, containerEpoch:record.containerEpoch,
            containerVersion:version, offset:0, limit:slots.length, slots:slots,
            filterFacets:[], filterItemCount:inventory.size(),
            setFacets:[], setFilterItemCount:0};
    }

    private static function validateTooltipSource(record:Object, ref:Object):Object {
        if (ref == null || typeof ref.containerId != "string") {
            return {success:false, error:"invalid_payload"};
        }
        if (String(ref.containerId) == record.lootContainerId) return validateLootSource(record, ref);
        if (String(ref.containerId) != "背包") return {success:false, error:"transfer_forbidden"};
        return InventoryPanelService.validateExternalSlotRef(ref, false);
    }

    private static function validateLootSource(record:Object, ref:Object):Object {
        if (ref == null || String(ref.containerId) != record.lootContainerId
                || !whole(Number(ref.slot)) || typeof ref.expectedLease != "string"
                || !positiveWhole(Number(ref.expectedContainerVersion))) {
            return {success:false, error:"invalid_payload"};
        }
        var slot:Number = Number(ref.slot);
        if (slot < 0 || slot >= record.inventory.capacity) return {success:false, error:"invalid_slot"};
        var version:Number = record.inventory.getMutationRevision();
        if (Number(ref.expectedContainerVersion) != version
                || record.leases[slot] !== ref.expectedLease
                || Number(record.leaseVersions[slot]) != version) {
            return {success:false, error:"stale_state"};
        }
        var item:Object = record.inventory.getItem(String(slot));
        if (item == null || item !== record.leaseRefs[slot]
                || itemSignature(item) != String(record.leaseSignatures[slot])) {
            return {success:false, error:"stale_state"};
        }
        return {success:true, containerId:record.lootContainerId,
            inventory:record.inventory, slot:slot, item:item,
            mapping:record.mappings[slot]};
    }

    private static function buildTooltip(item:Object):Object {
        if (item == null) return null;
        var data:Object = ItemUtil.getItemData(String(item.name));
        if (data == null) return null;
        var projection:Object = InventoryPanelService.buildItemProjection(item);
        var value:Object = typeof item.value == "object" ? item.value : {level:1};
        var equipment = item instanceof BaseItem && typeof item.value == "object"
            ? item : null;
        var desc:String;
        var intro:String;
        try {
            desc = TooltipComposer.generateItemDescriptionText(data, equipment);
            intro = TooltipComposer.generateIntroPanelContent(equipment, data, value);
        } catch (tooltipError) { return null; }
        if (typeof desc != "string" || typeof intro != "string") return null;
        var itemType:String = String(projection.majorType);
        if (itemType == "消耗品" && projection.use != undefined) itemType = String(projection.use);
        return {itemName:String(item.name), displayname:String(projection.displayName),
            iconName:String(projection.icon), itemType:itemType,
            descHTML:desc, introHTML:intro};
    }

    private static function recordResponse(record:Object, success:Boolean,
                                           errorCode:String):Object {
        var terminal:Object = null;
        if (record != null && record.state == CONSUMED) {
            terminal = {kind:String(record.state), reason:String(record.reason),
                remainingCount:record.inventory == null ? 0 : record.inventory.size()};
        }
        return {success:success, error:errorCode,
            chestSessionId:record == null ? "" : String(record.chestSessionId),
            lootContainerId:record == null ? "" : String(record.lootContainerId),
            containerEpoch:record == null ? 0 : Number(record.containerEpoch),
            authorityRevision:record == null ? 0 : Number(record.authorityRevision),
            lastAppliedOperationId:record == null ? "" : String(record.lastAppliedOperationId),
            closeLease:success && record != null && record.state == ACTIVE
                ? String(record.closeLease) : "",
            state:record == null ? "" : String(record.state),
            remainingCount:record == null || record.inventory == null
                ? 0 : record.inventory.size(),
            snapshots:[], tooltip:null, materials:null, terminal:terminal};
    }

    private static function emptyFailure(params:Object, errorCode:String):Object {
        return {success:false, error:errorCode,
            chestSessionId:params == null ? "" : String(params.chestSessionId || ""),
            lootContainerId:params == null ? "" : String(params.lootContainerId || ""),
            containerEpoch:params == null ? 0 : Number(params.containerEpoch || 0),
            authorityRevision:0, lastAppliedOperationId:"", closeLease:"", state:"",
            remainingCount:0, snapshots:[], tooltip:null, materials:null, terminal:null};
    }

    private static function failureFor(record:Object, errorCode:String):Object {
        return recordResponse(record, false, errorCode);
    }

    private static function authorityProjection(record:Object):Object {
        if (record == null || record.state != ACTIVE) return null;
        var feature:Object = ensureFeature();
        var discovery:Object = rootDiscovery(feature);
        return {sourceKind:"reward_inbox",
            chestSessionId:String(record.chestSessionId),
            lootContainerId:String(record.lootContainerId),
            containerEpoch:Number(record.containerEpoch),
            openAttemptSeq:Number(record.openAttemptSeq),
            displayName:String(record.displayName),
            authorityRevision:Number(record.authorityRevision), state:ACTIVE,
            remainingCount:record.inventory.size(), capacity:Number(record.inventory.capacity),
            columns:Math.min(8, Number(record.inventory.capacity)),
            recoverableRootOperationId:String(discovery.rootOperationId),
            recoverableRootStatus:String(discovery.rootStatus),
            recoveryRequired:discovery.recoveryRequired === true,
            recoveryOnly:record.recoveryOnly === true};
    }

    private static function standardLaneBusy():Boolean {
        if (_standardLaneBusyProbe == null) return true;
        try {
            return _standardLaneBusyProbe() === true;
        } catch (probeError) {
            return true;
        }
    }

    private static function normalizeFeature(raw:Object):Object {
        if (raw == null || typeof raw != "object") {
            return {ok:true, changed:true, feature:{v:VERSION, sequence:0,
                authorityRevision:1, batches:[], receipts:[], migrations:[],
                supplyKeys:[], activeClaimRoot:null, claimRootTerminal:null}};
        }
        if (raw.v != VERSION) return {ok:false, changed:false, error:"future_reward_inbox"};
        var changed:Boolean = false;
        if (!(raw.batches instanceof Array)) { raw.batches = []; changed = true; }
        if (!(raw.receipts instanceof Array)) { raw.receipts = []; changed = true; }
        if (!(raw.migrations instanceof Array)) { raw.migrations = []; changed = true; }
        if (!(raw.supplyKeys instanceof Array)) { raw.supplyKeys = []; changed = true; }
        if (!hasOwnField(raw, "activeClaimRoot")) {
            raw.activeClaimRoot = null; changed = true;
        }
        if (!hasOwnField(raw, "claimRootTerminal")) {
            raw.claimRootTerminal = null; changed = true;
        }
        if (!nonNegativeWhole(Number(raw.sequence))) { raw.sequence = 0; changed = true; }
        if (!positiveWhole(Number(raw.authorityRevision))) {
            raw.authorityRevision = 1; changed = true;
        }
        if (normalizeClaimRootResultShapes(raw.activeClaimRoot)) changed = true;
        if (normalizeClaimRootResultShapes(raw.claimRootTerminal)) changed = true;
        var lane:Object = inspectRootLane(raw);
        return {ok:true, changed:changed, feature:raw,
            quarantined:lane.quarantined === true, diagnostic:String(lane.error || "")};
    }

    // AMF0/JSON 存档往返无法保留空数组：空的 appliedEntryIds/blockedEntries/
    // remainingEntryIds 会以空对象 {} 落盘，读回后被 validRootResult 误判为
    // malformed_claim_root_terminal 并 quarantine 整条奖励车道（症状是所有
    // 礼包 open 报 reward_inbox_full）。这里只把"空对象"修复为 []；带键的
    // 非数组仍是真实损坏，继续交给 quarantine。
    private static function normalizeClaimRootResultShapes(root:Object):Boolean {
        if (root == null || root.result == null || typeof root.result != "object") return false;
        var changed:Boolean = false;
        var keys:Array = ["appliedEntryIds", "blockedEntries", "remainingEntryIds"];
        for (var i:Number = 0; i < keys.length; i++) {
            var value:Object = root.result[keys[i]];
            if (value != null && typeof value == "object" && !(value instanceof Array)
                    && emptyOwnObject(value)) {
                root.result[keys[i]] = [];
                changed = true;
            }
        }
        return changed;
    }

    private static function emptyOwnObject(value:Object):Boolean {
        for (var key:String in value) return false;
        return true;
    }

    private static function nextBatchId(feature:Object, prefix:String):String {
        feature.sequence = Number(feature.sequence) + 1;
        return prefix + "." + String(feature.sequence);
    }

    private static function remainingCount(feature:Object):Number {
        var count:Number = 0;
        if (feature == null || !(feature.batches instanceof Array)) return 0;
        for (var b:Number = 0; b < feature.batches.length; b++) {
            var batch:Object = feature.batches[b];
            if (batch == null || !(batch.entries instanceof Array)) continue;
            for (var e:Number = 0; e < batch.entries.length; e++) {
                if (batch.entries[e] != null
                        && positiveWhole(Number(batch.entries[e].remaining))) count++;
            }
        }
        return count;
    }

    private static function pendingBatchCount(feature:Object):Number {
        var count:Number = 0;
        if (feature == null || !(feature.batches instanceof Array)) return 0;
        for (var b:Number = 0; b < feature.batches.length; b++) {
            var batch:Object = feature.batches[b];
            if (batch == null || !(batch.entries instanceof Array)) continue;
            for (var e:Number = 0; e < batch.entries.length; e++) {
                if (batch.entries[e] != null
                        && positiveWhole(Number(batch.entries[e].remaining))) {
                    count++;
                    break;
                }
            }
        }
        return count;
    }

    private static function pruneCompletedBatches(feature:Object):Void {
        var pending:Array = [];
        for (var b:Number = 0; b < feature.batches.length; b++) {
            var batch:Object = feature.batches[b];
            var keep:Boolean = false;
            if (batch != null && batch.entries instanceof Array) {
                for (var e:Number = 0; e < batch.entries.length; e++) {
                    if (batch.entries[e] != null
                            && positiveWhole(Number(batch.entries[e].remaining))) {
                        keep = true; break;
                    }
                }
            }
            if (keep) pending.push(batch);
        }
        feature.batches = pending;
    }

    private static function findReceipt(feature:Object, operationId:String):Object {
        for (var i:Number = feature.receipts.length - 1; i >= 0; i--) {
            var receipt:Object = feature.receipts[i];
            if (receipt != null && String(receipt.operationId) == operationId) return receipt;
        }
        return null;
    }

    private static function isLegacyCarrier(name:String):Boolean {
        return name == "the girl套装包" || name == "红包" || name == "福袋"
            || name == "材料盒子" || name == "普通K点装备盒子"
            || name == "战宠灵石大盒" || name == "感恩节礼包"
            || name == "强化石小盒" || name == "强化石大盒"
            || name == "大礼包" || name == "回馈大礼包" || name == "92套装盒子";
    }

    private static function isLegacyTombstone(name:String):Boolean {
        return name == "新手礼包" || name == "pig套装包"
            || name == "小礼包" || name == "2144新春礼包";
    }

    private static function containsString(values:Array, expected:String):Boolean {
        for (var i:Number = 0; i < values.length; i++) {
            if (String(values[i]) == expected) return true;
        }
        return false;
    }

    private static function containsPrefix(values:Array, expectedPrefix:String):Boolean {
        for (var i:Number = 0; i < values.length; i++) {
            if (String(values[i]).indexOf(expectedPrefix) == 0) return true;
        }
        return false;
    }

    /**
     * 会话 token 只用于区分 Flash 运行，不参与补给计时。
     * AVM1 会把超过 int32 的 Number.toString(36) 饱和成 -2147483648，不能
     * 直接编码毫秒时间；先拆成两个安全整数再编码，且不消费玩家可见随机序列。
     */
    private static function supplySessionPrefix():String {
        if (_supplySessionToken == null) {
            var timestamp:Number = Number(new Date().getTime());
            if (isNaN(timestamp) || timestamp < 0) timestamp = 0;
            timestamp = Math.floor(timestamp);
            var high:Number = Math.floor(timestamp / 1000000);
            var low:Number = timestamp - high * 1000000;
            var token:String = high.toString(36) + "-" + low.toString(36)
                + "-" + _supplyTokenGeneration.toString(36);
            _supplyTokenGeneration++;
            _supplySessionToken = token;
        }
        return "online_supply:" + _supplySessionToken + ":";
    }

    private static function findBatchIdByOperation(feature:Object,
                                                    operationId:String):String {
        for (var i:Number = feature.batches.length - 1; i >= 0; i--) {
            var batch:Object = feature.batches[i];
            if (batch != null && String(batch.openOperationId) == operationId) {
                return String(batch.batchId);
            }
        }
        return "";
    }

    private static function isOnlineSupplyPack(name:String):Boolean {
        return name == "在线补给包·Ⅰ" || name == "在线补给包·Ⅱ"
            || name == "在线补给包·Ⅲ" || name == "在线补给包·Ⅳ"
            || name == "在线补给包·Ⅴ";
    }

    private static function isOnlineSupplySourceKey(value:String):Boolean {
        if (!validSupplySourceKey(value)) return false;
        return value == "christmas_tree:online-10m"
            || value == "christmas_tree:online-20m"
            || value == "christmas_tree:online-40m"
            || value == "christmas_tree:online-60m"
            || value == "christmas_tree:online-120m";
    }

    private static function isOnlineSupplyPair(name:String, sourceKey:String):Boolean {
        if (!isOnlineSupplyPack(name) || !isOnlineSupplySourceKey(sourceKey)) return false;
        return (sourceKey == "christmas_tree:online-10m" && name == "在线补给包·Ⅰ")
            || (sourceKey == "christmas_tree:online-20m" && name == "在线补给包·Ⅱ")
            || (sourceKey == "christmas_tree:online-40m" && name == "在线补给包·Ⅲ")
            || (sourceKey == "christmas_tree:online-60m" && name == "在线补给包·Ⅳ")
            || (sourceKey == "christmas_tree:online-120m" && name == "在线补给包·Ⅴ");
    }

    private static function validSupplySourceKey(value:String):Boolean {
        return typeof value == "string" && String(value).length <= 72
            && validOperationId(String(value));
    }

    private static function sameIdentity(record:Object, params:Object):Boolean {
        return String(params.chestSessionId) == record.chestSessionId
            && String(params.lootContainerId) == record.lootContainerId
            && Number(params.containerEpoch) == record.containerEpoch;
    }

    private static function validExpectedRevision(record:Object, params:Object):Boolean {
        return positiveWhole(Number(params.expectedAuthorityRevision))
            && Number(params.expectedAuthorityRevision) == record.authorityRevision;
    }

    private static function validWindow(window:Object, capacity:Number,
                                        full:Boolean):Boolean {
        if (window == null || !nonNegativeWhole(Number(window.offset))
                || !positiveWhole(Number(window.limit))) return false;
        return full ? Number(window.offset) == 0 && Number(window.limit) == capacity
            : Number(window.offset) < capacity && Number(window.limit) <= capacity;
    }

    private static function issueLease(record:Object, slot:Number,
                                       item:Object, version:Number):String {
        var signature:String = itemSignature(item);
        var current:String = record.leases[slot] == undefined
            ? "" : String(record.leases[slot]);
        if (current != "" && record.leaseRefs[slot] === item
                && Number(record.leaseVersions[slot]) == version
                && String(record.leaseSignatures[slot]) == signature) return current;
        _leaseSeq++;
        var lease:String = record.lootContainerId + ".slot." + slot + "." + _leaseSeq;
        record.leases[slot] = lease;
        record.leaseRefs[slot] = item;
        record.leaseVersions[slot] = version;
        record.leaseSignatures[slot] = signature;
        return lease;
    }

    private static function invalidateLeases(record:Object):Void {
        record.leases = []; record.leaseRefs = [];
        record.leaseVersions = []; record.leaseSignatures = [];
    }

    private static function stripBalanceSummary(snapshot:Object):Void {
        for (var i:Number = 0; i < snapshot.slots.length; i++) {
            if (snapshot.slots[i] != null && snapshot.slots[i].item != null) {
                delete snapshot.slots[i].item.balanceSummary;
            }
        }
    }

    private static function itemSignature(item:Object):String {
        return item == null ? "empty" : String(item.name) + "|"
            + String(item.lastUpdate) + "|" + String(item.value);
    }

    private static function classifyItem(item:Object):String {
        var name:String = String(item.name);
        if (ItemUtil.isMaterial(name)) return "material";
        if (ItemUtil.isInformation(name)) return "information";
        return "ordinary";
    }

    private static function capacityFailure(errorCode:String):Boolean {
        return errorCode == "target_full" || errorCode == "inventory_full"
            || errorCode == "capacity_reached" || errorCode == "cap_reached";
    }

    private static function claimFingerprint(params:Object):String {
        var source:Object = params.source;
        return String(params.direction) + "|" + String(params.targetContainerId) + "|"
            + String(source.containerId) + "|" + String(source.slot) + "|"
            + String(source.expectedLease) + "|" + String(source.expectedContainerVersion);
    }

    private static function batchFingerprint(params:Object):String {
        var result:String = String(params.direction) + "|" + String(params.targetContainerId);
        for (var i:Number = 0; i < params.sources.length; i++) {
            var source:Object = params.sources[i];
            result += "|" + String(source.containerId) + ":" + String(source.slot)
                + ":" + String(source.expectedLease) + ":"
                + String(source.expectedContainerVersion);
        }
        return result;
    }

    private static function validOperationId(value):Boolean {
        if (typeof value != "string") return false;
        var text:String = String(value);
        if (text.length < 1 || text.length > 96) return false;
        for (var i:Number = 0; i < text.length; i++) {
            var code:Number = text.charCodeAt(i);
            var valid:Boolean = (code >= 48 && code <= 57)
                || (code >= 65 && code <= 90) || (code >= 97 && code <= 122)
                || code == 45 || code == 46 || code == 58 || code == 95;
            if (!valid) return false;
        }
        return true;
    }

    private static function markDirty():Boolean {
        if (_root.存档系统 == null) return false;
        _root.存档系统.dirtyMark = true;
        return _root.存档系统.dirtyMark === true;
    }

    private static function flushSave(cutName:String):Boolean {
        if (_durableCutAttemptProbe != null) {
            try { _durableCutAttemptProbe(cutName); }
            catch (attemptProbeError) { }
        }
        var ok:Boolean = false;
        if (typeof _root.强制存盘 == "function") {
            try { ok = _root.强制存盘() === true; }
            catch (saveError) { ok = false; }
        }
        if (_durableCutProbe != null) {
            try { _durableCutProbe(cutName, ok); }
            catch (probeError) { }
        }
        return ok;
    }

    private static function whole(value:Number):Boolean {
        return !isNaN(value) && Math.floor(value) == value;
    }
    private static function nonNegativeWhole(value:Number):Boolean {
        return whole(value) && value >= 0;
    }
    private static function positiveWhole(value:Number):Boolean {
        return whole(value) && value > 0 && value <= 9007199254740991;
    }

    public static function resetForTests():Void {
        resetSession();
        _authoritySeq = 0;
        _supplySessionToken = null;
    }
}
