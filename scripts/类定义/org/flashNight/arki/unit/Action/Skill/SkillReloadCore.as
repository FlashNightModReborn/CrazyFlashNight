// 文件路径：org/flashNight/arki/unit/Action/Skill/SkillReloadCore.as
 
import org.flashNight.arki.item.*;

/**
 * @class SkillReloadCore
 * @description 技能换弹工具类
 *
 * 提供技能系统中与换弹相关的工具函数，主要用于：
 * - 单个武器的换弹逻辑
 * - 批量换弹（如翻滚时同时换弹多种武器）
 *
 * 换弹逻辑说明：
 * - 检查武器是否有已发射弹药（shot > 0）
 * - 尝试提交（消耗）一个弹夹道具
 * - 提交成功后重置武器的已发射数为0
 *
 * 所有方法均为静态方法，无需实例化即可调用。
 *
 * @example 典型调用方式：
 * // 单个武器换弹
 * SkillReloadCore.reloadWeapon(unit.长枪, unit.长枪属性, unit);
 *
 * // 翻滚换弹（批量）
 * SkillReloadCore.rollReload(unit);
 */
class org.flashNight.arki.unit.Action.Skill.SkillReloadCore {

    /**
     * 单个武器换弹工具函数
     *
     * 检查指定武器是否有已发射弹药，如果有则尝试提交弹夹道具并重置发射数。
     * 该函数是换弹逻辑的原子操作，可被其他批量换弹函数复用。
     *
     * 执行流程：
     * 1. 检查 weapon.value.shot 是否大于0（是否有已发射弹药）
     * 2. 从武器属性中获取弹夹道具名称（weaponAttr.clipname）
     * 3. 调用 ItemUtil.singleSubmit 尝试提交1个弹夹道具
     * 4. 提交成功后重置 weapon.value.shot 和 unit.当前弹夹副武器已发射数 为0
     *
     * @param weapon 武器对象（如 unit.长枪、unit.手枪）
     * @param weaponAttr 武器属性对象（如 unit.长枪属性、unit.手枪属性），需包含 clipname 字段
     * @param unit 单位对象（用于重置 当前弹夹副武器已发射数）
     * @return void
     *
     * @example 在技能中使用
     * // 为长枪换弹
     * SkillReloadCore.reloadWeapon(_parent.长枪, _parent.长枪属性, _parent);
     */
    public static function reloadWeapon(weapon:Object, weaponAttr:Object, unit:MovieClip):Void {
        // 检查是否有已发射弹药
        if (weapon.value.shot > 0) {
            // 获取弹夹道具名称
            var clipName:String = weaponAttr.clipname;

            // 尝试提交（消耗）1个弹夹道具
            if (ItemUtil.singleSubmit(clipName, 1)) {
                // 提交成功，重置已发射数
                weapon.value.shot = 0;
                unit.当前弹夹副武器已发射数 = 0;
            }
        }
    }

    /**
     * 翻滚换弹函数（批量换弹）
     *
     * 在翻滚技能释放时，自动为长枪、手枪、手枪2三种武器进行换弹。
     * 该函数会根据单位是否为玩家控制采取不同策略：
     * - 非玩家控制：直接重置已发射数（不消耗道具）
     * - 玩家控制：调用 reloadWeapon 正常消耗弹夹道具
     *
     * 执行流程：
     * 1. 检查单位是否为当前控制目标
     * 2. 如果不是，直接重置三种武器的已发射数（AI/NPC逻辑）
     * 3. 如果是，调用 reloadWeapon 为每种武器单独换弹（玩家逻辑）
     *
     * @param unit 单位对象（需要包含 长枪、手枪、手枪2 及其属性对象）
     * @return void
     *
     * @example 在翻滚技能中使用
     * _root.技能函数.翻滚换弹 = function() {
     *     SkillReloadCore.rollReload(_parent);
     * }
     */
    public static function rollReload(unit:MovieClip):Void {
        // 检查是否为玩家控制目标
        if (_root.控制目标 != unit._name) {
            // 非玩家控制，直接重置（不消耗道具）
            unit.长枪.value.shot = 0;
            unit.当前弹夹副武器已发射数 = 0;
            unit.手枪.value.shot = 0;
            unit.手枪2.value.shot = 0;
            return;
        }

        // 玩家控制，使用工具函数处理三种武器的换弹（消耗道具）
        reloadWeapon(unit.长枪, unit.长枪属性, unit);
        reloadWeapon(unit.手枪, unit.手枪属性, unit);
        reloadWeapon(unit.手枪2, unit.手枪2属性, unit);
    }
}
