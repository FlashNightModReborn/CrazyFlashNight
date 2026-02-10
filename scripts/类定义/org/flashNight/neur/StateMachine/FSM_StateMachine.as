import org.flashNight.neur.StateMachine.FSM_Status;
import org.flashNight.neur.StateMachine.IMachine;
import org.flashNight.neur.StateMachine.Transitions;

class org.flashNight.neur.StateMachine.FSM_StateMachine extends FSM_Status implements IMachine {
    public var statusDict:Object; // 状态列表（public: BaseUnitBehavior/EnemyBehavior 需外部访问）
    private var statusCount:Number; // 状态总数
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
        this.statusCount = 0;
        this.actionCount = 0;
        this.transitions = new Transitions(this);
    }

    /**
     * 状态切换 - 使用 while 循环替代递归以避免栈溢出风险。
     * 当 onEnter/onExit 中触发新的 ChangeState 时，新请求被暂存到 _pending，
     * 循环回来处理，而非递归调用。
     */
    public function ChangeState(next:String):Void {
        var target:FSM_Status = this.statusDict[next];
        // instanceof 防止 Object.prototype 属性穿透（如 toString/constructor）
        if (!(target instanceof FSM_Status) || target == this.activeState) return;

        if (_isChanging) {
            // 在 onEnter/onExit 回调中触发的 ChangeState，暂存而非递归
            _pending = next;
            return;
        }

        _isChanging = true;
        // 用 while 循环处理连锁切换（原递归展开为迭代）
        var maxChain:Number = 10; // 安全上限，防止无限连锁
        var chainCount:Number = 0;

        while ((target instanceof FSM_Status) && target != this.activeState && chainCount < maxChain) {
            // 先退出当前状态
            if (this.activeState) {
                this.activeState.onExit();
            }

            this.lastState = this.activeState;
            this.activeState = target;
            this.actionCount = 0;

            // 再进入新状态（onEnter 可能设置 _pending）
            _pending = null;
            if (this.activeState) {
                this.activeState.onEnter();
            }

            // 检查 onEnter 中是否触发了新的 ChangeState
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
            trace("[FSM] Warning: ChangeState chain reached limit (" + maxChain + "), possible oscillation");
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
        this.statusCount++;

        if (this.statusCount == 1) {
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
     */
    public function onExit():Void {
        // 1. 首先将onExit事件传播到当前激活的子状态（由内而外）。
        if (this.activeState != null) {
            this.activeState.onExit();
        }

        // 2. 然后执行状态机自身的onExit回调（如果已定义）。
        super.onExit();
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
        if (!this.activeState) return;

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
        this._pending = null;
        this._isChanging = false;
        this._started = false;

        // 先销毁子状态，再销毁自身（由内而外）
        for(var statename:String in this.statusDict){
            this.statusDict[statename].destroy();
        }
        this.statusDict = null;
        this.activeState = null;
        this.lastState = null;
        this.defaultState = null;

        super.destroy();
    }
}
