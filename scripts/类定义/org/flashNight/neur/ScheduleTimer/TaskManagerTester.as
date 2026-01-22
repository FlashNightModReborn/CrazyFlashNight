import org.flashNight.neur.ScheduleTimer.*;
import org.flashNight.neur.Server.*; 
import org.flashNight.neur.Event.*;
import org.flashNight.naki.DataStructures.*;
import org.flashNight.aven.Coordinator.*;

/**
 * TaskManagerTester.as
 * -----------------------------------------------------------------------------
 * 本测试类用于全面验证 TaskManager 类的各项功能，涵盖基本功能、边界情况以及混合场景的测试，
 * 同时输出详细的调试日志，帮助开发者精确定位任务调度存在的问题。
 *
 * 主要功能：
 *  1. 每个测试用例运行前独立构建新的调度器与 TaskManager，并重置当前帧数、断言和日志，
 *     避免测试间状态互相干扰。
 *  2. 利用闭包捕获测试对象引用（self），确保回调函数中可以正确获取 currentFrame 等成员变量。
 *  3. 对循环中使用闭包问题通过辅助函数 createCallbackForIndex 进行处理。
 *  4. 包含对添加单次任务、循环任务、更新任务、生命周期任务、任务删除、任务延迟、
 *     零/负间隔任务、重复次数为 0 或负数任务、任务ID唯一性、混合测试以及并发任务等场景的测试。
 *
 * 使用方法：
 *  直接调用 TaskManagerTester.runAllTests() 即可运行所有测试用例，每个测试用例均在一个全新的测试环境中执行，
 *  最后在控制台输出各项断言结果及调试日志。
 */

class org.flashNight.neur.ScheduleTimer.TaskManagerTester {
    // 外部任务调度器实例
    private var scheduleTimer:CerberusScheduler;
    // TaskManager 实例
    private var taskManager:TaskManager;
    // 当前帧率（与项目帧计时器一致）
    private var frameRate:Number = 30;
    // 当前帧数计数
    private var currentFrame:Number;
    // 额外日志数组（可记录重要调试信息）
    private var logs:Array;

    // =====================================================================
    // 静态测试统计（跨测试用例累积）
    // =====================================================================
    private static var testStats:Object = {passed: 0, failed: 0, errors: []};

    /**
     * 构造函数
     * ---------------------------------------------------------------------------
     * 初始化测试环境。为保证每个测试用例状态隔离，构造函数中调用 resetBeforeTest() 重置计时器、任务管理器
     * 及相关状态。
     */
    public function TaskManagerTester() {
        this.resetBeforeTest();
    }

    /**
     * resetBeforeTest
     * ---------------------------------------------------------------------------
     * 在每个测试用例运行前调用，重置当前帧、日志、任务调度器和 TaskManager 实例，
     * 从而确保测试环境隔离，避免多个测试间数据混淆。
     */
    private function resetBeforeTest():Void {
        this.currentFrame = 0;
        this.logs = [];
        // 初始化调度器
        this.scheduleTimer = new CerberusScheduler();
        var singleWheelSize:Number = 150;
        var multiLevelSecondsSize:Number = 60;
        var multiLevelMinutesSize:Number = 60;
        var precisionThreshold:Number = 0.1;
        this.scheduleTimer.initialize(singleWheelSize, multiLevelSecondsSize, multiLevelMinutesSize, this.frameRate, precisionThreshold);
        // 初始化 TaskManager 实例
        this.taskManager = new TaskManager(this.scheduleTimer, this.frameRate);
    }

    /**
     * simulateFrames
     * ---------------------------------------------------------------------------
     * 模拟 numFrames 帧的更新，每帧调用 TaskManager.updateFrame() 更新任务。
     * 默认静默执行，可传入 verbose=true 开启调试输出。
     *
     * @param numFrames 要模拟的帧数。
     * @param verbose   可选，是否每5帧输出调试信息。
     */
    private function simulateFrames(numFrames:Number, verbose:Boolean):Void {
        for (var i:Number = 0; i < numFrames; i++) {
            this.currentFrame++;
            this.taskManager.updateFrame();
            // verbose 模式下每 5 帧输出一次调试信息
            if (verbose && this.currentFrame % 5 == 0) {
                this.debugTaskManagerState();
            }
        }
    }

    /**
     * debugTaskManagerState
     * ---------------------------------------------------------------------------
     * 输出当前帧数以及 TaskManager 内部状态（正常调度任务和零帧任务的键列表）。
     * 利用反射方式获取私有属性，便于调试分析任务调度状态。
     */
    private function debugTaskManagerState():Void {
        trace("----- Debug Info at Frame " + this.currentFrame + " -----");
        var keysTaskTable:String = "";
        var taskTableObj:Object = this.taskManager["taskTable"];
        for (var key in taskTableObj) {
            keysTaskTable += key + " ";
        }
        trace("Task Table keys: " + keysTaskTable);
        
        var keysZeroFrame:String = "";
        var zeroFrameObj:Object = this.taskManager["zeroFrameTasks"];
        for (var key in zeroFrameObj) {
            keysZeroFrame += key + " ";
        }
        trace("ZeroFrame Tasks keys: " + keysZeroFrame);
        trace("---------------------------------------------");
    }

    /**
     * assert
     * ---------------------------------------------------------------------------
     * 断言工具：条件为假时抛出异常，由 _safeRunTest 捕获并统计。
     *
     * @param condition 断言条件，true 表示通过
     * @param message 断言失败时的错误提示
     */
    private function assert(condition:Boolean, message:String):Void {
        if (!condition) {
            throw new Error("断言失败 (帧 " + this.currentFrame + "): " + message);
        }
    }

    /**
     * _safeRunTest
     * ---------------------------------------------------------------------------
     * 安全执行单个测试，捕获异常并记录统计信息。
     * 一个测试失败不会影响其他测试继续执行。
     *
     * @param testName 测试名称
     * @param testFunction 测试函数
     */
    private static function _safeRunTest(testName:String, tester:TaskManagerTester):Void {
        try {
            tester[testName]();
            trace("  [PASS] " + testName);
            testStats.passed++;
        } catch (e:Error) {
            trace("  [FAIL] " + testName + " - " + e.toString());
            testStats.failed++;
            testStats.errors.push({test: testName, error: e.toString()});
        }
    }

