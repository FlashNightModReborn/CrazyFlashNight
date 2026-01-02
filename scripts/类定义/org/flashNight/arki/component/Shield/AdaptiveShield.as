// File: org/flashNight/arki/component/Shield/AdaptiveShield.as
 
import org.flashNight.arki.component.Shield.*;

/**
 * AdaptiveShield - 自适应护盾
 *
 * ============================================================
 * 【设计目标】
 * ============================================================
 * 三模式自适应护盾系统，针对游戏业务需求优化：
 * - 空壳模式（MODE_DORMANT）：初始状态，不参与逻辑，等待护盾推入
 * - 单盾模式（MODE_SINGLE）：等同 Shield 的调用成本与逻辑
 * - 栈模式（MODE_STACK）：等同 ShieldStack 的调用成本与逻辑
 *
 * 结构切换仅在"加/减层"发生，战斗热路径无分支判断。
 *
 * ============================================================
 * 【业务场景：持久挂载】
 * ============================================================
 * 推荐用法：为每个单位挂载一个空壳护盾，生命周期与单位绑定。
 *
 *   var unit.shield = AdaptiveShield.createDormant("单位护盾");
 *   // 初始：空壳模式，不参与任何逻辑
 *
 *   unit.shield.addShield(Shield.createTemporary(100, 50, 300, "技能护盾"));
 *   // 自动升级到栈模式，开始工作
 *
 *   // 护盾耗尽后自动降级回空壳模式，等待新护盾推入
 *   // unit.shield 始终存在，无需重新创建
 *
 * ============================================================
 * 【核心机制：实例级方法替换】
 * ============================================================
 * 采用 AS2 实例级方法覆盖实现零代理开销：
 * - 直接将 this.absorbDamage/update/getCapacity/... 替换为当前模式实现
 * - 外部调用 shield.absorbDamage() 直接进入对应实现，无中间层
 * - 性能与原生 Shield/ShieldStack 完全一致
 *
 * 切换时机：
 * - addShield() 从空壳升级到单盾模式（单护盾最优热路径）或栈模式（ShieldStack）
 * - addShield() 从单盾升级到栈模式
 * - update() 后层数降为 1：降级到单盾模式（带迟滞）
 * - update() 后层数降为 0：降级到空壳模式（保持激活，等待新护盾）
 * - 单盾模式碎盾/过期：降级到空壳模式（保持激活）
 *
 * ============================================================
 * 【空壳模式特性】
 * ============================================================
 * - 所有方法都是最简实现，零逻辑开销
 * - absorbDamage() 直接返回 damage（全穿透）
 * - update() 直接返回 false（无变化）
 * - getCapacity/getStrength 返回 0
 * - isEmpty() 返回 true
 * - isActive() 返回 true（保持激活以接收新护盾）
 *
 * ============================================================
 * 【外部契约】
 * ============================================================
 * 实现 IShield 接口（兼容现有系统）
 * 额外提供 addShield/removeShield/getShields/getShieldCount/clear
 * （与 ShieldStack 同名同语义，方便表达叠层）
 *
 * ============================================================
 * 【层对象引用约束】
 * ============================================================
 * 外部不应长期缓存层对象引用（getShields 返回的数组元素）。
 * 层对象生命周期由 AdaptiveShield 管理，降级时可能被回收。
 * 若需稳定访问，使用 getShieldById(id)。
 *
 * ============================================================
 * 【方法引用警告】
 * ============================================================
 * 由于采用实例级方法替换机制，外部代码不应缓存方法引用。
 * 错误用法：var fn:Function = shield.absorbDamage; fn(100);
 *           模式切换后 fn 仍指向旧实现，导致行为不一致。
 * 正确用法：始终通过实例调用 shield.absorbDamage(100)。
 *
 * ============================================================
 * 【降级类型限制】
 * ============================================================
 * 仅当栈中最后一层为 Shield 或 BaseShield 时才允许降级到单盾模式。
 * 若最后一层为其他 IShield 实现（如嵌套 ShieldStack），则保持栈模式不降级。
 * 所有护盾耗尽时，无论类型，都降级到空壳模式。
 *
 * ============================================================
 * 【与现有实现的一致性保证】
 * ============================================================
 * - SingleMode：数值语义等价 Shield（容器级回调以容器为参数）
 * - StackMode：数值/分摊语义等价 ShieldStack，并额外提供容器级回调派发与回调重入安全
 */
class org.flashNight.arki.component.Shield.AdaptiveShield implements IShield {

    // ==================== 模式常量 ====================

    /** 空壳模式（初始状态，不参与逻辑） */
    private static var MODE_DORMANT:Number = 0;

    /** 单盾模式 */
    private static var MODE_SINGLE:Number = 1;

    /** 栈模式 */
    private static var MODE_STACK:Number = 2;

    /** 降级迟滞帧数（连续保持单层多少帧才降级） */
    private static var DOWNGRADE_HYSTERESIS:Number = 30;

    // ==================== 结构操作常量（回调重入安全） ====================

    private static var STRUCT_OP_ADD:Number = 1;
    private static var STRUCT_OP_REMOVE:Number = 2;
    private static var STRUCT_OP_REMOVE_BY_ID:Number = 3;
    private static var STRUCT_OP_CLEAR:Number = 4;

    // ==================== 当前模式 ====================

    /** 当前模式：MODE_DORMANT / MODE_SINGLE / MODE_STACK */
    private var _mode:Number;

    /** 降级迟滞计数器 */
    private var _downgradeCounter:Number;

    // ==================== 单盾模式字段（等价 Shield） ====================

    /** 当前护盾容量 */
    private var _capacity:Number;

    /** 护盾最大容量 */
    private var _maxCapacity:Number;

    /** 护盾目标容量(填充恢复到此值) */
    private var _targetCapacity:Number;

    /** 护盾强度(每次攻击最多吸收此值的伤害) */
    private var _strength:Number;

    /** 护盾填充速度(每帧恢复量，正数充能，负数衰减) */
    private var _rechargeRate:Number;

    /** 填充延迟时间(受击后需等待的帧数) */
    private var _rechargeDelay:Number;

    /** 当前延迟计时器 */
    private var _delayTimer:Number;

    /** 是否处于填充延迟中 */
    private var _isDelayed:Boolean;

    /** 护盾是否激活 */
    private var _isActive:Boolean;

    /** 是否抵抗绕过(如抗真伤) */
    private var _resistBypass:Boolean;

    /** 护盾唯一标识(用于稳定排序) */
    private var _id:Number;

    /** 护盾名称 */
    private var _name:String;

    /** 护盾类型标签 */
    private var _type:String;

    /** 是否为临时盾 */
    private var _isTemporary:Boolean;

    /** 剩余持续时间 */
    private var _duration:Number;

    /** 单盾模式下保留的原始护盾引用（用于委托调用，保留自定义逻辑/回调） */
    private var _singleShield:IShield;

    /** 单盾模式是否使用扁平化（true=扁平化高性能，false=委托保留自定义逻辑） */
    private var _singleFlattened:Boolean;

    // ==================== 栈模式字段（等价 ShieldStack） ====================

    /** 护盾数组(栈模式使用) */
    private var _shields:Array;

    /** 是否需要重新排序 */
    private var _needsSort:Boolean;

    /** 缓存的表观强度 */
    private var _cachedStrength:Number;

    /** 抵抗绕过的护盾计数 */
    private var _resistantCount:Number;

    /** 缓存的当前总容量 */
    private var _cachedCapacity:Number;

    /** 缓存的最大总容量 */
    private var _cachedMaxCapacity:Number;

    /** 缓存的目标总容量 */
    private var _cachedTargetCapacity:Number;

    /** 缓存是否有效 */
    private var _cacheValid:Boolean;

    // ==================== 回调重入安全：结构修改排队 ====================

    /** 结构锁深度（>0 时 add/remove/clear 将排队，避免迭代期间数组被改写） */
    private var _structureLockDepth:Number;

    /** 排队的结构操作列表 */
    private var _pendingStructureOps:Array;

    // ==================== 立场抗性派生字段 ====================

    /** 上次同步时的模式 */
    private var _lastSyncedMode:Number;

    /** 上次同步时的强度 */
    private var _lastSyncedStrength:Number;

    /** 上次同步时的基础抗性 */
    private var _lastSyncedBaseResist:Number;

    // ==================== 共享字段 ====================

    /** 所属单位引用 */
    private var _owner:Object;

    // 注：ID 分配已迁移至 ShieldIdAllocator，此处不再维护 _idCounter

    // ==================== 事件回调 ====================

    /** 被命中时的回调函数 function(shield:IShield, absorbed:Number):Void */
    public var onHitCallback:Function;

    /** 护盾击碎时的回调函数 function(shield:IShield):Void */
    public var onBreakCallback:Function;

    /** 开始充能时的回调函数 function(shield:IShield):Void */
    public var onRechargeStartCallback:Function;

    /** 充能完毕时的回调函数 function(shield:IShield):Void */
    public var onRechargeFullCallback:Function;

    /** 过期事件回调 function(shield:IShield):Void */
    public var onExpireCallback:Function;

    /**
     * 护盾被弹出时的回调（单盾模式+栈模式通用）
     * function(ejected:IShield, container:AdaptiveShield):Void
     *
     * 【触发时机】
     * - 单盾模式：临时盾过期/击碎时触发，ejected 为被移除护盾的快照
     * - 栈模式：任意护盾从栈中移除时触发
     *
     * 【回调安全性】
     * 回调触发时容器结构已稳定（单盾模式会先降级到空壳；栈模式会先完成截断/排队操作），
     * 可安全调用 addShield/removeShield/clear 等修改结构的方法。
     */
    public var onShieldEjectedCallback:Function;

    /**
     * 所有护盾耗尽时的回调（单盾模式+栈模式通用）
     * function(container:AdaptiveShield):Void
     *
     * 【触发时机】
     * - 单盾模式：护盾失活后立即触发
     * - 栈模式：最后一个护盾被移除后触发
     *
     * 【回调安全性】
     * 回调触发时容器已降级到空壳模式，可安全调用 addShield() 补充新护盾
     */
    public var onAllShieldsDepletedCallback:Function;

    // ==================== 构造函数 ====================

    /**
     * 构造函数。
     *
     * 【默认行为】
     * 无参数调用时进入空壳模式（MODE_DORMANT），不参与任何逻辑运作，
     * 等待外部通过 addShield() 推入护盾后才开始工作。
     *
     * 【兼容模式】
     * 传入有效参数时进入单盾模式（MODE_SINGLE），行为与原有逻辑一致。
     *
     * @param maxCapacity 最大容量（undefined时进入空壳模式）
     * @param strength 护盾强度
     * @param rechargeRate 填充速度(默认0)
     * @param rechargeDelay 填充延迟帧数(默认0)
     * @param name 护盾名称(默认"AdaptiveShield")
     * @param type 护盾类型(默认"adaptive")
     */
    public function AdaptiveShield(
        maxCapacity:Number,
        strength:Number,
        rechargeRate:Number,
        rechargeDelay:Number,
        name:String,
        type:String
    ) {
        // 判断是否进入空壳模式：所有核心参数都未定义时
        var dormant:Boolean = (maxCapacity == undefined && strength == undefined);

        // 容器级别的字段初始化
        this._id = ShieldIdAllocator.nextId();
        this._owner = null;
        this._isActive = true;
        this._resistBypass = false;
        this._name = (name == undefined || name == null) ? "AdaptiveShield" : name;
        this._type = (type == undefined || type == null) ? (dormant ? "dormant" : "adaptive") : type;
        this._isTemporary = false;
        this._duration = -1;

        // 初始化旧字段（用于兼容性，空壳模式下返回0）
        this._maxCapacity = 0;
        this._capacity = 0;
        this._targetCapacity = 0;
        this._strength = 0;
        this._rechargeRate = 0;
        this._rechargeDelay = 0;
        this._delayTimer = 0;
        this._isDelayed = false;

        // 初始化栈模式字段
        this._shields = null;
        this._needsSort = false;
        this._cachedStrength = 0;
        this._resistantCount = 0;
        this._cachedCapacity = 0;
        this._cachedMaxCapacity = 0;
        this._cachedTargetCapacity = 0;
        this._cacheValid = false;

        // 初始化结构修改锁
        this._structureLockDepth = 0;
        this._pendingStructureOps = null;

        // 初始化立场抗性同步缓存
        this._lastSyncedMode = -1;  // 强制首次同步
        this._lastSyncedStrength = 0;
        this._lastSyncedBaseResist = 0;

        // 初始化回调为null
        this.onHitCallback = null;
        this.onBreakCallback = null;
        this.onRechargeStartCallback = null;
        this.onRechargeFullCallback = null;
        this.onExpireCallback = null;
        this.onShieldEjectedCallback = null;
        this.onAllShieldsDepletedCallback = null;

        // 根据参数决定初始模式
        this._downgradeCounter = 0;
        this._singleFlattened = false;
        if (dormant) {
            this._mode = MODE_DORMANT;
            this._singleShield = null;
            this._bindDormantMethods();
        } else {
            // 非空壳模式：使用扁平化单盾模式（高性能）
            var actualMaxCap:Number = isNaN(maxCapacity) ? 100 : maxCapacity;
            var actualStrength:Number = isNaN(strength) ? 50 : strength;
            var actualRate:Number = (rechargeRate == undefined || isNaN(rechargeRate)) ? 0 : rechargeRate;
            var actualDelay:Number = (rechargeDelay == undefined || isNaN(rechargeDelay)) ? 0 : rechargeDelay;

            // 直接复制属性到容器字段（扁平化）
            this._maxCapacity = actualMaxCap;
            this._capacity = actualMaxCap;
            this._targetCapacity = actualMaxCap;
            this._strength = actualStrength;
            this._rechargeRate = actualRate;
            this._rechargeDelay = actualDelay;
            this._delayTimer = 0;
            this._isDelayed = false;

            this._singleShield = null;
            this._singleFlattened = true;
            this._mode = MODE_SINGLE;
            this._bindSingleFlattenedMethods();
        }
    }

