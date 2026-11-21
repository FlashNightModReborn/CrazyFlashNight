import org.flashNight.arki.scene.WaveSpawner;

class org.flashNight.arki.scene.StageMControlRoomTest {
    private static var passed:Number = 0;
    private static var failed:Number = 0;

    private static function check(value:Boolean, label:String):Void {
        if (value) passed++;
        else { failed++; trace("StageMControlRoomTest FAIL: " + label); }
    }

    private static function finishesAtThreshold(threshold:Number):Number {
        var sp:WaveSpawner = WaveSpawner.getInstance();
        var finishes:Number = 0;
        var world:MovieClip = _root.createEmptyMovieClip("StageMControlRoomWorld", 30000);
        world.地图 = {僵尸型敌人总个数:0};
        sp.gameworld = world;
        sp["waveInfo"] = [[{Duration:0, FinishRequirement:threshold}], [{}]];
        sp.spawnPoints = [{NoCount:true, 僵尸型敌人总个数:0}];
        sp.currentWave = 0;
        sp.totalWave = 2;
        sp.finishRequirement = threshold;
        sp.waveTime = 0;
        sp.countDownTime = 0;
        sp.isActive = true;
        sp.isFinished = false;
        sp.finishWave = function():Void { finishes++; };
        sp.clockTick();
        sp.isActive = false;
        world.removeMovieClip();
        return finishes;
    }

    public static function runAllTests():Void {
        passed = 0; failed = 0;
        check(finishesAtThreshold(0) == 1, "empty opening finishes with the repaired threshold");
        check(finishesAtThreshold(-1) == 0, "former negative threshold reproduces the blocked opening");
        trace("StageMControlRoomTest Tests Passed: " + passed);
        trace("StageMControlRoomTest Tests Failed: " + failed);
    }
}
