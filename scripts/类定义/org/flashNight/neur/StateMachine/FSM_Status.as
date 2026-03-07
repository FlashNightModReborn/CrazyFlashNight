import org.flashNight.neur.StateMachine.IStatus;
import org.flashNight.neur.StateMachine.IMachine;

class org.flashNight.neur.StateMachine.FSM_Status implements IStatus {
	public var name:String; // 状态名称
    public var superMachine:IMachine; // 上级状态机
    public var isDestroyed:Boolean = false; // 该状态是否已销毁
    public var data:Object; // 数据黑板

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

    /**
     * 内联回调优化（Meta-State Polymorphism for leaf states）
     *
     * 仅对非 FSM_StateMachine 的状态调用（由 AddStatus 保证）。
     * 对每个生命周期槽位：
     *   - 回调非 null → 直接赋值为实例属性（消除 if + .call，省 ~1235ns/call）
     *   - 回调为 null → 不动（保留原型方法，兼容子类 override 的场景）
     *
     * this 绑定：cur.onAction() 调用时 this 自然指向 cur（FSM_Status 实例），
     * 与原来 _onActionCb.call(this) 的语义一致。
     *
     * 子类兼容：SearchTargetState 等通过 super(null,null,null) + override 方式
     * 实现生命周期方法。回调为 null 时不设实例属性，原型链上的 override 不受影响。
     */
    public function inlineCallbacks():Void {
        if (this._onActionCb) {
            this.onAction = this._onActionCb;
            this._onActionCb = null;
        }
        if (this._onEnterCb) {
            this.onEnter = this._onEnterCb;
            this._onEnterCb = null;
        }
        if (this._onExitCb) {
            this.onExit = this._onExitCb;
            this._onExitCb = null;
        }
    }

    public function isRootMachine():Boolean {
        return !this.superMachine;
    }

    public function destroy():Void {
        this.isDestroyed = true;
        this.superMachine = null;
        this.data = null;
        this._onActionCb = null;
        this._onEnterCb = null;
        this._onExitCb = null;
        // 若已内联，delete 实例属性恢复原型方法（释放闭包引用）
        delete this.onAction;
        delete this.onEnter;
        delete this.onExit;
    }
}
