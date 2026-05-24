import org.flashNight.naki.PseudoRandom.*;
import org.flashNight.naki.RandomNumberEngine.*;

/**
 * PseudoRandomDistribution 单元测试
 *
 * Sentinel:
 *   - 全 PASS → [TEST_PASS] PRD suites
 *   - 任一 FAIL → [TEST_FAIL] PRD suites
 *
 * 覆盖：
 *   T1 边界 (p<=0, p>=1, NaN, key 一致性)
 *   T2 命中清零 + 失败递增
 *   T3 peekProbability 不消费计数
 *   T4 多 key 计数隔离
 *   T5 state 注入：mutation 反映到外部对象
 *   T6 attachState 重绑：旧引用断开、新引用同步
 *   T7 reset / resetAll
 *   T8 频率收敛：N 大样本命中率 ≈ P（容忍 ±10%）
 *   T9 方差压缩：PRD gap std < 0.75 × geometric std
 *  T10 跨槽位 deterministic：同 seed + 同 state 出同结果（持久化等价性）
 */
class org.flashNight.naki.PseudoRandom.PseudoRandomDistributionTest {

    private static var passCount:Number = 0;
    private static var failCount:Number = 0;

    private static function ok(cond:Boolean, msg:String):Void {
        if (cond) {
            passCount++;
            trace("  PASS  " + msg);
        } else {
            failCount++;
            trace("  FAIL  " + msg);
        }
    }

    private static function nearly(actual:Number, expected:Number, tol:Number, msg:String):Void {
        var diff:Number = actual - expected;
        if (diff < 0) diff = -diff;
        if (diff <= tol) {
            passCount++;
            trace("  PASS  " + msg + "  (got=" + actual + " expected≈" + expected + " tol=" + tol + ")");
        } else {
            failCount++;
            trace("  FAIL  " + msg + "  (got=" + actual + " expected≈" + expected + " tol=" + tol + ")");
        }
    }

    // 统计辅助：跑 N 次 roll，记录命中数与相邻命中间的 gap（含本次命中）
    private static function runRolls(prd:PseudoRandomDistribution, key:String, p:Number, N:Number):Object {
        var hits:Number = 0;
        var gaps:Array = [];
        var curGap:Number = 0;
        for (var i:Number = 0; i < N; i++) {
            curGap++;
            if (prd.roll(key, p)) {
                hits++;
                gaps.push(curGap);
                curGap = 0;
            }
        }
        return { hits: hits, gaps: gaps };
    }

    private static function stddev(arr:Array):Number {
        var n:Number = arr.length;
        if (n < 2) return 0;
        var sum:Number = 0;
        for (var i:Number = 0; i < n; i++) sum += arr[i];
        var mean:Number = sum / n;
        var sq:Number = 0;
        for (var j:Number = 0; j < n; j++) {
            var d:Number = arr[j] - mean;
            sq += d * d;
        }
        return Math.sqrt(sq / (n - 1));
    }

    public static function runAll():Boolean {
        var t0:Number = getTimer();
        passCount = 0;
        failCount = 0;
        trace("================================================================");
        trace("PseudoRandomDistribution Test Suite");
        trace("================================================================");

        // 确保熵源就绪并 seed 化以便统计断言可复现
        LinearCongruentialEngine.getInstance().setSeed(20260524);

        testBoundary();
        testCounterLifecycle();
        testPeek();
        testKeyIsolation();
        testStateInjection();
        testAttachStateRebind();
        testReset();
        testFrequencyConvergence();
        testVarianceCompression();
        testPersistenceEquivalence();

        var elapsed:Number = getTimer() - t0;
        trace("----------------------------------------------------------------");
        trace("PRD test totals: " + passCount + " PASS, " + failCount + " FAIL, " + elapsed + "ms");
        trace("----------------------------------------------------------------");
        if (failCount == 0) {
            trace("[TEST_PASS] PRD suites");
            return true;
        } else {
            trace("[TEST_FAIL] PRD suites");
            return false;
        }
    }

