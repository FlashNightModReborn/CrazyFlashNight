// 文件路径：org/flashNight/arki/unit/Action/Skill/SkillReleaseGuard.as

/**
 * @class SkillReleaseGuard
 * @description 快捷技能从 UI 槽位进入角色状态机前的统一校验边界。
 *
 * 空槽在历史存档与 XFL 初始化期间可能表现为 null / undefined / 空字符串 / "空"。
 * 必须先检查原始值再转 String，避免 null 被提升为可通过 truthy 判断的 "null"。
 */
class org.flashNight.arki.unit.Action.Skill.SkillReleaseGuard {

    /**
     * 规范化技能名。返回 null 表示空槽或历史哨兵值。
     */
    public static function normalizeSkillName(rawSkillName):String {
        if (rawSkillName == null) return null;

        var skillName:String = String(rawSkillName);
        if (skillName == "" || skillName == "空"
            || skillName == "null" || skillName == "undefined") {
            return null;
        }
        return skillName;
    }

    /**
     * 解析一次合法释放请求。只有技能已学习、技能数据存在且 MP 消耗有效时才返回结果。
     */
    public static function resolve(root:Object, rawSkillName, rawMpCost):Object {
        if (!root) return null;

        var skillName:String = normalizeSkillName(rawSkillName);
        if (skillName == null) return null;
        if (typeof root.根据技能名查找主角技能等级 != "function"
            || typeof root.根据技能名查找全部属性 != "function") {
            return null;
        }

        var skillLevel:Number = Number(root.根据技能名查找主角技能等级(skillName));
        if (isNaN(skillLevel) || skillLevel <= 0) return null;

        var skillData:Object = root.根据技能名查找全部属性(skillName);
        if (!skillData) return null;

        var mpCost:Number = Number(rawMpCost);
        if (isNaN(mpCost) || mpCost < 0) return null;

        // 保留旧行为：异常超上限等级按 1 级执行，但不存在/未学习技能不再伪装成 1 级。
        if (skillLevel > 10) skillLevel = 1;

        return {
            skillName: skillName,
            skillLevel: skillLevel,
            skillData: skillData,
            mpCost: mpCost
        };
    }

    /**
     * 输入层槽位结构校验。是否装备必须由 XFL 技能表匹配流程明确置为 1。
     */
    public static function isEquippedSlot(skillSlot:Object):Boolean {
        if (!skillSlot || skillSlot.是否装备 != 1) return false;
        if (normalizeSkillName(skillSlot.已装备名) == null) return false;

        var mpCost:Number = Number(skillSlot.消耗mp);
        var cooldownTime:Number = Number(skillSlot.冷却时间);
        return !isNaN(mpCost) && mpCost >= 0
            && !isNaN(cooldownTime) && cooldownTime >= 0;
    }
}
