import org.flashNight.arki.bullet.BulletComponent.Type.ITypesetter;
import org.flashNight.gesh.object.ObjectUtil;

/**
 * BulletTypesetter 类用于设置子弹类型的标志位和基础素材名。
 * 
 * 功能：
 * 1. 定义各种子弹类型的位标志。
 * 2. 根据子弹种类字符串计算其属性标志（例如：近战、联弹、穿刺等）。
 * 3. 缓存计算结果以提高性能。
 * 4. 提取基础素材名（子弹种类的前缀部分）。
 * 5. 支持清空缓存和获取基础素材名的方法。
 */
class org.flashNight.arki.bullet.BulletComponent.Type.BulletTypesetter implements ITypesetter {

    /**
     * 子弹类型位标志定义
     * 每种子弹类型使用一个唯一的二进制位表示。
     */
    private static var FLAG_MELEE:Number         = 1 << 0; // 近战子弹
    private static var FLAG_CHAIN:Number         = 1 << 1; // 联弹子弹
    private static var FLAG_PIERCE:Number        = 1 << 2; // 穿刺子弹
    private static var FLAG_TRANSPARENCY:Number  = 1 << 3; // 透明子弹
    private static var FLAG_GRENADE:Number       = 1 << 4; // 手雷子弹
    private static var FLAG_EXPLOSIVE:Number     = 1 << 5; // 爆炸子弹
    private static var FLAG_NORMAL:Number        = 1 << 6; // 普通子弹
    private static var FLAG_VERTICAL:Number      = 1 << 7; // 纵向子弹

    /**
     * 缓存对象
     * 键（key）：子弹种类字符串。
     * 值（value）：包含以下属性的对象：
     * - flags：子弹类型的标志位。
     * - baseAsset：基础素材名（子弹种类的前缀部分）。
     */
    private static var typeCache:Object = {};

    /**
     * 定义透明类型的完整匹配列表，用于快速检查透明子弹。
     * 透明类型字符串使用 "|" 作为分隔符。
     */
    private static var transparency:String = "|" + ["近战子弹", "近战联弹", "透明子弹"].join("|") + "|";

    /**
     * 构造函数
     * 该类不需要实例化，因此不进行任何初始化。
     */
    public function BulletTypesetter() {
        // 无需初始化
    }

    /**
     * 设置子弹类型标志位。
     * 
     * @param bullet:Object 子弹对象，需包含子弹种类 (子弹种类: String)。
     * @return Number 计算后的标志位值，如果子弹或子弹种类未定义，则返回 undefined。
     */
    public static function setTypeFlags(bullet:Object):Number {
        if (bullet == undefined || bullet.子弹种类 == undefined) {
            trace("Warning: Bullet object or 子弹种类 is undefined.");
            return;
        }

        var bulletType:String = bullet.子弹种类;
        var cachedData:Object = typeCache[bulletType];

        // 如果缓存中不存在，进行计算
        if (cachedData == undefined) {
            var isMelee:Boolean         = (bulletType.indexOf("近战") != -1);         // 是否近战子弹
            var isChain:Boolean         = (bulletType.indexOf("联弹") != -1);         // 是否联弹子弹
            var isPierce:Boolean        = (bulletType.indexOf("穿刺") != -1);         // 是否穿刺子弹
            var isTransparency:Boolean  = (transparency.indexOf("|" + bulletType + "|") != -1); // 是否透明子弹
            var isGrenade:Boolean       = (bulletType.indexOf("手雷") != -1);         // 是否手雷子弹
            var isExplosive:Boolean     = (bulletType.indexOf("爆炸") != -1);         // 是否爆炸子弹
            var isVertical:Boolean      = (bulletType.indexOf("纵向") != -1);         // 是否纵向子弹

            // 是否普通子弹的逻辑
            var isNormal:Boolean = !isPierce && !isExplosive &&
                                   (isMelee || isTransparency || (bulletType.indexOf("普通") != -1));

            // 计算标志位
            var flags:Number = ((isMelee         ? FLAG_MELEE         : 0)
                              | (isChain         ? FLAG_CHAIN         : 0)
                              | (isPierce        ? FLAG_PIERCE        : 0)
                              | (isTransparency  ? FLAG_TRANSPARENCY  : 0)
                              | (isGrenade       ? FLAG_GRENADE       : 0)
                              | (isExplosive     ? FLAG_EXPLOSIVE     : 0)
                              | (isNormal        ? FLAG_NORMAL        : 0)
                              | (isVertical      ? FLAG_VERTICAL      : 0));

            // 对联弹提取基础素材名（取子弹种类中 "-" 分隔符前的部分）
            var baseAsset:String = isChain ? bulletType.split("-")[0] : bulletType;

            // 将结果缓存
            typeCache[bulletType] = { flags: flags, baseAsset: baseAsset };
        }

        // 从缓存中读取数据
        var data:Object = typeCache[bulletType];
        var flags:Number = data.flags;
        var baseAsset:String = data.baseAsset;

        // 设置子弹检测标志
        bullet.近战检测 = ((flags & FLAG_MELEE) != 0);
        bullet.联弹检测 = ((flags & FLAG_CHAIN) != 0);
        bullet.穿刺检测 = bullet.穿刺检测 || ((flags & FLAG_PIERCE) != 0);
        bullet.透明检测 = bullet.透明检测 || ((flags & FLAG_TRANSPARENCY) != 0);
        bullet.手雷检测 = bullet.手雷检测 || ((flags & FLAG_GRENADE) != 0);
        bullet.爆炸检测 = bullet.爆炸检测 || ((flags & FLAG_EXPLOSIVE) != 0);
        bullet.纵向检测 = bullet.纵向检测 || ((flags & FLAG_VERTICAL) != 0);

        // 更新普通子弹标志
        bullet.普通检测 = ((flags & FLAG_NORMAL) != 0);

        // 缓存基础素材名
        bullet.baseAsset = baseAsset;

        // 缓存标志位
        bullet.flags = flags;
        // _root.发布消息(baseAsset + ":" + flagsToString(flags))
        return flags
    }

