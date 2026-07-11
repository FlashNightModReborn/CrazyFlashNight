import org.flashNight.arki.item.itemCollection.ArrayInventory;

import org.flashNight.gesh.tooltip.TooltipComposer;
import org.flashNight.arki.item.BaseItem;
import org.flashNight.arki.item.EquipmentUtil;
import org.flashNight.arki.item.equipment.TierSystem;

/**
 * Web 双栏工作台的 inventory-domain 权威服务。
 *
 * v1 开放：range snapshot、lease-bound tooltip、背包 discard、背包↔仓库 whole-slot
 * move/merge/swap，以及仓库整容器 sortAndMerge。所有写入都在同一重入守卫内完成：双端 lease 校验 →
 * 领域预检 → 无事件提交/失败回滚 → dirtyMark → 统一生命周期事件 → snapshot。
 */
class org.flashNight.arki.item.InventoryPanelService {
    private static var _json:LiteJSON;
    private static var _inited:Boolean = false;
    private static var _busy:Boolean = false;
    private static var _sessionCounter:Number = 0;
    private static var _sessionNonce:String = "";
    private static var _leaseSeq:Number = 0;
    private static var _snapshotSeq:Number = 0;
    private static var _containerEpochs:Object = {};
    private static var _leaseIds:Object = {};
    private static var _leaseRefs:Object = {};
    private static var _leaseCounts:Object = {};
    private static var _leaseMergeKeys:Object = {};
    private static var _leaseConfirm:Object = {};
    private static var _sortMethods:Object = {
        byType: true, byUse: true, byPrice: true, byLevel: true,
        byID: true, byName: true, byValue: true, byTime: true
    };

    // Gate A2 的确定性失败注入，仅供 TestLoader 验证 rollback；生产默认永不命中。
    private static var _testFailContainerId:String = "";
    private static var _testFailSlot:Number = -1;

    public static function install():Void {
        if (_inited) return;
        _json = new LiteJSON();
        if (_root.gameCommands == undefined) _root.gameCommands = {};

        _root.gameCommands["inventorySnapshot"] = function(params) {
            org.flashNight.arki.item.InventoryPanelService.handle("snapshot", params);
        };
        _root.gameCommands["inventoryTooltip"] = function(params) {
            org.flashNight.arki.item.InventoryPanelService.handle("tooltip", params);
        };
        _root.gameCommands["inventoryDiscard"] = function(params) {
            org.flashNight.arki.item.InventoryPanelService.handle("discard", params);
        };
        _root.gameCommands["inventoryMove"] = function(params) {
            org.flashNight.arki.item.InventoryPanelService.handle("move", params);
        };
        _root.gameCommands["inventoryMerge"] = function(params) {
            org.flashNight.arki.item.InventoryPanelService.handle("merge", params);
        };
        _root.gameCommands["inventorySwap"] = function(params) {
            org.flashNight.arki.item.InventoryPanelService.handle("swap", params);
        };
        _root.gameCommands["inventorySortAndMerge"] = function(params) {
            org.flashNight.arki.item.InventoryPanelService.handle("sortAndMerge", params);
        };

        beginSession();
        _inited = true;
    }

    private static function handle(commandName:String, params:Object):Void {
        var response:Object = execute(commandName, params);
        response.task = "inventory_response";
        response.callId = params == undefined ? undefined : params.callId;
        sendResponse(response);
    }

    /** 纯同步执行入口，同时供 TestLoader 验证事务语义。 */
    public static function execute(commandName:String, params:Object):Object {
        if (_busy) return fail("busy");
        if (params == undefined || Number(params.v) != 1) return fail("unsupported_version");

        if (commandName == "snapshot") return executeSnapshot(params);
        if (commandName == "tooltip") return executeTooltip(params);
        if (commandName == "discard") return executeDiscard(params);
        if (commandName == "move" || commandName == "merge" || commandName == "swap") {
            return executeTransfer(commandName, params);
        }
        if (commandName == "sortAndMerge") return executeSortAndMerge(params);
        return fail("unsupported_cmd");
    }

