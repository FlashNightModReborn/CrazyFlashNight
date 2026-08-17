import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.item.InventoryPanelService;
import org.flashNight.arki.item.MaterialArchiveProjector;
import org.flashNight.arki.task.TaskUtil;
import org.flashNight.gesh.object.ObjectUtil;

/**
 * 合成标记、任务物资与跨容器持有量的唯一 AS2 权威。
 * 存档只保存稳定 recipeId → plannedCrafts；高亮、缺口、来源和持有量
 * 每次 snapshot 从当前配方、进行中任务、物品栏与商店目录重新派生。
 */
class org.flashNight.arki.item.ProcurementPlanService {
    private static var STORE_VERSION:Number = 1;
    private static var MAX_PLANNED_CRAFTS:Number = 99;
    private static var MAX_SAFE_REVISION:Number = 9007199254740991;
    private static var MAX_EXPECTED_REVISION:Number = 9007199254740990;
    private static var MAX_REASONS:Number = 64;
    private static var MAX_SOURCES:Number = 32;
    private static var _purchaseSourceIndexBuildCount:Number = 0;
    private static var _ownedIndexBuildCount:Number = 0;

    public static function getRevision():Number {
        return Number(readStore().revision);
    }

    public static function getPlannedCrafts(recipeId:String):Number {
        var value:Number = Number(readStore().recipes[recipeId]);
        return validWhole(value, 1, MAX_PLANNED_CRAFTS) ? value : 0;
    }

    public static function setPlan(params:Object):Object {
        if (!hasExactOwnKeys(params,
                ["v", "recipeId", "plannedCrafts", "expectedRevision"])
                || typeof params.v != "number"
                || Number(params.v) != STORE_VERSION
                || typeof params.recipeId != "string"
                || typeof params.plannedCrafts != "number"
                || typeof params.expectedRevision != "number") return fail("invalid_payload");
        var recipeId:String = String(params.recipeId);
        var plannedCrafts:Number = Number(params.plannedCrafts);
        var expectedRevision:Number = Number(params.expectedRevision);
        if (!validRecipeId(recipeId)
                || !validWhole(plannedCrafts, 0, MAX_PLANNED_CRAFTS)
                || !validWhole(expectedRevision, 0, MAX_EXPECTED_REVISION)) {
            return fail("invalid_payload");
        }
        if (findRecipe(recipeId) == null) return fail("recipe_not_found");
        var current:Object = readStore();
        if (Number(current.revision) != expectedRevision) return fail("stale_state");
        var recipes:Object = clonePlanEntries(current.recipes);
        if (plannedCrafts == 0) delete recipes[recipeId];
        else recipes[recipeId] = plannedCrafts;
        var next:Object = {v:STORE_VERSION, revision:expectedRevision + 1, recipes:recipes};
        writeStore(next);
        return {success:true, v:STORE_VERSION, revision:next.revision,
            recipeId:recipeId, plannedCrafts:plannedCrafts};
    }

    /**
     * 真实 Host → Flash 写线。传输字段与业务字段都必须精确存在，随后只把
     * 业务投影交给 setPlan；不能让 transport envelope 污染领域校验。
     */
    public static function setPlanFromWire(params:Object):Object {
        if (!hasExactOwnKeys(params,
                ["task", "action", "callId", "v", "recipeId",
                    "plannedCrafts", "expectedRevision"])
                || typeof params.task != "string" || params.task !== "cmd"
                || typeof params.action != "string"
                || params.action !== "craftingPlanSet"
                || typeof params.callId != "number"
                || !validWhole(Number(params.callId), 1, 2147483647)) {
            return fail("invalid_payload");
        }
        return setPlan({
            v:params.v,
            recipeId:params.recipeId,
            plannedCrafts:params.plannedCrafts,
            expectedRevision:params.expectedRevision
        });
    }

    /** 成功合成后按实际 craftCount 精确冲减；零时移除标记。 */
    public static function consumeCompleted(recipeId:String, craftCount:Number):Object {
        var current:Object = readStore();
        var planned:Number = Number(current.recipes[recipeId]);
        if (!validWhole(planned, 1, MAX_PLANNED_CRAFTS)
                || !validWhole(craftCount, 1, MAX_PLANNED_CRAFTS)) {
            return {revision:Number(current.revision), plannedCrafts:0, changed:false};
        }
        var remaining:Number = Math.max(0, planned - craftCount);
        var recipes:Object = clonePlanEntries(current.recipes);
        if (remaining == 0) delete recipes[recipeId];
        else recipes[recipeId] = remaining;
        var next:Object = {v:STORE_VERSION, revision:Number(current.revision) + 1,
            recipes:recipes};
        writeStore(next);
        return {revision:next.revision, plannedCrafts:remaining, changed:true};
    }

    public static function buildPlanSummary():Object {
        return {revision:getRevision(), directShopNavigation:hasDirectShopNavigation()};
    }

