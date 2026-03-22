import org.flashNight.arki.component.Damage.*;
import org.flashNight.arki.component.StatHandler.*;

/**
 * DamageHandlersTest - 各伤害处理器的单元测试与管线性能基准
 *
 * 覆盖: CritDamageHandle, DodgeStateDamageHandle (default/bounce/penetration/miss),
 *       NanoToxicDamageHandle, LifeStealDamageHandle, CrumbleDamageHandle, ExecuteDamageHandle
 *
 * 启动:
 *   import org.flashNight.arki.component.Damage.*;
 *   DamageHandlersTest.runTests();
 */
class org.flashNight.arki.component.Damage.DamageHandlersTest {

    private static var _total:Number = 0;
    private static var _pass:Number = 0;
    private static var _fail:Number = 0;

    // ========== 断言工具 ==========

    private static function assertEq(expected, actual, msg:String):Void {
        _total++;
        if (expected != actual) {
            _fail++;
            trace("[FAIL] " + msg);
            trace("  expected: " + expected);
            trace("  actual  : " + actual);
        } else {
            _pass++;
            trace("[PASS] " + msg);
        }
    }

    private static function assertFloatEq(expected:Number, actual:Number, delta:Number, msg:String):Void {
        _total++;
        var diff:Number = expected - actual;
        if (diff < 0) diff = -diff;
        if (diff > delta) {
            _fail++;
            trace("[FAIL] " + msg);
            trace("  expected: " + expected + " +/-" + delta);
            trace("  actual  : " + actual + " (diff=" + diff + ")");
        } else {
            _pass++;
            trace("[PASS] " + msg);
        }
    }

    private static function assertTrue(cond:Boolean, msg:String):Void {
        _total++;
        if (!cond) { _fail++; trace("[FAIL] " + msg); }
        else { _pass++; trace("[PASS] " + msg); }
    }

    // ========== Mock 工厂 ==========

    private static function freshResult():DamageResult {
        var r:DamageResult = new DamageResult();
        r.reset();
        return r;
    }

    private static function mockShield():Object {
        return {
            getStrength: function():Number { return 0; },
            getCapacity: function():Number { return 0; },
            consumeCapacity: function():Void {}
        };
    }

    private static function mockManager(dodgeState:String):Object {
        return {overlapRatio: 1, dodgeState: dodgeState};
    }

    // ========== 测试入口 ==========

    public static function runTests():Void {
        trace("===== DamageHandlers 测试套件 =====");
        _total = 0; _pass = 0; _fail = 0;

        // DodgeState 默认路径调用 _root.受击变红，确保存在
        if (_root.受击变红 == undefined) {
            _root.受击变红 = function():Void {};
        }

        test_Crit_基础暴击();
        test_Crit_canHandle();

        test_DodgeState_默认路径();
        test_DodgeState_跳弹();
        test_DodgeState_过穿();
        test_DodgeState_躲闪();
        test_DodgeState_真伤免疫闪避();

        test_NanoToxic_基础毒素();
        test_NanoToxic_canHandle();

        test_LifeSteal_基础吸血();
        test_LifeSteal_canHandle();
        test_LifeSteal_canHandle_边界值();

        test_Crumble_基础击溃();
        test_Crumble_canHandle();

        test_Execute_触发斩杀();
        test_Execute_未达阈值();
        test_Execute_canHandle();

        test_createBasic_零值可选处理器不入管线();
        test_createBasic_正值可选处理器入管线();

        runOptimizationBenchmarks();

        trace("===== DamageHandlers 汇总: run=" + _total + " pass=" + _pass + " fail=" + _fail + " =====");
    }

    // ==================== CritDamageHandle ====================

    private static function test_Crit_基础暴击():Void {
        var h:CritDamageHandle = CritDamageHandle.getInstance();
        var bullet:Object = {
            破坏力: 100,
            暴击: function(b:Object):Number { return 1.5; }
        };
        h.handleBulletDamage(bullet, null, null, null, freshResult());
        assertFloatEq(150, bullet.破坏力, 0.01, "Crit: 100*1.5=150");
    }

