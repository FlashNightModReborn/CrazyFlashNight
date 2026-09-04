import org.flashNight.arki.item.InventoryPanelService;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.item.PlayerAssetTransaction;
import org.flashNight.arki.item.RewardInboxService;
import org.flashNight.gesh.object.ObjectUtil;

/** 背包物品的封闭 open/consume/query 权威服务。 */
class org.flashNight.arki.item.ItemUseService {
    private static var _json:LiteJSON;
    private static var _inited:Boolean = false;
    private static var _busy:Boolean = false;
    private static var _testRandomValues:Array = null;
    private static var _contextValidator:Function = null;
    private static var MAX_SAFE_INTEGER:Number = 9007199254740991;

    /** CharacterBuildService 注入 exact panel/session 校验，避免两类双向静态依赖。 */
    public static function setContextValidator(validator:Function):Void {
        _contextValidator = validator;
    }

    public static function install():Void {
        if (_inited) return;
        RewardInboxService.installRootFacade();
        _json = new LiteJSON();
        if (_root.gameCommands == undefined) _root.gameCommands = {};
        _root.gameCommands["itemUseOpen"] = function(params) {
            org.flashNight.arki.item.ItemUseService.handle("open", params);
        };
        _root.gameCommands["itemUseConsume"] = function(params) {
            org.flashNight.arki.item.ItemUseService.handle("consume", params);
        };
        _root.gameCommands["itemUseQuery"] = function(params) {
            org.flashNight.arki.item.ItemUseService.handle("query", params);
        };
        _root.gameCommands["itemUseInboxSnapshot"] = function(params) {
            org.flashNight.arki.item.ItemUseService.handle("inboxSnapshot", params);
        };
        _root.gameCommands["itemUseCooldownSnapshot"] = function(params) {
            org.flashNight.arki.item.ItemUseService.handle("cooldownSnapshot", params);
        };
        _inited = true;
    }

    private static function handle(commandName:String, params:Object):Void {
        var response:Object = execute(commandName, params);
        response.task = "item_use_response";
        sendResponse(response);
    }

    public static function execute(commandName:String, params:Object):Object {
        if (_busy) return commonFailure(commandName, params, "service_not_ready");
        if (commandName != "open" && commandName != "consume"
                && commandName != "query" && commandName != "inboxSnapshot"
                && commandName != "cooldownSnapshot") {
            return commonFailure(commandName, params, "unsupported_cmd");
        }
        if (!validateEnvelope(commandName, params)) {
            var invalidOperation:Boolean = params != null && Number(params.v) == 1
                && commandName != "inboxSnapshot"
                && commandName != "cooldownSnapshot"
                && !validOperationId(params.operationId);
            return commonFailure(commandName, params,
                params == null || Number(params.v) != 1
                    ? "unsupported_version" : invalidOperation
                        ? "invalid_operation_id" : "invalid_payload");
        }
        var context:Object = null;
        try {
            if (_contextValidator != null) {
                context = _contextValidator(String(params.panelInstanceId),
                    Number(params.sessionGeneration));
            }
        } catch (contextError) {
            context = null;
        }
        if (context == null) {
            return commonFailure(commandName, params, "service_not_ready");
        }
        if (!context.success) return commonFailure(commandName, params, String(context.error));
        if (commandName == "query") return executeQuery(params);
        if (commandName == "inboxSnapshot") return executeInboxSnapshot(params);
        if (commandName == "cooldownSnapshot") return executeCooldownSnapshot(params);
        if (commandName == "open") return executeOpen(params);
        if (commandName == "consume") return executeConsume(params);
        return commonFailure(commandName, params, "unsupported_cmd");
    }

