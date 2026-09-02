/**
 * 八槽药剂“原槽恢复”元数据、纯规划与提交叶。
 *
 * 持久化真源：_root._saveExt.drugLoadout v3。本服务不 flush，也不拥有
 * 资产事务；调用方必须在权威写之前标 dirty，再在 exact 写后提交 affinity。
 */
class org.flashNight.arki.item.DrugSlotAffinityService {
    public static var VERSION:Number = 3;
    public static var SLOT_COUNT:Number = 8;
    public static var MAX_SAFE_SEQUENCE:Number = 9007199254740991;

    /**
     * 纯数据 schema 归一化。不读写 _root，不修改 feature/rawDrugSlots。
     *
     * rawDrugSlots 是以 "0".."7" 为键的已存档或运行时物品对象；
     * isDrugKey 是可选纯查询函数，返回 true 才保留空槽 affinity。
     */
    public static function normalizeSavedFeature(
        feature:Object,
        rawDrugSlots:Object,
        isDrugKey:Function
    ):Object {
        var diagnostics:Array = [];
        var hasVersion:Boolean = feature != null
            && feature.version != undefined;
        var inputVersion:Number = hasVersion
            ? Number(feature.version) : 2;
        if (hasVersion && (isNaN(inputVersion)
                || Math.floor(inputVersion) != inputVersion)) {
            return {
                ok:false,
                changed:false,
                error:"invalid_drug_loadout_version",
                feature:feature,
                diagnostics:["invalid_version"]
            };
        }
        if (inputVersion > VERSION) {
            return {
                ok:false,
                changed:false,
                error:"future_drug_loadout_version",
                feature:feature,
                diagnostics:["future_version:" + inputVersion]
            };
        }

        var migrated:Boolean = inputVersion < VERSION;
        var inputSlots:Array = !migrated && feature != null
            && feature.slots instanceof Array ? feature.slots : null;
        var slots:Array = [];
        var seenSequences:Object = {};
        var duplicateSequence:Boolean = false;
        var maximumSequence:Number = 0;

        for (var slot:Number = 0; slot < SLOT_COUNT; slot++) {
            var itemKey:String = "";
            var sequence:Number = 0;
            if (inputSlots != null) {
                var inputEntry:Object = inputSlots[slot];
                if (inputEntry != null && typeof inputEntry == "object"
                        && typeof inputEntry.itemKey == "string") {
                    itemKey = String(inputEntry.itemKey);
                    sequence = Number(inputEntry.lastDepletedSequence);
                    if (itemKey == "" || itemKey == "undefined") {
                        itemKey = "";
                        sequence = 0;
                    } else if (!isWholeSequence(sequence)) {
                        diagnostics.push("invalid_sequence:" + slot);
                        itemKey = "";
                        sequence = 0;
                    } else if (!validDrugKey(itemKey, isDrugKey)) {
                        diagnostics.push("invalid_item_key:" + slot);
                        itemKey = "";
                        sequence = 0;
                    }
                } else if (inputEntry != null || inputSlots.length > slot) {
                    diagnostics.push("invalid_slot_entry:" + slot);
                }
            }

            var rawItem:Object = rawDrugSlots == null
                ? null : rawDrugSlots[String(slot)];
            if (rawItem != null) {
                var occupiedKey:String = typeof rawItem.name == "string"
                    ? String(rawItem.name) : "";
                if (occupiedKey != "" && occupiedKey != "undefined"
                        && validDrugKey(occupiedKey, isDrugKey)) {
                    if (itemKey != occupiedKey || sequence != 0) {
                        diagnostics.push("occupied_rebound:" + slot);
                    }
                    itemKey = occupiedKey;
                    sequence = 0;
                } else {
                    diagnostics.push("invalid_occupied_item:" + slot);
                    itemKey = "";
                    sequence = 0;
                }
            } else if (itemKey != "" && sequence == 0) {
                // 空槽只有“已耗尽”才能保留 affinity。seq=0 只表示
                // 当前被同名药剂占用；无占用时该组合是无效中间态。
                diagnostics.push("empty_bound_slot:" + slot);
                itemKey = "";
            }

            slots[slot] = {
                itemKey:itemKey,
                lastDepletedSequence:sequence
            };
            if (sequence > 0) {
                var sequenceKey:String = String(sequence);
                if (seenSequences[sequenceKey] === true) {
                    duplicateSequence = true;
                }
                seenSequences[sequenceKey] = true;
                if (sequence > maximumSequence) maximumSequence = sequence;
            }
        }

        var inputNext:Number = feature == null
            ? NaN : Number(feature.nextDepletedSequence);
        var mustCompact:Boolean = duplicateSequence
            || maximumSequence >= MAX_SAFE_SEQUENCE;
        if (mustCompact) {
            compactSequences(slots);
            maximumSequence = maximumSlotSequence(slots);
            diagnostics.push("sequence_compacted");
        }
        var nextSequence:Number = inputNext;
        if (migrated || !isWholeNextSequence(nextSequence)
                || nextSequence <= maximumSequence) {
            nextSequence = maximumSequence + 1;
            if (nextSequence < 1) nextSequence = 1;
            diagnostics.push("next_sequence_repaired");
        }
        if (nextSequence > MAX_SAFE_SEQUENCE) {
            compactSequences(slots);
            maximumSequence = maximumSlotSequence(slots);
            nextSequence = maximumSequence + 1;
            diagnostics.push("sequence_compacted");
        }

        var normalized:Object = {
            version:VERSION,
            slots:slots,
            nextDepletedSequence:nextSequence
        };
        return {
            ok:true,
            changed:!featureEquals(feature, normalized),
            feature:normalized,
            diagnostics:diagnostics
        };
    }

