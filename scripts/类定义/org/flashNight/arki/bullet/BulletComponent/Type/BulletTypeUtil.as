import org.flashNight.arki.bullet.BulletComponent.Type.BulletTypeData;

/**
 * BulletTypeUtil 类：子弹类型操作工具类
 * 
 * 职责：
 * 1. 负责所有类型计算逻辑
 * 2. 管理缓存机制
 * 3. 提供工厂方法创建 BulletTypeData 实例
 * 4. 提供各种实用工具方法
 * 5. 处理类型解析和标志位计算
 */
class org.flashNight.arki.bullet.BulletComponent.Type.BulletTypeUtil {

    // --- 缓存管理 ---
    private static var instanceCache:Object = {};
    
    // --- 类型识别配置 ---
    private static var transparencyTypes:String = "|" + ["近战子弹", "近战联弹", "透明子弹"].join("|") + "|";
    
    // --- 类型关键字配置 ---
    private static var typeKeywords:Object = {
        近战: BulletTypeData.FLAG_MELEE,
        联弹: BulletTypeData.FLAG_CHAIN,
        穿刺: BulletTypeData.FLAG_PIERCE,
        手雷: BulletTypeData.FLAG_GRENADE,
        爆炸: BulletTypeData.FLAG_EXPLOSIVE,
        普通: BulletTypeData.FLAG_NORMAL
    };

    /**
     * 工厂方法：从子弹种类字符串创建 BulletTypeData 实例
     * 
     * @param bulletType:String 子弹种类字符串
     * @return BulletTypeData 类型数据实例，失败时返回 null
     */
    public static function createFromType(bulletType:String):BulletTypeData {
        if (!isValidBulletType(bulletType)) {
            trace("Warning: Invalid bullet type: " + bulletType);
            return null;
        }

        // 检查缓存
        var cached:BulletTypeData = instanceCache[bulletType];
        if (cached != undefined) {
            return cached;
        }

        // 计算类型数据
        var flags:Number = calculateTypeFlags(bulletType);
        var baseAsset:String = calculateBaseAsset(bulletType, flags);

        // 创建新实例并缓存
        var instance:BulletTypeData = new BulletTypeData(bulletType, flags, baseAsset);
        instanceCache[bulletType] = instance;
        
        return instance;
    }

    /**
     * 工厂方法：从预计算的数据创建 BulletTypeData 实例
     * 
     * @param bulletType:String 子弹种类字符串
     * @param flags:Number      预计算的标志位
     * @param baseAsset:String  预计算的基础素材名
     * @return BulletTypeData 类型数据实例
     */
    public static function createFromData(bulletType:String, flags:Number, baseAsset:String):BulletTypeData {
        if (!isValidBulletType(bulletType)) {
            trace("Warning: Invalid bullet type: " + bulletType);
            return null;
        }

        // 检查缓存
        var cached:BulletTypeData = instanceCache[bulletType];
        if (cached != undefined) {
            return cached;
        }

        // 创建新实例并缓存
        var instance:BulletTypeData = new BulletTypeData(bulletType, flags, baseAsset);
        instanceCache[bulletType] = instance;
        
        return instance;
    }

    /**
     * 计算子弹类型的标志位
     * 
     * @param bulletType:String 子弹种类字符串
     * @return Number 计算后的标志位
     */
    public static function calculateTypeFlags(bulletType:String):Number {
        var flags:Number = 0;

        // 基础类型检测
        var isMelee:Boolean         = (bulletType.indexOf("近战") != -1);
        var isChain:Boolean         = (bulletType.indexOf("联弹") != -1);
        var isPierce:Boolean        = (bulletType.indexOf("穿刺") != -1);
        var isTransparency:Boolean  = isTransparencyType(bulletType);
        var isGrenade:Boolean       = (bulletType.indexOf("手雷") != -1);
        var isExplosive:Boolean     = (bulletType.indexOf("爆炸") != -1);

        // 普通子弹逻辑：非穿刺非爆炸，且为近战/透明或明确标注普通
        var isNormal:Boolean = !isPierce && !isExplosive &&
                               (isMelee || isTransparency || (bulletType.indexOf("普通") != -1));

        // 组合标志位
        if (isMelee)         flags |= BulletTypeData.FLAG_MELEE;
        if (isChain)         flags |= BulletTypeData.FLAG_CHAIN;
        if (isPierce)        flags |= BulletTypeData.FLAG_PIERCE;
        if (isTransparency)  flags |= BulletTypeData.FLAG_TRANSPARENCY;
        if (isGrenade)       flags |= BulletTypeData.FLAG_GRENADE;
        if (isExplosive)     flags |= BulletTypeData.FLAG_EXPLOSIVE;
        if (isNormal)        flags |= BulletTypeData.FLAG_NORMAL;

        return flags;
    }

    /**
     * 计算基础素材名
     * 
     * @param bulletType:String 子弹种类字符串
     * @param flags:Number      标志位（用于判断是否为联弹）
     * @return String 基础素材名
     */
    public static function calculateBaseAsset(bulletType:String, flags:Number):String {
        var isChain:Boolean = (flags & BulletTypeData.FLAG_CHAIN) != 0;
        
        if (isChain) {
            // 联弹类型：取 "-" 分隔符前的部分
            var parts:Array = bulletType.split("-");
            return parts.length > 0 ? parts[0] : bulletType;
        }
        
        return bulletType;
    }

    /**
     * 检查是否为透明类型
     * 
     * @param bulletType:String 子弹种类字符串
     * @return Boolean 是否为透明类型
     */
    public static function isTransparencyType(bulletType:String):Boolean {
        return transparencyTypes.indexOf("|" + bulletType + "|") != -1;
    }

