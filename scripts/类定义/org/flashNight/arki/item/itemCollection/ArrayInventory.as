import org.flashNight.arki.item.itemCollection.Inventory;
import org.flashNight.naki.DataStructures.TreeSet;
import org.flashNight.gesh.iterator.*;
import org.flashNight.naki.Sort.*;
import org.flashNight.gesh.object.ObjectUtil;

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

    //返回索引TreeSet
    public function getTreeSet():TreeSet{
        return indexes;
    }

    

    // 外部直接设置TreeSet
    public function setIndexes(indexes:TreeSet):Void
    {
        this.indexes = indexes;
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
     * 高性能排序重建方法
     * 1. 使用批量数组操作代替逐个插入
     * 2. 直接操作底层数据结构避免继承链开销
     * 3. 利用TreeSet.buildFromArray创建平衡树结构
     * 
     * @param sortFunction 排序函数(null则保持原序)
     */
    public function rebuildOrder(sortFunction:Function):Void {
        // 阶段1：准备数据
        var oldItems:Array = this.getItemArray(); // 获取当前有序物品数组
        var maxItems:Number = Math.min(oldItems.length, this.capacity);

        _root.服务器.发布服务器消息(ObjectUtil.toString(oldItems))
        
        // 阶段2：排序处理（时间复杂度：O(n log n)）
        if (sortFunction != null) {
            // 使用原地排序避免内存分配
            TimSort.sort(oldItems, sortFunction);
        }
        
        // 阶段3：生成新索引（时间复杂度：O(n)）
        var newIndexes:Array = [];
        for (var i:Number = 0; i < maxItems; i++) {
            newIndexes.push(i); // 生成0到capacity-1的连续索引
        }
        
        // 阶段4：批量重建数据结构（时间复杂度：O(n)）
        // timsort 对有序数组效率极高，因此额外排序的成本可以忽略
        // 4.1 直接替换索引树
        this.indexes = TreeSet.buildFromArray(
            newIndexes, 
            this.indexes.getCompareFunction() // 保持原有比较函数
        );
        
        // 4.2 直接替换物品存储
        var newItems:Object = {};
        for (i = 0; i < maxItems; i++) {
            newItems[String(i)] = oldItems[i]; // 直接写入无需检查
        }
        this.items = newItems;
        
        /*
        // 阶段5：处理溢出物品（如果有?）
        if (oldItems.length > this.capacity) {
            // 发布消息？...
        }
        */
    }
}
