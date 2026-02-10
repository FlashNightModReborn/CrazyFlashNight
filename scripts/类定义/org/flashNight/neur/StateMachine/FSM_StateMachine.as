import org.flashNight.neur.StateMachine.FSM_Status;
import org.flashNight.neur.StateMachine.IMachine;
import org.flashNight.neur.StateMachine.Transitions;

class org.flashNight.neur.StateMachine.FSM_StateMachine extends FSM_Status implements IMachine {
    public var statusDict:Object; // 状态列表（public: BaseUnitBehavior/EnemyBehavior 需外部访问）
    private var activeState:FSM_Status; // 当前状态
    private var lastState:FSM_Status; // 上个状态
    private var defaultState:FSM_Status; // 默认状态
    public var actionCount:Number = 0; // 当前状态已执行的action次数（public: 外部消费者需读取）
    private var _isChanging:Boolean = false;
    private var _started:Boolean = false; // 是否已显式启动

    /**
     * 保留名黑名单：Object 原型链上的属性名不可用作状态名。
     * 在 AddStatus 中一次性校验，零运行时开销。
     */
    private static var RESERVED:Object = {
        toString: 1, constructor: 1, __proto__: 1,
        valueOf: 1, hasOwnProperty: 1, isPrototypeOf: 1,
        propertyIsEnumerable: 1, toLocaleString: 1
    };

    public function FSM_StateMachine(_onAction:Function, _onEnter:Function, _onExit:Function){
        super(_onAction, _onEnter, _onExit);
        this.statusDict = new Object();
        this.actionCount = 0;
        this.transitions = new Transitions(this);
    }

    /**
     * 状态切换 - 4 阶段管线，while 循环替代递归。
     *
     * 修复：onExit 中触发的 ChangeState 不再被静默吞掉。
     * Phase A: 退出当前状态（_pending 清零后调 onExit，onExit 可设 _pending）
     * Phase B: 检查 onExit 重定向（若 _pending 有效则覆盖 target）
     * Phase C: 进入新状态（更新 activeState/lastState/actionCount）
     * Phase D: 检查 onEnter 链式切换（若 _pending 有效则继续循环）
     *
     * 契约：调用者保证 next 是已通过 AddStatus 注册的合法状态名。
     * 若 next 不存在或等于当前状态，静默返回（不切换）。
     */
    public function ChangeState(next:String):Void {
        var target:FSM_Status = this.statusDict[next];
        // instanceof 防止 Object.prototype 属性穿透（如 toString/constructor）
        if (!(target instanceof FSM_Status) || target == this.activeState) return;

        // 构建期（未 start）：仅移动指针，不触发 onExit/onEnter 生命周期。
        // 避免"没 enter 先 exit"的怪序列。start() 会统一触发首次 onEnter。
        if (!this._started) {
            this.activeState = target;
            return;
        }

        if (_isChanging) {
            // 在 onEnter/onExit 回调中触发的 ChangeState，暂存而非递归
            _pending = next;
            return;
        }

        _isChanging = true;
        var maxChain:Number = 10; // 安全上限，防止无限连锁
        var chainCount:Number = 0;

        while ((target instanceof FSM_Status) && target != this.activeState && chainCount < maxChain) {
            // ── Phase A: 退出当前状态 ──
            _pending = null;
            if (this.activeState) {
                this.activeState.onExit();
                // onExit 回调可能调用 ChangeState → 设置 _pending
            }

            // ── Phase B: onExit 重定向检查 ──
            if (_pending != null) {
                var exitRedirect:FSM_Status = this.statusDict[_pending];
                if (exitRedirect instanceof FSM_Status && exitRedirect != this.activeState) {
                    target = exitRedirect;
                    next = _pending;
                    chainCount++; // 仅在 target 实际被修改时消耗链式配额
                }
                _pending = null;
                // fall through → Phase C 使用（可能被重定向的）target
            }

            // ── Phase C: 进入新状态 ──
            this.lastState = this.activeState;
            this.activeState = target;
            this.actionCount = 0;

            // ── Phase D: onEnter 链式切换检查 ──
            _pending = null;
            if (this.activeState) {
                this.activeState.onEnter();
                // onEnter 回调可能调用 ChangeState → 设置 _pending
            }

            if (_pending != null) {
                next = _pending;
                _pending = null;
                target = this.statusDict[next];
                chainCount++;
            } else {
                break;
            }
        }

        if (chainCount >= maxChain) {
            trace("[FSM] Warning: ChangeState chain reached limit (" + maxChain + "), possible oscillation. last=" + next);
        }

        _isChanging = false;
    }

