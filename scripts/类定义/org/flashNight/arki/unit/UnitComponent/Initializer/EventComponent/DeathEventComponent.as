// 路径: org/flashNight/arki/unit/UnitComponent/Initializer/EventComponent/KillEventComponent.as
import org.flashNight.neur.Event.EventDispatcher;
import org.flashNight.arki.unit.UnitComponent.Updater.HitUpdater;
import org.flashNight.arki.unit.UnitComponent.Targetcache.FactionManager;

class org.flashNight.arki.unit.UnitComponent.Initializer.EventComponent.DeathEventComponent {
    /**
     * 初始化单位的死亡事件监听
     * @param target 目标单位( MovieClip )
     */
    public static function initialize(target:MovieClip):Void {
        var dispatcher:EventDispatcher = target.dispatcher;
        var func:Function;
        // 订阅 hit 事件到 HitUpdater 逻辑
        if(target.兵种) {
            func = DeathEventComponent.onDeath;
        } else {
            return; // 如果不是兵种，则不处理死亡事件
        }
        // 订阅 hkil 事件到 HitUpdater 逻辑
        dispatcher.subscribeSingle("death", func, target);
    }
    

    public static var reservedInstance = {
        man:true,
        装扮:true,
        装扮2:true
    }

    public static function onDeath(target:MovieClip):Void {
        if(!target.respawn){
            // 遍历目标下的所有影片剪辑
            for(var i:String in target){
                // 检查属性是否为影片剪辑且不是名为"man"的实例
                var child = target[i];
                if(child instanceof MovieClip && !reservedInstance[child._name]) {
                    // 移除该影片剪辑
                    // _root.服务器.发布服务器消息("移除 " + child._name)
                    child.removeMovieClip();
                }
            }
            // 发布特殊死亡事件
            if(target.publishStageEvent === true){
                _root.gameworld.dispatcher.publish("UnitDeath", target._name);
            }
        }

        // if(!target.已加经验值 && FactionManager.getFactionFromUnit(target) == FactionManager.FACTION_HOSTILE_NEUTRAL)
        // {
        //     _root.敌人死亡计数 = _root.敌人死亡计数 + 1;
        //     _root.gameworld[target.产生源].僵尸型敌人场上实际人数--;
        //     _root.gameworld[target.产生源].僵尸型敌人总个数--;
        // }
    }
}