    private static function executeSnapshot(params:Object):Object {
        var requests:Array = params.requests;
        if (!(requests instanceof Array) || requests.length < 1 || requests.length > 4) {
            return fail("invalid_payload");
        }

        var normalized:Array = [];
        var i:Number;
        for (i = 0; i < requests.length; i++) {
            var request:Object = requests[i];
            var containerId:String = request == undefined ? "" : String(request.containerId);
            var inventory:ArrayInventory = resolveContainer(containerId);
            if (inventory == null) return fail("unsupported_container");
            if (!isWholeNumber(request.offset) || !isWholeNumber(request.limit)) return fail("invalid_payload");
            var offset:Number = Number(request.offset);
            var limit:Number = Number(request.limit);
            if (offset < 0 || offset >= inventory.capacity || limit < 1 || limit > 100) {
                return fail("invalid_payload");
            }
            normalized.push({containerId: containerId, inventory: inventory, offset: offset, limit: limit});
        }

        // 每次显式读取都开启新的 snapshot-local lease session；旧 Web 会话 token 立即失效。
        beginSession();
        var snapshots:Array = [];
        for (i = 0; i < normalized.length; i++) {
            var entry:Object = normalized[i];
            snapshots.push(buildSnapshot(entry.containerId, entry.inventory, entry.offset, entry.limit));
        }
        return {success: true, v: 1, sessionNonce: _sessionNonce, snapshots: snapshots};
    }

    /**
     * 读取当前 lease 对应的真实物品实例，避免只按名称生成的基础 tooltip 丢失强化、进阶和配件信息。
     * 这是纯读操作；槽位或实例已变化时返回 stale_state，不回退到 Web 投影猜测。
     */
    private static function executeTooltip(params:Object):Object {
        var sourceCheck:Object = validateSlotRef(params.source, true, false);
        if (!sourceCheck.success) return sourceCheck;

        var item:Object = sourceCheck.item;
        // ItemUtil.getItemData 以 __proto__ 区分 String/Number；保留 BaseItem.name 原始值，
        // 不额外套 String(...)，否则部分 AS2 运行时会落到 null 分支。
        var itemData:Object = org.flashNight.arki.item.ItemUtil.getItemData(item.name);
        if (itemData == undefined) return fail("item_data_missing");

        // TooltipComposer 的 baseItem 分支面向 value:Object 的装备实例；数值型 stack
        // 若也传 BaseItem，会把数量当装备 value 读取。stack 只需基础物品数据与默认等级。
        var instanceValue:Object = typeof item.value == "object" ? item.value : {level: 1};
        var baseItem = typeof item.value == "object" && typeof item.getData == "function" ? item : null;
        var descHTML:String;
        var introHTML:String;
        try {
            descHTML = TooltipComposer.generateItemDescriptionText(itemData, baseItem);
            introHTML = TooltipComposer.generateIntroPanelContent(baseItem, itemData, instanceValue);
        } catch (error) {
            trace("[InventoryPanelService tooltip] compose failed: " + error);
            return fail("tooltip_failed");
        }

        var projection:Object = buildItemProjection(item);
        var itemType:String = String(projection.majorType);
        if (itemType == "消耗品" && projection.use != undefined) itemType = String(projection.use);
        return {
            success: true,
            v: 1,
            itemName: String(item.name),
            displayname: String(projection.displayName),
            iconName: String(projection.icon),
            itemType: itemType,
            descHTML: descHTML.split('"').join("&quot;"),
            introHTML: introHTML.split('"').join("&quot;")
        };
    }

    private static function executeDiscard(params:Object):Object {
        var source:Object = params.source;
        var sourceCheck:Object = validateSlotRef(source, true, false);
        if (!sourceCheck.success) return sourceCheck;
        if (sourceCheck.containerId != "背包") return fail("discard_forbidden");
        if (!confirmProjectionMatches(sourceCheck)) return fail("stale_state");

        _busy = true;
        var oldItem:Object = sourceCheck.item;
        if (!commitSlot(sourceCheck.containerId, sourceCheck.inventory, sourceCheck.slot, null)) {
            _busy = false;
            return fail("commit_failed");
        }

        invalidateSlot(sourceCheck.containerId, sourceCheck.slot);
        markDirty();
        sourceCheck.inventory.publishTransactionChange(sourceCheck.slot, "removed");
        var snapshots:Array = [buildSnapshot("背包", sourceCheck.inventory, 0, Math.min(50, sourceCheck.inventory.capacity))];
        _busy = false;
        return {success: true, v: 1, operation: "discard", discarded: buildItemProjection(oldItem), snapshots: snapshots};
    }

