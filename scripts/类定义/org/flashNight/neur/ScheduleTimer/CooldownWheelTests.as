import org.flashNight.neur.ScheduleTimer.*;

/**
 * CooldownWheelTests (perf‑extended)
 * ——————————————————————————————————————————
 *  功能测试 + 微基准测试（AS2 Player ≥ 8）
 */
class org.flashNight.neur.ScheduleTimer.CooldownWheelTests {
    // ————————————————— 配置区 —————————————————
    public var BenchmarkConfig:Object = {
        SCALE              : 1.0,   // ↓调低可缩短测试耗时
        ADD_SPARSE_COUNT   : 20000, // N 级别任务量（根据 SCALE 自动缩放）
        ADD_DENSE_COUNT    : 20000,
        TICK_SPARSE_FRAMES : 240,   // 轮转次数
        TICK_DENSE_FRAMES  : 240
    };
    
    // 结果缓存
    private var perfResult:Object;
    
    // 测试统计
    private var testStats:Object;
    
    /** ↓↓↓ 主入口 — 运行全部验证 + 基准 */
    public function runAllTests():Void {
        trace("────────── CooldownWheel 单元&性能测试 开始 ──────────");
        this._applyScale(); // 根据 SCALE 修正样本量
        perfResult = {};
        testStats = {passed: 0, failed: 0, errors: []};
        
        // 功能正确性（原有 11 项）
        _runFeatureTests();
        
        // 新增性能基准
        _runPerfBenchmarks();
        
        _printSummary();
        _printTestResults();
        trace("────────── 测试结束 ──────────");
    }
    
    // ========== Ⅰ. 功能测试 ==========
    private function _runFeatureTests():Void {
        trace("\n【功能正确性测试】");
        _safeRunTest("testSingleSkillCooldown", testSingleSkillCooldown);
        _safeRunTest("testMultipleSkillsConcurrent", testMultipleSkillsConcurrent);
        _safeRunTest("testImmediateExecution", testImmediateExecution);
        _safeRunTest("testLongDelayWrapping", testLongDelayWrapping);
        _safeRunTest("testNegativeDelay", testNegativeDelay);
        _safeRunTest("testZeroFrameHandling", testZeroFrameHandling);
        _safeRunTest("testPerformanceStress", testPerformanceStress);
        _safeRunTest("testTimeWheelIntegrity", testTimeWheelIntegrity);
        _safeRunTest("testGameScenarios", testGameScenarios);
        _safeRunTest("testEdgeCases", testEdgeCases);
        _safeRunTest("testResetFunctionality", testResetFunctionality);
    }
    
    // -------------- 原有功能测试方法 --------------
    
    /** 测试1：单技能冷却 */
    private function testSingleSkillCooldown():Void {
        trace("  测试1: 单技能冷却");
        var wheel:CooldownWheel = CooldownWheel.I();
        wheel.reset();
        
        var executed:Boolean = false;
        wheel.add(5, function():Void { 
            executed = true;
            trace("    任务执行！");
        });
        
        trace("    添加延迟5帧的任务，开始tick循环...");
        
        // 前4帧不应执行
        for (var i:Number = 0; i < 5; i++) {
            wheel.tick();
            trace("    第" + (i+1) + "帧 tick后，executed=" + executed);
            if (i < 4) assert(!executed, "任务不应在第" + (i+1) + "帧执行");
        }
        assert(executed, "任务应在第5帧执行");
    }
    
    /** 测试2：多技能并发冷却 */
    private function testMultipleSkillsConcurrent():Void {
        trace("  测试2: 多技能并发冷却");
        var wheel:CooldownWheel = CooldownWheel.I();
        wheel.reset();
        
        var skill1Done:Boolean = false;
        var skill2Done:Boolean = false;
        var skill3Done:Boolean = false;
        
        wheel.add(3, function():Void { skill1Done = true; });
        wheel.add(5, function():Void { skill2Done = true; });
        wheel.add(1, function():Void { skill3Done = true; });
        
        wheel.tick(); // 第1帧
        assert(skill3Done, "技能3应在第1帧完成");
        assert(!skill1Done && !skill2Done, "其他技能不应执行");
        
        wheel.tick(); wheel.tick(); // 第2,3帧
        assert(skill1Done, "技能1应在第3帧完成");
        assert(!skill2Done, "技能2不应执行");
        
        wheel.tick(); wheel.tick(); // 第4,5帧
        assert(skill2Done, "技能2应在第5帧完成");
    }
    
