import org.flashNight.arki.item.itemCollection.DictCollection;

/*
 * 成就和情报物品集合，继承字典集合
 * 情报物品集合创建时需要传入一个Object，其中每个键值对表示可以存入该集合的物品与其最大值
*/

class org.flashNight.arki.item.itemCollection.AchievementCollection extends DictCollection{

    private var maxValues:Object;//所有能放入集合的物品名和最大值

    public function AchievementCollection(_items:Object,_maxValues:Object) {
        super(_items);
        this.maxValues = _maxValues;
    }

    // public function initMaxValues():Void{
    //     if(maxValues == null){
    //         //
    //     }
    // }

    public function getMaxValue(key:String):Number{
        return maxValues[key];
    }

    
    //添加前检测maxValues中是否存在对应键以及value是否大于最大值
    public function add(key:String,value:Number):Boolean{
        var maxval = maxValues[key];
        if(isNaN(maxval)) return false;
        if(value > maxval) value = maxval;
        return super.add(key,value);
    }

    //改变值后检测是否大于最大值
    public function addValue(key:String,value:Number):Void{
        super.addValue(key,value);
        if(items[key] > maxValues[key]) items[key] = maxValues[key];
    }
}
