// 路径: org/flashNight/arki/unit/UnitComponent/Initializer/EventComponent/KillEventComponent.as
import org.flashNight.neur.Event.*;
import org.flashNight.arki.unit.UnitComponent.Updater.*;
import org.flashNight.arki.component.StatHandler.*;


class org.flashNight.arki.unit.UnitComponent.Initializer.EventComponent.UpdateEventComponent {
    /**
     * 初始化单位的死亡事件监听
     * @param target 目标单位( MovieClip )
     */
    public static function initialize(target:MovieClip):Void {
        var dispatcher:EventDispatcher = target.dispatcher;
        // 订阅 UpdateEventComponent 事件到 onUpdate 逻辑
        dispatcher.subscribeSingle("UpdateEventComponent", UpdateEventComponent.onUpdate, target);
        
        // 主角换装不会销毁自身，因此直接使用相同的标签会导致生命周期函数多次设置
        // 利用版本号进行区分

        var label:String = "UpdateEventComponent" + target.version;
        if(target.updateEventComponentID) {
            //_root.发布消息("移除任务: " + target.updateEventComponentID)
            _root.帧计时器.移除任务(target.updateEventComponentID);
        }
        
        // if(target._parent !== _root.gameworld){
        //     return;
        // }
        // 以4帧为间隔加入生命周期任务
        target.updateEventComponentID = _root.帧计时器.添加生命周期任务(target, label, function (t:MovieClip)
        {
            this.dispatcher.publish("UpdateEventComponent", t);
        }, 130 , target)
    }

    public static function onUpdate(target:MovieClip):Void {
        ImpactUpdater.update(target);
        InformationComponentUpdater.update(target);
        target.unitAI.update();
    }
}
