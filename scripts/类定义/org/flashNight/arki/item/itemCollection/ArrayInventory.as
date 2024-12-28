import org.flashNight.arki.item.itemCollection.Inventory;

/*
 * 只以数字作为键的定长物品栏，继承物品栏基类
*/
class org.flashNight.arki.item.itemCollection.ArrayInventory extends Inventory {
    
    public var capacity:Number; //总格数
    private var indexes:Array; //索引数组

    public function ArrayInventory(_items:Object,_capacity:Number) {
        super(_items);
        if(_capacity <= 1) _capacity = 8;
        this.capacity = _capacity;
         //建立索引数组（并没有建
    }

    //重构isEmpty函数，非数字键也会返回false
    public function isEmpty(key:Number):Boolean{
        if(key < 0 || key >= capacity) return false;
        return !(items[key] != null);
    }

    //重构add函数，填写-1时自动寻找可用的索引
    public function add(key:Number,item:Object):Boolean{
        if(key == -1){
            if(isNaN(item.value)){
                key = getFirstVacancy();
            }else{
                for(var i:Number = 0; i < this.capacity; i++){
                    if(items[i].name == item.name && !isNaN(items[i].value)) {
                        key = i;
                        break;
                    }
                }
                if(key == -1) key = getFirstVacancy();
            }
        }
        if(key == -1) return false;
        return super.add(String(key),item);
    }


    //寻找第一个空格的数字索引，若栏位全满则返回-1
    public function getFirstVacancy():Number{
        for(var i:Number=0; i<this.capacity; i++){
            if(!items[i]) return i;
        }
        return -1;
    }

    //返回前n个空格的数字索引，若未填写数量则返回至多16个空索引
    public function getVacancies(amount:Number):Array{
        if(isNaN(amount)) amount = 16;
        var list = [];
        var count = 0;
        for(var i:Number = 0; i < this.capacity; i++){
            if(!items[i]) {
                list.push(i);
                count++;
                if(count >= amount) break;
            }
        }
        return list;
    }
}