    /**
     * _printTestResults
     * ---------------------------------------------------------------------------
     * 输出测试结果汇总：通过/失败数量及失败详情。
     */
    private static function _printTestResults():Void {
        trace("\n=====================================================");
        trace("【测试结果汇总】");
        trace("  通过: " + testStats.passed + " 个");
        trace("  失败: " + testStats.failed + " 个");
        trace("  总计: " + (testStats.passed + testStats.failed) + " 个");

        if (testStats.failed > 0) {
            trace("\n【失败详情】");
            for (var i:Number = 0; i < testStats.errors.length; i++) {
                var err:Object = testStats.errors[i];
                trace("  " + (i + 1) + ". " + err.test + ": " + err.error);
            }
            trace("\n[!] 存在 " + testStats.failed + " 个测试失败，请检查上述详情");
        } else {
            trace("\n[OK] 所有测试通过！");
        }
        trace("=====================================================");
    }

    /**
     * _resetStats
     * ---------------------------------------------------------------------------
     * 重置测试统计，用于开始新一轮测试。
     */
    private static function _resetStats():Void {
        testStats = {passed: 0, failed: 0, errors: []};
    }

    // ----------------------------
    // 测试用例
    // ----------------------------

    /**
     * testAddSingleTask
     * ---------------------------------------------------------------------------
     * 测试添加单次任务：
     *  - 延迟 100ms 后执行，任务执行后应被移除（locateTask 返回 null）。
     */
    public function testAddSingleTask():Void {
        var self:TaskManagerTester = this;
        trace("Running testAddSingleTask...");
        var executed:Boolean = false;
        var taskID:String = this.taskManager.addSingleTask(
            function():Void {
                executed = true;
                trace("Single task executed at frame " + self.currentFrame);
            },
            100
        );
        // 模拟 10 帧（足以覆盖 100ms 延迟）
        simulateFrames(10);
        assert(executed, "Single task should execute after specified delay");
        assert(this.taskManager.locateTask(taskID) == null, "Single task should be removed after execution");
    }

    /**
     * testAddLoopTask
     * ---------------------------------------------------------------------------
     * 测试添加循环任务：
     *  - 延迟 50ms 执行，每次任务执行后累计计数，多帧模拟后任务应执行多次。
     */
    public function testAddLoopTask():Void {
        var self:TaskManagerTester = this;
        trace("Running testAddLoopTask...");
        var count:Number = 0;
        var taskID:String = this.taskManager.addLoopTask(
            function():Void {
                count++;
                trace("Loop task executed, count=" + count + " at frame " + self.currentFrame);
            },
            50
        );
        simulateFrames(20);
        assert(count > 1, "Loop task should execute multiple times, actual count=" + count);
        // 移除循环任务，防止对后续测试产生影响
        this.taskManager.removeTask(taskID);
    }

    /**
     * testAddOrUpdateTask
     * ---------------------------------------------------------------------------
     * 测试添加或更新任务：
     *  - 首次添加时，任务应能执行且任务ID存入对象属性；
     *  - 更新任务后应采用新的回调执行。
     */
    public function testAddOrUpdateTask():Void {
        var self:TaskManagerTester = this;
        trace("Running testAddOrUpdateTask...");
        var obj:Object = {};
        var executed:Boolean = false;
        var taskID:String = this.taskManager.addOrUpdateTask(obj, "testLabel",
            function():Void {
                executed = true;
                trace("First callback executed at frame " + self.currentFrame);
            },
            100
        );
        simulateFrames(10);
        assert(executed, "AddOrUpdateTask should execute the task (first callback)");
        assert(obj.taskLabel["testLabel"] == taskID, "Task ID should be stored in object's taskLabel");

        // 更新任务：新回调设置
        var newExecuted:Boolean = false;
        this.taskManager.addOrUpdateTask(obj, "testLabel",
            function():Void {
                newExecuted = true;
                trace("Updated callback executed at frame " + self.currentFrame);
            },
            50
        );
        simulateFrames(10);
        assert(newExecuted, "Updated task should execute with new action");
    }

    /**
     * testAddLifecycleTask
     * ---------------------------------------------------------------------------
     * 测试添加生命周期任务：
     *  - 任务为无限循环任务，会多次执行；
     *  - 模拟对象卸载后任务自动清除，且对象内任务标签被移除。
     */
    public function testAddLifecycleTask():Void {
        var self:TaskManagerTester = this;
        trace("Running testAddLifecycleTask...");
        var obj:Object = {};
        var count:Number = 0;
        var taskID:String = this.taskManager.addLifecycleTask(obj, "lifecycleLabel",
            function():Void {
                count++;
                trace("Lifecycle task executed, count=" + count + " at frame " + self.currentFrame);
            },
            50
        );
        simulateFrames(20);
        assert(count > 1, "Lifecycle task should execute multiple times, actual count=" + count);
        // 模拟对象卸载
        if (typeof obj.onUnload == "function") {
            obj.onUnload();
        } else {
            trace("Warning: obj.onUnload is not defined, simulating unload manually.");
            obj.onUnload = function():Void {};
            obj.onUnload();
        }
        simulateFrames(1);
        assert(this.taskManager.locateTask(taskID) == null, "Lifecycle task should be removed after unload");
        assert(obj.taskLabel["lifecycleLabel"] == undefined, "Task label should be cleared on unload");
    }

    /**
     * testRemoveTask
     * ---------------------------------------------------------------------------
     * 测试移除任务：
     *  - 添加单次任务后立即调用 removeTask，
     *  - 模拟多帧后任务不应执行。
     */
    public function testRemoveTask():Void {
        var self:TaskManagerTester = this;
        trace("Running testRemoveTask...");
        var executed:Boolean = false;
        var taskID:String = this.taskManager.addSingleTask(
            function():Void {
                executed = true;
                trace("This task should not execute. Frame: " + self.currentFrame);
            },
            100
        );
        // 立即移除任务
        this.taskManager.removeTask(taskID);
        simulateFrames(10);
        assert(!executed, "Removed task should not execute");
    }

    /**
     * testLocateTask
     * ---------------------------------------------------------------------------
     * 测试任务定位：
     *  - 在任务执行前能通过 locateTask 查到任务，
     *  - 任务执行后则查不到。
     */
    public function testLocateTask():Void {
        var self:TaskManagerTester = this;
        trace("Running testLocateTask...");
        var taskID:String = this.taskManager.addSingleTask(
            function():Void {
                trace("LocateTask: Single task executed at frame " + self.currentFrame);
            },
            100
        );
        var task:Task = this.taskManager.locateTask(taskID);
        assert(task != null, "Task should be locatable before execution");
        simulateFrames(10);
        assert(this.taskManager.locateTask(taskID) == null, "Task should not be locatable after execution");
    }

