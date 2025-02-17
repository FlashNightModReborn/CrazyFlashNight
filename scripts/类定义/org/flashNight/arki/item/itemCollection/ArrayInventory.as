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
                key = getFirstVacancy();
            } else {
                var self = this;
                var iterator = new TreeSetMinimalIterator(this.indexes);
                var foundValue = iterator.find(function(value):Boolean {
                    var existingItem = self.items[value];
                    return existingItem && existingItem.name == item.name && !isNaN(existingItem.value);
                });
                key = foundValue !== undefined ? foundValue : getFirstVacancy();
            }
        }

        if (key == -1 || !super.add(String(key), item)) return false;

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

    // 覆写修改 searchFirstKey 方法以获得顺序支持
    public function searchFirstKey(name:String):String {
        var self = this;
        var foundValue = new TreeSetMinimalIterator(indexes).find(function(value):Boolean {
            return self.items[value].name == name;
        });
        return foundValue != null ? String(foundValue) : undefined;
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
        var self = this;
        var foundValue = new TreeSetMinimalIterator(indexes).find(function(value):Boolean {
            return callback(self.items[value]);
        });
        return foundValue != null ? self.items[foundValue] : null;
    }

    //返回第一个满足条件的物品索引
    public function findIndex(callback:Function):Number {
        var foundValue = new TreeSetMinimalIterator(indexes).find(function(value):Boolean {
            return callback(this.items[value]);
        });
        return foundValue != null ? foundValue : -1;
    }



    /**
     * 根据提供的排序函数重新排列物品栏中的物品，确保致密排列（不留空格）。
     * 如果排序函数为 null 或 undefined，则维持当前物品顺序，仅去除空格。
     * 
     * @param sortFunction 用于排序物品的比较函数，若为空则保持原顺序
     */
    public function rebuild(sortFunction:Function):Void {
        // 获取当前所有有效物品（按索引顺序）
        var itemArr:Array = this.getItemArray();
        
        // 如果提供了有效的排序函数，则对物品进行排序
        if (sortFunction != null) {
            itemArr.sort(sortFunction);
        }
        
        // 清空当前的物品和索引
        this.items = {};
        this.indexes = new TreeSet(null);
        
        // 重新填充物品，确保不超过容量且连续排列
        var maxIndex:Number = Math.min(itemArr.length, this.capacity);
        for (var i:Number = 0; i < maxIndex; i++) {
            var item:Object = itemArr[i];
            this.items[i] = item;
            this.indexes.add(i);
        }
    }
}
