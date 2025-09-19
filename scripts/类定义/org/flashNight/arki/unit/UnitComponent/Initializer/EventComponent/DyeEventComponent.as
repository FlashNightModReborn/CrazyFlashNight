
import org.flashNight.neur.Event.EventDispatcher;

class org.flashNight.arki.unit.UnitComponent.Initializer.EventComponent.DyeEventComponent {
    /**
     * 初始化单位的HP事件监听
     * @param target 目标单位( MovieClip )
     */
    public static function initialize(target:MovieClip):Void {
        if(!target.dyeParam) return;
        
        var dispatcher:EventDispatcher = target.dispatcher;

        dispatcher.subscribeSingle("dyeing", function():Void
        {
            _root.色彩引擎.调整颜色(target.man, target.dyeParam);
        }, target);
        dispatcher.publish("dyeing");
    }
}
