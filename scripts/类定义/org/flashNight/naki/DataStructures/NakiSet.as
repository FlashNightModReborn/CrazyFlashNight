/**
 * AS2 实现的 Set 类，位于 org.flashNight.naki.DataStructures 中
 * 支持基础类型与对象/函数作为集合元素，并提供集合常用操作。
 *
 * 注意：
 *  - 对象或函数通过静态方法 getStaticUID 生成 UID，内部进行去重。
 *  - 本实现不依赖 Dictionary 实例，仅借助其类似的思想和静态 UID 机制。
 */
class org.flashNight.naki.DataStructures.NakiSet extends Object {
    
    //============================================================================
    // 内部存储
    //============================================================================
    
    private var stringStorage:Object; // 用于存储字符串、数字、布尔等基础类型（它们当做字符串key存储）
    private var objectStorage:Object; // 用于存储对象、函数等的UID
    private var count:Number;         // 当前集合中元素的数量
    
    // 静态 UID 相关（在这演示，也可独立一个工具类）
    private static var uidCounter:Number = 1; // 用于给对象/函数分配唯一ID
    private static var uidMap:Object = {};    // 如果需要在某些场合取回原对象，可以维护此映射
    
    /**
     * 构造函数：初始化内部存储
     */
    public function NakiSet() {
        super();
        this.stringStorage = {};
        this.objectStorage = {};
        this.count = 0;
    }
    
    
    //============================================================================
    // 静态方法：为对象/函数生成全局唯一UID (AS2 中模拟)
    //============================================================================
    
    /**
     * 给目标对象/函数生成或获取静态UID。
     * 注意：此处设置 __setUID__ 不可枚举，可避免 for..in 时被遍历到。
     */
    private static function getStaticUID(key:Object):Number {
        // 如果是 null 或 undefined，直接返回 -1 表示不可用
        if (key == null || key == undefined) {
            return -1;
        }
        
        // 如果原先已经有UID，直接返回
        var uid:Number = key.__setUID__;
        if (uid != undefined) {
            return uid;
        }
        
        // 否则分配新的UID
        uid = uidCounter++;
        key.__setUID__ = uid;
        
        // 在某些场合下需要保存映射（可选，看你的需求）
        uidMap[uid] = key;
        
        // 在AS2中，可用 ASSetPropFlags 控制不可枚举
        // _global.ASSetPropFlags(key, ["__setUID__"], 1, false);
        
        return uid;
    }
    
    
    //============================================================================
    // 主要接口方法
    //============================================================================
    
    /**
     * 向集合中添加一个元素（如果元素已存在则忽略）。
     * @param item 要添加的元素，可以是字符串、数字、布尔、对象或函数
     */
    public function add(item:Object):Void {
        var keyType:String = typeof item;
        
        if (item == null || item == undefined) {
            // 忽略 null 或 undefined
            return;
        }
        
        // 处理基础类型
        if (keyType == "string" || keyType == "number" || keyType == "boolean") {
            // AS2 中 number、boolean 都可以当做字符串key
            var keyStr:String = String(item);
            if (stringStorage[keyStr] == undefined) {
                // 新元素
                stringStorage[keyStr] = true; // 标记存在即可
                count++;
            }
        } else {
            // 对象或函数
            var uid:Number = getStaticUID(item);
            if (uid == -1) {
                return; // 无法生成UID
            }
            var uidStr:String = String(uid);
            if (objectStorage[uidStr] == undefined) {
                // 新元素
                objectStorage[uidStr] = item; // 存储引用以便后续遍历或操作
                count++;
            }
        }
    }
    
    /**
     * 一次性添加多个元素
     * @param items 要添加的元素数组
     */
    public function addAll(items:Array):Void {
        for (var i:Number = 0; i < items.length; i++) {
            add(items[i]);
        }
    }
    
    /**
     * 从集合中移除一个元素（如果元素不存在则忽略）。
     * @param item 要移除的元素
     */
    public function remove(item:Object):Void {
        var keyType:String = typeof item;
        
        if (item == null || item == undefined) {
            return;
        }
        
        if (keyType == "string" || keyType == "number" || keyType == "boolean") {
            var keyStr:String = String(item);
            if (stringStorage[keyStr] != undefined) {
                delete stringStorage[keyStr];
                count--;
            }
        } else {
            var uid:Number = item.__setUID__;
            if (uid != undefined) {
                var uidStr:String = String(uid);
                if (objectStorage[uidStr] != undefined) {
                    delete objectStorage[uidStr];
                    // 可选：delete uidMap[uid]; // 如果希望彻底删掉映射
                    // 可选：delete item.__setUID__; // 若希望移除UID标识
                    count--;
                }
            }
        }
    }
    
