// 文件路径：org/flashNight/arki/bullet/BulletComponent/Movement/FSM_state/TestState.as

import org.flashNight.neur.StateMachine.FSM_Status;
import org.flashNight.arki.bullet.BulletComponent.Movement.FSMMovement;

class org.flashNight.arki.bullet.BulletComponent.Movement.FSM_state.TestState extends FSM_Status {
    private var movement:FSMMovement;

    public function TestState(movement:FSMMovement) {
        super(null, null, null);
        this.movement = movement;
    }

    public function onEnter():Void {
        trace("进入 TestState 状态");
    }

    public function onAction():Void {
        trace("执行 TestState 的 onAction");
        // 这里可以添加一些测试逻辑，例如改变位置
        if (movement.targetObject != undefined) {
            movement.targetObject._x += 5;
            movement.targetObject._y += 5;
        }

        // 模拟状态转换，例如在执行一次后切换到另一个状态
        this.superMachine.ChangeState("AnotherTestState");
    }

    public function onExit():Void {
        trace("退出 TestState 状态");
    }
}
