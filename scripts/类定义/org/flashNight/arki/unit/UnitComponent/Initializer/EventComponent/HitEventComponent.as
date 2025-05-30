// 路径: org/flashNight/arki/unit/UnitComponent/Initializer/EventComponent/HitEventComponent.as
import org.flashNight.neur.Event.EventDispatcher;
import org.flashNight.arki.unit.UnitComponent.Updater.HitUpdater;

class org.flashNight.arki.unit.UnitComponent.Initializer.EventComponent.HitEventComponent {
    /**
     * 初始化单位的受击事件监听
     * @param target 目标单位( MovieClip )
     */
    public static function initialize(target:MovieClip, shooter:MovieClip):Void {
        
        var dispatcher:EventDispatcher = target.dispatcher;
        var func:Function;
        // 订阅 hit 事件到 HitUpdater 逻辑
        if(target.兵种) {
            func = HitUpdater.getUpdater(target);
        } else {
            func = HitEventComponent.onMapElementHit;
        }
        dispatcher.subscribeSingle("hit", func, target);
    }

    public static function onMapElementHit(target:MovieClip, shooter:MovieClip, bullet:MovieClip):Void {

        target.hitPoint--;

        if(target.hitPoint <= 0) {
            var dispatcher:EventDispatcher = target.dispatcher;
            var hitDirection:Boolean = Boolean((target._x < shooter._x) ^ bullet.水平击退反向);
            target._xscale = (hitDirection ? 100 : -100);

            target.hp = 0;
            dispatcher.publish("kill", target);
        } else {
            var maxFrame:Number = target.maxFrame;
            var currentFrame:Number = maxFrame - Math.ceil(target.hitPoint / target.hitPointMax * maxFrame);
            target.element.gotoAndStop(currentFrame);
        }
    }
}
