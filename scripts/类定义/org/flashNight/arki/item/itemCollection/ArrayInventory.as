import org.flashNight.arki.item.itemCollection.Inventory;
import org.flashNight.naki.DataStructures.TreeSet;
import org.flashNight.gesh.iterator.*;
/*
 * 只以数字作为键的定长物品栏，继承物品栏基类
*/
class org.flashNight.arki.item.itemCollection.ArrayInventory extends Inventory {
    
    public var capacity:Number; //总格数
    private var indexes:TreeSet; //索引TreeSet

    public function ArrayInventory(_items:Object,_capacity:Number) {
        super(_items);
        if(_capacity <= 1) _capacity = 8;
        this.capacity = _capacity;
        //建立索引TreeSet
        indexes = new TreeSet(null);
        for(var key in this.items){
            indexes.add(Number(key));
        }
    }

    //重构isEmpty函数，非数字键也会返回false
    public function isEmpty(key:Number):Boolean{
        if(key < 0 || key >= capacity) return false;
        return items[key] == null;
    }

    //重构add函数，填写-1时自动寻找可用的索引
    public function add(key:Number, item:Object):Boolean {
        if (key == -1) {
            if (isNaN(item.value)) {
                key = getFirstVacancy(); // 如果是没有值的物品，找到第一个空位
            } else {
                // 使用迭代器来查找是否有相同的物品
                var iterator:IIterator = new TreeSetMinimalIterator(this.indexes);
                while (iterator.hasNext()) {
                    var index:Number = Number(iterator.next().getValue());
                    // 检查是否有相同名字的物品且 value 不为 NaN
                    if (this.items[index].name == item.name && !isNaN(this.items[index].value)) {
                        key = index;
                        break; // 找到相同物品时，直接赋值并跳出循环
                    }
                }
                // 如果没有找到匹配物品，找到第一个空位
                if (key == -1) key = getFirstVacancy();
            }
        }

        if (key == -1) return false; // 如果没有找到空位，则返回 false

        // 调用父类的 add 方法
        var result:Boolean = super.add(String(key), item);
        if (!result) return false;

        // 将新添加的 key 加入索引
        indexes.add(key);
        return true;
    }


    public function remove(key:Number):Void{
        super.remove(String(key));
        indexes.remove(key);
    }

    //返回索引TreeSet的数组形式
    public function getIndexes():Array{
        return indexes.toArray();
    }

    //以数字索引顺序返回物品数组
    public function getItemArray():Array{
        var indexArr = this.indexes.toArray();
        var list = [];
        for(var i = 0; i<indexArr.length; i++){
            list.push(this.items[indexArr[i]]);
        }
        return list;
    }


    //寻找空格
    //寻找第一个空格的数字索引，若栏位全满则返回-1
    public function getFirstVacancy():Number {
        var iterator:IIterator = new TreeSetMinimalIterator(this.indexes);
        var currentVacancy:Number = 0;  // 当前要检查的索引

        // 遍历已占用的位置
        while (iterator.hasNext()) {
            var occupiedIndex:Number = Number(iterator.next().getValue());
            // 如果当前占用的位置大于等于正在检查的空位位置，说明空位就在这个位置之前
            if (occupiedIndex > currentVacancy) {
                return currentVacancy; // 返回第一个空位
            }
            // 跳过已经占用的位置，继续寻找下一个空位
            currentVacancy = occupiedIndex + 1;
        }
        
        // 如果遍历完所有的已占用位置后，当前Vacancy仍然有效，则返回
        if (currentVacancy < this.capacity) {
            return currentVacancy; // 返回空位
        }
        
        // 如果没有找到空位，则返回 -1
        return -1;
    }

    //返回前n个空格的数字索引，若未填写数量则返回至多16个空索引
    public function getVacancies(amount:Number):Array {
        if (isNaN(amount)) amount = 16;
        var vacancies:Array = [];
        var iterator:IIterator = new TreeSetMinimalIterator(this.indexes);
        var currentVacancy:Number = 0;  // 当前要检查的索引

        // 遍历已占用的位置并寻找空位
        while (iterator.hasNext() && vacancies.length < amount) {
            var occupiedIndex:Number = Number(iterator.next().getValue());
            
            // 如果当前占用位置大于当前检查的位置，则计算空位区间
            if (occupiedIndex > currentVacancy) {
                // 批量添加从 currentVacancy 到 occupiedIndex - 1 的空位
                var emptySpaceCount:Number = occupiedIndex - currentVacancy;
                var spacesToAdd:Number = Math.min(emptySpaceCount, amount - vacancies.length);
                for (var i:Number = 0; i < spacesToAdd; i++) {
                    vacancies.push(currentVacancy++);
                }
            }

            // 跳过已占用的当前索引
            currentVacancy = occupiedIndex + 1;
        }

        // 如果没有填满数量，继续添加剩余的空位直到容量为止
        while (vacancies.length < amount && currentVacancy < this.capacity) {
            vacancies.push(currentVacancy++);
        }

        return vacancies;
    }


    
    //寻找物品格
    //返回第一个满足条件的物品
    public function find(callback:Function) {
        var iterator:IIterator = new TreeSetMinimalIterator(this.indexes);
        while (iterator.hasNext()) {
            var index:Number = Number(iterator.next().getValue());
            var item:Object = this.items[index];
            if (callback(item) == true) return item;
        }
        return null;
    }

    //返回第一个满足条件的物品索引
    public function findIndex(callback:Function) {
        var iterator:IIterator = new TreeSetMinimalIterator(this.indexes);
        while (iterator.hasNext()) {
            var index:Number = Number(iterator.next().getValue());
            if (callback(this.items[index]) == true) return index;
        }
        return -1;
    }
}
