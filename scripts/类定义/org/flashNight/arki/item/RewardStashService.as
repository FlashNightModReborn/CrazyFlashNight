import org.flashNight.arki.item.RewardStashStore;
import org.flashNight.arki.item.RewardInboxService;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.item.BaseItem;
import org.flashNight.arki.item.InventoryPanelService;
import org.flashNight.arki.item.PlayerAssetTransaction;
import org.flashNight.gesh.object.PersistedSnapshot;
import org.flashNight.neur.Server.SaveManager;

/** 奖励源与 v2 暂存共用的一次候选提交。领域只在 begin/end 之间改写。 */
class org.flashNight.arki.item.RewardStashService {
    private static var _pending:Object = null;
    private static var _sequence:Number = 0;
    public static var lastError:String = "";

    public static function peek():Object {
        var raw:Object = _root._saveExt == null ? null : _root._saveExt.rewardInbox;
        return raw != null && raw.v === 2 ? raw : null;
    }

    /** Queries expose the last committed stock while a full-save candidate is unresolved. */
    public static function committedFeature():Object {
        return _pending == null ? _root._saveExt.rewardInbox : _pending.before.ext.rewardInbox;
    }

    public static function pendingOperationId():String {
        return SaveManager.getInstance().rewardCommitOperationId();
    }

    public static function deliverSupply(packName:String, sourceKey:String, prefix:String):Object {
        var store:Object = peek();
        var legacy:Object = store == null ? _root._saveExt.rewardInbox : store.legacy;
        var key:String = prefix + sourceKey;
        if (pendingOperationId() != "") return {success:false, error:"commit_pending"};
        if (legacy.supplyKeys instanceof Array) {
            for (var i:Number = 0; i < legacy.supplyKeys.length; i++) {
                if (legacy.supplyKeys[i] === key) return {success:true, duplicate:true, batchId:key};
            }
        }
        var context:Object = {source:"online_supply", reason:"supply_delivery", operationId:key};
        if (!begin(key, context, null, null)) return {success:false, error:lastError};
        try {
            var item:BaseItem = BaseItem.create(packName, 1);
            if (item == null || !admit([item.toObject()], false, true, context)) return cancel("invalid_supply_delivery");
            var kept:Array = [];
            var old:Array = peek().legacy.supplyKeys;
            for (var j:Number = 0; j < old.length; j++) {
                if (String(old[j]).indexOf(prefix) == 0) kept.push(old[j]);
            }
            kept.push(key); peek().legacy.supplyKeys = kept;
            return end("supply.v2|" + key + "|" + packName,
                {success:true, duplicate:false, batchId:key}, "reward.supply_delivery");
        } catch (supplyError) { return cancel("invalid_supply_delivery"); }
    }

    public static function nextOperationId(kind:String):String {
        _sequence++;
        return "stash." + kind + "." + new Date().getTime() + "." + _sequence;
    }

    /** 与 legacy root 的写互斥；旧视图、库存非空本身不会拒绝准入。 */
    public static function begin(operationId:String, context:Object,
                                  onResolved:Function, domain:Object):Boolean {
        lastError = "";
        if (_pending != null || SaveManager.getInstance().hasRewardCommitPending()) {
            lastError = "commit_pending"; return false;
        }
        var converted:Object;
        try { converted = buildCandidateStore(); } catch (decodeError) { lastError = "invalid_reward_stash"; return false; }
        if (!converted.success) { lastError = String(converted.error); return false; }
        var snapshot:Object;
        try {
            snapshot = {assets:ItemUtil.capturePlayerAssetSnapshot(),
                ext:_root._saveExt, progress:captureProgress()};
            if (!SaveManager.getInstance().beginRewardCommit(operationId, resolveDomain, null)) {
                lastError = "save_unavailable"; return false;
            }
        } catch (snapshotError) { lastError = "invalid_reward_snapshot"; return false; }
        _pending = {operationId:operationId, before:snapshot,
            onResolved:onResolved, domain:domain, result:null,
            transaction:null};
        try {
            _pending.transaction = PlayerAssetTransaction.begin(context);
            var candidateExt:Object = {};
            for(var key:String in snapshot.ext) if(key != "rewardInbox") candidateExt[key] = PersistedSnapshot.clone(snapshot.ext[key]);
            candidateExt.rewardInbox = converted.store;
            _root._saveExt = candidateExt;
            PlayerAssetTransaction.markDirtyRequired(_root.存档系统);
            return true;
        } catch (prepareError) { lastError = String(cancel("save_unavailable").error); return false; }
    }

