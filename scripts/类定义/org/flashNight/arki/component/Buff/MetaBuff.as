/**
 * MetaBuff.as - 专注于状态管理的复合Buff
 *
 * 版本历史:
 * v1.4 (2026-01) - 架构优化 & 单一数据源
 *   [PERF] _hasValidChildBuffs 改用脏标记 + 短路优化，消除无用遍历
 *   [REFACTOR] 移除 _injectedBuffIds，由 BuffManager 作为注入列表唯一数据源
 *   [CLEANUP] 移除 recordInjectedBuffId/removeInjectedBuffId/clearInjectedBuffIds/getInjectedBuffIds
 *
 * v1.3 (2026-01) - 类型安全增强
 *   [REFACTOR] stateInfo改为StateInfo类，提供编译期类型检查
 *   [PERF] 使用StateInfo静态单例，保持0GC特性
 *
 * v1.2 (2026-01) - 性能优化
 *   [PERF] update()返回的stateInfo改为静态类变量复用，实现0GC
 *   [PERF] 消除每帧每个MetaBuff创建临时对象的GC压力
 *
 * v1.1 (2026-01) - 代码审查修复
 *   [FIX] update()中组件判断改为动态检查 _components.length > 0
 *   [CLEANUP] 移除无用的 _componentBased 字段，避免误导后续维护者
 */
import org.flashNight.arki.component.Buff.*;
import org.flashNight.arki.component.Buff.Component.*;

class org.flashNight.arki.component.Buff.MetaBuff extends BaseBuff {
    // 状态枚举
    private static var STATE_INACTIVE:Number = 0;
    private static var STATE_ACTIVE:Number = 1;
    private static var STATE_PENDING_DEACTIVATE:Number = 2;

    // [v1.3] 缓存StateInfo单例引用，热路径零函数调用
    // 首次使用时通过getInstance()安全初始化，之后直接访问缓存
    private static var _stateInfo:StateInfo;

    private var _components:Array;      // [IBuffComponent]
    private var _childBuffs:Array;      // 内嵌 PodBuff 模板
    private var _priority:Number;
    // [v2.6] 移除 _componentBased 字段，改为动态检查 _components.length > 0

    // 状态管理
    private var _currentState:Number;
    private var _lastState:Number;
    // [v1.4] 移除 _injectedBuffIds，由 BuffManager._metaBuffInjections 作为唯一数据源

    // [v1.4] 脏标记：-1=未计算, 0=false, 1=true
    // 用于 _hasValidChildBuffs 缓存，避免无组件时每帧遍历
    private var _childBuffsValidCache:Number;

    // [Phase 0] 销毁标志，防止复用已销毁的实例
    private var _destroyed:Boolean;
    
    /**
     * @param childBuffs Array.<PodBuff>  数值 Buff 模板列表
     * @param comps      Array.<IBuffComponent> 附加组件
     * @param priority   Number 优先级（可选）
     */
    public function MetaBuff(childBuffs:Array, comps:Array, priority:Number) {
        super();
        this._type = "MetaBuff";

        // [Phase 0 / P1-4] Defensive copy - 防止外部修改影响内部状态
        this._childBuffs = (childBuffs != null) ? childBuffs.slice() : [];
        this._components = (comps != null) ? comps.slice() : [];

        this._priority = priority || 0;

        // 初始状态
        this._currentState = STATE_ACTIVE; // 初始即激活
        this._lastState = STATE_INACTIVE;
        // [v1.4] 移除 _injectedBuffIds 初始化，由 BuffManager 管理

        // [v1.4] 初始化脏标记为"未计算"
        this._childBuffsValidCache = -1;

        // [Phase 0] 初始化销毁标志
        this._destroyed = false;

        // 验证子 Buff 必须是 PodBuff（同时使脏标记失效）
        for (var i:Number = 0; i < this._childBuffs.length; i++) {
            if (!this._childBuffs[i].isPod()) {
                trace("[MetaBuff] 警告：只接受 PodBuff 作为子 Buff");
                this._childBuffs.splice(i, 1);
                this._childBuffsValidCache = -1;  // 数组变化，标记失效
                i--;
            }
        }

        // 挂载组件
        this._attachAllComponents();
    }
    
    /**
     * 重写 applyEffect - MetaBuff 不参与计算
     * BuffCalculator 永远不会调用这个方法
     */
    public function applyEffect(calc:IBuffCalculator, ctx:BuffContext):Void {
        // 空实现 - MetaBuff 不直接参与数值计算
    }
    