    // ==================== 工厂方法 ====================

    /**
     * 创建一个空壳护盾（推荐用于单位挂载）。
     *
     * 【使用场景】
     * 为每个单位创建一个持久存在的护盾容器，初始状态不参与逻辑运作，
     * 等待外部通过 addShield() 推入具体护盾后才开始工作。
     *
     * 【生命周期】
     * 空壳 → addShield() → 栈模式 → 护盾耗尽 → 回到空壳 → 等待新护盾
     *
     * @param name 护盾名称(默认"DormantShield")
     * @return AdaptiveShield 空壳护盾实例
     */
    public static function createDormant(name:String):AdaptiveShield {
        var shield:AdaptiveShield = new AdaptiveShield();
        if (name != undefined && name != null) {
            shield._name = name;
        } else {
            shield._name = "DormantShield";
        }
        return shield;
    }

    /**
     * 创建一个临时护盾。
     */
    public static function createTemporary(
        maxCapacity:Number,
        strength:Number,
        duration:Number,
        name:String
    ):AdaptiveShield {
        var shield:AdaptiveShield = new AdaptiveShield(maxCapacity, strength, 0, 0, name, "temporary");
        // 设置临时属性（扁平化模式下直接设置字段）
        shield._isTemporary = true;
        var dur:Number = (duration == undefined || isNaN(duration)) ? -1 : duration;
        shield._duration = dur;
        return shield;
    }

    /**
     * 创建一个可回充护盾。
     */
    public static function createRechargeable(
        maxCapacity:Number,
        strength:Number,
        rechargeRate:Number,
        rechargeDelay:Number,
        name:String
    ):AdaptiveShield {
        var shield:AdaptiveShield = new AdaptiveShield(maxCapacity, strength, rechargeRate, rechargeDelay, name, "rechargeable");
        // 内部护盾默认不是临时的，无需额外设置
        return shield;
    }

    /**
     * 创建一个衰减护盾。
     */
    public static function createDecaying(
        maxCapacity:Number,
        strength:Number,
        decayRate:Number,
        name:String
    ):AdaptiveShield {
        var rate:Number = decayRate;
        if (rate > 0) rate = -rate;
        var shield:AdaptiveShield = new AdaptiveShield(maxCapacity, strength, rate, 0, name, "decaying");
        // 设置临时属性（扁平化模式下直接设置字段）
        shield._isTemporary = true;
        return shield;
    }

    /**
     * 创建一个可抗真伤的护盾。
     */
    public static function createResistant(
        maxCapacity:Number,
        strength:Number,
        duration:Number,
        name:String
    ):AdaptiveShield {
        var shield:AdaptiveShield = new AdaptiveShield(maxCapacity, strength, 0, 0, name, "resistant");
        // 设置属性（扁平化模式下直接设置字段）
        shield._isTemporary = true;
        var dur:Number = (duration == undefined || isNaN(duration)) ? -1 : duration;
        shield._duration = dur;
        shield._resistBypass = true;
        return shield;
    }

    // ==================== 实例级方法绑定（核心） ====================

    /**
     * 绑定空壳模式方法到实例。
     * 空壳模式下所有操作都是最简实现，零逻辑开销。
     *
     * 【统一清理】
     * 进入空壳模式时统一清理 _singleShield 和 _shields 引用，
     * 避免在各处（击碎/过期/clear/removeById）重复清理造成遗漏。
     */

    /**
     * 创建扁平化单盾的元数据快照（用于回调参数）。
     *
     * 【用途】
     * 扁平化模式下，降级后容器状态变为空壳，无法再读取原护盾属性。
     * 此方法在降级前创建 ShieldSnapshot 对象，供 onShieldEjectedCallback 使用。
     *
     * 【ID 语义】
     * - layerId：优先使用内部护盾的 ID（如果存在），用于追溯原始护盾
     * - containerId：始终使用容器的 ID
     * 这样回调接收方可通过 layerId 识别具体是哪个护盾被弹出。
     *
     * @return ShieldSnapshot 实现 IShield 接口的快照对象
     */
    private function _createFlattenedSnapshot():ShieldSnapshot {
        // 优先使用内部护盾的 ID 作为层 ID，用于追溯原始护盾
        var layerId:Number = this._id;
        if (this._singleShield != null) {
            layerId = this._singleShield.getId();
        }

        return new ShieldSnapshot(
            layerId,            // layerId：原始护盾的 ID
            this._id,           // containerId：容器的 ID
            this._name,
            this._type,
            this._capacity,
            this._maxCapacity,
            this._targetCapacity,
            this._strength,
            this._rechargeRate,
            this._rechargeDelay,
            this._isTemporary,
            this._resistBypass,
            this._owner
        );
    }

    private function _bindDormantMethods():Void {
        this._mode = MODE_DORMANT;

        // 统一清理护盾引用（防止泄漏旧层对象）
        this._singleShield = null;
        this._shields = null;

        // 直接将实例方法替换为空壳实现
        this.absorbDamage = this._dormant_absorbDamage;
        this.consumeCapacity = this._dormant_consumeCapacity;
        this.update = this._dormant_update;
        this.getCapacity = this._dormant_getCapacity;
        this.getMaxCapacity = this._dormant_getMaxCapacity;
        this.getTargetCapacity = this._dormant_getTargetCapacity;
        this.getStrength = this._dormant_getStrength;
        this.getRechargeRate = this._dormant_getRechargeRate;
        this.getRechargeDelay = this._dormant_getRechargeDelay;
        this.isEmpty = this._dormant_isEmpty;
        this.getResistantCount = this._dormant_getResistantCount;
        this.getSortPriority = this._dormant_getSortPriority;
        this.onHit = this._dormant_onHit;
        this.onBreak = this._dormant_onBreak;
        this.onRechargeStart = this._dormant_onRechargeStart;
        this.onRechargeFull = this._dormant_onRechargeFull;

        // 模式切换后同步立场抗性
        this._syncStanceResistance();
    }

    /**
     * 绑定单盾委托模式方法到实例（保留内部护盾引用）。
     * 用于需要保留自定义逻辑和回调的场景。
     */
    private function _bindSingleDelegateMethods():Void {
        this._mode = MODE_SINGLE;
        this._singleFlattened = false;

        // 直接将实例方法替换为委托实现
        this.absorbDamage = this._singleDelegate_absorbDamage;
        this.consumeCapacity = this._singleDelegate_consumeCapacity;
        this.update = this._singleDelegate_update;
        this.getCapacity = this._singleDelegate_getCapacity;
        this.getMaxCapacity = this._singleDelegate_getMaxCapacity;
        this.getTargetCapacity = this._singleDelegate_getTargetCapacity;
        this.getStrength = this._singleDelegate_getStrength;
        this.getRechargeRate = this._singleDelegate_getRechargeRate;
        this.getRechargeDelay = this._singleDelegate_getRechargeDelay;
        this.isEmpty = this._singleDelegate_isEmpty;
        this.getResistantCount = this._singleDelegate_getResistantCount;
        this.getSortPriority = this._singleDelegate_getSortPriority;
        this.onHit = this._singleDelegate_onHit;
        this.onBreak = this._singleDelegate_onBreak;
        this.onRechargeStart = this._singleDelegate_onRechargeStart;
        this.onRechargeFull = this._singleDelegate_onRechargeFull;

        // 模式切换后同步立场抗性
        this._syncStanceResistance();
    }

    /**
     * 绑定单盾扁平化模式方法到实例（高性能）。
     * 直接使用容器自身字段，无委托开销。
     */
    private function _bindSingleFlattenedMethods():Void {
        this._mode = MODE_SINGLE;
        this._singleFlattened = true;

        // 直接将实例方法替换为扁平化实现
        this.absorbDamage = this._singleFlat_absorbDamage;
        this.consumeCapacity = this._singleFlat_consumeCapacity;
        this.update = this._singleFlat_update;
        this.getCapacity = this._singleFlat_getCapacity;
        this.getMaxCapacity = this._singleFlat_getMaxCapacity;
        this.getTargetCapacity = this._singleFlat_getTargetCapacity;
        this.getStrength = this._singleFlat_getStrength;
        this.getRechargeRate = this._singleFlat_getRechargeRate;
        this.getRechargeDelay = this._singleFlat_getRechargeDelay;
        this.isEmpty = this._singleFlat_isEmpty;
        this.getResistantCount = this._singleFlat_getResistantCount;
        this.getSortPriority = this._singleFlat_getSortPriority;
        this.onHit = this._singleFlat_onHit;
        this.onBreak = this._singleFlat_onBreak;
        this.onRechargeStart = this._singleFlat_onRechargeStart;
        this.onRechargeFull = this._singleFlat_onRechargeFull;

        // 模式切换后同步立场抗性
        this._syncStanceResistance();
    }

    /**
     * 绑定栈模式方法到实例。
     * 直接覆盖实例的公有方法，消除代理开销。
     */
    private function _bindStackMethods():Void {
        this._mode = MODE_STACK;

        // 直接将实例方法替换为栈实现
        this.absorbDamage = this._stack_absorbDamage;
        this.consumeCapacity = this._stack_consumeCapacity;
        this.update = this._stack_update;
        this.getCapacity = this._stack_getCapacity;
        this.getMaxCapacity = this._stack_getMaxCapacity;
        this.getTargetCapacity = this._stack_getTargetCapacity;
        this.getStrength = this._stack_getStrength;
        this.getRechargeRate = this._stack_getRechargeRate;
        this.getRechargeDelay = this._stack_getRechargeDelay;
        this.isEmpty = this._stack_isEmpty;
        this.getResistantCount = this._stack_getResistantCount;
        this.getSortPriority = this._stack_getSortPriority;
        this.onHit = this._stack_onHit;
        this.onBreak = this._stack_onBreak;
        this.onRechargeStart = this._stack_onRechargeStart;
        this.onRechargeFull = this._stack_onRechargeFull;

        // 模式切换后同步立场抗性
        this._syncStanceResistance();
    }

