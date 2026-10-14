import org.flashNight.arki.item.*;
import org.flashNight.arki.item.itemCollection.*;
import org.flashNight.neur.Event.*;
import org.flashNight.naki.DataStructures.*;

/** Index snapshots, synchronous notifications and exact rollback use real containers. */
class org.flashNight.arki.item.itemCollection.ArrayInventoryIndexTest {
    private static var passed:Number;
    private static var failed:Number;
    private static function check(value:Boolean, label:String):Void {
        if (value) passed++; else { failed++; trace("[FAIL] ArrayInventoryIndexTest " + label); }
    }
    private static function item(name:String, value:Number):BaseItem {
        return new BaseItem(name, value, 1);
    }
    private static function throwAt(phase:String):Function {
        return function(current:String):Void { if (current == phase) throw "index-test/" + phase; };
    }
    private static function snapshots():Void {
        var bag:ArrayInventory = new ArrayInventory(null, 50);
        var alpha:BaseItem = item("Alpha", 2);
        var beta:BaseItem = item("Beta", 3);
        bag.add(3, beta); bag.add(0, alpha);
        var snapshot:Array = bag.getIndexes();
        snapshot[0] = 49; snapshot.push(48);
        check(bag.getIndexes().join(",") == "0,3", "returned index arrays cannot poison future queries");
        var slots:Object = bag.getItems();
        delete slots[0]; slots[1] = item("Gamma", 1);
        check(bag.getItem("0") === alpha && bag.getItem("1") == null && bag.size() == 2,
            "returned slot map cannot add or delete authoritative membership");
        check(slots[3] === beta && bag.getItems()[0] === alpha, "slot snapshots preserve item object identity");
        var tree:TreeSet = bag.getTreeSet();
        tree.remove(0); tree.add(1);
        check(bag.getIndexes().join(",") == "0,3" && bag.getFirstVacancy() == 1,
            "returned TreeSet is a detached compatibility view");
        bag.setIndexes(tree);
        check(bag.getIndexes().join(",") == "0,3" && bag.size() == 2,
            "legacy setIndexes repairs from authoritative slots");
        check(bag.searchFirstKey("Alpha") == "0" && bag.getVacancies(2).join(",") == "1,2",
            "lowest-slot selection and ordered vacancies remain compatible");
        check(bag.getVacancies(0).length == 0 && bag.getVacancies(-1).length == 0,
            "nonpositive vacancy requests remain empty");
        check(bag.getVacancies(NaN).length == 16 && bag.getVacancies(1.5).length == 2,
            "default and fractional vacancy request behavior remains compatible");
        var before:Number = bag.getMutationRevision();
        check(!bag.add(0, alpha) && !bag.add(50, alpha) && bag.getMutationRevision() == before,
            "rejected writes do not change revision");
        bag.add(49, item("Gamma", 4));
        check(bag.getIndexes().join(",") == "0,3,49" && bag.findIndex(function(value:Object):Boolean {
            return value.name == "Gamma";
        }) == 49, "high-slot insertion refreshes ordered query state");
        bag.remove(3);
        check(bag.getIndexes().join(",") == "0,49" && bag.size() == 2, "removal refreshes count and snapshot");
        bag.capacity = 3;
        check(bag.getIndexes().join(",") == "0" && bag.size() == 1, "capacity changes invalidate cached physical membership");
    }
    private static function notifications():Void {
        var bag:ArrayInventory = new ArrayInventory(null, 50);
        var holder:MovieClip = _root.createEmptyMovieClip("__arrayIndexEvents", 9201);
        var dispatcher:LifecycleEventDispatcher = new LifecycleEventDispatcher(holder);
        var spy:Object = dispatcher;
        var events:Array = [];
        spy.publish = function(kind:String, source:Object, key:String):Void {
            events.push(kind + ":" + key);
            if (kind == "ItemAdded" && key == "0") {
                org.flashNight.arki.item.itemCollection.ArrayInventoryIndexTest.check(
                    source.size() == 1 && source.getIndexes().join(",") == "0"
                    && source.getFirstVacancy() == 1 && source.searchFirstKey("Alpha") == "0",
                    "ItemAdded sees complete slot, count and ordered query state");
                source.add(-1, new BaseItem("Beta", 1, 1));
            }
        };
        bag.setDispatcher(dispatcher);
        check(bag.add(0, item("Alpha", 1)) && bag.getIndexes().join(",") == "0,1"
            && events.join(",") == "ItemAdded:0,ItemAdded:1", "synchronous nested add picks the next true vacancy");
        spy.publish = function(kind:String, source:Object, key:String):Void {
            org.flashNight.arki.item.itemCollection.ArrayInventoryIndexTest.check(
                source.size() == 1 && source.getIndexes().join(",") == "1" && source.getFirstVacancy() == 0,
                "ItemRemoved sees the complete resulting index state");
        };
        bag.remove(0);
        var before:Number = bag.getMutationRevision();
        spy.publish = function():Void { throw "index-test/observer"; };
        var caught:Boolean = false;
        try { bag.add(0, item("Gamma", 1)); } catch (error) { caught = true; }
        check(caught && bag.getItem("0").name == "Gamma" && bag.size() == 2
            && bag.getIndexes().join(",") == "0,1" && bag.getMutationRevision() > before,
            "observer failure propagates after the authoritative write and derived state are complete");
        before = bag.getMutationRevision(); caught = false;
        try { bag.remove(0); } catch (error) { caught = true; }
        check(caught && bag.getItem("0") == null && bag.getIndexes().join(",") == "1"
            && bag.size() == 1 && bag.getMutationRevision() > before,
            "observer failure after remove cannot leave a stale count or occupied index");
        bag.setDispatcher(null); holder.removeMovieClip();
    }
    private static function transactions():Void {
        var bag:ArrayInventory = new ArrayInventory(null, 50);
        var alpha:BaseItem = item("Alpha", 2); var beta:BaseItem = item("Beta", 3);
        bag.add(0, alpha); bag.add(3, beta); bag.getIndexes();
        var before:Number = bag.getMutationRevision();
        var builds:Number = bag._getIndexRebuildCountForTests();
        var gamma:BaseItem = item("Gamma", 1);
        var receipt:Object = bag.transactionApplySlotChangesWithReceipt([
            {slot:0, expectedItem:alpha, item:null}, {slot:1, expectedItem:null, item:gamma}]);
        check(receipt.success && bag.getIndexes().join(",") == "1,3" && bag.size() == 2
            && bag.getMutationRevision() == before + 1 && bag._getIndexRebuildCountForTests() == builds + 1,
            "one batch publishes one coherent structural snapshot and rebuild");
        check(bag.rollbackSlotTransaction(receipt) && bag.getItem("0") === alpha && bag.getItem("1") == null
            && bag.getIndexes().join(",") == "0,3" && bag.getMutationRevision() == before,
            "slot receipt rollback restores references, cached indexes and exact revision");
        var phases:Array = ["mutation", "rebuildIndexes", "bumpRevision"];
        for (var i:Number = 0; i < phases.length; i++) {
            bag._setTransactionWriteFaultHookForTests(throwAt(phases[i]));
            check(!bag.transactionWrite(2, gamma), "single-write fault returns false at " + phases[i]);
            check(bag.getItem("0") === alpha && bag.getItem("2") == null && bag.size() == 2
                && bag.getIndexes().join(",") == "0,3" && bag.getFirstVacancy() == 1
                && bag.getMutationRevision() == before, "single-write fault restores warm cache at " + phases[i]);
        }
        bag._setTransactionWriteFaultHookForTests(null);
        var beforeValue:Object = {level:2, mods:[]};
        alpha.value = beforeValue;
        var values:Object = bag.transactionApplyValueChangesWithReceipt([
            {slot:0, expectedItem:alpha, expectedValue:beforeValue, expectedLastUpdate:1,
                value:{level:7, mods:[]}, lastUpdate:9}]);
        check(values.success && alpha.value.level == 7 && bag.getIndexes().join(",") == "0,3", "equipment value updates preserve membership snapshots");
        check(bag.rollbackValueTransaction(values) && alpha.value === beforeValue && alpha.lastUpdate == 1
            && bag.getMutationRevision() == before, "value rollback restores the exact before state");
        var box:ArrayInventory = new ArrayInventory(null, 400);
        box.add(0, alpha); box.add(399, beta);
        check(box.transactionReplacePrefix([gamma], 40) && box.getItem("0") === gamma
            && box.getItem("399") === beta && box.getIndexes().join(",") == "0,399",
            "locked tail survives prefix replacement and cache rebuild");
        var saved:Object = {};
        saved[0] = {name:"Alpha", value:2, lastUpdate:1};
        saved[75] = {name:"Beta", value:3, lastUpdate:1};
        bag.setItems(saved);
        check(bag.getIndexes().join(",") == "0" && bag.toObject()[75].name == "Beta",
            "out-of-capacity saved records remain serialized without joining physical indexes");
    }
    private static function callbackSnapshots():Void {
        var bag:ArrayInventory = new ArrayInventory(null, 50);
        bag.add(0, item("Alpha", 1)); bag.add(3, item("Beta", 1));
        var result:Object = bag.find(function(value:Object):Boolean {
            if (value.name == "Alpha") bag.add(1, new BaseItem("Gamma", 1, 1));
            return value.name == "Gamma";
        });
        check(result == null && bag.searchFirstKey("Gamma") == "1", "find keeps its entry index snapshot during callback writes");
        var before:Number = bag.getMutationRevision();
        bag.rebuildOrder(function(a:Object, b:Object):Number { return a.name < b.name ? 1 : a.name > b.name ? -1 : 0; });
        check(bag.getIndexes().join(",") == "0,1,2" && bag.getItem("0").name == "Gamma"
            && bag.getMutationRevision() > before, "sorting advances revision and refreshes all physical indexes");
    }
    public static function runAllTests():Void {
        passed = 0; failed = 0;
        ItemUtil.itemDataDict = {Alpha:{name:"Alpha"}, Beta:{name:"Beta"}, Gamma:{name:"Gamma"}};
        ItemUtil.equipmentDict = {}; ItemUtil.materialDict = {}; ItemUtil.informationMaxValueDict = {};
        snapshots(); notifications(); transactions(); callbackSnapshots();
        trace("ArrayInventoryIndexTest Tests Passed: " + passed);
        trace("ArrayInventoryIndexTest Tests Failed: " + failed);
    }
}
