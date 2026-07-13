// 文件路径：org/flashNight/arki/unit/Action/Skill/QuickSkillInputService.as

import org.flashNight.arki.unit.Action.Skill.ManualCooldownService;

/**
 * @class QuickSkillInputService
 * @description 12 槽快捷技能输入语义服务
 *
 * 帧计时器只负责逐帧调用根桥。本服务统一采样实时键位、维护每槽按住锁存，
 * 并编排技能释放、MP 刷新与权威冷却启动。旧技能控制器仅保留键位显示，
 * 旧冷却条只接受 ManualCooldownService 投影，缺失时不阻塞输入。
 */
class org.flashNight.arki.unit.Action.Skill.QuickSkillInputService {

    public static var SLOT_COUNT:Number = 12;

    private static var KEY_NAMES:Array = [
        null,
        "快捷技能栏键1", "快捷技能栏键2", "快捷技能栏键3", "快捷技能栏键4",
        "快捷技能栏键5", "快捷技能栏键6", "快捷技能栏键7", "快捷技能栏键8",
        "快捷技能栏键9", "快捷技能栏键10", "快捷技能栏键11", "快捷技能栏键12"
    ];

    /**
     * 安装在 _root 上的兼容桥。闭包只在玩家模板初始化时创建一次。
     */
    public static function installRootBridge(root:Object):Void {
        if (!root) return;

        var rootRef:Object = root;
        var bridge:Object = {};
        bridge.update = function(unit:Object):Number {
            var inputEnabled:Boolean = !rootRef.暂停 && rootRef.当前玩家总数 == 1;
            var interfaceRoot:Object = rootRef.玩家信息界面;
            var view:Object = interfaceRoot ? interfaceRoot.快捷技能界面 : null;
            var releasedCount:Number = 0;

            for (var slotIndex:Number = 1; slotIndex <= QuickSkillInputService.SLOT_COUNT; slotIndex++) {
                var keyName:String = QuickSkillInputService.getKeyName(slotIndex);
                var keyCode:Number = Number(rootRef[keyName]);
                var keyDown:Boolean = !isNaN(keyCode) && Key.isDown(keyCode);

                QuickSkillInputService.syncKeyLabel(view, slotIndex, keyCode, rootRef);
                var result:Object = QuickSkillInputService.updateSlot(
                    unit,
                    slotIndex,
                    keyDown,
                    inputEnabled,
                    view,
                    keyCode
                );
                if (result && result.released) releasedCount++;
            }

            if (releasedCount > 0 && interfaceRoot && interfaceRoot.刷新mp显示) {
                interfaceRoot.刷新mp显示();
            }

            return releasedCount;
        };
        bridge.clearUnit = function(unit:Object):Void {
            QuickSkillInputService.clearUnit(unit);
        };
        bridge.getKeyName = function(slotIndex:Number):String {
            return QuickSkillInputService.getKeyName(slotIndex);
        };

        root.快捷技能输入控制器 = bridge;
    }

    /**
     * 更新单槽输入。按住锁存按单位、按槽独立保存，不经过单槽动作邮箱。
     */
    public static function updateSlot(
        unit:Object,
        slotIndex:Number,
        keyDown:Boolean,
        inputEnabled:Boolean,
        view:Object,
        keyCode:Number
    ):Object {
        if (!unit || !isValidSlotIndex(slotIndex)) return null;

        var cooldownKey:String = ManualCooldownService.quickSkillKey(slotIndex);
        var cooldownBar:Object = getCooldownBar(view, slotIndex);
        if (cooldownBar) ManualCooldownService.bindRenderer(cooldownKey, cooldownBar);

        var consumedSlots:Array = getConsumedSlots(unit);
        if (!keyDown) {
            consumedSlots[slotIndex] = false;
            return null;
        }

        if (!inputEnabled || consumedSlots[slotIndex] === true) return null;

        var skillSlot:Object = getSkillSlot(view, slotIndex);
        if (!isEquippedSkill(skillSlot) || !ManualCooldownService.isReady(cooldownKey)) {
            return null;
        }

        // 与旧控制器一致：只要进入一次释放尝试，无论成功与否都必须松键后再触发。
        consumedSlots[slotIndex] = true;
        return releaseSlot(unit, slotIndex, skillSlot, keyCode);
    }

    /**
     * 执行技能释放，并在成功时启动对应冷却条。
     */
    public static function releaseSlot(
        unit:Object,
        slotIndex:Number,
        skillSlot:Object,
        keyCode:Number
    ):Object {
        var skillName:String = String(skillSlot.已装备名);
        var cooldownTime:Number = Number(skillSlot.冷却时间);
        var released:Boolean = unit.释放技能(skillName, skillSlot.消耗mp, keyCode) ? true : false;
        var cooldownStarted:Boolean = false;

        if (released) {
            cooldownStarted = ManualCooldownService.start(
                ManualCooldownService.quickSkillKey(slotIndex),
                cooldownTime
            );
        }

        return {
            attempted: true,
            released: released,
            refreshMp: released,
            cooldownStarted: cooldownStarted,
            slotIndex: slotIndex,
            skillName: skillName,
            keyCode: keyCode,
            cooldownTime: cooldownTime
        };
    }

    /**
     * 同步旧透明控制器上的键位文本，支持运行时改键后即时刷新。
     */
    public static function syncKeyLabel(
        view:Object,
        slotIndex:Number,
        keyCode:Number,
        root:Object
    ):Void {
        if (!view || !root || !root.keyshow || !isValidSlotIndex(slotIndex) || isNaN(keyCode)) return;

        var controller:Object = view["控制器" + slotIndex];
        if (!controller || !controller.mytext) return;

        controller.inputOwnedByAS = true;
        if (controller.__quickSkillDisplayedKeyCode === keyCode) return;

        controller.__quickSkillDisplayedKeyCode = keyCode;
        controller.mytext.text = root.keyshow(keyCode);
    }

    public static function getKeyName(slotIndex:Number):String {
        if (!isValidSlotIndex(slotIndex)) return null;
        return String(KEY_NAMES[slotIndex]);
    }

    public static function clearUnit(unit:Object):Void {
        if (!unit) return;
        delete unit.__quickSkillInputConsumedSlots;
    }

    private static function getConsumedSlots(unit:Object):Array {
        var consumedSlots:Array = unit.__quickSkillInputConsumedSlots;
        if (!consumedSlots) {
            consumedSlots = [];
            unit.__quickSkillInputConsumedSlots = consumedSlots;
        }
        return consumedSlots;
    }

    private static function getSkillSlot(view:Object, slotIndex:Number):Object {
        return view ? view["快捷技能栏" + slotIndex] : null;
    }

    private static function getCooldownBar(view:Object, slotIndex:Number):Object {
        return view ? view["进度条" + slotIndex] : null;
    }

    private static function isValidSlotIndex(slotIndex:Number):Boolean {
        return slotIndex >= 1 && slotIndex <= SLOT_COUNT && Math.floor(slotIndex) === slotIndex;
    }

    private static function isEquippedSkill(skillSlot:Object):Boolean {
        if (!skillSlot) return false;
        var skillName:String = String(skillSlot.已装备名);
        return skillName != null && skillName != "" && skillName != "undefined" && skillName != "空";
    }
}