    public static function end(fingerprint:String, result:Object, reason:String):Object {
        if (_pending == null) return {success:false, error:"no_reward_candidate"};
        var operationId:String = String(_pending.operationId);
        _pending.result = PersistedSnapshot.clone(result);
        RewardStashStore.recordCommit(peek(), operationId, fingerprint, result);
        var state:String = SaveManager.getInstance().commitRewardCandidate(operationId, reason);
        if (state == "committed") return result;
        if (state == "pending" && _pending != null) {
            PlayerAssetTransaction.parkForDurable(_pending.transaction);
        }
        return {success:false, error:state == "not_committed" ? "save_not_committed" : "commit_pending",
            operationId:operationId};
    }

    public static function cancel(error:String):Object {
        lastError = error;
        if (_pending != null) SaveManager.getInstance().cancelRewardCommit(String(_pending.operationId));
        return {success:false, error:pendingOperationId() != "" ? "commit_pending" : error};
    }

    private static function resolveDomain(committed:Boolean):Boolean {
        var p:Object = _pending;
        if (p == null) return true;
        if (!committed) {
            if (!ItemUtil.restorePlayerAssetSnapshot(p.before.assets)) return false;
            _root._saveExt = PersistedSnapshot.clone(p.before.ext);
            restoreProgress(p.before.progress);
        }
        // 发布已提交资产通知后才进入任务对话/后继任务等可选消费者。
        if (committed) {
            if (p.before.ext.rewardInbox.v !== 2) RewardInboxService.resetSession();
            try { PlayerAssetTransaction.finishDurable(p.transaction, true); }
            catch (publishError) { trace("[RewardStash] committed asset notification: " + publishError); }
        }
        try {
            if (typeof p.onResolved == "function") {
                var domainOk:Object = p.onResolved.call(p.domain, committed, p.domain);
                if (!committed && domainOk === false) return false;
            }
        } catch (callbackError) {
            if (!committed) return false;
            trace("[RewardStash] committed projection failed: " + callbackError);
        }
        try { if (!committed) PlayerAssetTransaction.finishDurable(p.transaction, false); }
        finally { _pending = null; }
        // 槽位修订由权威写推进；租约缓存失效，旧点击不能重用。
        for (var i:Number = 0; i < 50; i++) InventoryPanelService.invalidateExternalSlot("背包", i);
        return true;
    }

    private static function captureProgress():Object {
        var result:Object = {};
        var keys:Array = progressKeys();
        for (var i:Number = 0; i < keys.length; i++) result[keys[i]] = PersistedSnapshot.clone(_root[keys[i]]);
        return result;
    }

    private static function restoreProgress(snapshot:Object):Void {
        var keys:Array = progressKeys();
        for (var i:Number = 0; i < keys.length; i++) _root[keys[i]] = PersistedSnapshot.clone(snapshot[keys[i]]);
    }

    private static function progressKeys():Array {
        return ["经验值", "等级", "技能点数", "身价", "主线任务进度",
            "tasks_to_do", "tasks_finished", "task_chains_progress", "商城已购买物品"];
    }