    private static function executeTransfer(commandName:String, params:Object):Object {
        var sourceCheck:Object = validateSlotRef(params.source, true, commandName == "merge");
        if (!sourceCheck.success) return sourceCheck;
        var targetMustOccupy:Boolean = commandName == "merge" || commandName == "swap";
        var targetCheck:Object = validateSlotRef(params.target, targetMustOccupy, commandName == "merge");
        if (!targetCheck.success) return targetCheck;
        if (sourceCheck.containerId == targetCheck.containerId && sourceCheck.slot == targetCheck.slot) {
            return fail("same_slot");
        }

        if (commandName == "move" && targetCheck.item != null) return fail("target_occupied");
        if (commandName == "merge") {
            if (typeof sourceCheck.item.value != "number" || typeof targetCheck.item.value != "number") {
                return fail("merge_rejected");
            }
            if (sourceCheck.item.name != targetCheck.item.name) return fail("merge_rejected");
        }
        if (commandName == "swap" && targetCheck.item == null) return fail("target_empty");

        _busy = true;
        var committed:Boolean;
        if (commandName == "move") committed = commitMove(sourceCheck, targetCheck);
        else if (commandName == "merge") committed = commitMerge(sourceCheck, targetCheck);
        else committed = commitSwap(sourceCheck, targetCheck);

        if (!committed) {
            _busy = false;
            return fail("commit_failed");
        }

        invalidateSlot(sourceCheck.containerId, sourceCheck.slot);
        invalidateSlot(targetCheck.containerId, targetCheck.slot);
        markDirty();
        publishTransferEvents(commandName, sourceCheck, targetCheck);
        var snapshots:Array = buildAffectedSnapshots(sourceCheck, targetCheck);
        _busy = false;
        return {success: true, v: 1, operation: commandName, snapshots: snapshots};
    }

    private static function executeSortAndMerge(params:Object):Object {
        var container:Object = params.container;
        if (container == undefined) return fail("invalid_payload");
        var containerId:String = String(container.containerId);
        if (containerId != "仓库") return fail("sort_forbidden");
        var inventory:ArrayInventory = resolveContainer(containerId);
        if (inventory == null) return fail("unsupported_container");
        if (!isWholeNumber(container.offset) || !isWholeNumber(container.limit)) return fail("invalid_payload");
        var offset:Number = Number(container.offset);
        var limit:Number = Number(container.limit);
        if (offset < 0 || offset >= inventory.capacity || limit < 1 || limit > 100) return fail("invalid_payload");
        var methodName:String = String(params.methodName);
        if (_sortMethods[methodName] !== true) return fail("unsupported_sort_method");

        var oldSlots:Array = [];
        for (var slot:Number = 0; slot < inventory.capacity; slot++) {
            var current:Object = inventory.getItem(String(slot));
            oldSlots[slot] = current;
        }

        _busy = true;
        var working:ArrayInventory = new ArrayInventory(null, inventory.capacity);
        if (!working.transactionReplaceAll(inventory.getItemArray())) {
            _busy = false;
            return fail("sort_failed");
        }
        var planned:Array;
        try {
            org.flashNight.arki.item.ItemSortUtil.sortInventory(working, methodName, null);
            planned = working.getItemArray();
        } catch (error) {
            _busy = false;
            return fail("sort_failed");
        }
        if (!sameInventoryMass(inventory.getItemArray(), planned)) {
            _busy = false;
            return fail("sort_failed");
        }
        if (!commitReplaceAll(containerId, inventory, planned)) {
            _busy = false;
            return fail("commit_failed");
        }

        invalidateContainer(containerId);
        bumpContainerEpoch(containerId);
        markDirty();
        publishRebuildEvents(inventory, oldSlots);
        var snapshots:Array = [buildSnapshot(containerId, inventory, offset, limit)];
        _busy = false;
        return {
            success: true,
            v: 1,
            operation: "sortAndMerge",
            methodName: methodName,
            snapshots: snapshots
        };
    }

