// File: org/flashNight/arki/component/Shield/BaseShield.as

import org.flashNight.arki.component.Shield.*;

/**
 * BaseShield 类是护盾系统的抽象基类。
 * 该类实现了 IShield 接口，提供了护盾的核心属性存储和默认行为实现。
 * 子类(如Shield)通过重写方法来实现特定的护盾行为。
 *
 * 【护盾属性说明】
 * - capacity: 当前护盾容量
 * - maxCapacity: 护盾容量上限
 * - targetCapacity: 目标容量(填充恢复到此值)
 * - strength: 护盾强度(过滤伤害阈值)
 * - rechargeRate: 填充速度(正数充能，负数衰减)
 * - rechargeDelay: 填充延迟(受击后等待帧数，仅正充能有效)
 *
 * 【事件回调系统】
 * 支持在创建时或运行时注册事件回调函数：
 * - onHitCallback: 被命中时调用
 * - onBreakCallback: 护盾击碎时调用
 * - onRechargeStartCallback: 开始充能时调用
 * - onRechargeFullCallback: 充能完毕时调用
 *
 * 【时间单位】
 * 所有时间参数均以帧(frame)为单位
 *
 * 【排序优先级计算】
 * sortPriority = strength * 10000 - rechargeRate - id * 0.001
 * 确保强度优先，同强度时填充慢者优先
 */
class org.flashNight.arki.component.Shield.BaseShield implements IShield {

    // ==================== 核心属性 ====================

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

    // ==================== 状态属性 ====================

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

    // ==================== 构造函数 ====================

    /**
     * 构造函数。
     * 初始化护盾的基本属性。
     *
     * @param maxCapacity 最大容量
     * @param strength 护盾强度
     * @param rechargeRate 填充速度(默认0，正数充能，负数衰减)
     * @param rechargeDelay 填充延迟帧数(默认0，仅正充能有效)
     */
    public function BaseShield(
        maxCapacity:Number,
        strength:Number,
        rechargeRate:Number,
        rechargeDelay:Number
    ) {
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
        this._id = BaseShield._idCounter++;

        // 初始化回调为null
        this.onHitCallback = null;
        this.onBreakCallback = null;
        this.onRechargeStartCallback = null;
        this.onRechargeFullCallback = null;
    }

    // ==================== IShield 接口实现 ====================

    /**
     * 吸收伤害并返回穿透值。
     *
     * 【核心逻辑】
     * 1. bypassShield=true 且不抵抗绕过：直接穿透
     * 2. 计算有效强度：effectiveStrength = strength * hitCount
     * 3. absorbed = min(damage, effectiveStrength, capacity)
     * 4. 触发 onHit 事件
     * 5. 返回 damage - absorbed
     *
     * 【联弹支持】
     * hitCount 用于联弹场景(单发子弹模拟多段弹幕)：
     * - 普通子弹传入 1（默认值）
     * - 10段联弹传入 10，强度按10倍计算
     * - 玩家视角：护盾能挡住的"每段伤害"仍是强度值
     *
     * @param damage 输入伤害(联弹为总伤害)
     * @param bypassShield 是否绕过护盾(如真伤)，默认false
     * @param hitCount 命中段数(联弹段数)，默认1
     * @return Number 穿透伤害
     */
    public function absorbDamage(damage:Number, bypassShield:Boolean, hitCount:Number):Number {
        // 绕过护盾检查：bypassShield=true 且护盾不抵抗绕过
        if (bypassShield && !this._resistBypass) {
            return damage;
        }

        // 护盾未激活或已耗尽，伤害全部穿透
        var cap:Number = this._capacity;
        if (!this._isActive || cap <= 0) {
            return damage;
        }

        // hitCount 默认值处理
        if (hitCount == undefined || hitCount < 1) {
            hitCount = 1;
        }

        // 计算有效强度：基础强度 * 段数
        var effectiveStrength:Number = this._strength * hitCount;

        // 计算可吸收量: min(伤害, 有效强度, 剩余容量)
        var absorbable:Number = damage;
        if (absorbable > effectiveStrength) absorbable = effectiveStrength;
        if (absorbable > cap) absorbable = cap;

        // 扣除护盾容量
        this._capacity = cap - absorbable;

        // 触发命中事件
        this.onHit(absorbable);

        // 检查是否击碎
        if (this._capacity <= 0) {
            this._capacity = 0;
            this.onBreak();
        }

        // 返回穿透伤害
        return damage - absorbable;
    }

