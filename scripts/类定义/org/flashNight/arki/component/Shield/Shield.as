// File: org/flashNight/arki/component/Shield/Shield.as

import org.flashNight.arki.component.Shield.*;

/**
 * Shield 类是具体的护盾实现。
 * 继承自 BaseShield，提供完整的单个护盾功能。
 *
 * 【使用场景】
 * - 角色基础护盾
 * - 技能临时护盾
 * - 装备提供的护盾
 * - 环境效果护盾
 *
 * 【扩展点】
 * 子类可重写以下方法添加自定义行为：
 * - onHit(): 被命中时的特效、音效
 * - onBreak(): 护盾击碎时的特效、音效
 * - onRechargeStart(): 开始回充时的提示
 * - onRechargeFull(): 完全回充时的特效
 * - onExpire(): 临时盾过期时的处理
 * - absorbDamage(): 自定义伤害吸收逻辑(如特定属性免疫)
 *
 * 【护盾强度→属性抗性转换】
 * 使用 ShieldUtil.calcResistanceBonus(strength) 计算
 * 公式: bonus = strength / (strength + 100) * 30
 * 强度100时获得15%额外抗性
 *
 * 【抵抗绕过】
 * 通过 setResistBypass(true) 可使护盾抵抗绕过(如抗真伤)
 *
 * 【回调注册】
 * 支持通过 setCallbacks() 方法批量注册事件回调，便于与外部事件系统交互
 */
class org.flashNight.arki.component.Shield.Shield extends BaseShield {

    // ==================== 扩展属性 ====================

    /** 护盾名称(用于UI显示和调试) */
    private var _name:String;

    /** 护盾类型标签(如"能量盾"、"物理盾") */
    private var _type:String;

    /** 护盾是否为临时盾(耗尽后自动移除) */
    private var _isTemporary:Boolean;

    /** 护盾剩余持续时间(仅临时盾使用，-1表示永久) */
    private var _duration:Number;

    /** 过期事件回调 function(shield:IShield):Void */
    public var onExpireCallback:Function;

    // ==================== 构造函数 ====================

    /**
     * 构造函数。
     *
     * @param maxCapacity 最大容量
     * @param strength 护盾强度
     * @param rechargeRate 填充速度(默认0，正数充能，负数衰减)
     * @param rechargeDelay 填充延迟帧数(默认0)
     * @param name 护盾名称(默认"Shield")
     * @param type 护盾类型(默认"default")
     */
    public function Shield(
        maxCapacity:Number,
        strength:Number,
        rechargeRate:Number,
        rechargeDelay:Number,
        name:String,
        type:String
    ) {
        // 调用父类构造函数
        super(maxCapacity, strength, rechargeRate, rechargeDelay);

        this._name = (name == undefined || name == null) ? "Shield" : name;
        this._type = (type == undefined || type == null) ? "default" : type;
        this._isTemporary = false;
        this._duration = -1;
        this.onExpireCallback = null;
    }

    // ==================== 工厂方法 ====================

    /**
     * 创建一个临时护盾。
     * 临时盾耗尽或持续时间结束后自动标记为非激活。
     *
     * @param maxCapacity 最大容量
     * @param strength 护盾强度
     * @param duration 持续时间帧数(-1为永久直到耗尽)
     * @param name 护盾名称
     * @return Shield 临时护盾实例
     */
    public static function createTemporary(
        maxCapacity:Number,
        strength:Number,
        duration:Number,
        name:String
    ):Shield {
        var shield:Shield = new Shield(maxCapacity, strength, 0, 0, name, "temporary");
        shield._isTemporary = true;
        shield._duration = (duration == undefined || isNaN(duration)) ? -1 : duration;
        return shield;
    }

    /**
     * 创建一个可回充护盾。
     * 适用于角色基础护盾。
     *
     * @param maxCapacity 最大容量
     * @param strength 护盾强度
     * @param rechargeRate 每帧回充量
     * @param rechargeDelay 受击后回充延迟帧数
     * @param name 护盾名称
     * @return Shield 可回充护盾实例
     */
    public static function createRechargeable(
        maxCapacity:Number,
        strength:Number,
        rechargeRate:Number,
        rechargeDelay:Number,
        name:String
    ):Shield {
        var shield:Shield = new Shield(maxCapacity, strength, rechargeRate, rechargeDelay, name, "rechargeable");
        shield._isTemporary = false;
        return shield;
    }

