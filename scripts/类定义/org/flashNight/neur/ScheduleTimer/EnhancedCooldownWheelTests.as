import org.flashNight.neur.ScheduleTimer.*;

/**
 * EnhancedCooldownWheelTests
 * ——————————————————————————————————————————
 * 增强版时间轮的功能测试 + 性能基准测试
 * 
 * 测试覆盖：
 * - 原有CooldownWheel功能兼容性
 * - 新增重复任务功能
 * - 任务取消机制
 * - 参数传递
 * - 任务ID管理
 * - 兼容原帧计时器接口
 */
class org.flashNight.neur.ScheduleTimer.EnhancedCooldownWheelTests {
    
    // ————————————————— 配置区 —————————————————
    public var BenchmarkConfig:Object = {
        SCALE              : 1.0,   // 缩放因子
        ADD_SPARSE_COUNT   : 15000, // 稀疏任务量
        ADD_DENSE_COUNT    : 15000, // 密集任务量
        REPEATING_COUNT    : 5000,  // 重复任务量
        TICK_SPARSE_FRAMES : 200,   // 稀疏轮转次数
        TICK_DENSE_FRAMES  : 200,   // 密集轮转次数
        CANCEL_RATIO       : 0.3    // 取消任务比例
    };
    
    // 结果缓存
    private var perfResult:Object;
    
    // 测试统计
    private var testStats:Object;
    
    /** 主入口 — 运行全部验证 + 基准 */
    public function runAllTests():Void {
        trace("────────── EnhancedCooldownWheel 测试套件开始 ──────────");
        this._applyScale();
        perfResult = {};
        testStats = {passed: 0, failed: 0, errors: []};
        
        // 功能正确性测试
        _runFeatureTests();

        // v1.3 生命周期 API 测试
        runFixV13Tests();

        // v1.8 Never-Early 修复测试
        runFixV18Tests();

        // 性能基准测试
        _runPerfBenchmarks();
        
        _printSummary();
        _printTestResults();
        trace("────────── 测试结束 ──────────");
    }
    
    // ========== Ⅰ. 功能测试 ==========
    private function _runFeatureTests():Void {
        trace("\n【功能正确性测试】");
        
        // 基础兼容性测试
        _safeRunTest("testBasicCompatibility", testBasicCompatibility);
        _safeRunTest("testAddDelayedTask", testAddDelayedTask);
        _safeRunTest("testImmediateExecution", testImmediateExecution);
        _safeRunTest("testLongDelayWrapping", testLongDelayWrapping);
        
        // 新增功能测试
        _safeRunTest("testRepeatingTasks", testRepeatingTasks);
        _safeRunTest("testTaskCancellation", testTaskCancellation);
        _safeRunTest("testParameterPassing", testParameterPassing);
        _safeRunTest("testTaskIdManagement", testTaskIdManagement);
        _safeRunTest("testFrameTimerCompatibility", testFrameTimerCompatibility);
        
        // 复杂场景测试
        _safeRunTest("testMixedTaskTypes", testMixedTaskTypes);
        _safeRunTest("testMassiveCancellation", testMassiveCancellation);
        _safeRunTest("testRepeatingTaskLimits", testRepeatingTaskLimits);
        _safeRunTest("testErrorHandling", testErrorHandling);
        _safeRunTest("testResourceCleanup", testResourceCleanup);
        _safeRunTest("testGameScenarioSimulation", testGameScenarioSimulation);
        _safeRunTest("testResetFunctionality", testResetFunctionality);
    }
    
    // -------------- 基础兼容性测试 --------------
    
    /** 测试1：基础兼容性 */
    private function testBasicCompatibility():Void {
        trace("  测试1: 基础兼容性");
        var wheel:EnhancedCooldownWheel = EnhancedCooldownWheel.I();
        wheel.reset();
        
        var executed:Boolean = false;
        wheel.add(5, function():Void { 
            executed = true;
            trace("    兼容性任务执行！");
        });
        
        trace("    添加延迟5帧的任务...");
        for (var i:Number = 0; i < 6; i++) {
            wheel.tick();
            if (i < 4) assert(!executed, "任务不应在第" + (i+1) + "帧执行");
        }
        assert(executed, "任务应在第5帧执行");
    }
    
    /** 测试2：addDelayedTask方法 */
    private function testAddDelayedTask():Void {
        trace("  测试2: addDelayedTask方法");
        var wheel:EnhancedCooldownWheel = EnhancedCooldownWheel.I();
        wheel.reset();
        
        var results:Array = [];
        var task1Id:Number = wheel.addDelayedTask(100, function(msg:String):Void { 
            results.push(msg);
        }, "task1");
        var task2Id:Number = wheel.addDelayedTask(200, function(msg:String):Void { 
            results.push(msg);
        }, "task2");
        
        assert(task1Id != task2Id, "任务ID应该不同");
        
        for (var i:Number = 0; i < 15; i++) {
            wheel.tick();
        }
        assert(results.length == 2, "两个延迟任务都应执行");
        assert(arrayContains(results, "task1"), "task1应执行");
        assert(arrayContains(results, "task2"), "task2应执行");
    }
    
    /** 测试3：立即执行 */
    private function testImmediateExecution():Void {
        trace("  测试3: 立即执行测试");
        var wheel:EnhancedCooldownWheel = EnhancedCooldownWheel.I();
        wheel.reset();
        
        var count:Number = 0;
        wheel.addDelayedTask(0, function():Void { count++; });
        wheel.addDelayedTask(-50, function():Void { count++; });
        
        wheel.tick();
        assert(count == 2, "零/负延迟任务应立即执行");
    }
    
