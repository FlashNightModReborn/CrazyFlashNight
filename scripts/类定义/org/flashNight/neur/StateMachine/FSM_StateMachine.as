import org.flashNight.neur.StateMachine.FSM_Status;
import org.flashNight.neur.StateMachine.IMachine;
import org.flashNight.neur.StateMachine.Transitions;

/**
 * FSM_StateMachine — 分层有限状态机（HFSM）
 *
 * ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 *  契约总览（维护者必读）
 * ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 *
 * 【C1 — 生命周期阶段】
 *
 *   构建期      ─ new → AddStatus → [ChangeState] → start()
 *   运行期      ─ start() 之后，onAction / ChangeState 正常工作
 *   退出/重入期 ─ 被上级 ChangeState 退出后，可被再次 onEnter 重新激活
 *   终态        ─ destroy() 之后不可复用（所有公共入口被封为空操作）
 *
 *   ChangeState 在不同阶段有不同语义（Meta-State Polymorphism）:
 *     构建期 / onEnter回调中 → _csInit  — 仅移指针，不触发 onExit/onEnter
 *     运行期               → _csRun   — 完整 4 阶段管线
 *     _csRun 管线执行中     → _csPend  — 记录目标名，由 while 循环消费
 *     onExit / destroy 中  → _csNoop  — 静默丢弃
 *
 * 【C2 — 回调契约（最重要）】
 *
 *   所有用户回调（onAction/onEnter/onExit 的 callback）必须满足：
 *
 *   a) 不得抛出异常。
 *      原因：_csRun 入口将 ChangeState 替换为 _csPend，异常会跳过末尾的
 *      恢复语句（this.ChangeState = this._csRun），导致状态机永久锁死为
 *      _csPend——后续所有 ChangeState 调用仅设 _pending 而无人消费，
 *      表现为"单位卡死在当前状态"。onAction 不受影响但无法转换。
 *      （本设计有意不加 try/catch 以保持热路径零开销。）
 *
 *   b) onExit 回调中可以调用 ChangeState 实现重定向，
 *      但仅最后一次调用生效（_csPend 覆盖语义）。
 *
 *   c) onEnter 回调中可以调用 ChangeState 实现链式切换，
 *      同样仅最后一次生效，while 循环最多展开 maxChain=10 步。
 *
 *   d) 不得从回调中调用 destroy()。destroy 有独立的锁机制。
 *
 * 【C3 — AddStatus 契约】
 *
 *   a) name 不可为 null / 空字符串。
 *   b) state 必须是 FSM_Status 实例（instanceof 校验）。
 *   c) name 不可为 Object 原型链保留名（toString/constructor 等），
 *      见 RESERVED 静态表。违反上述任一条件，AddStatus 静默拒绝并 trace 报错。
 *   d) machine.data 必须在首次 AddStatus 之前设定（非嵌套子状态会继承 data 引用）。
 *   e) 嵌套子机（FSM_StateMachine）不继承父机 data，需自行管理。
 *
 * 【C4 — ChangeState 4 阶段管线（_csRun）】
 *
 *   Phase A: 退出当前状态 — _pending=null → cur.onExit()（可设 _pending）
 *   Phase B: onExit 重定向 — 若 _pending 有效且不同于 cur，覆盖 target
 *   Phase C: 进入新状态   — lastState=cur, activeState=target, actionCount=0
 *   Phase D: onEnter 链   — _pending=null → target.onEnter()（可设 _pending）
 *            若 _pending 有效，while 继续（最多 maxChain=10 步）
 *
 *   自转换（target == cur）在入口即被拒绝，不触发任何生命周期。
 *
 * 【C5 — onAction 管线（_oaRun）】
 *
 *   Phase 1: Gate 转换检查（动作前，即时阻断）
 *   Phase 2: 执行 cur.onAction()（可内部调用 ChangeState）
 *   Phase 3: Normal 转换检查（动作后，条件转换）
 *   Phase 4: actionCount++ + super.onAction()（机器级回调）
 *
 *   任一 Phase 导致 activeState 变化 → continue 回到 Phase 1（最多 10 次）。
 *   Gate/Normal 返回无效目标 → ChangeState 静默失败 → break 跳出循环，
 *   该帧的 Phase 2 action 不执行（Gate 场景）或已执行（Normal 场景）。
 *
 * 【C6 — 嵌套机约束】
 *
 *   a) 嵌套子机的 onEnter/onExit 由父机管线自动调用，不需手动 start()。
 *   b) 子状态 onAction/onExit 中可通过 this.superMachine.ChangeState()
 *      切换父机状态，但不得跨越两级以上（祖父机）。
 *      跨级调用不会崩溃，但会导致已退出的中间层在当前帧残余执行。
 *   c) destroy() 若已启动：先 cur.onExit()（子状态退出），再 super.onExit()
 *      （machine-level 回调），最后递归销毁所有子状态。
 *   d) destroy() 结束后，start/onEnter/onExit/AddStatus/ChangeState/onAction
 *      全部被方法替换为空操作，防止误调用导致"部分复活"。
 *
 * 【C7 — 异常安全等级】
 *
 *   本系统采用"契约优先，无 try/catch"策略。
 *   回调抛异常 → _csRun 永久锁死（见 C2a）。
 *   恢复手段：外部调用 delete machine.ChangeState 可回退到原型方法（pointer-only），
 *   机器可继续运行但只有 pointer-only 切换语义。
 *
 * ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 */
