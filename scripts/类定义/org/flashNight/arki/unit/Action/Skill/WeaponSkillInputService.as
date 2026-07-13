// 文件路径：org/flashNight/arki/unit/Action/Skill/WeaponSkillInputService.as

import org.flashNight.arki.unit.Action.Input.UnitActionIntentService;
import org.flashNight.arki.unit.Action.Shoot.LongGunSubWeaponCore;
import org.flashNight.arki.unit.Action.Skill.ManualCooldownService;

/**
 * @class WeaponSkillInputService
 * @description 武器技能键输入语义服务
 *
 * 帧计时器负责把 F 键当前状态交给本服务；本服务持有按住锁存、触发门控与释放编排。
 * 共享冷却状态由 ManualCooldownService 持有；旧玩家信息界面只提供时长与可选渲染器。
 * 副武器快装不是普通主动战技，因此可绕过共享战技冷却，并且成功后不启动共享冷却。
 */
class org.flashNight.arki.unit.Action.Skill.WeaponSkillInputService {

    private static var WEAPON_SKILL_PRIORITY:Number = 10;
    private static var SUBWEAPON_RELOAD_PRIORITY:Number = 20;
    // 输入通常在 n 帧提交、n+1 帧进入持枪状态机；跑姿归一化后的 man 到 n+2 才完成函数绑定。
    private static var SUBWEAPON_RELOAD_TTL_FRAMES:Number = 2;

    public static function installRootBridge(root:Object):Void {
        if (!root) return;

        var rootRef:Object = root;
        var cooldownPort:Object = {};
        cooldownPort.bindRenderer = function():Void {
            var info:Object = rootRef.玩家信息界面 ? rootRef.玩家信息界面.玩家必要信息界面 : null;
            var bar:Object = info ? info.战技进度条 : null;
            if (bar) ManualCooldownService.bindRenderer(ManualCooldownService.WEAPON_SKILL_KEY, bar);
        };
        cooldownPort.getCooldownTime = function(skill:Object):Number {
            var info:Object = rootRef.玩家信息界面 ? rootRef.玩家信息界面.玩家必要信息界面 : null;
            var slot:Object = info ? info.战技栏 : null;
            if (slot && Number(slot.冷却时间) > 0) {
                return Number(slot.冷却时间);
            }
            return skill && Number(skill.冷却时间) > 0 ? Number(skill.冷却时间) : 0;
        };

        var bridge:Object = {};
        bridge.update = function(unit:Object, keyDown:Boolean):Object {
            var inputEnabled:Boolean = !rootRef.暂停 && rootRef.当前玩家总数 === 1;
            var inputFrame:Number = rootRef.帧计时器 ? Number(rootRef.帧计时器.当前帧数) : 0;
            var result:Object = WeaponSkillInputService.updateUnit(unit, keyDown, inputEnabled, cooldownPort, inputFrame);
            if (result && result.refreshMp && rootRef.玩家信息界面 && rootRef.玩家信息界面.刷新mp显示) {
                rootRef.玩家信息界面.刷新mp显示();
            }
            return result;
        };
        bridge.canTriggerUnit = function(unit:Object, sharedCooldownReady:Boolean):Boolean {
            return WeaponSkillInputService.canTriggerUnit(unit, sharedCooldownReady);
        };
        bridge.releaseUnit = function(unit:Object):Object {
            var inputFrame:Number = rootRef.帧计时器 ? Number(rootRef.帧计时器.当前帧数) : 0;
            return WeaponSkillInputService.releaseUnit(unit, inputFrame);
        };
        bridge.isCurrentSubweaponControl = function(unit:Object):Boolean {
            return WeaponSkillInputService.isCurrentSubweaponControl(unit);
        };

        root.武器技能输入控制器 = bridge;
    }