     /**
      * 从单盾模式升级到栈模式。
      *
      * 【ID稳定性保证】
      * 扁平化模式下保留了原始护盾引用（_singleShield），升级时复用该对象：
      * 1. 将容器字段回写到原Shield（同步扁平化期间的状态变更）
      * 2. 直接将原Shield入栈（保持ID不变）
      * 这样保证层ID跨单盾↔栈模式稳定，外部持有的ID始终有效。
      *
      * 【回调一致性策略】
      * 栈模式下不再把“容器级回调”写入子盾（避免子盾回调重入导致结构迭代失真）。
      * 容器级 onHit/onBreak/onRechargeStart/onRechargeFull/onExpire 由容器在栈热路径统一派发。
      */
     private function _upgradeToStackMode():Void {
        var innerShield:IShield;

        if (this._singleFlattened) {
            // 扁平化模式：复用原始护盾引用，回写容器字段
            if (this._singleShield != null && this._singleShield instanceof BaseShield) {
                var bs:BaseShield = BaseShield(this._singleShield);

                // 回写核心属性（扁平化期间可能被修改）
                // 注意顺序：先设置 maxCapacity，再设置 capacity/targetCapacity
                // 避免 capacity 被旧的 max 值截断（如扁平化期间 max 上调且 capacity 已超过旧 max）
                bs.setMaxCapacity(this._maxCapacity);
                bs.setCapacity(this._capacity);
                bs.setTargetCapacity(this._targetCapacity);
                bs.setStrength(this._strength);
                bs.setRechargeRate(this._rechargeRate);
                bs.setRechargeDelay(this._rechargeDelay);
                bs.setDelayState(this._isDelayed, this._delayTimer);
                bs.setResistBypass(this._resistBypass);
                bs.setOwner(this._owner);

                // 如果是 Shield，回写更多属性
                if (this._singleShield instanceof Shield) {
                    var s:Shield = Shield(this._singleShield);
                    s.setTemporary(this._isTemporary);
                    s.setDuration(this._duration);
                    s.setName(this._name);
                    s.setType(this._type);
                }

                 innerShield = this._singleShield;
             } else {
                // 理论上不应该发生：扁平化模式但无引用，创建新Shield作为回退
                var newShield:Shield = new Shield(
                    this._maxCapacity,
                    this._strength,
                    this._rechargeRate,
                    this._rechargeDelay,
                    this._name,
                    this._type
                );
                newShield.setCapacity(this._capacity);
                newShield.setTargetCapacity(this._targetCapacity);
                newShield.setTemporary(this._isTemporary);
                newShield.setDuration(this._duration);
                newShield.setResistBypass(this._resistBypass);
                newShield.setDelayState(this._isDelayed, this._delayTimer);
                newShield.setOwner(this._owner);

                 innerShield = newShield;
             }
         } else {
            // 委托模式：直接使用原始护盾引用
            innerShield = this._singleShield;
        }

        // 清理单盾引用（已转移到栈）
        this._singleShield = null;

        // 初始化栈
        this._shields = [innerShield];
        this._needsSort = false;
        this._cacheValid = false;
        this._singleFlattened = false;

        // 切换方法
        this._bindStackMethods();
    }

    /**
      * 判断是否为“原生 Shield 实例”（严格等于 Shield 类，而非其子类）。
      * 用于扁平化白名单：避免误吞掉 Shield 子类的 override 逻辑。
      *
      * @param shield 待检测对象
      * @return Boolean 是原生 Shield 返回 true
      */
     private function _isNativeShieldInstance(shield:Object):Boolean {
         return (shield != null && (shield instanceof Shield) && (shield.__proto__ === Shield.prototype));
     }
 
     /**
      * 初始化单盾模式（扁平化方式）。
      * 将护盾属性复制到容器字段，实现高性能访问。
      *
      * 【身份句柄保留】
     * 保留原始护盾引用作为"身份句柄"，用于：
     * - 提供稳定的层ID（通过 _singleShield.getId()）
     * - 升级到栈模式时复用原对象（避免ID漂移）
     * 热路径仍走扁平化字段，不委托方法调用。
     *
     * @param shield 源护盾
     * @return Boolean 是否成功
     */
    private function _initSingleFlattened(shield:IShield):Boolean {
        // 仅允许“原生 Shield”扁平化，避免吞掉子类 override 行为
        if (!this._isNativeShieldInstance(shield)) return false;
        // 防御性：Shield 必然是 BaseShield，但保留显式检查，便于未来重构
        if (!(shield instanceof BaseShield)) return false;

        var bs:BaseShield = BaseShield(shield);

        // 复制属性到容器字段
        this._capacity = bs.getCapacity();
        this._maxCapacity = bs.getMaxCapacity();
        this._targetCapacity = bs.getTargetCapacity();
        this._strength = bs.getStrength();
        this._rechargeRate = bs.getRechargeRate();
        this._rechargeDelay = bs.getRechargeDelay();
        this._delayTimer = bs.getDelayTimer();
        this._isDelayed = bs.isDelayed();
        this._resistBypass = bs.getResistBypass();

        // 如果是 Shield，复制更多属性
        if (shield instanceof Shield) {
            var s:Shield = Shield(shield);
            this._name = s.getName();
            this._type = s.getType();
            this._isTemporary = s.isTemporary();
            this._duration = s.getDuration();
        }

        // 保留引用作为身份句柄（热路径不委托，仅用于ID查询和升级复用）
        this._singleShield = shield;
        this._singleFlattened = true;

        return true;
    }

    /**
     * 初始化单盾模式（委托方式）。
     * 保留护盾引用，通过委托调用保留自定义逻辑和回调。
     *
     * @param shield 要保留的护盾
     * @return Boolean 是否成功（仅 Shield/BaseShield 返回 true）
     */
    private function _initSingleDelegate(shield:IShield):Boolean {
        // 只有 Shield 或 BaseShield（非 ShieldStack）才能进入单盾模式
        if (shield instanceof ShieldStack) return false;
        if (!(shield instanceof BaseShield)) return false;

        // 保留引用，通过委托调用
        this._singleShield = shield;
        this._singleFlattened = false;

        return true;
    }

    /**
     * 检查是否可以安全降级。
     * 仅当最后一层为 Shield 或 BaseShield 时返回 true。
     *
     * @return Boolean 是否可以降级
     */
    private function _canDowngrade():Boolean {
        var arr:Array = this._shields;
        if (arr == null || arr.length != 1) return false;

        var lastShield:Object = arr[0];
        // 只有 Shield 或 BaseShield（非 ShieldStack 等其他实现）才能降级
        return (lastShield instanceof Shield) ||
               (lastShield instanceof BaseShield && !(lastShield instanceof ShieldStack));
    }

    /**
     * 从栈模式降级到单盾模式。
     *
      * 【策略选择】
      * - 如果护盾是原生 Shield 且无自定义回调：使用扁平化（高性能）
      * - 如果护盾有自定义回调或是自定义子类：使用委托（保留逻辑）
      */
    private function _downgradeToSingleMode():Void {
        var arr:Array = this._shields;
        if (arr == null || arr.length != 1) return;

        var shield:IShield = arr[0];

        // 清理栈
        this._shields = null;

        // 检查是否可以安全扁平化（无自定义回调）
        var canFlatten:Boolean = false;
        if (this._isNativeShieldInstance(shield)) {
            var s:Shield = Shield(shield);
            // 如果没有自定义回调，可以扁平化
            canFlatten = (s.onHitCallback == null && s.onBreakCallback == null &&
                          s.onRechargeStartCallback == null && s.onRechargeFullCallback == null &&
                          s.onExpireCallback == null);
        }

        if (canFlatten) {
            // 扁平化模式
            this._initSingleFlattened(shield);
            this._bindSingleFlattenedMethods();
        } else {
            // 委托模式（保留自定义逻辑）
            this._singleShield = shield;
            this._singleFlattened = false;
            this._bindSingleDelegateMethods();
        }

        this._downgradeCounter = 0;
    }

    // ==================== 结构修改锁（回调重入安全） ====================

    private function _lockStructure():Void {
        this._structureLockDepth++;
    }

    private function _unlockStructure():Void {
        this._structureLockDepth--;
        if (this._structureLockDepth <= 0) {
            this._structureLockDepth = 0;
            this._flushStructureOps();
        }
    }

    private function _isStructureLocked():Boolean {
        return this._structureLockDepth > 0;
    }

    private function _queueStructureOp(op:Object):Void {
        if (this._pendingStructureOps == null) {
            this._pendingStructureOps = [];
        }
        this._pendingStructureOps.push(op);
    }

    private function _flushStructureOps():Void {
        // 防御：允许在 flush 期间再次排队（循环处理直到队列为空）
        var guard:Number = 0;
        while (this._pendingStructureOps != null && this._pendingStructureOps.length > 0) {
            var ops:Array = this._pendingStructureOps;
            this._pendingStructureOps = null;

            var len:Number = ops.length;
            for (var i:Number = 0; i < len; i++) {
                this._applyStructureOp(ops[i]);
            }

            guard++;
            if (guard > 16) {
                // 极端情况下避免无限循环（例如回调内持续排队）
                break;
            }
        }
    }

    private function _applyStructureOp(op:Object):Void {
        if (op == null) return;
        var t:Number = op.t;
        if (t == STRUCT_OP_ADD) {
            this.addShield(IShield(op.shield), op.preserveReference);
        } else if (t == STRUCT_OP_REMOVE) {
            this.removeShield(IShield(op.shield));
        } else if (t == STRUCT_OP_REMOVE_BY_ID) {
            this.removeShieldById(op.id);
        } else if (t == STRUCT_OP_CLEAR) {
            this.clear();
        }
    }

    /**
     * 检测添加 child 是否会形成容器环（cycle）。
     *
     * 【问题背景】
     * AdaptiveShield 支持将“其他容器型 IShield”作为层加入（例如 ShieldStack / 另一个 AdaptiveShield），
     * 若出现 A->B->...->A 的环，会在 getResistantCount/_stack_updateCache 等递归聚合路径导致无限递归/卡死。
     *
     * 【实现策略】
     * 仅在 addShield() 时做一次性 DFS 检测：如果 child 内部（通过 getShields）可达 this，则拒绝添加。
     * 该检测只在“加入一个容器型子盾”时才会发生，不影响普通 Shield/BaseShield 热路径。
     *
     * @param child 待添加的子盾
     * @return Boolean 会形成环返回 true
     */
    private function _wouldCreateCycle(child:IShield):Boolean {
        // 非容器（无 getShields 方法）不可能包含 this
        if (child == null || typeof child["getShields"] != "function") return false;

        var visited:Object = {};
        var stack:Array = [child];
        var guard:Number = 0;

        while (stack.length > 0) {
            var node:Object = stack.pop();
            if (node == null) continue;
            if (node === this) return true;

            var key:String = null;
            if (typeof node["getId"] == "function") {
                var nid:Number = Number(node.getId());
                key = String(nid);
            }

            if (key != null) {
                if (visited[key]) continue;
                visited[key] = true;
            }

            if (typeof node["getShields"] == "function") {
                var children:Array = node.getShields();
                var clen:Number = (children != null) ? children.length : 0;
                for (var i:Number = 0; i < clen; i++) {
                    stack.push(children[i]);
                }
            }

            guard++;
            if (guard > 256) {
                // 防御：异常结构下避免死循环
                break;
            }
        }

        return false;
    }

    // ==================== 层管理接口（ShieldStack 兼容） ====================

    /**
     * 添加护盾层。
     *
     * 【模式转换】
     * - 空壳模式 + 添加单护盾(Shield/BaseShield) → 单盾模式（最优热路径）
     * - 空壳模式 + 添加嵌套栈(ShieldStack) → 栈模式
     * - 单盾模式 + 添加护盾 → 升级到栈模式
     * - 栈模式 + 添加护盾 → 追加到栈
     *
     * 【preserveReference 参数】
     * - false（默认）：尝试使用扁平化模式（仅原生 Shield 且无自定义回调时生效），高性能但不保留护盾的自定义回调
     * - true：使用委托模式，保留护盾的自定义回调和子类重写方法
     *
     * 【自动检测】
     * 当 preserveReference=false 时：
     * - 若检测到护盾有自定义回调，自动切换到委托模式
     * - 若为 Shield 子类（override 逻辑），自动切换到委托模式（避免扁平化吞掉子类行为）
     *
     * 【不会添加】
     * null、未激活护盾、容器自身、重复引用护盾、会形成容器环(cycle)的护盾。
     *
     * @param shield 要添加的护盾
     * @param preserveReference 是否保留护盾引用（默认false，高性能扁平化）
     * @return Boolean 添加成功返回true
     */
    public function addShield(shield:IShield, preserveReference:Boolean):Boolean {
        if (shield == null) return false;
        // 防御：禁止把容器自身作为层加入（会形成递归引用）
        if (shield === this) return false;
        if (!shield.isActive()) return false;

        // 容器环防护：禁止引入能回到自身的子容器
        if (this._wouldCreateCycle(shield)) return false;

        // 默认值处理
        if (preserveReference == undefined) preserveReference = false;

        // 回调重入保护：迭代期间的结构修改排队，避免数组迭代失真
        if (this._isStructureLocked()) {
            // 重复引用防护：避免排队后产生重复层
            if (this._mode == MODE_SINGLE && this._singleShield === shield) return false;
            if (this._mode == MODE_STACK && this._shields != null) {
                var existArr:Array = this._shields;
                var existLen:Number = existArr.length;
                for (var ei:Number = 0; ei < existLen; ei++) {
                    if (existArr[ei] === shield) return false;
                }
            }
            this._queueStructureOp({t: STRUCT_OP_ADD, shield: shield, preserveReference: preserveReference});
            return true;
        }

        // 重复引用防护：避免同一层对象被重复加入
        if (this._mode == MODE_SINGLE && this._singleShield === shield) return false;
        if (this._mode == MODE_STACK && this._shields != null) {
            var arr0:Array = this._shields;
            var len0:Number = arr0.length;
            for (var di:Number = 0; di < len0; di++) {
                if (arr0[di] === shield) return false;
            }
        }

        // 根据当前模式决定升级路径
        if (this._mode == MODE_DORMANT) {
            // 空壳模式：优先尝试进入单盾模式（最优热路径）
            // 检查是否能进入单盾模式
            if (shield instanceof ShieldStack) {
                // ShieldStack 必须进入栈模式
                this._shields = [shield];
                this._needsSort = false;
                this._cacheValid = false;
                // 先设置 owner，再绑定方法（_bindStackMethods 内部会调用 _syncStanceResistance）
                shield.setOwner(this._owner);
                this._bindStackMethods();
                return true;
            } else if (shield instanceof BaseShield) {
                // 确定使用扁平化还是委托
                var useDelegate:Boolean = preserveReference;

                // 如果未指定保留引用，检查是否有自定义回调需要保留
                if (!useDelegate && shield instanceof Shield) {
                    var s:Shield = Shield(shield);
                    // Shield 子类默认走委托，避免扁平化吞掉 override 逻辑
                    if (!this._isNativeShieldInstance(s)) {
                        useDelegate = true;
                    } else {
                        useDelegate = (s.onHitCallback != null || s.onBreakCallback != null ||
                                       s.onRechargeStartCallback != null || s.onRechargeFullCallback != null ||
                                       s.onExpireCallback != null);
                    }
                }
                // 非 Shield 的 BaseShield 子类始终使用委托（保留子类逻辑）
                if (!useDelegate && !(shield instanceof Shield)) {
                    useDelegate = true;
                }

                if (useDelegate) {
                    // 委托模式
                    this._initSingleDelegate(shield);
                    this._bindSingleDelegateMethods();
                } else {
                    // 扁平化模式
                    this._initSingleFlattened(shield);
                    this._bindSingleFlattenedMethods();
                }

                // 设置 owner（BaseShield 路径）
                BaseShield(shield).setOwner(this._owner);
                return true;
            } else {
                // 其他 IShield 实现进入栈模式
                this._shields = [shield];
                this._needsSort = false;
                this._cacheValid = false;
                // 先设置 owner，再绑定方法（_bindStackMethods 内部会调用 _syncStanceResistance）
                shield.setOwner(this._owner);
                this._bindStackMethods();
                return true;
            }
        } else if (this._mode == MODE_SINGLE) {
            // 单盾模式：先升级到栈模式
            this._upgradeToStackMode();
            // 再添加到栈
            this._shields.push(shield);
            this._needsSort = true;
            this._cacheValid = false;
        } else {
            // 栈模式：直接添加
            this._shields.push(shield);
            this._needsSort = true;
            this._cacheValid = false;
        }

        // 设置owner（栈模式路径，通过接口）
        shield.setOwner(this._owner);

        // 栈路径：push 后立即同步立场抗性，确保添加护盾后 owner.魔法抗性["立场"] 立即一致
        this._syncStanceResistance();

        return true;
    }

