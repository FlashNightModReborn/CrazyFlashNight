import org.flashNight.arki.item.itemCollection.EquipmentInventory;
import org.flashNight.neur.Event.LifecycleEventDispatcher;

/** B0：EquipmentInventory 原始写版本、无事件事务与兼容事件回归。 */
class org.flashNight.arki.item.itemCollection.EquipmentInventoryTest {
    private static var _passed:Number = 0;
    private static var _failed:Number = 0;
    private static var _previousGetItemData:Function;
    private static var _slotKeys:Array = [
        "头部装备", "上装装备", "下装装备", "手部装备", "脚部装备", "颈部装备",
        "长枪", "手枪", "手枪2", "刀", "手雷"
    ];

    public static function runAllTests():Void {
        _passed = 0;
        _failed = 0;
        trace("=== EquipmentInventoryTest start ===");

        installItemDataFixture();
        testTransactionWhitelistAndNoOp();
        testOrdinaryMutationRevisionAndEvents();
        testTransactionEventBoundary();
        testWornValueTransactionAtomicity();
        restoreItemDataFixture();

        trace("EquipmentInventoryTest Tests Passed: " + _passed);
        trace("EquipmentInventoryTest Tests Failed: " + _failed);
        trace("=== EquipmentInventoryTest end ===");
    }

    private static function assertTrue(condition:Boolean, message:String):Void {
        if (condition) {
            _passed++;
            trace("[PASS] " + message);
        } else {
            _failed++;
            trace("[FAIL] " + message);
        }
    }

    private static function installItemDataFixture():Void {
        _previousGetItemData = _root.getItemData;
        var fixture:Object = {};
        for (var i:Number = 0; i < _slotKeys.length; i++) {
            var key:String = String(_slotKeys[i]);
            fixture[itemNameForSlot(key)] = {use:key == "手枪2" ? "手枪" : key};
        }
        fixture["EquipmentInventoryTest/非法槽"] = {use:"非法槽"};
        _root.__equipmentInventoryTestData = fixture;
        _root.getItemData = function(name):Object {
            return _root.__equipmentInventoryTestData[String(name)];
        };
    }

    private static function restoreItemDataFixture():Void {
        if (_previousGetItemData == undefined) delete _root.getItemData;
        else _root.getItemData = _previousGetItemData;
        delete _root.__equipmentInventoryTestData;
    }

    private static function itemNameForSlot(key:String):String {
        return "EquipmentInventoryTest/" + key;
    }

    private static function itemForSlot(key:String, marker:Number):Object {
        return {
            name:itemNameForSlot(key),
            value:key == "手雷" ? 3 : {level:marker, mods:[]},
            lastUpdate:marker
        };
    }

    private static function testTransactionWhitelistAndNoOp():Void {
        var inventory:EquipmentInventory = new EquipmentInventory(null);
        var initialRevision:Number = inventory.getMutationRevision();
        var allSupported:Boolean = true;
        var refs:Object = {};
        for (var i:Number = 0; i < _slotKeys.length; i++) {
            var key:String = String(_slotKeys[i]);
            var item:Object = itemForSlot(key, i + 1);
            refs[key] = item;
            allSupported = inventory.transactionWrite(key, item) && allSupported;
        }
        assertTrue(allSupported
                && inventory.getMutationRevision() == initialRevision + _slotKeys.length,
            "transactionWrite 接受精确 11 槽并逐次推进原始版本");

        var beforeInvalid:Number = inventory.getMutationRevision();
        var invalidItem:Object = {
            name:"EquipmentInventoryTest/非法槽",
            value:{level:1, mods:[]},
            lastUpdate:1
        };
        var invalid:Boolean = inventory.transactionWrite("非法槽", invalidItem);
        assertTrue(!invalid && inventory.getMutationRevision() == beforeInvalid
                && inventory.getItem("非法槽") == null,
            "transactionWrite 拒绝白名单外键且不推进版本");

        var beforeMismatch:Number = inventory.getMutationRevision();
        var mismatched:Object = itemForSlot("手枪", 99);
        var mismatch:Boolean = inventory.transactionWrite("头部装备", mismatched);
        assertTrue(!mismatch && inventory.getMutationRevision() == beforeMismatch
                && inventory.getItem("头部装备") === refs["头部装备"],
            "transactionWrite 复用 use 校验并拒绝不匹配装备");

        var corruptSameRef:Object = refs["头部装备"];
        var validName:String = String(corruptSameRef.name);
        corruptSameRef.name = itemNameForSlot("手枪");
        var beforeCorruptSameRef:Number = inventory.getMutationRevision();
        var corruptSameRefResult:Boolean = inventory.transactionWrite(
            "头部装备", corruptSameRef);
        assertTrue(!corruptSameRefResult
                && inventory.getMutationRevision() == beforeCorruptSameRef
                && inventory.getItem("头部装备") === corruptSameRef,
            "同引用 no-op 之前仍严格复核 use，拒绝既有损坏槽");
        corruptSameRef.name = validName;

        var removed:Boolean = inventory.transactionWrite("脚部装备", null);
        var afterRemove:Number = inventory.getMutationRevision();
        var sameRef:Boolean = inventory.transactionWrite("头部装备", refs["头部装备"]);
        var emptyNoOp:Boolean = inventory.transactionWrite("脚部装备", null);
        assertTrue(removed && sameRef && emptyNoOp
                && inventory.getMutationRevision() == afterRemove,
            "相同引用写与空槽清空是无副作用 no-op");
    }

