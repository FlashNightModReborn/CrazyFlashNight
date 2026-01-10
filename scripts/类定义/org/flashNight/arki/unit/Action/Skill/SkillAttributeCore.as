// 文件路径：org/flashNight/arki/unit/Action/Skill/SkillAttributeCore.as

/**
 * @class SkillAttributeCore
 * @description 技能属性传递工具类
 *
 * 提供技能系统中与属性传递相关的工具函数，主要用于：
 * - 将单位装备的兵器特殊属性传递给技能发射的子弹（兵器模式）
 * - 将单位的空手战斗属性传递给技能发射的子弹（空手模式）
 *
 * 支持传递的属性包括：
 * - 伤害类型（物理/魔法等）
 * - 魔法伤害属性（火/冰/雷等元素）
 * - 毒、吸血、击溃、暴击、斩杀等特殊效果
 *
 * 所有方法均为静态方法，无需实例化即可调用。
 *
 * @example 典型调用方式（兵器模式）：
 * var bulletParams:Object = new Object();
 * bulletParams.子弹威力 = 1000;
 * SkillAttributeCore.transferWeaponAttributes(unit, bulletParams);
 * // 此时 bulletParams 已包含单位的兵器特殊属性
 *
 * @example 典型调用方式（空手模式）：
 * var bulletParams:Object = new Object();
 * bulletParams.子弹威力 = 500;
 * SkillAttributeCore.transferUnarmedAttributes(unit, bulletParams);
 * // 此时 bulletParams 已包含单位的空手战斗属性
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
     *     _parent.刀口位置生成子弹(_parent, 子弹参数);
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

    /**
     * 传递空手模式属性到子弹工具函数
     *
     * 将单位的空手战斗相关属性复制到子弹对象中，用于空手技能的伤害计算。
     * 该函数只传递已定义的属性，未定义的属性不会覆盖子弹的默认值。
     *
     * 传递的属性列表：
     * - 空手伤害类型 → 伤害类型（如"物理"、"魔法"）
     * - 空手魔法伤害属性 → 魔法伤害属性（如"火"、"冰"、"雷"、"冲"）
     * - 空手毒 → 毒（毒伤害数值，如毒手套效果）
     * - 空手吸血 → 吸血（吸血比例）
     * - 空手击溃 → 血量上限击溃（百分比击溃值）
     * - 空手暴击 → 暴击（暴击函数或暴击率）
     * - 空手斩杀 → 斩杀（斩杀函数或斩杀阈值）
     *
     * 注意：空手模式下的属性通常来源于：
     * - 拳套/手套类装备
     * - 内力修炼加成
     * - 被动技能效果
     *
     * @param unit 单位对象（需要包含 空手XXX 系列属性）
     * @param bullet 子弹对象或子弹参数对象（属性将被写入此对象）
     * @return void
     *
     * @example 在刀剑乱舞等混合技能中使用
     * _root.技能函数.刀剑乱舞判定 = function() {
     *     // 攻击点子弹：空手模式
     *     var 空手子弹 = _root.子弹属性初始化(this.攻击点);
     *     空手子弹.子弹威力 = _parent.空手攻击力 * 2;
     *     SkillAttributeCore.transferUnarmedAttributes(_parent, 空手子弹);
     *     _root.子弹区域shoot传递(空手子弹);
     *
     *     // 刀子弹：兵器模式
     *     var 刀子弹 = _root.子弹属性初始化(this.刀);
     *     刀子弹.子弹威力 = _parent.刀属性.power * 2;
     *     SkillAttributeCore.transferWeaponAttributes(_parent, 刀子弹);
     *     _root.子弹区域shoot传递(刀子弹);
     * }
     */
    public static function transferUnarmedAttributes(unit:MovieClip, bullet:Object):Void {
        // 传递伤害类型（如"物理"、"魔法"等）
        if (unit.空手伤害类型) {
            bullet.伤害类型 = unit.空手伤害类型;
            // _root.发布消息("传递空手伤害类型: " + unit.空手伤害类型);
        }

        // 传递魔法伤害属性（如"火"、"冰"、"雷"等）
        if (unit.空手魔法伤害属性) {
            bullet.魔法伤害属性 = unit.空手魔法伤害属性;
            // _root.发布消息("传递空手魔法伤害属性: " + unit.空手魔法伤害属性);
        }

        // 传递毒属性（如毒手套效果）
        if (unit.空手毒) {
            bullet.毒 = unit.空手毒;
        }

        // 传递吸血属性
        if (unit.空手吸血) {
            bullet.吸血 = unit.空手吸血;
        }

        // 传递击溃属性（血量上限击溃）
        if (unit.空手击溃) {
            bullet.血量上限击溃 = unit.空手击溃;
        }

        // 传递暴击属性
        if (unit.空手暴击) {
            bullet.暴击 = unit.空手暴击;
        }

        // 传递斩杀属性
        if (unit.空手斩杀) {
            bullet.斩杀 = unit.空手斩杀;
        }
    }
}
