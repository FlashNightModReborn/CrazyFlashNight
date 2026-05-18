import org.flashNight.arki.unit.UnitComponent.Routing.RoutingIntent;

/**
 * RoutingIntent Test Suite
 *
 * 第三步起步：把 RoutingIntent 中不涉及 Flash runtime 黑箱（attachMovie / gotoAndStop /
 * onClipEvent）的部分用 plain object 模拟 unit/man 跑一遍，验证：
 *  - 同帧跳转保护跨帧/跨 kind 的语义
 *  - 状态切换作业的 lazy-alloc / arg 重置 / consumer 标空闲 / 兜底清理 不变量
 *  - bindContainerEndState 的 onUnload chain + 写状态语义
 *  - 状态/帧名常量值
 *
 * 帧戳作为参数直接传给 mark/is，不再有全局帧时钟注入机制 —
 * 真正的纯函数 surface：测试直接 RoutingIntent.isWeaponSameFrameJump(u, 42)。
 *
 * AS2 strict 类型注意：fake unit/man 都是 plain Object 字面量，调用 RoutingIntent.*
 * 这种声明 `:MovieClip` 形参的方法时必须 untyped 传递（[[feedback-as2-strict-function-param-dynamic-path]]）。
 * 因此本文件内 var 一律 untyped（不写 `:Object`/`:Function`），让编译器把它当 untyped expr 处理。
 *
 * 用法： org.flashNight.arki.unit.UnitComponent.Routing.RoutingIntentTest.runAll();
 */
class org.flashNight.arki.unit.UnitComponent.Routing.RoutingIntentTest {

    private static var testCount:Number = 0;
    private static var passedTests:Number = 0;
    private static var failedTests:Number = 0;

    // ====================================================================
    // 断言工具
    // ====================================================================

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

    private static function assertFalse(name:String, cond:Boolean):Void {
        assertTrue(name, !cond);
    }

    private static function assertSame(name:String, expectedRef, actualRef):Void {
        testCount++;
        if (expectedRef === actualRef) {
            passedTests++;
            trace("  [PASS] " + name);
        } else {
            failedTests++;
            trace("  [FAIL] " + name + " (ref mismatch)");
        }
    }

    // ====================================================================
    // 夹具构造（所有 fake 字段 untyped；method 内挂的 spy 字段用 untyped this[*]）
    // ====================================================================

    private static function makeUnit(name:String) {
        var u = {
            _name: name,
            状态: undefined,
            旧状态: undefined,
            __stateGotoLabel: undefined,
            __stateTransitionJob: undefined,
            __skipWeaponChangeFrame: undefined,
            __skipBarehandChangeFrame: undefined,
            __spy_stateChangeCount: 0,
            __spy_stateChangeLast: undefined,
            __spy_bigLast: undefined,
            __spy_smallLast: undefined,
            __spy_bigCount: 0
        };
        u.状态改变 = function(s) {
            this.__spy_stateChangeCount++;
            this.__spy_stateChangeLast = s;
        };
        u.UpdateBigSmallState = function(big, small) {
            this.__spy_bigCount++;
            this.__spy_bigLast = big;
            this.__spy_smallLast = small;
        };
        return u;
    }

    private static function makeMan() {
        return {
            __isDynamicMan: true,
            onUnload: undefined
        };
    }

    // ====================================================================
    // 测试入口
    // ====================================================================

    public static function runAll():Boolean {
        trace("================================================================");
        trace("RoutingIntent Test Suite");
        trace("================================================================");

        var t0:Number = getTimer();
        testCount = 0;
        passedTests = 0;
        failedTests = 0;

        testConstants();
        testSameFrameJumpWeapon();
        testSameFrameJumpBarehand();
        testSameFrameJumpIsolation();
        testCreateJobLazyAlloc();
        testCreateJobReusesObject();
        testCreateJobClearsArgs();
        testGetJobGotoOverride();
        testExecuteJobConsumesCallback();
        testExecuteJobNoOpWhenIdle();
        testClearJobResetsAllFields();
        testSuppressOldManUnload();
        testSuppressOldManUnloadNoMan();
        testBindContainerEndState();
        testBindContainerEndStateChainsPrev();
        testBindContainerEndStateUndefinedMan();
        testDumpStateBasic();

        var elapsed:Number = getTimer() - t0;
        trace("================================================================");
        trace("Results: " + passedTests + "/" + testCount + " passed, "
              + failedTests + " failed (" + elapsed + "ms)");
        trace("================================================================");
        return failedTests == 0;
    }