    /** 测试4：长延迟环绕行为验证
     * 【契约行为】: delay > 127 帧时，会因位运算回环而执行时间不可预测。
     * 此测试验证这是已知的、确定的契约行为，而非 bug。
     *
     * 例如：delay = 200 帧，实际槽位 = (pos + 200) & 127 = pos + 72
     * 任务会在约 72 帧后执行，而非 200 帧。
     */
    private function testLongDelayWrapping():Void {
        trace("  测试4: 长延迟环绕行为验证（契约行为）");
        var wheel:EnhancedCooldownWheel = EnhancedCooldownWheel.I();
        wheel.reset();

        var executed:Boolean = false;
        var executedAtTick:Number = -1;

        // 【契约测试】: 使用超出 127 帧的延迟，验证回环行为
        // 200 帧 -> (pos + 200) & 127 = 约 72 帧后执行（取决于当前 pos）
        var overflowDelay:Number = 200; // 超过 127 帧限制
        wheel.add(overflowDelay, function():Void {
            executed = true;
            executedAtTick = tickCount;
        });

        var tickCount:Number = 0;
        // 执行 128 帧，足够覆盖任何回环位置
        for (var i:Number = 0; i < 128; i++) {
            tickCount = i;
            wheel.tick();
        }

        // 【契约验证】: 任务应该执行了，但不是在 200 帧
        // 实际执行位置 = (200) & 127 = 72（相对于添加时的 pos）
        assert(executed, "回环任务应在 128 帧内执行（契约行为：delay 被截断）");
        trace("    任务在第 " + executedAtTick + " 帧执行（契约：200 帧被回环）");
    }
    
    // -------------- 新增功能测试 --------------
    
    /** 测试5：重复任务 */
    private function testRepeatingTasks():Void {
        trace("  测试5: 重复任务测试");
        var wheel:EnhancedCooldownWheel = EnhancedCooldownWheel.I();
        wheel.reset();
        
        var counter:Number = 0;
        var taskId:Number = wheel.addTask(function():Void { 
            counter++;
            trace("    重复任务执行第" + counter + "次");
        }, 100, 3); // 100ms间隔，重复3次
        
        trace("    添加重复3次的任务，间隔100ms...");
        
        // 执行足够的帧数
        for (var i:Number = 0; i < 25; i++) {
            wheel.tick();
        }
        
        assert(counter == 3, "重复任务应执行3次，实际执行" + counter + "次");
        assert(wheel.getActiveTaskCount() == 0, "任务完成后应被清理");
    }
    
    /** 测试6：任务取消 */
    private function testTaskCancellation():Void {
        trace("  测试6: 任务取消测试");
        var wheel:EnhancedCooldownWheel = EnhancedCooldownWheel.I();
        wheel.reset();
        
        var executed:Boolean = false;
        var taskId:Number = wheel.addDelayedTask(300, function():Void { 
            executed = true;
            trace("    被取消的任务意外执行！");
        });
        
        trace("    添加300ms延迟任务，任务ID=" + taskId);
        
        // 执行几帧
        wheel.tick();
        wheel.tick();
        
        // 取消任务
        trace("    取消任务...");
        wheel.removeTask(taskId);
        
        // 继续执行
        for (var i:Number = 0; i < 10; i++) {
            wheel.tick();
        }
        
        assert(!executed, "被取消的任务不应执行");
        assert(wheel.getActiveTaskCount() == 0, "取消后应无活跃任务");
    }
    
    /** 测试7：参数传递 */
    private function testParameterPassing():Void {
        trace("  测试7: 参数传递测试");
        var wheel:EnhancedCooldownWheel = EnhancedCooldownWheel.I();
        wheel.reset();
        
        var results:Array = [];
        
        // 单参数
        wheel.addDelayedTask(50, function(msg:String):Void { 
            results.push("single:" + msg);
        }, "hello");
        
        // 多参数
        wheel.addTask(function(a:Number, b:String, c:Boolean):Void { 
            results.push("multi:" + a + "," + b + "," + c);
        }, 80, 1, 42, "world", true);
        
        // 无参数
        wheel.addDelayedTask(60, function():Void { 
            results.push("none");
        });
        
        for (var i:Number = 0; i < 5; i++) {
            wheel.tick();
        }
        
        assert(results.length == 3, "所有参数传递任务都应执行");
        assert(results.join("|").indexOf("single:hello") >= 0, "单参数传递失败");
        assert(results.join("|").indexOf("multi:42,world,true") >= 0, "多参数传递失败");
        assert(results.join("|").indexOf("none") >= 0, "无参数任务执行失败");
    }
    
    /** 测试8：任务ID管理 */
    private function testTaskIdManagement():Void {
        trace("  测试8: 任务ID管理测试");
        var wheel:EnhancedCooldownWheel = EnhancedCooldownWheel.I();
        wheel.reset();
        
        var ids:Array = [];
        
        // 创建多个任务
        for (var i:Number = 0; i < 10; i++) {
            var id:Number = wheel.addDelayedTask(100 * (i + 1), function():Void {});
            ids.push(id);
        }
        
        // 验证ID唯一性
        for (var j:Number = 0; j < ids.length; j++) {
            for (var k:Number = j + 1; k < ids.length; k++) {
                assert(ids[j] != ids[k], "任务ID应该唯一");
            }
        }
        
        assert(wheel.getActiveTaskCount() == 10, "应有10个活跃任务");
        
        // 取消一半任务
        for (var l:Number = 0; l < 5; l++) {
            wheel.removeTask(ids[l]);
        }
        
        assert(wheel.getActiveTaskCount() == 5, "取消后应剩余5个活跃任务");
    }
    
