import org.flashNight.arki.item.itemCollection.Inventory;

/*
药剂栏，继承物品栏基类
*/
class org.flashNight.arki.item.itemCollection.DrugInventory extends Inventory {

    public function DrugInventory(_items:Object) {
        super(_items);
    }

    //重构isAddable函数，判定物品是否为药剂
    public function isAddable(key:String,item:Object):Boolean{
        if(!super.isAddable(key,item)) return false;
        return _root.getItemData(item.name).use == "药剂";
    }
}
