import org.flashNight.arki.component.Damage.*;
import org.flashNight.gesh.func.*;

/**
 * DamageManagerFactory
 *
 * 伤害管理器工厂类：
 * - 支持动态构建 DamageManager，并根据子弹属性选择合适的伤害处理器。
 * - 通过位掩码 + ARCEnhancedLazyCache 实现惰性创建和高效缓存。
 * - 既支持实例化工厂，也支持静态全局工厂，灵活适配不同场景。
 */
class org.flashNight.arki.component.Damage.DamageManagerFactory {

    // ========== 静态区域（全局工厂管理） ==========

    /** 存储具名工厂的映射表（name -> factory） */
    private static var _namedFactories:Object = {};
    /** 默认的基础工厂，预置了常用的伤害处理器 */
    public static var Basic:DamageManagerFactory;

    /**
     * 创建一个默认的基础伤害工厂，内置常用处理器。
     * @return DamageManagerFactory 实例
     */
    public static function createBasic():DamageManagerFactory {
        var handles:Array = new Array();

        // 按顺序注册常用的伤害处理器
        handles.push(CritDamageHandle.instance); // 暴击处理器
        handles.push(TrueDamageHandle.instance); // 真伤处理器
        handles.push(MagicDamageHandle.instance); // 魔法伤害处理器
        handles.push(BasicDamageHandle.instance); // 基础伤害处理器
        handles.push(DodgeStateDamageHandle.instance); // 躲闪状态处理器
        handles.push(MultiShotDamageHandle.instance); // 联弹处理器
        handles.push(NanoToxicDamageHandle.instance); // 毒素处理器
        handles.push(LifeStealDamageHandle.instance); // 吸血处理器
        handles.push(CrumbleDamageHandle.instance); // 击溃处理器
        handles.push(ExecuteDamageHandle.instance); // 斩杀处理器

        // 检查处理器数量是否超过32个
        if (handles.length > 32) {
            throw "DamageManagerFactory 支持的处理器数量最多为 32 个。";
        }

        return new DamageManagerFactory(handles, 64);
    }

    /**
     * 初始化默认的基础工厂。
     */
    public static function init():Void {
        Basic = createBasic();
    }

    /**
     * 注册一个具名工厂到全局映射中
     * @param name          工厂名称（唯一标识）
     * @param handles       处理器数组
     * @param cacheCapacity 缓存容量
     */
    public static function registerFactory(name:String, handles:Array, cacheCapacity:Number):Void {
        if (_namedFactories[name] != undefined) {
            throw "工厂名称 '" + name + "' 已存在，无法重复注册。";
        }

        // 检查处理器数量是否超过32个
        if (handles.length > 32) {
            throw "DamageManagerFactory 支持的处理器数量最多为 32 个。";
        }

        var factory:DamageManagerFactory = new DamageManagerFactory(handles, cacheCapacity);
        _namedFactories[name] = factory;
    }

    /**
     * 获取已注册的具名工厂
     * @param name 工厂名称
     * @return 对应的 DamageManagerFactory 实例
     */
    public static function getFactory(name:String):DamageManagerFactory {
        var factory:DamageManagerFactory = _namedFactories[name];
        if (factory == undefined) {
            throw "工厂 '" + name + "' 未注册，请先调用 registerFactory 注册。";
        }
        return factory;
    }

    /**
     * 移除已注册的具名工厂
     * @param name 工厂名称
     */
    public static function removeFactory(name:String):Void {
        if (_namedFactories[name] == undefined) {
            throw "工厂 '" + name + "' 不存在，无法移除。";
        }
        delete _namedFactories[name];
    }

    /**
     * 清空所有已注册的具名工厂
     */
    public static function clearAllFactories():Void {
        for (var name:String in _namedFactories) {
            delete _namedFactories[name];
        }
    }

    // ========== 实例区域（工厂实例逻辑） ==========