    private static function executeOpen(params:Object):Object {
        var operationId:String = String(params.operationId);
        var fingerprint:String = sourceFingerprint(params.source);
        var prior:Object = RewardInboxService.lookupReceipt(operationId);
        if (prior != null) {
            if (prior.kind != "open" || prior.fingerprint != fingerprint) {
                return commonFailure("open", params, "operation_conflict");
            }
            return openSuccess(params, prior);
        }
        var source:Object = validateBackpackSource(params.source);
        if (!source.success) return commonFailure("open", params, source.error);
        var itemData:Object = effectiveData(source.item);
        if (itemData == null || itemData.use !== "礼包") {
            return commonFailure("open", params, "unsupported_item");
        }
        var recipe:Object = normalizeRecipe(itemData.data == null
            ? null : itemData.data.rewardPack);
        if (!recipe.success) return commonFailure("open", params, "invalid_reward_pack");
        var rolled:Object = rollRecipe(recipe);
        if (!rolled.success) return commonFailure("open", params, "invalid_reward_pack");
        if (!RewardInboxService.canAppendOccurrenceCount(rolled.entries.length)) {
            return commonFailure("open", params, "reward_inbox_full");
        }

        var bag:Object = source.inventory;
        var bagBefore:Object = bag.toObject();
        var feature:Object = RewardInboxService.ensureFeature();
        if (feature == null) return commonFailure("open", params, "service_not_ready");
        var featureBefore:Object = ObjectUtil.clone(feature);
        var dirtyBefore = _root.存档系统 == null
            ? undefined : _root.存档系统.dirtyMark;
        var assetContext:Object = {source:"item_use", reason:"reward_pack_open",
            operationId:operationId, mergeScope:"operation"};
        var transaction:Object = PlayerAssetTransaction.begin(assetContext);
        var batch:Object = null;
        var remaining:Number = 0;
        _busy = true;
        try {
            PlayerAssetTransaction.markDirtyRequired(_root.存档系统);
            var before:Number = Number(source.item.value);
            bag.addValue(String(source.slot), -1);
            var afterItem:Object = bag.getItem(String(source.slot));
            remaining = afterItem == null ? 0 : Number(afterItem.value);
            if (before - remaining != 1) throw "source_commit_mismatch";
            PlayerAssetTransaction.recordEffect("loss", "item",
                String(source.item.name), 1, assetContext);
            batch = RewardInboxService.appendRewardBatch(
                String(source.item.name), operationId, rolled.entries);
            if (batch == null || batch.success !== true) throw "batch_append_failed";
            var receipt:Object = {operationId:operationId, kind:"open",
                status:"committed", fingerprint:fingerprint, consumed:1,
                remaining:remaining, rewardBatchId:String(batch.batchId),
                rewardReady:rewardSummaryReady(RewardInboxService.inboxSummary())};
            if (!RewardInboxService.recordReceipt(receipt)) throw "receipt_conflict";
            if (!flushSave()) throw "flush_failed";
            PlayerAssetTransaction.commit(transaction);
        } catch (openError) {
            var restored:Boolean = restoreOpenState(
                bag, bagBefore, featureBefore, dirtyBefore);
            PlayerAssetTransaction.settleAfterException(transaction, !restored);
            _busy = false;
            InventoryPanelService.invalidateExternalSlot("背包", Number(source.slot));
            return commonFailure("open", params, "commit_pending");
        }
        _busy = false;
        InventoryPanelService.invalidateExternalSlot("背包", Number(source.slot));
        return openSuccess(params, RewardInboxService.lookupReceipt(operationId));
    }

