/*
物品集合基类
*/

class org.flashNight.arki.item.itemCollection.Collection {
    
    private var items:Object; //物品数据

    public function ItemCollection(_items:Object) {
        if(!items) this.items = new Object();
        else this.items = _items;
    }

    //获取物品对象索引
    public function getItem(key:String):Object{
        var item = items[key];
        if(!item) return null;
        return item;
    }

    //判断某个键是否为空
    public function isEmpty(key:String):Boolean{
        return !(items[key] != null);
    }

    //判断是否能放入某个物品
    public function isAddable(key:String,item:Object):Boolean{
        return true;
    }

    //放入物品
    public function add(key:String,item:Object):Boolean{
        if(isEmpty(key) && isAddable(key,item)){
            items[key] = item;
            return true;
        }
        return false;
    }

    //删除物品
    public function remove(key:String):Void{
        delete items[key];
    }
}
