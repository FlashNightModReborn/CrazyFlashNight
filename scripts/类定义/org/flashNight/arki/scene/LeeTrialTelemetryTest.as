import org.flashNight.arki.scene.LeeTrialTelemetry;

/** 内存观测运算回归；不修改角色，也不读写存档。 */
class org.flashNight.arki.scene.LeeTrialTelemetryTest {
    public static function runAllTests():Void {
        var room:Object = {entryMs:100, endHp:1000, minHp:1000, elapsedMs:0,
            observedHpLoss:0, observedHpGain:0, samples:0};
        var passed:Number = 0;
        var failed:Number = 0;
        LeeTrialTelemetry.observe(room, 700, 1100);
        if (room.endHp == 700 && room.minHp == 700 && room.observedHpLoss == 300
                && room.observedHpGain == 0 && room.elapsedMs == 1000) passed++;
        else { failed++; trace("FAIL resource observation captures HP loss and active elapsed time"); }
        LeeTrialTelemetry.observe(room, 900, 1100);
        if (room.endHp == 900 && room.minHp == 700 && room.observedHpLoss == 300
                && room.observedHpGain == 200 && room.elapsedMs == 1000) passed++;
        else { failed++; trace("FAIL paused clock and observed recovery remain distinct"); }
        LeeTrialTelemetry.observe(room, -100, 2100);
        if (room.endHp == 0 && room.minHp == 0 && room.observedHpLoss == 1200
                && room.observedHpGain == 200 && room.samples == 3) passed++;
        else { failed++; trace("FAIL fatal overkill is clamped to actual HP resource loss"); }
        LeeTrialTelemetry.observe(room, Number("invalid"), 3100);
        if (room.endHp == 0 && room.samples == 3 && room.elapsedMs == 2000) passed++;
        else { failed++; trace("FAIL invalid sample must not pollute the record"); }
        LeeTrialTelemetry.observe(room, 0, 10000);
        if (room.elapsedMs == 2000 && room.firstDeathMs == 2000 && room.observedHpLoss == 1200) passed++;
        else { failed++; trace("FAIL resource time ends at the first death and excludes waiting for return"); }
        trace("LeeTrialTelemetryTest Tests Passed: " + passed);
        trace("LeeTrialTelemetryTest Tests Failed: " + failed);
    }
}