    private static function executeConsume(params:Object):Object {
        var operationId:String = String(params.operationId);
        var fingerprint:String = sourceFingerprint(params.source);
        var prior:Object = RewardInboxService.lookupReceipt(operationId);
        if (prior != null) {
            if (prior.kind != "consume" || prior.fingerprint != fingerprint) {
                return commonFailure("consume", params, "operation_conflict");
            }
            return consumeSuccess(params, prior);
        }
        var source:Object = validateBackpackSource(params.source);
        if (!source.success) return commonFailure("consume", params, source.error);
        var itemData:Object = effectiveData(source.item);
        if (itemData == null || itemData.use !== "药剂") {
            return commonFailure("consume", params, "unsupported_item");
        }
        var lane:Object = org.flashNight.arki.unit.Action.Skill.DrugInputService
            .selectDirectUseLane(String(source.item.name), _root.物品栏.药剂栏);
        if (lane == null || lane.success !== true) {
            return commonFailure("consume", params,
                lane == null ? "cooldown_unavailable" : String(lane.error));
        }
        var unit:Object = currentPlayerUnit();
        if (unit == null || Number(unit.hp) <= 0) {
            return commonFailure("consume", params, "player_unavailable");
        }
        // 与 open 路径对称：任何权威写之前先捕获 exact snapshot，receipt 无法
        // 落地时按同一粒度恢复，避免 Web 侧 not_committed 重试造成二次扣药。
        var bag:Object = source.inventory;
        var bagBefore:Object = bag.toObject();
        var dirtyBefore = _root.存档系统 == null
            ? undefined : _root.存档系统.dirtyMark;
        _busy = true;
        var used:Object = null;
        try {
            used = org.flashNight.arki.unit.Action.Skill.DrugInputService
                .consumeBackpackItem(unit, bag, Number(source.slot),
                    source.item, Number(lane.lane), _root);
        } catch (consumeError) {
            used = null;
        }
        _busy = false;
        if (used == null || used.used !== true) {
            return commonFailure("consume", params,
                used == null || used.error == undefined
                    ? "commit_pending" : String(used.error));
        }
        var receipt:Object = {operationId:operationId, kind:"consume",
            status:"committed", fingerprint:fingerprint, consumed:1,
            remaining:Number(used.remaining), selectedLane:Number(lane.lane)};
        if (!RewardInboxService.recordReceipt(receipt)) {
            if (!restoreConsumeState(bag, bagBefore, String(source.item.name),
                    Number(lane.lane), dirtyBefore)) {
                trace("[ItemUseService] consume restore incomplete after receipt failure: "
                    + operationId);
            }
            InventoryPanelService.invalidateExternalSlot("背包", Number(source.slot));
            return commonFailure("consume", params, "commit_pending");
        }
        if (_root.存档系统 != null) _root.存档系统.dirtyMark = true;
        InventoryPanelService.invalidateExternalSlot("背包", Number(source.slot));
        return consumeSuccess(params, receipt);
    }

    private static function executeQuery(params:Object):Object {
        var operationId:String = String(params.operationId);
        var receipt:Object = RewardInboxService.lookupReceipt(operationId);
        var summary:Object = RewardInboxService.inboxSummary();
        if (summary == null) return commonFailure("query", params,
            "service_not_ready");
        var response:Object = common("query", params, true, "");
        response.found = receipt != null;
        response.inboxSummary = summary;
        if (receipt == null) return response;
        response.receipt = projectReceipt(receipt);
        return response;
    }

    private static function executeInboxSnapshot(params:Object):Object {
        var summary:Object = RewardInboxService.inboxSummary();
        if (summary == null) return commonFailure("inboxSnapshot", params, "service_not_ready");
        var response:Object = common("inboxSnapshot", params, true, "");
        response.inboxSummary = summary;
        response.rewardReady = rewardSummaryReady(summary);
        response.rewardAuthority = response.rewardReady
            ? RewardInboxService.materializeAuthority() : null;
        return response;
    }

