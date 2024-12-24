import org.flashNight.arki.item.itemCollection.ItemCollection;

/*
 * 字典集合基类，继承物品集合基类
 * 字典集合中的物品均有字符串键和数字值组成
*/

class org.flashNight.arki.item.itemCollection.DictCollection extends ItemCollection{

    public function DictCollection(_items:Object) {
        super(_items);
    }

    //放入键值对
    public function add(key:String,value:Number):Boolean{
        if(isEmpty(key) && isAddable(key,value)){
            items[key] = value;
            return true;
        }
        return false;
    }

    //获取对应键的值
    public function getValue(key:String):Number{
        var value = items[key];
        if(isNaN(value)) return null;
        return value;
    }

    //改变键值对的值
    public function addValue(key:String,value:Number):Void{
        if(isNaN(value)) return;
        items[key] += value;
        if(items[key] <= 0){
            remove(key);
        }
    }
}
