// 文件路径：org/flashNight/arki/unit/Action/Skill/DrugInputServiceTest.as

import org.flashNight.arki.unit.Action.Skill.DrugInputService;
import org.flashNight.arki.unit.Action.Skill.ManualCooldownService;

class org.flashNight.arki.unit.Action.Skill.DrugInputServiceTest {

    private static var testsRun:Number = 0;
    private static var testsPassed:Number = 0;
    private static var testsFailed:Number = 0;
    private static var queue:Array = [];

    public static function runAllTests():Void {
        testsRun = testsPassed = testsFailed = 0;
        trace("--- DrugInputServiceTest ---");

        testConsumptionCooldownAndLastDoseMirror();
        testHeldInputDeadUnitZeroValueAndCooldownWait();
        testRendererOptionalSimultaneousSlotsAndFourSlotBoundary();
        testEffectFailureKeepsLegacyConsumptionOrder();
        testLiveKeyLabelAndCleanup();

        ManualCooldownService.resetForTests();
        trace("--- DrugInputServiceTest: " + testsPassed + "/" + testsRun + " passed, " + testsFailed + " failed ---");
    }

    private static function resetFixture():Void {
        queue = [];
        ManualCooldownService.resetForTests();
        ManualCooldownService.setSchedulerForTests(function(callback:Function):Void {
            queue.push(callback);
        });
    }

    private static function drainQueue():Void {
        var guard:Number = 0;
        while (queue.length > 0 && guard++ < 1000) {
            var callback = queue.shift();
            callback();
        }
    }

    private static function testConsumptionCooldownAndLastDoseMirror():Void {
        resetFixture();
        var unit:Object = {hp: 100};
        var inventory:Object = makeInventory([{name: "测试药剂", value: 2}]);
        var root:Object = makeRoot();
        root.快捷物品栏0 = "测试药剂";

        var first:Object = DrugInputService.updateSlot(unit, 0, true, true, inventory, root, null);
        assert(first.used && first.cooldownStarted && !first.depleted, "valid drug input calls effect, starts cooldown and consumes one dose");
        assert(root.effectCalls == 1 && inventory.getItem("0").value == 1, "first dose keeps one authoritative inventory item");
        assert(root.快捷物品栏0 == "测试药剂", "non-final dose keeps legacy quick-slot mirror");

        var held:Object = DrugInputService.updateSlot(unit, 0, true, true, inventory, root, null);
        assert(held == null && root.effectCalls == 1, "one held drug key cannot consume twice");
        drainQueue();
        DrugInputService.updateSlot(unit, 0, false, true, inventory, root, null);
        var last:Object = DrugInputService.updateSlot(unit, 0, true, true, inventory, root, null);
        assert(last.used && last.depleted && inventory.getItem("0") == null, "last dose removes the authoritative inventory entry");
        assert(root.快捷物品栏0 == "" && root.messages.length == 1, "last dose clears mirror and publishes one exhaustion message");
    }

    private static function testHeldInputDeadUnitZeroValueAndCooldownWait():Void {
        resetFixture();
        var root:Object = makeRoot();
        var unit:Object = {hp: 0};
        var inventory:Object = makeInventory([{name: "死亡测试药剂", value: 1}]);

        var dead:Object = DrugInputService.updateSlot(unit, 0, true, true, inventory, root, null);
        assert(dead.attempted && !dead.used && inventory.getItem("0").value == 1, "dead unit consumes hold but not a dose");
        unit.hp = 100;
        assert(DrugInputService.updateSlot(unit, 0, true, true, inventory, root, null) == null,
            "dead-unit attempt still requires key release before retry");
        DrugInputService.updateSlot(unit, 0, false, true, inventory, root, null);

        inventory.getItem("0").value = 0;
        root.快捷物品栏0 = "死亡测试药剂";
        var zero:Object = DrugInputService.updateSlot(unit, 0, true, true, inventory, root, null);
        assert(zero.depleted && !zero.used && root.快捷物品栏0 == "", "zero-value legacy entry clears mirror without invoking drug effect");

        resetFixture();
        unit = {hp: 100};
        inventory = makeInventory([{name: "等待测试药剂", value: 2}]);
        ManualCooldownService.start(ManualCooldownService.drugKey(0), 100);
        var waiting:Object = DrugInputService.updateSlot(unit, 0, true, true, inventory, root, null);
        assert(waiting == null && unit.__drugInputConsumedSlots[0] !== true, "held drug key stays armed while cooldown is active");
        drainQueue();
        var released:Object = DrugInputService.updateSlot(unit, 0, true, true, inventory, root, null);
        assert(released.used, "held drug key fires once when cooldown becomes ready");
    }