    /**
     * testDelayTask
     * ---------------------------------------------------------------------------
     * 测试任务延迟：
     *  - 为单次任务增加额外 50ms 延迟（总延迟 150ms），
     *  - 在延迟期间任务不执行，延迟到位后任务执行。
     */
    public function testDelayTask():Void {
        var self:TaskManagerTester = this;
        trace("Running testDelayTask...");
        var executed:Boolean = false;
        var taskID:String = this.taskManager.addSingleTask(
            function():Void {
                executed = true;
                trace("Delayed task executed at frame " + self.currentFrame);
            },
            100
        );
        // 为任务增加 50ms 延迟
        this.taskManager.delayTask(taskID, 50);
        simulateFrames(3);
        trace("After 3 frames, delay task executed? " + executed);
        assert(!executed, "Task should not execute before total delay (150ms)");
        simulateFrames(2);
        trace("After additional 2 frames, delay task executed? " + executed);
        assert(executed, "Task should execute after additional delay");
    }

    /**
     * testDelayTaskNonNumeric
     * ---------------------------------------------------------------------------
     * 测试 delayTask 非数字参数：
     *  - 当 delayTime 为 true 时，pendingFrames 应设置为 Infinity（无限延迟），
     *    此时任务不会执行。
     */
    public function testDelayTaskNonNumeric():Void {
        var self:TaskManagerTester = this;
        trace("Running testDelayTaskNonNumeric...");
        var executed:Boolean = false;
        var taskID:String = this.taskManager.addSingleTask(
            function():Void {
                executed = true;
                trace("Non-numeric delay task executed at frame " + self.currentFrame + " (BUG!)");
            },
            100
        );
        
        // 检查 AS2 中布尔值的数字转换行为
        trace("DEBUG: isNaN(true) = " + isNaN(true));
        trace("DEBUG: typeof(true) = " + typeof(true));
        trace("DEBUG: Number(true) = " + Number(true));
        
        // 使用非数字参数 true 进行延迟
        this.taskManager.delayTask(taskID, true);
        simulateFrames(10);
        
        trace("Task executed after delay(true): " + executed + " at frame " + this.currentFrame);
        assert(!executed, "Task with non-numeric delay (true) should not execute");
        
        // 通过反射检查内部 pendingFrames（仅供调试）
        var taskObj:Task = this.taskManager.locateTask(taskID);
        if (taskObj != null) {
            trace("Non-numeric delay task pendingFrames: " + taskObj.pendingFrames);
            assert(taskObj.pendingFrames == Infinity, "PendingFrames should be Infinity for non-numeric delay true");
        } else {
            trace("Task not found - may have been executed and removed");
        }
    }

    /**
     * testZeroIntervalTask
     * ---------------------------------------------------------------------------
     * 测试间隔为 0 的任务：
     *  - 应立即执行，且返回的任务ID为 null。
     */
    public function testZeroIntervalTask():Void {
        var self:TaskManagerTester = this;
        trace("Running testZeroIntervalTask...");
        var executed:Boolean = false;
        var taskID:String = this.taskManager.addSingleTask(
            function():Void {
                executed = true;
                trace("Zero interval task executed immediately at frame " + self.currentFrame);
            },
            0
        );
        assert(executed, "Task with zero interval should execute immediately");
        assert(taskID == null, "Zero interval task should return null ID");
    }

    /**
     * testNegativeIntervalTask
     * ---------------------------------------------------------------------------
     * 测试负间隔任务：
     *  - 负间隔同样应立即执行，且返回的任务ID为 null。
     */
    public function testNegativeIntervalTask():Void {
        var self:TaskManagerTester = this;
        trace("Running testNegativeIntervalTask...");
        var executed:Boolean = false;
        var taskID:String = this.taskManager.addSingleTask(
            function():Void {
                executed = true;
                trace("Negative interval task executed immediately at frame " + self.currentFrame);
            },
            -10
        );
        assert(executed, "Task with negative interval should execute immediately");
        assert(taskID == null, "Negative interval task should return null ID");
    }

    /**
     * testZeroRepeatCount
     * ---------------------------------------------------------------------------
     * 测试重复次数为 0 的任务：
     *  - 任务预期只执行一次（即使 repeatCount 为 0）。
     */
    public function testZeroRepeatCount():Void {
        var self:TaskManagerTester = this;
        trace("Running testZeroRepeatCount...");
        var count:Number = 0;
        var taskID:String = this.taskManager.addTask(
            function():Void {
                count++;
                trace("Zero repeat count task executed, count=" + count + " at frame " + self.currentFrame);
            },
            50,
            0
        );
        simulateFrames(10);
        trace("TestZeroRepeatCount: final count = " + count);
        assert(count == 1, "Task with zero repeat count is expected to execute once, actual count=" + count);
    }

    /**
     * testNegativeRepeatCount
     * ---------------------------------------------------------------------------
     * 测试重复次数为负数的任务：
     *  - 任务同样预期只执行一次（即使 repeatCount 为负）。
     */
    public function testNegativeRepeatCount():Void {
        var self:TaskManagerTester = this;
        trace("Running testNegativeRepeatCount...");
        var count:Number = 0;
        var taskID:String = this.taskManager.addTask(
            function():Void {
                count++;
                trace("Negative repeat count task executed, count=" + count + " at frame " + self.currentFrame);
            },
            50,
            -5
        );
        simulateFrames(10);
        trace("TestNegativeRepeatCount: final count = " + count);
        assert(count == 1, "Task with negative repeat count is expected to execute once, actual count=" + count);
    }

    /**
     * testTaskIDUniqueness
     * ---------------------------------------------------------------------------
     * 测试任务 ID 的唯一性：
     *  - 多次添加任务应返回不同的任务ID。
     */
    public function testTaskIDUniqueness():Void {
        trace("Running testTaskIDUniqueness...");
        var taskID1:String = this.taskManager.addSingleTask(function():Void{}, 100);
        var taskID2:String = this.taskManager.addSingleTask(function():Void{}, 100);
        trace("Task IDs: " + taskID1 + ", " + taskID2);
        assert(taskID1 != taskID2, "Task IDs should be unique, got: " + taskID1 + " and " + taskID2);
    }

