import org.flashNight.arki.item.BaseItem;
import org.flashNight.arki.item.ItemUtil;

import org.flashNight.arki.item.EquipmentUtil;
import org.flashNight.arki.item.InventoryPanelService;
import org.flashNight.arki.item.MaterialArchiveProjector;
import org.flashNight.arki.item.ProcurementPlanService;
import org.flashNight.arki.item.PlayerAssetTransaction;
import org.flashNight.arki.item.obtain.ItemObtainIndex;
import org.flashNight.arki.item.synthesis.SynthesisIndex;
import org.flashNight.gesh.object.ObjectUtil;
import org.flashNight.gesh.object.PersistedSnapshot;
import org.flashNight.gesh.string.StringUtils;

/**
 * 合成 Web Panel 的 Flash 权威服务。
 * C0-C3：目录投影/单份可合成状态、批量权威预览与一次性 token 原子提交。
 */
class org.flashNight.arki.item.CraftingPanelService {
    private static var _installed:Boolean = false;
    private static var _busy:Boolean = false;
    private static var _json:LiteJSON;
    private static var _plan:Object = null;
    private static var _planSeq:Number = 0;
    private static var _categories:Object = {};
    private static var MAX_CRAFT_COUNT:Number = 99;
    private static var _availabilityPlanCount:Number = 0;
    private static var _maximumProbeCount:Number = 0;

    public static function install():Void {
        if (_installed) return;
        _installed = true;
        _categories["铁枪会"] = true;
        _categories["属性武器"] = true;
        _categories["烹饪"] = true;
        _categories["化学生产"] = true;
        _categories["武器合成"] = true;
        _categories["饰品合成"] = true;
        _categories["进阶防具"] = true;
        _categories["基础防具"] = true;
        _categories["公社防具"] = true;
        _categories["黑白契约"] = true;
        _categories["插件合成"] = true;
        _categories["大学装备"] = true;
        _categories["书中配给"] = true;
        _categories["调酒"] = true;
        _json = new LiteJSON();
        _root.gameCommands["craftingSnapshot"] = function(params) {
            org.flashNight.arki.item.CraftingPanelService.handle("snapshot", params);
        };
        _root.gameCommands["craftingMaterials"] = function(params) {
            org.flashNight.arki.item.CraftingPanelService.handle("materials", params);
        };
        _root.gameCommands["craftingMaterialDetail"] = function(params) {
            org.flashNight.arki.item.CraftingPanelService.handle("materialDetail", params);
        };
        _root.gameCommands["craftingMaterialShopAuthorize"] = function(params) {
            org.flashNight.arki.item.CraftingPanelService.handleMaterialShopAuthorize(params);
        };
        _root.gameCommands["craftingProcurementShopAuthorize"] = function(params) {
            org.flashNight.arki.item.CraftingPanelService.handleProcurementShopAuthorize(params);
        };
        _root.gameCommands["craftingProcurementKShopAuthorize"] = function(params) {
            org.flashNight.arki.item.CraftingPanelService.handleProcurementKShopAuthorize(params);
        };
        _root.gameCommands["craftingPreview"] = function(params) {
            org.flashNight.arki.item.CraftingPanelService.handle("preview", params);
        };
        _root.gameCommands["craftingTooltip"] = function(params) {
            org.flashNight.arki.item.CraftingPanelService.handle("tooltip", params);
        };
        _root.gameCommands["craftingPlanSet"] = function(params) {
            org.flashNight.arki.item.CraftingPanelService.handle("setPlan", params);
        };
        _root.gameCommands["craftingCommit"] = function(params) {
            org.flashNight.arki.item.CraftingPanelService.handle("commit", params);
        };
        _root.gameCommands["openCraftingWorkbench"] = function(params):Boolean {
            return org.flashNight.arki.item.CraftingPanelService.openPanel(
                params == undefined ? "" : String(params.category || ""),
                params == undefined ? "crafting_entry" : String(params.source || "crafting_entry")
            );
        };
    }

    public static function openPanel(category:String, source:String):Boolean {
        if (!isCategory(category) || _root.改装清单 == undefined
                || !(_root.改装清单[category] instanceof Array)) return false;
        if (_root.server == undefined || _root.server.sendSocketMessage == undefined) return false;
        if (source != "world_crafting_entry" && source != "world_npc"
                && source != "crafting_entry") source = "crafting_entry";
        var payload:String = org.flashNight.arki.ui.PanelRequestEnvelope.build(
            "crafting", source, [], [{name:"category", value:category}]
        );
        return _root.server.sendSocketMessage(payload);
    }

    public static function openMaterialsPanel(source:String, openRequestId):Boolean {
        if (_root.server == undefined || _root.server.sendSocketMessage == undefined) return false;
        if (source != "nativehud_materials") source = "nativehud_materials";
        var fields:Array = [];
        if (arguments.length >= 2) {
            var safeRequestId:String = safeOpenRequestId(openRequestId);
            if (safeRequestId == null) return false;
            fields.push({name:"openRequestId", value:safeRequestId});
        }
        var payload:String = org.flashNight.arki.ui.PanelRequestEnvelope.build(
            "crafting", source, fields, [{name:"view", value:"materials"}]
        );
        return _root.server.sendSocketMessage(payload);
    }

    private static function safeOpenRequestId(value):String {
        if (typeof(value) != "string") return null;
        var token:String = String(value);
        if (token.length < 1 || token.length > 160) return null;
        for (var i:Number = 0; i < token.length; i++) {
            var code:Number = token.charCodeAt(i);
            var allowed:Boolean = (code >= 48 && code <= 57)
                || (code >= 65 && code <= 90)
                || (code >= 97 && code <= 122)
                || code == 45 || code == 46 || code == 95 || code == 126;
            if (!allowed) return null;
        }
        return token;
    }

    /**
     * 旧数据只在 AS2 authority projection 边界补齐展示与图标键。
     * 空白值必须回落到内部名，不能继续下发给 Host/Web 再次猜测。
     */
    private static function projectLegacyIdentityField(value, name:String):String {
        var projected:String = typeof value == "string" ? String(value) : "";
        var trimmed:String = StringUtils.trim(projected);
        return trimmed.length == 0 || trimmed.toLowerCase() == "undefined"
            ? name : projected;
    }

    public static function handle(commandName:String, params:Object):Void {
        var callId:Number = params == undefined ? 0 : Number(params.callId);
        var response:Object;
        if (commandName == "setPlan") {
            if (_busy) response = fail("busy");
            else {
                _busy = true;
                response = ProcurementPlanService.setPlanFromWire(params || {});
                _busy = false;
            }
        } else response = execute(commandName, params || {});
        response.task = "crafting_response";
        response.callId = callId;
        sendResponse(response);
    }

    /**
     * A4b Host-only authority wire. It has its own response task and deliberately
     * bypasses CraftingTask/crafting_response/_busy. An uncorrelatable fid is
     * dropped; every correlatable malformed request receives exact invalid_payload.
     */
    public static function handleMaterialShopAuthorize(params:Object):Void {
        if (!validMaterialShopAccessCallId(params)) return;
        var response:Object = MaterialArchiveProjector.authorizeShopAccess(params);
        sendResponse(response);
    }

    public static function handleProcurementShopAuthorize(params:Object):Void {
        if (!validMaterialShopAccessCallId(params)) return;
        var response:Object = ProcurementPlanService.authorizeShopAccess(params);
        sendResponse(response);
    }

    public static function handleProcurementKShopAuthorize(params:Object):Void {
        if (!validMaterialShopAccessCallId(params)) return;
        var response:Object = ProcurementPlanService.authorizeKShopAccess(params);
        sendResponse(response);
    }

    private static function validMaterialShopAccessCallId(params:Object):Boolean {
        if (params == null || typeof params != "object"
                || typeof params.callId != "number") return false;
        var callId:Number = Number(params.callId);
        return !isNaN(callId) && (callId - callId) == 0
            && Math.floor(callId) == callId
            && callId >= 1 && callId <= 2147483647;
    }

    public static function execute(commandName:String, params:Object):Object {
        if (_busy && commandName != "snapshot" && commandName != "materials"
                && commandName != "materialDetail" && commandName != "tooltip") return fail("busy");
        if (commandName == "snapshot") return executeSnapshot(params);
        if (commandName == "materials") return executeMaterials(params);
        if (commandName == "materialDetail") return executeMaterialDetail(params);
        if (commandName == "preview") return executePreview(params);
        if (commandName == "tooltip") return executeTooltip(params);
        if (commandName == "setPlan") {
            _busy = true;
            try {
                return ProcurementPlanService.setPlan(params);
            } finally {
                _busy = false;
            }
        }
        if (commandName != "commit") return fail("unsupported_cmd");
        _busy = true;
        try {
            return executeCommit(params);
        } finally {
            _busy = false;
        }
    }

    private static function executeSnapshot(params:Object):Object {
        if (params != null && params.materialSnapshotId != undefined) {
            var navigationError:String = MaterialArchiveProjector.authorizeCraftingAccess(
                params.materialSnapshotId);
            if (navigationError != "") return fail(navigationError);
        }
        var category:String = String(params.category || "");
        var recipes:Array = getRecipes(category);
        if (recipes == null) return fail("category_not_found");
        _plan = null;
        var catalog:Array = [];
        var procurementSources:Object = ProcurementPlanService.buildPurchaseSourceIndex();
        var ownedIndex:Object = ProcurementPlanService.buildOwnedIndex();
        for (var i:Number = 0; i < recipes.length; i++) {
            var projected:Object = projectRecipe(
                category, recipes[i], i, procurementSources, ownedIndex);
            if (projected != null) catalog.push(projected);
        }
        var snapshot:Object = {success:true, v:1, category:category, gender:buildGender(), recipes:catalog,
            balance:buildBalance(), skills:buildSkills(),
            procurement:ProcurementPlanService.buildPlanSummary(),
            note:categoryNote(category)};
        if (params != null && params.supportsBattleBox === true) {
            snapshot.battleBoxAccessible = InventoryPanelService.getAccessibleCapacity("战备箱") > 0;
        }
        return snapshot;
    }

