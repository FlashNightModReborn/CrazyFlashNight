// 文件路径：org.flashNight.arki.bullet.BulletComponent.Movement.MissileStates.FreeFlyState.as

import org.flashNight.neur.StateMachine.FSM_Status;
import org.flashNight.arki.bullet.BulletComponent.Movement.BaseMissileMovement;

class org.flashNight.arki.bullet.BulletComponent.Movement.MissileStates.FreeFlyState extends FSM_Status {
    private var movement:BaseMissileMovement;
    private var searchRetryFrames:Number;

    public function FreeFlyState(movement:BaseMissileMovement) {
        super(null, null, null);
        this.movement = movement;
    }

    public function onEnter():Void {
        trace("进入 FreeFly 状态");
        this.searchRetryFrames = 0;
    }

    public function onAction():Void {
        // 执行自由飞行逻辑
        this.movement.freeFly();
        // Empty/exhausted searches do not scan the entire target cache every frame.
        // Movement and the existing 150-frame lifetime continue in MissileMovement.
        if (++this.searchRetryFrames >= 8) this.superMachine.ChangeState("SearchTarget");
    }

    public function onExit():Void {
        trace("退出 FreeFly 状态");
    }
}