    /**
     * testMixedScenarios
     * ---------------------------------------------------------------------------
     * 混合测试：
     *  - 同时添加单次任务、循环任务、生命周期任务；
     *  - 模拟一定帧数后验证各任务的执行情况；
     *  - 移除循环任务后验证其停止执行；
     *  - 延迟生命周期任务后检查任务执行是否暂停（允许取整规则导致的微小偏差）；
     *  - 模拟对象卸载后验证生命周期任务被清除。
     */
    public function testMixedScenarios():Void {
        var self:TaskManagerTester = this;
        trace("Running testMixedScenarios...");
        var singleExecuted:Boolean = false;
        var loopCount:Number = 0;
        var lifecycleCount:Number = 0;
        var obj:Object = {};

        // 添加单次任务
        var singleTaskID:String = this.taskManager.addSingleTask(
            function():Void {
                singleExecuted = true;
                trace("Mixed scenario: Single task executed at frame " + self.currentFrame);
            },
            100
        );

        // 添加循环任务
        var loopTaskID:String = this.taskManager.addLoopTask(
            function():Void {
                loopCount++;
                trace("Mixed scenario: Loop task executed, count=" + loopCount + " at frame " + self.currentFrame);
            },
            50
        );

        // 添加生命周期任务
        var lifecycleTaskID:String = this.taskManager.addLifecycleTask(obj, "mixedLabel",
            function():Void {
                lifecycleCount++;
                trace("Mixed scenario: Lifecycle task executed, count=" + lifecycleCount + " at frame " + self.currentFrame);
            },
            50
        );

        simulateFrames(20);
        trace("Mixed scenario: After 20 frames, singleExecuted=" + singleExecuted + ", loopCount=" + loopCount + ", lifecycleCount=" + lifecycleCount);
        assert(singleExecuted, "Single task should execute once");
        assert(loopCount > 1, "Loop task should execute multiple times, actual count=" + loopCount);
        assert(lifecycleCount > 1, "Lifecycle task should execute multiple times, actual count=" + lifecycleCount);

        // 移除循环任务后
        this.taskManager.removeTask(loopTaskID);
        var prevLoopCount:Number = loopCount;
        trace("Mixed scenario: Removed loop task at frame " + this.currentFrame + ", prevLoopCount=" + prevLoopCount);
        simulateFrames(10);
        trace("Mixed scenario: After additional 10 frames, loopCount=" + loopCount);
        assert(loopCount == prevLoopCount, "Loop task should stop after removal, expected " + prevLoopCount + ", got " + loopCount);

        // 对生命周期任务增加延迟（此处延迟参数若原来用 Infinity，可替换为一个足够大的数）
        this.taskManager.delayTask(lifecycleTaskID, 100);
        var prevLifecycleCount:Number = lifecycleCount;
        trace("Mixed scenario: Delayed lifecycle task at frame " + this.currentFrame + ", prevLifecycleCount=" + prevLifecycleCount);
        simulateFrames(5);
        trace("Mixed scenario: After delay, lifecycleCount=" + lifecycleCount);

        // 考虑到帧数转换及调度可能存在 1 帧的偏差，允许最多额外执行 1 次
        var tolerance:Number = 1;
        assert((lifecycleCount - prevLifecycleCount) <= tolerance, 
            "Lifecycle task should be paused during delay, expected increase <= " + tolerance +
            " count(s), got " + (lifecycleCount - prevLifecycleCount));

        // 模拟对象卸载
        if (typeof obj.onUnload == "function") {
            obj.onUnload();
        } else {
            trace("Mixed scenario: obj.onUnload not defined, simulating unload manually.");
            obj.onUnload = function():Void {};
            obj.onUnload();
        }
        simulateFrames(1);
        assert(this.taskManager.locateTask(lifecycleTaskID) == null, "Lifecycle task should be removed after unload");
    }


    /**
     * createCallbackForIndex
     * ---------------------------------------------------------------------------
     * 辅助函数，用于在循环中为每个并发任务生成独立的回调函数，确保闭包中 index 不被覆盖。
     *
     * @param index 当前任务索引
     * @param execCounts 数组，用于记录各任务的执行次数
     * @return 返回闭包回调函数
     */
    private function createCallbackForIndex(index:Number, execCounts:Array):Function {
        var self:TaskManagerTester = this;
        return function():Void {
            execCounts[index]++;
            trace("Concurrent task " + index + " executed, count=" + execCounts[index] + " at frame " + self.currentFrame);
        };
    }

    /**
     * testConcurrentTasks
     * ---------------------------------------------------------------------------
     * 测试并发添加多个任务：
     *  - 同时添加多个任务，各自应有唯一的任务ID；
     *  - 模拟后验证每个任务都能按各自延迟执行。
     */
    public function testConcurrentTasks():Void {
        trace("Running testConcurrentTasks...");
        var execCounts:Array = [];
        for (var i:Number = 0; i < 5; i++) {
            execCounts[i] = 0;
            // 为每个任务设置不同延迟
            var delay:Number = 50 * (i + 1);
            var callback:Function = createCallbackForIndex(i, execCounts);
            this.taskManager.addLoopTask(callback, delay);
        }
        simulateFrames(30);
        // 检查每个任务均至少执行过一次
        for (var j:Number = 0; j < 5; j++) {
            assert(execCounts[j] > 0, "Concurrent task " + j + " should execute at least once, actual count=" + execCounts[j]);
        }
    }

    // ----------------------------
    // 运行所有测试用例（静态方法）
    // ----------------------------

    /**
     * testRaceConditionBug
     * ---------------------------------------------------------------------------
     * 测试竞态条件缺陷（对应 TaskManager.as 第82-94行注释中的问题）：
     *  - 任务在回调中调用 removeTask() 删除自己
     *  - 但 updateFrame() 不知情，继续执行重调度逻辑
     *  - 导致已删除的"僵尸任务"被重新添加回调度器
     */
    public function testRaceConditionBug():Void {
        var self:TaskManagerTester = this;
        trace("Running testRaceConditionBug...");
        var executionCount:Number = 0;
        var taskID:String;
        
        // 创建一个会在回调中删除自己的循环任务
        taskID = this.taskManager.addLoopTask(
            function():Void {
                executionCount++;
                trace("Race condition task executed, count=" + executionCount + " at frame " + self.currentFrame);
                
                if (executionCount == 2) {
                    trace("Task removing itself at execution #" + executionCount);
                    trace("Task exists before removal: " + (self.taskManager.locateTask(taskID) != null));
                    self.taskManager.removeTask(taskID);
                    trace("Task exists after removal: " + (self.taskManager.locateTask(taskID) != null));
                    trace("Task removal completed");
                }
            },
            50 // 每50ms执行一次
        );
        
        trace("Initial task ID: " + taskID);
        
        // 运行足够多的帧让任务执行多次
        simulateFrames(25);
        
        // 验证任务被删除后的状态
        var taskAfterRemoval:Task = this.taskManager.locateTask(taskID);
        trace("Task location after self-removal: " + (taskAfterRemoval != null ? "FOUND (POTENTIAL BUG!)" : "null (correct)"));
        assert(taskAfterRemoval == null, "Task should be null after self-removal, but found: " + taskAfterRemoval);
        
        // 继续运行更多帧，检查是否有"僵尸任务"重新出现
        var countBeforeMoreFrames:Number = executionCount;
        trace("Execution count before additional frames: " + countBeforeMoreFrames);
        simulateFrames(15);
        trace("Execution count after additional frames: " + executionCount);
        
        // 即使测试通过，也要警告潜在风险
        if (executionCount == countBeforeMoreFrames) {
            trace("WARNING: Race condition test passed, but the risk still exists in the code!");
            trace("The bug may manifest under different timing or load conditions.");
        }
        
        assert(executionCount == countBeforeMoreFrames, 
            "Zombie task detected! Expected count=" + countBeforeMoreFrames + ", actual=" + executionCount);
    }

