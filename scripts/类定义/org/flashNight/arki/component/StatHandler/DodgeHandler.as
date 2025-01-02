import org.flashNight.naki.NormalizationUtil;
import org.flashNight.naki.RandomNumberEngine.*;

/**
 * DodgeHandler
 * 负责与闪避、命中计算相关的逻辑，如：
 *  - 躲闪状态校验
 *  - 根据等级计算闪避率
 *  - 根据命中率计算是否闪避成功
 *  - 懒闪避（Lazy Miss）处理
 */
class org.flashNight.arki.component.StatHandler.DodgeHandler
{
    // ----------------- 常量定义 -----------------
    // 对应原脚本中的各类闪避相关常量
    public static var DODGE_RATE_LIMIT:Number = 0.01;           // 最低闪避率
    public static var HIT_RATE_LIMIT:Number   = 0.01;           // 最低命中率
    public static var DODGE_SYSTEM_MAX:Number = 0.5 * 100;      // 闪避系统闪避率上限(50%)
    public static var BASE_DODGE_RATE:Number  = 3;              // 基准躲闪率
    public static var BASE_HIT_RATE:Number    = 10;             // 基准命中率

    // 对应原脚本中的重量参考
    public static var JUMP_BOUNCE_BASE_WEIGHT:Number = 100;     // 跳弹基准重量
    public static var PENETRATION_BASE_WEIGHT:Number = 20;      // 过穿基准重量

    private static var RandomNumberEngine:LinearCongruentialEngine = LinearCongruentialEngine.getInstance();

    // ----------------- 方法定义 -----------------

    /**
     * 根据重量判断躲闪类型（跳弹/过穿/躲闪），对应 _root.躲闪状态校验
     * @param weight  重量
     * @param level   等级
     * @return "躲闪" / "跳弹" / "过穿"
     */
    public static function checkDodgeState(weight:Number, level:Number):String
    {
        if (DodgeHandler.RandomNumberEngine.successRate(level - weight))
        {
            return "躲闪";
        }
        else if (DodgeHandler.RandomNumberEngine.successRate(100 * (weight - PENETRATION_BASE_WEIGHT) / (JUMP_BOUNCE_BASE_WEIGHT - PENETRATION_BASE_WEIGHT)))
        {
            return "跳弹";
        }
        else
        {
            return "过穿";
        }
    }

    /**
     * 具体的躲闪状态计算逻辑（对应 _root.躲闪状态计算）
     * @param targetMC   命中对象 (MovieClip)
     * @param dodgeResult  是否躲闪成功 (true/false)
     * @param bulletMC   子弹 (MovieClip)
     * @return 对应的躲闪状态字符串，如 "直感" / "躲闪" / "跳弹" / "过穿" / "格挡" / "未躲闪"
     */
    public static function calculateDodgeState(targetMC:MovieClip, dodgeResult:Boolean, bulletMC:MovieClip):String
    {
        // 计算用伤害值 = 命中对象.损伤值 + 子弹.附加层伤害计算
        var calcDamage:Number = targetMC.损伤值 + bulletMC.附加层伤害计算;
        calcDamage = (isNaN(calcDamage) ? 0 : calcDamage);

        // 懒闪避相关逻辑
        if (targetMC.懒闪避 > 0)
        {
            if (lazyMiss(targetMC, calcDamage, targetMC.懒闪避))
            {
                return "直感";
            }
        }

        if (dodgeResult)
        {
            // 等级/重量异常校验
            if (isNaN(targetMC.等级))
            {
                targetMC.等级 = 1;
                _root.发布消息(targetMC + " 触发异常等级 " + targetMC.等级);
            }
            if (isNaN(targetMC.重量))
            {
                targetMC.重量 = 999;
                _root.发布消息(targetMC + " 触发异常重量 " + targetMC.重量);
            }
            // 若闪避成功，调用 checkDodgeState
            return checkDodgeState(targetMC.重量, targetMC.等级);
        }
        else if (targetMC.受击反制)
        {
            return "格挡";
        }
        return "未躲闪";
    }

