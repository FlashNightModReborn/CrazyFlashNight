import org.flashNight.arki.item.ItemUtil;

import org.flashNight.neur.Event.EventBus;

/**
 * 玩家资产已提交回执基座。
 *
 * 本类不接管商店、制作、掉落或换弹的业务规则，也不把位置移动误判为所有权变化。
 * 领域服务仍负责预检、原子写入与回滚；只有在领域确认提交后，才把脱离可变物品
 * 引用的 effect 发布给播报、统计等可选消费者。
 *
 * 显式事务用于制作/交易等复合操作：begin -> record* -> commit/rollback。
 * 没有显式事务时，record* 会创建并立即提交一个短事务，兼容旧 ItemUtil 调用点。
 */
class org.flashNight.arki.item.PlayerAssetTransaction {
    private static var MAX_SAFE_INTEGER:Number = 9007199254740991;
    private static var _stack:Array = [];
    private static var _nextOperation:Number = 1;
    private static var _testSink:Function = null;
    private static var _testStrongSaveSink:Function = null;
    private static var _lastCommittedReceipt:Object = null;

    public static function begin(context:Object):Object {
        var normalized:Object = normalizeContext(context);
        var operationId:String = normalized.operationId;
        if (operationId.length == 0) operationId = nextOperationId();
        var mergeScope:String = normalized.mergeScope;
        if (mergeScope == "operation") mergeScope = operationId;

        var transaction:Object = {
            state:"open",
            operationId:operationId,
            source:normalized.source,
            reason:normalized.reason,
            mergeScope:mergeScope,
            effects:[],
            effectIndex:{},
            authorityWriteObserved:false,
            strongSaveRequested:false,
            strongSaveFlushed:false,
            recoverDispatch:EventBus.getInstance().createDispatchRecoveryToken(),
            startedAt:nowMilliseconds()
        };
        _stack.push(transaction);
        return transaction;
    }

    public static function current():Object {
        if (_stack.length == 0) return null;
        return _stack[_stack.length - 1];
    }

    /** ItemUtil 用于标记回执外的真实写（经验/技能点也属于资产事实）。 */
    public static function markAuthorityWrite(transaction:Object):Void {
        if (transaction != null) transaction.authorityWriteObserved = true;
    }

    public static function hasAuthorityWrite(transaction:Object):Boolean {
        return transaction != null && transaction.authorityWriteObserved === true;
    }

    /**
     * 玩家物资领域首写前的强制存档脏标记。
     *
     * AVM1 对 undefined owner 的成员赋值可能静默跳过，调用方不能再用
     * `_root.存档系统.dirtyMark = true` 充当 fail-fast。这里先验证 owner，
     * 再写入并读回确认；任一失败都必须发生在玩家资产首写之前。
     */
    public static function markDirtyRequired(saveOwner:Object):Void {
        if (saveOwner == undefined || saveOwner == null) {
            throw new Error("player_asset_save_owner_missing");
        }
        saveOwner.dirtyMark = true;
        if (saveOwner.dirtyMark !== true) {
            throw new Error("player_asset_dirty_mark_failed");
        }
    }

