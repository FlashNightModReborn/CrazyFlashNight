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

    /** 缓存的表观强度对应的层索引（第一个 active 且非空的护盾索引，不存在为 -1） */
    private var _cachedTopIndex:Number;

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

    // ==================== 结构操作常量（回调重入安全） ====================

    private static var STRUCT_OP_ADD:Number = 1;
    private static var STRUCT_OP_REMOVE:Number = 2;
    private static var STRUCT_OP_REMOVE_BY_ID:Number = 3;
    private static var STRUCT_OP_CLEAR:Number = 4;

    // ==================== 回调重入安全：结构修改排队 ====================

    /** 结构锁深度（>0 时 add/remove/clear 将排队，避免迭代期间数组被改写） */
    private var _structureLockDepth:Number;

    /** 排队的结构操作列表 */
    private var _pendingStructureOps:Array;

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
        this._cachedTopIndex = -1;
        this._resistantCount = 0;
        this._cachedCapacity = 0;
        this._cachedMaxCapacity = 0;
        this._cachedTargetCapacity = 0;
        this._cacheValid = false;
        this.onShieldEjectedCallback = null;
        this.onAllShieldsDepletedCallback = null;
        this._structureLockDepth = 0;
        this._pendingStructureOps = null;
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
            this.addShield(IShield(op.shield));
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
     * ShieldStack 支持组合模式与嵌套栈（栈作为子盾），若出现 A->B->...->A 的环，
     * 在 getResistantCount/updateCache 等递归聚合路径会导致无限递归/卡死。
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

    // ==================== 护盾管理 ====================

    /**
     * 添加护盾到栈中。
     * 不会添加：null、未激活护盾、栈自身、重复引用护盾、会形成容器环(cycle)的护盾。
     *
     * @param shield 要添加的护盾
     * @return Boolean 添加成功返回true
     */
    public function addShield(shield:IShield):Boolean {
        if (shield == null) return false;
        // 防御：禁止把栈自身作为子盾加入（会形成递归引用）
        if (shield === this) return false;

        // 不添加未激活的护盾
        if (!shield.isActive()) return false;

        // 容器环防护：禁止引入能回到自身的子容器
        if (this._wouldCreateCycle(shield)) return false;

        // 回调重入保护：迭代期间的结构修改排队，避免数组迭代失真
        if (this._isStructureLocked()) {
            // 防御：禁止同一引用重复加入（避免迭代与缓存出现隐性退化）
            var qArr:Array = this._shields;
            var qLen:Number = qArr.length;
            for (var qi:Number = 0; qi < qLen; qi++) {
                if (qArr[qi] === shield) return false;
            }
            this._queueStructureOp({t: STRUCT_OP_ADD, shield: shield});
            return true;
        }

        // 防御：禁止同一引用重复加入（避免迭代与缓存出现隐性退化）
        var arr:Array = this._shields;
        var len:Number = arr.length;
        for (var i:Number = 0; i < len; i++) {
            if (arr[i] === shield) return false;
        }

        this._shields.push(shield);
        this._needsSort = true;
        this._cacheValid = false;

        // 通过接口传播 owner
        shield.setOwner(this._owner);

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
                return true;
            }
        }
        return false;
    }

    /**
     * 根据ID移除护盾。
     * 通过 IShield.getId() 接口匹配，支持所有 IShield 实现。
     * 使用交换法 O(1) 删除，后续排序会恢复顺序。
     *
     * @param id 护盾ID
     * @return Boolean 移除成功返回true
     */
    public function removeShieldById(id:Number):Boolean {
        // 回调重入保护：迭代期间排队移除请求
        if (this._isStructureLocked()) {
            var qArr:Array = this._shields;
            var qLen:Number = qArr.length;
            for (var qi:Number = 0; qi < qLen; qi++) {
                if (qArr[qi].getId() == id) {
                    this._queueStructureOp({t: STRUCT_OP_REMOVE_BY_ID, id: id});
                    return true;
                }
            }
            return false;
        }

        var arr:Array = this._shields;
        var len:Number = arr.length;
        for (var i:Number = 0; i < len; i++) {
            if (arr[i].getId() == id) {
                // 交换到末尾并截断（O(1) 删除，避免 pop 函数调用开销）
                arr[i] = arr[len - 1];
                arr.length = len - 1;
                this._cacheValid = false;
                this._needsSort = true;
                return true;
            }
        }
        return false;
    }

    /**
     * 根据ID获取护盾。
     * 通过 IShield.getId() 接口匹配，支持所有 IShield 实现
     * （包括 BaseShield、Shield、ShieldStack、AdaptiveShield 等）。
     *
     * @param id 护盾ID
     * @return IShield 护盾实例，不存在返回null
     */
    public function getShieldById(id:Number):IShield {
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
        // 回调重入保护：迭代期间排队清空请求
        if (this._isStructureLocked()) {
            this._queueStructureOp({t: STRUCT_OP_CLEAR});
            return;
        }

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
        this._cachedTopIndex = -1;
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
                this._cachedTopIndex = i;
                foundFirst = true;
            }
        }

        this._cacheValid = true;
    }

    /**
     * 从指定索引开始刷新表观强度缓存。
     * 仅扫描到找到下一层 active 且非空护盾为止（或扫描结束）。
     *
     * @param startIndex 起始索引（通常为当前 _cachedTopIndex）
     */
    private function refreshTopCacheFrom(startIndex:Number):Void {
        var arr:Array = this._shields;
        var len:Number = arr.length;

        if (startIndex == undefined || isNaN(startIndex) || startIndex < 0) {
            startIndex = 0;
        }

        for (var i:Number = startIndex; i < len; i++) {
            var s:IShield = arr[i];
            if (!s.isActive() || s.isEmpty()) continue;
            this._cachedStrength = s.getStrength();
            this._cachedTopIndex = i;
            return;
        }

        // 未找到任何有效护盾
        this._cachedStrength = 0;
        this._cachedTopIndex = -1;
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

        // 迭代期间加锁：子盾回调中若修改栈结构，将延迟到分摊循环结束后生效
        // 这样可避免每次 slice() 产生 GC，同时保证本次分摊语义稳定（不跳层/不重复）
        var arr:Array = this._shields;
        var len:Number = arr.length;
        var start:Number = this._cachedTopIndex;
        if (start < 0) start = 0;

        // 按有效强度节流
        var absorbable:Number = damage;
        if (absorbable > effectiveStrength) {
            absorbable = effectiveStrength;
        }

        // 穿透伤害 = 超过有效强度的部分
        var penetrating:Number = damage - absorbable;

        // 将节流后的伤害分配给内部护盾（按优先级逐个消耗容量）
        var toAbsorb:Number = absorbable;
        var inactiveCapToRemove:Number = 0;
        var inactiveMaxToRemove:Number = 0;
        var inactiveTargetToRemove:Number = 0;
        var inactiveResistToRemove:Number = 0;

        this._lockStructure();
        for (var j:Number = start; j < len && toAbsorb > 0; j++) {
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

            // 若回调导致该层失活，则需要从聚合缓存中剔除其剩余贡献（不等同于 absorbed）
            if (!shield.isActive()) {
                inactiveCapToRemove += shield.getCapacity();
                inactiveMaxToRemove += shield.getMaxCapacity();
                inactiveTargetToRemove += shield.getTargetCapacity();
                inactiveResistToRemove += shield.getResistantCount();
            }
        }
        this._unlockStructure();

        // 未能吸收的部分也算穿透
        penetrating += toAbsorb;

        // 触发栈级别命中事件
        var absorbed:Number = absorbable - toAbsorb;
        if (absorbed > 0) {
            this.onHit(absorbed);
            // 增量维护缓存：避免每次命中都全量 updateCache()（高频场景会退化到 O(H·N)）
            // 注意：若回调触发了结构修改/显式 invalidateCache，则 _cacheValid 可能已被置为 false，此处不做增量更新。
            if (this._cacheValid) {
                this._cachedCapacity -= absorbed;
                this._cachedCapacity -= inactiveCapToRemove;
                if (this._cachedCapacity < 0) this._cachedCapacity = 0;

                this._cachedMaxCapacity -= inactiveMaxToRemove;
                if (this._cachedMaxCapacity < 0) this._cachedMaxCapacity = 0;

                this._cachedTargetCapacity -= inactiveTargetToRemove;
                if (this._cachedTargetCapacity < 0) this._cachedTargetCapacity = 0;

                this._resistantCount -= inactiveResistToRemove;
                if (this._resistantCount < 0) this._resistantCount = 0;

                // 若当前表观层被清空/失活，刷新表观强度（只会向内扫描，不会重排）
                this.refreshTopCacheFrom(this._cachedTopIndex);
            }
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

        // 迭代期间加锁：子盾回调中若修改栈结构，将延迟到分摊循环结束后生效
        var arr:Array = this._shields;
        var len:Number = arr.length;
        var start:Number = this._cachedTopIndex;
        if (start < 0) start = 0;
        var toConsume:Number = amount;
        var totalConsumed:Number = 0;
        var inactiveCapToRemove:Number = 0;
        var inactiveMaxToRemove:Number = 0;
        var inactiveTargetToRemove:Number = 0;
        var inactiveResistToRemove:Number = 0;

        this._lockStructure();
        for (var i:Number = start; i < len && toConsume > 0; i++) {
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

            // 若回调导致该层失活，则需要从聚合缓存中剔除其剩余贡献
            if (!shield.isActive()) {
                inactiveCapToRemove += shield.getCapacity();
                inactiveMaxToRemove += shield.getMaxCapacity();
                inactiveTargetToRemove += shield.getTargetCapacity();
                inactiveResistToRemove += shield.getResistantCount();
            }
        }
        this._unlockStructure();

        // 触发栈级别命中事件
        if (totalConsumed > 0) {
            this.onHit(totalConsumed);
            if (this._cacheValid) {
                this._cachedCapacity -= totalConsumed;
                this._cachedCapacity -= inactiveCapToRemove;
                if (this._cachedCapacity < 0) this._cachedCapacity = 0;

                this._cachedMaxCapacity -= inactiveMaxToRemove;
                if (this._cachedMaxCapacity < 0) this._cachedMaxCapacity = 0;

                this._cachedTargetCapacity -= inactiveTargetToRemove;
                if (this._cachedTargetCapacity < 0) this._cachedTargetCapacity = 0;

                this._resistantCount -= inactiveResistToRemove;
                if (this._resistantCount < 0) this._resistantCount = 0;

                this.refreshTopCacheFrom(this._cachedTopIndex);
            }
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
     * 【回调安全性重构】
     * 采用"先截断后回调"策略，保证 onShieldEjectedCallback 触发时数组结构已稳定：
     * 1. Phase 1: 遍历并收集待弹出护盾，交换到尾部
     * 2. Phase 2: 统一截断数组
     * 3. Phase 3: 触发 ejected 回调（此时结构已稳定，回调可安全修改）
     * 4. Phase 4: 重新读取数组长度，评估耗尽条件
     *
     * 这确保了回调内的 addShield/removeShield/clear 操作不会被后续截断吞掉。
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

        // ========== Phase 1: 遍历更新，收集待弹出护盾 ==========
        // 延迟初始化 ejectedList，大多数帧无护盾弹出
        var ejectedList:Array = null;
        var tail:Number = len;

        // Phase 1/2 期间加锁：子盾回调里若修改结构，将自动排队到 Phase 2 之后执行
        this._lockStructure();
        for (var i:Number = len - 1; i >= 0; i--) {
            var shield:IShield = arr[i];

            if (shield.update(deltaTime)) {
                changed = true;
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

        // ========== Phase 3: 触发 ejected 回调（结构已稳定） ==========
        var ejectedCb:Function = this.onShieldEjectedCallback;
        if (ejectedList != null && ejectedCb != null) {
            var ejectedLen:Number = ejectedList.length;
            for (var j:Number = 0; j < ejectedLen; j++) {
                ejectedCb(ejectedList[j], this);
            }
        }

        // ========== Phase 4: 重新评估状态（回调可能修改了结构） ==========
        // 重新读取数组长度，因为回调可能调用了 addShield/removeShield/clear
        var finalLen:Number = this._shields.length;

        if (finalLen == 0) {
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
     * 通过 IShield 接口向所有子护盾传播 owner。
     *
     * @param value 单位引用
     */
    public function setOwner(value:Object):Void {
        this._owner = value;

        // 通过接口向所有子护盾传播 owner
        var arr:Array = this._shields;
        var len:Number = arr.length;
        for (var i:Number = 0; i < len; i++) {
            IShield(arr[i]).setOwner(value);
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
