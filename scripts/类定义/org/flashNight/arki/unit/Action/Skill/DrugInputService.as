// 文件路径：org/flashNight/arki/unit/Action/Skill/DrugInputService.as

import org.flashNight.arki.unit.Action.Skill.ManualCooldownService;

/**
 * @class DrugInputService
 * @description 四槽快捷药剂输入与消耗编排。
 *
 * 输入和库存读取不依赖玩家信息 XFL；旧控制器只显示键位，旧进度条只投影冷却。
 */
class org.flashNight.arki.unit.Action.Skill.DrugInputService {

    public static var SLOT_COUNT:Number = 4;

    private static var KEY_NAMES:Array = [
        "快捷物品栏键1", "快捷物品栏键2", "快捷物品栏键3", "快捷物品栏键4"
    ];

    public static function installRootBridge(root:Object):Void {
        if (!root) return;

        var rootRef:Object = root;
        var bridge:Object = {};
        bridge.update = function(unit:Object):Number {
            var inputEnabled:Boolean = !rootRef.暂停 && rootRef.当前玩家总数 == 1;
            var view:Object = rootRef.玩家信息界面 ? rootRef.玩家信息界面.快捷药剂界面 : null;
            var inventory:Object = rootRef.物品栏 ? rootRef.物品栏.药剂栏 : null;
            var usedCount:Number = 0;

            for (var slotIndex:Number = 0; slotIndex < DrugInputService.SLOT_COUNT; slotIndex++) {
                var keyName:String = DrugInputService.getKeyName(slotIndex);
                var keyCode:Number = Number(rootRef[keyName]);
                var keyDown:Boolean = !isNaN(keyCode) && Key.isDown(keyCode);
                DrugInputService.syncView(view, slotIndex, keyCode, rootRef);
                var result:Object = DrugInputService.updateSlot(
                    unit,
                    slotIndex,
                    keyDown,
                    inputEnabled,
                    inventory,
                    rootRef,
                    null
                );
                if (result && result.used) usedCount++;
            }
            return usedCount;
        };
        bridge.clearUnit = function(unit:Object):Void {
            DrugInputService.clearUnit(unit);
        };

        root.药剂输入控制器 = bridge;
    }

    public static function updateSlot(
        unit:Object,
        slotIndex:Number,
        keyDown:Boolean,
        inputEnabled:Boolean,
        inventory:Object,
        root:Object,
        view:Object
    ):Object {
        if (!unit || !isValidSlotIndex(slotIndex)) return null;

        bindRenderer(view, slotIndex);
        var consumedSlots:Array = getConsumedSlots(unit);
        if (!keyDown) {
            consumedSlots[slotIndex] = false;
            return null;
        }
        if (!inputEnabled || consumedSlots[slotIndex] === true || !inventory || !inventory.getItem) return null;

        var item:Object = inventory.getItem(String(slotIndex));
        if (!item) return null;

        var cooldownKey:String = ManualCooldownService.drugKey(slotIndex);
        if (!ManualCooldownService.isReady(cooldownKey)) return null;

        // 与旧时间轴一致：有物品且冷却可用时即消费本次按住；死亡和零数量也要松键后重试。
        consumedSlots[slotIndex] = true;
        var itemName:String = String(item.name);
        var result:Object = {
            attempted: true,
            used: false,
            cooldownStarted: false,
            depleted: false,
            slotIndex: slotIndex,
            itemName: itemName
        };

        if (Number(unit.hp) <= 0) return result;
        if (Number(item.value) <= 0) {
            clearExhaustedMirror(root, slotIndex, itemName);
            result.depleted = true;
            return result;
        }

        if (root && root.使用药剂) root.使用药剂(itemName);
        result.cooldownStarted = ManualCooldownService.start(cooldownKey, Number(root.吃药冷却时间));
        var quantityBefore:Number = Number(item.value);
        inventory.addValue(String(slotIndex), -1);
        result.used = true;
        var remaining:Object = inventory.getItem(String(slotIndex));
        if ((remaining !== item || Number(remaining.value) != quantityBefore)
                && root && root.存档系统) {
            root.存档系统.dirtyMark = true;
        }

        if (!remaining) {
            clearExhaustedMirror(root, slotIndex, itemName);
            result.depleted = true;
        }
        return result;
    }

    public static function syncView(view:Object, slotIndex:Number, keyCode:Number, root:Object):Void {
        if (!view || !isValidSlotIndex(slotIndex)) return;

        var controller:Object = view["控制器" + slotIndex];
        if (controller) {
            controller.inputOwnedByAS = true;
            if (root && root.keyshow && controller.mytext && !isNaN(keyCode)
                && controller.__drugDisplayedKeyCode !== keyCode) {
                controller.__drugDisplayedKeyCode = keyCode;
                controller.mytext.text = root.keyshow(keyCode);
            }
        }
        bindRenderer(view, slotIndex);
    }

    public static function getKeyName(slotIndex:Number):String {
        return isValidSlotIndex(slotIndex) ? String(KEY_NAMES[slotIndex]) : null;
    }

    public static function clearUnit(unit:Object):Void {
        if (unit) delete unit.__drugInputConsumedSlots;
    }

    private static function bindRenderer(view:Object, slotIndex:Number):Void {
        if (!view) return;
        var renderer:Object = view["进度条" + slotIndex];
        if (renderer) ManualCooldownService.bindRenderer(ManualCooldownService.drugKey(slotIndex), renderer);
    }

    private static function clearExhaustedMirror(root:Object, slotIndex:Number, itemName:String):Void {
        if (!root) return;
        if (root.发布消息 && itemName != null && itemName != "" && itemName != "undefined") {
            root.发布消息(itemName + "耗尽！");
        }
        root["快捷物品栏" + slotIndex] = "";
    }

    private static function getConsumedSlots(unit:Object):Array {
        var consumedSlots:Array = unit.__drugInputConsumedSlots;
        if (!consumedSlots) {
            consumedSlots = [];
            unit.__drugInputConsumedSlots = consumedSlots;
        }
        return consumedSlots;
    }

    private static function isValidSlotIndex(slotIndex:Number):Boolean {
        return slotIndex >= 0 && slotIndex < SLOT_COUNT && Math.floor(slotIndex) === slotIndex;
    }
}
