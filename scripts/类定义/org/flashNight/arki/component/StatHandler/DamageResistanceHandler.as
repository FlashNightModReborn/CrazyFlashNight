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
     * 防御减伤比（对应 _root.防御减伤比）
     * @param defense 防御力（非负）
     * @return 减伤系数
     */
    public static function defenseDamageRatio(defense:Number):Number
    {
        // 不使用内建函数，直接返回结果
        // 原： return 300 / (defense + 300);
        return 300 / (defense + 300);
    }

    /**
     * 跳弹伤害计算（对应 _root.跳弹伤害计算）
     * @param damage 伤害值（非负整数）
     * @param defense 防御力（非负整数）
     * @return 最终伤害
     */
    public static function bounceDamageCalculation(damage:Number, defense:Number):Number
    {
        // 1) 计算 t = floor(damage - defense / 5)
        //    这里用 (x | 0) 代替 Math.floor(x)（对非负数等效）
        // 2) 返回 max(t, 1)
        var t:Number = (damage - (defense / 5)) | 0;
        return (t < 1) ? 1 : t;
    }

    /**
     * 过穿伤害计算（对应 _root.过穿伤害计算）
     * @param damage 伤害值（非负整数）
     * @param defense 防御力（非负整数）
     * @return 最终伤害
     */
    public static function penetrationDamageCalculation(damage:Number, defense:Number):Number
    {
        // 原公式：Math.max(Math.floor(damage * (300 / (defense + 300))), 1)
        // 先计算 damage * (300 / (defense + 300))，再 floor，最后与 1 取最大
        // 用位运算直接取整，并保留 max(t, 1) 判断
        var t:Number = (damage * 300 / (defense + 300)) >> 0;
        return (t < 1) ? 1 : t;
    }
}