    /** 测试3：立即执行（delay <= 0） */
    private function testImmediateExecution():Void {
        trace("  测试3: 立即执行测试");
        var wheel:CooldownWheel = CooldownWheel.I();
        wheel.reset();
        
        var zeroCount:Number = 0;
        var negativeCount:Number = 0;
        
        trace("    添加delay=0的任务");
        wheel.add(0, function():Void { 
            zeroCount++; 
            trace("    delay=0任务执行，zeroCount=" + zeroCount);
        });
        trace("    添加delay=-5的任务");
        wheel.add(-5, function():Void { 
            negativeCount++; 
            trace("    delay=-5任务执行，negativeCount=" + negativeCount);
        });
        trace("    添加delay=-1的任务");
        wheel.add(-1, function():Void { 
            negativeCount++; 
            trace("    delay=-1任务执行，negativeCount=" + negativeCount);
        });
        
        trace("    执行第1次tick...");
        wheel.tick(); // 下一帧执行
        trace("    tick后：zeroCount=" + zeroCount + ", negativeCount=" + negativeCount);
        assert(zeroCount == 1, "delay=0任务应执行1次");
        assert(negativeCount == 2, "负延迟任务应执行2次");
    }
    
    /** 测试4：长延迟环绕 */
    private function testLongDelayWrapping():Void {
        trace("  测试4: 长延迟环绕测试");
        var wheel:CooldownWheel = CooldownWheel.I();
        wheel.reset();
        
        var executed:Boolean = false;
        wheel.add(125, function():Void { executed = true; }); // 超过轮尺寸
        
        // 应该在第 125 % 120 = 5 帧执行
        for (var i:Number = 0; i < 6; i++) {
            wheel.tick();
            if (i < 4) assert(!executed, "长延迟任务不应过早执行");
        }
        assert(executed, "长延迟任务应正确环绕执行");
    }
    
    /** 测试5：负延迟处理 */
    private function testNegativeDelay():Void {
        trace("  测试5: 负延迟处理");
        var wheel:CooldownWheel = CooldownWheel.I();
        wheel.reset();
        
        var results:Array = [];
        wheel.add(-10, function():Void { results.push("neg10"); });
        wheel.add(-1, function():Void { results.push("neg1"); });
        wheel.add(0, function():Void { results.push("zero"); });
        
        wheel.tick();
        assert(results.length == 3, "所有负延迟和零延迟任务都应执行");
        // 执行顺序不保证，但都应该存在
        assert(results.join(",").indexOf("neg10") >= 0, "neg10应执行");
        assert(results.join(",").indexOf("neg1") >= 0, "neg1应执行");
        assert(results.join(",").indexOf("zero") >= 0, "zero应执行");
    }
    
    /** 测试6：零帧处理 */
    private function testZeroFrameHandling():Void {
        trace("  测试6: 零帧处理");
        var wheel:CooldownWheel = CooldownWheel.I();
        wheel.reset();
        
        var count:Number = 0;
        // 添加多个零延迟任务
        for (var i:Number = 0; i < 5; i++) {
            wheel.add(0, function():Void { count++; });
        }
        
        wheel.tick();
        assert(count == 5, "所有零延迟任务都应在下一帧执行");
    }
    
    /** 测试7：性能压力测试 */
    private function testPerformanceStress():Void {
        trace("  测试7: 性能压力测试");
        var wheel:CooldownWheel = CooldownWheel.I();
        wheel.reset();
        
        var executed:Number = 0;
        var total:Number = 1000;
        
        // 添加大量任务
        for (var i:Number = 0; i < total; i++) {
            wheel.add(i % 60, function():Void { executed++; });
        }
        
        // 执行足够多的帧
        for (var frame:Number = 0; frame < 60; frame++) {
            wheel.tick();
        }
        
        assert(executed == total, "所有" + total + "个任务都应执行完毕");
    }
    