    /** 测试9：帧计时器兼容性 */
    private function testFrameTimerCompatibility():Void {
        trace("  测试9: 帧计时器兼容性测试");
        var wheel:EnhancedCooldownWheel = EnhancedCooldownWheel.I();
        wheel.reset();
        
        var canvas:Object = {cycleCount: 0, shadowCount: 5};
        var fadeCount:Number = 0;
        
        // 模拟VectorAfterimageRenderer的使用方式
        var callback:Function = function(canvasObj:Object):Void {
            canvasObj.cycleCount++;
            fadeCount++;
            trace("    渐隐回调执行，cycleCount=" + canvasObj.cycleCount);
        };
        
        var taskId:Number = wheel.addTask(callback, 100, 5, canvas);
        
        trace("    模拟渐隐任务，间隔100ms，重复5次...");
        
        for (var i:Number = 0; i < 35; i++) {
            wheel.tick();
        }
        
        assert(fadeCount == 5, "渐隐任务应执行5次");
        assert(canvas.cycleCount == 5, "画布计数应为5");
        assert(wheel.getActiveTaskCount() == 0, "任务完成后应清理");
    }
    
    // -------------- 复杂场景测试 --------------
    
    /** 测试10：混合任务类型 */
    private function testMixedTaskTypes():Void {
        trace("  测试10: 混合任务类型测试");
        var wheel:EnhancedCooldownWheel = EnhancedCooldownWheel.I();
        wheel.reset();
        
        var results:Array = [];
        
        // 一次性任务
        wheel.addDelayedTask(50, function():Void { results.push("once"); });
        
        // 重复任务
        wheel.addTask(function():Void { results.push("repeat"); }, 80, 2);
        
        // 立即任务
        wheel.add(0, function():Void { results.push("immediate"); });
        
        // 长延迟任务
        wheel.addDelayedTask(300, function():Void { results.push("long"); });
        
        for (var i:Number = 0; i < 12; i++) {
            wheel.tick();
        }
        
        assert(results.length == 5, "混合任务执行总数应为5"); // once + repeat*2 + immediate + long
        assert(arrayContains(results, "immediate"), "立即任务应执行");
        assert(arrayContains(results, "once"), "一次性任务应执行");
        assert(arrayContains(results, "long"), "长延迟任务应执行");
        
        var repeatCount:Number = 0;
        for (var j:Number = 0; j < results.length; j++) {
            if (results[j] == "repeat") repeatCount++;
        }
        assert(repeatCount == 2, "重复任务应执行2次");
    }
    
    /** 测试11：大量取消 */
    private function testMassiveCancellation():Void {
        trace("  测试11: 大量取消测试");
        var wheel:EnhancedCooldownWheel = EnhancedCooldownWheel.I();
        wheel.reset();
        
        var ids:Array = [];
        var executed:Number = 0;
        
        // 创建大量任务
        for (var i:Number = 0; i < 100; i++) {
            var id:Number = wheel.addDelayedTask(200, function():Void { executed++; });
            ids.push(id);
        }
        
        assert(wheel.getActiveTaskCount() == 100, "应有100个活跃任务");
        
        // 取消大部分任务
        for (var j:Number = 0; j < 80; j++) {
            wheel.removeTask(ids[j]);
        }
        
        assert(wheel.getActiveTaskCount() == 20, "取消后应剩余20个活跃任务");
        
        // 执行剩余任务
        for (var k:Number = 0; k < 8; k++) {
            wheel.tick();
        }
        
        assert(executed == 20, "应只执行20个未取消的任务");
    }
    
    /** 测试12：重复任务限制 */
    private function testRepeatingTaskLimits():Void {
        trace("  测试12: 重复任务限制测试");
        var wheel:EnhancedCooldownWheel = EnhancedCooldownWheel.I();
        wheel.reset();
        
        var counter:Number = 0;
        
        // 无限重复任务（传入 true 表示无限）
        var taskId:Number = wheel.addTask(function():Void { 
            counter++;
            if (counter >= 10) {
                // 手动停止无限重复
                wheel.removeTask(taskId);
            }
        }, 50, true); // true表示无限重复（v1.4统一语义）
        
        for (var i:Number = 0; i < 20; i++) {
            wheel.tick();
        }
        
        assert(counter == 10, "无限重复任务应被手动停止在10次");
        assert(wheel.getActiveTaskCount() == 0, "停止后应无活跃任务");
    }
    
