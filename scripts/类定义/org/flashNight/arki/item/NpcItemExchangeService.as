import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.item.PlayerAssetTransaction;

/**
 * 日常插话的物品交接：Host 经 gameCommand 同步调用，结果经 npc_item_response 回包。
 *
 * 权威边界：
 * - 赠送只走 ItemUtil.acquireReward（标准获得回执驱动左下反馈），成功后再发一条
 *   “NPC赠送了你X个物品”的对话消息；不另造拾取实体。
 * - 索取时普通物品走 ItemUtil.submit；装备只查背包（穿戴中的装备在装备栏，天然排除），
 *   同名取强化度最低、同强化度取背包顺序第一件，逐槽位移除；金币与情报单独扣除。
 * - operationId 幂等：同一编号只执行一次，重试直接返回首次结果。异常结果按
 *   unknown 记录，重试不会再次发放/扣除。
 */
class org.flashNight.arki.item.NpcItemExchangeService {
    private static var MAX_QUANTITY:Number = 9999;
    private static var MAX_RECENT:Number = 64;
    private static var _recent:Object = {};
    private static var _recentOrder:Array = [];
    private static var _testSink:Function = null;
    private static var _installed:Boolean = false;

    /** 由 asLoader 帧脚本在 boot 完成后调用一次；重复调用无副作用。 */
    public static function install():Void {
        if (_root.gameCommands == undefined) _root.gameCommands = {};
        _root.gameCommands["npcItemSummary"] = function(params:Object):Void {
            org.flashNight.arki.item.NpcItemExchangeService.dispatch("summary", params);
        };
        _root.gameCommands["npcItemCount"] = function(params:Object):Void {
            org.flashNight.arki.item.NpcItemExchangeService.dispatch("count", params);
        };
        _root.gameCommands["npcItemGrant"] = function(params:Object):Void {
            org.flashNight.arki.item.NpcItemExchangeService.dispatch("grant", params);
        };
        _root.gameCommands["npcItemTake"] = function(params:Object):Void {
            org.flashNight.arki.item.NpcItemExchangeService.dispatch("take", params);
        };
        _installed = true;
    }

    /** 查询：背包/药剂栏/材料/情报按名字聚合；装备只统计背包并给最低强化度。 */
    public static function npcItemSummary(params:Object):Object {
        var bag:Object = container("背包");
        var drugs:Object = container("药剂栏");
        var materials:Object = materialsContainer();
        var intel:Object = informationContainer();
        if (bag == null || drugs == null) {
            return {success:false, error:"inventory_unavailable"};
        }
        var items:Array = [];
        var itemMap:Object = {};
        collectOrdinary(bag, items, itemMap);
        collectOrdinary(drugs, items, itemMap);
        collectDict(materials, items, itemMap);
        collectDict(intel, items, itemMap);
        var equipment:Array = [];
        collectEquipment(bag, equipment);
        return {
            success:true,
            money:moneyValue(),
            items:items,
            equipment:equipment
        };
    }

    /** 按名字查询可交付持有量；装备返回背包同名件数与最低强化度。 */
    public static function npcItemCount(params:Object):Object {
        var name:String = text(params == null ? null : params.name, 100);
        if (name == "") return {success:false, error:"invalid_name"};
        if (name == "金币") {
            return {success:true, name:name, count:moneyValue(), equipment:false};
        }
        if (!ItemUtil.isItem(name)) {
            return {success:true, name:name, count:0, equipment:false};
        }
        if (ItemUtil.isEquipment(name)) {
            var found:Object = bagEquipment(name);
            return {
                success:true, name:name, count:found.count,
                equipment:true, minLevel:found.minLevel
            };
        }
        return {
            success:true, name:name, count:ordinaryCount(name), equipment:false
        };
    }