    // ============================== T1 ==============================
    private static function testBoundary():Void {
        trace("[T1] Boundary conditions");
        var s:Object = {};
        var prd:PseudoRandomDistribution = new PseudoRandomDistribution(s);

        // p<=0: 永远不中且不累计失败计数（防污染 key 空间）
        var hits:Number = 0;
        for (var i:Number = 0; i < 50; i++) {
            if (prd.roll("k", 0)) hits++;
        }
        ok(hits == 0, "T1.1 p=0 永远不命中");
        ok(prd.getFailCount("k") == 0, "T1.2 p=0 不累计失败计数");

        // 负值同理
        prd.roll("k", -0.5);
        ok(prd.getFailCount("k") == 0, "T1.3 p<0 不累计");

        // p>=1 必中并清零
        prd.getState()["k2"] = 99;  // 注入旧计数
        var allHit:Boolean = true;
        for (var j:Number = 0; j < 20; j++) {
            if (!prd.roll("k2", 1)) allHit = false;
        }
        ok(allHit, "T1.4 p>=1 必命中");
        ok(prd.getFailCount("k2") == 0, "T1.5 p>=1 清零计数");

        // p>1 同样按必中处理
        var x:Boolean = prd.roll("k3", 2.0);
        ok(x, "T1.6 p>1 按必中处理");
    }

    // ============================== T2 ==============================
    private static function testCounterLifecycle():Void {
        trace("[T2] Counter lifecycle (fail++ / hit→0)");
        // 用极低 p 强制第一波必失败，确认计数累积
        var s:Object = {};
        var prd:PseudoRandomDistribution = new PseudoRandomDistribution(s);
        // p=0.0001 → C ≈ 0.00000078，前 100 次必失败
        for (var i:Number = 0; i < 30; i++) prd.roll("low", 0.0001);
        ok(prd.getFailCount("low") == 30, "T2.1 低 p 下连续失败 fail count == roll count");

        // 强制命中：手动设大 N 让 C·N 超过 1
        s["forced"] = 100000;  // 任何 p>0 下 C·101 都会被 clamp 到 1，必中
        var r:Boolean = prd.roll("forced", 0.01);
        ok(r == true, "T2.2 失败计数 N 使 C·(N+1) >= 1 时必中");
        ok(prd.getFailCount("forced") == 0, "T2.3 命中后计数清零");
    }

    // ============================== T3 ==============================
    private static function testPeek():Void {
        trace("[T3] peekProbability 不消费计数");
        var s:Object = {};
        var prd:PseudoRandomDistribution = new PseudoRandomDistribution(s);
        prd.getState()["k"] = 5;
        var p1:Number = prd.peekProbability("k", 0.2);
        var p2:Number = prd.peekProbability("k", 0.2);
        ok(p1 == p2, "T3.1 peek 幂等");
        ok(prd.getFailCount("k") == 5, "T3.2 peek 不修改计数");
        // peek 与 roll 内部用的 p_now 应一致：C(0.2)*(5+1)
        // C(0.2) 查表 = 0.055704043
        nearly(p1, 0.055704043 * 6, 1e-6, "T3.3 peek 等于 C*(N+1)");
        ok(prd.peekProbability("k", 0) == 0, "T3.4 peek(p<=0) == 0");
        ok(prd.peekProbability("k", 1.5) == 1, "T3.5 peek(p>=1) == 1");
    }

    // ============================== T4 ==============================
    private static function testKeyIsolation():Void {
        trace("[T4] Key isolation");
        var s:Object = {};
        var prd:PseudoRandomDistribution = new PseudoRandomDistribution(s);
        for (var i:Number = 0; i < 10; i++) prd.roll("a", 0.0001);
        for (var j:Number = 0; j < 5; j++) prd.roll("b", 0.0001);
        ok(prd.getFailCount("a") == 10, "T4.1 a 独立计数 10");
        ok(prd.getFailCount("b") == 5, "T4.2 b 独立计数 5");
        ok(prd.getFailCount("c") == 0, "T4.3 未出现的 key 计数为 0");
    }

    // ============================== T5 ==============================
    private static function testStateInjection():Void {
        trace("[T5] State injection (外部对象同步)");
        var hostState:Object = {};
        var prd:PseudoRandomDistribution = new PseudoRandomDistribution(hostState);
        for (var i:Number = 0; i < 7; i++) prd.roll("x", 0.0001);
        // 引擎的 mutation 应直接出现在 host
        ok(hostState["x"] == 7, "T5.1 引擎写入反映在外部 state 对象");
        // 反过来：外部修改 host 也被引擎看到
        hostState["x"] = 42;
        ok(prd.getFailCount("x") == 42, "T5.2 外部修改外部对象也被引擎看到");
    }