    /**
     * 获取子弹的 flags 值，且不改变原始子弹对象。
     * 
     * @param bullet:Object 子弹对象，需包含子弹种类 (子弹种类: String)。
     * @return Number 计算后的标志位值，如果子弹或子弹种类未定义，则返回 0。
     */
    public static function getFlags(bullet:Object):Number {
        if (bullet == undefined || bullet.子弹种类 == undefined) {
            trace("Warning: Bullet object or 子弹种类 is undefined.");
            return 0;
        }
        
        var bulletType:String = bullet.子弹种类;
        var cachedData:Object = typeCache[bulletType];
        
        if (cachedData == undefined) {
            // 创建一个假子弹对象，仅包含必要的属性，避免影响原始对象
            var dummyBullet:Object = { 子弹种类: bulletType };
            return setTypeFlags(dummyBullet);
        }
        
        return cachedData.flags;
    }


    /**
     * 获取基础素材名。
     * 
     * @param bulletType:String 子弹种类字符串。
     * @return String 基础素材名。
     */
    public static function getBaseAsset(bulletType:String):String {
        var cachedData:Object = typeCache[bulletType];
        if (cachedData != undefined) {
            return cachedData.baseAsset;
        } else {
            // 如果未缓存，临时计算
            var tempBullet:Object = { 子弹种类: bulletType };
            setTypeFlags(tempBullet);
            return typeCache[bulletType].baseAsset;
        }
    }

    /**
     * 检查子弹类型是否为纵向子弹。
     * 
     * @param bulletType:String 子弹种类字符串。
     * @return Boolean 如果是纵向子弹返回 true，否则返回 false。
     */
    public static function isVertical(bulletType:String):Boolean {
        var flags:Number = getFlags({ 子弹种类: bulletType });
        return (flags & FLAG_VERTICAL) != 0;
    }

    /**
    * 将子弹类型的标志位转换为可读的字符串，便于调试输出。
    * 
    * @param flags:Number 标志位值。
    * @return String 转换后的字符串，格式如 "MELEE, CHAIN"。若无标志位则返回 "NONE"。
    */
    public static function flagsToString(flags:Number):String {
        var parts:Array = [];
        if (flags & FLAG_MELEE)         parts.push("MELEE");
        if (flags & FLAG_CHAIN)         parts.push("CHAIN");
        if (flags & FLAG_PIERCE)        parts.push("PIERCE");
        if (flags & FLAG_TRANSPARENCY)  parts.push("TRANSPARENCY");
        if (flags & FLAG_GRENADE)       parts.push("GRENADE");
        if (flags & FLAG_EXPLOSIVE)     parts.push("EXPLOSIVE");
        if (flags & FLAG_NORMAL)        parts.push("NORMAL");
        if (flags & FLAG_VERTICAL)      parts.push("VERTICAL");
        return parts.length > 0 ? parts.join(", ") : "NONE";
    }

    /**
     * 清空缓存。
     * 
     * @return Void
     */
    public static function clearCache():Void {
        for (var key:String in typeCache) {
            delete typeCache[key];
        }
    }
}
