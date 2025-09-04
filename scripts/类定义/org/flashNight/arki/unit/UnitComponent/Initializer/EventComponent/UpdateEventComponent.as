// 路径: org/flashNight/arki/unit/UnitComponent/Initializer/EventComponent/KillEventComponent.as
import org.flashNight.neur.Event.*;
import org.flashNight.arki.unit.UnitComponent.Updater.*;
import org.flashNight.arki.component.StatHandler.*;
import org.flashNight.arki.component.Buff.*;
import org.flashNight.arki.component.Buff.Component.*;

class org.flashNight.arki.unit.UnitComponent.Initializer.EventComponent.UpdateEventComponent {

    // --- 屏外剔除：可按需调节缓冲 ---
    // 设为 0 表示严格以屏幕边缘为界；>0 则加入缓冲，减少边缘闪烁
    private static var CULL_PAD:Number = 100;

    // —— 防抖用：隐藏门槛（连续多少帧在屏外才隐藏）——
    private static var HIDE_AFTER:Number = 3;


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
        /*
        // 用 man 做精确边界
        var b:Object = target.man.getBounds(_root);
        */

        // 目前发现使用man做边界会频繁因异步加载导致边界错判，当前性能预算足够，放宽为用整个MC边界
        var b:Object = target.getBounds(_root);

        var sw:Number = Stage.width;
        var sh:Number = Stage.height;
        var pad:Number = CULL_PAD;

        var outside:Boolean =
            (b.xMax < -pad) || (b.xMin > sw + pad) ||
            (b.yMax < -pad) || (b.yMin > sh + pad);

        // 轻量状态：仅记录“连续在外”的帧数
        var st:Object = target.__cullState;

        if (outside) {
            st.outCount++; // 直接自增，不做上限夹紧
            if (st.outCount >= HIDE_AFTER && target._visible) {
                target._visible = false;
                // _root.发布消息(target.man, false);
            }
        } else {
            // 一回到视界就显示 & 清零计数
            if (!target._visible) {
                target._visible = true;
                // _root.发布消息(target.man, true);
            }
            st.outCount = 0;
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
