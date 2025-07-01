/**
 * BulletTypeData 类：用于封装子弹类型的数据和属性
 * 
 * 设计目标：
 * 1. 将子弹类型数据从子弹对象中隔离出来
 * 2. 提供不可变的类型数据对象，便于缓存和重用
 * 3. 简化子弹对象的结构，只保留必要的类型引用
 */
class org.flashNight.arki.bullet.BulletComponent.Type.BulletTypeData {

    // --- 位标志常量 ---
    public static var FLAG_MELEE:Number         = 1 << 0;
    public static var FLAG_CHAIN:Number         = 1 << 1;
    public static var FLAG_PIERCE:Number        = 1 << 2;
    public static var FLAG_TRANSPARENCY:Number  = 1 << 3;
    public static var FLAG_GRENADE:Number       = 1 << 4;
    public static var FLAG_EXPLOSIVE:Number     = 1 << 5;
    public static var FLAG_NORMAL:Number        = 1 << 6;

    // --- 缓存机制 ---
    private static var instanceCache:Object = {};
    private static var transparency:String = "|" + ["近战子弹", "近战联弹", "透明子弹"].join("|") + "|";

    // --- 公共只读属性 ---
    public var flags:Number;         // 原始标志位
    public var baseAsset:String;     // 基础素材名
    public var bulletType:String;    // 原始子弹种类字符串

    public var isMelee:Boolean;      // 是否近战
    public var isChain:Boolean;      // 是否联弹
    public var isPierce:Boolean;     // 是否穿刺
    public var isTransparency:Boolean; // 是否透明
    public var isGrenade:Boolean;    // 是否手雷
    public var isExplosive:Boolean;  // 是否爆炸
    public var isNormal:Boolean;     // 是否普通

    /**
     * 私有构造函数，只能通过工厂方法创建实例
     * @param bulletType:String 子弹种类字符串
     * @param flags:Number      计算好的类型标志位
     * @param baseAsset:String  计算好的基础素材名
     */
    private function BulletTypeData(bulletType:String, flags:Number, baseAsset:String) {
        this.bulletType = bulletType;
        this.flags = flags;
        this.baseAsset = baseAsset;

        // 根据 flags 初始化所有布尔属性
        this.isMelee        = (flags & BulletTypeData.FLAG_MELEE) != 0;
        this.isChain        = (flags & BulletTypeData.FLAG_CHAIN) != 0;
        this.isPierce       = (flags & BulletTypeData.FLAG_PIERCE) != 0;
        this.isTransparency = (flags & BulletTypeData.FLAG_TRANSPARENCY) != 0;
        this.isGrenade      = (flags & BulletTypeData.FLAG_GRENADE) != 0;
        this.isExplosive    = (flags & BulletTypeData.FLAG_EXPLOSIVE) != 0;
        this.isNormal       = (flags & BulletTypeData.FLAG_NORMAL) != 0;
    }

    /**
     * 工厂方法：从子弹种类字符串创建 BulletTypeData 实例
     * 使用缓存机制避免重复创建相同类型的实例
     * 
     * @param bulletType:String 子弹种类字符串
     * @return BulletTypeData 类型数据实例
     */
    public static function fromBulletType(bulletType:String):BulletTypeData {
        if (bulletType == undefined || bulletType == "") {
            trace("Warning: Invalid bullet type: " + bulletType);
            return null;
        }

        // 检查缓存
        var cached:BulletTypeData = instanceCache[bulletType];
        if (cached != undefined) {
            return cached;
        }

        // 计算标志位
        var flags:Number = calculateFlags(bulletType);
        
        // 计算基础素材名
        var baseAsset:String = calculateBaseAsset(bulletType, flags);

        // 创建新实例并缓存
        var instance:BulletTypeData = new BulletTypeData(bulletType, flags, baseAsset);
        instanceCache[bulletType] = instance;
        
        return instance;
    }

