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
    
    /**
     * 改变物品value - 仅适用于非装备类物品
     *
     * 重要约定（Convention over Configuration）：
     * 本函数仅用于数量型物品（value为Number），不适用于装备类物品（value为Object）！
     *
     * 适用场景：
     * - 消耗品数量增减（如：药水、材料、货币）
     * - 可堆叠物品的数量变化
     *
     * 禁止场景：
     * - 装备类物品的任何操作（装备的value是Object，包含level等属性）
     * - 如需替换装备，应使用 remove() + add() 组合
     *
     * 设计理由：
     * 1. 性能优化：避免运行时类型检查，减少性能开销
     * 2. 约定优先：通过明确的使用约定替代防御性编程
     * 3. 调用安全：当前所有调用点均符合此约定（已验证）
     *
     * 警告：
     * 如果对装备类物品调用此函数，会导致：
     * - item.value(Object) + value(Number) = 字符串拼接或undefined行为
     * - 可能破坏装备数据结构
     *
     * @param key 物品栏位置键
     * @param value 要增减的数量（正数增加，负数减少）
     */
    public function addValue(key:String,value:Number):Void{
        if(isNaN(value)) return;
        var item = items[key];
        item.value += value;  // 注意：此处假定item.value为Number类型
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
