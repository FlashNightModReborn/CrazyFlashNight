import org.flashNight.arki.component.Damage.*;
import org.flashNight.gesh.func.*;

/**
 * DamageManagerFactory 是用于创建和管理 DamageManager 实例的工厂类。
 * 
 * <p>主要功能包括：
 * <ul>
 *   <li>动态构建 DamageManager，根据子弹属性选择合适的伤害处理器。</li>
 *   <li>通过位掩码与 ARCEnhancedLazyCache 实现惰性创建和高效缓存。</li>
 *   <li>支持实例化工厂和静态全局工厂，适配不同的使用场景。</li>
 * </ul>
 * </p>
 */
class org.flashNight.arki.component.Damage.DamageManagerFactory {

    // ========== 静态区域（全局工厂管理） ==========

    /** 存储具名工厂的映射表（名称 -> 工厂实例） */
    private static var _namedFactories:Object = {};

    /** 默认的基础工厂，预置了常用的伤害处理器 */
    public static var Basic:DamageManagerFactory;

    /**
     * 创建一个默认的基础伤害工厂，内置常用处理器。
     * 
     * <p>该工厂包含以下处理器：
     * <ul>
     *   <li>CritDamageHandle：暴击处理器</li>
     *   <li>UniversalDamageHandle：通用处理器</li>
     *   <li>DodgeStateDamageHandle：躲闪状态处理器</li>
     *   <li>MultiShotDamageHandle：联弹处理器</li>
     *   <li>NanoToxicDamageHandle：毒素处理器</li>
     *   <li>LifeStealDamageHandle：吸血处理器</li>
     *   <li>CrumbleDamageHandle：击溃处理器</li>
     *   <li>ExecuteDamageHandle：斩杀处理器</li>
     * </ul>
     * </p>
     *
     * @return 创建好的 DamageManagerFactory 实例
     * @throws 如果处理器数量超过32个，将抛出异常
     */
    public static function createBasic():DamageManagerFactory {
        var handles:Array = new Array();

        // 按顺序注册常用的伤害处理器
        handles.push(CritDamageHandle.getInstance()); // 暴击处理器
        handles.push(UniversalDamageHandle.getInstance()); // 通用处理器
        handles.push(DodgeStateDamageHandle.getInstance()); // 躲闪状态处理器
        handles.push(MultiShotDamageHandle.getInstance()); // 联弹处理器
        handles.push(NanoToxicDamageHandle.getInstance()); // 毒素处理器
        handles.push(LifeStealDamageHandle.getInstance()); // 吸血处理器
        handles.push(CrumbleDamageHandle.getInstance()); // 击溃处理器
        handles.push(ExecuteDamageHandle.getInstance()); // 斩杀处理器

        // 检查处理器数量是否超过32个
        if (handles.length > 32) {
            throw "DamageManagerFactory 支持的处理器数量最多为 32 个。";
        }

        // 创建 DamageManagerFactory 实例，缓存容量设为64
        var factory:DamageManagerFactory = new DamageManagerFactory(handles, 64);

        // 注册到全局具名工厂中
        registerExistingFactory("Basic", factory);

        return factory;
    }

    /**
     * 初始化默认的基础工厂。
     * 
     * <p>调用此方法后，可以通过 DamageManagerFactory.Basic 访问默认工厂。</p>
     */
    public static function init():Void {
        // 创建并初始化基础工厂
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

        // 创建新的 DamageManagerFactory 实例
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

    /** 储存处理器数组，索引即为位掩码的位置 */
    private var _handles:Array;

    /** 用于缓存 DamageManager 的 LazyCache 实例 */
    private var _managerCache:ARCEnhancedLazyCache;

    /** 预计算的 skipCheck 位掩码，用于快速过滤无需条件检查的处理器 */
    private var _skipCheckBitmask:Number;

    /** 仅包含需要进行 canHandle 检查的处理器的索引数组 */
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

        // 检查处理器数量是否超过32个
        if (handles.length > 32) {
            throw "DamageManagerFactory 支持的处理器数量最多为 32 个。";
        }

        // 拷贝处理器数组，避免外部修改
        _handles = handles.concat();

        // 预计算 skipCheck 位掩码和需要条件检查的处理器索引
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

        // 根据处理器数量创建不同的 evaluator 以优化性能
        var evaluator:Function;
        var h = this._handles;
        evaluator = createEvaluator(h);

        // 验证 cacheCapacity 合法性
        if (cacheCapacity <= 0) {
            throw "缓存容量必须大于 0。";
        }

        // 初始化缓存
        _managerCache = new ARCEnhancedLazyCache(evaluator, cacheCapacity);
    }

