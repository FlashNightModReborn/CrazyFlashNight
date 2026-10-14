import org.flashNight.arki.item.*;
import org.flashNight.arki.item.itemCollection.*;

/** Real AVM1 experiment; isolated memory inventories, one bounded scenario per frame. */
class org.flashNight.dev.ArrayInventoryQueryBenchmark {
    private static var completion:Function;
    private static var jobs:Array;
    private static var nextJob:Number;
    private static var passed:Number;
    private static var failed:Number;
    private static var tickClip:MovieClip;
    private static var sink;
    public static function setCompletion(callback:Function):Void {
        completion = callback;
    }
    private static function matchLast(item:Object):Boolean {
        return item.name == "last";
    }
    private static function check(value:Boolean, label:String):Void {
        if (value) passed++;
        else { failed++; trace("[FAIL] ArrayInventoryQueryBenchmark " + label); }
    }
    private static function seed(capacity:Number, state:String):Object {
        var result:Object = {};
        var positions:Array = [];
        var count:Number = Math.max(2, Math.floor(capacity / 10));
        var slot:Number;
        if (state == "sparse-prefix") {
            for (slot = 0; slot < count; slot++) positions.push(slot);
        } else if (state == "sparse-tail") {
            for (slot = capacity - count; slot < capacity; slot++) positions.push(slot);
        } else if (state == "half") {
            for (slot = 0; slot < capacity; slot += 2) positions.push(slot);
        } else if (state == "full") {
            for (slot = 0; slot < capacity; slot++) positions.push(slot);
        }
        for (var i:Number = 0; i < positions.length; i++) {
            var name:String = i == 0 ? "first" : i == positions.length - 1 ? "last" : "fill";
            result[String(positions[i])] = {name:name, value:i + 1, lastUpdate:1};
        }
        return result;
    }
    private static function signature(inv:Object, operation:Number):String {
        if (operation == 0) return String(inv.searchFirstKey("first"));
        if (operation == 1 || operation == 9) return String(inv.searchFirstKey("last"));
        if (operation == 2) return String(inv.searchFirstKey("absent"));
        if (operation == 3) return String(inv.getFirstVacancy());
        if (operation == 4) return inv.getVacancies(16).join(",");
        if (operation == 5) {
            var item:Object = inv.find(matchLast);
            return item == null ? "null" : item.name + ":" + item.value;
        }
        if (operation == 6) return String(inv.findIndex(matchLast));
        if (operation == 7) return inv.getIndexes().join(",");
        var values:Array = inv.getItemArray();
        var result:String = "";
        for (var i:Number = 0; i < values.length; i++) result += values[i].name + ":" + values[i].value + "|";
        return result;
    }
    private static function measure(inv:Object, operation:Number, iterations:Number):Number {
        var i:Number;
        var result;
        var predicate:Function = matchLast;
        var firstItem:Object = inv.getItem("0");
        var start:Number = getTimer();
        if (operation == 0) {
            for (i = 0; i < iterations; i++) result = inv.searchFirstKey("first");
        } else if (operation == 1) {
            for (i = 0; i < iterations; i++) result = inv.searchFirstKey("last");
        } else if (operation == 2) {
            for (i = 0; i < iterations; i++) result = inv.searchFirstKey("absent");
        } else if (operation == 3) {
            for (i = 0; i < iterations; i++) result = inv.getFirstVacancy();
        } else if (operation == 4) {
            for (i = 0; i < iterations; i++) result = inv.getVacancies(16);
        } else if (operation == 5) {
            for (i = 0; i < iterations; i++) result = inv.find(predicate);
        } else if (operation == 6) {
            for (i = 0; i < iterations; i++) result = inv.findIndex(predicate);
        } else if (operation == 7) {
            for (i = 0; i < iterations; i++) result = inv.getIndexes();
        } else if (operation == 8) {
            for (i = 0; i < iterations; i++) result = inv.getItemArray();
        } else {
            for (i = 0; i < iterations; i++) {
                inv.remove(0);
                inv.add(0, firstItem);
                result = inv.searchFirstKey("last");
            }
        }
        var elapsed:Number = getTimer() - start;
        sink = result;
        return elapsed;
    }
    private static function calibrate(inv:Object, operation:Number):Number {
        var iterations:Number = 64;
        while (iterations < 131072) {
            if (measure(inv, operation, iterations) >= 25) return iterations;
            iterations *= 2;
        }
        return iterations;
    }
    private static function runJob(job:Object):Void {
        var initial:Object = seed(job.capacity, job.state);
        var variants:Array = [
            new org.flashNight.dev.ArrayInventoryTreeBaseline(null, job.capacity),
            new org.flashNight.dev.ArrayInventoryLinearProbe(null, job.capacity),
            new org.flashNight.dev.ArrayInventoryCachedProbe(null, job.capacity),
            new org.flashNight.dev.ArrayInventoryIncrementalProbe(null, job.capacity)
        ];
        var candidate:Number;
        for (var key:String in initial) {
            var seedItem:Object = initial[key];
            for (candidate = 0; candidate < variants.length; candidate++) {
                var seededItem:Object = new BaseItem(seedItem.name, seedItem.value, 1);
                if (!variants[candidate].add(Number(key), seededItem)) {
                    throw "identical API seed failed at " + key + "/" + candidate
                        + " capacity=" + variants[candidate].capacity
                        + " empty=" + variants[candidate].isEmpty(Number(key))
                        + " addable=" + variants[candidate].isAddable(key, seededItem)
                        + " name=" + seededItem.name + " value=" + seededItem.value
                        + " current=" + variants[candidate].getItem(key);
                }
            }
        }
        var names:Array = ["baseline", "linear", "cached", "optimized"];
        var expected:String = signature(variants[0], job.operation);
        var iterations:Array = [];
        var samples:Array = [[], [], [], []];
        var revisions:Array = [];
        var failuresBefore:Number = failed;
        for (candidate = 0; candidate < variants.length; candidate++) {
            var actual:String = signature(variants[candidate], job.operation);
            if (candidate > 0) check(actual == expected,
                job.capacity + "/" + job.state + "/" + job.operation + "/" + names[candidate]
                + " expected=" + expected.substr(0, 160) + " actual=" + actual.substr(0, 160));
            if (failed != failuresBefore) throw "pre-measure semantic mismatch";
            measure(variants[candidate], job.operation, 32);
            iterations[candidate] = calibrate(variants[candidate], job.operation);
            revisions[candidate] = variants[candidate].getMutationRevision();
        }
        for (var round:Number = 0; round < 5; round++) {
            for (var offset:Number = 0; offset < variants.length; offset++) {
                candidate = (round + offset + nextJob) % variants.length;
                samples[candidate].push(measure(variants[candidate], job.operation, iterations[candidate]));
            }
        }
        for (candidate = 0; candidate < variants.length; candidate++) {
            var medianSamples:Array = samples[candidate].concat();
            medianSamples.sort(Array.NUMERIC);
            var us:Number = medianSamples[2] * 1000 / iterations[candidate];
            trace("ArrayInventoryBenchRow|" + job.capacity + "|" + job.state + "|" + job.operation
                + "|" + names[candidate] + "|" + iterations[candidate]
                + "|" + samples[candidate].join(",") + "|" + us);
            check(job.operation == 9 || variants[candidate].getMutationRevision() == revisions[candidate],
                "read changed revision " + names[candidate]);
            check(signature(variants[candidate], job.operation) == expected,
                "post-measure result " + names[candidate]);
        }
    }
    private static function finish():Void {
        delete tickClip.onEnterFrame;
        tickClip.removeMovieClip();
        trace("ArrayInventoryQueryBenchmark rows=" + nextJob + " passed=" + passed + " failed=" + failed);
        completion();
    }
    public static function tick():Void {
        if (nextJob >= jobs.length) { finish(); return; }
        try {
            runJob(jobs[nextJob]);
            nextJob++;
        } catch (error) {
            failed++;
            trace("[FAIL] ArrayInventoryQueryBenchmark exception: " + error);
            finish();
        }
    }
    public static function runAllTests():Void {
        passed = 0; failed = 0; nextJob = 0; jobs = [];
        ItemUtil.itemDataDict = {first:{name:"first"}, last:{name:"last"}, fill:{name:"fill"}};
        ItemUtil.equipmentDict = {}; ItemUtil.materialDict = {}; ItemUtil.informationMaxValueDict = {};
        var capacities:Array = [8, 50, 400, 1200];
        var states:Array = ["empty", "sparse-prefix", "sparse-tail", "half", "full"];
        for (var c:Number = 0; c < capacities.length; c++) {
            for (var s:Number = 0; s < states.length; s++) {
                for (var op:Number = 0; op < 9; op++) {
                    jobs.push({capacity:capacities[c], state:states[s], operation:op});
                }
            }
            jobs.push({capacity:capacities[c], state:"full", operation:9});
        }
        trace("ArrayInventoryBenchmarkProtocol|v1|rounds=5|window_ms=25|warmup=32|independent_calibration=true|rotated_order=true|writes_in_query_probes=baseline");
        tickClip = _root.createEmptyMovieClip("__arrayInventoryBenchmark", 9100);
        tickClip.onEnterFrame = function():Void { org.flashNight.dev.ArrayInventoryQueryBenchmark.tick(); };
    }
}