    private static function testOrdinaryMutationRevisionAndEvents():Void {
        var inventory:EquipmentInventory = new EquipmentInventory(null);
        var holder:MovieClip = _root.createEmptyMovieClip(
            "__equipmentInventoryRevisionTest", _root.getNextHighestDepth());
        var dispatcher:LifecycleEventDispatcher = new LifecycleEventDispatcher(holder);
        inventory.setDispatcher(dispatcher);

        var addCount:Number = 0;
        var removeCount:Number = 0;
        var valueCount:Number = 0;
        var addEventRevision:Number = -1;
        var removeEventRevision:Number = -1;
        var valueEventRevision:Number = -1;
        var lastEventKey:String = "";
        dispatcher.subscribe("ItemAdded", function(source:Object, key:String):Void {
            addCount++;
            addEventRevision = inventory.getMutationRevision();
            lastEventKey = key;
        });
        dispatcher.subscribe("ItemRemoved", function(source:Object, key:String):Void {
            removeCount++;
            removeEventRevision = inventory.getMutationRevision();
            lastEventKey = key;
        });
        dispatcher.subscribe("ItemValueChanged", function(source:Object, key:String):Void {
            valueCount++;
            valueEventRevision = inventory.getMutationRevision();
            lastEventKey = key;
        });

        var head:Object = itemForSlot("头部装备", 1);
        var v0:Number = inventory.getMutationRevision();
        var addedHead:Boolean = inventory.add("头部装备", head);
        var v1:Number = inventory.getMutationRevision();
        assertTrue(addedHead && v1 > v0 && addCount == 1
                && addEventRevision == v1 && lastEventKey == "头部装备",
            "普通 add 在同步 ItemAdded 前推进版本");

        var failedAdd:Boolean = inventory.add("头部装备", itemForSlot("头部装备", 2));
        assertTrue(!failedAdd && inventory.getMutationRevision() == v1 && addCount == 1,
            "占用槽 add 失败不推进版本也不派发事件");

        var grenade:Object = itemForSlot("手雷", 1);
        var addedGrenade:Boolean = inventory.add("手雷", grenade);
        var v2:Number = inventory.getMutationRevision();
        assertTrue(addedGrenade && v2 > v1 && addCount == 2
                && addEventRevision == v2 && lastEventKey == "手雷",
            "数量型手雷普通 add 也在事件前推进版本");

        inventory.addValue("手雷", -1);
        var v3:Number = inventory.getMutationRevision();
        assertTrue(grenade.value == 2 && v3 > v2 && valueCount == 1
                && valueEventRevision == v3 && lastEventKey == "手雷",
            "手雷 addValue 在同步 ItemValueChanged 前推进版本");

        inventory.addValue("手雷", 0);
        inventory.addValue("头部装备", 1);
        assertTrue(inventory.getMutationRevision() == v3 && valueCount == 1,
            "零增量和装备对象 addValue 是无副作用 no-op");

        grenade.value -= 1;
        assertTrue(grenade.value == 1 && inventory.getMutationRevision() == v3,
            "手雷直接字段扣量绕过容器版本，留给上层语义签名观察");

        inventory.remove("头部装备");
        var v4:Number = inventory.getMutationRevision();
        assertTrue(inventory.getItem("头部装备") == null && v4 > v3
                && removeCount == 1 && removeEventRevision == v4
                && lastEventKey == "头部装备",
            "普通 remove 在同步 ItemRemoved 前推进版本");

        inventory.remove("头部装备");
        assertTrue(inventory.getMutationRevision() == v4 && removeCount == 1,
            "空槽 remove 不推进版本也不派发事件");

        inventory.addValue("手雷", -1);
        var v5:Number = inventory.getMutationRevision();
        assertTrue(inventory.getItem("手雷") == null && v5 > v4
                && removeCount == 2 && removeEventRevision == v5
                && lastEventKey == "手雷",
            "手雷耗尽删除推进版本且移除事件观察到最终版本");

        inventory.add("脚部装备", itemForSlot("脚部装备", 1));
        var addCountBeforeSet:Number = addCount;
        var removeCountBeforeSet:Number = removeCount;
        var beforeSet:Number = inventory.getMutationRevision();
        inventory.setItems({});
        assertTrue(inventory.getItem("脚部装备") == null
                && inventory.getMutationRevision() > beforeSet
                && addCount == addCountBeforeSet && removeCount == removeCountBeforeSet,
            "setItems 整体替换推进版本但不伪造单槽生命周期事件");

        inventory.setDispatcher(null);
        holder.removeMovieClip();
    }

