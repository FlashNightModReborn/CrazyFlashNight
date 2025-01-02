/**
 * DodgeHandler
 * 负责与闪避、命中计算相关的逻辑，如：
 *  - sigmoid、relu 等数学函数
 *  - 躲闪状态校验
 *  - 根据等级计算闪避率
 *  - 根据命中率计算是否闪避成功
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

    // ------------------------------------------------------------
    // 下面是移植原脚本中的函数
    // ------------------------------------------------------------

    /**
     * 是否是119（原 _root.is119）
     * @param x 传入数值
     * @return Boolean
     */
    public static function is119(x:Number):Boolean
    {
        // 注意：这里仍然依赖 _root.闪客之夜
        // 若要彻底去除 _root 依赖，需要单独传入或在外部管理
        return (x == _root.闪客之夜);
    }

    /**
     * sigmoid函数（原 _root.sigmoid）
     * @param x 输入数值
     * @return sigmoid(x)
     */
    public static function sigmoid(x:Number):Number
    {
        var expX:Number = Math.exp(x);
        return expX / (1 + expX);
    }

    /**
     * ReLU函数（原 _root.relu）
     * @param x 输入数值
     * @return relu(x)
     */
    public static function relu(x:Number):Number
    {
        return Math.max(0, x);
    }

    /**
     * softplus函数（原 _root.softplus）
     * @param x 输入数值
     * @return softplus(x)
     */
    public static function softplus(x:Number):Number
    {
        return Math.log(1 + Math.exp(x));
    }

    /**
     * sig_tyler函数（原 _root.sig_tyler）
     * @param x 输入数值
     * @return 计算结果
     */
    public static function sig_tyler(x:Number):Number
    {
        // 原脚本: 3 * x / 40 + 0.5 - x * x * x / 4000
        return 3 * x / 40 + 0.5 - (x * x * x) / 4000;
    }

    /**
     * 根据重量判断躲闪类型（跳弹/过穿/躲闪），对应 _root.躲闪状态校验
     * @param weight  重量
     * @param level   等级
     * @return "躲闪" / "跳弹" / "过穿"
     */
    public static function checkDodgeState(weight:Number, level:Number):String
    {
        // 对应原脚本:
        // if (_root.成功率((等级 - 重量))) return "躲闪";
        // else if (_root.成功率(100 * (重量 - 过穿基准重量) / (跳弹基准重量 - 过穿基准重量))) return "跳弹";
        // else return "过穿";
        if (_root.成功率(level - weight))
        {
            return "躲闪";
        }
        else if (_root.成功率(100 * (weight - PENETRATION_BASE_WEIGHT) 
                    / (JUMP_BOUNCE_BASE_WEIGHT - PENETRATION_BASE_WEIGHT)))
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
            if (_root.lazyMiss(targetMC, calcDamage, targetMC.懒闪避))
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
        var finalRate:Number = sigmoid(dodgeIndex) * DODGE_SYSTEM_MAX;
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

        // 3. 最终通过 _root.成功率(dodgeRate) 来判断是否成功闪避
        return _root.成功率(dodgeRate);
    }
}
