import org.flashNight.arki.item.itemCollection.ICollection;
import org.flashNight.arki.item.BaseItem;
import org.flashNight.neur.Event.LifecycleEventDispatcher;
import org.flashNight.gesh.object.ObjectUtil;

/*
 * 物品集合基类
*/

class org.flashNight.arki.item.itemCollection.ItemCollection implements ICollection{
    
    private var items:Object; //物品数据
    public var isDict:Boolean; //是否为字典集合

    private var dispatcher:LifecycleEventDispatcher; //事件分发器实例

    public function ItemCollection(_items:Object) {
        if(!_items) this.items = new Object();
        else setItems(_items);
    }

    //获取物品对象
    public function getItem(key:String):Object{
        var item = items[key];
        if(!item) return null;
        return item;
    }

    //获取对应键的值（未使用）
    public function getValue(key:String):Object{
        var value = items[key].value;
        if(!value) return null;
        return value;
    }

    //获取全部物品集合数据
    public function getItems():Object{
        return items;
    }

    // 获取全部物品集合数据的Object形式的拷贝
    public function toObject():Object{
        var obj = {};
        for(var key in items){
            var item:BaseItem = items[key];
            obj[key] = item.toObject();
        }
        return obj;
    }

    // 设置物品集合数据
    public function setItems(_items:Object):Void{
        var newItems = {};
        for(var key in _items){
            newItems[key] = BaseItem.createFromObject(_items[key]);
        }
        this.items = newItems;
    }

    //判断某个键是否为空
    public function isEmpty(key:String):Boolean{
        return items[key] == null;
    }

    //判断是否能添加指定物品
    public function isAddable(key:String,item):Boolean{
        return true;
    }

    //添加物品
    public function add(key:String,item):Boolean{
        if(isEmpty(key) && isAddable(key,item)){
            items[key] = item;
            if(hasDispatcher()) dispatcher.publish("ItemAdded", this, key); // 发布ItemAdded事件
            return true;
        }
        return false;
    }

    //移除物品
    public function remove(key:String):Void{
        delete items[key];
        if(hasDispatcher()) dispatcher.publish("ItemRemoved", this, key); // 发布ItemRemoved事件
    }


    //设置事件分发器
    public function setDispatcher(_dispatcher:LifecycleEventDispatcher):Void{
        if(this.hasDispatcher()) this.dispatcher.destroy();
        this.dispatcher = _dispatcher;
    }
    //获取事件分发器实例
    public function getDispatcher():LifecycleEventDispatcher{
        if(hasDispatcher()) return this.dispatcher;
        return null;
    }
    //检查事件分发器是否存在
    private function hasDispatcher():Boolean{
        if(this.dispatcher == null) return false;
        if(this.dispatcher.isDestroyed()){
            this.dispatcher = null;
            return false;
        }
        return true;
    }
}