    // ==================== 容量消耗 ====================

    /**
     * 直接消耗护盾容量（供 ShieldStack 内部调用）。
     *
     * 【与 absorbDamage 的区别】
     * - absorbDamage: 完整的伤害处理流程（强度节流 + 容量消耗 + 事件）
     * - consumeCapacity: 仅消耗容量 + 触发事件（强度节流已在栈级别完成）
     *
     * 【行为】
     * 1. 扣除指定容量（不超过当前容量）
     * 2. 触发 onHit 事件
     * 3. 若容量归零，触发 onBreak 事件
     *
     * @param amount 要消耗的容量
     * @return Number 实际消耗的容量
     */
    public function consumeCapacity(amount:Number):Number {
        var cap:Number = this._capacity;
        if (cap <= 0 || amount <= 0) return 0;

        // 实际消耗量
        var consumed:Number = amount;
        if (consumed > cap) consumed = cap;

        // 扣除容量
        this._capacity = cap - consumed;

        // 触发命中事件
        this.onHit(consumed);

        // 检查是否击碎
        if (this._capacity <= 0) {
            this._capacity = 0;
            this.onBreak();
        }

        return consumed;
    }

    // ==================== 属性访问器 ====================

    public function getCapacity():Number {
        return this._capacity;
    }

    public function getMaxCapacity():Number {
        return this._maxCapacity;
    }

    public function getTargetCapacity():Number {
        return this._targetCapacity;
    }

    public function getStrength():Number {
        return this._strength;
    }

    public function getRechargeRate():Number {
        return this._rechargeRate;
    }

    public function getRechargeDelay():Number {
        return this._rechargeDelay;
    }

    // ==================== 属性设置器 ====================

    /**
     * 设置当前容量。
     * @param value 新容量值
     */
    public function setCapacity(value:Number):Void {
        if (value < 0) value = 0;
        else if (value > this._maxCapacity) value = this._maxCapacity;
        this._capacity = value;
    }

    /**
     * 设置最大容量。
     * @param value 新最大容量
     */
    public function setMaxCapacity(value:Number):Void {
        this._maxCapacity = value;
        if (this._capacity > value) {
            this._capacity = value;
        }
    }

    /**
     * 设置目标容量。
     * @param value 新目标容量
     */
    public function setTargetCapacity(value:Number):Void {
        this._targetCapacity = value;
    }

    /**
     * 设置护盾强度。
     * @param value 新强度值
     */
    public function setStrength(value:Number):Void {
        this._strength = value;
    }

    /**
     * 设置填充速度。
     * @param value 新填充速度(正数充能，负数衰减)
     */
    public function setRechargeRate(value:Number):Void {
        this._rechargeRate = value;
    }

    /**
     * 设置填充延迟。
     * @param value 新延迟帧数
     */
    public function setRechargeDelay(value:Number):Void {
        this._rechargeDelay = value;
    }

    // ==================== 状态查询 ====================

    public function isEmpty():Boolean {
        return this._capacity <= 0;
    }

    public function isActive():Boolean {
        return this._isActive;
    }

    /**
     * 设置护盾激活状态。
     * @param value 激活状态
     */
    public function setActive(value:Boolean):Void {
        this._isActive = value;
    }

    /**
     * 获取护盾唯一ID。
     * @return Number 唯一标识
     */
    public function getId():Number {
        return this._id;
    }

    /**
     * 检查是否处于充能延迟中。
     * @return Boolean 是否延迟中
     */
    public function isDelayed():Boolean {
        return this._isDelayed;
    }

    /**
     * 获取当前延迟剩余帧数。
     * @return Number 剩余延迟帧数
     */
    public function getDelayTimer():Number {
        return this._delayTimer;
    }

    /**
     * 检查是否抵抗绕过。
     * @return Boolean 是否抵抗绕过
     */
    public function getResistBypass():Boolean {
        return this._resistBypass;
    }

    /**
     * 设置是否抵抗绕过。
     * @param value 是否抵抗绕过
     */
    public function setResistBypass(value:Boolean):Void {
        this._resistBypass = value;
    }

