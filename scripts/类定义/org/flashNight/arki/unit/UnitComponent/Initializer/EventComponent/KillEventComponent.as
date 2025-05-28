// 路径: org/flashNight/arki/unit/UnitComponent/Initializer/EventComponent/KillEventComponent.as
import org.flashNight.neur.Event.EventDispatcher;
import org.flashNight.arki.unit.UnitComponent.Updater.HitUpdater;

class org.flashNight.arki.unit.UnitComponent.Initializer.EventComponent.KillEventComponent {
    /**
     * 初始化单位的死亡事件监听
     * @param target 目标单位( MovieClip )
     */
    public static function initialize(target:MovieClip):Void {
        var dispatcher:EventDispatcher = target.dispatcher;

        var func:Function;
        
        // 根据是否有兵种决定是单位还是地图元件
        if(target.兵种) {
            func = KillEventComponent.onKill;
        } else {
            func = KillEventComponent.onMapElementKill;
        }

        // 订阅 kill 事件到 HitUpdater 逻辑
        dispatcher.subscribeSingle("kill", func, target);
    }

    public static function onKill(target:MovieClip):Void {
        target.状态改变("血腥死");
        target._killed = true;
        if(target.垂直速度 < 0) target.垂直速度 = 0; // 让被非近战子弹击杀的单位从空中更快下落
        // 不再在Kill事件时移除碰撞箱
        // target.aabbCollider.getFactory().releaseCollider(target.aabbCollider);
        // target.aabbCollider = null;
        // 设置"哨兵"碰撞箱，让它具有最大的left值
        // target.aabbCollider = {
        //     left: Number.MAX_VALUE  // 极大值作为哨兵
        // };
        target.dispatcher.publish("death", target);
    }

     public static function onMapElementKill(target:MovieClip):Void {
        target.gotoAndPlay("结束");
        target._killed = true;
        if(target.垂直速度 < 0) target.垂直速度 = 0; // 让被非近战子弹击杀的单位从空中更快下落

        target.dispatcher.publish("death", target);
    }
}