    public static function testOnlyResetStats():Void {
        _purchaseSourceIndexBuildCount = 0;
        _ownedIndexBuildCount = 0;
    }

    public static function testOnlyStats():Object {
        return {purchaseSourceIndexes:_purchaseSourceIndexBuildCount,
            ownedIndexes:_ownedIndexBuildCount};
    }

    /** 产物持有量：仓库与战备箱锁定尾部明确排除。 */
    public static function buildOwnedSummary(itemName:String, ownedIndex:Object):Object {
        var summary:Object = buildOwnedSummaryInternal(itemName, ownedIndex);
        return {bag:Number(summary.bag), drug:Number(summary.drug),
            equipped:Number(summary.equipped), battleBox:Number(summary.battleBox),
            material:Number(summary.material), information:Number(summary.information),
            usable:Number(summary.usable), total:Number(summary.total),
            usableMaxEnhancement:Number(summary.usableMaxEnhancement),
            totalMaxEnhancement:Number(summary.totalMaxEnhancement)};
    }

    /** 采购缺口还需要装备栏/战备箱各自的强化上限；这些内部字段不扩张配方 owned wire。 */
    private static function buildOwnedSummaryInternal(itemName:String,
            ownedIndex:Object):Object {
        if (ownedIndex != null) {
            return cloneOwnedSummary(ownedIndex[itemName]);
        }
        var result:Object = {bag:0, drug:0, equipped:0, battleBox:0,
            material:0, information:0, usable:0, total:0,
            usableMaxEnhancement:0, equippedMaxEnhancement:0,
            battleBoxMaxEnhancement:0, totalMaxEnhancement:0};
        if (!ItemUtil.isItem(itemName)) return result;
        if (ItemUtil.isMaterial(itemName)) {
            result.material = collectionValue(_root.收集品栏 == undefined
                ? null : _root.收集品栏.材料, itemName);
            result.usable = result.material; result.total = result.material;
            return result;
        }
        if (ItemUtil.isInformation(itemName)) {
            result.information = collectionValue(_root.收集品栏 == undefined
                ? null : _root.收集品栏.情报, itemName);
            result.usable = result.information; result.total = result.information;
            return result;
        }
        if (_root.物品栏 == undefined) return result;
        accumulateArray(result, "bag", _root.物品栏.背包, itemName, -1);
        accumulateArray(result, "drug", _root.物品栏.药剂栏, itemName, -1);
        accumulateEquipment(result, _root.物品栏.装备栏, itemName);
        accumulateArray(result, "battleBox", _root.物品栏.战备箱, itemName,
            InventoryPanelService.getAccessibleCapacity("战备箱"));
        result.usable = Number(result.bag) + Number(result.drug);
        result.total = result.usable + Number(result.equipped) + Number(result.battleBox);
        return result;
    }

    /**
     * 单次扫描合成可见的全部持有容器。调用方必须把返回值限定在同一次
     * snapshot/preview 内复用，不能跨帧缓存成第二份存档真值。
     */
    public static function buildOwnedIndex():Object {
        _ownedIndexBuildCount++;
        var byItem:Object = {};
        indexCollection(byItem, _root.收集品栏 == undefined
            ? null : _root.收集品栏.材料, "material");
        indexCollection(byItem, _root.收集品栏 == undefined
            ? null : _root.收集品栏.情报, "information");
        if (_root.物品栏 != undefined) {
            indexArrayInventory(byItem, "bag", _root.物品栏.背包, -1, true);
            indexArrayInventory(byItem, "drug", _root.物品栏.药剂栏, -1, true);
            indexEquipmentInventory(byItem, _root.物品栏.装备栏);
            indexArrayInventory(byItem, "battleBox", _root.物品栏.战备箱,
                InventoryPanelService.getAccessibleCapacity("战备箱"), false);
        }
        for (var itemName:String in byItem) {
            if (ObjectUtil.isInternalKey(itemName)) continue;
            var summary:Object = byItem[itemName];
            if (Number(summary.material) > 0 || Number(summary.information) > 0) {
                summary.usable = Number(summary.material) + Number(summary.information);
                summary.total = Number(summary.usable);
            } else {
                summary.usable = Number(summary.bag) + Number(summary.drug);
                summary.total = Number(summary.usable) + Number(summary.equipped)
                    + Number(summary.battleBox);
            }
        }
        return byItem;
    }

    /** 当前合成预览用；不要求先标记，也不写入采购计划。 */
    public static function buildImmediateDemand(itemName:String, required:Number,
            isQuantity:Boolean, sourceIndex:Object, ownedIndex:Object):Object {
        var aggregate:Object = newAggregate(itemName);
        var mode:String = ItemUtil.isInformation(itemName) ? "retain" : "consume";
        addRequirement(aggregate, required, isQuantity, mode,
            {kind:"craft", sourceId:"current", label:"当前合成",
                required:safeRequired(required), mode:mode});
        aggregate.craftRequired = requirementUnits(itemName, isQuantity, required);
        if (sourceIndex == null) sourceIndex = buildPurchaseSourceIndex();
        return finalizeDemand(aggregate, sourceIndex, ownedIndex);
    }