    private static function test_Crit_canHandle():Void {
        var h:CritDamageHandle = CritDamageHandle.getInstance();
        assertTrue(h.canHandle({暴击: function():Number { return 2; }}), "Crit.canHandle: 有暴击=true");
        assertTrue(!h.canHandle({暴击: null}), "Crit.canHandle: null=false");
        assertTrue(!h.canHandle({}), "Crit.canHandle: 无属性=false");
    }

    // ==================== DodgeStateDamageHandle ====================

    private static function test_DodgeState_默认路径():Void {
        var h:DodgeStateDamageHandle = DodgeStateDamageHandle.getInstance();
        var bullet:Object = {伤害类型: "物理", 是否为敌人: true, flags: 0};
        var target:Object = {损伤值: 55.7, hp: 300, 防御力: 50};
        var r:DamageResult = freshResult();
        r.damageSize = 28;
        h.handleBulletDamage(bullet, null, target, mockManager(""), r);
        assertEq(55, target.损伤值, "DodgeState默认: floor(55.7)=55");
        assertEq(28, r.damageSize, "DodgeState默认: damageSize不变");
    }

    private static function test_DodgeState_跳弹():Void {
        var h:DodgeStateDamageHandle = DodgeStateDamageHandle.getInstance();
        var bullet:Object = {伤害类型: "物理", 是否为敌人: true, flags: 0};
        var target:Object = {损伤值: 100, hp: 300, 防御力: 50};
        var r:DamageResult = freshResult();
        r.damageSize = 28;
        h.handleBulletDamage(bullet, null, target, mockManager("跳弹"), r);
        // bounce = max(floor(100 - 50/5), 1) = 90
        assertEq(90, target.损伤值, "DodgeState跳弹: 100-(50/5)=90");
        assertEq(7, r._dmgColorId, "DodgeState跳弹: 敌方颜色=7");
    }

    private static function test_DodgeState_过穿():Void {
        var h:DodgeStateDamageHandle = DodgeStateDamageHandle.getInstance();
        var bullet:Object = {伤害类型: "物理", 是否为敌人: true, flags: 0};
        var target:Object = {损伤值: 100, hp: 300, 防御力: 300};
        var r:DamageResult = freshResult();
        r.damageSize = 28;
        h.handleBulletDamage(bullet, null, target, mockManager("过穿"), r);
        // penetration = max(floor(100 * 300/600), 1) = 50
        assertEq(50, target.损伤值, "DodgeState过穿: 100*300/600=50");
        assertEq(9, r._dmgColorId, "DodgeState过穿: 敌方颜色=9");
    }

    private static function test_DodgeState_躲闪():Void {
        var h:DodgeStateDamageHandle = DodgeStateDamageHandle.getInstance();
        var bullet:Object = {伤害类型: "物理", 是否为敌人: true, flags: 0};
        var target:Object = {损伤值: 100, hp: 300, 防御力: 50};
        var r:DamageResult = freshResult();
        r.damageSize = 28;
        h.handleBulletDamage(bullet, null, target, mockManager("躲闪"), r);
        assertEq(0, target.损伤值, "DodgeState躲闪: 损伤=0");
        assertEq("MISS", r.dodgeStatus, "DodgeState躲闪: MISS状态");
    }

    private static function test_DodgeState_真伤免疫闪避():Void {
        var h:DodgeStateDamageHandle = DodgeStateDamageHandle.getInstance();
        var bullet:Object = {伤害类型: "真伤", 是否为敌人: true, flags: 0};
        var target:Object = {损伤值: 55.7, hp: 300, 防御力: 50};
        var r:DamageResult = freshResult();
        h.handleBulletDamage(bullet, null, target, mockManager("躲闪"), r);
        assertEq(55, target.损伤值, "DodgeState真伤: 无视闪避, floor=55");
        assertTrue(r.dodgeStatus != "MISS", "DodgeState真伤: 不是MISS");
    }

    // ==================== NanoToxicDamageHandle ====================

