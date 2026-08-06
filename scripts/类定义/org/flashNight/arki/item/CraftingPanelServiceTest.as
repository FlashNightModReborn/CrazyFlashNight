import org.flashNight.arki.item.CraftingPanelService;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.item.BaseItem;
import org.flashNight.arki.item.itemCollection.ArrayInventory;
import org.flashNight.arki.item.itemCollection.DictCollection;
import org.flashNight.arki.item.obtain.ItemObtainIndex;
import org.flashNight.arki.item.synthesis.SynthesisIndex;

/** CraftingPanelService C0-C3 回归测试。 */
class org.flashNight.arki.item.CraftingPanelServiceTest {
    private static var passed:Number = 0;
    private static var failed:Number = 0;

    public static function runAllTests():Void {
        passed = 0; failed = 0;
        setup();
        testOpenRequestWire();
        testMaterialsProjection();
        testLegacyIdentityWhitespaceFallback();
        testInformationOverflowPolicy();
        testSnapshotProjection();
        testSnapshotGenderNormalization();
        testSnapshotAvailabilityRefresh();
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
            药剂栏:new ArrayInventory(null, 4)
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
        _root.改装清单 = {};
        _root.改装清单["武器合成"] = [
            {title:"棱镜折射阵列图纸", name:"光棱射线弹-强化", price:101, kprice:21,
                materials:["测试图纸#1", "旧测试枪#3", "测试矿石#2"]},
            {title:"测试药剂图纸", name:"测试药剂", value:3, price:0, kprice:0,
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
        var obtainIndex:ItemObtainIndex = ItemObtainIndex.getInstance();
        obtainIndex.reset(true);
        obtainIndex.buildIndex(_root.改装清单, shop, []);
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
            && catalog.materials[0].owned == 5 && catalog.materials[0].sourceCount == 1
            && catalog.materials[0].useCount == 2 && catalog.materials[0].hasSourceSummary,
            "material catalog projects owned count and existing source/use indexes");
        var detail:Object = CraftingPanelService.execute("materialDetail", {itemName:"测试矿石"});
        check(detail.success && detail.material.name == "测试矿石"
            && detail.material.sourceSummary.indexOf("测试关卡") >= 0
            && detail.sources.length == 1 && detail.sources[0].kind == "shop"
            && detail.uses.length == 2 && detail.uses[0].required > 0,
            "material detail exposes annotation, structured sources and recipe uses");
        var previousEnemyTable:Object = _root.敌人属性表;
        _root.敌人属性表 = {};
        _root.敌人属性表["enemy.internal.visible"] = {displayname:"敌人展示名"};
        _root.敌人属性表["enemy.internal.equal"] = {displayname:"enemy.internal.equal"};
        _root.敌人属性表["enemy.internal.missing"] = {};
        _root.敌人属性表["enemy.internal.sentinel"] = {displayname:" Undefined "};
        _root.敌人属性表["enemy.internal.wrong"] = {displayname:{legacy:"bad"}};
        var obtainIndex:ItemObtainIndex = ItemObtainIndex.getInstance();
        obtainIndex.updateEnemyDrops("enemy.internal.visible", [
            {名字:"测试矿石", 概率:0.25, 最小逆向等级:1, 最大逆向等级:9}
        ]);
        obtainIndex.updateEnemyDrops("enemy.internal.equal", [
            {名字:"测试矿石", 概率:0.2, 最小逆向等级:0, 最大逆向等级:0}
        ]);
        obtainIndex.updateEnemyDrops("enemy.internal.missing", [
            {名字:"测试矿石", 概率:0.15, 最小逆向等级:0, 最大逆向等级:0}
        ]);
        obtainIndex.updateEnemyDrops("enemy.internal.sentinel", [
            {名字:"测试矿石", 概率:0.1, 最小逆向等级:0, 最大逆向等级:0}
        ]);
        obtainIndex.updateEnemyDrops("enemy.internal.wrong", [
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
            if (source.enemyType == "enemy.internal.visible") visibleEnemy = source;
            else if (source.enemyType == "enemy.internal.equal") equalEnemy = source;
            else if (source.enemyType == "enemy.internal.missing") missingEnemy = source;
            else if (source.enemyType == "enemy.internal.sentinel") sentinelEnemy = source;
            else if (source.enemyType == "enemy.internal.wrong") wrongEnemy = source;
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
        check(firstStats.availabilityPlans == first.recipes.length && firstStats.maximumProbes == 0,
            "snapshot evaluates one bounded availability plan per recipe without batch maximum probes");
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
            && refreshedStats.maximumProbes == 0,
            "snapshot availability refreshes after material and balance mutations without maximum scans");
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
        _root.物品栏.药剂栏.add(1, BaseItem.create("测试药剂", 4));
        var drugOutput:Object = CraftingPanelService.execute("preview", {
            category:"武器合成", recipeIndex:1, craftCount:1
        });
        check(drugOutput.canCommit && drugOutput.outputDelivery.storageKind == "drug"
            && drugOutput.outputDelivery.mode == "merge"
            && drugOutput.outputDelivery.physicalSlot == 1,
            "singleRequire projects an existing drug-slot merge destination");

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
        _root.物品栏.药剂栏.add(1, BaseItem.create("测试药剂", 4));
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
                == _root.物品栏.药剂栏.getItem(1).lastUpdate,
            "stack merge receipt binds the frozen unit prototype to the literal post-merge quantity");
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

    private static function check(ok:Boolean, label:String):Void {
        if (ok) { passed++; trace("[PASS] " + label); }
        else { failed++; trace("[TEST_FAIL] " + label); }
    }
}
