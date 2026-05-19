import org.flashNight.arki.unit.UnitComponent.Routing.*;

/**
 * RoutingRuntime Test Suite — attachMovie adapter
 *
 * 覆盖低层 adapter 注入面：
 *   - 默认路径（adapter 未注入）→ 转发到 parent.attachMovie
 *   - adapter 注入后接管 → parent.attachMovie 完全不被调到
 *   - adapter 收齐 5 个参数（含 initObject）
 *   - adapter 返回 undefined → caller 看到 undefined（missing symbol 语义）
 *   - clearAttachMovieAdapterForTest 后回退到 parent 路径
 *
 * 注：暂不覆盖 air controller / scheduler 的 spy，这部分已经在 RoutingLifecycle
 * 套件里通过 setAirControllerForTest / setSchedulerForTest 间接断言。
 */
class org.flashNight.arki.unit.UnitComponent.Routing.RoutingRuntimeTest {

    private static var testCount:Number = 0;
    private static var passedTests:Number = 0;
    private static var failedTests:Number = 0;

    private static function assertEquals(name:String, expected, actual):Void {
        testCount++;
        if (expected === actual) {
            passedTests++;
            trace("  [PASS] " + name);
        } else {
            failedTests++;
            trace("  [FAIL] " + name + " (exp=" + expected + " act=" + actual + ")");
        }
    }

    private static function assertTrue(name:String, cond:Boolean):Void {
        testCount++;
        if (cond) {
            passedTests++;
            trace("  [PASS] " + name);
        } else {
            failedTests++;
            trace("  [FAIL] " + name);
        }
    }

    public static function runAll():Boolean {
        trace("================================================================");
        trace("RoutingRuntime Test Suite (attachMovie adapter)");
        trace("================================================================");

        var t0:Number = getTimer();
        testCount = 0;
        passedTests = 0;
        failedTests = 0;

        testAttachMovie_FallThroughToParent();
        testAttachMovie_AdapterIntercepts();
        testAttachMovie_AdapterReceivesAllArgs();
        testAttachMovie_AdapterReturnsUndefined();
        testAttachMovie_ClearAdapterRestoresParent();

        // 兜底清理 adapter，避免污染下游套件
        RoutingRuntime.clearAttachMovieAdapterForTest();

        var elapsed:Number = getTimer() - t0;
        trace("================================================================");
        trace("Results: " + passedTests + "/" + testCount + " passed, "
              + failedTests + " failed (" + elapsed + "ms)");
        trace("================================================================");
        return failedTests == 0;
    }

    // ====================================================================
    // helpers
    // ====================================================================

    private static function makeFakeParent():Object {
        var p:Object = {};
        p.__lastAttachLinkage = undefined;
        p.__lastAttachName = undefined;
        p.__lastAttachDepth = undefined;
        p.__lastAttachInit = undefined;
        p.__lastAttachCount = 0;
        p.attachMovie = function(linkage, name, depth, initObj) {
            this.__lastAttachLinkage = linkage;
            this.__lastAttachName = name;
            this.__lastAttachDepth = depth;
            this.__lastAttachInit = initObj;
            this.__lastAttachCount++;
            return {__from: "parent", linkage: linkage};
        };
        return p;
    }

    private static function makeFakeAdapter():Object {
        var a:Object = {};
        a.__lastParent = undefined;
        a.__lastLinkage = undefined;
        a.__lastName = undefined;
        a.__lastDepth = undefined;
        a.__lastInit = undefined;
        a.__lastCount = 0;
        a.__returnValue = {__from: "adapter"};
        a.attachMovie = function(parent, linkage, name, depth, initObj) {
            this.__lastParent = parent;
            this.__lastLinkage = linkage;
            this.__lastName = name;
            this.__lastDepth = depth;
            this.__lastInit = initObj;
            this.__lastCount++;
            return this.__returnValue;
        };
        return a;
    }

    // ====================================================================
    // cases
    // ====================================================================