    // ====================================================================
    // 常量
    // ====================================================================

    private static function testConstants():Void {
        trace("\n--- testConstants ---");
        assertEquals("LABEL_CONTAINER",        "容器",         RoutingIntent.LABEL_CONTAINER);
        assertEquals("STATE_WEAPON",           "兵器攻击",     RoutingIntent.STATE_WEAPON);
        assertEquals("STATE_WEAPON_CONTAINER", "兵器攻击容器", RoutingIntent.STATE_WEAPON_CONTAINER);
        assertEquals("STATE_BAREHAND",         "空手攻击",     RoutingIntent.STATE_BAREHAND);
        assertEquals("BIG_END_PUNCH",          "普攻结束",     RoutingIntent.BIG_END_PUNCH);
        assertEquals("SMALL_END_WEAPON",       "兵器攻击结束", RoutingIntent.SMALL_END_WEAPON);
        assertEquals("SMALL_END_BAREHAND",     "空手攻击结束", RoutingIntent.SMALL_END_BAREHAND);
    }

    // ====================================================================
    // 同帧跳转保护 — 帧戳作为参数直接传，纯函数
    // ====================================================================

    private static function testSameFrameJumpWeapon():Void {
        trace("\n--- testSameFrameJumpWeapon ---");
        var u = makeUnit("w");

        assertFalse("frame=10 未标记 → false", RoutingIntent.isWeaponSameFrameJump(u, 10));

        RoutingIntent.markWeaponSameFrameJump(u, 10);
        assertTrue("frame=10 标记后同帧 → true", RoutingIntent.isWeaponSameFrameJump(u, 10));

        // 跨帧：标 10 查 11
        assertFalse("frame=11 跨帧 → false", RoutingIntent.isWeaponSameFrameJump(u, 11));

        // 标 11 后查 10：仍 false（unit 上记录的是帧戳，不是 boolean，回到旧帧也不匹配）
        RoutingIntent.markWeaponSameFrameJump(u, 11);
        assertFalse("回到旧帧 → false", RoutingIntent.isWeaponSameFrameJump(u, 10));
    }

    private static function testSameFrameJumpBarehand():Void {
        trace("\n--- testSameFrameJumpBarehand ---");
        var u = makeUnit("b");

        assertFalse("未标记 → false", RoutingIntent.isBarehandSameFrameJump(u, 20));

        RoutingIntent.markBarehandSameFrameJump(u, 20);
        assertTrue("标记后同帧 → true", RoutingIntent.isBarehandSameFrameJump(u, 20));

        assertFalse("跨帧 → false", RoutingIntent.isBarehandSameFrameJump(u, 21));
    }

    private static function testSameFrameJumpIsolation():Void {
        trace("\n--- testSameFrameJumpIsolation ---");
        var u = makeUnit("iso");

        RoutingIntent.markWeaponSameFrameJump(u, 30);

        assertTrue("weapon 同帧 → true",   RoutingIntent.isWeaponSameFrameJump(u, 30));
        assertFalse("barehand 不应受影响", RoutingIntent.isBarehandSameFrameJump(u, 30));

        RoutingIntent.markBarehandSameFrameJump(u, 30);
        assertTrue("barehand 同帧 → true", RoutingIntent.isBarehandSameFrameJump(u, 30));
        assertTrue("weapon 仍同帧 → true", RoutingIntent.isWeaponSameFrameJump(u, 30));

        // 兵器与空手字段独立：同一 unit 不同帧也不互相覆盖
        RoutingIntent.markWeaponSameFrameJump(u, 31);
        assertEquals("weapon 字段更新到 31", 31, u.__skipWeaponChangeFrame);
        assertEquals("barehand 字段保留 30",  30, u.__skipBarehandChangeFrame);
    }

    // ====================================================================
    // 状态切换作业
    // ====================================================================

    private static function testCreateJobLazyAlloc():Void {
        trace("\n--- testCreateJobLazyAlloc ---");
        var u = makeUnit("c1");
        assertEquals("初始 job undefined", undefined, u.__stateTransitionJob);

        var noop = function(unit):Void {};
        var job = RoutingIntent.createStateTransitionJob(u, "容器", noop);

        assertTrue("create 后 job 非空", job != undefined);
        assertSame("unit.__stateTransitionJob 指向同一对象", job, u.__stateTransitionJob);
        assertEquals("job.gotoLabel", "容器", job.gotoLabel);
        assertSame("job.callback 指向同一 fn", noop, job.callback);
    }