    /** NPCShop/KShop snapshot 共用的一次性派生索引。 */
    public static function buildDemandIndex():Object {
        var byItem:Object = {};
        addMarkedRecipeDemands(byItem);
        addActiveTaskDemands(byItem);
        var sourceIndex:Object = buildPurchaseSourceIndex();
        var ownedIndex:Object = buildOwnedIndex();
        for (var itemName:String in byItem) {
            if (!ObjectUtil.isInternalKey(itemName)) {
                byItem[itemName] = finalizeDemand(
                    byItem[itemName], sourceIndex, ownedIndex);
            }
        }
        return {revision:getRevision(), directShopNavigation:hasDirectShopNavigation(),
            byItem:byItem};
    }

    /** 单次扫描所有商店目录，供同一 snapshot/preview 内的全部材料复用。 */
    public static function buildPurchaseSourceIndex():Object {
        _purchaseSourceIndexBuildCount++;
        var byItem:Object = {}, shopIds:Array = [];
        if (_root.shops != undefined) {
            for (var shopId:String in _root.shops) {
                if (!ObjectUtil.isInternalKey(shopId)) shopIds.push(shopId);
            }
        }
        shopIds.sort();
        for (var shopIndex:Number = 0; shopIndex < shopIds.length; shopIndex++) {
            var currentShopId:String = String(shopIds[shopIndex]);
            var shop:Object = _root.shops[currentShopId];
            if (shop == null || typeof shop != "object") continue;
            var indexes:Array = [];
            for (var rawIndex:String in shop) {
                var catalogIndex:Number = Number(rawIndex);
                if (validWhole(catalogIndex, 0, 10000)) indexes.push(catalogIndex);
            }
            indexes.sort(Array.NUMERIC);
            for (var i:Number = 0; i < indexes.length; i++) {
                var entry:Object = shop[String(indexes[i])];
                if (entry == undefined) entry = shop[indexes[i]];
                var soldName:String = typeof entry == "string" ? String(entry)
                    : String(entry == null ? "" : entry.name);
                appendPurchaseSource(byItem, soldName, {kind:"npcshop",
                    shopId:currentShopId, catalogIndex:indexes[i], label:currentShopId});
            }
        }
        var kshop:Array = _root.kshop_list instanceof Array ? _root.kshop_list : [];
        for (var k:Number = 0; k < kshop.length; k++) {
            var kEntry:Object = kshop[k];
            if (kEntry == null) continue;
            appendPurchaseSource(byItem, String(kEntry.item || ""), {kind:"kshop",
                catalogIndex:k, entryId:String(kEntry.id || ""),
                category:String(kEntry.type || ""),
                label:String(kEntry.type || "K 点商城")});
        }
        return byItem;
    }

    /**
     * 配方详情直达金币商店的点击时权威门。配方材料可以是装备或普通物品，
     * 因此不能要求它先成为材料档案成员；MaterialArchiveProjector 只复证
     * current obtain occurrence 与 exact live slot。本层额外证明稳定配方身份、
     * 材料引用以及摩托车/越野车基建能力。
     */
    public static function authorizeShopAccess(params:Object):Object {
        var callId:Number = params != null && typeof params.callId == "number"
            ? Number(params.callId) : 0;
        if (!validProcurementShopRequest(params)) {
            return shopAccessFailure(callId, "deny", "invalid_payload");
        }
        if (!hasDirectShopNavigation()) {
            return shopAccessFailure(callId, "deny", "access_denied");
        }
        var recipeId:String = String(params.recipeId);
        var category:String = String(params.category);
        var recipeIndex:Number = Number(params.recipeIndex);
        var materialName:String = String(params.materialName);
        var found:Object = findRecipe(recipeId);
        if (found == null || String(found.category) != category
                || Number(found.recipeIndex) !== recipeIndex
                || !recipeRequiresMaterial(found.recipe, materialName)) {
            return shopAccessFailure(callId, "stale", "source_not_current");
        }
        var result:Object = MaterialArchiveProjector.authorizeRecipeShopAccess(
            callId, materialName, String(params.shopId), Number(params.catalogIndex));
        if (result == null || result.success !== true) return result;
        result.reason = "procurement_indexed_live_match";
        result.recipeId = recipeId;
        result.category = category;
        result.recipeIndex = recipeIndex;
        return result;
    }