    /**
     * 检查集合中是否包含指定元素。
     * @param item 要检查的元素
     * @return true表示存在，false表示不存在
     */
    public function has(item:Object):Boolean {
        if (item == null || item == undefined) {
            return false;
        }
        
        var keyType:String = typeof item;
        if (keyType == "string" || keyType == "number" || keyType == "boolean") {
            var keyStr:String = String(item);
            return (stringStorage[keyStr] != undefined);
        } else {
            var uid:Number = item.__setUID__;
            if (uid == undefined) {
                return false;
            }
            var uidStr:String = String(uid);
            return (objectStorage[uidStr] != undefined);
        }
    }
    
    /**
     * 清空集合
     */
    public function clear():Void {
        // 清空基础类型存储
        this.stringStorage = {};
        
        // 清空对象存储
        for (var uidStr:String in objectStorage) {
            delete objectStorage[uidStr];
        }
        
        this.count = 0;
    }
    
    /**
     * 获取当前集合的大小（元素个数）
     */
    public function size():Number {
        return this.count;
    }
    
    /**
     * 判断集合是否为空
     */
    public function isEmpty():Boolean {
        return (this.count == 0);
    }
    
    /**
     * 返回集合中所有元素的一个副本数组。
     * （无序）
     * @return 包含所有元素的Array
     */
    public function toArray():Array {
        var result:Array = [];
        
        // 先遍历 stringStorage
        for (var keyStr:String in stringStorage) {
            // keyStr 可能代表 string/number/boolean 原始值，需根据需求还原：
            // 不过AS2中只存了字符串，这里直接 push(keyStr) 也可以
            // 如果希望区分数字和字符串，可以尝试做类型解析。
            // 简化处理，直接放进去:
            result.push(keyStr);
        }
        
        // 再遍历 objectStorage
        for (var uidStr:String in objectStorage) {
            result.push(objectStorage[uidStr]);
        }
        
        return result;
    }
    
    //============================================================================
    // 集合运算
    //============================================================================
    
    /**
     * 并集：返回一个新的Set，包含当前Set和otherSet中所有元素
     * @param other 另一个Set
     * @return 新的Set对象，表示并集结果
     */
    public function union(other:NakiSet):NakiSet {
        var result:NakiSet = new NakiSet();
        
        // 先将当前集合的所有元素添加进去
        var arrThis:Array = this.toArray();
        for (var i:Number = 0; i < arrThis.length; i++) {
            result.add(arrThis[i]);
        }
        
        // 再把other集合的所有元素添加进去
        var arrOther:Array = other.toArray();
        for (var j:Number = 0; j < arrOther.length; j++) {
            result.add(arrOther[j]);
        }
        
        return result;
    }
    
    /**
     * 交集：返回一个新的Set，包含当前Set与otherSet的共同元素
     * @param other 另一个Set
     * @return 新的Set对象，表示交集结果
     */
    public function intersection(other:NakiSet):NakiSet {
        var result:NakiSet = new NakiSet();
        
        // 遍历当前集合，只有当 other 也包含时才添加
        var arrThis:Array = this.toArray();
        for (var i:Number = 0; i < arrThis.length; i++) {
            if (other.has(arrThis[i])) {
                result.add(arrThis[i]);
            }
        }
        
        return result;
    }
    
    /**
     * 差集：返回一个新的Set，包含在当前Set中但不在otherSet中的元素
     * @param other 另一个Set
     * @return 新的Set对象，表示差集结果
     */
    public function difference(other:NakiSet):NakiSet {
        var result:NakiSet = new NakiSet();
        
        // 只保留当前Set中那些不在otherSet里的元素
        var arrThis:Array = this.toArray();
        for (var i:Number = 0; i < arrThis.length; i++) {
            if (!other.has(arrThis[i])) {
                result.add(arrThis[i]);
            }
        }
        
        return result;
    }
    
    //============================================================================
    // 其他实用方法
    //============================================================================
    
    /**
     * 遍历所有元素并执行回调函数
     * @param callback 回调函数，格式 function(element:Object):Void
     */
    public function forEach(callback:Function):Void {
        var arr:Array = this.toArray();
        for (var i:Number = 0; i < arr.length; i++) {
            callback(arr[i]);
        }
    }
    
    /**
     * 销毁集合，清除所有内部引用，释放内存
     */
    public function destroy():Void {
        clear();
        this.stringStorage = null;
        this.objectStorage = null;
        // uidMap 可视需要是否清除，这里看实际需求
    }
}
