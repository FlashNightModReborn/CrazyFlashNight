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
    private var indexesDirty:Boolean; //索引树是否需要重建（索引树异常时标记，避免空位判断误判）
    private var occupiedCount:Number; //当前占用格子数（与 items 对齐，用于快速校验 indexes 完整性）

    public function ArrayInventory(_items:Object,_capacity:Number) {
        super(_items);
        if(_capacity <= 1) _capacity = 8;
        this.capacity = _capacity;
        // 建立索引TreeSet（强制使用 WAVL：性能更优；并配合索引自修复避免长时间运行后的索引失真）
        indexes = new TreeSet(null, TreeSet.TYPE_WAVL);
        indexesDirty = true;
        occupiedCount = 0;
        rebuildIndexesFromItems();
    }

    //重构isEmpty函数，非数字键也会返回false
    public function isEmpty(key:Number):Boolean{
        if(isNaN(key) || Math.floor(key) != key) return false;
        if(key < 0 || key >= capacity) return false;
        return items[key] == null;
    }

    //重构add函数，填写-1时自动寻找可用的索引
    public function add(key:Number, item:Object):Boolean {
        if(item == null || item.name == undefined || item.name == "" || item.value == undefined || item.value == null) return false;
        if(typeof item.value == "number" && (isNaN(item.value) || item.value <= 0)) return false;

        if (key == -1) {
            key = getFirstVacancy();
        }
        if (isNaN(key) || Math.floor(key) != key || key < 0 || key >= capacity) return false;
        if (!super.add(String(key), item)) return false;

        // 增量维护索引树；若索引树异常则回退为全量重建
        if (this.indexes == null || this.indexesDirty) {
            rebuildIndexesFromItems();
            return true;
        }
        try {
            // 若索引树已经包含该key，则说明索引树已失真（items是空格但indexes认为被占用）
            if (this.indexes.contains(key)) {
                rebuildIndexesFromItems();
                return true;
            }
            this.indexes.add(key);
            this.occupiedCount++;
        } catch (e) {
            rebuildIndexesFromItems();
        }
        return true;
    }


    public function remove(key:Number):Void{
        if(isNaN(key) || Math.floor(key) != key) return;
        if(key < 0 || key >= capacity) return;
        if(items[key] == null) return;
        super.remove(String(key));

        // 增量维护索引树；若索引树异常则回退为全量重建
        if (this.indexes == null || this.indexesDirty) {
            rebuildIndexesFromItems();
            return;
        }
        try {
            var removed:Boolean = this.indexes.remove(key);
            if (!removed) {
                rebuildIndexesFromItems();
                return;
            }
            if (this.occupiedCount > 0) {
                this.occupiedCount--;
            } else {
                rebuildIndexesFromItems();
            }
        } catch (e) {
            rebuildIndexesFromItems();
        }
    }

    //返回索引TreeSet的数组形式
    public function getIndexes():Array{
        return getValidatedIndexes();
    }

    //返回索引TreeSet
    public function getTreeSet():TreeSet{
        getValidatedIndexes(); // 对外暴露 TreeSet 前先保证其可用
        return indexes;
    }

    //覆写setItems，批量替换items后索引需要重建
    public function setItems(_items:Object):Void{
        super.setItems(_items);
        indexesDirty = true;
        rebuildIndexesFromItems();
    }

    

    // 外部直接设置TreeSet
    public function setIndexes(indexes:TreeSet):Void
    {
        if (indexes == null) {
            this.indexes = new TreeSet(null, TreeSet.TYPE_WAVL);
            this.indexesDirty = true;
            rebuildIndexesFromItems();
            return;
        }

        // 强制使用 WAVL（性能更优），同时保留原有比较函数
        var cmpFn:Function = indexes.getCompareFunction();
        var arr:Array = null;
        try {
            arr = indexes.toArray();
        } catch (e) {
            arr = null;
        }
        if (arr == null) {
            this.indexes = new TreeSet(cmpFn, TreeSet.TYPE_WAVL);
            this.indexesDirty = true;
            rebuildIndexesFromItems();
            return;
        }

        this.indexes = TreeSet.buildFromArray(arr, cmpFn, TreeSet.TYPE_WAVL);
        this.indexesDirty = false;
    }

    //以数字索引顺序返回物品数组
    public function getItemArray():Array{
        var indexArr:Array = getValidatedIndexes();
        var list = [];
        for(var i = 0; i<indexArr.length; i++){
            list.push(this.items[indexArr[i]]);
        }
        return list;
    }

    // 覆写修改 searchFirstKey 方法以获得顺序支持
    public function searchFirstKey(name:String):String {
        if(name == null || name == undefined || name == "") return undefined;
        var indexArr:Array = getValidatedIndexes();
        for(var i:Number = 0; i < indexArr.length; i++){
            var index:Number = Number(indexArr[i]);
            var item:Object = this.items[index];
            if(item != null && item.name == name) return String(index);
        }
        return undefined;
    }


    //寻找空格
    //寻找第一个空格的数字索引，若栏位全满则返回-1
    public function getFirstVacancy():Number {
        var indexArr:Array = getValidatedIndexes();
        var currentVacancy:Number = 0;  // 当前要检查的索引

        for(var i:Number = 0; i < indexArr.length; i++){
            var occupiedIndex:Number = Number(indexArr[i]);
            if (occupiedIndex > currentVacancy) {
                return currentVacancy < this.capacity ? currentVacancy : -1;
            }
            currentVacancy = occupiedIndex + 1;
            if(currentVacancy >= this.capacity) return -1;
        }

        return currentVacancy < this.capacity ? currentVacancy : -1;
    }

    //返回前n个空格的数字索引，若未填写数量则返回至多16个空索引
    public function getVacancies(amount:Number):Array {
        if (isNaN(amount)) amount = 16;
        var vacancies:Array = [];
        var currentVacancy:Number = 0;  // 当前要检查的索引
        var indexArr:Array = getValidatedIndexes();

        // 遍历已占用的位置并寻找空位
        for (var i:Number = 0; i < indexArr.length && vacancies.length < amount; i++) {
            var occupiedIndex:Number = Number(indexArr[i]);
            
            // 如果当前占用位置大于当前检查的位置，则计算空位区间
            if (occupiedIndex > currentVacancy) {
                // 批量添加从 currentVacancy 到 occupiedIndex - 1 的空位
                var spacesToAdd:Number = Math.min(occupiedIndex - currentVacancy, amount - vacancies.length);
                for (var j:Number = 0; j < spacesToAdd; j++) {
                    if(currentVacancy >= this.capacity) return vacancies;
                    vacancies.push(currentVacancy++);
                }
            }

            // 跳过已占用的当前索引
            currentVacancy = occupiedIndex + 1;
            if(currentVacancy >= this.capacity) return vacancies;
        }

        // 如果没有填满数量，继续添加剩余的空位直到容量为止
        while (vacancies.length < amount && currentVacancy < this.capacity) {
            vacancies.push(currentVacancy++);
        }

        return vacancies;
    }


    //返回物品栏占用格子数
    public function size():Number {
        return this.occupiedCount;
    }

    
    //寻找物品格
    //返回第一个满足条件的物品
    public function find(callback:Function) {
        if(typeof callback !== "function") return null;
        var indexArr:Array = getValidatedIndexes();
        for(var i:Number = 0; i < indexArr.length; i++){
            var index:Number = Number(indexArr[i]);
            var item:Object = this.items[index];
            if(callback(item)) return item;
        }
        return null;
    }

    //返回第一个满足条件的物品索引
    public function findIndex(callback:Function):Number {
        if(typeof callback !== "function") return -1;
        var indexArr:Array = getValidatedIndexes();
        for(var i:Number = 0; i < indexArr.length; i++){
            var index:Number = Number(indexArr[i]);
            var item:Object = this.items[index];
            if(callback(item)) return index;
        }
        return -1;
    }

    
    //返回物品栏中目标物品的总数
    public function getTotal(targetName:String):Number {
        var total = 0;
        for(var key in this.items){
            var currentItem = this.items[key];
            if(currentItem != null && currentItem.name === targetName){
                total += isNaN(currentItem.value) ? 1 : currentItem.value;
            }
        }
        return total;
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

        if(_root.服务器 && typeof _root.服务器.发布服务器消息 == "function"){
            _root.服务器.发布服务器消息(ObjectUtil.toString(oldItems));
        }
        
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
            this.indexes.getCompareFunction(), // 保持原有比较函数
            TreeSet.TYPE_WAVL // 强制使用 WAVL：性能更优
        );
        
        // 4.2 直接替换物品存储
        var newItems:Object = {};
        for (i = 0; i < maxItems; i++) {
            newItems[String(i)] = oldItems[i]; // 直接写入无需检查
        }
        this.items = newItems;
        this.occupiedCount = maxItems;
        this.indexesDirty = false;
        
        /*
        // 阶段5：处理溢出物品（如果有?）
        if (oldItems.length > this.capacity) {
            // 发布消息？...
        }
        */
    }

    /**
     * 从当前 items 重建索引树，并返回最新索引数组（升序、去重、范围内）。
     */
    private function rebuildIndexesFromItems():Array {
        var indexArr:Array = [];
        var seen:Object = {};
        for (var key:String in this.items) {
            if (ObjectUtil.isInternalKey(key)) continue;
            var idx:Number = Number(key);
            if (isNaN(idx) || Math.floor(idx) != idx) continue;
            if (idx < 0 || idx >= this.capacity) continue;
            if (String(idx) != key) continue; // 排除 "01" / "1.0" 等非规范键，避免幽灵格
            if (this.items[key] == null) continue;
            if (seen[key]) continue;
            seen[key] = true;
            indexArr.push(idx);
        }
        indexArr.sort(Array.NUMERIC);

        var cmpFn:Function = (this.indexes != null) ? this.indexes.getCompareFunction() : null;
        this.indexes = TreeSet.buildFromArray(indexArr, cmpFn, TreeSet.TYPE_WAVL);
        this.occupiedCount = indexArr.length;
        this.indexesDirty = false;
        return indexArr;
    }

    /**
     * 获取可靠的索引数组：优先使用现有 indexes，异常/脏标记时自动重建。
     */
    private function getValidatedIndexes():Array {
        if (this.indexes == null || this.indexesDirty) {
            return rebuildIndexesFromItems();
        }

        var indexArr:Array = null;
        try {
            indexArr = this.indexes.toArray();
        } catch (e) {
            indexArr = null;
        }

        if (!isIndexArrayValid(indexArr)) {
            return rebuildIndexesFromItems();
        }
        return indexArr;
    }

    /**
     * 校验 indexes.toArray() 是否与 items 一致，避免空位判断误判。
     */
    private function isIndexArrayValid(indexArr:Array):Boolean {
        if (indexArr == null) return false;

        // 完整性检查：索引数量必须与 items 的占用格子数量一致
        if (indexArr.length != this.occupiedCount) return false;

        var last:Number = -1;
        for (var i:Number = 0; i < indexArr.length; i++) {
            var idx:Number = Number(indexArr[i]);
            if (isNaN(idx) || Math.floor(idx) != idx) return false;
            if (idx < 0 || idx >= this.capacity) return false;
            if (idx <= last) return false;
            if (this.items[idx] == null) return false;
            last = idx;
        }
        return true;
    }
}