    /**
     * 创建一个衰减护盾。
     * 容量随时间减少，适用于技能增益效果。
     * 衰减护盾不受命中影响，持续衰减。
     *
     * @param maxCapacity 最大容量
     * @param strength 护盾强度
     * @param decayRate 每帧衰减量(正数)
     * @param name 护盾名称
     * @return Shield 衰减护盾实例
     */
    public static function createDecaying(
        maxCapacity:Number,
        strength:Number,
        decayRate:Number,
        name:String
    ):Shield {
        // 衰减用负的填充速度表示
        var rate:Number = decayRate;
        if (rate > 0) rate = -rate;
        var shield:Shield = new Shield(maxCapacity, strength, rate, 0, name, "decaying");
        shield._isTemporary = true;
        return shield;
    }

    /**
     * 创建一个可抗真伤的护盾。
     * 该护盾能抵抗绕过(如真伤)，适用于特殊防护效果。
     *
     * @param maxCapacity 最大容量
     * @param strength 护盾强度
     * @param duration 持续时间帧数(-1为永久直到耗尽)
     * @param name 护盾名称
     * @return Shield 抗真伤护盾实例
     */
    public static function createResistant(
        maxCapacity:Number,
        strength:Number,
        duration:Number,
        name:String
    ):Shield {
        var shield:Shield = new Shield(maxCapacity, strength, 0, 0, name, "resistant");
        shield._isTemporary = true;
        shield._duration = (duration == undefined || isNaN(duration)) ? -1 : duration;
        shield.setResistBypass(true);
        return shield;
    }

    // ==================== 回调注册 ====================

    /**
     * 批量设置事件回调。
     * 便于与外部事件分发器交互。
     *
     * @param callbacks 包含回调函数的对象
     *        {
     *            onHit: function(shield, absorbed),
     *            onBreak: function(shield),
     *            onRechargeStart: function(shield),
     *            onRechargeFull: function(shield),
     *            onExpire: function(shield)
     *        }
     * @return Shield 返回自身，支持链式调用
     */
    public function setCallbacks(callbacks:Object):Shield {
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

        return this;
    }

    // ==================== 扩展属性访问器 ====================

    /**
     * 获取护盾名称。
     * @return String 护盾名称
     */
    public function getName():String {
        return this._name;
    }

    /**
     * 设置护盾名称。
     * @param value 新名称
     */
    public function setName(value:String):Void {
        this._name = value;
    }

    /**
     * 获取护盾类型。
     * @return String 护盾类型
     */
    public function getType():String {
        return this._type;
    }

    /**
     * 设置护盾类型。
     * @param value 新类型
     */
    public function setType(value:String):Void {
        this._type = value;
    }

    // 注：getOwner() 和 setOwner() 已由 BaseShield 提供

    /**
     * 检查是否为临时盾。
     * @return Boolean 是否临时
     */
    public function isTemporary():Boolean {
        return this._isTemporary;
    }

    /**
     * 设置是否为临时盾。
     * @param value 是否临时
     */
    public function setTemporary(value:Boolean):Void {
        this._isTemporary = value;
    }

    /**
     * 获取剩余持续时间。
     * @return Number 剩余帧数，-1表示永久
     */
    public function getDuration():Number {
        return this._duration;
    }

    /**
     * 设置持续时间。
     * @param value 持续时间帧数
     */
    public function setDuration(value:Number):Void {
        this._duration = value;
    }

    // ==================== 生命周期重写 ====================

    /**
     * 帧更新。
     * 扩展父类方法，增加持续时间处理。
     *
     * @param deltaTime 帧间隔(通常为1)
     */
    public function update(deltaTime:Number):Void {
        if (!this.isActive()) return;

        // 处理持续时间
        var dur:Number = this._duration;
        if (this._isTemporary && dur > 0) {
            dur -= deltaTime;
            if (dur <= 0) {
                this._duration = 0;
                this.setActive(false);
                this.onExpire();
                return;
            }
            this._duration = dur;
        }

        // 调用父类更新
        super.update(deltaTime);
    }

    /**
     * 护盾过期回调。
     * 当临时盾持续时间结束时触发。
     */
    public function onExpire():Void {
        if (this.onExpireCallback != null) {
            this.onExpireCallback(this);
        }
    }

    /**
     * 护盾击碎回调。
     * 重写父类方法，临时盾击碎后标记为非激活。
     */
    public function onBreak():Void {
        if (this._isTemporary) {
            this.setActive(false);
        }

        // 调用父类回调
        super.onBreak();
    }

    // ==================== 工具方法 ====================

    /**
     * 返回护盾状态的字符串表示。
     * @return String 状态信息
     */
    public function toString():String {
        return "Shield[" + this._name +
               ", type=" + this._type +
               ", capacity=" + this.getCapacity() + "/" + this.getMaxCapacity() +
               ", strength=" + this.getStrength() +
               ", recharge=" + this.getRechargeRate() +
               ", temporary=" + this._isTemporary +
               ", duration=" + this._duration +
               ", active=" + this.isActive() + "]";
    }
}
