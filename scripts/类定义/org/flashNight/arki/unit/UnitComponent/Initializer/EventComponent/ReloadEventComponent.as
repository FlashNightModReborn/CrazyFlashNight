// 路径: org/flashNight/arki/unit/UnitComponent/Initializer/EventComponent/KillEventComponent.as
import org.flashNight.neur.Event.EventDispatcher;

class org.flashNight.arki.unit.UnitComponent.Initializer.EventComponent.ReloadEventComponent {
    /**
     * 初始化单位的换弹监听
     * @param target 目标单位( MovieClip )
     */
    public static function initialize(target:MovieClip):Void {
        if(target.兵种 != "主角-男") return;

        var dispatcher:EventDispatcher = target.dispatcher;
        var func:Function;

        if(_root.控制目标 === target._name) {
            func = ReloadEventComponent.updateHeroBullet;
        } else {
            func = ReloadEventComponent.updateNpcBullet;
        }

        dispatcher.subscribeSingle("updateBullet", func, target);
    }

    public static function updateHeroBullet(target:MovieClip, shootStateName:String, magazineRemaining:Number, playerBulletField:String):Void
    {
        _root.玩家信息界面.玩家必要信息界面[playerBulletField] = magazineRemaining;
        ReloadEventComponent.updateNpcBullet(target, shootStateName, magazineRemaining);
    }

    public static function updateNpcBullet(target:MovieClip, shootStateName:String, magazineRemaining:Number):Void
    {
        target.射击最大后摇中 = target[shootStateName] = (magazineRemaining > 0 && target[shootStateName]);
    }

    public static function updateBulletOrigin(target:MovieClip, shootStateName:String, magazineRemaining:Number, playerBulletField:String):Void
    {
        if (_root.控制目标 === target._name) {
            _root.玩家信息界面.玩家必要信息界面[playerBulletField] = magazineRemaining;
        }
        target.射击最大后摇中 = target[shootStateName] = (magazineRemaining > 0 && target[shootStateName]);
    }
}