    /** 运行时纯读投影；不修改 ext 或容器。 */
    public static function previewNormalized(
        root:Object,
        drugInventory:Object
    ):Object {
        var resolvedRoot:Object = root == null ? _root : root;
        var raw:Object = captureRuntimeSlots(drugInventory);
        if (raw == null) {
            return {
                ok:false,
                changed:false,
                error:"drug_inventory_unavailable",
                feature:null,
                diagnostics:["drug_inventory_unavailable"]
            };
        }
        var feature:Object = resolvedRoot == null
            || resolvedRoot._saveExt == undefined
            || resolvedRoot._saveExt == null
            ? null : resolvedRoot._saveExt.drugLoadout;
        var validator:Function = function(itemKey:String):Boolean {
            return org.flashNight.arki.item.DrugSlotAffinityService
                .isRuntimeDrugKey(resolvedRoot, itemKey);
        };
        return normalizeSavedFeature(feature, raw, validator);
    }

    /** 提交归一化 schema/占用槽交叉一致性，但不标 dirty/flush。 */
    public static function reconcile(
        root:Object,
        drugInventory:Object
    ):Object {
        var resolvedRoot:Object = root == null ? _root : root;
        var normalized:Object = previewNormalized(
            resolvedRoot, drugInventory);
        if (!normalized.ok) return normalized;
        if (!normalized.changed) return normalized;
        if (resolvedRoot._saveExt == undefined
                || resolvedRoot._saveExt == null
                || typeof resolvedRoot._saveExt != "object") {
            resolvedRoot._saveExt = {};
        }
        resolvedRoot._saveExt.drugLoadout = normalized.feature;
        return normalized;
    }

    /**
     * 建立批内纯规划状态。后续 planAcquireTarget 只改 shadow，
     * 不修改物品栏、ext 或存档。
     */
    public static function createAcquirePlanningState(
        root:Object,
        drugInventory:Object,
        backpackInventory:Object
    ):Object {
        var normalized:Object = previewNormalized(root, drugInventory);
        if (!normalized.ok) return normalized;
        if (backpackInventory == null
                || typeof backpackInventory.getItem != "function") {
            return {ok:false, error:"backpack_unavailable"};
        }
        var capacity:Number = Number(backpackInventory.capacity);
        if (isNaN(capacity) || Math.floor(capacity) != capacity
                || capacity < 1 || capacity > 100000) {
            return {ok:false, error:"invalid_backpack_capacity"};
        }

        var drugShadow:Array = [];
        for (var slot:Number = 0; slot < SLOT_COUNT; slot++) {
            drugShadow[slot] = shadowEntry(
                drugInventory.getItem(String(slot)));
        }
        var bagShadow:Array = [];
        for (slot = 0; slot < capacity; slot++) {
            bagShadow[slot] = shadowEntry(
                backpackInventory.getItem(String(slot)));
        }
        return {
            ok:true,
            feature:normalized.feature,
            diagnostics:normalized.diagnostics,
            drugs:drugShadow,
            backpack:bagShadow,
            backpackCapacity:capacity,
            nextPlanId:1
        };
    }