    /**
     * 创建 evaluator 函数，根据处理器数量进行优化。
     *
     * <p>Evaluator 函数用于根据位掩码生成对应的 DamageManager 实例。
     * 该方法根据处理器的数量（<=8 或 <=32）选择不同的实现方式，以提高性能。</p>
     *
     * <h3>数学背景解析：</h3>
     * <p>位掩码用于表示需要激活的处理器。每一位对应一个处理器的启用状态。
     * 通过提取位掩码中的每一个激活位，可以快速定位需要应用的处理器。</p>
     * 
     * <p>对于最多8个处理器的情况，使用预先构建的索引查找表 <code>indexLookup</code>，
     * 通过位运算提取最低有效位并查找对应的处理器索引。</p>
     * 
     * <p>对于最多32个处理器的情况，使用对数运算 <code>Math.log(bm & -bm) * (1 / Math.log(2))</code>
     * 来计算最低有效位的指数。由于 as2 中缺少直接的 log2 函数，采用此方式近似计算 log2。</p>
     * 
     * <p>具体来说：
     * <ul>
     *   <li><code>bm & -bm</code>：提取位掩码中最低的一个激活位。</li>
     *   <li><code>Math.log(bm & -bm)</code>：计算该位的自然对数。</li>
     *   <li><code>1.4426950408889634</code>：这是常数 <code>1 / Math.log(2)</code>，用于将自然对数转换为以2为底的对数。</li>
     *   <li>最终结果为 log2(bm & -bm)，即最低激活位的位置索引。</li>
     * </ul>
     * </p>
     *
     * @param h 处理器数组
     * @return 优化后的 evaluator 函数
     */
    private function createEvaluator(h:Array):Function {
        if (h.length <= 8) {
            // 适用于最多8个处理器的 evaluator
        
            // 位掩码索引查找表，用于快速定位处理器索引 
            // 局部创建通过闭包传递，以降低全局上的内存占用开销
            
            var indexLookup:Object = {};

            // 初始化位掩码索引查找表，用于快速定位处理器索引
            indexLookup[1] = 0;
            indexLookup[2] = 1;
            indexLookup[4] = 2;
            indexLookup[8] = 3;
            indexLookup[16] = 4;
            indexLookup[32] = 5;
            indexLookup[64] = 6;
            indexLookup[128] = 7;

            return function(bitmask:Number):DamageManager {
                var handles:Array = [];
                var bm:Number = bitmask;

                do {
                    // 提取最低有效位并通过查找表获取处理器索引
                    handles[handles.length] = h[indexLookup[bm & -bm]];
                } while ((bm &= (bm - 1)) != 0); // 清除最低有效位

                return new DamageManager(handles);
            }
        }
        else {
            // 适用于最多32个处理器的 evaluator
            return function(bitmask:Number):DamageManager {
                var handles:Array = [];
                var bm:Number = bitmask;
                
                do {
                    // 提取最低有效位并计算其 log2 值以获取处理器索引
                    handles[handles.length] = h[Math.log(bm & -bm) * 1.4426950408889634];
                } while ((bm &= (bm - 1)) != 0); // 清除最低有效位

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
        // 初始化位掩码为预计算的 skipCheck 位掩码，表示无需条件检查的处理器已激活
        var bitmask:Number = _skipCheckBitmask;
        var handles:Array = _handles; // 缓存 handles 数组

        // 仅遍历需要进行 canHandle 检查的处理器
        var conditionalIndices:Array = _conditionalHandlerIndices;
        var len:Number = conditionalIndices.length;

        var i:Number = 0;
        do {
            var index:Number = conditionalIndices[i];

            // 如果处理器能处理该子弹属性，则在位掩码中激活对应位
            if (handles[index].canHandle(bullet)) {
                bitmask |= (1 << index);
            }
        } while (++i < len);

        // 从缓存中获取或创建对应的 DamageManager 实例
        return DamageManager(_managerCache.get(bitmask));
    }

    /**
     * 重置工厂（支持更新处理器和缓存）。
     *
     * <p>此方法允许动态更新工厂的处理器数组和评估器逻辑，并选择是否清空缓存。</p>
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

            // 重新计算 skipCheck 位掩码和条件处理器索引
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

            // 根据新的处理器数量创建新的 evaluator 并重置缓存
            var h:Array = _handles;
            var newEvaluatorFunc:Function = createEvaluator(h);
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
     * <p>输出内容包括处理器列表、缓存容量、skipCheck 位掩码等信息。</p>
     *
     * @return 描述 DamageManagerFactory 的字符串
     */
    public function toString():String {
        var result:String = "[DamageManagerFactory]\n";

        // 输出处理器列表
        result += "Handles:\n";
        for (var i:Number = 0; i < _handles.length; i++) {
            var handler:BaseDamageHandle = _handles[i];
            result += "  [" + i + "] " + handler.toString() + " (skipCheck: " + handler.skipCheck + ")\n";
        }

        // 输出缓存容量
        result += "Cache Capacity: " + _managerCache.getCapacity() + "\n";

        // 输出 skipCheck 位掩码
        result += "SkipCheck Bitmask: " + _skipCheckBitmask.toString(2) + "\n";

        // 输出需要条件检查的处理器索引
        result += "Conditional Handler Indices: " + _conditionalHandlerIndices.join(", ") + "\n";

        return result;
    }
}