    /**
     * Web 角色构筑只读四条共享药剂冷却；每次采样都来自帧计时器驱动的
     * ManualCooldownService，不以浏览器现实时间替代游戏帧权威。
     */
    private static function executeCooldownSnapshot(params:Object):Object {
        var response:Object = common("cooldownSnapshot", params, true, "");
        var lanes:Array = [];
        try {
            for (var lane:Number = 0;
                    lane < org.flashNight.arki.unit.Action.Skill
                        .DrugInputService.LANE_COUNT; lane++) {
                var cooldown:Object = org.flashNight.arki.unit.Action.Skill
                    .ManualCooldownService.getSnapshot(
                        org.flashNight.arki.unit.Action.Skill
                            .ManualCooldownService.drugKey(lane));
                if (cooldown == null || typeof cooldown != "object") {
                    return commonFailure("cooldownSnapshot", params,
                        "cooldown_unavailable");
                }
                var totalSteps:Number = Math.max(0,
                    Math.floor(Number(cooldown.totalSteps)));
                var currentStep:Number = Math.max(0, Math.min(totalSteps,
                    Math.floor(Number(cooldown.currentStep))));
                var progressPercent:Number = Math.max(0, Math.min(100,
                    Math.floor(Number(cooldown.progressPercent))));
                var animationFrame:Number = Math.max(0,
                    Math.floor(Number(cooldown.animationFrame)));
                var ready:Boolean = cooldown.ready === true;
                lanes.push({lane:lane, ready:ready,
                    totalSteps:totalSteps, currentStep:currentStep,
                    progressPercent:progressPercent,
                    animationFrame:animationFrame,
                    remainingMs:ready ? 0 : Math.ceil(
                        (totalSteps - currentStep)
                        * org.flashNight.arki.unit.Action.Skill
                            .ManualCooldownService.FRAME_MS)});
            }
        } catch (cooldownError) {
            return commonFailure("cooldownSnapshot", params,
                "cooldown_unavailable");
        }
        response.cooldownLanes = lanes;
        return response;
    }

    private static function rewardSummaryReady(summary:Object):Boolean {
        return summary != null && (Number(summary.remainingCount) > 0
            || summary.recoveryRequired === true);
    }

    private static function openSuccess(params:Object, receipt:Object):Object {
        var response:Object = common("open", params, true, "");
        response.consumed = 1;
        response.remaining = Number(receipt.remaining);
        response.rewardReady = receipt.rewardReady === true;
        response.rewardBatchId = String(receipt.rewardBatchId);
        response.inboxSummary = RewardInboxService.inboxSummary();
        response.rewardAuthority = response.rewardReady
            ? RewardInboxService.materializeAuthority() : null;
        return response;
    }

    private static function consumeSuccess(params:Object, receipt:Object):Object {
        var response:Object = common("consume", params, true, "");
        response.consumed = 1;
        response.remaining = Number(receipt.remaining);
        response.selectedLane = Number(receipt.selectedLane);
        return response;
    }

    /** CharacterBuild backpack overview 的独立 use capability。 */
    public static function buildCandidateUseAction(item:Object, itemData:Object,
                                                   physicalSlot:Number,
                                                   slotLease:String,
                                                   backpackVersion:Number):Object {
        var none:Object = {useAction:null, useBlockedReason:""};
        if (item == null || itemData == null || typeof itemData.use != "string") return none;
        var command:String = "";
        var label:String = "";
        var blocked:String = "";
        if (itemData.use === "礼包") {
            var recipe:Object = normalizeRecipe(itemData.data == null
                ? null : itemData.data.rewardPack);
            if (!recipe.success) return none;
            command = "open";
            label = "打开";
            var summary:Object = RewardInboxService.inboxSummary();
            if (summary == null) blocked = "service_not_ready";
            else if (Number(summary.remainingCount) + Number(recipe.maxOccurrences)
                    > RewardInboxService.MAX_OCCURRENCES) blocked = "reward_inbox_full";
        } else if (itemData.use === "药剂") {
            command = "consume";
            label = "服用";
            var unit:Object = currentPlayerUnit();
            if (unit == null || Number(unit.hp) <= 0) blocked = "player_unavailable";
            else if (_root == null || _root.物品栏 == null
                    || _root.物品栏.药剂栏 == null) {
                blocked = "service_not_ready";
            } else {
                var lane:Object = org.flashNight.arki.unit.Action.Skill.DrugInputService
                    .selectDirectUseLane(String(item.name), _root.物品栏.药剂栏);
                if (lane == null) blocked = "cooldown_unavailable";
                else if (lane.success !== true) blocked = String(lane.error);
            }
        } else return none;
        return {useAction:{command:command, label:label,
            source:{physicalSlot:physicalSlot, slotLease:slotLease,
                itemName:String(item.name), backpackVersion:backpackVersion}},
            useBlockedReason:blocked};
    }