    /**
     * 单项批内规划：空 exact affinity（最近耗尽优先）→药剂栏同名
     * →背包同名→背包最低空位。活动组不参与排序。
     */
    public static function planAcquireTarget(
        state:Object,
        itemKey:String,
        quantity:Number,
        isDrug:Boolean,
        mergeable:Boolean
    ):Object {
        if (state == null || state.ok !== true) {
            return {success:false, error:"invalid_planning_state"};
        }
        quantity = Number(quantity);
        if (typeof itemKey != "string" || itemKey == ""
                || itemKey == "undefined" || !isWholePositive(quantity)) {
            return {success:false, error:"invalid_item"};
        }

        var slot:Number = -1;
        var mode:String = "";
        if (isDrug && mergeable) {
            var bestSequence:Number = -1;
            for (var i:Number = 0; i < SLOT_COUNT; i++) {
                var affinity:Object = state.feature.slots[i];
                if (state.drugs[i] == null
                        && affinity != null
                        && String(affinity.itemKey) == itemKey
                        && Number(affinity.lastDepletedSequence) > 0) {
                    var sequence:Number = Number(
                        affinity.lastDepletedSequence);
                    if (slot < 0 || sequence > bestSequence
                            || (sequence == bestSequence && i < slot)) {
                        slot = i;
                        bestSequence = sequence;
                    }
                }
            }
            if (slot >= 0) mode = "affinity_restore";
        }

        if (slot < 0 && isDrug && mergeable) {
            slot = firstMergeSlot(state.drugs, itemKey, quantity);
            if (slot == -2) {
                return {success:false, error:"quantity_overflow"};
            }
            if (slot >= 0) mode = "drug_merge";
        }
        var storageKind:String = "drug";
        var targetShadow:Object;
        if (slot < 0 && mergeable) {
            slot = firstMergeSlot(state.backpack, itemKey, quantity);
            if (slot == -2) {
                return {success:false, error:"quantity_overflow"};
            }
            if (slot >= 0) {
                mode = "backpack_merge";
                storageKind = "backpack";
            }
        }
        if (slot < 0) {
            slot = firstVacancy(state.backpack);
            if (slot < 0) {
                return {success:false, error:"inventory_full"};
            }
            mode = "backpack_empty";
            storageKind = "backpack";
        }

        var shadow:Array = storageKind == "drug"
            ? state.drugs : state.backpack;
        targetShadow = shadow[slot];
        var planId:Number = Number(state.nextPlanId++);
        var expectedRef:Object = targetShadow == null
            ? null : targetShadow.ref;
        var expectedValue:Number = targetShadow == null
            ? 0 : Number(targetShadow.value);
        if (targetShadow == null) {
            shadow[slot] = {
                ref:null,
                name:itemKey,
                value:quantity,
                createdByPlanId:planId
            };
        } else {
            targetShadow.value = Number(targetShadow.value) + quantity;
        }
        return {
            success:true,
            planId:planId,
            storageKind:storageKind,
            slot:slot,
            mode:mode,
            itemKey:itemKey,
            quantity:quantity,
            expectedRef:expectedRef,
            expectedValue:expectedValue
        };
    }

    /** exact 物品写完成后提交 affinity；背包目标为空操作。 */
    public static function commitAcquireTarget(
        root:Object,
        drugInventory:Object,
        plan:Object
    ):Object {
        if (plan == null || plan.success !== true) {
            return {success:false, changed:false, error:"invalid_plan"};
        }
        if (String(plan.storageKind) != "drug") {
            return {success:true, changed:false};
        }
        var slot:Number = Number(plan.slot);
        if (!validSlot(slot) || typeof plan.itemKey != "string") {
            return {success:false, changed:false, error:"invalid_plan"};
        }
        var current:Object = drugInventory.getItem(String(slot));
        if (current == null || String(current.name) != String(plan.itemKey)
                || !isWholePositive(Number(current.value))) {
            return {
                success:false,
                changed:false,
                error:"drug_target_mismatch"
            };
        }
        var expectedValue:Number = Number(plan.expectedValue);
        if (plan.expectedValue != undefined
                && (!isWholeSequence(expectedValue)
                    || Number(current.value)
                        != expectedValue + Number(plan.quantity))) {
            return {
                success:false,
                changed:false,
                error:"drug_target_value_mismatch"
            };
        }
        if (plan.expectedRef != undefined && plan.expectedRef != null
                && current !== plan.expectedRef) {
            return {
                success:false,
                changed:false,
                error:"drug_target_ref_mismatch"
            };
        }
        return recordManualSlots(root, drugInventory, [slot], true);
    }

