import org.flashNight.arki.item.CraftingPanelService;
import org.flashNight.arki.item.EquipmentUtil;
import org.flashNight.arki.item.ProcurementPlanService;
import org.flashNight.arki.item.MaterialArchiveProjector;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.item.BaseItem;
import org.flashNight.arki.item.PlayerAssetTransaction;
import org.flashNight.arki.item.itemCollection.ArrayInventory;
import org.flashNight.arki.item.itemCollection.DictCollection;
import org.flashNight.arki.item.itemCollection.EquipmentInventory;
import org.flashNight.arki.item.obtain.ItemObtainIndex;
import org.flashNight.arki.item.synthesis.SynthesisIndex;
import org.flashNight.arki.task.TaskUtil;
import org.flashNight.neur.Event.EventBus;
import org.flashNight.neur.Event.LifecycleEventDispatcher;
import org.flashNight.gesh.tooltip.builder.ObtainMethodsBuilder;

/** CraftingPanelService C0-C3 回归测试。 */
class org.flashNight.arki.item.CraftingPanelServiceTest {
    private static var passed:Number = 0;
    private static var failed:Number = 0;

    public static function runAllTests():Void {
        passed = 0; failed = 0;
        setup();
        testOpenRequestWire();
        testMaterialsProjection();
        testMaterialsV2SnapshotProjection();
        testMaterialBoundaryProbe();
        testDropOccurrenceProjection();
        testStaticSourceOccurrenceIdentity();
        testExactRecipeUseOccurrences();
        testLegacyIdentityWhitespaceFallback();
        testInformationOverflowPolicy();
        testSnapshotProjection();
        testSnapshotGenderNormalization();
        testSnapshotAvailabilityRefresh();
        testNestedCraftingSourceProjection();
        testProcurementOwnedScope();
        testProcurementPlanAndTaskDemand();
        testProcurementMutationAndConsumption();
        testProcurementFaultRestoresExactSnapshot();
        testSubmitReentryRestoresExactSnapshot();
        testPreviewAuthority();
        testStoragePlanProjection();
        testMergeReceiptAuthority();
        testOutputValueAndPrototypeAuthority();
        testBatchAuthority();
        testStalePlanHasNoWrite();
        testProjectionDriftHasNoWrite();
        testAtomicCommitAndReplay();
        testBlockedPreviewHasNoToken();
        testResponseWire();
        testResponseWireEscaping();
        testHandleDirectDispatch();
        trace("CraftingPanelServiceTest Tests Passed: " + passed);
        trace("CraftingPanelServiceTest Tests Failed: " + failed);
    }

    private static function setup():Void {
        var data:Object = {};
        data["测试矿石"] = itemData("测试矿石", "收集品", "材料", 0);
        data["测试图纸"] = itemData("测试图纸", "收集品", "情报", 0);
        data["测试图纸"].price = 1000;
        data["旧测试枪"] = itemData("旧测试枪", "武器", "手枪", 1);
        data["光棱射线弹-强化"] = itemData("光棱射线弹-强化", "武器", "手枪", 12);
        data["光棱射线弹-强化"].displayname = "棱镜折射阵列";
        data["光棱射线弹-强化"].icon = "全光谱棱镜阵列";
        data["光棱射线弹-强化"].actiontype = "双刀";
        data["光棱射线弹-强化"].setId = "test_sidearm";
        data["光棱射线弹-强化"].setName = "测试侧武器套装";
        data["光棱射线弹-强化"].rarity = "rare";
        data["测试药剂"] = itemData("测试药剂", "消耗品", "药剂", 1);
        ItemUtil.itemDataDict = data;
        ItemUtil.equipmentDict = {};
        ItemUtil.equipmentDict["旧测试枪"] = true;
        ItemUtil.equipmentDict["光棱射线弹-强化"] = true;
        ItemUtil.materialDict = {};
        ItemUtil.materialDict["测试矿石"] = true;
        ItemUtil.informationMaxValueDict = {};
        ItemUtil.informationMaxValueDict["测试图纸"] = 99;
        // 同一 fresh runner 会继续执行 NPC suite；只安装本域命令，不能清空
        // 其他生产域已经挂载的 gameCommands。
        if (_root.gameCommands == undefined) _root.gameCommands = {};
        _root.Web物品注释HTML = function(name:String):Object {
            return {displayname:name, descHTML:"desc", introHTML:"intro"};
        };
        _root.soundEffectManager = {playSound:function():Void {}};
        CraftingPanelService.install();
        resetOwned();
    }

    private static function itemData(name:String, type:String, use:String, level:Number):Object {
        return {name:name, displayname:name, icon:name + "图标", type:type, use:use, weapontype:use,
            data:{level:level, modslot:0}};
    }

    private static function resetOwned():Void {
        _root.物品栏 = {
            背包:new ArrayInventory(null, 5),
            药剂栏:new ArrayInventory(null, 8),
            装备栏:new EquipmentInventory(null),
            战备箱:new ArrayInventory(null, 80)
        };
        _root.收集品栏 = {
            材料:new DictCollection(null),
            情报:new DictCollection(null)
        };
        _root.收集品栏.材料.add("测试矿石", 5);
        _root.收集品栏.情报.add("测试图纸", 1);
        _root.物品栏.背包.add(0, BaseItem.create("旧测试枪", 5));
        _root.金钱 = 1000;
        _root.虚拟币 = 100;
        _root.等级 = 10;
        _root.性别 = "男";
        _root.主角被动技能 = {
            逆向:{启用:true, 等级:2},
            铁匠:{启用:true, 等级:2}
        };
        _root.存档系统 = {dirtyMark:false};
        _root._saveExt = {};
        _root.tasks_to_do = [];
        TaskUtil.tasks = [];
        TaskUtil.task_texts = {};
        _root.主线任务进度 = 14;
        _root.task_chains_progress = {};
        _root.基建系统 = {infrastructure:{}};
        _root.改装清单 = {};
        _root.改装分类顺序 = ["武器合成"];
        _root.改装清单["武器合成"] = [
            {recipeId:"craft.weapon.001", title:"棱镜折射阵列图纸", name:"光棱射线弹-强化", price:101, kprice:21,
                materials:["测试图纸#1", "旧测试枪#3", "测试矿石#2"]},
            {recipeId:"craft.weapon.002", title:"测试药剂图纸", name:"测试药剂", value:3, price:0, kprice:0,
                materials:["测试矿石#9"]}
        ];
        _root.改装清单对象 = {};
        _root.改装清单对象["光棱射线弹-强化"] = _root.改装清单["武器合成"][0];
        _root.改装清单对象["测试药剂"] = _root.改装清单["武器合成"][1];
        ItemUtil.itemDataDict["光棱射线弹-强化"].synthesis = "光棱射线弹-强化";
        ItemUtil.itemDataDict["测试药剂"].synthesis = "测试药剂";
        _root.图鉴信息 = {材料大全:[
            {Name:"测试矿石", Information:"【掉落单位】测试敌人\n【掉落关卡】测试关卡"}
        ]};
        var shop:Object = {};
        shop["测试商人"] = {};
        shop["测试商人"]["0"] = "测试矿石";
        shop["测试商人"]["1"] = "旧测试枪";
        _root.shops = shop;
        _root.kshop_list = [{id:"mat-1", item:"测试矿石", type:"材料", price:1}];
        var obtainIndex:ItemObtainIndex = ItemObtainIndex.getInstance();
        obtainIndex.reset(true);
        obtainIndex.buildIndex(_root.改装清单, shop, _root.kshop_list);
        SynthesisIndex.reset();
        CraftingPanelService.testOnlyReset();
    }

    private static function testNestedCraftingSourceProjection():Void {
        resetOwned();
        var materials:Array = _root.改装清单["武器合成"][0].materials;
        materials.push("测试药剂#1");
        SynthesisIndex.reset();
        var result:Object = CraftingPanelService.execute("preview", {
            category:"武器合成", recipeIndex:0, craftCount:1
        });
        var nested:Object = result.materials[result.materials.length - 1];
        var sources:Array = nested.craftingSources;
        check(result.success && nested.name == "测试药剂"
                && sources.length == 1
                && sources[0].category == "武器合成"
                && sources[0].recipeIndex == 1
                && sources[0].recipeId == "craft.weapon.002"
                && sources[0].title == "测试药剂图纸",
            "preview projects exact nested crafting source identity without Web inference");
        materials.pop();
        SynthesisIndex.reset();
        CraftingPanelService.testOnlyReset();
    }

    private static function testOpenRequestWire():Void {
        var previous:Object = _root.server;
        _root.server = {sent:null, sendCount:0};
        _root.server.sendSocketMessage = function(message:String):Boolean {
            this.sent = message;
            this.sendCount++;
            return true;
        };
        var opened:Boolean = CraftingPanelService.openPanel("武器合成", "world_crafting_entry");
        check(opened && String(_root.server.sent) == '{"task":"panel_request","panel":"crafting","source":"world_crafting_entry","initData":{"category":"武器合成"}}',
            "world crafting entry emits strict panel request");
        check(!CraftingPanelService.openPanel("未知分类", "world_crafting_entry"),
            "unknown crafting category is rejected before host");
        check(CraftingPanelService.openMaterialsPanel("nativehud_materials")
            && String(_root.server.sent) == '{"task":"panel_request","panel":"crafting","source":"nativehud_materials","initData":{"view":"materials"}}',
            "missing material token retains the legacy ordinary envelope");
        check(CraftingPanelService.openMaterialsPanel(
                "nativehud_materials", "material.open.1.Valid_-~")
            && String(_root.server.sent) == '{"task":"panel_request","panel":"crafting","source":"nativehud_materials","openRequestId":"material.open.1.Valid_-~","initData":{"view":"materials"}}',
            "legal material token is echoed exactly at panel_request top level");
        var beforeInvalid:Number = Number(_root.server.sendCount);
        var overlong:String = "";
        for (var i:Number = 0; i < 161; i++) overlong += "a";
        check(!CraftingPanelService.openMaterialsPanel(
                "nativehud_materials", null)
            && !CraftingPanelService.openMaterialsPanel(
                "nativehud_materials", 7)
            && !CraftingPanelService.openMaterialsPanel(
                "nativehud_materials", "")
            && !CraftingPanelService.openMaterialsPanel(
                "nativehud_materials", "bad token")
            && !CraftingPanelService.openMaterialsPanel(
                "nativehud_materials", "bad/token")
            && !CraftingPanelService.openMaterialsPanel(
                "nativehud_materials", overlong)
            && Number(_root.server.sendCount) == beforeInvalid,
            "explicit malformed or overlong material tokens perform zero sends");
        _root.server = previous;
    }

    private static function testMaterialsProjection():Void {
        resetOwned();
        var catalog:Object = CraftingPanelService.execute("materials", {});
        check(catalog.success && catalog.v == 1 && catalog.view == "materials"
            && catalog.materials.length == 1 && catalog.materials[0].name == "测试矿石"
            && catalog.materials[0].owned == 5 && catalog.materials[0].sourceCount == 2
            && catalog.materials[0].useCount == 2 && catalog.materials[0].hasSourceSummary,
            "material catalog projects owned count and existing source/use indexes");
        var detail:Object = CraftingPanelService.execute("materialDetail", {itemName:"测试矿石"});
        check(detail.success && detail.material.name == "测试矿石"
            && detail.material.sourceSummary.indexOf("测试关卡") >= 0
            && detail.sources.length == 2 && detail.sources[0].kind == "shop"
            && detail.sources[1].kind == "kshop"
            && detail.uses.length == 2 && detail.uses[0].required > 0,
            "material detail exposes annotation, structured sources and recipe uses");
        var previousEnemyTable:Object = _root.敌人属性表;
        _root.敌人属性表 = {};
        _root.敌人属性表["敌人-enemy.internal.visible"] = {displayname:"敌人展示名"};
        _root.敌人属性表["敌人-enemy.internal.equal"] = {displayname:"敌人-enemy.internal.equal"};
        _root.敌人属性表["敌人-enemy.internal.missing"] = {};
        _root.敌人属性表["敌人-enemy.internal.sentinel"] = {displayname:" Undefined "};
        _root.敌人属性表["敌人-enemy.internal.wrong"] = {displayname:{legacy:"bad"}};
        var obtainIndex:ItemObtainIndex = ItemObtainIndex.getInstance();
        obtainIndex.updateEnemyDrops("敌人-enemy.internal.visible", [
            {名字:"测试矿石", 概率:0.25, 最小逆向等级:1, 最大逆向等级:9}
        ]);
        obtainIndex.updateEnemyDrops("敌人-enemy.internal.equal", [
            {名字:"测试矿石", 概率:0.2, 最小逆向等级:0, 最大逆向等级:0}
        ]);
        obtainIndex.updateEnemyDrops("敌人-enemy.internal.missing", [
            {名字:"测试矿石", 概率:0.15, 最小逆向等级:0, 最大逆向等级:0}
        ]);
        obtainIndex.updateEnemyDrops("敌人-enemy.internal.sentinel", [
            {名字:"测试矿石", 概率:0.1, 最小逆向等级:0, 最大逆向等级:0}
        ]);
        obtainIndex.updateEnemyDrops("敌人-enemy.internal.wrong", [
            {名字:"测试矿石", 概率:0.05, 最小逆向等级:0, 最大逆向等级:0}
        ]);
        obtainIndex.updateQuestRewards("quest.internal.visible", "任务展示名", ["测试矿石#1"]);
        obtainIndex.updateQuestRewards("quest.internal.equal", "quest.internal.equal", ["测试矿石#1"]);
        obtainIndex.updateQuestRewards("quest.internal.missing", undefined, ["测试矿石#2"]);
        obtainIndex.updateQuestRewards("quest.internal.sentinel", " Undefined ", ["测试矿石#1"]);
        obtainIndex.updateQuestRewards(
            "quest.internal.wrong", {legacy:"bad"}, ["测试矿石#1"]);
        var labelled:Object = CraftingPanelService.execute("materialDetail", {itemName:"测试矿石"});
        var visibleEnemy:Object = null;
        var equalEnemy:Object = null;
        var missingEnemy:Object = null;
        var sentinelEnemy:Object = null;
        var wrongEnemy:Object = null;
        var visibleQuest:Object = null;
        var equalQuest:Object = null;
        var missingQuest:Object = null;
        var sentinelQuest:Object = null;
        var wrongQuest:Object = null;
        for (var sourceIndex:Number = 0; sourceIndex < labelled.sources.length; sourceIndex++) {
            var source:Object = labelled.sources[sourceIndex];
            if (source.enemyType == "敌人-enemy.internal.visible") visibleEnemy = source;
            else if (source.enemyType == "敌人-enemy.internal.equal") equalEnemy = source;
            else if (source.enemyType == "敌人-enemy.internal.missing") missingEnemy = source;
            else if (source.enemyType == "敌人-enemy.internal.sentinel") sentinelEnemy = source;
            else if (source.enemyType == "敌人-enemy.internal.wrong") wrongEnemy = source;
            else if (source.questId == "quest.internal.visible") visibleQuest = source;
            else if (source.questId == "quest.internal.equal") equalQuest = source;
            else if (source.questId == "quest.internal.missing") missingQuest = source;
            else if (source.questId == "quest.internal.sentinel") sentinelQuest = source;
            else if (source.questId == "quest.internal.wrong") wrongQuest = source;
        }
        check(visibleEnemy != null && equalEnemy != null && missingEnemy != null
                && sentinelEnemy != null && wrongEnemy != null
                && visibleEnemy.displayName == "敌人展示名"
                && equalEnemy.displayName == equalEnemy.enemyType
                && missingEnemy.displayName == "未知敌人"
                && sentinelEnemy.displayName == "未知敌人"
                && wrongEnemy.displayName == "未知敌人",
            "enemy source accepts explicit equality and neutralizes missing, sentinel and wrong-type labels");
        check(visibleQuest != null && equalQuest != null && missingQuest != null
                && sentinelQuest != null && wrongQuest != null
                && visibleQuest.title == "任务展示名"
                && equalQuest.title == equalQuest.questId
                && missingQuest.title == "未知任务"
                && sentinelQuest.title == "未知任务"
                && wrongQuest.title == "未知任务",
            "quest source accepts explicit equality and neutralizes missing, sentinel and wrong-type labels");
        _root.敌人属性表 = previousEnemyTable;
        var missing:Object = CraftingPanelService.execute("materialDetail", {itemName:"未知材料"});
        check(!missing.success && missing.error == "item_not_found",
            "material detail rejects unknown names");
    }