    /**
     * 从栈中移除指定护盾。
     * 使用交换法 O(1) 删除，后续排序会恢复顺序。
     *
     * @param shield 要移除的护盾
     * @return Boolean 移除成功返回true
     */
    public function removeShield(shield:IShield):Boolean {
        if (this._mode != MODE_STACK) return false;
        if (shield == null) return false;

        // 回调重入保护：迭代期间排队移除请求
        if (this._isStructureLocked()) {
            var qArr:Array = this._shields;
            var qLen:Number = qArr.length;
            for (var qi:Number = 0; qi < qLen; qi++) {
                if (qArr[qi] === shield) {
                    this._queueStructureOp({t: STRUCT_OP_REMOVE, shield: shield});
                    return true;
                }
            }
            return false;
        }

        var arr:Array = this._shields;
        var len:Number = arr.length;
        for (var i:Number = 0; i < len; i++) {
            if (arr[i] === shield) {
                // 交换到末尾并截断（O(1) 删除，避免 pop 函数调用开销）
                arr[i] = arr[len - 1];
                arr.length = len - 1;
                this._cacheValid = false;
                this._needsSort = true;
                // 检查是否清空到0层，若是则切回空壳模式
                if (len == 1) {
                    this._shields = null;
                    this._bindDormantMethods();
                    this._downgradeCounter = 0;
                } else {
                    // 移除后同步立场抗性（表观强度可能变化）
                    this._syncStanceResistance();
                }
                return true;
            }
        }
        return false;
    }

    /**
     * 根据ID移除护盾。
     *
     * 【单盾模式支持】
     * 现在支持在单盾模式下按层ID移除护盾：
     * - 扁平化模式：通过 _singleShield.getId() 匹配
     * - 委托模式：通过 _singleShield.getId() 匹配
     * - 匹配成功则降级到空壳模式
     *
     * 【向后兼容】
     * 单盾模式下也兼容容器ID匹配（this._id），确保旧代码不受影响。
     *
     * @param id 护盾ID
     * @return Boolean 移除成功返回true
     */
    public function removeShieldById(id:Number):Boolean {
        // 空壳模式：无护盾可移除
        if (this._mode == MODE_DORMANT) {
            return false;
        }

        // 回调重入保护：迭代期间排队移除请求
        if (this._isStructureLocked()) {
            if (this._mode == MODE_SINGLE) {
                var targetId:Number = -1;
                if (this._singleShield != null) {
                    targetId = this._singleShield.getId();
                } else {
                    targetId = this._id;
                }
                if (targetId == id || this._id == id) {
                    this._queueStructureOp({t: STRUCT_OP_REMOVE_BY_ID, id: id});
                    return true;
                }
                return false;
            }

            // 栈模式：查找匹配项后排队
            var qArr2:Array = this._shields;
            var qLen2:Number = qArr2.length;
            for (var qi2:Number = 0; qi2 < qLen2; qi2++) {
                if (qArr2[qi2].getId() == id) {
                    this._queueStructureOp({t: STRUCT_OP_REMOVE_BY_ID, id: id});
                    return true;
                }
            }
            return false;
        }

        // 单盾模式：按层ID匹配
        if (this._mode == MODE_SINGLE) {
            var targetId:Number = -1;

            // 通过接口获取内部护盾的ID
            if (this._singleShield != null) {
                targetId = this._singleShield.getId();
            } else {
                // 扁平化但引用丢失（理论上不应该发生），退化用容器ID
                targetId = this._id;
            }

            // 匹配层ID
            if (targetId == id) {
                this._bindDormantMethods();  // 统一清理并降级
                this._downgradeCounter = 0;
                return true;
            }

            // 向后兼容：也匹配容器ID
            if (this._id == id) {
                this._bindDormantMethods();
                this._downgradeCounter = 0;
                return true;
            }

            return false;
        }

        // 栈模式：遍历数组匹配，通过接口 getId() 支持所有 IShield 实现
        // 使用交换法 O(1) 删除
        var arr:Array = this._shields;
        var len:Number = arr.length;
        for (var i:Number = 0; i < len; i++) {
            if (arr[i].getId() == id) {
                // 交换到末尾并截断（O(1) 删除，避免 pop 函数调用开销）
                arr[i] = arr[len - 1];
                arr.length = len - 1;
                this._cacheValid = false;
                this._needsSort = true;
                // 检查是否清空到0层，若是则切回空壳模式
                if (len == 1) {
                    this._bindDormantMethods();
                    this._downgradeCounter = 0;
                } else {
                    // 移除后同步立场抗性（表观强度可能变化）
                    this._syncStanceResistance();
                }
                return true;
            }
        }
        return false;
    }

    /**
     * 获取所有护盾层。
     * 空壳模式和单盾模式返回空数组。
     *
     * @return Array 护盾数组的副本
     */
    public function getShields():Array {
        if (this._mode == MODE_STACK) {
            return this._shields.slice();
        }
        return [];
    }

    /**
     * 获取护盾层数。
     * 空壳模式返回0，单盾模式返回1。
     *
     * @return Number 当前护盾层数
     */
    public function getShieldCount():Number {
        if (this._mode == MODE_DORMANT) {
            return 0;
        } else if (this._mode == MODE_SINGLE) {
            return 1;
        }
        return this._shields.length;
    }

    /**
     * 根据ID获取护盾。
     *
     * 【单盾模式修正】
     * 现在按层ID（内部护盾的ID）匹配，而非容器ID：
     * - 扁平化模式：通过 _singleShield.getId() 匹配，返回前同步状态
     * - 委托模式：通过 _singleShield.getId() 匹配
     * - 匹配成功返回内部护盾引用
     *
     * 【扁平化状态同步】
     * 扁平化模式下 _singleShield 仅作为身份句柄，其属性可能是旧值。
     * 返回前将容器字段同步到 _singleShield，确保调用方读取到正确状态。
     *
     * 【向后兼容】
     * 单盾模式下也兼容容器ID匹配（this._id），返回 this。
     *
     * @param id 护盾ID
     * @return IShield 护盾实例，不存在返回null
     */
    public function getShieldById(id:Number):IShield {
        if (this._mode == MODE_DORMANT) {
            return null;
        } else if (this._mode == MODE_SINGLE) {
            // 优先匹配层ID（通过接口获取内部护盾的ID）
            if (this._singleShield != null) {
                if (this._singleShield.getId() == id) {
                    // 扁平化模式下，返回前同步状态到身份句柄
                    if (this._singleFlattened && this._singleShield instanceof BaseShield) {
                        this._syncStateToInnerShield();
                    }
                    return this._singleShield;
                }
            }
            // 向后兼容：容器ID也能匹配
            if (this._id == id) {
                return this;
            }
            return null;
        }

        // 栈模式：遍历数组匹配，通过接口 getId() 支持所有 IShield 实现
        var arr:Array = this._shields;
        var len:Number = arr.length;
        for (var i:Number = 0; i < len; i++) {
            var s:IShield = arr[i];
            if (s.getId() == id) {
                return s;
            }
        }
        return null;
    }

    /**
     * 将容器字段同步到内部护盾引用（扁平化模式专用）。
     *
     * 【使用场景】
     * 扁平化模式下 _singleShield 仅作为身份句柄，热路径不更新其属性。
     * 当外部需要通过 getShieldById 获取内部护盾引用时，需先同步状态，
     * 确保调用方读取到的 getCapacity()/getName()/getOwner() 等值是最新的。
     *
     * 【契约】
     * 此方法同步核心数值和元数据，确保返回的护盾引用可用于读取当前状态：
     * - 数值状态：capacity/maxCapacity/targetCapacity/strength/rechargeRate/rechargeDelay
     * - 延迟状态：isDelayed/delayTimer
     * - 标志位：resistBypass/isTemporary
     * - 时间属性：duration
     * - 元数据：owner/name/type
     *
     * 【不同步项】
     * - isActive：AdaptiveShield 的 _isActive 语义与内部护盾不同（容器始终保持 true 以接收新护盾），
     *   不应强行同步。调用方若需判断护盾是否有效，应使用容器的 isActive() 或 isDormantMode()。
     */
    private function _syncStateToInnerShield():Void {
        if (this._singleShield == null || !(this._singleShield instanceof BaseShield)) {
            return;
        }

        var bs:BaseShield = BaseShield(this._singleShield);

        // 同步核心属性（先 max 再 capacity，避免截断）
        bs.setMaxCapacity(this._maxCapacity);
        bs.setCapacity(this._capacity);
        bs.setTargetCapacity(this._targetCapacity);
        bs.setStrength(this._strength);
        bs.setRechargeRate(this._rechargeRate);
        bs.setRechargeDelay(this._rechargeDelay);
        bs.setDelayState(this._isDelayed, this._delayTimer);
        bs.setResistBypass(this._resistBypass);
        bs.setOwner(this._owner);

        // 如果是 Shield，同步更多属性（含元数据）
        if (this._singleShield instanceof Shield) {
            var s:Shield = Shield(this._singleShield);
            s.setTemporary(this._isTemporary);
            s.setDuration(this._duration);
            s.setName(this._name);
            s.setType(this._type);
        }
    }

    /**
     * 清空所有护盾层并重置到空壳模式。
     * 护盾将保持激活但不参与逻辑，等待新护盾推入。
     */
    public function clear():Void {
        // 回调重入保护：迭代期间排队清空请求
        if (this._isStructureLocked()) {
            this._queueStructureOp({t: STRUCT_OP_CLEAR});
            return;
        }

        // 无论当前模式，都重置到空壳模式
        this._singleShield = null;
        this._shields = null;
        this._cacheValid = false;
        this._delayTimer = 0;
        this._isDelayed = false;
        this._isActive = true;  // 保持激活状态
        this._downgradeCounter = 0;
        this._bindDormantMethods();
    }

    // ==================== IShield 接口实现（占位，运行时被替换） ====================
    // 这些方法在构造时会被 _bindSingleMethods 或 _bindStackMethods 覆盖
    // 这里的实现仅作为类型签名占位符

    public function absorbDamage(damage:Number, bypassShield:Boolean, hitCount:Number):Number {
        return damage; // 占位
    }

