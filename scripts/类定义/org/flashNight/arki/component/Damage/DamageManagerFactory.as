import org.flashNight.arki.component.Damage.*;
import org.flashNight.gesh.func.*;

/**
 * DamageManagerFactory 是用于创建和管理 DamageManager 实例的工厂类。
 * 主要功能包括：
 * - 动态构建 DamageManager，根据子弹属性选择合适的伤害处理器。
 * - 通过位掩码与 ARCEnhancedLazyCache 实现惰性创建和高效缓存。
 * - 支持实例化工厂和静态全局工厂，适配不同的使用场景。
 */
class org.flashNight.arki.component.Damage.DamageManagerFactory {

    // ========== 静态区域（全局工厂管理） ==========

    // 存储具名工厂的映射表（名称 -> 工厂实例）
    private static var _namedFactories:Object = {};

    // 默认的基础工厂，预置了常用的伤害处理器
    public static var Basic:DamageManagerFactory;

    /**
     * 创建一个默认的基础伤害工厂，内置常用处理器。
     * 该工厂包含以下处理器：
     * - CritDamageHandle：暴击处理器
     * - UniversalDamageHandle：通用处理器
     * - DodgeStateDamageHandle：躲闪状态处理器
     * - MultiShotDamageHandle：联弹处理器
     * - NanoToxicDamageHandle：毒素处理器
     * - LifeStealDamageHandle：吸血处理器
     * - CrumbleDamageHandle：击溃处理器
     * - ExecuteDamageHandle：斩杀处理器
     *
     * @return 创建好的 DamageManagerFactory 实例
     * @throws 如果处理器数量超过32个，将抛出异常
     */
    public static function createBasic():DamageManagerFactory {
        var handles:Array = [
            CritDamageHandle.getInstance(),         // 暴击处理器
            UniversalDamageHandle.getInstance(),    // 通用处理器
            DodgeStateDamageHandle.getInstance(),   // 躲闪状态处理器
            MultiShotDamageHandle.getInstance(),    // 联弹处理器
            NanoToxicDamageHandle.getInstance(),    // 毒素处理器
            LifeStealDamageHandle.getInstance(),    // 吸血处理器
            CrumbleDamageHandle.getInstance(),      // 击溃处理器
            ExecuteDamageHandle.getInstance()       // 斩杀处理器
        ];

        if (handles.length > 32) {
            throw "DamageManagerFactory 支持的处理器数量最多为 32 个。";
        }

        var factory:DamageManagerFactory = new DamageManagerFactory(handles, 64);
        registerExistingFactory("Basic", factory);
        return factory;
    }

    /**
     * 初始化默认的基础工厂。
     * 调用此方法后，可以通过 DamageManagerFactory.Basic 访问默认工厂。
     */
    public static function init():Void {
        Basic = createBasic();
    }

    /**
     * 注册一个具名工厂到全局映射中。
     *
     * @param name          工厂名称（唯一标识）
     * @param handles       处理器数组
     * @param cacheCapacity 缓存容量
     * @throws 如果工厂名称已存在或处理器数量超过32个，则抛出异常
     */
    public static function registerFactory(name:String, handles:Array, cacheCapacity:Number):Void {
        if (_namedFactories[name] != undefined) {
            throw "工厂名称 '" + name + "' 已存在，无法重复注册。";
        }

        if (handles.length > 32) {
            throw "DamageManagerFactory 支持的处理器数量最多为 32 个。";
        }

        var factory:DamageManagerFactory = new DamageManagerFactory(handles, cacheCapacity);
        _namedFactories[name] = factory;
    }

    /**
     * 注册一个已构建好的 DamageManagerFactory 实例到全局映射中。
     *
     * @param name    工厂名称（唯一标识）
     * @param factory 已实例化的 DamageManagerFactory 对象
     * @throws 如果工厂名称已存在或 factory 不是 DamageManagerFactory 实例，则抛出异常
     */
    public static function registerExistingFactory(name:String, factory:DamageManagerFactory):Void {
        if (_namedFactories[name] != undefined) {
            throw "工厂名称 '" + name + "' 已存在，无法重复注册。";
        }

        if (factory == null || !(factory instanceof DamageManagerFactory)) {
            throw "提供的 factory 不是有效的 DamageManagerFactory 实例。";
        }

        _namedFactories[name] = factory;
    }

    /**
     * 获取已注册的具名工厂。
     *
     * @param name 工厂名称
     * @return 对应的 DamageManagerFactory 实例
     * @throws 如果工厂未注册，则抛出异常
     */
    public static function getFactory(name:String):DamageManagerFactory {
        var factory:DamageManagerFactory = _namedFactories[name];
        if (factory == undefined) {
            throw "工厂 '" + name + "' 未注册，请先调用 registerFactory 注册。";
        }
        return factory;
    }

    /**
     * 移除已注册的具名工厂。
     *
     * @param name 工厂名称
     * @throws 如果工厂不存在，则抛出异常
     */
    public static function removeFactory(name:String):Void {
        if (_namedFactories[name] == undefined) {
            throw "工厂 '" + name + "' 不存在，无法移除。";
        }
        delete _namedFactories[name];
    }

    /**
     * 清空所有已注册的具名工厂。
     */
    public static function clearAllFactories():Void {
        for (var name:String in _namedFactories) {
            delete _namedFactories[name];
        }
    }

    // ========== 实例区域（工厂实例逻辑） ==========

    // 储存处理器数组，索引即为位掩码的位置
    private var _handles:Array;

    // 用于缓存 DamageManager 的 LazyCache 实例
    private var _managerCache:ARCEnhancedLazyCache;

