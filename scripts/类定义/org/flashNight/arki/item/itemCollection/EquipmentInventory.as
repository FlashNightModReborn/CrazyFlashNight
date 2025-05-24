import org.flashNight.arki.item.itemCollection.Inventory;

/*
 * 装备栏，继承物品栏基类
 * 装备栏的键直接代表能接受的装备类型
*/
class org.flashNight.arki.item.itemCollection.EquipmentInventory extends Inventory {

    public function EquipmentInventory(_items:Object) {
        super(_items);
    }

    //重构isAddable函数，判定装备类型是否和对应的键相同
    public function isAddable(key:String,item:Object):Boolean{
        if(!super.isAddable(key,item)) return false;
        var use = _root.getItemData(item.name).use;
        //对手枪2进行额外检测
        return use == key || (use == "手枪" && key == "手枪2");
    }

    //返回装备名称字符串，若未装备则返回空字符串
    public function getNameString(key:String):String{
        if(isEmpty(key)) return "";
        return items[key].name;
    }

    //返回装备强化度
    public function getLevel(key:String):Number{
        if(isEmpty(key)) return 0;
        return items[key].value.level;
    }
}