    /**
     * 记录一组已实际写入的物品变化。装备默认按一件计数；只有 isQuantity=true
     * 才把 value 解释为装备件数。经验/技能点属于进度聚合，不进入玩家物资回执。
     */
    public static function recordItems(direction:String, itemArray:Array,
                                       context:Object):Void {
        if (!(itemArray instanceof Array) || itemArray.length == 0) return;
        var transaction:Object = current();
        var implicit:Boolean = transaction == null;
        if (implicit) transaction = begin(context);
        var completed:Boolean = false;
        try {
            for (var i:Number = 0; i < itemArray.length; i++) {
                var entry:Object = itemArray[i];
                if (entry == null || entry.name == undefined) continue;
                var name:String = String(entry.name);
                if (name == "经验值" || name == "技能点") continue;

                var kind:String = entry.kind == undefined
                    ? inferKind(name) : String(entry.kind);
                var count:Number;
                // ownershipDelta 允许复合领域把“实际写入数量”与“所有权变化数量”分开。
                // 例如出售装备时拆下的配件只是从装备迁回材料栏，不应伪装成新获得。
                if (entry.ownershipDelta != undefined) {
                    count = Number(entry.ownershipDelta);
                } else if (kind == "equip" && entry.isQuantity !== true) {
                    count = 1;
                } else if (entry.count != undefined) {
                    count = Number(entry.count);
                } else {
                    count = Number(entry.value);
                }
                var rawTier = entry.tier;
                if ((rawTier == undefined || rawTier == null)
                        && typeof entry.value == "object" && entry.value != null) {
                    rawTier = entry.value.tier;
                }
                var tier:String = rawTier == undefined || rawTier == null
                    ? "" : String(rawTier);
                addEffect(transaction, direction, kind, normalizeName(name, kind),
                    count, tier, context);
            }
            completed = true;
        } finally {
            // 显式事务由领域调用方决定 commit/rollback；只有本方法创建的短事务
            // 才在异常时立即丢弃，避免一条坏输入永久占住全局栈顶。
            if (implicit) {
                if (completed) commit(transaction);
                else rollback(transaction);
            }
        }
    }

    /** 记录单个已提交变化；count 永远是正数，方向由 direction 表达。 */
    public static function recordEffect(direction:String, kind:String,
                                        name:String, count:Number,
                                        context:Object):Void {
        var transaction:Object = current();
        var implicit:Boolean = transaction == null;
        if (implicit) transaction = begin(context);
        var completed:Boolean = false;
        try {
            addEffect(transaction, direction, kind, normalizeName(name, kind),
                count, context == null ? "" : String(context.tier || ""), context);
            completed = true;
        } finally {
            if (implicit) {
                if (completed) commit(transaction);
                else rollback(transaction);
            }
        }
    }

    /**
     * 适配仍由领域服务直接持有的货币标量。delta 使用账本符号：正数为获得，
     * 负数为失去；两种货币会进入同一 receipt，不允许调用方再另发 gross/net 卡片。
     */
    public static function recordCurrencyDeltas(moneyDelta:Number,
                                                kpointDelta:Number,
                                                context:Object):Void {
        var transaction:Object = current();
        var implicit:Boolean = transaction == null;
        if (implicit) transaction = begin(context);
        var completed:Boolean = false;
        try {
            addSignedCurrency(transaction, "money", "金钱", moneyDelta, context);
            addSignedCurrency(transaction, "kpoint", "K点", kpointDelta, context);
            completed = true;
        } finally {
            if (implicit) {
                if (completed) commit(transaction);
                else rollback(transaction);
            }
        }
    }

    /**
     * 请求一次升级后的强制存盘。显式资产事务存在时只记录请求，由最外层
     * commit 在领域状态已经完成后执行；无事务时保持旧行为，立即强制存盘。
     */
    public static function requestStrongSave():Void {
        var transaction:Object = current();
        if (transaction != null && transaction.state == "open") {
            transaction.strongSaveRequested = true;
            return;
        }
        performStrongSave();
    }

    /**
     * 显式 durable fence：立即执行一次强制存盘并只返回真实 durable 结果。
     *
     * 需要在回执发布之前确认 durable 的命令车道（K 店 checkout/claim）在所有权威写
     * 完成、commit 之前调用；false 与异常都按未 durable 处理，由调用方 exact restore
     * 或 preserve。与 requestStrongSave 不同，本方法不经事务的延迟请求队列，调用方
     * 因此能在发布成功 receipt 之前否决命令 finality（存盘风暴止血专项 A①）。
     */
    public static function flushStrongSaveNow():Boolean {
        try {
            return performStrongSave() === true;
        } catch (flushError) {
            trace("[PlayerAssetTransaction] explicit strong save fence failed: "
                + flushError);
            return false;
        }
    }