    private static function testRendererOptionalSimultaneousSlotsAndFourSlotBoundary():Void {
        resetFixture();
        var root:Object = makeRoot();
        var unit:Object = {hp: 100};
        var inventory:Object = makeInventory([
            {name: "药剂0", value: 2}, {name: "药剂1", value: 2},
            {name: "药剂2", value: 2}, {name: "药剂3", value: 2},
            {name: "旧第五格", value: 2}
        ]);

        var first:Object = DrugInputService.updateSlot(unit, 0, true, true, inventory, root, null);
        var fourth:Object = DrugInputService.updateSlot(unit, 3, true, true, inventory, root, null);
        assert(first.used && fourth.used && root.effectCalls == 2, "two drug slots may fire independently in the same frame without UI renderers");
        assert(!ManualCooldownService.isReady(ManualCooldownService.drugKey(0))
            && !ManualCooldownService.isReady(ManualCooldownService.drugKey(3)), "simultaneous slots own independent cooldowns");
        assert(DrugInputService.SLOT_COUNT == 4 && DrugInputService.getKeyName(3) == "快捷物品栏键4"
            && DrugInputService.getKeyName(4) == null, "input service excludes the decorative fifth legacy slot");
        assert(inventory.getItem("4").value == 2, "decorative fifth slot cannot be consumed by migrated input");
    }

    private static function testEffectFailureKeepsLegacyConsumptionOrder():Void {
        resetFixture();
        var root:Object = makeRoot();
        root.使用药剂 = function(itemName:String):Void {
            this.effectCalls++;
            this.lastEffectRejected = true;
        };
        var unit:Object = {hp: 100};
        var inventory:Object = makeInventory([{name: "无效药效数据", value: 2}]);

        var result:Object = DrugInputService.updateSlot(unit, 0, true, true, inventory, root, null);
        assert(result.used && root.lastEffectRejected === true, "input transaction still calls the legacy void drug-effect entry");
        assert(inventory.getItem("0").value == 1 && !ManualCooldownService.isReady(ManualCooldownService.drugKey(0)),
            "void effect rejection preserves existing deduct-and-cooldown behavior");
    }

    private static function testLiveKeyLabelAndCleanup():Void {
        resetFixture();
        var root:Object = makeRoot();
        root.keyshow = function(keyCode:Number):String { return "KEY-" + keyCode; };
        var view:Object = {控制器2: {mytext: {text: ""}}, 进度条2: makeRenderer()};
        DrugInputService.syncView(view, 2, 57, root);
        assert(view.控制器2.inputOwnedByAS === true && view.控制器2.mytext.text == "KEY-57",
            "legacy drug controller is marked display-only and receives live key label");

        var unit:Object = {hp: 100};
        var inventory:Object = makeInventory([null, null, {name: "清理测试", value: 1}]);
        DrugInputService.updateSlot(unit, 2, false, true, inventory, root, view);
        DrugInputService.clearUnit(unit);
        assert(unit.__drugInputConsumedSlots == undefined, "drug input cleanup removes all per-slot latches");
    }

    private static function makeRoot():Object {
        var root:Object = {吃药冷却时间: 100, effectCalls: 0, messages: []};
        root.使用药剂 = function(itemName:String):Void {
            this.effectCalls++;
            this.lastDrugName = itemName;
        };
        root.发布消息 = function(message:String):Void {
            this.messages.push(message);
        };
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

    private static function makeRenderer():Object {
        var renderer:Object = {};
        renderer.应用冷却投影 = function(ready:Boolean, total:Number, current:Number, frame:Number):Void {
            this.冷却 = ready;
            this.总步数 = total;
            this.当前进度 = current;
            this.lastFrame = frame;
        };
        return renderer;
    }

    private static function assert(condition:Boolean, message:String):Void {
        testsRun++;
        if (condition) {
            testsPassed++;
            trace("[PASS] " + message);
        } else {
            testsFailed++;
            trace("[TEST_FAIL] " + message);
        }
    }
}
