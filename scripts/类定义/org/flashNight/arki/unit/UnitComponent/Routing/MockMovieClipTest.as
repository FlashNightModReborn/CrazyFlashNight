import org.flashNight.arki.unit.UnitComponent.Routing.*;

/**
 * MockMovieClip Test Suite
 *
 * 覆盖契约 §1+§2+§3+§4：
 *   - 构造与字段默认值
 *   - attachMovie 同步 enumerate + copy + child 暴露 + missing symbol + 同名覆盖
 *   - removeMovieClip 幂等 / detached / 级联子级 / unload 顺序
 *   - onUnload chain（多层 wrapper）/ suppressOldManUnload 风格替换
 *   - gotoAndStop frameEpoch + 已 remove 后 no-op
 *
 * 测试本身是夹具的"自反测试"；III.2 + III.3 + III.4 端到端样例消费这里的 mock。
 */
class org.flashNight.arki.unit.UnitComponent.Routing.MockMovieClipTest {

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
        trace("MockMovieClip Test Suite");
        trace("================================================================");

        var t0:Number = getTimer();
        testCount = 0;
        passedTests = 0;
        failedTests = 0;

        // 构造
        testCtor_FieldDefaults();

        // attachMovie
        testAttachMovie_CreatesChildAndCopiesInit();
        testAttachMovie_ExposesChildAsOwnProperty();
        testAttachMovie_MissingReturnsUndefined();
        testAttachMovie_MissingStillRecordsHistory();
        testAttachMovie_SameNameReplacesAndUnloadsOld();
        testAttachMovie_SnapshotIsolatesFutureMutation();

        // removeMovieClip
        testRemoveMovieClip_TriggersOnUnload();
        testRemoveMovieClip_Idempotent();
        testRemoveMovieClip_DetachesFromParent();
        testRemoveMovieClip_CascadesToChildren();
        testRemoveMovieClip_ChildUnloadBeforeParent();
        testRemoveMovieClip_DetachedSignature();

        // onUnload chain
        testOnUnload_ChainPrevThenWrapper();
        testOnUnload_SuppressByEmptyFn();

        // gotoAndStop
        testGotoAndStop_BumpsFrameEpoch();
        testGotoAndStop_AfterRemoveIsNoOp();
        testGotoAndStop_DoesNotRemoveChildren();