    /** 测试13：任务执行顺序与 LIFO 行为
     * 【契约行为】
     * - 不同槽位的任务按槽位顺序执行（先到期的先执行）
     * - 同一槽位内的任务按 LIFO 顺序执行（后添加的先执行）
     */
    private function testErrorHandling():Void {
        trace("  测试13: 任务执行顺序测试");
        var wheel:EnhancedCooldownWheel = EnhancedCooldownWheel.I();
        wheel.reset();

        var executionOrder:Array = [];

        // 使用帧级 API 确保任务在不同槽位
        // task1: 2 帧后执行
        wheel.add(2, function():Void {
            executionOrder.push("task1");
        });

        // task2: 4 帧后执行
        wheel.add(4, function():Void {
            executionOrder.push("task2");
        });

        // 执行 5 帧
        for (var i:Number = 0; i < 5; i++) {
            wheel.tick();
        }

        assert(executionOrder.length == 2, "两个任务都应执行");
        assert(executionOrder[0] == "task1", "task1 应先执行（2帧 < 4帧）");
        assert(executionOrder[1] == "task2", "task2 应后执行（4帧 > 2帧）");

        // 额外测试：同槽位 LIFO 行为
        wheel.reset();
        executionOrder = [];

        // 两个任务在同一槽位（都是 2 帧后）
        wheel.add(2, function():Void { executionOrder.push("A"); });
        wheel.add(2, function():Void { executionOrder.push("B"); });

        for (var j:Number = 0; j < 3; j++) {
            wheel.tick();
        }

        assert(executionOrder.length == 2, "同槽位任务都应执行");
        assert(executionOrder[0] == "B", "LIFO: 后添加的 B 应先执行");
        assert(executionOrder[1] == "A", "LIFO: 先添加的 A 应后执行");
    }
    
    /** 测试14：资源清理 */
    private function testResourceCleanup():Void {
        trace("  测试14: 资源清理测试");
        var wheel:EnhancedCooldownWheel = EnhancedCooldownWheel.I();
        wheel.reset();
        
        // 创建多种类型任务
        for (var i:Number = 0; i < 50; i++) {
            if (i % 3 == 0) {
                wheel.addDelayedTask(100, function():Void {});
            } else {
                wheel.addTask(function():Void {}, 80, 1);
            }
        }
        
        var initialCount:Number = wheel.getActiveTaskCount();
        assert(initialCount == 50, "初始应有50个活跃任务");
        
        // 执行足够时间让所有任务完成
        for (var j:Number = 0; j < 10; j++) {
            wheel.tick();
        }
        
        assert(wheel.getActiveTaskCount() == 0, "所有任务完成后应被清理");
    }
    
    /** 测试15：游戏场景模拟 */
    private function testGameScenarioSimulation():Void {
        trace("  测试15: 游戏场景模拟");
        var wheel:EnhancedCooldownWheel = EnhancedCooldownWheel.I();
        wheel.reset();
        
        var gameState:Object = {
            skillCooldowns: {},
            buffTimers: {},
            effects: []
        };
        
        // 技能冷却
        var fireballId:Number = wheel.addDelayedTask(3000, function():Void {
            gameState.skillCooldowns.fireball = false;
            trace("    火球术冷却完成");
        });
        gameState.skillCooldowns.fireball = true;
        
        // BUFF计时器
        var hasteId:Number = wheel.addDelayedTask(5000, function():Void {
            delete gameState.buffTimers.haste;
            trace("    急速BUFF结束");
        });
        gameState.buffTimers.haste = hasteId;
        
        // 持续伤害效果
        var dotId:Number = wheel.addTask(function():Void {
            gameState.effects.push("dot_tick");
            trace("    持续伤害tick");
        }, 1000, 3);
        
        // 模拟游戏运行
        for (var i:Number = 0; i < 200; i++) {
            wheel.tick();
        }
        
        assert(!gameState.skillCooldowns.fireball, "技能冷却应完成");
        assert(!gameState.buffTimers.haste, "BUFF应过期");
        assert(gameState.effects.length == 3, "持续效果应触发3次");
    }
    
    /** 测试16：重置功能 */
    private function testResetFunctionality():Void {
        trace("  测试16: 重置功能测试");
        var wheel:EnhancedCooldownWheel = EnhancedCooldownWheel.I();
        wheel.reset();
        
        var executed:Number = 0;
        
        // 添加各种任务
        wheel.addDelayedTask(200, function():Void { executed++; });
        wheel.addTask(function():Void { executed++; }, 100, 5);
        wheel.add(10, function():Void { executed++; });
        
        assert(wheel.getActiveTaskCount() > 0, "重置前应有活跃任务");
        
        // 执行几帧
        wheel.tick();
        wheel.tick();
        
        // 重置
        wheel.reset();
        
        assert(wheel.getActiveTaskCount() == 0, "重置后应无活跃任务");
        
        // 继续执行
        for (var i:Number = 0; i < 20; i++) {
            wheel.tick();
        }
        
        assert(executed <= 1, "重置后不应有更多任务执行"); // 可能有立即任务在reset前执行
    }
    
    // ========== Ⅱ. 性能基准测试 ==========
    public function _runPerfBenchmarks():Void {
        trace("\n【性能基准测试】");
        _safeRunTest("benchAddSparse", benchAddSparse);
        _safeRunTest("benchAddDense", benchAddDense);
        _safeRunTest("benchRepeatingTasks", benchRepeatingTasks);
        _safeRunTest("benchTaskCancellation", benchTaskCancellation);
        _safeRunTest("benchTickSparse", benchTickSparse);
        _safeRunTest("benchTickDense", benchTickDense);
        _safeRunTest("benchMixedOperations", benchMixedOperations);
    }
    
