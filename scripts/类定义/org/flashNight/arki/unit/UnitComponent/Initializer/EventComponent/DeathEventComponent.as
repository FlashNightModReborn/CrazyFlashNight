// 路径: org/flashNight/arki/unit/UnitComponent/Initializer/EventComponent/KillEventComponent.as
import org.flashNight.neur.Event.EventDispatcher;
import org.flashNight.arki.unit.UnitComponent.Updater.HitUpdater;

class org.flashNight.arki.unit.UnitComponent.Initializer.EventComponent.DeathEventComponent {
    /**
     * 初始化单位的死亡事件监听
     * @param target 目标单位( MovieClip )
     */
    public static function initialize(target:MovieClip):Void {
        var dispatcher:EventDispatcher = target.dispatcher;
        // 订阅 hkil 事件到 HitUpdater 逻辑
        dispatcher.subscribeSingle("death", DeathEventComponent.onDeath, target);
    }

    public static function onDeath(target:MovieClip):Void {
        target.人物文字信息.removeMovieClip();
        target.新版人物文字信息.removeMovieClip();
    }
}
