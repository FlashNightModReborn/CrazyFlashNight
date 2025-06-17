import org.flashNight.neur.Event.*;
import org.flashNight.arki.unit.UnitComponent.Initializer.*;
import org.flashNight.arki.unit.UnitComponent.Deinitializer.*;
import org.flashNight.aven.Coordinator.*;
import org.flashNight.arki.component.Buff.*;
import org.flashNight.arki.component.Buff.Component.*;

class org.flashNight.arki.unit.UnitComponent.Initializer.BuffManagerInitializer {

    public static function initialize(target:MovieClip):Void {
        // _root.发布消息("BuffManagerInitializer", target)
        if (!target.buffManager) {
            // 构造时传入 target 作为 owner，和一组可选回调
            target.buffManager = new BuffManager(
                target,
                {
                    onBuffAdded: function(buff:IBuff, id:String):Void {
                        _root.服务器.发布服务器消息("add buff " + buff + " : " + target.hp)
                    },
                    onBuffRemoved: function(buff:IBuff, id:String):Void {
                        _root.服务器.发布服务器消息("remove buff " + buff + " : " + target.hp)
                    }
                }
            );
            /*

            var podBuff:PodBuff = new PodBuff("hp", BuffCalculationType.ADD, 1500);
            var childBuffs:Array = [podBuff];
            
            var timeLimitComp:TimeLimitComponent = new TimeLimitComponent(150); // 5S生命周期
            var components:Array = [timeLimitComp];
            
            var metaBuff:MetaBuff = new MetaBuff(childBuffs, components, 0);
            target.buffManager.addBuff(metaBuff);

            */
        }
        target.buffManager.update(0); // 强制更新一次以防万一
    }
}