    private static function addSignedCurrency(transaction:Object, kind:String,
                                              name:String, delta:Number,
                                              context:Object):Void {
        delta = Number(delta);
        if (isNaN(delta) || !isFinite(delta) || delta == 0) return;
        addEffect(transaction, delta > 0 ? "gain" : "loss", kind, name,
            Math.abs(delta), "", context);
    }

    /**
     * 完成最外层事务并发布回执。嵌套事务只把已归一化 effect 合并进父事务，
     * 防止内层 ItemUtil 在外层领域事务尚未完成时提前播报。
     */
    public static function commit(transaction:Object):Object {
        if (!isTopOpen(transaction)) return null;
        _stack.pop();
        transaction.state = "committed";
        transaction.recoverDispatch = null;
        transaction.committedAt = nowMilliseconds();
        delete transaction.effectIndex;

        var parent:Object = current();
        if (parent != null && parent.state == "open") {
            for (var i:Number = 0; i < transaction.effects.length; i++) {
                mergeDetachedEffect(parent, transaction.effects[i]);
            }
            if (transaction.authorityWriteObserved === true) {
                parent.authorityWriteObserved = true;
            }
            if (transaction.strongSaveRequested === true) {
                parent.strongSaveRequested = true;
            }
            return detachedReceipt(transaction);
        }

        var receipt:Object = detachedReceipt(transaction);
        if (transaction.strongSaveRequested === true) {
            // false 表示 SaveManager 保留 dirty 等待后续重试；资产仍已在内存提交，
            // 所以回执照常发布，但不得把尝试误标成 durable success。
            try {
                transaction.strongSaveFlushed = performStrongSave();
            } catch (strongSaveError) {
                transaction.strongSaveFlushed = false;
                trace("[PlayerAssetTransaction] strong save failed: " + strongSaveError);
            }
        }
        _lastCommittedReceipt = receipt;
        publish(receipt);
        return receipt;
    }

    /** 回滚只丢弃尚未提交的可选消费者回执；领域服务仍负责恢复真实资产。 */
    public static function rollback(transaction:Object):Boolean {
        if (!isTopOpen(transaction)) return false;
        _stack.pop();
        transaction.state = "rolled_back";
        transaction.recoverDispatch = null;
        transaction.effects = [];
        transaction.effectIndex = {};
        transaction.strongSaveRequested = false;
        return true;
    }

    /**
     * 显式领域边界捕获异常后的唯一清栈入口。
     *
     * 本方法只结算 PlayerAssetTransaction 的可选消费者 frame，绝不恢复或改写
     * 玩家资产。调用方必须先按领域权威决定：
     * - preserveCommittedEffects=true：真实写入无法/不应恢复，合并异常期间已经
     *   记录的 effect，并按当前事实提交；事务内强存盘请求也随最终提交执行。
     * - preserveCommittedEffects=false：领域已经用自己的 exact snapshot 恢复，
     *   丢弃尚未发布的 effect 与强存盘请求。
     *
     * 若异常路径意外留下了本事务的子 frame，本方法会一并结算，避免后续隐式
     * record 方法/requestStrongSave 被旧栈顶污染。它不会越过 transaction 去处置更早
     * 的外层 frame。
     */
    public static function settleAfterException(transaction:Object,
                                                 preserveCommittedEffects:Boolean):Object {
        var transactionIndex:Number = findOpenTransactionIndex(transaction);
        if (transactionIndex < 0) return null;

        // begin 时捕获的 token 只回退本领域进入后的 EventBus depth，不清空
        // 更早的外层 publish。无事件异常时 depth 不变，调用仍为安全 no-op。
        if (transaction.recoverDispatch != null) {
            transaction.recoverDispatch();
            transaction.recoverDispatch = null;
        }

        if (preserveCommittedEffects) {
            // 子 frame 都产生于本显式领域调用期间。异常让它们失去独立 finality，
            // 但其中已经记录的真实 effect 仍需并入领域 frame 后统一提交。
            for (var mergeIndex:Number = transactionIndex + 1;
                    mergeIndex < _stack.length; mergeIndex++) {
                var child:Object = _stack[mergeIndex];
                if (child == null || child.state != "open") continue;
                for (var effectIndex:Number = 0;
                        effectIndex < child.effects.length; effectIndex++) {
                    mergeDetachedEffect(transaction, child.effects[effectIndex]);
                }
                if (child.strongSaveRequested === true) {
                    transaction.strongSaveRequested = true;
                }
                if (child.authorityWriteObserved === true) {
                    transaction.authorityWriteObserved = true;
                }
            }
        }

        while (_stack.length - 1 > transactionIndex) {
            var abandonedChild:Object = _stack.pop();
            abandonedChild.state = preserveCommittedEffects
                ? "exception_merged" : "exception_discarded";
            abandonedChild.effects = [];
            abandonedChild.effectIndex = {};
            abandonedChild.strongSaveRequested = false;
            abandonedChild.recoverDispatch = null;
        }

        if (preserveCommittedEffects) return commit(transaction);
        rollback(transaction);
        return null;
    }

