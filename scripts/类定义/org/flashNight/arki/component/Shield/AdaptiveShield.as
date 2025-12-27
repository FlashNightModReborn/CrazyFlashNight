// File: org/flashNight/arki/component/Shield/AdaptiveShield.as
 
import org.flashNight.arki.component.Shield.*;

/**
 * AdaptiveShield - 自适应护盾
 *
 * ============================================================
 * 【设计目标】
 * ============================================================
 * 绝大多数时间走"单盾"热路径（等同 Shield 的调用成本与逻辑）。
 * 需要叠盾时走"栈"路径（等同 ShieldStack 的调用成本与逻辑）。
 * 结构切换仅在"加/减层"发生，战斗热路径无分支判断。
 *
 * ============================================================
 * 【核心机制：实例级方法替换】
 * ============================================================
 * 采用 AS2 实例级方法覆盖实现零代理开销：
 * - 直接将 this.absorbDamage/update/getCapacity/... 替换为单盾或栈实现
 * - 外部调用 shield.absorbDamage() 直接进入对应实现，无中间层
 * - 性能与原生 Shield/ShieldStack 完全一致
 *
 * 切换时机：
 * - addShield() 使 layerCount 从 1 变为 >1：升级到 StackMode
 * - update() 后 layerCount 降为 1（仅限 Shield/BaseShield 类型）：降级到 SingleMode（带迟滞）
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
 * 【全耗尽行为】
 * ============================================================
 * 当所有护盾层耗尽（栈模式）或单盾容量归零（临时盾）时：
 * - _isActive 被设为 false
 * - 后续 absorbDamage() 将直接穿透
 * - 若需继续接收新盾，外部需调用 setActive(true) 或 clear() 重置
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
 * 仅当栈中最后一层为 Shield 或 BaseShield 时才允许降级。
 * 若最后一层为其他 IShield 实现（如嵌套 ShieldStack），则保持栈模式不降级，
 * 以避免语义丢失（如 getResistantCount 等）。
 *
 * ============================================================
 * 【与现有实现的一致性保证】
 * ============================================================
 * - SingleMode 下的 absorbDamage/update 逻辑逐句等价 Shield
 * - StackMode 下的 absorbDamage/update 逻辑逐句等价 ShieldStack
 * - 字段语义、事件触发时机、边界行为完全一致
 */
class org.flashNight.arki.component.Shield.AdaptiveShield implements IShield {

    // ==================== 模式常量 ====================

    /** 单盾模式 */
    private static var MODE_SINGLE:Number = 0;

    /** 栈模式 */
    private static var MODE_STACK:Number = 1;

    /** 降级迟滞帧数（连续保持单层多少帧才降级） */
    private static var DOWNGRADE_HYSTERESIS:Number = 30;

    // ==================== 当前模式 ====================

    /** 当前模式：MODE_SINGLE 或 MODE_STACK */
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

    // ==================== 共享字段 ====================

    /** 所属单位引用 */
    private var _owner:Object;

    /** 全局ID计数器 */
    private static var _idCounter:Number = 0;

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

    /** 护盾被弹出时的回调（栈模式）function(shield:IShield, stack:AdaptiveShield):Void */
    public var onShieldEjectedCallback:Function;

    /** 所有护盾耗尽时的回调（栈模式）function(stack:AdaptiveShield):Void */
    public var onAllShieldsDepletedCallback:Function;

    // ==================== 构造函数 ====================

