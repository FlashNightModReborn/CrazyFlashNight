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
     * 透明子弹类型哈希表（单一数据源）
     * 遵循DRY原则：关于"哪些子弹是透明的"这一信息只在此处定义
     * 使用Object作为哈希表，O(1)查找性能，利用undefined的falsy特性
     */
    private static var TRANSPARENCY_MAP:Object = {
        近战子弹: true,
        近战联弹: true,
        透明子弹: true
        // 未来新增透明子弹类型时，只需在此对象中添加键值对
    };

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
            // 使用纯函数计算标志位
            var flags:Number = calculateFlags(bullet);
            
            // 使用宏展开+位运算优化联弹检测
            #include "../macros/FLAG_CHAIN.as"
            
            // 对联弹提取基础素材名（取子弹种类中 "-" 分隔符前的部分）
            var baseAsset:String = ((flags & FLAG_CHAIN) != 0) ? 
                bulletType.split("-")[0] : bulletType;

            // 将结果缓存
            typeCache[bulletType] = { flags: flags, baseAsset: baseAsset };
        }

        // 从缓存中读取数据
        var data:Object = typeCache[bulletType];
        var flags:Number = data.flags;
        var baseAsset:String = data.baseAsset;

        
        if(((flags & FLAG_GRENADE) != 0)) {
            delete bullet.FLAG_GRENADE; // 清除外部xml传参引入的冗余标志位
        }

        // 设置子弹检测标志
        // bullet.近战检测 = ((flags & FLAG_MELEE) != 0);
        // bullet.联弹检测 = ((flags & FLAG_CHAIN) != 0);
        // bullet.穿刺检测 = ((flags & FLAG_PIERCE) != 0);
        // bullet.透明检测 = ((flags & FLAG_TRANSPARENCY) != 0);
        // bullet.纵向检测 = ((flags & FLAG_VERTICAL) != 0);
        // bullet.普通检测 = ((flags & FLAG_NORMAL) != 0);
        // bullet.手雷检测 = ((flags & FLAG_GRENADE) != 0);
        // bullet.爆炸检测 = ((flags & FLAG_EXPLOSIVE) != 0);

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
    

        // 缓存基础素材名
        bullet.baseAsset = baseAsset;

        // _root.发布消息(baseAsset + ":" + flagsToString(flags, true));

        // 缓存并且返回标志位
        return bullet.flags = flags;
    }

    /**
     * 纯函数：根据子弹对象计算标志位，不涉及缓存操作
     * 
     * === 宏展开优化说明 ===
     * 本函数采用宏展开机制优化性能，将所有FLAG常量引用替换为编译时直接注入的局部变量，
     * 完全绕开类属性索引的运行时开销。每个#include在编译时直接插入常量定义到当前作用域。
     * 
     * 性能提升要点：
     * • 零属性索引：编译时展开替代运行时查找 BulletTypesetter.FLAG_xxx
     * • CPU缓存友好：所有常量位于连续的栈空间，减少内存跳转
     * • 编译器优化：静态常量利于编译器进行更激进的优化
     * 
     * @param bullet:Object 子弹对象，需包含子弹种类 (子弹种类: String)
     * @return Number 计算后的标志位值，如果子弹或子弹种类未定义，则返回 0
     */
    public static function calculateFlags(bullet:Object):Number {
        if (bullet == undefined || bullet.子弹种类 == undefined) {
            return 0;
        }

        // === 宏展开性能优化：编译时常量注入 ===
        // 以下#include指令在编译时直接将宏文件内容插入到当前作用域
        // 每个宏文件包含形如 "var FLAG_XXX:Number = 位值;" 的定义
        // 编译后这些将成为局部栈变量，访问速度远超类属性索引
        
        #include "../macros/FLAG_MELEE.as"        
        // 注入: var FLAG_MELEE:Number = 1;
        #include "../macros/FLAG_CHAIN.as"        
        // 注入: var FLAG_CHAIN:Number = 2;  
        #include "../macros/FLAG_PIERCE.as"       
        // 注入: var FLAG_PIERCE:Number = 4;
        #include "../macros/FLAG_TRANSPARENCY.as" 
        // 注入: var FLAG_TRANSPARENCY:Number = 8;
        #include "../macros/FLAG_GRENADE.as"      
        // 注入: var FLAG_GRENADE:Number = 16;
        #include "../macros/FLAG_EXPLOSIVE.as"    
        // 注入: var FLAG_EXPLOSIVE:Number = 32;
        #include "../macros/FLAG_NORMAL.as"       
        // 注入: var FLAG_NORMAL:Number = 64;
        #include "../macros/FLAG_VERTICAL.as"     
        // 注入: var FLAG_VERTICAL:Number = 128;

        var bulletType:String = bullet.子弹种类;
        
        // 子弹类型检测（字符串匹配性能已通过indexOf优化）
        var isMelee:Boolean         = (bulletType.indexOf("近战") != -1);
        var isChain:Boolean         = (bulletType.indexOf("联弹") != -1);
        var isPierce:Boolean        = (bulletType.indexOf("穿刺") != -1);
        var isTransparency:Boolean  = !!TRANSPARENCY_MAP[bulletType];
        var isVertical:Boolean      = (bulletType.indexOf("纵向") != -1);
        var isExplosive:Boolean     = (bulletType.indexOf("爆炸") != -1);
        var isGrenade:Boolean       = bullet.FLAG_GRENADE || (bulletType.indexOf("手雷") != -1);

        var isNormal:Boolean = !isPierce && !isExplosive &&
                               (isMelee || isTransparency || (bulletType.indexOf("普通") != -1));

        // === 位运算组合：现在使用局部常量，性能最优 ===
        // 原来：BulletTypesetter.FLAG_MELEE (类属性索引 + 哈希查找)
        // 现在：FLAG_MELEE (局部栈变量直接访问)
        return ((isMelee         ? FLAG_MELEE         : 0)
              | (isChain         ? FLAG_CHAIN         : 0)
              | (isPierce        ? FLAG_PIERCE        : 0)
              | (isTransparency  ? FLAG_TRANSPARENCY  : 0)
              | (isGrenade       ? FLAG_GRENADE       : 0)
              | (isExplosive     ? FLAG_EXPLOSIVE     : 0)
              | (isNormal        ? FLAG_NORMAL        : 0)
              | (isVertical      ? FLAG_VERTICAL      : 0));
    }

    /**
     * 调试用方法：获取子弹的 flags 值，不改变原始子弹对象
     * 
     * 注意：约定大于限制 - 此方法允许对未完全初始化的对象产生误判
     * 仅用于调试和便捷检查，业务逻辑应使用已完全初始化的子弹对象
     * 
     * @param bullet:Object 子弹对象，需包含子弹种类 (子弹种类: String)
     * @return Number 计算后的标志位值，如果子弹或子弹种类未定义，则返回 0
     */
    public static function getFlags(bullet:Object):Number {
        if (bullet == undefined || bullet.子弹种类 == undefined) {
            return 0;
        }
        
        var bulletType:String = bullet.子弹种类;
        var cachedData:Object = typeCache[bulletType];
        
        if (cachedData != undefined) {
            return cachedData.flags;
        }
        
        // 对于未缓存的类型，直接计算（不污染缓存）
        return calculateFlags(bullet);
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
     * 检查子弹类型是否为近战子弹。
     * 
     * @param bulletType:String 子弹种类字符串。
     * @return Boolean 如果是近战子弹返回 true，否则返回 false。
     */
    public static function isMelee(bulletType:String):Boolean {
        var flags:Number = getFlags({ 子弹种类: bulletType });
        return (flags & FLAG_MELEE) != 0;
    }

    /**
     * 检查子弹类型是否为联弹子弹。
     * 
     * @param bulletType:String 子弹种类字符串。
     * @return Boolean 如果是联弹子弹返回 true，否则返回 false。
     */
    public static function isChain(bulletType:String):Boolean {
        var flags:Number = getFlags({ 子弹种类: bulletType });
        return (flags & FLAG_CHAIN) != 0;
    }

    /**
     * 检查子弹类型是否为穿刺子弹。
     * 
     * @param bulletType:String 子弹种类字符串。
     * @return Boolean 如果是穿刺子弹返回 true，否则返回 false。
     */
    public static function isPierce(bulletType:String):Boolean {
        var flags:Number = getFlags({ 子弹种类: bulletType });
        return (flags & FLAG_PIERCE) != 0;
    }

    /**
     * 检查子弹类型是否为透明子弹。
     * 
     * @param bulletType:String 子弹种类字符串。
     * @return Boolean 如果是透明子弹返回 true，否则返回 false。
     */
    public static function isTransparency(bulletType:String):Boolean {
        // 使用O(1)哈希查找替代O(n)标志位计算，性能更优
        return !!TRANSPARENCY_MAP[bulletType];
    }

    /**
     * 检查子弹类型是否为手雷子弹。
     * 
     * @param bulletType:String 子弹种类字符串。
     * @return Boolean 如果是手雷子弹返回 true，否则返回 false。
     */
    public static function isGrenade(bulletType:String):Boolean {
        var flags:Number = getFlags({ 子弹种类: bulletType });
        return (flags & FLAG_GRENADE) != 0;
    }

    /**
     * 检查子弹类型是否为爆炸子弹。
     * 
     * @param bulletType:String 子弹种类字符串。
     * @return Boolean 如果是爆炸子弹返回 true，否则返回 false。
     */
    public static function isExplosive(bulletType:String):Boolean {
        var flags:Number = getFlags({ 子弹种类: bulletType });
        return (flags & FLAG_EXPLOSIVE) != 0;
    }

    /**
     * 检查子弹类型是否为普通子弹。
     * 
     * @param bulletType:String 子弹种类字符串。
     * @return Boolean 如果是普通子弹返回 true，否则返回 false。
     */
    public static function isNormal(bulletType:String):Boolean {
        var flags:Number = getFlags({ 子弹种类: bulletType });
        return (flags & FLAG_NORMAL) != 0;
    }

    /**
    * 将子弹类型的标志位转换为可读的字符串，便于调试输出。
    * 
    * @param flags:Number 标志位值。
    * @param useChinese:Boolean 可选参数，是否使用中文输出。默认 false（英文）。
    * @return String 转换后的字符串，格式如 "MELEE, CHAIN" 或 "近战, 联弹"。若无标志位则返回 "NONE" 或 "无"。
    */
    public static function flagsToString(flags:Number, useChinese:Boolean):String {
        // 处理默认参数
        if (useChinese == undefined) useChinese = false;
        
        var parts:Array = [];
        
        if (useChinese) {
            // 中文输出
            if (flags & FLAG_MELEE)         parts.push("近战");
            if (flags & FLAG_CHAIN)         parts.push("联弹");
            if (flags & FLAG_PIERCE)        parts.push("穿刺");
            if (flags & FLAG_TRANSPARENCY)  parts.push("透明");
            if (flags & FLAG_GRENADE)       parts.push("手雷");
            if (flags & FLAG_EXPLOSIVE)     parts.push("爆炸");
            if (flags & FLAG_NORMAL)        parts.push("普通");
            if (flags & FLAG_VERTICAL)      parts.push("纵向");
            return parts.length > 0 ? parts.join(", ") : "无";
        } else {
            // 英文输出（原有逻辑）
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
    }


    /**
     * 获取所有透明子弹类型列表（只读访问）
     * 
     * @return Array 透明子弹类型数组
     */
    public static function getTransparencyTypes():Array {
        var types:Array = [];
        for (var type:String in TRANSPARENCY_MAP) {
            types.push(type);
        }
        return types;
    }

    /**
     * 动态添加透明子弹类型（运行时扩展，谨慎使用）
     * 
     * @param bulletType:String 要添加的子弹类型
     * @return Boolean 添加成功返回true，已存在返回false
     */
    public static function addTransparencyType(bulletType:String):Boolean {
        if (TRANSPARENCY_MAP[bulletType]) {
            return false; // 已存在
        }
        
        TRANSPARENCY_MAP[bulletType] = true;
        // 清空相关缓存，确保一致性
        clearCache();
        return true;
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
