/**
 * Dictionary 类提供支持任意类型键（字符串、对象、函数）的键值对存储。
 *
 * 版本历史:
 * v2.2 (2026-01) - 三方交叉审查综合修复
 *   [CRITICAL] 使用实例级 _uidToKey 替代静态 uidMap，修复跨实例破坏问题
 *              之前：A字典 removeItem 会删除 uidMap 中的映射，导致 B字典 getKeys 返回 undefined
 *              现在：每个字典实例维护自己的 uid→key 映射，互不干扰
 *   [DEPRECATED] 静态 uidMap 保留用于 getUID 的向后兼容，但不再被实例方法使用
 *
 * v2.1 (2026-01) - 三方交叉审查修复
 *   [FIX] getStaticUID 为 __dictUID 设置不可枚举属性，避免污染 for..in 循环
 *   [FIX] removeItem/clear 中删除 uidMap 映射，防止内存泄漏
 *   [NOTE] getStaticUID 不写入 uidMap（保持原设计），因此不存在泄漏风险
 *
 * UID 系统说明:
 *   - uidCounter 使用负数递减，天然与字符串键隔离
 *   - __dictUID 属性添加到对象时会设置为不可枚举，避免污染 for..in
 *   - getStaticUID 不持有对象引用（不写入 uidMap），适合外部使用
 *   - [v2.2] setItem 使用实例级 _uidToKey，不再写入静态 uidMap
 */
class org.flashNight.naki.DataStructures.Dictionary extends Object {

    private var stringStorage:Object;    // 用于存储字符串键的对象
    private var objectStorage:Object;    // 用于存储对象和函数键的对象

    /** [v2.2] 实例级 uid→key 映射，替代静态 uidMap，避免跨实例破坏 */
    private var _uidToKey:Object;

    // 使用负数递减，天然与字符串键隔离
    private static var uidCounter:Number = 0;
    /** @deprecated 仅用于 getUID 的向后兼容，实例方法不再使用 */
    private static var uidMap:Object = {};
    private var count:Number = 0;

    private var keysCache:Array = null;
    private var isKeysCacheDirty:Boolean = true;

    /**
     * 构造函数，初始化字典对象
     */
    public function Dictionary() {
        super();
        stringStorage = {};
        objectStorage = {};
        _uidToKey = {};  // [v2.2] 初始化实例级映射
    }

    /**
     * 获取对象的唯一标识符（实例方法版本）
     * 注意：此方法会将对象存入静态 uidMap，可能阻止 GC
     *
     * @param key 键（对象或函数）
     * @return 返回唯一标识符
     */
    public function getUID(key:Object):Number {
        var uid:Number = key.__dictUID;
        if (uid === undefined) {
            uid = key.__dictUID = --uidCounter;
            uidMap[uid] = key;
            // [v2.1 FIX] 设置 __dictUID 不可枚举，避免污染 for..in
            _global.ASSetPropFlags(key, ["__dictUID"], 1, true);
        }
        return uid;
    }

    /**
     * 获取对象的唯一标识符（静态方法版本）
     * 不持有对象引用，不写入 uidMap，适合外部使用
     *
     * [v2.1 FIX] 首次赋值时设置 __dictUID 为不可枚举
     *
     * @param key 键（对象或函数）
     * @return 返回唯一标识符
     */
    public static function getStaticUID(key:Object):Number {
        var uid:Number = key.__dictUID;
        if (uid === undefined) {
            uid = key.__dictUID = --uidCounter;
            // [v2.1 FIX] 设置 __dictUID 不可枚举，避免污染 for..in
            // 这是一次性成本，仅在首次分配 UID 时发生，不影响热路径
            _global.ASSetPropFlags(key, ["__dictUID"], 1, true);
        }
        return uid;
    }

    /**
     * 强制更新或分配一个新的 UID 给指定对象。
     * 警告：高风险操作，会使对象在已存在的 Dictionary 中"失联"
     *
     * @param key 需要强制更新 UID 的对象
     * @return 返回新的 UID
     */
    public static function forceUpdateUID(key:Object):Number {
        if (key == null || typeof key == "string") {
            return undefined;
        }

        var oldUID:Number = key.__dictUID;
        if (oldUID !== undefined && uidMap != null) {
            delete uidMap[oldUID];
        }

        var newUID:Number = --uidCounter;
        key.__dictUID = newUID;

        if (uidMap != null) {
            uidMap[newUID] = key;
        }

        _global.ASSetPropFlags(key, ["__dictUID"], 1, true);

        return newUID;
    }

