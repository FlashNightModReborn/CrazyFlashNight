import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.item.itemCollection.ArrayInventory;

/**
 * Loot claim 的双资源提交协调器。目的写成功、source 删除失败时先尝试回滚；只有观察到
 * exact before 才宣告回滚成功。若 rollback false/throw 且目的仍为 exact after，则保留
 * pendingCommit，下一次同 operation forward-complete source 删除，绝不把半提交当普通失败清掉。
 */
class org.flashNight.arki.item.LootClaimCommitCoordinator {
    private static var MAX_SAFE_INTEGER:Number = 9007199254740991;
    private static var _testFaults:Object = {};
    private static var _testFaultCounts:Object = {};

    public static function begin(pending:Object, source:Object, kind:String):Object {
        if (pending == null || source == null || source.inventory == null || source.item == null) {
            return {success:false, error:"commit_failed"};
        }
        pending.kind = kind;
        pending.sourceInventory = source.inventory;
        pending.sourceSlot = Number(source.slot);
        pending.sourceItem = source.item;
        pending.phase = "PREPARING";
        try {
            if (kind == "ordinary") return beginOrdinary(pending);
            return beginSpecial(pending);
        } catch (commitError) {
            trace("[LootClaimCommitCoordinator] begin failed: " + commitError);
            return reconcileAfterFailure(pending);
        }
    }

    public static function resume(pending:Object):Object {
        if (pending == null || pending.sourceInventory == null || pending.sourceItem == null) {
            return {success:false, error:"commit_failed"};
        }
        try {
            // TestLoader 专用 fault point：模拟进程内连续 query 仍无法观察/续跑 journal。
            // 无注入时 consumeFault 为空，不改变生产提交路径。
            if (consumeFault("resume") != "") {
                return {success:false, error:"commit_pending", pending:true};
            }
            var destinationState:String = observeDestination(pending);
            var sourceState:String = observeSource(pending);
            if (destinationState == "conflict" || sourceState == "conflict") {
                return {success:false, error:"commit_pending", pending:true};
            }
            if (destinationState == "before") {
                if (!applyDestinationAfter(pending)) {
                    return {success:false, error:"commit_pending", pending:true};
                }
                destinationState = observeDestination(pending);
            }
            if (destinationState != "after") {
                return {success:false, error:"commit_pending", pending:true};
            }
            if (sourceState == "present") {
                if (!writeInventory(pending.kind == "ordinary"
                        ? "ordinary_source_write" : "special_source_write",
                        pending.sourceInventory, pending.sourceSlot, null)) {
                    pending.phase = "DESTINATION_APPLIED";
                    return {success:false, error:"commit_pending", pending:true};
                }
                sourceState = observeSource(pending);
            }
            if (sourceState != "empty") {
                return {success:false, error:"commit_pending", pending:true};
            }
            pending.phase = "COMMITTED";
            return successOutcome(pending);
        } catch (resumeError) {
            trace("[LootClaimCommitCoordinator] resume failed: " + resumeError);
            return {success:false, error:"commit_pending", pending:true};
        }
    }

    /**
     * scene cleanup 不能把 destination-after/source-present 的半提交直接丢掉。
     * 先走正常 resume；若包装层仍报告失败，但 destination 已精确落地，则只在 source
     * 仍是 exact item 时做一次无事件删除。无法证明 committed/rolled-back 时保持 pending，
     * 由调用方拒绝终止 authority，而不是冒险遗失持久化与幂等 journal。
     */
    public static function settleForSceneExpiry(pending:Object):Object {
        var resumed:Object = resume(pending);
        if (resumed != null && resumed.success) return resumed;
        try {
            var destinationState:String = observeDestination(pending);
            var sourceState:String = observeSource(pending);
            if (destinationState == "after" && sourceState == "present") {
                if (transactionWriteSafe(pending.sourceInventory, pending.sourceSlot, null)) {
                    sourceState = observeSource(pending);
                }
            }
            if (destinationState == "after" && sourceState == "empty") {
                pending.phase = "COMMITTED_ON_SCENE_EXPIRY";
                return successOutcome(pending);
            }
            if (destinationState == "before" && sourceState == "present") {
                pending.phase = "ROLLED_BACK";
                return {success:false, error:"commit_failed", rolledBack:true};
            }
        } catch (settleError) {
            trace("[LootClaimCommitCoordinator] scene expiry settle failed: " + settleError);
        }
        pending.phase = "UNCERTAIN";
        return {success:false, error:"commit_pending", pending:true};
    }

