import org.flashNight.arki.item.ItemUtil;

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
            strongSaveRequested:false,
            strongSaveFlushed:false,
            startedAt:nowMilliseconds()
        };
        _stack.push(transaction);
        return transaction;
    }

    public static function current():Object {
        if (_stack.length == 0) return null;
        return _stack[_stack.length - 1];
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

        if (implicit) commit(transaction);
    }

    /** 记录单个已提交变化；count 永远是正数，方向由 direction 表达。 */
    public static function recordEffect(direction:String, kind:String,
                                        name:String, count:Number,
                                        context:Object):Void {
        var transaction:Object = current();
        var implicit:Boolean = transaction == null;
        if (implicit) transaction = begin(context);
        addEffect(transaction, direction, kind, normalizeName(name, kind),
            count, context == null ? "" : String(context.tier || ""), context);
        if (implicit) commit(transaction);
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
        addSignedCurrency(transaction, "money", "金钱", moneyDelta, context);
        addSignedCurrency(transaction, "kpoint", "K点", kpointDelta, context);
        if (implicit) commit(transaction);
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
        transaction.committedAt = nowMilliseconds();
        delete transaction.effectIndex;

        var parent:Object = current();
        if (parent != null && parent.state == "open") {
            for (var i:Number = 0; i < transaction.effects.length; i++) {
                mergeDetachedEffect(parent, transaction.effects[i]);
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
        transaction.effects = [];
        transaction.effectIndex = {};
        transaction.strongSaveRequested = false;
        return true;
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