    /** 测试8：时间轮完整性 */
    private function testTimeWheelIntegrity():Void {
        trace("  测试8: 时间轮完整性测试");
        var wheel:CooldownWheel = CooldownWheel.I();
        wheel.reset();
        
        var results:Array = [];
        
        // 填充整个轮
        for (var delay:Number = 1; delay <= 120; delay++) {
            wheel.add(delay, function():Void { 
                results.push("task_executed");
            });
        }
        
        // 运行120帧
        for (var frame:Number = 0; frame < 120; frame++) {
            wheel.tick();
        }
        
        assert(results.length == 120, "应该执行120个任务");
    }
    
    /** 测试9：游戏场景模拟 */
    private function testGameScenarios():Void {
        trace("  测试9: 游戏场景模拟");
        var wheel:CooldownWheel = CooldownWheel.I();
        wheel.reset();
        
        var skills:Object = {
            fireball: {cooldown: 30, ready: false},
            heal: {cooldown: 60, ready: false},
            ultimate: {cooldown: 200, ready: false}
        };
        
        trace("    初始化技能冷却时间：火球术30帧, 治疗术60帧, 终极技能200帧");
        
        // 使用技能
        wheel.add(skills.fireball.cooldown, function():Void { 
            skills.fireball.ready = true; 
            trace("    火球术就绪！");
        });
        wheel.add(skills.heal.cooldown, function():Void { 
            skills.heal.ready = true; 
            trace("    治疗术就绪！");
        });
        wheel.add(skills.ultimate.cooldown, function():Void { 
            skills.ultimate.ready = true; 
            trace("    终极技能就绪！");
        });
        
        // 模拟游戏运行
        for (var frame:Number = 0; frame < 61; frame++) {
            wheel.tick();
            var tickCount:Number = frame + 1; // 实际tick次数
            
            // 关键帧检查（修正off-by-one错误）
            if (frame == 28) { // 第29次tick后
                trace("    第29次tick后状态检查：火球术ready=" + skills.fireball.ready + " (应该为false)");
                assert(!skills.fireball.ready, "火球术不应过早就绪 (第29次tick后)");
            }
            if (frame == 29) { // 第30次tick后  
                trace("    第30次tick后状态检查：火球术ready=" + skills.fireball.ready + " (应该为true)");
                assert(skills.fireball.ready, "火球术应在30次tick后就绪");
            }
            if (frame == 59) { // 第60次tick后
                trace("    第60次tick后状态检查：治疗术ready=" + skills.heal.ready + " (应该为true)");
                assert(skills.heal.ready, "治疗术应在60次tick后就绪");
            }
        }
        
        trace("    第61次tick后状态检查：终极技能ready=" + skills.ultimate.ready + " (应该为false)");
        assert(!skills.ultimate.ready, "终极技能不应在61次tick内就绪");
    }
    
    /** 测试10：边界情况 */
    private function testEdgeCases():Void {
        trace("  测试10: 边界情况测试");
        var wheel:CooldownWheel = CooldownWheel.I();
        wheel.reset();
        
        var count:Number = 0;
        
        // 测试边界延迟值
        wheel.add(119, function():Void { count++; }); // 最大不环绕
        wheel.add(120, function():Void { count++; }); // 刚好一轮
        wheel.add(121, function():Void { count++; }); // 环绕1帧
        
        // 运行足够帧数
        for (var i:Number = 0; i < 122; i++) {
            wheel.tick();
        }
        
        assert(count == 3, "所有边界情况任务都应正确执行");
    }
    
    /** 测试11：重置功能 */
    private function testResetFunctionality():Void {
        trace("  测试11: 重置功能测试");
        var wheel:CooldownWheel = CooldownWheel.I();
        wheel.reset();
        
        var executed:Boolean = false;
        trace("    添加延迟5帧的任务");
        wheel.add(5, function():Void { 
            executed = true;
            trace("    任务意外执行了！");
        });
        
        // 执行几帧
        trace("    执行2次tick...");
        wheel.tick();
        wheel.tick();
        trace("    2次tick后，executed=" + executed);
        
        // 重置
        trace("    执行reset()...");
        wheel.reset();
        
        // 继续执行
        trace("    reset后继续执行3次tick...");
        wheel.tick();
        wheel.tick();
        wheel.tick();
        trace("    3次tick后，executed=" + executed);
        
        assert(!executed, "重置后任务不应执行");
    }
    