    private static function executeMaterials(params:Object):Object {
        var version:Number = materialRequestVersion(params);
        if (version == 2) return MaterialArchiveProjector.executeMaterials();
        if (version != 1) return fail("unsupported_version");
        MaterialArchiveProjector.reset();
        var informationByName:Object = buildMaterialInformationIndex();
        var names:Array = [];
        var seen:Object = {};
        var name:String;
        for (name in informationByName) {
            if (ObjectUtil.isInternalKey(name) || seen[name]) continue;
            seen[name] = true;
            names.push(name);
        }
        for (name in ItemUtil.materialDict) {
            if (ObjectUtil.isInternalKey(name) || seen[name]) continue;
            seen[name] = true;
            names.push(name);
        }
        names.sort();

        var index:ItemObtainIndex = ItemObtainIndex.getInstance();
        var catalog:Array = [];
        for (var i:Number = 0; i < names.length; i++) {
            name = String(names[i]);
            var data:Object = ItemUtil.getRawItemData(name);
            if (data == null || !ItemUtil.isMaterial(name)) continue;
            var records:Array = index.getObtainRecords(name);
            var uses:Array = SynthesisIndex.getRecipesUsing(name);
            catalog.push({
                name:name,
                displayName:projectLegacyIdentityField(data.displayname, name),
                icon:projectLegacyIdentityField(data.icon, name),
                owned:Number(_root.收集品栏.材料.getValue(name) || 0),
                sourceCount:records == null ? 0 : records.length,
                useCount:uses.length,
                hasSourceSummary:String(informationByName[name] || "").length > 0
            });
        }
        return {success:true, v:1, view:"materials", materials:catalog};
    }

    private static function executeMaterialDetail(params:Object):Object {
        var version:Number = materialRequestVersion(params);
        if (version == 2) return MaterialArchiveProjector.executeMaterialDetail(params);
        if (version != 1) return fail("unsupported_version");
        var name:String = String(params.itemName || "");
        if (!ItemUtil.isMaterial(name)) return fail("item_not_found");
        var data:Object = ItemUtil.getRawItemData(name);
        if (data == null) return fail("item_not_found");
        var informationByName:Object = buildMaterialInformationIndex();
        var index:ItemObtainIndex = ItemObtainIndex.getInstance();
        var records:Array = index.getObtainRecords(name);
        var sources:Array = [];
        for (var i:Number = 0; records != null && i < records.length; i++) {
            var projected:Object = projectObtainRecord(records[i]);
            if (projected != null) sources.push(projected);
        }
        var products:Array = SynthesisIndex.getRecipesUsing(name);
        var uses:Array = [];
        for (i = 0; i < products.length; i++) {
            var use:Object = projectMaterialUse(name, String(products[i]), index);
            if (use != null) uses.push(use);
        }
        return {
            success:true,
            v:1,
            view:"materials",
            material:{
                name:name,
                displayName:projectLegacyIdentityField(data.displayname, name),
                icon:projectLegacyIdentityField(data.icon, name),
                description:String(data.description || ""),
                owned:Number(_root.收集品栏.材料.getValue(name) || 0),
                sourceSummary:String(informationByName[name] || "")
            },
            sources:sources,
            uses:uses
        };
    }

    private static function buildMaterialInformationIndex():Object {
        var result:Object = {};
        var dictionary:Object = _root.图鉴信息 == undefined
            ? null : _root.图鉴信息.材料大全;
        if (dictionary == null) return result;
        var rows:Array = dictionary instanceof Array ? dictionary : [dictionary];
        for (var i:Number = 0; i < rows.length; i++) {
            var row:Object = rows[i];
            var name:String = String(row == null ? "" : row.Name || "");
            if (name == "") continue;
            result[name] = String(row.Information || "");
        }
        return result;
    }

    /** 旧 Host/直接 AS2 caller 未携 v 时维持 v1；显式版本必须是整数。 */
    private static function materialRequestVersion(params:Object):Number {
        if (params == null || params.v === undefined) return 1;
        if (typeof params.v != "number") return -1;
        var version:Number = Number(params.v);
        return isNaN(version) || (version - version) != 0
            || Math.floor(version) != version ? -1 : version;
    }

    private static function projectObtainRecord(record:Object):Object {
        if (record == null) return null;
        var kind:String = String(record.kind || "");
        if (kind == ItemObtainIndex.KIND_CRAFT) {
            return {kind:"craft", category:String(record.category || ""),
                price:Number(record.price || 0), kpoints:Number(record.kprice || 0)};
        }
        if (kind == ItemObtainIndex.KIND_SHOP) {
            return {kind:"shop", npc:String(record.npc || ""),
                requirement:String(record.requiredInfo || "")};
        }
        if (kind == ItemObtainIndex.KIND_KSHOP) {
            return {kind:"kshop", category:String(record.type || ""),
                priceK:Number(record.priceK || 0)};
        }
        if (kind == ItemObtainIndex.KIND_QUEST) {
            return {kind:"quest", questId:String(record.questId || ""),
                title:projectVisibleSourceLabel(record.questTitle, "未知任务"),
                quantity:Number(record.quantity || 0)};
        }
        if (kind != ItemObtainIndex.KIND_DROP) return null;
        if (String(record.dropType) == ItemObtainIndex.DROP_TYPE_STAGE) {
            return {kind:"stage", stageName:String(record.stageName || ""),
                probability:Number(record.probability || 0),
                quantityMax:Number(record.quantityMax || 0)};
        }
        var enemyType:String = String(record.enemyType || "");
        var enemyProperties:Object = _root.敌人属性表 == undefined
            ? null : _root.敌人属性表[enemyType];
        var resolvedEnemyName:Object = enemyProperties == null
            ? undefined : enemyProperties.displayname;
        return {kind:"enemy", enemyType:enemyType,
            displayName:projectVisibleSourceLabel(resolvedEnemyName, "未知敌人"),
            probability:Number(record.probability || 0),
            minLevel:Number(record.minLevel || 0),
            maxLevel:Number(record.maxLevel || 0)};
    }

    private static function projectVisibleSourceLabel(value, fallback:String):String {
        var projected:String = typeof value == "string" ? String(value) : "";
        var trimmed:String = StringUtils.trim(projected);
        if (trimmed.length == 0 || trimmed.toLowerCase() == "undefined") return fallback;
        return projected;
    }

    private static function projectMaterialUse(inputName:String, productName:String,
            index:ItemObtainIndex):Object {
        var data:Object = ItemUtil.getRawItemData(productName);
        if (data == null) return null;
        var recipe:Object = null;
        if (data.synthesis != undefined) recipe = SynthesisIndex.getRecipe(String(data.synthesis));
        if (recipe == null) recipe = SynthesisIndex.getRecipe(productName);
        var required:Number = 0;
        if (recipe != null) {
            var requirements:Array = ItemUtil.getRequirementFromTask(recipe.materials || []);
            for (var i:Number = 0; i < requirements.length; i++) {
                if (String(requirements[i].name) != inputName) continue;
                required += Number(requirements[i].value || 0);
            }
        }
        var category:String = "";
        var records:Array = index.getObtainRecords(productName);
        for (i = 0; records != null && i < records.length; i++) {
            if (String(records[i].kind) != ItemObtainIndex.KIND_CRAFT) continue;
            category = String(records[i].category || "");
            break;
        }
        var item:Object = projectItem(productName, 1);
        return {name:productName, displayName:projectLegacyIdentityField(data.displayname, productName),
            icon:projectLegacyIdentityField(data.icon, productName), itemKind:String(item.itemKind || "stack"),
            category:category, required:required};
    }

    private static function executePreview(params:Object):Object {
        // 任意新预览意图先撤销旧计划；即使新参数非法，也不能保留旧 token。
        _plan = null;
        var category:String = String(params.category || "");
        var recipeIndex:Number = Number(params.recipeIndex);
        var craftCount:Number = Number(params.craftCount);
        if (isNaN(craftCount) || Math.floor(craftCount) != craftCount
                || craftCount < 1 || craftCount > MAX_CRAFT_COUNT) return fail("invalid_payload");
        var resolved:Object = resolveRecipe(category, recipeIndex);
        if (!resolved.success) return resolved;
        // 调制方式是配方级权威声明：Web 只提交选择，匹配裁决在此完成；
        // 已配平的选择随计划冻结进 acceptedPlan，preview→commit 不可漂移。
        var declared:Object = declaredTechnique(resolved.recipe);
        var chosenTechnique:Object = null;
        if (declared == null) {
            if (params.technique != undefined) return fail("technique_not_supported");
        } else {
            chosenTechnique = matchTechnique(declared, params.technique);
            if (chosenTechnique == null) return fail("technique_mismatch");
        }
        if (params.useBattleBox != undefined && typeof params.useBattleBox != "boolean") {
            return fail("invalid_payload");
        }
        var useBattleBox:Boolean = params.useBattleBox === true;
        var plan:Object = buildPlan(category, recipeIndex, resolved.recipe, craftCount, true,
            null, null, chosenTechnique, useBattleBox);
        if (!plan.success) return plan;
        if (plan.canCommit) {
            _planSeq++;
            plan.token = "craft." + getTimer() + "." + _planSeq;
            _plan = plan;
        }
        return projectPreview(plan);
    }

    private static function executeTooltip(params:Object):Object {
        var itemName:String = String(params.itemName || "");
        if (!ItemUtil.isItem(itemName)) return fail("item_not_found");
        var tooltip:Object = _root.Web物品注释HTML(itemName);
        if (tooltip == null) return fail("tooltip_failed");
        // wire 由 sendResponse 的 stringifySafe 统一转义；这里保留原始双引号属性，
        // Web 端 convertAS2Html 的 DOMParser 两种引号风格都正确解析。
        return {success:true, v:1, itemName:itemName,
            displayname:String(tooltip.displayname || itemName),
            descHTML:String(tooltip.descHTML || ""),
            introHTML:String(tooltip.introHTML || ""),
            // COMMON v1 语义文档：纯数据透传（纯文本 title/runs，Host/Web 不得二次解析）
            tooltipInput: tooltip.tooltipInput};
    }

