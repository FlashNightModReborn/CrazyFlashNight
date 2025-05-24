// 文件路径：org.flashNight.arki.bullet.BulletComponent.Movement.MissileStates.PreLaunchState.as

import org.flashNight.neur.StateMachine.FSM_Status;
import org.flashNight.arki.bullet.BulletComponent.Movement.BaseMissileMovement;

class org.flashNight.arki.bullet.BulletComponent.Movement.MissileStates.PreLaunchState extends FSM_Status {
    private var movement:BaseMissileMovement;

    public function PreLaunchState(movement:BaseMissileMovement) {
        super(null, null, null);
        this.movement = movement;
    }

    public function onEnter():Void {
        // 初始化 PreLaunch 状态的参数
        trace("进入 PreLaunch 状态");
    }

    public function onAction():Void {
        // 调用发射前运动逻辑
        this.movement.preLaunchMove();
        // 判断是否结束 PreLaunch 状态
        if (this.movement.isPreLaunchComplete()) {
            // 切换到 Initialize 状态
            this.superMachine.ChangeState("Initialize");
        }
    }

    public function onExit():Void {
        trace("退出 PreLaunch 状态");
        // 需要时清理或重置参数
    }
}
