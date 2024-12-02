import org.flashNight.neur.StateMachine.*;

class org.flashNight.arki.bullet.BulletComponent.Movement.MissileFSM.SearchTargetState extends FSM_Status {
    private var missile:MissileBulletMovement;

    public function SearchTargetState(missile:MissileBulletMovement) {
        super(null, null, null);
        this.missile = missile;
    }

    public function onAction():Void {
        // 执行寻找目标的逻辑
        var found:Boolean = missile.findAttackTarget();
        if (found) {
            // 找到目标，请求转换到追踪目标状态
            this.superMachine.ChangeState("TrackTarget");
        } else if (missile.shouldDestroy()) {
            // 未找到目标且需要销毁，转换到销毁状态
            this.superMachine.ChangeState("Destroy");
        } else {
            // 更新导弹位置
            missile.updateMovementWithoutTarget();
        }
    }
}
