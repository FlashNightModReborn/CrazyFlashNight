// File: org/flashNight/arki/component/Shield/ShieldStack.as

import org.flashNight.arki.component.Shield.*;

/**
 * ShieldStack 类实现护盾栈，管理多个护盾的生命周期。
 *
 * 【设计模式】
 * 采用组合模式(Composite Pattern)，ShieldStack 实现 IShield 接口，
 * 外部调用者可以像操作单个护盾一样操作护盾栈。
 *
 * 【核心职责】
 * - 管理多个护盾的添加、移除
 * - 按优先级排序护盾(强度高→填充慢)
 * - 逐级分发伤害给内部护盾
 * - 自动弹出未激活的护盾
 *
 * 【伤害分发策略】
 * 1. 按排序顺序遍历所有激活护盾
 * 2. 每个护盾吸收 min(剩余伤害, 强度, 容量)
 * 3. 溢出部分(超过强度)不传递给下一层，直接穿透
 * 4. 真伤直接穿透所有护盾
 *
 * 【属性聚合】
 * - getCapacity(): 所有护盾容量之和
 * - getMaxCapacity(): 所有护盾最大容量之和
 * - getStrength(): 最外层活跃护盾的强度
 *
 * 【护盾弹出机制】
 * - update() 时自动检测并移除 isActive() == false 的护盾
 * - 保证护盾栈中只存在激活状态的护盾
 *
 * 【抗性计算】
 * 使用 ShieldUtil.calcResistanceBonus(stack.getStrength()) 计算
 */
class org.flashNight.arki.component.Shield.ShieldStack implements IShield {

    // ==================== 内部数据 ====================

    /** 护盾数组(已按优先级排序) */
    private var _shields:Array;

    /** 是否需要重新排序 */
    private var _needsSort:Boolean;

    /** 护盾栈是否激活 */
    private var _isActive:Boolean;

    /** 所属单位引用 */
    private var _owner:Object;

    // ==================== 事件回调 ====================

    /** 护盾被弹出时的回调 function(shield:IShield, stack:ShieldStack):Void */
    public var onShieldEjectedCallback:Function;

    /** 所有护盾耗尽时的回调 function(stack:ShieldStack):Void */
    public var onAllShieldsDepletedCallback:Function;

    // ==================== 构造函数 ====================

    /**
     * 构造函数。
     * 初始化空的护盾栈。
     */
    public function ShieldStack() {
        this._shields = [];
        this._needsSort = false;
        this._isActive = true;
        this._owner = null;
        this.onShieldEjectedCallback = null;
        this.onAllShieldsDepletedCallback = null;
    }

    // ==================== 护盾管理 ====================

