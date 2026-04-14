import org.flashNight.arki.component.Damage.*;
import org.flashNight.arki.component.StatHandler.*;

/**
 * ImpactStateHandler
 * 用于处理单位受击后的冲击力与状态判断逻辑。
 * 此类提供一个静态方法 handleImpactState() 来处理 hitTarget 的状态改变与受击移动。
 */
class org.flashNight.arki.unit.UnitComponent.Status.ImpactStateHandler {

    private static var DOWN_LOG_COOLDOWN:Number = 8;
    private static var DOWN_PENDING_MAX_AGE:Number = 12;

    private static function logDiagnostic(message:String):Void {
        if (_root == undefined || _root.服务器 == undefined || _root.服务器.发布服务器消息 == undefined) {
            return;
        }
        _root.服务器.发布服务器消息(message);
    }

    private static function safeNum(value:Number):String {
        return isNaN(value) ? "-" : String(Math.round(value));
    }

    private static function safePct(cur:Number, max:Number):String {
        if (isNaN(cur) || isNaN(max) || max <= 0) {
            return "-";
        }
        return Math.round(cur / max * 100) + "%";
    }

    public static function shouldTrackCombatDiagnostics(target:MovieClip):Boolean {
        if (target == null) {
            return false;
        }
        if (target.佣兵数据 != undefined && target.佣兵数据 != null) {
            return true;
        }
        return target.unitAI != null
            && target.unitAI.data != null
            && target.unitAI.data.arbiter != null;
    }

    private static function getAICombatSnapshot(target:MovieClip):String {
        if (target == null || target.unitAI == null || target.unitAI.data == null || target.unitAI.data.arbiter == null) {
            return " mode=" + (target.攻击模式 || "-") + " urg=- enc=- near=-";
        }

        var arbiter = target.unitAI.data.arbiter;
        return " mode=" + (target.攻击模式 || "-")
            + " urg=" + Math.round(arbiter.getRetreatUrgency() * 100)
            + " enc=" + Math.round(arbiter.getEncirclement() * 100)
            + " near=" + Math.round(arbiter.getNearbyCount());
    }

    private static function stashImpactSnapshot(hitTarget:MovieClip,
                                                bullet:MovieClip,
                                                damageResult:DamageResult,
                                                hitDirection:String,
                                                reason:String,
                                                impactForce:Number,
                                                impactCap:Number,
                                                impactStagger:Number):Void {
        hitTarget._lastImpactReason = reason;
        hitTarget._lastImpactForce = impactForce;
        hitTarget._lastImpactCap = impactCap;
        hitTarget._lastImpactStagger = impactStagger;
        hitTarget._lastImpactDirection = hitDirection;
        hitTarget._lastImpactHSpeed = bullet.水平击退速度;
        hitTarget._lastImpactVSpeed = bullet.垂直击退速度;
        hitTarget._lastImpactDodge = (damageResult == null || damageResult.dodgeStatus == null || damageResult.dodgeStatus == "") ? "-" : damageResult.dodgeStatus;
    }

    private static function queueKnockdownDiagnostic(hitTarget:MovieClip,
                                                     bullet:MovieClip,
                                                     damageResult:DamageResult,
                                                     hitDirection:String,
                                                     isRigid:Boolean,
                                                     reason:String):Void {
        if (!shouldTrackCombatDiagnostics(hitTarget)) {
            return;
        }
        var frame:Number = (_root.帧计时器 != undefined) ? _root.帧计时器.当前帧数 : -1;
        if (!isNaN(hitTarget._lastDownDiagFrame) && frame - hitTarget._lastDownDiagFrame < DOWN_LOG_COOLDOWN) {
            return;
        }
        hitTarget._lastDownDiagFrame = frame;
        hitTarget._pendingDownDiag = true;
        hitTarget._pendingDownDiagFrame = frame;
        hitTarget._pendingDownDiagReason = reason;
        hitTarget._pendingDownDiagHpPct = safePct(hitTarget.hp, hitTarget.hp满血值);
        hitTarget._pendingDownDiagRf = safeNum(hitTarget.remainingImpactForce);
        hitTarget._pendingDownDiagCap = safeNum(hitTarget.韧性上限);
        hitTarget._pendingDownDiagStagger = safeNum(hitTarget.impactStaggerBoundary);
        hitTarget._pendingDownDiagRigid = isRigid ? 1 : 0;
        hitTarget._pendingDownDiagDodge = (damageResult == null || damageResult.dodgeStatus == null || damageResult.dodgeStatus == "") ? "-" : damageResult.dodgeStatus;
        hitTarget._pendingDownDiagDirection = hitDirection;
        hitTarget._pendingDownDiagKbX = safeNum(bullet.水平击退速度);
        hitTarget._pendingDownDiagKbY = safeNum(bullet.垂直击退速度);
    }

    public static function flushPendingDiagnostics(target:MovieClip):Void {
        if (target == null || target._pendingDownDiag != true) {
            return;
        }

        var frame:Number = (_root.帧计时器 != undefined) ? _root.帧计时器.当前帧数 : -1;
        var queuedFrame:Number = Number(target._pendingDownDiagFrame);
        if (!isNaN(queuedFrame) && frame - queuedFrame > DOWN_PENDING_MAX_AGE) {
            target._pendingDownDiag = false;
            return;
        }
        if (!shouldTrackCombatDiagnostics(target)) {
            target._pendingDownDiag = false;
            return;
        }

        logDiagnostic("[UNIT-DOWN] " + target._name
            + " reason=" + (target._pendingDownDiagReason || "-")
            + " hp=" + (target._pendingDownDiagHpPct || "-")
            + " rf=" + (target._pendingDownDiagRf || "-") + "/" + (target._pendingDownDiagCap || "-")
            + " stagger=" + (target._pendingDownDiagStagger || "-")
            + " rigid=" + (target._pendingDownDiagRigid || 0)
            + " dodge=" + (target._pendingDownDiagDodge || "-")
            + " dir=" + (target._pendingDownDiagDirection || "-")
            + " kb=" + (target._pendingDownDiagKbX || "-") + "/" + (target._pendingDownDiagKbY || "-")
            + " src=" + (target._lastHitShooterName || "-") + "/" + (target._lastHitBulletName || "-")
            + getAICombatSnapshot(target));
        target._pendingDownDiag = false;
    }