class org.flashNight.neur.StateMachine.FSM_StateMachine extends FSM_Status implements IMachine {

    // ═══════ 字段声明 ═══════

    public var statusDict:Object;           // 状态列表（public: BaseUnitBehavior/EnemyBehavior 需外部访问）
    public var transitions:Transitions;     // 过渡线（仅状态机需要，从 FSM_Status 移至此处）
    private var activeState:FSM_Status;     // 当前状态
    private var lastState:FSM_Status;       // 上个状态
    private var defaultState:FSM_Status;    // 默认状态
    public var actionCount:Number = 0;      // 当前状态已执行的action次数（public: 外部消费者需读取）
    private var _booted:Boolean = false;    // start() 幂等守卫
    private var _started:Boolean = false;   // destroy() 生命周期守卫（不在热路径中）
    private var _pending:String = null;     // 重入挂起目标

    /**
     * 保留名黑名单：Object 原型链上的属性名不可用作状态名。
     * 在 AddStatus 中一次性校验，零运行时开销。
     */
    private static var RESERVED:Object = {
        toString: 1, constructor: 1, __proto__: 1,
        valueOf: 1, hasOwnProperty: 1, isPrototypeOf: 1,
        propertyIsEnumerable: 1, toLocaleString: 1
    };

    // ═══════ 构造函数 ═══════

    public function FSM_StateMachine(_onAction:Function, _onEnter:Function, _onExit:Function) {
        super(_onAction, _onEnter, _onExit);
        this.statusDict = new Object();
        this.actionCount = 0;
        this.transitions = new Transitions(this);

        // Meta-State Polymorphism: 初始态——仅指针移动，不触发生命周期
        this.ChangeState = this._csInit;
        this.onAction = this._oaNoop;
    }

    // ═══════════════════════════════════════════════════
    //  Meta-State Polymorphism — 方法变体
    //
    //  通过实例属性遮蔽原型方法，消除热路径中的分支判断。
    //  状态机生命周期各阶段切换不同的方法实现：
    //
    //  ChangeState 变体：
    //    ┌─ 构造/onExit后 ─→ _csInit  (指针移动)
    //    ├─ 运行中        ─→ _csRun   (完整4阶段管线)
    //    ├─ _csRun管线内  ─→ _csPend  (挂起重入)
    //    └─ onExit/destroy ─→ _csNoop  (静默吞掉)
    //
    //  onAction 变体：
    //    ├─ 未启动        ─→ _oaNoop  (空操作)
    //    └─ 运行中        ─→ _oaRun   (Gate→Action→Normal)
    // ═══════════════════════════════════════════════════

