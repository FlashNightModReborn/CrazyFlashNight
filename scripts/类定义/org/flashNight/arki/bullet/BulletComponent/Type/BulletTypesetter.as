import org.flashNight.gesh.object.ObjectUtil;
import org.flashNight.arki.bullet.BulletComponent.Type.*;

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
     * === 宏展开机制已替代初始化 ===
     * 原有的initialized和init()机制已不再需要。
     * 所有FLAG常量现在通过编译时宏展开直接注入到需要的函数作用域中。
     */

    /**
     * === 宏展开机制已替代静态变量 ===
     * 原有的子弹类型位标志静态变量已被宏展开机制完全替代。
     * 所有FLAG常量现在通过编译时#include指令直接注入到需要的函数作用域中，
     * 实现零运行时开销的常量访问。
     * 
     * 性能提升：
     * • 消除类属性哈希表查找开销
     * • 减少静态变量内存占用
     * • 提升CPU缓存局部性
     * • 便于编译器优化
     */

    /**
     * 缓存对象
     * 键（key）：子弹种类字符串。
     * 值（value）：包含以下属性的对象：
     * - flags：子弹类型的标志位。
     * - baseAsset：基础素材名（子弹种类的前缀部分）。
     */
    private static var typeCache:Object = {};

    /**
     * === 透明子弹管理已搬迁 ===
     * 透明子弹类型管理已搬迁到 BulletTypeUtil 类中。
     * 统一的透明子弹哈希表现在位于 BulletTypeUtil.TRANSPARENCY_MAP。
     */

    /**
     * === 宏展开机制已替代静态初始化 ===
     * 原有的init()函数已不再需要。
     * 所有FLAG常量现在通过编译时#include指令直接注入到需要的函数作用域中，
     * 实现真正的零运行时开销。
     * 
     * 性能优势：
     * • 消除初始化函数调用开销
     * • 消除静态变量赋值开销
     * • 消除类属性索引开销
     * • 减少内存占用和初始化时间
     */

    /**
     * 构造函数
     * 该类不需要实例化，因此不进行任何初始化。
     * 宏展开机制使得所有初始化都在编译时完成。
     */
    public function BulletTypesetter() {
        // 无需初始化 - 宏展开已在编译时完成所有常量定义
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

        
        // === 宏展开优化：手雷标志检测 ===
        #include "../macros/FLAG_GRENADE.as"  
        // 注入: var FLAG_GRENADE:Number = 16;
        
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

        // === 修复:合并标志位而非覆盖 ===
        // 如果 bullet.flags 已存在(可能包含 additionalFlags 如 FLAG_RAY),
        // 则使用位或合并以保留已有标志位
        if (bullet.flags != undefined && bullet.flags != 0) {
            bullet.flags |= flags;  // 合并新标志位
        } else {
            bullet.flags = flags;   // 首次设置
        }

        return bullet.flags;
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
        var isTransparency:Boolean  = BulletTypeUtil.isTransparency(bulletType);
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

    // ========== 已搬迁方法的兼容性重定向 ==========
    // 以下方法已搬迁到 BulletTypeUtil 类中，这里保留重定向以维护向后兼容性

    /**
     * === 已搬迁：重定向到 BulletTypeUtil ===
     * 所有 is 系列查询方法已搬迁到 BulletTypeUtil 类中以减少 BulletTypesetter 的复杂度。
     * 建议直接使用 BulletTypeUtil 中的对应方法以获得最佳性能。
     */
    
    public static function isVertical(bulletType:String):Boolean {
        return BulletTypeUtil.isVertical(bulletType);
    }
    
    public static function isMelee(bulletType:String):Boolean {
        return BulletTypeUtil.isMelee(bulletType);
    }
    
    public static function isChain(bulletType:String):Boolean {
        return BulletTypeUtil.isChain(bulletType);
    }
    
    public static function isPierce(bulletType:String):Boolean {
        return BulletTypeUtil.isPierce(bulletType);
    }
    
    public static function isTransparency(bulletType:String):Boolean {
        return BulletTypeUtil.isTransparency(bulletType);
    }
    
    public static function isGrenade(bulletType:String):Boolean {
        return BulletTypeUtil.isGrenade(bulletType);
    }
    
    public static function isExplosive(bulletType:String):Boolean {
        return BulletTypeUtil.isExplosive(bulletType);
    }
    
    public static function isNormal(bulletType:String):Boolean {
        return BulletTypeUtil.isNormal(bulletType);
    }
    
    public static function flagsToString(flags:Number, useChinese:Boolean):String {
        return BulletTypeUtil.flagsToString(flags, useChinese);
    }
    
    public static function getTransparencyTypes():Array {
        return BulletTypeUtil.getTransparencyTypes();
    }
    
    public static function addTransparencyType(bulletType:String):Boolean {
        return BulletTypeUtil.addTransparencyType(bulletType);
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