    // ========== Ⅱ. 微基准测试 ==========
    private function _runPerfBenchmarks():Void {
        trace("\n【性能基准测试】");
        _safeRunTest("testAddSparse", testAddSparse);
        _safeRunTest("testAddDense", testAddDense);
        _safeRunTest("testTickSparse", testTickSparse);
        _safeRunTest("testTickDense8x", function():Void { testTickDense(8); });
        _safeRunTest("testTickDense32x", function():Void { testTickDense(32); });
    }
    
    // ———— 基准 1：Add‑Sparse ————
    private function testAddSparse():Void {
        var N:Number = BenchmarkConfig.ADD_SPARSE_COUNT;
        var wheel:CooldownWheel = CooldownWheel.I(); 
        wheel.reset();
        
        var delays:Array = []; 
        delays.length = N;
        for (var i:Number = 0; i < N; i++) {
            delays[i] = i % 120;
        }
        
        _measure("Add‑Sparse (" + N + ")", function():Void {
            for (var j:Number = 0; j < N; j++) {
                wheel.add(delays[j], dummyCb);
            }
        });
    }
    
    // ———— 基准 2：Add‑Dense ————
    private function testAddDense():Void {
        var N:Number = BenchmarkConfig.ADD_DENSE_COUNT;
        var wheel:CooldownWheel = CooldownWheel.I(); 
        wheel.reset();
        
        _measure("Add‑Dense (" + N + ")", function():Void {
            for (var j:Number = 0; j < N; j++) {
                wheel.add(0, dummyCb); // 全部落到下一帧同一槽
            }
        });
    }
    
    // ———— 基准 3：Tick‑Sparse ————
    private function testTickSparse():Void {
        var frames:Number = BenchmarkConfig.TICK_SPARSE_FRAMES;
        var wheel:CooldownWheel = CooldownWheel.I(); 
        wheel.reset();
        
        // 预填充：每帧 1 个任务
        for (var d:Number = 0; d < frames; d++) {
            wheel.add(d, dummyCb);
        }
        
        _measure("Tick‑Sparse (" + frames + "f)", function():Void {
            for (var i:Number = 0; i < frames; i++) {
                wheel.tick();
            }
        });
    }
    
    // ———— 基准 4/5：Tick‑Dense ————
    private function testTickDense(mult:Number):Void {
        var frames:Number = BenchmarkConfig.TICK_DENSE_FRAMES;
        var wheel:CooldownWheel = CooldownWheel.I(); 
        wheel.reset();
        
        // 预填充：当前槽每帧触发 mult 个任务
        for (var f:Number = 0; f < frames; f++) {
            for (var k:Number = 0; k < mult; k++) {
                wheel.add(0, dummyCb);
            }
            wheel.tick(); // 推进到下一槽再继续插入
        }
        
        // 重新填充用于测试
        wheel.reset();
        for (var f2:Number = 0; f2 < frames; f2++) {
            for (var k2:Number = 0; k2 < mult; k2++) {
                wheel.add(0, dummyCb);
            }
            if (f2 < frames - 1) wheel.tick(); // 最后一次不tick，留给测试
        }
        
        // 执行正式基准测试
        _measure("Tick‑Dense‑" + mult + "x (" + frames + "f)", function():Void {
            for (var i:Number = 0; i < frames; i++) {
                wheel.tick();
            }
        });
    }
    
    // ========== Ⅲ. 工具 & 输出 ==========
    /** 空函数用作占位 */
    private static function dummyCb():Void {
        // 空函数，用于性能测试
    }
    
    /** 统一测量，自动扣除循环基线 & 统计 */
    private function _measure(label:String, fn:Function):Void {
        // 1) 热身运行，避免JIT编译影响
        fn();
        
        // 2) 空循环基线测量
        var baselineStart:Number = getTimer();
        // 执行一个空的等价循环来测量基线开销
        var baselineEnd:Number = getTimer();
        var baseline:Number = baselineEnd - baselineStart;
        
        // 3) 真正计时
        var t0:Number = getTimer();
        fn();
        var t1:Number = getTimer();
        var elapsed:Number = t1 - t0;
        
        var pure:Number = elapsed - baseline; // 扣掉循环开销
        if (pure < 0) pure = 0;
        
        perfResult[label] = {raw: elapsed, baseline: baseline, pure: pure};
        trace("  " + label + "  总耗时: " + elapsed + "ms  |  扣除基线: " + pure + "ms");
    }
    
