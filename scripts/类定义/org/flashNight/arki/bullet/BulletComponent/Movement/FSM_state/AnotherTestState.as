// 文件路径：org/flashNight/arki/bullet/BulletComponent/Movement/FSM_state/AnotherTestState.as

import org.flashNight.neur.StateMachine.FSM_Status;
import org.flashNight.arki.bullet.BulletComponent.Movement.FSMMovement;

class org.flashNight.arki.bullet.BulletComponent.Movement.FSM_state.AnotherTestState extends FSM_Status {
    private var movement:FSMMovement;

    public function AnotherTestState(movement:FSMMovement) {
        super(null, null, null);
        this.movement = movement;
    }

    public function onEnter():Void {
        trace("进入 AnotherTestState 状态");
    }

    public function onAction():Void {
        trace("执行 AnotherTestState 的 onAction");
        // 添加一些测试逻辑，例如改变位置
        if (movement.targetObject != undefined) {
            movement.targetObject._x -= 5;
            movement.targetObject._y -= 5;
        }

        // 模拟循环切换回 TestState
        this.superMachine.ChangeState("TestState");
    }

    public function onExit():Void {
        trace("退出 AnotherTestState 状态");
    }
}
