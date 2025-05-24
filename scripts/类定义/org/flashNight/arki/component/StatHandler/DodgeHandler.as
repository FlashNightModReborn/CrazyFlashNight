import org.flashNight.naki.RandomNumberEngine.*;
import org.flashNight.naki.Normalization.*;

import org.flashNight.arki.component.StatHandler.*; // 状态处理

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
    public static var DODGE_RATE_LIMIT:Number = 0.01;           // 最低闪避率
    public static var HIT_RATE_LIMIT:Number   = 0.01;           // 最低命中率
    public static var DODGE_SYSTEM_MAX:Number = 0.5 * 100;      // 闪避系统闪避率上限(50%)
    public static var BASE_DODGE_RATE:Number  = 3;              // 基准躲闪率
    public static var BASE_HIT_RATE:Number    = 10;             // 基准命中率

    // 重量参考常量
    public static var JUMP_BOUNCE_BASE_WEIGHT:Number = 100;     // 跳弹基准重量
    public static var PENETRATION_BASE_WEIGHT:Number = 20;      // 过穿基准重量
    public static var BOUNCE_PENETRATION_RANGE_WEIGHT:Number = JUMP_BOUNCE_BASE_WEIGHT - PENETRATION_BASE_WEIGHT;


    private static var RandomNumberEngine:LinearCongruentialEngine = LinearCongruentialEngine.getInstance();

    // ----------------- 方法定义 -----------------

    /**
     * 根据重量判断躲闪类型（跳弹/过穿/躲闪），对应 _root.躲闪状态校验
     * @param weight 重量
     * @param level  等级
     * @return 躲闪状态字符串
     */
    public static function checkDodgeState(weight:Number, level:Number):String {
        // 1. 生成一个 [0, 1] 范围内的随机数
        var r:Number = RandomNumberEngine.nextFloat();

        // 2. 计算躲闪概率，并归一化到 [0, 1]，使用一行表达式：
        //    先计算 (level - weight)：
        //       - 如果小于 0，则归一化结果为 0；
        //       - 如果大于 100，则归一化结果为 1；
        //       - 否则，归一化为 (level - weight) / 100
        var dodgeProb:Number = ((dodgeProb = level - weight) < 0)
                                ? 0
                                : ((dodgeProb > 100) ? 1 : (dodgeProb / 100));

        // 3. 如果随机数在躲闪概率以内，则直接返回“躲闪”
        if (r <= dodgeProb) {
            return DodgeStatus.DODGE;
        } else {
            // 4. 否则，对剩余概率空间 [dodgeProb, 1] 归一化，
            //    同时直接内联计算跳弹概率，并利用同一寄存器 r 做中间计算：
            //
            //    - 左侧表达式 (r - dodgeProb) / (1 - dodgeProb)
            //      将原始随机数 r 从整体 [0,1] 空间映射到 [0,1] 范围，
            //      其中 [0, dodgeProb] 已用于躲闪判断，剩余部分用来判断跳弹/过穿。
            //
            //    - 右侧表达式计算跳弹概率：
            //        先将 r 赋值为 (weight - PENETRATION_BASE_WEIGHT)，
            //          * 如果小于 0（即 weight 小于等于 PENETRATION_BASE_WEIGHT），跳弹概率为 0；
            //          * 如果 weight 大于等于 JUMP_BOUNCE_BASE_WEIGHT，则跳弹概率为 1；
            //          * 否则跳弹概率为 (weight - PENETRATION_BASE_WEIGHT) 除以 (JUMP_BOUNCE_BASE_WEIGHT - PENETRATION_BASE_WEIGHT)
            //
            //    - 如果归一化后的随机数小于等于跳弹概率，则判定为“跳弹”，否则为“过穿”
            if (((r - dodgeProb) / (1 - dodgeProb)) <= (((r = weight - PENETRATION_BASE_WEIGHT) < 0)
                                                    ? 0
                                                    : (weight >= JUMP_BOUNCE_BASE_WEIGHT ? 1 : r / (JUMP_BOUNCE_BASE_WEIGHT - PENETRATION_BASE_WEIGHT)))) {
                // _root.发布消息("跳弹");
                return DodgeStatus.JUMP_BOUNCE;
            } else {
                // _root.发布消息("过穿");
                return DodgeStatus.PENETRATION;
            }
        }
    }




    /**
     * 具体的躲闪状态计算逻辑（对应 _root.躲闪状态计算）
     * @param targetMC   命中对象 (MovieClip)
     * @param dodgeResult  是否躲闪成功 (true/false)
     * @param bulletMC   子弹 (MovieClip)
     * @return 对应的躲闪状态字符串
     */
    public static function calculateDodgeState(targetMC:MovieClip, dodgeResult:Boolean, bulletMC:MovieClip):String
    {
        var calcDamage:Number = targetMC.损伤值 + bulletMC.additionalEffectDamage;
        calcDamage = (isNaN(calcDamage) ? 0 : calcDamage);

        // 懒闪避相关逻辑
        if (targetMC.懒闪避 > 0)
        {
            if (lazyMiss(targetMC, calcDamage, targetMC.懒闪避))
            {
                return DodgeStatus.INSTANT_FEEL;
            }
        }

        // _root.发布消息(targetMC + " " + dodgeResult + " " + bulletMC)

        if (dodgeResult)
        {
            // validateAndFixTargetStats(targetMC);
            return checkDodgeState(targetMC.重量, targetMC.等级);
        }
        else if (targetMC.受击反制)
        {
            return DodgeStatus.BLOCK;
        }
        return DodgeStatus.NOT_DODGE;
    }

    /**
     * 校验并修正命中对象的等级和重量
     * @param targetMC 命中对象
     */
    private static function validateAndFixTargetStats(targetMC:MovieClip):Void
    {
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
        if (dodgeRate < DODGE_RATE_LIMIT || isNaN(dodgeRate))
        {
            return 0;
        }

        // 公式计算
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

        /*
        // 2. 若结果为 NaN，则进行异常值修正
        if (isNaN(dodgeRate))
        {
            fixShooterAndTargetStats(shooter, target);
            dodgeRate = calcDodgeRateByLevel(shooter.等级, target.等级, target.躲闪率, shooter.命中率);
        }
        */

        // 3. 最终通过 RandomNumberEngine.successRate(dodgeRate) 来判断是否成功闪避
        return (dodgeRate > DODGE_RATE_LIMIT) && RandomNumberEngine.successRate(dodgeRate);
    }

    /**
     * 修正发射者和目标的异常统计数据
     * @param shooter 发射者对象
     * @param target 目标对象
     */
    private static function fixShooterAndTargetStats(shooter:Object, target:Object):Void
    {
        shooter.等级   = (isNaN(shooter.等级)   ? 1              : shooter.等级);
        shooter.命中率 = (isNaN(shooter.命中率) ? BASE_HIT_RATE  : shooter.命中率);
        target.等级   = (isNaN(target.等级)     ? 1              : target.等级);
        target.躲闪率 = (isNaN(target.躲闪率)   ? 999            : target.躲闪率);

        // 日志记录
        _root.发布消息("修正后的发射者等级: " + shooter.等级 + ", 命中率: " + shooter.命中率);
        _root.发布消息("修正后的目标等级: " + target.等级 + ", 躲闪率: " + target.躲闪率);
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

        if (damage > fullHp / 2)
        {
            successRate = 100 * lazyMissValue;
        }
        else if (currentHp < fullHp / 2)
        {
            successRate = calculateLazyMissRateWhenBelowHalfHp(damage, fullHp, lazyMissValue);
        }
        else
        {
            successRate = calculateLazyMissRateWhenAboveOrEqualHalfHp(damage, fullHp, lazyMissValue);
        }

        return (successRate > 0) && RandomNumberEngine.successRate(successRate);
    }

    /**
     * 计算当前血量低于半血时的懒闪避率
     * @param damage 伤害值
     * @param fullHp 满血值
     * @param lazyMissValue 懒闪避值
     * @return 懒闪避成功率
     */
    private static function calculateLazyMissRateWhenBelowHalfHp(damage:Number, fullHp:Number, lazyMissValue:Number):Number
    {
        if (damage > fullHp / 5)
        {
            return 100 * lazyMissValue;
        }
        else if (damage < fullHp * 0.025)
        {
            return 0; // 伤害小于2.5%不闪避
        }
        else
        {
            // 计算动态闪避率
            return 100 * lazyMissValue * damage * 5 / fullHp;
        }
    }

    /**
     * 计算当前血量大于或等于半血时的懒闪避率
     * @param damage 伤害值
     * @param fullHp 满血值
     * @param lazyMissValue 懒闪避值
     * @return 懒闪避成功率
     */
    private static function calculateLazyMissRateWhenAboveOrEqualHalfHp(damage:Number, fullHp:Number, lazyMissValue:Number):Number
    {
        if (damage < fullHp * 0.05)
        {
            return 0; // 伤害小于5%不闪避
        }
        // 计算动态闪避率
        return 100 * lazyMissValue * damage * 2 / fullHp;
    }
}
