// 文件路径：org/flashNight/arki/unit/Action/Skill/DrugInputService.as

import org.flashNight.arki.unit.Action.Skill.ManualCooldownService;
import org.flashNight.arki.item.PlayerAssetTransaction;

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

        var assetContext:Object = {
            source:"item_use", reason:"drug_use", mergeScope:"operation"
        };
        var assetTransaction:Object = PlayerAssetTransaction.begin(assetContext);
        var quantityBefore:Number = Number(item.value);
        var remaining:Object;
        try {
            // 药效、冷却与扣药组成既有领域顺序；存档系统缺失时在任何一步前失败。
            PlayerAssetTransaction.markDirtyRequired(root.存档系统);
            if (root && root.使用药剂) root.使用药剂(itemName);
            result.cooldownStarted = ManualCooldownService.start(cooldownKey, Number(root.吃药冷却时间));
            // addValue 会在数量写入后同步发布 ItemValueChanged/ItemRemoved；
            // dirty 必须先于监听器可见，异常路径再按 before/after 记录真实扣除。
            try {
                inventory.addValue(String(slotIndex), -1);
                result.used = true;
            } finally {
                // receipt 在权威写 finally 内按 before/after 固化；catch 因而可以先
                // 清 frame，再做索引修复，任何清理异常都不会吞掉真实 loss。
                remaining = inventory.getItem(String(slotIndex));
                var quantityAfter:Number = remaining == null ? 0 : Number(remaining.value);
                var committedLoss:Number = quantityBefore - quantityAfter;
                if (committedLoss > 0 && Math.floor(committedLoss) == committedLoss) {
                    PlayerAssetTransaction.recordEffect(
                        "loss", "item", itemName, committedLoss, assetContext);
                }
            }
            PlayerAssetTransaction.commit(assetTransaction);
        } catch (useError) {
            // 领域效果没有通用逆操作；finally 已固化真实扣药，先恢复 EventBus/
            // frame，再做派生索引修复，始终保留原始异常。
            PlayerAssetTransaction.settleAfterException(assetTransaction, true);
            // ArrayInventory.remove 先删除权威 item、同步发布 ItemRemoved，随后才
            // 维护索引树；listener fault 会跳过后半段。这里无事件重建派生索引，
            // 同时保留原异常与已经发生的扣药事实。
            try {
                if (inventory.setIndexes != undefined) inventory.setIndexes(null);
            } catch (indexRepairError) {
                trace("[DrugInputService] inventory index repair failed: " + indexRepairError);
            }
            throw useError;
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
        try {
            if (root.发布消息 && itemName != null && itemName != "" && itemName != "undefined") {
                root.发布消息(itemName + "耗尽！");
            }
        } catch (exhaustedMessageError) {
            // 扣药已经提交；可选提示失败也必须清掉快捷栏镜像，避免下一按键重放。
            trace("[DrugInputService] exhausted message failed: " + exhaustedMessageError);
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