    /** fixed/independent/chooseOne 的唯一 recipe normalizer。 */
    public static function normalizeRecipe(raw:Object):Object {
        if (raw == null || typeof raw != "object") return {success:false};
        var mode:String = String(raw.mode || "");
        if (mode != "fixed" && mode != "independent" && mode != "chooseOne") {
            return {success:false};
        }
        var rawEntries = raw.entries == null ? null : raw.entries.entry;
        var source:Array = rawEntries instanceof Array ? rawEntries : [rawEntries];
        if (rawEntries == null || source.length < 1 || source.length > 64) {
            return {success:false};
        }
        var entries:Array = [];
        var totalWeight:Number = 0;
        for (var i:Number = 0; i < source.length; i++) {
            var entry:Object = source[i];
            if (entry == null || typeof entry.itemName != "string"
                    || !ItemUtil.isItem(String(entry.itemName))) return {success:false};
            var minimum:Number = Number(entry.quantityMin);
            var maximum:Number = Number(entry.quantityMax);
            if (!positiveWhole(minimum) || !positiveWhole(maximum)
                    || maximum < minimum) return {success:false};
            if (ItemUtil.isEquipment(String(entry.itemName)) && maximum != 1) {
                return {success:false};
            }
            var normalized:Object = {itemName:String(entry.itemName),
                quantityMin:minimum, quantityMax:maximum};
            if (mode == "independent") {
                var numerator:Number = Number(entry.chanceNumerator);
                var denominator:Number = Number(entry.chanceDenominator);
                if (!positiveWhole(numerator) || !positiveWhole(denominator)
                        || numerator > denominator) return {success:false};
                normalized.chanceNumerator = numerator;
                normalized.chanceDenominator = denominator;
            } else if (mode == "chooseOne") {
                var weight:Number = Number(entry.weight);
                if (!positiveWhole(weight) || totalWeight + weight > MAX_SAFE_INTEGER) {
                    return {success:false};
                }
                normalized.weight = weight;
                totalWeight += weight;
            }
            entries.push(normalized);
        }
        return {success:true, mode:mode, entries:entries,
            totalWeight:totalWeight,
            maxOccurrences:mode == "chooseOne" ? 1 : entries.length};
    }

    private static function rollRecipe(recipe:Object):Object {
        var rolled:Array = [];
        var entries:Array = recipe.entries;
        if (recipe.mode == "chooseOne") {
            var draw:Number = nextRandomInt(Number(recipe.totalWeight));
            var cursor:Number = 0;
            for (var c:Number = 0; c < entries.length; c++) {
                cursor += Number(entries[c].weight);
                if (draw < cursor) {
                    rolled.push(rollEntry(entries[c]));
                    break;
                }
            }
        } else {
            for (var i:Number = 0; i < entries.length; i++) {
                var entry:Object = entries[i];
                if (recipe.mode == "independent"
                        && nextRandomInt(Number(entry.chanceDenominator))
                            >= Number(entry.chanceNumerator)) continue;
                rolled.push(rollEntry(entry));
            }
        }
        return {success:true, entries:rolled};
    }

    private static function rollEntry(entry:Object):Object {
        var span:Number = Number(entry.quantityMax) - Number(entry.quantityMin) + 1;
        return {itemName:String(entry.itemName),
            quantity:Number(entry.quantityMin) + nextRandomInt(span)};
    }

    private static function nextRandomInt(bound:Number):Number {
        if (!positiveWhole(bound)) return 0;
        if (_testRandomValues != null && _testRandomValues.length > 0) {
            var value:Number = Number(_testRandomValues.shift());
            if (!nonNegativeWhole(value)) value = 0;
            return value % bound;
        }
        return random(bound);
    }