    /** 未预料异常只能在 journal 已足够观察 source/destination 时进入 pending reconcile。 */
    public static function reconcileUnexpectedFailure(pending:Object):Object {
        if (!hasObservableJournal(pending)) {
            return {success:false, error:"commit_failed", rolledBack:true};
        }
        try {
            return reconcileAfterFailure(pending);
        } catch (reconcileError) {
            trace("[LootClaimCommitCoordinator] unexpected reconcile failed: " + reconcileError);
            return {success:false, error:"commit_pending", pending:true};
        }
    }

    private static function beginOrdinary(pending:Object):Object {
        var backpack:ArrayInventory = resolveBackpack();
        if (backpack == null) return {success:false, error:"authority_unavailable"};
        var sourceItem:Object = pending.sourceItem;
        var isStack:Boolean = typeof sourceItem.value == "number";
        var mergeSlot:Number = -1;
        var emptySlot:Number = -1;
        var mergeItem:Object = null;
        for (var slot:Number = 0; slot < backpack.capacity; slot++) {
            var candidate:Object = backpack.getItem(String(slot));
            if (candidate == null) {
                if (emptySlot < 0) emptySlot = slot;
            } else if (isStack && typeof candidate.value == "number"
                    && candidate.name === sourceItem.name) {
                mergeSlot = slot;
                mergeItem = candidate;
                break;
            }
        }

        pending.domain = "ordinary";
        pending.destinationInventory = backpack;
        if (mergeSlot >= 0) {
            var before:Number = Number(mergeItem.value);
            var quantity:Number = Number(sourceItem.value);
            var after:Number = before + quantity;
            if (!isPositiveWhole(before) || !isPositiveWhole(quantity)
                    || !isPositiveWhole(after)) return {success:false, error:"invalid_quantity"};
            pending.destinationKind = "merge";
            pending.destinationSlot = mergeSlot;
            pending.destinationItem = mergeItem;
            pending.destinationBeforeValue = before;
            pending.destinationAfterValue = after;
            pending.outcome = {
                success:true, destinationSlot:mergeSlot,
                destinationInventory:backpack, destinationEvent:"value"
            };
        } else {
            if (emptySlot < 0) return {success:false, error:"target_full"};
            pending.destinationKind = "empty";
            pending.destinationSlot = emptySlot;
            pending.destinationItem = sourceItem;
            pending.outcome = {
                success:true, destinationSlot:emptySlot,
                destinationInventory:backpack, destinationEvent:"added"
            };
        }

        pending.phase = "PREPARED";
        if (!applyDestinationAfter(pending)) return reconcileAfterFailure(pending);
        pending.phase = "DESTINATION_APPLIED";
        if (writeInventory("ordinary_source_write", pending.sourceInventory,
                           pending.sourceSlot, null)) {
            pending.phase = "COMMITTED";
            return successOutcome(pending);
        }
        return rollbackOrPreservePending(pending, "ordinary_rollback");
    }

