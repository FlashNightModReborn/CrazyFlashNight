import org.flashNight.arki.item.itemCollection.ItemCollection;

/*
 * 物品栏基类，继承物品集合基类
*/

class org.flashNight.arki.item.itemCollection.Inventory extends ItemCollection{

    public function Inventory(_items:Object) {
        super(_items);
    }

    //重构isAddable函数，判断某格是否能放入某个物品
    public function isAddable(key:String,item:Object):Boolean{
        return item.name && item.value;
    }

    //根据物品名查找第一个物品对应的键
    public function searchFirstKey(name:String):String{
        for(var key in items){
            if(items[key].name == name) return key;
        }
    }

    //根据物品名查找所有同名物品对应的键
    public function searchKeys(name:String):Array{
        var list = [];
        for(var key in items){
            if(items[key].name == name) list.push(key);
        }
        return list;
    }
    
    //改变物品value
    public function addValue(key:String,value:Number):Void{
        if(isNaN(value)) return;
        var item = items[key];
        item.value += value;
        if(item.value <= 0) remove(key);
        else if(hasDispatcher()) dispatcher.publish("ItemValueChanged", this, key); // 发布ItemValueChanged事件
    }
    


    //物品移动操作

    //移动物品至另一空格
    public function move(target:Inventory, key:String, targetKey:String):Boolean{
        var item = items[key];
        if(!item || !target.isEmpty(targetKey)) return false;
        var result = target.add(targetKey,item);
        if(!result) return false;
        remove(key);
        return true;
    }

    //合并两个格子的物品
    public function merge(target:Inventory, key:String, targetKey:String):Boolean{
        var item = items[key];
        var targetItem = target.getItem(targetKey);
        if(item.name != targetItem.name || isNaN(item.value) || isNaN(targetItem.value)) return false;
        target.addValue(targetKey,item.value);
        remove(key);
        return true;
    }

    //交换两个格子的物品
    public function swap(target:Inventory, key:String, targetKey:String):Boolean{
        var item = this.getItem(key);
        var targetItem = target.getItem(targetKey);
        if(!item || !targetItem || !this.isAddable(key,targetItem) || !target.isAddable(targetKey,item)) return false;
        this.remove(key);
        this.add(key,targetItem);
        target.remove(targetKey);
        target.add(targetKey,item);
        return true;
    }
}