    // 预计算的 skipCheck 位掩码，用于快速过滤无需条件检查的处理器
    private var _skipCheckBitmask:Number;

    // 仅包含需要进行 canHandle 检查的处理器的索引数组
    private var _conditionalHandlerIndices:Array;

    /**
     * 构造函数。
     * 初始化 DamageManagerFactory 实例。
     *
     * @param handles       处理器数组（顺序影响执行顺序）
     * @param cacheCapacity 缓存容量
     * @throws 如果处理器数组为空或数量超过32个，则抛出异常
     */
    public function DamageManagerFactory(handles:Array, cacheCapacity:Number) {
        if (handles == null || handles.length == 0) {
            throw "创建 DamageManagerFactory 时，处理器数组不能为空。";
        }

        if (handles.length > 32) {
            throw "DamageManagerFactory 支持的处理器数量最多为 32 个。";
        }

        _handles = handles.concat();

        _skipCheckBitmask = 0;
        _conditionalHandlerIndices = [];
        for (var i:Number = 0; i < _handles.length; i++) {
            var handler:BaseDamageHandle = _handles[i];
            if (handler.skipCheck) {
                _skipCheckBitmask |= (1 << i);
            } else {
                _conditionalHandlerIndices.push(i);
            }
        }

        var evaluator:Function = createEvaluator(_handles);

        if (cacheCapacity <= 0) {
            throw "缓存容量必须大于 0。";
        }

        _managerCache = new ARCEnhancedLazyCache(evaluator, cacheCapacity);
    }

    /**
     * 创建 evaluator 函数，根据处理器数量进行优化。
     *
     * Evaluator 函数用于根据位掩码生成对应的 DamageManager 实例。
     * 该方法根据处理器的数量（<=8 或 <=32）选择不同的实现方式，以提高性能。
     *
     * @param h 处理器数组
     * @return 优化后的 evaluator 函数
     */
    private function createEvaluator(h:Array):Function {
        if (h.length <= 8) {
            return function(bitmask:Number):DamageManager {
                var handles:Array = [];
                var temp:Number;
                var len:Number = 0;
                do {
                    if ((temp = (bitmask & -bitmask)) >= 16) {
                        handles[len++] = h[4 + 2 * ((temp >= 64) && (temp >>= 6)) + (temp >= 32)];
                    } else {
                        handles[len++] = h[2 * ((temp >= 4) && (temp >>= 2)) + (temp >= 2)];
                    }
                } while ((bitmask &= (bitmask - 1)) != 0);
                return new DamageManager(handles);
            };
        } else {
            return function(bitmask:Number):DamageManager {
                var handles:Array = [];
                var len:Number = 0;
                do {
                    handles[len++] = h[Math.log(bitmask & -bitmask) * 1.4426950408889634];
                } while ((bitmask &= (bitmask - 1)) != 0);
                return new DamageManager(handles);
            };
        }
    }

    /**
     * 获取 DamageManager（自动缓存）。
     * 根据子弹属性选择合适的处理器，并返回对应的 DamageManager 实例。
     *
     * @param bullet 子弹对象，包含影响伤害处理的属性
     * @return 对应的 DamageManager 实例
     */
    public function getDamageManager(bullet:Object):DamageManager {
        var bitmask:Number = _skipCheckBitmask;
        var handles:Array = _handles;
        var conditionalIndices:Array = _conditionalHandlerIndices;
        var len:Number = conditionalIndices.length;

        var i:Number = 0;
        do {
            var index:Number = conditionalIndices[i];
            if (handles[index].canHandle(bullet)) {
                bitmask |= (1 << index);
            }
        } while (++i < len);

        return DamageManager(_managerCache.get(bitmask));
    }

    /**
     * 重置工厂（支持更新处理器和缓存）。
     *
     * @param newHandles   新的处理器数组（可选）
     * @param newEvaluator 新的评估器函数（可选）
     * @param clearCache   是否清空缓存（默认 true）
     * @throws 如果处理器数量超过32个或 newEvaluator 不是函数，则抛出异常
     */
    public function resetFactory(newHandles:Array, newEvaluator:Function, clearCache:Boolean):Void {
        if (newHandles != null) {
            if (newHandles.length > 32) {
                throw "DamageManagerFactory 支持的处理器数量最多为 32 个。";
            }
            _handles = newHandles.concat();

            _skipCheckBitmask = 0;
            _conditionalHandlerIndices = [];
            for (var i:Number = 0; i < _handles.length; i++) {
                var handler:BaseDamageHandle = _handles[i];
                if (handler.skipCheck) {
                    _skipCheckBitmask |= (1 << i);
                } else {
                    _conditionalHandlerIndices.push(i);
                }
            }

            var newEvaluatorFunc:Function = createEvaluator(_handles);
            _managerCache.reset(newEvaluatorFunc, clearCache);
            return;
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

    /**
     * 返回 DamageManagerFactory 的字符串表示形式，便于调试和日志记录。
     *
     * @return 描述 DamageManagerFactory 的字符串
     */
    public function toString():String {
        var result:String = "[DamageManagerFactory]\n";

        result += "Handles:\n";
        for (var i:Number = 0; i < _handles.length; i++) {
            var handler:BaseDamageHandle = _handles[i];
            result += "  [" + i + "] " + handler.toString() + " (skipCheck: " + handler.skipCheck + ")\n";
        }

        result += "Cache Capacity: " + _managerCache.getCapacity() + "\n";
        result += "SkipCheck Bitmask: " + _skipCheckBitmask.toString(2) + "\n";
        result += "Conditional Handler Indices: " + _conditionalHandlerIndices.join(", ") + "\n";

        return result;
    }
}