    private static function test_NanoToxic_基础毒素():Void {
        var h:NanoToxicDamageHandle = NanoToxicDamageHandle.getInstance();
        // flags=0 → 不含FLAG_NORMAL(64) → nanoToxicAmount *= 0.3
        var bullet:Object = {nanoToxic: 100, flags: 0, 子弹威力: 999, additionalEffectDamage: 0, nanoToxicDecay: 0};
        var target:Object = {损伤值: 50, hp: 300, shield: mockShield(), 毒返: 0};
        var r:DamageResult = freshResult();
        r.actualScatterUsed = 1;
        h.handleBulletDamage(bullet, {淬毒: 0}, target, null, r);
        // 非普通: 100*0.3=30, 损伤=50+30=80
        assertFloatEq(80, target.损伤值, 0.01, "NanoToxic非普通: 50+100*0.3=80");
        assertTrue((r._efFlags & 2) != 0, "NanoToxic: EF_TOXIC已设置");
    }

    private static function test_NanoToxic_canHandle():Void {
        var h:NanoToxicDamageHandle = NanoToxicDamageHandle.getInstance();
        assertTrue(h.canHandle({nanoToxic: 10}), "NanoToxic.canHandle: >0=true");
        assertTrue(!h.canHandle({nanoToxic: 0}), "NanoToxic.canHandle: 0=false");
        assertTrue(!h.canHandle({}), "NanoToxic.canHandle: 无属性=false");
    }

    // ==================== LifeStealDamageHandle ====================

    private static function test_LifeSteal_基础吸血():Void {
        var h:LifeStealDamageHandle = LifeStealDamageHandle.getInstance();
        var bullet:Object = {吸血: 10, 子弹威力: 999};
        var shooter:Object = {hp: 80, hp满血值: 100};
        var target:Object = {损伤值: 200, hp: 300, shield: mockShield()};
        var r:DamageResult = freshResult();
        r.actualScatterUsed = 1;
        h.handleBulletDamage(bullet, shooter, target, null, r);
        // lifeSteal = floor(200*10/100) = 20, maxHeal = floor(150-80) = 70
        assertEq(100, shooter.hp, "LifeSteal: 80+20=100");
        assertTrue((r._efFlags & 32) != 0, "LifeSteal: EF_LIFESTEAL已设置");
    }

    private static function test_LifeSteal_canHandle():Void {
        var h:LifeStealDamageHandle = LifeStealDamageHandle.getInstance();
        assertTrue(h.canHandle({吸血: 10}), "LifeSteal.canHandle: >0=true");
        assertTrue(!h.canHandle({吸血: 0}), "LifeSteal.canHandle: 0=false");
    }

    private static function test_LifeSteal_canHandle_边界值():Void {
        var h:LifeStealDamageHandle = LifeStealDamageHandle.getInstance();
        assertTrue(!h.canHandle({吸血: -5}), "LifeSteal.canHandle: 负值=false");
        assertTrue(!h.canHandle({吸血: null}), "LifeSteal.canHandle: null=false");
        assertTrue(!h.canHandle({}), "LifeSteal.canHandle: 缺省=false");
    }

    // ==================== CrumbleDamageHandle ====================

    private static function test_Crumble_基础击溃():Void {
        var h:CrumbleDamageHandle = CrumbleDamageHandle.getInstance();
        var bullet:Object = {击溃: 10, 子弹威力: 999, additionalEffectDamage: 0};
        var target:Object = {损伤值: 50, hp: 300, hp满血值: 300, shield: mockShield()};
        var r:DamageResult = freshResult();
        h.handleBulletDamage(bullet, null, target, null, r);
        // crumble = floor(300*10/100) = 30
        assertEq(270, target.hp满血值, "Crumble: 300-30=270");
        assertEq(80, target.损伤值, "Crumble: 50+30=80");
        assertTrue((r._efFlags & 1) != 0, "Crumble: EF_CRUMBLE已设置");
    }

    private static function test_Crumble_canHandle():Void {
        var h:CrumbleDamageHandle = CrumbleDamageHandle.getInstance();
        assertTrue(h.canHandle({击溃: 5}), "Crumble.canHandle: >0=true");
        assertTrue(!h.canHandle({击溃: 0}), "Crumble.canHandle: 0=false");
    }

