import org.flashNight.arki.unit.UnitComponent.Routing.*;

/**
 * ContainerAttachAction Test Suite
 *
 * 覆盖：
 *   - happy path: 4 kind × 成功 attach → STATUS_OK + man 来自 adapter + linkage 拼接正确
 *   - missing path: 4 kind × adapter 返回 undefined →
 *       weapon / unarmed → STATUS_MISSING_ABORT
 *       skill / battleSkill → STATUS_MISSING_SILENT_CONTINUE
 *   - linkage 字段在 result 上正确暴露
 *   - initObject 完整传到低层 adapter（端到端）
 *
 * 测试机制：通过 RoutingRuntime.setAttachMovieAdapterForTest 注入 spy adapter，
 * 不依赖真实 MovieClip。
 */
class org.flashNight.arki.unit.UnitComponent.Routing.ContainerAttachActionTest {

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
        trace("ContainerAttachAction Test Suite");
        trace("================================================================");

        var t0:Number = getTimer();
        testCount = 0;
        passedTests = 0;
        failedTests = 0;

        testAttach_Happy_Weapon();
        testAttach_Happy_Unarmed();
        testAttach_Happy_Skill();
        testAttach_Happy_BattleSkill();

        testAttach_Missing_Weapon_Abort();
        testAttach_Missing_Unarmed_Abort();
        testAttach_Missing_Skill_SilentContinue();
        testAttach_Missing_BattleSkill_SilentContinue();

        testAttach_LinkageFieldOnResult();
        testAttach_InitObjectPassThrough();
        testAttach_UnknownKind_DefaultsToAbort();
        testAttach_AdapterCalledWithCorrectArgs();

        // Pre.4 反向断言：ContainerSpec.allKinds() 驱动的 happy + missing 全覆盖
        testAllKinds_HappyMapsToOk();
        testAllKinds_MissingHasRegisteredFallback();

        // 兜底
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

    /** 装一个 always-returns spy adapter */
    private static function installSpyAdapter(returnValue):Object {
        var a:Object = {};
        a.calls = [];
        a.__returnValue = returnValue;
        a.attachMovie = function(parent, linkage, name, depth, initObj) {
            this.calls.push({parent: parent, linkage: linkage, name: name, depth: depth, init: initObj});
            return this.__returnValue;
        };
        RoutingRuntime.setAttachMovieAdapterForTest(a);
        return a;
    }

    private static function fakeUnit():Object {
        var u:Object = {};
        u._name = "spy-unit";
        return u;
    }

    private static function fakeMan(tag:String):Object {
        var m:Object = {};
        m.__tag = tag;
        return m;
    }

    // ====================================================================
    // happy path: 4 kind
    // ====================================================================

    private static function testAttach_Happy_Weapon():Void {
        trace("\n--- testAttach_Happy_Weapon ---");
        var man = fakeMan("weapon-man");
        installSpyAdapter(man);
        var result:Object = ContainerAttachAction.attach(fakeUnit(),
            ContainerSpec.KIND_WEAPON, "重斩", {});
        assertEquals("status = OK", ContainerAttachAction.STATUS_OK, result.status);
        assertEquals("man = spy 返回值", man, result.man);
        assertEquals("linkage = 兵器攻击容器-重斩", "兵器攻击容器-重斩", result.linkage);
    }

    private static function testAttach_Happy_Unarmed():Void {
        trace("\n--- testAttach_Happy_Unarmed ---");
        var man = fakeMan("unarmed-man");
        installSpyAdapter(man);
        var result:Object = ContainerAttachAction.attach(fakeUnit(),
            ContainerSpec.KIND_UNARMED, "1连招", {});
        assertEquals("status = OK", ContainerAttachAction.STATUS_OK, result.status);
        assertEquals("man = spy 返回值", man, result.man);
        assertEquals("linkage = 空手攻击容器-1连招", "空手攻击容器-1连招", result.linkage);
    }

    private static function testAttach_Happy_Skill():Void {
        trace("\n--- testAttach_Happy_Skill ---");
        var man = fakeMan("skill-man");
        installSpyAdapter(man);
        var result:Object = ContainerAttachAction.attach(fakeUnit(),
            ContainerSpec.KIND_SKILL, "升龙拳", {});
        assertEquals("status = OK", ContainerAttachAction.STATUS_OK, result.status);
        assertEquals("man = spy 返回值", man, result.man);
        assertEquals("linkage = 技能容器-升龙拳", "技能容器-升龙拳", result.linkage);
    }