    private static function beginSpecial(pending:Object):Object {
        var item:Object = pending.sourceItem;
        var quantity:Number = Number(item.value);
        if (!isPositiveWhole(quantity)) return {success:false, error:"invalid_quantity"};
        var kind:String = String(pending.kind);
        var before:Number;
        var after:Number;

        pending.domain = kind == "money" || kind == "kpoints"
            || kind == "experience" || kind == "skill_points" ? "scalar" : "collection";
        pending.destinationName = String(item.name);
        pending.quantity = quantity;
        if (pending.domain == "scalar") {
            if (kind == "experience" && typeof _root.主角是否升级 != "function") {
                return {success:false, error:"authority_unavailable"};
            }
            before = readScalar(kind);
            after = before + quantity;
            if (!isWhole(before) || before < 0 || !isWhole(after)
                    || after > MAX_SAFE_INTEGER) return {success:false, error:"invalid_quantity"};
            pending.destinationBeforeValue = before;
            pending.destinationAfterValue = after;
            pending.outcome = {success:true, postCommitKind:kind};
        } else {
            if (_root.收集品栏 == undefined) return {success:false, error:"authority_unavailable"};
            var collection:Object = kind == "information"
                ? _root.收集品栏.情报 : _root.收集品栏.材料;
            if (collection == null || typeof collection.getValue != "function"
                    || typeof collection.canApplyTransactionDeltas != "function"
                    || typeof collection.transactionApplyDeltas != "function") {
                return {success:false, error:"authority_unavailable"};
            }
            before = Number(collection.getValue(String(item.name)));
            after = before + quantity;
            if (!isWhole(before) || before < 0 || !isWhole(after)
                    || after > MAX_SAFE_INTEGER) return {success:false, error:"invalid_quantity"};
            if (kind == "information") {
                var maximum:Number = Number(ItemUtil.informationMaxValueDict[item.name]);
                if (!isPositiveWhole(maximum)) return {success:false, error:"authority_unavailable"};
                if (after > maximum) return {success:false, error:"cap_reached"};
            }
            pending.destinationCollection = collection;
            pending.destinationBeforeValue = before;
            pending.destinationAfterValue = after;
            pending.outcome = {success:true, collection:collection, collectionChanges:null};
        }

        pending.phase = "PREPARED";
        if (!applyDestinationAfter(pending)) return reconcileAfterFailure(pending);
        pending.phase = "DESTINATION_APPLIED";
        if (writeInventory("special_source_write", pending.sourceInventory,
                           pending.sourceSlot, null)) {
            pending.phase = "COMMITTED";
            return successOutcome(pending);
        }
        return rollbackOrPreservePending(pending, "special_rollback");
    }

    private static function rollbackOrPreservePending(pending:Object,
                                                       rollbackStage:String):Object {
        var rolledBack:Boolean = false;
        try {
            rolledBack = applyDestinationBefore(pending, rollbackStage);
        } catch (rollbackError) {
            trace("[LootClaimCommitCoordinator] rollback failed: " + rollbackError);
            rolledBack = false;
        }
        var destinationState:String = observeDestination(pending);
        var sourceState:String = observeSource(pending);
        if (rolledBack && destinationState == "before" && sourceState == "present") {
            pending.phase = "ROLLED_BACK";
            return {success:false, error:"commit_failed", rolledBack:true};
        }
        if (destinationState == "after" && sourceState == "present") {
            pending.phase = "DESTINATION_APPLIED";
            return {success:false, error:"commit_pending", pending:true};
        }
        // 返回值不可信时以真实观察为准；exact before + exact source 仍可证明已回滚。
        if (destinationState == "before" && sourceState == "present") {
            pending.phase = "ROLLED_BACK";
            return {success:false, error:"commit_failed", rolledBack:true};
        }
        pending.phase = "UNCERTAIN";
        return {success:false, error:"commit_pending", pending:true};
    }

    private static function reconcileAfterFailure(pending:Object):Object {
        var sourceState:String = observeSource(pending);
        if (pending.domain == undefined && sourceState == "present") {
            pending.phase = "ROLLED_BACK";
            return {success:false, error:"commit_failed", rolledBack:true};
        }
        var destinationState:String = observeDestination(pending);
        if (destinationState == "before" && sourceState == "present") {
            pending.phase = "ROLLED_BACK";
            return {success:false, error:"commit_failed", rolledBack:true};
        }
        pending.phase = "UNCERTAIN";
        return {success:false, error:"commit_pending", pending:true};
    }

    private static function applyDestinationAfter(pending:Object):Boolean {
        if (pending.domain == "ordinary") {
            if (pending.destinationKind == "merge") {
                var mergeItem:Object = pending.destinationItem;
                mergeItem.value = pending.destinationAfterValue;
                if (writeInventory("ordinary_destination_write", pending.destinationInventory,
                                   pending.destinationSlot, mergeItem)) return true;
                mergeItem.value = pending.destinationBeforeValue;
                return false;
            }
            return writeInventory("ordinary_destination_write", pending.destinationInventory,
                pending.destinationSlot, pending.destinationItem);
        }
        if (pending.domain == "scalar") {
            writeScalar(pending.kind, pending.destinationAfterValue);
            return readScalar(pending.kind) == pending.destinationAfterValue;
        }
        var delta:Object = {};
        delta[pending.destinationName] = pending.quantity;
        var applied:Object = applyCollection("special_destination_write",
            pending.destinationCollection, delta);
        if (applied == null || applied.success !== true) return false;
        pending.outcome.collectionChanges = applied.changes;
        return observeDestination(pending) == "after";
    }