    // ==================== ExecuteDamageHandle ====================

    private static function test_Execute_触发斩杀():Void {
        var h:ExecuteDamageHandle = ExecuteDamageHandle.getInstance();
        var bullet:Object = {斩杀: 50, 子弹威力: 999, 是否为敌人: true};
        var target:Object = {
            hp: 100, hp满血值: 200, 损伤值: 80,
            shield: {
                getStrength: function():Number { return 0; },
                getCapacity: function():Number { return 0; },
                consumeCapacity: function():Void {}
            }
        };
        var r:DamageResult = freshResult();
        h.handleBulletDamage(bullet, null, target, null, r);
        // 剩余=100-80=20, 阈值=200*50/100=100, 20<100 → 斩杀
        assertEq(0, target.hp, "Execute触发: hp归零");
        assertTrue((r._efFlags & 4) != 0, "Execute: EF_EXECUTE已设置");
    }

    private static function test_Execute_未达阈值():Void {
        var h:ExecuteDamageHandle = ExecuteDamageHandle.getInstance();
        var bullet:Object = {斩杀: 10, 子弹威力: 999, 是否为敌人: true};
        var target:Object = {
            hp: 300, hp满血值: 300, 损伤值: 50,
            shield: {
                getStrength: function():Number { return 0; },
                getCapacity: function():Number { return 0; },
                consumeCapacity: function():Void {}
            }
        };
        var r:DamageResult = freshResult();
        h.handleBulletDamage(bullet, null, target, null, r);
        // 剩余=300-50=250, 阈值=300*10/100=30, 250>30 → 不触发
        assertEq(300, target.hp, "Execute未触发: hp不变");
        assertTrue((r._efFlags & 4) == 0, "Execute未触发: EF_EXECUTE未设置");
    }

    private static function test_Execute_canHandle():Void {
        var h:ExecuteDamageHandle = ExecuteDamageHandle.getInstance();
        assertTrue(h.canHandle({斩杀: 10}), "Execute.canHandle: >0=true");
        assertTrue(!h.canHandle({斩杀: 0}), "Execute.canHandle: 0=false");
        assertTrue(!h.canHandle({斩杀: -1}), "Execute.canHandle: 负值=false");
        assertTrue(!h.canHandle({斩杀: null}), "Execute.canHandle: null=false");
        assertTrue(!h.canHandle({}), "Execute.canHandle: 缺省=false");
    }

    // ==================== createBasic 管线回归 ====================

    private static function test_createBasic_零值可选处理器不入管线():Void {
        var factory:DamageManagerFactory = new DamageManagerFactory([
            CritDamageHandle.getInstance(),
            UniversalDamageHandle.getInstance(),
            DodgeStateDamageHandle.getInstance(),
            MultiShotDamageHandle.getInstance(),
            NanoToxicDamageHandle.getInstance(),
            LifeStealDamageHandle.getInstance(),
            CrumbleDamageHandle.getInstance(),
            ExecuteDamageHandle.getInstance()
        ], 64);

        var bullet:Object = {
            破坏力: 100,
            是否为敌人: true,
            伤害类型: "物理",
            魔法伤害属性: null,
            暴击: null,
            flags: 64,
            nanoToxic: 0,
            吸血: 0,
            击溃: 0,
            斩杀: 0,
            霰弹值: 1,
            最小霰弹值: 1
        };
        var mgr:DamageManager = factory.getDamageManager(bullet);
        var dump:String = mgr.toString();
        assertTrue(dump.indexOf("UniversalDamageHandle") >= 0, "createBasic零值: 含Universal");
        assertTrue(dump.indexOf("DodgeStateDamageHandle") >= 0, "createBasic零值: 含DodgeState");
        assertTrue(dump.indexOf("LifeStealDamageHandle") < 0, "createBasic零值: 不含LifeSteal");
        assertTrue(dump.indexOf("ExecuteDamageHandle") < 0, "createBasic零值: 不含Execute");
    }

