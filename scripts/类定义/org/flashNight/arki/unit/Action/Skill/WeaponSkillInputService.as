// 文件路径：org/flashNight/arki/unit/Action/Skill/WeaponSkillInputService.as

/**
 * @class WeaponSkillInputService
 * @description 武器技能键输入语义服务
 *
 * UI 只负责把 F 键按下事件交给本服务；本服务决定当前主动战技是否允许触发、
 * 触发成功后是否应该启动共享的战技冷却条。副武器快装不是普通主动战技，
 * 因此可绕过共享战技冷却，并且成功后不启动共享冷却。
 */
class org.flashNight.arki.unit.Action.Skill.WeaponSkillInputService {

    public static function installRootBridge(root:Object):Void {
        if (!root) return;

        var bridge:Object = {};
        bridge.canTrigger = function(controller:Object):Boolean {
            return WeaponSkillInputService.canTrigger(controller);
        };
        bridge.release = function(controller:Object):Object {
            return WeaponSkillInputService.release(controller);
        };
        bridge.canTriggerUnit = function(unit:Object, sharedCooldownReady:Boolean):Boolean {
            return WeaponSkillInputService.canTriggerUnit(unit, sharedCooldownReady);
        };
        bridge.releaseUnit = function(unit:Object):Object {
            return WeaponSkillInputService.releaseUnit(unit);
        };
        bridge.isCurrentSubweaponControl = function(unit:Object):Boolean {
            return WeaponSkillInputService.isCurrentSubweaponControl(unit);
        };

        root.武器技能输入控制器 = bridge;
    }

    public static function canTrigger(controller:Object):Boolean {
        if (_root.暂停 || _root.当前玩家总数 !== 1) {
            return false;
        }

        return canTriggerUnit(getControlUnit(), isSharedCooldownReady(controller));
    }

    public static function canTriggerUnit(unit:Object, sharedCooldownReady:Boolean):Boolean {
        var skill:Object = getCurrentSkill(unit);
        if (!skill) {
            return false;
        }
        if (isSubweaponControlSkill(skill)) {
            return true;
        }
        return sharedCooldownReady;
    }

    public static function release(controller:Object):Object {
        var result:Object = releaseUnit(getControlUnit());
        if (result.startSharedCooldown) {
            result.cooldownTime = getCooldownTime(controller, result.skill);
        }
        return result;
    }

    public static function releaseUnit(unit:Object):Object {
        var skill:Object = getCurrentSkill(unit);
        var isSubweapon:Boolean = isSubweaponControlSkill(skill);
        var result:Object = {
            released: false,
            refreshMp: false,
            startSharedCooldown: false,
            cooldownTime: 0,
            isSubweaponControl: isSubweapon,
            skill: skill
        };

        if (!unit || !skill || !unit.释放主动战技) {
            return result;
        }

        var released:Boolean = unit.释放主动战技();
        if (!released) {
            return result;
        }

        result.released = true;
        result.refreshMp = true;
        result.startSharedCooldown = !isSubweapon;
        if (!isSubweapon && skill.冷却时间 > 0) {
            result.cooldownTime = skill.冷却时间;
        }
        return result;
    }

    public static function isCurrentSubweaponControl(unit:Object):Boolean {
        return isSubweaponControlSkill(getCurrentSkill(unit));
    }

    private static function getControlUnit():Object {
        if (!_root.gameworld || !_root.控制目标) {
            return null;
        }
        return _root.gameworld[_root.控制目标];
    }

    private static function getCurrentSkill(unit:Object):Object {
        if (!unit || !unit.主动战技) {
            return null;
        }

        var mode:String = unit.攻击模式;
        if (!mode) {
            mode = _root.攻击模式;
        }
        if (!mode) {
            return null;
        }
        return unit.主动战技[mode];
    }

    private static function isSubweaponControlSkill(skill:Object):Boolean {
        return skill && skill.isSubweaponControl === true;
    }

    private static function getControllerHolder(controller:Object):Object {
        if (!controller) {
            return null;
        }
        return controller._parent;
    }

    private static function isSharedCooldownReady(controller:Object):Boolean {
        var holder:Object = getControllerHolder(controller);
        if (!holder) {
            return false;
        }
        var cooldownBar:Object = holder[controller.控制参数2];
        return cooldownBar && cooldownBar.冷却;
    }

    private static function getCooldownTime(controller:Object, skill:Object):Number {
        var holder:Object = getControllerHolder(controller);
        if (holder) {
            var skillBar:Object = holder[controller.控制参数];
            if (skillBar && skillBar.冷却时间 > 0) {
                return Number(skillBar.冷却时间);
            }
        }
        if (skill && skill.冷却时间 > 0) {
            return Number(skill.冷却时间);
        }
        return 0;
    }
}