    private static function commitMove(source:Object, target:Object):Boolean {
        var item:Object = source.item;
        if (!commitSlot(source.containerId, source.inventory, source.slot, null)) return false;
        if (!commitSlot(target.containerId, target.inventory, target.slot, item)) {
            source.inventory.transactionWrite(source.slot, item);
            return false;
        }
        return true;
    }

    private static function commitSwap(source:Object, target:Object):Boolean {
        var sourceItem:Object = source.item;
        var targetItem:Object = target.item;
        if (!commitSlot(source.containerId, source.inventory, source.slot, targetItem)) return false;
        if (!commitSlot(target.containerId, target.inventory, target.slot, sourceItem)) {
            source.inventory.transactionWrite(source.slot, sourceItem);
            return false;
        }
        return true;
    }

    private static function commitMerge(source:Object, target:Object):Boolean {
        var sourceValue:Number = Number(source.item.value);
        var oldTargetValue:Number = Number(target.item.value);
        target.item.value = oldTargetValue + sourceValue;
        if (!commitSlot(source.containerId, source.inventory, source.slot, null)) {
            target.item.value = oldTargetValue;
            return false;
        }
        return true;
    }

    private static function publishTransferEvents(commandName:String, source:Object, target:Object):Void {
        if (commandName == "move") {
            source.inventory.publishTransactionChange(source.slot, "removed");
            target.inventory.publishTransactionChange(target.slot, "added");
        } else if (commandName == "merge") {
            source.inventory.publishTransactionChange(source.slot, "removed");
            target.inventory.publishTransactionChange(target.slot, "value");
        } else {
            source.inventory.publishTransactionChange(source.slot, "replaced");
            target.inventory.publishTransactionChange(target.slot, "replaced");
        }
    }

    private static function publishRebuildEvents(inventory:ArrayInventory, oldSlots:Array):Void {
        for (var slot:Number = 0; slot < inventory.capacity; slot++) {
            var before:Object = oldSlots[slot];
            var after:Object = inventory.getItem(String(slot));
            if (before === after) continue;
            if (before == null) inventory.publishTransactionChange(slot, "added");
            else if (after == null) inventory.publishTransactionChange(slot, "removed");
            else inventory.publishTransactionChange(slot, "replaced");
        }
    }

    private static function sameInventoryMass(before:Array, after:Array):Boolean {
        var beforeMass:Object = buildInventoryMass(before);
        var afterMass:Object = buildInventoryMass(after);
        if (beforeMass == null || afterMass == null) return false;
        var key:String;
        for (key in beforeMass) {
            if (Number(beforeMass[key]) != Number(afterMass[key])) return false;
        }
        for (key in afterMass) {
            if (Number(afterMass[key]) != Number(beforeMass[key])) return false;
        }
        return true;
    }

    private static function buildInventoryMass(items:Array):Object {
        if (!(items instanceof Array)) return null;
        var mass:Object = {};
        for (var i:Number = 0; i < items.length; i++) {
            var item:Object = items[i];
            if (item == null || item.name == undefined || item.value == undefined) return null;
            var numeric:Boolean = typeof item.value == "number";
            var amount:Number = numeric ? Number(item.value) : 1;
            if (isNaN(amount) || amount <= 0) return null;
            var key:String = "$" + (numeric ? "n|" : "o|") + String(item.name);
            var current:Number = Number(mass[key]);
            if (isNaN(current)) current = 0;
            mass[key] = current + amount;
        }
        return mass;
    }

