// 文件路径：org.flashNight.arki.bullet.BulletComponent.Movement.MissileStates.InitializeState.as

import org.flashNight.neur.StateMachine.FSM_Status;
import org.flashNight.arki.bullet.BulletComponent.Movement.BaseMissileMovement;

class org.flashNight.arki.bullet.BulletComponent.Movement.MissileStates.InitializeState extends FSM_Status {
    private var movement:BaseMissileMovement;

    public function InitializeState(movement:BaseMissileMovement) {
        super(null, null, null);
        this.movement = movement;
    }

    public function onEnter():Void {
        trace("进入 Initialize 状态");
        // 调用初始化导弹参数
        this.movement.initializeMissile();
        // 切换到 SearchTarget 状态
        this.superMachine.ChangeState("SearchTarget");
    }

    public function onAction():Void {
        // Initialize 状态通常不需要 onAction
    }

    public function onExit():Void {
        trace("退出 Initialize 状态");
    }
}
