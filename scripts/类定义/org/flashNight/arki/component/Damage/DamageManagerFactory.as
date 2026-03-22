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
     * 创建 evaluator 函数——统一 Modulo 37 合并方案。
     *
     * ### 算法原理
     * 利用 37 为素数的性质：对任意 i ∈ {0,...,31}，(2^i) % 37 两两不同。
     * 工厂创建时预合并查找表 hlut[(1<<i)%37] = h[i]，运行时单次 GetMember 直接
     * 拿到 handler 引用，省去 CTZ→索引→h[索引] 的两级查找。
     *
     * **P-code 循环体仅 8 条指令**：
     *   GetVariable "hlut" → Push bitmask,0,bitmask → Subtract → BitAnd
     *   → Push 37 → Modulo → GetMember → (赋值到 handles)
     *
     * ### 修改依据
     * 详见同目录 CTZ优化施工记录.md，基于 4 轮实验。
     *
     * ### 关键优势
     * - **统一实现**：消除 hlen<=8 / hlen<32 / hlen==32 三分支，一个闭包通吃
     * - **bit31 安全**：(-2147483648) % 37 = -22，Object 键自动字符串化，无符号问题
     * - **实测性能**：相比旧方案 8-bit 加速 1.50×，16-bit 加速 1.60×，32-bit 加速 1.62×
     *
     * ### 输入掩码强制要求
     * - **掩码必须非0**：do...while 至少执行一次，bitmask=0 会导致 hlut[0%37]=hlut[0]=undefined
     * - 调用方需确保传入的 bitmask 至少有一个置位
     *
     * @param h 处理器数组（索引对应位掩码位置）
     * @return 优化后的 evaluator 函数
     */
    private function createEvaluator(h:Array):Function {
        var hlen:Number = h.length;
        if (hlen > 32) {
            throw new Error("超过32位支持");
        }

        // 预合并查找表：hlut[(1<<i)%37] = h[i]
        // 单次 GetMember 直接拿到 handler，省去 CTZ→index→h[index] 的两级查找
        //
        // Array(37) 预分配：正数哈希（0-36）走数组索引快路径（~35ns），
        // bit31 的 -22 作为字符串属性存储（Array 继承 Object），同样正确
        //
        // 不提升为静态变量：每个工厂的 handler 实例不同，hlut 内容无法共享；
        // 且仅在构造时创建一次（工厂是单例），一次性 ~550ns 开销可忽略
        var hlut:Array = new Array(37);
        var i:Number;
        for (i = 0; i < hlen; i++) {
            hlut[(1 << i) % 37] = h[i];
        }

        return function(bitmask:Number):DamageManager {
            var handles:Array = [];
            var len:Number = 0;
            do {
                handles[len++] = hlut[(bitmask & (-bitmask)) % 37];
            } while ((bitmask &= (bitmask - 1)) != 0);
            return new DamageManager(handles);
        };
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
        var index:Number;
        var i:Number = 0;
        do {
            if (handles[index = conditionalIndices[i]].canHandle(bullet)) {
                bitmask |= (1 << index);
            }
        } while (++i < len);

        return this._resolve(bitmask);
    }

    public function getDamageManager1(bullet:Object):DamageManager {
        var bitmask:Number = this._skipCheckBitmask;
        var index:Number;

        if (this._handles[index = this._conditionalHandlerIndices[0]].canHandle(bullet))
            bitmask |= (1 << index);

        return this._resolve(bitmask);
    }

    public function getDamageManager2(bullet:Object):DamageManager {
        var bitmask:Number = this._skipCheckBitmask;
        var handles:Array = this._handles;
        var conditionalIndices:Array = this._conditionalHandlerIndices;
        var index:Number;

        if (handles[index = conditionalIndices[0]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[1]].canHandle(bullet))
            bitmask |= (1 << index);

        return this._resolve(bitmask);
    }

    public function getDamageManager3(bullet:Object):DamageManager {
        var bitmask:Number = this._skipCheckBitmask;
        var handles:Array = this._handles;
        var conditionalIndices:Array = this._conditionalHandlerIndices;
        var index:Number;

        if (handles[index = conditionalIndices[0]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[1]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[2]].canHandle(bullet))
            bitmask |= (1 << index);

        return this._resolve(bitmask);
    }

    public function getDamageManager4(bullet:Object):DamageManager {
        var bitmask:Number = this._skipCheckBitmask;
        var handles:Array = this._handles;
        var conditionalIndices:Array = this._conditionalHandlerIndices;
        var index:Number;

        if (handles[index = conditionalIndices[0]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[1]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[2]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[3]].canHandle(bullet))
            bitmask |= (1 << index);

        return this._resolve(bitmask);
    }

    public function getDamageManager5(bullet:Object):DamageManager {
        var bitmask:Number = this._skipCheckBitmask;
        var handles:Array = this._handles;
        var conditionalIndices:Array = this._conditionalHandlerIndices;
        var index:Number;

        if (handles[index = conditionalIndices[0]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[1]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[2]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[3]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[4]].canHandle(bullet))
            bitmask |= (1 << index);

        return this._resolve(bitmask);
    }

    public function getDamageManager6(bullet:Object):DamageManager {
        var bitmask:Number = this._skipCheckBitmask;
        var handles:Array = this._handles;
        var conditionalIndices:Array = this._conditionalHandlerIndices;
        var index:Number;

        if (handles[index = conditionalIndices[0]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[1]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[2]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[3]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[4]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[5]].canHandle(bullet))
            bitmask |= (1 << index);

        return this._resolve(bitmask);
    }

    public function getDamageManager7(bullet:Object):DamageManager {
        var bitmask:Number = this._skipCheckBitmask;
        var handles:Array = this._handles;
        var conditionalIndices:Array = this._conditionalHandlerIndices;
        var index:Number;

        if (handles[index = conditionalIndices[0]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[1]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[2]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[3]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[4]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[5]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[6]].canHandle(bullet))
            bitmask |= (1 << index);

        return this._resolve(bitmask);
    }

    public function getDamageManager8(bullet:Object):DamageManager {
        var bitmask:Number = this._skipCheckBitmask;
        var handles:Array = this._handles;
        var conditionalIndices:Array = this._conditionalHandlerIndices;
        var index:Number;

        if (handles[index = conditionalIndices[0]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[1]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[2]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[3]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[4]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[5]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[6]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[7]].canHandle(bullet))
            bitmask |= (1 << index);

        return this._resolve(bitmask);
    }

    public function getDamageManager9(bullet:Object):DamageManager {
        var bitmask:Number = this._skipCheckBitmask;
        var handles:Array = this._handles;
        var conditionalIndices:Array = this._conditionalHandlerIndices;
        var index:Number;

        if (handles[index = conditionalIndices[0]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[1]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[2]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[3]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[4]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[5]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[6]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[7]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[8]].canHandle(bullet))
            bitmask |= (1 << index);

        return this._resolve(bitmask);
    }

    public function getDamageManager10(bullet:Object):DamageManager {
        var bitmask:Number = this._skipCheckBitmask;
        var handles:Array = this._handles;
        var conditionalIndices:Array = this._conditionalHandlerIndices;
        var index:Number;

        if (handles[index = conditionalIndices[0]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[1]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[2]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[3]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[4]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[5]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[6]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[7]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[8]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[9]].canHandle(bullet))
            bitmask |= (1 << index);

        return this._resolve(bitmask);
    }

    public function getDamageManager11(bullet:Object):DamageManager {
        var bitmask:Number = this._skipCheckBitmask;
        var handles:Array = this._handles;
        var conditionalIndices:Array = this._conditionalHandlerIndices;
        var index:Number;

        if (handles[index = conditionalIndices[0]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[1]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[2]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[3]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[4]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[5]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[6]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[7]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[8]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[9]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[10]].canHandle(bullet))
            bitmask |= (1 << index);

        return this._resolve(bitmask);
    }

    public function getDamageManager12(bullet:Object):DamageManager {
        var bitmask:Number = this._skipCheckBitmask;
        var handles:Array = this._handles;
        var conditionalIndices:Array = this._conditionalHandlerIndices;
        var index:Number;

        if (handles[index = conditionalIndices[0]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[1]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[2]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[3]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[4]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[5]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[6]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[7]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[8]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[9]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[10]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[11]].canHandle(bullet))
            bitmask |= (1 << index);

        return this._resolve(bitmask);
    }

    public function getDamageManager13(bullet:Object):DamageManager {
        var bitmask:Number = this._skipCheckBitmask;
        var handles:Array = this._handles;
        var conditionalIndices:Array = this._conditionalHandlerIndices;
        var index:Number;

        if (handles[index = conditionalIndices[0]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[1]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[2]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[3]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[4]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[5]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[6]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[7]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[8]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[9]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[10]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[11]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[12]].canHandle(bullet))
            bitmask |= (1 << index);

        return this._resolve(bitmask);
    }

    public function getDamageManager14(bullet:Object):DamageManager {
        var bitmask:Number = this._skipCheckBitmask;
        var handles:Array = this._handles;
        var conditionalIndices:Array = this._conditionalHandlerIndices;
        var index:Number;

        if (handles[index = conditionalIndices[0]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[1]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[2]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[3]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[4]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[5]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[6]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[7]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[8]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[9]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[10]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[11]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[12]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[13]].canHandle(bullet))
            bitmask |= (1 << index);

        return this._resolve(bitmask);
    }

    public function getDamageManager15(bullet:Object):DamageManager {
        var bitmask:Number = this._skipCheckBitmask;
        var handles:Array = this._handles;
        var conditionalIndices:Array = this._conditionalHandlerIndices;
        var index:Number;

        if (handles[index = conditionalIndices[0]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[1]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[2]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[3]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[4]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[5]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[6]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[7]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[8]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[9]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[10]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[11]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[12]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[13]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[14]].canHandle(bullet))
            bitmask |= (1 << index);

        return this._resolve(bitmask);
    }

    public function getDamageManager16(bullet:Object):DamageManager {
        var bitmask:Number = this._skipCheckBitmask;
        var handles:Array = this._handles;
        var conditionalIndices:Array = this._conditionalHandlerIndices;
        var index:Number;

        if (handles[index = conditionalIndices[0]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[1]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[2]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[3]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[4]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[5]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[6]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[7]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[8]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[9]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[10]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[11]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[12]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[13]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[14]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[15]].canHandle(bullet))
            bitmask |= (1 << index);

        return this._resolve(bitmask);
    }

    public function getDamageManager17(bullet:Object):DamageManager {
        var bitmask:Number = this._skipCheckBitmask;
        var handles:Array = this._handles;
        var conditionalIndices:Array = this._conditionalHandlerIndices;
        var index:Number;

        if (handles[index = conditionalIndices[0]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[1]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[2]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[3]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[4]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[5]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[6]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[7]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[8]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[9]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[10]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[11]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[12]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[13]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[14]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[15]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[16]].canHandle(bullet))
            bitmask |= (1 << index);

        return this._resolve(bitmask);
    }

    public function getDamageManager18(bullet:Object):DamageManager {
        var bitmask:Number = this._skipCheckBitmask;
        var handles:Array = this._handles;
        var conditionalIndices:Array = this._conditionalHandlerIndices;
        var index:Number;

        if (handles[index = conditionalIndices[0]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[1]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[2]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[3]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[4]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[5]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[6]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[7]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[8]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[9]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[10]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[11]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[12]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[13]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[14]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[15]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[16]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[17]].canHandle(bullet))
            bitmask |= (1 << index);

        return this._resolve(bitmask);
    }

    public function getDamageManager19(bullet:Object):DamageManager {
        var bitmask:Number = this._skipCheckBitmask;
        var handles:Array = this._handles;
        var conditionalIndices:Array = this._conditionalHandlerIndices;
        var index:Number;

        if (handles[index = conditionalIndices[0]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[1]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[2]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[3]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[4]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[5]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[6]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[7]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[8]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[9]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[10]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[11]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[12]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[13]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[14]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[15]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[16]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[17]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[18]].canHandle(bullet))
            bitmask |= (1 << index);

        return this._resolve(bitmask);
    }

    public function getDamageManager20(bullet:Object):DamageManager {
        var bitmask:Number = this._skipCheckBitmask;
        var handles:Array = this._handles;
        var conditionalIndices:Array = this._conditionalHandlerIndices;
        var index:Number;

        if (handles[index = conditionalIndices[0]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[1]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[2]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[3]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[4]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[5]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[6]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[7]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[8]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[9]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[10]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[11]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[12]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[13]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[14]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[15]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[16]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[17]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[18]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[19]].canHandle(bullet))
            bitmask |= (1 << index);

        return this._resolve(bitmask);
    }

    public function getDamageManager21(bullet:Object):DamageManager {
        var bitmask:Number = this._skipCheckBitmask;
        var handles:Array = this._handles;
        var conditionalIndices:Array = this._conditionalHandlerIndices;
        var index:Number;

        if (handles[index = conditionalIndices[0]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[1]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[2]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[3]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[4]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[5]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[6]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[7]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[8]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[9]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[10]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[11]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[12]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[13]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[14]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[15]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[16]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[17]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[18]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[19]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[20]].canHandle(bullet))
            bitmask |= (1 << index);

        return this._resolve(bitmask);
    }

    public function getDamageManager22(bullet:Object):DamageManager {
        var bitmask:Number = this._skipCheckBitmask;
        var handles:Array = this._handles;
        var conditionalIndices:Array = this._conditionalHandlerIndices;
        var index:Number;

        if (handles[index = conditionalIndices[0]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[1]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[2]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[3]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[4]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[5]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[6]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[7]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[8]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[9]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[10]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[11]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[12]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[13]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[14]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[15]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[16]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[17]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[18]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[19]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[20]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[21]].canHandle(bullet))
            bitmask |= (1 << index);

        return this._resolve(bitmask);
    }

    public function getDamageManager23(bullet:Object):DamageManager {
        var bitmask:Number = this._skipCheckBitmask;
        var handles:Array = this._handles;
        var conditionalIndices:Array = this._conditionalHandlerIndices;
        var index:Number;

        if (handles[index = conditionalIndices[0]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[1]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[2]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[3]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[4]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[5]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[6]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[7]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[8]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[9]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[10]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[11]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[12]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[13]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[14]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[15]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[16]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[17]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[18]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[19]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[20]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[21]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[22]].canHandle(bullet))
            bitmask |= (1 << index);

        return this._resolve(bitmask);
    }

    public function getDamageManager24(bullet:Object):DamageManager {
        var bitmask:Number = this._skipCheckBitmask;
        var handles:Array = this._handles;
        var conditionalIndices:Array = this._conditionalHandlerIndices;
        var index:Number;

        if (handles[index = conditionalIndices[0]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[1]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[2]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[3]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[4]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[5]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[6]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[7]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[8]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[9]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[10]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[11]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[12]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[13]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[14]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[15]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[16]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[17]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[18]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[19]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[20]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[21]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[22]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[23]].canHandle(bullet))
            bitmask |= (1 << index);

        return this._resolve(bitmask);
    }

    public function getDamageManager25(bullet:Object):DamageManager {
        var bitmask:Number = this._skipCheckBitmask;
        var handles:Array = this._handles;
        var conditionalIndices:Array = this._conditionalHandlerIndices;
        var index:Number;

        if (handles[index = conditionalIndices[0]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[1]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[2]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[3]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[4]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[5]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[6]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[7]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[8]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[9]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[10]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[11]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[12]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[13]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[14]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[15]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[16]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[17]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[18]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[19]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[20]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[21]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[22]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[23]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[24]].canHandle(bullet))
            bitmask |= (1 << index);

        return this._resolve(bitmask);
    }

    public function getDamageManager26(bullet:Object):DamageManager {
        var bitmask:Number = this._skipCheckBitmask;
        var handles:Array = this._handles;
        var conditionalIndices:Array = this._conditionalHandlerIndices;
        var index:Number;

        if (handles[index = conditionalIndices[0]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[1]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[2]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[3]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[4]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[5]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[6]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[7]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[8]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[9]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[10]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[11]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[12]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[13]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[14]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[15]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[16]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[17]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[18]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[19]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[20]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[21]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[22]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[23]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[24]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[25]].canHandle(bullet))
            bitmask |= (1 << index);

        return this._resolve(bitmask);
    }

    public function getDamageManager27(bullet:Object):DamageManager {
        var bitmask:Number = this._skipCheckBitmask;
        var handles:Array = this._handles;
        var conditionalIndices:Array = this._conditionalHandlerIndices;
        var index:Number;

        if (handles[index = conditionalIndices[0]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[1]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[2]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[3]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[4]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[5]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[6]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[7]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[8]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[9]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[10]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[11]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[12]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[13]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[14]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[15]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[16]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[17]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[18]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[19]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[20]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[21]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[22]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[23]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[24]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[25]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[26]].canHandle(bullet))
            bitmask |= (1 << index);

        return this._resolve(bitmask);
    }

    public function getDamageManager28(bullet:Object):DamageManager {
        var bitmask:Number = this._skipCheckBitmask;
        var handles:Array = this._handles;
        var conditionalIndices:Array = this._conditionalHandlerIndices;
        var index:Number;

        if (handles[index = conditionalIndices[0]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[1]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[2]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[3]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[4]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[5]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[6]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[7]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[8]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[9]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[10]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[11]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[12]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[13]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[14]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[15]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[16]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[17]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[18]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[19]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[20]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[21]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[22]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[23]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[24]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[25]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[26]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[27]].canHandle(bullet))
            bitmask |= (1 << index);

        return this._resolve(bitmask);
    }

    public function getDamageManager29(bullet:Object):DamageManager {
        var bitmask:Number = this._skipCheckBitmask;
        var handles:Array = this._handles;
        var conditionalIndices:Array = this._conditionalHandlerIndices;
        var index:Number;

        if (handles[index = conditionalIndices[0]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[1]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[2]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[3]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[4]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[5]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[6]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[7]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[8]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[9]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[10]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[11]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[12]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[13]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[14]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[15]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[16]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[17]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[18]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[19]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[20]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[21]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[22]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[23]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[24]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[25]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[26]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[27]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[28]].canHandle(bullet))
            bitmask |= (1 << index);

        return this._resolve(bitmask);
    }

    public function getDamageManager30(bullet:Object):DamageManager {
        var bitmask:Number = this._skipCheckBitmask;
        var handles:Array = this._handles;
        var conditionalIndices:Array = this._conditionalHandlerIndices;
        var index:Number;

        if (handles[index = conditionalIndices[0]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[1]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[2]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[3]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[4]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[5]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[6]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[7]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[8]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[9]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[10]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[11]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[12]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[13]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[14]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[15]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[16]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[17]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[18]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[19]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[20]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[21]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[22]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[23]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[24]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[25]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[26]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[27]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[28]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[29]].canHandle(bullet))
            bitmask |= (1 << index);

        return this._resolve(bitmask);
    }

    public function getDamageManager31(bullet:Object):DamageManager {
        var bitmask:Number = this._skipCheckBitmask;
        var handles:Array = this._handles;
        var conditionalIndices:Array = this._conditionalHandlerIndices;
        var index:Number;

        if (handles[index = conditionalIndices[0]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[1]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[2]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[3]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[4]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[5]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[6]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[7]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[8]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[9]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[10]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[11]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[12]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[13]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[14]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[15]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[16]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[17]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[18]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[19]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[20]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[21]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[22]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[23]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[24]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[25]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[26]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[27]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[28]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[29]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[30]].canHandle(bullet))
            bitmask |= (1 << index);

        return this._resolve(bitmask);
    }

    public function getDamageManager32(bullet:Object):DamageManager {
        var bitmask:Number = this._skipCheckBitmask;
        var handles:Array = this._handles;
        var conditionalIndices:Array = this._conditionalHandlerIndices;
        var index:Number;

        if (handles[index = conditionalIndices[0]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[1]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[2]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[3]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[4]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[5]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[6]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[7]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[8]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[9]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[10]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[11]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[12]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[13]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[14]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[15]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[16]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[17]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[18]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[19]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[20]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[21]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[22]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[23]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[24]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[25]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[26]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[27]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[28]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[29]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[30]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[31]].canHandle(bullet))
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
