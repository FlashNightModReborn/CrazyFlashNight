import org.flashNight.arki.scene.WaveSpawnWheel;
import org.flashNight.arki.scene.WaveSpawner;

/** Real AVM1 scheduler regression: a rejected spawn never consumes reserved work. */
class org.flashNight.arki.scene.WaveSpawnWheelTest {
    private static var passed:Number;
    private static var failed:Number;
    private static function check(value:Boolean, message:String):Void {
        if (value) passed++;
        else { failed++; trace("[FAIL] WaveSpawnWheelTest: " + message); }
    }
    private static function spawner(capacity:Number):Object {
        var result:Object = {capacity:capacity, live:0, attempts:0, created:0,
            accepted:[], seen:[], failAll:false};
        result.spawn = function(attribute, index:Number, waveIndex:Number, quantity:Number):Boolean {
            this.attempts++;
            this.seen.push({attribute:attribute, index:index, waveIndex:waveIndex, quantity:quantity});
            if (this.failAll || !(this.live < this.capacity)) return false;
            this.live++; this.created++;
            this.accepted.push(quantity);
            return true;
        };
        return result;
    }
    private static function wheel(fake:Object):WaveSpawnWheel {
        var spawnerApi:Object = org.flashNight.arki.scene.WaveSpawner;
        spawnerApi.instance = fake;
        var result:WaveSpawnWheel = WaveSpawnWheel.getInstance();
        result.init();
        return result;
    }
    public static function runAllTests():Void {
        passed = 0; failed = 0;
        var spawnerApi:Object = org.flashNight.arki.scene.WaveSpawner;
        var savedSpawner = spawnerApi.instance;
        var savedWheel:WaveSpawnWheel = WaveSpawnWheel.instance;
        WaveSpawnWheel.instance = null;
        try {
            var fake:Object = spawner(2);
            var scheduler:WaveSpawnWheel = wheel(fake);
            var attributes:Object = {Name:"CF6 A03 doorway"};
            scheduler.addTask(5, 100, 0, attributes, 0, 4);
            scheduler.minHeapTick();
            check(fake.created == 2, "A03 first frame respects capacity two");
            check(fake.attempts == 5, "first frame attempts are bounded at five");
            check(fake.seen[0].attribute === attributes && fake.seen[0].index == 0
                && fake.seen[0].waveIndex == 4, "spawn receives original identity and indices");
            check(fake.seen[2].quantity == 3 && fake.seen[4].quantity == 3,
                "three deferred enemies stay reserved during repeated rejection");
            scheduler.minHeapTick();
            check(fake.created == 2, "full doorway creates no excess enemies");
            check(fake.attempts == 10 && fake.seen[9].quantity == 3,
                "full doorway keeps retrying unchanged remaining count");
            fake.live = 1;
            scheduler.minHeapTick();
            check(fake.created == 3 && fake.live == 2, "one freed slot admits exactly one deferred enemy");
            check(fake.attempts == 15 && fake.seen[14].quantity == 2,
                "rejected attempts after refill preserve two remaining enemies");
            fake.live = 0;
            scheduler.minHeapTick();
            check(fake.created == 5 && fake.live == 2, "all five reserved enemies eventually spawn");
            check(fake.accepted.join(",") == "5,4,3,2,1", "successful remaining-count sequence has no gaps");
            check(fake.attempts == 17, "completed task stops attempts immediately");
            scheduler.minHeapTick();
            check(fake.attempts == 17, "drained task cannot spawn twice");

            fake = spawner(9); fake.failAll = true; scheduler = wheel(fake);
            scheduler.addTask(1, 100, 0, {}, 2, 3);
            scheduler.minHeapTick(); scheduler.minHeapTick();
            check(fake.created == 0 && fake.attempts == 10, "unavailable spawn remains pending across frames");
            fake.failAll = false; scheduler.minHeapTick();
            check(fake.created == 1 && fake.attempts == 11, "later availability recovers the pending task");

            fake = spawner(20); scheduler = wheel(fake);
            scheduler.addTask(7, 100, 0, {}, 0, 0);
            scheduler.minHeapTick();
            check(fake.created == 5, "successful tasks still obey the five-attempt frame budget");
            scheduler.minHeapTick();
            check(fake.created == 7 && fake.attempts == 7, "large successful task drains on its next frame");

            fake = spawner(20); scheduler = wheel(fake);
            scheduler.addTask(3, 100, 0, {name:"first"}, 0, 0);
            scheduler.addTask(4, 100, 0, {name:"second"}, 1, 0);
            scheduler.minHeapTick();
            check(fake.created == 5 && fake.seen[0].index == 1 && fake.seen[4].index == 0,
                "completed wrapper hands remaining frame budget to the previous task");
            scheduler.minHeapTick();
            check(fake.created == 7 && fake.attempts == 7, "multiple tasks drain exactly once");
        } finally {
            if (WaveSpawnWheel.instance != null) WaveSpawnWheel.instance.dispose();
            WaveSpawnWheel.instance = savedWheel;
            spawnerApi.instance = savedSpawner;
        }
        trace("WaveSpawnWheelTest Tests Passed: " + passed);
        trace("WaveSpawnWheelTest Tests Failed: " + failed);
    }
}