    public static function authorizeKShopAccess(params:Object):Object {
        var callId:Number = params != null && typeof params.callId == "number"
            ? Number(params.callId) : 0;
        if (!validProcurementKShopRequest(params)) {
            return shopAccessFailure(callId, "deny", "invalid_payload");
        }
        if (!hasDirectShopNavigation()) {
            return shopAccessFailure(callId, "deny", "access_denied");
        }
        var recipeId:String = String(params.recipeId);
        var recipeCategory:String = String(params.recipeCategory);
        var recipeIndex:Number = Number(params.recipeIndex);
        var materialName:String = String(params.materialName);
        var found:Object = findRecipe(recipeId);
        if (found == null || String(found.category) != recipeCategory
                || Number(found.recipeIndex) !== recipeIndex
                || !recipeRequiresMaterial(found.recipe, materialName)) {
            return shopAccessFailure(callId, "stale", "source_not_current");
        }
        var result:Object = MaterialArchiveProjector.authorizeRecipeKShopAccess(
            callId, materialName, Number(params.catalogIndex),
            String(params.entryId), String(params.kshopCategory));
        if (result == null || result.success !== true) return result;
        result.reason = "procurement_kshop_indexed_live_match";
        result.recipeId = recipeId;
        result.recipeCategory = recipeCategory;
        result.recipeIndex = recipeIndex;
        return result;
    }

    private static function addMarkedRecipeDemands(byItem:Object):Void {
        var store:Object = readStore();
        for (var recipeId:String in store.recipes) {
            if (ObjectUtil.isInternalKey(recipeId)) continue;
            var planned:Number = Number(store.recipes[recipeId]);
            var found:Object = findRecipe(recipeId);
            if (!validWhole(planned, 1, MAX_PLANNED_CRAFTS) || found == null
                    || !(found.recipe.materials instanceof Array)) continue;
            var requirements:Array = ItemUtil.getRequirementFromTask(found.recipe.materials);
            for (var index:Number = 0; index < requirements.length; index++) {
                var req:Object = requirements[index];
                var itemName:String = String(req.name || "");
                if (!ItemUtil.isItem(itemName)) continue;
                var equipmentLevelRequirement:Boolean = ItemUtil.isEquipment(itemName)
                    && req.isQuantity !== true;
                var retainedRequirement:Boolean = ItemUtil.isInformation(itemName);
                var required:Number = equipmentLevelRequirement || retainedRequirement
                    ? safeRequired(req.value) : safeRequired(req.value) * planned;
                var mode:String = retainedRequirement ? "retain" : "consume";
                var aggregate:Object = ensureAggregate(byItem, itemName);
                addRequirement(aggregate, required, req.isQuantity === true, mode,
                    {kind:"craft", sourceId:recipeId,
                        label:String(found.recipe.title || found.recipe.name || recipeId),
                        required:equipmentLevelRequirement ? planned : required, mode:mode},
                    equipmentLevelRequirement ? planned : undefined);
                aggregate.craftRequired += equipmentLevelRequirement
                    ? planned : requirementUnits(itemName, req.isQuantity === true, required);
                if (aggregate.recipeIds[recipeId] !== true) {
                    aggregate.recipeIds[recipeId] = true; aggregate.plannedRecipeCount++;
                }
            }
        }
    }

    private static function addActiveTaskDemands(byItem:Object):Void {
        var active:Array = _root.tasks_to_do instanceof Array ? _root.tasks_to_do : [];
        for (var index:Number = 0; index < active.length; index++) {
            var entry:Object = active[index];
            if (entry == null || TaskUtil.tasks == undefined) continue;
            var taskId:String = String(entry.id);
            var task:Object = TaskUtil.tasks[entry.id];
            if (task == null) continue;
            addTaskArray(byItem, taskId, taskTitle(task), task.finish_submit_items, "submit");
            addTaskArray(byItem, taskId, taskTitle(task), task.finish_contain_items, "contain");
        }
    }

    private static function addTaskArray(byItem:Object, taskId:String, title:String,
            raw:Array, taskMode:String):Void {
        if (!(raw instanceof Array) || raw.length == 0) return;
        var requirements:Array = ItemUtil.getRequirementFromTask(raw);
        for (var index:Number = 0; index < requirements.length; index++) {
            var req:Object = requirements[index];
            var itemName:String = String(req.name || "");
            if (!ItemUtil.isItem(itemName)) continue;
            var required:Number = safeRequired(req.value);
            var mode:String = taskMode == "contain" || ItemUtil.isInformation(itemName)
                ? "retain" : "consume";
            var aggregate:Object = ensureAggregate(byItem, itemName);
            addRequirement(aggregate, required, req.isQuantity === true, mode,
                {kind:"task", sourceId:taskId, label:title,
                    required:required, mode:taskMode});
            aggregate.taskRequired += requirementUnits(itemName,
                req.isQuantity === true, required);
            if (aggregate.taskIds[taskId] !== true) {
                aggregate.taskIds[taskId] = true; aggregate.activeTaskCount++;
            }
        }
    }

