import org.flashNight.neur.Event.*;
import org.flashNight.arki.unit.UnitComponent.Initializer.*;
import org.flashNight.arki.unit.UnitComponent.Deinitializer.*;
import org.flashNight.aven.Coordinator.*;
import org.flashNight.arki.component.Buff.*;
import org.flashNight.arki.component.Buff.Component.*;

class org.flashNight.arki.unit.UnitComponent.Initializer.BuffManagerInitializer {

    public static function initialize(target:MovieClip):Void {
        _root.发布消息("BuffManagerInitializer", target)
        if (!target.buffManager) {
            // 构造时传入 target 作为 owner，和一组可选回调
            target.buffManager = new BuffManager(
                target,
                {
                    onBuffAdded: function(buff:IBuff, id:String):Void {
                        _root.发布消息("add buff", buff)
                    },
                    onBuffRemoved: function(buff:IBuff, id:String):Void {
                        _root.发布消息("remove buff", buff)
                    }
                }
            );
            //_root.发布消息(target.hp);
            //target.buffManager.addBuff(new PodBuff("hp", BuffCalculationType.ADD, 123454));
            target.buffManager.update(1); // 强制更新一次以防万一
            //_root.发布消息(target.hp);
        }
    }
}
