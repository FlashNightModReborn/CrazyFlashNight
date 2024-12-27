// import org.flashNight.arki.item.itemSlot.ISlot;

/*
 * 物品槽UI基类
*/

class org.flashNight.arki.item.itemSlot.itemSlot{
    
    private var items:Object; //物品数据

    public function ItemSlot(_items:Object) {
        if(!_items) this.items = new Object();
        else this.items = _items;
    }

    //获取物品对象
    public function getItem(key:String):Object{
        var item = items[key];
        if(!item) return null;
        return item;
    }
}