    private static function testAttach_Happy_BattleSkill():Void {
        trace("\n--- testAttach_Happy_BattleSkill ---");
        var man = fakeMan("bs-man");
        installSpyAdapter(man);
        var result:Object = ContainerAttachAction.attach(fakeUnit(),
            ContainerSpec.KIND_BATTLE_SKILL, "双刀变长柄", {});
        assertEquals("status = OK", ContainerAttachAction.STATUS_OK, result.status);
        assertEquals("man = spy 返回值", man, result.man);
        assertEquals("linkage = 战技容器-双刀变长柄", "战技容器-双刀变长柄", result.linkage);
    }

    // ====================================================================
    // missing path: 4 kind × fallback 分流
    // ====================================================================

    private static function testAttach_Missing_Weapon_Abort():Void {
        trace("\n--- testAttach_Missing_Weapon_Abort ---");
        installSpyAdapter(undefined);
        var result:Object = ContainerAttachAction.attach(fakeUnit(),
            ContainerSpec.KIND_WEAPON, "不存在的招", {});
        assertEquals("status = MISSING_ABORT",
            ContainerAttachAction.STATUS_MISSING_ABORT, result.status);
        assertTrue("man = undefined", result.man === undefined);
        assertEquals("linkage 仍暴露", "兵器攻击容器-不存在的招", result.linkage);
    }

    private static function testAttach_Missing_Unarmed_Abort():Void {
        trace("\n--- testAttach_Missing_Unarmed_Abort ---");
        installSpyAdapter(undefined);
        var result:Object = ContainerAttachAction.attach(fakeUnit(),
            ContainerSpec.KIND_UNARMED, "不存在的连招", {});
        assertEquals("status = MISSING_ABORT",
            ContainerAttachAction.STATUS_MISSING_ABORT, result.status);
        assertTrue("man = undefined", result.man === undefined);
    }

    private static function testAttach_Missing_Skill_SilentContinue():Void {
        trace("\n--- testAttach_Missing_Skill_SilentContinue ---");
        installSpyAdapter(undefined);
        var result:Object = ContainerAttachAction.attach(fakeUnit(),
            ContainerSpec.KIND_SKILL, "不存在的技能", {});
        assertEquals("status = MISSING_SILENT_CONTINUE",
            ContainerAttachAction.STATUS_MISSING_SILENT_CONTINUE, result.status);
        assertTrue("man = undefined", result.man === undefined);
    }

    private static function testAttach_Missing_BattleSkill_SilentContinue():Void {
        trace("\n--- testAttach_Missing_BattleSkill_SilentContinue ---");
        installSpyAdapter(undefined);
        var result:Object = ContainerAttachAction.attach(fakeUnit(),
            ContainerSpec.KIND_BATTLE_SKILL, "不存在的战技", {});
        assertEquals("status = MISSING_SILENT_CONTINUE",
            ContainerAttachAction.STATUS_MISSING_SILENT_CONTINUE, result.status);
        assertTrue("man = undefined", result.man === undefined);
    }

    // ====================================================================
    // 字段 / 透传 / 未注册 kind
    // ====================================================================

    private static function testAttach_LinkageFieldOnResult():Void {
        trace("\n--- testAttach_LinkageFieldOnResult ---");
        installSpyAdapter(fakeMan("m"));
        var r:Object = ContainerAttachAction.attach(fakeUnit(),
            ContainerSpec.KIND_SKILL, "test", {});
        assertEquals("linkage 字段类型 String", "string", typeof r.linkage);
        assertEquals("linkage 字面", "技能容器-test", r.linkage);
    }

    private static function testAttach_InitObjectPassThrough():Void {
        trace("\n--- testAttach_InitObjectPassThrough ---");
        var adapter = installSpyAdapter(fakeMan("m"));
        var initObj:Object = {数据栏: 42, hello: "world"};
        ContainerAttachAction.attach(fakeUnit(),
            ContainerSpec.KIND_WEAPON, "重斩", initObj);
        var lastCall:Object = adapter.calls[0];
        assertEquals("initObj 引用透传到低层 adapter", initObj, lastCall.init);
        assertEquals("initObj.数据栏 字段保留", 42, lastCall.init.数据栏);
        assertEquals("initObj.hello 字段保留", "world", lastCall.init.hello);
    }

