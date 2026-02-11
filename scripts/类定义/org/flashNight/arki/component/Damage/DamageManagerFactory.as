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
        var handles:Array = [CritDamageHandle.getInstance(), // 暴击处理器
            UniversalDamageHandle.getInstance(), // 通用处理器
            DodgeStateDamageHandle.getInstance(), // 躲闪状态处理器
            MultiShotDamageHandle.getInstance(), // 联弹处理器
            NanoToxicDamageHandle.getInstance(), // 毒素处理器
            LifeStealDamageHandle.getInstance(), // 吸血处理器
            CrumbleDamageHandle.getInstance(), // 击溃处理器
            ExecuteDamageHandle.getInstance() // 斩杀处理器
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

    // 用于缓存 DamageManager 的 LazyCache 实例（ARC 策略时非 null）
    private var _managerCache:ARCEnhancedLazyCache;

    // 直接数组缓存（直接策略时非 null，索引 = bitmask）
    private var _directCache:Array;

    // evaluator 函数引用（直接策略时使用，允许 resetFactory 更新而无需重建闭包）
    private var _evaluator:Function;

    // 统一的 bitmask → DamageManager 解析入口（闭包，构造时绑定策略）
    public var _resolve:Function;

    // 预计算的 skipCheck 位掩码，用于快速过滤无需条件检查的处理器
    private var _skipCheckBitmask:Number;

    // 仅包含需要进行 canHandle 检查的处理器的索引数组
    private var _conditionalHandlerIndices:Array;

    /** 条件处理器数量阈值：≤ 此值使用直接数组策略，> 此值使用 ARC 策略 */
    private static var DIRECT_THRESHOLD:Number = 12;

    /**
     * 构造函数。
     * 初始化 DamageManagerFactory 实例。
     *
     * 缓存策略自动选择：
     * - 条件处理器数量 ≤ DIRECT_THRESHOLD（12）：直接数组索引，O(1) 零开销
     *   键空间 = 2^conditionalCount，最大 2^12 = 4096 个槽位
     * - 条件处理器数量 > DIRECT_THRESHOLD：ARC 自适应替换缓存
     *   适用于键空间过大不宜全量缓存的场景
     *
     * @param handles       处理器数组（顺序影响执行顺序）
     * @param cacheCapacity 缓存容量（ARC 策略时使用；直接策略时忽略）
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

        var len:Number = _handles.length;

        for (var i:Number = 0; i < len; i++) {
            var handler:BaseDamageHandle = _handles[i];
            if (handler.skipCheck) {
                _skipCheckBitmask |= (1 << i);
            } else {
                _conditionalHandlerIndices.push(i);
            }
        }

        // ==== 新增检查：确保至少有一个处理器无需条件检查 ====
        if (_skipCheckBitmask == 0) {
            throw "至少需要一个处理器标记为 skipCheck = true。";
        }

        var evaluator:Function = createEvaluator(_handles);
        this.getDamageManager = this["getDamageManager" + len];

        // ---- 缓存策略选择 ----
        if (_conditionalHandlerIndices.length <= DIRECT_THRESHOLD) {
            // 直接数组策略：键空间 ≤ 2^12 = 4096，可全量缓存
            _setupDirectResolve(evaluator, null);
            _managerCache = null;
        } else {
            // ARC 策略：键空间过大，使用自适应替换缓存
            if (cacheCapacity <= 0) {
                throw "缓存容量必须大于 0。";
            }
            _directCache = null;
            _evaluator = null;
            var arc:ARCEnhancedLazyCache = new ARCEnhancedLazyCache(evaluator, cacheCapacity);
            _managerCache = arc;
            this._resolve = function(bitmask:Number):DamageManager {
                return DamageManager(arc.get(bitmask));
            };
        }
    }

    /**
     * 设置直接数组解析策略。
     *
     * 闭包直接捕获 dc（数组引用），命中路径零间接层。
     * evaluator 通过 self._evaluator 间接读取，允许 resetFactory 更新
     * evaluator 而无需重建闭包。
     *
     * @param evaluator     bitmask → DamageManager 的计算函数
     * @param existingCache 可复用的已有缓存数组（null 则新建）
     */
    private function _setupDirectResolve(evaluator:Function, existingCache:Array):Void {
        var dc:Array = (existingCache != null) ? existingCache : [];
        var self:DamageManagerFactory = this;
        this._directCache = dc;
        this._evaluator = evaluator;
        this._resolve = function(bitmask:Number):DamageManager {
            var mgr:DamageManager = dc[bitmask];
            if (mgr != undefined) return mgr;
            mgr = self._evaluator(bitmask);
            dc[bitmask] = mgr;
            return mgr;
        };
    }

    /**
     * 创建 evaluator 函数，根据处理器数量进行优化。
     *
     * Evaluator 函数用于根据位掩码生成对应的 DamageManager 实例。
     * 该方法根据处理器的数量（<=8 或 <=32）选择不同的实现方式，以提高性能。
     *
     * ### 数理原理解析
     * 1. **位掩码到处理器的映射逻辑**:
     *    - 位掩码 `bitmask` 的每个置位（set bit）对应一个处理器。
     *    - 通过遍历所有置位（从最低有效位到最高），提取对应处理器索引。
     *
     * 2. **分支优化策略**:
     *    - **当处理器数量 ≤8 时**：使用位掩码分段和条件位移优化索引计算。
     *      - `temp = bitmask & -bitmask`：提取最低有效位（LSB）的值（如 `0b1000` → 8）。
     *      - 通过比较 LSB 的值分段处理（高位段 ≥16 和低位段 <16）：
     *        - **高位段**（16/32/64）: 映射到数组后4个位置，通过位移压缩索引范围。
     *          - `(temp >= 64) && (temp >>=6)`：若 ≥64 则右移6位（等价于除以64），否则保持原值。
     *          - 计算结果为 `4 + 2 * (是否≥64) + (是否≥32)`，将 64→4, 32→5, 16→6, 8→7。
     *        - **低位段**（1/2/4/8）: 映射到数组前4个位置。
     *          - 类似逻辑：`2 * (是否≥4) + (是否≥2)`，将 4→2, 2→3, 1→0（由 `temp >=2` 为 false）。
     *    - **当处理器数量 >8 时**：使用对数计算位索引。
     *      - `Math.log(bitmask & -bitmask) * 1.4426950408889634`：
     *        - `bitmask & -bitmask` 提取最低有效位值（如 8 → 0b1000）。
     *        - `Math.log(x)` 计算自然对数，乘以 `1/ln(2)`（≈1.442695）转换为以2为底的对数。
     *        - 结果等价于 `log2(x)`，直接得到位的索引（如 8 → log2(8)=3 → 索引3）。
     *
     * ### 输入掩码强制要求
     * - **掩码必须非0**：由于 `do...while` 循环至少执行一次，若 `bitmask=0`：
     *   - 首次循环 `temp = 0`，索引计算会越界或访问 `h[NaN]`，导致运行时错误。
     * - 调用方需确保传入的 `bitmask` 至少有一个置位（即非0）。
     *
     * @param h 处理器数组（索引对应位掩码位置）
     * @return 优化后的 evaluator 函数
     */
    private function createEvaluator(h:Array):Function {
        var hlen:Number = h.length;
        if (hlen <= 8) {
            return function(bitmask:Number):DamageManager {
                var handles:Array = [];
                var temp:Number;
                var len:Number = 0;
                do {
                    handles[len++] = h[6 - (((!((temp = bitmask & -bitmask) >= 16 && (temp >>= 4)) << 1) + !(temp >= 4 && (temp >>= 2))) << 1) + (temp >= 2)];

                } while ((bitmask &= (bitmask - 1)) != 0); // 清除最低有效位，继续循环
                return new DamageManager(handles);
            };
        } else if (hlen < 32) {
            return function(bitmask:Number):DamageManager {
                var handles:Array = [];
                var len:Number = 0;
                do {
                    // 通过 log2(LSB) 计算位索引（如 8 → log2(8)=3 → 索引3）
                    handles[len++] = h[(Math.log(bitmask & -bitmask) * 1.4426950408889634 + 0.5) | 0];
                } while ((bitmask &= (bitmask - 1)) != 0); // 清除最低有效位，继续循环
                return new DamageManager(handles);
            };
        } else if (hlen == 32) { 
            return function(bitmask:Number):DamageManager {
                var handles:Array = [];
                var len:Number = 0;
                var index:Number = 0;

                // 遍历每一位，从最低位（0）到第31位
                while (bitmask != 0 && index < 32) {
                    if ((bitmask & 1) != 0) {
                        handles[len++] = h[index];
                    }
                    bitmask = bitmask >>> 1; // 无符号右移，避免符号位扩展
                    index++;
                }

                return new DamageManager(handles);
            };
        } else {
            throw new Error("超过32位支持");
        }
    }

    /**
     * 获取 DamageManager（自动缓存）。
     * 根据子弹属性选择合适的处理器，并返回对应的 DamageManager 实例。
     * 占位使用，实际使用会替换成特化版
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

        return this._resolve(bitmask);
    }

    public function getDamageManager1(bullet:Object):DamageManager {
        var bitmask:Number = this._skipCheckBitmask;
        var index:Number;

        index = this._conditionalHandlerIndices[0];
        if (this._handles[index].canHandle(bullet))
            bitmask |= (1 << index);

        return this._resolve(bitmask);
    }

    public function getDamageManager2(bullet:Object):DamageManager {
        var bitmask:Number = this._skipCheckBitmask;
        var handles:Array = this._handles;
        var conditionalIndices:Array = this._conditionalHandlerIndices;
        var index:Number;

        index = conditionalIndices[0];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[1];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);

        return this._resolve(bitmask);
    }

    public function getDamageManager3(bullet:Object):DamageManager {
        var bitmask:Number = this._skipCheckBitmask;
        var handles:Array = this._handles;
        var conditionalIndices:Array = this._conditionalHandlerIndices;
        var index:Number;

        index = conditionalIndices[0];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[1];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[2];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);

        return this._resolve(bitmask);
    }

    public function getDamageManager4(bullet:Object):DamageManager {
        var bitmask:Number = this._skipCheckBitmask;
        var handles:Array = this._handles;
        var conditionalIndices:Array = this._conditionalHandlerIndices;
        var index:Number;

        index = conditionalIndices[0];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[1];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[2];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[3];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);

        return this._resolve(bitmask);
    }

    public function getDamageManager5(bullet:Object):DamageManager {
        var bitmask:Number = this._skipCheckBitmask;
        var handles:Array = this._handles;
        var conditionalIndices:Array = this._conditionalHandlerIndices;
        var index:Number;

        index = conditionalIndices[0];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[1];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[2];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[3];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[4];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);

        return this._resolve(bitmask);
    }

    public function getDamageManager6(bullet:Object):DamageManager {
        var bitmask:Number = this._skipCheckBitmask;
        var handles:Array = this._handles;
        var conditionalIndices:Array = this._conditionalHandlerIndices;
        var index:Number;

        index = conditionalIndices[0];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[1];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[2];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[3];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[4];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[5];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);

        return this._resolve(bitmask);
    }

    public function getDamageManager7(bullet:Object):DamageManager {
        var bitmask:Number = this._skipCheckBitmask;
        var handles:Array = this._handles;
        var conditionalIndices:Array = this._conditionalHandlerIndices;
        var index:Number;

        index = conditionalIndices[0];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[1];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[2];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[3];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[4];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[5];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[6];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);

        return this._resolve(bitmask);
    }

    public function getDamageManager8(bullet:Object):DamageManager {
        var bitmask:Number = this._skipCheckBitmask;
        var handles:Array = this._handles;
        var conditionalIndices:Array = this._conditionalHandlerIndices;
        var index:Number;

        index = conditionalIndices[0];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[1];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[2];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[3];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[4];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[5];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[6];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[7];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);

        return this._resolve(bitmask);
    }

    public function getDamageManager9(bullet:Object):DamageManager {
        var bitmask:Number = this._skipCheckBitmask;
        var handles:Array = this._handles;
        var conditionalIndices:Array = this._conditionalHandlerIndices;
        var index:Number;

        index = conditionalIndices[0];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[1];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[2];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[3];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[4];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[5];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[6];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[7];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[8];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);

        return this._resolve(bitmask);
    }

    public function getDamageManager10(bullet:Object):DamageManager {
        var bitmask:Number = this._skipCheckBitmask;
        var handles:Array = this._handles;
        var conditionalIndices:Array = this._conditionalHandlerIndices;
        var index:Number;

        index = conditionalIndices[0];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[1];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[2];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[3];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[4];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[5];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[6];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[7];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[8];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[9];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);

        return this._resolve(bitmask);
    }

    public function getDamageManager11(bullet:Object):DamageManager {
        var bitmask:Number = this._skipCheckBitmask;
        var handles:Array = this._handles;
        var conditionalIndices:Array = this._conditionalHandlerIndices;
        var index:Number;

        index = conditionalIndices[0];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[1];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[2];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[3];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[4];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[5];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[6];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[7];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[8];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[9];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[10];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);

        return this._resolve(bitmask);
    }

    public function getDamageManager12(bullet:Object):DamageManager {
        var bitmask:Number = this._skipCheckBitmask;
        var handles:Array = this._handles;
        var conditionalIndices:Array = this._conditionalHandlerIndices;
        var index:Number;

        index = conditionalIndices[0];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[1];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[2];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[3];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[4];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[5];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[6];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[7];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[8];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[9];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[10];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[11];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);

        return this._resolve(bitmask);
    }

    public function getDamageManager13(bullet:Object):DamageManager {
        var bitmask:Number = this._skipCheckBitmask;
        var handles:Array = this._handles;
        var conditionalIndices:Array = this._conditionalHandlerIndices;
        var index:Number;

        index = conditionalIndices[0];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[1];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[2];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[3];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[4];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[5];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[6];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[7];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[8];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[9];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[10];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[11];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[12];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);

        return this._resolve(bitmask);
    }

    public function getDamageManager14(bullet:Object):DamageManager {
        var bitmask:Number = this._skipCheckBitmask;
        var handles:Array = this._handles;
        var conditionalIndices:Array = this._conditionalHandlerIndices;
        var index:Number;

        index = conditionalIndices[0];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[1];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[2];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[3];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[4];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[5];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[6];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[7];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[8];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[9];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[10];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[11];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[12];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[13];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);

        return this._resolve(bitmask);
    }

    public function getDamageManager15(bullet:Object):DamageManager {
        var bitmask:Number = this._skipCheckBitmask;
        var handles:Array = this._handles;
        var conditionalIndices:Array = this._conditionalHandlerIndices;
        var index:Number;

        index = conditionalIndices[0];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[1];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[2];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[3];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[4];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[5];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[6];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[7];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[8];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[9];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[10];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[11];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[12];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[13];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[14];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);

        return this._resolve(bitmask);
    }

    public function getDamageManager16(bullet:Object):DamageManager {
        var bitmask:Number = this._skipCheckBitmask;
        var handles:Array = this._handles;
        var conditionalIndices:Array = this._conditionalHandlerIndices;
        var index:Number;

        index = conditionalIndices[0];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[1];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[2];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[3];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[4];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[5];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[6];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[7];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[8];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[9];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[10];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[11];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[12];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[13];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[14];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[15];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);

        return this._resolve(bitmask);
    }

    public function getDamageManager17(bullet:Object):DamageManager {
        var bitmask:Number = this._skipCheckBitmask;
        var handles:Array = this._handles;
        var conditionalIndices:Array = this._conditionalHandlerIndices;
        var index:Number;

        index = conditionalIndices[0];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[1];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[2];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[3];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[4];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[5];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[6];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[7];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[8];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[9];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[10];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[11];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[12];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[13];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[14];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[15];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[16];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);

        return this._resolve(bitmask);
    }

    public function getDamageManager18(bullet:Object):DamageManager {
        var bitmask:Number = this._skipCheckBitmask;
        var handles:Array = this._handles;
        var conditionalIndices:Array = this._conditionalHandlerIndices;
        var index:Number;

        index = conditionalIndices[0];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[1];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[2];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[3];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[4];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[5];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[6];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[7];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[8];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[9];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[10];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[11];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[12];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[13];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[14];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[15];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[16];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[17];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);

        return this._resolve(bitmask);
    }

    public function getDamageManager19(bullet:Object):DamageManager {
        var bitmask:Number = this._skipCheckBitmask;
        var handles:Array = this._handles;
        var conditionalIndices:Array = this._conditionalHandlerIndices;
        var index:Number;

        index = conditionalIndices[0];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[1];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[2];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[3];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[4];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[5];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[6];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[7];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[8];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[9];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[10];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[11];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[12];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[13];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[14];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[15];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[16];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[17];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[18];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);

        return this._resolve(bitmask);
    }

    public function getDamageManager20(bullet:Object):DamageManager {
        var bitmask:Number = this._skipCheckBitmask;
        var handles:Array = this._handles;
        var conditionalIndices:Array = this._conditionalHandlerIndices;
        var index:Number;

        index = conditionalIndices[0];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[1];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[2];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[3];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[4];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[5];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[6];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[7];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[8];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[9];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[10];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[11];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[12];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[13];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[14];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[15];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[16];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[17];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[18];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[19];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);

        return this._resolve(bitmask);
    }

    public function getDamageManager21(bullet:Object):DamageManager {
        var bitmask:Number = this._skipCheckBitmask;
        var handles:Array = this._handles;
        var conditionalIndices:Array = this._conditionalHandlerIndices;
        var index:Number;

        index = conditionalIndices[0];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[1];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[2];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[3];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[4];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[5];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[6];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[7];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[8];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[9];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[10];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[11];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[12];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[13];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[14];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[15];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[16];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[17];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[18];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[19];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[20];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);

        return this._resolve(bitmask);
    }

    public function getDamageManager22(bullet:Object):DamageManager {
        var bitmask:Number = this._skipCheckBitmask;
        var handles:Array = this._handles;
        var conditionalIndices:Array = this._conditionalHandlerIndices;
        var index:Number;

        index = conditionalIndices[0];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[1];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[2];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[3];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[4];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[5];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[6];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[7];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[8];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[9];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[10];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[11];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[12];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[13];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[14];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[15];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[16];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[17];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[18];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[19];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[20];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[21];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);

        return this._resolve(bitmask);
    }

    public function getDamageManager23(bullet:Object):DamageManager {
        var bitmask:Number = this._skipCheckBitmask;
        var handles:Array = this._handles;
        var conditionalIndices:Array = this._conditionalHandlerIndices;
        var index:Number;

        index = conditionalIndices[0];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[1];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[2];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[3];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[4];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[5];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[6];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[7];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[8];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[9];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[10];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[11];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[12];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[13];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[14];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[15];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[16];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[17];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[18];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[19];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[20];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[21];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[22];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);

        return this._resolve(bitmask);
    }

    public function getDamageManager24(bullet:Object):DamageManager {
        var bitmask:Number = this._skipCheckBitmask;
        var handles:Array = this._handles;
        var conditionalIndices:Array = this._conditionalHandlerIndices;
        var index:Number;

        index = conditionalIndices[0];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[1];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[2];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[3];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[4];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[5];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[6];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[7];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[8];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[9];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[10];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[11];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[12];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[13];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[14];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[15];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[16];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[17];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[18];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[19];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[20];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[21];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[22];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[23];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);

        return this._resolve(bitmask);
    }

    public function getDamageManager25(bullet:Object):DamageManager {
        var bitmask:Number = this._skipCheckBitmask;
        var handles:Array = this._handles;
        var conditionalIndices:Array = this._conditionalHandlerIndices;
        var index:Number;

        index = conditionalIndices[0];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[1];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[2];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[3];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[4];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[5];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[6];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[7];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[8];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[9];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[10];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[11];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[12];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[13];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[14];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[15];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[16];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[17];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[18];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[19];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[20];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[21];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[22];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[23];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[24];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);

        return this._resolve(bitmask);
    }

    public function getDamageManager26(bullet:Object):DamageManager {
        var bitmask:Number = this._skipCheckBitmask;
        var handles:Array = this._handles;
        var conditionalIndices:Array = this._conditionalHandlerIndices;
        var index:Number;

        index = conditionalIndices[0];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[1];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[2];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[3];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[4];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[5];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[6];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[7];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[8];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[9];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[10];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[11];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[12];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[13];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[14];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[15];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[16];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[17];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[18];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[19];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[20];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[21];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[22];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[23];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[24];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[25];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);

        return this._resolve(bitmask);
    }

    public function getDamageManager27(bullet:Object):DamageManager {
        var bitmask:Number = this._skipCheckBitmask;
        var handles:Array = this._handles;
        var conditionalIndices:Array = this._conditionalHandlerIndices;
        var index:Number;

        index = conditionalIndices[0];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[1];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[2];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[3];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[4];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[5];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[6];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[7];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[8];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[9];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[10];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[11];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[12];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[13];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[14];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[15];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[16];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[17];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[18];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[19];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[20];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[21];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[22];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[23];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[24];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[25];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[26];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);

        return this._resolve(bitmask);
    }

    public function getDamageManager28(bullet:Object):DamageManager {
        var bitmask:Number = this._skipCheckBitmask;
        var handles:Array = this._handles;
        var conditionalIndices:Array = this._conditionalHandlerIndices;
        var index:Number;

        index = conditionalIndices[0];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[1];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[2];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[3];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[4];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[5];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[6];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[7];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[8];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[9];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[10];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[11];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[12];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[13];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[14];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[15];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[16];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[17];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[18];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[19];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[20];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[21];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[22];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[23];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[24];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[25];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[26];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[27];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);

        return this._resolve(bitmask);
    }

    public function getDamageManager29(bullet:Object):DamageManager {
        var bitmask:Number = this._skipCheckBitmask;
        var handles:Array = this._handles;
        var conditionalIndices:Array = this._conditionalHandlerIndices;
        var index:Number;

        index = conditionalIndices[0];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[1];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[2];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[3];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[4];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[5];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[6];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[7];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[8];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[9];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[10];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[11];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[12];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[13];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[14];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[15];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[16];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[17];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[18];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[19];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[20];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[21];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[22];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[23];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[24];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[25];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[26];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[27];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[28];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);

        return this._resolve(bitmask);
    }

    public function getDamageManager30(bullet:Object):DamageManager {
        var bitmask:Number = this._skipCheckBitmask;
        var handles:Array = this._handles;
        var conditionalIndices:Array = this._conditionalHandlerIndices;
        var index:Number;

        index = conditionalIndices[0];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[1];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[2];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[3];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[4];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[5];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[6];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[7];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[8];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[9];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[10];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[11];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[12];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[13];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[14];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[15];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[16];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[17];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[18];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[19];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[20];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[21];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[22];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[23];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[24];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[25];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[26];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[27];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[28];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[29];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);

        return this._resolve(bitmask);
    }

    public function getDamageManager31(bullet:Object):DamageManager {
        var bitmask:Number = this._skipCheckBitmask;
        var handles:Array = this._handles;
        var conditionalIndices:Array = this._conditionalHandlerIndices;
        var index:Number;

        index = conditionalIndices[0];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[1];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[2];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[3];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[4];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[5];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[6];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[7];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[8];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[9];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[10];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[11];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[12];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[13];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[14];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[15];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[16];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[17];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[18];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[19];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[20];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[21];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[22];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[23];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[24];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[25];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[26];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[27];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[28];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[29];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[30];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);

        return this._resolve(bitmask);
    }

    public function getDamageManager32(bullet:Object):DamageManager {
        var bitmask:Number = this._skipCheckBitmask;
        var handles:Array = this._handles;
        var conditionalIndices:Array = this._conditionalHandlerIndices;
        var index:Number;

        index = conditionalIndices[0];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[1];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[2];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[3];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[4];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[5];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[6];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[7];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[8];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[9];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[10];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[11];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[12];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[13];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[14];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[15];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[16];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[17];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[18];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[19];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[20];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[21];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[22];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[23];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[24];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[25];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[26];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[27];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[28];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[29];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[30];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);
        index = conditionalIndices[31];
        if (handles[index].canHandle(bullet))
            bitmask |= (1 << index);

        return this._resolve(bitmask);
    }




    /**
     * 重置工厂（支持更新处理器和缓存）。
     *
     * 当提供 newHandles 时，会重新计算 skipCheck 掩码和条件索引，
     * 并根据新的条件处理器数量重新选择缓存策略（直接/ARC）。
     *
     * @param newHandles   新的处理器数组（可选）
     * @param newEvaluator 新的评估器函数（可选，仅在 newHandles 为 null 时生效）
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

            // 根据新的条件处理器数量重新选择策略
            if (_conditionalHandlerIndices.length <= DIRECT_THRESHOLD) {
                // 直接策略：清空 ARC，设置直接解析
                _managerCache = null;
                _setupDirectResolve(newEvaluatorFunc, (clearCache !== false) ? null : _directCache);
            } else {
                // ARC 策略
                _directCache = null;
                _evaluator = null;
                if (_managerCache != null) {
                    _managerCache.reset(newEvaluatorFunc, clearCache);
                } else {
                    var arc:ARCEnhancedLazyCache = new ARCEnhancedLazyCache(newEvaluatorFunc, 64);
                    _managerCache = arc;
                    this._resolve = function(bitmask:Number):DamageManager {
                        return DamageManager(arc.get(bitmask));
                    };
                }
            }
            return;
        }

        // 仅更新 evaluator 或清空缓存（不改变处理器组合）
        if (newEvaluator != null) {
            if (typeof(newEvaluator) != "function") {
                throw "newEvaluator 必须是一个函数。";
            }
            if (_directCache != null) {
                // 直接策略：更新 evaluator 引用（闭包通过 self._evaluator 间接读取）
                _evaluator = newEvaluator;
                if (clearCache !== false) {
                    _directCache.length = 0;
                }
            } else {
                _managerCache.reset(newEvaluator, clearCache);
            }
        } else if (clearCache !== false) {
            if (_directCache != null) {
                _directCache.length = 0;
            } else {
                _managerCache.reset(null, true);
            }
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

        if (_directCache != null) {
            result += "Cache Strategy: DirectArray (keySpace: " + (1 << _conditionalHandlerIndices.length) + ")\n";
        } else {
            result += "Cache Strategy: ARC (capacity: " + _managerCache.getCapacity() + ")\n";
        }
        result += "SkipCheck Bitmask: " + _skipCheckBitmask.toString(2) + "\n";
        result += "Conditional Handler Indices: " + _conditionalHandlerIndices.join(", ") + "\n";

        return result;
    }
}