    private static function executeCommit(params:Object):Object {
        var category:String = String(params.category || "");
        var expectedToken:String = String(params.expectedCraftToken || "");
        var plan:Object = _plan;
        _plan = null;
        if (plan == null || expectedToken == "" || expectedToken != String(plan.token)
                || category != String(plan.category)) return fail("stale_state");

        var resolved:Object = resolveRecipe(category, Number(plan.recipeIndex));
        if (!resolved.success || recipeSignature(resolved.recipe) != String(plan.recipeSignature)) {
            return fail("stale_state");
        }
        var useBattleBox:Boolean = plan.useBattleBox === true;
        var current:Object = buildPlan(category, Number(plan.recipeIndex), resolved.recipe,
            Number(plan.craftCount), false, null, null, plan.technique, useBattleBox);
        if (!current.success || current.stateSignature != String(plan.stateSignature)) return fail("stale_state");
        if (!current.canCommit) return fail(String(current.blockingError || "stale_state"));
        // 配方、进阶配置与产物投影都必须在首次写入前与预览冻结计划完全一致。
        if (!deepEqual(current.acceptedPlan, plan.acceptedPlan, 0)) return fail("stale_state");

        var bag:Object = _root.物品栏.背包;
        var drugs:Object = _root.物品栏.药剂栏;
        var battleBox:Object = _root.物品栏.战备箱;
        var materials:Object = _root.收集品栏.材料;
        var intelligence:Object = _root.收集品栏.情报;
        var saveExt:Object = _root._saveExt;
        var procurementPlansExists:Boolean = saveExt != undefined && saveExt != null
            && saveExt.hasOwnProperty("procurementPlans");
        var drugLoadoutExists:Boolean = saveExt != undefined && saveExt != null
            && saveExt.hasOwnProperty("drugLoadout");
        var battleBoxTouched:Object = useBattleBox ? {} : null;
        var backup:Object = {bag:bag.toObject(), drugs:drugs.toObject(),
            battleBoxOwner:battleBox, battleBoxTouched:battleBoxTouched,
            bagOwner:bag, drugOwner:drugs, materialOwner:materials, intelOwner:intelligence,
            saveOwner:_root.存档系统,
            materials:materials.toObject(), intelligence:intelligence.toObject(),
            money:Number(_root.金钱), kpoints:Number(_root.虚拟币),
            dirty:_root.存档系统 == undefined ? undefined : _root.存档系统.dirtyMark,
            procurementPlansExists:procurementPlansExists,
            procurementPlans:procurementPlansExists
                ? ObjectUtil.clone(saveExt.procurementPlans) : null,
            drugLoadoutExists:drugLoadoutExists,
            drugLoadout:drugLoadoutExists
                ? ObjectUtil.clone(saveExt.drugLoadout) : null};

        var assetContext:Object = {
            source:"crafting", reason:"craft_commit", mergeScope:"operation"
        };
        var assetTransaction:Object = PlayerAssetTransaction.begin(assetContext);
        try {
            // 制作的材料、产物、货币与采购进度共享同一存档权威；缺失时零写失败。
            PlayerAssetTransaction.markDirtyRequired(_root.存档系统);
            if (!submitCraftingRequirements(current.requirements, useBattleBox, assetContext, battleBoxTouched, battleBox)) {
                return failAndRestore(backup, assetTransaction, "material_missing");
            }
            var actualRequire:Object = ItemUtil.singleRequire(current.output.name, current.output.value);
            var actualDelivery:Object = projectOutputDelivery(
                current.output.name, current.output.value, actualRequire);
            if (!deepEqual(actualDelivery, plan.outputDelivery, 0)) {
                return failAndRestore(backup, assetTransaction, "stale_state");
            }
            var targetBefore:Object = readOutputTarget(actualDelivery);
            if (!outputTargetMatchesMode(targetBefore, current.output.name, actualDelivery)) {
                return failAndRestore(backup, assetTransaction, "stale_state");
            }
            var beforeQuantity:Number = targetBefore == null ? 0 : Number(targetBefore.value);
            if (!ItemUtil.singleAcquire(current.output.name, current.output.value, assetContext)) {
                return failAndRestore(backup, assetTransaction, "inventory_full");
            }
            var outputReceipt:Object = null;
            if (requiresPhysicalOutputReceipt(actualDelivery)) {
                outputReceipt = InventoryPanelService.buildOutputReceipt(readOutputTarget(actualDelivery));
                if (!outputReceiptMatchesPrototype(outputReceipt, plan.acceptedPlan.outputPrototype,
                        actualDelivery, beforeQuantity)) {
                    return failAndRestore(backup, assetTransaction, "stale_state");
                }
            } else if (plan.acceptedPlan.outputPrototype != null) {
                return failAndRestore(backup, assetTransaction, "stale_state");
            }
            _root.金钱 = Number(backup.money) - Number(current.cost.money);
            _root.虚拟币 = Number(backup.kpoints) - Number(current.cost.kpoints);
            if (Number(current.cost.money) > 0) {
                PlayerAssetTransaction.recordEffect("loss", "money", "金钱",
                    Number(current.cost.money), assetContext);
            }
            if (Number(current.cost.kpoints) > 0) {
                PlayerAssetTransaction.recordEffect("loss", "kpoint", "K点",
                    Number(current.cost.kpoints), assetContext);
            }
            var procurement:Object = ProcurementPlanService.consumeCompleted(
                String(resolved.recipe.recipeId || ""), Number(current.craftCount));
            var successResponse:Object = {success:true, v:1, operation:"commit", category:category,
                recipeIndex:Number(current.recipeIndex), craftCount:Number(current.craftCount),
                crafted:current.output, acceptedPlan:plan.acceptedPlan,
                outputReceipt:outputReceipt, balance:buildBalance(), procurement:procurement};
        } catch (commitError) {
            trace("[CraftingPanelService] asset commit failed: " + commitError);
            return failAndRestore(backup, assetTransaction, "commit_failed");
        }
        // commit 之后绝不进入资产恢复 catch：消费者/强存盘异常不能把已发布或
        // 已耐久的事实恢复成旧资产状态。
        PlayerAssetTransaction.commit(assetTransaction);
        // 音效属于提交后的可选副作用；失败不能回滚已提交资产或制造幽灵回执。
        try {
            if (_root.soundEffectManager != undefined) _root.soundEffectManager.playSound("收银机.mp3");
        } catch (soundError) {
            trace("[CraftingPanelService] post-commit sound failed: " + soundError);
        }
        return successResponse;
    }

    // 部分回滚后的原交易明细已经失真。保留 dirty 和未知写，等待原配方的权威对账。
    private static function failAndRestore(backup:Object, transaction:Object, errorCode:String):Object {
        var complete:Boolean = false;
        try {
            restoreState(backup);
            complete = true;
        } catch (restoreError) {
            trace("[CraftingPanelService] incomplete restore: " + restoreError);
            try {
                if (backup.saveOwner != null) backup.saveOwner.dirtyMark = true;
            } catch (dirtyError) {
                trace("[CraftingPanelService] dirty restore failed: " + dirtyError);
            }
        } finally {
            PlayerAssetTransaction.settleAfterException(transaction, false);
        }
        if (complete) return fail(errorCode);
        return fail("commit_failed");
    }

    private static function restoreState(backup:Object):Void {
        if (_root.物品栏.背包 !== backup.bagOwner || _root.物品栏.药剂栏 !== backup.drugOwner
                || _root.收集品栏.材料 !== backup.materialOwner || _root.收集品栏.情报 !== backup.intelOwner
                || _root.存档系统 !== backup.saveOwner) throw new Error("craft_restore_owner_changed");
        _root.物品栏.背包.setItems(backup.bag);
        _root.物品栏.药剂栏.setItems(backup.drugs);
        _root.收集品栏.材料.setItems(backup.materials);
        _root.收集品栏.情报.setItems(backup.intelligence);
        _root.金钱 = Number(backup.money);
        _root.虚拟币 = Number(backup.kpoints);
        // consumeCompleted 先替换采购计划、再触发可扩展的 markDirty；后者
        // 抛错时必须把这份领域权威也恢复，才能兑现 executeCommit 的 exact snapshot。
        if (backup.procurementPlansExists === true) {
            if (_root._saveExt == undefined || _root._saveExt == null) _root._saveExt = {};
            _root._saveExt.procurementPlans = ObjectUtil.clone(backup.procurementPlans);
        } else if (_root._saveExt != undefined && _root._saveExt != null) {
            delete _root._saveExt.procurementPlans;
        }
        if (backup.drugLoadoutExists === true) {
            if (_root._saveExt == undefined || _root._saveExt == null) _root._saveExt = {};
            _root._saveExt.drugLoadout = ObjectUtil.clone(backup.drugLoadout);
        } else if (_root._saveExt != undefined && _root._saveExt != null) {
            delete _root._saveExt.drugLoadout;
        }
        var bbRestoreError:Error = null;
        if (backup.battleBoxTouched != null && hasMapEntries(backup.battleBoxTouched)) {
            var bb:Object = backup.battleBoxOwner;
            if (bb == null) throw new Error("battlebox_restore_owner_missing");
            for (var bbKey:String in backup.battleBoxTouched) {
                if (ObjectUtil.isInternalKey(bbKey)) continue;
                var bbSlot:Number = Number(bbKey);
                var savedEntry:Object = backup.battleBoxTouched[bbKey];
                var restoredItem:Object = null;
                if (savedEntry.existed) {
                    restoredItem = savedEntry.isBaseItem === true
                        ? BaseItem.createFromObject(PersistedSnapshot.cloneData(savedEntry.snapshot))
                        : ObjectUtil.clone(savedEntry.snapshot);
                    if (restoredItem == null) {
                        if (bbRestoreError == null) bbRestoreError = new Error("battlebox_restore_item_invalid");
                        continue;
                    }
                }
                try {
                    if (bb.transactionWrite(bbSlot, restoredItem) !== true || bb.getItem(bbSlot) !== restoredItem) {
                        bbRestoreError = new Error("battlebox_restore_write_failed");
                    }
                } catch (slotRestoreError) {
                    bbRestoreError = new Error("battlebox_restore_write_failed");
                }
            }
            if (_root.物品栏.战备箱 !== bb) throw new Error("battlebox_restore_owner_changed");
        }
        if (bbRestoreError != null) {
            throw bbRestoreError;
        }
        if (_root.存档系统 != undefined) _root.存档系统.dirtyMark = backup.dirty;
    }

