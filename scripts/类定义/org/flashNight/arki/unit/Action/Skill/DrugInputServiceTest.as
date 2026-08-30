// 文件路径：org/flashNight/arki/unit/Action/Skill/DrugInputServiceTest.as

import org.flashNight.arki.unit.Action.Skill.DrugInputService;
import org.flashNight.arki.unit.Action.Skill.ManualCooldownService;
import org.flashNight.arki.item.PlayerAssetTransaction;
import org.flashNight.arki.item.BaseItem;
import org.flashNight.arki.item.itemCollection.ArrayInventory;
import org.flashNight.neur.Event.LifecycleEventDispatcher;
import org.flashNight.neur.Event.EventBus;

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
        testSwitchEdgeCooldownAndNoBuffer();
        testLifecyclePreservesBankAndAllDrugCooldowns();
        testPairedPhysicalSlotsShareLaneCooldown();
        testBankProjectionAndSessionReset();
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
        DrugInputService.resetSession();
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
        assert(root.快捷物品栏0 == "测试药剂", "non-final dose does not mutate the retired legacy quick-slot mirror");

        root.存档系统.dirtyMark = false;
        var held:Object = DrugInputService.updateSlot(unit, 0, true, true, inventory, root, null);
        assert(held == null && root.effectCalls == 1
            && !root.存档系统.dirtyMark,
            "one held drug key cannot consume twice or mark a no-write attempt dirty");
        drainQueue();
        DrugInputService.updateSlot(unit, 0, false, true, inventory, root, null);
        var last:Object = DrugInputService.updateSlot(unit, 0, true, true, inventory, root, null);
        assert(last.used && last.depleted && inventory.getItem("0") == null
            && root.存档系统.dirtyMark && last.affinityCommitted
            && root._saveExt.drugLoadout.version == 3
            && root._saveExt.drugLoadout.slots[0].itemKey == "测试药剂"
            && root._saveExt.drugLoadout.slots[0]
                .lastDepletedSequence == 1
            && root._saveExt.drugLoadout.nextDepletedSequence == 2,
            "last dose removes the authoritative inventory entry and marks persistence dirty");
        assert(root.快捷物品栏0 == "测试药剂" && root.messages.length == 1,
            "last dose publishes exhaustion without writing the retired root mirror");
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
        assert(zero.depleted && !zero.used && root.快捷物品栏0 == "死亡测试药剂"
            && !root.存档系统.dirtyMark,
            "zero-value legacy entry reports depletion without a mirror or inventory write");

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
        assert(DrugInputService.BANK_COUNT == 2 && DrugInputService.LANE_COUNT == 4
            && DrugInputService.PHYSICAL_SLOT_COUNT == 8 && DrugInputService.SLOT_COUNT == 8,
            "input service exposes two banks, four lanes and eight physical slots");
        assert(DrugInputService.getKeyName(3) == "快捷物品栏键4"
            && DrugInputService.getKeyName(4) == null
            && DrugInputService.getSwitchKeyName() == "药剂组切换键",
            "four lane keys stay separate from the dedicated switch logical id");
        assert(DrugInputService.physicalSlotFor(1, 3) == 7
            && DrugInputService.bankForPhysicalSlot(7) == 1
            && DrugInputService.laneForPhysicalSlot(7) == 3
            && DrugInputService.physicalSlotFor(2, 0) == -1
            && DrugInputService.bankForPhysicalSlot(8) == -1,
            "bank, lane and physical-slot helpers enforce the frozen mapping");
        assert(inventory.getItem("4").value == 2,
            "bank-II physical slot is not consumed while bank I is active");
    }

    private static function testSwitchEdgeCooldownAndNoBuffer():Void {
        resetFixture();
        var root:Object = makeRoot();
        var unit:Object = {hp:100};

        var paused:Object = DrugInputService.updateSwitch(unit, true, false, root, null);
        assert(paused.attempted && !paused.switched && DrugInputService.getActiveBank() == 0,
            "paused switch edge is consumed without changing bank");
        var heldAfterPause:Object = DrugInputService.updateSwitch(unit, true, true, root, null);
        assert(heldAfterPause == null && DrugInputService.getActiveBank() == 0,
            "held switch does not buffer across pause recovery");
        DrugInputService.updateSwitch(unit, false, true, root, null);

        unit.hp = 0;
        var dead:Object = DrugInputService.updateSwitch(unit, true, true, root, null);
        assert(dead.attempted && !dead.switched && DrugInputService.getActiveBank() == 0,
            "dead-unit switch edge is consumed without changing bank");
        unit.hp = 100;
        assert(DrugInputService.updateSwitch(unit, true, true, root, null) == null,
            "held switch does not buffer across revive");
        DrugInputService.updateSwitch(unit, false, true, root, null);

        var switched:Object = DrugInputService.updateSwitch(unit, true, true, root, null);
        assert(switched.switched && switched.cooldownStarted
            && switched.activeBank == 1 && DrugInputService.getActiveBank() == 1,
            "fresh live edge switches to bank II and starts the independent cooldown");
        assert(!ManualCooldownService.isReady(ManualCooldownService.drugSwitchKey())
            && ManualCooldownService.isReady(ManualCooldownService.drugKey(0)),
            "switch cooldown does not start or reset a potion lane cooldown");
        DrugInputService.updateSwitch(unit, false, true, root, null);
        var duringCooldown:Object = DrugInputService.updateSwitch(unit, true, true, root, null);
        assert(duringCooldown.attempted && !duringCooldown.switched,
            "switch edge during switch cooldown is consumed without toggling");
        drainQueue();
        assert(DrugInputService.updateSwitch(unit, true, true, root, null) == null
            && DrugInputService.getActiveBank() == 1,
            "held edge does not fire when switch cooldown becomes ready");
        DrugInputService.updateSwitch(unit, false, true, root, null);
        assert(DrugInputService.updateSwitch(unit, true, true, root, null).switched
            && DrugInputService.getActiveBank() == 0,
            "release and re-press switches again after cooldown completion");
    }

    private static function testLifecyclePreservesBankAndAllDrugCooldowns():Void {
        resetFixture();
        var root:Object = makeRoot();
        root.药剂组切换冷却时间 = 3000;
        var unit:Object = {hp:100};

        var switched:Object = DrugInputService.updateSwitch(
            unit, true, true, root, null);
        for (var lane:Number = 0; lane < DrugInputService.LANE_COUNT; lane++) {
            ManualCooldownService.start(
                ManualCooldownService.drugKey(lane), 3000);
        }
        DrugInputService.updateSwitch(unit, false, true, root, null);
        assert(switched.switched && DrugInputService.getActiveBank() == 1
                && allDrugCooldownsReady(false) && queue.length == 5,
            "lifecycle fixture starts in bank II with four lane cooldowns and the switch cooldown active");

        unit.hp = 0;
        var deadPress:Object = DrugInputService.updateSwitch(
            unit, true, true, root, null);
        DrugInputService.clearUnit(unit);
        unit.hp = 100;
        var heldAfterRevive:Object = DrugInputService.updateSwitch(
            unit, true, true, root, null);
        assert(deadPress.attempted && !deadPress.switched
                && heldAfterRevive == null
                && DrugInputService.getActiveBank() == 1
                && allDrugCooldownsReady(false) && queue.length == 5,
            "death clearUnit and revive preserve bank II plus all five cooldowns, and consume the invalid switch edge");
        DrugInputService.updateSwitch(unit, false, true, root, null);

        var pausedPress:Object = DrugInputService.updateSwitch(
            unit, true, false, root, null);
        var heldAfterResume:Object = DrugInputService.updateSwitch(
            unit, true, true, root, null);
        assert(pausedPress.attempted && !pausedPress.switched
                && heldAfterResume == null
                && DrugInputService.getActiveBank() == 1
                && allDrugCooldownsReady(false) && queue.length == 5,
            "pause and resume preserve bank II plus all five cooldowns, and never queue the held switch press");
        DrugInputService.updateSwitch(unit, false, true, root, null);

        var scenePress:Object = DrugInputService.updateSwitch(
            unit, true, false, root, null);
        EventBus.getInstance().publish("SceneChanged");
        EventBus.getInstance().publish("SceneReady");
        var heldAfterScene:Object = DrugInputService.updateSwitch(
            unit, true, true, root, null);
        assert(scenePress.attempted && !scenePress.switched
                && heldAfterScene == null
                && DrugInputService.getActiveBank() == 1
                && allDrugCooldownsReady(false) && queue.length == 5,
            "SceneChanged to SceneReady preserves bank II plus all five cooldowns, and consumes the transition-time edge");

        drainQueue();
        assert(allDrugCooldownsReady(true)
                && DrugInputService.updateSwitch(
                    unit, true, true, root, null) == null
                && DrugInputService.getActiveBank() == 1,
            "all five cooldown callbacks survive the scene lifecycle, while the held rejected edge stays disarmed after readiness");
    }

    private static function testPairedPhysicalSlotsShareLaneCooldown():Void {
        resetFixture();
        var root:Object = makeRoot();
        var unit:Object = {hp:100};
        var inventory:Object = makeInventory([
            {name:"I-0", value:2}, null, null, null,
            {name:"II-0", value:2}, {name:"II-1", value:2}
        ]);

        var first:Object = DrugInputService.updateSlot(unit, 0, true, true, inventory, root, null);
        assert(first.used && first.physicalSlot == 0 && first.lane == 0 && first.bank == 0,
            "bank I lane 0 consumes physical slot 0");
        var switchResult:Object = DrugInputService.updateSwitch(unit, true, true, root, null);
        assert(switchResult.switched && DrugInputService.getActiveBank() == 1,
            "bank switch is independent while a potion lane is cooling");

        var sameTick:Object = DrugInputService.updateSlot(
            unit, 0, true, false, inventory, root, null);
        var nextTickHeld:Object = DrugInputService.updateSlot(
            unit, 0, true, true, inventory, root, null);
        assert(sameTick == null && nextTickHeld == null
                && inventory.getItem("4").value == 2,
            "successful switch suppresses same-tick use and every held lane stays latched on the next tick");

        // 必须先观察松键；随后仍由共享 lane 冷却阻止 4 号槽。
        DrugInputService.updateSlot(unit, 0, false, true, inventory, root, null);
        var pairedWaiting:Object = DrugInputService.updateSlot(unit, 0, true, true, inventory, root, null);
        assert(pairedWaiting == null && inventory.getItem("4").value == 2,
            "physical slots 0 and 4 share lane-0 cooldown without consuming bank II early");

        // lane 1 与 lane 0 独立，仍可在 bank II 同帧使用。
        DrugInputService.updateSlot(unit, 1, false, true, inventory, root, null);
        var independent:Object = DrugInputService.updateSlot(unit, 1, true, true, inventory, root, null);
        assert(independent.used && independent.physicalSlot == 5
            && inventory.getItem("5").value == 1,
            "different lane remains independent inside bank II");
        drainQueue();
        var pairedReady:Object = DrugInputService.updateSlot(unit, 0, true, true, inventory, root, null);
        assert(pairedReady.used && pairedReady.physicalSlot == 4
            && inventory.getItem("4").value == 1,
            "held bank-II lane fires once when its shared cooldown becomes ready");
    }

    private static function testBankProjectionAndSessionReset():Void {
        resetFixture();
        var resetCalls:Array = [];
        var icons:Array = [];
        for (var i:Number = 0; i < 4; i++) {
            var host:Object = {itemIcon:{}};
            host.itemIcon.reset = function(collection:Object, index:Number):Void {
                resetCalls.push(index);
            };
            icons.push(host);
        }
        var switchIcon:Object = {frames:[]};
        switchIcon.gotoAndStop = function(frame:Object):Void { this.frames.push(frame); };
        var view:Object = {
            药剂图标列表:icons,
            药剂组切换图标:switchIcon,
            控制器4:{mytext:{text:""}},
            进度条4:makeRenderer()
        };
        var inventory:Object = makeInventory([]);
        var root:Object = makeRoot();
        root.keyshow = function(code:Number):String { return "KEY-" + code; };

        var delayedIcon:Object = icons[3].itemIcon;
        icons[3].itemIcon = null;
        DrugInputService.syncBankView(view, inventory);
        assert(resetCalls.length == 0
                && view.__drugProjectedBank === undefined
                && view.__drugProjectedInventory === undefined,
            "HUD waits for every persistent itemIcon before committing an atomic bank projection");
        icons[3].itemIcon = delayedIcon;
        DrugInputService.syncBankView(view, inventory);
        DrugInputService.syncSwitchView(view, 54, root);
        assert(resetCalls.join(",") == "0,1,2,3" && switchIcon.frames[0] == "I",
            "HUD retries after delayed icon initialization and binds all four bank-I slots");
        assert(view.控制器4.inputOwnedByAS === true
            && view.控制器4.mytext.text == "KEY-54"
            && view.进度条4.__manualCooldownKey == "drug:switch",
            "HUD switch controller and progress bar are display-only projections");

        var unit:Object = {hp:100};
        DrugInputService.updateSwitch(unit, true, true, root, view);
        DrugInputService.syncBankView(view, inventory);
        assert(resetCalls.join(",") == "0,1,2,3,4,5,6,7"
            && switchIcon.frames[switchIcon.frames.length - 1] == "II",
            "successful switch reuses the same four icons for bank-II physical slots");

        DrugInputService.resetSession();
        DrugInputService.syncBankView(view, inventory);
        assert(DrugInputService.getActiveBank() == 0
            && resetCalls.slice(8).join(",") == "0,1,2,3"
            && ManualCooldownService.isReady(ManualCooldownService.drugSwitchKey()),
            "session reset restores bank I, refreshes projection and clears drug-family cooldowns");
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
        var inventory:ArrayInventory = new ArrayInventory({}, 8);
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
                    && repairedIndexes.length == 1 && repairedIndexes[0] == 1
                    && root._saveExt.drugLoadout.slots[0]
                        .itemKey == "监听故障药剂"
                    && root._saveExt.drugLoadout.slots[0]
                        .lastDepletedSequence == 1,
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
                    && PlayerAssetTransaction.current() == null
                    && next.affinityCommitted
                    && root._saveExt.drugLoadout.slots[1]
                        .itemKey == "后续独立药剂"
                    && root._saveExt.drugLoadout.slots[1]
                        .lastDepletedSequence == 2
                    && root._saveExt.drugLoadout.nextDepletedSequence == 3,
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
            存档系统:{dirtyMark:false},
            _saveExt:{drugLoadout:{version:2}}
        };
        root.getItemData = function(itemName:String):Object {
            return {name:itemName, type:"消耗品", use:"药剂"};
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

    private static function allDrugCooldownsReady(expected:Boolean):Boolean {
        for (var lane:Number = 0; lane < DrugInputService.LANE_COUNT; lane++) {
            if (ManualCooldownService.isReady(
                    ManualCooldownService.drugKey(lane)) != expected) {
                return false;
            }
        }
        return ManualCooldownService.isReady(
            ManualCooldownService.drugSwitchKey()) == expected;
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