    private static function validateBackpackSource(ref:Object):Object {
        var slotRef:Object = {containerId:"背包", slot:Number(ref.physicalSlot),
            expectedLease:String(ref.slotLease)};
        var checked:Object = InventoryPanelService.validateExternalSlotRef(slotRef, true);
        if (checked == null || checked.success !== true) {
            return {success:false, error:"stale_source"};
        }
        if (Number(ref.backpackVersion) != checked.inventory.getMutationRevision()
                || String(ref.itemName) != String(checked.item.name)) {
            return {success:false, error:"stale_source"};
        }
        return {success:true, inventory:checked.inventory,
            slot:Number(checked.slot), item:checked.item};
    }

    private static function effectiveData(item:Object):Object {
        try { return item == null || typeof item.getData != "function" ? null : item.getData(); }
        catch (dataError) { return null; }
    }

    private static function currentPlayerUnit():Object {
        if (_root == null || typeof _root.控制目标 != "string"
                || _root.gameworld == null) return null;
        var unit:Object = _root.gameworld[_root.控制目标];
        return unit == null || unit._name !== _root.控制目标 ? null : unit;
    }

    private static function validateEnvelope(commandName:String, params:Object):Boolean {
        if (params == null || params.v !== 1 || params.task !== "cmd"
                || typeof params.callId != "number" || !positiveWhole(Number(params.callId))
                || typeof params.panelInstanceId != "string"
                || String(params.panelInstanceId).length < 1
                || !positiveWhole(Number(params.sessionGeneration))) return false;
        var expectedAction:String = commandName == "open" ? "itemUseOpen"
            : commandName == "consume" ? "itemUseConsume"
            : commandName == "query" ? "itemUseQuery"
            : commandName == "inboxSnapshot" ? "itemUseInboxSnapshot"
            : commandName == "cooldownSnapshot" ? "itemUseCooldownSnapshot" : "";
        if (expectedAction == "" || params.action !== expectedAction) return false;
        if (commandName == "inboxSnapshot" || commandName == "cooldownSnapshot") {
            return onlyKeys(params,
            ["task","action","callId","v","panelInstanceId","sessionGeneration"]);
        }
        if (!validOperationId(params.operationId)) return false;
        if (commandName == "query") return onlyKeys(params,
            ["task","action","callId","v","operationId","panelInstanceId","sessionGeneration"]);
        if (!onlyKeys(params,["task","action","callId","v","operationId",
                "panelInstanceId","sessionGeneration","source"])) return false;
        var source:Object = params.source;
        return source != null && onlyKeys(source,
            ["physicalSlot","slotLease","itemName","backpackVersion"])
            && whole(Number(source.physicalSlot)) && Number(source.physicalSlot) >= 0
            && Number(source.physicalSlot) < 50 && typeof source.slotLease == "string"
            && String(source.slotLease).length > 0 && typeof source.itemName == "string"
            && String(source.itemName).length > 0
            && nonNegativeWhole(Number(source.backpackVersion));
    }

    private static function onlyKeys(value:Object, allowed:Array):Boolean {
        if (value == null || typeof value != "object" || value instanceof Array) return false;
        for (var key:String in value) {
            var found:Boolean = false;
            for (var i:Number = 0; i < allowed.length; i++) {
                if (key == allowed[i]) { found = true; break; }
            }
            if (!found) return false;
        }
        return true;
    }

    private static function sourceFingerprint(source:Object):String {
        return String(source.physicalSlot) + "|" + String(source.slotLease) + "|"
            + String(source.itemName) + "|" + String(source.backpackVersion);
    }

    private static function projectReceipt(receipt:Object):Object {
        var projected:Object = {kind:String(receipt.kind), status:"committed",
            consumed:Number(receipt.consumed), remaining:Number(receipt.remaining)};
        if (receipt.rewardBatchId != undefined) projected.rewardBatchId = String(receipt.rewardBatchId);
        if (receipt.selectedLane != undefined) projected.selectedLane = Number(receipt.selectedLane);
        if (receipt.rewardReady != undefined) projected.rewardReady = receipt.rewardReady === true;
        return projected;
    }