    private static function validateSlotRef(ref:Object, mustOccupy:Boolean, checkCount:Boolean):Object {
        if (ref == undefined) return fail("invalid_payload");
        var containerId:String = String(ref.containerId);
        var inventory:ArrayInventory = resolveContainer(containerId);
        if (inventory == null) return fail("unsupported_container");
        if (!isWholeNumber(ref.slot)) return fail("invalid_payload");
        var slot:Number = Number(ref.slot);
        if (slot < 0 || slot >= inventory.capacity) return fail("invalid_slot");
        var expectedLease:String = String(ref.expectedLease);
        if (expectedLease == "" || leaseArray(_leaseIds, containerId)[slot] != expectedLease) {
            return fail("stale_state");
        }

        var item:Object = inventory.getItem(String(slot));
        if (item !== leaseArray(_leaseRefs, containerId)[slot]) return fail("stale_state");
        if (mustOccupy && item == null) return fail("stale_state");
        if (checkCount) {
            if (item == null || typeof item.value != "number") return fail("stale_state");
            if (Number(item.value) != Number(leaseArray(_leaseCounts, containerId)[slot])) return fail("stale_state");
            if (String(item.name) != String(leaseArray(_leaseMergeKeys, containerId)[slot])) return fail("stale_state");
        }
        return {success: true, containerId: containerId, inventory: inventory, slot: slot, item: item};
    }

    private static function confirmProjectionMatches(slotCheck:Object):Boolean {
        var expected:Object = leaseArray(_leaseConfirm, slotCheck.containerId)[slotCheck.slot];
        var current:Object = buildConfirmProjection(slotCheck.item);
        if (expected == null || current == null) return expected == current;
        return expected.itemKind == current.itemKind
            && expected.displayName == current.displayName
            && Number(expected.quantity) == Number(current.quantity)
            && Number(expected.enhancementLevel) == Number(current.enhancementLevel)
            && String(expected.rarity) == String(current.rarity);
    }

    private static function buildAffectedSnapshots(source:Object, target:Object):Array {
        var snapshots:Array = [];
        var sourceOffset:Number = Math.floor(source.slot / 50) * 50;
        var targetOffset:Number = Math.floor(target.slot / 50) * 50;
        snapshots.push(buildSnapshot(source.containerId, source.inventory, sourceOffset, 50));
        if (source.containerId != target.containerId || sourceOffset != targetOffset) {
            snapshots.push(buildSnapshot(target.containerId, target.inventory, targetOffset, 50));
        }
        return snapshots;
    }

    private static function buildSnapshot(containerId:String, inventory:ArrayInventory, offset:Number, limit:Number):Object {
        var end:Number = Math.min(inventory.capacity, offset + limit);
        var slots:Array = [];
        for (var slot:Number = offset; slot < end; slot++) {
            var item:Object = inventory.getItem(String(slot));
            var lease:String = issueLease(containerId, slot, item);
            var slotSnapshot:Object = {
                physicalSlot: slot,
                occupied: item != null,
                slotLease: lease
            };
            if (item != null) {
                slotSnapshot.item = buildItemProjection(item);
                slotSnapshot.confirmProjection = buildConfirmProjection(item);
            }
            slots.push(slotSnapshot);
        }
        _snapshotSeq++;
        return {
            containerId: containerId,
            capacity: inventory.capacity,
            snapshotSeq: _snapshotSeq,
            containerEpoch: getContainerEpoch(containerId),
            offset: offset,
            limit: end - offset,
            slots: slots
        };
    }

