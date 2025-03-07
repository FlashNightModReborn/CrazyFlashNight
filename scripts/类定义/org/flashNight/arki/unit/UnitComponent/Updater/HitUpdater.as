import org.flashNight.arki.component.StatHandler.*;
import org.flashNight.sara.util.*;
import org.flashNight.arki.component.Damage.*;
import org.flashNight.arki.component.Collider.*;
import org.flashNight.arki.component.Effect.*;
import org.flashNight.arki.unit.UnitComponent.Status.*;

class org.flashNight.arki.unit.UnitComponent.Updater.HitUpdater {

    public static function getUpdater():Function {
        return function(hitTarget:MovieClip, shooter:MovieClip, bullet:MovieClip, collisionResult:CollisionResult, damageResult:DamageResult):Void {

            // ────────────── 调试与预处理 ──────────────

            // 若处于调试模式，绘制目标区域轮廓
            if(_root.调试模式) {
                _root.绘制线框(hitTarget.area);
            }

            // 刷新目标的冲击力数据
            ImpactHandler.refreshImpactForce(hitTarget);

            // 记录攻击来源
            hitTarget.攻击目标 = shooter._name;

            // 若命中目标为玩家控制对象，则刷新玩家血量显示
            if (hitTarget._name === _root.控制目标) {
                _root.玩家信息界面.刷新hp显示();
            }

            // 初步判断：若非近战/爆炸子弹且目标血量已耗尽，直接设定死亡状态
            if (!bullet.近战检测 && !bullet.爆炸检测 && hitTarget.hp <= 0) {
                hitTarget.状态改变("血腥死");
            }


            // ────────────── 方向判断及效果 ──────────────

            // 利用布尔运算确定初始受击方向，考虑了两个因素：
            // 1. 命中对象相对于射手的位置：若 hitTarget 的 _x 坐标小于 shooter 的 _x 坐标，表示 hitTarget 位于射手左侧。
            // 2. 子弹是否要求反转水平击退方向（bullet.水平击退反向 为 true 时表示需要反转）。
            //
            // 这里用异或（^）操作符，将两个布尔值进行组合，解释如下：
            // - 若 hitTarget 在射手左侧 (true) 且 bullet.水平击退反向 为 false，则 true ^ false 得到 true，
            //   表示默认方向为“左”；
            // - 若 hitTarget 在射手左侧 (true) 但 bullet.水平击退反向 为 true，则 true ^ true 得到 false，
            //   表示反转方向，变为“右”；
            // - 若 hitTarget 不在射手左侧 (false) 且 bullet.水平击退反向 为 false，则 false ^ false 得到 false，
            //   默认方向为“右”；
            // - 若 hitTarget 不在射手左侧 (false) 但 bullet.水平击退反向 为 true，则 false ^ true 得到 true，
            //   反转后方向为“左”。
            //
            // 根据异或运算的结果，使用三元运算符直接赋值 hitDirection 为 "左" 或 "右"。
            var hitDirection:String = ((hitTarget._x < shooter._x) ^ bullet.水平击退反向) ? "左" : "右";

            // 为了实现被击目标视觉上"面向"与受击方向相反的效果（左右取反），
            // 这里将 hitTarget 的面向设置为 hitDirection 的反方向。
            // 例如：如果 hitDirection 为 "左"，则将 hitTarget 面向设置为 "右"。
            hitTarget.方向改变((hitDirection == "左") ? "右" : "左");


            var overlapCenter:Vector = collisionResult.overlapCenter;
            var ocx:Number = overlapCenter.x;
            var ocy:Number = overlapCenter.y;
            var sxc:Number = shooter._xscale;
            var bloodEnabled:Boolean = _root.血腥开关;
            
            // 根据血腥开关，生成对应的击中血液效果
            if(bloodEnabled) BulletEffectHandler.createBulletEffect(
                hitTarget,
                ocx,
                ocy,
                sxc
            );
            

            // ────────────── 冲击力与状态判断 ──────────────
            ImpactStateHandler.handleImpactState(hitTarget, bullet, damageResult, hitDirection, bloodEnabled);
 
            // ────────────── 血槽颜色与后续特效 ──────────────

            // 根据当前状态，重置或暗化血槽色彩
            BloodBarEffectHandler.updateStatus(hitTarget);

            // 生成击中特效
            EffectSystem.Effect(hitTarget.击中效果, ocx, ocy, sxc);

            // 判断是否需要生成子弹击中后的后续效果
            bullet.shouldGeneratePostHitEffect = (hitTarget.击中效果 != bullet.击中后子弹的效果);
        };
    }
}
