// 文件路径：org/flashNight/arki/unit/Action/Skill/DrugInputService.as

import org.flashNight.arki.unit.Action.Skill.ManualCooldownService;
import org.flashNight.arki.item.PlayerAssetTransaction;
import org.flashNight.arki.item.DrugSlotAffinityService;

/**
 * @class DrugInputService
 * @description 双药剂组、四输入 lane 的快捷药剂输入与消耗编排。
 *
 * 输入和库存读取不依赖玩家信息 XFL；旧控制器只显示键位，旧进度条只投影冷却。
 */
class org.flashNight.arki.unit.Action.Skill.DrugInputService {

    public static var BANK_COUNT:Number = 2;
    public static var LANE_COUNT:Number = 4;
    public static var PHYSICAL_SLOT_COUNT:Number = 8;
    /** 兼容旧调用方；新代码应明确使用 PHYSICAL_SLOT_COUNT 或 LANE_COUNT。 */
    public static var SLOT_COUNT:Number = PHYSICAL_SLOT_COUNT;
    public static var SWITCH_KEY_NAME:String = "药剂组切换键";

    private static var KEY_NAMES:Array = [
        "快捷物品栏键1", "快捷物品栏键2", "快捷物品栏键3", "快捷物品栏键4"
    ];
    private static var activeBank:Number = 0;
    private static var switchKeyConsumed:Boolean = false;
    private static var sessionGeneration:Number = 1;

