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
        
        for (var i:Number = 0; i < 4; i++) {
            wheel.tick();
        }
        assert(results.length == 2, "两个延迟任务都应执行");
        assert(results.indexOf("task1") >= 0, "task1应执行");
        assert(results.indexOf("task2") >= 0, "task2应执行");
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
    
    /** 测试4：长延迟环绕 */
    private function testLongDelayWrapping():Void {
        trace("  测试4: 长延迟环绕测试");
        var wheel:EnhancedCooldownWheel = EnhancedCooldownWheel.I();
        wheel.reset();
        
        var executed:Boolean = false;
        wheel.addDelayedTask(125 * wheel.每帧毫秒, function():Void { executed = true; });
        
        for (var i:Number = 0; i < 6; i++) {
            wheel.tick();
            if (i < 4) assert(!executed, "长延迟任务不应过早执行");
        }
        assert(executed, "长延迟任务应正确环绕执行");
    }
    
    // -------------- 新增功能测试 --------------
    
    /** 测试5：重复任务 */
    private function testRepeatingTasks():Void {
        trace("  测试5: 重复任务测试");
        var wheel:EnhancedCooldownWheel = EnhancedCooldownWheel.I();
        wheel.reset();
        
        var counter:Number = 0;
        var taskId:Number = wheel.添加任务(function():Void { 
            counter++;
            trace("    重复任务执行第" + counter + "次");
        }, 100, 3); // 100ms间隔，重复3次
        
        trace("    添加重复3次的任务，间隔100ms...");
        
        // 执行足够的帧数
        for (var i:Number = 0; i < 10; i++) {
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
        wheel.移除任务(taskId);
        
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
        wheel.添加任务(function(a:Number, b:String, c:Boolean):Void { 
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
            wheel.移除任务(ids[l]);
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
        
        var taskId:Number = wheel.添加任务(callback, 100, 5, canvas);
        
        trace("    模拟渐隐任务，间隔100ms，重复5次...");
        
        for (var i:Number = 0; i < 15; i++) {
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
        wheel.添加任务(function():Void { results.push("repeat"); }, 80, 2);
        
        // 立即任务
        wheel.add(0, function():Void { results.push("immediate"); });
        
        // 长延迟任务
        wheel.addDelayedTask(300, function():Void { results.push("long"); });
        
        for (var i:Number = 0; i < 8; i++) {
            wheel.tick();
        }
        
        assert(results.length == 5, "混合任务执行总数应为5"); // once + repeat*2 + immediate + long
        assert(results.indexOf("immediate") >= 0, "立即任务应执行");
        assert(results.indexOf("once") >= 0, "一次性任务应执行");
        assert(results.indexOf("long") >= 0, "长延迟任务应执行");
        
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
            wheel.移除任务(ids[j]);
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
        
        // 无限重复任务（传入0或负数作为重复次数）
        var taskId:Number = wheel.添加任务(function():Void { 
            counter++;
            if (counter >= 10) {
                // 手动停止无限重复
                wheel.移除任务(taskId);
            }
        }, 50, 0); // 0表示无限重复
        
        for (var i:Number = 0; i < 20; i++) {
            wheel.tick();
        }
        
        assert(counter == 10, "无限重复任务应被手动停止在10次");
        assert(wheel.getActiveTaskCount() == 0, "停止后应无活跃任务");
    }
    
    /** 测试13：错误处理 */
    private function testErrorHandling():Void {
        trace("  测试13: 错误处理测试");
        var wheel:EnhancedCooldownWheel = EnhancedCooldownWheel.I();
        wheel.reset();
        
        var normalExecuted:Boolean = false;
        
        // 会抛出错误的任务
        wheel.addDelayedTask(50, function():Void {
            throw new Error("测试错误");
        });
        
        // 正常任务
        wheel.addDelayedTask(80, function():Void {
            normalExecuted = true;
        });
        
        // 执行任务
        for (var i:Number = 0; i < 5; i++) {
            wheel.tick();
        }
        
        assert(normalExecuted, "正常任务应在错误任务后继续执行");
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
                wheel.添加任务(function():Void {}, 80, 1);
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
        var dotId:Number = wheel.添加任务(function():Void {
            gameState.effects.push("dot_tick");
            trace("    持续伤害tick");
        }, 1000, 3);
        
        // 模拟游戏运行
        for (var i:Number = 0; i < 60; i++) {
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
        wheel.添加任务(function():Void { executed++; }, 100, 5);
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
                wheel.添加任务(dummyCb, 100, 3);
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
                wheel.移除任务(ids[j]);
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
                    ids.push(wheel.添加任务(dummyCb, 80, 2));
                } else {
                    wheel.add(i % 10, dummyCb);
                }
            }
            
            // 取消一些任务
            for (var j:Number = 0; j < 100; j++) {
                if (ids[j]) wheel.移除任务(ids[j]);
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
}