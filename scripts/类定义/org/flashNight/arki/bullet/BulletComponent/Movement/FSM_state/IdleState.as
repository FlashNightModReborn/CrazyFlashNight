import org.flashNight.neur.StateMachine.FSM_Status;
import org.flashNight.arki.bullet.BulletComponent.Movement.FSMMovement;

class org.flashNight.arki.bullet.BulletComponent.Movement.FSM_state.IdleState extends FSM_Status {
    private var movement:FSMMovement;
    
    public function IdleState(movement:FSMMovement) {
        super(null, null, null);
        this.movement = movement;
    }
    
    public function onEnter():Void {
        trace("Enter Idle State");
    }
    
    public function onAction():Void {
        trace("Idle State Action");
        // 模拟条件，切换到 MoveState
        if (Key.isDown(Key.SPACE)) {
            this.superMachine.ChangeState("MoveState");
        }
    }
    
    public function onExit():Void {
        trace("Exit Idle State");
    }
}