    /**
     * 核心更新方法 - 返回状态变化信息
     * @param deltaFrames 增量帧数
     * @return StateInfo 状态变化信息（静态单例，调用方需在下一次update前完成读取）
     */
    public function update(deltaFrames:Number):StateInfo {
        // 保存上一次状态
        this._lastState = this._currentState;

        // [v2.6 修复] 在更新组件之前检查是否有组件
        // 必须在_updateComponents之前检查，因为门控组件死亡后会被splice掉
        // 如果在之后检查，length已经变为0，会错误地fallback到childAlive判断
        var useComponents:Boolean = (this._components.length > 0);

        // 更新组件
        var compsAlive:Boolean = this._updateComponents(deltaFrames);

        // [v1.4] 短路优化：有组件时跳过 _hasValidChildBuffs 计算
        // 动态判断：当前是否有组件决定存活依据，而非初始状态
        // 解决"初始有组件但全部被移除后变成僵尸"的边缘情况
        var shouldBeActive:Boolean;
        if (useComponents) {
            shouldBeActive = compsAlive;
        } else {
            shouldBeActive = this._hasValidChildBuffs();
        }
        
        // 状态机更新
        switch (this._currentState) {
            case STATE_INACTIVE:
                if (shouldBeActive) {
                    this._currentState = STATE_ACTIVE;
                }
                break;
                
            case STATE_ACTIVE:
                if (!shouldBeActive) {
                    this._currentState = STATE_PENDING_DEACTIVATE;
                }
                break;
                
            case STATE_PENDING_DEACTIVATE:
                // 给一帧的缓冲时间，确保 BuffManager 能处理注销
                this._currentState = STATE_INACTIVE;
                break;
        }
        
        // [v1.3] 使用缓存的StateInfo单例，热路径零函数调用开销
        var info:StateInfo = _stateInfo;
        if (info == null) {
            // 首次使用，安全初始化并缓存
            info = _stateInfo = StateInfo.getInstance();
        }
        info.alive = this._currentState != STATE_INACTIVE;
        info.stateChanged = this._currentState != this._lastState;
        info.needsInject = this._lastState == STATE_INACTIVE && this._currentState == STATE_ACTIVE;
        info.needsEject = this._lastState == STATE_ACTIVE && this._currentState == STATE_PENDING_DEACTIVATE;
        return info;
    }
    
    /**
     * 获取需要注入的 PodBuff 列表
     *
     * [v1.4] 简化：仅创建并返回 PodBuff 实例数组
     * 注入 ID 的记录由 BuffManager._metaBuffInjections 统一管理
     *
     * @return Array 新创建的 PodBuff 实例数组
     */
    public function createPodBuffsForInjection():Array {
        var podBuffs:Array = [];

        for (var i:Number = 0; i < this._childBuffs.length; i++) {
            var template:PodBuff = PodBuff(this._childBuffs[i]);
            if (template && template.isActive()) {
                // 创建新的 PodBuff 实例（复制模板）
                var newPod:PodBuff = new PodBuff(
                    template.getTargetProperty(),
                    template.getCalculationType(),
                    template.getValue()
                );
                podBuffs.push(newPod);
                // [v1.4] 移除 _injectedBuffIds.push，由 BuffManager 统一管理
            }
        }

        return podBuffs;
    }
    
    // [v1.4] 移除以下方法，由 BuffManager._metaBuffInjections 作为唯一数据源：
    // - getInjectedBuffIds()
    // - clearInjectedBuffIds()
    // - removeInjectedBuffId()
    // - recordInjectedBuffId()
    //
    // 如需查询某个 MetaBuff 注入的 PodBuff ID 列表，
    // 请调用 BuffManager.getInjectedPodIds(metaId)
    
    /**
     * 更新所有组件
     *
     * [Phase A / P0-2 修复] 门控组件AND语义：
     * - 门控组件(isLifeGate=true)返回false → 立即终结宿主Buff
     * - 非门控组件(isLifeGate=false)返回false → 仅卸载该组件，不影响宿主
     * - 所有门控组件都必须返回true，宿主才能存活
     *
     * 【契约】组件不得throw异常
     * - AS2下大多数错误不会throw，只有显式throw才会
     * - 移除try/catch以优化性能，组件实现需自行保证不抛异常
     *
     * @return Boolean 是否仍存活
     */
    private function _updateComponents(deltaFrames:Number):Boolean {
        // 如果没有组件，返回true（由childBuffs决定）
        if (this._components.length == 0) {
            return true;
        }

        for (var i:Number = this._components.length - 1; i >= 0; i--) {
            var comp:IBuffComponent = this._components[i];
            if (!comp) {
                this._components.splice(i, 1);
                continue;
            }

            // 【契约】组件update不得throw
            var alive:Boolean = comp.update(this, deltaFrames);

            // 检查是否为门控组件（默认为门控）
            var isGate:Boolean = true;
            if (typeof comp["isLifeGate"] == "function") {
                isGate = comp["isLifeGate"]();
            }

            if (!alive) {
                // 【契约】组件onDetach不得throw
                comp.onDetach();
                this._components.splice(i, 1);

                // [核心逻辑] 门控组件失败 → 终结宿主Buff
                if (isGate) {
                    return false;
                }
                // 非门控组件失败 → 仅卸载，继续检查其他组件
            }
        }

        // 所有门控组件都存活，返回true
        return true;
    }
    
