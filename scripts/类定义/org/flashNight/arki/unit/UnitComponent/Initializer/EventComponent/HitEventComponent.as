// 路径: org/flashNight/arki/unit/UnitComponent/Initializer/EventComponent/HitEventComponent.as
import org.flashNight.neur.Event.EventDispatcher;
import org.flashNight.arki.unit.UnitComponent.Updater.HitUpdater;

class org.flashNight.arki.unit.UnitComponent.Initializer.EventComponent.HitEventComponent {
    /**
     * 初始化单位的受击事件监听
     * @param target 目标单位( MovieClip )
     */
    public static function initialize(target:MovieClip):Void {
        var dispatcher:EventDispatcher = target.dispatcher;
        // 订阅 hit 事件到 HitUpdater 逻辑
        dispatcher.subscribeSingle("hit", HitUpdater.getUpdater(target), target);
    }
}