    /** 赠送：真实发放 + 对话消息；实际数量按情报溢出折算后的结果返回。 */
    public static function npcItemGrant(params:Object):Object {
        var name:String = text(params == null ? null : params.name, 100);
        if (name == "") return {success:false, error:"invalid_name"};
        var quantity:Number = wholeQuantity(params == null ? null : params.quantity);
        if (quantity < 1) return {success:false, error:"invalid_quantity"};
        var operationId:String = text(params == null ? null : params.operationId, 128);
        if (operationId == "") return {success:false, error:"invalid_operation"};
        var cached:Object = recall(operationId);
        if (cached != null) return cached;
        if (name != "金币" && !ItemUtil.isItem(name)) {
            return remember(operationId, {success:false, error:"unknown_item"});
        }

        var npc:String = text(params == null ? null : params.npc, 100);
        var plan:Object = null;
        try {
            plan = ItemUtil.acquireReward(
                [{name:name, value:quantity}],
                {source:"npc_gift", reason:"dialogue_gift", operationId:operationId}
            );
        } catch (grantError) {
            // 发放可能已经发生：按未知结果封存，重试不得再次发放。
            trace("[NpcItemExchange] grant unknown: " + grantError);
            return remember(operationId, {
                success:false, error:"grant_unknown", name:name, requested:quantity
            });
        }
        if (plan == null || plan.success !== true) {
            return remember(operationId, {
                success:false,
                error:plan == null ? "invalid_reward" : "inventory_full",
                name:name, requested:quantity
            });
        }

        var actual:Number = quantity;
        var conversions:Array = plan.conversions instanceof Array ? plan.conversions : [];
        for (var i:Number = 0; i < conversions.length; i++) {
            if (String(conversions[i].name) == name) {
                actual = Number(conversions[i].accepted);
                break;
            }
        }
        var overflowMoney:Number = Number(plan.overflowMoney);
        if (isNaN(overflowMoney) || overflowMoney < 0) overflowMoney = 0;
        if (actual < 1) {
            return remember(operationId, {
                success:false, error:"no_capacity", name:name,
                requested:quantity, actual:0, overflowMoney:overflowMoney
            });
        }

        var result:Object = {
            success:true, name:name, requested:quantity,
            actual:actual, overflowMoney:overflowMoney
        };
        remember(operationId, result);
        publishGiftNotice(npc, name, actual);
        return result;
    }

    /** 索取：真实扣除玩家持有；装备返回实际扣掉那件的强化度。 */
    public static function npcItemTake(params:Object):Object {
        var name:String = text(params == null ? null : params.name, 100);
        if (name == "") return {success:false, error:"invalid_name"};
        var quantity:Number = wholeQuantity(params == null ? null : params.quantity);
        if (quantity < 1) return {success:false, error:"invalid_quantity"};
        var operationId:String = text(params == null ? null : params.operationId, 128);
        if (operationId == "") return {success:false, error:"invalid_operation"};
        var cached:Object = recall(operationId);
        if (cached != null) return cached;
        var npc:String = text(params == null ? null : params.npc, 100);

        var context:Object = {
            source:"npc_take", reason:"dialogue_gift", operationId:operationId
        };
        var result:Object;
        if (name == "金币") {
            result = takeMoney(name, quantity, context);
        } else if (!ItemUtil.isItem(name)) {
            result = {success:false, error:"unknown_item", name:name};
        } else if (ItemUtil.isEquipment(name)) {
            result = takeEquipment(name, context);
        } else if (ItemUtil.isInformation(name)) {
            result = takeInformation(name, quantity, context);
        } else {
            result = takeOrdinary(name, quantity, context);
        }
        result = remember(operationId, result);
        if (result != null && result.success === true) {
            var actual:Number = result.actual == undefined ? quantity : Number(result.actual);
            if (!isNaN(actual) && actual > 0) publishTakeNotice(npc, name, actual);
        }
        return result;
    }

    // ==================== 扣除实现 ====================

    private static function takeMoney(name:String, quantity:Number, context:Object):Object {
        var before:Number = moneyValue();
        if (before < quantity) {
            return {success:false, error:"insufficient", name:name, count:before};
        }
        var transaction:Object;
        try { transaction = PlayerAssetTransaction.begin(context); }
        catch (beginError) {
            return {success:false, error:"asset_write_blocked", name:name};
        }
        try {
            PlayerAssetTransaction.markDirtyRequired(_root.存档系统);
            _root.金钱 = before - quantity;
        } catch (moneyError) {
            try { _root.金钱 = before; } catch (restoreError) { }
            PlayerAssetTransaction.rollback(transaction);
            return {success:false, error:"deduct_failed", name:name};
        }
        if (Number(_root.金钱) != before - quantity) {
            try { _root.金钱 = before; } catch (restoreError2) { }
            PlayerAssetTransaction.rollback(transaction);
            return {success:false, error:"deduct_failed", name:name};
        }
        PlayerAssetTransaction.recordEffect("loss", "money", "金钱", quantity, context);
        PlayerAssetTransaction.commit(transaction);
        return {success:true, name:name, quantity:quantity, actual:quantity, equipment:false};
    }

