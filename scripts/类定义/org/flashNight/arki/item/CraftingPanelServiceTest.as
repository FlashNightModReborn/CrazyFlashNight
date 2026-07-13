import org.flashNight.arki.item.CraftingPanelService;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.item.BaseItem;
import org.flashNight.arki.item.itemCollection.ArrayInventory;
import org.flashNight.arki.item.itemCollection.DictCollection;

/** CraftingPanelService C0-C3 回归测试。 */
class org.flashNight.arki.item.CraftingPanelServiceTest {
    private static var passed:Number = 0;
    private static var failed:Number = 0;

    public static function runAllTests():Void {
        passed = 0; failed = 0;
        setup();
        testOpenRequestWire();
        testSnapshotProjection();
        testSnapshotAvailabilityRefresh();
        testPreviewAuthority();
        testBatchAuthority();
        testStalePlanHasNoWrite();
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
        data["旧测试枪"] = itemData("旧测试枪", "武器", "手枪", 1);
        data["新测试枪"] = itemData("新测试枪", "武器", "手枪", 12);
        data["测试药剂"] = itemData("测试药剂", "消耗品", "药剂", 1);
        ItemUtil.itemDataDict = data;
        ItemUtil.equipmentDict = {};
        ItemUtil.equipmentDict["旧测试枪"] = true;
        ItemUtil.equipmentDict["新测试枪"] = true;
        ItemUtil.materialDict = {};
        ItemUtil.materialDict["测试矿石"] = true;
        ItemUtil.informationMaxValueDict = {};
        ItemUtil.informationMaxValueDict["测试图纸"] = 1;
        _root.gameCommands = {};
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
        _root.主角被动技能 = {
            逆向:{启用:true, 等级:2},
            铁匠:{启用:true, 等级:2}
        };
        _root.存档系统 = {dirtyMark:false};
        _root.改装清单 = {};
        _root.改装清单["武器合成"] = [
            {title:"新测试枪图纸", name:"新测试枪", price:101, kprice:21,
                materials:["测试图纸#1", "旧测试枪#3", "测试矿石#2"]},
            {title:"测试药剂图纸", name:"测试药剂", value:3, price:0, kprice:0,
                materials:["测试矿石#9"]}
        ];
        CraftingPanelService.testOnlyReset();
    }

    private static function testOpenRequestWire():Void {
        var previous:Object = _root.server;
        _root.server = {sent:null};
        _root.server.sendSocketMessage = function(message:String):Boolean { this.sent = message; return true; };
        var opened:Boolean = CraftingPanelService.openPanel("武器合成", "legacy_crafting_entry");
        check(opened && String(_root.server.sent) == '{"task":"panel_request","panel":"crafting","source":"legacy_crafting_entry","initData":{"category":"武器合成"}}',
            "legacy crafting entry emits strict panel request");
        check(!CraftingPanelService.openPanel("未知分类", "legacy_crafting_entry"),
            "unknown crafting category is rejected before host");
        _root.server = previous;
    }

    private static function testSnapshotProjection():Void {
        resetOwned();
        var result:Object = CraftingPanelService.execute("snapshot", {category:"武器合成"});
        check(result.success && result.v == 1 && result.recipes.length == 2,
            "snapshot projects category catalog");
        check(result.recipes[0].output.name == "新测试枪" && result.recipes[0].materialCount == 3
            && result.recipes[0].canCraftOne && result.recipes[0].availability == "ready"
            && !result.recipes[1].canCraftOne && result.recipes[1].availability == "material_missing",
            "snapshot exposes static output and authoritative one-craft availability");
        check(!result.recipes[0].batchEligible && result.recipes[1].batchEligible
            && result.recipes[0].output.weaponType == "手枪",
            "snapshot exposes batch eligibility and shared filter taxonomy");
        check(result.balance.money == 1000 && result.skills.smithLevel == 2,
            "snapshot exposes authoritative balances and skills");
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
        check(result.output.enhancementLevel == 5 && result.levelAllowed,
            "equipment inherits highest material enhancement and reverse level opens gate");
        check(result.materials[0].consumed == false && result.materials[0].enough,
            "information requirement is authoritative but retained");
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

    private static function testAtomicCommitAndReplay():Void {
        resetOwned();
        var preview:Object = CraftingPanelService.execute("preview", {category:"武器合成", recipeIndex:0, craftCount:1});
        var result:Object = CraftingPanelService.execute("commit", {
            category:"武器合成", expectedCraftToken:preview.craftToken
        });
        var crafted:Object = _root.物品栏.背包.getItem(0);
        if (crafted == null || crafted.name != "新测试枪") crafted = _root.物品栏.背包.getItem(1);
        check(result.success && result.operation == "commit" && crafted != null
            && crafted.name == "新测试枪" && crafted.value.level == 5,
            "commit consumes materials and acquires inherited equipment atomically");
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
            && result.craftToken == undefined, "blocked preview never issues a commit token");
    }

    private static function testResponseWire():Void {
        resetOwned();
        _root.server = {sent:null};
        _root.server.sendSocketMessage = function(message:String):Boolean { this.sent = message; return true; };
        _root.gameCommands["craftingSnapshot"]({category:"武器合成", callId:17});
        var response:Object = new LiteJSON().parse(String(_root.server.sent));
        check(response.task == "crafting_response" && response.callId == 17
            && response.success && response.recipes.length == 2,
            "snapshot handler emits parseable domain response wire");
    }

    private static function check(ok:Boolean, label:String):Void {
        if (ok) { passed++; trace("[PASS] " + label); }
        else { failed++; trace("[TEST_FAIL] " + label); }
    }
}
