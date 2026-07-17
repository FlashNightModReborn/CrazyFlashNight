import org.flashNight.arki.item.itemCollection.ItemCollection;

/*
 * 字典集合基类，继承物品集合基类
 * 字典集合中的物品均有字符串键和数字值组成
*/

class org.flashNight.arki.item.itemCollection.DictCollection extends ItemCollection{

    public var isDict:Boolean = true;
    private var mutationRevision:Number;

    public function DictCollection(_items:Object) {
        super(_items);
        mutationRevision = 1;
    }

    //添加键值对
    public function add(key:String,value:Number):Boolean{
        if(isNaN(value)) return false;
        if(isEmpty(key) && isAddable(key,value)){
            items[key] = value;
            bumpMutationRevision();
            if(this.hasDispatcher()) dispatcher.publish("ItemAdded", this, key); // 发布ItemAdded事件
            return true;
        }
        return false;
    }

    //获取对应键的值
    public function getValue(key:String):Number{
        var value = items[key];
        if(value <= 0) return 0;
        return value;
    }

    //改变键值对的值
    public function addValue(key:String,value:Number):Void{
        if(isNaN(value)) return;
        var before:Number = getValue(key);
        var after:Number = before + value;
        if (after == before) return;
        if(after <= 0) {
            if (before <= 0) return;
            delete items[key];
            bumpMutationRevision();
            if(this.hasDispatcher()) dispatcher.publish("ItemRemoved", this, key);
            return;
        }
        items[key] = after;
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
            if (isNaN(delta) || Math.floor(delta) != delta) return false;
            if (isNaN(before) || Math.floor(before) != before || before < 0) return false;
            if (before + delta < 0) return false;
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
        for (var key:String in deltas) {
            var delta:Number = Number(deltas[key]);
            if (delta == 0) continue;
            var before:Number = getValue(key);
            var after:Number = before + delta;
            if (after <= 0) delete items[key];
            else items[key] = after;
            changes.push({key: key, before: before, delta: delta, after: after});
        }
        if (changes.length > 0) bumpMutationRevision();
        return {success: true, changes: changes, revision: getMutationRevision()};
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
        for(var key in _items){
            if(_items[key] > 0) newItems[key] = _items[key];
        }
        this.items = newItems;
        if (mutationRevision != undefined) bumpMutationRevision();
    }

    // 重写深度拷贝功能
    public function toObject():Object{
        var obj = {};
        for(var key in items){
            obj[key] = items[key];
        }
        return obj;
    }
}