    private static function takeOrdinary(name:String, quantity:Number, context:Object):Object {
        var request:Array = [{name:name, value:quantity}];
        if (ItemUtil.contain(request) == null) {
            return {success:false, error:"insufficient", name:name};
        }
        var removed:Boolean = false;
        try { removed = ItemUtil.submit(request, context) === true; }
        catch (submitError) {
            trace("[NpcItemExchange] take submit failed: " + submitError);
            return {success:false, error:"deduct_failed", name:name};
        }
        if (!removed) {
            return {success:false, error:"deduct_failed", name:name};
        }
        return {success:true, name:name, quantity:quantity, actual:quantity, equipment:false};
    }

    private static function takeInformation(name:String, quantity:Number, context:Object):Object {
        var intel:Object = informationContainer();
        if (intel == null || intel.getValue(name) < quantity) {
            return {success:false, error:"insufficient", name:name};
        }
        var transaction:Object;
        try { transaction = PlayerAssetTransaction.begin(context); }
        catch (beginError) {
            return {success:false, error:"asset_write_blocked", name:name};
        }
        var committed:Number = 0;
        var before:Number = Number(intel.getValue(name));
        try {
            PlayerAssetTransaction.markDirtyRequired(_root.存档系统);
            intel.addValue(name, -quantity);
        } catch (intelError) {
            trace("[NpcItemExchange] intel remove failed: " + intelError);
        }
        // 监听器可能在实际扣除后抛错：按容器前后差记账，不按请求量虚报。
        committed = before - Number(intel.getValue(name));
        if (committed < 1) {
            PlayerAssetTransaction.rollback(transaction);
            return {success:false, error:"deduct_failed", name:name};
        }
        if (committed > quantity) committed = quantity;
        PlayerAssetTransaction.recordEffect("loss", "intel", name, committed, context);
        PlayerAssetTransaction.commit(transaction);
        return {success:true, name:name, quantity:committed, actual:committed, equipment:false};
    }

    /**
     * 装备只从背包取：同名多件选强化度最低，同强化度按背包顺序取第一件；
     * 数量固定 1。背包与装备栏是两个容器，穿戴中的装备不会进入候选。
     */
    private static function takeEquipment(name:String, context:Object):Object {
        var bag:Object = container("背包");
        if (bag == null || typeof bag.getIndexes != "function") {
            return {success:false, error:"inventory_unavailable", name:name};
        }
        var indexes:Array = bag.getIndexes();
        var pickedKey:Number = -1;
        var pickedLevel:Number = 0;
        var pickedTier:String = "";
        for (var i:Number = 0; i < indexes.length; i++) {
            var key:Number = Number(indexes[i]);
            var item:Object = bag.getItem(key);
            if (item == null || String(item.name) != name) continue;
            if (!ItemUtil.isEquipment(String(item.name))) continue;
            var level:Number = Number(item.value == null ? 0 : item.value.level);
            if (isNaN(level)) level = 0;
            if (pickedKey < 0 || level < pickedLevel) {
                pickedKey = key;
                pickedLevel = level;
                pickedTier = item.value == null || item.value.tier == undefined
                    ? "" : String(item.value.tier);
            }
        }
        if (pickedKey < 0) {
            return {success:false, error:"insufficient", name:name};
        }

        var transaction:Object;
        try { transaction = PlayerAssetTransaction.begin(context); }
        catch (beginError) {
            return {success:false, error:"asset_write_blocked", name:name};
        }
        var removed:Boolean = false;
        try {
            PlayerAssetTransaction.markDirtyRequired(_root.存档系统);
            bag.remove(pickedKey);
        } catch (removeError) {
            trace("[NpcItemExchange] equipment remove failed: " + removeError);
        }
        // 监听器在删除后抛错也算真实扣除：按容器事实记账，不回滚。
        removed = bag.getItem(pickedKey) == null;
        if (!removed) {
            PlayerAssetTransaction.rollback(transaction);
            return {success:false, error:"deduct_failed", name:name};
        }
        var effectContext:Object = {
            source:context.source, reason:context.reason,
            operationId:context.operationId, tier:pickedTier
        };
        PlayerAssetTransaction.recordEffect("loss", "equip", name, 1, effectContext);
        PlayerAssetTransaction.commit(transaction);
        return {
            success:true, name:name, quantity:1, actual:1,
            equipment:true, itemLevel:pickedLevel
        };
    }

    // ==================== 查询实现 ====================

