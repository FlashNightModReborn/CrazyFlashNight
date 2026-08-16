import org.flashNight.arki.item.itemCollection.ItemCollection;

/*
 * 字典集合基类，继承物品集合基类
 * 字典集合中的物品均有字符串键和数字值组成
*/

class org.flashNight.arki.item.itemCollection.DictCollection extends ItemCollection{

    public var isDict:Boolean = true;
    private static var MAX_SAFE_INTEGER:Number = 9007199254740991;
    private var mutationRevision:Number;
    // 旧档中无法作为运行时数量使用、但仍代表正数持有量的原始值放在这里。
    // 它们不进入 getValue()/getItems() 的业务投影，却会由 toObject() 原样写回，
    // 避免加载时用截断、取整或删除猜测性破坏存档。
    private var quarantinedItems:Object;
    private var quarantinedEntryCount:Number;

    public function DictCollection(_items:Object) {
        super(_items);
        if (quarantinedItems == undefined) quarantinedItems = {};
        if (isNaN(quarantinedEntryCount)) quarantinedEntryCount = 0;
        mutationRevision = 1;
    }

    //添加键值对
    public function add(key:String,value:Number):Boolean{
        if(!isPositiveSafeInteger(value)) return false;
        if(isEmpty(key) && isAddable(key,value)){
            items[key] = value;
            clearQuarantinedKey(key);
            bumpMutationRevision();
            if(this.hasDispatcher()) dispatcher.publish("ItemAdded", this, key); // 发布ItemAdded事件
            return true;
        }
        return false;
    }

    //获取对应键的值
    public function getValue(key:String):Number{
        var value = items[key];
        if(!isPositiveSafeInteger(value)) return 0;
        return Number(value);
    }

    // 隔离值在业务上视为空，因此后续一次合法获得可以显式修复同名键。
    public function isEmpty(key:String):Boolean{
        return !isPositiveSafeInteger(items[key]);
    }

    //改变键值对的值
    public function addValue(key:String,value:Number):Void{
        if(!isSafeInteger(value)) return;
        var before:Number = getValue(key);
        var after:Number = before + value;
        if(!isSafeInteger(after) || after > MAX_SAFE_INTEGER) return;
        if (after == before) return;
        if(after <= 0) {
            if (before <= 0) return;
            delete items[key];
            clearQuarantinedKey(key);
            bumpMutationRevision();
            if(this.hasDispatcher()) dispatcher.publish("ItemRemoved", this, key);
            return;
        }
        items[key] = after;
        clearQuarantinedKey(key);
        bumpMutationRevision();
        if(this.hasDispatcher()) {
            dispatcher.publish(before <= 0 ? "ItemAdded" : "ItemValueChanged", this, key);
        }
    }

    /** 返回材料字典的单调写版本。 */
    public function getMutationRevision():Number {
        var current:Number = Number(mutationRevision);
        return isNaN(current) || current < 0 ? 0 : current;
    }

    private function bumpMutationRevision():Void {
        var current:Number = Number(mutationRevision);
        if (isNaN(current) || current < 0) current = 0;
        mutationRevision = current + 1;
    }

    /** 完整预检一组材料 delta；本方法零写、零事件。 */
    public function canApplyTransactionDeltas(deltas:Object):Boolean {
        if (deltas == null || typeof deltas != "object") return false;
        for (var key:String in deltas) {
            if (key == "") return false;
            var delta:Number = Number(deltas[key]);
            var before:Number = getValue(key);
            var after:Number = before + delta;
            if (hasQuarantinedKey(key)
                    || (items[key] != null && !isPositiveSafeInteger(items[key]))) return false;
            if (!isSafeInteger(delta)) return false;
            if (!isSafeInteger(before) || before < 0) return false;
            if (!isSafeInteger(after) || after < 0 || after > MAX_SAFE_INTEGER) return false;
        }
        return true;
    }

    /**
     * 材料事务的无事件提交阶段。全部 delta 先验证，再一次写完并只推进一次 revision；
     * 返回的 changes 供调用方在装备与材料均已提交后统一派发事件。
     */
    public function transactionApplyDeltas(deltas:Object):Object {
        if (!canApplyTransactionDeltas(deltas)) return {success: false};
        var changes:Array = [];
        var beforeRevision:Number = getMutationRevision();
        for (var key:String in deltas) {
            var delta:Number = Number(deltas[key]);
            if (delta == 0) continue;
            var before:Number = getValue(key);
            var after:Number = before + delta;
            changes.push({key: key, before: before, delta: delta, after: after});
        }
        try {
            for (var i:Number = 0; i < changes.length; i++) {
                var change:Object = changes[i];
                if (Number(change.after) <= 0) delete items[String(change.key)];
                else items[String(change.key)] = Number(change.after);
                clearQuarantinedKey(String(change.key));
            }
            if (changes.length > 0) bumpMutationRevision();
        } catch (writeError) {
            var restored:Boolean = restoreTransactionChanges(
                changes, beforeRevision);
            return {success:false, rollbackComplete:restored};
        }
        return {
            success:true,
            changes:changes,
            beforeRevision:beforeRevision,
            revision:getMutationRevision()
        };
    }