    /** 新库创建/旧库迁移属于第一次真实写；所有查询都不调用。 */
    private static function buildCandidateStore():Object {
        var current:Object = peek();
        if (current != null) {
            var copy:Object = RewardStashStore.candidate(current);
            var valid:Object = RewardInboxService.validateStashCandidate(copy);
            if (!valid.ok) return {success:false, error:valid.error};
            return {success:true, store:copy};
        }
        var legacyResult:Object = RewardInboxService.exportForStash();
        if (!legacyResult.success) return legacyResult;
        var legacy:Object = legacyResult.feature;
        var store:Object = RewardStashStore.create(nextOperationId("store"), PersistedSnapshot.clone(legacy));
        var items:Array = [];
        for (var b:Number = 0; b < legacy.batches.length; b++) {
            var batch:Object = legacy.batches[b];
            if (batch == null || !(batch.entries instanceof Array)) return {success:false, error:"malformed_legacy_rewards"};
            for (var e:Number = 0; e < batch.entries.length; e++) {
                var entry:Object = batch.entries[e];
                if (entry == null || !RewardStashStore.whole(Number(entry.remaining))) return {success:false, error:"malformed_legacy_rewards"};
                if (Number(entry.remaining) == 0) continue;
                // v1 装备 remaining 是强化度。完整 itemData 优先，不能按它生成多件。
                var rawItem:Object = entry.itemData == null ? null : PersistedSnapshot.clone(entry.itemData);
                if (rawItem != null && ItemUtil.isEquipment(String(rawItem.name))) {
                    if (RewardStashStore.emptyObject(rawItem.value.mods)) rawItem.value.mods = [];
                    if (!RewardStashStore.validItem(rawItem)) return {success:false, error:"malformed_legacy_equipment"};
                }
                var item:BaseItem = rawItem != null
                    ? BaseItem.createFromObject(rawItem)
                    : BaseItem.create(String(entry.itemName), Number(entry.remaining));
                if (item == null) return {success:false, error:"unknown_legacy_reward"};
                if (typeof item.value == "number") item.value = Number(entry.remaining);
                items.push(item.toObject());
            }
        }
        if (!RewardStashStore.append(store, items)) return {success:false, error:"invalid_legacy_rewards"};
        store.legacy.batches = [];
        store.legacy.migrations.push("reward_stash_v2");
        return {success:true, store:store};
    }

    public static function migrate(operationId:String, storeId:String, expectedRevision:Number):Object {
        if (pendingOperationId() != "") return {success:false, error:"commit_pending"};
        var store:Object = peek();
        var op:String = operationId == null ? nextOperationId("migrate") : operationId;
        if (store != null) {
            var checked:Object = RewardStashStore.inspectCommand(store, storeId, expectedRevision, op, "migrate.v2");
            if (checked.state == "committed") return checked.result;
            if (checked.state != "fresh") return {success:false, error:"stale_stash"};
        } else if (storeId != "" || expectedRevision !== 0) return {success:false, error:"stale_stash"};
        var purchased:Object = _root.商城已购买物品;
        if (purchased != null && !(purchased instanceof Array)) {
            if (typeof purchased != "object") return {success:false, error:"invalid_legacy_purchased"};
            for (var malformed:String in purchased) return {success:false, error:"invalid_legacy_purchased"};
            purchased = [];
        }
        var hasLegacy:Boolean = purchased instanceof Array && purchased.length > 0;
        if (store != null && !hasLegacy) return {success:true, migrated:false};
        var shop:Object = _root.UI系统.商城WebView;
        var domain:Object = null;
        var items:Array = [];
        if (hasLegacy) {
            if (shop == null || typeof shop.buildPurchasedSnapshot != "function") return {success:false, error:"service_not_ready"};
            var snapshot:Object = shop.buildPurchasedSnapshot();
            if (snapshot == null || snapshot.success !== true) return {success:false, error:"invalid_legacy_purchased"};
            var count:Number = Math.min(40, snapshot.purchased.length);
            var selected:Array = snapshot.fingerprints.slice(0, count);
            domain = {shop:shop, token:String(shop.purchasedToken), rows:selected, count:count, purchased:purchased};
            for (var k:Number = 0; k < count; k++) {
                var old:Array = snapshot.purchased[k];
                var converted:BaseItem = BaseItem.create(String(old[1]), Number(old[4]));
                if (converted == null || !RewardStashStore.validItem(converted.toObject())) return {success:false, error:"invalid_legacy_purchased"};
                items.push(converted.toObject());
            }
        }
        if (!begin(op, {source:"reward_stash", reason:"legacy_migration", operationId:op}, migrationResolved, domain)) {
            return {success:false, error:lastError};
        }
        try {
            if (domain != null) {
                if (_root.商城已购买物品 !== domain.purchased || String(shop.purchasedToken) !== domain.token) throw new Error("stale_purchased_state");
                // 旧已购物品在购买时已属玩家；这里只搬运，不重新收费/播报获得。
                if (!admit(items, false, false, {source:"legacy_kshop_migration", operationId:op})) throw new Error("invalid_legacy_purchased");
                _root.商城已购买物品 = domain.purchased.slice(domain.count);
                shop.rotatePurchasedToken();
                // packGameState + syncTopLevel 一同覆盖两份镜像；旧 batch receipts 原样保留。
            }
            var migrationResult:Object = {success:true, migrated:true};
            // Bounded source proof is retained with this commit, not as a second stock ledger.
            if (domain != null) peek().legacy.stashMigrationProof = {operationId:op, token:domain.token, rows:domain.rows};
            return end("migrate.v2", migrationResult, "reward.stash_migration");
        } catch (migrationError) { return cancel("invalid_legacy_purchased"); }
    }