    /** 最后一剂 exact 删除后记录原槽及耗尽顺序。 */
    public static function recordDepleted(
        root:Object,
        drugInventory:Object,
        slot:Number,
        itemKey:String
    ):Object {
        if (!validSlot(slot) || typeof itemKey != "string"
                || itemKey == "" || itemKey == "undefined") {
            return {success:false, changed:false, error:"invalid_depletion"};
        }
        var resolvedRoot:Object = root == null ? _root : root;
        if (!isRuntimeDrugKey(resolvedRoot, itemKey)) {
            return {success:false, changed:false, error:"invalid_item_key"};
        }
        if (drugInventory == null
                || drugInventory.getItem(String(slot)) != null) {
            return {success:false, changed:false, error:"slot_not_empty"};
        }
        var normalized:Object = reconcile(resolvedRoot, drugInventory);
        if (!normalized.ok) return normalized;
        var feature:Object = resolvedRoot._saveExt.drugLoadout;
        if (!isWholeNextSequence(Number(feature.nextDepletedSequence))
                || Number(feature.nextDepletedSequence)
                    >= MAX_SAFE_SEQUENCE) {
            compactSequences(feature.slots);
            feature.nextDepletedSequence =
                maximumSlotSequence(feature.slots) + 1;
        }
        var sequence:Number = Number(feature.nextDepletedSequence);
        feature.slots[slot] = {
            itemKey:itemKey,
            lastDepletedSequence:sequence
        };
        feature.nextDepletedSequence = sequence + 1;
        return {success:true, changed:true, slot:slot, sequence:sequence};
    }

    /**
     * 主动安装/移动/卸下后按实际槽内容提交绑定。
     * clearEmpty=true 表示空源槽是玩家意图，必须清除 affinity。
     */
    public static function recordManualSlots(
        root:Object,
        drugInventory:Object,
        slots:Array,
        clearEmpty:Boolean
    ):Object {
        if (!(slots instanceof Array)) {
            return {success:false, changed:false, error:"invalid_slots"};
        }
        var resolvedRoot:Object = root == null ? _root : root;
        var normalized:Object = reconcile(resolvedRoot, drugInventory);
        if (!normalized.ok) return normalized;
        var feature:Object = resolvedRoot._saveExt.drugLoadout;
        var changed:Boolean = normalized.changed === true;
        var visited:Object = {};
        for (var i:Number = 0; i < slots.length; i++) {
            var slot:Number = Number(slots[i]);
            if (!validSlot(slot) || visited[String(slot)] === true) {
                if (!validSlot(slot)) {
                    return {success:false, changed:changed, error:"invalid_slot"};
                }
                continue;
            }
            visited[String(slot)] = true;
            var item:Object = drugInventory.getItem(String(slot));
            var entry:Object = feature.slots[slot];
            if (item == null) {
                if (clearEmpty && (String(entry.itemKey) != ""
                        || Number(entry.lastDepletedSequence) != 0)) {
                    feature.slots[slot] = emptyEntry();
                    changed = true;
                }
                continue;
            }
            var itemKey:String = typeof item.name == "string"
                ? String(item.name) : "";
            if (!isRuntimeDrugKey(resolvedRoot, itemKey)) {
                if (String(entry.itemKey) != ""
                        || Number(entry.lastDepletedSequence) != 0) {
                    feature.slots[slot] = emptyEntry();
                    changed = true;
                }
                continue;
            }
            if (String(entry.itemKey) != itemKey
                    || Number(entry.lastDepletedSequence) != 0) {
                feature.slots[slot] = {
                    itemKey:itemKey,
                    lastDepletedSequence:0
                };
                changed = true;
            }
        }
        return {success:true, changed:changed};
    }

    private static function captureRuntimeSlots(
        drugInventory:Object
    ):Object {
        if (drugInventory == null
                || typeof drugInventory.getItem != "function") return null;
        var raw:Object = {};
        for (var slot:Number = 0; slot < SLOT_COUNT; slot++) {
            var item:Object = drugInventory.getItem(String(slot));
            if (item != null) raw[String(slot)] = item;
        }
        return raw;
    }

    private static function isRuntimeDrugKey(
        root:Object,
        itemKey:String
    ):Boolean {
        if (typeof itemKey != "string" || itemKey == ""
                || itemKey == "undefined") return false;
        var data:Object = null;
        if (root != null && typeof root.getItemData == "function") {
            data = root.getItemData(itemKey);
        }
        return data != null && typeof data.use == "string"
            && String(data.use) == "药剂";
    }

    private static function validDrugKey(
        itemKey:String,
        validator:Function
    ):Boolean {
        if (typeof itemKey != "string" || itemKey == ""
                || itemKey == "undefined") return false;
        return typeof validator != "function"
            || validator(itemKey) === true;
    }

