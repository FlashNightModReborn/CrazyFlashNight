import org.flashNight.arki.hud.PlayerHudService;
import org.flashNight.arki.unit.Action.Skill.ManualCooldownService;

/** 真实 AVM1：冻结旧读路径作差分 oracle；计时只代表这里的确定性局部负载。 */
class org.flashNight.arki.hud.PlayerHudHotPathTest {
    private static var passed:Number = 0;
    private static var failed:Number = 0;
    private static var queue:Array = [];
    private static var legacyCooldownCache:Array;
    private static var checksum:Number = 0;

    private static function check(value:Boolean, message:String):Void {
        if (value) passed++;
        else { failed++; trace("[FAIL] PlayerHudHotPathTest: " + message); }
    }
    public static function runAllTests():Void {
        passed = failed = checksum = 0;
        testCooldownProjection();
        trace("PlayerHudHotPathTest Tests Passed: " + passed);
        trace("PlayerHudHotPathTest Tests Failed: " + failed);
    }
    private static function keys():Array {
        var result:Array = [ManualCooldownService.WEAPON_SKILL_KEY];
        var i:Number;
        for (i = 1; i < 13; i++) result.push(ManualCooldownService.quickSkillKey(i));
        for (i = 0; i < 4; i++) result.push(ManualCooldownService.drugKey(i));
        result.push(ManualCooldownService.drugSwitchKey());
        return result;
    }
    // 冻结自 5361c1a 的 readCooldowns；不调用新批量读取入口。
    private static function legacyCooldowns():Array {
        var result:Array = [];
        var channelKeys:Array = [ManualCooldownService.WEAPON_SKILL_KEY];
        var i:Number;
        for (i = 1; i < 13; i++) channelKeys.push(ManualCooldownService.quickSkillKey(i));
        for (i = 0; i < 4; i++) channelKeys.push(ManualCooldownService.drugKey(i));
        channelKeys.push(ManualCooldownService.drugSwitchKey());
        for (i = 0; i < channelKeys.length; i++) {
            var state:Object = ManualCooldownService.getSnapshot(channelKeys[i]);
            var current:Number = Number(state.currentStep);
            var total:Number = Number(state.totalSteps);
            result.push([state.ready === true ? 1 : 0,
                (current-current) == 0 ? current : 0, (total-total) == 0 ? total : 0]);
        }
        return result;
    }
    private static function legacyCooldownGroup():Object {
        var groups:Object = {};
        var value:Array = legacyCooldowns();
        if (!PlayerHudService.testOnlySameProjection(legacyCooldownCache, value)) {
            legacyCooldownCache = value;
            groups.cooldowns = value;
        }
        return groups;
    }
    private static function advanceFrame():Void {
        var count:Number = queue.length;
        for (var i:Number = 0; i < count; i++) {
            var callback = queue.shift();
            callback();
        }
    }
    private static function testCooldownProjection():Void {
        var service:Object = PlayerHudService;
        var savedGroups:Object = service.rawGroups;
        var channelKeys:Array = keys();
        var samples:Array = [];
        try {
            service.rawGroups = {};
            ManualCooldownService.resetForTests();
            queue = [];
            ManualCooldownService.setSchedulerForTests(function(callback:Function):Void {
                PlayerHudHotPathTest.queue.push(callback);
            });
            var first:Object = PlayerHudService.testOnlyCooldownGroup(false);
            check(first.cooldowns.length == 18, "wire owns the original 18-channel order");
            check(PlayerHudService.testOnlySameProjection(first.cooldowns, legacyCooldowns()), "cold default matches frozen reader");
            check(PlayerHudService.testOnlyCooldownGroup(false).cooldowns == undefined, "unchanged cold defaults emit no group");
            check(PlayerHudService.testOnlyCooldownGroup(true).cooldowns === first.cooldowns, "forced resync sends the detached unchanged snapshot");
            ManualCooldownService.writeHudSnapshot(channelKeys, samples);
            check(samples.length == 54 && samples[0] === 1 && samples[53] === 0, "batch returns finite flat triples");
            samples[0] = 0; samples[1] = 999;
            check(ManualCooldownService.isReady(channelKeys[0]) && ManualCooldownService.getSnapshot(channelKeys[0]).currentStep == 0,
                "caller scratch does not alias authority state");
            ManualCooldownService.start(channelKeys[0], 100);
            var started:Object = PlayerHudService.testOnlyCooldownGroup(false);
            check(started.cooldowns !== first.cooldowns && started.cooldowns[0][0] === 0, "start publishes a new detached group");
            check(first.cooldowns[0][0] === 1 && first.cooldowns[0][2] === 0, "start never mutates the previously sent snapshot");
            advanceFrame();
            var advanced:Object = PlayerHudService.testOnlyCooldownGroup(false);
            check(advanced.cooldowns[0][1] === 1 && started.cooldowns[0][1] === 0, "step change is visible without mutable DTO aliasing");
            check(PlayerHudService.testOnlySameProjection(advanced.cooldowns, legacyCooldowns()), "one running channel matches old snapshot");
            ManualCooldownService.reset(channelKeys[0]);
            check(PlayerHudService.testOnlySameProjection(PlayerHudService.testOnlyCooldownGroup(false).cooldowns, legacyCooldowns()), "reset clears current and total on wire");
            advanceFrame();
            check(PlayerHudService.testOnlyCooldownGroup(false).cooldowns == undefined, "stale scheduled generation causes no phantom change");
            var i:Number;
            for (i = 0; i < 18; i++) ManualCooldownService.start(channelKeys[i], 100);
            for (var frame:Number = 0; frame < 5; frame++) {
                var full:Object = PlayerHudService.testOnlyCooldownGroup(true);
                check(PlayerHudService.testOnlySameProjection(full.cooldowns, legacyCooldowns()), "18-channel frame " + frame + " matches old reader");
                advanceFrame();
            }
            service.rawGroups = {};
            check(PlayerHudService.testOnlyCooldownGroup(false).cooldowns.length == 18, "new actor/group context republishes all cooldowns");
            ManualCooldownService.writeHudSnapshot([channelKeys[0]], samples);
            check(samples.length == 3, "batch truncates trailing caller scratch");
            benchmarkCooldowns(0);
            benchmarkCooldowns(1);
            benchmarkCooldowns(18);
        } finally {
            service.rawGroups = savedGroups;
            ManualCooldownService.resetForTests();
            queue = [];
        }
    }
    private static function timeCooldowns(legacy:Boolean, count:Number):Number {
        var started:Number = getTimer();
        for (var i:Number = 0; i < count; i++) {
            var groups:Object = legacy ? legacyCooldownGroup() : PlayerHudService.testOnlyCooldownGroup(false);
            if (groups.cooldowns != undefined) checksum += groups.cooldowns.length;
        }
        return getTimer() - started;
    }
    private static function benchmarkCooldowns(active:Number):Void {
        ManualCooldownService.resetForTests();
        ManualCooldownService.setSchedulerForTests(function(callback:Function):Void { });
        var channelKeys:Array = keys();
        for (var i:Number = 0; i < active; i++) ManualCooldownService.start(channelKeys[i], 1000);
        PlayerHudService.testOnlyCooldownGroup(true);
        legacyCooldownCache = legacyCooldowns();
        timeCooldowns(true, 20); timeCooldowns(false, 20);
        var original:Array = [], candidate:Array = [];
        for (var round:Number = 0; round < 5; round++) {
            if ((round & 1) == 0) {
                original.push(timeCooldowns(true, 300)); candidate.push(timeCooldowns(false, 300));
            } else {
                candidate.push(timeCooldowns(false, 300)); original.push(timeCooldowns(true, 300));
            }
        }
        trace("[AS2_HOTPATH_BENCH] cooldown_active_" + active + "|iterations=300|baselineMs=" + original.join(",") + "|candidateMs=" + candidate.join(","));
    }
}
