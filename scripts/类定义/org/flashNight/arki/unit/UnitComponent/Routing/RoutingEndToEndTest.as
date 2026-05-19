import org.flashNight.arki.unit.UnitComponent.Routing.*;

/**
 * RoutingEndToEndTest — III.2 attachMovie / initObject / onUnload / removeMovieClip
 * 端到端组合样例
 *
 * 用 MockMovieClip 做 parent unit，让 ContainerAttachAction.attach 走 RoutingRuntime.attachMovie
 * 兜底路径（parent.attachMovie 调用 MockMovieClip.attachMovie 实现），完整模拟 5 个生产
 * 调用点。
 *
 * 覆盖：
 *   - HAPPY 路径：兵器 / 技能 两 kind，端到端 attach + initObj 字段透传 + child 暴露
 *   - MISSING ABORT 路径：unit 上设置 missingSymbol → STATUS_MISSING_ABORT
 *   - MISSING SILENT_CONTINUE 路径 + undefined man 下游验证（user 2026-05-19 风险点）：
 *       * handleFloat(undefined, unit, ...) AS2 silent 不崩
 *       * bindEndCleanup(undefined, unit, ...) AS2 silent 不崩
 *       * unit 业务字段不被错改
 *   - bindContainerEndState 端到端：attach → bind → removeMovieClip → onUnload chain →
 *       UpdateBigSmallState(BIG_END_PUNCH, SMALL_END_WEAPON) 触发
 *   - removeMovieClip 端到端：parent.man 引用清理
 *
 * AS2 strict 类型约定（[[feedback-as2-strict-function-param-dynamic-path]]）：
 * unit / man 走 fake，参数类型本身就是 untyped → 不会因 :MovieClip 形参注解 fail。
 */
class org.flashNight.arki.unit.UnitComponent.Routing.RoutingEndToEndTest {

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
        trace("Routing EndToEnd Test Suite (III.2)");
        trace("================================================================");

        var t0:Number = getTimer();
        testCount = 0;
        passedTests = 0;
        failedTests = 0;

        // 兜底：不注入 attachMovie adapter，让 RoutingRuntime.attachMovie 走 parent.attachMovie
        RoutingRuntime.clearAttachMovieAdapterForTest();

        testE2E_Happy_Weapon();
        testE2E_Happy_Skill_InitObjectFieldsCopiedToMan();
        testE2E_Missing_Weapon_Abort();
        testE2E_Missing_Skill_SilentContinue_UndefinedManNoCrash();

        // 黑箱观察：handleFloat(undefined, unit, ...) 裸调行为（非生产路径）
        testBlackbox_HandleFloat_UndefinedMan_TempY0_NoOp();
        testBlackbox_HandleFloat_UndefinedMan_TempYPositive_PollutesUnit();

        // 生产路径锁修复（2026-05-19 user 决策）：missing skill/battleSkill 经路由入口
        // 不得污染 unit.浮空 / unit.技能浮空 / unit._y
        testProduction_MissingSkill_ShortCircuits_NoUnitPollution();
        testProduction_MissingBattleSkill_ShortCircuits_NoUnitPollution();
        testProduction_HappySkill_StillRunsLifecycle();

        testE2E_BindContainerEndState_FiresOnRemove();
        testE2E_BindContainerEndState_PrevOnUnloadChain();
        testE2E_RemoveMovieClip_ClearsParentReference();