    private static function common(commandName:String, params:Object,
                                   success:Boolean, errorCode:String):Object {
        var response:Object = {task:"item_use_response", v:1, success:success,
            command:commandName,
            callId:params == null ? undefined : params.callId,
            panelInstanceId:params == null ? undefined : params.panelInstanceId,
            sessionGeneration:params == null ? 0 : Number(params.sessionGeneration)};
        if (commandName != "inboxSnapshot" && commandName != "cooldownSnapshot") {
            response.operationId = params == null ? undefined : params.operationId;
        }
        if (!success) response.error = errorCode;
        return response;
    }

    private static function commonFailure(commandName:String, params:Object,
                                          errorCode:String):Object {
        return common(commandName, params, false, errorCode);
    }

    private static function restoreOpenState(bag:Object, bagBefore:Object,
                                             featureBefore:Object,
                                             dirtyBefore):Boolean {
        try {
            bag.setItems(bagBefore);
            _root._saveExt.rewardInbox = featureBefore;
            if (_root.存档系统 != null) _root.存档系统.dirtyMark = dirtyBefore;
            return true;
        } catch (restoreError) { return false; }
    }

    /**
     * consume 的 exact snapshot 恢复，粒度对齐 restoreOpenState：整体回滚背包、
     * 还原 dirtyMark；药剂 lane 冷却是 consume 独有且可被 reset 安全逆操作的
     * 副作用，一并复位。root.使用药剂 的药效没有通用逆操作，保持已发生事实
     * （与 DrugInputService 异常恢复惯例一致）；consume 内部事务已播报的 loss
     * 无法收回，补一笔对冲 gain 保持资产流水与 HUD 播报净零。
     */
    private static function restoreConsumeState(bag:Object, bagBefore:Object,
                                                itemName:String, lane:Number,
                                                dirtyBefore):Boolean {
        var restored:Boolean = true;
        try {
            bag.setItems(bagBefore);
        } catch (restoreError) { restored = false; }
        try {
            org.flashNight.arki.unit.Action.Skill.ManualCooldownService.reset(
                org.flashNight.arki.unit.Action.Skill.ManualCooldownService
                    .drugKey(lane));
        } catch (cooldownError) { }
        if (restored) {
            try {
                PlayerAssetTransaction.recordEffect("gain", "item", itemName, 1,
                    {source:"item_use", reason:"direct_drug_use_reverted",
                        mergeScope:"operation"});
            } catch (effectError) { }
        }
        try {
            if (_root.存档系统 != null) _root.存档系统.dirtyMark = dirtyBefore;
        } catch (dirtyError) { }
        return restored;
    }

    private static function flushSave():Boolean {
        // R1 步骤 9：durable cut 内核换 flushDurableNow；false/异常语义不变
        if (_root.存档系统 == null || typeof _root.存档系统.flushDurableNow != "function") return false;
        try { return _root.存档系统.flushDurableNow("item_use.open_commit") === true; }
        catch (saveError) { return false; }
    }

    private static function sendResponse(response:Object):Void {
        if (_root.server == null || typeof _root.server.sendSocketMessage != "function") return;
        if (_json == undefined) _json = new LiteJSON();
        _root.server.sendSocketMessage(_json.stringifySafe(response));
    }

    private static function validOperationId(value):Boolean {
        if (typeof value != "string") return false;
        var text:String = String(value);
        if (text.length < 1 || text.length > 96) return false;
        for (var i:Number = 0; i < text.length; i++) {
            var code:Number = text.charCodeAt(i);
            var valid:Boolean = (code >= 48 && code <= 57)
                || (code >= 65 && code <= 90) || (code >= 97 && code <= 122)
                || code == 45 || code == 46 || code == 58 || code == 95;
            if (!valid) return false;
        }
        return true;
    }

    private static function whole(value:Number):Boolean {
        return !isNaN(value) && Math.floor(value) == value;
    }
    private static function nonNegativeWhole(value:Number):Boolean {
        return whole(value) && value >= 0;
    }
    private static function positiveWhole(value:Number):Boolean {
        return whole(value) && value > 0 && value <= MAX_SAFE_INTEGER;
    }

    public static function setRandomValuesForTests(values:Array):Void {
        _testRandomValues = values == null ? null : values.concat();
    }
}