    /** A2：catalog/detail v2 使用同一 frozen snapshot，来源与用途 exact 投影。 */
    private static function testMaterialsV2SnapshotProjection():Void {
        resetOwned();
        var previousCatalog:Object = _root.材料档案目录;
        var previousOrder:Object = _root.改装分类顺序;
        var previousEnemyTable:Object = _root.敌人属性表;
        var previousUi:Object = _root.UI系统;
        var previousShops:Object = _root.shops;
        var previousBoot:Object = _root.__boot;
        var previousNpcService:Object = previousUi == undefined
            ? undefined : previousUi.NPC商店WebView;
        var previousModDict:Object = EquipmentUtil.modDict;
        var previousModList:Array = EquipmentUtil.modList;
        var previousInfrastructureSystem:Object = _root.基建系统;
        var previousInfrastructure:Object = previousInfrastructureSystem == undefined
            ? undefined : previousInfrastructureSystem.infrastructure;

        EquipmentUtil.modDict = {};
        EquipmentUtil.modList = [];
        if (_root.基建系统 == undefined) _root.基建系统 = {};
        _root.基建系统.infrastructure = {自行车:0, 摩托车:0, 越野车:0};
        var taxonomyMods:Array = materialTaxonomyModFixtures();
        var catalogMaterials:Array = [
            {Name:"测试矿石", typeId:"general", legacyVisible:true,
                legacyInformation:"【档案摘要】测试矿石",
                authoredDirectPurposeId:"system:equipment_tuning"}
        ];
        for (var taxonomyIndex:Number = 0; taxonomyIndex < taxonomyMods.length;
                taxonomyIndex++) {
            var taxonomyMod:Object = taxonomyMods[taxonomyIndex];
            var taxonomyName:String = String(taxonomyMod.name);
            ItemUtil.itemDataDict[taxonomyName] = itemData(
                taxonomyName, "收集品", "材料", 0);
            ItemUtil.materialDict[taxonomyName] = true;
            EquipmentUtil.modDict[taxonomyName] = taxonomyMod;
            EquipmentUtil.modList.push(taxonomyName);
            catalogMaterials.push({Name:taxonomyName, typeId:"equipment_mod",
                legacyVisible:false});
        }
        _root.改装分类顺序 = ["武器合成"];
        _root.材料档案目录 = {
            schemaVersion:1,
            DirectPurpose:{id:"system:equipment_tuning", label:"装备改装",
                order:0, consumerEvidence:"EquipmentTuningService"},
            Material:catalogMaterials
        };
        _root.敌人属性表 = {};
        _root.敌人属性表["敌人-测试两档"] = {displayname:"测试两档"};
        _root.敌人属性表["敌人-键:|𠀀"] = {displayname:"特殊键敌人"};

        var index:ItemObtainIndex = ItemObtainIndex.getInstance();
        index.updateEnemyDrops("敌人-测试两档", [
            {名字:"测试矿石", 概率:3, 最大逆向等级:2, 最小数量:1, 最大数量:1},
            {名字:"测试矿石", 概率:5, 最小逆向等级:3, 最小数量:2, 最大数量:4}
        ]);
        index.updateEnemyDrops("敌人-键:|𠀀", [
            {名字:"测试矿石", 概率:7}
        ]);
        index.updateStageDrops("测试关卡多档", [
            ["测试矿石", 8, 1], ["测试矿石", 50, 2]
        ]);

        if (_root.UI系统 == undefined) _root.UI系统 = {};
        _root.__boot = {shopCatalogReady:true};
        _root.shops = {};
        _root.shops["测试商人"] = {};
        _root.shops["测试商人"]["0"] = "测试矿石";
        _root.shops["测试商人"]["1"] = "旧测试枪";
        var shopProjector:Object = {price:120, locked:true, maxQuantity:0,
            buyRatePermille:1000, lastBuyRatePermille:null,
            rateReadCount:0, catalogCallCount:0, catalogMode:"exact"};
        shopProjector.getBuyRatePermille = function():Number {
            this.rateReadCount++;
            return Number(this.buyRatePermille);
        };
        shopProjector.buildCatalog = function(
                shopId:String, buyRatePermille:Number):Array {
            if (!org.flashNight.gesh.number.NumberUtil.isSafeNonNegativeInteger(
                    buyRatePermille)
                    || buyRatePermille !== Number(this.buyRatePermille)) {
                return null;
            }
            this.catalogCallCount++;
            this.lastBuyRatePermille = buyRatePermille;
            if (this.catalogMode == "empty") return [];
            if (this.catalogMode == "non_array") return null;
            if (this.catalogMode == "throw") throw "shop_catalog_fixture_throw";
            if (this.catalogMode == "wrong_index") {
                return [{catalogIndex:1, itemName:"测试矿石"}];
            }
            if (this.catalogMode == "wrong_name") {
                return [{catalogIndex:0, itemName:"测试药剂"}];
            }
            if (this.catalogMode == "duplicate") {
                return [{catalogIndex:0, itemName:"测试矿石"},
                    {catalogIndex:0, itemName:"测试矿石"}];
            }
            return [{catalogIndex:0, itemName:"测试矿石",
                    basePrice:this.price,
                    unitPrice:org.flashNight.gesh.number.NumberUtil.floorPermille(
                        this.price, buyRatePermille),
                    requiredInfo:"测试图纸", locked:this.locked,
                    maxQuantity:this.maxQuantity},
                {catalogIndex:1, itemName:"旧测试枪",
                    basePrice:900, unitPrice:900, requiredInfo:"",
                    locked:false, maxQuantity:0}];
        };
        _root.UI系统.NPC商店WebView = shopProjector;

        var catalog:Object = CraftingPanelService.execute("materials", {v:2});
        var snapshotId:String = String(catalog.snapshotId || "");
        var mineral:Object = catalog.success ? catalog.materials[0] : null;
        var mod:Object = catalog.success ? catalog.materials[1] : null;
        check(catalog.success && catalog.v == 2 && catalog.view == "materials"
                && snapshotId.indexOf("materials.snapshot.") == 0
                && catalog.navigationAccess.shop === false
                && catalog.navigationAccess.crafting === false
                && catalog.taxonomy.recipePurposes.length == 1
                && catalog.taxonomy.recipePurposes[0].id == "recipe:武器合成"
                && catalog.taxonomy.directPurposes[0].id
                    == "system:equipment_tuning"
                && catalog.materials.length == 7
                && mineral.name == "测试矿石" && mineral.archiveOrder == 0
                && mod.name == "测试插件" && mod.archiveOrder == 1,
            "v2 catalog freezes authored order and projects versioned taxonomy");
        check(mineral.typeId == "general" && mineral.modFacetIds == undefined
                && mod.typeId == "equipment_mod"
                && mod.modFacetIds.grade == "high"
                && mod.modFacetIds.scope == "firearm"
                && mod.modFacetIds.role == "mechanism"
                && mineral.recipePurposeIds.length == 1
                && mineral.directPurposeIds.length == 1
                && mineral.useCount == 2
                && mineral.structuredPurposeCount == 3
                && mineral.sourceCount == 5
                && mineral.dropVariantCount == 5,
            "v2 catalog separates mod facets, recipe occurrences, purposes and source counts");

        // Caller mutation and later owned mutation cannot alter the frozen detail snapshot.
        catalog.materials[0].owned = 999;
        _root.收集品栏.材料.addValue("测试矿石", 10);
        // BootSequencer hands off by deleting the transient __boot object.
        // Runtime shop authority must therefore come only from the persistent
        // index, raw shop table and live NPC catalog service below.
        delete _root.__boot;
        var detail:Object = CraftingPanelService.execute("materialDetail", {
            v:2, snapshotId:snapshotId, itemName:"测试矿石"
        });
        var shop:Object = findProjectedSource(detail.sources, "shop", "shopId", "测试商人");
        var kshop:Object = findProjectedSource(detail.sources, "kshop", "entryId", "mat-1");
        var stage:Object = findProjectedSource(detail.sources, "stage", "stageName", "测试关卡多档");
        var enemy:Object = findProjectedSource(detail.sources, "enemy", "enemyType", "敌人-测试两档");
        var escaped:Object = findProjectedSource(detail.sources, "enemy", "enemyType", "敌人-键:|𠀀");
        check(detail.success && detail.snapshotId == snapshotId
                && detail.material.name == "测试矿石"
                && detail.material.owned == 5
                && detail.material.sourceSummary == "【档案摘要】测试矿石"
                && detail.sourceCount == 5 && detail.dropVariantCount == 5
                && detail.useCount == 2 && detail.structuredPurposeCount == 3,
            "v2 detail reuses immutable catalog state while preserving authored summary");
        check(shop != null && shop.sourceOrder == 0
                && shop.basePrice == 120 && shop.unitPriceAtSnapshot == 120
                && shop.requiredInfo == "测试图纸" && shop.locked
                && shop.shopAccessMode == "full"
                && shop.shopAccessReason == "indexed_live_match"
                && shopProjector.lastBuyRatePermille === 1000
                && kshop != null && kshop.sourceOrder == 1
                && kshop.catalogIndex == 0 && kshop.entryId == "mat-1"
                && kshop.category == "材料" && kshop.priceK == 1
                && stage != null && stage.sourceOrder == 2
                && stage.variants.length == 2
                && stage.variants[0].defaultBranchChancePercent == 12.5
                && enemy != null && enemy.variants.length == 2
                && enemy.variants[0].chanceInputState == "explicit"
                && enemy.variants[1].quantityMin == 2
                && escaped != null
                && escaped.sourceKey == "lp1|5:enemy|8:敌人-键:|𠀀",
            "v2 post-handoff sources retain full exact shop authority without transient boot state");
        check(detail.uses.length == 2
                && detail.uses[0].category == "武器合成"
                && detail.uses[0].recipeIndex == 0
                && detail.uses[0].productName == "光棱射线弹-强化"
                && detail.uses[0].itemKind == "equipment"
                && detail.uses[0].required == 2
                && detail.uses[0].ingredients.length == 3
                && detail.uses[0].ingredients[0].isQuantity === true
                && detail.uses[0].ingredients[1].isQuantity === false
                && detail.uses[0].ingredients[2].name == "测试矿石"
                && detail.uses[0].ingredients[2].icon == "测试矿石图标"
                && detail.uses[0].ingredients[2].required == 2
                && detail.uses[0].ingredients[2].isQuantity === true
                && detail.uses[1].recipeIndex == 1
                && detail.uses[1].required == 9
                && detail.directPurposes.length == 1
                && detail.infrastructureUses == undefined,
            "v2 uses preserve exact recipe occurrences and preview every required ingredient");

        testProductionNpcCatalogSeam(
            snapshotId, previousNpcService, shopProjector);

        var ordinarySnapshot:Object = CraftingPanelService.execute(
            "snapshot", {category:"武器合成"});
        var lockedShopAccess:Object = MaterialArchiveProjector.authorizeShopAccess(
            materialShopAccessRequest(snapshotId, 42));
        _root.基建系统.infrastructure.自行车 = 1;
        var bicycleCrafting:Object = CraftingPanelService.execute(
            "snapshot", {category:"武器合成", materialSnapshotId:snapshotId});
        _root.基建系统.infrastructure.摩托车 = 1;
        var motorcycleCrafting:Object = CraftingPanelService.execute(
            "snapshot", {category:"武器合成", materialSnapshotId:snapshotId});
        _root.基建系统.infrastructure.摩托车 = 0;
        _root.基建系统.infrastructure.越野车 = 1;
        var offroadCrafting:Object = CraftingPanelService.execute(
            "snapshot", {category:"武器合成", materialSnapshotId:snapshotId});
        _root.基建系统.infrastructure.越野车 = 0;
        var staleCrafting:Object = CraftingPanelService.execute(
            "snapshot", {category:"武器合成",
                materialSnapshotId:"materials.snapshot.stale"});
        var malformedCrafting:Object = CraftingPanelService.execute(
            "snapshot", {category:"武器合成", materialSnapshotId:7});
        check(ordinarySnapshot.success
                && exactShopAccessFailure(
                    lockedShopAccess, 42, "deny", "access_denied")
                && exactFailure(bicycleCrafting, "access_denied")
                && motorcycleCrafting.success && offroadCrafting.success
                && exactFailure(staleCrafting, "stale_snapshot")
                && exactFailure(malformedCrafting, "invalid_payload"),
            "material recipe navigation rechecks motorcycle/offroad live while ordinary crafting stays available");

        testMaterialShopAccessAuthorization(
            index, snapshotId, shopProjector);
        testProcurementShopAccessAuthorization(snapshotId);

        // Only shop dynamic fields may refresh inside one frozen material snapshot.
        shopProjector.price = 220;
        shopProjector.buyRatePermille = 700;
        var repriced:Object = CraftingPanelService.execute("materialDetail", {
            v:2, snapshotId:snapshotId, itemName:"测试矿石"
        });
        var repricedShop:Object = findProjectedSource(
            repriced.sources, "shop", "shopId", "测试商人");
        check(repriced.success && repriced.material.owned == 5
                && repricedShop.basePrice == 220
                && repricedShop.unitPriceAtSnapshot == 154
                && shopProjector.lastBuyRatePermille === 700,
            "v2 detail refreshes live NPC shop price, rate and lock projection");

        delete shopProjector.locked;
        var missingLocked:Object = CraftingPanelService.execute(
            "materialDetail", {v:2, snapshotId:snapshotId, itemName:"测试矿石"});
        shopProjector.locked = "false";
        var stringLocked:Object = CraftingPanelService.execute(
            "materialDetail", {v:2, snapshotId:snapshotId, itemName:"测试矿石"});
        shopProjector.locked = true;
        var restoredLocked:Object = CraftingPanelService.execute(
            "materialDetail", {v:2, snapshotId:snapshotId, itemName:"测试矿石"});
        check(!missingLocked.success && missingLocked.error == "shop_snapshot_mismatch"
                && !stringLocked.success && stringLocked.error == "shop_snapshot_mismatch"
                && restoredLocked.success,
            "v2 shop join requires an exact boolean locked field without coercion");

        var stale:Object = CraftingPanelService.execute("materialDetail", {
            v:2, snapshotId:"materials.snapshot.stale", itemName:"测试矿石"
        });
        var refreshed:Object = CraftingPanelService.execute("materials", {v:2});
        var retired:Object = CraftingPanelService.execute("materialDetail", {
            v:2, snapshotId:snapshotId, itemName:"测试矿石"
        });
        var unsupportedCatalog:Object = CraftingPanelService.execute("materials", {v:3});
        var unsupportedDetail:Object = CraftingPanelService.execute("materialDetail", {
            v:3, itemName:"测试矿石"
        });
        var stringVersion:Object = CraftingPanelService.execute("materials", {v:"2"});
        var booleanVersion:Object = CraftingPanelService.execute("materials", {v:true});
        var nullVersion:Object = CraftingPanelService.execute("materials", {v:null});
        check(!stale.success && stale.error == "stale_snapshot"
                && refreshed.success && refreshed.snapshotId != snapshotId
                && refreshed.navigationAccess.shop === true
                && refreshed.navigationAccess.crafting === false
                && !retired.success && retired.error == "stale_snapshot"
                && !unsupportedCatalog.success
                && unsupportedCatalog.error == "unsupported_version"
                && !unsupportedDetail.success
                && unsupportedDetail.error == "unsupported_version"
                && !stringVersion.success && stringVersion.error == "unsupported_version"
                && !booleanVersion.success && booleanVersion.error == "unsupported_version"
                && !nullVersion.success && nullVersion.error == "unsupported_version",
            "v2 rejects stale snapshots and non-integer material protocol versions without coercion");

        _root.基建系统.infrastructure.自行车 = 0;
        _root.基建系统.infrastructure.摩托车 = 1;
        var motorcycleCatalog:Object = CraftingPanelService.execute("materials", {v:2});
        _root.基建系统.infrastructure.摩托车 = 0;
        _root.基建系统.infrastructure.越野车 = 1;
        var offroadCatalog:Object = CraftingPanelService.execute("materials", {v:2});
        _root.基建系统.infrastructure.越野车 = 0;
        var lockedCatalog:Object = CraftingPanelService.execute("materials", {v:2});
        check(motorcycleCatalog.success && motorcycleCatalog.navigationAccess.shop
                && motorcycleCatalog.navigationAccess.crafting
                && offroadCatalog.success && offroadCatalog.navigationAccess.shop
                && offroadCatalog.navigationAccess.crafting
                && lockedCatalog.success && !lockedCatalog.navigationAccess.shop
                && !lockedCatalog.navigationAccess.crafting,
            "material navigation projection follows the existing vehicle fallback hierarchy");

        var legacy:Object = CraftingPanelService.execute("materials", {});
        var retiredByLegacy:Object = CraftingPanelService.execute("materialDetail", {
            v:2, snapshotId:String(refreshed.snapshotId), itemName:"测试矿石"
        });
        check(legacy.success && legacy.v == 1 && legacy.snapshotId == undefined
                && !retiredByLegacy.success
                && retiredByLegacy.error == "stale_snapshot",
            "legacy materials stays exact v1 and retires any prior v2 snapshot");

        // Identity trim-empty must match Host/Python for every non-ASCII
        // whitespace scalar in their shared contract; C0/C1 remain forbidden.
        var purpose:Object = _root.材料档案目录.DirectPurpose;
        var originalPurposeLabel:String = String(purpose.label);
        var whitespaceCodes:Array = [160,5760,8192,8193,8194,8195,8196,
            8197,8198,8199,8200,8201,8202,8232,8233,8239,8287,12288];
        var unicodeWhitespace:String = "";
        var allWhitespaceRejected:Boolean = true;
        for (var whitespaceIndex:Number = 0;
                whitespaceIndex < whitespaceCodes.length; whitespaceIndex++) {
            var whitespace:String = String.fromCharCode(
                Number(whitespaceCodes[whitespaceIndex]));
            unicodeWhitespace += whitespace;
            purpose.label = whitespace;
            var whitespaceFailure:Object = CraftingPanelService.execute(
                "materials", {v:2});
            if (whitespaceFailure.success
                    || whitespaceFailure.error != "invalid_purpose_registry") {
                allWhitespaceRejected = false;
            }
        }
        purpose.label = unicodeWhitespace + "UnDeFiNeD" + unicodeWhitespace;
        var wrappedUndefined:Object = CraftingPanelService.execute(
            "materials", {v:2});
        purpose.label = "C0" + String.fromCharCode(31);
        var c0Identity:Object = CraftingPanelService.execute("materials", {v:2});
        purpose.label = "C1" + String.fromCharCode(133);
        var c1Identity:Object = CraftingPanelService.execute("materials", {v:2});
        purpose.label = originalPurposeLabel;
        check(allWhitespaceRejected
                && !wrappedUndefined.success
                && wrappedUndefined.error == "invalid_purpose_registry"
                && !c0Identity.success && c0Identity.error == "invalid_purpose_registry"
                && !c1Identity.success && c1Identity.error == "invalid_purpose_registry",
            "v2 identities reject each Unicode trim-empty scalar, wrapped undefined and C0/C1 controls");

        // ordered list, dictionary own keys, material membership and catalog
        // equipment_mod rows are one exact set in both directions.
        EquipmentUtil.modDict["测试额外插件"] = taxonomyMods[0];
        var extraMod:Object = CraftingPanelService.execute("materials", {v:2});
        delete EquipmentUtil.modDict["测试额外插件"];
        EquipmentUtil.modList.push(EquipmentUtil.modList[0]);
        var duplicateMod:Object = CraftingPanelService.execute("materials", {v:2});
        EquipmentUtil.modList.pop();
        var missingModName:String = String(EquipmentUtil.modList.pop());
        var missingMod:Object = CraftingPanelService.execute("materials", {v:2});
        EquipmentUtil.modList.push(missingModName);
        var originalModType:String = String(catalogMaterials[1].typeId);
        catalogMaterials[1].typeId = "general";
        var misclassifiedMod:Object = CraftingPanelService.execute(
            "materials", {v:2});
        catalogMaterials[1].typeId = originalModType;
        delete ItemUtil.materialDict["测试插件"];
        var nonMaterialMod:Object = CraftingPanelService.execute("materials", {v:2});
        ItemUtil.materialDict["测试插件"] = true;
        check(!extraMod.success && extraMod.error == "invalid_mod_catalog_closure"
                && !duplicateMod.success
                && duplicateMod.error == "invalid_mod_catalog_closure"
                && !missingMod.success
                && missingMod.error == "invalid_mod_catalog_closure"
                && !misclassifiedMod.success
                && misclassifiedMod.error == "invalid_mod_catalog_closure"
                && !nonMaterialMod.success
                && nonMaterialMod.error == "invalid_catalog_item",
            "v2 rejects extra, duplicate, missing, misclassified and non-material mod registry members");

        testInfrastructureUsesProjection(catalogMaterials);
        testMaterialCollectionCapProductionPaths(catalogMaterials, index);

        var beforeFailedRefresh:Object = CraftingPanelService.execute(
            "materials", {v:2});
        purpose.label = String.fromCharCode(160);
        var failedRefresh:Object = CraftingPanelService.execute("materials", {v:2});
        purpose.label = originalPurposeLabel;
        var retiredAfterFailure:Object = CraftingPanelService.execute(
            "materialDetail", {v:2,
                snapshotId:String(beforeFailedRefresh.snapshotId),
                itemName:"测试矿石"});
        check(beforeFailedRefresh.success
                && exactFailure(failedRefresh, "invalid_purpose_registry")
                && exactFailure(retiredAfterFailure, "stale_snapshot"),
            "failed v2 catalog refresh is versionless and retires the prior snapshot");

        for (var cleanupModIndex:Number = 0;
                cleanupModIndex < taxonomyMods.length; cleanupModIndex++) {
            var cleanupModName:String = String(taxonomyMods[cleanupModIndex].name);
            delete ItemUtil.itemDataDict[cleanupModName];
            delete ItemUtil.materialDict[cleanupModName];
        }
        EquipmentUtil.modDict = previousModDict;
        EquipmentUtil.modList = previousModList;
        if (previousInfrastructureSystem == undefined) {
            delete _root.基建系统;
        } else {
            _root.基建系统 = previousInfrastructureSystem;
            _root.基建系统.infrastructure = previousInfrastructure;
        }
        _root.材料档案目录 = previousCatalog;
        _root.改装分类顺序 = previousOrder;
        _root.敌人属性表 = previousEnemyTable;
        _root.shops = previousShops;
        _root.__boot = previousBoot;
        if (previousUi == undefined) {
            delete _root.UI系统;
        } else {
            _root.UI系统 = previousUi;
            _root.UI系统.NPC商店WebView = previousNpcService;
        }
        resetOwned();
    }

