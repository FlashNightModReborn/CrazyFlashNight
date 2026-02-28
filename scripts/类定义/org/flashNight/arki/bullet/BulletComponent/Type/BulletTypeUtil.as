import org.flashNight.arki.bullet.BulletComponent.Type.BulletTypeData;
import org.flashNight.arki.bullet.BulletComponent.Type.BulletTypesetter;
import org.flashNight.arki.bullet.BulletComponent.Init.BulletInitializer;

/**
 * BulletTypeUtil 子弹类型工具类
 * 
 * 职责：
 * • 提供子弹类型的查询和检测功能
 * • 提供调试和诊断工具
 * • 管理透明子弹类型配置 
 * • 提供各种便捷的工具方法
 * 
 * 设计原则：
 * • 所有方法都是静态的，不需要实例化
 * • 采用宏展开优化，实现最佳性能
 * • 依赖BulletTypesetter进行核心计算
 * • 专注于查询和工具功能，不涉及状态修改
 */
class org.flashNight.arki.bullet.BulletComponent.Type.BulletTypeUtil {

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
     * 构造函数
     * 该类不需要实例化，因此不进行任何初始化。
     */
    public function BulletTypeUtil() {
        // 无需初始化 - 纯工具类
    }

    // ========== 子弹类型检测方法 ==========

    /**
     * 检查子弹类型是否为纵向子弹。
     * 
     * === 宏展开性能优化 ===
     * 使用宏展开机制避免类属性索引开销
     * 
     * @param bulletType:String 子弹种类字符串。
     * @return Boolean 如果是纵向子弹返回 true，否则返回 false。
     */
    public static function isVertical(bulletType:String):Boolean {
        #include "../macros/FLAG_VERTICAL.as"  
        // 注入: var FLAG_VERTICAL:Number = 128;
        
        var flags:Number = BulletTypesetter.getFlags({ 子弹种类: bulletType });
        return (flags & FLAG_VERTICAL) != 0;
    }

    /**
     * 检查子弹类型是否为近战子弹。
     * 
     * === 宏展开性能优化 ===
     * 使用宏展开机制避免类属性索引开销
     * 
     * @param bulletType:String 子弹种类字符串。
     * @return Boolean 如果是近战子弹返回 true，否则返回 false。
     */
    public static function isMelee(bulletType:String):Boolean {
        #include "../macros/FLAG_MELEE.as"  
        // 注入: var FLAG_MELEE:Number = 1;
        
        var flags:Number = BulletTypesetter.getFlags({ 子弹种类: bulletType });
        return (flags & FLAG_MELEE) != 0;
    }

    /**
     * 检查子弹类型是否为联弹子弹。
     * 
     * === 宏展开性能优化 ===
     * 使用宏展开机制避免类属性索引开销
     * 
     * @param bulletType:String 子弹种类字符串。
     * @return Boolean 如果是联弹子弹返回 true，否则返回 false。
     */
    public static function isChain(bulletType:String):Boolean {
        #include "../macros/FLAG_CHAIN.as"  
        // 注入: var FLAG_CHAIN:Number = 2;
        
        var flags:Number = BulletTypesetter.getFlags({ 子弹种类: bulletType });
        return (flags & FLAG_CHAIN) != 0;
    }

    /**
     * 检查子弹类型是否为穿刺子弹。
     * 
     * === 宏展开性能优化 ===
     * 使用宏展开机制避免类属性索引开销
     * 
     * @param bulletType:String 子弹种类字符串。
     * @return Boolean 如果是穿刺子弹返回 true，否则返回 false。
     */
    public static function isPierce(bulletType:String):Boolean {
        #include "../macros/FLAG_PIERCE.as"  
        // 注入: var FLAG_PIERCE:Number = 4;
        
        var flags:Number = BulletTypesetter.getFlags({ 子弹种类: bulletType });
        return (flags & FLAG_PIERCE) != 0;
    }

    /**
     * 检查子弹类型是否为透明子弹。
     * 
     * === 性能优化：直接哈希查找 ===
     * 使用O(1)哈希查找替代O(n)标志位计算，性能更优
     * 
     * @param bulletType:String 子弹种类字符串。
     * @return Boolean 如果是透明子弹返回 true，否则返回 false。
     */
    public static function isTransparency(bulletType:String):Boolean {
        return !!TRANSPARENCY_MAP[bulletType];
    }

