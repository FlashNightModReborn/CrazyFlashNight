// 路径: org/flashNight/arki/unit/UnitComponent/Initializer/EventComponent/KillEventComponent.as
import org.flashNight.neur.Event.EventDispatcher;
import org.flashNight.arki.unit.UnitComponent.Updater.HitUpdater;

class org.flashNight.arki.unit.UnitComponent.Initializer.EventComponent.UpdateEventComponent {
    /**
     * 初始化单位的死亡事件监听
     * @param target 目标单位( MovieClip )
     */
    public static function initialize(target:MovieClip):Void {
        var dispatcher:EventDispatcher = target.dispatcher;
        // 订阅 hkil 事件到 HitUpdater 逻辑
        dispatcher.subscribeSingle("update", UpdateEventComponent.onUpdate, target);
        
        _root.帧计时器.添加生命周期任务(target, "UpdateEventComponent", function (t:MovieClip)
        {
            this.dispatcher.publish("update", t);
        }, 130 , target)
    }

    public static function onUpdate(target:MovieClip):Void {
        _root.发布消息("update 事件" + target);
    }
}