    private static function taskTitle(task:Object):String {
        var title:String = String(task.title || "任务物资");
        if (TaskUtil.task_texts != undefined && typeof TaskUtil.task_texts[task.title] == "string") {
            title = String(TaskUtil.task_texts[task.title]);
        }
        return title;
    }

    private static function ensureAggregate(byItem:Object, itemName:String):Object {
        if (byItem[itemName] == undefined) byItem[itemName] = newAggregate(itemName);
        return byItem[itemName];
    }

    private static function newAggregate(itemName:String):Object {
        return {itemName:itemName, consumeUnits:0, retainUnits:0,
            requiredEnhancement:0, craftRequired:0, taskRequired:0,
            plannedRecipeCount:0, activeTaskCount:0,
            recipeIds:{}, taskIds:{}, reasons:[]};
    }

    private static function addRequirement(aggregate:Object, required:Number,
            isQuantity:Boolean, mode:String, reason:Object,
            equipmentUnits:Number):Void {
        required = safeRequired(required);
        if (ItemUtil.isEquipment(aggregate.itemName) && !isQuantity) {
            aggregate.requiredEnhancement = Math.max(Number(aggregate.requiredEnhancement), required);
            var units:Number = validWhole(Number(equipmentUnits), 1, MAX_PLANNED_CRAFTS)
                ? Number(equipmentUnits) : 1;
            if (mode == "retain") aggregate.retainUnits = Math.max(
                Number(aggregate.retainUnits), units);
            else aggregate.consumeUnits += units;
        } else if (mode == "retain") {
            aggregate.retainUnits = Math.max(Number(aggregate.retainUnits), required);
        } else aggregate.consumeUnits += required;
        if (aggregate.reasons.length < MAX_REASONS) aggregate.reasons.push(reason);
    }

    private static function requirementUnits(itemName:String, isQuantity:Boolean,
            required:Number):Number {
        return ItemUtil.isEquipment(itemName) && !isQuantity ? 1 : safeRequired(required);
    }

    private static function finalizeDemand(aggregate:Object, sourceIndex:Object,
            ownedIndex:Object):Object {
        var owned:Object = buildOwnedSummaryInternal(
            String(aggregate.itemName), ownedIndex);
        var requiredUnits:Number = Number(aggregate.consumeUnits) + Number(aggregate.retainUnits);
        if (Number(aggregate.requiredEnhancement) > 0) requiredUnits = Math.max(1, requiredUnits);
        var usable:Number = Number(owned.usable), total:Number = Number(owned.total);
        var relocateMissing:Number = Math.min(Math.max(0, requiredUnits - usable),
            Math.max(0, total - usable));
        var obtainMissing:Number = Math.max(0, requiredUnits - total);
        var needsEnhancement:Boolean = Number(aggregate.requiredEnhancement) > 0
            && Number(owned.totalMaxEnhancement) < Number(aggregate.requiredEnhancement);
        if (needsEnhancement && total <= 0) obtainMissing = Math.max(1, obtainMissing);
        if (!needsEnhancement && Number(aggregate.requiredEnhancement) > 0
                && Number(owned.usableMaxEnhancement) < Number(aggregate.requiredEnhancement)
                && Number(owned.totalMaxEnhancement) >= Number(aggregate.requiredEnhancement)) {
            relocateMissing = Math.max(1, relocateMissing);
        }
        var sources:Array = sourceIndex != null
            && sourceIndex[String(aggregate.itemName)] instanceof Array
            ? sourceIndex[String(aggregate.itemName)] : [];
        return {itemName:String(aggregate.itemName), required:requiredUnits,
            requiredEnhancement:Number(aggregate.requiredEnhancement),
            usableOwned:usable, equippedOwned:Number(owned.equipped),
            battleBoxOwned:Number(owned.battleBox), totalOwned:total,
            usableMaxEnhancement:Number(owned.usableMaxEnhancement),
            equippedMaxEnhancement:Number(owned.equippedMaxEnhancement),
            battleBoxMaxEnhancement:Number(owned.battleBoxMaxEnhancement),
            totalMaxEnhancement:Number(owned.totalMaxEnhancement),
            obtainMissing:obtainMissing, relocateMissing:relocateMissing,
            needsEnhancement:needsEnhancement,
            craftRequired:Number(aggregate.craftRequired), taskRequired:Number(aggregate.taskRequired),
            plannedRecipeCount:Number(aggregate.plannedRecipeCount),
            activeTaskCount:Number(aggregate.activeTaskCount),
            reasons:aggregate.reasons, sources:sources};
    }

    private static function appendPurchaseSource(byItem:Object, itemName:String,
            source:Object):Void {
        if (itemName == "" || ObjectUtil.isInternalKey(itemName)) return;
        if (!(byItem[itemName] instanceof Array)) byItem[itemName] = [];
        if (byItem[itemName].length < MAX_SOURCES) byItem[itemName].push(source);
    }

