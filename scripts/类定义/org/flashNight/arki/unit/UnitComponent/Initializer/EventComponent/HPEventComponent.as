
import org.flashNight.neur.Event.EventDispatcher;
import org.flashNight.arki.unit.UnitComponent.Updater.InformationComponentUpdater;

class org.flashNight.arki.unit.UnitComponent.Initializer.EventComponent.HPEventComponent {
    /**
     * 初始化单位的HP事件监听
     * @param target 目标单位( MovieClip )
     */
    public static function initialize(target:MovieClip):Void {
        var dispatcher:EventDispatcher = target.dispatcher;
        // 订阅 HPChanged 事件到 HitUpdater 逻辑
        dispatcher.subscribeSingle("HPChanged", InformationComponentUpdater.onHPChanged, target);
    }
}