    private static function applyDestinationBefore(pending:Object, stage:String):Boolean {
        var fault:String = consumeFault(stage);
        if (fault == "throw") throw "injected_" + stage;
        if (fault == "false") return false;
        if (pending.domain == "ordinary") {
            if (pending.destinationKind == "merge") {
                pending.destinationItem.value = pending.destinationBeforeValue;
                return transactionWriteSafe(pending.destinationInventory,
                    pending.destinationSlot, pending.destinationItem);
            }
            return transactionWriteSafe(pending.destinationInventory,
                pending.destinationSlot, null);
        }
        if (pending.domain == "scalar") {
            writeScalar(pending.kind, pending.destinationBeforeValue);
            return readScalar(pending.kind) == pending.destinationBeforeValue;
        }
        var rollback:Object = {};
        rollback[pending.destinationName] = -pending.quantity;
        var result:Object = applyCollectionDirect(pending.destinationCollection, rollback);
        return result != null && result.success === true
            && observeDestination(pending) == "before";
    }

    private static function observeDestination(pending:Object):String {
        if (pending == null || pending.domain == undefined) return "conflict";
        if (pending.domain == "ordinary") {
            var current:Object = pending.destinationInventory.getItem(
                String(pending.destinationSlot));
            if (pending.destinationKind == "empty") {
                if (current == null) return "before";
                return current === pending.destinationItem ? "after" : "conflict";
            }
            if (current !== pending.destinationItem) return "conflict";
            var currentValue:Number = Number(current.value);
            if (currentValue == pending.destinationBeforeValue) return "before";
            if (currentValue == pending.destinationAfterValue) return "after";
            return "conflict";
        }
        var value:Number = pending.domain == "scalar"
            ? readScalar(pending.kind)
            : Number(pending.destinationCollection.getValue(pending.destinationName));
        if (value == pending.destinationBeforeValue) return "before";
        if (value == pending.destinationAfterValue) return "after";
        return "conflict";
    }

    private static function observeSource(pending:Object):String {
        var current:Object = pending.sourceInventory.getItem(String(pending.sourceSlot));
        if (current == null) return "empty";
        return current === pending.sourceItem ? "present" : "conflict";
    }

    private static function hasObservableJournal(pending:Object):Boolean {
        if (pending == null || pending.sourceInventory == null || pending.sourceItem == null
                || !isWhole(pending.sourceSlot)) return false;
        if (pending.domain == "ordinary") {
            return pending.destinationInventory != null
                && (pending.destinationKind == "empty" || pending.destinationKind == "merge")
                && isWhole(pending.destinationSlot) && pending.destinationItem != null;
        }
        if (pending.domain == "scalar") {
            return isWhole(pending.destinationBeforeValue)
                && isWhole(pending.destinationAfterValue);
        }
        if (pending.domain == "collection") {
            return pending.destinationCollection != null
                && typeof pending.destinationName == "string"
                && isWhole(pending.destinationBeforeValue)
                && isWhole(pending.destinationAfterValue);
        }
        return false;
    }

    private static function successOutcome(pending:Object):Object {
        var outcome:Object = pending.outcome;
        if (outcome == null) return {success:false, error:"commit_failed"};
        outcome.success = true;
        // 播报永不破坏提交链路：feed 发射异常只留 trace，不影响已提交结果
        try {
            emitLootFeed(pending);
        } catch (emitError) {
            trace("[LootClaimCommitCoordinator] loot feed emit failed: " + emitError);
        }
        return outcome;
    }

    /**
     * 战利品箱领取成功的 loot feed 播报。统一收口在 successOutcome：begin/resume/
     * settleForSceneExpiry 三条提交路径都经此处。_lootFeedEmitted 防重：pending 理论上
     * 只成功一次，但 resume 可重入，幂等标记保证不会双发卡片。
     * kind 由包装函数按名称自动推导；ordinary 装备透传 tier 解析进阶名/图标。
     */
    private static function emitLootFeed(pending:Object):Void {
        if (pending == null || pending._lootFeedEmitted === true) return;
        pending._lootFeedEmitted = true;
        if (typeof _root.发布战利品消息 != "function") return;

        var kind:String = String(pending.kind);
        if (kind == "ordinary") {
            var item:Object = pending.sourceItem;
            if (item == null) return;
            // 非堆叠装备 value 不是数字（beginOrdinary 的 isStack 同款判据），每件按 1 计
            var claimCount:Number = (typeof item.value == "number") ? Number(item.value) : 1;
            _root.发布战利品消息(null, String(item.name), claimCount, "loot_box", item.tier);
            return;
        }
        var count:Number = Number(pending.quantity);
        if (kind == "money") {
            _root.发布战利品消息("money", "金钱", count, "loot_box");
        } else if (kind == "kpoints") {
            _root.发布战利品消息("kpoint", "K点", count, "loot_box");
        } else {
            // information / 材料 / experience / skill_points：名称自动推导 kind 与图标
            _root.发布战利品消息(null, String(pending.destinationName), count, "loot_box");
        }
    }