    /**
     * 每帧输入更新。
     *
     * 当前语义不是严格按下沿：按住期间若冷却尚未结束，会在首次变为可触发时释放一次；
     * 一旦尝试释放（即使业务释放失败）便消费本次按住，直到松键后重新武装。
     */
    public static function updateUnit(unit:Object,
                                      keyDown:Boolean,
                                      inputEnabled:Boolean,
                                      cooldownPort:Object,
                                      inputFrame:Number):Object {
        if (!unit) return null;
        bindCooldownRenderer(cooldownPort);

        if (!keyDown) {
            unit.__weaponSkillInputConsumed = false;
            return null;
        }
        if (!inputEnabled || unit.__weaponSkillInputConsumed === true) {
            return null;
        }

        var sharedCooldownReady:Boolean = ManualCooldownService.isReady(ManualCooldownService.WEAPON_SKILL_KEY);
        if (!canTriggerUnit(unit, sharedCooldownReady)) {
            return null;
        }

        // 必须在 release 前锁存；失败释放同样只允许本次按住尝试一次。
        unit.__weaponSkillInputConsumed = true;
        var result:Object = releaseUnit(unit, inputFrame);
        if (result.startSharedCooldown) {
            result.cooldownTime = getCooldownTimeFromPort(cooldownPort, result.skill);
            if (result.cooldownTime > 0) {
                ManualCooldownService.start(ManualCooldownService.WEAPON_SKILL_KEY, result.cooldownTime);
            }
        }
        return result;
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

    public static function releaseUnit(unit:Object, inputFrame:Number):Object {
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

        if (!unit || !skill) {
            return result;
        }

        var frame:Number = resolveInputFrame(inputFrame);
        if (isSubweapon) {
            var queued:Boolean = requestSubweaponControl(unit, frame);
            if (!queued) return result;
            result.released = true;
            result.refreshMp = true;
            return result;
        }

        if (!unit.释放主动战技) return result;
        var submitted:Boolean = UnitActionIntentService.submit(
            unit,
            UnitActionIntentService.CHANNEL_COMBAT,
            UnitActionIntentService.KIND_WEAPON_SKILL,
            frame,
            UnitActionIntentService.DEFAULT_TTL_FRAMES,
            {skill: skill},
            WEAPON_SKILL_PRIORITY
        );
        if (!submitted) return result;

        var intent:Object = UnitActionIntentService.take(
            unit,
            UnitActionIntentService.CHANNEL_COMBAT,
            UnitActionIntentService.KIND_WEAPON_SKILL,
            frame,
            false
        );
        if (!intent) return result;

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

    /**
     * 副武器控制槽的兼容入口：业务校验后只提交通用 combat intent，不直接抢占 man 时间轴。
     */
    public static function requestSubweaponControl(unit:Object, inputFrame:Number):Boolean {
        if (!unit || !isSubweaponControlSkill(getCurrentSkill(unit))) return false;
        if (!LongGunSubWeaponCore.canReloadManual(unit)) return false;
        var frame:Number = resolveInputFrame(inputFrame);
        return UnitActionIntentService.submit(
            unit,
            UnitActionIntentService.CHANNEL_COMBAT,
            UnitActionIntentService.KIND_SUBWEAPON_RELOAD,
            frame,
            SUBWEAPON_RELOAD_TTL_FRAMES,
            null,
            SUBWEAPON_RELOAD_PRIORITY
        );
    }

    public static function isCurrentSubweaponControl(unit:Object):Boolean {
        return isSubweaponControlSkill(getCurrentSkill(unit));
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

    private static function bindCooldownRenderer(cooldownPort:Object):Void {
        if (cooldownPort && cooldownPort.bindRenderer) cooldownPort.bindRenderer();
    }

    private static function getCooldownTimeFromPort(cooldownPort:Object, skill:Object):Number {
        if (cooldownPort && cooldownPort.getCooldownTime) {
            var portTime:Number = Number(cooldownPort.getCooldownTime(skill));
            if (!isNaN(portTime) && portTime > 0) return portTime;
        }
        if (skill && Number(skill.冷却时间) > 0) {
            return Number(skill.冷却时间);
        }
        return 0;
    }

    private static function resolveInputFrame(inputFrame:Number):Number {
        if (!isNaN(inputFrame)) return inputFrame;
        var timer:Object = _root.帧计时器;
        var frame:Number = timer ? Number(timer.当前帧数) : 0;
        return isNaN(frame) ? 0 : frame;
    }
}
