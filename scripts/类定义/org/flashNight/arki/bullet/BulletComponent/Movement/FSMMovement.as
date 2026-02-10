// 文件路径：org.flashNight.arki.bullet.BulletComponent.Movement.FSMMovement.as

import org.flashNight.neur.StateMachine.*;
import org.flashNight.arki.bullet.BulletComponent.Movement.IMovement;
import mx.utils.Delegate;

class org.flashNight.arki.bullet.BulletComponent.Movement.FSMMovement implements IMovement {
    // 状态机实例
    public var stateMachine:FSM_StateMachine;

    // 引用移动对象（例如子弹的影片剪辑）
    public var targetObject:MovieClip;

    /**
     * 构造函数
     * 子类可以传入参数以定制移动组件
     */
    public function FSMMovement() {
        // 初始化状态机
        this.stateMachine = new FSM_StateMachine(null, null, null);
        this.stateMachine.data = {}; // 可选的数据黑板

        // 初始化状态
        this.initializeStates();
    }

    /**
     * 初始化状态（供子类覆盖）
     */
    public function initializeStates():Void {
        // 子类实现，添加状态和状态转换
    }

    /**
     * 更新移动逻辑，每帧调用
     * @param target:MovieClip 要移动的目标对象
     */
    public function updateMovement(target:MovieClip):Void {
        this.targetObject = target;
        this.stateMachine.onAction();
    }

    /**
     * 改变状态
     * @param stateName:String 要切换到的状态名
     */
    public function changeState(stateName:String):Void {
        this.stateMachine.ChangeState(stateName);
    }

    /**
     * 获取当前状态名
     * @return String 当前状态名
     */
    public function getCurrentStateName():String {
        return this.stateMachine.getActiveStateName();
    }

    /**
     * 添加状态
     * @param stateName:String 状态名
     * @param state:FSM_Status 状态实例
     */
    public function addState(stateName:String, state:FSM_Status):Void {
        // superMachine/name/data 由 AddStatus 内部统一赋值，无需预设
        this.stateMachine.AddStatus(stateName, state);
    }
}


/*

// 导入必要的类和接口
import org.flashNight.neur.StateMachine.*;
import org.flashNight.arki.bullet.BulletComponent.Movement.*;
import org.flashNight.arki.bullet.BulletComponent.Movement.FSM_state.*;

// 创建一个影片剪辑，作为移动对象
var mc:MovieClip = _root.createEmptyMovieClip("mc", _root.getNextHighestDepth());
mc.beginFill(0xFF0000);
mc.moveTo(-10, -10);
mc.lineTo(10, -10);
mc.lineTo(10, 10);
mc.lineTo(-10, 10);
mc.lineTo(-10, -10);
mc.endFill();
mc._x = 50;
mc._y = Stage.height / 2;

// 创建 FSMMovement 的实例
var movement:FSMMovement = new FSMMovement();

// 添加状态
var idleState:IdleState = new IdleState(movement);
var moveState:MoveState = new MoveState(movement);

movement.addState("IdleState", idleState);
movement.addState("MoveState", moveState);

// 设置初始状态（构建期 ChangeState 仅移指针，不触发 onEnter）
movement.changeState("IdleState");

// 启动状态机：统一触发首次 onEnter
movement.stateMachine.start();

// 在 onEnterFrame 中更新移动逻辑
mc.onEnterFrame = function() {
    movement.updateMovement(this);
};

*/