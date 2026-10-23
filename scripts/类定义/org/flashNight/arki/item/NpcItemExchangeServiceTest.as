import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.item.BaseItem;
import org.flashNight.arki.item.NpcItemExchangeService;
import org.flashNight.arki.item.PlayerAssetTransaction;
import org.flashNight.arki.item.itemCollection.ArrayInventory;
import org.flashNight.arki.item.itemCollection.DictCollection;
import org.flashNight.arki.item.itemCollection.DrugInventory;
import org.flashNight.arki.item.itemCollection.EquipmentInventory;

/**
 * 日常插话物品交接的 AVM1 回归：真实 ItemUtil/容器/资产事务，发送与消息只做内存替身。
 * 覆盖赠送成功/叠加/金币/背满/情报溢出/非法参数/重复编号，索取普通物品/金币/情报/
 * 装备最低强化度与同强化度顺序/穿戴中拒取/重复编号。
 */
class org.flashNight.arki.item.NpcItemExchangeServiceTest {
    private static var passed:Number;
    private static var failed:Number;
    public static var messages:Array;
    public static var responses:Array;
    private static var oldGetItemData;

    private static function check(value:Boolean, label:String):Void {
        if (value) passed++;
        else { failed++; trace("[NpcItemExchangeTest] FAIL " + label); }
    }

    private static function loadData():Void {
        ItemUtil.loadItemData([
            {name:"测试药剂", displayname:"测试药剂", icon:"测试", type:"消耗品",
                use:"药剂", price:100, data:{}},
            {name:"测试药剂B", displayname:"测试药剂B", icon:"测试", type:"消耗品",
                use:"药剂", price:100, data:{}},
            {name:"测试材料", displayname:"测试材料", icon:"测试", type:"收集品",
                use:"材料", price:10, data:{}},
            {name:"测试情报", displayname:"测试情报", icon:"测试", type:"收集品",
                use:"情报", price:5, maxvalue:10, data:{}},
            {name:"测试剑", displayname:"测试剑", icon:"测试", type:"武器",
                use:"刀", price:500, data:{level:1, modslot:1, damage:5}},
            {name:"测试盾", displayname:"测试盾", icon:"测试", type:"防具",
                use:"手部装备", price:500, data:{level:1, modslot:1, defence:5}},
            {name:"测试头盔", displayname:"测试头盔", icon:"测试", type:"防具",
                use:"头部装备", price:500, data:{level:1, modslot:1, defence:5}}
        ]);
    }

    private static function resetFixture():Void {
        _root.物品栏 = {
            背包:new ArrayInventory(null, 8),
            药剂栏:new DrugInventory(null, 8),
            装备栏:new EquipmentInventory(null)
        };
        _root.收集品栏 = {材料:new DictCollection(null), 情报:new DictCollection(null)};
        _root.存档系统 = {dirtyMark:false};
        _root.金钱 = 1000;
        _root.虚拟币 = 0;
        messages = [];
        responses = [];
        PlayerAssetTransaction.resetForTests();
        oldGetItemData = _root.getItemData;
        _root.getItemData = function(name):Object {
            return org.flashNight.arki.item.ItemUtil.getRawItemData(String(name));
        };
        _root.发布消息 = function(message:String):Void {
            org.flashNight.arki.item.NpcItemExchangeServiceTest.messages.push(String(message));
        };
        _root.gameCommands = {};
        NpcItemExchangeService.resetForTests();
        NpcItemExchangeService.setTestSink(function(payload:Object):Void {
            org.flashNight.arki.item.NpcItemExchangeServiceTest.responses.push(payload);
        });
        NpcItemExchangeService.install();
    }

    private static function invoke(command:String, params:Object):Object {
        responses = [];
        var handler:Function = _root.gameCommands[command];
        if (typeof handler != "function") {
            trace("[NpcItemExchangeTest] no handler " + command);
            return null;
        }
        handler(params);
        return responses.length > 0 ? responses[responses.length - 1] : null;
    }

    private static function summaryItems(response:Object, name:String):Number {
        if (response == null || !(response.items instanceof Array)) return -1;
        for (var i:Number = 0; i < response.items.length; i++) {
            if (String(response.items[i].name) == name) return Number(response.items[i].count);
        }
        return 0;
    }

    private static function summaryEquipment(response:Object, name:String):Object {
        if (response == null || !(response.equipment instanceof Array)) return null;
        for (var i:Number = 0; i < response.equipment.length; i++) {
            if (String(response.equipment[i].name) == name) return response.equipment[i];
        }
        return null;
    }