    /**
     * 构造函数。
     * 初始化为单盾模式。
     *
     * @param maxCapacity 最大容量
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
        // 初始化单盾模式字段（等价 Shield 构造）
        this._maxCapacity = (maxCapacity == undefined || isNaN(maxCapacity)) ? 100 : maxCapacity;
        this._capacity = this._maxCapacity;
        this._targetCapacity = this._maxCapacity;
        this._strength = (strength == undefined || isNaN(strength)) ? 50 : strength;
        this._rechargeRate = (rechargeRate == undefined || isNaN(rechargeRate)) ? 0 : rechargeRate;
        this._rechargeDelay = (rechargeDelay == undefined || isNaN(rechargeDelay)) ? 0 : rechargeDelay;

        this._delayTimer = 0;
        this._isDelayed = false;
        this._isActive = true;
        this._resistBypass = false;
        this._id = AdaptiveShield._idCounter++;
        this._owner = null;

        this._name = (name == undefined || name == null) ? "AdaptiveShield" : name;
        this._type = (type == undefined || type == null) ? "adaptive" : type;
        this._isTemporary = false;
        this._duration = -1;

        // 初始化栈模式字段（预分配，但不使用）
        this._shields = null; // 延迟分配
        this._needsSort = false;
        this._cachedStrength = 0;
        this._resistantCount = 0;
        this._cachedCapacity = 0;
        this._cachedMaxCapacity = 0;
        this._cachedTargetCapacity = 0;
        this._cacheValid = false;

        // 初始化回调为null
        this.onHitCallback = null;
        this.onBreakCallback = null;
        this.onRechargeStartCallback = null;
        this.onRechargeFullCallback = null;
        this.onExpireCallback = null;
        this.onShieldEjectedCallback = null;
        this.onAllShieldsDepletedCallback = null;

        // 初始化为单盾模式
        this._mode = MODE_SINGLE;
        this._downgradeCounter = 0;
        this._bindSingleMethods();
    }

    // ==================== 工厂方法 ====================

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
        shield._isTemporary = true;
        shield._duration = (duration == undefined || isNaN(duration)) ? -1 : duration;
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
        shield._isTemporary = false;
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
        shield._isTemporary = true;
        shield._duration = (duration == undefined || isNaN(duration)) ? -1 : duration;
        shield._resistBypass = true;
        return shield;
    }

    // ==================== 实例级方法绑定（核心） ====================

    /**
     * 绑定单盾模式方法到实例。
     * 直接覆盖实例的公有方法，消除代理开销。
     */
    private function _bindSingleMethods():Void {
        this._mode = MODE_SINGLE;

        // 直接将实例方法替换为单盾实现
        this.absorbDamage = this._single_absorbDamage;
        this.consumeCapacity = this._single_consumeCapacity;
        this.update = this._single_update;
        this.getCapacity = this._single_getCapacity;
        this.getMaxCapacity = this._single_getMaxCapacity;
        this.getTargetCapacity = this._single_getTargetCapacity;
        this.getStrength = this._single_getStrength;
        this.getRechargeRate = this._single_getRechargeRate;
        this.getRechargeDelay = this._single_getRechargeDelay;
        this.isEmpty = this._single_isEmpty;
        this.getResistantCount = this._single_getResistantCount;
        this.getSortPriority = this._single_getSortPriority;
        this.onHit = this._single_onHit;
        this.onBreak = this._single_onBreak;
        this.onRechargeStart = this._single_onRechargeStart;
        this.onRechargeFull = this._single_onRechargeFull;
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
    }