    /**
     * 处理冲击力与状态判断。
     * @param hitTarget 被击中的目标对象
     * @param bullet 当前子弹对象，包含相关击退参数
     * @param damageResult 子弹造成伤害的结果信息，包含躲闪状态等数据
     * @param hitDirection 初步判断后的受击方向（"左" 或 "右"）
     * @param bloodEnabled 是否开启血腥效果的开关
     */
    public static function handleImpactState(hitTarget:MovieClip, 
                                             bullet:MovieClip, 
                                             damageResult:DamageResult, 
                                             hitDirection:String, 
                                             bloodEnabled:Boolean):Void {
        var trackDiag:Boolean = shouldTrackCombatDiagnostics(hitTarget);
        var isRigid:Boolean = hitTarget.刚体 || hitTarget.man.刚体标签;
        var impactReason:String = "MOVE";
        var impactForceSnapshot:Number = hitTarget.remainingImpactForce;
        var impactCapSnapshot:Number = hitTarget.韧性上限;
        var impactStaggerSnapshot:Number = hitTarget.impactStaggerBoundary;

        // 若目标既不处于浮空也不处于倒地状态，执行常规冲击处理
        if (!(hitTarget.浮空 || hitTarget.倒地)) {
        // if (hitTarget.状态 !== "击倒" || hitTarget.状态 !== "倒地") {
            ImpactHandler.settleImpactForce(hitTarget.损伤值, bullet.击倒率, hitTarget);
            impactForceSnapshot = hitTarget.remainingImpactForce;
            impactCapSnapshot = hitTarget.韧性上限;
            impactStaggerSnapshot = hitTarget.impactStaggerBoundary;
            hitTarget.barColorState = "常态";

            if (hitTarget.hp <= 0) {
                // 血量耗尽，根据血腥开关设定死亡或击倒状态
                impactReason = bloodEnabled ? "LETHAL" : "LETHAL_DOWN";
                hitTarget.状态改变(bloodEnabled ? "血腥死" : "击倒");
                if (!bloodEnabled) {
                    queueKnockdownDiagnostic(hitTarget, bullet, damageResult, hitDirection, isRigid, impactReason);
                }
            } else if (damageResult.dodgeStatus == "躲闪") {
                // 目标成功躲闪，执行被击移动效果
                impactReason = "DODGE";
                hitTarget.被击移动(hitDirection, bullet.水平击退速度, 3);
            } else if (hitTarget.remainingImpactForce > hitTarget.韧性上限) {
                // 冲击力超过韧性上限，如非刚体则设为击倒状态，并重置冲击力
                impactReason = "TOUGH_BREAK";
                if (!isRigid) {
                    hitTarget.状态改变("击倒");
                    hitTarget.barColorState = "击倒";
                    queueKnockdownDiagnostic(hitTarget, bullet, damageResult, hitDirection, isRigid, impactReason);
                }
                hitTarget.remainingImpactForce = 0;
                hitTarget.被击移动(hitDirection, bullet.水平击退速度, 0.5);
            } else if (hitTarget.remainingImpactForce > hitTarget.impactStaggerBoundary) {
                // 冲击力处于中间范围，如非刚体则设为被击状态
                impactReason = "STAGGER";
                if (!isRigid) {
                    hitTarget.状态改变("被击");
                    hitTarget.barColorState = "被击";
                }
                hitTarget.被击移动(hitDirection, bullet.水平击退速度, 2);
            } else {
                // 其他情况，执行默认被击移动效果
                impactReason = "MOVE";
                hitTarget.被击移动(hitDirection, bullet.水平击退速度, 3);
            }
        } else {
            // 当目标处于浮空或倒地状态时的处理逻辑
            impactReason = "AIRBORNE_DOWN";
            hitTarget.remainingImpactForce = 0;
            if (!isRigid) {
                hitTarget.状态改变("击倒");
                hitTarget.barColorState = "击倒";
                queueKnockdownDiagnostic(hitTarget, bullet, damageResult, hitDirection, isRigid, impactReason);
                if (bullet.垂直击退速度 <= 0) {
                    if(hitTarget.垂直速度 > -5) hitTarget.垂直速度 = -5;
                    hitTarget.man.垂直速度 = -5;
                }
            }
            hitTarget.被击移动(hitDirection, bullet.水平击退速度, 0.5);
        }

        // 若子弹有垂直击退速度，则恢复动画播放并处理相关状态
        // 尝试应用负的垂直击退速度
        if (bullet.垂直击退速度 > 0 || bullet.垂直击退速度 < 0) {
            hitTarget.man.play();
            hitTarget.硬直中 = false;
            // _root.fly(hitTarget, bullet.垂直击退速度, 0);
            var flyspeed = hitTarget.起跳速度 - bullet.垂直击退速度;
            if(hitTarget.垂直速度 > flyspeed){
                hitTarget.垂直速度 = flyspeed;
            }
        }

        if (trackDiag) {
            stashImpactSnapshot(hitTarget, bullet, damageResult, hitDirection, impactReason,
                impactForceSnapshot, impactCapSnapshot, impactStaggerSnapshot);
        }
    }
}
