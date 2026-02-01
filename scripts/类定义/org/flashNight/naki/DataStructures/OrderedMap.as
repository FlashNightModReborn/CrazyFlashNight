// OrderedMap.as
import org.flashNight.naki.DataStructures.*;
import org.flashNight.naki.Sort.*;
import org.flashNight.gesh.string.*;
import org.flashNight.gesh.iterator.*;

/**
 * @class OrderedMap
 * @package org.flashNight.naki.DataStructures
 * @description 增强版有序映射，支持多种数据格式输入输出
 */
class org.flashNight.naki.DataStructures.OrderedMap {
    private var keySet:TreeSet;   // 有序键集合
    private var valueMap:Object;  // 键值存储
    private var version:Number;   // 结构修改版本号
    
    /**
     * 构造函数
     * @param compareFunction 键比较函数，格式function(a,b):Number
     */
    public function OrderedMap(compareFunction:Function) {
        this.keySet = new TreeSet(compareFunction);
        this.valueMap = {};
        this.version = 0;
    }
    
    //======================= 核心操作方法 =======================//
    
    /**
     * 插入/更新键值对
     * 【优化】使用 valueMap.hasOwnProperty() (O(1)) 替代 keySet.contains() (O(log n))
     *        避免双查找开销
     * @param key 键
     * @param value 值
     */
    public function put(key:String, value:Object):Void {
        // 【优化】hasOwnProperty 是 O(1) 哈希查找，比 TreeSet.contains() 的 O(log n) 更快
        if (!valueMap.hasOwnProperty(key)) {
            keySet.add(key);
            version++; // 仅当添加新键时增加版本号
        }
        valueMap[key] = value;
    }
    
    /**
     * 获取键对应值
     * @param key 键
     * @return 值，不存在返回null
     */
    public function get(key:String):Object {
        return valueMap.hasOwnProperty(key) ? valueMap[key] : null;
    }
    
    /**
     * 删除键值对
     * 【优化】直接调用 keySet.remove() 并使用其返回值，避免 contains() + remove() 双查找
     * @param key 键
     * @return 是否成功删除
     */
    public function remove(key:String):Boolean {
        // 【优化】keySet.remove() 已返回删除成功与否，无需先 contains() 检查
        if (!keySet.remove(key)) return false;

        delete valueMap[key];
        version++;
        return true;
    }
    
    /**
     * 当前映射大小
     * @return 键值对数量
     */
    public function size():Number {
        return keySet.size();
    }
    
    /**
     * 是否包含键
     * @param key 键
     * @return 是否存在
     */
    public function contains(key:String):Boolean {
        return keySet.contains(key);
    }
    
    //======================= 批量操作方法 =======================//
    
