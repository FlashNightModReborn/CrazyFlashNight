// File: org/flashNight/arki/component/Shield/ShieldStack.as

import org.flashNight.arki.component.Shield.*;

/**
 * ShieldStack 类实现护盾栈，管理多个护盾的生命周期。
 *
 * ============================================================
 * 【玩家心智模型】
 * ============================================================
 * 护盾栈对外表现为"一层护盾"：
 * - 强度 = 最高强度护盾的强度值
 * - 容量 = 所有护盾容量之和
 * - 超过强度的伤害直接穿透本体
 * - 未穿透的伤害从护盾容量中扣除
 *
 * 简单理解：
 * "护盾只能挡住不超过其强度的伤害，挡住的伤害消耗容量"
 *
 * 【联弹兼容】
 * 联弹是单发子弹模拟多段弹幕的性能优化方案：
 * - 联弹总伤害 = 单段伤害 × 段数
 * - 护盾有效强度 = 基础强度 × 段数
 * - 例：强度50护盾 vs 10段联弹(每段60伤害，总600)
 *   有效强度 = 50 × 10 = 500，吸收500，穿透100
 * - 玩家视角：护盾能挡住的"每段伤害"仍是强度值
 *
 * ============================================================
 * 【构筑设计空间】
 * ============================================================
 * 1. 高强度低容量 - "格挡型"
 *    能挡住高伤害单发，但持续输出会打穿容量
 *    适合对抗Boss大招、狙击等
 *
 * 2. 低强度高容量 - "吸收型"
 *    被高伤害穿透，但能抵挡大量低伤害
 *    适合对抗小兵群攻、持续伤害等
 *
 * 3. 多层护盾叠加 - "复合型"
 *    高强度盾在外层过滤伤害，低强度高容量盾在内层吸收
 *    兼顾两种优势
 *
 * 4. 抗真伤盾(resistBypass) - "绝对防御"
 *    可抵抗绕过效果(如真伤)，但通常容量有限或持续时间短
 *
 * 5. 衰减盾(负rechargeRate) - "临时增益"
 *    容量随时间减少，适合技能增益效果
 *
 * ============================================================
 * 【技术实现】
 * ============================================================
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
 * 1. 按栈的表观强度(最高强度)做一次节流
 * 2. 节流后的伤害由内部护盾按优先级逐个承担
 * 3. 超过表观强度的部分直接穿透
 *
 * 【属性聚合】
 * - getCapacity(): 所有护盾容量之和
 * - getMaxCapacity(): 所有护盾最大容量之和
 * - getStrength(): 最外层活跃护盾的强度(已缓存)
 *
 * 【缓存机制】
 * - 表观强度和抵抗绕过计数通过脏标记缓存
 * - 护盾增删、排序变化、伤害吸收后自动失效
 * - 抵抗绕过：扫描全栈，任意一层有即生效（使用计数器）
 *
 * 【容量消耗机制】
 * - 栈对外像"一层盾"，子盾只承担容量消耗
 * - 子盾使用 consumeCapacity() 而非 absorbDamage()
 * - 强度节流在栈级别完成，子盾不再重复计算
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

    /** 护盾栈唯一标识 */
    private var _id:Number;

    // ==================== 缓存属性 ====================

    /** 缓存的表观强度(第一个有效护盾的强度) */
    private var _cachedStrength:Number;

    /** 抵抗绕过的护盾计数(任意一层有即生效) */
    private var _resistantCount:Number;

    /** 缓存的当前总容量 */
    private var _cachedCapacity:Number;

    /** 缓存的最大总容量 */
    private var _cachedMaxCapacity:Number;

    /** 缓存的目标总容量 */
    private var _cachedTargetCapacity:Number;

    /** 缓存是否有效 */
    private var _cacheValid:Boolean;

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
        this._id = ShieldIdAllocator.nextId();
        this._cachedStrength = 0;
        this._resistantCount = 0;
        this._cachedCapacity = 0;
        this._cachedMaxCapacity = 0;
        this._cachedTargetCapacity = 0;
        this._cacheValid = false;
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
        this._cacheValid = false;

        // 设置owner（BaseShield 及其子类都支持）
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
        var arr:Array = this._shields;
        var len:Number = arr.length;
        for (var i:Number = 0; i < len; i++) {
            if (arr[i] === shield) {
                arr.splice(i, 1);
                this._cacheValid = false;
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
                this._cacheValid = false;
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
        this._cacheValid = false;
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
        this._cacheValid = false;
    }

    /**
     * 使缓存失效。
     * 当护盾的 resistBypass 属性变化或护盾状态变化时调用。
     */
    public function invalidateCache():Void {
        this._cacheValid = false;
    }

    /**
     * 更新缓存值。
     * 计算表观强度、容量聚合值和抵抗绕过护盾计数。
     *
     * 【缓存内容】
     * - 表观强度：第一个有效护盾的强度
     * - 总容量/最大容量/目标容量：所有激活护盾的聚合值
     * - 抵抗绕过计数：递归统计所有子护盾（支持嵌套 ShieldStack）
     *
     * 【失效时机】
     * - 护盾增删、排序变化、伤害吸收、子盾更新后自动失效
     */
    private function updateCache():Void {
        if (this._cacheValid) return;

        this.sortShields();

        var arr:Array = this._shields;
        var len:Number = arr.length;

        // 重置所有缓存值
        this._cachedStrength = 0;
        this._resistantCount = 0;
        this._cachedCapacity = 0;
        this._cachedMaxCapacity = 0;
        this._cachedTargetCapacity = 0;

        var foundFirst:Boolean = false;
        for (var i:Number = 0; i < len; i++) {
            var s:IShield = arr[i];
            if (!s.isActive()) continue;

            // 聚合容量值
            this._cachedCapacity += s.getCapacity();
            this._cachedMaxCapacity += s.getMaxCapacity();
            this._cachedTargetCapacity += s.getTargetCapacity();

            // 通过接口统计抵抗绕过（递归支持嵌套 ShieldStack）
            this._resistantCount += s.getResistantCount();

            // 记录第一个有效护盾的强度
            if (!foundFirst && !s.isEmpty()) {
                this._cachedStrength = s.getStrength();
                foundFirst = true;
            }
        }

        this._cacheValid = true;
    }

    // ==================== IShield 接口实现 ====================

    /**
     * 吸收伤害。
     * 按栈的表观强度节流后，由内部护盾逐个承担。
     *
     * 【玩家视角 - 简化心智模型】
     * - 护盾栈对外表现为"一层护盾"，强度=最高强度护盾的强度
     * - 超过强度的伤害直接穿透，不消耗护盾
     * - 未穿透的伤害从护盾容量中扣除
     *
     * 【联弹支持】
     * - hitCount 用于联弹(单发模拟多段弹幕)场景
     * - 有效强度 = 基础强度 * hitCount
     * - 例：强度50护盾，10段联弹，有效强度=500
     * - 玩家视角：护盾能挡住的"每段伤害"仍是强度值
     *
     * 【设计空间 - 构筑强度】
     * - 高强度低容量：抵抗高伤害单发，但持续输出会打穿
     * - 低强度高容量：被高伤害穿透，但能抵挡大量低伤害
     * - 多层护盾叠加：按优先级消耗，强度盾保护容量盾
     * - 抗真伤盾(resistBypass)：可抵抗绕过效果
     *
     * 【内部实现】
     * 1. 取栈的表观强度(最高优先级护盾的强度)
     * 2. 计算有效强度：effectiveStrength = stackStrength * hitCount
     * 3. 节流：absorbable = min(damage, effectiveStrength)
     * 4. 穿透 = damage - absorbable (超过有效强度的部分)
     * 5. 将 absorbable 按优先级分配给内部护盾消耗容量
     * 6. 若内部护盾容量不足，剩余部分也算穿透
     *
     * @param damage 输入伤害(联弹为总伤害)
     * @param bypassShield 是否绕过护盾(如真伤)，默认false
     * @param hitCount 命中段数(联弹段数)，默认1
     * @return Number 穿透伤害
     */
    public function absorbDamage(damage:Number, bypassShield:Boolean, hitCount:Number):Number {
        // 护盾栈未激活
        if (!this._isActive) {
            return damage;
        }

        // 更新缓存(内部会确保排序)
        this.updateCache();

        // 使用缓存的值
        var stackStrength:Number = this._cachedStrength;

        // 无有效护盾，全部穿透
        if (stackStrength <= 0) {
            return damage;
        }

        // 绕过检查：bypassShield=true 且无抵抗绕过的护盾
        // 任意一层有 resistBypass 即可抵抗绕过
        if (bypassShield && this._resistantCount <= 0) {
            return damage;
        }

        // hitCount 默认值处理
        if (hitCount == undefined || hitCount < 1) {
            hitCount = 1;
        }

        // 计算有效强度：基础强度 * 段数
        var effectiveStrength:Number = stackStrength * hitCount;

        var arr:Array = this._shields;
        var len:Number = arr.length;

        // 按有效强度节流
        var absorbable:Number = damage;
        if (absorbable > effectiveStrength) {
            absorbable = effectiveStrength;
        }

        // 穿透伤害 = 超过有效强度的部分
        var penetrating:Number = damage - absorbable;

        // 将节流后的伤害分配给内部护盾（按优先级逐个消耗容量）
        var toAbsorb:Number = absorbable;
        for (var j:Number = 0; j < len && toAbsorb > 0; j++) {
            var shield:IShield = arr[j];

            // 跳过未激活或已耗尽的护盾
            if (!shield.isActive() || shield.isEmpty()) {
                continue;
            }

            // 该护盾承担的伤害 = min(剩余待吸收, 护盾容量)
            var cap:Number = shield.getCapacity();
            var shieldAbsorb:Number = toAbsorb;
            if (shieldAbsorb > cap) {
                shieldAbsorb = cap;
            }

            // 通过接口调用消耗容量（支持嵌套 ShieldStack）
            var consumed:Number = shield.consumeCapacity(shieldAbsorb);
            toAbsorb -= consumed;
        }

        // 未能吸收的部分也算穿透
        penetrating += toAbsorb;

        // 触发栈级别命中事件
        var absorbed:Number = absorbable - toAbsorb;
        if (absorbed > 0) {
            this.onHit(absorbed);
            // 护盾容量可能变化，缓存可能失效
            this._cacheValid = false;
        }

        return penetrating;
    }

    /**
     * 直接消耗护盾栈容量（供外层 ShieldStack 调用）。
     *
     * 【组合模式支持】
     * 实现 IShield.consumeCapacity 接口，使 ShieldStack 可作为子护盾嵌套。
     * 容量消耗按优先级分发给内部护盾。
     *
     * 【行为】
     * 1. 按优先级遍历内部护盾
     * 2. 逐个调用子护盾的 consumeCapacity
     * 3. 累计实际消耗量并触发相应事件
     *
     * @param amount 要消耗的容量
     * @return Number 实际消耗的容量
     */
    public function consumeCapacity(amount:Number):Number {
        if (!this._isActive || amount <= 0) return 0;

        this.updateCache();

        var arr:Array = this._shields;
        var len:Number = arr.length;
        var toConsume:Number = amount;
        var totalConsumed:Number = 0;

        for (var i:Number = 0; i < len && toConsume > 0; i++) {
            var shield:IShield = arr[i];

            // 跳过未激活或已耗尽的护盾
            if (!shield.isActive() || shield.isEmpty()) {
                continue;
            }

            // 该护盾承担的消耗 = min(剩余待消耗, 护盾容量)
            var cap:Number = shield.getCapacity();
            var shieldConsume:Number = toConsume;
            if (shieldConsume > cap) {
                shieldConsume = cap;
            }

            // 调用子护盾的 consumeCapacity（支持嵌套）
            var consumed:Number = shield.consumeCapacity(shieldConsume);
            totalConsumed += consumed;
            toConsume -= consumed;
        }

        // 触发栈级别命中事件
        if (totalConsumed > 0) {
            this.onHit(totalConsumed);
            this._cacheValid = false;
        }

        return totalConsumed;
    }

    /**
     * 获取当前总容量（缓存）。
     * @return Number 所有护盾容量之和
     */
    public function getCapacity():Number {
        if (!this._cacheValid) this.updateCache();
        return this._cachedCapacity;
    }

    /**
     * 获取最大总容量（缓存）。
     * @return Number 所有护盾最大容量之和
     */
    public function getMaxCapacity():Number {
        if (!this._cacheValid) this.updateCache();
        return this._cachedMaxCapacity;
    }

    /**
     * 获取目标总容量（缓存）。
     * @return Number 所有护盾目标容量之和
     */
    public function getTargetCapacity():Number {
        if (!this._cacheValid) this.updateCache();
        return this._cachedTargetCapacity;
    }

    /**
     * 获取护盾栈的"表观强度"。
     * 返回最外层(第一个)活跃护盾的强度。
     *
     * @return Number 表观强度，无护盾时返回0
     */
    public function getStrength():Number {
        if (!this._cacheValid) this.updateCache();
        return this._cachedStrength;
    }

    /**
     * 检查护盾栈中是否有抵抗绕过的护盾。
     * 任意一层有 resistBypass=true 即返回 true。
     * @return Boolean 是否有抵抗绕过的护盾
     */
    public function hasResistantShield():Boolean {
        if (!this._cacheValid) this.updateCache();
        return this._resistantCount > 0;
    }

    /**
     * 获取抵抗绕过的护盾数量。
     * @return Number 抵抗绕过的护盾计数
     */
    public function getResistantCount():Number {
        if (!this._cacheValid) this.updateCache();
        return this._resistantCount;
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
     * 【缓存失效】
     * 仅当子盾状态实际变化时才置脏缓存。
     *
     * @param deltaTime 帧间隔(通常为1)
     * @return Boolean 是否有子盾状态变化或护盾弹出
     */
    public function update(deltaTime:Number):Boolean {
        if (!this._isActive) return false;

        var arr:Array = this._shields;
        var len:Number = arr.length;
        if (len == 0) return false;

        var changed:Boolean = false;
        var ejectedCb:Function = this.onShieldEjectedCallback;

        // 从后向前遍历，便于安全移除
        for (var i:Number = len - 1; i >= 0; i--) {
            var shield:IShield = arr[i];

            // 更新护盾并记录是否有变化
            if (shield.update(deltaTime)) {
                changed = true;
            }

            // 检查护盾是否未激活，直接弹出
            if (!shield.isActive()) {
                arr.splice(i, 1);
                changed = true;

                // 触发弹出回调
                if (ejectedCb != null) {
                    ejectedCb(shield, this);
                }
            }
        }

        // 仅当有变化时才置脏缓存
        if (changed) {
            this._cacheValid = false;
        }

        // 检查是否所有护盾都已弹出
        if (arr.length == 0) {
            this.onAllShieldsDepleted();
        }

        return changed;
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
     * 获取护盾栈唯一标识。
     * @return Number 全局唯一的护盾栈 ID
     */
    public function getId():Number {
        return this._id;
    }

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

        // 更新所有子护盾（BaseShield 及其子类都支持）
        var arr:Array = this._shields;
        var len:Number = arr.length;
        for (var i:Number = 0; i < len; i++) {
            var s:Object = arr[i];
            if (s instanceof BaseShield) {
                BaseShield(s).setOwner(value);
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
