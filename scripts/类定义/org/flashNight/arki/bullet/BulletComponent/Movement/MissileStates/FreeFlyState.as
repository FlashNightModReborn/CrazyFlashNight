// 文件路径：org.flashNight.arki.bullet.BulletComponent.Movement.MissileStates.FreeFlyState.as

import org.flashNight.neur.StateMachine.FSM_Status;
import org.flashNight.arki.bullet.BulletComponent.Movement.BaseMissileMovement;

class org.flashNight.arki.bullet.BulletComponent.Movement.MissileStates.FreeFlyState extends FSM_Status {
    private var movement:BaseMissileMovement;

    public function FreeFlyState(movement:BaseMissileMovement) {
        super(null, null, null);
        this.movement = movement;
    }

    public function onEnter():Void {
        trace("进入 FreeFly 状态");
    }

    public function onAction():Void {
        // 执行自由飞行逻辑
        this.movement.freeFly();
        // 可选：再次尝试寻找目标或判断导弹是否需要销毁
    }

    public function onExit():Void {
        trace("退出 FreeFly 状态");
    }
}
