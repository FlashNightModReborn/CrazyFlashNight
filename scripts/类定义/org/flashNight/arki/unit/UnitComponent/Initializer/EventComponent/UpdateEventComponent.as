// 路径: org/flashNight/arki/unit/UnitComponent/Initializer/EventComponent/KillEventComponent.as
import org.flashNight.neur.Event.*;
import org.flashNight.arki.unit.UnitComponent.Updater.*;
import org.flashNight.arki.component.StatHandler.*;
import org.flashNight.arki.component.Buff.*;
import org.flashNight.arki.component.Buff.Component.*;

class org.flashNight.arki.unit.UnitComponent.Initializer.EventComponent.UpdateEventComponent {

    // --- 屏外剔除：可按需调节缓冲 ---
    // 设为 0 表示严格以屏幕边缘为界；>0 则加入缓冲，减少边缘闪烁
    private static var CULL_PAD:Number = 50;

    /**
     * 初始化单位的死亡事件监听
     * @param target 目标单位( MovieClip )
     */
    public static function initialize(target:MovieClip):Void {
        if(target.updateEventComponentID != null) {
            return;
        }

        var dispatcher:EventDispatcher = target.dispatcher;

        var func:Function;
        if(target._name === _root.控制目标) {
            func = UpdateEventComponent.onHeroUpdate;
        } else if(target.element) {
            func = UpdateEventComponent.getMapElementUpdate(target);
        } else {
            func = UpdateEventComponent.onUpdate;
        }
        dispatcher.subscribeSingle("UpdateEventComponent", func, target);

        // 用 UnitUpdateWheel 托管刷新事件
        target.updateEventComponentID = _root.帧计时器.unitUpdateWheel.add(target);

        WatchDogUpdater.init(target);

        if(target._name === _root.控制目标) {
            HeroPositionUpdater.init(target);
        }
    }

    // ===== 可见性剔除（仅控制渲染，不影响逻辑） =====
    private static function applyVisibilityCulling(target:MovieClip):Void {
        // 取得 target 在 _root 坐标系下的包围框
        var b:Object = target.man.getBounds(_root);
        var sw:Number = Stage.width;
        var sh:Number = Stage.height;
        var pad:Number = CULL_PAD;

        // “完全不在屏幕范围内”判定（加入可选 pad）
        var outside:Boolean =
            (b.xMax < -pad) || (b.xMin > sw + pad) ||
            (b.yMax < -pad) || (b.yMin > sh + pad);

        var shouldVisible:Boolean = !outside;

        // 仅在状态变化时切换，避免无谓赋值
        if (target._visible != shouldVisible) {
            target._visible = shouldVisible;
            // _root.发布消息(target._name, target._visible)
        }
    }

    public static function onUpdate(target:MovieClip):Void {
        // —— 屏外渲染剔除（非主角） ——
        applyVisibilityCulling(target);

        // —— 原有刷新逻辑（ ——
        ImpactUpdater.update(target);
        InformationComponentUpdater.update(target);
        target.unitAI.update();
        target.buffManager.update(4);
        WatchDogUpdater.update(target);
    }

    public static function onHeroUpdate(target:MovieClip):Void {
        // 主角不做渲染剔除
        ImpactUpdater.updateHero(target);
        InformationComponentUpdater.update(target);
        target.buffManager.update(4);
        WatchDogUpdater.update(target);
        HeroPositionUpdater.update(target);
    }

    public static function onMapElementUpdate(target:MovieClip):Void {
        // —— 地图元素也做渲染剔除 ——
        applyVisibilityCulling(target);
        target.swapDepths(target._y);
    }

    public static function onTauntMapElementUpdate(target:MovieClip):Void {
        if(target.hitPoint > 0) {
            target.dispatcher.publish("hit", target);
            target.hitPointText.text = target.hitPoint;
        }
    }

    public static function getMapElementUpdate(target:MovieClip):Function {
        var basicFunc:Function = UpdateEventComponent.onMapElementUpdate;

        if(target.taunt) {
            return function(target:MovieClip):Void {
                basicFunc(target);                // 含可见性剔除
                onTauntMapElementUpdate(target);  // 额外嘲讽逻辑
            }
        }
        return UpdateEventComponent.onMapElementUpdate; // 含可见性剔除
    }
}
