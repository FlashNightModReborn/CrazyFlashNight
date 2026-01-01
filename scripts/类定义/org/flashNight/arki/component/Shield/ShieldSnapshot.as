// File: org/flashNight/arki/component/Shield/ShieldSnapshot.as

import org.flashNight.arki.component.Shield.*;

/**
 * ShieldSnapshot - 护盾元数据快照
 *
 * 【设计目的】
 * 为 onShieldEjectedCallback 提供类型安全的护盾信息载体。
 * 实现 IShield 接口的只读子集，使回调代码可以统一处理真实护盾和快照。
 *
 * 【使用场景】
 * - 扁平化单盾模式：降级后容器已变空壳，无法读取原护盾属性
 * - 需要保留被弹出护盾的元数据供回调使用
 *
 * 【ID 语义】
 * - getId(): 返回被弹出护盾的层 ID（用于识别/对账）
 * - getContainerId(): 返回所属容器的 ID
 *
 * 【只读契约】
 * 所有修改操作（absorbDamage、consumeCapacity、update 等）为空实现或返回无效值。
 * 快照仅用于读取元数据，不参与实际护盾逻辑。
 */
class org.flashNight.arki.component.Shield.ShieldSnapshot implements IShield {

    // ==================== 核心元数据 ====================

    /** 层 ID（被弹出护盾的原始 ID） */
    private var _layerId:Number;

    /** 容器 ID（所属 AdaptiveShield 的 ID） */
    private var _containerId:Number;

    /** 护盾名称 */
    private var _name:String;

    /** 护盾类型标签 */
    private var _type:String;

    /** 快照时的容量 */
    private var _capacity:Number;

    /** 最大容量 */
    private var _maxCapacity:Number;

    /** 目标容量 */
    private var _targetCapacity:Number;

    /** 护盾强度 */
    private var _strength:Number;

    /** 填充速度 */
    private var _rechargeRate:Number;

    /** 填充延迟 */
    private var _rechargeDelay:Number;

    /** 是否为临时盾 */
    private var _isTemporary:Boolean;

    /** 是否抵抗绕过 */
    private var _resistBypass:Boolean;

    /** 快照时的 owner 引用 */
    private var _owner:Object;

    // ==================== 构造函数 ====================

    /**
     * 创建护盾快照。
     *
     * @param layerId 层 ID（被弹出护盾的 ID）
     * @param containerId 容器 ID
     * @param name 护盾名称
     * @param type 护盾类型
     * @param capacity 当前容量
     * @param maxCapacity 最大容量
     * @param targetCapacity 目标容量
     * @param strength 护盾强度
     * @param rechargeRate 填充速度
     * @param rechargeDelay 填充延迟
     * @param isTemporary 是否临时盾
     * @param resistBypass 是否抵抗绕过
     * @param owner 快照时的 owner 引用
     */
    public function ShieldSnapshot(
        layerId:Number,
        containerId:Number,
        name:String,
        type:String,
        capacity:Number,
        maxCapacity:Number,
        targetCapacity:Number,
        strength:Number,
        rechargeRate:Number,
        rechargeDelay:Number,
        isTemporary:Boolean,
        resistBypass:Boolean,
        owner:Object
    ) {
        this._layerId = layerId;
        this._containerId = containerId;
        this._name = (name == undefined || name == null) ? "Snapshot" : name;
        this._type = (type == undefined || type == null) ? "snapshot" : type;
        this._capacity = isNaN(capacity) ? 0 : capacity;
        this._maxCapacity = isNaN(maxCapacity) ? 0 : maxCapacity;
        this._targetCapacity = isNaN(targetCapacity) ? 0 : targetCapacity;
        this._strength = isNaN(strength) ? 0 : strength;
        this._rechargeRate = isNaN(rechargeRate) ? 0 : rechargeRate;
        this._rechargeDelay = isNaN(rechargeDelay) ? 0 : rechargeDelay;
        this._isTemporary = (isTemporary == true);
        this._resistBypass = (resistBypass == true);
        this._owner = owner;
    }

    // ==================== ID 访问 ====================

    /**
     * 获取层 ID（被弹出护盾的原始 ID）。
     * 用于识别具体是哪个护盾被弹出。
     */
    public function getId():Number {
        return this._layerId;
    }

    /**
     * 获取容器 ID。
     * 用于识别护盾来自哪个 AdaptiveShield。
     */
    public function getContainerId():Number {
        return this._containerId;
    }

    /**
     * 获取护盾名称。
     */
    public function getName():String {
        return this._name;
    }

    /**
     * 获取护盾类型。
     */
    public function getType():String {
        return this._type;
    }

    /**
     * 检查是否为临时盾。
     * 兼容名称：isTemporaryShield
     */
    public function isTemporary():Boolean {
        return this._isTemporary;
    }

    /**
     * 检查是否为临时盾（别名，保持向后兼容）。
     */
    public function isTemporaryShield():Boolean {
        return this._isTemporary;
    }