    /**
     * 构建期 ChangeState：仅移动指针，不触发 onExit/onEnter 生命周期。
     * 用于 start() 之前的状态预设和 onEnter 回调中的安全切换 (Risk A fix)。
     */
    private function _csInit(next:String):Void {
        var target:FSM_Status = this.statusDict[next];
        var cur:FSM_Status = this.activeState;
        if (!(target instanceof FSM_Status) || target == cur) return;
        this.lastState = cur;
        this.activeState = target;
        this.actionCount = 0;
    }

    /**
     * 运行期 ChangeState：完整 4 阶段管线，while 循环替代递归。
     * 入口自动切换为 _csPend 捕获重入请求，退出时恢复为 _csRun。
     *
     * Phase A: 退出当前状态（_pending 清零后调 onExit，onExit 可设 _pending）
     * Phase B: 检查 onExit 重定向（若 _pending 有效则覆盖 target）
     * Phase C: 进入新状态（更新 activeState/lastState/actionCount）
     * Phase D: 检查 onEnter 链式切换（若 _pending 有效则继续循环）
     *
     * 契约：调用者保证 next 是已通过 AddStatus 注册的合法状态名。
     */
    private function _csRun(next:String):Void {
        var dict:Object = this.statusDict;
        var target:FSM_Status = dict[next];
        var cur:FSM_Status = this.activeState;
        if (!(target instanceof FSM_Status) || target == cur) return;

        this.ChangeState = this._csPend;
        var maxChain:Number = 10;
        var chainCount:Number = 0;
        var p:String;

        do {
            // ── Phase A: 退出当前状态 ──
            this._pending = null;
            if (cur) {
                cur.onExit();
                // onExit 回调可能调用 _csPend → 设置 this._pending
            }

            // ── Phase B: onExit 重定向检查 ──
            p = this._pending;
            if (p != null) {
                var exitRedirect:FSM_Status = dict[p];
                if (exitRedirect instanceof FSM_Status && exitRedirect != cur) {
                    target = exitRedirect;
                    next = p;
                    chainCount++;
                }
                this._pending = null;
            }

            // ── Phase C: 进入新状态 ──
            this.lastState = cur;
            this.activeState = target;
            this.actionCount = 0;
            cur = target;

            // ── Phase D: onEnter 链式切换检查 ──
            this._pending = null;
            cur.onEnter();
            // onEnter 回调可能调用 _csPend → 设置 this._pending

            p = this._pending;
            if (p != null) {
                next = p;
                this._pending = null;
                target = dict[next];
                chainCount++;
            } else {
                break;
            }
        } while ((target instanceof FSM_Status) && target != cur && chainCount < maxChain);

        if (chainCount >= maxChain) {
            trace("[FSM] Warning: ChangeState chain reached limit (" + maxChain + "), possible oscillation. last=" + next);
        }

        this.ChangeState = this._csRun;
    }

    /**
     * 重入挂起：在 _csRun 管线执行期间被调用时，仅记录目标名，不递归。
     */
    private function _csPend(next:String):Void {
        _pending = next;
    }

    /**
     * 空操作：onExit/destroy 期间静默吞掉所有 ChangeState 请求。
     */
    private function _csNoop(next:String):Void {
    }

    /**
     * 空操作：start() 之前不执行任何动作。
     */
    private function _oaNoop():Void {
    }

