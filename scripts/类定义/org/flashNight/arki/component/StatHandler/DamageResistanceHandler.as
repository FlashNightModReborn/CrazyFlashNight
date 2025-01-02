/**
 * DamageResistanceHandler
 * 负责与防御、伤害计算相关的逻辑，如：
 *  - 防御减伤比例
 *  - 跳弹伤害计算
 *  - 过穿伤害计算
 */
class org.flashNight.arki.component.DamageResistanceHandler
{
    // 这里可根据需要进行重命名或增加更多常量
    public static var BASE_DEF:Number = 300;  // 与防御计算相关的基础数值

    // 跳弹模式相关系数（原 _root.跳弹防御系数 = 5）
    public static var BOUNCE_DEF_COEFF:Number = 5;

    /**
     * 防御减伤比（对应 _root.防御减伤比）
     * @param defenseNumber 防御力
     * @return 减伤系数
     */
    public static function defenseDamageRatio(defenseNumber:Number):Number
    {
        // 原脚本：return 300 / (防御力 + 300);
        return BASE_DEF / (defenseNumber + BASE_DEF);
    }

    /**
     * 跳弹伤害计算（对应 _root.跳弹伤害计算）
     * @param damage 伤害值
     * @param defenseNumber 防御力
     * @return 最终伤害
     */
    public static function bounceDamageCalculation(damage:Number, defenseNumber:Number):Number
    {
        // 原脚本：Math.max(Math.floor(伤害 - 防御力 / _root.跳弹防御系数), 1);
        return Math.max(Math.floor(damage - defenseNumber / BOUNCE_DEF_COEFF), 1);
    }

    /**
     * 过穿伤害计算（对应 _root.过穿伤害计算）
     * @param damage 伤害值
     * @param defenseNumber 防御力
     * @return 最终伤害
     */
    public static function penetrationDamageCalculation(damage:Number, defenseNumber:Number):Number
    {
        // 原脚本：Math.max(Math.floor(伤害 * _root.防御减伤比(防御力)), 1);
        // 即：伤害 * defenseDamageRatio(防御力)
        var finalDamage:Number = damage * defenseDamageRatio(defenseNumber);
        return Math.max(Math.floor(finalDamage), 1);
    }
}
