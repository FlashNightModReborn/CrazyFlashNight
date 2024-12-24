import org.flashNight.arki.item.itemCollection.ItemCollection;

/*
物品栏基类
*/

class org.flashNight.arki.item.itemCollection.Inventory extends ItemCollection{
    
    private var items:Object; //物品数据

    public function Inventory(_items:Object) {
        super(_items);
    }

    //获取物品对象索引
    public function getItem(key:String):Object{
        var item = items[key];
        if(!item) return null;
        return item;
    }

    //重构isAddable，判断某格是否能放入某个物品
    public function isAddable(key:String,item:Object):Boolean{
        return item.name && item.value;
    }
    
    //改变物品value
    public function changeValue(key:String,value:Number):Void{
        if(isNaN(value)) return;
        var item = items[key];
        item.value += value;
        if(item.value <= 0){
            remove(key);
        }
    }
    
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
        if(item.name != targetItem.name) return false;
        return true;
    }

    //交换两个格子的物品
    public function switch(target:Inventory, key:String, targetKey:String):Boolean{
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