    private static function testTransactionEventBoundary():Void {
        var inventory:EquipmentInventory = new EquipmentInventory(null);
        var holder:MovieClip = _root.createEmptyMovieClip(
            "__equipmentInventoryTransactionTest", _root.getNextHighestDepth());
        var dispatcher:LifecycleEventDispatcher = new LifecycleEventDispatcher(holder);
        inventory.setDispatcher(dispatcher);

        var addCount:Number = 0;
        var removeCount:Number = 0;
        var valueCount:Number = 0;
        var eventOrder:String = "";
        var allEventsSawCurrent:Boolean = true;
        var expectedCurrent:Object = null;
        var lastEventRevision:Number = -1;
        dispatcher.subscribe("ItemAdded", function(source:Object, key:String):Void {
            addCount++;
            eventOrder += "A";
            allEventsSawCurrent = allEventsSawCurrent
                && inventory.getItem(key) === expectedCurrent;
            lastEventRevision = inventory.getMutationRevision();
        });
        dispatcher.subscribe("ItemRemoved", function(source:Object, key:String):Void {
            removeCount++;
            eventOrder += "R";
            allEventsSawCurrent = allEventsSawCurrent
                && inventory.getItem(key) === expectedCurrent;
            lastEventRevision = inventory.getMutationRevision();
        });
        dispatcher.subscribe("ItemValueChanged", function(source:Object, key:String):Void {
            valueCount++;
            eventOrder += "V";
            allEventsSawCurrent = allEventsSawCurrent
                && inventory.getItem(key) === expectedCurrent;
            lastEventRevision = inventory.getMutationRevision();
        });

        var first:Object = itemForSlot("上装装备", 1);
        var v0:Number = inventory.getMutationRevision();
        expectedCurrent = first;
        var wroteFirst:Boolean = inventory.transactionWrite("上装装备", first);
        var v1:Number = inventory.getMutationRevision();
        assertTrue(wroteFirst && v1 > v0 && addCount == 0
                && removeCount == 0 && valueCount == 0,
            "transactionWrite 写入并推进版本但不派发事件");

        inventory.publishTransactionChange("上装装备", "added");
        assertTrue(addCount == 1 && eventOrder == "A"
                && allEventsSawCurrent && lastEventRevision == v1,
            "显式 publish added 在提交后派发并暴露最终引用/版本");

        var second:Object = itemForSlot("上装装备", 2);
        eventOrder = "";
        expectedCurrent = second;
        var wroteSecond:Boolean = inventory.transactionWrite("上装装备", second);
        var v2:Number = inventory.getMutationRevision();
        assertTrue(wroteSecond && v2 > v1 && addCount == 1 && removeCount == 0,
            "transaction replacement 在 publish 前保持事件静默");

        inventory.publishTransactionChange("上装装备", "replaced");
        assertTrue(eventOrder == "RA" && removeCount == 1 && addCount == 2
                && allEventsSawCurrent && lastEventRevision == v2,
            "replaced 统一按 removed→added 派发且监听器不见半提交");

        eventOrder = "";
        expectedCurrent = null;
        var removed:Boolean = inventory.transactionWrite("上装装备", null);
        var v3:Number = inventory.getMutationRevision();
        assertTrue(removed && v3 > v2 && eventOrder == ""
                && inventory.getItem("上装装备") == null,
            "transaction removal 在 publish 前保持事件静默");
        inventory.publishTransactionChange("上装装备", "removed");
        assertTrue(eventOrder == "R" && removeCount == 2
                && allEventsSawCurrent && lastEventRevision == v3,
            "显式 publish removed 只在提交后派发");

        var grenade:Object = itemForSlot("手雷", 1);
        inventory.transactionWrite("手雷", grenade);
        expectedCurrent = grenade;
        eventOrder = "";
        var valueRevision:Number = inventory.getMutationRevision();
        inventory.publishTransactionChange("手雷", "value");
        assertTrue(eventOrder == "V" && valueCount == 1
                && allEventsSawCurrent && lastEventRevision == valueRevision,
            "显式 publish value 复用兼容 ItemValueChanged 事件");

        var eventOrderBeforeInvalid:String = eventOrder;
        inventory.publishTransactionChange("非法槽", "added");
        assertTrue(eventOrder == eventOrderBeforeInvalid,
            "白名单外 publish 被忽略且不泄漏生命周期事件");

        inventory.setDispatcher(null);
        holder.removeMovieClip();
    }

