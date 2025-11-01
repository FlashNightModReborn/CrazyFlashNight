// 文件路径：org/flashNight/arki/unit/Action/Skill/SkillDamageCore.as
 
/**
 * @class SkillDamageCore
 * @description 技能伤害计算工具类
 *
 * 提供技能系统中与伤害计算相关的工具函数，包括：
 * - 速度转伤害计算（用于刀剑技能）
 * - 从XML配置读取技能乘数
 *
 * 所有方法均为静态方法，无需实例化即可调用。
 *
 * @example 典型调用方式：
 * // 速度转伤害
 * var bonus:Number = SkillDamageCore.speedToDamage(unit.行走X速度);
 *
 * // 获取技能乘数
 * var multiplier:Number = SkillDamageCore.getSkillMultiplier(unit, "凶斩");
 */
class org.flashNight.arki.unit.Action.Skill.SkillDamageCore {

    /**
     * 速度转伤害函数
     *
     * 用于给部分刀剑技能增加基于移动速度的额外伤害加成。
     * 计算公式：(显示速度 - 8) * 6
     * 其中显示速度 = floor(原始速度 * 20) / 10 (单位: m/s)
     *
     * @param walkSpeedX 单位的原始X轴移动速度值
     * @return 伤害加成数值（可能为负数）
     *
     * @example
     * var unit:MovieClip = _parent;
     * if (unit.行走X速度) {
     *     var speedBonus:Number = SkillDamageCore.speedToDamage(unit.行走X速度);
     *     bulletDamage += speedBonus;
     * }
     */
    public static function speedToDamage(walkSpeedX:Number):Number {
        // 计算显示速度值（m/s）
        var displaySpeed:Number = Math.floor(walkSpeedX * 20) / 10;

        // 按公式计算伤害加成：(速度-8)*6
        var damage:Number = (displaySpeed - 8) * 6;

        // 调试信息（已注释，按需启用）
        // _root.发布消息("速度转伤害加成：" + damage + " (速度:" + displaySpeed + "m/s)");

        return damage;
    }

    /**
     * 获取技能乘数工具函数（从XML配置读取）
     *
     * 从单位装备的武器XML配置中读取特定技能的伤害乘数。
     * 配置路径：武器.刀属性.skillmultipliers[技能名称]
     *
     * 特性：
     * - 进行三重空值检查，确保安全访问
     * - 验证数值有效性（非NaN且大于1）
     * - 配置无效时返回默认值1（无加成）
     *
     * @param unit 单位对象（需要包含 刀属性.skillmultipliers 配置）
     * @param skillName 技能名称字符串，如"凶斩"、"瞬步斩"、"龙斩"、"拔刀术"等
     * @return 技能乘数（默认为1，表示无加成；大于1表示有伤害加成）
     *
     * @example XML配置示例（data/items/武器_刀.xml）
     * <weapon>
     *     <skillmultipliers>
     *         <凶斩>1.5</凶斩>
     *         <瞬步斩>1.3</瞬步斩>
     *     </skillmultipliers>
     * </weapon>
     *
     * @example 使用示例
     * var unit:MovieClip = _parent;
     * var multiplier:Number = SkillDamageCore.getSkillMultiplier(unit, "凶斩");
     * var finalDamage:Number = baseDamage * multiplier;
     */
    public static function getSkillMultiplier(unit:MovieClip, skillName:String):Number {
        // 默认乘数为1（无加成）
        var defaultMultiplier:Number = 1;

        // 三重空值检查：刀属性 -> skillmultipliers -> 具体技能
        if (unit.刀属性 &&
            unit.刀属性.skillmultipliers &&
            unit.刀属性.skillmultipliers[skillName]) {

            // 显式类型转换为数字
            var multiplier:Number = Number(unit.刀属性.skillmultipliers[skillName]);

            // 验证数值有效性：非NaN且大于1才使用
            if (!isNaN(multiplier) && multiplier > 1) {
                return multiplier;
            }
        }

        // 如果没有配置或配置无效，返回默认值
        return defaultMultiplier;
    }
}