    public function consumeCapacity(amount:Number):Number {
        return 0; // 占位
    }

    public function getCapacity():Number {
        return 0; // 占位
    }

    public function getMaxCapacity():Number {
        return 0; // 占位
    }

    public function getTargetCapacity():Number {
        return 0; // 占位
    }

    public function getStrength():Number {
        return 0; // 占位
    }

    public function getRechargeRate():Number {
        return 0; // 占位
    }

    public function getRechargeDelay():Number {
        return 0; // 占位
    }

    public function isEmpty():Boolean {
        return true; // 占位
    }

    public function isActive():Boolean {
        return this._isActive;
    }

    public function getResistantCount():Number {
        return 0; // 占位
    }

    public function update(deltaTime:Number):Boolean {
        return false; // 占位
    }

    public function onHit(absorbed:Number):Void {
        // 占位
    }

    public function onBreak():Void {
        // 占位
    }

    public function onRechargeStart():Void {
        // 占位
    }

    public function onRechargeFull():Void {
        // 占位
    }

    public function getSortPriority():Number {
        return 0; // 占位
    }

    // ==================== 空壳模式实现（零逻辑开销） ====================

    /**
     * 空壳模式：直接穿透所有伤害
     */
    private function _dormant_absorbDamage(damage:Number, bypassShield:Boolean, hitCount:Number):Number {
        return damage;
    }

    /**
     * 空壳模式：不消耗任何容量
     */
    private function _dormant_consumeCapacity(amount:Number):Number {
        return 0;
    }

    /**
     * 空壳模式：无需更新
     */
    private function _dormant_update(deltaTime:Number):Boolean {
        return false;
    }

    /**
     * 空壳模式：容量为0
     */
    private function _dormant_getCapacity():Number {
        return 0;
    }

    /**
     * 空壳模式：最大容量为0
     */
    private function _dormant_getMaxCapacity():Number {
        return 0;
    }

    /**
     * 空壳模式：目标容量为0
     */
    private function _dormant_getTargetCapacity():Number {
        return 0;
    }

    /**
     * 空壳模式：强度为0
     */
    private function _dormant_getStrength():Number {
        return 0;
    }

    /**
     * 空壳模式：充能速率为0
     */
    private function _dormant_getRechargeRate():Number {
        return 0;
    }

    /**
     * 空壳模式：充能延迟为0
     */
    private function _dormant_getRechargeDelay():Number {
        return 0;
    }

    /**
     * 空壳模式：始终为空
     */
    private function _dormant_isEmpty():Boolean {
        return true;
    }

    /**
     * 空壳模式：无抵抗绕过
     */
    private function _dormant_getResistantCount():Number {
        return 0;
    }

    /**
     * 空壳模式：最低优先级
     */
    private function _dormant_getSortPriority():Number {
        return -Infinity;
    }

    /**
     * 空壳模式：命中无效果
     */
    private function _dormant_onHit(absorbed:Number):Void {
        // 空壳模式不处理命中
    }

    /**
     * 空壳模式：击碎无效果
     */
    private function _dormant_onBreak():Void {
        // 空壳模式不处理击碎
    }

    /**
     * 空壳模式：充能开始无效果
     */
    private function _dormant_onRechargeStart():Void {
        // 空壳模式不处理充能开始
    }

    /**
     * 空壳模式：充能完毕无效果
     */
    private function _dormant_onRechargeFull():Void {
        // 空壳模式不处理充能完毕
    }

    // ==================== 单盾扁平化模式实现（高性能，直接使用容器字段） ====================

    /**
     * 扁平化模式伤害吸收：直接使用容器字段
     */
    private function _singleFlat_absorbDamage(damage:Number, bypassShield:Boolean, hitCount:Number):Number {
        if (!this._isActive) return damage;

        // 容量为0时提前返回（与 BaseShield 一致，避免重复触发 onBreakCallback）
        var capacity:Number = this._capacity;
        if (capacity <= 0) return damage;

        var strength:Number = this._strength;
        if (strength <= 0) return damage;

        // 绕过检查
        if (bypassShield && !this._resistBypass) {
            return damage;
        }

        if (hitCount == undefined || hitCount < 1) hitCount = 1;

        var effectiveStrength:Number = strength * hitCount;

        // 计算可吸收量
        var absorbable:Number = damage;
        if (absorbable > effectiveStrength) absorbable = effectiveStrength;
        if (absorbable > capacity) absorbable = capacity;

        // 扣除容量
        this._capacity = capacity - absorbable;

        // 触发 onHit 回调
        if (absorbable > 0) {
            if (this.onHitCallback != null) {
                this.onHitCallback(this, absorbable);
            }
            // 重置延迟计时器（仅正充能）
            if (this._rechargeRate > 0 && this._rechargeDelay > 0) {
                this._delayTimer = this._rechargeDelay;
                this._isDelayed = true;
            }
        }

        // 检查是否击碎
        if (this._capacity <= 0) {
            this._capacity = 0;
            if (this.onBreakCallback != null) {
                this.onBreakCallback(this);
            }
            // 临时盾击碎后降级到空壳模式（保持激活以接收新护盾）
            if (this._isTemporary) {
                // 在降级前保存快照，供回调读取原护盾元数据
                var snapshot:Object = this._createFlattenedSnapshot();
                // 先降级，这样回调中的 addShield 可以正常工作
                this._bindDormantMethods();
                // 触发弹出回调（单盾模式也视为从容器弹出）
                if (this.onShieldEjectedCallback != null) {
                    this.onShieldEjectedCallback(snapshot, this);
                }
                // 触发全部耗尽回调（单盾耗尽即全部耗尽）
                if (this.onAllShieldsDepletedCallback != null) {
                    this.onAllShieldsDepletedCallback(this);
                }
            }
        }

        return damage - absorbable;
    }

    /**
     * 扁平化模式容量消耗
     */
    private function _singleFlat_consumeCapacity(amount:Number):Number {
        // 容量为0时提前返回（与 BaseShield 一致，避免重复触发 onBreakCallback）
        var capacity:Number = this._capacity;
        if (!this._isActive || amount <= 0 || capacity <= 0) return 0;

        var consumed:Number = amount;
        if (consumed > capacity) consumed = capacity;

        this._capacity = capacity - consumed;

        // 触发 onHit
        if (consumed > 0) {
            if (this.onHitCallback != null) {
                this.onHitCallback(this, consumed);
            }
            if (this._rechargeRate > 0 && this._rechargeDelay > 0) {
                this._delayTimer = this._rechargeDelay;
                this._isDelayed = true;
            }
        }

        // 检查击碎
        if (this._capacity <= 0) {
            this._capacity = 0;
            if (this.onBreakCallback != null) {
                this.onBreakCallback(this);
            }
            // 临时盾击碎后降级到空壳模式（保持激活以接收新护盾）
            if (this._isTemporary) {
                // 在降级前保存快照，供回调读取原护盾元数据
                var snapshot:Object = this._createFlattenedSnapshot();
                // 先降级，这样回调中的 addShield 可以正常工作
                this._bindDormantMethods();
                // 触发弹出回调（单盾模式也视为从容器弹出）
                if (this.onShieldEjectedCallback != null) {
                    this.onShieldEjectedCallback(snapshot, this);
                }
                // 触发全部耗尽回调（单盾耗尽即全部耗尽）
                if (this.onAllShieldsDepletedCallback != null) {
                    this.onAllShieldsDepletedCallback(this);
                }
            }
        }

        return consumed;
    }

    /**
     * 扁平化模式更新
     */
    private function _singleFlat_update(deltaTime:Number):Boolean {
        if (!this._isActive) return false;

        var changed:Boolean = false;
        var rate:Number = this._rechargeRate;

        // 处理持续时间（临时盾）
        if (this._isTemporary && this._duration > 0) {
            this._duration -= deltaTime;
            if (this._duration <= 0) {
                this._duration = 0;
                // 触发过期回调
                if (this.onExpireCallback != null) {
                    this.onExpireCallback(this);
                }
                // 在降级前保存快照，供回调读取原护盾元数据
                var snapshot:Object = this._createFlattenedSnapshot();
                // 先降级到空壳模式（保持激活以接收新护盾）
                // 这样回调中的 addShield 可以正常工作
                this._bindDormantMethods();
                // 触发弹出回调（单盾模式也视为从容器弹出）
                if (this.onShieldEjectedCallback != null) {
                    this.onShieldEjectedCallback(snapshot, this);
                }
                // 触发全部耗尽回调（单盾耗尽即全部耗尽）
                if (this.onAllShieldsDepletedCallback != null) {
                    this.onAllShieldsDepletedCallback(this);
                }
                return true;
            }
        }

        // 正充能逻辑
         if (rate > 0) {
             var capacity:Number = this._capacity;
            // 维持不变量：targetCapacity 不应超过 maxCapacity
            var max:Number = this._maxCapacity;
            var target:Number = this._targetCapacity;
            if (target > max) target = max;
            if (target < 0) target = 0;

            if (capacity >= target) return false;

            // 处理延迟
            if (this._isDelayed) {
                this._delayTimer -= deltaTime;
                if (this._delayTimer <= 0) {
                    this._delayTimer = 0;
                    this._isDelayed = false;
                    if (this.onRechargeStartCallback != null) {
                        this.onRechargeStartCallback(this);
                    }
                }
                return false; // 延迟期间容量不变
            }

             // 充能
             capacity += rate * deltaTime;
             if (capacity >= target) {
                 capacity = target;
                 if (this.onRechargeFullCallback != null) {
                     this.onRechargeFullCallback(this);
                 }
             }
            if (capacity > max) capacity = max;
             this._capacity = capacity;
             changed = true;
         }
        // 负充能逻辑（衰减）
        else if (rate < 0) {
            var cap:Number = this._capacity;
            if (cap <= 0) return false;

            cap += rate * deltaTime;
            if (cap <= 0) {
                cap = 0;
                this._capacity = cap;
                // 触发击碎回调
                if (this.onBreakCallback != null) {
                    this.onBreakCallback(this);
                }
                // 在降级前保存快照，供回调读取原护盾元数据
                var decaySnapshot:Object = this._createFlattenedSnapshot();
                // 先降级到空壳模式（保持激活以接收新护盾）
                // 这样回调中的 addShield 可以正常工作
                this._bindDormantMethods();
                // 触发弹出回调（单盾模式也视为从容器弹出）
                if (this.onShieldEjectedCallback != null) {
                    this.onShieldEjectedCallback(decaySnapshot, this);
                }
                // 触发全部耗尽回调（单盾耗尽即全部耗尽）
                if (this.onAllShieldsDepletedCallback != null) {
                    this.onAllShieldsDepletedCallback(this);
                }
                return true;
            }
            this._capacity = cap;
            changed = true;
        }

        return changed;
    }

    private function _singleFlat_getCapacity():Number { return this._capacity; }
    private function _singleFlat_getMaxCapacity():Number { return this._maxCapacity; }
    private function _singleFlat_getTargetCapacity():Number { return this._targetCapacity; }
    private function _singleFlat_getStrength():Number { return this._strength; }
    private function _singleFlat_getRechargeRate():Number { return this._rechargeRate; }
    private function _singleFlat_getRechargeDelay():Number { return this._rechargeDelay; }
    private function _singleFlat_isEmpty():Boolean { return this._capacity <= 0; }
    private function _singleFlat_getResistantCount():Number { return this._resistBypass ? 1 : 0; }

    private function _singleFlat_getSortPriority():Number {
        return ShieldUtil.calcSortPriority(this._strength, this._rechargeRate, this._id);
    }

    private function _singleFlat_onHit(absorbed:Number):Void {
        if (this._rechargeRate > 0 && this._rechargeDelay > 0) {
            this._delayTimer = this._rechargeDelay;
            this._isDelayed = true;
        }
    }

    private function _singleFlat_onBreak():Void {
        if (this.onBreakCallback != null) {
            this.onBreakCallback(this);
        }
        if (this._isTemporary) {
            // 降级到空壳模式（保持 _isActive = true 以接收新护盾）
            this._bindDormantMethods();
        }
    }

    private function _singleFlat_onRechargeStart():Void {
        if (this.onRechargeStartCallback != null) {
            this.onRechargeStartCallback(this);
        }
    }

    private function _singleFlat_onRechargeFull():Void {
        if (this.onRechargeFullCallback != null) {
            this.onRechargeFullCallback(this);
        }
    }

    // ==================== 单盾委托模式实现（保留内部护盾引用） ====================