    // _pending 字段声明（AS2 中不需要显式声明，但保持语义清晰）
    private var _pending:String = null;

    public function getDefaultState():FSM_Status{
        return this.defaultState;
    }
    public function getActiveState():FSM_Status{
        return this.activeState;
    }

    /**
     * 直接设置活跃状态，不触发 onEnter/onExit 生命周期。
     *
     * 警告：此方法绕过完整的生命周期管理（lastState/actionCount/enter/exit 均不会更新），
     * 仅应在明确需要跳过生命周期的场景中使用（如 activate() 初始化）。
     * 推荐使用 ChangeState() 来保证状态一致性。
     */
    public function setActiveState(state:FSM_Status):Void{
        trace("[FSM] Warning: setActiveState() bypasses lifecycle. Use ChangeState() for safe transitions.");
        if(state == null) this.activeState = this.defaultState;
        else this.activeState = state;
    }
    public function getLastState():FSM_Status{
        return this.lastState;
    }
    public function setLastState(state:FSM_Status):Void{
        this.lastState = state;
    }
    public function getActiveStateName():String{
        return this.activeState ? this.activeState.name : null;
    }

    /**
     * 添加子状态到状态机。
     *
     * 注意：data 黑板在此处按引用赋值给非嵌套子状态。
     * 约束：machine.data 必须在第一次 AddStatus 调用之前设定，
     * 且后续不能替换 data 引用（只能修改 data 内部字段），
     * 否则旧状态会持有陈旧的 data 引用。
     */
    public function AddStatus(name:String, state:FSM_Status):Void {
        // 契约校验：拒绝无效输入
        if (!name) {
            trace("[FSM] Error: State name cannot be null or empty.");
            return;
        }
        if (!(state instanceof FSM_Status)) {
            trace("[FSM] Error: State must be an instance of FSM_Status.");
            return;
        }

        // 构建期校验：拒绝 Object 原型链上的保留名
        if (RESERVED[name] === 1) {
            trace("[FSM] Error: '" + name + "' is a reserved name (Object prototype). Choose another.");
            return;
        }

        var isNestedMachine:Boolean = (state instanceof FSM_StateMachine);

        state.superMachine = this;
        state.name = name;

        // data 黑板下发：仅对非嵌套状态赋值（嵌套机有自己的 data）
        if (!isNestedMachine) {
            state.data = this.data;
        }

        this.statusDict[name] = state;

        if (this.defaultState == null) {
            this.defaultState = state;
            this.activeState = state;
            this.lastState = state;
            // 不在 AddStatus 中触发 onEnter，由 start() 统一处理
        }
    }

    /**
     * 显式启动状态机。
     *
     * 将构建期与启动期分离：AddStatus 只做数据挂接，start() 统一触发首次 onEnter。
     * 这避免了嵌套状态机"先建子机再挂到父机"时子机默认状态 onEnter 过早/重复触发的问题。
     *
     * 对于根状态机，外部在组装完成后调用 start()；
     * 对于嵌套状态机，父机的 onEnter 传播会自动处理。
     */
    public function start():Void {
        if (this._started) return;
        this._started = true;

        if (this.activeState == null && this.defaultState != null) {
            this.activeState = this.defaultState;
            this.lastState = this.defaultState;
        }
        // 走 this.onEnter() 统一入口，确保 machine-level hook 一致触发
        this.onEnter();
    }

    // ========== 【核心修正区】 ==========
    // 以下是解决嵌套状态机问题的关键代码。

    /**
     * 当此状态机作为状态被"进入"时调用。
     * 此方法现在能正确地激活和传播事件到其子状态。
     */
    public function onEnter():Void {
        // 1. 首先执行状态机自身的onEnter回调（如果已定义）。
        super.onEnter();

        // 2. 标记为已启动（嵌套机通过父机 onEnter 传播自动启动）
        this._started = true;

        // 3. 检查并激活内部状态。
        if (this.activeState == null && this.defaultState != null) {
            this.activeState = this.defaultState;
            this.lastState = this.defaultState;
        }

        // 4. 将onEnter事件传播到当前激活的子状态。
        if (this.activeState != null) {
            this.activeState.onEnter();
        }
    }

