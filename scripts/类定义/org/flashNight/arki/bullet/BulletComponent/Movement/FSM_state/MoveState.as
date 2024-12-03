import org.flashNight.neur.StateMachine.FSM_Status;
import org.flashNight.arki.bullet.BulletComponent.Movement.FSMMovement;

class org.flashNight.arki.bullet.BulletComponent.Movement.FSM_state.MoveState extends FSM_Status {
    private var movement:FSMMovement;
    
    public function MoveState(movement:FSMMovement) {
        super(null, null, null);
        this.movement = movement;
    }
    
    public function onEnter():Void {
        trace("Enter Move State");
    }
    
    public function onAction():Void {
        trace("Move State Action");
        // 更新移动对象的位置
        this.movement.targetObject._x += 5;
        // 当对象移动到一定位置时，切换回 IdleState
        if (this.movement.targetObject._x > 300) {
            this.superMachine.ChangeState("IdleState");
        }
    }
    
    public function onExit():Void {
        trace("Exit Move State");
    }
}