    /**
     * 运行期 onAction：Gate→Action→Normal 4 阶段管线。
     *
     * Phase 1: Gate转换检查（动作前，即时阻断）
     * Phase 2: 执行当前状态动作
     * Phase 3: Normal转换检查（动作后，条件转换）
     * Phase 4: 状态机自身维护（actionCount + machine-level callback）
     */
    private function _oaRun():Void {
        var cur:FSM_Status = this.activeState;
        if (!cur) return;

        var trans:Transitions = this.transitions;
        var maxTransitions:Number = 10;
        var transitionCount:Number = 0;
        var sn:String;
        var tn:String;

        do {
            // Phase 1: Gate转换检查 - 门转换优先，立即生效
            sn = cur.name;
            tn = trans.TransitGate(sn);
            if (tn && tn != sn) {
                this.ChangeState(tn);
                if (this.activeState != cur) {
                    cur = this.activeState;
                    transitionCount++;
                    continue;
                }
                break;
            }

            // Phase 2: 执行当前状态动作
            cur.onAction();
            if (this.activeState != cur) {
                cur = this.activeState;
                transitionCount++;
                continue;
            }

            // Phase 3: Normal转换检查 - 基于动作结果的转换
            // sn 仍有效：同一状态，name 不变
            tn = trans.TransitNormal(sn);
            if (tn && tn != sn) {
                this.ChangeState(tn);
                if (this.activeState != cur) {
                    cur = this.activeState;
                    transitionCount++;
                    continue;
                }
                break;
            }

            break;
        } while (transitionCount < maxTransitions);

        if (transitionCount >= maxTransitions) {
            trace("[FSM] Warning: onAction transition loop reached limit (" + maxTransitions + "), possible oscillation");
        }

        // Phase 4: 状态机自身维护
        this.actionCount++;
        super.onAction();
    }

    // ═══════ 原型 ChangeState（接口合规 + 安全回退）═══════

    /**
     * 原型 ChangeState：指针移动语义（同 _csInit）。
     * 正常运行时被实例属性遮蔽，不会被调用。
     * 保留此定义用于：
     * 1. IMachine 接口编译合规
     * 2. delete 后的安全回退（降级为 pointer-only）
     */
    public function ChangeState(next:String):Void {
        var target:FSM_Status = this.statusDict[next];
        var cur:FSM_Status = this.activeState;
        if (!(target instanceof FSM_Status) || target == cur) return;
        this.lastState = cur;
        this.activeState = target;
        this.actionCount = 0;
    }

    // ═══════ Accessors ═══════

    public function getDefaultState():FSM_Status {
        return this.defaultState;
    }

    public function getActiveState():FSM_Status {
        return this.activeState;
    }

    public function getLastState():FSM_Status {
        return this.lastState;
    }

    public function getActiveStateName():String {
        return this.activeState ? this.activeState.name : null;
    }

    // ═══════ AddStatus ═══════

    /**
     * 添加子状态到状态机。
     * data 黑板按引用赋值给非嵌套子状态。
     * 约束：machine.data 必须在第一次 AddStatus 调用之前设定。
     */
    public function AddStatus(name:String, state:FSM_Status):Void {
        if (!name) {
            trace("[FSM] Error: State name cannot be null or empty.");
            return;
        }
        if (!(state instanceof FSM_Status)) {
            trace("[FSM] Error: State must be an instance of FSM_Status.");
            return;
        }
        if (RESERVED[name] === 1) {
            trace("[FSM] Error: '" + name + "' is a reserved name (Object prototype). Choose another.");
            return;
        }

        var isNestedMachine:Boolean = (state instanceof FSM_StateMachine);
        state.superMachine = this;
        state.name = name;
        if (!isNestedMachine) {
            state.data = this.data;
        }

        this.statusDict[name] = state;

        if (this.defaultState == null) {
            this.defaultState = state;
            this.activeState = state;
            this.lastState = state;
        }
    }

    // ═══════ Lifecycle ═══════

    /**
     * 显式启动状态机。
     * 将构建期与启动期分离：AddStatus 只做数据挂接，start() 统一触发首次 onEnter。
     */
    public function start():Void {
        if (this._booted) return;

        if (this.activeState == null && this.defaultState != null) {
            this.activeState = this.defaultState;
            this.lastState = this.defaultState;
        }
        this.onEnter();
    }