    private static function writeInventory(stage:String, inventory:ArrayInventory,
                                           slot:Number, item:Object):Boolean {
        var fault:String = consumeFault(stage);
        if (fault == "false") return false;
        try {
            if (fault == "throw") throw "injected_" + stage;
            var written:Boolean = inventory.transactionWrite(slot, item) === true;
            if (fault == "after_throw") throw "injected_after_" + stage;
            if (fault == "after_false") return false;
            return written;
        } catch (writeError) {
            trace("[LootClaimCommitCoordinator] transactionWrite failed: " + writeError);
            return false;
        }
    }

    private static function transactionWriteSafe(inventory:ArrayInventory,
                                                  slot:Number, item:Object):Boolean {
        try {
            return inventory.transactionWrite(slot, item) === true;
        } catch (writeError) {
            return false;
        }
    }

    private static function applyCollection(stage:String, collection:Object,
                                            delta:Object):Object {
        var fault:String = consumeFault(stage);
        if (fault == "false") return {success:false};
        try {
            if (fault == "throw") throw "injected_" + stage;
            if (!collection.canApplyTransactionDeltas(delta)) return {success:false};
            var applied:Object = collection.transactionApplyDeltas(delta);
            if (fault == "after_throw") throw "injected_after_" + stage;
            if (fault == "after_false") return {success:false};
            return applied;
        } catch (applyError) {
            return {success:false};
        }
    }

    private static function applyCollectionDirect(collection:Object, delta:Object):Object {
        try {
            return collection.transactionApplyDeltas(delta);
        } catch (applyError) {
            return {success:false};
        }
    }

    private static function resolveBackpack():ArrayInventory {
        if (_root.物品栏 == undefined) return null;
        var backpack:ArrayInventory = _root.物品栏.背包;
        return backpack instanceof ArrayInventory ? backpack : null;
    }

    private static function readScalar(kind:String):Number {
        if (kind == "money") return Number(_root.金钱);
        if (kind == "kpoints") return Number(_root.虚拟币);
        if (kind == "experience") return Number(_root.经验值);
        return Number(_root.技能点数);
    }

    private static function writeScalar(kind:String, value:Number):Void {
        if (kind == "money") _root.金钱 = value;
        else if (kind == "kpoints") _root.虚拟币 = value;
        else if (kind == "experience") _root.经验值 = value;
        else _root.技能点数 = value;
    }

    private static function isWhole(value):Boolean {
        return typeof value == "number" && (value - value) == 0 && Math.floor(value) == value;
    }

    private static function isPositiveWhole(value):Boolean {
        return isWhole(value) && Number(value) > 0 && Number(value) <= MAX_SAFE_INTEGER;
    }

    private static function consumeFault(stage:String):String {
        var mode:String = _testFaults[stage];
        if (mode == undefined) return "";
        var remaining:Number = Number(_testFaultCounts[stage]);
        if (!isWhole(remaining) || remaining <= 1) {
            delete _testFaults[stage];
            delete _testFaultCounts[stage];
        } else {
            _testFaultCounts[stage] = remaining - 1;
        }
        return mode;
    }

    public static function testOnlyFailNext(stage:String, mode:String,
                                            repeatCount:Number):Void {
        if (mode != "false" && mode != "throw"
                && mode != "after_false" && mode != "after_throw") return;
        _testFaults[stage] = mode;
        _testFaultCounts[stage] = isWhole(repeatCount)
                && repeatCount > 0 && repeatCount <= 100 ? repeatCount : 1;
    }

    public static function testOnlyReset():Void {
        _testFaults = {};
        _testFaultCounts = {};
    }
}
