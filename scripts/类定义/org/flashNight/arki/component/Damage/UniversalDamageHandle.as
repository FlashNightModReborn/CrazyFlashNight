import org.flashNight.arki.component.Damage.*;
import org.flashNight.arki.component.StatHandler.*;

/**
 * UniversalDamageHandle 类用于处理通用伤害以及躲闪状态的处理器。
 * - 优化合并了原来的 DodgeStateDamageHandle 逻辑。
 * - 通过减少冗余、合并分支、内联位运算等方式进行性能提升。
 * - 内联颜色常量以消除变量分配和解引用开销。
 */
class org.flashNight.arki.component.Damage.UniversalDamageHandle extends BaseDamageHandle implements IDamageHandle {

    // ========== 单例实例 ==========
    public static var instance:UniversalDamageHandle = new UniversalDamageHandle();

    /**
     * 构造函数。
     * 初始化时设置 skipCheck 为 true，表示始终处理伤害和躲闪状态。
     */
    public function UniversalDamageHandle() {
        this.skipCheck = true;
    }

    /**
     * 获取 UniversalDamageHandle 的单例实例 (闭包优化)。
     */
    public static function getInstance():UniversalDamageHandle {
        if (instance == null) {
            instance = new UniversalDamageHandle();
            getInstance = function():UniversalDamageHandle {
                return instance;
            };
        }
        return instance;
    }

    /**
     * 始终返回 true，表示可处理所有子弹。
     */
    public function canHandle(bullet:Object):Boolean {
        return true;
    }

