import org.flashNight.arki.item.itemCollection.ArrayInventory;

/*
 * 药剂栏，继承定长物品栏
*/
class org.flashNight.arki.item.itemCollection.DrugInventory extends ArrayInventory {

    public function DrugInventory(_items:Object,_capacity:Number) {
        super(_items,_capacity);
    }

    //重构isAddable函数，判定物品是否为药剂
    public function isAddable(key:String,item:Object):Boolean{
        if(!super.isAddable(key,item)) return false;
        return _root.getItemData(item.name).use == "药剂";
    }
}
