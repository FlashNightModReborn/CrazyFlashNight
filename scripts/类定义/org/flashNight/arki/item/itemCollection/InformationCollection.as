import org.flashNight.arki.item.itemCollection.DictCollection;
import org.flashNight.arki.item.ItemUtil;

/*
 * 情报物品集合，继承字典集合
 * 情报物品集合调用ItemUtil.informationMaxValueDict，其中每个键值对表示可以存入该集合的物品与其最大值
*/

class org.flashNight.arki.item.itemCollection.InformationCollection extends DictCollection{

    public function InformationCollection(_items:Object) {
        super(_items);
    }

    public function getMaxValue(key:String):Number{
        return ItemUtil.informationMaxValueDict[key];
    }

    
    //添加前检测maxValues中是否存在对应键以及value是否大于最大值
    public function add(key:String,value:Number):Boolean{
        var maxval = getMaxValue(key);
        if(isNaN(maxval)) return false;
        if(value > maxval) value = maxval;
        return super.add(key,value);
    }

    //改变值后检测是否大于最大值
    public function addValue(key:String,value:Number):Void{
        super.addValue(key,value);
        var maxval = getMaxValue(key);
        if(items[key] > maxval) items[key] = maxval;
    }


    //检查所有情报物品的值
    public function checkValues():Void{
        for(var key in items){
            var maxval = getMaxValue(key);
            if(items[key] > maxval) items[key] = maxval;
        }
    }
}
