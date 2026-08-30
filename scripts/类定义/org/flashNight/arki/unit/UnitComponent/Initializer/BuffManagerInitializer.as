import org.flashNight.neur.Event.*;
import org.flashNight.arki.unit.UnitComponent.Initializer.*;
import org.flashNight.arki.unit.UnitComponent.Deinitializer.*;
import org.flashNight.aven.Coordinator.*;
import org.flashNight.arki.component.Buff.*;
import org.flashNight.arki.component.Buff.Component.*;
import org.flashNight.arki.component.StatHandler.ImpactHandler;

class org.flashNight.arki.unit.UnitComponent.Initializer.BuffManagerInitializer {

    /**
     * Buff 属性变化后的派生刷新表。处理函数显式接收宿主，避免静态表捕获单位引用。
     * 新增派生关系时只登记一项，不在 BuffManager 回调里扩张条件分支。
     */
    private static var _propertyChangeHandlers:Object = initializePropertyChangeHandlers();

    private static function initializePropertyChangeHandlers():Object {
        var handlers:Object = {};
        handlers["韧性系数"] = function(target:MovieClip, newValue:Number):Void {
            ImpactHandler.refreshImpactDerived(target);
        };
        return handlers;
    }

    /**
     * 创建新的 BuffManager 实例
     * @param target 宿主单位
     * @return BuffManager
     */
    private static function createManager(target:MovieClip):BuffManager {
        // 构造时传入 target 作为 owner，和一组可选回调
        // 只捕获共享静态表的引用；不为每个单位重新创建处理器或分发表。
        var propertyChangeHandlers:Object = _propertyChangeHandlers;
        return new BuffManager(
            target,
            {
                // 注意：BuffManager 实际调用顺序是 (id, buff)
                onBuffAdded: function(id:String, buff:IBuff):Void {
                    // ("add buff " + id + " : " + buff);
                },
                onBuffRemoved: function(id:String, buff:IBuff):Void {
                    // _root.服务器.发布服务器消息("remove buff " + id + " : " + buff);
                },
                onPropertyChanged: function(propertyName:String, newValue:Number):Void {
                    var handler:Function = propertyChangeHandlers[propertyName];
                    if (handler != undefined) handler(target, newValue);
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
        }
        if(target._name === _root.控制目标){
            _root.UI系统.iconBar.initialize(target.buffManager);
        }
        target.buffManager.update(0); // 强制更新一次以防万一
    }
}
