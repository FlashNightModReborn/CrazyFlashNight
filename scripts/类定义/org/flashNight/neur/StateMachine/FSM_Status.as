import org.flashNight.neur.StateMachine.IStatus;
import org.flashNight.neur.StateMachine.IMachine;
import org.flashNight.neur.StateMachine.Transitions;

class org.flashNight.neur.StateMachine.FSM_Status implements IStatus {
	public var name:String; // 状态名称
    public var superMachine:IMachine; // 上级状态机
    public var isDestroyed:Boolean = false; // 该状态是否已销毁
    public var data:Object; // 数据黑板
    public var transitions:Transitions; // 过渡线

    // Path B: 回调存储在私有字段中，类方法作为包装器。
    // 这确保子类（如 FSM_StateMachine）override 的 onAction/onEnter/onExit
    // 不会被构造函数传入的回调通过实例属性覆写而"穿透"。
    private var _onActionCb:Function;
    private var _onEnterCb:Function;
    private var _onExitCb:Function;

    public function onAction():Void {
        if (_onActionCb) _onActionCb.call(this);
    }

    public function onEnter():Void {
        if (_onEnterCb) _onEnterCb.call(this);
    }

    public function onExit():Void {
        if (_onExitCb) _onExitCb.call(this);
    }

    public function FSM_Status(_onAction:Function, _onEnter:Function, _onExit:Function) {
        this._onActionCb = _onAction;
        this._onEnterCb = _onEnter;
        this._onExitCb = _onExit;
        this.superMachine = null;
    }

    public function isRootMachine():Boolean {
        return !this.superMachine;
    }

    public function destroy():Void {
        this.isDestroyed = true;
        this.superMachine = null;
        this.data = null;
        this.transitions = null;
        this._onActionCb = null;
        this._onEnterCb = null;
        this._onExitCb = null;
    }
}
