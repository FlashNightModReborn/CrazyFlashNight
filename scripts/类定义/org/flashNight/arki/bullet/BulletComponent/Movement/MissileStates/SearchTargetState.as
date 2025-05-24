// 文件路径：org.flashNight.arki.bullet.BulletComponent.Movement.MissileStates.SearchTargetState.as

import org.flashNight.neur.StateMachine.FSM_Status;
import org.flashNight.arki.bullet.BulletComponent.Movement.BaseMissileMovement;

class org.flashNight.arki.bullet.BulletComponent.Movement.MissileStates.SearchTargetState extends FSM_Status {
    private var movement:BaseMissileMovement;

    public function SearchTargetState(movement:BaseMissileMovement) {
        super(null, null, null);
        this.movement = movement;
    }

    public function onEnter():Void {
        trace("进入 SearchTarget 状态");
    }

    public function onAction():Void {
        // 尝试寻找目标
        var found:Boolean = this.movement.searchForTarget();
        if (found) {
            // 切换到 TrackTarget 状态
            this.superMachine.ChangeState("TrackTarget");
        } else {
            // 未找到目标，切换到 FreeFly 状态
            this.superMachine.ChangeState("FreeFly");
        }
    }

    public function onExit():Void {
        trace("退出 SearchTarget 状态");
    }
}