    private static function shadowEntry(item:Object):Object {
        if (item == null) return null;
        return {
            ref:item,
            name:String(item.name),
            value:Number(item.value),
            createdByPlanId:0
        };
    }

    private static function firstMergeSlot(
        shadow:Array,
        itemKey:String,
        quantity:Number
    ):Number {
        for (var slot:Number = 0; slot < shadow.length; slot++) {
            var entry:Object = shadow[slot];
            if (entry == null || String(entry.name) != itemKey) continue;
            var current:Number = Number(entry.value);
            var total:Number = current + quantity;
            if (!isWholePositive(current) || !isWholePositive(total)
                    || total > MAX_SAFE_SEQUENCE) return -2;
            return slot;
        }
        return -1;
    }

    private static function firstVacancy(shadow:Array):Number {
        for (var slot:Number = 0; slot < shadow.length; slot++) {
            if (shadow[slot] == null) return slot;
        }
        return -1;
    }

    private static function compactSequences(slots:Array):Void {
        var ranked:Array = [];
        for (var slot:Number = 0; slot < SLOT_COUNT; slot++) {
            var sequence:Number = Number(
                slots[slot].lastDepletedSequence);
            if (sequence > 0) ranked.push({slot:slot, sequence:sequence});
        }
        for (var i:Number = 0; i < ranked.length; i++) {
            var best:Number = i;
            for (var j:Number = i + 1; j < ranked.length; j++) {
                if (Number(ranked[j].sequence)
                        < Number(ranked[best].sequence)
                        || (Number(ranked[j].sequence)
                            == Number(ranked[best].sequence)
                            && Number(ranked[j].slot)
                                < Number(ranked[best].slot))) {
                    best = j;
                }
            }
            if (best != i) {
                var swap:Object = ranked[i];
                ranked[i] = ranked[best];
                ranked[best] = swap;
            }
        }
        for (i = 0; i < ranked.length; i++) {
            slots[Number(ranked[i].slot)].lastDepletedSequence = i + 1;
        }
    }

    private static function maximumSlotSequence(slots:Array):Number {
        var maximum:Number = 0;
        for (var slot:Number = 0; slot < SLOT_COUNT; slot++) {
            var sequence:Number = Number(
                slots[slot].lastDepletedSequence);
            if (sequence > maximum) maximum = sequence;
        }
        return maximum;
    }

    private static function featureEquals(
        source:Object,
        normalized:Object
    ):Boolean {
        if (source == null || typeof source.version != "number"
                || source.version !== VERSION
                || !(source.slots instanceof Array)
                || source.slots.length != SLOT_COUNT
                || typeof source.nextDepletedSequence != "number"
                || source.nextDepletedSequence
                    !== normalized.nextDepletedSequence) return false;
        var allowed:Object = {
            version:true,
            slots:true,
            nextDepletedSequence:true
        };
        for (var featureKey:String in source) {
            if (allowed[featureKey] !== true) return false;
        }
        for (var slot:Number = 0; slot < SLOT_COUNT; slot++) {
            var sourceEntry:Object = source.slots[slot];
            var targetEntry:Object = normalized.slots[slot];
            if (sourceEntry == null || typeof sourceEntry != "object"
                    || typeof sourceEntry.itemKey != "string"
                    || sourceEntry.itemKey !== targetEntry.itemKey
                    || typeof sourceEntry.lastDepletedSequence != "number"
                    || sourceEntry.lastDepletedSequence
                        !== targetEntry.lastDepletedSequence) return false;
            var entryKeyCount:Number = 0;
            for (var entryKey:String in sourceEntry) {
                if (entryKey != "itemKey"
                        && entryKey != "lastDepletedSequence") return false;
                entryKeyCount++;
            }
            if (entryKeyCount != 2) return false;
        }
        return true;
    }

    private static function emptyEntry():Object {
        return {itemKey:"", lastDepletedSequence:0};
    }

    private static function validSlot(slot:Number):Boolean {
        return !isNaN(slot) && Math.floor(slot) == slot
            && slot >= 0 && slot < SLOT_COUNT;
    }

    private static function isWholeSequence(value:Number):Boolean {
        return !isNaN(value) && isFinite(value)
            && Math.floor(value) == value
            && value >= 0 && value <= MAX_SAFE_SEQUENCE;
    }

    private static function isWholeNextSequence(value:Number):Boolean {
        return isWholeSequence(value) && value >= 1;
    }

    private static function isWholePositive(value:Number):Boolean {
        return !isNaN(value) && isFinite(value)
            && Math.floor(value) == value
            && value > 0 && value <= MAX_SAFE_SEQUENCE;
    }
}