    /** 真实 NPC leaf 与材料详情/两种导航 consumer 的跨文件契约缝。 */
    private static function testProductionNpcCatalogSeam(snapshotId:String,
            productionService:Object, fixtureService:Object):Void {
        var infrastructure:Object = _root.基建系统.infrastructure;
        var previousBicycle = infrastructure.自行车;
        var previousMotorcycle = infrastructure.摩托车;
        var previousOffroad = infrastructure.越野车;
        var passive:Object = _root.主角被动技能;
        var hadEloquence:Boolean = passive.hasOwnProperty("口才");
        var previousEloquence = passive.口才;
        var mineralData:Object = ItemUtil.itemDataDict["测试矿石"];
        var equipmentData:Object = ItemUtil.itemDataDict["旧测试枪"];
        var mineralHadPrice:Boolean = mineralData.hasOwnProperty("price");
        var equipmentHadPrice:Boolean = equipmentData.hasOwnProperty("price");
        var previousMineralPrice = mineralData.price;
        var previousEquipmentPrice = equipmentData.price;
        var detail:Object = null;
        var ordinaryRequest:Object = materialShopAccessRequest(snapshotId, 142);
        var ordinaryAccess:Object = null;
        var recipeAccess:Object = null;
        var failure:String = "";

        try {
            if (productionService == undefined || productionService == null
                    || typeof productionService.getBuyRatePermille != "function"
                    || typeof productionService.buildCatalog != "function") {
                throw "production_npc_catalog_service_missing";
            }
            _root.UI系统.NPC商店WebView = productionService;
            mineralData.price = 120;
            equipmentData.price = 900;
            passive.口才 = {启用:true, 等级:5};
            infrastructure.自行车 = 0;
            infrastructure.摩托车 = 0;
            infrastructure.越野车 = 0;

            detail = CraftingPanelService.execute("materialDetail", {
                v:2, snapshotId:snapshotId, itemName:"测试矿石"});

            infrastructure.自行车 = 1;
            ordinaryAccess = MaterialArchiveProjector.authorizeShopAccess(
                ordinaryRequest);

            infrastructure.自行车 = 0;
            infrastructure.摩托车 = 1;
            recipeAccess = MaterialArchiveProjector.authorizeRecipeShopAccess(
                143, "测试矿石", "测试商人", 0);
        } catch (error) {
            failure = String(error);
        } finally {
            _root.UI系统.NPC商店WebView = fixtureService;
            infrastructure.自行车 = previousBicycle;
            infrastructure.摩托车 = previousMotorcycle;
            infrastructure.越野车 = previousOffroad;
            if (hadEloquence) passive.口才 = previousEloquence;
            else delete passive.口才;
            if (mineralHadPrice) mineralData.price = previousMineralPrice;
            else delete mineralData.price;
            if (equipmentHadPrice) equipmentData.price = previousEquipmentPrice;
            else delete equipmentData.price;
        }

        var liveShop:Object = detail == null || detail.success !== true
            ? null : findProjectedSource(
                detail.sources, "shop", "shopId", "测试商人");
        check(failure == "" && detail.success && liveShop != null
                && liveShop.basePrice === 120
                && liveShop.unitPriceAtSnapshot === 102,
            "production NPC catalog seam applies the live 850 permille rate to material detail");
        check(failure == "" && exactShopAccessAllow(
                ordinaryAccess, ordinaryRequest),
            "production NPC catalog seam authorizes exact material navigation with a bicycle");
        check(failure == "" && recipeAccess != null
                && recipeAccess.task == "material_shop_access_response"
                && recipeAccess.callId === 143 && recipeAccess.success === true
                && recipeAccess.v === 1 && recipeAccess.decision == "allow"
                && recipeAccess.reason == "indexed_live_match"
                && recipeAccess.materialName == "测试矿石"
                && recipeAccess.shopId == "测试商人"
                && recipeAccess.catalogIndex === 0
                && recipeAccess.itemName == "测试矿石"
                && hasExactKeys(recipeAccess, {task:true,callId:true,
                    success:true,v:true,decision:true,reason:true,
                    materialName:true,shopId:true,catalogIndex:true,
                    itemName:true}, 10),
            "production NPC catalog seam authorizes exact recipe procurement with a motorcycle");
    }

    /** A4b：Host-only 商店导航必须在点击时重新证明三层 authority。 */
    private static function testMaterialShopAccessAuthorization(
            index:ItemObtainIndex, snapshotId:String,
            shopProjector:Object):Void {
        var previousServer:Object = _root.server;
        _root.server = {sent:null, sendCount:0};
        _root.server.sendSocketMessage = function(message:String):Boolean {
            this.sent = message;
            this.sendCount++;
            return true;
        };

        var request:Object = materialShopAccessRequest(snapshotId, 1);
        var allowed:Object = invokeMaterialShopAccess(request);
        check(exactShopAccessAllow(allowed, request)
                && shopProjector.locked === true
                && Number(shopProjector.maxQuantity) == 0
                && allowed.error == undefined,
            "A4b exact source allows navigation even when locked and maxed");

        request = materialShopAccessRequest(snapshotId, 2147483647);
        var maxFid:Object = invokeMaterialShopAccess(request);
        check(exactShopAccessAllow(maxFid, request),
            "A4b fid maximum remains correlatable and emits the exact allow wire");

        var sendsBeforeInvalidFid:Number = Number(_root.server.sendCount);
        var badFids:Array = [0,-1,2147483648,1.5,"1",null,Number.NaN];
        var invalidFidsDropped:Boolean = true;
        for (var fidIndex:Number = 0; fidIndex < badFids.length; fidIndex++) {
            request = materialShopAccessRequest(snapshotId, 7);
            request.callId = badFids[fidIndex];
            if (invokeMaterialShopAccess(request) != null) invalidFidsDropped = false;
        }
        if (invokeMaterialShopAccess(null) != null) invalidFidsDropped = false;
        check(invalidFidsDropped
                && Number(_root.server.sendCount) == sendsBeforeInvalidFid,
            "A4b uncorrelatable fid/type/null requests produce zero response sends");

        var malformed:Array = [];
        request = materialShopAccessRequest(snapshotId, 11);
        request.extra = true; malformed.push(request);
        request = materialShopAccessRequest(snapshotId, 12);
        request.task = "CMD"; malformed.push(request);
        request = materialShopAccessRequest(snapshotId, 13);
        request.action = "craftingMaterials"; malformed.push(request);
        request = materialShopAccessRequest(snapshotId, 14);
        request.v = "1"; malformed.push(request);
        request = materialShopAccessRequest(snapshotId, 15);
        request.materialSnapshotId = null; malformed.push(request);
        request = materialShopAccessRequest(snapshotId, 16);
        request.materialName = 7; malformed.push(request);
        request = materialShopAccessRequest(snapshotId, 17);
        request.shopId = ""; malformed.push(request);
        request = materialShopAccessRequest(snapshotId, 18);
        request.catalogIndex = "0"; malformed.push(request);
        request = materialShopAccessRequest(snapshotId, 19);
        request.catalogIndex = -1; malformed.push(request);
        request = materialShopAccessRequest(snapshotId, 20);
        delete request.shopId; malformed.push(request);
        var allMalformedDenied:Boolean = true;
        for (var malformedIndex:Number = 0;
                malformedIndex < malformed.length; malformedIndex++) {
            var malformedResult:Object = invokeMaterialShopAccess(
                malformed[malformedIndex]);
            if (!exactShopAccessFailure(malformedResult,
                    Number(malformed[malformedIndex].callId), "deny",
                    "invalid_payload")) allMalformedDenied = false;
        }
        check(allMalformedDenied,
            "A4b strict request rejects extra/missing/constants/type/null/version without coercion");

        request = materialShopAccessRequest(snapshotId, 21);
        request.catalogIndex = 10000;
        var upperCap:Object = invokeMaterialShopAccess(request);
        request = materialShopAccessRequest(snapshotId, 22);
        request.catalogIndex = 10001;
        var overCap:Object = invokeMaterialShopAccess(request);
        check(exactShopAccessFailure(upperCap, 21,
                    "stale", "source_not_current")
                && exactShopAccessFailure(overCap, 22,
                    "deny", "invalid_payload")
                && MaterialArchiveProjector.testOnlyValidateBoundary(
                    "ShopCatalogIndex", 10000)
                && !MaterialArchiveProjector.testOnlyValidateBoundary(
                    "ShopCatalogIndex", 10001)
                && MaterialArchiveProjector.testOnlyValidateBoundary(
                    "NNI", 10001),
            "ShopCatalogIndex caps only shop paths at 10000 while KShop NNI stays wider");

        request = materialShopAccessRequest("materials.snapshot.stale", 23);
        check(exactShopAccessFailure(invokeMaterialShopAccess(request), 23,
                "stale", "stale_snapshot"),
            "A4b stale snapshot has its exact stale classification");

        var records:Array = index.getExactObtainRecords("测试矿石");
        var shopRecordIndex:Number = findCurrentShopRecordIndex(records,
            "测试商人", 0);
        var shopRecord:Object = records[shopRecordIndex];
        request = materialShopAccessRequest(snapshotId, 24);
        request.shopId = "其他商人";
        var frozenMissing:Object = invokeMaterialShopAccess(request);
        records.push({kind:ItemObtainIndex.KIND_SHOP, npc:"测试商人",
            shopId:"测试商人", itemName:"测试矿石", catalogIndex:0});
        var duplicateSource:Object = invokeMaterialShopAccess(
            materialShopAccessRequest(snapshotId, 25));
        records.pop();
        records.splice(shopRecordIndex, 1);
        var removedSource:Object = invokeMaterialShopAccess(
            materialShopAccessRequest(snapshotId, 26));
        records.splice(shopRecordIndex, 0, shopRecord);
        shopRecord.itemName = "测试药剂";
        var nameDriftSource:Object = invokeMaterialShopAccess(
            materialShopAccessRequest(snapshotId, 27));
        shopRecord.itemName = "测试矿石";
        check(shopRecordIndex >= 0
                && exactShopAccessFailure(frozenMissing, 24, "stale",
                    "source_not_current")
                && exactShopAccessFailure(duplicateSource, 25, "stale",
                    "source_not_current")
                && exactShopAccessFailure(removedSource, 26, "stale",
                    "source_not_current")
                && exactShopAccessFailure(nameDriftSource, 27, "stale",
                    "source_not_current"),
            "A4b frozen/current missing, duplicate, removal and name drift stay source_not_current");

        var liveShop:Object = _root.shops["测试商人"];
        delete _root.shops["测试商人"];
        var removedShop:Object = invokeMaterialShopAccess(
            materialShopAccessRequest(snapshotId, 28));
        _root.shops["测试商人"] = {};
        var emptyShop:Object = invokeMaterialShopAccess(
            materialShopAccessRequest(snapshotId, 29));
        var movedShop:Object = {};
        movedShop["1"] = "测试矿石";
        _root.shops["测试商人"] = movedShop;
        var movedSameName:Object = invokeMaterialShopAccess(
            materialShopAccessRequest(snapshotId, 30));
        var driftedShop:Object = {};
        driftedShop["0"] = "测试药剂";
        _root.shops["测试商人"] = driftedShop;
        var rawNameDrift:Object = invokeMaterialShopAccess(
            materialShopAccessRequest(snapshotId, 31));
        _root.shops["测试商人"] = liveShop;
        check(exactShopAccessFailure(removedShop, 28, "stale",
                    "catalog_not_current")
                && exactShopAccessFailure(emptyShop, 29, "stale",
                    "catalog_not_current")
                && exactShopAccessFailure(movedSameName, 30, "stale",
                    "catalog_not_current")
                && exactShopAccessFailure(rawNameDrift, 31, "stale",
                    "catalog_not_current"),
            "A4b removed/empty/drifted raw shop slots never fall through to same-name slots");

        shopProjector.catalogMode = "empty";
        var emptyCatalog:Object = invokeMaterialShopAccess(
            materialShopAccessRequest(snapshotId, 32));
        shopProjector.catalogMode = "wrong_index";
        var wrongIndex:Object = invokeMaterialShopAccess(
            materialShopAccessRequest(snapshotId, 33));
        shopProjector.catalogMode = "wrong_name";
        var wrongName:Object = invokeMaterialShopAccess(
            materialShopAccessRequest(snapshotId, 34));
        shopProjector.catalogMode = "duplicate";
        var duplicateCatalog:Object = invokeMaterialShopAccess(
            materialShopAccessRequest(snapshotId, 35));
        shopProjector.catalogMode = "exact";
        check(exactShopAccessFailure(emptyCatalog, 32, "stale",
                    "catalog_not_current")
                && exactShopAccessFailure(wrongIndex, 33, "stale",
                    "catalog_not_current")
                && exactShopAccessFailure(wrongName, 34, "stale",
                    "catalog_not_current")
                && exactShopAccessFailure(duplicateCatalog, 35, "stale",
                    "catalog_not_current"),
            "A4b live empty/index/name/duplicate catalog drift is catalog_not_current");

        var savedNpcService:Object = _root.UI系统.NPC商店WebView;
        delete _root.UI系统.NPC商店WebView;
        var serviceNotReady:Object = invokeMaterialShopAccess(
            materialShopAccessRequest(snapshotId, 37));
        _root.UI系统.NPC商店WebView = savedNpcService;
        var savedBuildCatalog:Function = shopProjector.buildCatalog;
        delete shopProjector.buildCatalog;
        var methodNotReady:Object = invokeMaterialShopAccess(
            materialShopAccessRequest(snapshotId, 38));
        shopProjector.buildCatalog = savedBuildCatalog;
        var savedRateGetter:Function = shopProjector.getBuyRatePermille;
        delete shopProjector.getBuyRatePermille;
        var rateMethodNotReady:Object = invokeMaterialShopAccess(
            materialShopAccessRequest(snapshotId, 381));
        shopProjector.getBuyRatePermille = savedRateGetter;
        var catalogCallsBeforeInvalidRate:Number =
            Number(shopProjector.catalogCallCount);
        var savedBuyRatePermille:Number = Number(shopProjector.buyRatePermille);
        shopProjector.buyRatePermille = Number.NaN;
        var invalidRate:Object = invokeMaterialShopAccess(
            materialShopAccessRequest(snapshotId, 382));
        shopProjector.buyRatePermille = savedBuyRatePermille;
        shopProjector.catalogMode = "non_array";
        var invalidProjector:Object = invokeMaterialShopAccess(
            materialShopAccessRequest(snapshotId, 39));
        shopProjector.catalogMode = "exact";
        check(exactShopAccessFailure(serviceNotReady, 37, "deny",
                    "authority_unavailable")
                && exactShopAccessFailure(methodNotReady, 38, "deny",
                    "authority_unavailable")
                && exactShopAccessFailure(rateMethodNotReady, 381, "deny",
                    "authority_unavailable")
                && exactShopAccessFailure(invalidRate, 382, "deny",
                    "authority_unavailable")
                && Number(shopProjector.catalogCallCount)
                    == catalogCallsBeforeInvalidRate + 1
                && exactShopAccessFailure(invalidProjector, 39, "deny",
                    "authority_unavailable"),
            "A4b service, rate, catalog and non-array readiness fail unavailable before unsafe use");

        shopProjector.catalogMode = "throw";
        var projectorThrew:Boolean = false;
        try {
            invokeMaterialShopAccess(materialShopAccessRequest(snapshotId, 40));
        } catch (error) {
            projectorThrew = true;
        }
        shopProjector.catalogMode = "exact";
        check(projectorThrew && _root.server.sent == null,
            "A4b dedicated handler preserves projector exceptions instead of masking them");

        index.reset(false);
        var indexNotReady:Object = invokeMaterialShopAccess(
            materialShopAccessRequest(snapshotId, 41));
        index.buildIndex(_root.改装清单, _root.shops, _root.kshop_list);
        check(exactShopAccessFailure(indexNotReady, 41, "deny",
                "authority_unavailable"),
            "A4b unbuilt ItemObtainIndex fails unavailable before live catalog authority");

        var savedShops:Object = _root.shops;
        delete _root.shops;
        var degradedDetail:Object = CraftingPanelService.execute(
            "materialDetail", {v:2, snapshotId:snapshotId,
                itemName:"测试矿石"});
        _root.shops = savedShops;
        var degradedShop:Object = findProjectedSource(
            degradedDetail.sources, "shop", "shopId", "测试商人");
        check(degradedDetail.success && degradedShop != null
                && degradedShop.shopAccessMode == "unavailable"
                && degradedShop.shopAccessReason
                    == "no_authoritative_remote_access_capability",
            "A4b v2 detail uses only the two frozen access pairs and degrades fail closed");

        _root.server = previousServer;
    }