    private static function testWornValueTransactionAtomicity():Void {
        var inventory:EquipmentInventory =
            new EquipmentInventory(null);
        var item:Object = itemForSlot("手枪", 1);
        inventory.add("手枪", item);
        var holder:MovieClip = _root.createEmptyMovieClip(
            "__equipmentInventoryWornValueTest",
            _root.getNextHighestDepth());
        var dispatcher:LifecycleEventDispatcher =
            new LifecycleEventDispatcher(holder);
        inventory.setDispatcher(dispatcher);
        var valueEvents:Number = 0;
        var eventSawFinal:Boolean = false;
        dispatcher.subscribe("ItemValueChanged",
            function(source:Object, key:String):Void {
                valueEvents++;
                eventSawFinal = key == "手枪"
                    && item.value.level == 2
                    && item.lastUpdate == 20;
            });

        var beforeRevision:Number =
            inventory.getMutationRevision();
        var beforeValue:Object = item.value;
        var stale:Array = [{
            slot:"手枪",
            expectedItem:item,
            expectedValue:{level:1, mods:[]},
            expectedLastUpdate:item.lastUpdate,
            value:{level:2, mods:[]},
            lastUpdate:20
        }];
        assertTrue(!inventory.canApplyWornValueTransaction(stale)
                && inventory.transactionApplyWornValueChanges(
                    stale).success !== true
                && item.value === beforeValue
                && inventory.getMutationRevision()
                    == beforeRevision,
            "worn value 预检要求 exact item/value/lastUpdate 且失败零写");

        var changes:Array = [{
            slot:"手枪",
            expectedItem:item,
            expectedValue:beforeValue,
            expectedLastUpdate:item.lastUpdate,
            value:{level:2, mods:[]},
            lastUpdate:20
        }];
        var committed:Object =
            inventory.transactionApplyWornValueChanges(changes);
        assertTrue(committed.success
                && item.value === changes[0].value
                && item.lastUpdate == 20
                && inventory.getMutationRevision()
                    == beforeRevision + 1
                && valueEvents == 0,
            "worn value 单 batch 原位写且 raw revision 精确推进一次、提交前零事件");

        inventory.publishWornValueTransaction(committed);
        assertTrue(valueEvents == 1 && eventSawFinal,
            "worn value 只在完整提交后统一发布唯一最终态事件");

        var committedValue:Object = item.value;
        var committedRevision:Number =
            inventory.getMutationRevision();
        var rollbackChanges:Array = [{
            slot:"手枪",
            expectedItem:item,
            expectedValue:committedValue,
            expectedLastUpdate:item.lastUpdate,
            value:{level:3, mods:[]},
            lastUpdate:30
        }];
        var rollbackReceipt:Object =
            inventory.transactionApplyWornValueChanges(
                rollbackChanges);
        var rolledBack:Boolean =
            inventory.rollbackWornValueTransaction(
                rollbackReceipt);
        assertTrue(rolledBack
                && item.value === committedValue
                && item.lastUpdate == 20
                && inventory.getMutationRevision()
                    == committedRevision
                && valueEvents == 1,
            "worn value rollback 完整恢复 value/lastUpdate/raw revision 且不派发事件");

        var laterReceipt:Object =
            inventory.transactionApplyWornValueChanges(
                rollbackChanges);
        item.lastUpdate = 31;
        var rejectedRollback:Boolean =
            inventory.rollbackWornValueTransaction(
                laterReceipt);
        assertTrue(!rejectedRollback
                && item.value === rollbackChanges[0].value
                && item.lastUpdate == 31,
            "worn rollback 遇到后来状态时 fail-closed，不做部分恢复");

        inventory.setDispatcher(null);
        holder.removeMovieClip();
    }
}