    /**
     * 智能批量插入（支持多种格式）
     * @param input 支持格式：
     *              Array - [{key:"k1", value:"v1"}, ...]
     *              Object - {k1:"v1", k2:"v2"}
     */
    public function putAll(input:Object):Void {
        var entries:Array = normalizeInput(input);
        var keys:Array = [];
        var tempMap:Object = {};
        
        // 提取键值对
        for (var i:Number = 0; i < entries.length; i++) {
            var entry:Object = entries[i];
            keys.push(entry.key);
            tempMap[entry.key] = entry.value;
        }
        
        // 批量合并键集合
        var oldCompare:Function = keySet.getCompareFunction();
        var newKeySet:TreeSet = TreeSet.buildFromArray(keys, oldCompare);
        var mergedKeys:Array = newKeySet.toArray().concat(keySet.toArray());
        TimSort.sort(mergedKeys, oldCompare);
        var finalKeySet:TreeSet = TreeSet.buildFromArray(mergedKeys, oldCompare);
        
        // 更新数据结构
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
    
    //======================= 遍历操作方法 =======================//
    
    /**
     * 获取有序键数组
     * @return 按当前排序规则的键数组
     */
    public function keys():Array {
        return keySet.toArray();
    }
    
    /**
     * 获取有序值数组
     * @return 按键序对应的值数组
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
     * @return 按键序排列的{key,value}对象数组
     */
    public function entries():Array {
        var arr:Array = [];
        var keys:Array = keySet.toArray();
        for (var i:Number = 0; i < keys.length; i++) {
            var key:String = keys[i];
            arr.push({key:key, value:valueMap[key]});
        }
        return arr;
    }
    
    /**
     * 有序遍历
     * @param callback 回调函数，格式function(key:String, value:Object):Void
     */
    public function forEach(callback:Function):Void {
        var keys:Array = keySet.toArray();
        for (var i:Number = 0; i < keys.length; i++) {
            var key:String = keys[i];
            callback(key, valueMap[key]);
        }
    }
    
    //======================= 高级操作方法 =======================//
    
    /**
     * 更换比较函数并重新排序
     * @param newCompare 新的键比较函数
     */
    public function changeCompareFunction(newCompare:Function):Void {
        // 保存原始数据
        var oldEntries:Array = this.entries();
        
        // 创建新数据结构
        this.keySet = new TreeSet(newCompare);
        this.valueMap = {}; // 清空原有数据
        
        // 重新插入所有条目
        for (var i:Number = 0; i < oldEntries.length; i++) {
            var entry:Object = oldEntries[i];
            this.put(entry.key, entry.value); // 使用put方法保证版本号更新
        }
        
        // 强制版本号更新
        version++;
    }
    
    /**
     * 转换为标准Object
     * @return 包含所有键值对的Object
     */
    public function toObject():Object {
        var obj:Object = {};
        var keys:Array = keySet.toArray();
        for (var i:Number = 0; i < keys.length; i++) {
            var key:String = keys[i];
            obj[key] = valueMap[key];
        }
        return obj;
    }
    
    /**
     * 从Object加载数据
     * @param obj 包含键值对的Object
     */
    public function loadFromObject(obj:Object):Void {
        var entries:Array = [];
        for (var key:String in obj) {
            entries.push({key:key, value:obj[key]});
        }
        putAll(entries);
    }
    
    //======================= 迭代器相关 =======================//

    /**
     * 获取最小键
     *
     * 【优化说明】
     * 原实现使用 toArray()[0]，需要 O(n) 遍历整棵树。
     * 优化后直接沿左子树下潜，时间复杂度 O(log n)。
     * 对于 1000 元素的树，性能提升约 100-200 倍。
     *
     * @return 最小键，空映射返回null
     */
    public function firstKey():String {
        var node:Object = keySet.getRoot();
        if (node == null) return null;
        // 沿左子树下潜到最小节点
        while (node.left != null) {
            node = node.left;
        }
        return node.value;
    }

    /**
     * 获取最大键
     *
     * 【优化说明】
     * 原实现使用 toArray()[length-1]，需要 O(n) 遍历整棵树。
     * 优化后直接沿右子树下潜，时间复杂度 O(log n)。
     * 对于 1000 元素的树，性能提升约 100-200 倍。
     *
     * @return 最大键，空映射返回null
     */
    public function lastKey():String {
        var node:Object = keySet.getRoot();
        if (node == null) return null;
        // 沿右子树下潜到最大节点
        while (node.right != null) {
            node = node.right;
        }
        return node.value;
    }
    
    /**
     * 获取迭代器实例
     * @return OrderedMapMinimalIterator实例
     */
    public function iterator():IIterator {
        return new OrderedMapMinimalIterator(this);
    }
    
    //======================= 内部辅助方法 =======================//
    
    /**
     * 标准化输入为键值对数组
     * @param input 输入数据
     * @return 标准化的键值对数组
     */
    private function normalizeInput(input:Object):Array {
        if (input instanceof Array) {
            // 验证数组格式
            for (var i:Number = 0; i < input.length; i++) {
                if (typeof input[i] != "object" || !input[i].hasOwnProperty("key")) {
                    throw new Error("Invalid array element format");
                }
            }
            return input.slice(); // 返回副本
        }
        
        if (input instanceof Object) {
            // 转换Object为键值对数组
            var arr:Array = [];
            for (var key:String in input) {
                arr.push({key:key, value:input[key]});
            }
            return arr;
        }
        
        throw new Error("Unsupported input type: " + typeof input);
    }
    
    //======================= 访问器方法 =======================//
    
    /**
     * 获取内部键集合（仅供迭代器使用）
     * @return TreeSet实例
     */
    public function getKeySet():TreeSet {
        return keySet;
    }
    
    /**
     * 获取当前版本号（仅供迭代器使用）
     * @return 版本号
     */
    public function getVersion():Number {
        return version;
    }
    
    /**
     * 获取比较函数（仅供高级操作使用）
     * @return 当前比较函数
     */
    public function getCompareFunction():Function {
        return keySet.getCompareFunction();
    }
}
