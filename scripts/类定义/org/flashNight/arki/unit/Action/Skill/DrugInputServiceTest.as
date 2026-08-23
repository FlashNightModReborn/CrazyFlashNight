// 文件路径：org/flashNight/arki/unit/Action/Skill/DrugInputServiceTest.as

import org.flashNight.arki.unit.Action.Skill.DrugInputService;
import org.flashNight.arki.unit.Action.Skill.ManualCooldownService;
import org.flashNight.arki.item.PlayerAssetTransaction;
import org.flashNight.arki.item.BaseItem;
import org.flashNight.arki.item.itemCollection.ArrayInventory;
import org.flashNight.neur.Event.LifecycleEventDispatcher;

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
        testMissingSaveSystemFailsBeforeAnyAuthorityWrite();
        testItemRemovedListenerFaultRecoversIndexesAndNextTransaction();
        testLiveKeyLabelAndCleanup();

        ManualCooldownService.resetForTests();
        PlayerAssetTransaction.resetForTests();
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
        assert(root.effectCalls == 1 && inventory.getItem("0").value == 1
            && root.存档系统.dirtyMark,
            "first dose keeps one authoritative inventory item and marks persistence dirty");
        assert(root.快捷物品栏0 == "测试药剂", "non-final dose keeps legacy quick-slot mirror");

        root.存档系统.dirtyMark = false;
        var held:Object = DrugInputService.updateSlot(unit, 0, true, true, inventory, root, null);
        assert(held == null && root.effectCalls == 1
            && !root.存档系统.dirtyMark,
            "one held drug key cannot consume twice or mark a no-write attempt dirty");
        drainQueue();
        DrugInputService.updateSlot(unit, 0, false, true, inventory, root, null);
        var last:Object = DrugInputService.updateSlot(unit, 0, true, true, inventory, root, null);
        assert(last.used && last.depleted && inventory.getItem("0") == null
            && root.存档系统.dirtyMark,
            "last dose removes the authoritative inventory entry and marks persistence dirty");
        assert(root.快捷物品栏0 == "" && root.messages.length == 1, "last dose clears mirror and publishes one exhaustion message");
    }

    private static function testHeldInputDeadUnitZeroValueAndCooldownWait():Void {
        resetFixture();
        var root:Object = makeRoot();
        var unit:Object = {hp: 0};
        var inventory:Object = makeInventory([{name: "死亡测试药剂", value: 1}]);

        var dead:Object = DrugInputService.updateSlot(unit, 0, true, true, inventory, root, null);
        assert(dead.attempted && !dead.used && inventory.getItem("0").value == 1
            && !root.存档系统.dirtyMark,
            "dead unit consumes hold but neither a dose nor persistence state");
        unit.hp = 100;
        assert(DrugInputService.updateSlot(unit, 0, true, true, inventory, root, null) == null,
            "dead-unit attempt still requires key release before retry");
        DrugInputService.updateSlot(unit, 0, false, true, inventory, root, null);

        inventory.getItem("0").value = 0;
        root.快捷物品栏0 = "死亡测试药剂";
        var zero:Object = DrugInputService.updateSlot(unit, 0, true, true, inventory, root, null);
        assert(zero.depleted && !zero.used && root.快捷物品栏0 == ""
            && !root.存档系统.dirtyMark,
            "zero-value legacy entry clears mirror without marking an inventory write dirty");

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
        assert(result.used && root.lastEffectRejected === true
            && root.存档系统.dirtyMark,
            "input transaction still consumes and marks dirty after the legacy void drug-effect entry");
        assert(inventory.getItem("0").value == 1 && !ManualCooldownService.isReady(ManualCooldownService.drugKey(0)),
            "void effect rejection preserves existing deduct-and-cooldown behavior");
    }

    private static function testMissingSaveSystemFailsBeforeAnyAuthorityWrite():Void {
        resetFixture();
        PlayerAssetTransaction.resetForTests();
        var receipts:Array = [];
        PlayerAssetTransaction.setTestSink(function(receipt:Object):Void {
            receipts.push(receipt);
        });
        var root:Object = makeRoot();
        delete root.存档系统;
        var unit:Object = {hp:100};
        var inventory:Object = makeInventory([{name:"无存档药剂", value:1}]);

        try {
            var missingSaveError = null;
            try {
                DrugInputService.updateSlot(unit, 0, true, true, inventory, root, null);
            } catch (useError) {
                missingSaveError = useError;
            }
            assert(missingSaveError != null,
                "missing save system fails the drug transaction before authority work");
            assert(root.effectCalls == 0 && inventory.getItem("0").value == 1
                    && ManualCooldownService.isReady(ManualCooldownService.drugKey(0)),
                "missing persistence performs no effect, cooldown or inventory write");
            assert(PlayerAssetTransaction.current() == null && receipts.length == 0,
                "missing persistence settles the empty explicit frame without a ghost receipt");

            root.存档系统 = {dirtyMark:false};
            DrugInputService.updateSlot(unit, 0, false, true, inventory, root, null);
            var recovered:Object = DrugInputService.updateSlot(
                unit, 0, true, true, inventory, root, null);
            assert(recovered.used && recovered.depleted && root.存档系统.dirtyMark === true
                    && receipts.length == 1 && receipts[0].effects.length == 1
                    && receipts[0].effects[0].name == "无存档药剂",
                "the next released input opens an independent transaction after persistence recovers");
        } finally {
            PlayerAssetTransaction.resetForTests();
        }
    }

    private static function testItemRemovedListenerFaultRecoversIndexesAndNextTransaction():Void {
        resetFixture();
        PlayerAssetTransaction.resetForTests();
        var receipts:Array = [];
        PlayerAssetTransaction.setTestSink(function(receipt:Object):Void {
            receipts.push(receipt);
        });
        var root:Object = makeRoot();
        var unit:Object = {hp:100};
        var inventory:ArrayInventory = new ArrayInventory({}, 4);
        inventory.add(0, new BaseItem("监听故障药剂", 1, 1));
        inventory.add(1, new BaseItem("后续独立药剂", 1, 1));
        var holder:MovieClip = _root.createEmptyMovieClip(
            "__drugInputListenerFault", _root.getNextHighestDepth());
        var dispatcher:LifecycleEventDispatcher = new LifecycleEventDispatcher(holder);
        inventory.setDispatcher(dispatcher);
        dispatcher.subscribe("ItemRemoved", function():Void {
            throw "drug_removed_listener_failed";
        });

        try {
            var originalError = null;
            try {
                DrugInputService.updateSlot(unit, 0, true, true, inventory, root, null);
            } catch (useError) {
                originalError = useError;
            }
            assert(originalError == "drug_removed_listener_failed",
                "drug removal preserves the synchronous listener exception");
            var repairedIndexes:Array = inventory.getIndexes();
            assert(inventory.getItem("0") == null && root.存档系统.dirtyMark === true
                    && repairedIndexes.length == 1 && repairedIndexes[0] == 1,
                "listener fault keeps the committed dose loss, marks dirty first and repairs indexes");
            assert(PlayerAssetTransaction.current() == null && receipts.length == 1
                    && receipts[0].effects.length == 1
                    && receipts[0].effects[0].direction == "loss"
                    && receipts[0].effects[0].name == "监听故障药剂"
                    && receipts[0].effects[0].count == 1,
                "listener fault settles one exact loss receipt without leaking a transaction frame");

            inventory.setDispatcher(null);
            dispatcher = new LifecycleEventDispatcher(holder);
            inventory.setDispatcher(dispatcher);
            var observedNextRemoval:Number = 0;
            dispatcher.subscribe("ItemRemoved", function():Void {
                observedNextRemoval++;
            });
            root.存档系统.dirtyMark = false;
            var next:Object = DrugInputService.updateSlot(
                unit, 1, true, true, inventory, root, null);
            assert(next.used && next.depleted && inventory.getItem("1") == null
                    && observedNextRemoval == 1 && root.存档系统.dirtyMark === true
                    && PlayerAssetTransaction.current() == null,
                "the next slot dispatch and asset transaction complete independently after the fault");
            assert(receipts.length == 2 && receipts[1].effects.length == 1
                    && receipts[1].effects[0].name == "后续独立药剂"
                    && receipts[1].effects[0].count == 1,
                "the next receipt does not inherit the failed transaction effects");
        } finally {
            inventory.setDispatcher(null);
            holder.removeMovieClip();
            PlayerAssetTransaction.resetForTests();
        }
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
        var root:Object = {
            吃药冷却时间:100,
            effectCalls:0,
            messages:[],
            存档系统:{dirtyMark:false}
        };
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
