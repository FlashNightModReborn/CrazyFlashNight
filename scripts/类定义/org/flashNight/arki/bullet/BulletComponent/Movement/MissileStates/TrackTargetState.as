// 文件路径：org.flashNight.arki.bullet.BulletComponent.Movement.MissileStates.TrackTargetState.as

import org.flashNight.neur.StateMachine.FSM_Status;
import org.flashNight.arki.bullet.BulletComponent.Movement.BaseMissileMovement;

class org.flashNight.arki.bullet.BulletComponent.Movement.MissileStates.TrackTargetState extends FSM_Status {
    private var movement:BaseMissileMovement;

    public function TrackTargetState(movement:BaseMissileMovement) {
        super(null, null, null);
        this.movement = movement;
    }

    public function onEnter():Void {
        trace("进入 TrackTarget 状态");
    }

    public function onAction():Void {
        // 追踪目标
        this.movement.trackTarget();
        // 如果目标丢失，切换回 SearchTarget 状态
        if (!this.movement.hasTarget) {
            this.superMachine.ChangeState("SearchTarget");
        }
    }

    public function onExit():Void {
        trace("退出 TrackTarget 状态");
    }
}
