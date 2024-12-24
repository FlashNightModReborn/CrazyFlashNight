import org.flashNight.arki.inventory.Inventory;

/*
只以数字作为键的物品栏，继承物品栏基类
*/
class org.flashNight.arki.inventory.ArrayInventory extends Inventory {
    
    public var capacity:Number; //

    public function ArrayInventory(_items:Object,_capacity:Number) {
        super(_items);
        if(_capacity <= 1) _capacity = 8;
        this.capacity = _capacity;
    }

    //重构isEmpty函数，非数字键也会返回false
    public function isEmpty(key:Number):Boolean{
        if(key < 0 || key >= capacity) return false;
        return super.isEmpty(key);
    }

    //寻找第一个空的数字索引，若栏位全满则返回-1
    public function getFirstVacancy():Number{
        for(var i:Number=0; i<this.capacity; i++){
            if(!items[i]) return i;
        }
        return -1;
    }
}