    private static function buildPlan(category:String, recipeIndex:Number, recipe:Object,
            craftCount:Number, calculateMaximum:Boolean,
            procurementSources:Object, ownedIndex:Object, technique:Object,
            useBattleBox:Boolean):Object {
        if (!org.flashNight.arki.scene.Cf6Type61Service.recipeAllowed(String(recipe.recipeId))) return fail("recipe_not_found");
        var allowBattleBox:Boolean = useBattleBox === true;
        var baseRequirements:Array = ItemUtil.getRequirementFromTask(recipe.materials || []);
        // 卡莫特林可选的配方在选择加入时按份数追加一份材料需求；
        // 未声明调制方式的配方 technique 为 null，需求保持不变。
        if (technique != null && technique.karmotrine === true) {
            baseRequirements.push({name:"卡莫特林", value:1, isQuantity:true});
        }
        var batchEligible:Boolean = isBatchEligible(recipe, baseRequirements);
        if (!batchEligible && craftCount != 1) return fail("batch_not_supported");
        var requirements:Array = scaleRequirements(baseRequirements, craftCount);
        // contain() is the canonical deduction planner used by submit().  Project its
        // concrete storage route instead of making the Web layer infer one from names.
        var containmentPlan:Object = allowBattleBox
            ? planCraftingContainment(requirements, true)
            : ItemUtil.contain(requirements);
        if (procurementSources == null) {
            procurementSources = ProcurementPlanService.buildPurchaseSourceIndex();
        }
        if (ownedIndex == null) ownedIndex = ProcurementPlanService.buildOwnedIndex();
        var materialRows:Array = [];
        var allMaterials:Boolean = containmentPlan != null;
        var inheritedLevel:Number = 1;
        var stateParts:Array = [];
        // 基建门槛与材料核算同处一层：不消耗物品，只在等级不足时以
        // infrastructure_locked 阻断预览与提交。
        var infrastructureRows:Array = projectInfrastructureRows(recipe);
        var infrastructureMet:Boolean = true;
        for (var infraIndex:Number = 0; infraIndex < infrastructureRows.length; infraIndex++) {
            if (!infrastructureRows[infraIndex].met) { infrastructureMet = false; break; }
        }
        for (var i:Number = 0; i < requirements.length; i++) {
            var projection:Object = projectRequirement(requirements[i], containmentPlan,
                procurementSources, ownedIndex, allowBattleBox);
            if (projection == null) return fail("item_not_found");
            materialRows.push(projection);
            if (containmentPlan == null && projection.itemKind == "equipment") {
                inheritedLevel = Math.max(inheritedLevel, projection.maxEnhancement);
            }
            stateParts.push(projection.name + ":" + projection.owned + ":"
                + projection.maxEnhancement + ":" + projection.storageKind);
        }
        if (containmentPlan != null) {
            inheritedLevel = Math.max(inheritedLevel, selectedEquipmentMaxLevel(containmentPlan));
        }

        var outputData:Object = ItemUtil.getRawItemData(String(recipe.name));
        if (outputData == null) return fail("item_not_found");
        var unitOutputValue:Number = Number(recipe.value);
        var explicitOutputValue:Boolean = recipe.value != undefined && recipe.value != null
            && String(recipe.value) != "";
        if (!explicitOutputValue) unitOutputValue = 1;
        else if (!isStrictWholeNumber(unitOutputValue) || unitOutputValue <= 0
                || unitOutputValue > 9007199254740991) return fail("invalid_output_value");
        var outputValue:Number = ItemUtil.isEquipment(String(recipe.name))
            ? unitOutputValue : unitOutputValue * craftCount;
        var smith:Object = smithState();
        if (smith.enabled && ItemUtil.isEquipment(String(recipe.name))) {
            outputValue = Math.max(outputValue, inheritedLevel);
        }
        if (!isValidOutputValue(String(recipe.name), outputValue)) {
            return fail("invalid_output_value");
        }
        var multiplier:Number = smith.enabled ? Math.max(0, 1 - smith.level * 0.05) : 1;
        // 旧 Flash 合成界面对每份折扣价先向下取整；批量等价于重复单份合成。
        // 不能在总价层最后取整，否则会改变批量成本，也会把小数余额写入存档。
        var cost:Object = {money:adjustedUnitCost(recipe.price, multiplier) * craftCount,
            kpoints:adjustedUnitCost(recipe.kprice, multiplier) * craftCount};
        var requiredLevel:Number = outputData.data == undefined ? 0 : Number(outputData.data.level || 0);
        var reverseLevel:Number = reverseSkillLevel();
        var levelAllowed:Boolean = Number(_root.等级) + reverseLevel >= requiredLevel;
        var enoughMoney:Boolean = Number(_root.金钱) >= cost.money;
        var enoughKpoints:Boolean = Number(_root.虚拟币) >= cost.kpoints;
        // 预览必须投影真实提交顺序：先扣素材，再为产物选择合并或空格。
        // containPlan 不可用时预览仍可显示当前容量，但不会铸造 token。
        var outputDelivery:Object = containmentPlan == null
            ? projectOutputDelivery(String(recipe.name), outputValue,
                ItemUtil.singleRequire(String(recipe.name), outputValue))
            : projectOutputDeliveryAfterSubmit(
                String(recipe.name), outputValue, containmentPlan);
        var outputPrototype:Object = requiresPhysicalOutputReceipt(outputDelivery)
            ? InventoryPanelService.buildOutputPrototype(String(recipe.name), outputValue) : null;
        var projectionReady:Boolean = !requiresPhysicalOutputReceipt(outputDelivery)
            || outputPrototype != null;
        var enoughSpace:Boolean = outputDelivery.available && projectionReady;
        var blockingError:String = "";
        if (!infrastructureMet) blockingError = "infrastructure_locked";
        else if (!levelAllowed) blockingError = "level_locked";
        else if (!allMaterials) blockingError = "material_missing";
        else if (!enoughMoney) blockingError = "insufficient_money";
        else if (!enoughKpoints) blockingError = "insufficient_kpoint";
        else if (!projectionReady) blockingError = "output_projection_failed";
        else if (!enoughSpace) blockingError = "inventory_full";
        var maxCraftCount:Number = batchEligible
            ? (calculateMaximum
                ? calculateMaxCraftCount(recipe, baseRequirements, multiplier, levelAllowed, allowBattleBox)
                : (blockingError == "" ? 1 : 0))
            : (blockingError == "" ? 1 : 0);
        var output:Object = projectItem(String(recipe.name), outputValue);
        output.requiredLevel = requiredLevel;
        var acceptedPlan:Object = {category:category, recipeIndex:recipeIndex,
            craftCount:craftCount, output:output, materials:materialRows,
            infrastructure:infrastructureRows,
            outputDelivery:outputDelivery, outputPrototype:outputPrototype, cost:cost};
        if (technique != null) acceptedPlan.technique = technique;
        if (allowBattleBox) acceptedPlan.useBattleBox = true;
        var stateSignature:String = [recipeSignature(recipe), Number(_root.金钱),
            Number(_root.虚拟币), Number(_root.等级), reverseLevel, smith.enabled, smith.level,
            inventoryRevision(_root.物品栏.背包), inventoryRevision(_root.物品栏.药剂栏),
            allowBattleBox ? InventoryPanelService.getAccessibleCapacity("战备箱") : 0,
            allowBattleBox ? inventoryRevision(_root.物品栏.战备箱) : -1,
            allowBattleBox,
            craftCount, stateParts.join("|"), infrastructureSignature(infrastructureRows),
            outputDelivery.storageKind,
            outputDelivery.mode, outputDelivery.physicalSlot,
            projectionSignature(outputPrototype), projectionSignature(technique)].join(";");
        return {success:true, category:category, recipeIndex:recipeIndex, craftCount:craftCount,
            recipeSignature:recipeSignature(recipe), stateSignature:stateSignature,
            requirements:requirements, materials:materialRows, output:output, cost:cost,
            infrastructure:infrastructureRows,
            outputDelivery:outputDelivery, acceptedPlan:acceptedPlan, technique:technique,
            useBattleBox:allowBattleBox,
            balance:buildBalance(), skills:buildSkills(), levelAllowed:levelAllowed,
            enoughMaterials:allMaterials, enoughMoney:enoughMoney, enoughKpoints:enoughKpoints,
            enoughSpace:enoughSpace, batchEligible:batchEligible, maxCraftCount:maxCraftCount,
            canCommit:blockingError == "", blockingError:blockingError};
    }

    private static function projectPreview(plan:Object):Object {
        var result:Object = {success:true, v:1, category:plan.category,
            recipeIndex:plan.recipeIndex, craftCount:plan.craftCount,
            batchEligible:plan.batchEligible, maxCraftCount:plan.maxCraftCount,
            output:plan.output, materials:plan.materials,
            outputDelivery:plan.outputDelivery,
            cost:plan.cost, balance:plan.balance, skills:plan.skills,
            infrastructure:plan.infrastructure,
            levelAllowed:plan.levelAllowed, enoughMaterials:plan.enoughMaterials,
            enoughMoney:plan.enoughMoney, enoughKpoints:plan.enoughKpoints,
            enoughSpace:plan.enoughSpace, canCommit:plan.canCommit,
            blockingError:plan.blockingError};
        if (plan.technique != null) result.technique = plan.technique;
        if (plan.useBattleBox === true) result.useBattleBox = true;
        if (plan.canCommit) {
            result.craftToken = plan.token;
            result.acceptedPlan = plan.acceptedPlan;
        }
        return result;
    }

    private static function isBatchEligible(recipe:Object, requirements:Array):Boolean {
        if (ItemUtil.isEquipment(String(recipe.name))) return false;
        for (var i:Number = 0; i < requirements.length; i++) {
            if (ItemUtil.isEquipment(String(requirements[i].name))) return false;
        }
        return true;
    }

    private static function scaleRequirements(requirements:Array, craftCount:Number):Array {
        var scaled:Array = [];
        for (var i:Number = 0; i < requirements.length; i++) {
            var req:Object = requirements[i];
            var value:Number = Number(req.value);
            if (isNaN(value) || value <= 0) value = 1;
            scaled.push({name:String(req.name),
                value:ItemUtil.isInformation(String(req.name)) ? value : value * craftCount,
                isQuantity:req.isQuantity === true,
                tier:req.tier});
        }
        return scaled;
    }

    private static function calculateMaxCraftCount(recipe:Object, requirements:Array,
            multiplier:Number, levelAllowed:Boolean, useBattleBox:Boolean):Number {
        if (!levelAllowed) return 0;
        var low:Number = 0;
        var high:Number = MAX_CRAFT_COUNT;
        while (low < high) {
            var middle:Number = Math.ceil((low + high) / 2);
            _maximumProbeCount++;
            if (canAffordCount(recipe, requirements, middle, multiplier, useBattleBox)) low = middle;
            else high = middle - 1;
        }
        // 满包时更高份数可能清空整格后才腾出产物空间（非单调），从可负担上界向下核验落点。
        for (var candidate:Number = low; candidate >= 1; candidate--) {
            if (canDeliverCount(recipe, requirements, candidate, useBattleBox)) return candidate;
        }
        return 0;
    }

    private static function canAffordCount(recipe:Object, requirements:Array,
            craftCount:Number, multiplier:Number, useBattleBox:Boolean):Boolean {
        var scaled:Array = scaleRequirements(requirements, craftCount);
        var containmentPlan:Object = useBattleBox === true
            ? planCraftingContainment(scaled, true)
            : ItemUtil.contain(scaled);
        if (containmentPlan == null) return false;
        if (Number(_root.金钱) < adjustedUnitCost(recipe.price, multiplier) * craftCount) return false;
        if (Number(_root.虚拟币) < adjustedUnitCost(recipe.kprice, multiplier) * craftCount) return false;
        var outputValue:Number = Number(recipe.value);
        if (isNaN(outputValue) || outputValue <= 0) outputValue = 1;
        outputValue *= craftCount;
        return isValidOutputValue(String(recipe.name), outputValue);
    }

