// 文件路径：org/flashNight/arki/unit/Action/Skill/ManualCooldownServiceTest.as

import org.flashNight.arki.unit.Action.Skill.ManualCooldownService;

class org.flashNight.arki.unit.Action.Skill.ManualCooldownServiceTest {

    private static var testsRun:Number = 0;
    private static var testsPassed:Number = 0;
    private static var testsFailed:Number = 0;
    private static var queue:Array = [];

    public static function runAllTests():Void {
        testsRun = testsPassed = testsFailed = 0;
        trace("--- ManualCooldownServiceTest ---");

        testDurationRoundingAndDuplicateStart();
        testLegacyProjectionAndRendererRebind();
        testAllLogicalChannelsAreIndependent();
        testSafeKeyResetInvalidatesQueuedGeneration();
        testSchedulerProgressIgnoresPauseAndSceneObjects();

        ManualCooldownService.resetForTests();
        trace("--- ManualCooldownServiceTest: " + testsPassed + "/" + testsRun + " passed, " + testsFailed + " failed ---");
    }

    private static function resetFixture():Void {
        queue = [];
        ManualCooldownService.resetForTests();
        ManualCooldownService.setSchedulerForTests(function(callback:Function):Void {
            queue.push(callback);
        });
    }

    private static function runOneTick():Void {
        var callback = queue.shift();
        if (callback) callback();
    }

    private static function drainQueue():Void {
        var guard:Number = 0;
        while (queue.length > 0 && guard++ < 1000) runOneTick();
    }

    private static function testDurationRoundingAndDuplicateStart():Void {
        resetFixture();
        var key:String = ManualCooldownService.quickSkillKey(1);
        assert(ManualCooldownService.start(key, 100), "cooldown accepts first start");
        var snapshot:Object = ManualCooldownService.getSnapshot(key);
        assert(snapshot.totalSteps == 4 && snapshot.currentStep == 0, "100ms uses legacy ceil(ms/33.33333) rounding");
        assert(!ManualCooldownService.start(key, 100), "active cooldown rejects repeated start");

        runOneTick();
        snapshot = ManualCooldownService.getSnapshot(key);
        assert(!snapshot.ready && snapshot.currentStep == 1 && snapshot.progressPercent == 25 && snapshot.animationFrame == 26,
            "first tick keeps legacy rounded percent and animation frame");
        drainQueue();
        snapshot = ManualCooldownService.getSnapshot(key);
        assert(snapshot.ready && snapshot.currentStep == 0 && snapshot.animationFrame == 1,
            "final tick restores ready state and frame one");

        assert(ManualCooldownService.start(key, 0), "zero duration still starts a one-tick cooldown");
        assert(ManualCooldownService.getSnapshot(key).totalSteps == 1, "zero duration is normalized to one tick");
        drainQueue();
    }

    private static function testLegacyProjectionAndRendererRebind():Void {
        resetFixture();
        var key:String = ManualCooldownService.drugKey(0);
        var first:Object = makeRenderer();
        ManualCooldownService.bindRenderer(key, first);
        assert(first.冷却 === true && first.lastFrame == 1, "new renderer receives ready projection immediately");
        assert(first.冷却开始(100), "legacy cooldown starter delegates to authority after binding");
        runOneTick();
        assert(first.冷却 === false && first.当前进度 == 1 && first.lastFrame == 26,
            "bound legacy renderer follows authority progress");

        var replacement:Object = makeRenderer();
        ManualCooldownService.bindRenderer(key, replacement);
        assert(replacement.冷却 === false && replacement.当前进度 == 1 && replacement.lastFrame == 26,
            "replacement renderer catches up without resetting authority");
        drainQueue();
        assert(replacement.冷却 === true && replacement.lastFrame == 1, "replacement renderer receives completion");

        replacement.冷却开始 = function():Boolean { return false; };
        ManualCooldownService.bindRenderer(key, replacement);
        assert(replacement.冷却开始(34), "same renderer recovers authority starter after timeline frame script resets it");
        drainQueue();
    }

    private static function testAllLogicalChannelsAreIndependent():Void {
        resetFixture();
        var keys:Array = [];
        var i:Number;
        for (i = 1; i <= 12; i++) keys.push(ManualCooldownService.quickSkillKey(i));
        for (i = 0; i < 4; i++) keys.push(ManualCooldownService.drugKey(i));
        keys.push(ManualCooldownService.drugSwitchKey());
        keys.push(ManualCooldownService.WEAPON_SKILL_KEY);

        for (i = 0; i < keys.length; i++) {
            assert(ManualCooldownService.start(String(keys[i]), 34), "logical cooldown channel starts independently: " + keys[i]);
        }
        assert(keys.length == 18, "authority owns exactly 12 quick skills, 4 drug lanes, 1 drug switch and 1 shared weapon cooldown");
        runOneTick();
        assert(!ManualCooldownService.isReady(String(keys[0])) && !ManualCooldownService.isReady(String(keys[17])),
            "advancing one queued channel does not complete other channels");
        drainQueue();
        for (i = 0; i < keys.length; i++) {
            assert(ManualCooldownService.isReady(String(keys[i])), "logical channel completes independently: " + keys[i]);
        }
    }

    private static function testSafeKeyResetInvalidatesQueuedGeneration():Void {
        resetFixture();
        var key:String = ManualCooldownService.drugSwitchKey();
        var renderer:Object = makeRenderer();
        assert(key == "drug:switch" && ManualCooldownService.bindRenderer(key, renderer),
            "drug switch exposes one stable logical key and accepts renderer binding");
        assert(ManualCooldownService.start(key, 100) && queue.length == 1,
            "drug switch cooldown schedules independently");
        assert(ManualCooldownService.reset(key) && ManualCooldownService.isReady(key)
                && renderer.冷却 === true && renderer.lastFrame == 1,
            "safe key reset immediately restores ready projection");
        drainQueue();
        assert(ManualCooldownService.isReady(key)
                && ManualCooldownService.getSnapshot(key).totalSteps == 0,
            "queued callback from the reset generation cannot revive stale progress");
        assert(!ManualCooldownService.reset(null) && !ManualCooldownService.reset(""),
            "safe key reset rejects invalid keys without creating authority state");
    }

    private static function testSchedulerProgressIgnoresPauseAndSceneObjects():Void {
        resetFixture();
        var oldPause:Object = _root.暂停;
        var oldScene:Object = _root.场景转换中;
        var key:String = ManualCooldownService.WEAPON_SKILL_KEY;
        ManualCooldownService.start(key, 67);
        _root.暂停 = true;
        _root.场景转换中 = true;
        drainQueue();
        assert(ManualCooldownService.isReady(key), "cooldown scheduler advances while gameplay is paused or scene objects change");
        _root.暂停 = oldPause;
        _root.场景转换中 = oldScene;
    }

    private static function makeRenderer():Object {
        var renderer:Object = {冷却: true, 总步数: 0, 当前进度: 0, lastFrame: 0};
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