    /** 基准1：稀疏添加 */
    private function benchAddSparse():Void {
        var N:Number = BenchmarkConfig.ADD_SPARSE_COUNT;
        var wheel:EnhancedCooldownWheel = EnhancedCooldownWheel.I();
        wheel.reset();
        
        _measure("Add‑Sparse (" + N + ")", function():Void {
            for (var i:Number = 0; i < N; i++) {
                wheel.addDelayedTask((i % 120) * wheel.每帧毫秒, dummyCb);
            }
        });
    }
    
    /** 基准2：密集添加 */
    private function benchAddDense():Void {
        var N:Number = BenchmarkConfig.ADD_DENSE_COUNT;
        var wheel:EnhancedCooldownWheel = EnhancedCooldownWheel.I();
        wheel.reset();
        
        _measure("Add‑Dense (" + N + ")", function():Void {
            for (var i:Number = 0; i < N; i++) {
                wheel.addDelayedTask(0, dummyCb);
            }
        });
    }
    
    /** 基准3：重复任务 */
    private function benchRepeatingTasks():Void {
        var N:Number = BenchmarkConfig.REPEATING_COUNT;
        var wheel:EnhancedCooldownWheel = EnhancedCooldownWheel.I();
        wheel.reset();
        
        _measure("Repeating‑Tasks (" + N + ")", function():Void {
            for (var i:Number = 0; i < N; i++) {
                wheel.addTask(dummyCb, 100, 3);
            }
        });
    }
    
    /** 基准4：任务取消 */
    private function benchTaskCancellation():Void {
        var N:Number = Math.floor(BenchmarkConfig.ADD_SPARSE_COUNT * 0.5);
        var wheel:EnhancedCooldownWheel = EnhancedCooldownWheel.I();
        wheel.reset();
        
        var ids:Array = [];
        for (var i:Number = 0; i < N; i++) {
            ids.push(wheel.addDelayedTask(1000, dummyCb));
        }
        
        var cancelCount:Number = Math.floor(N * BenchmarkConfig.CANCEL_RATIO);
        _measure("Task‑Cancellation (" + cancelCount + "/" + N + ")", function():Void {
            for (var j:Number = 0; j < cancelCount; j++) {
                wheel.removeTask(ids[j]);
            }
        });
    }
    
    /** 基准5：稀疏tick */
    private function benchTickSparse():Void {
        var frames:Number = BenchmarkConfig.TICK_SPARSE_FRAMES;
        var wheel:EnhancedCooldownWheel = EnhancedCooldownWheel.I();
        wheel.reset();
        
        // 预填充
        for (var i:Number = 0; i < frames; i++) {
            wheel.addDelayedTask(i * wheel.每帧毫秒, dummyCb);
        }
        
        _measure("Tick‑Sparse (" + frames + "f)", function():Void {
            for (var j:Number = 0; j < frames; j++) {
                wheel.tick();
            }
        });
    }
    
    /** 基准6：密集tick */
    private function benchTickDense():Void {
        var frames:Number = BenchmarkConfig.TICK_DENSE_FRAMES;
        var wheel:EnhancedCooldownWheel = EnhancedCooldownWheel.I();
        wheel.reset();
        
        // 预填充：每帧20个任务
        for (var i:Number = 0; i < frames; i++) {
            for (var k:Number = 0; k < 20; k++) {
                wheel.addDelayedTask(0, dummyCb);
            }
            if (i < frames - 1) wheel.tick();
        }
        
        _measure("Tick‑Dense (" + frames + "f×20)", function():Void {
            for (var j:Number = 0; j < frames; j++) {
                wheel.tick();
            }
        });
    }
    
    /** 基准7：混合操作 */
    private function benchMixedOperations():Void {
        var wheel:EnhancedCooldownWheel = EnhancedCooldownWheel.I();
        wheel.reset();
        
        _measure("Mixed‑Operations", function():Void {
            var ids:Array = [];
            
            // 添加各种任务
            for (var i:Number = 0; i < 1000; i++) {
                if (i % 4 == 0) {
                    ids.push(wheel.addDelayedTask(100, dummyCb));
                } else if (i % 4 == 1) {
                    ids.push(wheel.addTask(dummyCb, 80, 2));
                } else {
                    wheel.add(i % 10, dummyCb);
                }
            }
            
            // 取消一些任务
            for (var j:Number = 0; j < 100; j++) {
                if (ids[j]) wheel.removeTask(ids[j]);
            }
            
            // 执行一些tick
            for (var k:Number = 0; k < 50; k++) {
                wheel.tick();
            }
        });
    }
    
    // ========== Ⅲ. 工具方法 ==========
    
    /** 空回调函数 */
    private static function dummyCb():Void {
        // 空函数，用于性能测试
    }
    
    /** 性能测量工具 */
    private function _measure(label:String, fn:Function):Void {
        // 热身
        fn();
        
        // 基线测量
        var baselineStart:Number = getTimer();
        var baselineEnd:Number = getTimer();
        var baseline:Number = baselineEnd - baselineStart;
        
        // 正式测量
        var t0:Number = getTimer();
        fn();
        var t1:Number = getTimer();
        var elapsed:Number = t1 - t0;
        
        var pure:Number = Math.max(0, elapsed - baseline);
        
        perfResult[label] = {raw: elapsed, baseline: baseline, pure: pure};
        trace("  " + label + "  总耗时: " + elapsed + "ms  |  净耗时: " + pure + "ms");
    }
    