    /**
     * testAS2TypeCheckingIssue
     * ---------------------------------------------------------------------------
     * 专门测试 AS2 中 isNaN() 对布尔值的错误处理
     * 验证 delayTask 中的类型检查逻辑问题
     */
    public function testAS2TypeCheckingIssue():Void {
        trace("Running testAS2TypeCheckingIssue...");
        trace("=== AS2 Type Checking Behavior Analysis ===");
        
        // 测试各种值在 isNaN() 下的行为
        var testValues:Array = [true, false, "string", null, undefined, 0, 1, NaN];
        for (var i:Number = 0; i < testValues.length; i++) {
            var val = testValues[i];
            trace("Value: " + val + " (type: " + typeof(val) + ")");
            trace("  isNaN(val): " + isNaN(val));
            trace("  Number(val): " + Number(val));
            trace("  typeof(val) != 'number': " + (typeof(val) != "number"));
            trace("  ---");
        }
        
        trace("=== Bug Demonstration ===");
        trace("delayTask expects non-numeric values to set infinite delay");
        trace("But isNaN(true) = " + isNaN(true) + " (should be true for infinite delay)");
        trace("Correct check: typeof(true) != 'number' = " + (typeof(true) != "number"));
        
        // 实际测试 delayTask 的行为
        var self:TaskManagerTester = this;
        var executed:Boolean = false;
        var taskID:String = this.taskManager.addSingleTask(
            function():Void {
                executed = true;
                trace("Task executed due to AS2 type checking bug!");
            },
            50
        );
        
        trace("Applying delay with boolean true...");
        this.taskManager.delayTask(taskID, true);
        
        // 检查任务状态
        var task:Task = this.taskManager.locateTask(taskID);
        if (task) {
            trace("Task pendingFrames after delay(true): " + task.pendingFrames);
            if (task.pendingFrames == Infinity) {
                trace("Correct: Task properly delayed to infinity");
            } else {
                trace("BUG: Task pendingFrames is not infinity, will execute soon!");
            }
        }
        
        simulateFrames(5);
        if (executed) {
            trace("CONFIRMED BUG: Task executed despite delay(true)");
        } else {
            trace("Task correctly delayed");
        }
    }

    /**
     * testLifecycleTaskIDReuseBug
     * ---------------------------------------------------------------------------
     * 测试生命周期任务ID复用缺陷（对应 TaskManager.as 第323-334行注释中的问题）：
     *  - addLifecycleTask 后手动 removeTask
     *  - obj.taskLabel[labelName] 不会被清除
     *  - 再次调用 addLifecycleTask 复用相同taskID，形成"幽灵任务"
     */
    public function testLifecycleTaskIDReuseBug():Void {
        var self:TaskManagerTester = this;
        trace("Running testLifecycleTaskIDReuseBug...");
        var obj:Object = {};
        var firstCallCount:Number = 0;
        var secondCallCount:Number = 0;
        
        // 第一次添加生命周期任务
        var firstTaskID:String = this.taskManager.addLifecycleTask(obj, "testLabel",
            function():Void {
                firstCallCount++;
                trace("First lifecycle task executed, count=" + firstCallCount + " at frame " + self.currentFrame);
            },
            50
        );
        
        trace("First task ID: " + firstTaskID);
        trace("obj.taskLabel['testLabel']: " + obj.taskLabel["testLabel"]);
        
        // 让任务执行几次
        simulateFrames(10);
        trace("First task execution count after 10 frames: " + firstCallCount);
        
        // 手动删除任务（模拟外部代码的误用）
        this.taskManager.removeTask(firstTaskID);
        trace("Manually removed first task");
        
        // 检查任务是否被删除
        var taskAfterRemoval:Task = this.taskManager.locateTask(firstTaskID);
        assert(taskAfterRemoval == null, "First task should be removed");
        
        // 关键检查：obj.taskLabel 是否仍然保留旧的taskID
        trace("obj.taskLabel['testLabel'] after manual removal: " + obj.taskLabel["testLabel"]);
        
        // 再次添加相同label的生命周期任务
        var secondTaskID:String = this.taskManager.addLifecycleTask(obj, "testLabel",
            function():Void {
                secondCallCount++;
                trace("Second lifecycle task executed, count=" + secondCallCount + " at frame " + self.currentFrame);
            },
            50
        );
        
        trace("Second task ID: " + secondTaskID);
        trace("Task ID reuse detected: " + (firstTaskID == secondTaskID ? "YES (BUG!)" : "NO (correct)"));
        
        // 验证是否复用了相同的taskID（这是bug的症状）
        assert(firstTaskID != secondTaskID, 
            "Task ID should not be reused! First ID: " + firstTaskID + ", Second ID: " + secondTaskID);
        
        // 运行更多帧，检查第二个任务是否正常工作
        var countBefore:Number = secondCallCount;
        simulateFrames(10);
        trace("Second task execution count: " + secondCallCount + " (should be > " + countBefore + ")");
        assert(secondCallCount > countBefore, 
            "Second task should execute normally, expected count > " + countBefore + ", got " + secondCallCount);
    }

    /**
     * testTaskIDCounterConsistency
     * ---------------------------------------------------------------------------
     * 测试任务ID计数器一致性：
     *  - 验证即使在复杂操作后，taskIdCounter 仍然单调递增
     *  - 这个测试有助于发现ID生成器的异常状态
     */
    public function testTaskIDCounterConsistency():Void {
        var self:TaskManagerTester = this;
        trace("Running testTaskIDCounterConsistency...");
        
        var taskIDs:Array = [];
        var obj:Object = {};
        
        // 添加多种类型的任务并记录ID
        taskIDs.push(this.taskManager.addSingleTask(function():Void{}, 100));
        taskIDs.push(this.taskManager.addLoopTask(function():Void{}, 50));
        taskIDs.push(this.taskManager.addLifecycleTask(obj, "label1", function():Void{}, 75));
        
        // 删除某些任务
        this.taskManager.removeTask(taskIDs[1]);
        
        // 再添加更多任务
        taskIDs.push(this.taskManager.addLifecycleTask(obj, "label2", function():Void{}, 60));
        taskIDs.push(this.taskManager.addSingleTask(function():Void{}, 120));
        
        trace("Generated task IDs: " + taskIDs.join(", "));
        
        // 验证所有ID都是唯一的且递增的
        for (var i:Number = 0; i < taskIDs.length; i++) {
            if (taskIDs[i] == null) continue; // 跳过立即执行的任务
            for (var j:Number = i + 1; j < taskIDs.length; j++) {
                if (taskIDs[j] == null) continue;
                assert(taskIDs[i] != taskIDs[j], 
                    "Task IDs should be unique: " + taskIDs[i] + " vs " + taskIDs[j] + " at indices " + i + ", " + j);
                assert(Number(taskIDs[i]) < Number(taskIDs[j]), 
                    "Task IDs should be monotonically increasing: " + taskIDs[i] + " should be < " + taskIDs[j]);
            }
        }
    }