    /** P3：合成条目直达金币商店必须额外复证基建与稳定配方身份。 */
    private static function testProcurementShopAccessAuthorization(
            snapshotId:String):Void {
        var previousServer:Object = _root.server;
        var infrastructure:Object = _root.基建系统.infrastructure;
        _root.server = {sent:null};
        _root.server.sendSocketMessage = function(message:String):Boolean {
            this.sent = message;
            return true;
        };

        infrastructure.自行车 = 1;
        infrastructure.摩托车 = 0;
        infrastructure.越野车 = 0;
        var request:Object = procurementShopAccessRequest(snapshotId, 43);
        var bicycleDenied:Object = invokeProcurementShopAccess(request);

        infrastructure.摩托车 = 1;
        var motorcycleAllowed:Object = invokeProcurementShopAccess(request);
        var equipmentRequest:Object = procurementShopAccessRequest(snapshotId, 51);
        equipmentRequest.materialName = "旧测试枪";
        equipmentRequest.catalogIndex = 1;
        var equipmentAllowed:Object = invokeProcurementShopAccess(equipmentRequest);
        infrastructure.摩托车 = 0;
        infrastructure.越野车 = 1;
        request = procurementShopAccessRequest(snapshotId, 44);
        var offroadAllowed:Object = invokeProcurementShopAccess(request);
        infrastructure.越野车 = 0;

        infrastructure.摩托车 = 1;
        request = procurementShopAccessRequest(snapshotId, 45);
        request.recipeId = "craft.weapon.002";
        var wrongRecipe:Object = invokeProcurementShopAccess(request);
        request = procurementShopAccessRequest(snapshotId, 46);
        request.category = "防具合成";
        var wrongCategory:Object = invokeProcurementShopAccess(request);
        request = procurementShopAccessRequest(snapshotId, 47);
        request.recipeIndex = 1;
        var wrongIndex:Object = invokeProcurementShopAccess(request);
        request = procurementShopAccessRequest(snapshotId, 48);
        request.materialName = "测试药剂";
        var wrongMaterial:Object = invokeProcurementShopAccess(request);
        request = procurementKShopAccessRequest(snapshotId, 49);
        var kshopAllowed:Object = invokeProcurementKShopAccess(request);
        _root.kshop_list[0].id = "changed-entry";
        request = procurementKShopAccessRequest(snapshotId, 50);
        var staleKShop:Object = invokeProcurementKShopAccess(request);
        _root.kshop_list[0].id = "mat-1";
        _root.shops["测试商人"]["1"] = "测试药剂";
        var staleEquipment:Object = invokeProcurementShopAccess(equipmentRequest);
        _root.shops["测试商人"]["1"] = "旧测试枪";
        infrastructure.摩托车 = 0;

        check(exactShopAccessFailure(bicycleDenied, 43, "deny", "access_denied")
                && exactProcurementShopAccessAllow(motorcycleAllowed,
                    procurementShopAccessRequest(snapshotId, 43))
                && exactProcurementShopAccessAllow(
                    equipmentAllowed, equipmentRequest)
                && exactProcurementShopAccessAllow(offroadAllowed,
                    procurementShopAccessRequest(snapshotId, 44))
                && exactProcurementKShopAccessAllow(kshopAllowed,
                    procurementKShopAccessRequest(snapshotId, 49)),
            "procurement navigation rejects bicycle-only infrastructure and allows motorcycle/offroad exact routes");
        check(exactShopAccessFailure(wrongRecipe, 45, "stale", "source_not_current")
                && exactShopAccessFailure(wrongCategory, 46, "stale", "source_not_current")
                && exactShopAccessFailure(wrongIndex, 47, "stale", "source_not_current")
                && exactShopAccessFailure(wrongMaterial, 48, "stale", "source_not_current")
                && exactShopAccessFailure(staleKShop, 50, "stale", "catalog_not_current")
                && exactShopAccessFailure(staleEquipment, 51, "stale", "catalog_not_current"),
            "procurement navigation supports equipment prerequisites and fails closed on identity or catalog drift");

        _root.server = previousServer;
    }

    private static function materialTaxonomyModFixtures():Array {
        return [
            {name:"测试插件", modGrade:"high", catalogScope:"firearm",
                uiRole:"mechanism", uiGradeLabel:"高等",
                uiGradeColor:"#0099FF", uiScopeLabel:"枪械",
                uiRoleLabel:"特殊机制", uiSymbol:"star-solid"},
            {name:"测试展示插件-低级防具", modGrade:"low",
                catalogScope:"armor", uiRole:"firepower",
                uiGradeLabel:"低级", uiGradeColor:"#006600", uiScopeLabel:"防具",
                uiRoleLabel:"火力", uiSymbol:"triangle-solid"},
            {name:"测试展示插件-中等刀具", modGrade:"medium",
                catalogScope:"blade", uiRole:"precision",
                uiGradeLabel:"中等", uiGradeColor:"#996600", uiScopeLabel:"刀具",
                uiRoleLabel:"精准与操控", uiSymbol:"triangle-outline"},
            {name:"测试展示插件-特殊拳套", modGrade:"special",
                catalogScope:"fist", uiRole:"sustain",
                uiGradeLabel:"特殊", uiGradeColor:"#FFFF00", uiScopeLabel:"拳套",
                uiRoleLabel:"续航", uiSymbol:"circle-outline"},
            {name:"测试展示插件-低级通用", modGrade:"low",
                catalogScope:"universal", uiRole:"utility",
                uiGradeLabel:"低级", uiGradeColor:"#006600", uiScopeLabel:"通用",
                uiRoleLabel:"结构与功能", uiSymbol:"diamond-outline"},
            {name:"测试展示插件-中等下挂", modGrade:"medium",
                catalogScope:"underbarrel", uiRole:"stability",
                uiGradeLabel:"中等", uiGradeColor:"#996600", uiScopeLabel:"下挂武器",
                uiRoleLabel:"稳定与防护", uiSymbol:"square-outline"}
        ];
    }

    /** A2：producer 与 ADR 共用的 scalar/count boundary±1 表。 */
    private static function testMaterialBoundaryProbe():Void {
        var stringAliases:Array = [
            {alias:"Name", maximum:128},
            {alias:"ShopId", maximum:80},
            {alias:"Id", maximum:256},
            {alias:"Display", maximum:256},
            {alias:"Label", maximum:512},
            {alias:"ShortText", maximum:512},
            {alias:"Description", maximum:12000},
            {alias:"Summary", maximum:20000},
            {alias:"Identity768", maximum:768}
        ];
        var stringsExact:Boolean = true;
        for (var stringIndex:Number = 0;
                stringIndex < stringAliases.length; stringIndex++) {
            var stringBoundary:Object = stringAliases[stringIndex];
            var maximum:Number = Number(stringBoundary.maximum);
            if (!MaterialArchiveProjector.testOnlyValidateBoundary(
                    String(stringBoundary.alias), repeatText("x", maximum))
                    || MaterialArchiveProjector.testOnlyValidateBoundary(
                    String(stringBoundary.alias), repeatText("x", maximum + 1))) {
                stringsExact = false;
            }
        }
        check(stringsExact,
            "v2 producer accepts max and rejects max+1 for every ADR string alias");

        var safeInteger:Number = 9007199254740991;
        var infinity:Number = 1 / 0;
        var negativeInfinity:Number = -1 / 0;
        var notANumber:Number = Number("not-a-number");
        check(MaterialArchiveProjector.testOnlyValidateBoundary("NNI", 0)
                && MaterialArchiveProjector.testOnlyValidateBoundary(
                    "NNI", safeInteger)
                && !MaterialArchiveProjector.testOnlyValidateBoundary(
                    "NNI", safeInteger + 1)
                && !MaterialArchiveProjector.testOnlyValidateBoundary("NNI", infinity)
                && !MaterialArchiveProjector.testOnlyValidateBoundary(
                    "NNI", negativeInfinity)
                && !MaterialArchiveProjector.testOnlyValidateBoundary("NNI", notANumber)
                && !MaterialArchiveProjector.testOnlyValidateBoundary("NNI", 0.5)
                && !MaterialArchiveProjector.testOnlyValidateBoundary("NNI", -1)
                && MaterialArchiveProjector.testOnlyValidateBoundary("PI", 1)
                && MaterialArchiveProjector.testOnlyValidateBoundary(
                    "PI", safeInteger)
                && !MaterialArchiveProjector.testOnlyValidateBoundary("PI", 0)
                && MaterialArchiveProjector.testOnlyValidateBoundary("NN", 0.5)
                && !MaterialArchiveProjector.testOnlyValidateBoundary("NN", infinity)
                && !MaterialArchiveProjector.testOnlyValidateBoundary(
                    "NN", negativeInfinity)
                && !MaterialArchiveProjector.testOnlyValidateBoundary("NN", notANumber)
                && !MaterialArchiveProjector.testOnlyValidateBoundary("NN", -1),
            "v2 numeric aliases reject unsafe, infinite, NaN, fractional and negative values exactly");
        check(MaterialArchiveProjector.testOnlyValidateBoundary("RecipeIndex", 999)
                && !MaterialArchiveProjector.testOnlyValidateBoundary(
                    "RecipeIndex", 1000)
                && !MaterialArchiveProjector.testOnlyValidateBoundary(
                    "RecipeIndex", 0.5)
                && MaterialArchiveProjector.testOnlyValidateBoundary("Bool", true)
                && MaterialArchiveProjector.testOnlyValidateBoundary("Bool", false)
                && !MaterialArchiveProjector.testOnlyValidateBoundary("Bool", "false")
                && MaterialArchiveProjector.testOnlyValidateBoundary(
                    "Color", "#a0B1c2")
                && !MaterialArchiveProjector.testOnlyValidateBoundary(
                    "Color", "#GG0000"),
            "v2 RecipeIndex, Bool and color aliases remain exact and non-coercing");
        var allowedMultiline:String = "首行\t字段\r\n次行";
        var forbiddenControl:String = "正文" + String.fromCharCode(1);
        check(MaterialArchiveProjector.testOnlyValidateBoundary(
                    "Description", allowedMultiline)
                && MaterialArchiveProjector.testOnlyValidateBoundary(
                    "Summary", allowedMultiline)
                && !MaterialArchiveProjector.testOnlyValidateBoundary(
                    "Description", forbiddenControl)
                && !MaterialArchiveProjector.testOnlyValidateBoundary(
                    "Summary", forbiddenControl)
                && !MaterialArchiveProjector.testOnlyValidateBoundary(
                    "ShortText", allowedMultiline),
            "v2 multiline aliases allow only CR/LF/TAB while single-line text rejects them");

        var countAliases:Array = [
            {alias:"MaterialsCount", maximum:4096},
            {alias:"SourcesCount", maximum:512},
            {alias:"VariantsCount", maximum:128},
            {alias:"DirectPurposesCount", maximum:128},
            {alias:"UsesCount", maximum:1024},
            {alias:"TaxonomyEntriesCount", maximum:1024},
            {alias:"InfrastructureProjectsCount", maximum:256},
            {alias:"InfrastructureLevelsCount", maximum:128}
        ];
        var countsExact:Boolean = true;
        for (var countIndex:Number = 0;
                countIndex < countAliases.length; countIndex++) {
            var countBoundary:Object = countAliases[countIndex];
            var cap:Number = Number(countBoundary.maximum);
            if (!MaterialArchiveProjector.testOnlyValidateBoundary(
                    String(countBoundary.alias), cap)
                    || MaterialArchiveProjector.testOnlyValidateBoundary(
                    String(countBoundary.alias), cap + 1)) {
                countsExact = false;
            }
        }
        check(countsExact,
            "v2 producer accepts each collection cap and rejects its cap+1 boundary");
        check(!MaterialArchiveProjector.testOnlyValidateBoundary("unknown", 0)
                && !MaterialArchiveProjector.testOnlyValidateBoundary("NNI", "1")
                && !MaterialArchiveProjector.testOnlyValidateBoundary("Name", 1),
            "test-only boundary probe rejects unknown aliases and wrong scalar types");
    }

    /** 基建用途冻结静态需求，但读取 live 发现态/等级与 snapshot owned。 */
    private static function testInfrastructureUsesProjection(
            catalogMaterials:Array):Void {
        resetOwned();
        var catalog:Object = _root.材料档案目录;
        var system:Object = _root.基建系统;
        var previousDirectPurpose = catalog.DirectPurpose;
        var previousAuthoredPurpose = catalogMaterials[0].authoredDirectPurposeId;
        var previousNameList = system.nameList;
        var previousDict = system.dict;
        var previousInfrastructure = system.infrastructure;

        var projectA:Object = {Name:"测试基建甲", Level:[
            {Material:[{Name:"测试矿石", Value:7}]},
            {Material:[{Name:"测试矿石", Value:9}]},
            {Material:[{Name:"测试矿石", Value:4}]},
            {}
        ]};
        var projectB:Object = {Name:"测试基建乙", Level:[
            {Material:[{Name:"测试矿石", Value:6}]}, {}
        ]};
        var projectC:Object = {Name:"测试基建丙", Level:[
            {Material:[{Name:"测试矿石", Value:20}]},
            {},
            {Material:[{Name:"测试矿石", Value:8}]},
            {}
        ]};
        system.nameList = [projectA, projectB, projectC];
        system.dict = {};
        system.dict["测试基建甲"] = projectA;
        system.dict["测试基建乙"] = projectB;
        system.dict["测试基建丙"] = projectC;
        system.infrastructure = {};
        system.infrastructure["测试基建甲"] = 0;
        system.infrastructure["测试基建丙"] = 2;
        catalog.DirectPurpose = [previousDirectPurpose,
            {id:"system:infrastructure_upgrade", label:"基建升级", order:1,
                consumerEvidence:"MaterialArchiveProjector"}];
        catalogMaterials[0].authoredDirectPurposeId = [
            "system:equipment_tuning", "system:infrastructure_upgrade"];
        var projectedCatalog:Object = CraftingPanelService.execute("materials", {v:2});
        var snapshotId:String = String(projectedCatalog.snapshotId || "");
        // Requirements are frozen here; only discovery/currentLevel stays live.
        projectA.Level[1].Material[0].Value = 99;
        system.infrastructure.测试基建甲 = 1;
        _root.收集品栏.材料.addValue("测试矿石", 10);
        var detail:Object = CraftingPanelService.execute("materialDetail", {
            v:2, snapshotId:snapshotId, itemName:"测试矿石"
        });
        var uses:Array = detail.infrastructureUses;
        check(projectedCatalog.success && detail.success
                && detail.directPurposes.length == 2
                && uses.length == 2
                && uses[0].infrastructureName == "测试基建甲"
                && uses[0].projectOrder == 0
                && uses[0].currentLevel == 1
                && uses[0].maximumLevel == 3
                && uses[0].levels.length == 3
                && uses[0].levels[0].status == "completed"
                && uses[0].levels[0].missing == 0
                && uses[0].levels[1].targetLevel == 2
                && uses[0].levels[1].required == 9
                && uses[0].levels[1].owned == 5
                && uses[0].levels[1].missing == 4
                && uses[0].levels[1].status == "current"
                && uses[0].levels[2].status == "future"
                && uses[1].infrastructureName == "测试基建丙"
                && uses[1].projectOrder == 2
                && uses[1].currentLevel == 2
                && uses[1].levels[1].levelIndex == 2
                && uses[1].levels[1].targetLevel == 3
                && uses[1].levels[1].missing == 3
                && uses[1].levels[1].status == "current",
            "v2 infrastructure cards freeze level requirements and owned while reading live levels");

        delete system.infrastructure.测试基建甲;
        delete system.infrastructure.测试基建丙;
        var undiscovered:Object = CraftingPanelService.execute("materialDetail", {
            v:2, snapshotId:snapshotId, itemName:"测试矿石"
        });
        var inheritedPrototype:Object = {};
        inheritedPrototype["测试基建甲"] = 1;
        var inheritedInfrastructure:Object = {};
        inheritedInfrastructure.__proto__ = inheritedPrototype;
        system.infrastructure = inheritedInfrastructure;
        var inheritedDiscovery:Object = CraftingPanelService.execute("materialDetail", {
            v:2, snapshotId:snapshotId, itemName:"测试矿石"
        });
        system.infrastructure["测试基建甲"] = 4;
        var invalidState:Object = CraftingPanelService.execute("materialDetail", {
            v:2, snapshotId:snapshotId, itemName:"测试矿石"
        });
        check(undiscovered.success && undiscovered.infrastructureUses.length == 0
                && inheritedDiscovery.success
                && inheritedDiscovery.infrastructureUses.length == 0
                && exactFailure(invalidState, "invalid_infrastructure_state"),
            "v2 infrastructure cards require own discovery keys and reject invalid live levels");

        var authoritativeDict:Object = system.dict;
        var inheritedDict:Object = {};
        inheritedDict.__proto__ = authoritativeDict;
        system.dict = inheritedDict;
        var inheritedDictFailure:Object = CraftingPanelService.execute("materials", {v:2});
        system.dict = authoritativeDict;
        catalogMaterials[0].authoredDirectPurposeId = "system:equipment_tuning";
        var closureFailure:Object = CraftingPanelService.execute("materials", {v:2});
        check(exactFailure(inheritedDictFailure, "invalid_infrastructure_catalog")
                && exactFailure(closureFailure,
                    "invalid_infrastructure_catalog_closure"),
            "v2 infrastructure authority requires own dictionary keys and exact material purposes");

        catalog.DirectPurpose = previousDirectPurpose;
        catalogMaterials[0].authoredDirectPurposeId = previousAuthoredPurpose;
        if (previousNameList == undefined) delete system.nameList;
        else system.nameList = previousNameList;
        if (previousDict == undefined) delete system.dict;
        else system.dict = previousDict;
        system.infrastructure = previousInfrastructure;
        resetOwned();
    }

