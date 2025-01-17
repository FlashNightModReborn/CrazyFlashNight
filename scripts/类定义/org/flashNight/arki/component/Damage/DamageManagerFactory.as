import org.flashNight.arki.component.Damage.*;
import org.flashNight.gesh.func.*;

/**
 * DamageManagerFactory 是伤害管理器的工厂类。
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
     * @return DamageManagerFactory 实例
     */
    public static function createBasic():DamageManagerFactory {
        var handles:Array = new Array();

        // 按顺序注册常用的伤害处理器
        handles.push(CritDamageHandle.instance); // 暴击处理器
        handles.push(UniversalDamageHandle.instance); // 通用处理器
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

        // 检查处理器数量是否超过32个
        if (handles.length > 32) {
            throw "DamageManagerFactory 支持的处理器数量最多为 32 个。";
        }

        var factory:DamageManagerFactory = new DamageManagerFactory(handles, cacheCapacity);
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

    /** 储存处理器数组，索引即为位掩码的位置 */
    private var _handles:Array;

    /** 用于缓存 DamageManager 的 LazyCache */
    private var _managerCache:ARCEnhancedLazyCache;

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

        // 检查处理器数量是否超过32个
        if (handles.length > 32) {
            throw "DamageManagerFactory 支持的处理器数量最多为 32 个。";
        }

        _handles = handles.concat(); // 拷贝一份，避免外部修改

        // 根据处理器数量创建不同的 evaluator 以优化性能
        var evaluator:Function;
        var h = this._handles;
        var handlerCount:Number = _handles.length;

        if (handlerCount <= 8) {
            // 适用于最多8个处理器的 evaluator
            evaluator = function(bitmask:Number):DamageManager {
                var handles:Array = [];
                var bm:Number = bitmask;

                do {
                    var index:Number = 0;
                    var temp:Number = bm & -bm;  // 提取最低位的 1

                    // 快速位移法计算最低位 1 的索引，最多8位
                    
                    if (temp >= 16) { 
                        temp >>= 4; 
                        index += 4;  
                    }
                    if (temp >= 4) { 
                        temp >>= 2; 
                        index += 2;  
                    }
                    if (temp >= 2) { 
                        index += 1; 
                    }

                    // 将对应的处理器加入 handles 数组
                    handles[handles.length] = h[index];
                } while ((bm &= (bm - 1)) != 0);

                return new DamageManager(handles);
            };
        }
        else if (handlerCount <= 16) {
            // 适用于最多16个处理器的 evaluator
            evaluator = function(bitmask:Number):DamageManager {
                var handles:Array = [];
                var bm:Number = bitmask;

                do {
                    var index:Number = 0;
                    var temp:Number = bm & -bm;  // 提取最低位的 1

                    // 快速位移法计算最低位 1 的索引，最多16位
                    if (temp >= 256) { 
                        temp >>= 8; 
                        index += 8;  
                    }
                    if (temp >= 16) { 
                        temp >>= 4; 
                        index += 4;  
                    }
                    if (temp >= 4) { 
                        temp >>= 2; 
                        index += 2;  
                    }
                    if (temp >= 2) { 
                        index += 1; 
                    }

                    // 将对应的处理器加入 handles 数组
                    handles[handles.length] = h[index];
                } while ((bm &= (bm - 1)) != 0);

                return new DamageManager(handles);
            };
        }
        else {
            // 适用于最多32个处理器的 evaluator
            evaluator = function(bitmask:Number):DamageManager {
                var handles:Array = [];
                var bm:Number = bitmask;

                do {
                    var index:Number = 0;
                    var temp:Number = bm & -bm;  // 提取最低位的 1

                    // 快速位移法计算最低位 1 的索引，最多32位
                    if (temp >= 65536) { 
                        temp >>= 16; 
                        index += 16; 
                    }
                    if (temp >= 256) { 
                        temp >>= 8;  
                        index += 8;  
                    }
                    if (temp >= 16) { 
                        temp >>= 4;  
                        index += 4;  
                    }
                    if (temp >= 4) { 
                        temp >>= 2;  
                        index += 2;  
                    }
                    if (temp >= 2) { 
                        index += 1; 
                    }

                    // 将对应的处理器加入 handles 数组
                    handles[handles.length] = h[index];
                } while ((bm &= (bm - 1)) != 0);

                return new DamageManager(handles);
            };
        }

        // 验证 cacheCapacity 合法性
        if (cacheCapacity <= 0) {
            throw "缓存容量必须大于 0。";
        }

        _managerCache = new ARCEnhancedLazyCache(evaluator, cacheCapacity);
    }

    /**
     * 获取 DamageManager（自动缓存）。
     * 根据子弹属性选择合适的处理器，并返回对应的 DamageManager 实例。
     *
     * @param bullet 子弹对象
     * @return DamageManager 实例
     */
    public function getDamageManager(bullet:Object):DamageManager {
        var bitmask:Number = 0;
        var i:Number = 0;
        var handles:Array = _handles;  // 缓存引用
        var len:Number = handles.length;

        var h:BaseDamageHandle;
        do {
            h = handles[i];

            if (h.skipCheck) {
                bitmask |= (1 << i);
            } else if (h.canHandle(bullet)) {
                bitmask |= (1 << i);
            }
        } while (++i < len);  // 将 i++ 放入条件中，减少一次指令

        return DamageManager(_managerCache.get(bitmask));
    }

    /**
     * 重置工厂（支持更新处理器和缓存）。
     *
     * @param newHandles   新的处理器数组（可选）
     * @param newEvaluator 新的评估器逻辑（可选）
     * @param clearCache   是否清空缓存（默认 true）
     * @throws 如果处理器数量超过32个或 newEvaluator 不是函数，则抛出异常
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
}