    /**
     * runAllTests
     * ---------------------------------------------------------------------------
     * 运行所有测试用例，每个测试用例在独立的测试环境中执行，
     * 分组显示核心功能测试和已知限制测试，自动统计并输出汇总结果。
     */
    public static function runAllTests():Void {
        trace("=====================================================");
        trace("【TaskManager 完整测试套件】");
        trace("=====================================================");

        _resetStats();

        // ==================== 第一组：核心功能测试（应全部通过）====================
        trace("\n--- 核心功能测试 (应全部通过) ---");
        var coreTests:Array = [
            "testAddSingleTask", "testAddLoopTask", "testAddOrUpdateTask",
            "testAddLifecycleTask", "testRemoveTask", "testLocateTask",
            "testDelayTask", "testZeroIntervalTask",
            "testNegativeIntervalTask", "testZeroRepeatCount", "testNegativeRepeatCount",
            "testTaskIDUniqueness", "testMixedScenarios", "testConcurrentTasks",
            "testTaskIDCounterConsistency",
            // v1.1 修复验证测试
            "testZombieTaskFix_v1_1", "testRescheduleNodeReferenceFix_v1_1", "testNodePoolReuse_v1_1",
            // v1.3 修复验证测试
            "testGhostIDFix_v1_3", "testZeroDelayBoundaryFix_v1_3", "testArrayReuseFix_v1_3", "testFramesPerMsRename_v1_3",
            // v1.3 修复后，原先失败的测试现在应该通过
            "testLifecycleTaskIDReuseBug"
        ];

        for (var i:Number = 0; i < coreTests.length; i++) {
            var tester:TaskManagerTester = new TaskManagerTester();
            _safeRunTest(coreTests[i], tester);
        }

        var coreStats:Object = {passed: testStats.passed, failed: testStats.failed};

        // ==================== 第二组：已知限制测试（部分预期失败）====================
        trace("\n--- 已知限制/Bug复现测试 (部分预期失败) ---");
        var knownIssueTests:Array = [
            "testDelayTaskNonNumeric",      // AS2 isNaN(true)=false 类型转换问题
            "testAS2TypeCheckingIssue",     // AS2 类型检查行为分析
            "testRaceConditionBug"          // 竞态条件（v1.1已修复，此测试应通过）
            // testLifecycleTaskIDReuseBug 已移至核心测试（v1.3 修复后应通过）
        ];

        for (var j:Number = 0; j < knownIssueTests.length; j++) {
            var tester2:TaskManagerTester = new TaskManagerTester();
            _safeRunTest(knownIssueTests[j], tester2);
        }

        // 输出分组汇总
        _printTestResultsGrouped(coreStats, coreTests.length, knownIssueTests.length);
    }

    /**
     * _printTestResultsGrouped
     * ---------------------------------------------------------------------------
     * 分组输出测试结果汇总。
     */
    private static function _printTestResultsGrouped(coreStats:Object, coreCount:Number, knownCount:Number):Void {
        var knownPassed:Number = testStats.passed - coreStats.passed;
        var knownFailed:Number = testStats.failed - coreStats.failed;

        trace("\n=====================================================");
        trace("【测试结果汇总】");
        trace("-----------------------------------------------------");
        trace("  核心功能测试: " + coreStats.passed + "/" + coreCount + " 通过" +
              (coreStats.failed > 0 ? " [!] " + coreStats.failed + " 个失败" : " [OK]"));
        trace("  已知限制测试: " + knownPassed + "/" + knownCount + " 通过" +
              (knownFailed > 0 ? " (预期部分失败)" : ""));
        trace("-----------------------------------------------------");
        trace("  总计: " + testStats.passed + "/" + (coreCount + knownCount) + " 通过");

        if (coreStats.failed > 0) {
            trace("\n【核心功能失败详情】（需要修复！）");
            for (var i:Number = 0; i < testStats.errors.length; i++) {
                var err:Object = testStats.errors[i];
                // 检查是否是核心测试的失败
                var isCore:Boolean = true;
                if (err.test == "testDelayTaskNonNumeric" ||
                    err.test == "testAS2TypeCheckingIssue" ||
                    err.test == "testRaceConditionBug") {
                    isCore = false;
                }
                if (isCore) {
                    trace("  - " + err.test + ": " + err.error);
                }
            }
        }

        if (knownFailed > 0) {
            trace("\n【已知限制失败详情】（预期行为，无需修复）");
            for (var j:Number = 0; j < testStats.errors.length; j++) {
                var err2:Object = testStats.errors[j];
                if (err2.test == "testDelayTaskNonNumeric" ||
                    err2.test == "testAS2TypeCheckingIssue" ||
                    err2.test == "testRaceConditionBug") {
                    trace("  - " + err2.test + ": " + err2.error);
                }
            }
        }

        trace("=====================================================");
        if (coreStats.failed == 0) {
            trace("[OK] 核心功能测试全部通过！");
        } else {
            trace("[!] 核心功能存在 " + coreStats.failed + " 个失败，请检查！");
        }
    }

    /**
     * runBugTests
     * ---------------------------------------------------------------------------
     * 运行已知限制/Bug复现测试（这些测试预期会失败，用于记录已知问题）
     *  - testDelayTaskNonNumeric: AS2 isNaN(true)=false 的类型转换问题
     *  - testAS2TypeCheckingIssue: AS2 类型检查行为分析
     *  - testRaceConditionBug: 竞态条件潜在风险（已在v1.1修复，现应通过）
     *
     * 【v1.3 更新】testLifecycleTaskIDReuseBug 已修复，移至核心测试
     */
    public static function runBugTests():Void {
        trace("=====================================================");
        trace("【已知限制/Bug复现测试】（部分测试预期失败）");
        trace("=====================================================");

        _resetStats();

        var bugTests:Array = [
            "testDelayTaskNonNumeric",      // AS2 isNaN() 类型检查bug
            "testAS2TypeCheckingIssue",     // AS2 类型检查行为分析
            "testRaceConditionBug"          // 竞态条件（v1.1修复，应通过）
            // testLifecycleTaskIDReuseBug 已在 v1.3 修复，移至核心测试
        ];

        for (var i:Number = 0; i < bugTests.length; i++) {
            var tester:TaskManagerTester = new TaskManagerTester();
            _safeRunTest(bugTests[i], tester);
        }

        _printTestResults();
    }