    private static function test_createBasic_正值可选处理器入管线():Void {
        var factory:DamageManagerFactory = new DamageManagerFactory([
            CritDamageHandle.getInstance(),
            UniversalDamageHandle.getInstance(),
            DodgeStateDamageHandle.getInstance(),
            MultiShotDamageHandle.getInstance(),
            NanoToxicDamageHandle.getInstance(),
            LifeStealDamageHandle.getInstance(),
            CrumbleDamageHandle.getInstance(),
            ExecuteDamageHandle.getInstance()
        ], 64);

        var bullet:Object = {
            破坏力: 100,
            是否为敌人: true,
            伤害类型: "物理",
            魔法伤害属性: null,
            暴击: null,
            flags: 64,
            nanoToxic: 0,
            吸血: 5,
            击溃: 0,
            斩杀: 10,
            霰弹值: 1,
            最小霰弹值: 1
        };
        var mgr:DamageManager = factory.getDamageManager(bullet);
        var dump:String = mgr.toString();
        assertTrue(dump.indexOf("LifeStealDamageHandle") >= 0, "createBasic正值: 含LifeSteal");
        assertTrue(dump.indexOf("ExecuteDamageHandle") >= 0, "createBasic正值: 含Execute");
    }

    // ==================== 管线性能基准 ====================

    private static function runOptimizationBenchmarks():Void {
        trace("");
        trace("===== 优化对照基准 =====");

        benchmark_零斩杀管线收缩();

        trace("");
    }

    private static function benchmark_零斩杀管线收缩():Void {
        var ITERS:Number = 60000;
        var shooter:Object = {hp: 500, hp满血值: 500, 淬毒: 0};
        var factory:DamageManagerFactory = new DamageManagerFactory([
            CritDamageHandle.getInstance(),
            UniversalDamageHandle.getInstance(),
            DodgeStateDamageHandle.getInstance(),
            MultiShotDamageHandle.getInstance(),
            NanoToxicDamageHandle.getInstance(),
            LifeStealDamageHandle.getInstance(),
            CrumbleDamageHandle.getInstance(),
            ExecuteDamageHandle.getInstance()
        ], 64);
        var bullet:Object = {
            破坏力: 100,
            是否为敌人: true,
            伤害类型: "物理",
            魔法伤害属性: null,
            暴击: null,
            flags: 64,
            nanoToxic: 0,
            吸血: 0,
            击溃: 0,
            斩杀: 0,
            霰弹值: 1,
            最小霰弹值: 1,
            子弹威力: 999
        };
        var target:Object = {hp: 9999, hp满血值: 9999, 防御力: 300, 损伤值: 0, 等级: 10, 魔法抗性: null,
            无敌: false, man: {无敌标签: false}, NPC: false, shield: mockShield()};
        var oldMgr:DamageManager = new DamageManager([
            UniversalDamageHandle.getInstance(),
            DodgeStateDamageHandle.getInstance(),
            ExecuteDamageHandle.getInstance()
        ]);
        var newMgr:DamageManager = factory.getDamageManager(bullet);
        var resultOld:DamageResult = new DamageResult();
        var resultNew:DamageResult = new DamageResult();
        var i:Number;
        var t0:Number;

        t0 = getTimer();
        for (i = 0; i < ITERS; i++) {
            resultOld._efFlags = 0;
            resultOld._dmgColorId = 0;
            resultOld.damageSize = 28;
            resultOld.dodgeStatus = "";
            target.hp = 9999;
            target.损伤值 = 0;
            oldMgr.overlapRatio = 1;
            oldMgr.dodgeState = "";
            oldMgr.execute(bullet, shooter, target, resultOld);
        }
        var msOld:Number = getTimer() - t0;

        t0 = getTimer();
        for (i = 0; i < ITERS; i++) {
            resultNew._efFlags = 0;
            resultNew._dmgColorId = 0;
            resultNew.damageSize = 28;
            resultNew.dodgeStatus = "";
            target.hp = 9999;
            target.损伤值 = 0;
            newMgr.overlapRatio = 1;
            newMgr.dodgeState = "";
            newMgr.execute(bullet, shooter, target, resultNew);
        }
        var msNew:Number = getTimer() - t0;
        var improve:Number = msOld > 0 ? Math.round((msOld - msNew) * 10000 / msOld) / 100 : 0;

        trace("  零斩杀旧管线(含Execute): " + ITERS + "次 = " + msOld + "ms");
        trace("  零斩杀新管线(不含Execute): " + ITERS + "次 = " + msNew + "ms");
        trace("  零斩杀管线收缩提升: " + improve + "%");
    }