    /**
     * 委托模式伤害吸收：委托到内部护盾
     */
    private function _singleDelegate_absorbDamage(damage:Number, bypassShield:Boolean, hitCount:Number):Number {
        if (!this._isActive) return damage;

        var shield:IShield = this._singleShield;

        // 容量为0时提前返回（与扁平化模式一致，避免重复触发 onBreakCallback）
        var preCapacity:Number = shield.getCapacity();
        if (preCapacity <= 0) return damage;

        // 委托伤害处理
        var remaining:Number = shield.absorbDamage(damage, bypassShield, hitCount);

        // 计算实际吸收量并触发容器级 onHit 回调
        var absorbed:Number = damage - remaining;
        if (absorbed > 0 && this.onHitCallback != null) {
            this.onHitCallback(this, absorbed);
        }

        // 检查是否击碎（容量从 >0 变为 0）
        var postCapacity:Number = shield.getCapacity();
        if (preCapacity > 0 && postCapacity <= 0) {
            if (this.onBreakCallback != null) {
                this.onBreakCallback(this);
            }
        }

        // 检查护盾是否失活（通常为临时盾击碎）
        if (!shield.isActive()) {
            // 先降级到空壳模式，这样回调中的 addShield 可以正常工作
            this._singleShield = null;
            this._bindDormantMethods();
            // 触发弹出回调（单盾模式也视为从容器弹出）
            if (this.onShieldEjectedCallback != null) {
                this.onShieldEjectedCallback(shield, this);
            }
            // 触发全部耗尽回调（单盾耗尽即全部耗尽）
            if (this.onAllShieldsDepletedCallback != null) {
                this.onAllShieldsDepletedCallback(this);
            }
        }

        return remaining;
    }

    /**
     * 委托模式容量消耗：委托到内部护盾
     */
    private function _singleDelegate_consumeCapacity(amount:Number):Number {
        if (!this._isActive || amount <= 0) return 0;

        var shield:IShield = this._singleShield;

        // 容量为0时提前返回（与扁平化模式一致，避免重复触发 onBreakCallback）
        var preCapacity:Number = shield.getCapacity();
        if (preCapacity <= 0) return 0;

        var consumed:Number = shield.consumeCapacity(amount);

        // 触发容器级 onHit 回调
        if (consumed > 0 && this.onHitCallback != null) {
            this.onHitCallback(this, consumed);
        }

        // 检查是否击碎（容量从 >0 变为 0）
        var postCapacity:Number = shield.getCapacity();
        if (preCapacity > 0 && postCapacity <= 0) {
            if (this.onBreakCallback != null) {
                this.onBreakCallback(this);
            }
        }

        // 检查护盾是否失活
        if (!shield.isActive()) {
            // 先降级到空壳模式，这样回调中的 addShield 可以正常工作
            this._singleShield = null;
            this._bindDormantMethods();
            // 触发弹出回调（单盾模式也视为从容器弹出）
            if (this.onShieldEjectedCallback != null) {
                this.onShieldEjectedCallback(shield, this);
            }
            // 触发全部耗尽回调（单盾耗尽即全部耗尽）
            if (this.onAllShieldsDepletedCallback != null) {
                this.onAllShieldsDepletedCallback(this);
            }
        }

        return consumed;
    }

    /**
     * 委托模式更新：委托到内部护盾并检测状态变化
     */
    private function _singleDelegate_update(deltaTime:Number):Boolean {
        if (!this._isActive) return false;

        var shield:IShield = this._singleShield;

        // 预读取状态用于容器级回调一致性（不依赖子盾的回调字段）
        var preCapacity:Number = shield.getCapacity();
        var preMax:Number = shield.getMaxCapacity();
        var preTarget:Number = shield.getTargetCapacity();
        if (preTarget > preMax) preTarget = preMax;
        if (preTarget < 0) preTarget = 0;

        var preDelayed:Boolean = false;
        if (shield instanceof BaseShield) {
            preDelayed = BaseShield(shield).isDelayed();
        }

        var watchExpire:Boolean = false;
        var preDuration:Number = 0;
        if (shield instanceof Shield) {
            var preS:Shield = Shield(shield);
            preDuration = preS.getDuration();
            watchExpire = (preS.isTemporary() && preDuration > 0);
        }

        // 委托更新
        var changed:Boolean = shield.update(deltaTime);

        // 统一读取更新后的状态（避免重复调用接口）
        var postCapacity:Number = shield.getCapacity();

        // 容器级充能回调：延迟结束/充能满（单盾委托模式也应触发）
        if (shield instanceof BaseShield) {
            var bs:BaseShield = BaseShield(shield);
            if (preDelayed && !bs.isDelayed()) {
                if (this.onRechargeStartCallback != null) {
                    this.onRechargeStartCallback(this);
                }
            }
        }
        if (preCapacity < preTarget && postCapacity >= preTarget) {
            if (this.onRechargeFullCallback != null) {
                this.onRechargeFullCallback(this);
            }
        }

        // 容器级击碎回调：容量从 >0 变为 0（包含衰减到0的情况）
        if (preCapacity > 0 && postCapacity <= 0) {
            if (this.onBreakCallback != null) {
                this.onBreakCallback(this);
            }
        }

        // 容器级过期回调：仅对 Shield 的“持续时间归零”语义生效
        if (watchExpire) {
            var postDuration:Number = Shield(shield).getDuration();
            if (preDuration > 0 && postDuration <= 0) {
                if (this.onExpireCallback != null) {
                    this.onExpireCallback(this);
                }
            }
        }

        // 检查护盾是否失活（过期/临时盾击碎/自定义失活）
        if (!shield.isActive()) {
            // 先降级到空壳模式，这样回调中的 addShield 可以正常工作
            this._singleShield = null;
            this._bindDormantMethods();
            // 触发弹出回调（单盾模式也视为从容器弹出）
            if (this.onShieldEjectedCallback != null) {
                this.onShieldEjectedCallback(shield, this);
            }
            // 触发全部耗尽回调（单盾耗尽即全部耗尽）
            if (this.onAllShieldsDepletedCallback != null) {
                this.onAllShieldsDepletedCallback(this);
            }
            return true;
        }

        return changed;
    }

    private function _singleDelegate_onHit(absorbed:Number):Void {
        this._singleShield.onHit(absorbed);
    }

    private function _singleDelegate_onBreak():Void {
        this._singleShield.onBreak();
        if (this.onBreakCallback != null) {
            this.onBreakCallback(this);
        }
        this._singleShield = null;
        this._bindDormantMethods();
    }

    private function _singleDelegate_onRechargeStart():Void {
        this._singleShield.onRechargeStart();
    }

    private function _singleDelegate_onRechargeFull():Void {
        this._singleShield.onRechargeFull();
    }

    private function _singleDelegate_getCapacity():Number { return this._singleShield.getCapacity(); }
    private function _singleDelegate_getMaxCapacity():Number { return this._singleShield.getMaxCapacity(); }
    private function _singleDelegate_getTargetCapacity():Number { return this._singleShield.getTargetCapacity(); }
    private function _singleDelegate_getStrength():Number { return this._singleShield.getStrength(); }
    private function _singleDelegate_getRechargeRate():Number { return this._singleShield.getRechargeRate(); }
    private function _singleDelegate_getRechargeDelay():Number { return this._singleShield.getRechargeDelay(); }
    private function _singleDelegate_isEmpty():Boolean { return this._singleShield.isEmpty(); }
    private function _singleDelegate_getResistantCount():Number { return this._singleShield.getResistantCount(); }
    private function _singleDelegate_getSortPriority():Number { return this._singleShield.getSortPriority(); }

    // ==================== 栈模式实现（等价 ShieldStack） ====================

    private function _stack_sortShields():Void {
        if (!this._needsSort) return;

        var arr:Array = this._shields;
        var len:Number = arr.length;

        // 插入排序
        for (var i:Number = 1; i < len; i++) {
            var current:IShield = arr[i];
            var currentPriority:Number = current.getSortPriority();
            var j:Number = i - 1;

            while (j >= 0 && IShield(arr[j]).getSortPriority() < currentPriority) {
                arr[j + 1] = arr[j];
                j--;
            }
            arr[j + 1] = current;
        }

        this._needsSort = false;
    }

    private function _stack_updateCache():Void {
        if (this._cacheValid) return;

        this._stack_sortShields();

        var arr:Array = this._shields;
        var len:Number = arr.length;

        // 保存旧强度用于变化检测
        var oldStrength:Number = this._cachedStrength;

        this._cachedStrength = 0;
        this._resistantCount = 0;
        this._cachedCapacity = 0;
        this._cachedMaxCapacity = 0;
        this._cachedTargetCapacity = 0;

        var foundFirst:Boolean = false;
        for (var i:Number = 0; i < len; i++) {
            var s:IShield = arr[i];
            if (!s.isActive()) continue;

            this._cachedCapacity += s.getCapacity();
            this._cachedMaxCapacity += s.getMaxCapacity();
            this._cachedTargetCapacity += s.getTargetCapacity();
            this._resistantCount += s.getResistantCount();

            if (!foundFirst && !s.isEmpty()) {
                this._cachedStrength = s.getStrength();
                foundFirst = true;
            }
        }

        this._cacheValid = true;

        // 强度变化时同步立场抗性
        if (this._cachedStrength != oldStrength) {
            this._syncStanceResistance();
        }
    }

    private function _stack_absorbDamage(damage:Number, bypassShield:Boolean, hitCount:Number):Number {
        if (!this._isActive) {
            return damage;
        }

        this._stack_updateCache();

        var stackStrength:Number = this._cachedStrength;
        var preTotalCapacity:Number = this._cachedCapacity;

        if (stackStrength <= 0) {
            return damage;
        }

        // 绕过检查
        if (bypassShield && this._resistantCount <= 0) {
            return damage;
        }

        if (hitCount == undefined || hitCount < 1) {
            hitCount = 1;
        }

        var effectiveStrength:Number = stackStrength * hitCount;

        var arr:Array = this._shields;
        var len:Number = arr.length;

        // 按有效强度节流
        var absorbable:Number = damage;
        if (absorbable > effectiveStrength) {
            absorbable = effectiveStrength;
        }

        var penetrating:Number = damage - absorbable;

        // 分配给内部护盾
        var toAbsorb:Number = absorbable;
        this._lockStructure();
        for (var j:Number = 0; j < len && toAbsorb > 0; j++) {
            var shield:IShield = arr[j];

            if (!shield.isActive() || shield.isEmpty()) {
                continue;
            }

            var cap:Number = shield.getCapacity();
            var shieldAbsorb:Number = toAbsorb;
            if (shieldAbsorb > cap) {
                shieldAbsorb = cap;
            }

            var consumed:Number = shield.consumeCapacity(shieldAbsorb);
            toAbsorb -= consumed;
        }
        this._unlockStructure();

        penetrating += toAbsorb;

        var absorbed:Number = absorbable - toAbsorb;
        if (absorbed > 0) {
            this._cacheValid = false;
            // 容器级 onHit：栈模式也应触发（对外心智无感）
            if (this.onHitCallback != null) {
                this.onHitCallback(this, absorbed);
            }
            // 容器级 onBreak：总容量从 >0 降至 0 时触发
            if (preTotalCapacity > 0 && (preTotalCapacity - absorbed) <= 0) {
                if (this.onBreakCallback != null) {
                    this.onBreakCallback(this);
                }
            }
        }

        return penetrating;
    }

    private function _stack_consumeCapacity(amount:Number):Number {
        if (!this._isActive || amount <= 0) return 0;

        this._stack_updateCache();

        var preTotalCapacity:Number = this._cachedCapacity;
        var arr:Array = this._shields;
        var len:Number = arr.length;
        var toConsume:Number = amount;
        var totalConsumed:Number = 0;

        this._lockStructure();
        for (var i:Number = 0; i < len && toConsume > 0; i++) {
            var shield:IShield = arr[i];

            if (!shield.isActive() || shield.isEmpty()) {
                continue;
            }

            var cap:Number = shield.getCapacity();
            var shieldConsume:Number = toConsume;
            if (shieldConsume > cap) {
                shieldConsume = cap;
            }

            var consumed:Number = shield.consumeCapacity(shieldConsume);
            totalConsumed += consumed;
            toConsume -= consumed;
        }
        this._unlockStructure();

        if (totalConsumed > 0) {
            this._cacheValid = false;
            // 容器级 onHit：栈模式也应触发
            if (this.onHitCallback != null) {
                this.onHitCallback(this, totalConsumed);
            }
            // 容器级 onBreak：总容量从 >0 降至 0 时触发
            if (preTotalCapacity > 0 && (preTotalCapacity - totalConsumed) <= 0) {
                if (this.onBreakCallback != null) {
                    this.onBreakCallback(this);
                }
            }
        }

        return totalConsumed;
    }