    /**
     * 处理子弹伤害（含通用伤害 + 躲闪状态）。
     *
     * @param bullet  子弹对象
     * @param shooter 射击者对象
     * @param target  目标对象
     * @param manager 管理器对象 (其中包含 dodgeState)
     * @param result  伤害结果对象 (其中包含 damageSize 等)
     */
    public function handleBulletDamage(bullet:Object, shooter:Object, target:Object, manager:Object, result:DamageResult):Void {

        // -----------【通用伤害阶段】-----------
        var bulletPower:Number = bullet.破坏力;
        var damageType:String = bullet.伤害类型;
        var isFriendly:Boolean = bullet.子弹敌我属性值;  // 若为真，说明是友方子弹？


        //_root.发布消息("power: " + bulletPower + " type: " + damageType + " isFriendly: " + isFriendly);
        // 定义整合后的最终输出值
        var finalDamage:Number;
        var finalDamageSize:Number = result.damageSize;  // 初始大小
        var finalColor:String;     // 最终颜色
        var finalEffect:String;    // 最终伤害文本特效（如 "真" "能" "物"）

        // 先做通用伤害逻辑
        switch (damageType) {

            case "真伤":
                finalColor  = isFriendly ? "#4A0099" : "#660033";  // 直接内联颜色
                finalEffect = '<font color="' + finalColor + '" size="20"> 真</font>';
                finalDamage = bulletPower; // 真伤直接=破坏力

                //_root.发布消息("真伤" + " finalDamage: " + finalDamage + " finalColor: " + finalColor + " finalEffect: " + finalEffect);
                break;

            case "魔法":
                var bulletMagicAttr:String = bullet.魔法伤害属性; 
                var targetResist:Object    = target.魔法抗性;
                var targetLevel:Number     = target.等级;

                finalColor  = isFriendly ? "#0099FF" : "#AC99FF";  // 直接内联颜色
                finalEffect = '<font color="' + finalColor + '" size="20"> ' 
                              + (bulletMagicAttr ? bulletMagicAttr : "能") + '</font>';

                // 计算魔抗
                var enemyMagicResist:Number =
                    (bulletMagicAttr && targetResist && (targetResist[bulletMagicAttr] || targetResist[bulletMagicAttr] === 0))
                        ? targetResist[bulletMagicAttr]
                        : (targetResist && (targetResist["基础"] || targetResist["基础"] === 0))
                            ? targetResist["基础"]
                            : 10 + (targetLevel >> 1); // 右移优化

                // isNaN 检查 & 范围限制
                if (enemyMagicResist != enemyMagicResist) { 
                    // 等价 isNaN()
                    enemyMagicResist = 20;
                } else if (enemyMagicResist < -1000) {
                    enemyMagicResist = -1000;
                } else if (enemyMagicResist > 100) {
                    enemyMagicResist = 100;
                }

                var magicDamage:Number = bulletPower * (100 - enemyMagicResist) * 0.01;
                // 若>=0则用 (|0) 截断，若<0 则向下取整
                finalDamage = (magicDamage >= 0)
                                ? (magicDamage | 0)
                                : ((magicDamage == (magicDamage | 0)) ? magicDamage : ((magicDamage - 1) | 0));
                
                //_root.发布消息("Resist: " + enemyMagicResist + " finalDamage: " + finalDamage + " finalColor: " + finalColor + " finalEffect: " + finalEffect);
                break;

            default: // 基础物理伤害
                finalColor  = isFriendly ? "#FFCC00" : "#FF0000";  // 直接内联颜色
                finalEffect = '<font color="' + finalColor + '" size="20"> </font>';
                finalDamage = bulletPower * DamageResistanceHandler.defenseDamageRatio(target.防御力);
                //_root.发布消息("defense: " + target.防御力 + " finalDamage: " + finalDamage + " finalColor: " + finalColor + " finalEffect: " + finalEffect);
                break;
        }

        //_root.发布消息("firstDamage: " + finalDamage + " firstColor: " + finalColor + " firstEffect: " + finalEffect);

        // 添加通用伤害效果
        result.addDamageEffect(finalEffect);

        // -----------【躲闪处理阶段】-----------
        // 注意：最终伤害要在此基础上根据躲闪来修正
        var dodgeState:String = manager.dodgeState;
        if (dodgeState) { // 如果有躲闪状态，进行处理
            switch (dodgeState) {

                case "跳弹":
                    finalDamage = DamageResistanceHandler.bounceDamageCalculation(finalDamage, target.防御力);
                    finalColor  = isFriendly ? "#7F6A00" : "#7F0000";  // 直接内联颜色

                    // 根据新伤害比率动态缩放伤害大小
                    finalDamageSize *= 0.3 + 0.7 * finalDamage / bulletPower;
                    break;

                case "过穿":
                    finalDamage = DamageResistanceHandler.penetrationDamageCalculation(finalDamage, target.防御力);
                    finalColor  = isFriendly ? "#FFE770" : "#FF7F7F";  // 直接内联颜色

                    // 根据新伤害比率动态缩放伤害大小
                    finalDamageSize *= 0.3 + 0.7 * finalDamage / bulletPower;
                    break;

                case "躲闪":
                case "直感":
                    finalDamage = 0;       // 直接赋值为 0
                    finalDamageSize *= 0.5;
                    result.dodgeStatus = "MISS";
                    break;

                case "格挡":
                    var blockValue:Number = target.受击反制(finalDamage, bullet);
                    if (blockValue > 0) {
                        // 普通格挡，造成一些反制伤害
                        finalDamage = blockValue;
                        finalDamageSize *= 0.3 + 0.7 * blockValue / bulletPower;
                    } else if (blockValue === 0) {
                        // 完全被格挡掉，没伤害
                        finalDamage = 0;
                        finalDamageSize *= 1.2;
                    } else {
                        // blockValue<0 或者 NaN，视为 MISS
                        finalDamage = 0;
                        finalDamageSize *= 0.5;
                        result.dodgeStatus = "MISS";
                    }
                    break;

                default:
                    // 无匹配时，相当于无躲闪；但仍需对伤害进行最小值处理
                    // 如果 finalDamage <= 0，则至少保证为 1
                    if (finalDamage <= 0) {
                        finalDamage = 1;
                    } else {
                        finalDamage = finalDamage | 0; // 向下取整
                    }
                    // 原逻辑：_root.受击变红(120, target);
                    _root.受击变红(120, target);
            }
        } else {
            // 若没有任何躲闪状态，也需要对伤害进行最小值处理
            if (finalDamage <= 0) {
                finalDamage = 1;
            } else {
                finalDamage = finalDamage | 0;
            }
        }

        _root.服务器.发布服务器消息("通用计算完成 " + result.toString());
        //_root.发布消息("finalDamage: " + finalDamage + " finalColor: " + finalColor + " finalEffect: " + finalEffect);

        // -----------【统一写回】-----------
        target.损伤值 = finalDamage;        // 最终伤害
        result.damageSize = finalDamageSize; // 更新伤害大小
        result.setDamageColor(finalColor);    // 最终生效颜色(可能被躲闪阶段覆盖)

        // 备注：在原代码中，“通用伤害”部分会立即 setDamageColor，
        //       但之后在躲闪分支又可能调用 setDamageColor 从而覆盖。
        //       为减少函数调用开销，这里在最后只调用一次 setDamageColor。
    }

    public function toString():String {
        return "UniversalDamageHandle";
    }
}