    // ----------------------------
    // v1.1 修复验证测试用例
    // ----------------------------

    /**
     * testZombieTaskFix_v1_1
     * ---------------------------------------------------------------------------
     * [FIX v1.1] 验证僵尸任务复活修复：
     *  - 任务在回调中调用 removeTask() 删除自己
     *  - 修复后：updateFrame() 在执行回调后检查任务是否仍存在
     *  - 如果任务已被删除，跳过重调度逻辑，不会产生僵尸任务
     */
    public function testZombieTaskFix_v1_1():Void {
        var self:TaskManagerTester = this;
        var executionCount:Number = 0;
        var taskID:String;

        // 创建一个在第2次执行时删除自己的循环任务
        taskID = this.taskManager.addLoopTask(
            function():Void {
                executionCount++;
                if (executionCount == 2) {
                    self.taskManager.removeTask(taskID);
                }
            },
            50 // 每50ms执行一次
        );

        // 运行足够多的帧
        simulateFrames(30);

        // 验证：任务应该被删除且不会复活
        var taskAfter:Task = this.taskManager.locateTask(taskID);
        assert(taskAfter == null, "Task should be null after self-removal");

        // 验证：任务在删除后不应再执行
        assert(executionCount == 2, "Task should execute exactly 2 times before self-removal, got " + executionCount);
    }

    /**
     * testRescheduleNodeReferenceFix_v1_1
     * ---------------------------------------------------------------------------
     * [FIX v1.1] 验证 rescheduleTaskByNode 节点引用修复：
     *  - 调用 rescheduleTaskByNode 后，task.node 应指向新节点
     *  - 修复前：返回 Void，task.node 指向旧的被reset的节点
     *  - 修复后：返回新节点，调用方更新 task.node
     */
    public function testRescheduleNodeReferenceFix_v1_1():Void {
        var self:TaskManagerTester = this;
        var obj:Object = {};
        var executionCount:Number = 0;

        // 添加一个生命周期任务
        var taskID:String = this.taskManager.addLifecycleTask(obj, "nodeRefTest",
            function():Void { executionCount++; },
            100
        );

        // 执行几帧让任务执行一次
        simulateFrames(5);
        var countAfterFirst:Number = executionCount;

        // 获取任务并检查节点
        var task:Task = this.taskManager.locateTask(taskID);
        assert(task != null, "Task should exist");

        // 通过 addLifecycleTask 触发 reschedule（更新同名任务）
        this.taskManager.addLifecycleTask(obj, "nodeRefTest",
            function():Void { executionCount++; },
            50 // 更短的间隔
        );

        // 继续执行，验证任务仍然正常工作
        simulateFrames(10);
        var countAfterReschedule:Number = executionCount;

        assert(countAfterReschedule > countAfterFirst,
            "Task should continue executing after reschedule");

        // 测试 delayTask 是否也能正常工作
        this.taskManager.delayTask(taskID, 100);
        var countBeforeDelay:Number = executionCount;
        simulateFrames(3);

        // 在延迟期间任务不应执行（或最多执行1次，由于帧对齐）
        assert(executionCount - countBeforeDelay <= 1,
            "Task should be delayed properly, got " + (executionCount - countBeforeDelay) + " extra executions");
    }

    /**
     * testNodePoolReuse_v1_1
     * ---------------------------------------------------------------------------
     * [FIX v1.1] 验证节点池复用：
     *  - evaluateAndInsertTask 应从 SingleLevelTimeWheel 的节点池获取节点
     *  - 而不是每次都 new TaskIDNode
     *  - 这是性能优化，通过观察节点池大小变化来验证
     */
    public function testNodePoolReuse_v1_1():Void {
        // 预填充节点池
        this.scheduleTimer["singleLevelTimeWheel"].fillNodePool(20);
        var filledPoolSize:Number = this.scheduleTimer["singleLevelTimeWheel"].getNodePoolSize();

        // 添加多个任务（应该从池中获取节点）
        for (var i:Number = 0; i < 10; i++) {
            this.taskManager.addSingleTask(function():Void{}, 100);
        }

        // 检查节点池大小减少
        var afterAddPoolSize:Number = this.scheduleTimer["singleLevelTimeWheel"].getNodePoolSize();

        // 节点池应该减少（因为节点被取出）
        assert(afterAddPoolSize < filledPoolSize,
            "Node pool should decrease after adding tasks. Before: " + filledPoolSize + ", After: " + afterAddPoolSize);

        // 执行几帧让任务完成
        simulateFrames(10);

        // 任务完成后，节点应该被归还到池中
        var afterExecutePoolSize:Number = this.scheduleTimer["singleLevelTimeWheel"].getNodePoolSize();

        // 节点池应该恢复或增加（节点被归还）
        assert(afterExecutePoolSize >= afterAddPoolSize,
            "Node pool should increase after tasks complete. Before: " + afterAddPoolSize + ", After: " + afterExecutePoolSize);
    }

    // ----------------------------
    // v1.3 修复验证测试用例
    // ----------------------------

    /**
     * testGhostIDFix_v1_3
     * ---------------------------------------------------------------------------
     * [FIX v1.3] 验证幽灵 ID 修复：
     *  - 手动 removeTask 删除生命周期任务后，再次 addLifecycleTask 应分配新 ID
     *  - 修复前：复用旧 ID，旧的 unload 回调会杀死新任务
     *  - 修复后：检测到幽灵 ID，强制生成新 ID
     */
    public function testGhostIDFix_v1_3():Void {
        var self:TaskManagerTester = this;
        trace("Running testGhostIDFix_v1_3...");
        var obj:Object = {};
        var firstCallCount:Number = 0;
        var secondCallCount:Number = 0;

        // 第一次添加生命周期任务
        var firstTaskID:String = this.taskManager.addLifecycleTask(obj, "ghostTest",
            function():Void { firstCallCount++; },
            50
        );
        trace("First task ID: " + firstTaskID);

        // 让任务执行几次
        simulateFrames(5);

        // 手动删除任务（违反契约但应被正确处理）
        this.taskManager.removeTask(firstTaskID);
        trace("Manually removed first task");
        trace("obj.taskLabel['ghostTest'] after removal: " + obj.taskLabel["ghostTest"]);

        // 再次添加相同 label 的生命周期任务
        var secondTaskID:String = this.taskManager.addLifecycleTask(obj, "ghostTest",
            function():Void { secondCallCount++; },
            50
        );
        trace("Second task ID: " + secondTaskID);

        // [FIX v1.3] 验证：新任务应该分配新 ID，不复用旧 ID
        assert(firstTaskID != secondTaskID,
            "[FIX v1.3] Should allocate new ID for ghost detection. First: " + firstTaskID + ", Second: " + secondTaskID);

        // 验证第二个任务正常工作
        var countBefore:Number = secondCallCount;
        simulateFrames(10);
        assert(secondCallCount > countBefore,
            "Second task should execute normally after ghost ID fix");
    }