    private static function testCreateJobReusesObject():Void {
        trace("\n--- testCreateJobReusesObject ---");
        var u = makeUnit("c2");

        var noop = function(unit):Void {};
        var job1 = RoutingIntent.createStateTransitionJob(u, "label1", noop);
        var job2 = RoutingIntent.createStateTransitionJob(u, "label2", noop);
        assertSame("第二次 create 复用同一对象", job1, job2);
        assertEquals("第二次 gotoLabel 覆盖", "label2", job2.gotoLabel);
    }

    private static function testCreateJobClearsArgs():Void {
        trace("\n--- testCreateJobClearsArgs ---");
        var u = makeUnit("c3");

        var noop = function(unit):Void {};
        var job = RoutingIntent.createStateTransitionJob(u, "labelA", noop);
        job.arg_containerName = "破极拳1连招";
        job.arg_targetLabel = "破极拳5连招";

        var job2 = RoutingIntent.createStateTransitionJob(u, "labelB", noop);
        assertEquals("arg_containerName 已清零", undefined, job2.arg_containerName);
        assertEquals("arg_targetLabel 已清零", undefined, job2.arg_targetLabel);
    }

    private static function testGetJobGotoOverride():Void {
        trace("\n--- testGetJobGotoOverride ---");
        var u = makeUnit("g1");
        assertEquals("无 job 时 null", null, RoutingIntent.getJobGotoOverride(u));

        var noop = function(unit):Void {};
        RoutingIntent.createStateTransitionJob(u, "容器", noop);
        assertEquals("create 后返回 gotoLabel", "容器", RoutingIntent.getJobGotoOverride(u));

        RoutingIntent.clearStateTransitionJob(u);
        assertEquals("clear 后 null", null, RoutingIntent.getJobGotoOverride(u));
    }

    private static function testExecuteJobConsumesCallback():Void {
        trace("\n--- testExecuteJobConsumesCallback ---");
        var u = makeUnit("e1");

        var capturedJobState = { goto: "<unset>", cb: "<unset>" };
        var cbCallCount:Number = 0;

        var cb = function(unit):Void {
            cbCallCount++;
            var j = unit.__stateTransitionJob;
            capturedJobState.goto = j.gotoLabel;
            capturedJobState.cb = j.callback;
        };

        RoutingIntent.createStateTransitionJob(u, "容器", cb);
        RoutingIntent.executeStateTransitionJob(u);

        assertEquals("callback 被调用 1 次", 1, cbCallCount);
        assertEquals("callback 内看到 gotoLabel 已 undefined", undefined, capturedJobState.goto);
        assertEquals("callback 内看到 callback 字段已 undefined", undefined, capturedJobState.cb);
        assertTrue("job 对象保留（未 delete）", u.__stateTransitionJob != undefined);
    }

    private static function testExecuteJobNoOpWhenIdle():Void {
        trace("\n--- testExecuteJobNoOpWhenIdle ---");

        var u = makeUnit("e2");
        RoutingIntent.executeStateTransitionJob(u);
        assertEquals("job 仍 undefined", undefined, u.__stateTransitionJob);

        var u2 = makeUnit("e2b");
        u2.__stateTransitionJob = { gotoLabel: undefined, callback: undefined };
        RoutingIntent.executeStateTransitionJob(u2);
        assertTrue("idle job 调 execute 不抛异常", true);
    }

    private static function testClearJobResetsAllFields():Void {
        trace("\n--- testClearJobResetsAllFields ---");
        var u = makeUnit("clr");

        var noop = function(unit):Void {};
        var job = RoutingIntent.createStateTransitionJob(u, "容器", noop);
        job.arg_containerName = "A";
        job.arg_targetLabel = "B";

        RoutingIntent.clearStateTransitionJob(u);
        assertEquals("gotoLabel 清零", undefined, job.gotoLabel);
        assertEquals("callback 清零", undefined, job.callback);
        assertEquals("arg_containerName 清零", undefined, job.arg_containerName);
        assertEquals("arg_targetLabel 清零", undefined, job.arg_targetLabel);
        assertTrue("对象本身保留", u.__stateTransitionJob != undefined);

        var u2 = makeUnit("clr2");
        RoutingIntent.clearStateTransitionJob(u2);
        assertTrue("无 job 调 clear 不抛异常", true);
    }