    /**
     * 栈模式帧更新。
     *
     * 【回调安全性重构】
     * 采用"先截断后回调"策略，保证 onShieldEjectedCallback 触发时数组结构已稳定：
     * 1. Phase 1: 遍历并收集待弹出护盾，交换到尾部
     * 2. Phase 2: 统一截断数组
     * 3. Phase 3: 触发 ejected 回调（此时结构已稳定，回调可安全修改）
     * 4. Phase 4: 重新读取数组长度，评估降级/耗尽条件
     *
     * 这确保了回调内的 addShield/removeShield/clear 操作不会被后续截断吞掉。
     */
    private function _stack_update(deltaTime:Number):Boolean {
        if (!this._isActive) return false;

        var arr:Array = this._shields;
        var len:Number = arr.length;
        if (len == 0) return false;

        var changed:Boolean = false;

        // 容器级回调事件收集（避免子盾回调重入修改结构时破坏迭代）
        var rechargeStartTriggered:Boolean = false;
        var rechargeFullTriggered:Boolean = false;
        var expiredList:Array = null;

        // 用于“衰减归零”等在 update 路径触发的容器级 onBreak 判定
        var preHadNonEmpty:Boolean = false;
        var postHasNonEmpty:Boolean = false;
        var brokeThisUpdate:Boolean = false;

        var watchRechargeStart:Boolean = (this.onRechargeStartCallback != null);
        var watchRechargeFull:Boolean = (this.onRechargeFullCallback != null);
        var watchExpire:Boolean = (this.onExpireCallback != null);
        var watchBreak:Boolean = (this.onBreakCallback != null);

        // ========== Phase 1: 遍历更新，收集待弹出护盾 ==========
        // 延迟初始化 ejectedList，大多数帧无护盾弹出
        var ejectedList:Array = null;
        var tail:Number = len;

        // Phase 1/2 期间加锁：子盾回调里若修改结构，将自动排队到 Phase 2 之后执行
        this._lockStructure();
        for (var i:Number = len - 1; i >= 0; i--) {
            var shield:IShield = arr[i];

            // 预状态采样（仅在需要时采样，避免不必要开销）
            if (!preHadNonEmpty && shield.isActive() && !shield.isEmpty()) {
                preHadNonEmpty = true;
            }

            var preCap:Number = 0;
            var preTarget:Number = 0;
            var preMax:Number = 0;
            if (watchRechargeFull || watchBreak) {
                preCap = shield.getCapacity();
                preMax = shield.getMaxCapacity();
                preTarget = shield.getTargetCapacity();
                if (preTarget > preMax) preTarget = preMax;
                if (preTarget < 0) preTarget = 0;
            }

            var preDelayed:Boolean = false;
            if (watchRechargeStart && shield instanceof BaseShield) {
                preDelayed = BaseShield(shield).isDelayed();
            }

            var checkExpire:Boolean = false;
            var preDuration:Number = 0;
            if (watchExpire && shield instanceof Shield) {
                var s0:Shield = Shield(shield);
                preDuration = s0.getDuration();
                checkExpire = (s0.isTemporary() && preDuration > 0);
            }

            if (shield.update(deltaTime)) {
                changed = true;
            }

            // 事件检测：充能开始/充能完毕/过期/击碎
            if (watchRechargeStart && preDelayed && shield instanceof BaseShield) {
                if (!BaseShield(shield).isDelayed()) {
                    rechargeStartTriggered = true;
                }
            }

            if (watchRechargeFull || watchBreak) {
                var postCap:Number = shield.getCapacity();
                if (preCap < preTarget && postCap >= preTarget) {
                    rechargeFullTriggered = true;
                }
                if (preCap > 0 && postCap <= 0) {
                    brokeThisUpdate = true;
                }
            }

            if (checkExpire) {
                var postDuration:Number = Shield(shield).getDuration();
                if (preDuration > 0 && postDuration <= 0) {
                    if (expiredList == null) expiredList = [];
                    expiredList.push(shield);
                }
            }

            if (!postHasNonEmpty && shield.isActive() && !shield.isEmpty()) {
                postHasNonEmpty = true;
            }

            if (!shield.isActive()) {
                // 交换到尾部待删除区
                tail--;
                arr[i] = arr[tail];
                changed = true;

                // 收集待弹出护盾（延迟初始化）
                if (ejectedList == null) ejectedList = [];
                ejectedList.push(shield);
            }
        }

        // ========== Phase 2: 统一截断数组 ==========
        if (tail < len) {
            arr.length = tail;
            this._needsSort = true;
        }

        // Phase 2 完成后解锁并应用排队的结构修改
        this._unlockStructure();

        if (changed) {
            this._cacheValid = false;
        }

        // ========== 容器级回调派发（结构稳定后触发，允许回调安全修改结构） ==========
        // 1) 过期回调（先于 ejected）
        if (watchExpire && expiredList != null && this.onExpireCallback != null) {
            var expLen:Number = expiredList.length;
            for (var e:Number = 0; e < expLen; e++) {
                this.onExpireCallback(this);
            }
        }

        // 2) 充能开始/充能满（栈模式也应对外触发）
        if (rechargeStartTriggered && this.onRechargeStartCallback != null) {
            this.onRechargeStartCallback(this);
        }
        if (rechargeFullTriggered && this.onRechargeFullCallback != null) {
            this.onRechargeFullCallback(this);
        }

        // 3) update 路径的击碎（主要覆盖“衰减归零”场景；过期不触发）
        if (watchBreak && brokeThisUpdate && preHadNonEmpty && !postHasNonEmpty) {
            if (this.onBreakCallback != null) {
                this.onBreakCallback(this);
            }
        }

        // ========== Phase 3: 触发 ejected 回调（结构已稳定） ==========
        var ejectedCb:Function = this.onShieldEjectedCallback;
        if (ejectedList != null && ejectedCb != null) {
            var ejectedLen:Number = ejectedList.length;
            for (var j:Number = 0; j < ejectedLen; j++) {
                ejectedCb(ejectedList[j], this);
            }
        }

        // ========== Phase 4: 重新评估状态（回调可能修改了结构） ==========
        // 重新读取数组引用和长度，因为回调可能调用了 clear() 导致 _shields = null
        arr = this._shields;
        var finalLen:Number = (arr != null) ? arr.length : 0;

        if (finalLen == 0) {
            // 降级到空壳模式（如果尚未降级）
            if (this._mode != MODE_DORMANT) {
                this._shields = null;
                this._bindDormantMethods();
                this._downgradeCounter = 0;
            }
            // 触发全部耗尽回调
            if (this.onAllShieldsDepletedCallback != null) {
                this.onAllShieldsDepletedCallback(this);
            }
            return true;
        } else if (finalLen == 1 && this._canDowngrade()) {
            // 降级迟滞检查（仅限可降级类型）
            this._downgradeCounter++;
            if (this._downgradeCounter >= DOWNGRADE_HYSTERESIS) {
                this._downgradeToSingleMode();
            }
        } else {
            this._downgradeCounter = 0;
        }

        return changed;
    }

    private function _stack_onHit(absorbed:Number):Void {
        // 栈模式下由内部护盾各自处理
    }

    private function _stack_onBreak():Void {
        // 检查是否真的全部耗尽
        if (this._stack_isEmpty()) {
            // 先降级到空壳模式，这样回调中的 addShield 可以正常工作
            this._shields = null;
            this._bindDormantMethods();
            this._downgradeCounter = 0;
            // 然后触发全部耗尽回调
            if (this.onAllShieldsDepletedCallback != null) {
                this.onAllShieldsDepletedCallback(this);
            }
        }
    }

    private function _stack_onRechargeStart():Void {
        // 栈模式级别的回调，通常不使用
    }

    private function _stack_onRechargeFull():Void {
        // 栈模式级别的回调，通常不使用
    }

    private function _stack_getCapacity():Number {
        this._stack_updateCache();
        return this._cachedCapacity;
    }

    private function _stack_getMaxCapacity():Number {
        this._stack_updateCache();
        return this._cachedMaxCapacity;
    }

    private function _stack_getTargetCapacity():Number {
        this._stack_updateCache();
        return this._cachedTargetCapacity;
    }

    private function _stack_getStrength():Number {
        this._stack_updateCache();
        return this._cachedStrength;
    }

    private function _stack_getRechargeRate():Number {
        var total:Number = 0;
        var arr:Array = this._shields;
        var len:Number = arr.length;
        for (var i:Number = 0; i < len; i++) {
            var s:IShield = arr[i];
            if (s.isActive()) {
                total += s.getRechargeRate();
            }
        }
        return total;
    }

    private function _stack_getRechargeDelay():Number {
        var maxDelay:Number = 0;
        var arr:Array = this._shields;
        var len:Number = arr.length;
        for (var i:Number = 0; i < len; i++) {
            var s:IShield = arr[i];
            if (s.isActive()) {
                var delay:Number = s.getRechargeDelay();
                if (delay > maxDelay) maxDelay = delay;
            }
        }
        return maxDelay;
    }

    private function _stack_isEmpty():Boolean {
        var arr:Array = this._shields;
        var len:Number = arr.length;
        for (var i:Number = 0; i < len; i++) {
            var s:IShield = arr[i];
            if (s.isActive() && !s.isEmpty()) {
                return false;
            }
        }
        return true;
    }

    private function _stack_getResistantCount():Number {
        this._stack_updateCache();
        return this._resistantCount;
    }

    private function _stack_getSortPriority():Number {
        this._stack_sortShields();

        var arr:Array = this._shields;
        if (arr.length > 0) {
            return IShield(arr[0]).getSortPriority();
        }
        return 0;
    }

    // ==================== 扩展属性访问器 ====================

    public function getName():String {
        // 委托模式：从内部护盾获取
        if (this._mode == MODE_SINGLE && !this._singleFlattened && this._singleShield instanceof Shield) {
            return Shield(this._singleShield).getName();
        }
        // 扁平化模式或其他：返回容器字段
        return this._name;
    }

    public function setName(value:String):Void {
        this._name = value;
        // 委托模式：同步到内部护盾
        if (this._mode == MODE_SINGLE && !this._singleFlattened && this._singleShield instanceof Shield) {
            Shield(this._singleShield).setName(value);
        }
    }

    public function getType():String {
        if (this._mode == MODE_SINGLE && !this._singleFlattened && this._singleShield instanceof Shield) {
            return Shield(this._singleShield).getType();
        }
        return this._type;
    }

    public function setType(value:String):Void {
        this._type = value;
        if (this._mode == MODE_SINGLE && !this._singleFlattened && this._singleShield instanceof Shield) {
            Shield(this._singleShield).setType(value);
        }
    }

    public function isTemporary():Boolean {
        if (this._mode == MODE_SINGLE && !this._singleFlattened && this._singleShield instanceof Shield) {
            return Shield(this._singleShield).isTemporary();
        }
        return this._isTemporary;
    }

    public function setTemporary(value:Boolean):Void {
        this._isTemporary = value;
        if (this._mode == MODE_SINGLE && !this._singleFlattened && this._singleShield instanceof Shield) {
            Shield(this._singleShield).setTemporary(value);
        }
    }

    public function getDuration():Number {
        if (this._mode == MODE_SINGLE && !this._singleFlattened && this._singleShield instanceof Shield) {
            return Shield(this._singleShield).getDuration();
        }
        return this._duration;
    }

    public function setDuration(value:Number):Void {
        this._duration = value;
        if (this._mode == MODE_SINGLE && !this._singleFlattened && this._singleShield instanceof Shield) {
            Shield(this._singleShield).setDuration(value);
        }
    }

    public function getId():Number {
        return this._id;
    }

    public function getOwner():Object {
        return this._owner;
    }

    public function setOwner(value:Object):Void {
        this._owner = value;
        // 委托模式：通过接口同步到内部护盾
        if (this._mode == MODE_SINGLE && !this._singleFlattened && this._singleShield != null) {
            this._singleShield.setOwner(value);
        }

        // 栈模式：通过接口更新所有子护盾
        if (this._mode == MODE_STACK && this._shields != null) {
            var arr:Array = this._shields;
            var len:Number = arr.length;
            for (var i:Number = 0; i < len; i++) {
                IShield(arr[i]).setOwner(value);
            }
        }

        // 绑定 owner 后触发立场抗性同步
        this._syncStanceResistance();
    }

    // ==================== 立场抗性派生字段同步 ====================

