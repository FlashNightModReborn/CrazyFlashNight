import org.flashNight.arki.item.drug.DrugProhibitionService;
import org.flashNight.arki.unit.Action.Skill.DrugInputService;
import org.flashNight.arki.unit.Action.Skill.ManualCooldownService;
import org.flashNight.arki.item.PlayerAssetTransaction;

/**
 * DrugProhibitionTest - 关卡禁药拦截单元测试
 *
 * focused runner: scripts/run-battle-supply-tests.ps1（battle-supply 域第三 suite）
 *
 * 覆盖（设计契约 docs/战场即时补给品-技术调研与首批施工准备-2026-09-12.md §13 禁药段）：
 *   - 禁药开启：快捷用药（updateSlot）零药效/零冷却/零扣药/有提示
 *   - 禁药开启：背包直服（consumeBackpackItem，ItemUseService 委托同一方法）同样拦截
 *   - 禁药关闭：同一物品两个入口恢复正常（药效触发、库存-1、冷却启动）
 *   - 战场补给（use=战场补给）与非药剂物品恒不被禁
 *
 * 限制条目开关用限制系统自身的 openEntries/clearEntries 接口语义模拟
 * （最小 mock 同名字段，不依赖真实关卡 XML）。
 */
class org.flashNight.arki.item.drug.DrugProhibitionTest {

    private static var passed:Number;
    private static var failed:Number;

    private static var oldGetItemData:Function;
    private static var oldRestriction:Object;

    private static function check(ok:Boolean, label:String):Void {
        if (ok) passed++;
        else { failed++; trace("[FAIL] DrugProhibitionTest: " + label); }
    }

    private static function assertEq(expected, actual, label:String):Void {
        if (expected == actual) passed++;
        else {
            failed++;
            trace("[FAIL] DrugProhibitionTest: " + label +
                " | expected: " + expected + " | actual: " + actual);
        }
    }

    public static function runAllTests():Void {
        passed = 0; failed = 0;
        oldGetItemData = _root.getItemData;
        oldRestriction = _root.限制系统;

        _root.getItemData = function(name):Object {
            if (name == "战场医疗包") return {name: name, use: "战场补给"};
            if (name == "砖") return {name: name, use: "材料"};
            if (name == "不存在的物品") return null;
            return {name: name, use: "药剂"};
        };
        _root.限制系统 = makeRestriction();

        try {
            testJudgmentMatrix();
            testQuickSlotBlockedZeroWrites();
            testBackpackBlockedZeroWrites();
            testUnblockedAfterEntryOff();
        } catch (error) {
            check(false, "unexpected exception: " + error);
        }
        finish();
    }

    private static function makeRestriction():Object {
        var restriction:Object = {entries: {}};
        restriction.openEntries = function(entryArray:Array):Void {
            for (var i:Number = 0; i < entryArray.length; i++) this.entries[entryArray[i]] = true;
        };
        restriction.clearEntries = function():Void { this.entries = {}; };
        restriction.getEntry = function(key:String):Boolean { return this.entries[key] === true; };
        return restriction;
    }

    private static function resetFixture():Void {
        _root.限制系统.clearEntries();
        ManualCooldownService.resetForTests();
        PlayerAssetTransaction.resetForTests();
        DrugInputService.resetSession();
    }

    private static function makeRoot():Object {
        var root:Object = {
            吃药冷却时间: 100,
            effectCalls: 0,
            messages: [],
            存档系统: {dirtyMark: false},
            _saveExt: {drugLoadout: {version: 2}}
        };
        root.使用药剂 = function(itemName:String):Void { this.effectCalls++; };
        root.发布消息 = function(message:String):Void { this.messages.push(message); };
        return root;
    }

    private static function makeInventory(initial:Array):Object {
        var inventory:Object = {items: {}};
        for (var i:Number = 0; i < initial.length; i++) {
            if (initial[i] != null) inventory.items[String(i)] = initial[i];
        }
        inventory.getItem = function(key:String):Object { return this.items[key]; };
        inventory.addValue = function(key:String, delta:Number):Void {
            var item:Object = this.items[key];
            if (!item) return;
            item.value += delta;
            if (item.value <= 0) delete this.items[key];
        };
        return inventory;
    }