    private static function addEffect(transaction:Object, direction:String,
                                      kind:String, name:String, count:Number,
                                      tier:String, context:Object):Void {
        if (transaction == null || transaction.state != "open") return;
        if (direction != "gain" && direction != "loss") return;
        if (kind == null || kind.length == 0 || name == null || name.length == 0) return;
        count = Number(count);
        if (isNaN(count) || !isFinite(count) || count <= 0
                || Math.floor(count) != count || count > MAX_SAFE_INTEGER) return;

        var normalized:Object = normalizeContext(context);
        var source:String = normalized.source == "unknown"
            ? String(transaction.source) : normalized.source;
        var reason:String = normalized.reason.length == 0
            ? String(transaction.reason) : normalized.reason;
        var mergeScope:String = normalized.mergeScope.length == 0
            ? String(transaction.mergeScope) : normalized.mergeScope;
        if (mergeScope == "operation") mergeScope = String(transaction.operationId);

        var effect:Object = {
            direction:direction,
            kind:kind,
            name:name,
            count:count,
            source:source,
            reason:reason,
            tier:tier == null ? "" : String(tier),
            mergeScope:mergeScope
        };
        mergeDetachedEffect(transaction, effect);
    }

    private static function mergeDetachedEffect(transaction:Object,
                                                effect:Object):Void {
        var key:String = effectKey(effect);
        var index = transaction.effectIndex[key];
        if (index != undefined) {
            var existing:Object = transaction.effects[Number(index)];
            var total:Number = Number(existing.count) + Number(effect.count);
            existing.count = total > MAX_SAFE_INTEGER ? MAX_SAFE_INTEGER : total;
            return;
        }
        transaction.effectIndex[key] = transaction.effects.length;
        transaction.effects.push(cloneEffect(effect));
    }

    private static function effectKey(effect:Object):String {
        return lengthKey(String(effect.direction))
            + lengthKey(String(effect.kind))
            + lengthKey(String(effect.name))
            + lengthKey(String(effect.source))
            + lengthKey(String(effect.reason))
            + lengthKey(String(effect.tier))
            + lengthKey(String(effect.mergeScope));
    }

    private static function lengthKey(value:String):String {
        return String(value.length) + ":" + value + "|";
    }

    private static function cloneEffect(effect:Object):Object {
        return {
            direction:String(effect.direction),
            kind:String(effect.kind),
            name:String(effect.name),
            count:Number(effect.count),
            source:String(effect.source),
            reason:String(effect.reason),
            tier:String(effect.tier),
            mergeScope:String(effect.mergeScope)
        };
    }