    /** 每个 collection cap 至少一条真实 producer max+1 路径。 */
    private static function testMaterialCollectionCapProductionPaths(
            catalogMaterials:Array, index:ItemObtainIndex):Void {
        var catalog:Object = _root.材料档案目录;

        var overMaterials:Array = [];
        for (var materialIndex:Number = 0; materialIndex < 4097; materialIndex++) {
            overMaterials.push(catalogMaterials[0]);
        }
        catalog.Material = overMaterials;
        var materialsCap:Object = CraftingPanelService.execute("materials", {v:2});
        catalog.Material = catalogMaterials;
        check(exactFailure(materialsCap, "invalid_catalog"),
            "v2 producer rejects the real materials[4097] path");

        var originalPurposeIds = catalogMaterials[0].authoredDirectPurposeId;
        var overDirectPurposes:Array = [];
        for (var directIndex:Number = 0; directIndex < 129; directIndex++) {
            overDirectPurposes.push("system:equipment_tuning");
        }
        catalogMaterials[0].authoredDirectPurposeId = overDirectPurposes;
        var directCap:Object = CraftingPanelService.execute("materials", {v:2});
        catalogMaterials[0].authoredDirectPurposeId = originalPurposeIds;
        check(exactFailure(directCap, "too_many_direct_purposes"),
            "v2 producer rejects the real directPurposes[129] path");

        var originalRecipes:Array = _root.改装清单["武器合成"];
        var overUses:Array = [];
        for (var useIndex:Number = 0; useIndex < 1025; useIndex++) {
            overUses.push({name:"测试药剂", materials:["测试矿石#1"]});
        }
        _root.改装清单["武器合成"] = overUses;
        SynthesisIndex.reset();
        var usesCap:Object = CraftingPanelService.execute("materials", {v:2});
        _root.改装清单["武器合成"] = originalRecipes;
        SynthesisIndex.reset();
        check(exactFailure(usesCap, "too_many_uses"),
            "v2 producer rejects the real indexed uses[1025] path");

        index.reset(true);
        index.buildIndex(_root.改装清单, {}, []);
        for (var sourceIndex:Number = 0; sourceIndex < 513; sourceIndex++) {
            index.updateQuestRewards("cap.quest." + sourceIndex,
                "上限任务" + sourceIndex, ["测试矿石#1"]);
        }
        var sourcesCap:Object = CraftingPanelService.execute("materials", {v:2});
        restoreV2FixtureObtainIndex(index);
        check(exactFailure(sourcesCap, "too_many_sources"),
            "v2 producer rejects the real indexed sources[513] path");

        index.reset(true);
        index.buildIndex(_root.改装清单, {}, []);
        var overVariants:Array = [];
        for (var variantIndex:Number = 0; variantIndex < 129; variantIndex++) {
            overVariants.push(["测试矿石", 8, 1]);
        }
        index.updateStageDrops("测试档位上限", overVariants);
        var variantsCap:Object = CraftingPanelService.execute("materials", {v:2});
        restoreV2FixtureObtainIndex(index);
        check(exactFailure(variantsCap, "invalid_stage_source"),
            "v2 producer rejects the real grouped variants[129] path");

        var originalOrder:Array = _root.改装分类顺序;
        var originalCrafting:Object = _root.改装清单;
        var overTaxonomyOrder:Array = [];
        var overTaxonomyCrafting:Object = {};
        for (var categoryIndex:Number = 0; categoryIndex < 999; categoryIndex++) {
            var categoryName:String = "测试上限分类" + categoryIndex;
            overTaxonomyOrder.push(categoryName);
            overTaxonomyCrafting[categoryName] = [];
        }
        _root.改装分类顺序 = overTaxonomyOrder;
        _root.改装清单 = overTaxonomyCrafting;
        var taxonomyCap:Object = CraftingPanelService.execute("materials", {v:2});
        _root.改装分类顺序 = originalOrder;
        _root.改装清单 = originalCrafting;
        SynthesisIndex.reset();
        check(exactFailure(taxonomyCap, "too_many_taxonomy_entries"),
            "v2 producer rejects the real taxonomy total 1025 path");
    }

    private static function restoreV2FixtureObtainIndex(index:ItemObtainIndex):Void {
        var shops:Object = {};
        shops["测试商人"] = {};
        shops["测试商人"]["0"] = "测试矿石";
        index.reset(true);
        index.buildIndex(_root.改装清单, shops, []);
        index.updateEnemyDrops("敌人-测试两档", [
            {名字:"测试矿石", 概率:3, 最大逆向等级:2, 最小数量:1, 最大数量:1},
            {名字:"测试矿石", 概率:5, 最小逆向等级:3, 最小数量:2, 最大数量:4}
        ]);
        index.updateEnemyDrops("敌人-键:|𠀀", [
            {名字:"测试矿石", 概率:7}
        ]);
        index.updateStageDrops("测试关卡多档", [
            ["测试矿石", 8, 1], ["测试矿石", 50, 2]
        ]);
    }

    /** A1a：掉落 cache 保留 occurrence，exact grouped projection 一来源一卡多档。 */
    private static function testDropOccurrenceProjection():Void {
        resetOwned();
        var previousEnemyTable:Object = _root.敌人属性表;
        var enemyFour:Array = [
            {名字:"测试矿石", 概率:0},
            {名字:"测试矿石", 概率:1, 最小逆向等级:0, 最大逆向等级:0,
                最小数量:2, 最大数量:4},
            {名字:"测试矿石", 概率:100, 最小逆向等级:3, 最大逆向等级:7},
            {名字:"测试矿石"}
        ];
        var enemyThree:Array = [
            {名字:"测试矿石", 概率:""},
            {名字:"测试矿石", 概率:"   "},
            {名字:"测试矿石", 概率:"not-a-number"}
        ];
        var enemyTwo:Array = [
            {名字:"测试矿石", 概率:3, 最小逆向等级:1, 最大逆向等级:3,
                最小数量:1, 最大数量:2},
            {名字:"测试矿石", 概率:5, 最小逆向等级:4, 最大逆向等级:9,
                最小数量:3, 最大数量:6}
        ];
        var invalidEnemy:Array = [
            {名字:"测试矿石", 概率:101},
            {名字:"测试矿石", 概率:1 / 0},
            {名字:"测试矿石", 概率:5, 最小数量:0, 最大数量:1},
            {名字:"测试矿石", 概率:5, 最小逆向等级:8, 最大逆向等级:2}
        ];
        var mixedInvalidEnemy:Array = [
            {名字:"测试矿石", 概率:3},
            {名字:"测试矿石", 概率:-1}
        ];
        var infiniteEnemy:Array = [
            {名字:"测试矿石", 概率:3},
            {名字:"测试矿石", 概率:1 / 0}
        ];
        var negativeInfiniteEnemy:Array = [
            {名字:"测试矿石", 概率:3},
            {名字:"测试矿石", 概率:-1 / 0}
        ];
        _root.敌人属性表 = {};
        _root.敌人属性表["敌人-测试四档"] = {displayname:"测试四档", 掉落物:enemyFour};
        _root.敌人属性表["敌人-测试三档"] = {displayname:"测试三档", 掉落物:enemyThree};
        _root.敌人属性表["敌人-测试两档"] = {displayname:"测试两档", 掉落物:enemyTwo};
        _root.敌人属性表["敌人-测试非法"] = {displayname:"测试非法", 掉落物:invalidEnemy};
        _root.敌人属性表["敌人-测试混合非法"] = {
            displayname:"测试混合非法", 掉落物:mixedInvalidEnemy};
        _root.敌人属性表["敌人-测试正无穷"] = {
            displayname:"测试正无穷", 掉落物:infiniteEnemy};
        _root.敌人属性表["敌人-测试负无穷"] = {
            displayname:"测试负无穷", 掉落物:negativeInfiniteEnemy};

        var index:ItemObtainIndex = ItemObtainIndex.getInstance();
        check(!index.updateEnemyDrops("测试四档", enemyFour)
                && !index.isEnemyDiscovered("测试四档"),
            "enemy discovery rejects stripped-prefix/display alias and requires exact table identity");
        index.updateEnemyDrops("敌人-测试四档", enemyFour);
        index.updateEnemyDrops("敌人-测试三档", enemyThree);
        index.updateEnemyDrops("敌人-测试两档", enemyTwo);
        index.updateEnemyDrops("敌人-测试非法", invalidEnemy);
        index.updateEnemyDrops("敌人-测试混合非法", mixedInvalidEnemy);
        index.updateEnemyDrops("敌人-测试正无穷", infiniteEnemy);
        index.updateEnemyDrops("敌人-测试负无穷", negativeInfiniteEnemy);

        var exact:Array = index.getExactObtainRecords("测试矿石");
        var four:Object = findExactDrop(exact, ItemObtainIndex.DROP_TYPE_ENEMY,
            "敌人-测试四档");
        var three:Object = findExactDrop(exact, ItemObtainIndex.DROP_TYPE_ENEMY,
            "敌人-测试三档");
        var two:Object = findExactDrop(exact, ItemObtainIndex.DROP_TYPE_ENEMY,
            "敌人-测试两档");
        check(four != null && four.enemyType == "敌人-测试四档"
                && four.chanceModel == "enemy_prd_with_reverse_bonus"
                && four.variants.length == 4,
            "enemy exact identity groups four XML occurrences into one source");
        check(four != null && four.variants[0].occurrenceIndex == 0
                && four.variants[0].chanceInputState == "explicit"
                && four.variants[0].chanceRaw == 0
                && four.variants[1].chanceRaw == 1
                && four.variants[2].chanceRaw == 100,
            "enemy explicit 0/1/100 remain nominal percent in XML order");
        check(four != null && four.variants[0].minReverseLevel == null
                && four.variants[0].maxReverseLevel == null
                && four.variants[0].quantityMin == 1
                && four.variants[0].quantityMax == 1
                && four.variants[1].minReverseLevel == 0
                && four.variants[1].maxReverseLevel == 0
                && four.variants[1].quantityMin == 2
                && four.variants[1].quantityMax == 4,
            "enemy nullable reverse bounds and default/explicit quantities stay distinct");
        check(four != null && four.variants[3].occurrenceIndex == 3
                && four.variants[3].chanceInputState == "absent_defaulted"
                && four.variants[3].chanceRaw == null
                && four.variants[3].nominalChancePercent == 100,
            "missing enemy chance projects absent_defaulted nominal 100");
        check(three != null && three.variants.length == 3
                && three.variants[0].chanceInputState == "invalid_defaulted"
                && three.variants[1].chanceInputState == "invalid_defaulted"
                && three.variants[2].chanceInputState == "invalid_defaulted"
                && three.variants[0].chanceRaw == null
                && three.variants[1].nominalChancePercent == 100,
            "empty, whitespace and invalid enemy chance use AVM1 NaN default semantics");
        check(two != null && two.variants.length == 2
                && two.variants[0].minReverseLevel == 1
                && two.variants[1].minReverseLevel == 4
                && two.variants[1].quantityMin == 3
                && two.variants[1].quantityMax == 6,
            "two enemy grade occurrences preserve reverse and quantity ranges");
        check(findExactDrop(exact, ItemObtainIndex.DROP_TYPE_ENEMY,
                "敌人-测试非法") == null,
            "out-of-range chance, invalid quantity and inverted reverse bounds fail closed");
        check(findExactDrop(exact, ItemObtainIndex.DROP_TYPE_ENEMY,
                    "敌人-测试混合非法") == null
                && findExactDrop(exact, ItemObtainIndex.DROP_TYPE_ENEMY,
                    "敌人-测试正无穷") == null
                && findExactDrop(exact, ItemObtainIndex.DROP_TYPE_ENEMY,
                    "敌人-测试负无穷") == null,
            "mixed valid/invalid and signed infinite enemy chances fail the whole logical source closed");

        var stageRewards:Array = [
            ["测试矿石", 1, 1],
            ["测试矿石", 2, 2],
            ["测试矿石", 8, 3],
            ["测试矿石", 50, 4],
            ["测试矿石", 50, 4]
        ];
        index.updateStageDrops("测试关卡多档", stageRewards);
        var stage:Object = findExactDrop(index.getExactObtainRecords("测试矿石"),
            ItemObtainIndex.DROP_TYPE_STAGE, "测试关卡多档");
        check(stage != null && stage.chanceModel == "stage_roll_divisor_with_legacy_domain_branch"
                && stage.legacyConditionId == "andylaw_domain_bonus"
                && stage.variants.length == 5
                && stage.variants[0].defaultBranchChancePercent == 100
                && stage.variants[1].defaultBranchChancePercent == 50
                && stage.variants[2].defaultBranchChancePercent == 12.5
                && stage.variants[3].defaultBranchChancePercent == 2,
            "stage divisors 1/2/8/50 project ordered default-branch percentages with contextual model");
        var legacyDomainReachable:Boolean = typeof _root.是否是某网站 == "function"
            && _root.是否是某网站(["andylaw.net", "www.andylaw.net",
                "game.andylaw.net", "crazyparkour.andylaw.net"]) == true;
        trace("[A1_STAGE_CHANCE] entry=TestLoader url=" + String(_root._url)
            + " andylawDomainReachable=" + legacyDomainReachable
            + " model=stage_roll_divisor_with_legacy_domain_branch");
        check(!legacyDomainReachable,
            "fresh standalone TestLoader does not enter AndyLaw branch; producer still retains contextual model");
        check(stage != null && stage.variants[3].rollDivisor == stage.variants[4].rollDivisor
                && stage.variants[3].quantityMax == stage.variants[4].quantityMax
                && stage.variants[3].occurrenceIndex == 3
                && stage.variants[4].occurrenceIndex == 4,
            "identical stage reward occurrences remain two distinct ordered variants");
        index.updateStageDrops("测试关卡多档", stageRewards);
        stage = findExactDrop(index.getExactObtainRecords("测试矿石"),
            ItemObtainIndex.DROP_TYPE_STAGE, "测试关卡多档");
        check(stage != null && stage.variants.length == 5
                && stage.variants[4].occurrenceIndex == 4,
            "rebuilding the same stage replaces rather than multiplies variants");
        index.updateStageDrops("测试关卡非法", [
            ["测试矿石", 0, 1], ["测试矿石", 2, 0]
        ]);
        index.updateStageDrops("测试关卡混合非法", [
            ["测试矿石", 2, 1], ["测试矿石", 0, 1]
        ]);
        check(findExactDrop(index.getExactObtainRecords("测试矿石"),
                ItemObtainIndex.DROP_TYPE_STAGE, "测试关卡非法") == null,
            "invalid stage divisor or quantity fails closed without a partial source");
        check(findExactDrop(index.getExactObtainRecords("测试矿石"),
                ItemObtainIndex.DROP_TYPE_STAGE, "测试关卡混合非法") == null,
            "one invalid stage occurrence rejects its whole logical source");

        var legacyDetail:Object = CraftingPanelService.execute(
            "materialDetail", {itemName:"测试矿石"});
        var legacyEnemy:Object = findProjectedSource(
            legacyDetail.sources, "enemy", "enemyType", "敌人-测试四档");
        check(legacyEnemy != null && legacyEnemy.probability == 0
                && legacyEnemy.minLevel == 0 && legacyEnemy.maxLevel == 999
                && legacyEnemy.variants == undefined
                && legacyEnemy.chanceModel == undefined,
            "v1 material detail keeps first-scalar compatibility and exposes no half-v2 keys");

        var save:Object = index.exportToSave();
        index.loadFromSave(save);
        var rebuiltFour:Object = findExactDrop(index.getExactObtainRecords("测试矿石"),
            ItemObtainIndex.DROP_TYPE_ENEMY, "敌人-测试四档");
        check(rebuiltFour != null && rebuiltFour.variants.length == 4
                && rebuiltFour.variants[3].chanceInputState == "absent_defaulted",
            "save reload reconstructs exact enemy variants from current config");
        check(index.isStageDiscovered("测试关卡多档")
                && findExactDrop(index.getExactObtainRecords("测试矿石"),
                    ItemObtainIndex.DROP_TYPE_STAGE, "测试关卡多档") == null,
            "save reload preserves stage discovery but characterizes current delayed stage rebuild gap");
        index.loadFromSave(save);
        rebuiltFour = findExactDrop(index.getExactObtainRecords("测试矿石"),
            ItemObtainIndex.DROP_TYPE_ENEMY, "敌人-测试四档");
        check(rebuiltFour != null && rebuiltFour.variants.length == 4
                && rebuiltFour.variants[0].occurrenceIndex == 0
                && rebuiltFour.variants[3].occurrenceIndex == 3,
            "repeated save reload keeps enemy occurrence identity and order without growth");
        var delayedEnemyTable:Object = _root.敌人属性表;
        _root.敌人属性表 = null;
        index.loadFromSave(save);
        rebuiltFour = findExactDrop(index.getExactObtainRecords("测试矿石"),
            ItemObtainIndex.DROP_TYPE_ENEMY, "敌人-测试四档");
        check(rebuiltFour == null && index.isEnemyDiscovered("敌人-测试四档"),
            "save discovery remains hidden while the enemy provider is not ready");
        _root.敌人属性表 = delayedEnemyTable;
        index.rehydrateDiscoveredRecordsFromCurrentConfig();
        rebuiltFour = findExactDrop(index.getExactObtainRecords("测试矿石"),
            ItemObtainIndex.DROP_TYPE_ENEMY, "敌人-测试四档");
        check(rebuiltFour != null && rebuiltFour.variants.length == 4
                && rebuiltFour.variants[3].occurrenceIndex == 3,
            "late enemy provider rehydrates saved grouped occurrences without widening discovery");
        index.rehydrateDiscoveredRecordsFromCurrentConfig();
        rebuiltFour = findExactDrop(index.getExactObtainRecords("测试矿石"),
            ItemObtainIndex.DROP_TYPE_ENEMY, "敌人-测试四档");
        check(rebuiltFour != null && rebuiltFour.variants.length == 4,
            "late-provider rehydrate is idempotent and does not multiply enemy variants");
        index.updateStageDrops("测试关卡多档", stageRewards);
        var restoredStage:Object = findExactDrop(index.getExactObtainRecords("测试矿石"),
            ItemObtainIndex.DROP_TYPE_STAGE, "测试关卡多档");
        check(restoredStage != null && restoredStage.variants.length == 5,
            "re-entering a discovered stage restores its exact grouped source");
        var obtainTooltip:String = ObtainMethodsBuilder.build("测试矿石").join("");
        check(obtainTooltip.indexOf("测试关卡多档") >= 0
                && obtainTooltip.indexOf("测试四档") >= 0,
            "legacy ObtainMethodsBuilder consumes grouped first-scalar sources without shape regression");

        _root.敌人属性表 = previousEnemyTable;
        resetOwned();
    }