    /** 储存处理器数组，索引即为位掩码的位置 */
    private var _handles:Array;

    /** 用于缓存 DamageManager 的 LazyCache */
    private var _managerCache:ARCEnhancedLazyCache;

    /**
     * 构造函数
     * @param handles       处理器数组（顺序影响执行顺序）
     * @param cacheCapacity 缓存容量
     */
    public function DamageManagerFactory(handles:Array, cacheCapacity:Number) {
        if (handles == null || handles.length == 0) {
            throw "创建 DamageManagerFactory 时，处理器数组不能为空。";
        }

        // 检查处理器数量是否超过32个
        if (handles.length > 32) {
            throw "DamageManagerFactory 支持的处理器数量最多为 32 个。";
        }

        _handles = handles.concat(); // 拷贝一份，避免外部修改

        // 构建缓存 evaluator（按位掩码创建 DamageManager）
        var self:DamageManagerFactory = this;
        var evaluator:Function = function(bitmask:Number):DamageManager {
            return self.createManagerByBitmask(bitmask);
        };

        // 验证 cacheCapacity 合法性
        if (cacheCapacity <= 0) {
            throw "缓存容量必须大于 0。";
        }

        _managerCache = new ARCEnhancedLazyCache(evaluator, cacheCapacity);
    }

    /**
     * 获取 DamageManager（自动缓存）
     * @param bullet 子弹对象
     * @return DamageManager 实例
     */
    public function getDamageManager(bullet:Object):DamageManager {
        if (bullet == null) {
            throw "bullet 不能为空。";
        }
        var bitmask:Number = computeBitmask(bullet);
        return DamageManager(_managerCache.get(bitmask));
    }

    /**
     * 重置工厂（支持更新处理器和缓存）
     * @param newHandles   新的处理器数组（可选）
     * @param newEvaluator 新的评估器逻辑（可选）
     * @param clearCache   是否清空缓存（默认 true）
     */
    public function resetFactory(newHandles:Array, newEvaluator:Function, clearCache:Boolean):Void {
        if (newHandles != null) {
            if (newHandles.length > 32) {
                throw "DamageManagerFactory 支持的处理器数量最多为 32 个。";
            }
            _handles = newHandles.concat();
        }

        if (newEvaluator != null) {
            if (typeof(newEvaluator) != "function") {
                throw "newEvaluator 必须是一个函数。";
            }
            _managerCache.reset(newEvaluator, clearCache);
        } else if (clearCache) {
            _managerCache.reset(null, true);
        }
    }

    // ========== 私有方法 ==========

    /**
     * 计算位掩码（根据 bullet 属性决定激活的处理器）
     * 使用 while 循环避免多次访问 _handles.length 并提升性能。
     * @param bullet 子弹对象
     * @return 位掩码（每一位表示是否激活对应处理器）
     */
    private function computeBitmask(bullet:Object):Number {
        var bitmask:Number = 0;
        var i:Number = 0;
        var handles:Array = _handles;          // 缓存引用
        var len:Number = handles.length;       // 缓存长度
        var handler:Object;                    
    
        while (i < len) {
            handler = handles[i];
            if (handler.canHandle(bullet)) {
                bitmask |= (1 << i);
            }
            i++;
        }
    
        return bitmask;
    }


    /**
     * 根据位掩码构建 DamageManager（按需加载）
     * 使用 while 循环避免多次访问 _handles.length 并提升性能。
     * @param bitmask 位掩码
     * @return DamageManager 实例
     */
    private function createManagerByBitmask(bitmask:Number):DamageManager {
        var handles:Array = [];
        var handlers:Array = _handles;         // 缓存引用
        var i:Number = 0;

        while (bitmask != 0) {
            if (bitmask & 1) {                   // 检查最低位是否为1
                handles.push(handlers[i]);       // 添加对应处理器
            }
            bitmask >>= 1;                       // 右移一位处理下一个bit
            i++;
        }

        return new DamageManager(handles);
    }

}