    private static function bagCount(name:String):Number {
        var bag:Object = _root.物品栏.背包;
        var indexes:Array = bag.getIndexes();
        var total:Number = 0;
        for (var i:Number = 0; i < indexes.length; i++) {
            var item:Object = bag.getItem(Number(indexes[i]));
            if (item != null && String(item.name) == name) total += 1;
        }
        return total;
    }

    private static function addBag(slot:Number, name:String, value):BaseItem {
        var item:BaseItem = new BaseItem(name, value, 0);
        _root.物品栏.背包.add(slot, item);
        return item;
    }

    public static function runAllTests():Void {
        passed = 0;
        failed = 0;
        loadData();
        testInstall();
        testSummaryAndCount();
        testGrantSuccessAndIdempotency();
        testGrantGoldAndInvalid();
        testGrantInventoryFull();
        testGrantIntelOverflow();
        testTakeOrdinaryAndIdempotency();
        testTakeGold();
        testTakeEquipmentLowestLevel();
        testTakeWornOnlyRejected();
        trace("NpcItemExchangeServiceTest Tests Passed: " + passed);
        trace("NpcItemExchangeServiceTest Tests Failed: " + failed);
    }

    private static function testInstall():Void {
        resetFixture();
        check(typeof _root.gameCommands["npcItemSummary"] == "function", "summary command installed");
        check(typeof _root.gameCommands["npcItemCount"] == "function", "count command installed");
        check(typeof _root.gameCommands["npcItemGrant"] == "function", "grant command installed");
        check(typeof _root.gameCommands["npcItemTake"] == "function", "take command installed");
    }

    private static function testSummaryAndCount():Void {
        resetFixture();
        addBag(0, "测试药剂", 3);
        addBag(1, "测试剑", {level:3, mods:[]});
        addBag(2, "测试剑", {level:1, mods:[]});
        _root.物品栏.药剂栏.add(0, new BaseItem("测试药剂", 2, 0));
        _root.收集品栏.材料.add("测试材料", 5);
        _root.收集品栏.情报.add("测试情报", 4);
        _root.物品栏.装备栏.add("头部装备", new BaseItem("测试头盔", {level:7, mods:[]}, 0));
        _root.金钱 = 1234;

        var summary:Object = invoke("npcItemSummary", {requestId:"s1"});
        check(summary != null && summary.task == "npc_item_response", "summary envelope task");
        check(summary != null && summary.op == "summary" && summary.requestId == "s1",
            "summary envelope op/requestId");
        check(summary != null && summary.success === true && summary.money == 1234,
            "summary money");
        check(summaryItems(summary, "测试药剂") == 5, "summary aggregates bag and drugs");
        check(summaryItems(summary, "测试材料") == 5, "summary material count");
        check(summaryItems(summary, "测试情报") == 4, "summary intel count");
        var swords:Object = summaryEquipment(summary, "测试剑");
        check(swords != null && swords.count == 2 && swords.minLevel == 1,
            "summary equipment only bag with minLevel");
        check(summaryEquipment(summary, "测试头盔") == null,
            "summary excludes worn equipment");

        var count:Object = invoke("npcItemCount", {requestId:"c1", name:"测试药剂"});
        check(count != null && count.success === true && count.count == 5,
            "count ordinary across containers");
        count = invoke("npcItemCount", {requestId:"c2", name:"测试材料"});
        check(count != null && count.count == 5, "count material");
        count = invoke("npcItemCount", {requestId:"c3", name:"测试情报"});
        check(count != null && count.count == 4, "count intel");
        count = invoke("npcItemCount", {requestId:"c4", name:"测试剑"});
        check(count != null && count.count == 2 && count.equipment === true && count.minLevel == 1,
            "count equipment reports bag count and minLevel");
        count = invoke("npcItemCount", {requestId:"c5", name:"金币"});
        check(count != null && count.count == 1234, "count gold");
        count = invoke("npcItemCount", {requestId:"c6", name:"不存在物品"});
        check(count != null && count.success === true && count.count == 0,
            "count unknown name returns zero");
    }

    private static function testGrantSuccessAndIdempotency():Void {
        resetFixture();
        var result:Object = invoke("npcItemGrant", {
            requestId:"g1", npc:"测试NPC", name:"测试药剂",
            quantity:3, operationId:"op-grant-1"
        });
        check(result != null && result.success === true && result.actual == 3,
            "grant success actual");
        check(bagCount("测试药剂") == 1
            && _root.物品栏.背包.getItem(0) != null
            && Number(_root.物品栏.背包.getItem(0).value) == 3,
            "grant writes real bag stack");
        check(messages.length == 1
            && String(messages[0]) == "测试NPC赠送了你3个测试药剂",
            "grant publishes npc item message");

        var replay:Object = invoke("npcItemGrant", {
            requestId:"g1-retry", npc:"测试NPC", name:"测试药剂",
            quantity:99, operationId:"op-grant-1"
        });
        check(replay != null && replay.success === true && replay.actual == 3,
            "repeat operation returns first result");
        check(Number(_root.物品栏.背包.getItem(0).value) == 3 && messages.length == 1,
            "repeat operation does not grant twice");
    }