    /** A1b/c：内部保留 occurrence，现役 v1 getter/projector 仍给 legacy view。 */
    private static function testStaticSourceOccurrenceIdentity():Void {
        resetOwned();
        var index:ItemObtainIndex = ItemObtainIndex.getInstance();
        index.reset(true);
        var crafting:Object = {};
        crafting["重复合成"] = [
            {name:"测试矿石", price:1, kprice:2, materials:[]},
            {name:"测试矿石", price:3, kprice:4, materials:[]}
        ];
        var shopItems:Object = {};
        shopItems[0] = {name:"测试矿石", requiredInfo:"情报甲"};
        shopItems[1] = {name:"测试矿石", requiredInfo:"情报乙"};
        var shops:Object = {};
        shops["测试重复商人"] = shopItems;
        var kshop:Array = [
            {id:"k-a", item:"测试矿石", type:"材料", price:5},
            {id:"k-b", item:"测试矿石", type:"材料", price:6}
        ];
        index.buildIndex(crafting, shops, kshop);

        var exact:Array = index.getExactObtainRecords("测试矿石");
        var crafts:Array = filterExactKind(exact, ItemObtainIndex.KIND_CRAFT);
        var shopSources:Array = filterExactKind(exact, ItemObtainIndex.KIND_SHOP);
        var kshopSources:Array = filterExactKind(exact, ItemObtainIndex.KIND_KSHOP);
        check(crafts.length == 2 && crafts[0].recipeIndex == 0
                && crafts[1].recipeIndex == 1
                && crafts[0].productName == "测试矿石",
            "same-category same-product craft occurrences keep exact recipeIndex identities");
        check(shopSources.length == 2 && shopSources[0].shopId == "测试重复商人"
                && shopSources[0].catalogIndex == 0
                && shopSources[1].catalogIndex == 1
                && shopSources[0].requiredInfo == "情报甲"
                && shopSources[1].requiredInfo == "情报乙",
            "same-NPC duplicate items keep catalogIndex and current requiredInfo fields");
        check(kshopSources.length == 2 && kshopSources[0].catalogIndex == 0
                && kshopSources[1].catalogIndex == 1
                && kshopSources[1].entryId == "k-b",
            "KShop occurrences expose stable catalogIndex while retaining entry id");
        check(index.getObtainRecords("测试矿石").length == 4,
            "legacy getter collapses craft/shop identities but preserves historical KShop occurrences");

        index.updateQuestRewards("任务-重复奖励", "重复奖励任务",
            ["测试矿石#1", "测试矿石#2"]);
        var firstAppend:Boolean = index.appendQuestRewards("任务-重复奖励", "重复奖励任务",
            ["测试矿石#3", "测试矿石#4"]);
        var secondAppend:Boolean = index.appendQuestRewards("任务-重复奖励", "重复奖励任务",
            ["测试矿石#3", "测试矿石#4"]);
        var quests:Array = filterExactKind(index.getExactObtainRecords("测试矿石"),
            ItemObtainIndex.KIND_QUEST);
        check(firstAppend && !secondAppend && quests.length == 4,
            "quest base/challenge duplicate items preserve four occurrences and append idempotently");
        check(quests[0].rewardSet == "base" && quests[0].authoredIndex == 0
                && quests[1].rewardSet == "base" && quests[1].authoredIndex == 1
                && quests[2].rewardSet == "challenge" && quests[2].authoredIndex == 0
                && quests[3].rewardSet == "challenge" && quests[3].authoredIndex == 1,
            "quest identity keeps base before challenge with independent authored indexes");
        index.updateQuestRewards("任务-重复奖励", "重复奖励任务",
            ["测试矿石#1", "测试矿石#2"]);
        quests = filterExactKind(index.getExactObtainRecords("测试矿石"),
            ItemObtainIndex.KIND_QUEST);
        check(quests.length == 4 && quests[2].rewardSet == "challenge"
                && quests[3].authoredIndex == 1,
            "refreshing base rewards preserves the completed challenge occurrence set");
        check(index.getObtainRecords("测试矿石").length == 5,
            "legacy getter keeps one quest source and does not leak exact occurrences into v1");
        var detail:Object = CraftingPanelService.execute(
            "materialDetail", {itemName:"测试矿石"});
        var projectedShop:Object = findProjectedSource(
            detail.sources, "shop", "npc", "测试重复商人");
        check(detail.sources.length == 5 && projectedShop != null
                && projectedShop.requirement == "情报甲"
                && projectedShop.catalogIndex == undefined
                && projectedShop.shopId == undefined,
            "v1 service retains legacy source count/shape while exact index carries new identities");
        index.appendQuestRewards("任务-先挑战", "先挑战任务", ["测试矿石#7"]);
        index.updateQuestRewards("任务-先挑战", "先挑战任务", ["测试矿石#8"]);
        var challengeFirst:Array = filterExactKind(
            index.getExactObtainRecords("测试矿石"), ItemObtainIndex.KIND_QUEST);
        check(challengeFirst.length == 6
                && challengeFirst[4].questId == "任务-先挑战"
                && challengeFirst[4].rewardSet == "base"
                && challengeFirst[5].rewardSet == "challenge",
            "challenge-first discovery is reprojected base-before-challenge after base arrives");

        var previousTasks:Object = TaskUtil.tasks;
        var previousTaskTexts:Object = TaskUtil.task_texts;
        TaskUtil.tasks = [];
        TaskUtil.task_texts = {};
        TaskUtil.tasks[7] = {
            title:"存档重建任务",
            rewards:["测试矿石#1", "测试矿石#2"],
            challenge:{rewards:["测试矿石#3", "测试矿石#4"]}
        };
        index.updateQuestRewards("7", "存档重建任务", TaskUtil.tasks[7].rewards);
        index.appendQuestRewards("7", "存档重建任务",
            TaskUtil.tasks[7].challenge.rewards);
        var questSave:Object = index.exportToSave();
        index.loadFromSave(questSave);
        var rebuiltQuests:Array = filterExactKind(
            index.getExactObtainRecords("测试矿石"), ItemObtainIndex.KIND_QUEST);
        check(rebuiltQuests.length == 4
                && rebuiltQuests[0].questId == "7"
                && rebuiltQuests[0].rewardSet == "base"
                && rebuiltQuests[0].authoredIndex == 0
                && rebuiltQuests[1].rewardSet == "base"
                && rebuiltQuests[1].authoredIndex == 1
                && rebuiltQuests[2].rewardSet == "challenge"
                && rebuiltQuests[2].authoredIndex == 0
                && rebuiltQuests[3].rewardSet == "challenge"
                && rebuiltQuests[3].authoredIndex == 1
                && index.getObtainRecords("测试矿石").length == 5,
            "save reload rebuilds exact base-before-challenge quest tuples while v1 keeps one quest source");
        index.loadFromSave(questSave);
        rebuiltQuests = filterExactKind(
            index.getExactObtainRecords("测试矿石"), ItemObtainIndex.KIND_QUEST);
        check(rebuiltQuests.length == 4
                && rebuiltQuests[0].rewardSet == "base"
                && rebuiltQuests[1].authoredIndex == 1
                && rebuiltQuests[2].rewardSet == "challenge"
                && rebuiltQuests[3].authoredIndex == 1,
            "repeated quest save reload is idempotent and preserves occurrence order");

        var delayedTask:Object = TaskUtil.tasks[7];
        TaskUtil.tasks = [];
        index.loadFromSave(questSave);
        rebuiltQuests = filterExactKind(
            index.getExactObtainRecords("测试矿石"), ItemObtainIndex.KIND_QUEST);
        check(rebuiltQuests.length == 0,
            "save discovery remains fail-closed while task providers are not ready");
        TaskUtil.tasks = [];
        TaskUtil.tasks[7] = delayedTask;
        index.rehydrateDiscoveredRecordsFromCurrentConfig();
        rebuiltQuests = filterExactKind(
            index.getExactObtainRecords("测试矿石"), ItemObtainIndex.KIND_QUEST);
        check(rebuiltQuests.length == 4
                && rebuiltQuests[0].rewardSet == "base"
                && rebuiltQuests[1].authoredIndex == 1
                && rebuiltQuests[2].rewardSet == "challenge"
                && rebuiltQuests[3].authoredIndex == 1,
            "late task provider rehydrates saved base and challenge occurrences in authored order");
        index.rehydrateDiscoveredRecordsFromCurrentConfig();
        rebuiltQuests = filterExactKind(
            index.getExactObtainRecords("测试矿石"), ItemObtainIndex.KIND_QUEST);
        check(rebuiltQuests.length == 4,
            "late-provider rehydrate is idempotent and does not multiply quest occurrences");
        TaskUtil.tasks = previousTasks;
        TaskUtil.task_texts = previousTaskTexts;
        resetOwned();
    }

    /** A1b：用途反查来自 category arrays，不再被同名产物 map 后写覆盖。 */
    private static function testExactRecipeUseOccurrences():Void {
        var previousList:Object = _root.改装清单;
        var previousMap:Object = _root.改装清单对象;
        _root.改装清单 = {};
        _root.改装清单["基础防具"] = [
            {name:"Andy套装碎片", materials:["国庆纪念币#1", "国庆纪念币#2"]},
            {name:"Andy套装碎片", materials:["国庆纪念币#3", "月之碎片#1"]},
            {name:"Andy套装碎片", materials:["剑圣碎片#1"]}
        ];
        _root.改装清单对象 = {};
        _root.改装清单对象["Andy套装碎片"] = _root.改装清单["基础防具"][2];
        SynthesisIndex.reset();
        var national:Array = SynthesisIndex.getRecipeUses("国庆纪念币");
        var moon:Array = SynthesisIndex.getRecipeUses("月之碎片");
        var sword:Array = SynthesisIndex.getRecipeUses("剑圣碎片");
        check(national.length == 2 && national[0].category == "基础防具"
                && national[0].recipeIndex == 0
                && national[0].productName == "Andy套装碎片"
                && national[1].recipeIndex == 1,
            "exact reverse-use de-dupes within one recipe but never by productName across recipes");
        check(moon.length == 1 && moon[0].recipeIndex == 1
                && sword.length == 1 && sword[0].recipeIndex == 2,
            "all three same-product Andy recipe occurrences remain addressable by exact indexes");
        check(SynthesisIndex.getRecipesUsing("国庆纪念币").length == 0,
            "legacy product map remains isolated and cannot masquerade as exact reverse-use");
        _root.改装清单 = previousList;
        _root.改装清单对象 = previousMap;
        SynthesisIndex.reset();
    }

    private static function testLegacyIdentityWhitespaceFallback():Void {
        resetOwned();
        var material:Object = ItemUtil.itemDataDict["测试矿石"];
        var product:Object = ItemUtil.itemDataDict["光棱射线弹-强化"];
        var oldMaterialDisplay = material.displayname;
        var oldMaterialIcon = material.icon;
        var oldProductDisplay = product.displayname;
        var oldProductIcon = product.icon;
        material.displayname = "   ";
        material.icon = "\t";
        product.displayname = "   ";
        product.icon = " Undefined ";
        var materials:Object = CraftingPanelService.execute("materials", {});
        var snapshot:Object = CraftingPanelService.execute("snapshot", {category:"武器合成"});
        material.displayname = 17;
        material.icon = {legacy:"bad"};
        product.displayname = {legacy:"bad"};
        product.icon = 23;
        var wrongTypeMaterials:Object = CraftingPanelService.execute("materials", {});
        var wrongTypeSnapshot:Object = CraftingPanelService.execute(
            "snapshot", {category:"武器合成"});
        check(materials.success && materials.materials[0].displayName == "测试矿石"
            && materials.materials[0].icon == "测试矿石"
            && snapshot.success && snapshot.recipes[0].output.displayName == "光棱射线弹-强化"
            && snapshot.recipes[0].output.icon == "光棱射线弹-强化"
            && wrongTypeMaterials.materials[0].displayName == "测试矿石"
            && wrongTypeMaterials.materials[0].icon == "测试矿石"
            && wrongTypeSnapshot.recipes[0].output.displayName == "光棱射线弹-强化"
            && wrongTypeSnapshot.recipes[0].output.icon == "光棱射线弹-强化",
            "AS2 adapter replaces whitespace, wrapped undefined and wrong-type identity fields before Host/Web");
        material.displayname = oldMaterialDisplay;
        material.icon = oldMaterialIcon;
        product.displayname = oldProductDisplay;
        product.icon = oldProductIcon;
    }

    private static function testInformationOverflowPolicy():Void {
        resetOwned();
        _root.收集品栏.情报.addValue("测试图纸", 97);
        var direct:Object = ItemUtil.planInformationAcquire("测试图纸", 5);
        check(direct.valid && direct.remaining == 1 && direct.accepted == 1
            && direct.overflow == 4 && direct.money == 4000,
            "information plan uses per-item maxvalue and converts 98 plus 5 overflow");

        var planned:Object = ItemUtil.planRewardAcquire([
            {name:"测试图纸", value:5},
            {name:"金币", value:100}
        ]);
        check(planned.items.length == 2
            && planned.items[0].name == "测试图纸" && planned.items[0].value == 1
            && planned.items[1].name == "金币" && planned.items[1].value == 4100
            && _root.收集品栏.情报.getValue("测试图纸") == 98,
            "reward planning reserves capacity and remains read-only");

        var settled:Object = ItemUtil.acquireReward([
            {name:"测试图纸", value:5},
            {name:"金币", value:100}
        ]);
        check(settled.success && settled.hasOverflow
            && _root.收集品栏.情报.getValue("测试图纸") == 99
            && _root.金钱 == 5100,
            "reward settlement atomically writes accepted information and overflow money");
    }

    private static function testSnapshotProjection():Void {
        resetOwned();
        var result:Object = CraftingPanelService.execute("snapshot", {category:"武器合成"});
        check(result.success && result.v == 1 && result.gender == "男" && result.recipes.length == 2,
            "snapshot projects category catalog");
        check(result.recipes[0].output.name == "光棱射线弹-强化"
            && result.recipes[0].output.displayName == "棱镜折射阵列"
            && result.recipes[0].output.icon == "全光谱棱镜阵列"
            && result.recipes[0].materialCount == 3
            && result.recipes[0].canCraftOne && result.recipes[0].availability == "ready"
            && !result.recipes[1].canCraftOne && result.recipes[1].availability == "material_missing",
            "snapshot exposes static output and authoritative one-craft availability");
        check(!result.recipes[0].batchEligible && result.recipes[1].batchEligible
            && result.recipes[0].output.weaponType == "手枪"
            && result.recipes[0].output.actionType == "双刀"
            && result.recipes[0].output.setId == "test_sidearm"
            && result.recipes[0].output.setName == "测试侧武器套装",
            "snapshot exposes action type, batch eligibility and shared category/set taxonomy");
        check(result.balance.money == 1000 && result.skills.smithLevel == 2,
            "snapshot exposes authoritative balances and skills");
    }

    private static function testSnapshotGenderNormalization():Void {
        resetOwned();
        _root.性别 = "女";
        var female:Object = CraftingPanelService.execute("snapshot", {category:"武器合成"});
        _root.性别 = "未知";
        var fallback:Object = CraftingPanelService.execute("snapshot", {category:"武器合成"});
        check(female.gender == "女", "snapshot projects restored female save gender");
        check(fallback.gender == "男", "snapshot normalizes invalid save gender to male");
    }

    private static function testSnapshotAvailabilityRefresh():Void {
        resetOwned();
        var first:Object = CraftingPanelService.execute("snapshot", {category:"武器合成"});
        var firstStats:Object = CraftingPanelService.testOnlyStats();
        check(firstStats.availabilityPlans == first.recipes.length
                && firstStats.maximumProbes == 0
                && firstStats.purchaseSourceIndexes == 1
                && firstStats.ownedIndexes == 1,
            "snapshot evaluates one bounded availability plan per recipe with one shared source and owned index");
        check(first.recipes[0].availability == "ready" && first.recipes[1].availability == "material_missing",
            "snapshot distinguishes ready and blocked recipes");

        _root.收集品栏.材料.addValue("测试矿石", 4);
        var materialRefresh:Object = CraftingPanelService.execute("snapshot", {category:"武器合成"});
        _root.金钱 = 0;
        var balanceRefresh:Object = CraftingPanelService.execute("snapshot", {category:"武器合成"});
        var refreshedStats:Object = CraftingPanelService.testOnlyStats();
        check(materialRefresh.recipes[1].canCraftOne && materialRefresh.recipes[1].availability == "ready"
            && !balanceRefresh.recipes[0].canCraftOne
            && balanceRefresh.recipes[0].availability == "insufficient_money"
            && balanceRefresh.recipes[1].canCraftOne
            && refreshedStats.availabilityPlans == first.recipes.length * 3
            && refreshedStats.maximumProbes == 0
            && refreshedStats.purchaseSourceIndexes == 3
            && refreshedStats.ownedIndexes == 3,
            "snapshot availability refreshes after mutations with exactly one source and owned scan per snapshot");
    }