    /**
     * 从单盾模式升级到栈模式。
     * 将当前单盾状态包装为 Shield 对象加入栈。
     *
     * 【延迟状态精确迁移】
     * 通过直接访问内部字段确保延迟计时器精确迁移。
     */
    private function _upgradeToStackMode():Void {
        // 创建内部 Shield 来持有当前单盾状态
        var innerShield:Shield = new Shield(
            this._maxCapacity,
            this._strength,
            this._rechargeRate,
            this._rechargeDelay,
            this._name,
            this._type
        );

        // 迁移基础状态
        innerShield.setCapacity(this._capacity);
        innerShield.setTargetCapacity(this._targetCapacity);
        innerShield.setActive(this._isActive);
        innerShield.setResistBypass(this._resistBypass);
        innerShield.setTemporary(this._isTemporary);
        innerShield.setDuration(this._duration);
        innerShield.setOwner(this._owner);

        // 精确迁移延迟状态（使用公有方法）
        innerShield.setDelayState(this._isDelayed, this._delayTimer);

        // 初始化栈
        this._shields = [innerShield];
        this._needsSort = false;
        this._cacheValid = false;

        // 切换方法
        this._bindStackMethods();
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
     * 将栈中唯一的护盾状态回填到单盾字段。
     *
     * 【延迟状态精确回填】
     * 通过直接访问内部字段确保延迟计时器精确回填。
     */
    private function _downgradeToSingleMode():Void {
        var arr:Array = this._shields;
        if (arr == null || arr.length != 1) return;

        var shield:IShield = arr[0];

        // 回填基础状态
        this._capacity = shield.getCapacity();
        this._maxCapacity = shield.getMaxCapacity();
        this._targetCapacity = shield.getTargetCapacity();
        this._strength = shield.getStrength();
        this._rechargeRate = shield.getRechargeRate();
        this._rechargeDelay = shield.getRechargeDelay();

        // 回填扩展状态
        if (shield instanceof Shield) {
            var s:Shield = Shield(shield);
            this._name = s.getName();
            this._type = s.getType();
            this._isTemporary = s.isTemporary();
            this._duration = s.getDuration();
            this._resistBypass = s.getResistBypass();
            // 精确回填延迟状态
            this._isDelayed = s.isDelayed();
            this._delayTimer = s.getDelayTimer();
        } else if (shield instanceof BaseShield) {
            var bs:BaseShield = BaseShield(shield);
            this._resistBypass = bs.getResistBypass();
            // 精确回填延迟状态
            this._isDelayed = bs.isDelayed();
            this._delayTimer = bs.getDelayTimer();
        }

        // 清理栈
        this._shields = null;

        // 切换方法
        this._bindSingleMethods();
        this._downgradeCounter = 0;
    }

    // ==================== 层管理接口（ShieldStack 兼容） ====================

    /**
     * 添加护盾层。
     *
     * @param shield 要添加的护盾
     * @return Boolean 添加成功返回true
     */
    public function addShield(shield:IShield):Boolean {
        if (shield == null) return false;
        if (!shield.isActive()) return false;

        // 如果当前是单盾模式，需要先升级
        if (this._mode == MODE_SINGLE) {
            this._upgradeToStackMode();
        }

        // 添加到栈
        this._shields.push(shield);
        this._needsSort = true;
        this._cacheValid = false;

        // 设置owner
        if (shield instanceof BaseShield) {
            BaseShield(shield).setOwner(this._owner);
        }

        return true;
    }

    /**
     * 从栈中移除指定护盾。
     *
     * @param shield 要移除的护盾
     * @return Boolean 移除成功返回true
     */
    public function removeShield(shield:IShield):Boolean {
        if (this._mode == MODE_SINGLE) return false;

        var arr:Array = this._shields;
        var len:Number = arr.length;
        for (var i:Number = 0; i < len; i++) {
            if (arr[i] === shield) {
                arr.splice(i, 1);
                this._cacheValid = false;
                // 不在这里降级，让 update 处理
                return true;
            }
        }
        return false;
    }

    /**
     * 根据ID移除护盾。
     *
     * @param id 护盾ID
     * @return Boolean 移除成功返回true
     */
    public function removeShieldById(id:Number):Boolean {
        if (this._mode == MODE_SINGLE) return false;

        var arr:Array = this._shields;
        var len:Number = arr.length;
        for (var i:Number = 0; i < len; i++) {
            var s:Object = arr[i];
            if (s instanceof BaseShield && BaseShield(s).getId() == id) {
                arr.splice(i, 1);
                this._cacheValid = false;
                return true;
            }
        }
        return false;
    }

    /**
     * 获取所有护盾层。
     * 单盾模式返回空数组。
     *
     * @return Array 护盾数组的副本
     */
    public function getShields():Array {
        if (this._mode == MODE_SINGLE) {
            return [];
        }
        return this._shields.slice();
    }

    /**
     * 获取护盾层数。
     * 单盾模式返回1。
     *
     * @return Number 当前护盾层数
     */
    public function getShieldCount():Number {
        if (this._mode == MODE_SINGLE) {
            return 1;
        }
        return this._shields.length;
    }

    /**
     * 根据ID获取护盾。
     *
     * @param id 护盾ID
     * @return IShield 护盾实例，不存在返回null
     */
    public function getShieldById(id:Number):IShield {
        if (this._mode == MODE_SINGLE) {
            return (this._id == id) ? this : null;
        }

        var arr:Array = this._shields;
        var len:Number = arr.length;
        for (var i:Number = 0; i < len; i++) {
            var s:Object = arr[i];
            if (s instanceof BaseShield && BaseShield(s).getId() == id) {
                return IShield(s);
            }
        }
        return null;
    }

    /**
     * 清空所有护盾层并重置为单盾模式。
     * 同时将 _isActive 重置为 true，允许继续接收新盾。
     */
    public function clear():Void {
        if (this._mode == MODE_STACK) {
            this._shields = null;
            this._bindSingleMethods();
        }
        // 重置单盾状态
        this._capacity = this._maxCapacity;
        this._targetCapacity = this._maxCapacity;
        this._delayTimer = 0;
        this._isDelayed = false;
        this._isActive = true;  // 重置为激活状态
        this._downgradeCounter = 0;
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

    // ==================== 单盾模式实现（等价 Shield/BaseShield） ====================

    private function _single_absorbDamage(damage:Number, bypassShield:Boolean, hitCount:Number):Number {
        // 绕过护盾检查
        if (bypassShield && !this._resistBypass) {
            return damage;
        }

        // 护盾未激活或已耗尽
        var cap:Number = this._capacity;
        if (!this._isActive || cap <= 0) {
            return damage;
        }

        // hitCount 默认值
        if (hitCount == undefined || hitCount < 1) {
            hitCount = 1;
        }

        // 计算有效强度
        var effectiveStrength:Number = this._strength * hitCount;

        // 计算可吸收量
        var absorbable:Number = damage;
        if (absorbable > effectiveStrength) absorbable = effectiveStrength;
        if (absorbable > cap) absorbable = cap;

        // 扣除容量
        this._capacity = cap - absorbable;

        // 触发命中事件
        this._single_onHit(absorbable);

        // 检查是否击碎
        if (this._capacity <= 0) {
            this._capacity = 0;
            this._single_onBreak_internal();
        }

        return damage - absorbable;
    }

    private function _single_consumeCapacity(amount:Number):Number {
        var cap:Number = this._capacity;
        if (cap <= 0 || amount <= 0) return 0;

        var consumed:Number = amount;
        if (consumed > cap) consumed = cap;

        this._capacity = cap - consumed;

        this._single_onHit(consumed);

        if (this._capacity <= 0) {
            this._capacity = 0;
            this._single_onBreak_internal();
        }

        return consumed;
    }

    private function _single_update(deltaTime:Number):Boolean {
        if (!this._isActive) return false;

        // 处理持续时间（Shield 扩展）
        var dur:Number = this._duration;
        if (this._isTemporary && dur > 0) {
            dur -= deltaTime;
            if (dur <= 0) {
                this._duration = 0;
                this._isActive = false;
                this._single_onExpire();
                return true;
            }
            this._duration = dur;
        }

        var rate:Number = this._rechargeRate;

        // 负充能：持续衰减
        if (rate < 0) {
            var oldCap:Number = this._capacity;
            if (oldCap <= 0) return false;

            var newCap:Number = oldCap + rate * deltaTime;
            if (newCap <= 0) {
                this._capacity = 0;
                this._single_onBreak_internal();
            } else {
                this._capacity = newCap;
            }
            return true;
        }

        // 正充能：处理延迟
        if (this._isDelayed) {
            this._delayTimer -= deltaTime;
            if (this._delayTimer <= 0) {
                this._isDelayed = false;
                this._delayTimer = 0;
                this._single_onRechargeStart();
            }
            return false;
        }

        // 执行充能
        var cap:Number = this._capacity;
        var target:Number = this._targetCapacity;
        if (rate > 0 && cap < target) {
            var oldC:Number = cap;
            cap += rate * deltaTime;

            if (cap > target) cap = target;
            var max:Number = this._maxCapacity;
            if (cap > max) cap = max;

            this._capacity = cap;

            if (oldC < target && cap >= target) {
                this._single_onRechargeFull();
            }
            return true;
        }

        return false;
    }

    private function _single_onHit(absorbed:Number):Void {
        // 仅正充能护盾受命中影响
        if (this._rechargeRate > 0 && this._rechargeDelay > 0) {
            this._isDelayed = true;
            this._delayTimer = this._rechargeDelay;
        }

        if (this.onHitCallback != null) {
            this.onHitCallback(this, absorbed);
        }
    }

    /**
     * 内部击碎处理（区分于公有 onBreak）
     */
    private function _single_onBreak_internal():Void {
        if (this._isTemporary) {
            this._isActive = false;
        }

        if (this.onBreakCallback != null) {
            this.onBreakCallback(this);
        }
    }

    private function _single_onBreak():Void {
        // 与 Shield.onBreak() 保持一致：临时盾设为非激活
        if (this._isTemporary) {
            this._isActive = false;
        }
        if (this.onBreakCallback != null) {
            this.onBreakCallback(this);
        }
    }

    private function _single_onExpire():Void {
        if (this.onExpireCallback != null) {
            this.onExpireCallback(this);
        }
    }

    private function _single_onRechargeStart():Void {
        if (this.onRechargeStartCallback != null) {
            this.onRechargeStartCallback(this);
        }
    }

    private function _single_onRechargeFull():Void {
        if (this.onRechargeFullCallback != null) {
            this.onRechargeFullCallback(this);
        }
    }

    private function _single_getCapacity():Number {
        return this._capacity;
    }

    private function _single_getMaxCapacity():Number {
        return this._maxCapacity;
    }

    private function _single_getTargetCapacity():Number {
        return this._targetCapacity;
    }

    private function _single_getStrength():Number {
        return this._strength;
    }

    private function _single_getRechargeRate():Number {
        return this._rechargeRate;
    }

    private function _single_getRechargeDelay():Number {
        return this._rechargeDelay;
    }

    private function _single_isEmpty():Boolean {
        return this._capacity <= 0;
    }

    private function _single_getResistantCount():Number {
        return this._resistBypass ? 1 : 0;
    }

    private function _single_getSortPriority():Number {
        return this._strength * 10000 - this._rechargeRate - this._id * 0.001;
    }

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
    }

    private function _stack_absorbDamage(damage:Number, bypassShield:Boolean, hitCount:Number):Number {
        if (!this._isActive) {
            return damage;
        }

        this._stack_updateCache();

        var stackStrength:Number = this._cachedStrength;

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

        penetrating += toAbsorb;

        var absorbed:Number = absorbable - toAbsorb;
        if (absorbed > 0) {
            this._cacheValid = false;
        }

        return penetrating;
    }

    private function _stack_consumeCapacity(amount:Number):Number {
        if (!this._isActive || amount <= 0) return 0;

        this._stack_updateCache();

        var arr:Array = this._shields;
        var len:Number = arr.length;
        var toConsume:Number = amount;
        var totalConsumed:Number = 0;

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

        if (totalConsumed > 0) {
            this._cacheValid = false;
        }

        return totalConsumed;
    }

    private function _stack_update(deltaTime:Number):Boolean {
        if (!this._isActive) return false;

        var arr:Array = this._shields;
        var len:Number = arr.length;
        if (len == 0) return false;

        var changed:Boolean = false;
        var ejectedCb:Function = this.onShieldEjectedCallback;

        // 从后向前遍历
        for (var i:Number = len - 1; i >= 0; i--) {
            var shield:IShield = arr[i];

            if (shield.update(deltaTime)) {
                changed = true;
            }

            if (!shield.isActive()) {
                arr.splice(i, 1);
                changed = true;

                if (ejectedCb != null) {
                    ejectedCb(shield, this);
                }
            }
        }

        if (changed) {
            this._cacheValid = false;
        }

        // 检查耗尽和降级条件
        var currentLen:Number = arr.length;
        if (currentLen == 0) {
            // 所有护盾耗尽
            if (this.onAllShieldsDepletedCallback != null) {
                this.onAllShieldsDepletedCallback(this);
            }
            // 切回单盾模式（空状态）
            this._shields = null;
            this._bindSingleMethods();
            this._capacity = 0;
            this._isActive = false;
            return true;
        } else if (currentLen == 1 && this._canDowngrade()) {
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
        return this._name;
    }

    public function setName(value:String):Void {
        this._name = value;
    }

    public function getType():String {
        return this._type;
    }

    public function setType(value:String):Void {
        this._type = value;
    }

    public function isTemporary():Boolean {
        return this._isTemporary;
    }

    public function setTemporary(value:Boolean):Void {
        this._isTemporary = value;
    }

    public function getDuration():Number {
        return this._duration;
    }

    public function setDuration(value:Number):Void {
        this._duration = value;
    }

    public function getId():Number {
        return this._id;
    }

    public function getOwner():Object {
        return this._owner;
    }

    public function setOwner(value:Object):Void {
        this._owner = value;

        // 如果在栈模式，也更新子护盾
        if (this._mode == MODE_STACK && this._shields != null) {
            var arr:Array = this._shields;
            var len:Number = arr.length;
            for (var i:Number = 0; i < len; i++) {
                var s:Object = arr[i];
                if (s instanceof BaseShield) {
                    BaseShield(s).setOwner(value);
                }
            }
        }
    }

    public function setActive(value:Boolean):Void {
        this._isActive = value;
    }

    public function getResistBypass():Boolean {
        return this._resistBypass;
    }

    public function setResistBypass(value:Boolean):Void {
        this._resistBypass = value;
    }

    public function isDelayed():Boolean {
        return this._isDelayed;
    }

    public function getDelayTimer():Number {
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
            this._isDelayed = isDelayed;
            this._delayTimer = delayTimer;
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

    public function setCapacity(value:Number):Void {
        if (this._mode == MODE_SINGLE) {
            if (value < 0) value = 0;
            else if (value > this._maxCapacity) value = this._maxCapacity;
            this._capacity = value;
        }
        // 栈模式下不支持直接设置
    }

    public function setMaxCapacity(value:Number):Void {
        if (this._mode == MODE_SINGLE) {
            this._maxCapacity = value;
            if (this._capacity > value) {
                this._capacity = value;
            }
        }
    }

    public function setTargetCapacity(value:Number):Void {
        if (this._mode == MODE_SINGLE) {
            this._targetCapacity = value;
        }
    }

    public function setStrength(value:Number):Void {
        if (this._mode == MODE_SINGLE) {
            this._strength = value;
        }
    }

    public function setRechargeRate(value:Number):Void {
        if (this._mode == MODE_SINGLE) {
            this._rechargeRate = value;
        }
    }

    public function setRechargeDelay(value:Number):Void {
        if (this._mode == MODE_SINGLE) {
            this._rechargeDelay = value;
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
        } else {
            // 单盾模式
            this._capacity = this._maxCapacity;
            this._targetCapacity = this._maxCapacity;
            this._delayTimer = 0;
            this._isDelayed = false;
        }
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
        if (this._mode == MODE_SINGLE) {
            return "AdaptiveShield[SINGLE, " + this._name +
                   ", capacity=" + this._capacity + "/" + this._maxCapacity +
                   ", strength=" + this._strength +
                   ", recharge=" + this._rechargeRate +
                   ", temporary=" + this._isTemporary +
                   ", duration=" + this._duration +
                   ", active=" + this._isActive + "]";
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
}