        var elapsed:Number = getTimer() - t0;
        trace("================================================================");
        trace("Results: " + passedTests + "/" + testCount + " passed, "
              + failedTests + " failed (" + elapsed + "ms)");
        trace("================================================================");
        return failedTests == 0;
    }

    // ════════════════════════════════════════════════════════════════════
    // 构造
    // ════════════════════════════════════════════════════════════════════

    private static function testCtor_FieldDefaults():Void {
        trace("\n--- testCtor_FieldDefaults ---");
        var m:MockMovieClip = new MockMovieClip();
        assertTrue("__name undefined", m.__name === undefined);
        assertEquals("__depth = 0", 0, m.__depth);
        assertTrue("__parent undefined", m.__parent === undefined);
        assertEquals("__removed false", false, m.__removed);
        assertTrue("__children 空对象", typeof m.__children === "object");
        assertEquals("__initObjectsReceived.length=0", 0, m.__initObjectsReceived.length);
        assertEquals("__frameEpoch=0", 0, m.__frameEpoch);
        assertEquals("__unloadCallCount=0", 0, m.__unloadCallCount);
        assertTrue("onUnload undefined", m.onUnload === undefined);
    }

    // ════════════════════════════════════════════════════════════════════
    // attachMovie
    // ════════════════════════════════════════════════════════════════════

    private static function testAttachMovie_CreatesChildAndCopiesInit():Void {
        trace("\n--- testAttachMovie_CreatesChildAndCopiesInit ---");
        var parent:MockMovieClip = new MockMovieClip();
        var init:Object = {数据栏: 42, hp: 100, label: "abc"};
        var child = parent.attachMovie("兵器攻击容器-重斩", "man", 0, init);
        assertTrue("child 不为 undefined", child != undefined);
        assertEquals("child.__name", "man", child.__name);
        assertEquals("child.__depth", 0, child.__depth);
        assertEquals("child.__parent", parent, child.__parent);
        assertEquals("child.数据栏 copy", 42, child.数据栏);
        assertEquals("child.hp copy", 100, child.hp);
        assertEquals("child.label copy", "abc", child.label);
    }

    private static function testAttachMovie_ExposesChildAsOwnProperty():Void {
        trace("\n--- testAttachMovie_ExposesChildAsOwnProperty ---");
        var parent:MockMovieClip = new MockMovieClip();
        var child = parent.attachMovie("L", "man", 0, {});
        assertEquals("parent.man === child", child, parent.man);
        assertEquals("parent.__children.man === child", child, parent.__children["man"]);
    }

    private static function testAttachMovie_MissingReturnsUndefined():Void {
        trace("\n--- testAttachMovie_MissingReturnsUndefined ---");
        var parent:MockMovieClip = new MockMovieClip();
        parent.__setMissingSymbol("missing-X");
        var result = parent.attachMovie("missing-X", "man", 0, {});
        assertTrue("missing → undefined", result === undefined);
        assertTrue("parent.man 未被设置", parent.man === undefined);
        assertTrue("parent.__children.man 未存在", parent.__children["man"] === undefined);
    }

    private static function testAttachMovie_MissingStillRecordsHistory():Void {
        trace("\n--- testAttachMovie_MissingStillRecordsHistory ---");
        var parent:MockMovieClip = new MockMovieClip();
        parent.__setMissingSymbol("missing-X");
        parent.attachMovie("missing-X", "man", 0, {x: 1});
        assertEquals("history.length=1", 1, parent.__initObjectsReceived.length);
        var rec:Object = parent.__initObjectsReceived[0];
        assertEquals("history.linkage", "missing-X", rec.linkage);
        assertEquals("history.missing=true", true, rec.missing);
    }

    private static function testAttachMovie_SameNameReplacesAndUnloadsOld():Void {
        trace("\n--- testAttachMovie_SameNameReplacesAndUnloadsOld ---");
        var parent:MockMovieClip = new MockMovieClip();
        var first = parent.attachMovie("L1", "man", 0, {});
        var unloadCalled:Number = 0;
        first.onUnload = function() { unloadCalled++; };
        var second = parent.attachMovie("L2", "man", 0, {});
        assertEquals("first.onUnload 被触发", 1, unloadCalled);
        assertEquals("first 已 detached", true, first.__removed);
        assertEquals("parent.man === second", second, parent.man);
        assertTrue("first !== second", first !== second);
    }

    private static function testAttachMovie_SnapshotIsolatesFutureMutation():Void {
        trace("\n--- testAttachMovie_SnapshotIsolatesFutureMutation ---");
        var parent:MockMovieClip = new MockMovieClip();
        var init:Object = {数据栏: 1};
        parent.attachMovie("L", "man", 0, init);
        init.数据栏 = 999;  // 测试: 后续 mutation 不影响 history snapshot
        var rec:Object = parent.__initObjectsReceived[0];
        assertEquals("history 快照 = 1", 1, rec.init.数据栏);
        // 但 child 上的 copy 是首次 enumerate 时的值（也应=1）
        assertEquals("child 字段保留首次值", 1, parent.man.数据栏);
    }

    // ════════════════════════════════════════════════════════════════════
    // removeMovieClip
    // ════════════════════════════════════════════════════════════════════

    private static function testRemoveMovieClip_TriggersOnUnload():Void {
        trace("\n--- testRemoveMovieClip_TriggersOnUnload ---");
        var parent:MockMovieClip = new MockMovieClip();
        var child = parent.attachMovie("L", "man", 0, {});
        var called:Number = 0;
        child.onUnload = function() { called++; };
        child.removeMovieClip();
        assertEquals("onUnload 触发 1 次", 1, called);
        assertEquals("__unloadCallCount=1", 1, child.__unloadCallCount);
        assertEquals("__removed=true", true, child.__removed);
    }

    private static function testRemoveMovieClip_Idempotent():Void {
        trace("\n--- testRemoveMovieClip_Idempotent ---");
        var parent:MockMovieClip = new MockMovieClip();
        var child = parent.attachMovie("L", "man", 0, {});
        var called:Number = 0;
        child.onUnload = function() { called++; };
        child.removeMovieClip();
        child.removeMovieClip();  // 二次调用
        child.removeMovieClip();  // 三次调用
        assertEquals("onUnload 只触发 1 次", 1, called);
        assertEquals("__unloadCallCount=1", 1, child.__unloadCallCount);
    }

    private static function testRemoveMovieClip_DetachesFromParent():Void {
        trace("\n--- testRemoveMovieClip_DetachesFromParent ---");
        var parent:MockMovieClip = new MockMovieClip();
        var child = parent.attachMovie("L", "man", 0, {});
        child.removeMovieClip();
        assertTrue("parent.__children.man 已删", parent.__children["man"] === undefined);
        assertTrue("parent.man 已删", parent.man === undefined);
        assertTrue("child.__parent 已 detach", child.__parent === undefined);
    }

    private static function testRemoveMovieClip_CascadesToChildren():Void {
        trace("\n--- testRemoveMovieClip_CascadesToChildren ---");
        var grand:MockMovieClip = new MockMovieClip();
        var parent = grand.attachMovie("Lp", "p", 0, {});
        var c1 = parent.attachMovie("L1", "c1", 0, {});
        var c2 = parent.attachMovie("L2", "c2", 0, {});
        var unloads:Array = [];
        parent.onUnload = function() { unloads.push("parent"); };
        c1.onUnload = function() { unloads.push("c1"); };
        c2.onUnload = function() { unloads.push("c2"); };
        parent.removeMovieClip();
        assertEquals("unload 总数=3", 3, unloads.length);
        assertEquals("c1 已 removed", true, c1.__removed);
        assertEquals("c2 已 removed", true, c2.__removed);
        assertEquals("parent 已 removed", true, parent.__removed);
        assertTrue("grand.__children.p 已删", grand.__children["p"] === undefined);
    }

    private static function testRemoveMovieClip_ChildUnloadBeforeParent():Void {
        trace("\n--- testRemoveMovieClip_ChildUnloadBeforeParent ---");
        var parent:MockMovieClip = new MockMovieClip();
        var child = parent.attachMovie("L", "c", 0, {});
        var order:Array = [];
        parent.onUnload = function() { order.push("parent"); };
        child.onUnload = function() { order.push("child"); };
        parent.removeMovieClip();
        assertEquals("order[0]=child", "child", order[0]);
        assertEquals("order[1]=parent", "parent", order[1]);
    }

    private static function testRemoveMovieClip_DetachedSignature():Void {
        trace("\n--- testRemoveMovieClip_DetachedSignature ---");
        var parent:MockMovieClip = new MockMovieClip();
        var child = parent.attachMovie("L", "man", 0, {hp: 50});
        child.removeMovieClip();
        // child 自身的 __parent / __children 清空
        assertTrue("child.__parent=undefined", child.__parent === undefined);
        // __removed=true 是 detached 标志
        assertEquals("child.__removed=true", true, child.__removed);
        // 再调 gotoAndStop / removeMovieClip 都是 no-op
        var beforeEpoch:Number = child.__frameEpoch;
        child.gotoAndStop("label-after-remove");
        assertEquals("detached gotoAndStop 不 bump frameEpoch",
            beforeEpoch, child.__frameEpoch);
    }

    // ════════════════════════════════════════════════════════════════════
    // onUnload chain
    // ════════════════════════════════════════════════════════════════════

    private static function testOnUnload_ChainPrevThenWrapper():Void {
        trace("\n--- testOnUnload_ChainPrevThenWrapper ---");
        var parent:MockMovieClip = new MockMovieClip();
        var child = parent.attachMovie("L", "man", 0, {});
        var order:Array = [];

        child.onUnload = function() { order.push("step1"); };

        // 模拟 RoutingIntent.bindContainerEndState 的 chain 写法
        var prev:Function = child.onUnload;
        child.onUnload = function() {
            if (prev != undefined) prev.apply(this);
            order.push("step2");
        };

        // 第三层
        var prev2:Function = child.onUnload;
        child.onUnload = function() {
            if (prev2 != undefined) prev2.apply(this);
            order.push("step3");
        };

        child.removeMovieClip();
        assertEquals("chain.length=3", 3, order.length);
        assertEquals("step1 first", "step1", order[0]);
        assertEquals("step2 second", "step2", order[1]);
        assertEquals("step3 third", "step3", order[2]);
    }

    private static function testOnUnload_SuppressByEmptyFn():Void {
        trace("\n--- testOnUnload_SuppressByEmptyFn ---");
        var parent:MockMovieClip = new MockMovieClip();
        var child = parent.attachMovie("L", "man", 0, {});
        var called:Number = 0;
        child.onUnload = function() { called++; };
        // 模拟 RoutingIntent.suppressOldManUnload 的覆盖写法
        child.onUnload = function() {};
        child.removeMovieClip();
        assertEquals("suppress 后旧 prev 不触发", 0, called);
        // __unloadCallCount 仍记录"onUnload 被调用"（虽然空函数）
        assertEquals("__unloadCallCount=1 (空函数也算)", 1, child.__unloadCallCount);
    }

    // ════════════════════════════════════════════════════════════════════
    // gotoAndStop
    // ════════════════════════════════════════════════════════════════════

    private static function testGotoAndStop_BumpsFrameEpoch():Void {
        trace("\n--- testGotoAndStop_BumpsFrameEpoch ---");
        var m:MockMovieClip = new MockMovieClip();
        assertEquals("初始 epoch=0", 0, m.__frameEpoch);
        m.gotoAndStop("frame-A");
        assertEquals("1 次后 epoch=1", 1, m.__frameEpoch);
        assertEquals("lastLabel=frame-A", "frame-A", m.__lastLabel);
        m.gotoAndStop("frame-B");
        assertEquals("2 次后 epoch=2", 2, m.__frameEpoch);
        assertEquals("lastLabel=frame-B", "frame-B", m.__lastLabel);
    }

    private static function testGotoAndStop_AfterRemoveIsNoOp():Void {
        trace("\n--- testGotoAndStop_AfterRemoveIsNoOp ---");
        var parent:MockMovieClip = new MockMovieClip();
        var child = parent.attachMovie("L", "man", 0, {});
        child.gotoAndStop("frame-A");
        var epochBefore:Number = child.__frameEpoch;
        child.removeMovieClip();
        child.gotoAndStop("frame-B");
        assertEquals("removed 后 gotoAndStop 不 bump epoch",
            epochBefore, child.__frameEpoch);
        // lastLabel 也保留 remove 之前的值（gotoAndStop 整体 no-op）
        assertEquals("lastLabel 保留 frame-A", "frame-A", child.__lastLabel);
    }

    private static function testGotoAndStop_DoesNotRemoveChildren():Void {
        trace("\n--- testGotoAndStop_DoesNotRemoveChildren ---");
        // 契约 §1：gotoAndStop 在本 mock 不主动 remove 子级。
        // 旧帧 owned-context poison 由业务代码显式 epoch token 检查实现（III.4 范围）。
        var parent:MockMovieClip = new MockMovieClip();
        var child = parent.attachMovie("L", "man", 0, {});
        var unloadCalled:Number = 0;
        child.onUnload = function() { unloadCalled++; };
        parent.gotoAndStop("new-frame");
        assertEquals("子级未被 remove", false, child.__removed);
        assertEquals("子级 onUnload 未触发", 0, unloadCalled);
        assertEquals("parent.man 仍指向 child", child, parent.man);
    }
}