    private static function canDeliverCount(recipe:Object, requirements:Array,
            craftCount:Number, useBattleBox:Boolean):Boolean {
        var scaled:Array = scaleRequirements(requirements, craftCount);
        var containmentPlan:Object = useBattleBox === true
            ? planCraftingContainment(scaled, true)
            : ItemUtil.contain(scaled);
        if (containmentPlan == null) return false;
        var outputValue:Number = Number(recipe.value);
        if (isNaN(outputValue) || outputValue <= 0) outputValue = 1;
        outputValue *= craftCount;
        var delivery:Object = projectOutputDeliveryAfterSubmit(
            String(recipe.name), outputValue, containmentPlan);
        if (!delivery.available) return false;
        return !requiresPhysicalOutputReceipt(delivery)
            || InventoryPanelService.buildOutputPrototype(String(recipe.name), outputValue) != null;
    }

    private static function adjustedUnitCost(rawCost:Object, multiplier:Number):Number {
        var cost:Number = Number(rawCost || 0);
        if (isNaN(cost) || cost < 0) cost = 0;
        return Math.floor(cost * multiplier);
    }

    private static function projectRequirement(req:Object, containmentPlan:Object,
            procurementSources:Object, ownedIndex:Object, useBattleBox:Boolean):Object {
        var name:String = String(req.name || "");
        var data:Object = ItemUtil.getRawItemData(name);
        if (data == null) return null;
        var required:Number = Number(req.value);
        if (isNaN(required) || required <= 0) required = 1;
        var owned:Number = 0;
        var maxEnhancement:Number = 0;
        var kind:String = ItemUtil.isEquipment(name) ? "equipment" : "stack";
        var consumed:Boolean = !ItemUtil.isInformation(name);
        var ownedSummary:Object = ProcurementPlanService.buildOwnedSummary(name, ownedIndex);
        if (ItemUtil.isMaterial(name)) owned = Number(ownedSummary.material);
        else if (ItemUtil.isInformation(name)) owned = Number(ownedSummary.information);
        else {
            owned = Number(ownedSummary.usable)
                + (useBattleBox === true ? Number(ownedSummary.battleBox) : 0);
            if (kind == "equipment") {
                maxEnhancement = Number(ownedSummary.usableMaxEnhancement);
                if (useBattleBox === true && ownedIndex != null && ownedIndex[name] != null) {
                    var bbMaxEnh:Number = Number(ownedIndex[name].battleBoxMaxEnhancement);
                    if (!isNaN(bbMaxEnh)) maxEnhancement = Math.max(maxEnhancement, bbMaxEnh);
                }
            }
        }
        var enough:Boolean = kind == "equipment" && !req.isQuantity
            ? maxEnhancement >= required : owned >= required;
        return {name:name, displayName:projectLegacyIdentityField(data.displayname, name),
            icon:projectLegacyIdentityField(data.icon, name),
            itemKind:kind, required:required, owned:owned, maxEnhancement:maxEnhancement,
            isQuantity:req.isQuantity === true, tier:req.tier == undefined ? "" : String(req.tier),
            consumed:consumed, enough:enough,
            storageKind:projectRequirementStorage(name, containmentPlan),
            craftingSources:SynthesisIndex.getRecipesProducing(name),
            procurement:ProcurementPlanService.buildImmediateDemand(
                name, required, req.isQuantity === true,
                procurementSources, ownedIndex)};
    }

    private static function projectRequirementStorage(name:String, containmentPlan:Object):String {
        if (ItemUtil.isMaterial(name)) return "material_collection";
        if (ItemUtil.isInformation(name)) return "information_collection";
        if (containmentPlan == null) return "unavailable";
        var inBag:Boolean = planContainsItem(containmentPlan.背包, _root.物品栏.背包, name);
        var inDrug:Boolean = planContainsItem(containmentPlan.药剂栏, _root.物品栏.药剂栏, name);
        var inBattleBox:Boolean = planContainsItem(containmentPlan.战备箱, _root.物品栏.战备箱, name);
        if (inBag && inDrug && inBattleBox) return "bag_drug_and_battlebox";
        if (inBag && inBattleBox) return "bag_and_battlebox";
        if (inDrug && inBattleBox) return "drug_and_battlebox";
        if (inBattleBox) return "battlebox";
        if (inBag && inDrug) return "bag_and_drug";
        if (inBag) return "bag";
        if (inDrug) return "drug";
        return "unavailable";
    }

    private static function planContainsItem(plan:Object, inventory:Object, name:String):Boolean {
        if (plan == null || inventory == null) return false;
        for (var key:String in plan) {
            var item:Object = inventory.getItem(Number(key));
            if (item != null && String(item.name) == name) return true;
        }
        return false;
    }

    private static function hasMapEntries(map:Object):Boolean {
        if (map == null) return false;
        for (var key:String in map) {
            if (!ObjectUtil.isInternalKey(key)) return true;
        }
        return false;
    }

    private static function selectedEquipmentMaxLevel(containmentPlan:Object):Number {
        var best:Number = 1;
        if (containmentPlan == null) return best;
        best = Math.max(best, maxPlannedEquipmentLevel(containmentPlan.背包, _root.物品栏.背包));
        best = Math.max(best, maxPlannedEquipmentLevel(containmentPlan.战备箱, _root.物品栏.战备箱));
        return best;
    }

    private static function maxPlannedEquipmentLevel(plan:Object, inventory:Object):Number {
        var best:Number = 1;
        if (plan == null || inventory == null) return best;
        for (var key:String in plan) {
            if (ObjectUtil.isInternalKey(key)) continue;
            var item:Object = inventory.getItem(Number(key));
            if (item == null || !ItemUtil.isEquipment(String(item.name || ""))) continue;
            var lv:Number = (item.value != null && typeof item.value == "object")
                ? Number(item.value.level) : 1;
            if (!isNaN(lv) && isFinite(lv) && lv > best) best = lv;
        }
        return best;
    }

    /**
     * 合成域专用的战备箱可选扣料规划器（严格只读，不修改全局 ItemUtil.contain）：
     * 按 背包 → 药剂栏 → 已解锁战备箱前缀（slot < accessibleCapacity）顺序规划，
     * 绝不触碰装备栏、仓库或战备箱未解锁尾部。
     * 装备需求先按强化阈值降序预留，再由剩余件满足数量型装备需求。
     */
    private static function planCraftingContainment(requirements:Array, useBattleBox:Boolean):Object {
        if (useBattleBox !== true) return ItemUtil.contain(requirements);
        var list:Object = {背包:{}, 材料:{}, 情报:{}, 药剂栏:{}, 战备箱:{}};
        var bag:Object = _root.物品栏.背包;
        var drugs:Object = _root.物品栏.药剂栏;
        var battleBox:Object = _root.物品栏.战备箱;
        var materials:Object = _root.收集品栏.材料;
        var intelligence:Object = _root.收集品栏.情报;
        var accessibleCap:Number = InventoryPanelService.getAccessibleCapacity("战备箱");
        var usedBag:Object = {};
        var usedDrug:Object = {};
        var usedBattleBox:Object = {};

        var ordered:Array = [];
        var equipThresholdReqs:Array = [];
        var equipQuantityReqs:Array = [];
        for (var r:Number = 0; r < requirements.length; r++) {
            var reqEntry:Object = requirements[r];
            var reqName:String = String(reqEntry.name || "");
            if (ItemUtil.isEquipment(reqName)) {
                if (reqEntry.isQuantity === true) equipQuantityReqs.push(reqEntry);
                else equipThresholdReqs.push(reqEntry);
            } else {
                ordered.push(reqEntry);
            }
        }
        equipThresholdReqs.sort(function(a:Object, b:Object):Number {
            return Number(b.value) - Number(a.value);
        });
        for (var e1:Number = 0; e1 < equipThresholdReqs.length; e1++) ordered.push(equipThresholdReqs[e1]);
        for (var e2:Number = 0; e2 < equipQuantityReqs.length; e2++) ordered.push(equipQuantityReqs[e2]);

        for (var i:Number = 0; i < ordered.length; i++) {
            var req:Object = ordered[i];
            var name:String = String(req.name || "");
            var need:Number = Number(req.value);
            var isQty:Boolean = req.isQuantity === true;
            if (ItemUtil.isMaterial(name)) {
                var prevMat:Number = Number(list.材料[name] || 0);
                if (Number(materials.getValue(name)) < prevMat + need) return null;
                list.材料[name] = prevMat + need;
                continue;
            }
            if (ItemUtil.isInformation(name)) {
                if (Number(intelligence.getValue(name)) < need) return null;
                var prevInfo:Number = Number(list.情报[name] || 0);
                list.情报[name] = Math.max(prevInfo, need);
                continue;
            }
            var isEquip:Boolean = ItemUtil.isEquipment(name);
            need = allocateContainerForRequirement(bag, -1, name, need, isEquip, isQty, list.背包, usedBag);
            if (!isEquip && need > 0) {
                need = allocateContainerForRequirement(drugs, -1, name, need, false, true, list.药剂栏, usedDrug);
            }
            if (need > 0 && battleBox != null && accessibleCap > 0) {
                need = allocateContainerForRequirement(battleBox, accessibleCap, name, need, isEquip, isQty, list.战备箱, usedBattleBox);
            }
            if (isNaN(need) || need > 0) return null;
        }
        return list;
    }

    private static function allocateContainerForRequirement(inventory:Object, maxSlotExclusive:Number,
            name:String, need:Number, isEquip:Boolean, isQty:Boolean,
            planMap:Object, usedMap:Object):Number {
        if (inventory == null || need <= 0) return need;
        var indexes:Array = inventory.getIndexes();
        for (var idx:Number = 0; idx < indexes.length; idx++) {
            var slot:Number = Number(indexes[idx]);
            if (maxSlotExclusive >= 0 && (slot < 0 || slot >= maxSlotExclusive)) continue;
            var slotKey:String = String(slot);
            var item:Object = inventory.getItem(slot);
            if (item == null || String(item.name) != name) continue;
            if (isEquip) {
                if (usedMap[slotKey] === true) continue;
                if (isQty) {
                    usedMap[slotKey] = true;
                    planMap[slotKey] = 1;
                    need -= 1;
                    if (need <= 0) return 0;
                    continue;
                }
                var itemLv:Number = (item.value != null && typeof item.value == "object")
                    ? Number(item.value.level || 0) : 0;
                if (itemLv >= need) {
                    usedMap[slotKey] = true;
                    planMap[slotKey] = need;
                    return 0;
                }
                continue;
            }
            var avail:Number = Number(item.value) - Number(usedMap[slotKey] || 0);
            if (isNaN(avail) || avail <= 0) continue;
            var take:Number = avail >= need ? need : avail;
            usedMap[slotKey] = Number(usedMap[slotKey] || 0) + take;
            planMap[slotKey] = Number(planMap[slotKey] || 0) + take;
            need -= take;
            if (need <= 0) return 0;
        }
        return need;
    }