    private static function testProcurementOwnedScope():Void {
        resetOwned();
        _root.物品栏.背包.add(1, BaseItem.create("光棱射线弹-强化", 4));
        _root.物品栏.装备栏.setItems({
            手枪:BaseItem.create("光棱射线弹-强化", 6)
        });
        _root.物品栏.战备箱.add(0, BaseItem.create("光棱射线弹-强化", 8));
        _root.物品栏.战备箱.add(40, BaseItem.create("光棱射线弹-强化", 13));
        _root.物品栏.背包.add(2, BaseItem.create("测试药剂", 2));
        _root.物品栏.药剂栏.add(0, BaseItem.create("测试药剂", 3));
        _root.物品栏.战备箱.add(1, BaseItem.create("测试药剂", 4));
        _root.物品栏.战备箱.add(41, BaseItem.create("测试药剂", 5));

        var equipment:Object = ProcurementPlanService.buildOwnedSummary(
            "光棱射线弹-强化");
        var stack:Object = ProcurementPlanService.buildOwnedSummary("测试药剂");
        var material:Object = ProcurementPlanService.buildOwnedSummary("测试矿石");
        var ownedIndex:Object = ProcurementPlanService.buildOwnedIndex();
        var indexedEquipment:Object = ProcurementPlanService.buildOwnedSummary(
            "光棱射线弹-强化", ownedIndex);
        var indexedStack:Object = ProcurementPlanService.buildOwnedSummary(
            "测试药剂", ownedIndex);
        var indexedMaterial:Object = ProcurementPlanService.buildOwnedSummary(
            "测试矿石", ownedIndex);
        var relocation:Object = ProcurementPlanService.buildImmediateDemand(
            "光棱射线弹-强化", 8, false, {}, ownedIndex);
        check(equipment.bag == 1 && equipment.equipped == 1
                && equipment.battleBox == 1 && equipment.usable == 1
                && equipment.total == 3 && equipment.usableMaxEnhancement == 4
                && equipment.totalMaxEnhancement == 8
                && relocation.equippedOwned == 1
                && relocation.battleBoxOwned == 1
                && relocation.equippedMaxEnhancement == 6
                && relocation.battleBoxMaxEnhancement == 8
                && relocation.relocateMissing == 1,
            "owned projection counts bag, equipped and unlocked BattleBox prefix and exposes exact relocation sources while excluding locked tail");
        check(stack.bag == 2 && stack.drug == 3 && stack.battleBox == 4
                && stack.usable == 5 && stack.total == 9,
            "stack owned projection includes drug quickslots and separates relocatable BattleBox stock");
        check(material.material == 5 && material.usable == 5 && material.total == 5,
            "collection material count remains its authoritative collection value");
        check(indexedEquipment.total == equipment.total
                && indexedEquipment.usableMaxEnhancement
                    == equipment.usableMaxEnhancement
                && indexedEquipment.totalMaxEnhancement
                    == equipment.totalMaxEnhancement
                && indexedStack.usable == stack.usable
                && indexedStack.total == stack.total
                && indexedMaterial.material == material.material,
            "single-pass owned index preserves direct cross-container projection semantics");
        check(!ProcurementPlanService.buildPlanSummary().directShopNavigation,
            "direct procurement navigation is unavailable without motorcycle infrastructure");
        _root.基建系统.infrastructure.摩托车 = 1;
        check(ProcurementPlanService.buildPlanSummary().directShopNavigation,
            "motorcycle infrastructure unlocks direct procurement navigation");
    }

    private static function testProcurementPlanAndTaskDemand():Void {
        resetOwned();
        var marked:Object = CraftingPanelService.execute("setPlan", {
            v:1, recipeId:"craft.weapon.001", plannedCrafts:2, expectedRevision:0
        });
        TaskUtil.tasks[7] = {
            title:"补给测试任务",
            finish_submit_items:["测试矿石#3"],
            finish_contain_items:["测试图纸#2"]
        };
        _root.tasks_to_do = [{id:7}];
        var index:Object = ProcurementPlanService.buildDemandIndex();
        var ore:Object = index.byItem["测试矿石"];
        var blueprint:Object = index.byItem["测试图纸"];
        var gun:Object = index.byItem["旧测试枪"];
        check(marked.success && marked.revision == 1
                && ore.required == 7 && ore.craftRequired == 4
                && ore.taskRequired == 3 && ore.usableOwned == 5
                && ore.obtainMissing == 2 && ore.relocateMissing == 0
                && ore.plannedRecipeCount == 1 && ore.activeTaskCount == 1
                && ore.reasons.length == 2 && ore.sources.length == 2,
            "marked recipes and active submit tasks aggregate exact shopping shortage and shop sources");
        check(blueprint.required == 2 && blueprint.craftRequired == 1
                && blueprint.taskRequired == 2 && blueprint.obtainMissing == 1
                && blueprint.reasons.length == 2,
            "retained information requirements use the maximum concurrent need instead of multiplying reuse");
        check(gun.required == 2 && gun.requiredEnhancement == 3
                && gun.craftRequired == 2 && gun.totalOwned == 1
                && gun.obtainMissing == 1 && !gun.needsEnhancement,
            "repeated equipment plans count copies independently while preserving the authored enhancement floor");
    }

    private static function testProcurementMutationAndConsumption():Void {
        resetOwned();
        var malformed:Object = ProcurementPlanService.setPlan({
            v:"1", recipeId:"craft.weapon.001", plannedCrafts:"1", expectedRevision:"0"
        });
        var extra:Object = ProcurementPlanService.setPlan({
            v:1, recipeId:"craft.weapon.001", plannedCrafts:1,
            expectedRevision:0, displayName:"伪字段"
        });
        var previousServer:Object = _root.server;
        _root.server = {sent:null};
        _root.server.sendSocketMessage = function(message:String):Boolean {
            this.sent = message;
            return true;
        };
        _root.gameCommands["craftingPlanSet"]({
            task:"cmd", action:"craftingPlanSet", callId:61, v:1,
            recipeId:"craft.weapon.001", plannedCrafts:1, expectedRevision:0
        });
        var marked:Object = new LiteJSON().parse(String(_root.server.sent));
        _root.gameCommands["craftingPlanSet"]({
            task:"cmd", action:"craftingPlanSet", callId:62, v:1,
            recipeId:"craft.weapon.001", plannedCrafts:2, expectedRevision:1,
            displayName:"伪字段"
        });
        var wireExtra:Object = new LiteJSON().parse(String(_root.server.sent));
        _root.server = previousServer;
        var stale:Object = CraftingPanelService.execute("setPlan", {
            v:1, recipeId:"craft.weapon.001", plannedCrafts:2, expectedRevision:0
        });
        var snapshot:Object = CraftingPanelService.execute("snapshot", {category:"武器合成"});
        var preview:Object = CraftingPanelService.execute("preview", {
            category:"武器合成", recipeIndex:0, craftCount:1
        });
        var committed:Object = CraftingPanelService.execute("commit", {
            category:"武器合成", expectedCraftToken:preview.craftToken
        });
        check(!malformed.success && malformed.error == "invalid_payload"
                && !extra.success && extra.error == "invalid_payload"
                && marked.task == "crafting_response" && marked.callId == 61
                && marked.success && marked.revision == 1
                && !wireExtra.success && wireExtra.callId == 62
                && wireExtra.error == "invalid_payload"
                && !stale.success && stale.error == "stale_state"
                && snapshot.procurement.revision == 1
                && snapshot.recipes[0].recipeId == "craft.weapon.001"
                && snapshot.recipes[0].plannedCrafts == 1,
            "real plan wire is exact, transport fields are separated, and OCC uses stable recipe identity");
        check(committed.success && committed.procurement.changed
                && committed.procurement.revision == 2
                && committed.procurement.plannedCrafts == 0
                && ProcurementPlanService.getPlannedCrafts("craft.weapon.001") == 0,
            "successful crafting consumes the exact saved plan and removes its zero remainder");
    }

    private static function testProcurementFaultRestoresExactSnapshot():Void {
        resetOwned();
        var marked:Object = ProcurementPlanService.setPlan({
            v:1, recipeId:"craft.weapon.001", plannedCrafts:1, expectedRevision:0
        });
        _root.存档系统.dirtyMark = false;
        var markDirtyCalls:Number = 0;
        _root.存档系统.markDirty = function():Void {
            markDirtyCalls++;
            throw "mock procurement dirty failure";
        };
        var preview:Object = CraftingPanelService.execute("preview", {
            category:"武器合成", recipeIndex:0, craftCount:1
        });
        var failed:Object = CraftingPanelService.execute("commit", {
            category:"武器合成", expectedCraftToken:preview.craftToken
        });
        var restoredGun:Object = _root.物品栏.背包.getItem(0);
        check(marked.success && !failed.success && failed.error == "commit_failed"
                && markDirtyCalls == 1
                && _root.收集品栏.材料.getValue("测试矿石") == 5
                && _root.收集品栏.情报.getValue("测试图纸") == 1
                && restoredGun != null && restoredGun.name == "旧测试枪"
                && _root.金钱 == 1000 && _root.虚拟币 == 100
                && _root.存档系统.dirtyMark === false
                && ProcurementPlanService.getRevision() == 1
                && ProcurementPlanService.getPlannedCrafts("craft.weapon.001") == 1
                && org.flashNight.arki.item.PlayerAssetTransaction.current() == null
                && Number(EventBus.getInstance()["_dispatchDepth"]) == 0,
            "procurement markDirty fault restores plan/assets/dirty and clears PAT/EventBus state");

        _root.存档系统.markDirty = function():Void {};
        var nextPreview:Object = CraftingPanelService.execute("preview", {
            category:"武器合成", recipeIndex:0, craftCount:1
        });
        var recovered:Object = CraftingPanelService.execute("commit", {
            category:"武器合成", expectedCraftToken:nextPreview.craftToken
        });
        check(recovered.success && recovered.procurement.changed
                && ProcurementPlanService.getRevision() == 2
                && ProcurementPlanService.getPlannedCrafts("craft.weapon.001") == 0
                && _root.金钱 == 910 && _root.虚拟币 == 82
                && org.flashNight.arki.item.PlayerAssetTransaction.current() == null
                && Number(EventBus.getInstance()["_dispatchDepth"]) == 0,
            "crafting fault settlement leaves the next independent crafting transaction healthy");
    }

    private static function testSubmitReentryRestoresExactSnapshot():Void {
        resetOwned();
        var marked:Object = ProcurementPlanService.setPlan({
            v:1, recipeId:"craft.weapon.001", plannedCrafts:1, expectedRevision:0
        });
        _root.存档系统.dirtyMark = false;
        var materials:DictCollection = _root.收集品栏.材料;
        var holder:MovieClip = _root.createEmptyMovieClip(
            "__craftSubmitReentry", _root.getNextHighestDepth());
        var dispatcher:LifecycleEventDispatcher =
            new LifecycleEventDispatcher(holder);
        materials.setDispatcher(dispatcher);
        var overRemoved:Boolean = false;
        dispatcher.subscribe("ItemValueChanged",
            function(collection:Object, key:String):Void {
                if(overRemoved || key != "测试矿石") return;
                overRemoved = true;
                materials.addValue("测试矿石", -1);
            });

        var preview:Object = CraftingPanelService.execute("preview", {
            category:"武器合成", recipeIndex:0, craftCount:1
        });
        var failed:Object = CraftingPanelService.execute("commit", {
            category:"武器合成", expectedCraftToken:preview.craftToken
        });
        check(marked.success && overRemoved
                && !failed.success && failed.error == "material_missing"
                && materials.getValue("测试矿石") == 5
                && _root.物品栏.背包.getItem(0) != null
                && _root.物品栏.背包.getItem(0).name == "旧测试枪"
                && _root.金钱 == 1000 && _root.虚拟币 == 100
                && _root.存档系统.dirtyMark === false
                && ProcurementPlanService.getRevision() == 1
                && ProcurementPlanService.getPlannedCrafts("craft.weapon.001") == 1
                && PlayerAssetTransaction.current() == null
                && Number(EventBus.getInstance()["_dispatchDepth"]) == 0,
            "crafting submit over-remove reentry returns false and restores all assets/dirty/frame");

        materials.setDispatcher(null);
        var nextPreview:Object = CraftingPanelService.execute("preview", {
            category:"武器合成", recipeIndex:0, craftCount:1
        });
        var recovered:Object = CraftingPanelService.execute("commit", {
            category:"武器合成", expectedCraftToken:nextPreview.craftToken
        });
        check(recovered.success && materials.getValue("测试矿石") == 3
                && _root.金钱 == 910 && _root.虚拟币 == 82
                && ProcurementPlanService.getRevision() == 2
                && ProcurementPlanService.getPlannedCrafts("craft.weapon.001") == 0
                && PlayerAssetTransaction.current() == null
                && Number(EventBus.getInstance()["_dispatchDepth"]) == 0,
            "crafting submit reentry failure leaves the next independent craft healthy");
        holder.removeMovieClip();
    }

    private static function testPreviewAuthority():Void {
        resetOwned();
        var result:Object = CraftingPanelService.execute("preview", {category:"武器合成", recipeIndex:0, craftCount:1});
        check(result.success && result.canCommit && String(result.craftToken).indexOf("craft.") == 0,
            "eligible preview issues one-use token");
        check(result.cost.money == 90 && result.cost.kpoints == 18,
            "smith multiplier floors each currency to legacy integer cost");
        check(result.output.name == "光棱射线弹-强化"
            && result.output.displayName == "棱镜折射阵列"
            && result.output.icon == "全光谱棱镜阵列"
            && result.output.enhancementLevel == 5 && result.levelAllowed,
            "equipment inherits highest material enhancement and reverse level opens gate");
        check(result.materials[0].consumed == false && result.materials[0].enough,
            "information requirement is authoritative but retained");
        check(result.materials[0].storageKind == "information_collection"
            && result.materials[1].storageKind == "bag"
            && result.materials[2].storageKind == "material_collection",
            "preview projects each canonical contain route without Web inference");
        check(result.outputDelivery.available && result.outputDelivery.storageKind == "bag"
            && result.outputDelivery.mode == "insert" && result.outputDelivery.physicalSlot == 0
            && result.outputDelivery.quantity == 1
            && result.acceptedPlan.outputDelivery.physicalSlot == 0
            && result.acceptedPlan.materials[1].storageKind == "bag"
            && result.acceptedPlan.cost.money == result.cost.money,
            "eligible preview binds the post-submit freed slot and equipment item count");
        check(result.acceptedPlan.outputPrototype.item.name == "光棱射线弹-强化"
            && result.acceptedPlan.outputPrototype.item.rarity == "rare"
            && result.acceptedPlan.outputPrototype.item.enhancementLevel == 5
            && result.acceptedPlan.outputPrototype.item.maxEnhancementLevel == 13
            && result.acceptedPlan.outputPrototype.item.modMeta == null
            && result.acceptedPlan.outputPrototype.confirmProjection.modSignature == ""
            && result.acceptedPlan.outputPrototype.confirmProjection.lastUpdate == undefined,
            "equipment preview freezes literal full inventory facts without a synthetic timestamp");
    }

    private static function testStoragePlanProjection():Void {
        resetOwned();
        _root.收集品栏.材料.addValue("测试矿石", 20);
        _root.物品栏.药剂栏.add(7, BaseItem.create("测试药剂", 4));
        var drugOutput:Object = CraftingPanelService.execute("preview", {
            category:"武器合成", recipeIndex:1, craftCount:1
        });
        check(drugOutput.canCommit && drugOutput.outputDelivery.storageKind == "drug"
            && drugOutput.outputDelivery.mode == "merge"
            && drugOutput.outputDelivery.physicalSlot == 7,
            "singleRequire projects an existing upper-bank drug-slot merge destination");

        _root.物品栏.背包.add(1, BaseItem.create("测试药剂", 1));
        _root.改装清单["武器合成"].push({title:"跨栏位测试", name:"测试矿石",
            value:1, price:0, kprice:0, materials:["测试药剂#5"]});
        var splitRoute:Object = CraftingPanelService.execute("preview", {
            category:"武器合成", recipeIndex:2, craftCount:1
        });
        check(splitRoute.canCommit && splitRoute.materials[0].storageKind == "bag_and_drug"
            && splitRoute.outputDelivery.storageKind == "material_collection"
            && splitRoute.outputDelivery.mode == "increment",
            "contain projects split bag-and-drug deduction and collection delivery");

        _root.改装清单["武器合成"].push({title:"缺失栏位测试", name:"测试矿石",
            value:1, price:0, kprice:0, materials:["测试药剂#99"]});
        var unavailable:Object = CraftingPanelService.execute("preview", {
            category:"武器合成", recipeIndex:3, craftCount:1
        });
        check(unavailable.success && !unavailable.canCommit
            && unavailable.materials[0].storageKind == "unavailable"
            && unavailable.acceptedPlan == undefined && unavailable.craftToken == undefined,
            "unprovable physical route stays visible but cannot mint an accepted plan or token");
    }

    private static function testOutputValueAndPrototypeAuthority():Void {
        resetOwned();
        _root.改装清单["武器合成"].push({title:"最高强化边界", name:"光棱射线弹-强化",
            value:13, price:0, kprice:0, materials:["测试矿石#1"]});
        _root.改装清单["武器合成"].push({title:"越过最高强化", name:"光棱射线弹-强化",
            value:14, price:0, kprice:0, materials:["测试矿石#1"]});
        _root.改装清单["武器合成"].push({title:"分数强化", name:"光棱射线弹-强化",
            value:1.5, price:0, kprice:0, materials:["测试矿石#1"]});
        var maximum:Object = CraftingPanelService.execute("preview", {
            category:"武器合成", recipeIndex:2, craftCount:1
        });
        var above:Object = CraftingPanelService.execute("preview", {
            category:"武器合成", recipeIndex:3, craftCount:1
        });
        var fractional:Object = CraftingPanelService.execute("preview", {
            category:"武器合成", recipeIndex:4, craftCount:1
        });
        check(maximum.success && maximum.canCommit
            && maximum.output.enhancementLevel == 13
            && maximum.outputDelivery.quantity == 1
            && maximum.acceptedPlan.outputPrototype.item.enhancementLevel == 13
            && maximum.acceptedPlan.outputPrototype.item.isMaxEnhancement,
            "equipment output at literal maximum level creates an exact strict prototype");
        check(!above.success && above.error == "invalid_output_value"
            && !fractional.success && fractional.error == "invalid_output_value",
            "equipment output above maximum or with a positive fractional level is rejected before token");
    }

