import org.flashNight.neur.StateMachine.*;

class org.flashNight.arki.bullet.BulletComponent.Movement.MissileFSM.DestroyState extends FSM_Status {
    private var missile:MissileBulletMovement;

    public function DestroyState(missile:MissileBulletMovement) {
        super(null, null, null);
        this.missile = missile;
    }

    public function onEnter():Void {
        // 清理导弹，移除影片剪辑
        missile.destroy();
    }
}