    private static function collectOrdinary(source:Object, items:Array, itemMap:Object):Void {
        if (source == null) return;
        if (typeof source.getIndexes == "function") {
            var indexes:Array = source.getIndexes();
            for (var i:Number = 0; i < indexes.length; i++) {
                var item:Object = source.getItem(Number(indexes[i]));
                if (item == null || ItemUtil.isEquipment(String(item.name))) continue;
                var count:Number = Number(item.value);
                if (isNaN(count) || count <= 0) continue;
                bump(items, itemMap, String(item.name), count);
            }
            return;
        }
        if (typeof source.getItems == "function") {
            var raw:Object = source.getItems();
            for (var key:String in raw) {
                var entry:Object = raw[key];
                if (entry == null || ItemUtil.isEquipment(String(entry.name))) continue;
                var value:Number = Number(entry.value);
                if (isNaN(value) || value <= 0) continue;
                bump(items, itemMap, String(entry.name), value);
            }
        }
    }

    private static function collectDict(source:Object, items:Array, itemMap:Object):Void {
        if (source == null || typeof source.getItems != "function") return;
        var raw:Object = source.getItems();
        for (var key:String in raw) {
            var value:Number = Number(raw[key]);
            if (isNaN(value) || value <= 0) continue;
            bump(items, itemMap, String(key), value);
        }
    }

    private static function collectEquipment(bag:Object, equipment:Array):Void {
        if (bag == null || typeof bag.getIndexes != "function") return;
        var map:Object = {};
        var order:Array = [];
        var indexes:Array = bag.getIndexes();
        for (var i:Number = 0; i < indexes.length; i++) {
            var item:Object = bag.getItem(Number(indexes[i]));
            if (item == null) continue;
            var name:String = String(item.name);
            if (!ItemUtil.isEquipment(name)) continue;
            var level:Number = Number(item.value == null ? 0 : item.value.level);
            if (isNaN(level)) level = 0;
            var entry:Object = map[name];
            if (entry == undefined) {
                entry = {name:name, count:0, minLevel:level};
                map[name] = entry;
                order.push(name);
            }
            entry.count += 1;
            if (level < entry.minLevel) entry.minLevel = level;
        }
        for (var j:Number = 0; j < order.length; j++) equipment.push(map[order[j]]);
    }

    private static function bagEquipment(name:String):Object {
        var result:Object = {count:0, minLevel:0};
        var bag:Object = container("背包");
        if (bag == null || typeof bag.getIndexes != "function") return result;
        var indexes:Array = bag.getIndexes();
        for (var i:Number = 0; i < indexes.length; i++) {
            var item:Object = bag.getItem(Number(indexes[i]));
            if (item == null || String(item.name) != name) continue;
            var level:Number = Number(item.value == null ? 0 : item.value.level);
            if (isNaN(level)) level = 0;
            if (result.count == 0 || level < result.minLevel) result.minLevel = level;
            result.count += 1;
        }
        return result;
    }

    private static function ordinaryCount(name:String):Number {
        var total:Number = 0;
        total += countInArray(container("背包"), name, false);
        total += countInArray(container("药剂栏"), name, false);
        total += countInDict(materialsContainer(), name);
        total += countInDict(informationContainer(), name);
        return total;
    }

    private static function countInArray(source:Object, name:String, equipment:Boolean):Number {
        var total:Number = 0;
        if (source == null || typeof source.getIndexes != "function") return total;
        var indexes:Array = source.getIndexes();
        for (var i:Number = 0; i < indexes.length; i++) {
            var item:Object = source.getItem(Number(indexes[i]));
            if (item == null || String(item.name) != name) continue;
            if (ItemUtil.isEquipment(name) != equipment) continue;
            var value:Number = Number(item.value);
            if (!isNaN(value) && value > 0) total += value;
        }
        return total;
    }

    private static function countInDict(source:Object, name:String):Number {
        if (source == null || typeof source.getValue != "function") return 0;
        var value:Number = Number(source.getValue(name));
        return isNaN(value) || value < 1 ? 0 : value;
    }

    private static function bump(items:Array, map:Object, name:String, count:Number):Void {
        var entry:Object = map[name];
        if (entry == undefined) {
            entry = {name:name, count:0};
            map[name] = entry;
            items.push(entry);
        }
        entry.count += count;
    }

    // ==================== 回包与状态 ====================