    private static function submitCraftingRequirements(requirements:Array, useBattleBox:Boolean,
            assetContext:Object, battleBoxTouched:Object, battleBoxOwner:Object):Boolean {
        if (useBattleBox !== true) return ItemUtil.submit(requirements, assetContext);
        var plan:Object = planCraftingContainment(requirements, true);
        if (plan == null) return false;
        var hasBbEntries:Boolean = hasMapEntries(plan.战备箱);
        var accessibleCap:Number = InventoryPanelService.getAccessibleCapacity("战备箱");
        var bag:Object = _root.物品栏.背包;
        var drugs:Object = _root.物品栏.药剂栏;
        var battleBox:Object = _root.物品栏.战备箱;
        var materials:Object = _root.收集品栏.材料;
        if (hasBbEntries && (battleBox == null || battleBox !== battleBoxOwner || accessibleCap <= 0)) return false;

        var expectedBag:Object = preflightContainerPlan(bag, -1, plan.背包);
        if (expectedBag == null) return false;
        var expectedDrug:Object = preflightContainerPlan(drugs, -1, plan.药剂栏);
        if (expectedDrug == null) return false;
        var expectedBattleBox:Object = hasBbEntries
            ? preflightContainerPlan(battleBox, accessibleCap, plan.战备箱) : {};
        if (expectedBattleBox == null) return false;
        for (var matName:String in plan.材料) {
            if (ObjectUtil.isInternalKey(matName)) continue;
            var reqMatQty:Number = Number(plan.材料[matName]);
            if (isNaN(reqMatQty) || reqMatQty <= 0 || Number(materials.getValue(matName)) < reqMatQty) return false;
        }

        var exact:Boolean = true;
        for (var mKey:String in plan.材料) {
            if (ObjectUtil.isInternalKey(mKey)) continue;
            var matQty:Number = Number(plan.材料[mKey]);
            var matBefore:Number = Number(materials.getValue(mKey));
            materials.addValue(mKey, -matQty);
            var matAfter:Number = Number(materials.getValue(mKey));
            var matDelta:Number = matBefore - matAfter;
            if (matDelta != matQty) exact = false;
            if (matDelta > 0) {
                PlayerAssetTransaction.recordEffect("loss", "material", mKey,
                    matDelta > matQty ? matQty : matDelta, assetContext);
            }
        }
        if (!deductContainerPlan(bag, -1, plan.背包, expectedBag, false, false, assetContext, null)) exact = false;
        if (!deductContainerPlan(drugs, -1, plan.药剂栏, expectedDrug, true, false, assetContext, null)) exact = false;
        if (hasBbEntries && !deductContainerPlan(battleBox, accessibleCap, plan.战备箱, expectedBattleBox, false, true, assetContext, battleBoxTouched)) exact = false;
        return exact;
    }

    private static function preflightContainerPlan(inventory:Object, maxSlotExclusive:Number,
            planMap:Object):Object {
        var expected:Object = {};
        for (var slotKey:String in planMap) {
            if (ObjectUtil.isInternalKey(slotKey)) continue;
            var slotNum:Number = Number(slotKey);
            if (isNaN(slotNum) || slotNum < 0 || (maxSlotExclusive >= 0 && slotNum >= maxSlotExclusive)) return null;
            if (inventory == null) return null;
            var item:Object = inventory.getItem(slotNum);
            if (item == null) return null;
            expected[slotKey] = {
                ref:item,
                name:String(item.name),
                equipment:ItemUtil.isEquipment(String(item.name))
            };
        }
        return expected;
    }

    private static function deductContainerPlan(inventory:Object, maxSlotExclusive:Number,
            planMap:Object, expectedMap:Object, isDrug:Boolean, isBattleBox:Boolean,
            assetContext:Object, touchedBackup:Object):Boolean {
        var exact:Boolean = true;
        for (var slotKey:String in planMap) {
            if (ObjectUtil.isInternalKey(slotKey)) continue;
            var slotNum:Number = Number(slotKey);
            var liveLimit:Number = isBattleBox
                ? InventoryPanelService.getAccessibleCapacity("战备箱") : maxSlotExclusive;
            if (isBattleBox && (_root.物品栏 == undefined || _root.物品栏.战备箱 !== inventory)) {
                exact = false;
                continue;
            }
            if (liveLimit >= 0 && (slotNum < 0 || slotNum >= liveLimit)) {
                exact = false;
                continue;
            }
            var item:Object = inventory.getItem(slotNum);
            var expected:Object = expectedMap[slotKey];
            if (item == null || expected == null || String(item.name) != String(expected.name)
                    || (expected.equipment && item !== expected.ref)) {
                exact = false;
                continue;
            }
            if (touchedBackup != null && !touchedBackup.hasOwnProperty(slotKey)) {
                var rawSnapshot:Object = typeof item.toObject == "function"
                    ? item.toObject() : ObjectUtil.clone(item);
                touchedBackup[slotKey] = {
                    existed:true,
                    isBaseItem:(item instanceof BaseItem),
                    snapshot:rawSnapshot
                };
            }
            var removedName:String = String(item.name);
            var plannedQty:Number = Number(planMap[slotKey]);
            var removedEquipment:Boolean = expected.equipment === true;
            var removedTier:String = "";
            if (removedEquipment && item.value != null && item.value.tier != undefined) {
                removedTier = String(item.value.tier);
            }
            var beforeItem:Object = item;
            var beforeValue:Number = Number(item.value);
            if (removedEquipment || isNaN(beforeValue)) {
                inventory.remove(slotNum);
            } else {
                inventory.addValue(String(slotNum), -plannedQty);
            }
            var afterItem:Object = inventory.getItem(slotNum);
            var rawCommitted:Number = 0;
            if (removedEquipment) {
                if (afterItem !== beforeItem) rawCommitted = 1;
            } else if (!isNaN(beforeValue)) {
                var afterValue:Number = afterItem == null ? 0 : Number(afterItem.value);
                if (!isNaN(afterValue)) rawCommitted = beforeValue - afterValue;
            } else if (afterItem !== beforeItem) {
                rawCommitted = plannedQty;
            }
            var expectedRemoval:Number = removedEquipment ? 1 : plannedQty;
            var committed:Number = rawCommitted > expectedRemoval ? expectedRemoval : rawCommitted;
            if (rawCommitted != expectedRemoval) exact = false;
            if (committed > 0 && !isNaN(committed)) {
                PlayerAssetTransaction.recordEffect(
                    "loss", removedEquipment ? "equip" : "item", removedName, committed,
                    removedTier == "" ? assetContext : {
                        source:assetContext == null ? undefined : assetContext.source,
                        reason:assetContext == null ? undefined : assetContext.reason,
                        mergeScope:assetContext == null ? undefined : assetContext.mergeScope,
                        tier:removedTier
                    });
                if (isDrug && afterItem == null) {
                    var affinityCommit:Object = org.flashNight.arki.item.DrugSlotAffinityService
                        .recordDepleted(_root, inventory, slotNum, removedName);
                    if (!affinityCommit.success) exact = false;
                }
            }
        }
        return exact;
    }

    private static function projectOutputDelivery(name:String, value:Number,
            requirePlan:Object):Object {
        var quantity:Number = ItemUtil.isEquipment(name) ? 1 : value;
        if (requirePlan == null) return {available:false, storageKind:"unavailable",
            mode:"none", physicalSlot:-1, quantity:quantity};
        if (ItemUtil.isMaterial(name)) return {available:true,
            storageKind:"material_collection", mode:"increment", physicalSlot:-1, quantity:quantity};
        if (ItemUtil.isInformation(name)) return {available:true,
            storageKind:"information_collection", mode:"increment", physicalSlot:-1, quantity:quantity};
        for (var drugKey:String in requirePlan.药剂栏) {
            var drugReq:Object = requirePlan.药剂栏[drugKey];
            if (drugReq != null && String(drugReq.name) == name) {
                var drugIndex:Number = Number(drugKey);
                var drugMode:String = _root.物品栏.药剂栏.isEmpty(drugIndex) ? "insert" : "merge";
                return {available:true, storageKind:"drug", mode:drugMode,
                    physicalSlot:drugIndex, quantity:quantity};
            }
        }
        for (var bagKey:String in requirePlan.背包) {
            var bagReq:Object = requirePlan.背包[bagKey];
            if (bagReq != null && String(bagReq.name) == name) {
                var bagIndex:Number = Number(bagKey);
                var mode:String = _root.物品栏.背包.isEmpty(bagIndex) ? "insert" : "merge";
                return {available:true, storageKind:"bag", mode:mode,
                    physicalSlot:bagIndex, quantity:quantity};
            }
        }
        return {available:false, storageKind:"unavailable",
            mode:"none", physicalSlot:-1, quantity:quantity};
    }

