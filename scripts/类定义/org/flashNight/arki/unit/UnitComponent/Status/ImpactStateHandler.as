import org.flashNight.arki.component.Damage.*;
import org.flashNight.arki.component.StatHandler.*;

/**
 * ImpactStateHandler
 * 用于处理单位受击后的冲击力与状态判断逻辑。
 * 此类提供一个静态方法 handleImpactState() 来处理 hitTarget 的状态改变与受击移动。
 */
class org.flashNight.arki.unit.UnitComponent.Status.ImpactStateHandler {

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
        var isRigid:Boolean = hitTarget.刚体 || hitTarget.man.刚体标签;

        // 若目标既不处于浮空也不处于倒地状态，执行常规冲击处理
        if (!(hitTarget.浮空 || hitTarget.倒地)) {
        // if (hitTarget.状态 !== "击倒" || hitTarget.状态 !== "倒地") {
            ImpactHandler.settleImpactForce(hitTarget.损伤值, bullet.击倒率, hitTarget);
            hitTarget.barColorState = "常态";

            if (hitTarget.hp <= 0) {
                // 血量耗尽，根据血腥开关设定死亡或击倒状态
                hitTarget.状态改变(bloodEnabled ? "血腥死" : "击倒");
            } else if (damageResult.dodgeStatus == "躲闪") {
                // 目标成功躲闪，执行被击移动效果
                hitTarget.被击移动(hitDirection, bullet.水平击退速度, 3);
            } else if (hitTarget.remainingImpactForce > hitTarget.韧性上限) {
                // 冲击力超过韧性上限，如非刚体则设为击倒状态，并重置冲击力
                if (!isRigid) {
                    hitTarget.状态改变("击倒");
                    hitTarget.barColorState = "击倒";
                }
                hitTarget.remainingImpactForce = 0;
                hitTarget.被击移动(hitDirection, bullet.水平击退速度, 0.5);
            } else if (hitTarget.remainingImpactForce > hitTarget.impactStaggerBoundary) {
                // 冲击力处于中间范围，如非刚体则设为被击状态
                if (!isRigid) {
                    hitTarget.状态改变("被击");
                    hitTarget.barColorState = "被击";
                }
                hitTarget.被击移动(hitDirection, bullet.水平击退速度, 2);
            } else {
                // 其他情况，执行默认被击移动效果
                hitTarget.被击移动(hitDirection, bullet.水平击退速度, 3);
            }
        } else {
            // 当目标处于浮空或倒地状态时的处理逻辑
            hitTarget.remainingImpactForce = 0;
            if (!isRigid) {
                hitTarget.状态改变("击倒");
                hitTarget.barColorState = "击倒";
                if (bullet.垂直击退速度 <= 0) {
                    if(hitTarget.垂直速度 > -5) hitTarget.垂直速度 = -5;
                    hitTarget.man.垂直速度 = -5;
                }
            }
            hitTarget.被击移动(hitDirection, bullet.水平击退速度, 0.5);
        }

        // 若子弹有垂直击退速度，则恢复动画播放并处理相关状态
        if (bullet.垂直击退速度 > 0) {
            hitTarget.man.play();
            // 安全地取消硬直:同时清除硬直定时器和标志
            if (hitTarget.knockStiffID != null) {
                _root.EnhancedCooldownWheel.I().removeTask(hitTarget.knockStiffID);
                hitTarget.knockStiffID = null;
            }
            hitTarget.硬直中 = false;
            // _root.fly(hitTarget, bullet.垂直击退速度, 0);
            var flyspeed = hitTarget.起跳速度 - bullet.垂直击退速度;
            if(hitTarget.垂直速度 > flyspeed){
                hitTarget.垂直速度 = flyspeed;
            }
        }
    }
}
