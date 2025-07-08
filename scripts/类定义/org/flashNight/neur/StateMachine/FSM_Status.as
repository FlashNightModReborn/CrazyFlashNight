import org.flashNight.neur.StateMachine.IStatus;
import org.flashNight.neur.StateMachine.IMachine;
import org.flashNight.neur.StateMachine.Transitions;

class org.flashNight.neur.StateMachine.FSM_Status implements IStatus {
	public var name:String; // 状态名称
    public var superMachine:IMachine; // 上级状态机
    public var active:Boolean; // 该状态是否激活
    public var isDestroyed:Boolean = false; // 该状态是否已销毁
    public var data:Object; // 数据黑板
    public var transitions:Transitions; // 过渡线

    public function onAction():Void{
    }
    public function onEnter():Void{
    };
    public function onExit():Void{
    };

    public function FSM_Status(_onAction:Function, _onEnter:Function, _onExit:Function){
        this.active = true;
        if(_onAction) this.onAction = _onAction;
        if(_onEnter) this.onEnter = _onEnter;
        if(_onExit) this.onExit = _onExit;
        this.superMachine = null;
    }

    public function isRootMachine():Boolean{
        return !this.superMachine;
    }

    // In FSM_Status.as
    public function OnInit():Void{
        // 此方法逻辑已证明有害，其功能已由 FSM_StateMachine.onEnter 正确实现。
        // 保留空方法以防现有代码调用，或从 FSM_StateMachine.AddStatus 中移除对此方法的调用。
    }

    public function destroy():Void{
        this.isDestroyed = true;
        this.active = false;
        this.superMachine = null;
        this.data = null;
        this.transitions = null;
        this.onAction = null;
        this.onEnter = null;
        this.onExit = null;
    }
}