    private static function migrationResolved(committed:Boolean, domain:Object):Boolean {
        if (!committed && domain != null) domain.shop.purchasedToken = domain.token;
        return true;
    }

    public static function resume(operationId:String):Object {
        var pending:String = pendingOperationId();
        if (pending == "") return {success:true, state:"settled"};
        if (pending !== operationId) return {success:false, error:"stale_operation"};
        var state:String = SaveManager.getInstance().resolveRewardCommit(pending);
        return state == "committed" || state == "not_committed"
            ? {success:true, state:"settled"} : {success:false, error:"commit_pending"};
    }

    /** 入账时执行情报持有上限；在同一候选里处理接受量与金币折算。 */
    public static function admit(items:Array, preferInventory:Boolean,
                                  acquired:Boolean, context:Object):Boolean {
        if (_pending == null || !(items instanceof Array)) return false;
        var appendItems:Array = [];
        for (var i:Number = 0; i < items.length; i++) {
            var item:Object = PersistedSnapshot.clone(items[i]);
            if (!RewardStashStore.validItem(item) || !ItemUtil.isItem(String(item.name))
                    || ItemUtil.isEquipment(String(item.name)) != (typeof item.value == "object")) return false;
            if (ItemUtil.isInformation(String(item.name)) && acquired) {
                var info:Object = ItemUtil.planInformationAcquire(String(item.name), Number(item.value));
                if (!info.valid) return false;
                if (info.money > 0 && !ItemUtil.acquire([{name:"金币", value:info.money}], context)) return false;
                if (info.accepted <= 0) continue;
                item.value = info.accepted;
            }
            if (preferInventory && moveIntoInventory(item, acquired, context) != null) continue;
            // Ordinary rows are planned once per bounded admission, avoiding one whole-store scan per item.
            if (ItemUtil.isInformation(String(item.name))) {
                if (!RewardStashStore.append(peek(), [item])) return false;
            } else appendItems.push(item);
            if (acquired) PlayerAssetTransaction.recordItems("gain", [{name:item.name,
                value:RewardStashStore.quantity(item), isQuantity:true,
                tier:typeof item.value == "object" ? String(item.value.tier || "") : ""}], context);
        }
        return RewardStashStore.append(peek(), appendItems);
    }

    /** 完整装备写入；数字物品复用现役材料/情报/手雷/药剂 affinity 路由。返回权威落位区域名或 null。 */
    private static function moveIntoInventory(item:Object, acquired:Boolean, context:Object):String {
        var equipment:Boolean = typeof item.value == "object";
        var request:Object = {name:String(item.name), value:equipment ? Number(item.value.level) : Number(item.value),
            ownershipDelta:acquired ? RewardStashStore.quantity(item) : 0};
        var plan:Object = ItemUtil.require([request]);
        if (plan == null) return null;
        var destination:String = plannedDestination(plan, request.name);
        if (destination == null) return null;
        if (!equipment) {
            if (!ItemUtil.acquire([request], context)) throw new Error("stash_inventory_write_inexact");
            return destination;
        }
        var slot:String = null;
        for (var key:String in plan.背包) { slot = key; break; }
        if (slot == null) return null;
        var value:BaseItem = BaseItem.createFromObject(PersistedSnapshot.clone(item));
        var bag:Object = _root.物品栏.背包;
        if (value == null || !bag.add(Number(slot), value)
                || bag.getItem(Number(slot)) !== value) throw new Error("stash_equipment_write_inexact");
        if (acquired) PlayerAssetTransaction.recordItems("gain", [{name:item.name,
            value:1, isQuantity:true, tier:String(item.value.tier || "")}], context);
        return destination;
    }

    /** 单项请求在权威计划中的真实接收区域；未落在任何持有区返回 null。 */
    private static function plannedDestination(plan:Object, itemName:String):String {
        for (var key:String in plan.背包) {
            if (String(plan.背包[key].name) == itemName) return "背包";
        }
        for (key in plan.药剂栏) {
            if (String(plan.药剂栏[key].name) == itemName) return "药剂栏";
        }
        if (plan.材料[itemName] != undefined) return "材料";
        if (plan.情报[itemName] != undefined) return "情报";
        if (plan.装备栏.手雷 != undefined && String(plan.装备栏.手雷.name) == itemName) return "装备栏";
        return null;
    }

