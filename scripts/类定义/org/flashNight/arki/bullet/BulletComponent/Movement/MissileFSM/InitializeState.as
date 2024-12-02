import org.flashNight.neur.StateMachine.*;

class org.flashNight.arki.bullet.BulletComponent.Movement.MissileFSM.InitializeState extends FSM_Status {
    private var missile:MissileBulletMovement;

    public function InitializeState(missile:MissileBulletMovement) {
        super(null, null, null);
        this.missile = missile;
    }

    public function onEnter():Void {
        // 执行初始化逻辑
        missile.initializeMissile();
        // 初始化完成后，直接请求转换到搜索目标状态
        this.superMachine.ChangeState("SearchTarget");
    }
}