    // ==================== 生命周期管理 ====================

    /**
     * 帧更新。
     * 处理填充延迟和容量恢复/衰减。
     *
     * 【正充能护盾】
     * - 延迟期间不充能
     * - 延迟结束后开始充能
     *
     * 【负充能护盾(衰减)】
     * - 不受延迟影响，持续衰减
     *
     * @param deltaTime 帧间隔(通常为1)
     */
    public function update(deltaTime:Number):Void {
        if (!this._isActive) return;

        var rate:Number = this._rechargeRate;

        // 负充能护盾：不受延迟影响，持续衰减
        if (rate < 0) {
            var oldCap:Number = this._capacity;
            var newCap:Number = oldCap + rate * deltaTime;

            if (newCap <= 0) {
                this._capacity = 0;
                if (oldCap > 0) {
                    this.onBreak();
                }
            } else {
                this._capacity = newCap;
            }
            return;
        }

        // 正充能护盾：处理延迟
        if (this._isDelayed) {
            this._delayTimer -= deltaTime;
            if (this._delayTimer <= 0) {
                this._isDelayed = false;
                this._delayTimer = 0;
                this.onRechargeStart();
            }
            return; // 延迟期间不充能
        }

        // 执行充能
        var cap:Number = this._capacity;
        var target:Number = this._targetCapacity;
        if (rate > 0 && cap < target) {
            var oldC:Number = cap;
            cap += rate * deltaTime;

            // 边界检查
            if (cap > target) cap = target;
            var max:Number = this._maxCapacity;
            if (cap > max) cap = max;

            this._capacity = cap;

            // 检查是否充能完毕
            if (oldC < target && cap >= target) {
                this.onRechargeFull();
            }
        }
    }

    /**
     * 护盾被命中事件。
     *
     * 【行为】
     * - 正充能护盾：重置延迟计时器，进入延迟状态
     * - 负充能护盾：不受影响
     *
     * @param absorbed 本次吸收的伤害量
     */
    public function onHit(absorbed:Number):Void {
        // 仅正充能护盾受命中影响
        if (this._rechargeRate > 0 && this._rechargeDelay > 0) {
            this._isDelayed = true;
            this._delayTimer = this._rechargeDelay;
        }

        // 调用外部回调
        if (this.onHitCallback != null) {
            this.onHitCallback(this, absorbed);
        }
    }

    /**
     * 护盾击碎回调。
     */
    public function onBreak():Void {
        if (this.onBreakCallback != null) {
            this.onBreakCallback(this);
        }
    }

    /**
     * 开始充能回调。
     */
    public function onRechargeStart():Void {
        if (this.onRechargeStartCallback != null) {
            this.onRechargeStartCallback(this);
        }
    }

    /**
     * 充能完毕回调。
     */
    public function onRechargeFull():Void {
        if (this.onRechargeFullCallback != null) {
            this.onRechargeFullCallback(this);
        }
    }

    // ==================== 排序支持 ====================

    /**
     * 获取排序优先级。
     *
     * 【排序规则】
     * 1. 强度高者优先 (strength * 10000)
     * 2. 强度相同时，填充速度低者优先 (-rechargeRate)
     * 3. 以上都相同时，ID小者优先 (-id * 0.001)
     *
     * @return Number 排序优先级
     */
    public function getSortPriority():Number {
        return this._strength * 10000 - this._rechargeRate - this._id * 0.001;
    }

    // ==================== 工具方法 ====================

    /**
     * 重置护盾到满状态。
     */
    public function reset():Void {
        this._capacity = this._maxCapacity;
        this._targetCapacity = this._maxCapacity;
        this._delayTimer = 0;
        this._isDelayed = false;
        this._isActive = true;
    }

    /**
     * 返回护盾状态的字符串表示。
     * @return String 状态信息
     */
    public function toString():String {
        return "BaseShield[id=" + this._id +
               ", capacity=" + this._capacity + "/" + this._maxCapacity +
               ", strength=" + this._strength +
               ", recharge=" + this._rechargeRate +
               ", delay=" + this._rechargeDelay +
               ", delayed=" + this._isDelayed +
               ", active=" + this._isActive + "]";
    }
}