    /**
     * 定点领取：目标槽位经库存 lease 精确校验，只允许确可进背包的物品；
     * 空位放入或合法同名堆叠，绝不交换或改投别格。返回 {destination,slot} 或 {reason}。
     */
    private static function placeAtBagTarget(item:Object, quantity:Number, target:Object):Object {
        var checked:Object = InventoryPanelService.validateExternalTargetRef(
            {containerId:"背包", slot:target.slot, expectedLease:target.expectedLease});
        if (checked == null || checked.success !== true) return {reason:"target_stale"};
        var bag:Object = checked.inventory;
        var existing:Object = checked.item;
        var equipment:Boolean = typeof item.value == "object";
        if (existing != null
                && (equipment || typeof existing.value != "number"
                    || String(existing.name) != String(item.name))) return {reason:"target_occupied"};
        // 权威路由先于任何写入：即使目标格躺着异常同名堆，材料/情报/药剂/已装备手雷补堆也绝不定点合并。
        var probe:Object = {name:String(item.name),
            value:equipment ? Number(item.value.level) : quantity, ownershipDelta:0};
        var plan:Object = ItemUtil.require([probe]);
        if (plan == null) return {reason:"inventory_full"};
        if (plannedDestination(plan, probe.name) != "背包") return {reason:"target_incompatible"};
        if (existing != null) {
            var merged:Number = Number(existing.value) + quantity;
            if (!RewardStashStore.whole(merged) || merged < 1) return {reason:"inventory_full"};
            bag.addValue(String(target.slot), quantity);
            var after:Object = bag.getItem(target.slot);
            if (after !== existing || Number(after.value) != merged) {
                throw new Error("stash_target_write_inexact");
            }
            return {destination:"背包", slot:Number(target.slot)};
        }
        var value:BaseItem = equipment
            ? BaseItem.createFromObject(PersistedSnapshot.clone(item))
            : BaseItem.create(String(item.name), quantity, Number(item.lastUpdate));
        if (value == null) return {reason:"target_incompatible"};
        if (!bag.add(target.slot, value) || bag.getItem(target.slot) !== value) {
            throw new Error("stash_target_write_inexact");
        }
        return {destination:"背包", slot:Number(target.slot)};
    }

    public static function takeFingerprint(params:Object):String {
        var rows:Array = ["take.v2", String(params.storeId), Number(params.expectedRevision)];
        // 无 target 的旧请求指纹必须逐字节不变；仅在携带定点目标时附加规范化字段。
        if (params.target !== undefined) {
            rows.push(["target", String(params.target.containerId),
                Number(params.target.slot), String(params.target.expectedLease)]);
        }
        for (var i:Number = 0; i < params.entries.length; i++) {
            var entry:Object = params.entries[i];
            rows.push([String(entry.entryId), Number(entry.revision), Number(entry.quantity)]);
        }
        return new LiteJSON().stringify(rows);
    }

