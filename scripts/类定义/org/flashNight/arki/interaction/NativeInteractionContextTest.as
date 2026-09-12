import org.flashNight.arki.interaction.NativeInteractionContext;
import org.flashNight.neur.Event.EventBus;

/**
 * NativeInteractionContextTest - 共享场景/请求身份上下文测试（focused runner 用）
 *
 * 覆盖：sceneId 同场景稳定且形式 ni.scene.<seq>.<timer>；
 *   requestId 精确形式 ni:<正整数> 且严格 +1、跨场景不重置；
 *   SceneChanged 时先执行已注册 teardown（回调内仍见旧 sceneId）再轮换身份；
 *   isCurrentWorld 普通对象 token 判定 + 懒捕获；install 幂等。
 *
 * 使用真实 EventBus 单例发布一次 SceneChanged（真生命周期机制）；
 * _root.gameworld 用临时对象桩并在结束后恢复，不触真实存档。
 */
class org.flashNight.arki.interaction.NativeInteractionContextTest {

    public static var testsRun:Number = 0;
    public static var testsPassed:Number = 0;
    public static var testsFailed:Number = 0;

    public static var probeScene:String = null;

    private static var _savedGw = undefined;

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

    private static function reqSeq(rid:String):Number {
        return Number(rid.substring(3));
    }

    public static function runAllTests():Void {
        testsRun = testsPassed = testsFailed = 0;
        trace("--- NativeInteractionContextTest ---");

        _savedGw = _root.gameworld;
        probeScene = null;

        NativeInteractionContext.install();
        NativeInteractionContext.install();   // 幂等：二次调用无副作用

        // ── sceneId：同场景稳定 + 形式 ──
        var sid1:String = NativeInteractionContext.getSceneId();
        assert(sid1.indexOf("ni.scene.") == 0, "sceneId: ni.scene. prefix");
        assertEq(sid1, NativeInteractionContext.getSceneId(),
            "sceneId: stable within same scene");

        // ── requestId：ni:<正整数> 严格递增 ──
        var r1:String = NativeInteractionContext.nextRequestId();
        var r2:String = NativeInteractionContext.nextRequestId();
        assert(r1.indexOf("ni:") == 0, "requestId: ni: prefix");
        assert(reqSeq(r1) > 0, "requestId: positive seq");
        assert(reqSeq(r2) === reqSeq(r1) + 1, "requestId: strictly +1");

        // ── 场景切换：先 teardown 再轮换 ──
        _root.gameworld = {fakeWorld: 1};
        NativeInteractionContext.onSceneTeardown(function():Void {
            org.flashNight.arki.interaction.NativeInteractionContextTest.probeScene =
                org.flashNight.arki.interaction.NativeInteractionContext.getSceneId();
        });
        EventBus.getInstance().publish("SceneChanged");
        assertEq(sid1, probeScene,
            "teardown: callback still sees OLD sceneId (runs before rotate)");
        var sid2:String = NativeInteractionContext.getSceneId();
        assert(sid2 !== sid1 && sid2.indexOf("ni.scene.") == 0,
            "teardown: sceneId rotated after callbacks");

        // ── 场景身份：普通对象 token ──
        assert(NativeInteractionContext.isCurrentWorld(_root.gameworld) === true,
            "identity: current world accepted");
        assert(NativeInteractionContext.isCurrentWorld({}) === false,
            "identity: foreign world rejected");
        assert(NativeInteractionContext.isCurrentWorld(undefined) === false,
            "identity: undefined rejected");
        assert(NativeInteractionContext.getSceneIdentity() != undefined,
            "identity: token captured for present world");

        // ── requestId 跨场景不重置 ──
        var r3:String = NativeInteractionContext.nextRequestId();
        assert(reqSeq(r3) === reqSeq(r2) + 1,
            "requestId: sequence survives scene rotation");

        // 恢复 gameworld 引用
        if (_savedGw != undefined) _root.gameworld = _savedGw;
        else delete _root.gameworld;
        _savedGw = undefined;

        trace("NativeInteractionContextTest Tests Passed: " + testsPassed);
        trace("NativeInteractionContextTest Tests Failed: " + testsFailed);
    }
}