    private static function testMergeReceiptAuthority():Void {
        resetOwned();
        _root.收集品栏.材料.addValue("测试矿石", 20);
        _root.物品栏.药剂栏.add(7, BaseItem.create("测试药剂", 4));
        var preview:Object = CraftingPanelService.execute("preview", {
            category:"武器合成", recipeIndex:1, craftCount:1
        });
        var commit:Object = CraftingPanelService.execute("commit", {
            category:"武器合成", expectedCraftToken:preview.craftToken
        });
        check(commit.success && preview.acceptedPlan.outputPrototype.item.quantity == 3
            && commit.outputReceipt.item.quantity == 7
            && commit.outputReceipt.confirmProjection.quantity == 7
            && commit.outputReceipt.confirmProjection.lastUpdate
                == _root.物品栏.药剂栏.getItem(7).lastUpdate,
            "stack merge receipt binds the frozen unit prototype to the literal upper-bank post-merge quantity");
    }

    private static function testBatchAuthority():Void {
        resetOwned();
        _root.收集品栏.材料.addValue("测试矿石", 20);
        _root.改装清单["武器合成"][1].price = 51;
        var result:Object = CraftingPanelService.execute("preview", {
            category:"武器合成", recipeIndex:1, craftCount:2
        });
        var previewStats:Object = CraftingPanelService.testOnlyStats();
        check(result.success && result.batchEligible && result.maxCraftCount == 2
            && result.craftCount == 2 && result.output.quantity == 6
            && previewStats.maximumProbes > 0 && previewStats.maximumProbes <= 7,
            "stack recipe preview exposes authoritative batch limit and total output");
        check(result.materials[0].required == 18 && result.canCommit && result.craftToken != undefined,
            "batch preview scales consumed material and issues count-bound token");
        check(result.cost.money == 90,
            "batch cost floors the discounted unit price before multiplying the craft count");
        var commit:Object = CraftingPanelService.execute("commit", {
            category:"武器合成", expectedCraftToken:result.craftToken
        });
        check(commit.success && commit.craftCount == 2
            && commit.acceptedPlan.outputDelivery.storageKind == result.outputDelivery.storageKind
            && commit.acceptedPlan.outputDelivery.physicalSlot == result.outputDelivery.physicalSlot
            && commit.acceptedPlan.materials[0].storageKind == result.materials[0].storageKind
            && commit.outputReceipt.item.quantity == 6
            && commit.outputReceipt.confirmProjection.quantity == 6
            && commit.outputReceipt.confirmProjection.lastUpdate >= 0
            && CraftingPanelService.testOnlyStats().maximumProbes == previewStats.maximumProbes
            && _root.收集品栏.材料.getValue("测试矿石") == 7
            && _root.物品栏.背包.getTotal("测试药剂")
                + _root.物品栏.药剂栏.getTotal("测试药剂") == 6,
            "batch commit consumes and acquires the previewed totals atomically");
        resetOwned();
        var oldPlan:Object = CraftingPanelService.execute("preview", {
            category:"武器合成", recipeIndex:0, craftCount:1
        });
        var rejected:Object = CraftingPanelService.execute("preview", {
            category:"武器合成", recipeIndex:0, craftCount:2
        });
        var stale:Object = CraftingPanelService.execute("commit", {
            category:"武器合成", expectedCraftToken:oldPlan.craftToken
        });
        check(!rejected.success && rejected.error == "batch_not_supported"
            && !stale.success && stale.error == "stale_state",
            "equipment batch is rejected and every new preview intent revokes the prior token");
    }

    private static function testStalePlanHasNoWrite():Void {
        resetOwned();
        var preview:Object = CraftingPanelService.execute("preview", {category:"武器合成", recipeIndex:0, craftCount:1});
        _root.收集品栏.材料.addValue("测试矿石", -1);
        var beforeMoney:Number = _root.金钱;
        var result:Object = CraftingPanelService.execute("commit", {
            category:"武器合成", expectedCraftToken:preview.craftToken
        });
        check(!result.success && result.error == "stale_state", "changed resource invalidates preview token");
        check(_root.金钱 == beforeMoney && _root.收集品栏.材料.getValue("测试矿石") == 4
            && _root.物品栏.背包.getItem(0).name == "旧测试枪",
            "stale commit performs no write");
    }

    private static function testProjectionDriftHasNoWrite():Void {
        resetOwned();
        var preview:Object = CraftingPanelService.execute("preview", {
            category:"武器合成", recipeIndex:0, craftCount:1
        });
        ItemUtil.itemDataDict["光棱射线弹-强化"].rarity = "legendary";
        var beforeMoney:Number = _root.金钱;
        var beforeMaterial:Number = _root.收集品栏.材料.getValue("测试矿石");
        var result:Object = CraftingPanelService.execute("commit", {
            category:"武器合成", expectedCraftToken:preview.craftToken
        });
        check(!result.success && result.error == "stale_state"
            && _root.金钱 == beforeMoney
            && _root.收集品栏.材料.getValue("测试矿石") == beforeMaterial
            && _root.物品栏.背包.getItem(0).name == "旧测试枪",
            "projection/config drift is rejected before the first write");
        ItemUtil.itemDataDict["光棱射线弹-强化"].rarity = "rare";
    }

    private static function testAtomicCommitAndReplay():Void {
        resetOwned();
        var preview:Object = CraftingPanelService.execute("preview", {category:"武器合成", recipeIndex:0, craftCount:1});
        var result:Object = CraftingPanelService.execute("commit", {
            category:"武器合成", expectedCraftToken:preview.craftToken
        });
        var crafted:Object = _root.物品栏.背包.getItem(0);
        if (crafted == null || crafted.name != "光棱射线弹-强化") crafted = _root.物品栏.背包.getItem(1);
        check(result.success && result.operation == "commit" && crafted != null
            && result.crafted.name == "光棱射线弹-强化"
            && result.crafted.displayName == "棱镜折射阵列"
            && result.crafted.icon == "全光谱棱镜阵列"
            && result.acceptedPlan.output.name == preview.acceptedPlan.output.name
            && result.acceptedPlan.outputDelivery.physicalSlot
                == preview.acceptedPlan.outputDelivery.physicalSlot
            && result.acceptedPlan.materials[1].storageKind
                == preview.acceptedPlan.materials[1].storageKind
            && crafted.name == "光棱射线弹-强化" && crafted.value.level == 5
            && result.outputReceipt.item.name == crafted.name
            && result.outputReceipt.item.rarity == "rare"
            && result.outputReceipt.item.maxEnhancementLevel == 13
            && result.outputReceipt.item.modMeta == null
            && result.outputReceipt.confirmProjection.modSignature == ""
            && result.outputReceipt.confirmProjection.lastUpdate == crafted.lastUpdate,
            "commit consumes materials and returns the literal full equipment receipt atomically");
        check(_root.收集品栏.材料.getValue("测试矿石") == 3
            && _root.收集品栏.情报.getValue("测试图纸") == 1
            && _root.金钱 == 910 && _root.虚拟币 == 82 && _root.存档系统.dirtyMark,
            "commit retains blueprint and deducts adjusted balances once");
        var replay:Object = CraftingPanelService.execute("commit", {
            category:"武器合成", expectedCraftToken:preview.craftToken
        });
        check(!replay.success && replay.error == "stale_state" && _root.金钱 == 910,
            "craft token cannot be replayed");
    }

    private static function testBlockedPreviewHasNoToken():Void {
        resetOwned();
        var result:Object = CraftingPanelService.execute("preview", {category:"武器合成", recipeIndex:1, craftCount:1});
        check(result.success && !result.canCommit && result.blockingError == "material_missing"
            && result.craftToken == undefined && result.acceptedPlan == undefined
            && result.outputDelivery != undefined,
            "blocked preview exposes delivery capability but never issues an accepted plan or token");
    }

    private static function testResponseWire():Void {
        resetOwned();
        _root.server = {sent:null};
        _root.server.sendSocketMessage = function(message:String):Boolean { this.sent = message; return true; };
        _root.gameCommands["craftingSnapshot"]({category:"武器合成", callId:17});
        var response:Object = new LiteJSON().parse(String(_root.server.sent));
        check(response.task == "crafting_response" && response.callId == 17
            && response.success && response.gender == "男" && response.recipes.length == 2,
            "snapshot handler emits parseable domain response wire");
    }

    private static function testResponseWireEscaping():Void {
        resetOwned();
        _root.server = {sent:null};
        _root.server.sendSocketMessage = function(message:String):Boolean { this.sent = message; return true; };
        // 真实数据里材料描述含 ASCII 引号（如 冰魄矿石/复合防御组件），
        // LiteJSON.stringify 不转义会产生畸形信封并被 Host 静默丢弃；wire 必须逐字保真。
        var previousDescription = ItemUtil.itemDataDict["测试矿石"].description;
        var quoted:String = "黑市切口：\"要点蜂蜜饼干吗？\" 路径 C:\\测试\\ 换行\n结束";
        ItemUtil.itemDataDict["测试矿石"].description = quoted;
        _root.gameCommands["craftingMaterialDetail"]({itemName:"测试矿石", callId:23});
        ItemUtil.itemDataDict["测试矿石"].description = previousDescription;
        var wire:String = String(_root.server.sent);
        var parsed:Object = new JSON(false).parse(wire);
        check(parsed != undefined && parsed.task == "crafting_response" && parsed.callId == 23
            && parsed.success && String(parsed.material.description) == quoted,
            "material detail wire escapes quotes, backslashes and control characters losslessly");
        check(new LiteJSON().parse(wire) == undefined,
            "quoted detail wire stays outside LiteJSON.parse's plain-scan contract");

        // tooltip 链路同样逐字保真（旧 split/join 变通已随 stringifySafe 出口移除）
        var previousTooltip:Object = _root.Web物品注释HTML;
        _root.Web物品注释HTML = function(name:String):Object {
            return {displayname:name,
                descHTML:"合成<font color=\"#ff00ff\">兽王套装</font>必备\"材料\"",
                introHTML:"intro"};
        };
        _root.gameCommands["craftingTooltip"]({itemName:"测试矿石", callId:31});
        _root.Web物品注释HTML = previousTooltip;
        var tipWire:String = String(_root.server.sent);
        var tipParsed:Object = new JSON(false).parse(tipWire);
        check(tipParsed != undefined && tipParsed.success && tipParsed.callId == 31
            && String(tipParsed.descHTML)
                == "合成<font color=\"#ff00ff\">兽王套装</font>必备\"材料\"",
            "tooltip wire keeps original double-quoted htmlText losslessly");
    }

    private static function testHandleDirectDispatch():Void {
        resetOwned();
        _root.server = {sent:null};
        _root.server.sendSocketMessage = function(message:String):Boolean { this.sent = message; return true; };
        _root.gameCommands["craftingSnapshot"]({category:"武器合成", callId:29});
        var parsed:Object = new JSON(false).parse(String(_root.server.sent));
        check(parsed != undefined && parsed.task == "crafting_response"
            && parsed.callId == 29 && parsed.success == true && parsed.recipes.length == 2,
            "registered command directly dispatches a successful snapshot response");
    }

    private static function materialShopAccessRequest(snapshotId:String,
                                                      callId:Number):Object {
        return {task:"cmd", action:"craftingMaterialShopAuthorize",
            callId:callId, v:1, materialSnapshotId:snapshotId,
            materialName:"测试矿石", shopId:"测试商人", catalogIndex:0};
    }

    private static function invokeMaterialShopAccess(params:Object):Object {
        _root.server.sent = null;
        _root.gameCommands["craftingMaterialShopAuthorize"](params);
        if (_root.server.sent == null) return null;
        return new LiteJSON().parse(String(_root.server.sent));
    }

    private static function procurementShopAccessRequest(snapshotId:String,
                                                          callId:Number):Object {
        return {task:"cmd", action:"craftingProcurementShopAuthorize",
            callId:callId, v:1, materialName:"测试矿石",
            shopId:"测试商人", catalogIndex:0,
            recipeId:"craft.weapon.001", category:"武器合成", recipeIndex:0};
    }

    private static function invokeProcurementShopAccess(params:Object):Object {
        _root.server.sent = null;
        _root.gameCommands["craftingProcurementShopAuthorize"](params);
        if (_root.server.sent == null) return null;
        return new LiteJSON().parse(String(_root.server.sent));
    }

    private static function procurementKShopAccessRequest(snapshotId:String,
                                                           callId:Number):Object {
        return {task:"cmd", action:"craftingProcurementKShopAuthorize",
            callId:callId, v:1, materialName:"测试矿石",
            catalogIndex:0, entryId:"mat-1",
            kshopCategory:"材料", recipeId:"craft.weapon.001",
            recipeCategory:"武器合成", recipeIndex:0};
    }

    private static function invokeProcurementKShopAccess(params:Object):Object {
        _root.server.sent = null;
        _root.gameCommands["craftingProcurementKShopAuthorize"](params);
        if (_root.server.sent == null) return null;
        return new LiteJSON().parse(String(_root.server.sent));
    }

    private static function exactShopAccessAllow(response:Object,
                                                 request:Object):Boolean {
        return response != null && response.task == "material_shop_access_response"
            && response.callId === request.callId && response.success === true
            && response.v === 1 && response.decision == "allow"
            && response.reason == "indexed_live_match"
            && response.materialSnapshotId == request.materialSnapshotId
            && response.materialName == request.materialName
            && response.shopId == request.shopId
            && response.catalogIndex === request.catalogIndex
            && response.itemName == request.materialName
            && hasExactKeys(response, {task:true,callId:true,success:true,v:true,
                decision:true,reason:true,materialSnapshotId:true,
                materialName:true,shopId:true,catalogIndex:true,itemName:true}, 11);
    }

    private static function exactProcurementShopAccessAllow(response:Object,
                                                             request:Object):Boolean {
        return response != null && response.task == "material_shop_access_response"
            && response.callId === request.callId && response.success === true
            && response.v === 1 && response.decision == "allow"
            && response.reason == "procurement_indexed_live_match"
            && response.materialName == request.materialName
            && response.shopId == request.shopId
            && response.catalogIndex === request.catalogIndex
            && response.itemName == request.materialName
            && response.recipeId == request.recipeId
            && response.category == request.category
            && response.recipeIndex === request.recipeIndex
            && hasExactKeys(response, {task:true,callId:true,success:true,v:true,
                decision:true,reason:true,
                materialName:true,shopId:true,catalogIndex:true,itemName:true,
                recipeId:true,category:true,recipeIndex:true}, 13);
    }

    private static function exactProcurementKShopAccessAllow(response:Object,
                                                              request:Object):Boolean {
        return response != null && response.task == "material_shop_access_response"
            && response.callId === request.callId && response.success === true
            && response.v === 1 && response.decision == "allow"
            && response.reason == "procurement_kshop_indexed_live_match"
            && response.materialName == request.materialName
            && response.catalogIndex === request.catalogIndex
            && response.entryId == request.entryId
            && response.category == request.kshopCategory
            && response.itemName == request.materialName
            && response.recipeId == request.recipeId
            && response.recipeCategory == request.recipeCategory
            && response.recipeIndex === request.recipeIndex
            && hasExactKeys(response, {task:true,callId:true,success:true,v:true,
                decision:true,reason:true,materialName:true,
                catalogIndex:true,entryId:true,category:true,itemName:true,
                recipeId:true,recipeCategory:true,recipeIndex:true}, 14);
    }

    private static function exactShopAccessFailure(response:Object,
            expectedCallId:Number, decision:String, errorCode:String):Boolean {
        return response != null && response.task == "material_shop_access_response"
            && response.callId === expectedCallId && response.success === false
            && response.v === 1 && response.decision == decision
            && response.error == errorCode
            && hasExactKeys(response, {task:true,callId:true,success:true,v:true,
                decision:true,error:true}, 6);
    }

    private static function hasExactKeys(value:Object, allowed:Object,
                                         expectedCount:Number):Boolean {
        if (value == null || typeof value != "object") return false;
        var count:Number = 0;
        for (var key:String in value) {
            if (typeof value.hasOwnProperty == "function"
                    && !value.hasOwnProperty(key)) continue;
            if (allowed[key] !== true) return false;
            count++;
        }
        return count == expectedCount;
    }

    private static function findCurrentShopRecordIndex(records:Array,
            shopId:String, catalogIndex:Number):Number {
        for (var i:Number = 0; i < records.length; i++) {
            var record:Object = records[i];
            if (record.kind == ItemObtainIndex.KIND_SHOP
                    && record.shopId == shopId
                    && Number(record.catalogIndex) == catalogIndex) return i;
        }
        return -1;
    }

    private static function findExactDrop(records:Array, dropType:String,
                                          identity:String):Object {
        for (var i:Number = 0; i < records.length; i++) {
            var record:Object = records[i];
            if (record.kind != ItemObtainIndex.KIND_DROP
                    || record.dropType != dropType) continue;
            if (dropType == ItemObtainIndex.DROP_TYPE_STAGE
                    && record.stageName == identity) return record;
            if (dropType == ItemObtainIndex.DROP_TYPE_ENEMY
                    && record.enemyType == identity) return record;
        }
        return null;
    }

    private static function filterExactKind(records:Array, kind:String):Array {
        var result:Array = [];
        for (var i:Number = 0; i < records.length; i++) {
            if (records[i].kind == kind) result.push(records[i]);
        }
        return result;
    }

    private static function findProjectedSource(sources:Array, kind:String,
                                                identityField:String,
                                                identity:String):Object {
        for (var i:Number = 0; i < sources.length; i++) {
            if (sources[i].kind == kind && sources[i][identityField] == identity) {
                return sources[i];
            }
        }
        return null;
    }

    private static function repeatText(value:String, count:Number):String {
        var result:String = "";
        for (var i:Number = 0; i < count; i++) result += value;
        return result;
    }

    private static function exactFailure(result:Object, errorCode:String):Boolean {
        if (result == null || result.success !== false
                || String(result.error) != errorCode) return false;
        var keyCount:Number = 0;
        for (var key:String in result) {
            if (typeof result.hasOwnProperty == "function"
                    && !result.hasOwnProperty(key)) continue;
            keyCount++;
            if (key != "success" && key != "error") return false;
        }
        return keyCount == 2;
    }

    private static function check(ok:Boolean, label:String):Void {
        if (ok) { passed++; trace("[PASS] " + label); }
        else { failed++; trace("[TEST_FAIL] " + label); }
    }
}