    /**
     * 添加护盾到栈中。
     *
     * @param shield 要添加的护盾
     * @return Boolean 添加成功返回true
     */
    public function addShield(shield:IShield):Boolean {
        if (shield == null) return false;

        // 不添加未激活的护盾
        if (!shield.isActive()) return false;

        this._shields.push(shield);
        this._needsSort = true;

        // 如果是Shield类型，设置owner
        if (shield instanceof Shield) {
            Shield(shield).setOwner(this._owner);
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
        var arr:Array = this._shields;
        var len:Number = arr.length;
        for (var i:Number = 0; i < len; i++) {
            if (arr[i] === shield) {
                arr.splice(i, 1);
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
        var arr:Array = this._shields;
        var len:Number = arr.length;
        for (var i:Number = 0; i < len; i++) {
            var s:Object = arr[i];
            if (s instanceof BaseShield && BaseShield(s).getId() == id) {
                arr.splice(i, 1);
                return true;
            }
        }
        return false;
    }

    /**
     * 获取所有护盾。
     *
     * @return Array 护盾数组的副本
     */
    public function getShields():Array {
        return this._shields.slice();
    }

    /**
     * 获取护盾数量。
     *
     * @return Number 当前护盾数量
     */
    public function getShieldCount():Number {
        return this._shields.length;
    }

    /**
     * 清空所有护盾。
     */
    public function clear():Void {
        this._shields = [];
        this._needsSort = false;
    }

    // ==================== 排序 ====================

    /**
     * 对护盾进行排序。
     * 按 getSortPriority() 降序排列(优先级高的在前)。
     */
    private function sortShields():Void {
        if (!this._needsSort) return;

        var arr:Array = this._shields;
        var len:Number = arr.length;

        // 简单的插入排序，对于小数组效率足够
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

    /**
     * 标记需要重新排序。
     * 当护盾属性变化时调用。
     */
    public function invalidateSort():Void {
        this._needsSort = true;
    }

    // ==================== IShield 接口实现 ====================

    /**
     * 吸收伤害。
     * 逐级将伤害分发给内部护盾。
     *
     * 【伤害分发逻辑】
     * 对于每个护盾:
     * - bypassShield=true 且护盾不抵抗绕过：跳过该护盾
     * - absorbed = min(damage, strength, capacity)
     * - 穿透 = damage - absorbed (超过强度的部分直接穿透)
     *
     * @param damage 输入伤害
     * @param bypassShield 是否绕过护盾(如真伤)，默认false
     * @return Number 穿透所有护盾后剩余的伤害
     */
    public function absorbDamage(damage:Number, bypassShield:Boolean):Number {
        // 护盾栈未激活
        if (!this._isActive) {
            return damage;
        }

        // 确保排序
        this.sortShields();

        var remaining:Number = damage;
        var arr:Array = this._shields;
        var len:Number = arr.length;

        // 遍历所有护盾
        for (var i:Number = 0; i < len && remaining > 0; i++) {
            var shield:IShield = arr[i];

            // 跳过未激活或已耗尽的护盾
            if (!shield.isActive() || shield.isEmpty()) {
                continue;
            }

            // 让护盾吸收伤害
            remaining = shield.absorbDamage(remaining, bypassShield);
        }

        return remaining;
    }

    /**
     * 获取当前总容量。
     * @return Number 所有护盾容量之和
     */
    public function getCapacity():Number {
        var total:Number = 0;
        var arr:Array = this._shields;
        var len:Number = arr.length;
        for (var i:Number = 0; i < len; i++) {
            var s:IShield = arr[i];
            if (s.isActive()) {
                total += s.getCapacity();
            }
        }
        return total;
    }

    /**
     * 获取最大总容量。
     * @return Number 所有护盾最大容量之和
     */
    public function getMaxCapacity():Number {
        var total:Number = 0;
        var arr:Array = this._shields;
        var len:Number = arr.length;
        for (var i:Number = 0; i < len; i++) {
            var s:IShield = arr[i];
            if (s.isActive()) {
                total += s.getMaxCapacity();
            }
        }
        return total;
    }

    /**
     * 获取目标总容量。
     * @return Number 所有护盾目标容量之和
     */
    public function getTargetCapacity():Number {
        var total:Number = 0;
        var arr:Array = this._shields;
        var len:Number = arr.length;
        for (var i:Number = 0; i < len; i++) {
            var s:IShield = arr[i];
            if (s.isActive()) {
                total += s.getTargetCapacity();
            }
        }
        return total;
    }

    /**
     * 获取护盾栈的"表观强度"。
     * 返回最外层(第一个)活跃护盾的强度。
     *
     * @return Number 表观强度，无护盾时返回0
     */
    public function getStrength():Number {
        this.sortShields();

        var arr:Array = this._shields;
        var len:Number = arr.length;
        for (var i:Number = 0; i < len; i++) {
            var s:IShield = arr[i];
            if (s.isActive() && !s.isEmpty()) {
                return s.getStrength();
            }
        }
        return 0;
    }

    /**
     * 获取总填充速度。
     * @return Number 所有护盾填充速度之和
     */
    public function getRechargeRate():Number {
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

    /**
     * 获取填充延迟(取所有护盾中的最大值)。
     * @return Number 最大填充延迟
     */
    public function getRechargeDelay():Number {
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

    /**
     * 检查护盾栈是否为空。
     * @return Boolean 所有护盾都耗尽时返回true
     */
    public function isEmpty():Boolean {
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

    /**
     * 检查护盾栈是否激活。
     * @return Boolean 激活状态
     */
    public function isActive():Boolean {
        return this._isActive;
    }

    /**
     * 设置护盾栈激活状态。
     * @param value 激活状态
     */
    public function setActive(value:Boolean):Void {
        this._isActive = value;
    }

    // ==================== 生命周期管理 ====================

    /**
     * 帧更新。
     * 更新所有护盾并弹出未激活的护盾。
     *
     * @param deltaTime 帧间隔(通常为1)
     */
    public function update(deltaTime:Number):Void {
        if (!this._isActive) return;

        var arr:Array = this._shields;
        var len:Number = arr.length;
        var hadShields:Boolean = len > 0;
        var ejectedCb:Function = this.onShieldEjectedCallback;

        // 从后向前遍历，便于安全移除
        for (var i:Number = len - 1; i >= 0; i--) {
            var shield:IShield = arr[i];

            // 先更新护盾
            shield.update(deltaTime);

            // 检查护盾是否未激活，直接弹出
            if (!shield.isActive()) {
                arr.splice(i, 1);

                // 触发弹出回调
                if (ejectedCb != null) {
                    ejectedCb(shield, this);
                }
            }
        }

        // 检查是否所有护盾都已弹出
        if (hadShields && arr.length == 0) {
            this.onAllShieldsDepleted();
        }
    }

    /**
     * 护盾被命中事件。
     * 护盾栈本身不处理命中，由内部护盾各自处理。
     *
     * @param absorbed 吸收的伤害量
     */
    public function onHit(absorbed:Number):Void {
        // 护盾栈级别不处理，内部护盾已各自处理
    }

    /**
     * 护盾栈击碎回调。
     * 当所有护盾都耗尽时可调用此方法。
     */
    public function onBreak():Void {
        // 检查是否真的全部耗尽
        if (this.isEmpty()) {
            this.onAllShieldsDepleted();
        }
    }

    /**
     * 所有护盾耗尽回调。
     */
    private function onAllShieldsDepleted():Void {
        if (this.onAllShieldsDepletedCallback != null) {
            this.onAllShieldsDepletedCallback(this);
        }
    }

    /**
     * 开始填充回调。
     */
    public function onRechargeStart():Void {
        // 护盾栈级别的回调，通常不使用
    }

    /**
     * 填充完毕回调。
     */
    public function onRechargeFull():Void {
        // 护盾栈级别的回调，通常不使用
    }

    /**
     * 获取排序优先级。
     * 护盾栈作为整体时，返回最高子护盾的优先级。
     *
     * @return Number 排序优先级
     */
    public function getSortPriority():Number {
        this.sortShields();

        var arr:Array = this._shields;
        if (arr.length > 0) {
            return IShield(arr[0]).getSortPriority();
        }
        return 0;
    }

    // ==================== 扩展属性 ====================

    /**
     * 获取所属单位。
     * @return Object 所属单位引用
     */
    public function getOwner():Object {
        return this._owner;
    }

    /**
     * 设置所属单位。
     * 同时更新所有子护盾的owner。
     *
     * @param value 单位引用
     */
    public function setOwner(value:Object):Void {
        this._owner = value;

        // 更新所有子护盾
        var arr:Array = this._shields;
        var len:Number = arr.length;
        for (var i:Number = 0; i < len; i++) {
            var s:Object = arr[i];
            if (s instanceof Shield) {
                Shield(s).setOwner(value);
            }
        }
    }

    /**
     * 批量设置回调。
     *
     * @param callbacks 包含回调的对象
     *        {
     *            onShieldEjected: function(shield, stack),
     *            onAllShieldsDepleted: function(stack)
     *        }
     * @return ShieldStack 返回自身，支持链式调用
     */
    public function setCallbacks(callbacks:Object):ShieldStack {
        if (callbacks == null) return this;

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
     * 重置所有护盾。
     */
    public function reset():Void {
        var arr:Array = this._shields;
        var len:Number = arr.length;
        for (var i:Number = 0; i < len; i++) {
            var s:Object = arr[i];
            if (s instanceof BaseShield) {
                BaseShield(s).reset();
            }
        }
    }

    /**
     * 返回护盾栈状态的字符串表示。
     * @return String 状态信息
     */
    public function toString():String {
        var arr:Array = this._shields;
        var len:Number = arr.length;

        var result:String = "ShieldStack[count=" + len +
                           ", capacity=" + this.getCapacity() + "/" + this.getMaxCapacity() +
                           ", strength=" + this.getStrength() +
                           ", active=" + this._isActive + "]\n";

        for (var i:Number = 0; i < len; i++) {
            result += "  [" + i + "] " + arr[i].toString() + "\n";
        }

        return result;
    }
}