    private static function detachedReceipt(transaction:Object):Object {
        var effects:Array = [];
        for (var i:Number = 0; i < transaction.effects.length; i++) {
            effects.push(cloneEffect(transaction.effects[i]));
        }
        return {
            version:1,
            operationId:String(transaction.operationId),
            source:String(transaction.source),
            reason:String(transaction.reason),
            startedAt:Number(transaction.startedAt),
            committedAt:Number(transaction.committedAt),
            effects:effects
        };
    }

    private static function publish(receipt:Object):Void {
        if (receipt == null || !(receipt.effects instanceof Array)
                || receipt.effects.length == 0) return;
        try {
            if (_testSink != null) {
                _testSink(receipt);
                return;
            }
            if (typeof _root.发布物资事务回执 == "function") {
                _root.发布物资事务回执(receipt);
            }
        } catch (publishError) {
            // 播报、统计等消费者不得反向破坏已经完成的权威资产写入。
            trace("[PlayerAssetTransaction] receipt publish failed: " + publishError);
        }
    }

    private static function performStrongSave():Boolean {
        if (_testStrongSaveSink != null) {
            return _testStrongSaveSink() === true;
        }
        if (typeof _root.强制存盘 == "function") return _root.强制存盘() === true;
        return false;
    }

    private static function normalizeContext(context:Object):Object {
        if (context == null || typeof context != "object") {
            return {operationId:"", source:"unknown", reason:"", mergeScope:""};
        }
        return {
            operationId:context.operationId == undefined || context.operationId == null
                ? "" : String(context.operationId),
            source:context.source == undefined || context.source == null
                || String(context.source).length == 0
                ? "unknown" : String(context.source),
            reason:context.reason == undefined || context.reason == null
                ? "" : String(context.reason),
            mergeScope:context.mergeScope == undefined || context.mergeScope == null
                ? "" : String(context.mergeScope)
        };
    }

    private static function inferKind(name:String):String {
        if (name == "金钱" || name == "金币") return "money";
        if (name == "K点") return "kpoint";
        if (ItemUtil.informationMaxValueDict != null && ItemUtil.isInformation(name)) return "intel";
        if (ItemUtil.materialDict != null && ItemUtil.isMaterial(name)) return "material";
        if (ItemUtil.equipmentDict != null && ItemUtil.isEquipment(name)) return "equip";
        return "item";
    }

    private static function normalizeName(name:String, kind:String):String {
        if (kind == "money" || name == "金币") return "金钱";
        return name == null ? "" : String(name);
    }

    private static function isTopOpen(transaction:Object):Boolean {
        return transaction != null && transaction.state == "open"
            && _stack.length > 0 && _stack[_stack.length - 1] === transaction;
    }

    private static function findOpenTransactionIndex(transaction:Object):Number {
        if (transaction == null || transaction.state != "open") return -1;
        for (var i:Number = _stack.length - 1; i >= 0; i--) {
            if (_stack[i] === transaction) return i;
        }
        return -1;
    }

    private static function nextOperationId():String {
        var current:Number = Number(_nextOperation);
        if (isNaN(current) || current < 1 || current > MAX_SAFE_INTEGER) current = 1;
        _nextOperation = current + 1;
        return "asset-" + String(nowMilliseconds()) + "-" + String(current);
    }

    private static function nowMilliseconds():Number {
        var value:Number = new Date().getTime();
        return isNaN(value) || !isFinite(value) || value < 0 ? 0 : value;
    }

    // ==================== TestLoader 专用钩子 ====================

    public static function setTestSink(sink:Function):Void {
        _testSink = sink;
    }

    public static function setTestStrongSaveSink(sink:Function):Void {
        _testStrongSaveSink = sink;
    }

    public static function getLastCommittedReceiptForTest():Object {
        return _lastCommittedReceipt;
    }

    public static function resetForTests():Void {
        _stack = [];
        _nextOperation = 1;
        _testSink = null;
        _testStrongSaveSink = null;
        _lastCommittedReceipt = null;
    }
}
