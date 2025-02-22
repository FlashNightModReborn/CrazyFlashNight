import org.flashNight.arki.item.itemCollection.ItemCollection;

/*
 * 字典集合基类，继承物品集合基类
 * 字典集合中的物品均有字符串键和数字值组成
*/

class org.flashNight.arki.item.itemCollection.DictCollection extends ItemCollection{

    public var isDict:Boolean = true;

    public function DictCollection(_items:Object) {
        super(_items);
    }

    //添加键值对
    public function add(key:String,value:Number):Boolean{
        if(isNaN(value)) return false;
        if(isEmpty(key) && isAddable(key,value)){
            items[key] = value;
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
        items[key] += value;
        if(items[key] <= 0) remove(key);
        else if(this.hasDispatcher()) dispatcher.publish("ItemValueChanged", this, key); // 发布ItemValueChanged事件
    }
}
