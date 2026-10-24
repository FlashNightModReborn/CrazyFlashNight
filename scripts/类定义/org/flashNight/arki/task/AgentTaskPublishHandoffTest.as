import org.flashNight.arki.task.AgentTaskPublishHandoff;

/**
 * AgentTaskPublishHandoffTest - 插话任务发布交接的纯逻辑测试（focused runner 用）。
 *
 * 覆盖：字段/槽位/战斗/已接/不可接/token 校验，版本相同直接接取，
 * 版本变化先热更再接取，热更失败提示，旧回调丢弃，热更后仍不可接的兜底，
 * 新任务定义尚未随热更落地时先热更、落地后再接取。
 * 环境能力全部由本测试注入，不读 _root、不建真实会话、不写任何存档。
 */
class org.flashNight.arki.task.AgentTaskPublishHandoffTest {
    public static var testsRun:Number = 0;
    public static var testsPassed:Number = 0;
    public static var testsFailed:Number = 0;

    public static var tips:Array = null;
    public static var closes:Number = 0;
    public static var opened:Array = null;
    public static var reloads:Array = null;
    public static var versionCallbacks:Array = null;
    public static var reloadDones:Array = null;
    public static var reloadFails:Array = null;
    public static var activeIds:Array = null;
    public static var availableFlag:Boolean = true;
    public static var hasDataFlag:Boolean = true;

    private static function assert(cond:Boolean, msg:String):Void {
        testsRun++;
        if (cond) { testsPassed++; trace("[PASS] " + msg); }
        else { testsFailed++; trace("[FAIL] " + msg); }
    }

    private static function assertEq(expected, actual, msg:String):Void {
        testsRun++;
        if (expected === actual) { testsPassed++; trace("[PASS] " + msg); }
        else { testsFailed++; trace("[FAIL] " + msg + " expected=" + expected + " actual=" + actual); }
    }

    private static function makeEnv():Object {
        tips = [];
        closes = 0;
        opened = [];
        reloads = [];
        versionCallbacks = [];
        reloadDones = [];
        reloadFails = [];
        activeIds = [];
        availableFlag = true;
        hasDataFlag = true;
        AgentTaskPublishHandoff.reset();
        return {
            currentSlot: "slotA",
            inCombat: false,
            lastTaskPublishVersion: 0,
            isTaskActive: function(taskId:Number):Boolean {
                for (var i:Number = 0; i < AgentTaskPublishHandoffTest.activeIds.length; i++) {
                    if (Number(AgentTaskPublishHandoffTest.activeIds[i]) == taskId) return true;
                }
                return false;
            },
            isTaskAvailable: function(taskId:Number):Boolean {
                return AgentTaskPublishHandoffTest.availableFlag;
            },
            hasTaskData: function(taskId:Number):Boolean {
                return AgentTaskPublishHandoffTest.hasDataFlag;
            },
            loadVersion: function(onReady:Function):Void {
                AgentTaskPublishHandoffTest.versionCallbacks.push(onReady);
            },
            reload: function(fileVer:Number, onDone:Function, onFailed:Function):Void {
                AgentTaskPublishHandoffTest.reloads.push(fileVer);
                AgentTaskPublishHandoffTest.reloadDones.push(onDone);
                AgentTaskPublishHandoffTest.reloadFails.push(onFailed);
            },
            closeSession: function():Void {
                AgentTaskPublishHandoffTest.closes++;
            },
            openTask: function(taskId:Number):Void {
                AgentTaskPublishHandoffTest.opened.push(taskId);
            },
            showTip: function(text:String):Void {
                AgentTaskPublishHandoffTest.tips.push(text);
            }
        };
    }

    private static function payload(taskId:Number, token:String, slot:String):Object {
        return {taskId:taskId, npc:"Andy Law", slot:slot, token:token};
    }

    public static function runAllTests():Void {
        testsRun = 0;
        testsPassed = 0;
        testsFailed = 0;

        testVersionChangeReloadsThenAccepts();
        testSameVersionAcceptsWithoutReload();
        testZeroVersionAcceptsWithoutReload();
        testAlreadyActiveOnlyClosesSession();
        testUnavailableRejectsWithTip();
        testCombatRejectsWithTip();
        testSlotMismatchRejectsWithTip();
        testEmptySlotSkipsSlotCheck();
        testInvalidTaskIgnored();
        testMissingNpcIgnored();
        testDuplicateTokenIgnored();
        testReloadFailureTipsAndClearsPending();
        testStaleVersionCallbackDropped();
        testUnavailableAfterReloadTips();
        testMissingVersionLoaderTips();
        testMissingReloaderTips();
        testUnknownTaskReloadsEvenWhenVersionSettled();
        testStillUnknownAfterReloadTips();
        testValidateDoesNotConsumeToken();

        trace("AgentTaskPublishHandoffTest Tests Passed: " + testsPassed);
        trace("AgentTaskPublishHandoffTest Tests Failed: " + testsFailed);
        AgentTaskPublishHandoff.reset();
    }