    /** 缩放配置 */
    private function _applyScale():Void {
        var s:Number = BenchmarkConfig.SCALE;
        BenchmarkConfig.ADD_SPARSE_COUNT = Math.floor(BenchmarkConfig.ADD_SPARSE_COUNT * s);
        BenchmarkConfig.ADD_DENSE_COUNT = Math.floor(BenchmarkConfig.ADD_DENSE_COUNT * s);
        BenchmarkConfig.REPEATING_COUNT = Math.floor(BenchmarkConfig.REPEATING_COUNT * s);
        BenchmarkConfig.TICK_SPARSE_FRAMES = Math.floor(BenchmarkConfig.TICK_SPARSE_FRAMES * s);
        BenchmarkConfig.TICK_DENSE_FRAMES = Math.floor(BenchmarkConfig.TICK_DENSE_FRAMES * s);
    }
    
    /** 安全执行测试 */
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
    
    /** 结果汇总 */
    private function _printSummary():Void {
        trace("\n【性能测试汇总】");
        trace("标签\traw(ms)\tbaseline(ms)\tpure(ms)");
        for (var key:String in perfResult) {
            var r:Object = perfResult[key];
            trace(key + "\t" + r.raw + "\t" + r.baseline + "\t" + r.pure);
        }
    }
    
