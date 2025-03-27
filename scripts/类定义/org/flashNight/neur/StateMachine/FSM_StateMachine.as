import org.flashNight.neur.StateMachine.FSM_Status;
import org.flashNight.neur.StateMachine.IMachine;
import org.flashNight.neur.StateMachine.Transitions;

class org.flashNight.neur.StateMachine.FSM_StateMachine extends FSM_Status implements IMachine{
    private var statusDict:Object; // 状态列表
    private var statusCount:Number; // 状态总数
    private var activeState:FSM_Status; // 当前状态
    private var lastState:FSM_Status; // 上个状态
    private var defaultState:FSM_Status; // 默认状态
    private var actionCount:Number = 0; // 当前状态已执行的action次数

    public function FSM_StateMachine(_onAction:Function, _onEnter:Function, _onExit:Function){
        super(_onAction, _onEnter, _onExit);
        this.statusDict = new Object();
        this.statusCount = 0;
        this.actionCount = 0;
        this.transitions = new Transitions(this);
    }

    public function ChangeState(statename:String):Void{
        // trace("state:"+statename);
        if(statename != activeState.name && statusDict[statename]){
            this.actionCount = 0;
            this.activeState.onExit();
            this.lastState = this.activeState;
            this.activeState = this.statusDict[statename];
            this.activeState.onEnter();
        }
    }

    public function getDefaultState():FSM_Status{
        return this.defaultState;
    }
    public function getActiveState():FSM_Status{
        return this.activeState;
    }
    public function setActiveState(state:FSM_Status):Void{
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
        return this.activeState.name;
    }

    public function AddStatus(name:String, state:FSM_Status):Void{
        state.superMachine = this;
        state.name = name;
        state.data = this.data;
        state.OnInit();

        if (this.statusCount == 0) this.defaultState = state;
        this.statusDict[name] = state;
        this.statusCount++;
    }

    public function onAction():Void{
        this.actionCount++;
        super.onAction();
        var statename = this.transitions.Transit(this.getActiveStateName());
        this.ChangeState(statename);
        this.activeState.onAction();
    }

    public function destroy():Void{
        super.destroy();
        //销毁所有子状态机
        for(var statename in this.statusDict){
            this.statusDict[statename].destroy();
        }
        this.statusDict = null;
        this.activeState = null;
        this.lastState = null;
        this.defaultState = null;
        }
}
