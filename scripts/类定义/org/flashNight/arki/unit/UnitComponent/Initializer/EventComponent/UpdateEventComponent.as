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
        var func;
        if(target._name === _root.控制目标) {
            func = UpdateEventComponent.onHeroUpdate;
        } else if(target.兵种) {
            func = UpdateEventComponent.onUpdate;
        } else {
            func = UpdateEventComponent.onMapElementUpdate;
        }
        dispatcher.subscribeSingle("UpdateEventComponent", func, target);

        
        // 主角换装不会销毁自身，因此直接使用相同的标签会导致生命周期函数多次设置
        // 利用版本号进行区分

        // var label:String = "UpdateEventComponent" + target.version;
        // if(target.updateEventComponentID) {
        //     //_root.发布消息("移除任务: " + target.updateEventComponentID)
        //     _root.帧计时器.移除任务(target.updateEventComponentID);
        // }
        
        // 以4帧为间隔加入生命周期任务
        // target.updateEventComponentID = _root.帧计时器.添加生命周期任务(target, label, function ()
        // {
        //     this.dispatcher.publish("UpdateEventComponent", this);
        // }, 130)

        // 用 UnitUpdateWheel 托管刷新事件
        target.updateEventComponentID = _root.帧计时器.unitUpdateWheel.add(target);

        WatchDogUpdater.init(target);
    }

    public static function onUpdate(target:MovieClip):Void {
        ImpactUpdater.update(target);
        InformationComponentUpdater.update(target);
        target.unitAI.update();
        WatchDogUpdater.update(target);
    }

    public static function onHeroUpdate(target:MovieClip):Void {
        ImpactUpdater.updateHero(target);
        InformationComponentUpdater.update(target);
        WatchDogUpdater.update(target);
    }

    public static function onMapElementUpdate(target:MovieClip):Void {
        target.swapDepths(target._y);
    }
}