    /**
     * 以 submit(requirements) 完成后的虚拟容器状态规划产物去向。
     * 不写入、不制造 BaseItem；commit 会在真实 submit 后再用 singleRequire
     * 核对一次，任何路由漂移都回滚。
     */
    private static function projectOutputDeliveryAfterSubmit(name:String, value:Number,
            containmentPlan:Object):Object {
        var quantity:Number = ItemUtil.isEquipment(name) ? 1 : value;
        if (containmentPlan == null) return {available:false, storageKind:"unavailable",
            mode:"none", physicalSlot:-1, quantity:quantity};
        if (ItemUtil.isMaterial(name) || ItemUtil.isInformation(name)) {
            return projectOutputDelivery(name, value, ItemUtil.singleRequire(name, value));
        }

        var drugs:Object = _root.物品栏.药剂栏;
        var bag:Object = _root.物品栏.背包;
        var acquireState:Object = org.flashNight.arki.item.DrugSlotAffinityService
            .createAcquirePlanningState(_root, drugs, bag);
        if (acquireState != null && acquireState.ok === true) {
            if (containmentPlan.药剂栏 != null) {
                for (var dKey:String in containmentPlan.药剂栏) {
                    if (ObjectUtil.isInternalKey(dKey)) continue;
                    var dSlot:Number = Number(dKey);
                    var dItem:Object = drugs.getItem(dSlot);
                    if (dItem == null || dSlot < 0
                            || dSlot >= org.flashNight.arki.item.DrugSlotAffinityService.SLOT_COUNT) continue;
                    var dRem:Number = remainingStackAfterSubmit(
                        dItem, containmentPlan.药剂栏, dSlot, String(dItem.name));
                    if (dRem <= 0) {
                        acquireState.drugs[dSlot] = null;
                        var dSeq:Number = Number(acquireState.feature.nextDepletedSequence || 1);
                        acquireState.feature.slots[dSlot] = {
                            itemKey:String(dItem.name),
                            lastDepletedSequence:dSeq
                        };
                        acquireState.feature.nextDepletedSequence = dSeq + 1;
                    } else if (acquireState.drugs[dSlot] != null) {
                        acquireState.drugs[dSlot].value = dRem;
                    }
                }
            }
            if (containmentPlan.背包 != null) {
                for (var bKey:String in containmentPlan.背包) {
                    if (ObjectUtil.isInternalKey(bKey)) continue;
                    var bSlot:Number = Number(bKey);
                    var bItem:Object = bag.getItem(bSlot);
                    if (bItem == null || bSlot < 0 || bSlot >= acquireState.backpackCapacity) continue;
                    var bRem:Number = remainingStackAfterSubmit(
                        bItem, containmentPlan.背包, bSlot, String(bItem.name));
                    if (bRem <= 0) {
                        acquireState.backpack[bSlot] = null;
                    } else if (acquireState.backpack[bSlot] != null) {
                        acquireState.backpack[bSlot].value = bRem;
                    }
                }
            }
            var rawOut:Object = ItemUtil.getRawItemData(name);
            var isDrugOut:Boolean = rawOut != null && typeof rawOut.use == "string"
                && String(rawOut.use) == "药剂";
            var outPlan:Object = org.flashNight.arki.item.DrugSlotAffinityService.planAcquireTarget(
                acquireState, name, quantity, isDrugOut, !ItemUtil.isEquipment(name));
            if (!outPlan.success) {
                return {available:false, storageKind:"unavailable",
                    mode:"none", physicalSlot:-1, quantity:quantity};
            }
            if (String(outPlan.storageKind) == "drug") {
                return {available:true, storageKind:"drug",
                    mode:(String(outPlan.mode) == "affinity_restore" ? "insert" : "merge"),
                    physicalSlot:Number(outPlan.slot), quantity:quantity};
            }
            return {available:true, storageKind:"bag",
                mode:(String(outPlan.mode) == "backpack_merge" ? "merge" : "insert"),
                physicalSlot:Number(outPlan.slot), quantity:quantity};
        }

        if (!ItemUtil.isEquipment(name)) {
            var drugIndexes:Array = drugs.getIndexes();
            for (var d:Number = 0; d < drugIndexes.length; d++) {
                var drugSlot:Number = Number(drugIndexes[d]);
                var drugItem:Object = drugs.getItem(drugSlot);
                if (remainingStackAfterSubmit(drugItem, containmentPlan.药剂栏, drugSlot, name) > 0) {
                    return {available:true, storageKind:"drug", mode:"merge",
                        physicalSlot:drugSlot, quantity:quantity};
                }
            }

            var bagIndexes:Array = bag.getIndexes();
            for (var b:Number = 0; b < bagIndexes.length; b++) {
                var bagSlot:Number = Number(bagIndexes[b]);
                var bagItem:Object = bag.getItem(bagSlot);
                if (remainingStackAfterSubmit(bagItem, containmentPlan.背包, bagSlot, name) > 0) {
                    return {available:true, storageKind:"bag", mode:"merge",
                        physicalSlot:bagSlot, quantity:quantity};
                }
            }
        }

        var vacancy:Number = firstBagVacancyAfterSubmit(containmentPlan.背包);
        return vacancy < 0
            ? {available:false, storageKind:"unavailable", mode:"none",
                physicalSlot:-1, quantity:quantity}
            : {available:true, storageKind:"bag", mode:"insert",
                physicalSlot:vacancy, quantity:quantity};
    }

    private static function remainingStackAfterSubmit(item:Object, plan:Object,
            slot:Number, expectedName:String):Number {
        if (item == null || String(item.name) != expectedName || typeof item.value != "number") return 0;
        var consumed:Number = plan == null || plan[String(slot)] == undefined
            ? 0 : Number(plan[String(slot)]);
        if (isNaN(consumed) || consumed < 0) return 0;
        return Math.max(0, Number(item.value) - consumed);
    }

    private static function firstBagVacancyAfterSubmit(plan:Object):Number {
        var bag:Object = _root.物品栏.背包;
        for (var slot:Number = 0; slot < Number(bag.capacity); slot++) {
            var item:Object = bag.getItem(slot);
            if (item == null) return slot;
            if (plan == null || plan[String(slot)] == undefined) continue;
            if (typeof item.value != "number") return slot;
            var consumed:Number = Number(plan[String(slot)]);
            if (!isNaN(consumed) && consumed >= Number(item.value)) return slot;
        }
        return -1;
    }

    private static function requiresPhysicalOutputReceipt(delivery:Object):Boolean {
        return delivery != null && delivery.available === true
            && (delivery.storageKind == "bag" || delivery.storageKind == "drug");
    }

    private static function readOutputTarget(delivery:Object):Object {
        if (!requiresPhysicalOutputReceipt(delivery)) return null;
        var inventory:Object = delivery.storageKind == "bag"
            ? _root.物品栏.背包 : _root.物品栏.药剂栏;
        return inventory.getItem(Number(delivery.physicalSlot));
    }

    private static function outputTargetMatchesMode(target:Object, name:String,
            delivery:Object):Boolean {
        if (!requiresPhysicalOutputReceipt(delivery)) return true;
        if (delivery.mode == "insert") return target == null;
        return delivery.mode == "merge" && target != null
            && String(target.name) == name && typeof target.value == "number"
            && !isNaN(Number(target.value)) && isFinite(Number(target.value))
            && Number(target.value) > 0;
    }

    private static function outputReceiptMatchesPrototype(receipt:Object,
            prototype:Object, delivery:Object, beforeQuantity:Number):Boolean {
        if (receipt == null || prototype == null || receipt.item == null
                || receipt.confirmProjection == null || prototype.item == null
                || prototype.confirmProjection == null) return false;
        var expectedQuantity:Number = delivery.mode == "merge"
            ? beforeQuantity + Number(delivery.quantity) : Number(delivery.quantity);
        if (!isValidOutputValue(String(prototype.item.name), Number(prototype.item.quantity))
                || !isStrictWholeNumber(expectedQuantity)
                || Number(receipt.item.quantity) != expectedQuantity
                || Number(receipt.confirmProjection.quantity) != expectedQuantity
                || Number(prototype.item.quantity) != Number(delivery.quantity)
                || Number(prototype.confirmProjection.quantity) != Number(delivery.quantity)
                || !isStrictWholeNumber(Number(receipt.confirmProjection.lastUpdate))
                || Number(receipt.confirmProjection.lastUpdate) < 0) return false;

        var normalizedItem:Object = ObjectUtil.clone(receipt.item);
        normalizedItem.quantity = prototype.item.quantity;
        var normalizedConfirm:Object = ObjectUtil.clone(receipt.confirmProjection);
        delete normalizedConfirm.lastUpdate;
        normalizedConfirm.quantity = prototype.confirmProjection.quantity;
        return deepEqual(normalizedItem, prototype.item, 0)
            && deepEqual(normalizedConfirm, prototype.confirmProjection, 0);
    }

    private static function isValidOutputValue(name:String, value:Number):Boolean {
        if (!isStrictWholeNumber(value) || value <= 0 || value > 9007199254740991) return false;
        return !ItemUtil.isEquipment(name) || value <= EquipmentUtil.getMaxLevel();
    }

    private static function isStrictWholeNumber(value:Number):Boolean {
        return !isNaN(value) && isFinite(value) && Math.floor(value) == value;
    }

    private static function projectionSignature(value:Object):String {
        if (value == null) return "null";
        if (_json == undefined) _json = new LiteJSON();
        return _json.stringify(value);
    }

    private static function projectRecipe(category:String, recipe:Object, recipeIndex:Number,
            procurementSources:Object, ownedIndex:Object):Object {
        if (recipe == null || !ItemUtil.isItem(String(recipe.name))) return null;
        if (!org.flashNight.arki.scene.Cf6Type61Service.recipeAllowed(String(recipe.recipeId))) return null;
        _availabilityPlanCount++;
        var availabilityPlan:Object = buildPlan(
            category, recipeIndex, recipe, 1, false, procurementSources, ownedIndex, null, false);
        if (!availabilityPlan.success) return null;
        var value:Number = Number(recipe.value);
        if (isNaN(value) || value <= 0) value = 1;
        var recipeId:String = String(recipe.recipeId || "");
        if (recipeId == "") return null;
        var declared:Object = declaredTechnique(recipe);
        var entry:Object = {recipeId:recipeId, recipeIndex:recipeIndex,
            title:String(recipe.title || recipe.name),
            book:recipeBookName(recipe),
            infrastructure:projectInfrastructureRows(recipe),
            output:projectItem(String(recipe.name), value),
            owned:ProcurementPlanService.buildOwnedSummary(
                String(recipe.name), ownedIndex),
            plannedCrafts:ProcurementPlanService.getPlannedCrafts(recipeId),
            baseCost:{money:Number(recipe.price || 0), kpoints:Number(recipe.kprice || 0)},
            materialCount:recipe.materials instanceof Array ? recipe.materials.length : 0,
            batchEligible:availabilityPlan.batchEligible,
            canCraftOne:availabilityPlan.canCommit,
            availability:availabilityPlan.canCommit ? "ready" : String(availabilityPlan.blockingError)};
        if (declared != null) entry.technique = declared;
        return entry;
    }

    /**
     * 配方可选 "technique" 字段：调酒类目的调制方式门槛。
     * 形如 {shake:"light"|"hard"|"none", ice:Boolean, aged:Boolean,
     * karmotrine:"required"|"optional"|"none"}，不参与消耗；
     * karmotrine=="optional" 时预览允许选择加入一份卡莫特林。
     * 返回值仅含合法声明；非法或缺失一律返回 null 按未声明处理。
     */
    private static function declaredTechnique(recipe:Object):Object {
        var spec:Object = recipe.technique;
        if (spec == undefined || typeof spec != "object") return null;
        var shake:String = String(spec.shake);
        if (shake != "light" && shake != "hard" && shake != "none") return null;
        var karmotrine:String = String(spec.karmotrine);
        if (karmotrine != "required" && karmotrine != "optional"
                && karmotrine != "none") return null;
        return {shake:shake, ice:spec.ice === true, aged:spec.aged === true,
            karmotrine:karmotrine};
    }