    private static function dispatch(op:String, params:Object):Void {
        var requestId:String = "";
        if (params != null) {
            var rawId = params.requestId;
            if (typeof rawId == "string") requestId = String(rawId);
        }
        var result:Object;
        if (op == "summary") result = npcItemSummary(params);
        else if (op == "count") result = npcItemCount(params);
        else if (op == "grant") result = npcItemGrant(params);
        else if (op == "take") result = npcItemTake(params);
        else result = {success:false, error:"unknown_op"};
        var payload:Object = {task:"npc_item_response", requestId:requestId, op:op};
        for (var key:String in result) payload[key] = result[key];
        respond(payload);
    }

    private static function respond(payload:Object):Void {
        if (_testSink != null) {
            _testSink(payload);
            return;
        }
        if (_root.server == undefined
                || typeof _root.server.sendSocketMessage != "function") return;
        var json:LiteJSON = new LiteJSON();
        var wire:String = json.stringifySafe(payload);
        if (wire == null) return;
        try { _root.server.sendSocketMessage(wire); }
        catch (sendError) { trace("[NpcItemExchange] response send failed: " + sendError); }
    }

    private static function publishGiftNotice(npc:String, name:String, quantity:Number):Void {
        if (npc == "") return;
        if (typeof _root.发布消息 != "function") return;
        var display:String = name;
        var data:Object = ItemUtil.getRawItemData(name);
        if (data != null && data.displayname != undefined
                && String(data.displayname).length > 0) {
            display = String(data.displayname);
        }
        try { _root.发布消息(npc + "赠送了你" + quantity + "个" + display); }
        catch (noticeError) { trace("[NpcItemExchange] gift notice failed: " + noticeError); }
    }

    private static function publishTakeNotice(npc:String, name:String, quantity:Number):Void {
        if (npc == "") return;
        if (typeof _root.发布消息 != "function") return;
        var display:String = name;
        var data:Object = ItemUtil.getRawItemData(name);
        if (data != null && data.displayname != undefined
                && String(data.displayname).length > 0) {
            display = String(data.displayname);
        }
        try { _root.发布消息("你赠送给" + npc + quantity + "个" + display); }
        catch (noticeError) { trace("[NpcItemExchange] take notice failed: " + noticeError); }
    }

    private static function recall(operationId:String):Object {
        var entry:Object = _recent[operationId];
        return entry == undefined ? null : entry;
    }

    private static function remember(operationId:String, result:Object):Object {
        var entry:Object = _recent[operationId];
        if (entry != null) return entry;
        _recent[operationId] = result;
        _recentOrder.push(operationId);
        while (_recentOrder.length > MAX_RECENT) {
            var oldest:String = String(_recentOrder.shift());
            delete _recent[oldest];
        }
        return result;
    }

    // ==================== 基础读取 ====================

    private static function container(key:String):Object {
        if (_root.物品栏 == undefined || _root.物品栏 == null) return null;
        var value:Object = _root.物品栏[key];
        return value == undefined ? null : value;
    }

    private static function materialsContainer():Object {
        if (_root.收集品栏 == undefined || _root.收集品栏 == null) return null;
        var value:Object = _root.收集品栏.材料;
        return value == undefined ? null : value;
    }

    private static function informationContainer():Object {
        if (_root.收集品栏 == undefined || _root.收集品栏 == null) return null;
        var value:Object = _root.收集品栏.情报;
        return value == undefined ? null : value;
    }

    private static function moneyValue():Number {
        var value:Number = Number(_root.金钱);
        return isNaN(value) || value < 0 ? 0 : value;
    }

    private static function text(value, maxLength:Number):String {
        if (typeof value != "string") return "";
        var result:String = String(value);
        if (result.length < 1 || result.length > maxLength) return "";
        // AVM1 的 String.fromCharCode(0) 会被吞成空串，不能拿它做 NUL 检索。
        for (var i:Number = 0; i < result.length; i++) {
            if (result.charCodeAt(i) == 0) return "";
        }
        return result;
    }

    private static function wholeQuantity(value):Number {
        if (typeof value != "number") return -1;
        var result:Number = Number(value);
        if (isNaN(result) || !isFinite(result)) return -1;
        if (result != Math.floor(result) || result < 1 || result > MAX_QUANTITY) return -1;
        return result;
    }

    // ==================== TestLoader 专用钩子 ====================

    public static function setTestSink(sink:Function):Void {
        _testSink = sink;
    }

    public static function resetForTests():Void {
        _recent = {};
        _recentOrder = [];
        _testSink = null;
        _installed = false;
    }

    public static function installedForTest():Boolean {
        return _installed;
    }
}