    private static function buildItemProjection(item:Object):Object {
        var data:Object = item != null && typeof item.getData == "function" ? item.getData() : null;
        var isEquipment:Boolean = typeof item.value == "object";
        var quantity:Number = !isEquipment ? Number(item.value) : 1;
        var enhancementLevel:Number = isEquipment ? Number(item.value.level) : 0;
        if (isNaN(enhancementLevel)) enhancementLevel = 0;
        var rarity = data == null ? "" : (data.rarity != undefined ? data.rarity : data.品质);
        var majorType = data == null ? "" : (data.type != undefined ? data.type : data.类型);
        var useName = data == null ? "" : data.use;
        var iconName = data == null || data.icon == undefined ? item.name : data.icon;
        var displayName = data == null || data.displayname == undefined || String(data.displayname).length == 0
            ? item.name : data.displayname;
        var maxEnhancementLevel:Number = EquipmentUtil.getMaxLevel();
        var tierSlotUsed:Boolean = isEquipment && item.value.tier != undefined
            && item.value.tier != null && String(item.value.tier) != "";
        var tierSlotAvailable:Boolean = tierSlotUsed;
        var modSlotCapacity:Number = 0;
        var modSlotUsed:Number = 0;
        var modSlots:Array = [];
        if (isEquipment) {
            if (data != null && data.data != undefined && !isNaN(Number(data.data.modslot))) {
                modSlotCapacity = Math.max(0, Math.floor(Number(data.data.modslot)));
            }
            var mods:Object = item.value.mods;
            if (mods instanceof Array) {
                modSlotUsed = mods.length;
                for (var modIndex:Number = 0; modIndex < mods.length && modIndex < 3; modIndex++) {
                    modSlots.push(buildModSlotProjection(String(mods[modIndex])));
                }
            } else if (mods != undefined && mods != null) {
                for (var modKey:String in mods) {
                    modSlotUsed++;
                    var legacyModValue:Object = mods[modKey];
                    var legacyModName:String = typeof legacyModValue == "string" ? String(legacyModValue) : modKey;
                    if (modSlots.length < 3) modSlots.push(buildModSlotProjection(legacyModName));
                }
            }
            // 生产库存是 BaseItem；测试/未知历史对象缺 getData 时保持关闭，不在 Web 端猜升阶资格。
            if (typeof item.getData == "function") {
                try {
                    var tierOptions:Array = TierSystem.getAvailableTierMaterials(BaseItem(item));
                    if (tierOptions != null && tierOptions.length > 0) tierSlotAvailable = true;
                } catch (tierError) {
                    trace("[InventoryPanelService projection] tier probe failed: " + tierError);
                }
            }
        }
        return {
            name: item.name,
            displayName: displayName,
            icon: iconName,
            majorType: majorType == undefined ? "" : majorType,
            use: useName == undefined ? "" : useName,
            itemKind: isEquipment ? "equipment" : "stack",
            quantity: quantity,
            enhancementLevel: enhancementLevel,
            maxEnhancementLevel: maxEnhancementLevel,
            isMaxEnhancement: isEquipment && enhancementLevel >= maxEnhancementLevel,
            tierSlotAvailable: tierSlotAvailable,
            tierSlotUsed: tierSlotUsed,
            modSlotCapacity: modSlotCapacity,
            modSlotUsed: modSlotUsed,
            modSlots: modSlots,
            rarity: rarity == undefined ? "" : rarity
        };
    }

    /** 将存档中的插件名解析为纯展示投影；未知旧插件使用中性线框菱形，绝不影响库存读取。 */
    private static function buildModSlotProjection(modName:String):Object {
        var modData:Object = EquipmentUtil.modDict == undefined ? null : EquipmentUtil.modDict[modName];
        if (modData == null) {
            return {
                name: modName,
                grade: "unknown",
                gradeLabel: "未知档级",
                gradeColor: "#58636E",
                role: "utility",
                roleLabel: "结构与功能",
                symbol: "diamond-outline"
            };
        }
        return {
            name: modName,
            grade: String(modData.uiGrade || "unknown"),
            gradeLabel: String(modData.uiGradeLabel || "未知档级"),
            gradeColor: String(modData.uiGradeColor || "#58636E"),
            role: String(modData.uiRole || "utility"),
            roleLabel: String(modData.uiRoleLabel || "结构与功能"),
            symbol: String(modData.uiSymbol || "diamond-outline")
        };
    }

    private static function buildConfirmProjection(item:Object):Object {
        if (item == null) return null;
        var projection:Object = buildItemProjection(item);
        return {
            itemKind: projection.itemKind,
            displayName: projection.displayName,
            quantity: projection.quantity,
            enhancementLevel: projection.enhancementLevel,
            rarity: projection.rarity
        };
    }

    private static function issueLease(containerId:String, slot:Number, item:Object):String {
        _leaseSeq++;
        var token:String = _sessionNonce + "." + _leaseSeq;
        leaseArray(_leaseIds, containerId)[slot] = token;
        leaseArray(_leaseRefs, containerId)[slot] = item;
        leaseArray(_leaseCounts, containerId)[slot] = item != null && typeof item.value == "number" ? Number(item.value) : 0;
        leaseArray(_leaseMergeKeys, containerId)[slot] = item == null ? "" : String(item.name);
        leaseArray(_leaseConfirm, containerId)[slot] = buildConfirmProjection(item);
        return token;
    }

