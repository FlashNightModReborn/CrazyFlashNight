import org.flashNight.arki.item.itemCollection.Inventory;

/*
装备栏，继承物品栏基类
装备栏的键直接代表能接受的装备类型
*/
class org.flashNight.arki.item.itemCollection.EquipmentInventory extends Inventory {

    public function EquipmentInventory(_items:Object) {
        super(_items);
    }

    //重构isAddable函数，判定装备类型是否和对应的键相同
    public function isAddable(key:String,item:Object):Boolean{
        if(!super.isAddable(key,item)) return false;
        var use = _root.getItemData(item.name).use;
        return use == key;
    }
}