    // ==================== IShield 只读实现 ====================

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

    /**
     * 快照始终为"空"状态（已被弹出）。
     */
    public function isEmpty():Boolean {
        return true;
    }

    /**
     * 快照始终为"非激活"状态（已被弹出）。
     */
    public function isActive():Boolean {
        return false;
    }

    public function getResistantCount():Number {
        return this._resistBypass ? 1 : 0;
    }

    public function getSortPriority():Number {
        return ShieldUtil.calcSortPriority(this._strength, this._rechargeRate, this._layerId);
    }

    // ==================== 身份与归属 ====================

    /**
     * 获取快照时的 owner 引用。
     */
    public function getOwner():Object {
        return this._owner;
    }

    /**
     * 快照不支持设置 owner（只读契约）。
     * 空操作，维持接口兼容。
     */
    public function setOwner(owner:Object):Void {
        // 快照是只读的，不响应 setOwner
    }

    // ==================== IShield 空操作实现 ====================

    /**
     * 快照不吸收伤害，直接返回原值。
     */
    public function absorbDamage(damage:Number, bypassShield:Boolean, hitCount:Number):Number {
        return damage;
    }

    /**
     * 快照不消耗容量，返回 0。
     */
    public function consumeCapacity(amount:Number):Number {
        return 0;
    }

    /**
     * 快照不更新，返回 false。
     */
    public function update(deltaTime:Number):Boolean {
        return false;
    }

    /**
     * 空操作。
     */
    public function onHit(absorbed:Number):Void {
        // 快照不响应事件
    }

    /**
     * 空操作。
     */
    public function onBreak():Void {
        // 快照不响应事件
    }

    /**
     * 空操作。
     */
    public function onRechargeStart():Void {
        // 快照不响应事件
    }

    /**
     * 空操作。
     */
    public function onRechargeFull():Void {
        // 快照不响应事件
    }

    // ==================== 工厂方法 ====================

    /**
     * 从扁平化 AdaptiveShield 状态创建快照。
     *
     * 【扁平化模式特殊处理】
     * 扁平化模式下容器本身就是"层"，layerId = containerId。
     *
     * @param container 扁平化模式的 AdaptiveShield
     * @return ShieldSnapshot 快照对象
     */
    public static function fromFlattenedContainer(container:AdaptiveShield):ShieldSnapshot {
        var containerId:Number = container.getId();
        return new ShieldSnapshot(
            containerId,  // layerId = containerId（扁平化模式下容器即层）
            containerId,
            container.getName(),
            container.getType(),
            container.getCapacity(),
            container.getMaxCapacity(),
            container.getTargetCapacity(),
            container.getStrength(),
            container.getRechargeRate(),
            container.getRechargeDelay(),
            container.isTemporary(),
            container.getResistantCount() > 0,
            container.getOwner()
        );
    }

    /**
     * 从 IShield 实例创建快照。
     *
     * @param shield 原始护盾
     * @param containerId 所属容器 ID
     * @return ShieldSnapshot 快照对象
     */
    public static function fromShield(shield:IShield, containerId:Number):ShieldSnapshot {
        var layerId:Number = 0;
        var name:String = "Unknown";
        var type:String = "unknown";
        var isTemp:Boolean = false;
        var resistBypass:Boolean = false;
        var owner:Object = null;

        // 尝试获取扩展信息
        // 注意：Shield 继承 BaseShield，需要先检测 Shield
        if (shield instanceof Shield) {
            var s:Shield = Shield(shield);
            layerId = s.getId();
            name = s.getName();
            type = s.getType();
            isTemp = s.isTemporary();
            resistBypass = s.getResistBypass();
            owner = s.getOwner();
        } else if (shield instanceof BaseShield) {
            var bs:BaseShield = BaseShield(shield);
            layerId = bs.getId();
            // BaseShield 没有 getName/getType，使用默认值
            name = "BaseShield";
            type = "base";
            isTemp = false; // BaseShield 无临时盾概念
            resistBypass = bs.getResistBypass();
            owner = bs.getOwner();
        } else if (shield instanceof AdaptiveShield) {
            var as:AdaptiveShield = AdaptiveShield(shield);
            layerId = as.getId();
            name = as.getName();
            type = as.getType();
            isTemp = as.isTemporary();
            resistBypass = as.getResistantCount() > 0;
            owner = as.getOwner();
        } else {
            // 通用 IShield 实现：使用接口方法获取
            layerId = shield.getId();
            owner = shield.getOwner();
        }

        return new ShieldSnapshot(
            layerId,
            containerId,
            name,
            type,
            shield.getCapacity(),
            shield.getMaxCapacity(),
            shield.getTargetCapacity(),
            shield.getStrength(),
            shield.getRechargeRate(),
            shield.getRechargeDelay(),
            isTemp,
            resistBypass,
            owner
        );
    }
}
