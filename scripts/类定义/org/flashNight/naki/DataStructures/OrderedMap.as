import org.flashNight.naki.DataStructures.TreeSet;
import org.flashNight.naki.Sort.TimSort;
import org.flashNight.gesh.string.StringUtils;

/**
 * @description 基于TreeSet实现的有序映射，提供稳定的键序遍历
 */
class org.flashNight.naki.DataStructures.OrderedMap {
    private var keySet:TreeSet;          // 有序键集合
    private var valueMap:Object;         // 键值存储
    private var version:Number;          // 结构修改版本号
    
    /**
     * @constructor
     * @param {Function} compareFunction 键比较函数，格式function(a,b):Number
     */
    public function OrderedMap(compareFunction:Function) {
        this.keySet = new TreeSet(compareFunction);
        this.valueMap = {};
        this.version = 0;
    }
    
    //======================= 基本操作 =======================//
    
    /**
     * 插入/更新键值对
     * @param {String} key 键
     * @param {Object} value 值
     */
    public function put(key:String, value:Object):Void {
        var isNewKey:Boolean = !keySet.contains(key);
        if (isNewKey) {
            keySet.add(key);
            version++; // 结构变更
        }
        valueMap[key] = value;
    }
    
    /**
     * 获取键对应值
     * @param {String} key 键
     * @return {Object} 值，不存在返回null
     */
    public function get(key:String):Object {
        return valueMap.hasOwnProperty(key) ? valueMap[key] : null;
    }
    
    /**
     * 删除键值对
     * @param {String} key 键
     * @return {Boolean} 是否成功删除
     */
    public function remove(key:String):Boolean {
        if (!keySet.contains(key)) return false;
        
        keySet.remove(key);
        delete valueMap[key];
        version++; // 结构变更
        return true;
    }
    
    /**
     * 当前映射大小
     * @return {Number} 键值对数量
     */
    public function size():Number {
        return keySet.size();
    }
    
    /**
     * 是否包含键
     * @param {String} key 键
     * @return {Boolean} 是否存在
     */
    public function contains(key:String):Boolean {
        return keySet.contains(key);
    }
    
    //======================= 遍历操作 =======================//
    
    /**
     * 获取有序键数组
     * @return {Array} 按当前排序规则的键数组
     */
    public function keys():Array {
        return keySet.toArray();
    }
    
    /**
     * 获取有序值数组
     * @return {Array} 按键序对应的值数组
     */
    public function values():Array {
        var arr:Array = [];
        var keys:Array = keySet.toArray();
        for (var i:Number = 0; i < keys.length; i++) {
            arr.push(valueMap[keys[i]]);
        }
        return arr;
    }
    
    /**
     * 获取有序键值对数组
     * @return {Array} 按键序排列的{key,value}对象数组
     */
    public function entries():Array {
        var arr:Array = [];
        var keys:Array = keySet.toArray();
        for (var i:Number = 0; i < keys.length; i++) {
            arr.push({
                key: keys[i],
                value: valueMap[keys[i]]
            });
        }
        return arr;
    }
    
    /**
     * 有序遍历
     * @param {Function} callback 格式function(key:String, value:Object):Void
     */
    public function forEach(callback:Function):Void {
        var keys:Array = keySet.toArray();
        for (var i:Number = 0; i < keys.length; i++) {
            var key:String = keys[i];
            callback(key, valueMap[key]);
        }
    }
    
    //======================= 批量操作 =======================//
    
    /**
     * 批量插入（高性能实现）
     * @param {Array} entries 键值对数组，格式[{key:String, value:Object},...]
     */
    public function putAll(entries:Array):Void {
        // 阶段1：分离键值
        var keys:Array = [];
        var tempMap:Object = {};
        for (var i:Number = 0; i < entries.length; i++) {
            var entry:Object = entries[i];
            keys.push(entry.key);
            tempMap[entry.key] = entry.value;
        }
        
        // 阶段2：批量添加键（利用TreeSet的buildFromArray）
        var oldCompare:Function = keySet.getCompareFunction();
        var newKeySet:TreeSet = TreeSet.buildFromArray(keys, oldCompare);
        
        // 阶段3：合并键集合
        var mergedKeys:Array = newKeySet.toArray().concat(keySet.toArray());
        TimSort.sort(mergedKeys, oldCompare);
        var finalKeySet:TreeSet = TreeSet.buildFromArray(mergedKeys, oldCompare);
        
        // 阶段4：更新数据结构
        this.keySet = finalKeySet;
        for (var key:String in tempMap) {
            valueMap[key] = tempMap[key];
        }
        version++;
    }
    
    /**
     * 清空所有键值对
     */
    public function clear():Void {
        keySet = new TreeSet(keySet.getCompareFunction());
        valueMap = {};
        version++;
    }
    
    //======================= 高级操作 =======================//
    
    /**
     * 更换比较函数并重新排序
     * @param {Function} newCompare 新的键比较函数
     */
    public function changeCompareFunction(newCompare:Function):Void {
        // 获取当前所有键值对
        var entries:Array = this.entries();
        
        // 重建键集合
        var keys:Array = [];
        for (var i:Number = 0; i < entries.length; i++) {
            keys.push(entries[i].key);
        }
        
        // 使用新比较函数排序
        TimSort.sort(keys, newCompare);
        this.keySet = TreeSet.buildFromArray(keys, newCompare);
        version++;
    }
    
    /**
     * 获取第一个键
     * @return {String} 最小键，空映射返回null
     */
    public function firstKey():String {
        var arr:Array = keySet.toArray();
        return arr.length > 0 ? arr[0] : null;
    }
    
    /**
     * 获取最后一个键
     * @return {String} 最大键，空映射返回null
     */
    public function lastKey():String {
        var arr:Array = keySet.toArray();
        return arr.length > 0 ? arr[arr.length - 1] : null;
    }
}
