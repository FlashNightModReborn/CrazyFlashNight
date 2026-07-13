import org.flashNight.arki.item.itemCollection.ArrayInventory;

import org.flashNight.gesh.tooltip.TooltipComposer;
import org.flashNight.arki.item.BaseItem;
import org.flashNight.arki.item.EquipmentUtil;
import org.flashNight.arki.item.equipment.TierSystem;

/**
 * Web 双栏工作台的 inventory-domain 权威服务。
 *
 * v1 开放：全局分类窗口 snapshot、lease-bound tooltip、背包 discard、背包↔仓库/战备箱 whole-slot
 * move/merge/swap，以及背包/仓库整容器、战备箱已解锁前缀的 sortAndMerge。战备箱只暴露剧情当前
 * 解锁的槽位窗口，物理容量不等于可访问容量。所有写入都在同一重入守卫内完成：双端 lease 校验 →
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
    private static var _facetCache:Object = {};
    private static var _leaseIds:Object = {};
    private static var _leaseRefs:Object = {};
    private static var _leaseCounts:Object = {};
    private static var _leaseMergeKeys:Object = {};
    private static var _leaseConfirm:Object = {};
    private static var _sortMethods:Object = {
        byType: true, byUse: true, byPrice: true, byLevel: true,
        byID: true, byName: true, byValue: true, byTime: true
    };
    private static var _filterKeys:Object = {
        all: true, weapon: true, armor: true, consumable: true,
        material: true, other: true
    };
    private static var _filterMajors:Object = {
        all: true, weapon: true, armor: true, consumable: true,
        material: true, collection: true, other: true
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
        _root.gameCommands["inventoryAutoTransfer"] = function(params) {
            org.flashNight.arki.item.InventoryPanelService.handle("autoTransfer", params);
        };
        _root.gameCommands["inventorySortAndMerge"] = function(params) {
            org.flashNight.arki.item.InventoryPanelService.handle("sortAndMerge", params);
        };
        _root.gameCommands["openInventoryWorkbench"] = function(params) {
            return org.flashNight.arki.item.InventoryPanelService.requestOpenWorkbench(params);
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
        if (commandName == "autoTransfer") return executeAutoTransfer(params);
        if (commandName == "sortAndMerge") return executeSortAndMerge(params);
        return fail("unsupported_cmd");
    }

    /**
     * 世界内稳定入口：只允许枚举 profile，不允许 XFL 直接拼 containerId 或 socket JSON。
     * warehouse = 宿舍背包—仓库；battlebox = 刘海/后勤背包—战备箱。
     */
    public static function requestOpenWorkbench(params:Object):Boolean {
        var profile:String = params == undefined || params.profile == undefined
            ? "" : String(params.profile);
        if (profile != "warehouse" && profile != "battlebox") return false;
        if (_root.server == undefined || _root.server.sendSocketMessage == undefined) return false;
        if (_json == undefined) _json = new LiteJSON();
        var source:String = params == undefined || params.source == undefined
            ? "inventory_workbench" : String(params.source);
        return _root.server.sendSocketMessage(_json.stringify({
            task: "panel_request",
            panel: "workbench",
            source: source,
            initData: {profile: profile}
        }));
    }

    private static function executeSnapshot(params:Object):Object {
        var windowCheck:Object = validateWindowRequests(params.requests);
        if (!windowCheck.success) return windowCheck;

        // 每次显式读取都开启新的 snapshot-local lease session；旧 Web 会话 token 立即失效。
        beginSession();
        var snapshots:Array = buildWindowSnapshots(windowCheck.normalized);
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
            // LiteJSON 不转义字符串中的双引号；改用 HTML 等价的单引号属性，
            // 避免 &quot; 被浏览器解析为属性值本身的一对引号而丢失字体样式。
            descHTML: descHTML.split('"').join("'"),
            introHTML: introHTML.split('"').join("'")
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
        var snapshots:Array = [buildSnapshot("背包", sourceCheck.inventory, 0, Math.min(50, sourceCheck.inventory.capacity), "all")];
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

    /**
     * 快速转移只接收来源 lease 与目标容器，不接收目标槽位。目标落位由 AS2 在完整可访问范围内
     * 按“同名数字堆叠优先，其次首个空槽”决定；绝不为了腾位自动交换异类物品。
     * windows 只描述 Web 当前视图，提交后按这些窗口重铸 lease，既不泄漏落位权威也不强制翻页。
     */
    private static function executeAutoTransfer(params:Object):Object {
        var sourceCheck:Object = validateSlotRef(params.source, true, false);
        if (!sourceCheck.success) return sourceCheck;

        var targetContainerId:String = params.targetContainerId == undefined
            ? "" : String(params.targetContainerId);
        if (!isAllowedAutoTransferPair(sourceCheck.containerId, targetContainerId)) {
            return fail("transfer_forbidden");
        }
        if (String(params.policy) != "mergeThenEmpty") return fail("unsupported_policy");

        var windowCheck:Object = validateWindowRequests(params.windows);
        if (!windowCheck.success) return windowCheck;
        var seenSource:Boolean = false;
        var seenTarget:Boolean = false;
        var seenContainers:Object = {};
        for (var windowIndex:Number = 0; windowIndex < windowCheck.normalized.length; windowIndex++) {
            var windowEntry:Object = windowCheck.normalized[windowIndex];
            if (seenContainers[windowEntry.containerId] === true) return fail("invalid_payload");
            seenContainers[windowEntry.containerId] = true;
            if (windowEntry.containerId == sourceCheck.containerId) seenSource = true;
            else if (windowEntry.containerId == targetContainerId) seenTarget = true;
            else return fail("invalid_payload");
        }
        if (!seenSource || !seenTarget) return fail("invalid_payload");

        var targetInventory:ArrayInventory = resolveContainer(targetContainerId);
        if (targetInventory == null) return fail("unsupported_container");
        var targetCapacity:Number = getAccessibleCapacity(targetContainerId);
        if (targetCapacity <= 0) return fail("slot_locked");

        var sourceIsStack:Boolean = typeof sourceCheck.item.value == "number";
        var targetSlot:Number = -1;
        var firstEmptySlot:Number = -1;
        var targetItem:Object = null;
        for (var slot:Number = 0; slot < targetCapacity; slot++) {
            var candidate:Object = targetInventory.getItem(String(slot));
            if (candidate == null) {
                if (firstEmptySlot < 0) firstEmptySlot = slot;
            } else if (sourceIsStack && typeof candidate.value == "number"
                    && candidate.name == sourceCheck.item.name) {
                targetSlot = slot;
                targetItem = candidate;
                break;
            }
        }
        var operation:String = "merge";
        if (targetSlot < 0) {
            if (firstEmptySlot < 0) return fail("target_full");
            targetSlot = firstEmptySlot;
            targetItem = null;
            operation = "move";
        }

        var targetCheck:Object = {
            success: true,
            containerId: targetContainerId,
            inventory: targetInventory,
            slot: targetSlot,
            item: targetItem
        };
        _busy = true;
        var committed:Boolean = operation == "merge"
            ? commitMerge(sourceCheck, targetCheck)
            : commitMove(sourceCheck, targetCheck);
        if (!committed) {
            _busy = false;
            return fail("commit_failed");
        }

        invalidateSlot(sourceCheck.containerId, sourceCheck.slot);
        invalidateSlot(targetCheck.containerId, targetCheck.slot);
        markDirty();
        publishTransferEvents(operation, sourceCheck, targetCheck);
        var snapshots:Array = buildWindowSnapshots(windowCheck.normalized);
        _busy = false;
        return {
            success: true,
            v: 1,
            operation: operation,
            policy: "mergeThenEmpty",
            destination: {containerId: targetContainerId, slot: targetSlot},
            snapshots: snapshots
        };
    }

    private static function executeSortAndMerge(params:Object):Object {
        var container:Object = params.container;
        if (container == undefined) return fail("invalid_payload");
        var containerId:String = String(container.containerId);
        if (containerId != "背包" && containerId != "仓库" && containerId != "战备箱") return fail("sort_forbidden");
        var inventory:ArrayInventory = resolveContainer(containerId);
        if (inventory == null) return fail("unsupported_container");
        if (!isWholeNumber(container.offset) || !isWholeNumber(container.limit)) return fail("invalid_payload");
        var offset:Number = Number(container.offset);
        var limit:Number = Number(container.limit);
        if (offset < 0 || offset >= inventory.capacity || limit < 1 || limit > 100) return fail("invalid_payload");
        var methodName:String = String(params.methodName);
        if (_sortMethods[methodName] !== true) return fail("unsupported_sort_method");
        var filterKey:String = container.filterKey == undefined ? "all" : String(container.filterKey);
        if (_filterKeys[filterKey] !== true) return fail("unsupported_filter");
        var filterSpec:Object = normalizeFilterSpec(container.filterSpec);
        if (container.filterSpec != undefined && filterSpec == null) return fail("unsupported_filter");
        if (filterSpec != null && !filterSpecMatchesKey(filterKey, filterSpec)) return fail("unsupported_filter");
        var sortCapacity:Number = getAccessibleCapacity(containerId);
        if (sortCapacity <= 0) return fail("sort_forbidden");

        var oldSlots:Array = [];
        var scopeItems:Array = [];
        for (var slot:Number = 0; slot < inventory.capacity; slot++) {
            var current:Object = inventory.getItem(String(slot));
            oldSlots[slot] = current;
            if (slot < sortCapacity && current != null) scopeItems.push(current);
        }

        _busy = true;
        var working:ArrayInventory = new ArrayInventory(null, sortCapacity);
        if (!working.transactionReplaceAll(scopeItems)) {
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
        if (!sameInventoryMass(scopeItems, planned)) {
            _busy = false;
            return fail("sort_failed");
        }
        if (!commitReplacePrefix(containerId, inventory, planned, sortCapacity)) {
            _busy = false;
            return fail("commit_failed");
        }

        invalidateContainer(containerId);
        bumpContainerEpoch(containerId);
        markDirty();
        publishRebuildEvents(inventory, oldSlots);
        var snapshots:Array = [buildSnapshot(containerId, inventory, offset, limit, filterKey, filterSpec)];
        _busy = false;
        return {
            success: true,
            v: 1,
            operation: "sortAndMerge",
            methodName: methodName,
            sortedCapacity: sortCapacity,
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

    private static function validateWindowRequests(requests:Array):Object {
        if (!(requests instanceof Array) || requests.length < 1 || requests.length > 4) {
            return fail("invalid_payload");
        }
        var normalized:Array = [];
        for (var i:Number = 0; i < requests.length; i++) {
            var request:Object = requests[i];
            var containerId:String = request == undefined ? "" : String(request.containerId);
            var filterKey:String = request == undefined || request.filterKey == undefined
                ? "all" : String(request.filterKey);
            var filterSpec:Object = request == undefined ? null : normalizeFilterSpec(request.filterSpec);
            var inventory:ArrayInventory = resolveContainer(containerId);
            if (inventory == null) return fail("unsupported_container");
            if (_filterKeys[filterKey] !== true) return fail("unsupported_filter");
            if (request != undefined && request.filterSpec != undefined && filterSpec == null) return fail("unsupported_filter");
            if (filterSpec != null && !filterSpecMatchesKey(filterKey, filterSpec)) return fail("unsupported_filter");
            if (!isWholeNumber(request.offset) || !isWholeNumber(request.limit)) return fail("invalid_payload");
            var offset:Number = Number(request.offset);
            var limit:Number = Number(request.limit);
            if (offset < 0 || offset >= inventory.capacity || limit < 1 || limit > 100) {
                return fail("invalid_payload");
            }
            var accessibleCapacity:Number = getAccessibleCapacity(containerId);
            if ((accessibleCapacity <= 0 && offset != 0)
                || (accessibleCapacity > 0 && offset >= accessibleCapacity)) {
                return fail("slot_locked");
            }
            normalized.push({
                containerId: containerId,
                inventory: inventory,
                offset: offset,
                limit: limit,
                filterKey: filterKey,
                filterSpec: filterSpec
            });
        }
        return {success: true, normalized: normalized};
    }

    private static function buildWindowSnapshots(normalized:Array):Array {
        var snapshots:Array = [];
        for (var i:Number = 0; i < normalized.length; i++) {
            var entry:Object = normalized[i];
            snapshots.push(buildSnapshot(
                entry.containerId,
                entry.inventory,
                entry.offset,
                entry.limit,
                entry.filterKey,
                entry.filterSpec
            ));
        }
        return snapshots;
    }

    private static function isAllowedAutoTransferPair(sourceContainerId:String, targetContainerId:String):Boolean {
        if (sourceContainerId == "背包") {
            return targetContainerId == "仓库" || targetContainerId == "战备箱";
        }
        if (targetContainerId != "背包") return false;
        return sourceContainerId == "仓库" || sourceContainerId == "战备箱";
    }

    private static function validateSlotRef(ref:Object, mustOccupy:Boolean, checkCount:Boolean):Object {
        if (ref == undefined) return fail("invalid_payload");
        var containerId:String = String(ref.containerId);
        var inventory:ArrayInventory = resolveContainer(containerId);
        if (inventory == null) return fail("unsupported_container");
        if (!isWholeNumber(ref.slot)) return fail("invalid_payload");
        var slot:Number = Number(ref.slot);
        if (slot < 0 || slot >= inventory.capacity) return fail("invalid_slot");
        if (slot >= getAccessibleCapacity(containerId)) return fail("slot_locked");
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

    /**
     * 供显式领域命令（NPC 金币出售、后续 equip）复用 owned-slot lease。
     * 调用方仍须自行持有领域重入守卫，并在同一同步调用栈内完成校验与写入。
     */
    public static function validateExternalSlotRef(ref:Object, checkCount:Boolean):Object {
        return validateSlotRef(ref, true, checkCount == true);
    }

    /** 显式领域命令提交后，使被写槽位的旧 lease 失效。 */
    public static function invalidateExternalSlot(containerId:String, slot:Number):Void {
        invalidateSlot(containerId, slot);
    }

    /** 显式领域命令完成后重投影可见窗口，不开启新的 inventory session。 */
    public static function buildExternalSnapshot(containerId:String, offset:Number, limit:Number):Object {
        var inventory:ArrayInventory = resolveContainer(containerId);
        if (inventory == null) return null;
        return buildSnapshot(containerId, inventory, offset, limit, "all");
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
        var sourcePageSize:Number = getPageSizeHint(source.containerId);
        var targetPageSize:Number = getPageSizeHint(target.containerId);
        var sourceOffset:Number = Math.floor(source.slot / sourcePageSize) * sourcePageSize;
        var targetOffset:Number = Math.floor(target.slot / targetPageSize) * targetPageSize;
        snapshots.push(buildSnapshot(source.containerId, source.inventory, sourceOffset, sourcePageSize, "all"));
        if (source.containerId != target.containerId || sourceOffset != targetOffset) {
            snapshots.push(buildSnapshot(target.containerId, target.inventory, targetOffset, targetPageSize, "all"));
        }
        return snapshots;
    }

    private static function buildSnapshot(containerId:String, inventory:ArrayInventory, offset:Number, limit:Number, filterKey:String, filterSpec:Object):Object {
        var accessibleCapacity:Number = getAccessibleCapacity(containerId);
        if (_filterKeys[filterKey] !== true) filterKey = "all";
        filterSpec = normalizeFilterSpec(filterSpec);
        var slots:Array = [];
        var viewCapacity:Number = accessibleCapacity;
        var effectiveOffset:Number = offset;
        var slot:Number;
        var item:Object;

        if (filterKey == "all") {
            if (viewCapacity <= 0) effectiveOffset = 0;
            else if (effectiveOffset >= viewCapacity) {
                effectiveOffset = Math.floor((viewCapacity - 1) / limit) * limit;
            }
            var end:Number = Math.min(accessibleCapacity, effectiveOffset + limit);
            for (slot = effectiveOffset; slot < end; slot++) {
                item = inventory.getItem(String(slot));
                slots.push(buildSlotSnapshot(containerId, slot, item));
            }
        } else {
            var matches:Array = [];
            for (slot = 0; slot < accessibleCapacity; slot++) {
                item = inventory.getItem(String(slot));
                if (item != null && itemMatchesFilter(item, filterKey, filterSpec)) matches.push(slot);
            }
            viewCapacity = matches.length;
            if (viewCapacity <= 0) effectiveOffset = 0;
            else if (effectiveOffset >= viewCapacity) {
                effectiveOffset = Math.floor((viewCapacity - 1) / limit) * limit;
            }
            var matchEnd:Number = Math.min(viewCapacity, effectiveOffset + limit);
            for (var matchIndex:Number = effectiveOffset; matchIndex < matchEnd; matchIndex++) {
                slot = Number(matches[matchIndex]);
                item = inventory.getItem(String(slot));
                slots.push(buildSlotSnapshot(containerId, slot, item));
            }
        }
        _snapshotSeq++;
        var facetSummary:Object = buildFilterFacetSummary(containerId, inventory, accessibleCapacity);
        var snapshot:Object = {
            containerId: containerId,
            capacity: inventory.capacity,
            accessibleCapacity: accessibleCapacity,
            viewCapacity: viewCapacity,
            filterKey: filterKey,
            pageSizeHint: getPageSizeHint(containerId),
            locked: accessibleCapacity <= 0,
            snapshotSeq: _snapshotSeq,
            containerEpoch: getContainerEpoch(containerId),
            offset: effectiveOffset,
            limit: slots.length,
            slots: slots,
            filterFacets: facetSummary.facets,
            filterItemCount: facetSummary.itemCount
        };
        if (filterSpec != null) snapshot.filterSpec = filterSpec;
        return snapshot;
    }

    private static function buildSlotSnapshot(containerId:String, slot:Number, item:Object):Object {
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
        return slotSnapshot;
    }

    private static function itemMatchesFilter(item:Object, filterKey:String, filterSpec:Object):Boolean {
        if (filterSpec != null) {
            var taxonomy:Object = itemTaxonomy(item);
            var major:String = String(filterSpec.major || "all");
            if (major != "all" && taxonomy.major != major) return false;
            if (filterSpec.use != undefined && String(filterSpec.use) != taxonomy.use) return false;
            if (filterSpec.subtype != undefined && String(filterSpec.subtype) != taxonomy.subtype) return false;
            return true;
        }
        if (filterKey == "all") return true;
        var data:Object = item != null && typeof item.getData == "function"
            ? item.getData() : org.flashNight.arki.item.ItemUtil.getItemData(item.name);
        var majorType:String = data == null ? "" : String(data.type != undefined ? data.type : data.类型);
        var useName:String = data == null || data.use == undefined ? "" : String(data.use);
        if (filterKey == "weapon") return majorType == "武器";
        if (filterKey == "armor") return majorType == "防具";
        if (filterKey == "consumable") return majorType == "消耗品";
        if (filterKey == "material") return majorType == "材料" || (majorType == "收集品" && useName == "材料");
        return majorType != "武器" && majorType != "防具" && majorType != "消耗品"
            && majorType != "材料" && !(majorType == "收集品" && useName == "材料");
    }

    private static function normalizeFilterSpec(input:Object):Object {
        if (input == undefined || input == null) return null;
        var major:String = String(input.major == undefined ? "all" : input.major);
        var useName:String = input.use == undefined ? "" : String(input.use);
        var subtype:String = input.subtype == undefined ? "" : String(input.subtype);
        if (_filterMajors[major] !== true || !safeFilterValue(useName) || !safeFilterValue(subtype)) return null;
        if (major == "all" && (useName != "" || subtype != "")) return null;
        if (subtype != "" && (major != "weapon" || useName == "")) return null;
        var normalized:Object = {major: major};
        if (useName != "") normalized.use = useName;
        if (subtype != "") normalized.subtype = subtype;
        return normalized;
    }

    private static function filterSpecMatchesKey(filterKey:String, filterSpec:Object):Boolean {
        if (filterSpec == null) return true;
        var major:String = String(filterSpec.major || "all");
        var expectedKey:String = major == "collection" ? "other" : major;
        return filterKey == expectedKey;
    }

    private static function safeFilterValue(value:String):Boolean {
        if (value == undefined || value.length > 64) return false;
        for (var i:Number = 0; i < value.length; i++) {
            var code:Number = value.charCodeAt(i);
            if (code < 32 || code == 127) return false;
        }
        return true;
    }

    private static function itemTaxonomy(item:Object):Object {
        var data:Object = item != null && typeof item.getData == "function"
            ? item.getData() : org.flashNight.arki.item.ItemUtil.getItemData(item.name);
        var typeName:String = data == null ? "" : String(data.type != undefined ? data.type : data.类型);
        var useName:String = data == null || data.use == undefined || String(data.use) == "" ? "其他" : String(data.use);
        var major:String = "other";
        var label:String = "其他";
        if (typeName == "武器") { major = "weapon"; label = "武器"; }
        else if (typeName == "防具") { major = "armor"; label = "防具"; }
        else if (typeName == "消耗品") { major = "consumable"; label = "消耗品"; }
        else if (typeName == "材料") { major = "material"; label = "材料"; }
        else if (typeName == "收集品") { major = "collection"; label = "收集品"; }
        var subtype:String = "";
        if (major == "weapon" && data != null) {
            if (data.weapontype != undefined) subtype = String(data.weapontype);
            else if (data.weaponType != undefined) subtype = String(data.weaponType);
            else if (data.actiontype != undefined) subtype = String(data.actiontype);
            else if (data.actionType != undefined) subtype = String(data.actionType);
            if (subtype == "") subtype = "其他";
        }
        return {major:major, label:label, use:useName, subtype:subtype};
    }

    private static function buildFilterFacetSummary(containerId:String, inventory:ArrayInventory, accessibleCapacity:Number):Object {
        var epoch:Number = getContainerEpoch(containerId);
        var cached:Object = _facetCache[containerId];
        if (cached != undefined && Number(cached.epoch) == epoch
                && Number(cached.accessibleCapacity) == accessibleCapacity
                && facetCacheMatchesInventory(cached, inventory, accessibleCapacity)) return cached;
        var facets:Array = [];
        var itemRefs:Array = [];
        var itemCount:Number = 0;
        for (var slot:Number = 0; slot < accessibleCapacity; slot++) {
            var item:Object = inventory.getItem(String(slot));
            itemRefs[slot] = item;
            if (item == null) continue;
            itemCount++;
            var taxonomy:Object = itemTaxonomy(item);
            var majorNode:Object = facetNode(facets, taxonomy.major, taxonomy.label);
            majorNode.count++;
            var useNode:Object = facetNode(majorNode.children, taxonomy.use, taxonomy.use);
            useNode.count++;
            if (taxonomy.subtype != "") {
                var subtypeNode:Object = facetNode(useNode.children, taxonomy.subtype, taxonomy.subtype);
                subtypeNode.count++;
            }
        }
        cached = {
            epoch:epoch,
            accessibleCapacity:accessibleCapacity,
            itemRefs:itemRefs,
            facets:facets,
            itemCount:itemCount
        };
        _facetCache[containerId] = cached;
        return cached;
    }

    /**
     * 外部游戏逻辑也会通过 ArrayInventory.add/remove 改容器，未必经过 inventory-domain。
     * 缓存命中前按槽位对象引用做轻量校验，避免 facet/count 在拾取、购买或跨容器移动后陈旧。
     */
    private static function facetCacheMatchesInventory(cached:Object, inventory:ArrayInventory, accessibleCapacity:Number):Boolean {
        var itemRefs:Array = cached == undefined ? null : cached.itemRefs;
        if (!(itemRefs instanceof Array) || itemRefs.length != accessibleCapacity) return false;
        for (var slot:Number = 0; slot < accessibleCapacity; slot++) {
            if (itemRefs[slot] !== inventory.getItem(String(slot))) return false;
        }
        return true;
    }

    private static function facetNode(nodes:Array, id:String, label:String):Object {
        for (var i:Number = 0; i < nodes.length; i++) {
            if (String(nodes[i].id) == id) return nodes[i];
        }
        var node:Object = {id:id, label:label, count:0, children:[]};
        nodes.push(node);
        return node;
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
        var actionType = data == null ? "" : (data.actiontype != undefined ? data.actiontype : data.actionType);
        var weaponType = data == null ? "" : (data.weapontype != undefined ? data.weapontype : data.weaponType);
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
            actionType: actionType == undefined ? "" : actionType,
            weaponType: weaponType == undefined ? "" : weaponType,
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
        delete _facetCache[containerId];
        leaseArray(_leaseIds, containerId)[slot] = null;
        leaseArray(_leaseRefs, containerId)[slot] = null;
        leaseArray(_leaseCounts, containerId)[slot] = null;
        leaseArray(_leaseMergeKeys, containerId)[slot] = null;
        leaseArray(_leaseConfirm, containerId)[slot] = null;
    }

    private static function invalidateContainer(containerId:String):Void {
        delete _facetCache[containerId];
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
        if (containerId != "背包" && containerId != "仓库" && containerId != "战备箱") return null;
        if (_root.物品栏 == undefined) return null;
        var inventory:ArrayInventory = _root.物品栏[containerId];
        if (!(inventory instanceof ArrayInventory)) return null;
        return inventory;
    }

    /**
     * 返回 Web 与旧 Flash 仓库界面共同采用的权威可访问容量。
     * 战备箱物理容量固定用于存档兼容；剧情只逐页开放前 0..240 个槽位。
     */
    public static function getAccessibleCapacity(containerId:String):Number {
        var inventory:ArrayInventory = resolveContainer(containerId);
        if (inventory == null) return 0;
        if (containerId != "战备箱") return inventory.capacity;

        var mainProgress:Number = Number(_root.主线任务进度);
        if (isNaN(mainProgress) || mainProgress <= 13) return 0;

        var pages:Number = 1;
        var challengeProgress:Number = NaN;
        if (_root.task_chains_progress != undefined) {
            challengeProgress = Number(_root.task_chains_progress.挑战);
        }
        if (!isNaN(challengeProgress)) {
            if (challengeProgress > 0) pages++;
            if (challengeProgress > 2) pages++;
        }
        if (mainProgress > 77) pages += 2;
        if (_root.基建系统 != undefined
            && _root.基建系统.infrastructure != undefined
            && _root.基建系统.infrastructure.越野车) {
            pages++;
        }
        return Math.min(inventory.capacity, pages * getPageSizeHint(containerId));
    }

    private static function getPageSizeHint(containerId:String):Number {
        return containerId == "战备箱" ? 40 : 50;
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

    private static function commitReplacePrefix(containerId:String, inventory:ArrayInventory, orderedItems:Array, prefixCapacity:Number):Boolean {
        if (_testFailContainerId == containerId && _testFailSlot < 0) {
            _testFailContainerId = "";
            _testFailSlot = -1;
            return false;
        }
        return inventory.transactionReplacePrefix(orderedItems, prefixCapacity);
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
        _facetCache = {};
        _testFailContainerId = "";
        _testFailSlot = -1;
        beginSession();
    }
}