    private static function emptyOwnedSummary():Object {
        return {bag:0, drug:0, equipped:0, battleBox:0,
            material:0, information:0, usable:0, total:0,
            usableMaxEnhancement:0, equippedMaxEnhancement:0,
            battleBoxMaxEnhancement:0, totalMaxEnhancement:0};
    }

    private static function cloneOwnedSummary(value:Object):Object {
        if (value == null || typeof value != "object") return emptyOwnedSummary();
        return {bag:Number(value.bag || 0), drug:Number(value.drug || 0),
            equipped:Number(value.equipped || 0),
            battleBox:Number(value.battleBox || 0),
            material:Number(value.material || 0),
            information:Number(value.information || 0),
            usable:Number(value.usable || 0), total:Number(value.total || 0),
            usableMaxEnhancement:Number(value.usableMaxEnhancement || 0),
            equippedMaxEnhancement:Number(value.equippedMaxEnhancement || 0),
            battleBoxMaxEnhancement:Number(value.battleBoxMaxEnhancement || 0),
            totalMaxEnhancement:Number(value.totalMaxEnhancement || 0)};
    }

    private static function ensureOwnedIndexEntry(byItem:Object,
            itemName:String):Object {
        if (byItem[itemName] == undefined) byItem[itemName] = emptyOwnedSummary();
        return byItem[itemName];
    }

    private static function indexCollection(byItem:Object, collection:Object,
            field:String):Void {
        if (collection == null || typeof collection.getItems != "function"
                || typeof collection.getValue != "function") return;
        var items:Object = collection.getItems();
        for (var itemName:String in items) {
            if (ObjectUtil.isInternalKey(itemName)
                    || field == "material" && !ItemUtil.isMaterial(itemName)
                    || field == "information" && !ItemUtil.isInformation(itemName)) continue;
            var quantity:Number = Number(collection.getValue(itemName));
            if (!validWhole(quantity, 1, 9007199254740991)) continue;
            var summary:Object = ensureOwnedIndexEntry(byItem, itemName);
            summary[field] = quantity;
        }
    }

    private static function indexArrayInventory(byItem:Object, field:String,
            inventory:Object, capacityLimit:Number, usable:Boolean):Void {
        if (inventory == null || typeof inventory.getIndexes != "function") return;
        var indexes:Array = inventory.getIndexes();
        for (var index:Number = 0; index < indexes.length; index++) {
            var slot:Number = Number(indexes[index]);
            if (capacityLimit >= 0 && slot >= capacityLimit) continue;
            indexOwnedItem(byItem, field, inventory.getItem(indexes[index]), usable);
        }
    }

    private static function indexEquipmentInventory(byItem:Object,
            inventory:Object):Void {
        if (inventory == null || typeof inventory.getItems != "function") return;
        var items:Object = inventory.getItems();
        for (var slot:String in items) {
            if (!ObjectUtil.isInternalKey(slot)) {
                indexOwnedItem(byItem, "equipped", items[slot], false);
            }
        }
    }

    private static function indexOwnedItem(byItem:Object, field:String,
            item:Object, usable:Boolean):Void {
        var itemName:String = item == null ? "" : String(item.name || "");
        if (itemName == "" || !ItemUtil.isItem(itemName)
                || ItemUtil.isMaterial(itemName) || ItemUtil.isInformation(itemName)) return;
        var quantity:Number = ItemUtil.isEquipment(itemName) ? 1 : Number(item.value);
        if (!validWhole(quantity, 1, 9007199254740991)) return;
        var summary:Object = ensureOwnedIndexEntry(byItem, itemName);
        summary[field] = Number(summary[field]) + quantity;
        if (!ItemUtil.isEquipment(itemName)) return;
        var level:Number = item.value == null ? 0 : Number(item.value.level);
        if (!validWhole(level, 0, 9007199254740991)) level = 0;
        summary.totalMaxEnhancement = Math.max(
            Number(summary.totalMaxEnhancement), level);
        if (field == "equipped") summary.equippedMaxEnhancement = Math.max(
            Number(summary.equippedMaxEnhancement), level);
        else if (field == "battleBox") summary.battleBoxMaxEnhancement = Math.max(
            Number(summary.battleBoxMaxEnhancement), level);
        if (usable) summary.usableMaxEnhancement = Math.max(
            Number(summary.usableMaxEnhancement), level);
    }

    private static function findRecipe(recipeId:String):Object {
        if (_root.改装清单 == undefined) return null;
        var found:Object = null;
        for (var category:String in _root.改装清单) {
            if (ObjectUtil.isInternalKey(category)) continue;
            var recipes:Array = _root.改装清单[category];
            if (!(recipes instanceof Array)) continue;
            for (var index:Number = 0; index < recipes.length; index++) {
                var recipe:Object = recipes[index];
                if (recipe == null || String(recipe.recipeId || "") != recipeId) continue;
                if (found != null) return null;
                found = {category:category, recipeIndex:index, recipe:recipe};
            }
        }
        return found;
    }