    private static function testAttach_UnknownKind_DefaultsToAbort():Void {
        trace("\n--- testAttach_UnknownKind_DefaultsToAbort ---");
        // 未知 kind: ContainerSpec.buildLinkageName 返回 "undefined-x",
        // adapter 同样返回 undefined,fallback 查表返回 undefined,
        // ContainerAttachAction 应退到 ABORT（防御漏注册）
        installSpyAdapter(undefined);
        var result:Object = ContainerAttachAction.attach(fakeUnit(),
            "unregistered_kind", "x", {});
        assertEquals("未注册 kind 退化为 ABORT",
            ContainerAttachAction.STATUS_MISSING_ABORT, result.status);
    }

    private static function testAttach_AdapterCalledWithCorrectArgs():Void {
        trace("\n--- testAttach_AdapterCalledWithCorrectArgs ---");
        var adapter = installSpyAdapter(fakeMan("m"));
        var unit:Object = fakeUnit();
        var initObj:Object = {x: 1};
        ContainerAttachAction.attach(unit, ContainerSpec.KIND_SKILL, "升龙拳", initObj);
        var c:Object = adapter.calls[0];
        assertEquals("adapter 收到 unit", unit, c.parent);
        assertEquals("adapter 收到 linkage", "技能容器-升龙拳", c.linkage);
        assertEquals("adapter 收到 name='man'", "man", c.name);
        assertEquals("adapter 收到 depth=0", 0, c.depth);
        assertEquals("adapter 收到 initObj", initObj, c.init);
    }

    // ====================================================================
    // Pre.4 反向断言：ContainerSpec.allKinds() driven 全覆盖
    // ====================================================================

    /**
     * 反向断言：ContainerSpec.allKinds() 中每个 kind，attach 成功路径都映射到 STATUS_OK。
     *
     * Tripwire 语义：如果有人扩了 ContainerSpec.KIND_* 但忘记在 ContainerAttachAction 里
     * 处理新 kind 的 happy path，本断言会立刻 FAIL。
     */
    private static function testAllKinds_HappyMapsToOk():Void {
        trace("\n--- testAllKinds_HappyMapsToOk ---");
        var kinds:Array = ContainerSpec.allKinds();
        for (var i:Number = 0; i < kinds.length; i++) {
            var kind:String = kinds[i];
            installSpyAdapter(fakeMan("happy-" + kind));
            var result:Object = ContainerAttachAction.attach(fakeUnit(), kind, "测试招", {});
            assertEquals("kind=" + kind + " 成功 → STATUS_OK",
                ContainerAttachAction.STATUS_OK, result.status);
            assertTrue("kind=" + kind + " man 非 undefined", result.man != undefined);
        }
    }

    /**
     * 反向断言：ContainerSpec.allKinds() 中每个 kind，missing 路径必须命中 ABORT 或
     * SILENT_CONTINUE 之一（即 ContainerSpec.getMissingFallback 必须显式注册）。
     *
     * Tripwire 语义：如果加了新 kind 但忘记在 getMissingFallback 注册 →
     * ContainerAttachAction.attach 走防御退化路径 (STATUS_MISSING_ABORT)，本断言不会
     * 自己 FAIL，因为退化也是合法 STATUS_MISSING_ABORT；所以这里还要交叉验：
     * 对于每个 kind，ContainerSpec.getMissingFallback(kind) 必须返回非 undefined。
     */
    private static function testAllKinds_MissingHasRegisteredFallback():Void {
        trace("\n--- testAllKinds_MissingHasRegisteredFallback ---");
        var kinds:Array = ContainerSpec.allKinds();
        for (var i:Number = 0; i < kinds.length; i++) {
            var kind:String = kinds[i];
            // (a) getMissingFallback 必须显式注册（非 undefined），不依赖防御退化
            var fb:String = ContainerSpec.getMissingFallback(kind);
            assertTrue("kind=" + kind + " getMissingFallback 已注册",
                fb === ContainerSpec.FALLBACK_ABORT
                || fb === ContainerSpec.FALLBACK_SILENT_CONTINUE);

            // (b) ContainerAttachAction.attach 在 missing 路径下 status 与 fb 一致
            installSpyAdapter(undefined);
            var result:Object = ContainerAttachAction.attach(fakeUnit(), kind, "missing-x", {});
            var expectedStatus:String = (fb === ContainerSpec.FALLBACK_SILENT_CONTINUE)
                ? ContainerAttachAction.STATUS_MISSING_SILENT_CONTINUE
                : ContainerAttachAction.STATUS_MISSING_ABORT;
            assertEquals("kind=" + kind + " missing status 与 fallback 注册一致",
                expectedStatus, result.status);
        }
    }
}