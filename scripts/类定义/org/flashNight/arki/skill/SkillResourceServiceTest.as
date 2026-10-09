import org.flashNight.arki.skill.SkillResourceService;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.item.BaseItem;
import org.flashNight.arki.item.itemCollection.ArrayInventory;
import org.flashNight.arki.item.itemCollection.DrugInventory;
import org.flashNight.arki.item.itemCollection.DictCollection;

/** 实际物品容器与冻结 contain oracle 的显示只读差分；不连接存档或交易入口。 */
class org.flashNight.arki.skill.SkillResourceServiceTest {
    private static var passed:Number = 0;
    private static var failed:Number = 0;
    private static var checksum:Number = 0;
    private static function check(value:Boolean, message:String):Void {
        if (value) passed++; else { failed++; trace("[FAIL] SkillResourceServiceTest: " + message); }
    }
    public static function runAllTests():Void {
        passed = failed = checksum = 0;
        testResourceCounts();
        trace("SkillResourceServiceTest Tests Passed: " + passed);
        trace("SkillResourceServiceTest Tests Failed: " + failed);
    }
    // 冻结自 5361c1a；保留全量 contain 的类型、异常值与手雷 fallback 语义。
    private static function legacyItemState(name:String, grenadeFallback:Boolean):Object {
        if (name == undefined || name == "") return {state:"unknown", reason:""};
        var fallback:Number = 0;
        var grenade:Object = _root.物品栏.装备栏.getItem("手雷");
        if (grenadeFallback && grenade && grenade.name == name)
            fallback = isNaN(Number(grenade.value)) ? 1 : Math.max(0, Number(grenade.value));
        if (fallback >= 2 || ItemUtil.singleContain(name, Math.max(0, 2 - fallback)) != null)
            return {state:"ready", reason:""};
        if (fallback >= 1 || ItemUtil.singleContain(name, 1) != null) return {state:"last", reason:"item"};
        return {state:"blocked", reason:"item"};
    }
    private static function compareResource(name:String, fallback:Boolean, label:String):Void {
        var expected:Object = legacyItemState(name, fallback);
        var actual:Object = SkillResourceService.itemState(name, fallback);
        check(actual.state === expected.state && actual.reason === expected.reason, label);
    }
    private static function pair(bagQuantity:Number, drugQuantity:Number, bagSlot:Number, drugSlot:Number):Object {
        var bag:ArrayInventory = new ArrayInventory({}, 24);
        var drugs:DrugInventory = new DrugInventory({}, 8);
        if (bagQuantity > 0) check(bag.add(bagSlot, new BaseItem("perfBattery", bagQuantity)), "fixture admits actual backpack item");
        if (drugQuantity > 0) {
            var admitted:Boolean = drugs.add(drugSlot, new BaseItem("perfBattery", drugQuantity));
            check(admitted, "fixture admits actual drug item");
            if (!admitted && bagQuantity == 0 && drugQuantity == 1)
                trace("[HUD_FIXTURE_DIAG] slot=" + drugSlot + "|capacity=" + drugs.capacity
                    + "|use=" + _root.getItemData("perfBattery").use + "|empty=" + drugs.isEmpty(drugSlot)
                    + "|addable=" + drugs.isAddable(String(drugSlot), new BaseItem("perfBattery", drugQuantity)));
        }
        var equip:Object = {grenade:null};
        equip.getItem = function(key:String):Object { return key == "手雷" ? this.grenade : null; };
        return {背包:bag, 药剂栏:drugs, 装备栏:equip};
    }
    private static function testResourceCounts():Void {
        var itemApi:Object = ItemUtil;
        var oldItems:Object = _root.物品栏, oldCollections:Object = _root.收集品栏;
        var oldData:Object = ItemUtil.itemDataDict, oldGetter:Function = _root.getItemData;
        var oldEquipment:Object = itemApi.equipmentDict, oldMaterial:Object = itemApi.materialDict;
        var oldInformation:Object = itemApi.informationMaxValueDict;
        try {
            ItemUtil.itemDataDict = {perfBattery:{type:"消耗品",use:"药剂"}, perfOther:{type:"消耗品",use:"药剂"},
                perfEquipment:{type:"武器"}, perfMaterial:{type:"材料"}, perfInformation:{type:"情报"}};
            itemApi.equipmentDict = {perfEquipment:true};
            itemApi.materialDict = {perfMaterial:true};
            itemApi.informationMaxValueDict = {perfInformation:99};
            _root.getItemData = function(name:String):Object { return ItemUtil.itemDataDict[name]; };
            check(_root.getItemData("perfBattery").use === "药剂", "fixture resolves drug catalog through root bridge");
            _root.收集品栏 = {材料:new DictCollection({perfMaterial:1}), 情报:new DictCollection({perfInformation:2})};
            var drugSlots:Array = [0, 4, 7];
            for (var position:Number = 0; position < 6; position++) {
                for (var bagCount:Number = 0; bagCount < 3; bagCount++) {
                    for (var drugCount:Number = 0; drugCount < 3; drugCount++) {
                        _root.物品栏 = pair(bagCount, drugCount, position < 3 ? 0 : 23, drugSlots[position % 3]);
                        for (var grenadeCount:Number = 0; grenadeCount < 3; grenadeCount++) {
                            _root.物品栏.装备栏.grenade = {name:"perfBattery", value:grenadeCount};
                            compareResource("perfBattery", false, "ordinary physical slot/quantity matrix");
                            compareResource("perfBattery", true, "grenade physical slot/quantity matrix");
                        }
                    }
                }
            }
            _root.物品栏 = pair(1, 0, 23, 7);
            compareResource("perfMaterial", false, "material dictionary remains authoritative");
            compareResource("perfInformation", false, "information dictionary remains authoritative");
            compareResource("", false, "empty name remains unknown");
            compareResource(undefined, false, "missing name remains unknown");
            _root.物品栏.背包.add(0, new BaseItem("perfEquipment", {level:1,mods:[]}));
            compareResource("perfEquipment", false, "equipment level semantics remain on contain");
            _root.物品栏.背包.getItem(0).value.level = 2;
            compareResource("perfEquipment", false, "equipment level two remains ready");
            var strange:Array = [0, -1, Number.NaN, Number.POSITIVE_INFINITY, "2", {}, null, undefined, 0.5];
            for (var i:Number = 0; i < strange.length; i++) {
                _root.物品栏 = pair(1, 1, 23, 7);
                _root.物品栏.背包.getItem(23).value = strange[i];
                compareResource("perfBattery", false, "aliased backpack value " + i);
                _root.物品栏 = pair(2, 1, 23, 7);
                _root.物品栏.药剂栏.getItem(7).value = strange[i];
                compareResource("perfBattery", false, "already satisfied bag retains drug anomaly " + i);
                _root.物品栏.装备栏.grenade = {name:"perfBattery", value:strange[i]};
                compareResource("perfBattery", true, "grenade fallback normalization " + i);
            }
            _root.物品栏 = pair(1, 0, 0, 0);
            _root.物品栏.背包.add(1, new BaseItem("perfBattery", 1));
            _root.物品栏.背包.add(2, new BaseItem("perfBattery", 1));
            _root.物品栏.背包.getItem(0).value = 0.2;
            _root.物品栏.背包.getItem(1).value = 0.4;
            _root.物品栏.背包.getItem(2).value = 1.4;
            check(_root.物品栏.背包.getIndexes().length == 3, "fractional fixture has three actual stacks");
            var originalContain:Function = itemApi.singleContain;
            var containCalls:Number = 0;
            itemApi.singleContain = function(name:String, amount:Number):Object {
                containCalls++;
                return originalContain(name, amount);
            };
            SkillResourceService.itemState("perfBattery", false);
            itemApi.singleContain = originalContain;
            check(containCalls > 0, "fractional stack quantities retain the original subtraction path");
            compareResource("perfBattery", false, "fractional stacks retain exact contain result");
            testResourceReadWork();
            benchmarkResources(0);
            benchmarkResources(1);
            benchmarkResources(2);
        } finally {
            _root.物品栏 = oldItems; _root.收集品栏 = oldCollections; _root.getItemData = oldGetter;
            ItemUtil.itemDataDict = oldData; itemApi.equipmentDict = oldEquipment;
            itemApi.materialDict = oldMaterial; itemApi.informationMaxValueDict = oldInformation;
        }
    }
    private static function countReads(inventory:Object):Void {
        inventory.__hintReads = 0;
        inventory.__hintIndexes = inventory.getIndexes;
        inventory.getIndexes = function():Array { this.__hintReads++; return this.__hintIndexes(); };
    }
    private static function testResourceReadWork():Void {
        _root.物品栏 = pair(0, 1, 23, 7);
        var bag:Object = _root.物品栏.背包, drugs:Object = _root.物品栏.药剂栏;
        var beforeBag:Number = bag.getMutationRevision(), beforeDrugs:Number = drugs.getMutationRevision();
        var item:Object = drugs.getItem(7);
        countReads(bag); countReads(drugs);
        var reads:Object = {};
        var first:Object = SkillResourceService.itemState("perfBattery", false, reads);
        var second:Object = SkillResourceService.itemState("perfBattery", false, reads);
        check(first.state == "last" && first === second, "same snapshot reuses the resource result");
        check(bag.__hintReads == 1 && drugs.__hintReads == 1, "last resource scans each actual container only once");
        check(bag.getMutationRevision() == beforeBag && drugs.getMutationRevision() == beforeDrugs
            && drugs.getItem(7) === item && item.value == 1, "projection changes neither inventory content nor revision");
        bag.__hintReads = drugs.__hintReads = 0;
        legacyItemState("perfBattery", false);
        check(bag.__hintReads == 2 && drugs.__hintReads == 2, "frozen baseline pays two index reads per container");
        item.value = 2;
        check(SkillResourceService.itemState("perfBattery", false, {}).state == "ready", "next snapshot sees in-place writes without a revision cache");
    }
    private static function timeResources(legacy:Boolean, count:Number):Number {
        var started:Number = getTimer();
        for (var i:Number = 0; i < count; i++) {
            var hint:Object = legacy ? legacyItemState("perfBattery", false) : SkillResourceService.itemState("perfBattery", false);
            checksum += length(hint.state);
        }
        return getTimer() - started;
    }
    private static function benchmarkResources(quantity:Number):Void {
        _root.物品栏 = pair(quantity, 0, 23, 7);
        for (var i:Number = 0; i < 20; i++) _root.物品栏.背包.add(i, new BaseItem("perfOther", 5));
        for (i = 0; i < 8; i++) _root.物品栏.药剂栏.add(i, new BaseItem("perfOther", 5));
        timeResources(true, 20); timeResources(false, 20);
        var original:Array = [], candidate:Array = [];
        for (var round:Number = 0; round < 5; round++) {
            if ((round & 1) == 0) {
                original.push(timeResources(true, 200)); candidate.push(timeResources(false, 200));
            } else {
                candidate.push(timeResources(false, 200)); original.push(timeResources(true, 200));
            }
        }
        trace("[AS2_HOTPATH_BENCH] resource_quantity_" + quantity + "|iterations=200|baselineMs=" + original.join(",") + "|candidateMs=" + candidate.join(","));
    }
}