    private static function testAttachMovie_FallThroughToParent():Void {
        trace("\n--- testAttachMovie_FallThroughToParent ---");
        RoutingRuntime.clearAttachMovieAdapterForTest();
        var parent:Object = makeFakeParent();
        var initObj:Object = {role: "test", n: 42};
        var result = RoutingRuntime.attachMovie(parent, "linkage-X", "man", 0, initObj);
        assertEquals("parent.attachMovie 调用 1 次", 1, parent.__lastAttachCount);
        assertEquals("parent 收到 linkage", "linkage-X", parent.__lastAttachLinkage);
        assertEquals("parent 收到 name", "man", parent.__lastAttachName);
        assertEquals("parent 收到 depth", 0, parent.__lastAttachDepth);
        assertEquals("parent 收到 initObj 引用", initObj, parent.__lastAttachInit);
        assertTrue("结果来自 parent", result.__from === "parent");
    }

    private static function testAttachMovie_AdapterIntercepts():Void {
        trace("\n--- testAttachMovie_AdapterIntercepts ---");
        var parent:Object = makeFakeParent();
        var adapter:Object = makeFakeAdapter();
        RoutingRuntime.setAttachMovieAdapterForTest(adapter);
        var result = RoutingRuntime.attachMovie(parent, "linkage-Y", "man", 1, {flag: true});
        assertEquals("adapter.attachMovie 调用 1 次", 1, adapter.__lastCount);
        assertEquals("parent.attachMovie 不被调用", 0, parent.__lastAttachCount);
        assertTrue("结果来自 adapter", result.__from === "adapter");
        RoutingRuntime.clearAttachMovieAdapterForTest();
    }

    private static function testAttachMovie_AdapterReceivesAllArgs():Void {
        trace("\n--- testAttachMovie_AdapterReceivesAllArgs ---");
        var parent:Object = makeFakeParent();
        var adapter:Object = makeFakeAdapter();
        RoutingRuntime.setAttachMovieAdapterForTest(adapter);
        var initObj:Object = {a: 1, b: "two"};
        RoutingRuntime.attachMovie(parent, "L", "N", 7, initObj);
        assertEquals("adapter 收到 parent 引用", parent, adapter.__lastParent);
        assertEquals("adapter 收到 linkage", "L", adapter.__lastLinkage);
        assertEquals("adapter 收到 name", "N", adapter.__lastName);
        assertEquals("adapter 收到 depth", 7, adapter.__lastDepth);
        assertEquals("adapter 收到 initObj 引用", initObj, adapter.__lastInit);
        assertEquals("initObj.a 字段透传", 1, adapter.__lastInit.a);
        assertEquals("initObj.b 字段透传", "two", adapter.__lastInit.b);
        RoutingRuntime.clearAttachMovieAdapterForTest();
    }

    private static function testAttachMovie_AdapterReturnsUndefined():Void {
        trace("\n--- testAttachMovie_AdapterReturnsUndefined ---");
        var parent:Object = makeFakeParent();
        var adapter:Object = makeFakeAdapter();
        adapter.__returnValue = undefined;
        RoutingRuntime.setAttachMovieAdapterForTest(adapter);
        var result = RoutingRuntime.attachMovie(parent, "missing", "man", 0, {});
        assertTrue("missing symbol → 返回 undefined", result === undefined);
        assertEquals("missing 时 adapter 仍被调用", 1, adapter.__lastCount);
        RoutingRuntime.clearAttachMovieAdapterForTest();
    }

    private static function testAttachMovie_ClearAdapterRestoresParent():Void {
        trace("\n--- testAttachMovie_ClearAdapterRestoresParent ---");
        var parent:Object = makeFakeParent();
        var adapter:Object = makeFakeAdapter();
        RoutingRuntime.setAttachMovieAdapterForTest(adapter);
        RoutingRuntime.attachMovie(parent, "via-adapter", "n", 0, {});
        RoutingRuntime.clearAttachMovieAdapterForTest();
        RoutingRuntime.attachMovie(parent, "via-parent", "n", 0, {});
        assertEquals("clear 后 parent.attachMovie 被走到", "via-parent", parent.__lastAttachLinkage);
        assertEquals("clear 后 adapter.count 不再增长", 1, adapter.__lastCount);
        assertEquals("clear 后 parent.count = 1", 1, parent.__lastAttachCount);
    }
}