    // ====================================================================
    // 屏蔽旧 man 卸载
    // ====================================================================

    private static function testSuppressOldManUnload():Void {
        trace("\n--- testSuppressOldManUnload ---");
        var u = makeUnit("s1");
        var unloadCount:Number = 0;
        u.man = makeMan();
        u.man.onUnload = function() { unloadCount++; };

        RoutingIntent.suppressOldManUnload(u);

        u.man.onUnload();
        assertEquals("旧 onUnload 已被替换为 no-op", 0, unloadCount);
    }

    private static function testSuppressOldManUnloadNoMan():Void {
        trace("\n--- testSuppressOldManUnloadNoMan ---");
        var u = makeUnit("s2");
        RoutingIntent.suppressOldManUnload(u);
        assertTrue("无 man 时不抛异常", true);
    }

    // ====================================================================
    // bindContainerEndState
    // ====================================================================

    private static function testBindContainerEndState():Void {
        trace("\n--- testBindContainerEndState ---");
        var u = makeUnit("b1");
        var man = makeMan();

        RoutingIntent.bindContainerEndState(man, u, RoutingIntent.SMALL_END_WEAPON);
        assertTrue("man.onUnload 已绑定", man.onUnload != undefined);

        man.onUnload();

        assertEquals("UpdateBigSmallState 被调用 1 次", 1, u.__spy_bigCount);
        assertEquals("big = BIG_END_PUNCH",          "普攻结束",     u.__spy_bigLast);
        assertEquals("small = SMALL_END_WEAPON",     "兵器攻击结束", u.__spy_smallLast);
    }

    private static function testBindContainerEndStateChainsPrev():Void {
        trace("\n--- testBindContainerEndStateChainsPrev ---");
        var u = makeUnit("b2");
        var man = makeMan();
        var prevCallCount:Number = 0;
        man.onUnload = function() { prevCallCount++; };

        RoutingIntent.bindContainerEndState(man, u, RoutingIntent.SMALL_END_BAREHAND);
        man.onUnload();

        assertEquals("前序 onUnload 被调用 1 次", 1, prevCallCount);
        assertEquals("UpdateBigSmallState 被调用 1 次", 1, u.__spy_bigCount);
        assertEquals("small = SMALL_END_BAREHAND",   "空手攻击结束", u.__spy_smallLast);
    }

    private static function testBindContainerEndStateUndefinedMan():Void {
        trace("\n--- testBindContainerEndStateUndefinedMan ---");
        var u = makeUnit("b3");
        RoutingIntent.bindContainerEndState(undefined, u, RoutingIntent.SMALL_END_WEAPON);
        assertEquals("UpdateBigSmallState 未被调用", 0, u.__spy_bigCount);
    }

    // ====================================================================
    // dumpState
    // ====================================================================

    private static function testDumpStateBasic():Void {
        // dumpStateAtFrame 显式传入帧戳，避免 TestLoader 依赖真实 _root.帧计时器。
        trace("\n--- testDumpStateBasic ---");

        assertEquals("undefined unit", "[路由dump] unit=undefined", RoutingIntent.dumpState(undefined));

        var u = makeUnit("dump1");
        u.状态 = "兵器攻击";
        u.兵器攻击名 = "刀剑1连招";
        u.浮空 = false;
        u._y = 300;
        u.Z轴坐标 = 300;

        RoutingIntent.markWeaponSameFrameJump(u, 42);

        var s:String = RoutingIntent.dumpStateAtFrame(u, 99);
        assertTrue("含 帧=99", s.indexOf("帧=99") >= 0);
        assertTrue("含 unit.name", s.indexOf("name=dump1") >= 0);
        assertTrue("含 状态",      s.indexOf("状态=兵器攻击") >= 0);
        assertTrue("含 兵器攻击名", s.indexOf("兵器攻击名=刀剑1连招") >= 0);
        assertTrue("含 __skipWeapon=42", s.indexOf("__skipWeapon=42") >= 0);
        assertTrue("含 job=undefined", s.indexOf("job=undefined") >= 0);
        assertTrue("含 man=false",  s.indexOf("man=false") >= 0);
    }
}