    private static function invalidateSlot(containerId:String, slot:Number):Void {
        leaseArray(_leaseIds, containerId)[slot] = null;
        leaseArray(_leaseRefs, containerId)[slot] = null;
        leaseArray(_leaseCounts, containerId)[slot] = null;
        leaseArray(_leaseMergeKeys, containerId)[slot] = null;
        leaseArray(_leaseConfirm, containerId)[slot] = null;
    }

    private static function invalidateContainer(containerId:String):Void {
        _leaseIds[containerId] = [];
        _leaseRefs[containerId] = [];
        _leaseCounts[containerId] = [];
        _leaseMergeKeys[containerId] = [];
        _leaseConfirm[containerId] = [];
    }

    private static function beginSession():Void {
        _sessionCounter++;
        _sessionNonce = "inv" + getTimer() + "." + _sessionCounter;
        _leaseSeq = 0;
        _leaseIds = {};
        _leaseRefs = {};
        _leaseCounts = {};
        _leaseMergeKeys = {};
        _leaseConfirm = {};
    }

    private static function leaseArray(store:Object, containerId:String):Array {
        var values:Array = store[containerId];
        if (!(values instanceof Array)) {
            values = [];
            store[containerId] = values;
        }
        return values;
    }

    private static function resolveContainer(containerId:String):ArrayInventory {
        if (containerId != "背包" && containerId != "仓库") return null;
        if (_root.物品栏 == undefined) return null;
        var inventory:ArrayInventory = _root.物品栏[containerId];
        if (!(inventory instanceof ArrayInventory)) return null;
        return inventory;
    }

    private static function getContainerEpoch(containerId:String):Number {
        var current = _containerEpochs[containerId];
        if (current == undefined || isNaN(Number(current))) {
            current = 1;
            _containerEpochs[containerId] = current;
        }
        return Number(current);
    }

    private static function bumpContainerEpoch(containerId:String):Number {
        var next:Number = getContainerEpoch(containerId) + 1;
        _containerEpochs[containerId] = next;
        return next;
    }

    private static function commitSlot(containerId:String, inventory:ArrayInventory, slot:Number, item:Object):Boolean {
        if (_testFailContainerId == containerId && (_testFailSlot < 0 || _testFailSlot == slot)) {
            _testFailContainerId = "";
            _testFailSlot = -1;
            return false;
        }
        return inventory.transactionWrite(slot, item);
    }

    private static function commitReplaceAll(containerId:String, inventory:ArrayInventory, orderedItems:Array):Boolean {
        if (_testFailContainerId == containerId && _testFailSlot < 0) {
            _testFailContainerId = "";
            _testFailSlot = -1;
            return false;
        }
        return inventory.transactionReplaceAll(orderedItems);
    }

    private static function markDirty():Void {
        if (_root.存档系统 != undefined) _root.存档系统.dirtyMark = true;
    }

    private static function isWholeNumber(value):Boolean {
        return typeof value == "number" && !isNaN(value) && Math.floor(value) == value;
    }

    private static function fail(errorCode:String):Object {
        return {success: false, error: errorCode};
    }

    private static function sendResponse(response:Object):Void {
        if (_root.server == undefined || _root.server.sendSocketMessage == undefined) return;
        _root.server.sendSocketMessage(_json.stringify(response));
    }

    /** TestLoader 专用：下一次指定槽的提交返回 false，用于证明失败回滚无部分写。 */
    public static function testOnlyFailNextCommit(containerId:String, slot:Number):Void {
        _testFailContainerId = containerId;
        _testFailSlot = slot;
    }

    /** TestLoader 专用：隔离静态 lease/session/guard。 */
    public static function testOnlyReset():Void {
        _busy = false;
        _containerEpochs = {};
        _testFailContainerId = "";
        _testFailSlot = -1;
        beginSession();
    }
}
