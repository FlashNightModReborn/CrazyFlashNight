class org.flashNight.naki.DataStructures.Dictionary extends Object {

    private var stringStorage:Object;    // 用于存储字符串键的对象
    private var objectStorage:Object;    // 用于存储对象和函数键的对象
    private static var uidCounter:Number = 1; // 用于生成对象和函数键的唯一标识符（UID）
    private static var uidMap:Object = {}; // 用于映射对象和函数键的 UID 到原始对象
    private var count:Number = 0;         // 存储当前字典中的键值对数量

    // 缓存键列表及其状态
    private var keysCache:Array = null;  // 用于缓存所有键的数组
    private var isKeysCacheDirty:Boolean = true; // 标记缓存的键列表是否需要更新

    /**
     * 构造函数，初始化字典对象
     */
    public function Dictionary() {
        super();
        stringStorage = {};  // 初始化字符串键存储对象
        objectStorage = {};  // 初始化对象/函数键存储对象
    }

    /**
     * 设置uid，以获得对象的唯一标识符管理
     * @param key 键（可以是字符串、对象或函数）
     * @return 返回与该键关联的值，如果键不存在则返回 null,返回number以便进行数学运算加速
     */
    public function getUID(key:Object):Number {
        var uid:Number = key.__dictUID;
        if (uid === undefined) {
            uid = key.__dictUID = uidCounter++;
            uidMap[uid] = key;
            _global.ASSetPropFlags(key, ["__dictUID"], 1, true); // 设置 __dictUID 不可枚举
        }
        return uid;
    }

    /**
     * 静态版getUID方法，用于外部使用，不持有引用避免循环引用干扰正常gc
     * @param key 键（可以是字符串、对象或函数）
     * @return 返回与该键关联的唯一标识符
     */
    public static function getStaticUID(key:Object):Number {
        var uid:Number = key.__dictUID;
        if (uid === undefined) {
            uid = key.__dictUID = uidCounter++;
            // uidMap[uid] = key;
            _global.ASSetPropFlags(key, ["__dictUID"], 1, true); // 设置 __dictUID 不可枚举
        }
        return uid;
    }


    /**
     * 添加或更新键值对
     * @param key 键（可以是字符串、对象或函数）
     * @param value 与键关联的值
     */
    public function setItem(key, value):Void {
        var keyType:String = typeof key;
        
        if (keyType == "string") {
            // 检查该字符串键是否不存在，若不存在则计数+1并标记缓存键列表为脏
            if (typeof(stringStorage[key]) == "undefined") {
                count++;
                isKeysCacheDirty = true;
            }
            stringStorage[key] = value;  // 为字符串键设置对应的值
        } else {
            // 处理对象或函数键
            var uid:Number = key.__dictUID;
            if (uid === undefined) {
                // 如果该对象没有 UID，则分配新的 UID 并存储在 uidMap 中
                uid = key.__dictUID = uidCounter++;
                uidMap[uid] = key;
                count++;
                isKeysCacheDirty = true;
            }
            var uidStr:String = String(uid);  // 将 UID 转换为字符串作为键
            if (typeof(objectStorage[uidStr]) == "undefined") {
                count++;
                isKeysCacheDirty = true;
            }
            objectStorage[uidStr] = value;  // 为对象/函数键设置对应的值
        }
    }

    /**
     * 获取指定键的值
     * @param key 键（可以是字符串、对象或函数）
     * @return 返回与该键关联的值，如果键不存在则返回 null
     */
    public function getItem(key) {
        var keyType:String = typeof key;
        
        if (keyType == "string") {
            var val = stringStorage[key];  // 从字符串存储中查找值
            return (val !== undefined) ? val : null;
        } else {
            var uid:Number = key.__dictUID;
            if (uid === undefined) return null;  // 如果该对象没有 UID，直接返回 null
            var uidStr:String = String(uid);
            var val = objectStorage[uidStr];  // 从对象存储中查找值
            return (val !== undefined) ? val : null;
        }
    }

    /**
     * 删除指定的键值对
     * @param key 键（可以是字符串、对象或函数）
     */
    public function removeItem(key):Void {
        var keyType:String = typeof key;
        
        if (keyType == "string") {
            // 如果字符串键存在，则删除并更新计数和缓存状态
            if (typeof(stringStorage[key]) != "undefined") {
                delete stringStorage[key];
                count--;
                isKeysCacheDirty = true;
            }
        } else {
            // 如果是对象或函数键，删除关联的 UID 和存储对象
            var uid:Number = key.__dictUID;
            if (uid !== undefined) {
                var uidStr:String = String(uid);
                if (typeof(objectStorage[uidStr]) != "undefined") {
                    delete objectStorage[uidStr];
                    delete uidMap[uid];  // 删除 UID 映射
                    delete key.__dictUID;  // 删除对象上的 UID 属性
                    count--;
                    isKeysCacheDirty = true;
                }
            }
        }
    }

    /**
     * 检查字典中是否包含指定的键
     * @param key 键（可以是字符串、对象或函数）
     * @return 如果键存在，返回 true；否则返回 false
     */
    public function hasKey(key):Boolean {
        var keyType:String = typeof key;
        
        if (keyType == "string") {
            return (typeof(stringStorage[key]) != "undefined");
        } else {
            var uid:Number = key.__dictUID;
            if (uid === undefined) return false;  // 对象或函数没有 UID 则返回 false
            var uidStr:String = String(uid);
            return (typeof(objectStorage[uidStr]) != "undefined");
        }
    }

    /**
     * 获取字典中所有的键
     * @return 返回包含所有键的数组（字符串键、对象键、函数键）
     */
    public function getKeys():Array {
        if (isKeysCacheDirty || keysCache === null) {
            keysCache = [];
            
            // 遍历存储字符串键的对象
            for (var key:String in stringStorage) {
                keysCache.push(key);
            }
            
            // 遍历存储对象/函数键的对象，并通过 UID 获取原始键
            for (var uidStr:String in objectStorage) {
                var originalKey = uidMap[Number(uidStr)];
                keysCache.push(originalKey);
            }
            
            isKeysCacheDirty = false;  // 键列表缓存更新完毕，标记为干净
        }
        
        return keysCache.concat();  // 返回键列表的副本，避免外部修改
    }

    /**
     * 清空字典
     * 移除所有的键值对，并清理相关的引用
     */
    public function clear():Void {
        // 清空字符串存储
        stringStorage = {};
        
        // 清空对象存储和 UID 映射
        for (var uidStr:String in objectStorage) {
            var key = uidMap[Number(uidStr)];
            if (key !== undefined) {
                delete key.__dictUID;  // 删除对象上的 UID 属性
            }
            delete objectStorage[uidStr];
            delete uidMap[Number(uidStr)];
        }
        
        uidCounter = 1;  // 重置 UID 计数器
        count = 0;       // 重置键值对数量
        isKeysCacheDirty = true;  // 标记键缓存为脏
        keysCache = null;         // 清空键缓存
    }

    /**
     * 获取字典中键值对的数量
     * @return 返回字典中的键值对数量
     */
    public function getCount():Number {
        return count;
    }

    /**
     * 遍历所有键值对，并对每个键值对执行回调函数
     * @param callback 回调函数，格式为 function(key, value)
     */
    public function forEach(callback:Function):Void {
        if (isKeysCacheDirty || keysCache === null) {
            getKeys();  // 确保键列表是最新的
        }
        var len:Number = keysCache.length;
        for (var i:Number = 0; i < len; i++) {
            var key = keysCache[i];
            var value = getItem(key);  // 获取键对应的值
            callback(key, value);  // 执行回调函数
        }
    }

    /**
     * 销毁字典
     * 清理所有的引用，防止内存泄漏
     */
    public function destroy():Void {
        clear();  // 清空字典内容
        stringStorage = null;  // 清理字符串存储对象
        objectStorage = null;  // 清理对象存储对象
        uidMap = null;         // 清理 UID 映射对象
        keysCache = null;      // 清理键缓存
    }

    /**
     * 静态方法：清空所有静态资源引用
     * 重置 UID 映射表和计数器，确保不再持有任何静态引用。
     */
    public static function destroyStatic():Void {
        // 直接清空静态引用
        uidMap = null;       // 清除 UID 映射表引用
        // uidCounter = 1;      // 重置 UID 计数器
    }


    
}