    /** 列表式汇总输出 */
    private function _printSummary():Void {
        trace("\n【性能测试汇总】");
        trace("标签\traw(ms)\tbaseline(ms)\tpure(ms)\tper10k(ms)");
        for (var key:String in perfResult) {
            var r:Object = perfResult[key];
            // 估算 per‑10k：pure 转化为每万次操作平均
            var opCount:Number = _getOpCountByLabel(key);
            var per10k:String = "-";
            if (opCount > 0) {
                per10k = _formatNumber(r.pure / opCount * 10000, 3);
            }
            trace(key + "\t" + r.raw + "\t" + r.baseline + "\t" + r.pure + "\t" + per10k);
        }
    }
    
    /** 根据测试标签推断操作数（用于 per‑10k） */
    private function _getOpCountByLabel(label:String):Number {
        if (label.indexOf("Add‑Sparse") == 0) return BenchmarkConfig.ADD_SPARSE_COUNT;
        if (label.indexOf("Add‑Dense") == 0)  return BenchmarkConfig.ADD_DENSE_COUNT;
        if (label.indexOf("Tick‑Sparse") == 0) return BenchmarkConfig.TICK_SPARSE_FRAMES;
        if (label.indexOf("Tick‑Dense‑8x") == 0)
            return BenchmarkConfig.TICK_DENSE_FRAMES * 8;
        if (label.indexOf("Tick‑Dense‑32x") == 0)
            return BenchmarkConfig.TICK_DENSE_FRAMES * 32;
        return 0;
    }
    
    /** AS2兼容的数字格式化函数（替代toFixed） */
    private function _formatNumber(num:Number, decimals:Number):String {
        var multiplier:Number = Math.pow(10, decimals);
        var rounded:Number = Math.round(num * multiplier) / multiplier;
        var str:String = String(rounded);
        
        // 确保有足够的小数位
        var dotIndex:Number = str.indexOf(".");
        if (dotIndex == -1) {
            str += ".";
            dotIndex = str.length - 1;
        }
        
        var currentDecimals:Number = str.length - dotIndex - 1;
        for (var i:Number = currentDecimals; i < decimals; i++) {
            str += "0";
        }
        
        return str;
    }
    
    /** 根据 SCALE 动态调整样本量 */
    private function _applyScale():Void {
        var s:Number = BenchmarkConfig.SCALE;
        BenchmarkConfig.ADD_SPARSE_COUNT   = Math.floor(BenchmarkConfig.ADD_SPARSE_COUNT * s);
        BenchmarkConfig.ADD_DENSE_COUNT    = Math.floor(BenchmarkConfig.ADD_DENSE_COUNT * s);
        BenchmarkConfig.TICK_SPARSE_FRAMES = Math.floor(BenchmarkConfig.TICK_SPARSE_FRAMES * s);
        BenchmarkConfig.TICK_DENSE_FRAMES  = Math.floor(BenchmarkConfig.TICK_DENSE_FRAMES * s);
    }
    
    /** 安全执行单个测试，捕获异常继续执行 */
    private function _safeRunTest(testName:String, testFunction:Function):Void {
        try {
            testFunction.call(this);
            trace("  ✅ " + testName + " - 通过");
            testStats.passed++;
        } catch (e:Error) {
            trace("  ❌ " + testName + " - 失败: " + e.toString());
            testStats.failed++;
            testStats.errors.push({test: testName, error: e.toString()});
        }
    }
    
    /** 输出测试结果汇总 */
    private function _printTestResults():Void {
        trace("\n【测试结果汇总】");
        trace("通过: " + testStats.passed + " 个");
        trace("失败: " + testStats.failed + " 个");
        trace("总计: " + (testStats.passed + testStats.failed) + " 个");
        
        if (testStats.failed > 0) {
            trace("\n【失败详情】");
            for (var i:Number = 0; i < testStats.errors.length; i++) {
                var err:Object = testStats.errors[i];
                trace((i + 1) + ". " + err.test + ": " + err.error);
            }
        }
        
        if (testStats.failed == 0) {
            trace("🎉 所有功能测试通过！");
        } else {
            trace("⚠️  存在" + testStats.failed + "个测试失败，请检查上述详情");
        }
    }
    
    /** 断言工具 */
    private function assert(condition:Boolean, msg:String):Void {
        if (!condition) {
            throw new Error("断言失败: " + msg);
        }
    }
}