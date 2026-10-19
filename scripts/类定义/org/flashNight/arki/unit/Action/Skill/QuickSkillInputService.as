// 文件路径：org/flashNight/arki/unit/Action/Skill/QuickSkillInputService.as

import org.flashNight.arki.unit.Action.Skill.ManualCooldownService;
import org.flashNight.arki.unit.Action.Skill.SkillReleaseGuard;
import org.flashNight.arki.skill.SkillLoadoutService;
import org.flashNight.arki.skill.SkillResourceService;

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
                if (result.released) releasedCount++;
            }

            if (releasedCount > 0 && interfaceRoot.刷新mp显示) {
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
        if (!unit || typeof unit.释放技能 != "function" || !isEquippedSkill(skillSlot)) return null;

        var skillName:String = SkillReleaseGuard.normalizeSkillName(
            skillSlot.__domainDescriptor === true ? skillSlot.skillKey : skillSlot.已装备名
        );
        var cooldownTime:Number = Number(skillSlot.__domainDescriptor === true ? skillSlot.cooldownMs : skillSlot.冷却时间);
        var mpCost:Number = Number(skillSlot.__domainDescriptor === true ? skillSlot.mp : skillSlot.消耗mp);
        SkillResourceService.begin(unit, "skill", slotIndex);
        var released:Boolean = unit.释放技能(skillName, mpCost, keyCode) ? true : false;
        SkillResourceService.finish(unit);
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
     * 按技能名释放（搓招入口）。双通道裁决：
     *
     *   ① 已装备（1..12 任一槽）：完全复用数字键语义
     *      - 逐个试「就绪」的槽 → releaseSlot（HUD 冷却条 + quick:<槽> 冷却 + MP 事务）
     *      - 全部在冷却/损坏 → 直接失败，**绝不回落到名字通道**（否则搓招可绕过槽冷却）
     *   ② 未装备：走名字通道
     *      - 成本读 技能表对象[名].MP（与槽描述符同源）
     *      - MP 由 unit.释放技能 扣，本方法只做只读预检 + 起冷却 + 刷显示
     *      - 冷却走 ManualCooldownService.skillKey(名)，与槽通道互不干扰
     *      - 不发 SkillResourceService「skill」反馈：HUD 协议对 kind=="skill" 强制 slot ∈ [1,12]
     *
     * @return null = 名字非法 / 未学会 / 数据不可释放；否则
     *         {attempted, released, reason, skillName, mpCost, cooldownTime, slotIndex, ...}
     */
    public static function releaseBySkillName(unit:Object, rawSkillName:String, keyCode:Number):Object {
        if (!unit || typeof unit.释放技能 != "function") return null;

        var skillName:String = SkillReleaseGuard.normalizeSkillName(rawSkillName);
        if (skillName == null) return null;

        // ① 已装备：槽通道
        var slots:Array = SkillLoadoutService.findEquippedSlots(skillName);
        if (slots.length > 0) {
            for (var i:Number = 0; i < slots.length; i++) {
                var slotIndex:Number = Number(slots[i]);
                var descriptor:Object = SkillLoadoutService.getSlotDescriptor(slotIndex);
                if (!descriptor || descriptor.stateHealth != "ok" || descriptor.writeBlocked === true) continue;
                descriptor.__domainDescriptor = true;
                if (!isEquippedSkill(descriptor)) continue;
                if (!ManualCooldownService.isReady(ManualCooldownService.quickSkillKey(slotIndex))) continue;

                var slotResult:Object = releaseSlot(unit, slotIndex, descriptor, keyCode);
                if (slotResult != null) slotResult.reason = slotResult.released === true ? "" : "rejected";
                return slotResult;
            }
            return {
                attempted: false, released: false, refreshMp: false, cooldownStarted: false,
                reason: "cooldown", skillName: skillName, keyCode: keyCode, slotIndex: 0
            };
        }

        // ② 未装备：名字通道
        var info:Object = SkillLoadoutService.getSkillDescriptor(skillName);
        if (info == null) return null;

        var mpCost:Number = Number(info.mp);
        var cooldownTime:Number = Number(info.cooldownMs);
        if (isNaN(mpCost) || mpCost < 0 || isNaN(cooldownTime) || cooldownTime < 0) return null;

        var cooldownKey:String = ManualCooldownService.skillKey(skillName);
        if (!ManualCooldownService.isReady(cooldownKey)) {
            return {
                attempted: false, released: false, refreshMp: false, cooldownStarted: false,
                reason: "cooldown", skillName: skillName, keyCode: keyCode,
                mpCost: mpCost, cooldownTime: cooldownTime, slotIndex: 0
            };
        }

        if (Number(unit.mp) < mpCost) {
            notifySkillMpDenied(unit, skillName);
            return {
                attempted: true, released: false, refreshMp: false, cooldownStarted: false,
                reason: "mp", skillName: skillName, keyCode: keyCode,
                mpCost: mpCost, cooldownTime: cooldownTime, slotIndex: 0
            };
        }

        // 唯一扣蓝点：释放技能 内部在「释放条件通过之后」执行 this.mp -= 消耗mp。
        // 本方法不做任何 mp 写入，避免双扣。
        var released:Boolean = unit.释放技能(skillName, mpCost, keyCode) ? true : false;
        var cooldownStarted:Boolean = false;
        if (released) {
            cooldownStarted = ManualCooldownService.start(cooldownKey, cooldownTime);
            refreshMpDisplay();
        }

        return {
            attempted: true, released: released, refreshMp: released, cooldownStarted: cooldownStarted,
            reason: released ? "" : "rejected", skillName: skillName, keyCode: keyCode,
            mpCost: mpCost, cooldownTime: cooldownTime, slotIndex: 0
        };
    }

    /** 未装备技能没有 HUD 槽位，只能走本地提示；带 1 秒静默窗口。 */
    private static function notifySkillMpDenied(unit:Object, skillName:String):Void {
        if (unit._name != _root.控制目标 || _root.暂停) return;
        var now:Number = getTimer();
        if (now - Number(unit.__skillMpNoticeAt) < 1000) return;
        unit.__skillMpNoticeAt = now;

        if (typeof _root.发布消息 == "function") {
            _root.发布消息("<FONT COLOR='#e87864'>" + skillName + "：MP 不足，无法释放</FONT>");
        }
        if (typeof _root.播放音效 == "function") {
            _root.播放音效("message_ui.wav");
        }
    }

    /** 与数字键桥接层同一刷新口径。 */
    private static function refreshMpDisplay():Void {
        var interfaceRoot:Object = _root.玩家信息界面;
        if (interfaceRoot && typeof interfaceRoot.刷新mp显示 == "function") {
            interfaceRoot.刷新mp显示();
        }
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
        // TestLoader 的显式 fixture 仍可隔离测试输入锁存；生产读路径只认领域描述符。
        if (view.__skillInputFixture === true) return view["快捷技能栏" + slotIndex];
        var descriptor:Object = SkillLoadoutService.getSlotDescriptor(slotIndex);
        if (!descriptor || descriptor.stateHealth != "ok" || descriptor.writeBlocked === true) return null;
        descriptor.__domainDescriptor = true;
        return descriptor;
    }

    private static function getCooldownBar(view:Object, slotIndex:Number):Object {
        return view ? view["进度条" + slotIndex] : null;
    }

    private static function isValidSlotIndex(slotIndex:Number):Boolean {
        return slotIndex >= 1 && slotIndex <= SLOT_COUNT && Math.floor(slotIndex) === slotIndex;
    }

    private static function isEquippedSkill(skillSlot:Object):Boolean {
        if (skillSlot.__domainDescriptor === true) {
            return skillSlot.equipped === true
                && SkillReleaseGuard.normalizeSkillName(skillSlot.skillKey) != null
                && !isNaN(Number(skillSlot.mp)) && Number(skillSlot.mp) >= 0
                && !isNaN(Number(skillSlot.cooldownMs)) && Number(skillSlot.cooldownMs) >= 0;
        }
        return SkillReleaseGuard.isEquippedSlot(skillSlot);
    }
}
