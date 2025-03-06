import org.flashNight.arki.component.StatHandler.*;
import org.flashNight.sara.util.*;
import org.flashNight.arki.component.Damage.*;
import org.flashNight.arki.component.Collider.*;

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

            // 获取并显示血槽（新版或旧版取决于 hitTarget 的数据结构）
            var bar = (hitTarget.新版人物文字信息) ? hitTarget.新版人物文字信息.头顶血槽 : hitTarget.人物文字信息.头顶血槽;
            bar._visible = true;
            bar.gotoAndPlay(2);

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
            
            // 根据血腥开关，生成对应的击中血液效果
            if (_root.血腥开关) {
                var bulletEffectFragment:String = "";
                switch (hitTarget.击中效果) {
                    case "飙血":
                        bulletEffectFragment = "子弹碎片-飞血";
                        break;
                    case "异形飙血":
                        bulletEffectFragment = "子弹碎片-异形飞血";
                        break;
                    default:
                        // 不生成子弹效果
                }
                if(bulletEffectFragment != "") {
                    var effectInstance = _root.效果(bulletEffectFragment, overlapCenter.x, overlapCenter.y, shooter._xscale);
                    effectInstance.出血来源 = hitTarget._name;
                }
            }


            // ────────────── 冲击力与状态判断 ──────────────

            // 缓存目标血量和刚体状态
            var hp:Number = hitTarget.hp;
            var isRigid:Boolean = hitTarget.刚体 || hitTarget.man.刚体标签;

            // 若目标不处于浮空或倒地状态，进行常态冲击处理
            if (!hitTarget.浮空 && !hitTarget.倒地) {
                // 计算冲击力结算
                _root.冲击力结算(hitTarget.损伤值, bullet.击倒率, hitTarget);
                hitTarget.barColorState = "常态";

                if (hp <= 0) {
                    // 血量耗尽，根据血腥开关设定死亡或击倒状态
                    hitTarget.状态改变(_root.血腥开关 ? "血腥死" : "击倒");
                } else if (damageResult.dodgeStatus == "躲闪") {
                    // 目标成功躲闪，执行被击移动效果
                    hitTarget.被击移动(hitDirection, bullet.水平击退速度, 3);
                } else {
                    // 根据剩余冲击力与韧性上限的对比决定后续状态和移动效果
                    if (hitTarget.remainingImpactForce > hitTarget.韧性上限) {
                        if (!isRigid) {
                            hitTarget.状态改变("击倒");
                            hitTarget.barColorState = "击倒";
                        }
                        hitTarget.remainingImpactForce = 0;
                        hitTarget.被击移动(hitDirection, bullet.水平击退速度, 0.5);
                    } else if (hitTarget.remainingImpactForce > hitTarget.韧性上限 / ImpactHandler.IMPACT_STAGGER_COEFFICIENT / hitTarget.躲闪率) {
                        if (!isRigid) {
                            hitTarget.状态改变("被击");
                            hitTarget.barColorState = "被击";
                        }
                        hitTarget.被击移动(hitDirection, bullet.水平击退速度, 2);
                    } else {
                        hitTarget.被击移动(hitDirection, bullet.水平击退速度, 3);
                    }
                }
            }
            // 若目标处于浮空或倒地状态，则执行不同的处理
            else {
                hitTarget.remainingImpactForce = 0;
                if (!isRigid) {
                    hitTarget.状态改变("击倒");
                    hitTarget.barColorState = "击倒";
                    if (!(bullet.垂直击退速度 > 0)) {
                        var y速度 = 5;
                        hitTarget.man.垂直速度 = -y速度;
                    }
                }
                hitTarget.被击移动(hitDirection, bullet.水平击退速度, 0.5);
            }

            // 再次检测血量，若血量耗尽且非近战/爆炸子弹，则设为死亡状态
            if (hp <= 0) {
                if (!bullet.近战检测 && !bullet.爆炸检测) {
                    hitTarget.状态改变("血腥死");
                }
            }


            // ────────────── 血槽颜色与后续特效 ──────────────

            // 根据当前状态，重置或暗化血槽色彩
            switch (hitTarget.barColorState) {
                case "常态":
                    _root.重置色彩(bar);
                    break;
                default:
                    _root.暗化色彩(bar);
            }

            // 生成击中特效（不影响后续的子弹效果判断）
            _root.效果(hitTarget.击中效果, overlapCenter.x, overlapCenter.y, shooter._xscale);

            // 判断是否需要生成子弹击中后的后续效果（目前仅标记，不做处理）
            bullet.shouldGeneratePostHitEffect = true;
            if (hitTarget.击中效果 == bullet.击中后子弹的效果) {
                bullet.shouldGeneratePostHitEffect = false;
            }


            // ────────────── 垂直击退处理 ──────────────

            // 若子弹有垂直击退速度，则恢复动画播放并处理相关状态
            if (bullet.垂直击退速度 > 0) {
                hitTarget.man.play();
                clearInterval(hitTarget.pauseInterval);
                hitTarget.硬直中 = false;
                clearInterval(hitTarget.pauseInterval2);
                _root.fly(hitTarget, bullet.垂直击退速度, 0);
            }
        };
    }
}
