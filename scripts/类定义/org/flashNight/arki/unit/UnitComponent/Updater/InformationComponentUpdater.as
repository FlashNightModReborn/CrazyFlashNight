import org.flashNight.neur.Event.*;
import org.flashNight.arki.component.StatHandler.*;
import org.flashNight.arki.component.Effect.*;

class org.flashNight.arki.unit.UnitComponent.Updater.InformationComponentUpdater {

    // -------------------
    // 常量定义
    // -------------------
    private static var ANIM_START:Number   = Math.round(2 * 30 / 4);  // 2秒开始 = 15
    private static var ANIM_END:Number     = Math.round(5 * 30 / 4);  // 5秒结束 = 38
    private static var FADE_OUT_START:Number = Math.round(7 * 30 / 4);  // 7秒开始 = 53
    private static var FADE_OUT_END:Number   = Math.round(10 * 30 / 4); // 10秒结束 = 75

    /**
     * 当HP发生变化时调用，重置相关计数器与动画起始状态
     */
    public static function onHPChanged(target:MovieClip, actualHpWidth:Number):Void {
        target.lastHp = target.hp;
        target.hpUnchangedCounter = 0;
        target._animStartResidual = target.residualHpWidth;
        target._animStartActual = actualHpWidth;

        var ic:MovieClip = target.新版人物文字信息;
        var hpBar:MovieClip = ic.头顶血槽;
        var hpBarBottom:MovieClip = hpBar.血槽底;
        var bloodBarLength:Number = hpBarBottom._width;
        ic._x = target.icX;
        ic._y = target.icY;
        hpBar.血槽条._width = actualHpWidth;
    }

    public static function update(target:MovieClip):Void {
        // ------------------- 初始设置 -------------------
        var ic:MovieClip = target.新版人物文字信息;
        ic._visible = (target.状态 == "登场") ? false : (ic._alpha > 0);
        if (!ic._visible) return;

        var hpBar:MovieClip = ic.头顶血槽;
        var hpBarBottom:MovieClip = hpBar.血槽底;
        var bloodBarLength:Number = hpBarBottom._width;

        // ------------------- 计算实际血槽宽度 -------------------
        var actualHpWidth:Number = target.hp / target.hp满血值 * bloodBarLength;

        // ------------------- HP 变化检测，调用 onHPChanged -------------------
        if (target.hp != target.lastHp) {
            onHPChanged(target, actualHpWidth);
            var dispatcher:EventDispatcher = target.dispatcher;
            // 订阅 HPChanged 事件到 HitUpdater 逻辑
            dispatcher.publish("HPChanged", target, actualHpWidth);
        } else {
            target.hpUnchangedCounter++;

            if(target.remainingImpactForce < target.韧性上限 / ImpactHandler.IMPACT_STAGGER_COEFFICIENT / target.躲闪率) {
                if(target.barColorState != "常态") {
                    target.barColorState = "常态";
                }
            } 
            BloodBarEffectHandler.updateColor(target);
        }

        // ------------------- 更新韧性与刚体遮罩 -------------------


        hpBar.韧性条._width = !(target.浮空 || target.倒地) ? bloodBarLength * target.nonlinearMappingResilience : 0;
        hpBar.刚体遮罩._visible = !!(target.刚体 || target.man.刚体标签);

        // ------------------- 残余血槽动画逻辑 -------------------
        var currentCounter:Number = target.hpUnchangedCounter;
        var residualHpWidth:Number = target.residualHpWidth;

        // HP 上升则残余血条被遮盖，无需同步
        // HP 下降：在动画区间内做二次缓出插值
        if (residualHpWidth > actualHpWidth) {
            if (currentCounter >= InformationComponentUpdater.ANIM_START && currentCounter <= InformationComponentUpdater.ANIM_END) {
                var t:Number = (currentCounter - InformationComponentUpdater.ANIM_START) / (InformationComponentUpdater.ANIM_END - InformationComponentUpdater.ANIM_START);
                var progress:Number = t * (2 - t);
                residualHpWidth = target._animStartResidual - 
                    (target._animStartResidual - target._animStartActual) * progress;
                if (Math.abs(residualHpWidth - actualHpWidth) < 5) {
                    residualHpWidth = actualHpWidth;
                }
            }
            else if (currentCounter > InformationComponentUpdater.ANIM_END) {
                residualHpWidth = actualHpWidth;
            }

            target.residualHpWidth = residualHpWidth;
            hpBar.残余血槽条._width = residualHpWidth;
        }
        
        if (currentCounter > FADE_OUT_START) {
            var fadeProgress:Number = (currentCounter - FADE_OUT_START) / (FADE_OUT_END - FADE_OUT_START);
            if (fadeProgress > 1) fadeProgress = 1;
            hpBar._alpha = (1 - fadeProgress) * 100;
        } else {
            hpBar._alpha = 100;
        }
    }
}