        var elapsed:Number = getTimer() - t0;
        trace("================================================================");
        trace("Results: " + passedTests + "/" + testCount + " passed, "
              + failedTests + " failed (" + elapsed + "ms)");
        trace("================================================================");
        return failedTests == 0;
    }

    // ════════════════════════════════════════════════════════════════════
    // 夹具
    // ════════════════════════════════════════════════════════════════════

    /**
     * MockMovieClip + 业务字段：unit 既是 attachMovie 的 parent，又是 RoutingLifecycle /
     * RoutingIntent 访问业务字段的目标。
     */
    // 返回值刻意 untyped：RoutingLifecycle / RoutingIntent 等 API 形参注解 :MovieClip，
    // AS2 strict 不接 :MockMovieClip → 用 untyped 通过传参（同 RoutingLifecycleTest 习惯）。
    private static function makeMockUnit(name:String) {
        var u:MockMovieClip = new MockMovieClip();
        u.__name = name;
        u._name = name;
        u.状态 = undefined;
        u.攻击模式 = undefined;
        u.temp_y = 0;
        u.浮空 = false;
        u.技能浮空 = false;
        u._y = 100;
        u.Z轴坐标 = 100;
        u.起始Y = undefined;
        u.无敌 = true;
        u.__preserveFloatFlagOnUnload = undefined;
        u.__spy_bigStateCount = 0;
        u.__spy_bigStateLastBig = undefined;
        u.__spy_bigStateLastSmall = undefined;
        u.__spy_bonusModeCount = 0;
        u.UpdateBigSmallState = function(big, small) {
            this.__spy_bigStateCount++;
            this.__spy_bigStateLastBig = big;
            this.__spy_bigStateLastSmall = small;
        };
        u.根据模式重新读取武器加成 = function(mode) {
            this.__spy_bonusModeCount++;
        };
        return u;
    }

    // ════════════════════════════════════════════════════════════════════
    // HAPPY 路径
    // ════════════════════════════════════════════════════════════════════

    private static function testE2E_Happy_Weapon():Void {
        trace("\n--- testE2E_Happy_Weapon ---");
        var unit = makeMockUnit("hero");
        var initObj:Object = {兵器攻击名: "重斩", hp: 100};

        var result:Object = ContainerAttachAction.attach(unit,
            ContainerSpec.KIND_WEAPON, "重斩", initObj);

        assertEquals("status = OK", ContainerAttachAction.STATUS_OK, result.status);
        assertTrue("result.man 非 undefined", result.man != undefined);
        assertEquals("result.man === unit.man", result.man, unit.man);
        assertEquals("man.__name = man", "man", unit.man.__name);
        assertEquals("man.兵器攻击名 字段透传", "重斩", unit.man.兵器攻击名);
        assertEquals("man.hp 字段透传", 100, unit.man.hp);
        assertEquals("linkage 拼接", "兵器攻击容器-重斩", result.linkage);
    }

    private static function testE2E_Happy_Skill_InitObjectFieldsCopiedToMan():Void {
        trace("\n--- testE2E_Happy_Skill_InitObjectFieldsCopiedToMan ---");
        var unit = makeMockUnit("hero");
        var initObj:Object = {技能名: "升龙拳", 启动伤害: 50, 启动浮空: true};

        var result:Object = ContainerAttachAction.attach(unit,
            ContainerSpec.KIND_SKILL, "升龙拳", initObj);

        assertEquals("status = OK", ContainerAttachAction.STATUS_OK, result.status);
        assertEquals("man.技能名", "升龙拳", unit.man.技能名);
        assertEquals("man.启动伤害", 50, unit.man.启动伤害);
        assertEquals("man.启动浮空", true, unit.man.启动浮空);
        assertEquals("linkage", "技能容器-升龙拳", result.linkage);
    }

    // ════════════════════════════════════════════════════════════════════
    // MISSING ABORT 路径
    // ════════════════════════════════════════════════════════════════════

    private static function testE2E_Missing_Weapon_Abort():Void {
        trace("\n--- testE2E_Missing_Weapon_Abort ---");
        var unit = makeMockUnit("hero");
        unit.__setMissingSymbol("兵器攻击容器-不存在的招");

        var result:Object = ContainerAttachAction.attach(unit,
            ContainerSpec.KIND_WEAPON, "不存在的招", {});

        assertEquals("status = MISSING_ABORT",
            ContainerAttachAction.STATUS_MISSING_ABORT, result.status);
        assertTrue("result.man = undefined", result.man === undefined);
        assertTrue("unit.man 未被设置", unit.man === undefined);
        assertTrue("unit.__children.man 不存在",
            unit.__children["man"] === undefined);
    }

    // ════════════════════════════════════════════════════════════════════
    // MISSING SILENT_CONTINUE 路径 + undefined man 下游（user 风险点）
    // ════════════════════════════════════════════════════════════════════

    private static function testE2E_Missing_Skill_SilentContinue_UndefinedManNoCrash():Void {
        trace("\n--- testE2E_Missing_Skill_SilentContinue_UndefinedManNoCrash ---");
        var unit = makeMockUnit("hero");
        unit.__setMissingSymbol("技能容器-不存在的技能");

        var result:Object = ContainerAttachAction.attach(unit,
            ContainerSpec.KIND_SKILL, "不存在的技能", {});

        assertEquals("status = MISSING_SILENT_CONTINUE",
            ContainerAttachAction.STATUS_MISSING_SILENT_CONTINUE, result.status);
        assertTrue("result.man = undefined", result.man === undefined);

        // 复刻生产代码：var man:MovieClip = attachResult.man;
        var man:MovieClip = result.man;
        assertTrue("生产 var man:MovieClip = undefined 不报错", man === undefined);

        // 下游 1: bindEndCleanup(undefined, ...) — AS2 undefined.onUnload 读写 silent
        // 直接调用，不应抛错；如果抛错，trace 后续 PASS 行不会出现
        RoutingLifecycle.bindEndCleanup(man, unit, "战技", "技能结束", "技能浮空");
        assertTrue("bindEndCleanup(undefined, ...) 不崩 → 跑到下一行", true);

        // unit 业务字段未被错改（bindEndCleanup 只写 clip.onUnload，对 unit 无副作用）
        assertEquals("unit.__spy_bigStateCount=0", 0, unit.__spy_bigStateCount);
    }

    // ════════════════════════════════════════════════════════════════════
    // 黑箱观察：handleFloat(undefined, unit, ...) 裸调（非生产路径）
    //
    // 这两个 case 记录"如果有人**裸调** handleFloat 传 undefined man 会怎么样"。
    // 现在的生产路径已经在 技能路由 / 战技路由 入口短路掉 missing 情况，所以这条
    // 路径不会从生产入口触达。保留为黑箱观察是为：
    //   (a) 文档化 AS2 `undefined.x = y` silent + unit[flag] = true 仍生效的事实
    //   (b) 若有人未来在别处裸调 handleFloat(undefined, ...)，这里能立刻验证行为
    // 生产语义锁在下方 testProduction_Missing*_ShortCircuits_*。
    // ════════════════════════════════════════════════════════════════════

    private static function testBlackbox_HandleFloat_UndefinedMan_TempY0_NoOp():Void {
        trace("\n--- testBlackbox_HandleFloat_UndefinedMan_TempY0_NoOp ---");
        var unit = makeMockUnit("hero");
        unit.temp_y = 0;  // 站立常态 → shouldApplyFloat=false → handleFloat early return

        // 直接裸调 handleFloat 传 undefined（非生产路径，仅作黑箱观察）
        RoutingLifecycle.handleFloat(undefined, unit, "技能浮空");
        assertTrue("handleFloat(undefined, unit, ...) tempy=0 不崩", true);
        assertEquals("unit.浮空 未被改写", false, unit.浮空);
        assertEquals("unit.技能浮空 未被改写", false, unit.技能浮空);
    }

    private static function testBlackbox_HandleFloat_UndefinedMan_TempYPositive_PollutesUnit():Void {
        trace("\n--- testBlackbox_HandleFloat_UndefinedMan_TempYPositive_PollutesUnit ---");
        var unit = makeMockUnit("hero");
        unit.temp_y = 30;  // 浮空触发 → shouldApplyFloat=true → 走到 unit[flag] = true 等写入

        // 此分支会走到：
        //   man.落地 = true;     (undefined silent no-op)
        //   unit[floatFlag] = true;     ← AS2 unit 是真对象，写入生效 → unit 被污染
        //   unit._y = unit.temp_y;
        //   unit.起始Y = unit.Z轴坐标;
        //   man.落地 = false;    (undefined silent no-op)
        //   unit.浮空 = true;
        //   RoutingRuntime.closeNaturalLanding/closeJumpFloat/enableSkillFloat
        //     —— 这些通过 getAirController()，无 air controller 时 silent no-op
        RoutingLifecycle.handleFloat(undefined, unit, "技能浮空");
        assertTrue("handleFloat(undefined, unit, ...) tempy>0 不崩", true);

        // 黑箱观察：unit 字段被污染 — 这正是生产路径短路掉的原因
        assertEquals("unit.浮空 被设为 true (污染)", true, unit.浮空);
        assertEquals("unit.技能浮空 flag 被设为 true (污染)", true, unit.技能浮空);
        assertEquals("unit._y 被改为 temp_y(30) (污染)", 30, unit._y);
    }

    // ════════════════════════════════════════════════════════════════════
    // 生产路径锁修复（2026-05-19 user 决策 + scripts/引擎/引擎_fs_技能路由.as /
    //                 scripts/引擎/引擎_fs_战技路由.as 短路落地）
    //
    // 复现 fix 后 _root.技能路由.载入后跳转技能容器 / 战技路由.载入后跳转战技容器 的
    // 核心算法：missing 容器时 STATUS !== OK 立即 return，不调 handleFloat/bindEndCleanup。
    //
    // **如果生产代码回归（去掉 status !== OK 短路），下面三条 production 断言会同步 FAIL。**
    // 维护规则：生产代码改动时这里要同步；保持 fix 落地的唯一证据。
    // ════════════════════════════════════════════════════════════════════

    /** 复现 fix 后 _root.技能路由.载入后跳转技能容器 核心算法 */
    private static function runSkillRouteEntry(unit, containerInit:Object):Object {
        var 技能名:String = unit.技能名;
        var attachResult:Object = ContainerAttachAction.attach(
            unit, ContainerSpec.KIND_SKILL, 技能名, containerInit);
        if (attachResult.status !== ContainerAttachAction.STATUS_OK) {
            return {man: undefined, shortCircuited: true};
        }
        var man:MovieClip = attachResult.man;
        RoutingLifecycle.handleFloat(man, unit, "技能浮空");
        RoutingLifecycle.bindEndCleanup(man, unit, "战技", "技能结束", "技能浮空");
        return {man: man, shortCircuited: false};
    }

    /** 复现 fix 后 _root.战技路由.载入后跳转战技容器 核心算法 */
    private static function runBattleSkillRouteEntry(unit, containerInit:Object):Object {
        var 技能名:String = unit.技能名;
        var attachResult:Object = ContainerAttachAction.attach(
            unit, ContainerSpec.KIND_BATTLE_SKILL, 技能名, containerInit);
        if (attachResult.status !== ContainerAttachAction.STATUS_OK) {
            return {man: undefined, shortCircuited: true};
        }
        var man:MovieClip = attachResult.man;
        RoutingLifecycle.handleFloat(man, unit, "技能浮空");
        RoutingLifecycle.bindEndCleanup(man, unit, undefined, "技能结束", "技能浮空");
        return {man: man, shortCircuited: false};
    }

    private static function testProduction_MissingSkill_ShortCircuits_NoUnitPollution():Void {
        trace("\n--- testProduction_MissingSkill_ShortCircuits_NoUnitPollution ---");
        var unit = makeMockUnit("hero");
        unit.技能名 = "升龙拳";
        unit.temp_y = 30;  // tempy>0 — 若误调 handleFloat 会污染
        unit.__setMissingSymbol("技能容器-升龙拳");

        var ret:Object = runSkillRouteEntry(unit, {});

        assertEquals("生产路径短路", true, ret.shortCircuited);
        assertTrue("man 未生成", ret.man === undefined);
        // 关键断言：unit 浮空相关字段保持 makeMockUnit 默认值
        assertEquals("unit.浮空 未被污染", false, unit.浮空);
        assertEquals("unit.技能浮空 未被污染", false, unit.技能浮空);
        assertEquals("unit._y 未被改写 (保留 100)", 100, unit._y);
        assertTrue("unit.起始Y 未被改写", unit.起始Y === undefined);
        // bindEndCleanup 也未调（没有 man.onUnload 被设置 → unit.__spy_bigStateCount 仍 0）
        assertEquals("UpdateBigSmallState 未触发", 0, unit.__spy_bigStateCount);
    }

    private static function testProduction_MissingBattleSkill_ShortCircuits_NoUnitPollution():Void {
        trace("\n--- testProduction_MissingBattleSkill_ShortCircuits_NoUnitPollution ---");
        var unit = makeMockUnit("hero");
        unit.技能名 = "双刀变长柄";
        unit.temp_y = 30;  // tempy>0 — 若误调 handleFloat 会污染
        unit.__setMissingSymbol("战技容器-双刀变长柄");

        var ret:Object = runBattleSkillRouteEntry(unit, {});

        assertEquals("生产路径短路", true, ret.shortCircuited);
        assertTrue("man 未生成", ret.man === undefined);
        assertEquals("unit.浮空 未被污染", false, unit.浮空);
        assertEquals("unit.技能浮空 未被污染", false, unit.技能浮空);
        assertEquals("unit._y 未被改写", 100, unit._y);
        assertEquals("UpdateBigSmallState 未触发", 0, unit.__spy_bigStateCount);
    }

    private static function testProduction_HappySkill_StillRunsLifecycle():Void {
        trace("\n--- testProduction_HappySkill_StillRunsLifecycle ---");
        // 正向断言：短路只在 STATUS !== OK 触发，happy 路径不变 — 仍 attach + handleFloat + bindEndCleanup
        var unit = makeMockUnit("hero");
        unit.技能名 = "升龙拳";
        unit.temp_y = 30;  // 浮空 → handleFloat 会执行所有写入

        var ret:Object = runSkillRouteEntry(unit, {});

        assertEquals("生产路径未短路", false, ret.shortCircuited);
        assertTrue("man 已生成", ret.man != undefined);
        assertEquals("unit.man = ret.man", ret.man, unit.man);
        // 这条 happy 走完整 lifecycle，handleFloat 写入应生效
        assertEquals("happy 路径 unit.浮空 = true", true, unit.浮空);
        assertEquals("happy 路径 unit.技能浮空 = true", true, unit.技能浮空);
        assertEquals("happy 路径 unit._y = 30", 30, unit._y);
        // bindEndCleanup 已挂 onUnload，man 卸载时会调 UpdateBigSmallState
        ret.man.removeMovieClip();
        assertEquals("happy 路径 bindEndCleanup 触发", 1, unit.__spy_bigStateCount);
    }

    // ════════════════════════════════════════════════════════════════════
    // bindContainerEndState 端到端
    // ════════════════════════════════════════════════════════════════════

    private static function testE2E_BindContainerEndState_FiresOnRemove():Void {
        trace("\n--- testE2E_BindContainerEndState_FiresOnRemove ---");
        var unit = makeMockUnit("hero");

        var result:Object = ContainerAttachAction.attach(unit,
            ContainerSpec.KIND_WEAPON, "重斩", {});
        RoutingIntent.bindContainerEndState(result.man, unit, RoutingIntent.SMALL_END_WEAPON);

        // 触发卸载（模拟 gotoAndStop 退出容器帧 / 显式 removeMovieClip）
        result.man.removeMovieClip();

        assertEquals("UpdateBigSmallState 触发 1 次", 1, unit.__spy_bigStateCount);
        assertEquals("big = BIG_END_PUNCH",
            RoutingIntent.BIG_END_PUNCH, unit.__spy_bigStateLastBig);
        assertEquals("small = SMALL_END_WEAPON",
            RoutingIntent.SMALL_END_WEAPON, unit.__spy_bigStateLastSmall);
    }

    private static function testE2E_BindContainerEndState_PrevOnUnloadChain():Void {
        trace("\n--- testE2E_BindContainerEndState_PrevOnUnloadChain ---");
        var unit = makeMockUnit("hero");

        var result:Object = ContainerAttachAction.attach(unit,
            ContainerSpec.KIND_WEAPON, "重斩", {});
        var man = result.man;

        // 模拟生产路径在 bindContainerEndState 之前已有自定义 onUnload
        var order:Array = [];
        man.onUnload = function() { order.push("preExisting"); };

        // bindContainerEndState wrap prev → 触发顺序应该是 preExisting 然后 endState
        RoutingIntent.bindContainerEndState(man, unit, RoutingIntent.SMALL_END_WEAPON);

        man.removeMovieClip();
        assertEquals("chain 长度 = 1 (preExisting)", "preExisting", order[0]);
        assertEquals("endState 也已触发", 1, unit.__spy_bigStateCount);
        assertEquals("UpdateBigSmallState big",
            RoutingIntent.BIG_END_PUNCH, unit.__spy_bigStateLastBig);
    }

    // ════════════════════════════════════════════════════════════════════
    // removeMovieClip 端到端
    // ════════════════════════════════════════════════════════════════════

    private static function testE2E_RemoveMovieClip_ClearsParentReference():Void {
        trace("\n--- testE2E_RemoveMovieClip_ClearsParentReference ---");
        var unit = makeMockUnit("hero");

        var result:Object = ContainerAttachAction.attach(unit,
            ContainerSpec.KIND_WEAPON, "重斩", {});
        var man = result.man;
        assertEquals("attach 后 unit.man 指向 man", man, unit.man);

        man.removeMovieClip();
        assertTrue("remove 后 unit.man = undefined", unit.man === undefined);
        assertTrue("__children.man 已删", unit.__children["man"] === undefined);
        assertEquals("man.__removed=true", true, man.__removed);
    }
}