    /**
     * testZeroDelayBoundaryFix_v1_3
     * ---------------------------------------------------------------------------
     * [FIX v1.3] 验证零帧边界处理修复：
     *  - 直接调用 CerberusScheduler.evaluateAndInsertTask(taskID, 0) 不应导致任务延迟 149 帧
     *  - 修复前：delayInFrames=0 -> delay=-1 -> 槽位回环到 149
     *  - 修复后：delayInFrames<1 被强制设为 1
     */
    public function testZeroDelayBoundaryFix_v1_3():Void {
        trace("Running testZeroDelayBoundaryFix_v1_3...");

        // 直接调用底层调度器测试边界条件
        var testTaskID:String = "boundary_test_task";

        // 添加一个 delay=0 的任务到调度器
        var node:Object = this.scheduleTimer.evaluateAndInsertTask(testTaskID, 0);

        // 运行 5 帧，任务应该在第 1-2 帧执行（而非 149 帧后）
        var executed:Boolean = false;
        for (var i:Number = 0; i < 5; i++) {
            this.currentFrame++;
            var tasks = this.scheduleTimer.tick();
            if (tasks != null) {
                var taskNode = tasks.getFirst();
                while (taskNode != null) {
                    if (taskNode.taskID == testTaskID) {
                        executed = true;
                        trace("[FIX v1.3] Zero delay task executed at frame " + this.currentFrame);
                    }
                    taskNode = taskNode.next;
                }
            }
        }

        assert(executed, "[FIX v1.3] Zero delay task should execute within 5 frames, not 149 frames later");
    }

    /**
     * testArrayReuseFix_v1_3
     * ---------------------------------------------------------------------------
     * [FIX v1.3] 验证数组复用修复：
     *  - updateFrame 中的 zeroIds 和 toDelete 应复用数组，避免每帧分配
     *  - 通过反射检查 _reusableZeroIds 和 _reusableToDelete 的存在
     */
    public function testArrayReuseFix_v1_3():Void {
        trace("Running testArrayReuseFix_v1_3...");

        // 检查复用数组是否存在
        var reusableZeroIds:Array = this.taskManager["_reusableZeroIds"];
        var reusableToDelete:Array = this.taskManager["_reusableToDelete"];

        assert(reusableZeroIds != null, "[FIX v1.3] _reusableZeroIds should exist");
        assert(reusableToDelete != null, "[FIX v1.3] _reusableToDelete should exist");

        // 添加一些零帧任务
        var zeroTaskCount:Number = 0;
        for (var i:Number = 0; i < 3; i++) {
            this.taskManager.addTask(function():Void { zeroTaskCount++; }, 0, 1);
        }

        // 执行一帧，触发 updateFrame
        this.taskManager.updateFrame();

        // 零帧任务应该都执行了
        assert(zeroTaskCount == 3, "Zero frame tasks should all execute, got " + zeroTaskCount);

        // 检查数组是否被正确清空（复用时会清空）
        trace("_reusableZeroIds length after updateFrame: " + reusableZeroIds.length);
        trace("_reusableToDelete length after updateFrame: " + reusableToDelete.length);

        // 数组应该存在但内容已处理（长度可能为 0 或保留上次内容）
        assert(reusableZeroIds instanceof Array, "[FIX v1.3] _reusableZeroIds should remain an array after use");
    }

    /**
     * testFramesPerMsRename_v1_3
     * ---------------------------------------------------------------------------
     * [FIX v1.3] 验证 msPerFrame 重命名为 framesPerMs：
     *  - 通过反射检查新属性存在，旧属性不存在
     */
    public function testFramesPerMsRename_v1_3():Void {
        trace("Running testFramesPerMsRename_v1_3...");

        // 检查新属性存在
        var framesPerMs:Number = this.taskManager["framesPerMs"];
        assert(!isNaN(framesPerMs), "[FIX v1.3] framesPerMs should exist and be a number");

        // 验证计算正确：30 FPS -> framesPerMs = 0.03
        var expected:Number = this.frameRate / 1000;
        assert(Math.abs(framesPerMs - expected) < 0.0001,
            "[FIX v1.3] framesPerMs should equal frameRate/1000, expected " + expected + ", got " + framesPerMs);

        // 验证任务延迟计算仍然正确
        var executed:Boolean = false;
        var execFrame:Number = 0;
        var self:TaskManagerTester = this;

        // 添加一个 100ms 延迟的任务（100ms * 0.03 = 3 帧）
        this.taskManager.addSingleTask(
            function():Void {
                executed = true;
                execFrame = self.currentFrame;
            },
            100
        );

        simulateFrames(5);

        assert(executed, "Task with 100ms delay should execute within 5 frames");
        assert(execFrame >= 3 && execFrame <= 4,
            "Task should execute around frame 3-4, executed at frame " + execFrame);
    }

    /**
     * runV1_3FixTests
     * ---------------------------------------------------------------------------
     * 运行 v1.3 修复相关的测试用例
     */
    public static function runV1_3FixTests():Void {
        trace("=====================================================");
        trace("【v1.3 修复验证测试套件】");
        trace("=====================================================");

        _resetStats();

        var fixTests:Array = [
            "testGhostIDFix_v1_3",           // 幽灵 ID 修复验证
            "testZeroDelayBoundaryFix_v1_3", // 零帧边界修复验证
            "testArrayReuseFix_v1_3",        // 数组复用修复验证
            "testFramesPerMsRename_v1_3"     // 属性重命名验证
        ];

        for (var i:Number = 0; i < fixTests.length; i++) {
            var tester:TaskManagerTester = new TaskManagerTester();
            _safeRunTest(fixTests[i], tester);
        }

        _printTestResults();
    }

    /**
     * runV1_1FixTests
     * ---------------------------------------------------------------------------
     * 运行 v1.1 修复相关的测试用例
     */
    public static function runV1_1FixTests():Void {
        trace("=====================================================");
        trace("【v1.1 修复验证测试套件】");
        trace("=====================================================");

        _resetStats();

        var fixTests:Array = [
            "testZombieTaskFix_v1_1",           // 僵尸任务修复验证
            "testRescheduleNodeReferenceFix_v1_1", // 节点引用修复验证
            "testNodePoolReuse_v1_1"            // 节点池复用验证
        ];

        for (var i:Number = 0; i < fixTests.length; i++) {
            var tester:TaskManagerTester = new TaskManagerTester();
            _safeRunTest(fixTests[i], tester);
        }

        _printTestResults();
    }
}