    private static function testGrantGoldAndInvalid():Void {
        resetFixture();
        var result:Object = invoke("npcItemGrant", {
            requestId:"g2", npc:"测试NPC", name:"金币",
            quantity:250, operationId:"op-gold"
        });
        check(result != null && result.success === true && result.actual == 250,
            "grant gold succeeds");
        check(_root.金钱 == 1250, "grant gold writes money");
        check(messages.length == 1 && String(messages[0]) == "测试NPC赠送了你250个金币",
            "grant gold message");

        var invalid:Object = invoke("npcItemGrant", {
            requestId:"g3", npc:"测试NPC", name:"测试药剂",
            quantity:0, operationId:"op-invalid-qty"
        });
        check(invalid != null && invalid.success === false && invalid.error == "invalid_quantity",
            "grant rejects zero quantity");
        invalid = invoke("npcItemGrant", {
            requestId:"g4", npc:"测试NPC", name:"测试药剂",
            quantity:1.5, operationId:"op-fraction"
        });
        check(invalid != null && invalid.error == "invalid_quantity", "grant rejects fraction");
        invalid = invoke("npcItemGrant", {
            requestId:"g5", npc:"测试NPC", name:"测试药剂",
            quantity:10000, operationId:"op-too-many"
        });
        check(invalid != null && invalid.error == "invalid_quantity", "grant rejects oversize quantity");
        invalid = invoke("npcItemGrant", {
            requestId:"g6", npc:"测试NPC", name:"测试药剂",
            quantity:1, operationId:""
        });
        check(invalid != null && invalid.error == "invalid_operation",
            "grant requires operation id");
        invalid = invoke("npcItemGrant", {
            requestId:"g7", npc:"测试NPC", name:"不存在物品",
            quantity:1, operationId:"op-unknown"
        });
        check(invalid != null && invalid.error == "unknown_item", "grant rejects unknown item");
        check(_root.金钱 == 1250, "invalid grants leave money untouched");
    }

    private static function testGrantInventoryFull():Void {
        resetFixture();
        _root.物品栏.背包.capacity = 1;
        addBag(0, "测试药剂", 1);
        var result:Object = invoke("npcItemGrant", {
            requestId:"g8", npc:"测试NPC", name:"测试药剂B",
            quantity:2, operationId:"op-full"
        });
        check(result != null && result.success === false && result.error == "inventory_full",
            "grant reports full bag");
        check(messages.length == 0, "failed grant publishes no message");
        var replay:Object = invoke("npcItemGrant", {
            requestId:"g8-retry", npc:"测试NPC", name:"测试药剂B",
            quantity:2, operationId:"op-full"
        });
        check(replay != null && replay.error == "inventory_full", "full-bag retry is idempotent");
    }

    private static function testGrantIntelOverflow():Void {
        resetFixture();
        var result:Object = invoke("npcItemGrant", {
            requestId:"g9", npc:"测试NPC", name:"测试情报",
            quantity:15, operationId:"op-intel"
        });
        check(result != null && result.success === true && result.actual == 10,
            "intel grant clamps to capacity");
        check(result != null && result.overflowMoney == 25,
            "intel overflow converts to money");
        check(_root.收集品栏.情报.getValue("测试情报") == 10, "intel capacity written");
        check(_root.金钱 == 1025, "intel overflow money written");
        check(messages.length == 1 && String(messages[0]) == "测试NPC赠送了你10个测试情报",
            "intel message uses actual quantity");
    }