    /**
     * Web 提交的调制方式 {shake, ice, aged, karmotrine} 与配方声明逐项比对；
     * 全等时返回标准化选择（卡莫特林折叠为 Boolean），否则返回 null。
     */
    private static function matchTechnique(declared:Object, chosen:Object):Object {
        if (chosen == undefined || typeof chosen != "object") return null;
        var shake:String = String(chosen.shake);
        if (shake != "light" && shake != "hard" && shake != "none") return null;
        var ice:Boolean = chosen.ice === true;
        var aged:Boolean = chosen.aged === true;
        var karmotrine:Boolean = chosen.karmotrine === true;
        if (shake != declared.shake) return null;
        if (ice != declared.ice) return null;
        if (aged != declared.aged) return null;
        if (karmotrine && declared.karmotrine != "optional") return null;
        return {shake:shake, ice:ice, aged:aged, karmotrine:karmotrine};
    }

    /**
     * 配方可选 "book" 字段：目录端按菜谱/图谱归属分组展示（如"基础家常菜配方"）。
     * 未显式声明时回落为材料列表中首个以"配方"结尾的物品名，找不到则为空串。
     */
    private static function recipeBookName(recipe:Object):String {
        var book:String = recipe.book == undefined ? "" : String(recipe.book);
        if (book != "") return book;
        var materials:Array = recipe.materials instanceof Array ? recipe.materials : [];
        for (var i:Number = 0; i < materials.length; i++) {
            var entry:String = String(materials[i] || "");
            var hashAt:Number = entry.lastIndexOf("#");
            var itemName:String = hashAt >= 0 ? entry.substring(0, hashAt) : entry;
            if (itemName.length >= 2
                    && itemName.substring(itemName.length - 2) == "配方") {
                return itemName;
            }
        }
        return "";
    }

    /**
     * 配方可选 "infrastructure" 字段：基建等级门槛，不参与消耗。
     * 取值 "设施名#所需等级"，或同形字符串数组，或 {name, level} 对象；
     * 所需等级对应 _root.基建系统.infrastructure[name] 的已完工级数，
     * 判定与 _root.基建系统.检查基建等级(name, level) 语义一致。
     */
    private static function recipeInfrastructure(recipe:Object):Array {
        var raw:Object = recipe.infrastructure;
        if (raw == undefined || raw == null) return [];
        var entries:Array = raw instanceof Array ? raw : [raw];
        var rows:Array = [];
        for (var i:Number = 0; i < entries.length; i++) {
            var entry:Object = entries[i];
            var name:String = "";
            var level:Number = NaN;
            if (typeof entry == "string") {
                var text:String = String(entry);
                var hashAt:Number = text.lastIndexOf("#");
                if (hashAt <= 0) continue;
                name = text.substring(0, hashAt);
                level = Number(text.substring(hashAt + 1));
            } else if (typeof entry == "object" && entry != null) {
                name = String(entry.name || "");
                level = Number(entry.level);
            }
            if (name == "" || !isStrictWholeNumber(level) || level < 1 || level > 99) {
                continue;
            }
            rows.push({name:name, required:level});
        }
        return rows;
    }

    private static function infrastructureLevel(name:String):Number {
        var system:Object = _root.基建系统;
        if (system == undefined || system.infrastructure == undefined) return 0;
        var value:Number = Number(system.infrastructure[name]);
        return isNaN(value) || value < 0 ? 0 : value;
    }

    private static function infrastructureAppliance(name:String, required:Number):String {
        var system:Object = _root.基建系统;
        if (system == undefined || system.dict == undefined) return "";
        var entry:Object = system.dict[name];
        if (entry == undefined || !(entry.Level instanceof Array)) return "";
        var node:Object = entry.Level[required - 1];
        if (node == undefined || node.Description == undefined) return "";
        return String(node.Description);
    }

    private static function projectInfrastructureRows(recipe:Object):Array {
        var requirements:Array = recipeInfrastructure(recipe);
        var rows:Array = [];
        for (var i:Number = 0; i < requirements.length; i++) {
            var name:String = String(requirements[i].name);
            var required:Number = Number(requirements[i].required);
            var current:Number = infrastructureLevel(name);
            rows.push({name:name, required:required, current:current,
                appliance:infrastructureAppliance(name, required),
                met:current >= required});
        }
        return rows;
    }

    private static function infrastructureSignature(rows:Array):String {
        var parts:Array = [];
        for (var i:Number = 0; i < rows.length; i++) {
            parts.push(String(rows[i].name) + "=" + Number(rows[i].current));
        }
        return parts.join(",");
    }

    private static function projectItem(name:String, value:Number):Object {
        var data:Object = ItemUtil.getRawItemData(name);
        var equipment:Boolean = ItemUtil.isEquipment(name);
        var actionType:Object = data == null ? "" : (data.actiontype != undefined ? data.actiontype : data.actionType);
        var weaponType:Object = data == null ? "" : (data.weapontype != undefined ? data.weapontype : data.weaponType);
        return {name:name,
            displayName:projectLegacyIdentityField(data == null ? undefined : data.displayname, name),
            icon:projectLegacyIdentityField(data == null ? undefined : data.icon, name),
            itemKind:equipment ? "equipment" : "stack", value:value,
            quantity:equipment ? 1 : value, enhancementLevel:equipment ? value : 0,
            majorType:data == null ? "" : String(data.type || ""),
            use:data == null ? "" : String(data.use || ""),
            actionType:actionType == undefined ? "" : String(actionType),
            weaponType:weaponType == undefined ? "" : String(weaponType),
            setId:data == null ? "" : String(data.setId || ""),
            setName:data == null ? "" : String(data.setName || ""),
            setOrder:data == null ? 0 : Number(data.setOrder || 0)};
    }

    private static function resolveRecipe(category:String, recipeIndex:Number):Object {
        var recipes:Array = getRecipes(category);
        if (recipes == null) return fail("category_not_found");
        if (isNaN(recipeIndex) || Math.floor(recipeIndex) != recipeIndex
                || recipeIndex < 0 || recipeIndex >= recipes.length) return fail("recipe_not_found");
        if (!org.flashNight.arki.scene.Cf6Type61Service.recipeAllowed(String(recipes[recipeIndex].recipeId))) return fail("recipe_not_found");
        return {success:true, recipe:recipes[recipeIndex]};
    }

    private static function getRecipes(category:String):Array {
        if (!isCategory(category) || _root.改装清单 == undefined) return null;
        var recipes:Array = _root.改装清单[category];
        return recipes instanceof Array ? recipes : null;
    }

    private static function isCategory(category:String):Boolean { return _categories[category] === true; }

    private static function recipeSignature(recipe:Object):String {
        var materials:Array = recipe.materials instanceof Array ? recipe.materials : [];
        return [String(recipe.title || ""), String(recipe.name || ""), Number(recipe.value || 1),
            Number(recipe.price || 0), Number(recipe.kprice || 0), materials.join("|")].join(";");
    }

    private static function inventoryRevision(inventory:Object):Number {
        return inventory != null && typeof inventory.getMutationRevision == "function"
            ? Number(inventory.getMutationRevision()) : 0;
    }

    private static function reverseSkillLevel():Number {
        var skill:Object = _root.主角被动技能 == undefined ? null : _root.主角被动技能.逆向;
        var level:Number = skill != null && skill.启用 ? Number(skill.等级) : 0;
        return isNaN(level) ? 0 : level;
    }

    private static function smithState():Object {
        var skill:Object = _root.主角被动技能 == undefined ? null : _root.主角被动技能.铁匠;
        var level:Number = skill == null ? 0 : Number(skill.等级);
        if (isNaN(level)) level = 0;
        return {enabled:skill != null && skill.启用 && level > 0, level:level};
    }

    private static function buildSkills():Object {
        var smith:Object = smithState();
        return {reverseLevel:reverseSkillLevel(), smithEnabled:smith.enabled, smithLevel:smith.level};
    }

    private static function buildGender():String {
        return String(_root.性别) == "女" ? "女" : "男";
    }

    private static function buildBalance():Object {
        return {money:Number(_root.金钱 || 0), kpoints:Number(_root.虚拟币 || 0)};
    }

    private static function categoryNote(category:String):String {
        if (category == "烹饪") return "菜品配方不会被消耗；部分菜品需要对应烹饪设备等级。";
        if (category == "化学生产") return "合成产出可能会受炼金等级影响（暂未实装）";
        if (category == "调酒") return "调酒配方不会被消耗；调制方式必须与配方一致，卡莫特林可选的配方可自行决定是否加入。";
        if (category == "插件合成") return "合成的经济消耗受铁匠等级影响";
        if (smithState().enabled) return "铁匠效果：减少货币消耗，装备继承素材最高强化度";
        return "改装后的装备默认强化等级为 1";
    }

    private static function deepEqual(left:Object, right:Object, depth:Number):Boolean {
        if (left === right) return true;
        if (depth > 16 || left == null || right == null || typeof left != typeof right) return false;
        if (typeof left != "object") return String(left) == String(right);
        var leftArray:Boolean = left instanceof Array;
        if (leftArray != (right instanceof Array)) return false;
        if (leftArray && left.length != right.length) return false;
        var leftCount:Number = 0;
        var rightCount:Number = 0;
        for (var leftKey:String in left) {
            if (typeof left.hasOwnProperty == "function" && !left.hasOwnProperty(leftKey)) continue;
            leftCount++;
            if (!deepEqual(left[leftKey], right[leftKey], depth + 1)) return false;
        }
        for (var rightKey:String in right) {
            if (typeof right.hasOwnProperty == "function" && !right.hasOwnProperty(rightKey)) continue;
            rightCount++;
        }
        return leftCount == rightCount;
    }

    private static function fail(errorCode:String):Object { return {success:false, error:errorCode}; }

    private static function sendResponse(response:Object):Void {
        if (_root.server == undefined || _root.server.sendSocketMessage == undefined) return;
        if (_json == undefined) _json = new LiteJSON();
        // 响应含用户可编辑自由文本（材料描述/档案摘要等），必须标准转义；
        // LiteJSON.stringify 不转义，含引号文本会产生畸形 JSON 并被 Host 静默丢弃。
        _root.server.sendSocketMessage(_json.stringifySafe(response));
    }

    public static function testOnlyReset():Void {
        _busy = false; _plan = null; _planSeq = 0;
        _availabilityPlanCount = 0; _maximumProbeCount = 0;
        ProcurementPlanService.testOnlyResetStats();
        MaterialArchiveProjector.reset();
    }

    public static function testOnlyStats():Object {
        var procurementStats:Object = ProcurementPlanService.testOnlyStats();
        return {availabilityPlans:_availabilityPlanCount,
            maximumProbes:_maximumProbeCount,
            purchaseSourceIndexes:Number(procurementStats.purchaseSourceIndexes),
            ownedIndexes:Number(procurementStats.ownedIndexes)};
    }
}