    public static function installRootBridge(root:Object):Void {
        if (!root) return;

        var rootRef:Object = root;
        var bridge:Object = {};
        bridge.update = function(unit:Object):Number {
            var inputEnabled:Boolean = !rootRef.暂停 && rootRef.当前玩家总数 == 1;
            var view:Object = rootRef.玩家信息界面 ? rootRef.玩家信息界面.快捷药剂界面 : null;
            var inventory:Object = rootRef.物品栏 ? rootRef.物品栏.药剂栏 : null;
            var usedCount:Number = 0;

            DrugInputService.syncBankView(view, inventory);

            var switchKeyCode:Number = Number(rootRef[DrugInputService.getSwitchKeyName()]);
            var switchKeyDown:Boolean = !isNaN(switchKeyCode) && Key.isDown(switchKeyCode);
            DrugInputService.syncSwitchView(view, switchKeyCode, rootRef);
            var switchResult:Object = DrugInputService.updateSwitch(
                unit, switchKeyDown, inputEnabled, rootRef, view);
            var switched:Boolean = switchResult != null && switchResult.switched === true;
            if (switched) DrugInputService.syncBankView(view, inventory);

            for (var lane:Number = 0; lane < DrugInputService.LANE_COUNT; lane++) {
                var keyName:String = DrugInputService.getKeyName(lane);
                var keyCode:Number = Number(rootRef[keyName]);
                var keyDown:Boolean = !isNaN(keyCode) && Key.isDown(keyCode);
                DrugInputService.syncView(view, lane, keyCode, rootRef);
                var result:Object = DrugInputService.updateSlot(
                    unit,
                    lane,
                    keyDown,
                    inputEnabled && !switched,
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
        bridge.getActiveBank = function():Number {
            return DrugInputService.getActiveBank();
        };
        bridge.resetSession = function():Void {
            DrugInputService.resetSession();
        };

        root.药剂输入控制器 = bridge;
    }

    /**
     * 切换键只认首次 key-down 边沿。无效边沿也立即锁存，因此暂停、死亡或冷却
     * 期间按住不会在条件恢复后补触发。
     */
    public static function updateSwitch(
        unit:Object,
        keyDown:Boolean,
        inputEnabled:Boolean,
        root:Object,
        view:Object
    ):Object {
        bindSwitchRenderer(view);
        if (!keyDown) {
            switchKeyConsumed = false;
            return null;
        }
        if (switchKeyConsumed) return null;
        switchKeyConsumed = true;

        var result:Object = {
            attempted:true,
            switched:false,
            cooldownStarted:false,
            activeBank:activeBank
        };
        var cooldownKey:String = ManualCooldownService.drugSwitchKey();
        if (!unit || !inputEnabled || Number(unit.hp) <= 0
                || !ManualCooldownService.isReady(cooldownKey)) {
            return result;
        }

        var durationMs:Number = root == null
            ? NaN : Number(root.药剂组切换冷却时间);
        if (isNaN(durationMs) || durationMs < 0) durationMs = 3000;
        result.cooldownStarted = ManualCooldownService.start(cooldownKey, durationMs);
        if (!result.cooldownStarted) return result;

        activeBank = activeBank == 0 ? 1 : 0;
        latchHeldLanesUntilRelease(unit);
        result.switched = true;
        result.activeBank = activeBank;
        updateSwitchIcon(view);
        return result;
    }

    public static function updateSlot(
        unit:Object,
        lane:Number,
        keyDown:Boolean,
        inputEnabled:Boolean,
        inventory:Object,
        root:Object,
        view:Object
    ):Object {
        if (!unit || !isValidLane(lane)) return null;

        bindRenderer(view, lane);
        var consumedSlots:Array = getConsumedSlots(unit);
        if (!keyDown) {
            consumedSlots[lane] = false;
            return null;
        }
        if (!inputEnabled || consumedSlots[lane] === true || !inventory || !inventory.getItem) return null;

        var physicalSlot:Number = physicalSlotFor(activeBank, lane);
        var item:Object = inventory.getItem(String(physicalSlot));
        if (!item) return null;

        var cooldownKey:String = ManualCooldownService.drugKey(lane);
        if (!ManualCooldownService.isReady(cooldownKey)) return null;

        // 与旧时间轴一致：有物品且冷却可用时即消费本次按住；死亡和零数量也要松键后重试。
        consumedSlots[lane] = true;
        var itemName:String = String(item.name);
        var result:Object = {
            attempted: true,
            used: false,
            cooldownStarted: false,
            depleted: false,
            slotIndex: physicalSlot,
            physicalSlot: physicalSlot,
            lane: lane,
            bank: activeBank,
            itemName: itemName,
            affinityCommitted: false
        };

        if (Number(unit.hp) <= 0) return result;
        if (Number(item.value) <= 0) {
            publishExhausted(root, itemName);
            result.depleted = true;
            return result;
        }

        // future schema 必须在药效/冷却/扣药任一权威写前 fail closed。
        // preview 纯读；最后一剂的 affinity 与扣药在同一 dirty frame 提交。
        var affinityPreflight:Object =
            DrugSlotAffinityService.previewNormalized(root, inventory);
        if (!affinityPreflight.ok) {
            result.affinityError = String(affinityPreflight.error);
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
                inventory.addValue(String(physicalSlot), -1);
                result.used = true;
            } finally {
                // receipt 在权威写 finally 内按 before/after 固化；catch 因而可以先
                // 清 frame，再做索引修复，任何清理异常都不会吞掉真实 loss。
                remaining = inventory.getItem(String(physicalSlot));
                var quantityAfter:Number = remaining == null ? 0 : Number(remaining.value);
                var committedLoss:Number = quantityBefore - quantityAfter;
                if (committedLoss > 0 && Math.floor(committedLoss) == committedLoss) {
                    PlayerAssetTransaction.recordEffect(
                        "loss", "item", itemName, committedLoss, assetContext);
                    if (remaining == null) {
                        recordDepletionAffinity(
                            root, inventory, physicalSlot, itemName, result);
                    }
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
            publishExhausted(root, itemName);
            result.depleted = true;
        }
        return result;
    }

    /**
     * 背包直服只借用四条药剂 lane 的冷却权威，不改变 active bank，亦不把
     * 背包物品临时装备进药剂栏。装备位是否已有其他药剂不代表这条冷却通道
     * 正在占用：先选已装备同名药剂的最低 ready lane，便于玩家从 HUD 对应；
     * 没有 ready 同名 lane 时，占用任意最低 ready lane。
     */
    public static function selectDirectUseLane(itemName:String,
                                                inventory:Object):Object {
        if (itemName == null || itemName == "" || itemName == "undefined"
                || inventory == null || typeof inventory.getItem != "function") {
            return {success:false, error:"service_not_ready"};
        }
        var lane:Number;
        try {
            for (lane = 0; lane < LANE_COUNT; lane++) {
                if (!ManualCooldownService.isReady(
                        ManualCooldownService.drugKey(lane))) continue;
                var first:Object = inventory.getItem(String(
                    physicalSlotFor(0, lane)));
                var second:Object = inventory.getItem(String(
                    physicalSlotFor(1, lane)));
                if ((first != null && String(first.name) == itemName)
                        || (second != null && String(second.name) == itemName)) {
                    return {success:true, lane:lane};
                }
            }
            for (lane = 0; lane < LANE_COUNT; lane++) {
                if (ManualCooldownService.isReady(
                        ManualCooldownService.drugKey(lane))) {
                    return {success:true, lane:lane};
                }
            }
        } catch (cooldownOrInventoryError) {
            return {success:false, error:"cooldown_unavailable"};
        }
        return {success:false, error:"no_available_lane"};
    }

    /**
     * 对 exact 背包来源执行一次药剂事务。暂停状态不是领域拒绝条件；调用方只需
     * 提供存活的当前玩家。该写不会记录药剂槽 affinity。
     */
    public static function consumeBackpackItem(unit:Object,
                                                inventory:Object,
                                                physicalSlot:Number,
                                                item:Object,
                                                lane:Number,
                                                root:Object):Object {
        if (unit == null || Number(unit.hp) <= 0) {
            return {used:false, error:"player_unavailable"};
        }
        if (root == null || root.存档系统 == null || inventory == null
                || typeof inventory.getItem != "function"
                || typeof inventory.addValue != "function"
                || !isValidLane(lane) || physicalSlot < 0
                || Math.floor(physicalSlot) != physicalSlot) {
            return {used:false, error:"service_not_ready"};
        }
        var current:Object;
        try {
            current = inventory.getItem(String(physicalSlot));
        } catch (sourceReadError) {
            return {used:false, error:"stale_source"};
        }
        if (current == null || current !== item || Number(current.value) <= 0) {
            return {used:false, error:"stale_source"};
        }
        var selected:Object = selectDirectUseLane(String(current.name),
            root.物品栏 == null ? null : root.物品栏.药剂栏);
        if (selected == null || selected.success !== true
                || Number(selected.lane) != lane) {
            return {used:false, error:selected == null
                ? "cooldown_unavailable" : String(selected.error)};
        }

        var itemName:String = String(current.name);
        var cooldownKey:String = ManualCooldownService.drugKey(lane);
        var result:Object = {attempted:true, used:false,
            cooldownStarted:false, depleted:false, physicalSlot:physicalSlot,
            lane:lane, itemName:itemName, remaining:Number(current.value)};
        var assetContext:Object = {
            source:"item_use", reason:"direct_drug_use", mergeScope:"operation"
        };
        var transaction:Object = PlayerAssetTransaction.begin(assetContext);
        var quantityBefore:Number = Number(current.value);
        var remaining:Object;
        try {
            PlayerAssetTransaction.markDirtyRequired(root.存档系统);
            if (root.使用药剂) root.使用药剂(itemName);
            result.cooldownStarted = ManualCooldownService.start(
                cooldownKey, Number(root.吃药冷却时间));
            if (!result.cooldownStarted) throw "cooldown_start_failed";
            try {
                inventory.addValue(String(physicalSlot), -1);
                result.used = true;
            } finally {
                remaining = inventory.getItem(String(physicalSlot));
                var quantityAfter:Number = remaining == null
                    ? 0 : Number(remaining.value);
                var committedLoss:Number = quantityBefore - quantityAfter;
                if (committedLoss > 0 && Math.floor(committedLoss) == committedLoss) {
                    PlayerAssetTransaction.recordEffect(
                        "loss", "item", itemName, committedLoss, assetContext);
                }
                result.remaining = quantityAfter;
            }
            PlayerAssetTransaction.commit(transaction);
        } catch (useError) {
            PlayerAssetTransaction.settleAfterException(transaction, true);
            try {
                if (inventory.setIndexes != undefined) inventory.setIndexes(null);
            } catch (indexRepairError) {
                trace("[DrugInputService] direct inventory index repair failed: "
                    + indexRepairError);
            }
            throw useError;
        }
        if (remaining == null) {
            publishExhausted(root, itemName);
            result.depleted = true;
        }
        return result;
    }

    private static function recordDepletionAffinity(
        root:Object,
        inventory:Object,
        physicalSlot:Number,
        itemName:String,
        result:Object
    ):Void {
        var affinityCommit:Object =
            DrugSlotAffinityService.recordDepleted(
                root, inventory, physicalSlot, itemName);
        result.affinityCommitted = affinityCommit.success === true;
        if (!result.affinityCommitted) {
            result.affinityError = String(affinityCommit.error);
            trace("[DrugInputService] affinity commit failed: "
                + result.affinityError);
        }
    }

    public static function syncView(view:Object, lane:Number, keyCode:Number, root:Object):Void {
        if (!view || !isValidLane(lane)) return;

        var controller:Object = view["控制器" + lane];
        if (controller) {
            controller.inputOwnedByAS = true;
            if (root && root.keyshow && controller.mytext && !isNaN(keyCode)
                && controller.__drugDisplayedKeyCode !== keyCode) {
                controller.__drugDisplayedKeyCode = keyCode;
                controller.mytext.text = root.keyshow(keyCode);
            }
        }
        bindRenderer(view, lane);
    }

    public static function syncSwitchView(view:Object, keyCode:Number, root:Object):Void {
        if (!view) return;
        var controller:Object = view.控制器4;
        if (controller) {
            controller.inputOwnedByAS = true;
            if (root && root.keyshow && controller.mytext && !isNaN(keyCode)
                    && controller.__drugDisplayedKeyCode !== keyCode) {
                controller.__drugDisplayedKeyCode = keyCode;
                controller.mytext.text = root.keyshow(keyCode);
            }
        }
        bindSwitchRenderer(view);
        updateSwitchIcon(view);
    }

    /** 四个持久 DrugIcon 只在 bank 或 inventory 身份变化时重绑物理槽。 */
    public static function syncBankView(view:Object, inventory:Object):Void {
        if (!view || !inventory) return;
        if (view.__drugProjectedBank === activeBank
                && view.__drugProjectedInventory === inventory) {
            updateSwitchIcon(view);
            return;
        }

        var icons:Array = view.药剂图标列表;
        if (icons instanceof Array && icons.length >= LANE_COUNT) {
            var projectedIcons:Array = [];
            var projectionReady:Boolean = true;
            for (var lane:Number = 0; lane < LANE_COUNT; lane++) {
                var iconHost:Object = icons[lane];
                var itemIcon:Object = iconHost ? iconHost.itemIcon : null;
                if (!itemIcon || typeof itemIcon.reset != "function") {
                    projectionReady = false;
                    break;
                }
                projectedIcons[lane] = itemIcon;
            }
            if (projectionReady) {
                for (lane = 0; lane < LANE_COUNT; lane++) {
                    projectedIcons[lane].reset(inventory, physicalSlotFor(activeBank, lane));
                }
                // 只有四个持久 icon 全部完成重绑后才提交整体投影标记；否则下一帧重试。
                view.__drugProjectedBank = activeBank;
                view.__drugProjectedInventory = inventory;
            }
        }
        updateSwitchIcon(view);
    }

    public static function getActiveBank():Number {
        return activeBank;
    }

    public static function bankForPhysicalSlot(slot:Number):Number {
        return isValidPhysicalSlot(slot) ? Math.floor(slot / LANE_COUNT) : -1;
    }

    public static function laneForPhysicalSlot(slot:Number):Number {
        return isValidPhysicalSlot(slot) ? slot % LANE_COUNT : -1;
    }

    public static function physicalSlotFor(bank:Number, lane:Number):Number {
        if (!isValidBank(bank) || !isValidLane(lane)) return -1;
        return bank * LANE_COUNT + lane;
    }

    public static function getKeyName(lane:Number):String {
        return isValidLane(lane) ? String(KEY_NAMES[lane]) : null;
    }

    public static function getSwitchKeyName():String {
        return SWITCH_KEY_NAME;
    }

    /** 新建、成功读档和删档边界调用；普通换组绝不调用。 */
    public static function resetSession():Void {
        activeBank = 0;
        switchKeyConsumed = false;
        sessionGeneration++;
        for (var lane:Number = 0; lane < LANE_COUNT; lane++) {
            ManualCooldownService.reset(ManualCooldownService.drugKey(lane));
        }
        ManualCooldownService.reset(ManualCooldownService.drugSwitchKey());
    }

    public static function clearUnit(unit:Object):Void {
        if (!unit) return;
        delete unit.__drugInputConsumedSlots;
        delete unit.__drugInputSessionGeneration;
    }

    private static function bindRenderer(view:Object, lane:Number):Void {
        if (!view) return;
        var renderer:Object = view["进度条" + lane];
        if (renderer) ManualCooldownService.bindRenderer(ManualCooldownService.drugKey(lane), renderer);
    }

    private static function bindSwitchRenderer(view:Object):Void {
        if (!view || !view.进度条4) return;
        ManualCooldownService.bindRenderer(ManualCooldownService.drugSwitchKey(), view.进度条4);
    }

    private static function updateSwitchIcon(view:Object):Void {
        if (!view || !view.药剂组切换图标) return;
        var icon:Object = view.药剂组切换图标;
        if (icon.__drugProjectedBank === activeBank) return;
        icon.__drugProjectedBank = activeBank;
        if (icon.gotoAndStop) icon.gotoAndStop(activeBank == 0 ? "I" : "II");
    }

    private static function publishExhausted(root:Object, itemName:String):Void {
        if (!root) return;
        try {
            if (root.发布消息 && itemName != null && itemName != "" && itemName != "undefined") {
                root.发布消息(itemName + "耗尽！");
            }
        } catch (exhaustedMessageError) {
            // 扣药已经提交；可选提示失败不能改变权威物品栏结果。
            trace("[DrugInputService] exhausted message failed: " + exhaustedMessageError);
        }
    }

    private static function getConsumedSlots(unit:Object):Array {
        var consumedSlots:Array = unit.__drugInputConsumedSlots;
        if (!consumedSlots || unit.__drugInputSessionGeneration !== sessionGeneration) {
            consumedSlots = [];
            unit.__drugInputConsumedSlots = consumedSlots;
            unit.__drugInputSessionGeneration = sessionGeneration;
        }
        return consumedSlots;
    }

    private static function latchHeldLanesUntilRelease(unit:Object):Void {
        if (!unit) return;
        var consumedSlots:Array = getConsumedSlots(unit);
        for (var lane:Number = 0; lane < LANE_COUNT; lane++) consumedSlots[lane] = true;
    }

    private static function isValidBank(bank:Number):Boolean {
        return bank >= 0 && bank < BANK_COUNT && Math.floor(bank) === bank;
    }

    private static function isValidLane(lane:Number):Boolean {
        return lane >= 0 && lane < LANE_COUNT && Math.floor(lane) === lane;
    }

    private static function isValidPhysicalSlot(slot:Number):Boolean {
        return slot >= 0 && slot < PHYSICAL_SLOT_COUNT && Math.floor(slot) === slot;
    }
}
