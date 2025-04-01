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
        var func:Function = updateBulletOrigin;


        /*
        if(_root.控制目标 === target._name) {
            func = ReloadEventComponent.updateHeroBullet;
            _root.发布消息(target + " " + "updateHeroBullet")
        } else {
            func = ReloadEventComponent.updateBullet;
            _root.发布消息(target + " " + "updateBullet")
        }
        */
        dispatcher.subscribeSingle("ReloadEvent", func, target);
    }

    public static function updateHeroBullet(target:MovieClip, shootStateName:String, magazineRemaining:Number, playerBulletField:String):Void
    {
        _root.玩家信息界面.玩家必要信息界面[playerBulletField] = magazineRemaining;
        ReloadEventComponent.updateBullet(target, shootStateName, magazineRemaining, playerBulletField);
    }

    public static function updateBullet(target:MovieClip, shootStateName:String, magazineRemaining:Number, playerBulletField:String):Void
    {
        if (magazineRemaining <= 0) {
            target[shootStateName] = false;
        }

        target.射击最大后摇中 = target[shootStateName];
    }

    public static function updateBulletOrigin(target:MovieClip, shootStateName:String, magazineRemaining:Number, playerBulletField:String):Void
    {
        if (_root.控制目标 === target._name) {
            _root.玩家信息界面.玩家必要信息界面[playerBulletField] = magazineRemaining;
        }
        if (magazineRemaining <= 0) {
            target[shootStateName] = false;
        }

        target.射击最大后摇中 = target[shootStateName];
    }
}
