import org.flashNight.neur.StateMachine.*;

class org.flashNight.arki.bullet.BulletComponent.Movement.MissileFSM.ExplodeState extends FSM_Status {
    private var missile:MissileBulletMovement;

    public function ExplodeState(missile:MissileBulletMovement) {
        super(null, null, null);
        this.missile = missile;
    }

    public function onEnter():Void {
        // 执行爆炸效果
        missile.explode();
        // 爆炸完成后，转换到销毁状态
        this.superMachine.ChangeState("Destroy");
    }
}
