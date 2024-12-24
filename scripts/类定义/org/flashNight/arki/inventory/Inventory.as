/*
物品栏基类
*/

class org.flashNight.arki.inventory.Inventory {
    
    private var items:Object; //物品数据

    public function Inventory(_items:Object) {
        if(!items) this.items = new Object();
        else this.items = _items;
    }

    public function getItem(key:String):Object{
        var item = items[key];
        if(!item) return null;
        return item;
    }

    public function isEmpty(key:String):Boolean{
        return !(items[key] != null);
    }

    public function isAddable(key:String,item:Object){
        return isEmpty(key) && item.name && item.value;
    }

    public function add(key:String,item:Object):Boolean{
        if(isAddable(key,item)){
            items[key] = item;
            return true;
        }
        return false;
    }
    
    //交换两个格子的物品
    public function switch(target:Inventory,key:String,targetKey:String):Boolean{
        var item = getItem(key);
        if(!item) return false;
        if(!target.isAddable(targetKey,item)) return false;
        if(target.isEmpty(targetKey)){
            target.add(targetKey,item);
            delete item;
            return true;
        }else{
            var targetItem = target.getItem(targetKey);
            if(!this.isAddable(key,targetItem)) return false;
            target.add(targetKey,item);
            this.add(key,targetItem);
            return true;
        }
    }
}