    /**
     * 同步立场抗性派生字段（内部使用）
     *
     * 【设计目的】
     * 单位的魔法抗性["立场"]作为派生字段，由护盾系统维护：
     * - 空壳模式：delete该字段（破击逻辑正确识别为"无抗性"）
     * - 非空壳模式：基础抗性 + 护盾强度加成
     *
     * 仅当值实际变化时才写回，避免热路径重复点链写入。
     */
    private function _syncStanceResistance():Void {
        var owner:Object = this._owner;
        if (!owner || !owner.魔法抗性) return;

        var resistTbl:Object = owner.魔法抗性;
        var mode:Number = this._mode;

        if (mode == MODE_DORMANT) {
            // 空壳模式：删除立场抗性
            if (this._lastSyncedMode != MODE_DORMANT) {
                delete resistTbl["立场"];
                this._lastSyncedMode = MODE_DORMANT;
                this._lastSyncedStrength = 0;
                this._lastSyncedBaseResist = 0;
            }
        } else {
            // 非空壳模式：计算并写入立场抗性
            var strength:Number = this.getStrength();
            var baseResist:Number = resistTbl["基础"];
            if (baseResist == undefined || isNaN(baseResist)) {
                baseResist = 0;
            }

            // 仅当值变化时才写回
            if (mode != this._lastSyncedMode ||
                strength != this._lastSyncedStrength ||
                baseResist != this._lastSyncedBaseResist) {

                var bonus:Number = ShieldUtil.calcResistanceBonus(strength);
                resistTbl["立场"] = baseResist + bonus;

                this._lastSyncedMode = mode;
                this._lastSyncedStrength = strength;
                this._lastSyncedBaseResist = baseResist;
            }
        }
    }

    /**
     * 公开的强制刷新方法（供外部调用）
     *
     * 【使用场景】
     * 当单位的魔法抗性表被重建/改写时（如 DressupInitializer.updateProperties），
     * 外部代码应调用此方法触发立场抗性派生字段的重新计算。
     */
    public function refreshStanceResistance():Void {
        // 强制重新同步
        this._lastSyncedMode = -1;
        this._syncStanceResistance();
    }

    public function setActive(value:Boolean):Void {
        this._isActive = value;
    }

    public function getResistBypass():Boolean {
        // 委托模式：从内部护盾获取
        if (this._mode == MODE_SINGLE && !this._singleFlattened && this._singleShield instanceof BaseShield) {
            return BaseShield(this._singleShield).getResistBypass();
        }
        return this._resistBypass;
    }

    public function setResistBypass(value:Boolean):Void {
        this._resistBypass = value;
        // 委托模式：同步到内部护盾
        if (this._mode == MODE_SINGLE && !this._singleFlattened && this._singleShield instanceof BaseShield) {
            BaseShield(this._singleShield).setResistBypass(value);
        }
    }

    public function isDelayed():Boolean {
        // 委托模式：从内部护盾获取
        if (this._mode == MODE_SINGLE && !this._singleFlattened && this._singleShield instanceof BaseShield) {
            return BaseShield(this._singleShield).isDelayed();
        }
        return this._isDelayed;
    }

    public function getDelayTimer():Number {
        // 委托模式：从内部护盾获取
        if (this._mode == MODE_SINGLE && !this._singleFlattened && this._singleShield instanceof BaseShield) {
            return BaseShield(this._singleShield).getDelayTimer();
        }
        return this._delayTimer;
    }

    /**
     * 设置延迟状态。
     * 用于状态迁移场景。
     *
     * @param isDelayed 是否处于延迟状态
     * @param delayTimer 剩余延迟帧数
     */
    public function setDelayState(isDelayed:Boolean, delayTimer:Number):Void {
        if (this._mode == MODE_SINGLE) {
            if (this._singleFlattened) {
                // 扁平化模式：直接设置容器字段
                this._isDelayed = isDelayed;
                // 与 BaseShield.setDelayState 一致：delayTimer 钳位到 [0, rechargeDelay]
                if (isNaN(delayTimer) || delayTimer < 0) {
                    delayTimer = 0;
                } else if (delayTimer > this._rechargeDelay) {
                    delayTimer = this._rechargeDelay;
                }
                this._delayTimer = delayTimer;
            } else if (this._singleShield instanceof BaseShield) {
                // 委托模式：设置内部护盾
                BaseShield(this._singleShield).setDelayState(isDelayed, delayTimer);
            }
        }
        // 栈模式下不支持直接设置
    }

    /**
     * 获取当前模式。
     * @return Number MODE_SINGLE(0) 或 MODE_STACK(1)
     */
    public function getMode():Number {
        return this._mode;
    }

    /**
     * 检查是否处于空壳模式。
     * 空壳模式下护盾不参与逻辑，等待外部推入护盾。
     */
    public function isDormantMode():Boolean {
        return this._mode == MODE_DORMANT;
    }

    /**
     * 检查是否处于单盾模式。
     */
    public function isSingleMode():Boolean {
        return this._mode == MODE_SINGLE;
    }

    /**
     * 检查是否处于栈模式。
     */
    public function isStackMode():Boolean {
        return this._mode == MODE_STACK;
    }

    /**
     * 检查是否有抵抗绕过的护盾。
     * @return Boolean 是否有抵抗绕过的护盾
     */
    public function hasResistantShield():Boolean {
        return this.getResistantCount() > 0;
    }

    // ==================== 单盾模式属性设置器 ====================

    /**
     * 设置当前容量。
     * 扁平化模式下与 BaseShield 保持一致的钳位行为：
     * - NaN 被忽略（保持原值）
     * - 负数钳位到 0
     * - 超过 maxCapacity 钳位到 maxCapacity
     */
    public function setCapacity(value:Number):Void {
        // NaN 保护：统一在入口处过滤，避免污染任何模式
        if (isNaN(value)) return;

        if (this._mode == MODE_SINGLE) {
            if (this._singleFlattened) {
                // 与 BaseShield.setCapacity 一致的钳位逻辑
                if (value < 0) value = 0;
                else if (value > this._maxCapacity) value = this._maxCapacity;
                this._capacity = value;
            } else if (this._singleShield instanceof BaseShield) {
                BaseShield(this._singleShield).setCapacity(value);
            }
        }
        // 栈模式下不支持直接设置
    }

    /**
     * 设置最大容量。
     * 扁平化模式下与 BaseShield 保持一致的行为：
     * - 如果当前容量超过新的最大容量，同步调整容量
     */
    public function setMaxCapacity(value:Number):Void {
        // NaN 保护：统一在入口处过滤
        if (isNaN(value)) return;

        if (this._mode == MODE_SINGLE) {
            if (this._singleFlattened) {
                // 与 BaseShield.setMaxCapacity 一致的逻辑
                this._maxCapacity = value;
                if (this._capacity > value) {
                    this._capacity = value;
                }
                // 维持不变量：targetCapacity 不应超过 maxCapacity
                if (this._targetCapacity > value) {
                    this._targetCapacity = value;
                }
            } else if (this._singleShield instanceof BaseShield) {
                BaseShield(this._singleShield).setMaxCapacity(value);
            }
        }
    }

    public function setTargetCapacity(value:Number):Void {
        // NaN 保护：统一在入口处过滤
        if (isNaN(value)) return;

        if (this._mode == MODE_SINGLE) {
            if (this._singleFlattened) {
                // 与 BaseShield.setTargetCapacity 一致的钳位逻辑
                if (value < 0) value = 0;
                else if (value > this._maxCapacity) value = this._maxCapacity;
                this._targetCapacity = value;
            } else if (this._singleShield instanceof BaseShield) {
                BaseShield(this._singleShield).setTargetCapacity(value);
            }
        }
    }

    public function setStrength(value:Number):Void {
        // NaN 保护：统一在入口处过滤
        if (isNaN(value)) return;

        if (this._mode == MODE_SINGLE) {
            if (this._singleFlattened) {
                this._strength = value;
                // 强度变化时同步立场抗性
                this._syncStanceResistance();
            } else if (this._singleShield instanceof BaseShield) {
                BaseShield(this._singleShield).setStrength(value);
            }
        }
    }

    public function setRechargeRate(value:Number):Void {
        // NaN 保护：统一在入口处过滤
        if (isNaN(value)) return;

        if (this._mode == MODE_SINGLE) {
            if (this._singleFlattened) {
                this._rechargeRate = value;
            } else if (this._singleShield instanceof BaseShield) {
                BaseShield(this._singleShield).setRechargeRate(value);
            }
        }
    }

    public function setRechargeDelay(value:Number):Void {
        // NaN 保护：统一在入口处过滤
        if (isNaN(value)) return;

        if (this._mode == MODE_SINGLE) {
            if (this._singleFlattened) {
                this._rechargeDelay = value;
            } else if (this._singleShield instanceof BaseShield) {
                BaseShield(this._singleShield).setRechargeDelay(value);
            }
        }
    }

    // ==================== 回调注册 ====================

    /**
     * 批量设置事件回调。
     *
     * @param callbacks 包含回调函数的对象
     * @return AdaptiveShield 返回自身，支持链式调用
     */
    public function setCallbacks(callbacks:Object):AdaptiveShield {
        if (callbacks == null) return this;

        if (callbacks.onHit != undefined) {
            this.onHitCallback = callbacks.onHit;
        }
        if (callbacks.onBreak != undefined) {
            this.onBreakCallback = callbacks.onBreak;
        }
        if (callbacks.onRechargeStart != undefined) {
            this.onRechargeStartCallback = callbacks.onRechargeStart;
        }
        if (callbacks.onRechargeFull != undefined) {
            this.onRechargeFullCallback = callbacks.onRechargeFull;
        }
        if (callbacks.onExpire != undefined) {
            this.onExpireCallback = callbacks.onExpire;
        }
        if (callbacks.onShieldEjected != undefined) {
            this.onShieldEjectedCallback = callbacks.onShieldEjected;
        }
        if (callbacks.onAllShieldsDepleted != undefined) {
            this.onAllShieldsDepletedCallback = callbacks.onAllShieldsDepleted;
        }

        return this;
    }

    // ==================== 工具方法 ====================

    /**
     * 重置护盾到满状态。
     * 同时将 _isActive 重置为 true。
     */
    public function reset():Void {
        if (this._mode == MODE_STACK) {
            // 栈模式下重置所有子护盾
            var arr:Array = this._shields;
            var len:Number = arr.length;
            for (var i:Number = 0; i < len; i++) {
                var s:Object = arr[i];
                if (s instanceof BaseShield) {
                    BaseShield(s).reset();
                }
            }
            this._cacheValid = false;
        } else if (this._mode == MODE_SINGLE) {
            if (this._singleFlattened) {
                // 扁平化模式：直接重置容器字段
                this._capacity = this._maxCapacity;
                this._targetCapacity = this._maxCapacity;
                this._delayTimer = 0;
                this._isDelayed = false;
            } else if (this._singleShield instanceof BaseShield) {
                // 委托模式：重置内部护盾
                BaseShield(this._singleShield).reset();
            }
        }
        // 空壳模式无需重置
        this._isActive = true;
    }

    /**
     * 强制标记排序无效（栈模式）。
     */
    public function invalidateSort():Void {
        if (this._mode == MODE_STACK) {
            this._needsSort = true;
            this._cacheValid = false;
        }
    }

    /**
     * 强制标记缓存无效（栈模式）。
     */
    public function invalidateCache():Void {
        if (this._mode == MODE_STACK) {
            this._cacheValid = false;
        }
    }

    /**
     * 返回护盾状态的字符串表示。
     */
    public function toString():String {
        if (this._mode == MODE_DORMANT) {
            return "AdaptiveShield[DORMANT, " + this._name + ", active=" + this._isActive + "]";
        } else if (this._mode == MODE_SINGLE) {
            var modeStr:String = this._singleFlattened ? "SINGLE-FLAT" : "SINGLE-DELEGATE";
            var innerStr:String = this._singleFlattened ? "(flattened)" : this._singleShield.toString();
            return "AdaptiveShield[" + modeStr + ", " + this._name +
                   ", capacity=" + this.getCapacity() + "/" + this.getMaxCapacity() +
                   ", strength=" + this.getStrength() +
                   ", recharge=" + this.getRechargeRate() +
                   ", active=" + this._isActive +
                   ", inner=" + innerStr + "]";
        } else {
            var arr:Array = this._shields;
            var len:Number = arr.length;
            var result:String = "AdaptiveShield[STACK, count=" + len +
                               ", capacity=" + this.getCapacity() + "/" + this.getMaxCapacity() +
                               ", strength=" + this.getStrength() +
                               ", active=" + this._isActive + "]\n";

            for (var i:Number = 0; i < len; i++) {
                result += "  [" + i + "] " + arr[i].toString() + "\n";
            }

            return result;
        }
    }

    /**
     * 检查是否使用扁平化单盾模式。
     * @return Boolean 扁平化模式返回 true，委托模式返回 false
     */
    public function isFlattenedMode():Boolean {
        return this._mode == MODE_SINGLE && this._singleFlattened;
    }

    /**
     * 检查是否使用委托单盾模式。
     * @return Boolean 委托模式返回 true，扁平化或其他模式返回 false
     */
    public function isDelegateMode():Boolean {
        return this._mode == MODE_SINGLE && !this._singleFlattened;
    }
}
