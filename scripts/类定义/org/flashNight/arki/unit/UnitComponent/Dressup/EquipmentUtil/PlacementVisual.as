/**
 * PlacementVisual - 装备 placement 视觉刷新挂钩 helper
 *
 * 30 个装备脚本初始化重复 pattern：
 *   DressupSubscriber.onPlacement(target, refName, function() {
 *       _root.装备生命周期函数.XXX视觉更新(ref);
 *   });
 * 此类 collapse 为单行：
 *   PlacementVisual.hookVisualUpdate(target, refName, ref, _root.装备生命周期函数.XXX视觉更新);
 *
 * 不追加进 DressupSubscriber — DressupSubscriber 是纯事件订阅 API，
 * 不应反向依赖装备 frame-script 全局 _root.装备生命周期函数。
 *
 * 多回调装备（吉他喷火 / 键盘镰刀）和带 scope arg 的剑圣甲族
 * 保留原 DressupSubscriber.onPlacement 写法，不通过本 helper。
 */
import org.flashNight.arki.unit.UnitComponent.Dressup.DressupSubscriber;

class org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.PlacementVisual {

    /**
     * @param scope 可选；默认沿用 target。需要随装备 lifecycle 精确退订时传入 ref。
     * @return 实际登记的 handler，供调用方以同一 callback + scope 退订。
     */
    public static function hookVisualUpdate(target:MovieClip, refName:String, ref:Object,
                                            updateFn, scope:Object):Function {
        var handler:Function = function() {
            updateFn(ref);
        };
        DressupSubscriber.onPlacement(target, refName, handler,
            scope != undefined ? scope : target);
        return handler;
    }
}
