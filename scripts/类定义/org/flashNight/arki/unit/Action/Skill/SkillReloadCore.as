import org.flashNight.arki.unit.Action.Shoot.WeaponAmmoRuntime;
import org.flashNight.arki.unit.Action.Shoot.ReloadManager;
// 文件路径：org/flashNight/arki/unit/Action/Skill/SkillReloadCore.as
 
import org.flashNight.arki.item.*;
import org.flashNight.arki.unit.Action.Shoot.LongGunSubWeaponCore;

/**
 * @class SkillReloadCore
 * @description 技能换弹工具类
 *
 * 提供技能系统中与换弹相关的工具函数，主要用于：
 * - 单个武器的换弹逻辑
 * - 批量换弹（如翻滚时同时换弹多种武器）
 *
 * 换弹逻辑说明：
 * - 复用普通仓付费补弹路径
 * - 仅显式 opt-in 时，在普通仓满后付费补幽灵弹
 * - 保留来源、拆包余额与至多一次的长枪副武器联动
 *
 * 所有方法均为静态方法，无需实例化即可调用。
 *
 * @example 典型调用方式：
 * // 单个武器换弹
 * SkillReloadCore.reloadWeapon(unit.长枪, unit.长枪属性, unit);
 *
 * // 翻滚换弹（批量）
 * SkillReloadCore.reloadAllWeapons(unit, true);
 */
class org.flashNight.arki.unit.Action.Skill.SkillReloadCore {

    /**
     * 单个武器技能换弹；旧调用只补普通仓。
     * 普通仓补弹成功时保留长枪副武器联动，ghost 补弹不增加联动次数。
     *
     * @param weapon 武器对象（如 unit.长枪、unit.手枪）
     * @param weaponAttr 武器属性对象，需包含 clipname 字段
     * @param unit 单位对象
     * @param allowPaidGhost 可选，默认 false；仅 true 允许普通仓满后付费补幽灵弹
     */
    public static function reloadWeapon(weapon:Object, weaponAttr:Object, unit:Object, allowPaidGhost:Boolean):Void {
        if (reloadWeaponAmmo(weapon, weaponAttr, unit, allowPaidGhost) && weapon === unit.长枪) {
            LongGunSubWeaponCore.reloadLinked(unit);
        }
    }

    /** 返回本次普通仓是否成功补弹，供批量入口避免重复联动副武器。 */
    private static function reloadWeaponAmmo(weapon:Object, weaponAttr:Object, unit:Object, allowPaidGhost:Boolean):Boolean {
        var slot:String = weapon === unit.长枪 ? "长枪" : (weapon === unit.手枪 ? "手枪" : "手枪2");
        var state:Object = WeaponAmmoRuntime.ensure(unit, slot);
        if (state) {
            var reloaded:Boolean = false;
            if (WeaponAmmoRuntime.normal(weapon.value, state.capacity) < state.capacity) {
                reloaded = WeaponAmmoRuntime.fillMagazine(unit, slot, weaponAttr.clipname, true);
            }
            // 满普通仓也能缺 ghost；不得用 shot > 0 或普通仓已满提前排除此入口。
            if (allowPaidGhost === true) ReloadManager.fillPaidGhostAfterSkill(unit, slot);
            return reloaded;
        }
        // 未使用 typed ammo 的旧武器保留原弹匣提交语义。
        if (weapon.value.shot > 0 && ItemUtil.singleSubmit(weaponAttr.clipname, 1, {
                source:"reload", reason:"skill_reload", mergeScope:"operation"
            })) {
            weapon.value.shot = 0;
            return true;
        }
        return false;
    }

    /**
     * 批量换弹函数（全量换弹）
     *
     * 为单位的所有武器（长枪、手枪、手枪2）进行换弹。
     * 该函数会根据单位是否为玩家控制采取不同策略：
     * - 非玩家控制：直接重置已发射数（不消耗道具）
     * - 玩家控制：调用 reloadWeapon 正常消耗弹夹道具
     *
     * 使用场景：
     * - 翻滚技能换弹
     * - 其他需要批量换弹的技能或行为
     *
     * 执行流程：
     * 1. 检查单位是否为当前控制目标
     * 2. 如果不是，直接重置三种武器的已发射数（AI/NPC逻辑）
     * 3. 如果是，调用 reloadWeapon 为每种武器单独换弹，并补做长枪副武器换弹检查（玩家逻辑）
     *
     * @param unit 单位对象（需要包含 长枪、手枪、手枪2 及其属性对象）
     * @param allowPaidGhost 可选，默认 false；仅翻滚入口显式启用付费幽灵补弹
     * @return void
     *
     * @example 典型使用场景
     * // 翻滚换弹
     * SkillReloadCore.reloadAllWeapons(_parent, true);
     *
     * // 其他需要批量换弹的场景
     * SkillReloadCore.reloadAllWeapons(unit);
     */
    public static function reloadAllWeapons(unit:Object, allowPaidGhost:Boolean):Void {
        // 检查是否为玩家控制目标
        if (_root.控制目标 != unit._name) {
            // 非玩家控制，直接重置（不消耗道具）
            WeaponAmmoRuntime.supplyValue(unit.长枪.value, false);
            LongGunSubWeaponCore.reloadLinkedFree(unit);
            WeaponAmmoRuntime.supplyValue(unit.手枪.value, false);
            WeaponAmmoRuntime.supplyValue(unit.手枪2.value, false);
            return;
        }

        // 普通仓成功时保持原有联动时机；满仓或失败时保留批量入口的兜底，均只调用一次。
        var longGunReloaded:Boolean = reloadWeaponAmmo(unit.长枪, unit.长枪属性, unit, allowPaidGhost);
        if (longGunReloaded) LongGunSubWeaponCore.reloadLinked(unit);
        reloadWeapon(unit.手枪, unit.手枪属性, unit, allowPaidGhost);
        reloadWeapon(unit.手枪2, unit.手枪2属性, unit, allowPaidGhost);
        if (!longGunReloaded) LongGunSubWeaponCore.reloadLinked(unit);
    }
}
