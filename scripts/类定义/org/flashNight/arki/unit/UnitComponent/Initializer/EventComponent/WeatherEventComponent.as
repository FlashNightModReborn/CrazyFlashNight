// 路径: org/flashNight/arki/unit/UnitComponent/Initializer/EventComponent/WeatherEventComponent.as
import org.flashNight.neur.Event.EventDispatcher;
import org.flashNight.arki.unit.UnitComponent.Updater.WeatherUpdater;

class org.flashNight.arki.unit.UnitComponent.Initializer.EventComponent.WeatherEventComponent {
    /**
     * 初始化单位的天气/时间事件监听
     * @param target 目标单位( MovieClip )
     */
    public static function initialize(target:MovieClip):Void {
        var dispatcher:EventDispatcher = target.dispatcher;
        var wtfunc:Function = WeatherUpdater.getUpdater();
        
        // 订阅全局天气变化事件
        dispatcher.subscribeSingleGlobal("WeatherTimeRateUpdated", wtfunc, target);
        // 立即调用以同步初始状态
        wtfunc.call(target);
    }
}