    /** 测试结果汇总 */
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
            trace("⚠️  存在" + testStats.failed + "个测试失败");
        } else {
            trace("🎉 所有测试通过！");
        }
    }
    
    /** 断言工具 */
    private function assert(condition:Boolean, msg:String):Void {
        if (!condition) {
            throw new Error("断言失败: " + msg);
        }
    }

    // ========== Ⅳ. v1.3 生命周期 API 测试 ==========

    /**
     * 运行所有 v1.3 测试
     */
    public function runFixV13Tests():Void {
        trace("\n【v1.3 生命周期 API 测试】");
        _safeRunTest("testAddOrUpdateTask_Basic", testAddOrUpdateTask_Basic);
        _safeRunTest("testAddOrUpdateTask_Replace", testAddOrUpdateTask_Replace);
        _safeRunTest("testRemoveTaskByLabel_Basic", testRemoveTaskByLabel_Basic);
        _safeRunTest("testRemoveTaskByLabel_NotExist", testRemoveTaskByLabel_NotExist);
        _safeRunTest("testTaskLabelAutoCleanup", testTaskLabelAutoCleanup);
        _safeRunTest("testRepeatingTaskWithLabel", testRepeatingTaskWithLabel);
        _safeRunTest("testMultipleLabelsOnSameObject", testMultipleLabelsOnSameObject);
        _safeRunTest("testShootCoreScenario", testShootCoreScenario);
    }

    /**
     * 测试 v1.3-1：addOrUpdateTask 基本功能
     */
    private function testAddOrUpdateTask_Basic():Void {
        trace("  测试 v1.3-1: addOrUpdateTask 基本功能");
        var wheel:EnhancedCooldownWheel = EnhancedCooldownWheel.I();
        wheel.reset();

        var obj:Object = {};
        var executed:Boolean = false;

        var taskId:Number = wheel.addOrUpdateTask(obj, "testLabel", function():Void {
            executed = true;
        }, 100, false, 0, null);

        // 验证 taskLabel 被创建
        assert(obj.taskLabel != undefined, "taskLabel 应被创建");
        assert(obj.taskLabel["testLabel"] == taskId, "taskLabel 应记录任务ID");
        assert(wheel.getActiveTaskCount() == 1, "应有1个活跃任务");

        // 执行任务
        for (var i:Number = 0; i < 5; i++) {
            wheel.tick();
        }

        assert(executed, "任务应被执行");
        assert(wheel.getActiveTaskCount() == 0, "任务完成后应被清理");
        assert(obj.taskLabel["testLabel"] == undefined, "taskLabel 应被自动清理");
    }

    /**
     * 测试 v1.3-2：addOrUpdateTask 替换旧任务
     */
    private function testAddOrUpdateTask_Replace():Void {
        trace("  测试 v1.3-2: addOrUpdateTask 替换旧任务");
        var wheel:EnhancedCooldownWheel = EnhancedCooldownWheel.I();
        wheel.reset();

        var obj:Object = {};
        var oldExecuted:Boolean = false;
        var newExecuted:Boolean = false;

        // 添加第一个任务
        var oldId:Number = wheel.addOrUpdateTask(obj, "replaceTest", function():Void {
            oldExecuted = true;
        }, 200, false, 0, null);

        // 添加同标签的新任务（应替换旧任务）
        var newId:Number = wheel.addOrUpdateTask(obj, "replaceTest", function():Void {
            newExecuted = true;
        }, 100, false, 0, null);

        assert(oldId != newId, "新旧任务ID应不同");
        assert(obj.taskLabel["replaceTest"] == newId, "taskLabel 应更新为新任务ID");
        assert(wheel.getActiveTaskCount() == 1, "应只有1个活跃任务（旧任务被移除）");

        // 执行足够帧数
        for (var i:Number = 0; i < 10; i++) {
            wheel.tick();
        }

        assert(!oldExecuted, "旧任务不应执行");
        assert(newExecuted, "新任务应执行");
    }

    /**
     * 测试 v1.3-3：removeTaskByLabel 基本功能
     */
    private function testRemoveTaskByLabel_Basic():Void {
        trace("  测试 v1.3-3: removeTaskByLabel 基本功能");
        var wheel:EnhancedCooldownWheel = EnhancedCooldownWheel.I();
        wheel.reset();

        var obj:Object = {};
        var executed:Boolean = false;

        wheel.addOrUpdateTask(obj, "removeTest", function():Void {
            executed = true;
        }, 200, false, 0, null);

        assert(wheel.getActiveTaskCount() == 1, "应有1个活跃任务");

        // 通过标签移除
        var result:Boolean = wheel.removeTaskByLabel(obj, "removeTest");
        assert(result == true, "移除应返回 true");
        assert(wheel.getActiveTaskCount() == 0, "移除后应无活跃任务");
        assert(obj.taskLabel["removeTest"] == undefined, "taskLabel 应被清理");

        // 执行任务
        for (var i:Number = 0; i < 10; i++) {
            wheel.tick();
        }

        assert(!executed, "被移除的任务不应执行");
    }

    /**
     * 测试 v1.3-4：removeTaskByLabel 任务不存在
     */
    private function testRemoveTaskByLabel_NotExist():Void {
        trace("  测试 v1.3-4: removeTaskByLabel 任务不存在");
        var wheel:EnhancedCooldownWheel = EnhancedCooldownWheel.I();
        wheel.reset();

        var obj:Object = {};

        // 无 taskLabel
        var result1:Boolean = wheel.removeTaskByLabel(obj, "notExist");
        assert(result1 == false, "无 taskLabel 时应返回 false");

        // 有 taskLabel 但无此标签
        obj.taskLabel = {};
        var result2:Boolean = wheel.removeTaskByLabel(obj, "notExist");
        assert(result2 == false, "标签不存在时应返回 false");

        // null 对象
        var result3:Boolean = wheel.removeTaskByLabel(null, "notExist");
        assert(result3 == false, "null 对象应返回 false");
    }

    /**
     * 测试 v1.3-5：任务完成后 taskLabel 自动清理
     */
    private function testTaskLabelAutoCleanup():Void {
        trace("  测试 v1.3-5: 任务完成后 taskLabel 自动清理");
        var wheel:EnhancedCooldownWheel = EnhancedCooldownWheel.I();
        wheel.reset();

        var obj:Object = {};
        var count:Number = 0;

        // 一次性任务
        wheel.addOrUpdateTask(obj, "onceTask", function():Void {
            count++;
        }, 50, false, 0, null);

        assert(obj.taskLabel["onceTask"] != undefined, "添加后 taskLabel 应存在");

        for (var i:Number = 0; i < 3; i++) {
            wheel.tick();
        }

        assert(count == 1, "任务应执行1次");
        assert(obj.taskLabel["onceTask"] == undefined, "完成后 taskLabel 应自动清理");
    }

    /**
     * 测试 v1.3-6：重复任务带标签
     */
    private function testRepeatingTaskWithLabel():Void {
        trace("  测试 v1.3-6: 重复任务带标签");
        var wheel:EnhancedCooldownWheel = EnhancedCooldownWheel.I();
        wheel.reset();

        var obj:Object = {};
        var count:Number = 0;

        // 重复3次的任务
        wheel.addOrUpdateTask(obj, "repeatTask", function():Void {
            count++;
        }, 100, true, 3, null);

        assert(obj.taskLabel["repeatTask"] != undefined, "添加后 taskLabel 应存在");

        // 执行足够帧数
        for (var i:Number = 0; i < 20; i++) {
            wheel.tick();
        }

        assert(count == 3, "任务应执行3次，实际: " + count);
        assert(obj.taskLabel["repeatTask"] == undefined, "完成后 taskLabel 应自动清理");
    }

    /**
     * 测试 v1.3-7：同一对象多个标签
     */
    private function testMultipleLabelsOnSameObject():Void {
        trace("  测试 v1.3-7: 同一对象多个标签");
        var wheel:EnhancedCooldownWheel = EnhancedCooldownWheel.I();
        wheel.reset();

        var obj:Object = {};
        var results:Array = [];

        wheel.addOrUpdateTask(obj, "labelA", function():Void {
            results.push("A");
        }, 50, false, 0, null);

        wheel.addOrUpdateTask(obj, "labelB", function():Void {
            results.push("B");
        }, 100, false, 0, null);

        wheel.addOrUpdateTask(obj, "labelC", function():Void {
            results.push("C");
        }, 150, false, 0, null);

        assert(wheel.getActiveTaskCount() == 3, "应有3个活跃任务");
        assert(obj.taskLabel["labelA"] != undefined, "labelA 应存在");
        assert(obj.taskLabel["labelB"] != undefined, "labelB 应存在");
        assert(obj.taskLabel["labelC"] != undefined, "labelC 应存在");

        // 移除 labelB
        wheel.removeTaskByLabel(obj, "labelB");
        assert(wheel.getActiveTaskCount() == 2, "移除后应有2个活跃任务");

        // 执行所有任务
        for (var i:Number = 0; i < 10; i++) {
            wheel.tick();
        }

        // AS2 没有 Array.indexOf，使用辅助函数
        var hasA:Boolean = arrayContains(results, "A");
        var hasB:Boolean = arrayContains(results, "B");
        var hasC:Boolean = arrayContains(results, "C");

        assert(results.length == 2, "应执行2个任务");
        assert(hasA, "labelA 应执行");
        assert(!hasB, "labelB 不应执行");
        assert(hasC, "labelC 应执行");
    }

    /** AS2 兼容的数组查找 */
    private function arrayContains(arr:Array, value:Object):Boolean {
        for (var i:Number = 0; i < arr.length; i++) {
            if (arr[i] == value) return true;
        }
        return false;
    }

    /**
     * 测试 v1.3-8：模拟 ShootCore 射击后摇场景
     */
    private function testShootCoreScenario():Void {
        trace("  测试 v1.3-8: 模拟 ShootCore 射击后摇场景");
        var wheel:EnhancedCooldownWheel = EnhancedCooldownWheel.I();
        wheel.reset();

        // 模拟自机对象
        var core:Object = {射击最大后摇中: true};

        // 模拟射击后摇任务（旧方式需要手动管理 taskLabel）
        // 新方式：直接使用 addOrUpdateTask
        wheel.addOrUpdateTask(core, "结束射击后摇", function(target:Object):Void {
            target.射击最大后摇中 = false;
        }, 300, false, 0, [core]);

        assert(core.射击最大后摇中 == true, "初始状态应为后摇中");

        // 模拟快速连射：在后摇任务执行前再次添加
        wheel.tick();
        wheel.tick();

        // 再次射击，应重置后摇计时
        wheel.addOrUpdateTask(core, "结束射击后摇", function(target:Object):Void {
            target.射击最大后摇中 = false;
        }, 300, false, 0, [core]);

        assert(wheel.getActiveTaskCount() == 1, "应只有1个后摇任务（旧任务被替换）");

        // 执行直到任务完成
        for (var i:Number = 0; i < 15; i++) {
            wheel.tick();
        }

        assert(core.射击最大后摇中 == false, "后摇应结束");
        assert(core.taskLabel["结束射击后摇"] == undefined, "taskLabel 应自动清理");
    }

    // ========== Ⅴ. v1.8 Never-Early 修复测试 ==========

    /**
     * 运行所有 v1.8 测试
     */
    public function runFixV18Tests():Void {
        trace("\n【v1.8 Never-Early 修复测试】");
        _safeRunTest("testNeverEarlyCeilBitOp_v1_8", testNeverEarlyCeilBitOp_v1_8);
    }

    /**
     * 测试 v1.8: 验证 ceiling bit-op 时间转换确保任务不会提前触发
     *
     * Never-Early 原则：ceil(ms / 每帧毫秒) 保证任务至少等够指定时间。
     * 修复前使用 Math.round 会导致非整数帧的请求提前触发。
     *
     * 验证点：
     *   - 50ms (@30FPS, 1.5帧) → 应为 2 帧（而非 round 的 2 帧，此例相同）
     *   - 34ms (@30FPS, 1.02帧) → 应为 2 帧（round 会得到 1 帧，提前触发！）
     *   - 67ms (@30FPS, 2.01帧) → 应为 3 帧（round 会得到 2 帧，提前触发！）
     *   - 100ms (@30FPS, 3.0帧) → 应为 3 帧（整数不变）
     *   - 33ms (@30FPS, 0.99帧) → 应为 1 帧（最小保障）
     */
    private function testNeverEarlyCeilBitOp_v1_8():Void {
        trace("  测试 v1.8: Never-Early ceiling bit-op");
        var wheel:EnhancedCooldownWheel = EnhancedCooldownWheel.I();
        wheel.reset();

        var msPerFrame:Number = wheel.每帧毫秒; // ≈33.33ms
        trace("  每帧毫秒 = " + msPerFrame);

        // 辅助函数：手动计算 ceiling bit-op 结果以验证
        // var _r = ms / 每帧毫秒; var _f = _r >> 0; result = (_f + (_r > _f)) || 1;

        // 测试用例集合: [inputMs, expectedFrames, description]
        var testCases:Array = [
            [50,  2, "50ms=1.5帧→ceil=2"],
            [34,  2, "34ms=1.02帧→ceil=2 (round会得1!)"],
            [67,  3, "67ms=2.01帧→ceil=3 (round会得2!)"],
            [100, 3, "100ms=3.0帧→ceil=3"],
            [33,  1, "33ms=0.99帧→保底=1"],
            [1,   1, "1ms=0.03帧→保底=1"],
            [66,  2, "66ms=1.98帧→ceil=2"],
            [127, 4, "127ms=3.81帧→ceil=4"]
        ];

        for (var i:Number = 0; i < testCases.length; i++) {
            var tc:Array = testCases[i];
            var inputMs:Number = tc[0];
            var expectedFrames:Number = tc[1];
            var desc:String = tc[2];

            // 使用与源码相同的 ceiling bit-op 公式验证
            var _r:Number = inputMs / msPerFrame;
            var _f:Number = _r >> 0;
            var actualFrames:Number = (_f + (_r > _f)) || 1;

            assert(actualFrames == expectedFrames,
                "Never-Early [" + desc + "]: expected " + expectedFrames + " frames, got " + actualFrames);
        }

        // 实际调度验证：34ms 的任务不应在 1 帧后触发
        var earlyFired:Boolean = false;
        var correctFired:Boolean = false;

        wheel.addTask(function():Void {
            correctFired = true;
        }, 34, 1);

        // 1 帧后不应触发（如果使用 round，会在这里触发）
        wheel.tick();
        assert(earlyFired == false && correctFired == false,
            "Never-Early: 34ms task should NOT fire after 1 tick");

        // 2 帧后应触发
        wheel.tick();
        assert(correctFired == true,
            "Never-Early: 34ms task should fire after 2 ticks (ceil guarantees no early fire)");

        trace("  Never-Early ceiling bit-op: 全部验证通过");
    }
}