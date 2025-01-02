/**
 * DamageResistanceHandler
 * 负责与防御、伤害计算相关的逻辑，如：
 *  - 防御减伤比例
 *  - 跳弹伤害计算
 *  - 过穿伤害计算
 */
class org.flashNight.arki.component.StatHandler.DamageResistanceHandler
{
    // 防御计算相关的基础数值
    // 性能优化角度硬编码，这里仅做注释
    // public static var BASE_DEF:Number = 300;

    // 跳弹模式相关系数
    // 性能优化角度硬编码，这里仅做注释
    // public static var BOUNCE_DEF_COEFF:Number = 5;

    /**
     * 【可选保留】如果其他地方仍需调用，可保留该函数；
     * 防御减伤比（对应 _root.防御减伤比）
     * @param defense 防御力（非负）
     * @return 减伤系数
     */
    public static function defenseDamageRatio(defense:Number):Number
    {
        // 不使用任何内建函数，直接返回结果
        // 原： return 300 / (defense + 300);
        return 300 / (defense + 300);
    }

    /**
     * 跳弹伤害计算（对应 _root.跳弹伤害计算）
     * @param damage 伤害值（非负）
     * @param defense 防御力（非负）
     * @return 最终伤害
     */
    public static function bounceDamageCalculation(damage:Number, defense:Number):Number
    {
        // 原：Math.max(Math.floor(damage - defense / BOUNCE_DEF_COEFF), 1);
        // 1) 先计算 t = damage - (defense / BOUNCE_DEF_COEFF)
        // 2) 用 t - (t % 1) 实现 floor(t)
        // 3) 若结果 < 1，则返回 1；否则返回该值。

        var t:Number = damage - (defense / 5);
        t = t - (t % 1); // floor(t) 等价写法（x 为非负数前提下）

        return t < 1 ? 1 : t; // max(t, 1)
    }

    /**
     * 过穿伤害计算（对应 _root.过穿伤害计算）
     * @param damage 伤害值（非负）
     * @param defense 防御力（非负）
     * @return 最终伤害
     */
    public static function penetrationDamageCalculation(damage:Number, defense:Number):Number
    {
        // 原：Math.max(Math.floor(damage * defenseDamageRatio(defense)), 1);
        // 即 damage * (300 / (defense + 300))

        // 直接内联“300 / (defense + 300)”
        var ratio:Number = 300 / (defense + 300);

        var t:Number = damage * ratio;

        // floor(t)
        t = t - (t % 1);

        
        return t < 1 ? 1 : t; // max(t, 1)
    }
}
