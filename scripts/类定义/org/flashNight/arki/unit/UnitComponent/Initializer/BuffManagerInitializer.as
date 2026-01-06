import org.flashNight.neur.Event.*;
import org.flashNight.arki.unit.UnitComponent.Initializer.*;
import org.flashNight.arki.unit.UnitComponent.Deinitializer.*;
import org.flashNight.aven.Coordinator.*;
import org.flashNight.arki.component.Buff.*;
import org.flashNight.arki.component.Buff.Component.*;

class org.flashNight.arki.unit.UnitComponent.Initializer.BuffManagerInitializer {

    /**
     * 创建新的 BuffManager 实例
     * @param target 宿主单位
     * @return BuffManager
     */
    private static function createManager(target:MovieClip):BuffManager {
        // 构造时传入 target 作为 owner，和一组可选回调
        return new BuffManager(
            target,
            {
                // 注意：BuffManager 实际调用顺序是 (id, buff)
                onBuffAdded: function(id:String, buff:IBuff):Void {
                    // ("add buff " + id + " : " + buff);
                },
                onBuffRemoved: function(id:String, buff:IBuff):Void {
                    // _root.服务器.发布服务器消息("remove buff " + id + " : " + buff);
                }
            }
        );
    }

    /**
     * 重置 BuffManager（用于换装/模板重初始化）
     * - 先 destroy 旧实例：清空 Buff、finalize 属性访问器、释放引用
     * - 再创建新实例：避免旧 buff 残留、旧 base 值污染
     *
     * 注意：该方法不会主动触发 update(0)，由调用方在合适的阶段统一更新。
     *
     * @param target 宿主单位
     */
    public static function reset(target:MovieClip):Void {
        if (!target) return;

        var oldManager:Object = target.buffManager;
        if (oldManager && typeof oldManager.destroy == "function") {
            oldManager.destroy();
        }

        target.buffManager = createManager(target);
    }

    public static function initialize(target:MovieClip):Void {
        // _root.发布消息("BuffManagerInitializer", target)
        if (!target) return;

        if (!target.buffManager || typeof target.buffManager.update != "function") {
            target.buffManager = createManager(target);
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