    // ── 正常路径 ────────────────────────────────────────────────

    private static function testVersionChangeReloadsThenAccepts():Void {
        var env:Object = makeEnv();
        AgentTaskPublishHandoff.handle(payload(200345, "t1", "slotA"), env);
        assertEq(1, versionCallbacks.length, "version read once");
        versionCallbacks[0](7);
        assertEq(1, reloads.length, "version change triggers reload");
        assertEq(7, reloads[0], "reload receives file version");
        assertEq(0, closes, "session stays open while reloading");
        reloadDones[0]();
        assertEq(1, closes, "reload done closes old dialogue");
        assertEq(1, opened.length, "task opened once");
        assertEq(200345, opened[0], "task opened with pushed id");
        assertEq(0, tips.length, "no fallback tip on success");
        assert(AgentTaskPublishHandoff.pendingForTest() == null, "pending cleared after accept");
    }

    private static function testSameVersionAcceptsWithoutReload():Void {
        var env:Object = makeEnv();
        env.lastTaskPublishVersion = 7;
        AgentTaskPublishHandoff.handle(payload(200346, "t2", "slotA"), env);
        versionCallbacks[0](7);
        assertEq(0, reloads.length, "same version skips reload");
        assertEq(1, closes, "same version still closes session");
        assertEq(200346, opened[0], "same version opens task");
    }

    private static function testZeroVersionAcceptsWithoutReload():Void {
        var env:Object = makeEnv();
        AgentTaskPublishHandoff.handle(payload(200347, "t3", ""), env);
        versionCallbacks[0](0);
        assertEq(0, reloads.length, "missing version skips reload");
        assertEq(200347, opened[0], "missing version still opens task");
    }

    private static function testAlreadyActiveOnlyClosesSession():Void {
        var env:Object = makeEnv();
        activeIds.push(200348);
        AgentTaskPublishHandoff.handle(payload(200348, "t4", "slotA"), env);
        assertEq(0, versionCallbacks.length, "already active skips version read");
        assertEq(1, closes, "already active closes old dialogue");
        assertEq(0, opened.length, "already active does not GetTask again");
        assertEq(0, tips.length, "already active stays silent");
    }

    // ── 校验拒绝 ────────────────────────────────────────────────

    private static function testUnavailableRejectsWithTip():Void {
        var env:Object = makeEnv();
        availableFlag = false;
        AgentTaskPublishHandoff.handle(payload(200349, "t5", "slotA"), env);
        assertEq(0, versionCallbacks.length, "unavailable does not read version");
        assertEq(1, tips.length, "unavailable shows fallback tip");
        assertEq(0, closes, "unavailable leaves dialogue open");
    }

    private static function testCombatRejectsWithTip():Void {
        var env:Object = makeEnv();
        env.inCombat = true;
        AgentTaskPublishHandoff.handle(payload(200350, "t6", "slotA"), env);
        assertEq(1, tips.length, "combat shows fallback tip");
        assertEq(0, versionCallbacks.length, "combat does not read version");
    }

    private static function testSlotMismatchRejectsWithTip():Void {
        var env:Object = makeEnv();
        AgentTaskPublishHandoff.handle(payload(200351, "t7", "slotB"), env);
        assertEq(1, tips.length, "slot mismatch shows fallback tip");
        assertEq(0, versionCallbacks.length, "slot mismatch does not read version");
    }

    private static function testEmptySlotSkipsSlotCheck():Void {
        var env:Object = makeEnv();
        AgentTaskPublishHandoff.handle(payload(200352, "t8", ""), env);
        assertEq(1, versionCallbacks.length, "empty pushed slot accepts current slot");
    }

    private static function testInvalidTaskIgnored():Void {
        var env:Object = makeEnv();
        AgentTaskPublishHandoff.handle({taskId:"abc", npc:"Andy Law", slot:"slotA", token:"t9"}, env);
        assertEq(0, versionCallbacks.length, "invalid task id does nothing");
        assertEq(0, tips.length, "invalid task id stays silent");
    }

    private static function testMissingNpcIgnored():Void {
        var env:Object = makeEnv();
        AgentTaskPublishHandoff.handle({taskId:200353, npc:"", slot:"slotA", token:"t10"}, env);
        assertEq(0, versionCallbacks.length, "missing npc does nothing");
        assertEq(0, tips.length, "missing npc stays silent");
    }