    /**
     * 验证子弹类型字符串是否有效
     * 
     * @param bulletType:String 子弹种类字符串
     * @return Boolean 是否有效
     */
    public static function isValidBulletType(bulletType:String):Boolean {
        return bulletType != undefined && bulletType != "" && bulletType.length > 0;
    }

    /**
     * 解析子弹类型字符串，返回包含的所有类型关键字
     * 
     * @param bulletType:String 子弹种类字符串
     * @return Array 包含的类型关键字数组
     */
    public static function parseTypeKeywords(bulletType:String):Array {
        var foundKeywords:Array = [];
        
        for (var keyword:String in typeKeywords) {
            if (bulletType.indexOf(keyword) != -1) {
                foundKeywords.push(keyword);
            }
        }
        
        // 特殊处理透明类型
        if (isTransparencyType(bulletType)) {
            foundKeywords.push("透明");
        }
        
        return foundKeywords;
    }

    /**
     * 将标志位转换为可读的字符串
     * 
     * @param flags:Number 标志位值
     * @return String 可读字符串
     */
    public static function flagsToString(flags:Number):String {
        var parts:Array = [];
        
        if (flags & BulletTypeData.FLAG_MELEE)         parts.push("MELEE");
        if (flags & BulletTypeData.FLAG_CHAIN)         parts.push("CHAIN");
        if (flags & BulletTypeData.FLAG_PIERCE)        parts.push("PIERCE");
        if (flags & BulletTypeData.FLAG_TRANSPARENCY)  parts.push("TRANSPARENCY");
        if (flags & BulletTypeData.FLAG_GRENADE)       parts.push("GRENADE");
        if (flags & BulletTypeData.FLAG_EXPLOSIVE)     parts.push("EXPLOSIVE");
        if (flags & BulletTypeData.FLAG_NORMAL)        parts.push("NORMAL");
        
        return parts.length > 0 ? parts.join(", ") : "NONE";
    }

    /**
     * 从缓存中获取类型数据（如果存在）
     * 
     * @param bulletType:String 子弹种类字符串
     * @return BulletTypeData 缓存的实例，不存在时返回 null
     */
    public static function getCachedTypeData(bulletType:String):BulletTypeData {
        return instanceCache[bulletType];
    }

    /**
     * 预加载常用的子弹类型到缓存
     * 
     * @param bulletTypes:Array 要预加载的子弹类型数组
     */
    public static function preloadTypes(bulletTypes:Array):Void {
        for (var i:Number = 0; i < bulletTypes.length; i++) {
            var bulletType:String = bulletTypes[i];
            if (isValidBulletType(bulletType) && !isCached(bulletType)) {
                createFromType(bulletType);
            }
        }
    }

    /**
     * 检查指定类型是否已缓存
     * 
     * @param bulletType:String 子弹种类字符串
     * @return Boolean 是否已缓存
     */
    public static function isCached(bulletType:String):Boolean {
        return instanceCache[bulletType] != undefined;
    }

    /**
     * 获取所有已缓存的子弹类型
     * 
     * @return Array 已缓存的子弹类型数组
     */
    public static function getCachedTypes():Array {
        var types:Array = [];
        for (var bulletType:String in instanceCache) {
            types.push(bulletType);
        }
        return types;
    }

    /**
     * 清空指定类型的缓存
     * 
     * @param bulletType:String 要清空的子弹种类字符串
     * @return Boolean 是否成功清空
     */
    public static function clearTypeCache(bulletType:String):Boolean {
        if (instanceCache[bulletType] != undefined) {
            delete instanceCache[bulletType];
            return true;
        }
        return false;
    }

    /**
     * 清空所有缓存
     */
    public static function clearAllCache():Void {
        for (var key:String in instanceCache) {
            delete instanceCache[key];
        }
    }

    /**
     * 获取当前缓存统计信息
     * 
     * @return Object 包含缓存统计的对象
     */
    public static function getCacheStats():Object {
        var count:Number = 0;
        var memoryEstimate:Number = 0;
        
        for (var key:String in instanceCache) {
            count++;
            // 粗略估算内存占用（字符串长度 + 对象开销）
            memoryEstimate += key.length * 2 + 100; // 假设每个对象约100字节开销
        }
        
        return {
            count: count,
            memoryEstimate: memoryEstimate,
            types: getCachedTypes()
        };
    }

    /**
     * 批量创建类型数据
     * 
     * @param bulletTypes:Array 子弹类型字符串数组
     * @return Array 对应的 BulletTypeData 实例数组
     */
    public static function createBatch(bulletTypes:Array):Array {
        var results:Array = [];
        
        for (var i:Number = 0; i < bulletTypes.length; i++) {
            var typeData:BulletTypeData = createFromType(bulletTypes[i]);
            results.push(typeData);
        }
        
        return results;
    }

    /**
     * 添加新的透明类型
     * 
     * @param bulletType:String 要添加的透明类型
     */
    public static function addTransparencyType(bulletType:String):Void {
        if (transparencyTypes.indexOf("|" + bulletType + "|") == -1) {
            transparencyTypes = transparencyTypes.slice(0, -1) + bulletType + "|";
            // 如果该类型已缓存，需要重新计算
            clearTypeCache(bulletType);
        }
    }

    /**
     * 移除透明类型
     * 
     * @param bulletType:String 要移除的透明类型
     */
    public static function removeTransparencyType(bulletType:String):Void {
        var target:String = "|" + bulletType + "|";
        var index:Number = transparencyTypes.indexOf(target);
        if (index != -1) {
            transparencyTypes = transparencyTypes.substring(0, index) + 
                               transparencyTypes.substring(index + target.length);
            // 如果该类型已缓存，需要重新计算
            clearTypeCache(bulletType);
        }
    }
}