import org.flashNight.neur.StateMachine.*;

class org.flashNight.arki.bullet.BulletComponent.Movement.MissileFSM.TrackTargetState extends FSM_Status {
    private var missile:MissileBulletMovement;

    public function TrackTargetState(missile:MissileBulletMovement) {
        super(null, null, null);
        this.missile = missile;
    }

    public function onAction():Void {
        // 执行追踪目标的逻辑
        missile.trackTarget();
        if (missile.hasReachedTarget()) {
            // 达到目标，转换到爆炸状态
            this.superMachine.ChangeState("Explode");
        } else if (missile.shouldDestroy()) {
            // 无法继续追踪，转换到销毁状态
            this.superMachine.ChangeState("Destroy");
        }
    }
}