    private static function recipeRequiresMaterial(recipe:Object,
            materialName:String):Boolean {
        if (recipe == null || !(recipe.materials instanceof Array)) return false;
        var requirements:Array = ItemUtil.getRequirementFromTask(recipe.materials);
        for (var index:Number = 0; index < requirements.length; index++) {
            if (String(requirements[index].name || "") == materialName) return true;
        }
        return false;
    }

    private static function validProcurementShopRequest(params:Object):Boolean {
        if (params == null || typeof params != "object") return false;
        var allowed:Object = {task:true,action:true,callId:true,v:true,
            materialName:true,shopId:true,catalogIndex:true,
            recipeId:true,category:true,recipeIndex:true};
        var count:Number = 0;
        for (var key:String in params) {
            if (ObjectUtil.isInternalKey(key)) continue;
            if (allowed[key] !== true) return false;
            count++;
        }
        return count == 10
            && typeof params.task == "string" && params.task === "cmd"
            && typeof params.action == "string"
            && params.action === "craftingProcurementShopAuthorize"
            && typeof params.callId == "number"
            && validWhole(Number(params.callId), 1, 2147483647)
            && typeof params.v == "number" && Number(params.v) === 1
            && typeof params.materialName == "string"
            && validIdentity(String(params.materialName), 128)
            && typeof params.shopId == "string"
            && validIdentity(String(params.shopId), 80)
            && typeof params.catalogIndex == "number"
            && validWhole(Number(params.catalogIndex), 0, 10000)
            && typeof params.recipeId == "string"
            && validRecipeId(String(params.recipeId))
            && typeof params.category == "string"
            && validIdentity(String(params.category), 256)
            && typeof params.recipeIndex == "number"
            && validWhole(Number(params.recipeIndex), 0, 999);
    }

    private static function validProcurementKShopRequest(params:Object):Boolean {
        if (params == null || typeof params != "object") return false;
        var allowed:Object = {task:true,action:true,callId:true,v:true,
            materialName:true,catalogIndex:true,entryId:true,
            kshopCategory:true,recipeId:true,recipeCategory:true,recipeIndex:true};
        var count:Number = 0;
        for (var key:String in params) {
            if (ObjectUtil.isInternalKey(key)) continue;
            if (allowed[key] !== true) return false;
            count++;
        }
        return count == 11
            && typeof params.task == "string" && params.task === "cmd"
            && typeof params.action == "string"
            && params.action === "craftingProcurementKShopAuthorize"
            && typeof params.callId == "number"
            && validWhole(Number(params.callId), 1, 2147483647)
            && typeof params.v == "number" && Number(params.v) === 1
            && typeof params.materialName == "string"
            && validIdentity(String(params.materialName), 128)
            && typeof params.catalogIndex == "number"
            && validWhole(Number(params.catalogIndex), 0, 10000)
            && typeof params.entryId == "string"
            && validIdentity(String(params.entryId), 256)
            && typeof params.kshopCategory == "string"
            && validIdentity(String(params.kshopCategory), 512)
            && typeof params.recipeId == "string"
            && validRecipeId(String(params.recipeId))
            && typeof params.recipeCategory == "string"
            && validIdentity(String(params.recipeCategory), 256)
            && typeof params.recipeIndex == "number"
            && validWhole(Number(params.recipeIndex), 0, 999);
    }

    private static function validIdentity(value:String, maximum:Number):Boolean {
        if (typeof value != "string" || value.length < 1 || value.length > maximum
                || value.toLowerCase() == "undefined") return false;
        for (var index:Number = 0; index < value.length; index++) {
            var code:Number = value.charCodeAt(index);
            if (code <= 31 || code == 127 || (code >= 128 && code <= 159)) return false;
        }
        return true;
    }

    private static function shopAccessFailure(callId:Number, decision:String,
            errorCode:String):Object {
        return {task:"material_shop_access_response", callId:callId,
            success:false, v:1, decision:decision, error:errorCode};
    }

    private static function readStore():Object {
        var raw:Object = _root._saveExt == undefined ? null : _root._saveExt.procurementPlans;
        if (raw == null || typeof raw.v != "number" || Number(raw.v) != STORE_VERSION
                || typeof raw.revision != "number"
                || !validWhole(Number(raw.revision), 0, MAX_SAFE_REVISION)
                || raw.recipes == null || typeof raw.recipes != "object") {
            return {v:STORE_VERSION, revision:0, recipes:{}};
        }
        return {v:STORE_VERSION, revision:Number(raw.revision),
            recipes:clonePlanEntries(raw.recipes)};
    }