    /**
     * 检查是否有有效的子 Buff
     *
     * [v1.4] 脏标记缓存优化：
     * - _childBuffs 是模板数组，构造后通常不变
     * - 模板中的 PodBuff.isActive() 状态正常流程不会变化
     * - 使用缓存避免无组件场景下每帧 O(n) 遍历
     */
    private function _hasValidChildBuffs():Boolean {
        // 缓存命中，直接返回
        if (this._childBuffsValidCache >= 0) {
            return this._childBuffsValidCache == 1;
        }

        // 缓存未命中，计算并缓存
        for (var i:Number = 0; i < this._childBuffs.length; i++) {
            var childBuff:IBuff = this._childBuffs[i];
            if (childBuff && childBuff.isActive()) {
                this._childBuffsValidCache = 1;
                return true;
            }
        }
        this._childBuffsValidCache = 0;
        return false;
    }

    /**
     * [v1.4] 使 childBuffs 有效性缓存失效
     * 当 _childBuffs 数组内容变化时调用
     */
    public function invalidateChildBuffsCache():Void {
        this._childBuffsValidCache = -1;
    }
    
    /**
     * 挂载所有组件
     */
    private function _attachAllComponents():Void {
        for (var i:Number = 0; i < this._components.length; i++) {
            var comp:IBuffComponent = this._components[i];
            if (comp) {
                comp.onAttach(this);
            }
        }
    }
    
    /**
     * 安全卸载组件
     */
    private function _detachComponent(index:Number):Void {
        if (index >= 0 && index < this._components.length) {
            var comp:IBuffComponent = this._components[index];
            if (comp) {
                comp.onDetach();
            }
            this._components.splice(index, 1);
        }
    }
    
    /**
     * 重写 isActive
     */
    public function isActive():Boolean {
        return this._currentState != STATE_INACTIVE;
    }
    
    /**
     * 重写 isPod
     */
    public function isPod():Boolean {
        return false;
    }
    
    /**
     * 获取当前状态（调试用）
     */
    public function getCurrentState():Number {
        return this._currentState;
    }
    
    /**
     * 手动停用
     */
    public function deactivate():Void {
        if (this._currentState == STATE_ACTIVE) {
            this._currentState = STATE_PENDING_DEACTIVATE;
        }
    }
    
    /**
     * 动态添加组件
     * [v2.6] 移除 _componentBased 维护，改为动态检查 _components.length > 0
     */
    public function addComponent(comp:IBuffComponent):Void {
        if (comp && this.isActive()) {
            this._components.push(comp);
            comp.onAttach(this);
        }
    }
    
    /**
     * 获取子 Buff（只读访问）
     */
    public function getChildBuff(index:Number):IBuff {
        return this._childBuffs[index];
    }
    
    /**
     * 获取子 Buff 数量
     */
    public function getChildBuffCount():Number {
        return this._childBuffs.length;
    }
    
    /**
     * 获取优先级
     */
    public function getPriority():Number {
        return this._priority;
    }
    
    /**
     * 销毁
     * 【契约】组件onDetach不得throw异常
     */
    public function destroy():Void {
        // [Phase 0 / P0-6] 设置销毁标志，防止复用
        this._destroyed = true;

        // 清理组件（契约：onDetach不得throw）
        if (this._components != null) {
            for (var i:Number = 0; i < this._components.length; i++) {
                var comp:IBuffComponent = this._components[i];
                if (comp) {
                    comp.onDetach();
                }
            }
        }

        // 注意：不销毁子 Buff 模板，它们可能被复用

        // 清理引用
        this._components = null;
        this._childBuffs = null;
        // [v1.4] 移除 _injectedBuffIds 清理，已由 BuffManager 管理
        this._childBuffsValidCache = -1;
        this._currentState = STATE_INACTIVE;

        super.destroy();
    }

    /**
     * [Phase 0] 检查是否已销毁
     * @return Boolean 是否已销毁
     */
    public function isDestroyed():Boolean {
        return this._destroyed === true;
    }
    
    /**
     * 调试信息
     * [v1.4] 移除 injected 字段，由 BuffManager 管理
     */
    public function toString():String {
        var stateStr:String = "UNKNOWN";
        switch (this._currentState) {
            case STATE_INACTIVE: stateStr = "INACTIVE"; break;
            case STATE_ACTIVE: stateStr = "ACTIVE"; break;
            case STATE_PENDING_DEACTIVATE: stateStr = "PENDING_DEACTIVATE"; break;
        }

        return "[MetaBuff id: " + this.getId() +
               ", state: " + stateStr +
               ", components: " + (this._components ? this._components.length : 0) +
               ", childBuffs: " + (this._childBuffs ? this._childBuffs.length : 0) + "]";
    }
}