    /**
     * 根据攻击者、闪避者的等级和命中/躲闪率来计算最终躲闪率（对应 _root.根据等级计算闪避率）
     * @param attackerLevel  攻击者等级
     * @param dodgerLevel    闪避者等级
     * @param dodgeRate      闪避率
     * @param hitRate        命中率
     * @return 最终可用的躲闪率
     */
    public static function calcDodgeRateByLevel(attackerLevel:Number, dodgerLevel:Number, dodgeRate:Number, hitRate:Number):Number
    {
        // 边界/异常处理
        if (dodgeRate < 0 || isNaN(dodgeRate))
        {
            return 0;
        }
        // 公式：(闪避者等级 * 基准命中率 / 闪避率 - 攻击者等级 * 命中率 / 基准躲闪率) / 40
        var dodgeIndex:Number = (dodgerLevel * BASE_HIT_RATE / dodgeRate 
                               - attackerLevel * hitRate / BASE_DODGE_RATE) / 40;
        // 通过 sigmoid 进行压缩，再乘以闪避上限
        var finalRate:Number = NormalizationUtil.sigmoid(dodgeIndex) * DODGE_SYSTEM_MAX;
        return finalRate;
    }

    /**
     * 根据命中率计算是否能躲闪（对应 _root.根据命中计算闪避结果）
     * @param shooter  发射者对象
     * @param target   命中者对象
     * @param inputHitRate   外部传入的命中率 (可能是 shooter.命中率)
     * @return Boolean 是否成功躲闪
     */
    public static function calcDodgeResult(shooter:Object, target:Object, inputHitRate:Number):Boolean
    {
        // 1. 根据等级计算出闪避率
        var dodgeRate:Number = calcDodgeRateByLevel(shooter.等级, target.等级, target.躲闪率, inputHitRate);

        // 2. 若结果为 NaN，则进行异常值修正
        if (isNaN(dodgeRate))
        {
            shooter.等级   = (isNaN(shooter.等级)   ? 1              : shooter.等级);
            shooter.命中率 = (isNaN(shooter.命中率) ? BASE_HIT_RATE  : shooter.命中率);
            target.等级   = (isNaN(target.等级)     ? 1              : target.等级);
            target.躲闪率 = (isNaN(target.躲闪率)   ? 999            : target.躲闪率);

            // 重新计算
            dodgeRate = calcDodgeRateByLevel(shooter.等级, target.等级, target.躲闪率, shooter.命中率);
        }

        // 3. 最终通过 RandomNumberEngine.successRate(dodgeRate) 来判断是否成功闪避
        return RandomNumberEngine.successRate(dodgeRate);
    }

    /**
     * 懒闪避（Lazy Miss）逻辑
     * 低于5%总血量不闪避，高于100%时达到最大闪避
     * @param Obj 被攻击对象
     * @param damage 伤害值
     * @param lazyMissValue 懒闪避值
     * @return Boolean 是否进行懒闪避
     */
    private static function lazyMiss(Obj:Object, damage:Number, lazyMissValue:Number):Boolean
    {
        // 检查对象的生命值是否有效
        if (!Obj.hp满血值 || !Obj.hp || Obj.hp <= 0)
        {
            return false;
        }

        var fullHp:Number = Obj.hp满血值;
        var currentHp:Number = Obj.hp;
        var successRate:Number;

        // 如果伤害大于半血
        if (damage > fullHp / 2)
        {
            successRate = 100 * lazyMissValue;
        }
        // 如果当前血量小于半血
        else if (currentHp < fullHp / 2)
        {
            if (damage > fullHp / 5)
            {
                successRate = 100 * lazyMissValue;
            }
            else if (damage < fullHp * 0.025)
            {
                return false; // 伤害小于2.5%不闪避
            }
            else
            {
                // 计算动态闪避率
                successRate = 100 * lazyMissValue * damage * 5 / fullHp;
            }
        }
        // 当前血量大于或等于半血
        else
        {
            if (damage < fullHp * 0.05)
            {
                return false; // 伤害小于5%不闪避
            }
            // 计算动态闪避率
            successRate = 100 * lazyMissValue * damage * 2 / fullHp;
        }

        return successRate > 0 ? RandomNumberEngine.successRate(successRate) : false;
    }
}
