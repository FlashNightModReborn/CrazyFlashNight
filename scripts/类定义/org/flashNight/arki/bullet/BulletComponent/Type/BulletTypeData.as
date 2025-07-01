/**
 * BulletTypeData 类：纯净的子弹类型数据容器
 * 
 * 设计原则：
 * 1. 只包含数据和最基本的访问方法
 * 2. 不包含任何业务逻辑或计算逻辑
 * 3. 不可变对象，创建后不允许修改
 * 4. 轻量级，便于缓存和传递
 */
class org.flashNight.arki.bullet.BulletComponent.Type.BulletTypeData {

    // --- 位标志常量 ---
    public static var FLAG_MELEE:Number         = 1 << 0;  // 近战
    public static var FLAG_CHAIN:Number         = 1 << 1;  // 联弹
    public static var FLAG_PIERCE:Number        = 1 << 2;  // 穿刺
    public static var FLAG_TRANSPARENCY:Number  = 1 << 3;  // 透明
    public static var FLAG_GRENADE:Number       = 1 << 4;  // 手雷
    public static var FLAG_EXPLOSIVE:Number     = 1 << 5;  // 爆炸
    public static var FLAG_NORMAL:Number        = 1 << 6;  // 普通

    // --- 不可变的公共属性 ---
    public var bulletType:String;    // 原始子弹种类字符串
    public var flags:Number;         // 类型标志位
    public var baseAsset:String;     // 基础素材名

    // --- 便捷的布尔属性（只读） ---
    public var isMelee:Boolean;      // 是否近战
    public var isChain:Boolean;      // 是否联弹
    public var isPierce:Boolean;     // 是否穿刺
    public var isTransparency:Boolean; // 是否透明
    public var isGrenade:Boolean;    // 是否手雷
    public var isExplosive:Boolean;  // 是否爆炸
    public var isNormal:Boolean;     // 是否普通

    /**
     * 构造函数：创建不可变的数据对象
     * 
     * @param bulletType:String 子弹种类字符串
     * @param flags:Number      类型标志位
     * @param baseAsset:String  基础素材名
     */
    public function BulletTypeData(bulletType:String, flags:Number, baseAsset:String) {
        // 设置基础数据
        this.bulletType = bulletType;
        this.flags = flags;
        this.baseAsset = baseAsset;

        // 根据标志位计算布尔属性（只计算一次）
        this.isMelee        = (flags & FLAG_MELEE) != 0;
        this.isChain        = (flags & FLAG_CHAIN) != 0;
        this.isPierce       = (flags & FLAG_PIERCE) != 0;
        this.isTransparency = (flags & FLAG_TRANSPARENCY) != 0;
        this.isGrenade      = (flags & FLAG_GRENADE) != 0;
        this.isExplosive    = (flags & FLAG_EXPLOSIVE) != 0;
        this.isNormal       = (flags & FLAG_NORMAL) != 0;
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
     * @param targetFlags:Number 要检查的标志位组合
     * @return Boolean 是否具有所有指定标志
     */
    public function hasAllFlags(targetFlags:Number):Boolean {
        return (this.flags & targetFlags) == targetFlags;
    }

    /**
     * 检查是否具有指定的多个类型标志（任一匹配）
     * 
     * @param targetFlags:Number 要检查的标志位组合
     * @return Boolean 是否具有任一指定标志
     */
    public function hasAnyFlag(targetFlags:Number):Boolean {
        return (this.flags & targetFlags) != 0;
    }

    /**
     * 获取类型标志的字符串表示（用于调试）
     * 
     * @return String 标志的字符串表示
     */
    public function getFlagsString():String {
        var parts:Array = [];
        if (isMelee)         parts.push("MELEE");
        if (isChain)         parts.push("CHAIN");
        if (isPierce)        parts.push("PIERCE");
        if (isTransparency)  parts.push("TRANSPARENCY");
        if (isGrenade)       parts.push("GRENADE");
        if (isExplosive)     parts.push("EXPLOSIVE");
        if (isNormal)        parts.push("NORMAL");
        
        return parts.length > 0 ? parts.join(", ") : "NONE";
    }

    /**
     * 对象的字符串表示（用于调试）
     * 
     * @return String 对象描述
     */
    public function toString():String {
        return "[BulletTypeData type=" + bulletType + 
               ", baseAsset=" + baseAsset + 
               ", flags=" + getFlagsString() + "]";
    }

    /**
     * 比较两个 BulletTypeData 对象是否相等
     * 
     * @param other:BulletTypeData 要比较的对象
     * @return Boolean 是否相等
     */
    public function equals(other:BulletTypeData):Boolean {
        if (other == null) return false;
        return this.bulletType == other.bulletType && 
               this.flags == other.flags && 
               this.baseAsset == other.baseAsset;
    }

    /**
     * 获取对象的哈希码（基于 bulletType）
     * 
     * @return String 哈希码
     */
    public function hashCode():String {
        return this.bulletType;
    }
}