    /**
     * 跨资源领域事务的补偿入口。只接受仍精确处于本 transaction receipt
     * post-state 的材料批次；先完整验证后一次恢复，期间不派发事件。
     */
    public function rollbackTransactionDeltas(receipt:Object):Boolean {
        if (receipt == null || receipt.success !== true
                || !(receipt.changes instanceof Array)
                || getMutationRevision() != Number(receipt.revision)) {
            return false;
        }
        var changes:Array = receipt.changes;
        for (var i:Number = 0; i < changes.length; i++) {
            var change:Object = changes[i];
            if (getValue(String(change.key)) != Number(change.after)) {
                return false;
            }
        }
        return restoreTransactionChanges(
            changes, Number(receipt.beforeRevision));
    }

    private function restoreTransactionChanges(changes:Array,
                                               beforeRevision:Number):Boolean {
        try {
            for (var i:Number = 0; i < changes.length; i++) {
                var change:Object = changes[i];
                if (Number(change.before) <= 0) {
                    delete items[String(change.key)];
                } else {
                    items[String(change.key)] = Number(change.before);
                }
            }
            mutationRevision = beforeRevision;
        } catch (rollbackError) {
            return false;
        }
        if (getMutationRevision() != beforeRevision) return false;
        for (i = 0; i < changes.length; i++) {
            change = changes[i];
            if (getValue(String(change.key)) != Number(change.before)) {
                return false;
            }
        }
        return true;
    }

    public function publishTransactionChanges(changes:Array):Void {
        if (!(changes instanceof Array) || !this.hasDispatcher()) return;
        for (var i:Number = 0; i < changes.length; i++) {
            var change:Object = changes[i];
            var eventName:String;
            if (Number(change.before) <= 0 && Number(change.after) > 0) eventName = "ItemAdded";
            else if (Number(change.after) <= 0) eventName = "ItemRemoved";
            else eventName = "ItemValueChanged";
            dispatcher.publish(eventName, this, String(change.key));
        }
    }


    // 重写设置物品集合功能
    public function setItems(_items:Object):Void{
        var newItems = {};
        var newQuarantinedItems:Object = {};
        var newQuarantinedEntryCount:Number = 0;
        for(var key in _items){
            var rawValue = _items[key];
            if(isPositiveSafeInteger(rawValue)) {
                newItems[key] = Number(rawValue);
            } else if(Number(rawValue) > 0) {
                newQuarantinedItems[key] = rawValue;
                newQuarantinedEntryCount++;
            }
        }
        this.items = newItems;
        this.quarantinedItems = newQuarantinedItems;
        this.quarantinedEntryCount = newQuarantinedEntryCount;
        if (mutationRevision != undefined) bumpMutationRevision();
    }

    // 重写深度拷贝功能
    public function toObject():Object{
        var obj = {};
        for(var quarantinedKey in quarantinedItems){
            obj[quarantinedKey] = quarantinedItems[quarantinedKey];
        }
        for(var key in items){
            var value = items[key];
            if(isPositiveSafeInteger(value) || Number(value) > 0) obj[key] = value;
        }
        return obj;
    }

    /** 返回被隔离、未进入业务投影的旧档条目数；不暴露键名或原值。 */
    public function getQuarantinedEntryCount():Number {
        var count:Number = Number(quarantinedEntryCount);
        if (!isSafeInteger(count) || count < 0) return 0;
        return count;
    }

    private function hasQuarantinedKey(key:String):Boolean {
        return quarantinedItems != undefined && quarantinedItems[key] != undefined;
    }

    private function clearQuarantinedKey(key:String):Void {
        if (!hasQuarantinedKey(key)) return;
        delete quarantinedItems[key];
        quarantinedEntryCount--;
        if (isNaN(quarantinedEntryCount) || quarantinedEntryCount < 0) {
            quarantinedEntryCount = 0;
        }
    }

    private function isPositiveSafeInteger(value):Boolean {
        return isSafeInteger(value) && Number(value) > 0;
    }

    private function isSafeInteger(value):Boolean {
        return typeof value == "number" && !isNaN(value) && isFinite(value)
            && Math.floor(Number(value)) == Number(value)
            && Number(value) >= -MAX_SAFE_INTEGER
            && Number(value) <= MAX_SAFE_INTEGER;
    }
}