    public static function take(params:Object):Object {
        var store:Object = peek();
        if (!(params.entries instanceof Array) || params.entries.length < 1
                || params.entries.length > RewardStashStore.TAKE_LIMIT) return {success:false, error:"invalid_payload"};
        var target:Object = null;
        if (params.target !== undefined) {
            var rawTarget:Object = params.target;
            var targetKeys:Number = 0;
            for (var targetKey:String in rawTarget) targetKeys++;
            if (params.entries.length != 1 || rawTarget == null || typeof rawTarget != "object"
                    || rawTarget instanceof Array || targetKeys != 3
                    || String(rawTarget.containerId) != "背包"
                    || !RewardStashStore.whole(rawTarget.slot) || rawTarget.slot < 0 || rawTarget.slot >= 50
                    || typeof rawTarget.expectedLease != "string"
                    || rawTarget.expectedLease.length < 1 || rawTarget.expectedLease.length > 160) {
                return {success:false, error:"invalid_payload"};
            }
            target = {containerId:"背包", slot:Number(rawTarget.slot),
                expectedLease:String(rawTarget.expectedLease)};
        }
        var fingerprint:String = takeFingerprint(params);
        var inspected:Object = RewardStashStore.inspectCommand(store, String(params.storeId),
            Number(params.expectedRevision), String(params.operationId), fingerprint);
        if (pendingOperationId() != "") return {success:false, error:"commit_pending"};
        if (inspected.state == "committed") return inspected.result;
        if (inspected.state != "fresh") return {success:false, error:"stale_stash"};
        var seen:Object = {};
        for (var i:Number = 0; i < params.entries.length; i++) {
            var ref:Object = params.entries[i];
            var row:Object = RewardStashStore.find(store, String(ref.entryId));
            if (row == null || seen["$" + ref.entryId] === true || row.revision !== ref.revision
                    || !RewardStashStore.whole(ref.quantity) || ref.quantity < 1
                    || ref.quantity > RewardStashStore.quantity(row.item)) return {success:false, error:"stale_entry"};
            seen["$" + ref.entryId] = true;
        }
        var context:Object = {source:"reward_stash", reason:"stash_take", operationId:String(params.operationId)};
        if (!begin(String(params.operationId), context, null, null)) return {success:false, error:lastError};
        var accepted:Array = [];
        var blocked:Array = [];
        try {
            for (var j:Number = 0; j < params.entries.length; j++) {
                var request:Object = params.entries[j];
                var current:Object = RewardStashStore.find(peek(), String(request.entryId));
                var item:Object = PersistedSnapshot.clone(current.item);
                if (typeof item.value == "number") item.value = Number(request.quantity);
                if (target != null) {
                    var placed:Object = placeAtBagTarget(item, Number(request.quantity), target);
                    if (placed == null || placed.destination == null) {
                        blocked.push({entryId:request.entryId,
                            reason:placed == null ? "target_incompatible" : String(placed.reason)});
                        continue;
                    }
                    if (!RewardStashStore.removeQuantity(peek(), request.entryId, Number(request.quantity))) throw new Error("stash_source_changed");
                    accepted.push({entryId:request.entryId, quantity:Number(request.quantity),
                        destination:String(placed.destination), slot:Number(placed.slot)});
                    continue;
                }
                var destination:String = moveIntoInventory(item, false, context);
                if (destination == null) {
                    blocked.push({entryId:request.entryId, reason:"inventory_full"}); continue;
                }
                if (!RewardStashStore.removeQuantity(peek(), request.entryId, Number(request.quantity))) throw new Error("stash_source_changed");
                accepted.push({entryId:request.entryId, quantity:Number(request.quantity),
                    destination:destination});
            }
        } catch (transferError) { return cancel("stash_write_failed"); }
        var result:Object = {success:true, accepted:accepted, blocked:blocked};
        if (accepted.length == 0) { var cancelled:Object = cancel("inventory_full"); return cancelled.error == "commit_pending" ? cancelled : result; }
        return end(fingerprint, result, "reward.stash_take");
    }

    public static function query(params:Object):Object {
        var pendingId:String = pendingOperationId();
        if (pendingId != "") {
            if (pendingId != String(params.operationId)) return {success:false, error:"commit_pending"};
            var outcome:String = SaveManager.getInstance().resolveRewardCommit(pendingId);
            if (outcome == "not_committed") return {success:true, state:"not_committed"};
            if (outcome != "committed") return {success:false, error:"commit_pending"};
        }
        var store:Object = peek();
        if (store == null) return {success:true, state:params.storeId === "" && params.expectedRevision === 0 ? "not_committed" : "stale"};
        if (store.storeId !== params.storeId && params.storeId !== "") return {success:false, error:"stale_stash"};
        var receipt:Object = store.lastCommit;
        if (receipt != null && receipt.operationId === params.operationId
                && receipt.beforeRevision === params.expectedRevision) {
            return {success:true, state:"committed", result:PersistedSnapshot.clone(receipt.result)};
        }
        return {success:true, state:store.commitRevision === params.expectedRevision ? "not_committed" : "stale"};
    }