    /**
     * 直接从已知的 flags 和 baseAsset 创建实例（用于特殊情况）
     * 
     * @param bulletType:String 子弹种类字符串
     * @param flags:Number      预计算的标志位
     * @param baseAsset:String  预计算的基础素材名
     * @return BulletTypeData 类型数据实例
     */
    public static function fromFlags(bulletType:String, flags:Number, baseAsset:String):BulletTypeData {
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
    private static function calculateFlags(bulletType:String):Number {
        var isMelee:Boolean         = (bulletType.indexOf("近战") != -1);
        var isChain:Boolean         = (bulletType.indexOf("联弹") != -1);
        var isPierce:Boolean        = (bulletType.indexOf("穿刺") != -1);
        var isTransparency:Boolean  = (transparency.indexOf("|" + bulletType + "|") != -1);
        var isGrenade:Boolean       = (bulletType.indexOf("手雷") != -1);
        var isExplosive:Boolean     = (bulletType.indexOf("爆炸") != -1);

        // 普通子弹逻辑
        var isNormal:Boolean = !isPierce && !isExplosive &&
                               (isMelee || isTransparency || (bulletType.indexOf("普通") != -1));

        return ((isMelee         ? FLAG_MELEE         : 0)
              | (isChain         ? FLAG_CHAIN         : 0)
              | (isPierce        ? FLAG_PIERCE        : 0)
              | (isTransparency  ? FLAG_TRANSPARENCY  : 0)
              | (isGrenade       ? FLAG_GRENADE       : 0)
              | (isExplosive     ? FLAG_EXPLOSIVE     : 0)
              | (isNormal        ? FLAG_NORMAL        : 0));
    }

    /**
     * 计算基础素材名
     * 
     * @param bulletType:String 子弹种类字符串
     * @param flags:Number      标志位（用于判断是否为联弹）
     * @return String 基础素材名
     */
    private static function calculateBaseAsset(bulletType:String, flags:Number):String {
        var isChain:Boolean = (flags & FLAG_CHAIN) != 0;
        return isChain ? bulletType.split("-")[0] : bulletType;
    }

    /**
     * 检查是否具有指定的类型标志
     * 
     * @param flag:Number 要检查的标志位
     * @return Boolean 是否具有该标志
     */
    public function hasFlag(flag:Number):Boolean {
        return (this.flags & flag) != 0;
    }

    /**
     * 检查是否具有指定的多个类型标志（全部匹配）
     * 
     * @param flags:Number 要检查的标志位组合
     * @return Boolean 是否具有所有指定标志
     */
    public function hasAllFlags(flags:Number):Boolean {
        return (this.flags & flags) == flags;
    }

    /**
     * 检查是否具有指定的多个类型标志（任一匹配）
     * 
     * @param flags:Number 要检查的标志位组合
     * @return Boolean 是否具有任一指定标志
     */
    public function hasAnyFlag(flags:Number):Boolean {
        return (this.flags & flags) != 0;
    }

    /**
     * 提供调试输出方法
     * @return String 描述字符串
     */
    public function toString():String {
        var parts:Array = [];
        if (isMelee)         parts.push("MELEE");
        if (isChain)         parts.push("CHAIN");
        if (isPierce)        parts.push("PIERCE");
        if (isTransparency)  parts.push("TRANSPARENCY");
        if (isGrenade)       parts.push("GRENADE");
        if (isExplosive)     parts.push("EXPLOSIVE");
        if (isNormal)        parts.push("NORMAL");
        
        var flagsStr = parts.length > 0 ? parts.join(", ") : "NONE";
        return "[BulletTypeData type=" + bulletType + ", baseAsset=" + baseAsset + ", flags=" + flagsStr + "]";
    }

    /**
     * 清空所有缓存实例
     */
    public static function clearCache():Void {
        for (var key:String in instanceCache) {
            delete instanceCache[key];
        }
    }

    /**
     * 获取当前缓存的实例数量（用于调试）
     * @return Number 缓存实例数量
     */
    public static function getCacheSize():Number {
        var count:Number = 0;
        for (var key:String in instanceCache) {
            count++;
        }
        return count;
    }
}