    /**
     * 当此状态机作为状态被"退出"时调用。
     * 此方法确保在自身退出前，先正确地退出其子状态。
     *
     * 契约：机器退出期间禁止内部 ChangeState。
     * 若子状态 onExit 回调尝试 ChangeState，请求被静默丢弃（机器即将停用）。
     * 此策略与 destroy() 一致。
     */
    public function onExit():Void {
        // 1. 锁定状态切换，防止子状态 onExit 回调触发内部 ChangeState
        this._isChanging = true;

        // 2. 将 onExit 事件传播到当前激活的子状态（由内而外）
        if (this.activeState != null) {
            this.activeState.onExit();
        }

        // 3. 丢弃退出期间产生的任何 pending，解除锁定
        this._pending = null;
        this._isChanging = false;

        // 4. 执行状态机自身的 onExit 回调（如果已定义）
        super.onExit();

        // 5. 标记为未启动，防止 destroy() 中重复触发 onExit
        this._started = false;
    }

    /**
     * 每帧更新。
     * 此方法正确地将onAction传播到活动的子状态，并处理自身的过渡。
     *
     * 4阶段管线：
     * Phase 1: Gate转换检查（动作前，即时阻断）
     * Phase 2: 执行当前状态动作
     * Phase 3: Normal转换检查（动作后，条件转换）
     * Phase 4: 状态机自身维护（actionCount + machine-level callback）
     */
    public function onAction():Void {
        if (!this._started || !this.activeState) return;

        var maxTransitions:Number = 10; // 防止无限循环
        var transitionCount:Number = 0;

        // 主循环：处理Gate转换、状态动作、Normal转换的完整流程
        while (transitionCount < maxTransitions) {
            // Phase 1: Gate转换检查 - 门转换优先，立即生效
            var activeStateName:String = this.getActiveStateName();
            var gateTarget:String = this.transitions.TransitGate(activeStateName);
            if (gateTarget && gateTarget != activeStateName) {
                this.ChangeState(gateTarget);
                transitionCount++;
                continue; // Gate转换后立即开始下一轮循环，不执行旧状态动作
            }

            // Phase 2: 执行当前状态动作
            var stateBeforeAction:FSM_Status = this.activeState;
            if (this.activeState) {
                this.activeState.onAction();
            }
            // 检测 Phase 2 期间是否发生了状态切换（如 onAction 内部调用了 ChangeState）
            if (this.activeState != stateBeforeAction) {
                transitionCount++;
                continue; // activeState 已变更，跳过 Normal 检查，重新走 Gate
            }

            // Phase 3: Normal转换检查 - 基于动作结果的转换
            activeStateName = this.getActiveStateName();
            var normalTarget:String = this.transitions.TransitNormal(activeStateName);
            if (normalTarget && normalTarget != activeStateName) {
                this.ChangeState(normalTarget);
                transitionCount++;
                continue; // Normal转换后继续下一轮循环，让新状态也能执行动作
            }

            // 如果既没有Gate转换也没有Normal转换，退出循环
            break;
        }

        if (transitionCount >= maxTransitions) {
            trace("[FSM] Warning: onAction transition loop reached limit (" + maxTransitions + "), possible oscillation");
        }

        // Phase 4: 状态机自身维护
        this.actionCount++; // 增加action计数
        super.onAction(); // 执行状态机自身的 _onActionCb 回调（如有），作为管线后处理
    }

    // ========== 修正区结束 ==========

    public function destroy():Void{
        // 1. 锁定状态切换，防止 onExit 回调触发 ChangeState 干扰销毁流程
        this._isChanging = true;
        this._pending = null;

        // 2. 若已启动，先触发 activeState 的 onExit 生命周期（由内而外）
        if (this._started && this.activeState) {
            this.activeState.onExit();
        }
        this._isChanging = false;
        this._started = false;

        // 3. 销毁所有子状态（instanceof 防御原型链污染）
        for (var statename:String in this.statusDict) {
            var s = this.statusDict[statename];
            if (s instanceof FSM_Status) {
                s.destroy();
            }
        }

        // 4. 清理转换表
        if (this.transitions) {
            this.transitions.reset();
        }

        this.statusDict = null;
        this.activeState = null;
        this.lastState = null;
        this.defaultState = null;

        super.destroy();
    }
}
