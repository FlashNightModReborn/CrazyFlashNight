import org.flashNight.arki.item.itemCollection.ICollection;

/*
 * 物品集合基类
*/

class org.flashNight.arki.item.itemCollection.ItemCollection implements ICollection{
    
    private var items:Object; //物品数据

    public function ItemCollection(_items:Object) {
        if(!items) this.items = new Object();
        else this.items = _items;
    }

    //获取物品对象
    public function getItem(key:String):Object{
        var item = items[key];
        if(!item) return null;
        return item;
    }

    //获取全部物品集合数据
    public function getItems():Object{
        return items;
    }

    //判断某个键是否为空
    public function isEmpty(key:String):Boolean{
        return !(items[key] != null);
    }

    //判断是否能添加指定物品
    public function isAddable(key:String,item:Object):Boolean{
        return true;
    }

    //添加物品
    public function add(key:String,item:Object):Boolean{
        if(isEmpty(key) && isAddable(key,item)){
            items[key] = item;
            return true;
        }
        return false;
    }

    //移除物品
    public function remove(key:String):Void{
        delete items[key];
    }
}
