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
     * 初始化标志，确保位标志常量正确加载
     */
    private static var initialized:Boolean = init();

    /**
     * 子弹类型位标志定义
     * 每种子弹类型使用一个唯一的二进制位表示。
     */
    private static var FLAG_MELEE:Number;
    private static var FLAG_CHAIN:Number;
    private static var FLAG_PIERCE:Number;
    private static var FLAG_TRANSPARENCY:Number;
    private static var FLAG_GRENADE:Number;
    private static var FLAG_EXPLOSIVE:Number;
    private static var FLAG_NORMAL:Number;
    private static var FLAG_VERTICAL:Number;

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
     * 静态初始化方法 - AS2 宏展开机制性能优化方案
     * 
     * === 宏展开机制说明 ===
     * AS2 的 #include 指令在编译时将外部文件内容直接插入到当前位置，
     * 类似于 C/C++ 的宏预处理机制。这种方式实现零运行时开销的常量引用。
     * 
     * === 性能优化要点 ===
     * 1. 编译时处理：所有 #include 在编译阶段完成，运行时无额外开销
     * 2. 作用域限制：宏展开的变量仅在当前函数作用域有效
     * 3. 一次初始化：静态变量只在类首次加载时初始化一次
     * 4. 内存优化：避免重复的常量定义，减少内存占用
     * 
     * === 最佳实践 ===
     * - 仅在需要时引用特定标志位宏文件
     * - 避免在热点代码路径中重复宏展开
     * - 利用静态初始化确保常量值的一致性
     */
    private static function init():Boolean {
        // 使用宏展开获取各个位标志值（编译时处理，零运行时成本）
        #include "../macros/FLAG_MELEE.as"
        #include "../macros/FLAG_CHAIN.as"
        #include "../macros/FLAG_PIERCE.as"
        #include "../macros/FLAG_TRANSPARENCY.as"
        #include "../macros/FLAG_GRENADE.as"
        #include "../macros/FLAG_EXPLOSIVE.as"
        #include "../macros/FLAG_NORMAL.as"
        #include "../macros/FLAG_VERTICAL.as"
        
        // 将宏展开的临时变量赋值给类的静态变量（一次性操作）
        BulletTypesetter.FLAG_MELEE = FLAG_MELEE;
        BulletTypesetter.FLAG_CHAIN = FLAG_CHAIN;
        BulletTypesetter.FLAG_PIERCE = FLAG_PIERCE;
        BulletTypesetter.FLAG_TRANSPARENCY = FLAG_TRANSPARENCY;
        BulletTypesetter.FLAG_GRENADE = FLAG_GRENADE;
        BulletTypesetter.FLAG_EXPLOSIVE = FLAG_EXPLOSIVE;
        BulletTypesetter.FLAG_NORMAL = FLAG_NORMAL;
        BulletTypesetter.FLAG_VERTICAL = FLAG_VERTICAL;
        
        return true;
    }

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
        // bullet.近战检测 = ((flags & FLAG_MELEE) != 0);
        // bullet.联弹检测 = ((flags & FLAG_CHAIN) != 0);
        // bullet.穿刺检测 = ((flags & FLAG_PIERCE) != 0);
        // bullet.透明检测 = ((flags & FLAG_TRANSPARENCY) != 0);
        // bullet.纵向检测 = ((flags & FLAG_VERTICAL) != 0);
        // bullet.普通检测 = ((flags & FLAG_NORMAL) != 0);
        
        /**
         * === 宏展开 + 位掩码双重性能优化教程 ===
         * 
         * 本项目采用"宏展开 + 位掩码"组合技术，实现极致性能优化，
         * 核心突破：完全绕开AS2运行时的属性索引开销！
         * 
         * === 第一层优化：宏展开机制绕开属性索引 ===
         * 
         * // 宏文件示例（FLAG_MELEE.as）：
         * var FLAG_MELEE:Number = 1 << 0;  // 编译时常量：1
         * var FLAG_CHAIN:Number = 1 << 1;  // 编译时常量：2  
         * var FLAG_PIERCE:Number = 1 << 2; // 编译时常量：4
         * var FLAG_VERTICAL:Number = 1 << 7; // 编译时常量：128
         * 
         * // 传统方式（每次都有属性索引开销）：
         * var melee = MyClass.FLAG_MELEE;     // 运行时查找类属性
         * var chain = MyClass.FLAG_CHAIN;     // 运行时查找类属性
         * 
         * // 宏展开优化（零属性索引开销）：
         * #include "../macros/FLAG_MELEE.as"  // 编译时直接注入: var FLAG_MELEE:Number = 1;
         * #include "../macros/FLAG_CHAIN.as"  // 编译时直接注入: var FLAG_CHAIN:Number = 2;
         * // 现在 FLAG_MELEE, FLAG_CHAIN 是当前作用域的局部常量，无需任何属性查找！
         * 
         * === 第二层优化：位掩码技术压缩存储与计算 ===
         * 
         * // 组合掩码创建（编译时计算）：
         * var PIERCE_AND_VERTICAL_MASK:Number = FLAG_PIERCE | FLAG_VERTICAL; // 4 | 128 = 132
         * 
         * // 高效条件检测（一次位运算替代多次布尔比较）：
         * if ((bullet.flags & PIERCE_AND_VERTICAL_MASK) == PIERCE_AND_VERTICAL_MASK) {
         *     // 同时满足穿刺和纵向条件
         * }
         * 
         * === 性能对比分析 ===
         * 
         * 传统方式的开销：
         * • 属性索引：MyClass.FLAG_XXX 需要哈希表查找
         * • 多次比较：if(a && b && c) 需要3次布尔运算和短路求值
         * • 内存访问：每个布尔属性独立存储和访问
         * 
         * 优化后的优势：
         * • 零索引开销：宏展开直接注入编译时常量
         * • 单次位运算：一个 & 操作替代多个 && 操作
         * • 紧凑存储：8个标志位压缩在1个Number中
         * • CPU缓存友好：减少内存访问次数
         * 
         * === 实际应用示例 ===
         * 
         * // 在需要使用标志的函数中：
         * function checkBulletProperties(bullet:Object):Boolean {
         *     #include "../macros/FLAG_PIERCE.as"      // 注入: var FLAG_PIERCE:Number = 4;
         *     #include "../macros/FLAG_VERTICAL.as"    // 注入: var FLAG_VERTICAL:Number = 128;
         *     
         *     var MASK:Number = FLAG_PIERCE | FLAG_VERTICAL; // 编译时计算为 132
         *     return (bullet.flags & MASK) == MASK;          // 运行时仅一次位运算
         * }
         * 
         * 参考实现：MultiShotDamageHandle.as 第71-88行 和 第130-151行
         */
        

        
        bullet.手雷检测 = bullet.手雷检测 || ((flags & FLAG_GRENADE) != 0);
        bullet.爆炸检测 = bullet.爆炸检测 || ((flags & FLAG_EXPLOSIVE) != 0);
        


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
