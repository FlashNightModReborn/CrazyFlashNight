import org.flashNight.arki.item.ItemUtil;

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
        _root.gameCommands["craftingPreview"] = function(params) {
            org.flashNight.arki.item.CraftingPanelService.handle("preview", params);
        };
        _root.gameCommands["craftingTooltip"] = function(params) {
            org.flashNight.arki.item.CraftingPanelService.handle("tooltip", params);
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
        if (source != "legacy_crafting_entry" && source != "world_npc"
                && source != "crafting_entry") source = "crafting_entry";
        var payload:String = org.flashNight.arki.ui.PanelRequestEnvelope.build(
            "crafting", source, [], [{name:"category", value:category}]
        );
        return _root.server.sendSocketMessage(payload);
    }

    public static function handle(commandName:String, params:Object):Void {
        var callId:Number = params == undefined ? 0 : Number(params.callId);
        var response:Object;
        try {
            response = execute(commandName, params || {});
        } catch (error) {
            trace("[CraftingPanelService] " + commandName + " failed: " + error);
            response = fail("internal_error");
            _busy = false;
        }
        response.task = "crafting_response";
        response.callId = callId;
        sendResponse(response);
    }

    public static function execute(commandName:String, params:Object):Object {
        if (_busy && commandName != "snapshot" && commandName != "tooltip") return fail("busy");
        if (commandName == "snapshot") return executeSnapshot(params);
        if (commandName == "preview") return executePreview(params);
        if (commandName == "tooltip") return executeTooltip(params);
        if (commandName != "commit") return fail("unsupported_cmd");
        _busy = true;
        var result:Object = executeCommit(params);
        _busy = false;
        return result;
    }

    private static function executeSnapshot(params:Object):Object {
        var category:String = String(params.category || "");
        var recipes:Array = getRecipes(category);
        if (recipes == null) return fail("category_not_found");
        _plan = null;
        var catalog:Array = [];
        for (var i:Number = 0; i < recipes.length; i++) {
            var projected:Object = projectRecipe(category, recipes[i], i);
            if (projected != null) catalog.push(projected);
        }
        return {success:true, v:1, category:category, recipes:catalog,
            balance:buildBalance(), skills:buildSkills(), note:categoryNote(category)};
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
        return {success:true, v:1, itemName:itemName,
            displayname:String(tooltip.displayname || itemName),
            descHTML:String(tooltip.descHTML || "").split('"').join("'"),
            introHTML:String(tooltip.introHTML || "").split('"').join("'")};
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

        var bag:Object = _root.物品栏.背包;
        var drugs:Object = _root.物品栏.药剂栏;
        var materials:Object = _root.收集品栏.材料;
        var intelligence:Object = _root.收集品栏.情报;
        var backup:Object = {bag:bag.toObject(), drugs:drugs.toObject(),
            materials:materials.toObject(), intelligence:intelligence.toObject(),
            money:Number(_root.金钱), kpoints:Number(_root.虚拟币),
            dirty:_root.存档系统 == undefined ? undefined : _root.存档系统.dirtyMark};

        if (!ItemUtil.submit(current.requirements)) return fail("material_missing");
        if (!ItemUtil.singleAcquire(current.output.name, current.output.value)) {
            restoreState(backup);
            return fail("inventory_full");
        }
        _root.金钱 = Number(backup.money) - Number(current.cost.money);
        _root.虚拟币 = Number(backup.kpoints) - Number(current.cost.kpoints);
        if (_root.存档系统 != undefined) _root.存档系统.dirtyMark = true;
        if (_root.soundEffectManager != undefined) _root.soundEffectManager.playSound("收银机.mp3");
        return {success:true, v:1, operation:"commit", category:category,
            recipeIndex:Number(current.recipeIndex), craftCount:Number(current.craftCount),
            crafted:current.output, balance:buildBalance()};
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
            craftCount:Number, calculateMaximum:Boolean):Object {
        var baseRequirements:Array = ItemUtil.getRequirementFromTask(recipe.materials || []);
        var batchEligible:Boolean = isBatchEligible(recipe, baseRequirements);
        if (!batchEligible && craftCount != 1) return fail("batch_not_supported");
        var requirements:Array = scaleRequirements(baseRequirements, craftCount);
        var materialRows:Array = [];
        var allMaterials:Boolean = true;
        var inheritedLevel:Number = 1;
        var stateParts:Array = [];
        for (var i:Number = 0; i < requirements.length; i++) {
            var projection:Object = projectRequirement(requirements[i]);
            if (projection == null) return fail("item_not_found");
            materialRows.push(projection);
            allMaterials = allMaterials && projection.enough;
            if (projection.itemKind == "equipment") {
                inheritedLevel = Math.max(inheritedLevel, projection.maxEnhancement);
            }
            stateParts.push(projection.name + ":" + projection.owned + ":" + projection.maxEnhancement);
        }

        var outputData:Object = ItemUtil.getRawItemData(String(recipe.name));
        if (outputData == null) return fail("item_not_found");
        var unitOutputValue:Number = Number(recipe.value);
        if (isNaN(unitOutputValue) || unitOutputValue <= 0) unitOutputValue = 1;
        var outputValue:Number = ItemUtil.isEquipment(String(recipe.name))
            ? unitOutputValue : unitOutputValue * craftCount;
        var smith:Object = smithState();
        if (smith.enabled && ItemUtil.isEquipment(String(recipe.name))) {
            outputValue = Math.max(outputValue, inheritedLevel);
        }
        var multiplier:Number = smith.enabled ? Math.max(0, 1 - smith.level * 0.05) : 1;
        var cost:Object = {money:Math.max(0, Number(recipe.price || 0) * multiplier * craftCount),
            kpoints:Math.max(0, Number(recipe.kprice || 0) * multiplier * craftCount)};
        var requiredLevel:Number = outputData.data == undefined ? 0 : Number(outputData.data.level || 0);
        var reverseLevel:Number = reverseSkillLevel();
        var levelAllowed:Boolean = Number(_root.等级) + reverseLevel >= requiredLevel;
        var enoughMoney:Boolean = Number(_root.金钱) >= cost.money;
        var enoughKpoints:Boolean = Number(_root.虚拟币) >= cost.kpoints;
        // 与旧系统保持保守容量语义：在扣素材前核算，避免依赖“消耗后腾格”的时序。
        var enoughSpace:Boolean = ItemUtil.singleRequire(String(recipe.name), outputValue) != null;
        var blockingError:String = "";
        if (!levelAllowed) blockingError = "level_locked";
        else if (!allMaterials) blockingError = "material_missing";
        else if (!enoughMoney) blockingError = "insufficient_money";
        else if (!enoughKpoints) blockingError = "insufficient_kpoint";
        else if (!enoughSpace) blockingError = "inventory_full";
        var maxCraftCount:Number = batchEligible
            ? (calculateMaximum
                ? calculateMaxCraftCount(recipe, baseRequirements, multiplier, levelAllowed)
                : (blockingError == "" ? 1 : 0))
            : (blockingError == "" ? 1 : 0);
        var output:Object = projectItem(String(recipe.name), outputValue);
        output.requiredLevel = requiredLevel;
        var stateSignature:String = [recipeSignature(recipe), Number(_root.金钱),
            Number(_root.虚拟币), Number(_root.等级), reverseLevel, smith.enabled, smith.level,
            inventoryRevision(_root.物品栏.背包), inventoryRevision(_root.物品栏.药剂栏),
            craftCount, stateParts.join("|")].join(";");
        return {success:true, category:category, recipeIndex:recipeIndex, craftCount:craftCount,
            recipeSignature:recipeSignature(recipe), stateSignature:stateSignature,
            requirements:requirements, materials:materialRows, output:output, cost:cost,
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
            cost:plan.cost, balance:plan.balance, skills:plan.skills,
            levelAllowed:plan.levelAllowed, enoughMaterials:plan.enoughMaterials,
            enoughMoney:plan.enoughMoney, enoughKpoints:plan.enoughKpoints,
            enoughSpace:plan.enoughSpace, canCommit:plan.canCommit,
            blockingError:plan.blockingError};
        if (plan.canCommit) result.craftToken = plan.token;
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
        if (ItemUtil.contain(scaleRequirements(requirements, craftCount)) == null) return false;
        if (Number(_root.金钱) < Math.max(0, Number(recipe.price || 0) * multiplier * craftCount)) return false;
        if (Number(_root.虚拟币) < Math.max(0, Number(recipe.kprice || 0) * multiplier * craftCount)) return false;
        var outputValue:Number = Number(recipe.value);
        if (isNaN(outputValue) || outputValue <= 0) outputValue = 1;
        return ItemUtil.singleRequire(String(recipe.name), outputValue * craftCount) != null;
    }

    private static function projectRequirement(req:Object):Object {
        var name:String = String(req.name || "");
        var data:Object = ItemUtil.getRawItemData(name);
        if (data == null) return null;
        var required:Number = Number(req.value);
        if (isNaN(required) || required <= 0) required = 1;
        var owned:Number = 0;
        var maxEnhancement:Number = 0;
        var kind:String = ItemUtil.isEquipment(name) ? "equipment" : "stack";
        var consumed:Boolean = !ItemUtil.isInformation(name);
        if (ItemUtil.isMaterial(name)) {
            owned = Number(_root.收集品栏.材料.getValue(name) || 0);
        } else if (ItemUtil.isInformation(name)) {
            owned = Number(_root.收集品栏.情报.getValue(name) || 0);
        } else if (kind == "equipment") {
            var bag:Object = _root.物品栏.背包;
            var indexes:Array = bag.getIndexes();
            for (var i:Number = 0; i < indexes.length; i++) {
                var item:Object = bag.getItem(indexes[i]);
                if (item == null || String(item.name) != name) continue;
                owned++;
                maxEnhancement = Math.max(maxEnhancement, Number(item.value.level || 0));
            }
        } else {
            owned = Number(_root.物品栏.背包.getTotal(name) || 0)
                + Number(_root.物品栏.药剂栏.getTotal(name) || 0);
        }
        var enough:Boolean = kind == "equipment" && !req.isQuantity
            ? maxEnhancement >= required : owned >= required;
        return {name:name, displayName:String(data.displayname || name), icon:String(data.icon || name),
            itemKind:kind, required:required, owned:owned, maxEnhancement:maxEnhancement,
            isQuantity:req.isQuantity === true, tier:req.tier == undefined ? "" : String(req.tier),
            consumed:consumed, enough:enough};
    }

    private static function projectRecipe(category:String, recipe:Object, recipeIndex:Number):Object {
        if (recipe == null || !ItemUtil.isItem(String(recipe.name))) return null;
        _availabilityPlanCount++;
        var availabilityPlan:Object = buildPlan(category, recipeIndex, recipe, 1, false);
        if (!availabilityPlan.success) return null;
        var value:Number = Number(recipe.value);
        if (isNaN(value) || value <= 0) value = 1;
        return {recipeIndex:recipeIndex, title:String(recipe.title || recipe.name),
            output:projectItem(String(recipe.name), value),
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
        return {name:name, displayName:data == null ? name : String(data.displayname || name),
            icon:data == null ? name : String(data.icon || name),
            itemKind:equipment ? "equipment" : "stack", value:value,
            quantity:equipment ? 1 : value, enhancementLevel:equipment ? value : 0,
            majorType:data == null ? "" : String(data.type || ""),
            use:data == null ? "" : String(data.use || ""),
            actionType:actionType == undefined ? "" : String(actionType),
            weaponType:weaponType == undefined ? "" : String(weaponType)};
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

    private static function fail(errorCode:String):Object { return {success:false, error:errorCode}; }

    private static function sendResponse(response:Object):Void {
        if (_root.server == undefined || _root.server.sendSocketMessage == undefined) return;
        if (_json == undefined) _json = new LiteJSON();
        _root.server.sendSocketMessage(_json.stringify(response));
    }

    public static function testOnlyReset():Void {
        _busy = false; _plan = null; _planSeq = 0;
        _availabilityPlanCount = 0; _maximumProbeCount = 0;
    }

    public static function testOnlyStats():Object {
        return {availabilityPlans:_availabilityPlanCount, maximumProbes:_maximumProbeCount};
    }
}
