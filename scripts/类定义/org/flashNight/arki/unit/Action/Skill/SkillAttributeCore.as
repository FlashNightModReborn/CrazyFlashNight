// 文件路径：org/flashNight/arki/unit/Action/Skill/SkillAttributeCore.as

/** 
 * @class SkillAttributeCore
 * @description 技能属性传递工具类
 *
 * 提供技能系统中与属性传递相关的工具函数，主要用于：
 * - 将单位装备的兵器特殊属性传递给技能发射的子弹
 *
 * 支持传递的属性包括：
 * - 伤害类型（物理/魔法等）
 * - 魔法伤害属性（火/冰/雷等元素）
 * - 毒、吸血、击溃、暴击、斩杀等特殊效果
 *
 * 所有方法均为静态方法，无需实例化即可调用。
 *
 * @example 典型调用方式：
 * var bulletParams:Object = new Object();
 * bulletParams.子弹威力 = 1000;
 * SkillAttributeCore.transferWeaponAttributes(unit, bulletParams);
 * // 此时 bulletParams 已包含单位的兵器特殊属性
 */
class org.flashNight.arki.unit.Action.Skill.SkillAttributeCore {

    /**
     * 传递兵器属性到子弹工具函数
     *
     * 将单位装备的兵器特殊属性复制到子弹对象中，使技能伤害继承武器的特殊效果。
     * 该函数只传递已定义的属性，未定义的属性不会覆盖子弹的默认值。
     *
     * 传递的属性列表：
     * - 兵器伤害类型 → 伤害类型（如"物理"、"魔法"）
     * - 兵器魔法伤害属性 → 魔法伤害属性（如"火"、"冰"、"雷"、"冲"）
     * - 兵器毒 → 毒（毒伤害数值）
     * - 兵器吸血 → 吸血（吸血比例）
     * - 兵器击溃 → 血量上限击溃（百分比击溃值）
     * - 兵器暴击 → 暴击（暴击函数或暴击率）
     * - 兵器斩杀 → 斩杀（斩杀函数或斩杀阈值）
     *
     * @param unit 单位对象（需要包含 兵器XXX 系列属性）
     * @param bullet 子弹对象或子弹参数对象（属性将被写入此对象）
     * @return void
     *
     * @example 在技能攻击函数中使用
     * _root.技能函数.凶斩攻击 = function(不硬直) {
     *     var 子弹参数 = new Object();
     *     子弹参数.子弹威力 = 1000;
     *     子弹参数.Z轴攻击范围 = 30;
     *
     *     // 传递兵器特殊属性到子弹
     *     SkillAttributeCore.transferWeaponAttributes(_parent, 子弹参数);
     *
     *     _parent.刀口位置生成子弹(子弹参数);
     * }
     */
    public static function transferWeaponAttributes(unit:MovieClip, bullet:Object):Void {
        // 传递伤害类型（如"物理"、"魔法"等）
        if (unit.兵器伤害类型) {
            bullet.伤害类型 = unit.兵器伤害类型;
        }

        // 传递魔法伤害属性（如"火"、"冰"、"雷"等）
        if (unit.兵器魔法伤害属性) {
            bullet.魔法伤害属性 = unit.兵器魔法伤害属性;
        }

        // 传递毒属性
        if (unit.兵器毒) {
            bullet.毒 = unit.兵器毒;
        }

        // 传递吸血属性
        if (unit.兵器吸血) {
            bullet.吸血 = unit.兵器吸血;
        }

        // 传递击溃属性（血量上限击溃）
        if (unit.兵器击溃) {
            bullet.血量上限击溃 = unit.兵器击溃;
        }

        // 传递暴击属性
        if (unit.兵器暴击) {
            bullet.暴击 = unit.兵器暴击;
        }

        // 传递斩杀属性
        if (unit.兵器斩杀) {
            bullet.斩杀 = unit.兵器斩杀;
        }
    }
}
