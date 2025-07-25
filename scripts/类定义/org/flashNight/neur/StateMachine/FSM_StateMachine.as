﻿import org.flashNight.neur.StateMachine.FSM_Status;
import org.flashNight.neur.StateMachine.IMachine;
import org.flashNight.neur.StateMachine.Transitions;

class org.flashNight.neur.StateMachine.FSM_StateMachine extends FSM_Status implements IMachine {
    private var statusDict:Object; // 状态列表
    private var statusCount:Number; // 状态总数
    private var activeState:FSM_Status; // 当前状态
    private var lastState:FSM_Status; // 上个状态
    private var defaultState:FSM_Status; // 默认状态
    private var actionCount:Number = 0; // 当前状态已执行的action次数
    private var _isChanging:Boolean = false;
    private var _pending:String     = null;

    public function FSM_StateMachine(_onAction:Function, _onEnter:Function, _onExit:Function){
        super(_onAction, _onEnter, _onExit);
        this.statusDict = new Object();
        this.statusCount = 0;
        this.actionCount = 0;
        this.transitions = new Transitions(this);
    }

    public function ChangeState(next:String):Void {
        var target:FSM_Status = this.statusDict[next];
        // 如果目标状态不存在，或者与当前状态相同，则不进行切换
        if (!target || target == this.activeState) return;

        if (_isChanging) {
            _pending = next;
            return;
        }

        _isChanging = true;
        
        // 先退出当前状态
        if (this.activeState) {
            this.activeState.onExit();
        }
        
        this.lastState = this.activeState;
        this.activeState = target;
        
        // 再进入新状态
        if (this.activeState) {
            this.activeState.onEnter();
        }

        _isChanging = false;
        
        if (_pending) {
            var tmp:String = _pending;
            _pending = null;
            ChangeState(tmp);
        }
        this.actionCount = 0;
    }

    public function getDefaultState():FSM_Status{
        return this.defaultState;
    }
    public function getActiveState():FSM_Status{
        return this.activeState;
    }
    public function setActiveState(state:FSM_Status):Void{
        // 此处逻辑修正：直接切换状态应使用ChangeState以触发完整的生命周期
        // 但为了兼容旧API，我们保留此方法，但不触发onEnter/onExit
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

    public function AddStatus(name:String, state:FSM_Status):Void {
        var isNestedMachine:Boolean = (state instanceof FSM_StateMachine);
        
        state.superMachine = this;
        state.name = name;
        
        if (!isNestedMachine) {
            state.data = this.data;
        }
        
        this.statusDict[name] = state;
        this.statusCount++;

        if (this.statusCount == 1) {
            this.defaultState = state;
            // 只有根状态机（没有父级）才应在添加第一个状态时立即激活它。
            // 嵌套状态机应该等待其父级通过 onEnter 来激活它。
            if (this.isRootMachine()) {
                this.activeState = state;
                this.lastState = state;
                // 启动状态机，调用 onEnter 以确保所有嵌套逻辑正确执行
                this.activeState.onEnter();
            }
        }
    }

    // ========== 【核心修正区】 ==========
    // 以下是解决嵌套状态机问题的关键代码。

    /**
     * 当此状态机作为状态被“进入”时调用。
     * 此方法现在能正确地激活和传播事件到其子状态。
     */
    public function onEnter():Void {
        // 1. 首先执行状态机自身的onEnter回调（如果已定义）。
        super.onEnter();
        
        // 2. 检查并激活内部状态。
        //    如果这是第一次进入此嵌套状态机，其activeState将为null。
        //    此时，应将其激活到默认状态。
        if (this.activeState == null && this.defaultState != null) {
            this.activeState = this.defaultState;
            this.lastState = this.defaultState;
        }
        
        // 3. 将onEnter事件传播到当前激活的子状态。
        //    这确保了无论是首次进入还是重新进入，子状态都能收到通知。
        if (this.activeState != null) {
            this.activeState.onEnter();
        }
    }

    /**
     * 当此状态机作为状态被“退出”时调用。
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
     */
    public function onAction():Void {
        // 1. 如果有激活的子状态，则首先执行子状态的onAction。
        if (this.activeState) {
            this.activeState.onAction();
        }
        // 2. 更新状态计数。
        this.actionCount++;

        // 3. 检查并执行此状态机级别的过渡。
        //    注意：过渡是基于子状态的名称。
        var currentSubStateName:String = this.getActiveStateName();
        if (currentSubStateName != null) {
            var nextStateName:String = this.transitions.Transit(currentSubStateName);
            if (nextStateName != null) {
                this.ChangeState(nextStateName);
            }
        }
        
        // 3. 最后，执行状态机自身的onAction回调（如果已定义）（实际上没有定义）。
        super.onAction();
    }
    // ========== 修正区结束 ==========

    public function destroy():Void{    
        this._pending = null;
        this._isChanging = false;
        
        super.destroy();
        for(var statename in this.statusDict){
            this.statusDict[statename].destroy();
        }
        this.statusDict = null;
        this.activeState = null;
        this.lastState = null;
        this.defaultState = null;
    }
}