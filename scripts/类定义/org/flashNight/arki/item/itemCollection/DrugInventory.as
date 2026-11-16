import org.flashNight.arki.item.itemCollection.ArrayInventory;

/*
 * 药剂栏，继承定长物品栏
*/
class org.flashNight.arki.item.itemCollection.DrugInventory extends ArrayInventory {

    private var slotChangeObserver:Function;
    private var slotChangeOwner:Object;

    public function DrugInventory(_items:Object,_capacity:Number) {
        super(_items,_capacity);
    }

    /** 不依赖HUD或可选dispatcher的单一同步观察位；不授予库存写权限。 */
    public function bindSlotChangeObserver(observer:Function, owner:Object):Boolean {
        if (observer == null || owner == null
                || (slotChangeOwner != null && slotChangeOwner !== owner)) return false;
        slotChangeObserver = observer;
        slotChangeOwner = owner;
        return true;
    }

    public function unbindSlotChangeObserver(owner:Object):Void {
        if (slotChangeOwner !== owner) return;
        slotChangeObserver = null;
        slotChangeOwner = null;
    }

    /** add/remove与原子事务都在完整提交后进入此点；先观察，再通知可选UI。 */
    public function publishTransactionChange(key:Number, changeKind:String):Void {
        if (slotChangeObserver != null) slotChangeObserver.call(slotChangeOwner, this, String(key));
        super.publishTransactionChange(key, changeKind);
    }

    //重构isAddable函数，判定物品是否为药剂
    public function isAddable(key:String,item:Object):Boolean{
        if(!super.isAddable(key,item)) return false;
        return _root.getItemData(item.name).use == "药剂";
    }
}