    public static function tooltip(params:Object):Object {
        var store:Object = _pending == null ? peek() : _pending.before.ext.rewardInbox;
        if (store == null || store.v !== 2 || store.storeId !== params.storeId) return {success:false, error:"stale_stash"};
        var entry:Object = RewardStashStore.find(store, String(params.entryId));
        if (entry == null || entry.revision !== params.revision) return {success:false, error:"stale_entry"};
        var item:BaseItem = BaseItem.createFromObject(PersistedSnapshot.clone(entry.item));
        var info:Object = InventoryPanelService.buildTooltipProjection(item);
        if (info == null || info.success !== true) return {success:false, error:"tooltip_failed"};
        delete info.success; delete info.v;
        return {success:true, tooltip:info};
    }

    /**
     * 只读页面，固定 32 条窗口；不 ensure/ACK/advance root，也不生成 authority。
     * filterSpec 沿用库存快照同一规范（normalizeItemFilterSpec）：携带时对全量 entries 先
     * 分类再分页，total 为筛选后总数，unfilteredTotal 为原始总数，并附同形状 facets。
     */
    public static function page(offset:Number, filterSpec:Object):Object {
        if (!RewardStashStore.whole(offset)) return {success:false, error:"invalid_payload"};
        var filter:Object = null;
        if (filterSpec !== undefined) {
            filter = InventoryPanelService.normalizeItemFilterSpec(filterSpec);
            if (filter == null) return {success:false, error:"invalid_payload"};
        }
        var raw:Object = committedFeature();
        if (raw != null && (typeof raw != "object" || (raw.v !== 1 && raw.v !== 2)))
            return {success:false, error:"reward_stash_quarantined"};
        var store:Object = raw != null && raw.v === 2 ? raw : null;
        if (store != null && !(store.entries instanceof Array)) return {success:false, error:"reward_stash_quarantined"};
        var legacyStock:Boolean = store == null && RewardInboxService.inboxSummary().remainingCount > 0;
        var result:Object = {success:true, storeId:store == null ? "" : String(store.storeId),
            revision:store == null ? 0 : Number(store.commitRevision), offset:offset,
            total:store == null ? 0 : store.entries.length, entries:[],
            migrationRequired:legacyStock || (_root.商城已购买物品 instanceof Array && _root.商城已购买物品.length > 0), pendingOperationId:pendingOperationId()};
        if (filter != null) {
            result.filterSpec = filter;
            result.unfilteredTotal = result.total;
        }
        if (store == null) {
            if (filter != null) {
                result.filterFacets = []; result.filterItemCount = 0;
                result.setFacets = []; result.setFilterItemCount = 0;
            }
            return result;
        }
        if (filter == null) {
            for (var i:Number = offset; i < Math.min(store.entries.length, offset + RewardStashStore.PAGE_SIZE); i++) {
                var projected:Object = projectPageEntry(store.entries[i]);
                if (projected.error != null) return {success:false, error:projected.error};
                result.entries.push(projected.row);
            }
            return result;
        }
        // 全局筛选：先对全量条目分类收集匹配下标与 facets，再按 offset 取窗口。
        var matches:Array = [];
        var items:Array = [];
        for (var e:Number = 0; e < store.entries.length; e++) {
            var row:Object = store.entries[e];
            if (!RewardStashStore.validItem(row.item)) return {success:false, error:"reward_stash_quarantined"};
            items.push(row.item);
            if (InventoryPanelService.itemMatchesItemFilter(row.item, filter)) matches.push(e);
        }
        var facetData:Object = InventoryPanelService.buildExternalFilterFacets(items);
        result.filterFacets = facetData.facets;
        result.filterItemCount = facetData.itemCount;
        result.setFacets = facetData.setFacets;
        result.setFilterItemCount = facetData.setItemCount;
        result.total = matches.length;
        for (var m:Number = offset; m < Math.min(matches.length, offset + RewardStashStore.PAGE_SIZE); m++) {
            var filtered:Object = projectPageEntry(store.entries[Number(matches[m])]);
            if (filtered.error != null) return {success:false, error:filtered.error};
            result.entries.push(filtered.row);
        }
        return result;
    }

    private static function projectPageEntry(entry:Object):Object {
        if (!RewardStashStore.validItem(entry.item)) return {error:"reward_stash_quarantined"};
        var item:BaseItem = BaseItem.createFromObject(PersistedSnapshot.clone(entry.item));
        if (item == null) return {error:"unknown_stash_item"};
        return {row:{entryId:String(entry.entryId), revision:Number(entry.revision),
            quantity:RewardStashStore.quantity(entry.item),
            item:InventoryPanelService.buildItemProjection(item)}};
    }
}