    /**
     * 检查子弹类型是否为手雷子弹。
     * 
     * === 宏展开性能优化 ===
     * 使用宏展开机制避免类属性索引开销
     * 
     * @param bulletType:String 子弹种类字符串。
     * @return Boolean 如果是手雷子弹返回 true，否则返回 false。
     */
    public static function isGrenade(bulletType:String):Boolean {
        #include "../macros/FLAG_GRENADE.as"  
        // 注入: var FLAG_GRENADE:Number = 16;
        
        var flags:Number = BulletTypesetter.getFlags({ 子弹种类: bulletType });
        return (flags & FLAG_GRENADE) != 0;
    }

    /**
     * 检查子弹类型是否为爆炸子弹。
     * 
     * === 宏展开性能优化 ===
     * 使用宏展开机制避免类属性索引开销
     * 
     * @param bulletType:String 子弹种类字符串。
     * @return Boolean 如果是爆炸子弹返回 true，否则返回 false。
     */
    public static function isExplosive(bulletType:String):Boolean {
        #include "../macros/FLAG_EXPLOSIVE.as"  
        // 注入: var FLAG_EXPLOSIVE:Number = 32;
        
        var flags:Number = BulletTypesetter.getFlags({ 子弹种类: bulletType });
        return (flags & FLAG_EXPLOSIVE) != 0;
    }

    /**
     * 检查子弹类型是否为普通子弹。
     * 
     * === 宏展开性能优化 ===
     * 使用宏展开机制避免类属性索引开销
     * 
     * @param bulletType:String 子弹种类字符串。
     * @return Boolean 如果是普通子弹返回 true，否则返回 false。
     */
    public static function isNormal(bulletType:String):Boolean {
        #include "../macros/FLAG_NORMAL.as"  
        // 注入: var FLAG_NORMAL:Number = 64;
        
        var flags:Number = BulletTypesetter.getFlags({ 子弹种类: bulletType });
        return (flags & FLAG_NORMAL) != 0;
    }

    /**
     * 检查子弹类型是否为射线子弹。
     *
     * === 数据源说明 ===
     * FLAG_RAY 由 AttributeLoader 根据 XML 中 <rayConfig> 节点存在性设置，
     * 存储在 BulletInitializer.attributeMap 中，而非 BulletTypesetter 的类型标志。
     * 因此本方法通过 BulletInitializer.getAttributeData 查询，而非标志位运算。
     *
     * @param bulletType:String 子弹种类字符串。
     * @return Boolean 如果是射线子弹返回 true，否则返回 false。
     */
    public static function isRay(bulletType:String):Boolean {
        var attr:Object = BulletInitializer.getAttributeData(bulletType);
        return (attr != undefined && attr.rayConfig != undefined);
    }

    // ========== 调试和诊断工具 ==========

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
        return BulletTypesetter.getFlags(bullet);
    }

    /**
     * 将子弹类型的标志位转换为可读的字符串，便于调试输出。
     * 
     * === 宏展开性能优化 ===
     * 使用宏展开机制避免类属性索引开销，提升调试输出性能
     * 
     * @param flags:Number 标志位值。
     * @param useChinese:Boolean 可选参数，是否使用中文输出。默认 false（英文）。
     * @return String 转换后的字符串，格式如 "MELEE, CHAIN" 或 "近战, 联弹"。若无标志位则返回 "NONE" 或 "无"。
     */
    public static function flagsToString(flags:Number, useChinese:Boolean):String {
        // === 宏展开性能优化：编译时常量注入 ===
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

        // 处理默认参数
        if (useChinese == undefined) useChinese = false;
        
        var parts:Array = [];
        
        if (useChinese) {
            // 中文输出 - 现在使用局部栈变量，性能最优
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
            // 英文输出 - 现在使用局部栈变量，性能最优
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

    // ========== 透明子弹类型管理 ==========

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
        BulletTypesetter.clearCache();
        return true;
    }
}