    // ── 幂等 / 失败 ────────────────────────────────────────────

    private static function testDuplicateTokenIgnored():Void {
        var env:Object = makeEnv();
        AgentTaskPublishHandoff.handle(payload(200354, "tdup", "slotA"), env);
        versionCallbacks[0](7);
        reloadDones[0]();
        assertEq(1, opened.length, "first consume opens task");
        AgentTaskPublishHandoff.handle(payload(200354, "tdup", "slotA"), env);
        assertEq(1, versionCallbacks.length, "duplicate token does no second read");
        assertEq(1, opened.length, "duplicate token does no second open");
    }

    private static function testReloadFailureTipsAndClearsPending():Void {
        var env:Object = makeEnv();
        AgentTaskPublishHandoff.handle(payload(200355, "t11", "slotA"), env);
        versionCallbacks[0](7);
        reloadFails[0]("boom");
        assertEq(1, tips.length, "reload failure shows fallback tip");
        assertEq(0, opened.length, "reload failure does not open task");
        assert(AgentTaskPublishHandoff.pendingForTest() == null, "reload failure clears pending");
    }

    private static function testStaleVersionCallbackDropped():Void {
        var env:Object = makeEnv();
        AgentTaskPublishHandoff.handle(payload(200356, "t12", "slotA"), env);
        AgentTaskPublishHandoff.handle(payload(200357, "t13", "slotA"), env);
        assertEq(2, versionCallbacks.length, "two pushes issue two reads");
        versionCallbacks[0](7);
        assertEq(0, reloads.length, "stale read callback is dropped");
        versionCallbacks[1](8);
        assertEq(1, reloads.length, "latest read callback reloads");
        reloadDones[0]();
        assertEq(1, opened.length, "only latest push opens task");
        assertEq(200357, opened[0], "latest push wins");
    }

    private static function testUnavailableAfterReloadTips():Void {
        var env:Object = makeEnv();
        AgentTaskPublishHandoff.handle(payload(200358, "t14", "slotA"), env);
        versionCallbacks[0](7);
        availableFlag = false;   // 热更后目标仍不可接（前置任务等变化）
        reloadDones[0]();
        assertEq(1, tips.length, "post-reload unavailable shows tip");
        assertEq(0, opened.length, "post-reload unavailable does not open");
        assertEq(1, closes, "post-reload unavailable still closes old dialogue");
    }

    private static function testMissingVersionLoaderTips():Void {
        var env:Object = makeEnv();
        env.loadVersion = null;
        AgentTaskPublishHandoff.handle(payload(200359, "t15", "slotA"), env);
        assertEq(1, tips.length, "missing version loader shows tip");
        assertEq(0, opened.length, "missing version loader does not open");
    }

    private static function testMissingReloaderTips():Void {
        var env:Object = makeEnv();
        env.reload = null;
        AgentTaskPublishHandoff.handle(payload(200360, "t16", "slotA"), env);
        versionCallbacks[0](7);
        assertEq(1, tips.length, "missing reloader shows tip");
        assertEq(0, opened.length, "missing reloader does not open");
        assert(AgentTaskPublishHandoff.pendingForTest() == null, "missing reloader clears pending");
    }

    private static function testUnknownTaskReloadsEvenWhenVersionSettled():Void {
        var env:Object = makeEnv();
        env.lastTaskPublishVersion = 7;
        hasDataFlag = false;
        AgentTaskPublishHandoff.handle(payload(200362, "t18", "slotA"), env);
        versionCallbacks[0](7);
        assertEq(1, reloads.length, "unknown task reloads even with settled version");
        hasDataFlag = true;
        reloadDones[0]();
        assertEq(1, opened.length, "task opens after reload lands");
        assertEq(200362, opened[0], "opens pushed id after reload");
        assertEq(0, tips.length, "no tip when reload lands the task");
    }

    private static function testStillUnknownAfterReloadTips():Void {
        var env:Object = makeEnv();
        hasDataFlag = false;
        AgentTaskPublishHandoff.handle(payload(200363, "t19", "slotA"), env);
        versionCallbacks[0](7);
        reloadDones[0]();
        assertEq(1, tips.length, "missing task after reload shows tip");
        assertEq(0, opened.length, "missing task after reload does not open");
        assertEq(1, closes, "missing task after reload still closes old dialogue");
    }

    private static function testValidateDoesNotConsumeToken():Void {
        var env:Object = makeEnv();
        var p:Object = payload(200361, "t17", "slotA");
        assertEq(true, AgentTaskPublishHandoff.validate(p, env).ok, "validate ok first time");
        assertEq(true, AgentTaskPublishHandoff.validate(p, env).ok, "validate ok twice (token not consumed)");
    }
}