    private static function testJudgmentMatrix():Void {
        resetFixture();
        check(DrugProhibitionService.isDrugUseBlocked("普通hp药剂") === false,
            "条目关闭时药剂不被拦");
        _root.限制系统.openEntries(["DisableDrug"]);
        check(DrugProhibitionService.isDrugUseBlocked("普通hp药剂") === true,
            "条目开启时药剂被拦");
        check(DrugProhibitionService.isDrugUseBlocked("战场医疗包") === false,
            "战场补给永不被禁");
        check(DrugProhibitionService.isDrugUseBlocked("砖") === false,
            "非药剂物品不在被禁范围");
        check(DrugProhibitionService.isDrugUseBlocked("不存在的物品") === false,
            "未注册物品安全返回 false");
        _root.限制系统.clearEntries();
        check(DrugProhibitionService.isDrugUseBlocked("普通hp药剂") === false,
            "条目清空后恢复不拦");
    }

    private static function testQuickSlotBlockedZeroWrites():Void {
        resetFixture();
        _root.限制系统.openEntries(["DisableDrug"]);
        var root:Object = makeRoot();
        var unit:Object = {hp: 100};
        var inventory:Object = makeInventory([{name: "普通hp药剂", value: 2}]);

        var result:Object = DrugInputService.updateSlot(unit, 0, true, true, inventory, root, null);
        check(result != null && result.used !== true && result.prohibited === true,
            "禁药开启快捷入口返回未使用且标记 prohibited");
        assertEq(0, root.effectCalls, "禁药零药效");
        check(inventory.getItem("0") != null && inventory.getItem("0").value == 2,
            "禁药零扣药");
        check(ManualCooldownService.isReady(ManualCooldownService.drugKey(0)),
            "禁药零冷却");
        check(root.messages.length == 1 && root.messages[0] == "本关卡禁止使用药剂！",
            "禁药拦截有明确提示");
        check(root.存档系统.dirtyMark === false, "禁药拦截不落脏");
    }

    private static function testBackpackBlockedZeroWrites():Void {
        resetFixture();
        _root.限制系统.openEntries(["DisableDrug"]);
        var root:Object = makeRoot();
        root.物品栏 = {药剂栏: makeInventory([])};
        var backpack:Object = makeInventory([{name: "普通hp药剂", value: 2}]);
        var item:Object = backpack.getItem("0");

        var result:Object = DrugInputService.consumeBackpackItem(
            {hp: 100}, backpack, 0, item, 0, root);
        check(result != null && result.used !== true && result.error == "prohibited",
            "禁药开启背包直服返回 prohibited");
        assertEq(0, root.effectCalls, "背包直服禁药零药效");
        check(backpack.getItem("0") != null && backpack.getItem("0").value == 2,
            "背包直服禁药零扣药");
        check(ManualCooldownService.isReady(ManualCooldownService.drugKey(0)),
            "背包直服禁药零冷却");
        check(root.messages.length == 1 && root.messages[0] == "本关卡禁止使用药剂！",
            "背包直服禁药有提示");
    }

    private static function testUnblockedAfterEntryOff():Void {
        resetFixture();
        _root.限制系统.openEntries(["DisableDrug"]);
        _root.限制系统.clearEntries();
        var root:Object = makeRoot();
        root.物品栏 = {药剂栏: makeInventory([])};
        var unit:Object = {hp: 100};
        var inventory:Object = makeInventory([{name: "普通hp药剂", value: 2}]);

        var quick:Object = DrugInputService.updateSlot(unit, 0, true, true, inventory, root, null);
        check(quick != null && quick.used === true, "禁药关闭后快捷入口恢复使用");
        assertEq(1, root.effectCalls, "关闭后药效正常触发");
        check(inventory.getItem("0") != null && inventory.getItem("0").value == 1,
            "关闭后库存正常 -1");
        check(!ManualCooldownService.isReady(ManualCooldownService.drugKey(0)),
            "关闭后冷却正常启动");
        check(root.存档系统.dirtyMark === true, "关闭后正常落脏");

        var backpack:Object = makeInventory([{name: "普通hp药剂", value: 1}]);
        var laneItem:Object = backpack.getItem("0");
        var direct:Object = DrugInputService.consumeBackpackItem(
            unit, backpack, 0, laneItem, 1, root);
        check(direct != null && direct.used === true && backpack.getItem("0") == null
            && root.effectCalls == 2, "关闭后背包直服同样恢复");
    }

    private static function finish():Void {
        ManualCooldownService.resetForTests();
        PlayerAssetTransaction.resetForTests();
        DrugInputService.resetSession();
        _root.getItemData = oldGetItemData;
        _root.限制系统 = oldRestriction;
        trace("DrugProhibitionTest Tests Passed: " + passed);
        trace("DrugProhibitionTest Tests Failed: " + failed);
    }
}
