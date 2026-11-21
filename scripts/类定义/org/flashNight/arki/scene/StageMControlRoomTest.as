import org.flashNight.arki.scene.WaveSpawner;
import org.flashNight.arki.scene.StageEvent;

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

    private static function finishesOnTrigger():Number {
        var sp:WaveSpawner = WaveSpawner.getInstance();
        var finishes:Number = 0;
        var world:MovieClip = _root.createEmptyMovieClip("StageMControlRoomTriggerWorld", 30010);
        _root.gameworld = world;
        world.地图 = {僵尸型敌人总个数:0};
        sp.gameworld = world;
        sp["waveInfo"] = [[{Duration:0, FinishRequirement:-1}], [{}]];
        sp.spawnPoints = [{NoCount:true, 僵尸型敌人总个数:0}];
        sp.currentWave = 0;
        sp.totalWave = 2;
        sp.finishRequirement = -1;
        sp.waveTime = 0;
        sp.countDownTime = 0;
        sp.isActive = true;
        sp.isFinished = false;
        sp.finishWave = function():Void { finishes++; };
        world.dispatcher.subscribe("ForceFinishWave", sp.forceFinishWave, sp);
        var event:StageEvent = new StageEvent({EventName:"TriggerPressed", StageProgress:"ForceFinishWave"});
        event.execute();
        sp.clockTick();
        sp.isActive = false;
        world.removeMovieClip();
        return finishes;
    }

    public static function runAllTests():Void {
        passed = 0; failed = 0;
        check(finishesOnTrigger() == 1, "gate interaction finishes the first wave");
        check(finishesAtThreshold(-1) == 0, "first wave cannot finish without interaction");
        trace("StageMControlRoomTest Tests Passed: " + passed);
        trace("StageMControlRoomTest Tests Failed: " + failed);
    }
}