    private static function runPipelineBenchmark():Void {
        trace("");
        trace("===== 管线性能基准 =====");

        DamageManagerFactory.init();
        var ITERS:Number = 20000;
        var factory:DamageManagerFactory = DamageManagerFactory.getFactory("Basic");
        var shooterA:Object = {hp: 500, hp满血值: 500, 淬毒: 0};

        // --- 场景A: 最简物理子弹（仅 Universal + DodgeState） ---
        var bA:Object = {破坏力: 100, 是否为敌人: true, 伤害类型: "物理", 魔法伤害属性: null,
            暴击: null, nanoToxic: 0, 吸血: 0, 击溃: 0, 斩杀: null,
            霰弹值: 1, 最小霰弹值: 1, flags: 64};
        var tA:Object = {hp: 9999, hp满血值: 9999, 防御力: 300, 损伤值: 0, 等级: 10, 魔法抗性: null,
            无敌: false, man: {无敌标签: false}, NPC: false, shield: mockShield()};
        var rA:DamageResult = new DamageResult();
        var mgrA:DamageManager = factory.getDamageManager(bA);

        var i:Number;
        var t0:Number = getTimer();
        for (i = 0; i < ITERS; i++) {
            rA._efFlags = 0; rA._dmgColorId = 0; rA.damageSize = 28; rA.dodgeStatus = "";
            tA.损伤值 = 0; tA.hp = 9999;
            mgrA.overlapRatio = 1; mgrA.dodgeState = "";
            mgrA.execute(bA, shooterA, tA, rA);
        }
        var msA:Number = getTimer() - t0;

        // --- 场景B: 暴击+破击+毒+吸血（多处理器管线） ---
        var bB:Object = {破坏力: 100, 是否为敌人: true, 伤害类型: "破击", 魔法伤害属性: "电",
            暴击: function(b:Object):Number { return 1.5; },
            nanoToxic: 20, 吸血: 5, 击溃: 0, 斩杀: null,
            霰弹值: 1, 最小霰弹值: 1, flags: 64,
            子弹威力: 999, additionalEffectDamage: 0, nanoToxicDecay: 0};
        var tB:Object = {hp: 9999, hp满血值: 9999, 防御力: 300, 损伤值: 0, 等级: 10,
            魔法抗性: {电: 30, 基础: 10}, 无敌: false, man: {无敌标签: false}, NPC: false,
            shield: mockShield(), 毒返: 0};
        var rB:DamageResult = new DamageResult();
        var mgrB:DamageManager = factory.getDamageManager(bB);

        t0 = getTimer();
        for (i = 0; i < ITERS; i++) {
            rB._efFlags = 0; rB._dmgColorId = 0; rB.damageSize = 28; rB.dodgeStatus = "";
            rB.actualScatterUsed = 1; rB.deferChainDodgeState = false;
            tB.损伤值 = 0; tB.hp = 9999; tB.hp满血值 = 9999;
            bB.破坏力 = 100; bB.additionalEffectDamage = 0;
            mgrB.overlapRatio = 1; mgrB.dodgeState = "";
            mgrB.execute(bB, shooterA, tB, rB);
        }
        var msB:Number = getTimer() - t0;

        trace("  场景A(物理最简): " + ITERS + "次 = " + msA + "ms (" + Math.round(msA * 1000000 / ITERS) + " ns/call)");
        trace("  场景B(暴击破击毒吸): " + ITERS + "次 = " + msB + "ms (" + Math.round(msB * 1000000 / ITERS) + " ns/call)");
        trace("");
    }
}