    /**
     * 当此状态机作为状态被"进入"时调用。
     * 激活并传播事件到子状态。
     *
     * 合法调用者：
     *   1. start()          — 顶层首次启动（_booted 守卫确保幂等）
     *   2. 父机 _csRun Phase D — 嵌套子机被父机管线进入
     *
     * 调用前提：_booted == false && _started == false
     *   （由 onExit() 重置或初始构造保证；父机管线自动满足此前提。）
     *
     * _booted 在 super.onEnter() 之前设为 true（两条路径的唯一赋值点）：
     *   1. 阻止 super.onEnter() 回调重入 start()（单线程下唯一重入窗口）
     *   2. 覆盖路径 2（嵌套入口不经 start()），确保后续 start() 幂等
     */
    public function onEnter():Void {
        // 1. 幂等守卫：两条路径的唯一赋值点
        //    必须在 super.onEnter() 之前：阻止回调经 start() 重入
        this._booted = true;

        // 2. Machine-level onEnter 回调
        //    此时 ChangeState 仍为 _csInit → 回调中的 ChangeState 走指针移动路径 (Risk A fix)
        super.onEnter();

        // 3. 激活：切换到运行态方法
        this._started = true;
        this.ChangeState = this._csRun;
        this.onAction = this._oaRun;

        // 4. 确保 activeState 有效，缓存到本地寄存器
        var cur:FSM_Status = this.activeState;
        if (cur == null) {
            cur = this.defaultState;
            if (cur != null) {
                this.activeState = cur;
                this.lastState = cur;
            }
        }

        // 5. 传播 onEnter 到当前激活的子状态
        //    此时 ChangeState = _csRun，子状态 onEnter 中的 ChangeState 走完整管线
        //    （满足 InitializeState 等消费者的需求）
        if (cur != null) {
            cur.onEnter();
        }
    }

    /**
     * 当此状态机作为状态被"退出"时调用。
     * 契约：退出期间禁止内部 ChangeState，请求被静默丢弃。
     */
    public function onExit():Void {
        // 1. 锁定：ChangeState → noop（退出期间吞掉所有切换请求）
        this.ChangeState = this._csNoop;

        // 2. 传播 onExit 到当前激活的子状态（由内而外）
        var cur:FSM_Status = this.activeState;
        if (cur != null) {
            cur.onExit();
        }

        // 3. 丢弃退出期间产生的 pending
        this._pending = null;

        // 4. Machine-level onExit 回调
        super.onExit();

        // 5. 停用：切换回初始态方法
        this._pending = null;
        this.ChangeState = this._csInit;
        this.onAction = this._oaNoop;

        // 6. 重置生命周期标志（可被重新 start/onEnter）
        this._booted = false;
        this._started = false;
    }

    /**
     * 终态销毁 - 释放全部资源。
     * 契约：销毁期间禁止内部 ChangeState；销毁后所有公共入口被封为空操作。
     */
    public function destroy():Void {
        // 1. 锁定
        this.ChangeState = this._csNoop;
        this.onAction = this._oaNoop;
        this._pending = null;

        // 2. 若已启动，传播 onExit 并触发 machine-level 回调
        if (this._started) {
            var cur:FSM_Status = this.activeState;
            if (cur) {
                cur.onExit();                // 子状态退出
            }
            this._pending = null;            // 清除子状态 onExit 中可能产生的 pending
            super.onExit();                  // P0-2: machine-level onExit 回调（与 onExit() 对称）
        }

        // 3. 重置
        this._booted = false;
        this._started = false;

        // 4. 销毁所有子状态（instanceof 防御原型链污染）
        var dict:Object = this.statusDict;
        for (var statename:String in dict) {
            var s:FSM_Status = dict[statename];
            if (s instanceof FSM_Status) {
                s.destroy();
            }
        }

        // 5. 清理转换表
        var t:Transitions = this.transitions;
        if (t) {
            t.destroy();
        }

        // 6. 释放引用
        this.statusDict = null;
        this.transitions = null;
        this.activeState = null;
        this.lastState = null;
        this.defaultState = null;

        super.destroy();

        // 7. P0-1: 终态封印 — 防止 destroy 后误调用导致"部分复活"
        //    与 ChangeState/_csNoop、onAction/_oaNoop 同源的方法替换模式
        var sealed:Function = this._oaNoop;
        this.start = sealed;
        this.onEnter = sealed;
        this.onExit = sealed;
        this.AddStatus = sealed;
    }
}