    private static function testTakeOrdinaryAndIdempotency():Void {
        resetFixture();
        addBag(0, "测试药剂", 5);
        _root.物品栏.药剂栏.add(0, new BaseItem("测试药剂", 2, 0));
        _root.收集品栏.材料.add("测试材料", 7);
        _root.收集品栏.情报.add("测试情报", 6);

        var result:Object = invoke("npcItemTake", {
            requestId:"t1", npc:"测试NPC", name:"测试药剂", quantity:6,
            operationId:"op-take-drug"
        });
        check(result != null && result.success === true && result.actual == 6,
            "take ordinary across bag and drugs");
        check(_root.物品栏.背包.getItem(0) == null
            && _root.物品栏.药剂栏.getValue(0) == 1,
            "take ordinary removes exact quantities");
        check(messages.length == 1
            && String(messages[0]) == "你赠送给测试NPC6个测试药剂",
            "take publishes player gift message");

        var replay:Object = invoke("npcItemTake", {
            requestId:"t1-retry", npc:"测试NPC", name:"测试药剂", quantity:6,
            operationId:"op-take-drug"
        });
        check(replay != null && replay.success === true && replay.actual == 6,
            "repeat take returns first result");
        check(_root.物品栏.药剂栏.getValue(0) == 1, "repeat take does not deduct twice");
        check(messages.length == 1, "repeat take does not publish twice");

        result = invoke("npcItemTake", {
            requestId:"t2", name:"测试材料", quantity:3, operationId:"op-take-material"
        });
        check(result != null && result.success === true, "take material");
        check(_root.收集品栏.材料.getValue("测试材料") == 4, "take material exact");
        result = invoke("npcItemTake", {
            requestId:"t3", name:"测试情报", quantity:4, operationId:"op-take-intel"
        });
        check(result != null && result.success === true, "take intel");
        check(_root.收集品栏.情报.getValue("测试情报") == 2, "take intel exact");

        result = invoke("npcItemTake", {
            requestId:"t4", name:"测试药剂", quantity:5, operationId:"op-take-short"
        });
        check(result != null && result.success === false && result.error == "insufficient",
            "take rejects insufficient holdings");
        check(_root.物品栏.药剂栏.getValue(0) == 1, "failed take leaves holdings intact");
    }

    private static function testTakeGold():Void {
        resetFixture();
        var result:Object = invoke("npcItemTake", {
            requestId:"t5", name:"金币", quantity:400, operationId:"op-take-gold"
        });
        check(result != null && result.success === true && result.actual == 400,
            "take gold succeeds");
        check(_root.金钱 == 600, "take gold deducts exact amount");
        result = invoke("npcItemTake", {
            requestId:"t6", name:"金币", quantity:5000, operationId:"op-take-gold-short"
        });
        check(result != null && result.success === false && result.error == "insufficient",
            "take gold rejects insufficient");
        check(_root.金钱 == 600, "failed gold take leaves money intact");
    }

    private static function testTakeEquipmentLowestLevel():Void {
        resetFixture();
        addBag(0, "测试剑", {level:3, mods:[]});
        addBag(1, "测试剑", {level:1, mods:[]});
        addBag(2, "测试剑", {level:1, mods:[]});
        _root.物品栏.装备栏.add("头部装备", new BaseItem("测试头盔", {level:9, mods:[]}, 0));

        var result:Object = invoke("npcItemTake", {
            requestId:"t7", name:"测试剑", quantity:5, operationId:"op-take-sword-1"
        });
        check(result != null && result.success === true, "take equipment succeeds");
        check(result != null && result.equipment === true && result.itemLevel == 1
            && result.quantity == 1, "take equipment forces one and returns level");
        check(_root.物品栏.背包.getItem(1) == null, "take removes lowest-level bag slot");
        check(_root.物品栏.背包.getItem(2) != null, "same-level tie keeps later slot");

        result = invoke("npcItemTake", {
            requestId:"t8", name:"测试剑", quantity:1, operationId:"op-take-sword-2"
        });
        check(result != null && result.success === true && result.itemLevel == 1,
            "second take removes the other same-level slot");
        check(_root.物品栏.背包.getItem(2) == null && _root.物品栏.背包.getItem(0) != null,
            "second take removes remaining level-one slot");
        check(_root.物品栏.装备栏.getItem("头部装备") != null,
            "take never touches worn equipment");

        result = invoke("npcItemTake", {
            requestId:"t9", name:"测试剑", quantity:1, operationId:"op-take-sword-3"
        });
        check(result != null && result.success === true && result.itemLevel == 3,
            "third take removes level three");
        result = invoke("npcItemTake", {
            requestId:"t10", name:"测试剑", quantity:1, operationId:"op-take-sword-4"
        });
        check(result != null && result.success === false && result.error == "insufficient",
            "empty bag reports insufficient");
    }

    private static function testTakeWornOnlyRejected():Void {
        resetFixture();
        _root.物品栏.装备栏.add("手部装备", new BaseItem("测试盾", {level:2, mods:[]}, 0));
        var result:Object = invoke("npcItemTake", {
            requestId:"t11", name:"测试盾", quantity:1, operationId:"op-take-worn"
        });
        check(result != null && result.success === false && result.error == "insufficient",
            "worn-only equipment cannot be taken");
        check(_root.物品栏.装备栏.getItem("手部装备") != null, "worn equipment preserved");
    }
}