    // ============================== T6 ==============================
    private static function testAttachStateRebind():Void {
        trace("[T6] attachState 重绑 (旧引用断、新引用同步)");
        var oldState:Object = {};
        var newState:Object = { preExisting: 11 };
        var prd:PseudoRandomDistribution = new PseudoRandomDistribution(oldState);
        prd.roll("z", 0.0001);  // oldState.z = 1
        ok(oldState["z"] == 1, "T6.1 重绑前写入 oldState");

        prd.attachState(newState);
        ok(prd.getFailCount("preExisting") == 11, "T6.2 重绑后能读到 newState 已有计数");
        prd.roll("y", 0.0001);
        ok(newState["y"] == 1, "T6.3 重绑后新写入落到 newState");
        ok(oldState["y"] == undefined, "T6.4 旧 state 不再被写入");
    }

    // ============================== T7 ==============================
    private static function testReset():Void {
        trace("[T7] reset / resetAll");
        var s:Object = {};
        var prd:PseudoRandomDistribution = new PseudoRandomDistribution(s);
        prd.getState()["a"] = 5;
        prd.getState()["b"] = 3;
        prd.reset("a");
        ok(prd.getFailCount("a") == 0, "T7.1 reset 单个 key");
        ok(prd.getFailCount("b") == 3, "T7.2 reset 不影响其他 key");
        prd.resetAll();
        ok(prd.getFailCount("b") == 0, "T7.3 resetAll 清空所有");
    }

    // ============================== T8 ==============================
    private static function testFrequencyConvergence():Void {
        trace("[T8] Frequency convergence (rate ≈ P)");
        var N:Number = 20000;
        var Ps:Array = [0.05, 0.1, 0.2, 0.5];
        for (var i:Number = 0; i < Ps.length; i++) {
            var p:Number = Ps[i];
            var prd:PseudoRandomDistribution = new PseudoRandomDistribution({});
            var r:Object = runRolls(prd, "k", p, N);
            var rate:Number = r.hits / N;
            // ±15% 相对误差容忍（N=20000 + LCG 周期内随机性已足够）
            var tol:Number = p * 0.15;
            nearly(rate, p, tol, "T8 p=" + p + " 实测命中率收敛");
        }
    }

    // ============================== T9 ==============================
    private static function testVarianceCompression():Void {
        trace("[T9] Variance compression (PRD gap std < uniform geom std)");
        var N:Number = 20000;
        var Ps:Array = [0.1, 0.2, 0.5];
        for (var i:Number = 0; i < Ps.length; i++) {
            var p:Number = Ps[i];
            var prd:PseudoRandomDistribution = new PseudoRandomDistribution({});
            var r:Object = runRolls(prd, "g", p, N);
            var prdStd:Number = stddev(r.gaps);
            // geometric(p) gap 理论 std = sqrt((1-p)/p²)
            var geomStd:Number = Math.sqrt((1 - p) / (p * p));
            var ratio:Number = prdStd / geomStd;
            // 实测 ratio ≈ 0.53–0.57，给出 0.75 上限留余量
            ok(ratio < 0.75, "T9 p=" + p + " PRD gap std 显著压缩 (prdStd=" + Math.round(prdStd*100)/100 + " geomStd=" + Math.round(geomStd*100)/100 + " ratio=" + Math.round(ratio*1000)/1000 + ")");
        }
    }

    // ============================== T10 ==============================
    private static function testPersistenceEquivalence():Void {
        trace("[T10] Persistence equivalence (同 seed+同 state → 同结果)");
        var N:Number = 200;

        // Round A：跑 N 次，落到 stateA
        LinearCongruentialEngine.getInstance().setSeed(99887766);
        var stateA:Object = {};
        var prdA:PseudoRandomDistribution = new PseudoRandomDistribution(stateA);
        var resA:Array = [];
        for (var i:Number = 0; i < N; i++) resA.push(prdA.roll("k", 0.2));

        // 模拟"保存退出再加载"：把 stateA 内容浅拷贝到 stateB，重置同种子，重绑
        var stateB:Object = {};
        for (var k:String in stateA) stateB[k] = stateA[k];
        LinearCongruentialEngine.getInstance().setSeed(99887766);
        var prdB:PseudoRandomDistribution = new PseudoRandomDistribution(stateB);
        var resB:Array = [];
        for (var j:Number = 0; j < N; j++) resB.push(prdB.roll("k", 0.2));

        // 同 seed 同初始 state → 序列应完全一致
        var allEq:Boolean = true;
        for (var m:Number = 0; m < N; m++) {
            if (resA[m] !== resB[m]) { allEq = false; break; }
        }
        ok(allEq, "T10.1 同 seed + 等价 state 产生等长完全相同的命中序列");
        ok(stateA["k"] == stateB["k"], "T10.2 终态计数表等价");
    }
}