    /**
     * 添加或更新键值对
     *
     * [v2.2] 使用实例级 _uidToKey 替代静态 uidMap
     *
     * @param key 键（可以是字符串、对象或函数）
     * @param value 与键关联的值
     */
    public function setItem(key, value):Void {
        var keyType:String = typeof key;

        if (keyType == "string") {
            if (typeof(stringStorage[key]) == "undefined") {
                count++;
                isKeysCacheDirty = true;
            }
            stringStorage[key] = value;
        } else {
            var uid:Number = key.__dictUID;
            if (uid === undefined) {
                uid = key.__dictUID = --uidCounter;
                // [v2.1 FIX] 设置 __dictUID 不可枚举
                _global.ASSetPropFlags(key, ["__dictUID"], 1, true);
            }
            var uidStr:String = String(uid);
            if (typeof(objectStorage[uidStr]) == "undefined") {
                count++;
                isKeysCacheDirty = true;
                // [v2.2] 仅在首次添加时写入实例级映射
                _uidToKey[uidStr] = key;
            }
            objectStorage[uidStr] = value;
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
            var val = stringStorage[key];
            return (val !== undefined) ? val : null;
        } else {
            var uid:Number = key.__dictUID;
            if (uid === undefined) return null;
            var uidStr:String = String(uid);
            var val = objectStorage[uidStr];
            return (val !== undefined) ? val : null;
        }
    }

    /**
     * 删除指定的键值对
     *
     * [v2.2] 只删除实例级 _uidToKey 中的映射，不影响其他 Dictionary 实例
     *
     * @param key 键（可以是字符串、对象或函数）
     */
    public function removeItem(key):Void {
        var keyType:String = typeof key;

        if (keyType == "string") {
            if (typeof(stringStorage[key]) != "undefined") {
                delete stringStorage[key];
                count--;
                isKeysCacheDirty = true;
            }
        } else {
            var uid:Number = key.__dictUID;
            if (uid !== undefined) {
                var uidStr:String = String(uid);
                if (typeof(objectStorage[uidStr]) != "undefined") {
                    delete objectStorage[uidStr];
                    // [v2.2] 只删除实例级映射，不影响其他 Dictionary 实例
                    delete _uidToKey[uidStr];
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
            if (uid === undefined) return false;
            var uidStr:String = String(uid);
            return (typeof(objectStorage[uidStr]) != "undefined");
        }
    }

    /**
     * 获取字典中所有的键
     *
     * [v2.2] 使用实例级 _uidToKey 替代静态 uidMap
     *
     * @return 返回包含所有键的数组
     */
    public function getKeys():Array {
        if (isKeysCacheDirty || keysCache === null) {
            keysCache = [];

            for (var key:String in stringStorage) {
                keysCache.push(key);
            }

            // [v2.2] 从实例级 _uidToKey 获取原始对象，避免跨实例破坏
            for (var uidStr:String in objectStorage) {
                var originalKey = _uidToKey[uidStr];
                if (originalKey !== undefined) {
                    keysCache.push(originalKey);
                }
            }

            isKeysCacheDirty = false;
        }

        return keysCache.concat();
    }

    /**
     * 清空字典
     *
     * [v2.2] 只清空实例级数据，不影响其他 Dictionary 实例
     */
    public function clear():Void {
        stringStorage = {};
        objectStorage = {};
        _uidToKey = {};  // [v2.2] 直接重置实例级映射

        count = 0;
        isKeysCacheDirty = true;
        keysCache = null;
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
            getKeys();
        }
        var len:Number = keysCache.length;
        for (var i:Number = 0; i < len; i++) {
            var key = keysCache[i];
            var value = getItem(key);
            callback(key, value);
        }
    }

    /**
     * 销毁字典实例
     */
    public function destroy():Void {
        clear();
        stringStorage = null;
        objectStorage = null;
        _uidToKey = null;  // [v2.2]
        keysCache = null;
    }

    /**
     * 静态方法：清理所有静态资源引用
     * 注意：不重置 uidCounter，保持已分配 UID 的稳定性
     */
    public static function destroyStatic():Void {
        uidMap = null;
    }
}