    private static function clonePlanEntries(raw:Object):Object {
        var result:Object = {};
        if (raw == null) return result;
        for (var recipeId:String in raw) {
            if (ObjectUtil.isInternalKey(recipeId)) continue;
            var value:Number = Number(raw[recipeId]);
            if (typeof raw[recipeId] == "number" && validRecipeId(recipeId)
                    && validWhole(value, 1, MAX_PLANNED_CRAFTS)) {
                result[recipeId] = value;
            }
        }
        return result;
    }

    private static function writeStore(store:Object):Void {
        if (_root._saveExt == undefined || _root._saveExt == null) _root._saveExt = {};
        _root._saveExt.procurementPlans = store;
        if (_root.存档系统 != undefined) {
            _root.存档系统.dirtyMark = true;
            if (typeof _root.存档系统.markDirty == "function") _root.存档系统.markDirty();
        }
    }

    private static function accumulateArray(result:Object, field:String,
            inventory:Object, itemName:String, capacityLimit:Number):Void {
        if (inventory == null || typeof inventory.getIndexes != "function") return;
        var indexes:Array = inventory.getIndexes();
        for (var index:Number = 0; index < indexes.length; index++) {
            var slot:Number = Number(indexes[index]);
            if (capacityLimit >= 0 && slot >= capacityLimit) continue;
            accumulateItem(result, field, inventory.getItem(indexes[index]), itemName,
                field == "bag" || field == "drug");
        }
    }

    private static function accumulateEquipment(result:Object, inventory:Object,
            itemName:String):Void {
        if (inventory == null || typeof inventory.getItems != "function") return;
        var items:Object = inventory.getItems();
        for (var slot:String in items) {
            if (!ObjectUtil.isInternalKey(slot)) {
                accumulateItem(result, "equipped", items[slot], itemName, false);
            }
        }
    }

    private static function accumulateItem(result:Object, field:String, item:Object,
            itemName:String, usable:Boolean):Void {
        if (item == null || String(item.name || "") != itemName) return;
        var quantity:Number = ItemUtil.isEquipment(itemName) ? 1 : Number(item.value);
        if (!validWhole(quantity, 1, 9007199254740991)) return;
        result[field] = Number(result[field]) + quantity;
        if (!ItemUtil.isEquipment(itemName)) return;
        var level:Number = item.value == null ? 0 : Number(item.value.level);
        if (!validWhole(level, 0, 9007199254740991)) level = 0;
        result.totalMaxEnhancement = Math.max(Number(result.totalMaxEnhancement), level);
        if (field == "equipped") result.equippedMaxEnhancement = Math.max(
            Number(result.equippedMaxEnhancement), level);
        else if (field == "battleBox") result.battleBoxMaxEnhancement = Math.max(
            Number(result.battleBoxMaxEnhancement), level);
        if (usable) result.usableMaxEnhancement = Math.max(
            Number(result.usableMaxEnhancement), level);
    }

    private static function collectionValue(collection:Object, itemName:String):Number {
        if (collection == null || typeof collection.getValue != "function") return 0;
        var value:Number = Number(collection.getValue(itemName));
        return validWhole(value, 0, 9007199254740991) ? value : 0;
    }

    private static function hasDirectShopNavigation():Boolean {
        var infra:Object = _root.基建系统 == undefined
            ? null : _root.基建系统.infrastructure;
        return unlocked(infra, "摩托车") || unlocked(infra, "越野车");
    }

    private static function unlocked(infra:Object, key:String):Boolean {
        return infra != null && infra[key] != undefined && infra[key] != null
            && Number(infra[key]) >= 1;
    }

    private static function safeRequired(value):Number {
        var required:Number = Number(value);
        return validWhole(required, 1, 9007199254740991) ? required : 1;
    }

    private static function validWhole(value:Number, minimum:Number, maximum:Number):Boolean {
        return !isNaN(value) && isFinite(value) && Math.floor(value) == value
            && value >= minimum && value <= maximum;
    }

    private static function hasExactOwnKeys(value:Object, expected:Array):Boolean {
        if (value == null || typeof value != "object") return false;
        var count:Number = 0;
        for (var key:String in value) {
            if (ObjectUtil.isInternalKey(key)) continue;
            var found:Boolean = false;
            for (var index:Number = 0; index < expected.length; index++) {
                if (expected[index] === key) { found = true; break; }
            }
            if (!found) return false;
            count++;
        }
        return count == expected.length;
    }

    private static function validRecipeId(value:String):Boolean {
        if (typeof value != "string" || value.length < 9 || value.length > 96
                || value.substr(0, 6) != "craft.") return false;
        for (var index:Number = 0; index < value.length; index++) {
            var code:Number = value.charCodeAt(index);
            if (!((code >= 48 && code <= 57) || (code >= 97 && code <= 122)
                    || code == 45 || code == 46)) return false;
        }
        return true;
    }

    private static function fail(errorCode:String):Object {
        return {success:false, error:errorCode};
    }
}
