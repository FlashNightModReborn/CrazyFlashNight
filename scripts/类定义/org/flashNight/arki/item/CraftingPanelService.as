import org.flashNight.arki.item.ItemUtil;

import org.flashNight.arki.item.EquipmentUtil;
import org.flashNight.arki.item.InventoryPanelService;
import org.flashNight.arki.item.MaterialArchiveProjector;
import org.flashNight.arki.item.ProcurementPlanService;
import org.flashNight.arki.item.PlayerAssetTransaction;
import org.flashNight.arki.item.obtain.ItemObtainIndex;
import org.flashNight.arki.item.synthesis.SynthesisIndex;
import org.flashNight.gesh.object.ObjectUtil;
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
            var planResult:Object = ProcurementPlanService.setPlan(params);
            _busy = false;
            return planResult;
        }
        if (commandName != "commit") return fail("unsupported_cmd");
        _busy = true;
        var result:Object = executeCommit(params);
        _busy = false;
        return result;
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
        return {success:true, v:1, category:category, gender:buildGender(), recipes:catalog,
            balance:buildBalance(), skills:buildSkills(),
            procurement:ProcurementPlanService.buildPlanSummary(),
            note:categoryNote(category)};
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
        var plan:Object = buildPlan(category, recipeIndex, resolved.recipe, craftCount, true);
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
            introHTML:String(tooltip.introHTML || "")};
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
        var current:Object = buildPlan(category, Number(plan.recipeIndex), resolved.recipe,
            Number(plan.craftCount), false);
        if (!current.success || current.stateSignature != String(plan.stateSignature)) return fail("stale_state");
        if (!current.canCommit) return fail(String(current.blockingError || "stale_state"));
        // 配方、进阶配置与产物投影都必须在首次写入前与预览冻结计划完全一致。
        if (!deepEqual(current.acceptedPlan, plan.acceptedPlan, 0)) return fail("stale_state");

        var bag:Object = _root.物品栏.背包;
        var drugs:Object = _root.物品栏.药剂栏;
        var materials:Object = _root.收集品栏.材料;
        var intelligence:Object = _root.收集品栏.情报;
        var backup:Object = {bag:bag.toObject(), drugs:drugs.toObject(),
            materials:materials.toObject(), intelligence:intelligence.toObject(),
            money:Number(_root.金钱), kpoints:Number(_root.虚拟币),
            dirty:_root.存档系统 == undefined ? undefined : _root.存档系统.dirtyMark};

        var assetContext:Object = {
            source:"crafting", reason:"craft_commit", mergeScope:"operation"
        };
        var assetTransaction:Object = PlayerAssetTransaction.begin(assetContext);
        try {
            if (!ItemUtil.submit(current.requirements, assetContext)) {
                PlayerAssetTransaction.rollback(assetTransaction);
                return fail("material_missing");
            }
            var actualRequire:Object = ItemUtil.singleRequire(current.output.name, current.output.value);
            var actualDelivery:Object = projectOutputDelivery(
                current.output.name, current.output.value, actualRequire);
            if (!deepEqual(actualDelivery, plan.outputDelivery, 0)) {
                restoreState(backup);
                PlayerAssetTransaction.rollback(assetTransaction);
                return fail("stale_state");
            }
            var targetBefore:Object = readOutputTarget(actualDelivery);
            if (!outputTargetMatchesMode(targetBefore, current.output.name, actualDelivery)) {
                restoreState(backup);
                PlayerAssetTransaction.rollback(assetTransaction);
                return fail("stale_state");
            }
            var beforeQuantity:Number = targetBefore == null ? 0 : Number(targetBefore.value);
            if (!ItemUtil.singleAcquire(current.output.name, current.output.value, assetContext)) {
                restoreState(backup);
                PlayerAssetTransaction.rollback(assetTransaction);
                return fail("inventory_full");
            }
            var outputReceipt:Object = null;
            if (requiresPhysicalOutputReceipt(actualDelivery)) {
                outputReceipt = InventoryPanelService.buildOutputReceipt(readOutputTarget(actualDelivery));
                if (!outputReceiptMatchesPrototype(outputReceipt, plan.acceptedPlan.outputPrototype,
                        actualDelivery, beforeQuantity)) {
                    restoreState(backup);
                    PlayerAssetTransaction.rollback(assetTransaction);
                    return fail("stale_state");
                }
            } else if (plan.acceptedPlan.outputPrototype != null) {
                restoreState(backup);
                PlayerAssetTransaction.rollback(assetTransaction);
                return fail("stale_state");
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
            if (_root.存档系统 != undefined) _root.存档系统.dirtyMark = true;
            var procurement:Object = ProcurementPlanService.consumeCompleted(
                String(resolved.recipe.recipeId || ""), Number(current.craftCount));
            var successResponse:Object = {success:true, v:1, operation:"commit", category:category,
                recipeIndex:Number(current.recipeIndex), craftCount:Number(current.craftCount),
                crafted:current.output, acceptedPlan:plan.acceptedPlan,
                outputReceipt:outputReceipt, balance:buildBalance(), procurement:procurement};
        } catch (commitError) {
            restoreState(backup);
            PlayerAssetTransaction.rollback(assetTransaction);
            trace("[CraftingPanelService] asset commit failed: " + commitError);
            return fail("commit_failed");
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

    private static function restoreState(backup:Object):Void {
        _root.物品栏.背包.setItems(backup.bag);
        _root.物品栏.药剂栏.setItems(backup.drugs);
        _root.收集品栏.材料.setItems(backup.materials);
        _root.收集品栏.情报.setItems(backup.intelligence);
        _root.金钱 = Number(backup.money);
        _root.虚拟币 = Number(backup.kpoints);
        if (_root.存档系统 != undefined) _root.存档系统.dirtyMark = backup.dirty;
    }

    private static function buildPlan(category:String, recipeIndex:Number, recipe:Object,
            craftCount:Number, calculateMaximum:Boolean,
            procurementSources:Object, ownedIndex:Object):Object {
        var baseRequirements:Array = ItemUtil.getRequirementFromTask(recipe.materials || []);
        var batchEligible:Boolean = isBatchEligible(recipe, baseRequirements);
        if (!batchEligible && craftCount != 1) return fail("batch_not_supported");
        var requirements:Array = scaleRequirements(baseRequirements, craftCount);
        // contain() is the canonical deduction planner used by submit().  Project its
        // concrete storage route instead of making the Web layer infer one from names.
        var containmentPlan:Object = ItemUtil.contain(requirements);
        if (procurementSources == null) {
            procurementSources = ProcurementPlanService.buildPurchaseSourceIndex();
        }
        if (ownedIndex == null) ownedIndex = ProcurementPlanService.buildOwnedIndex();
        var materialRows:Array = [];
        var allMaterials:Boolean = containmentPlan != null;
        var inheritedLevel:Number = 1;
        var stateParts:Array = [];
        for (var i:Number = 0; i < requirements.length; i++) {
            var projection:Object = projectRequirement(requirements[i], containmentPlan,
                procurementSources, ownedIndex);
            if (projection == null) return fail("item_not_found");
            materialRows.push(projection);
            if (projection.itemKind == "equipment") {
                inheritedLevel = Math.max(inheritedLevel, projection.maxEnhancement);
            }
            stateParts.push(projection.name + ":" + projection.owned + ":"
                + projection.maxEnhancement + ":" + projection.storageKind);
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
        if (!levelAllowed) blockingError = "level_locked";
        else if (!allMaterials) blockingError = "material_missing";
        else if (!enoughMoney) blockingError = "insufficient_money";
        else if (!enoughKpoints) blockingError = "insufficient_kpoint";
        else if (!projectionReady) blockingError = "output_projection_failed";
        else if (!enoughSpace) blockingError = "inventory_full";
        var maxCraftCount:Number = batchEligible
            ? (calculateMaximum
                ? calculateMaxCraftCount(recipe, baseRequirements, multiplier, levelAllowed)
                : (blockingError == "" ? 1 : 0))
            : (blockingError == "" ? 1 : 0);
        var output:Object = projectItem(String(recipe.name), outputValue);
        output.requiredLevel = requiredLevel;
        var acceptedPlan:Object = {category:category, recipeIndex:recipeIndex,
            craftCount:craftCount, output:output, materials:materialRows,
            outputDelivery:outputDelivery, outputPrototype:outputPrototype, cost:cost};
        var stateSignature:String = [recipeSignature(recipe), Number(_root.金钱),
            Number(_root.虚拟币), Number(_root.等级), reverseLevel, smith.enabled, smith.level,
            inventoryRevision(_root.物品栏.背包), inventoryRevision(_root.物品栏.药剂栏),
            craftCount, stateParts.join("|"), outputDelivery.storageKind,
            outputDelivery.mode, outputDelivery.physicalSlot,
            projectionSignature(outputPrototype)].join(";");
        return {success:true, category:category, recipeIndex:recipeIndex, craftCount:craftCount,
            recipeSignature:recipeSignature(recipe), stateSignature:stateSignature,
            requirements:requirements, materials:materialRows, output:output, cost:cost,
            outputDelivery:outputDelivery, acceptedPlan:acceptedPlan,
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
            levelAllowed:plan.levelAllowed, enoughMaterials:plan.enoughMaterials,
            enoughMoney:plan.enoughMoney, enoughKpoints:plan.enoughKpoints,
            enoughSpace:plan.enoughSpace, canCommit:plan.canCommit,
            blockingError:plan.blockingError};
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
            multiplier:Number, levelAllowed:Boolean):Number {
        if (!levelAllowed) return 0;
        var low:Number = 0;
        var high:Number = MAX_CRAFT_COUNT;
        while (low < high) {
            var middle:Number = Math.ceil((low + high) / 2);
            _maximumProbeCount++;
            if (canCraftCount(recipe, requirements, middle, multiplier)) low = middle;
            else high = middle - 1;
        }
        return low;
    }

    private static function canCraftCount(recipe:Object, requirements:Array,
            craftCount:Number, multiplier:Number):Boolean {
        var scaled:Array = scaleRequirements(requirements, craftCount);
        var containmentPlan:Object = ItemUtil.contain(scaled);
        if (containmentPlan == null) return false;
        if (Number(_root.金钱) < adjustedUnitCost(recipe.price, multiplier) * craftCount) return false;
        if (Number(_root.虚拟币) < adjustedUnitCost(recipe.kprice, multiplier) * craftCount) return false;
        var outputValue:Number = Number(recipe.value);
        if (isNaN(outputValue) || outputValue <= 0) outputValue = 1;
        outputValue *= craftCount;
        if (!isValidOutputValue(String(recipe.name), outputValue)) return false;
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
            procurementSources:Object, ownedIndex:Object):Object {
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
            owned = Number(ownedSummary.usable);
            if (kind == "equipment") {
                maxEnhancement = Number(ownedSummary.usableMaxEnhancement);
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
                return {available:true, storageKind:"drug", mode:"merge",
                    physicalSlot:Number(drugKey), quantity:quantity};
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

        if (!ItemUtil.isEquipment(name)) {
            var drugs:Object = _root.物品栏.药剂栏;
            var drugIndexes:Array = drugs.getIndexes();
            for (var d:Number = 0; d < drugIndexes.length; d++) {
                var drugSlot:Number = Number(drugIndexes[d]);
                var drugItem:Object = drugs.getItem(drugSlot);
                if (remainingStackAfterSubmit(drugItem, containmentPlan.药剂栏, drugSlot, name) > 0) {
                    return {available:true, storageKind:"drug", mode:"merge",
                        physicalSlot:drugSlot, quantity:quantity};
                }
            }

            var bag:Object = _root.物品栏.背包;
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
        _availabilityPlanCount++;
        var availabilityPlan:Object = buildPlan(
            category, recipeIndex, recipe, 1, false, procurementSources, ownedIndex);
        if (!availabilityPlan.success) return null;
        var value:Number = Number(recipe.value);
        if (isNaN(value) || value <= 0) value = 1;
        var recipeId:String = String(recipe.recipeId || "");
        if (recipeId == "") return null;
        return {recipeId:recipeId, recipeIndex:recipeIndex,
            title:String(recipe.title || recipe.name),
            output:projectItem(String(recipe.name), value),
            owned:ProcurementPlanService.buildOwnedSummary(
                String(recipe.name), ownedIndex),
            plannedCrafts:ProcurementPlanService.getPlannedCrafts(recipeId),
            baseCost:{money:Number(recipe.price || 0), kpoints:Number(recipe.kprice || 0)},
            materialCount:recipe.materials instanceof Array ? recipe.materials.length : 0,
            batchEligible:availabilityPlan.batchEligible,
            canCraftOne:availabilityPlan.canCommit,
            availability:availabilityPlan.canCommit ? "ready" : String(availabilityPlan.blockingError)};
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
        if (category == "烹饪") return "菜品配方不会被消耗";
        if (category == "化学生产") return "合成产出可能会受炼金等级影响（暂未实装）";
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
