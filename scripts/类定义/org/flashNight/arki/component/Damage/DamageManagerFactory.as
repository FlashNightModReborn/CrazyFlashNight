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

        return new DamageManagerFactory(handles, 64);
    }

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
            throw new Error("工厂名称 '" + name + "' 已存在，无法重复注册。");
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
            throw new Error("工厂 '" + name + "' 未注册，请先调用 registerFactory 注册。");
        }
        return factory;
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
            throw new Error("创建 DamageManagerFactory 时，处理器数组不能为空。");
        }
        _handles = handles.concat(); // 拷贝一份，避免外部修改

        // 构建缓存 evaluator（按位掩码创建 DamageManager）
        var self:DamageManagerFactory = this;
        var evaluator:Function = function(bitmask:Number):DamageManager {
            return self.createManagerByBitmask(bitmask);
        };

        _managerCache = new ARCEnhancedLazyCache(evaluator, cacheCapacity);
    }

    /**
     * 获取 DamageManager（自动缓存）
     * @param bullet 子弹对象
     * @return DamageManager 实例
     */
    public function getDamageManager(bullet:Object):DamageManager {
        if (bullet == null) {
            throw new Error("bullet 不能为空。");
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
            _handles = newHandles.concat();
        }
        _managerCache.reset(newEvaluator, clearCache);
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
        var len:Number = _handles.length; // 缓存长度
        while (i < len) {
            var handle:IDamageHandle = IDamageHandle(_handles[i]);
            if (handle.canHandle(bullet)) {
                bitmask |= (1 << i); // 设置第 i 位
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
        var manager:DamageManager = new DamageManager();
        var i:Number = 0;
        var len:Number = _handles.length; // 缓存长度

        while (i < len) {
            if (((bitmask >> i) & 1) == 1) {
                manager.addHandle(_handles[i]);
            }
            i++;
        }

        return manager;
    }
}
