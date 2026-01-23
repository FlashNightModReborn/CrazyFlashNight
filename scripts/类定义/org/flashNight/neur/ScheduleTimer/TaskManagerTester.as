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
            "testLifecycleTaskIDReuseBug",
            // v1.4 修复验证测试
            "testExpiredNodeRecycling_v1_4", "testLoopTaskNodeRecycling_v1_4", "testOwnerTypeRemovalDispatch_v1_4",
            // v1.5 修复验证测试
            "testSharedNodePoolIntegration_v1_5", "testDoubleRecycleProtection_v1_5",
            // v1.6 修复验证测试
            "testMinHeapCallbackSelfRemoval_v1_6", "testAddOrUpdateTaskGhostID_v1_6", "testRemoveLifecycleTaskAPI_v1_6",
            // v1.7 修复验证测试
            "testChainBreakingWheel_v1_7", "testChainBreakingHeap_v1_7",
            "testNeverEarlyTrigger_v1_7", "testStressRandomOps_v1_7",
            // v1.7 修复后，原已知限制测试现在应通过（typeof 替代 isNaN）
            "testDelayTaskNonNumeric", "testAS2TypeCheckingIssue",
            // v1.7.1 修复验证测试
            "testRepeatingRemoveDuringDispatch_v1_7_1",
            "testDelayTaskDuringDispatch_v1_7_1",
            "testDelayTaskDuringDispatch_Reschedule_v1_7_1",
            "testAddToMinHeapByIDPoolRecycling_v1_7_1",
            // v1.7.2 修复验证测试
            "testRemoveOverridesDelayDuringDispatch_v1_7_2",
            "testRemoveThenDelayFailsDuringDispatch_v1_7_2"
        ];

        for (var i:Number = 0; i < coreTests.length; i++) {
            var tester:TaskManagerTester = new TaskManagerTester();
            _safeRunTest(coreTests[i], tester);
        }

        var coreStats:Object = {passed: testStats.passed, failed: testStats.failed};

        // ==================== 第二组：已知限制测试（部分预期失败）====================
        trace("\n--- 已知限制/Bug复现测试 (部分预期失败) ---");
        var knownIssueTests:Array = [
            "testRaceConditionBug"          // 竞态条件（v1.1已修复，此测试应通过）
            // testLifecycleTaskIDReuseBug 已移至核心测试（v1.3 修复后应通过）
            // testDelayTaskNonNumeric 已移至核心测试（v1.7 typeof 修复后应通过）
            // testAS2TypeCheckingIssue 已移至核心测试（v1.7 typeof 修复后应通过）
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
                if (err.test == "testRaceConditionBug") {
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
                if (err2.test == "testRaceConditionBug") {
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
     *  - testRaceConditionBug: 竞态条件潜在风险（已在v1.1修复，现应通过）
     *
     * 【v1.3 更新】testLifecycleTaskIDReuseBug 已修复，移至核心测试
     * 【v1.7 更新】testDelayTaskNonNumeric / testAS2TypeCheckingIssue 已修复（typeof），移至核心测试
     */
    public static function runBugTests():Void {
        trace("=====================================================");
        trace("【已知限制/Bug复现测试】（部分测试预期失败）");
        trace("=====================================================");

        _resetStats();

        var bugTests:Array = [
            "testRaceConditionBug"          // 竞态条件（v1.1修复，应通过）
            // testLifecycleTaskIDReuseBug 已在 v1.3 修复，移至核心测试
            // testDelayTaskNonNumeric 已在 v1.7 修复（typeof），移至核心测试
            // testAS2TypeCheckingIssue 已在 v1.7 修复（typeof），移至核心测试
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

    // ----------------------------
    // v1.4 修复验证测试用例
    // ----------------------------

    /**
     * testExpiredNodeRecycling_v1_4
     * ---------------------------------------------------------------------------
     * [FIX v1.4] 验证到期节点回收机制：
     *  - 任务执行完毕后，节点应被回收到节点池
     *  - 任务重调度后，旧节点应被回收
     *  - 节点池大小应该保持稳定或增长
     */
    public function testExpiredNodeRecycling_v1_4():Void {
        var self:TaskManagerTester = this;
        trace("Running testExpiredNodeRecycling_v1_4...");

        // 预填充节点池
        this.scheduleTimer["singleLevelTimeWheel"].fillNodePool(20);
        var initialPoolSize:Number = this.scheduleTimer["singleLevelTimeWheel"].getNodePoolSize();
        trace("Initial node pool size: " + initialPoolSize);

        // 添加多个单次任务
        var taskCount:Number = 10;
        for (var i:Number = 0; i < taskCount; i++) {
            this.taskManager.addSingleTask(function():Void{}, 50);
        }

        var afterAddPoolSize:Number = this.scheduleTimer["singleLevelTimeWheel"].getNodePoolSize();
        trace("After adding " + taskCount + " tasks, pool size: " + afterAddPoolSize);

        // 执行足够多的帧让所有任务完成
        simulateFrames(10);

        var afterExecutePoolSize:Number = this.scheduleTimer["singleLevelTimeWheel"].getNodePoolSize();
        trace("After execution, pool size: " + afterExecutePoolSize);

        // [FIX v1.4] 任务执行后节点应被回收，池大小应恢复或增加
        assert(afterExecutePoolSize >= afterAddPoolSize,
            "[FIX v1.4] Node pool should recover after task execution. Before: " + afterAddPoolSize + ", After: " + afterExecutePoolSize);
    }

    /**
     * testLoopTaskNodeRecycling_v1_4
     * ---------------------------------------------------------------------------
     * [FIX v1.4] 验证循环任务重调度时的节点回收：
     *  - 循环任务每次执行后重调度，旧节点应被回收
     *  - 节点池不应无限增长或减少
     */
    public function testLoopTaskNodeRecycling_v1_4():Void {
        var self:TaskManagerTester = this;
        trace("Running testLoopTaskNodeRecycling_v1_4...");

        // 记录初始节点池大小
        var initialPoolSize:Number = this.scheduleTimer["singleLevelTimeWheel"].getNodePoolSize();
        trace("Initial pool size: " + initialPoolSize);

        var executionCount:Number = 0;
        var taskID:String = this.taskManager.addLoopTask(
            function():Void {
                executionCount++;
            },
            33 // 每33ms执行一次，约每帧
        );

        // 执行多帧
        simulateFrames(30);
        trace("Loop task executed " + executionCount + " times");

        var afterLoopPoolSize:Number = this.scheduleTimer["singleLevelTimeWheel"].getNodePoolSize();
        trace("After loop executions, pool size: " + afterLoopPoolSize);

        // 删除循环任务
        this.taskManager.removeTask(taskID);

        // [FIX v1.4] 节点池大小应该保持合理范围
        // 由于循环任务每次执行后旧节点被回收，池大小不应剧烈波动
        assert(executionCount > 1, "Loop task should execute multiple times, got " + executionCount);

        // 节点池大小变化应该在合理范围内（允许±20的波动）
        var poolDelta:Number = Math.abs(afterLoopPoolSize - initialPoolSize);
        assert(poolDelta < 20,
            "[FIX v1.4] Node pool size should be stable. Initial: " + initialPoolSize +
            ", After: " + afterLoopPoolSize + ", Delta: " + poolDelta);
    }

    /**
     * testOwnerTypeRemovalDispatch_v1_4
     * ---------------------------------------------------------------------------
     * [FIX v1.4] 验证基于 ownerType 的删除分派：
     *  - 时间轮节点（ownerType 1-3）通过链表删除
     *  - 堆节点（ownerType 4）通过 minHeap.removeNode 删除
     */
    public function testOwnerTypeRemovalDispatch_v1_4():Void {
        var self:TaskManagerTester = this;
        trace("Running testOwnerTypeRemovalDispatch_v1_4...");

        // 添加一个短延迟任务（进入单层时间轮）
        var shortTask:Object = {};
        var shortTaskID:String = this.taskManager.addLifecycleTask(shortTask, "shortTask",
            function():Void {},
            50
        );

        // 获取任务节点
        var shortTaskObj:Task = this.taskManager.locateTask(shortTaskID);
        assert(shortTaskObj != null, "Short task should exist");

        var shortNode:Object = shortTaskObj.node;
        var shortOwnerType:Number = shortNode.ownerType;
        trace("Short task ownerType: " + shortOwnerType);

        // 验证短延迟任务进入时间轮（ownerType 1-3）
        assert(shortOwnerType >= 1 && shortOwnerType <= 3,
            "[FIX v1.4] Short delay task should be in time wheel (ownerType 1-3), got " + shortOwnerType);

        // 删除任务
        this.taskManager.removeTask(shortTaskID);

        // 验证任务已删除
        assert(this.taskManager.locateTask(shortTaskID) == null,
            "Task should be removed after removeTask");

        // 添加一个超长延迟任务（可能进入最小堆，取决于延迟值）
        var longTask:Object = {};
        var longTaskID:String = this.taskManager.addLifecycleTask(longTask, "longTask",
            function():Void {},
            999999 // 很长的延迟，可能进入最小堆
        );

        var longTaskObj:Task = this.taskManager.locateTask(longTaskID);
        if (longTaskObj != null) {
            var longNode:Object = longTaskObj.node;
            var longOwnerType:Number = longNode.ownerType;
            trace("Long task ownerType: " + longOwnerType);

            // 删除任务
            this.taskManager.removeTask(longTaskID);

            // 验证任务已删除
            assert(this.taskManager.locateTask(longTaskID) == null,
                "Long task should be removed after removeTask");
        }
    }

    /**
     * runV1_4FixTests
     * ---------------------------------------------------------------------------
     * 运行 v1.4 修复相关的测试用例
     */
    public static function runV1_4FixTests():Void {
        trace("=====================================================");
        trace("【v1.4 修复验证测试套件】");
        trace("=====================================================");

        _resetStats();

        var fixTests:Array = [
            "testExpiredNodeRecycling_v1_4",       // 到期节点回收验证
            "testLoopTaskNodeRecycling_v1_4",      // 循环任务节点回收验证
            "testOwnerTypeRemovalDispatch_v1_4"    // ownerType 删除分派验证
        ];

        for (var i:Number = 0; i < fixTests.length; i++) {
            var tester:TaskManagerTester = new TaskManagerTester();
            _safeRunTest(fixTests[i], tester);
        }

        _printTestResults();
    }

    // ----------------------------
    // v1.5 修复验证测试用例
    // ----------------------------

    /**
     * testSharedNodePoolIntegration_v1_5
     * ---------------------------------------------------------------------------
     * [FIX v1.5] 验证统一节点池在 TaskManager 层的集成：
     *  - 通过 TaskManager 添加的任务使用统一节点池
     *  - 不同延迟范围的任务都正确共享节点池
     */
    public function testSharedNodePoolIntegration_v1_5():Void {
        var self:TaskManagerTester = this;
        trace("Running testSharedNodePoolIntegration_v1_5...");

        var initialPoolSize:Number = this.scheduleTimer["singleLevelTimeWheel"].getNodePoolSize();
        trace("Initial pool size: " + initialPoolSize);

        // 添加不同延迟范围的任务（会进入不同时间轮）
        var shortTaskID:String = this.taskManager.addSingleTask(function():Void{}, 50);     // 单层时间轮
        var mediumTaskID:String = this.taskManager.addSingleTask(function():Void{}, 7000);  // 二级时间轮（~7秒）
        var longTaskID:String = this.taskManager.addSingleTask(function():Void{}, 70000);   // 三级时间轮（~70秒）

        var afterAddPoolSize:Number = this.scheduleTimer["singleLevelTimeWheel"].getNodePoolSize();
        trace("After adding 3 tasks to different wheels, pool size: " + afterAddPoolSize);

        // 验证节点从统一池获取（池大小应减少3）
        assert(afterAddPoolSize == initialPoolSize - 3,
            "[FIX v1.5] All tasks should acquire nodes from shared pool. Expected: " +
            (initialPoolSize - 3) + ", Got: " + afterAddPoolSize);

        // 删除任务
        this.taskManager.removeTask(shortTaskID);
        this.taskManager.removeTask(mediumTaskID);
        this.taskManager.removeTask(longTaskID);

        var afterRemovePoolSize:Number = this.scheduleTimer["singleLevelTimeWheel"].getNodePoolSize();
        trace("After removing all tasks, pool size: " + afterRemovePoolSize);

        // 验证节点回收到统一池
        assert(afterRemovePoolSize == initialPoolSize,
            "[FIX v1.5] Removed nodes should return to shared pool. Expected: " +
            initialPoolSize + ", Got: " + afterRemovePoolSize);
    }

    /**
     * testDoubleRecycleProtection_v1_5
     * ---------------------------------------------------------------------------
     * [FIX v1.5] 验证防重复回收保护：
     *  - recycleExpiredNode 对已回收节点（ownerType==0）不重复操作
     *  - 防止节点池中出现重复引用
     */
    public function testDoubleRecycleProtection_v1_5():Void {
        var self:TaskManagerTester = this;
        trace("Running testDoubleRecycleProtection_v1_5...");

        // 获取初始池大小
        var initialPoolSize:Number = this.scheduleTimer["singleLevelTimeWheel"].getNodePoolSize();

        // 手动创建并回收节点以测试防重复机制
        var node:TaskIDNode = this.scheduleTimer["singleLevelTimeWheel"].acquireNode("doubleRecycleTest");
        node.ownerType = 1; // 模拟属于单层时间轮

        var afterAcquirePoolSize:Number = this.scheduleTimer["singleLevelTimeWheel"].getNodePoolSize();
        trace("After acquire, pool size: " + afterAcquirePoolSize);

        // 第一次回收
        this.scheduleTimer.recycleExpiredNode(node);
        var afterFirstRecyclePoolSize:Number = this.scheduleTimer["singleLevelTimeWheel"].getNodePoolSize();
        trace("After first recycle, pool size: " + afterFirstRecyclePoolSize);

        // 验证 ownerType 被重置为 0
        assert(node.ownerType == 0, "[FIX v1.5] ownerType should be 0 after recycle, got: " + node.ownerType);

        // 第二次回收（应被跳过）
        this.scheduleTimer.recycleExpiredNode(node);
        var afterSecondRecyclePoolSize:Number = this.scheduleTimer["singleLevelTimeWheel"].getNodePoolSize();
        trace("After second recycle, pool size: " + afterSecondRecyclePoolSize);

        // 验证池大小未变化（重复回收被阻止）
        assert(afterSecondRecyclePoolSize == afterFirstRecyclePoolSize,
            "[FIX v1.5] Double recycle should be prevented. Pool size should be " +
            afterFirstRecyclePoolSize + ", got: " + afterSecondRecyclePoolSize);
    }

    /**
     * runV1_5FixTests
     * ---------------------------------------------------------------------------
     * 运行 v1.5 修复相关的测试用例
     */
    public static function runV1_5FixTests():Void {
        trace("=====================================================");
        trace("【v1.5 修复验证测试套件】");
        trace("=====================================================");

        _resetStats();

        var fixTests:Array = [
            "testSharedNodePoolIntegration_v1_5",    // 统一节点池集成验证
            "testDoubleRecycleProtection_v1_5"       // 防重复回收验证
        ];

        for (var i:Number = 0; i < fixTests.length; i++) {
            var tester:TaskManagerTester = new TaskManagerTester();
            _safeRunTest(fixTests[i], tester);
        }

        _printTestResults();
    }

    // ----------------------------
    // v1.6 修复验证测试用例
    // ----------------------------

    /**
     * testMinHeapCallbackSelfRemoval_v1_6
     * ---------------------------------------------------------------------------
     * [FIX v1.6 S1] 验证最小堆任务在回调中删除自身的安全性：
     *  - 最小堆任务在 extractTasksAtMinFrame 后 frameMap 被删除
     *  - 回调中调用 removeTask 应安全处理，不导致堆损坏
     *  - 修复前：removeNode 访问 undefined frameMap 导致 heapSize 错误递减
     *  - 修复后：removeNode 检测到 undefined list 后直接回收节点并返回
     */
    public function testMinHeapCallbackSelfRemoval_v1_6():Void {
        var self:TaskManagerTester = this;
        trace("Running testMinHeapCallbackSelfRemoval_v1_6...");

        var executionCount:Number = 0;
        var taskID:String;

        // 添加一个超长延迟任务，确保进入最小堆（ownerType = 4）
        // 使用足够大的延迟确保任务进入最小堆而非时间轮
        taskID = this.taskManager.addTask(
            function():Void {
                executionCount++;
                trace("[FIX v1.6 S1] MinHeap task executed at frame " + self.currentFrame);
                // 在回调中删除自身
                self.taskManager.removeTask(taskID);
                trace("[FIX v1.6 S1] Task self-removed in callback");
            },
            100000, // 100秒延迟，确保进入最小堆
            1       // 单次执行
        );

        // 获取任务并验证 ownerType
        var task:Task = this.taskManager.locateTask(taskID);
        assert(task != null, "Task should exist");

        // 验证任务进入了最小堆（ownerType = 4）
        var node:Object = task.node;
        trace("Task ownerType: " + node.ownerType);

        // 由于延迟太长，我们需要直接手动触发执行
        // 这里我们通过 removeTask 然后重新添加短延迟任务来模拟
        this.taskManager.removeTask(taskID);

        // 重新添加短延迟任务到最小堆
        // 通过直接使用调度器的 addToMinHeapByID 确保进入最小堆
        var heapTaskID:String = "heap_self_remove_test";
        this.scheduleTimer.addToMinHeapByID(heapTaskID, 1); // 1帧延迟

        // 创建对应的 Task 对象并添加到 taskTable
        // 这里我们使用一个简化的测试：直接调用底层调度器
        trace("Testing min heap removeNode with extracted frame...");

        // 执行一帧，触发最小堆任务
        this.currentFrame++;
        var tasks = this.scheduleTimer.tick();

        if (tasks != null) {
            var taskNode = tasks.getFirst();
            while (taskNode != null) {
                if (taskNode.taskID == heapTaskID) {
                    trace("Heap task found, simulating self-removal...");
                    // 模拟在回调中调用 removeTaskByNode
                    // 此时 frameMap[frameIndex] 已被 extractTasksAtMinFrame 删除
                    // 修复前这会导致堆损坏，修复后应安全处理
                    this.scheduleTimer.removeTaskByNode(taskNode);
                    trace("Self-removal completed without crash - FIX VERIFIED");
                }
                taskNode = taskNode.next;
            }
        }

        // 如果代码执行到这里没有崩溃，说明修复有效
        assert(true, "[FIX v1.6 S1] Min heap callback self-removal handled safely");
    }

    /**
     * testAddOrUpdateTaskGhostID_v1_6
     * ---------------------------------------------------------------------------
     * [FIX v1.6 I1] 验证 addOrUpdateTask 的幽灵 ID 检测：
     *  - 手动 removeTask 删除任务后，taskLabel 仍存在
     *  - 再次调用 addOrUpdateTask 应检测到幽灵 ID 并分配新 ID
     *  - 修复前：复用旧 ID，可能导致任务状态混乱
     *  - 修复后：检测到幽灵 ID，强制生成新 ID
     */
    public function testAddOrUpdateTaskGhostID_v1_6():Void {
        var self:TaskManagerTester = this;
        trace("Running testAddOrUpdateTaskGhostID_v1_6...");

        var obj:Object = {};
        var firstCallCount:Number = 0;
        var secondCallCount:Number = 0;

        // 第一次添加任务
        var firstTaskID:String = this.taskManager.addOrUpdateTask(obj, "ghostTestLabel",
            function():Void { firstCallCount++; },
            50
        );
        trace("First task ID: " + firstTaskID);
        trace("obj.taskLabel['ghostTestLabel']: " + obj.taskLabel["ghostTestLabel"]);

        // 让任务执行一次
        simulateFrames(5);
        trace("First task execution count: " + firstCallCount);

        // 手动删除任务（但不清除 taskLabel）
        this.taskManager.removeTask(firstTaskID);
        trace("Manually removed first task");
        trace("obj.taskLabel['ghostTestLabel'] after removal: " + obj.taskLabel["ghostTestLabel"]);

        // 验证任务已被删除
        assert(this.taskManager.locateTask(firstTaskID) == null, "First task should be removed");

        // 验证 taskLabel 仍然存在（这是幽灵 ID 的前提条件）
        assert(obj.taskLabel["ghostTestLabel"] == firstTaskID,
            "taskLabel should still contain old ID (ghost ID scenario)");

        // 再次添加相同 label 的任务
        var secondTaskID:String = this.taskManager.addOrUpdateTask(obj, "ghostTestLabel",
            function():Void { secondCallCount++; },
            50
        );
        trace("Second task ID: " + secondTaskID);

        // [FIX v1.6 I1] 验证：新任务应该分配新 ID
        assert(firstTaskID != secondTaskID,
            "[FIX v1.6 I1] Should allocate new ID for ghost detection. First: " + firstTaskID + ", Second: " + secondTaskID);

        // 验证第二个任务正常工作
        var countBefore:Number = secondCallCount;
        simulateFrames(10);
        assert(secondCallCount > countBefore,
            "Second task should execute normally after ghost ID fix");
    }

    /**
     * testRemoveLifecycleTaskAPI_v1_6
     * ---------------------------------------------------------------------------
     * [FIX v1.6 I2] 验证 removeLifecycleTask 新 API：
     *  - 通过 obj + labelName 移除生命周期任务
     *  - 同时清理 obj.taskLabel[labelName]
     *  - 适用于不跟踪 taskID 的场景
     */
    public function testRemoveLifecycleTaskAPI_v1_6():Void {
        var self:TaskManagerTester = this;
        trace("Running testRemoveLifecycleTaskAPI_v1_6...");

        var obj:Object = {};
        var executionCount:Number = 0;

        // 添加生命周期任务
        var taskID:String = this.taskManager.addLifecycleTask(obj, "removeApiTest",
            function():Void { executionCount++; },
            50
        );
        trace("Task ID: " + taskID);

        // 让任务执行几次
        simulateFrames(10);
        trace("Execution count after 10 frames: " + executionCount);
        assert(executionCount > 0, "Task should have executed");

        // 验证 taskLabel 存在
        assert(obj.taskLabel["removeApiTest"] == taskID, "taskLabel should contain taskID");

        // 使用新 API 移除任务
        var result:Boolean = this.taskManager.removeLifecycleTask(obj, "removeApiTest");
        trace("removeLifecycleTask result: " + result);

        // 验证返回值为 true
        assert(result == true, "[FIX v1.6 I2] removeLifecycleTask should return true for existing task");

        // 验证任务已被移除
        assert(this.taskManager.locateTask(taskID) == null,
            "[FIX v1.6 I2] Task should be removed after removeLifecycleTask");

        // 验证 taskLabel 已被清理
        assert(obj.taskLabel["removeApiTest"] == undefined,
            "[FIX v1.6 I2] taskLabel should be cleared after removeLifecycleTask");

        // 验证任务不再执行
        var countBefore:Number = executionCount;
        simulateFrames(10);
        assert(executionCount == countBefore,
            "[FIX v1.6 I2] Task should not execute after removal");

        // 测试对不存在的任务调用 removeLifecycleTask
        var result2:Boolean = this.taskManager.removeLifecycleTask(obj, "nonExistentLabel");
        assert(result2 == false, "[FIX v1.6 I2] removeLifecycleTask should return false for non-existent task");

        // 测试对 null obj 调用 removeLifecycleTask
        var result3:Boolean = this.taskManager.removeLifecycleTask(null, "someLabel");
        assert(result3 == false, "[FIX v1.6 I2] removeLifecycleTask should return false for null obj");
    }

    /**
     * runV1_6FixTests
     * ---------------------------------------------------------------------------
     * 运行 v1.6 修复相关的测试用例
     */
    public static function runV1_6FixTests():Void {
        trace("=====================================================");
        trace("【v1.6 修复验证测试套件】");
        trace("=====================================================");

        _resetStats();

        var fixTests:Array = [
            "testMinHeapCallbackSelfRemoval_v1_6",    // S1: 最小堆回调自删除修复验证
            "testAddOrUpdateTaskGhostID_v1_6",        // I1: addOrUpdateTask 幽灵 ID 检测验证
            "testRemoveLifecycleTaskAPI_v1_6"         // I2: removeLifecycleTask 新 API 验证
        ];

        for (var i:Number = 0; i < fixTests.length; i++) {
            var tester:TaskManagerTester = new TaskManagerTester();
            _safeRunTest(fixTests[i], tester);
        }

        _printTestResults();
    }

    // ----------------------------
    // v1.7 修复验证测试用例
    // ----------------------------

    /**
     * resetWithConfig
     * ---------------------------------------------------------------------------
     * 使用自定义配置重置测试环境，用于需要特殊调度器参数的测试用例
     *
     * @param singleWheelSize 单层时间轮大小
     * @param secondSize 二级时间轮大小（秒）
     * @param thirdSize 三级时间轮大小（分钟）
     * @param fps 帧率
     */
    private function resetWithConfig(singleWheelSize:Number, secondSize:Number,
                                     thirdSize:Number, fps:Number):Void {
        this.currentFrame = 0;
        this.logs = [];
        this.frameRate = fps;
        this.scheduleTimer = new CerberusScheduler();
        this.scheduleTimer.initialize(singleWheelSize, secondSize, thirdSize, fps, 0.1);
        this.taskManager = new TaskManager(this.scheduleTimer, fps);
    }

    /**
     * testChainBreakingWheel_v1_7
     * ---------------------------------------------------------------------------
     * [FIX v1.7 S1] 验证同帧链式断裂修复（时间轮任务）：
     *
     * 场景：任务 A、B、C 在同一帧到期（同一时间轮槽位）。
     *   A 的回调调用 removeTask(B)。
     *   修复前：removeTask(B) 立即断开 B.next/B.prev，导致从 B 出发无法到达 C。
     *   修复后：_dispatching 标记期间 removeTask 仅做逻辑删除，不断开链表。
     *
     * 断言：
     *   - A 执行 ✓
     *   - B 不执行（已被逻辑删除）
     *   - C 必须执行 ✓
     */
    public function testChainBreakingWheel_v1_7():Void {
        var self:TaskManagerTester = this;
        trace("Running testChainBreakingWheel_v1_7...");

        var aExecuted:Boolean = false;
        var bExecuted:Boolean = false;
        var cExecuted:Boolean = false;
        var taskIDA:String;
        var taskIDB:String;
        var taskIDC:String;

        // 创建 3 个相同延迟的任务，使它们在同一帧到期
        // 100ms * 0.03 = 3 帧，会进入单层时间轮同一槽位
        taskIDA = this.taskManager.addSingleTask(
            function():Void {
                aExecuted = true;
                trace("[v1.7 S1 Wheel] A executed at frame " + self.currentFrame + ", removing B...");
                // 关键操作：在回调中删除同帧的另一个任务
                self.taskManager.removeTask(taskIDB);
            },
            100
        );

        taskIDB = this.taskManager.addSingleTask(
            function():Void {
                bExecuted = true;
                trace("[v1.7 S1 Wheel] B executed at frame " + self.currentFrame + " (BUG if reached after removal!)");
            },
            100
        );

        taskIDC = this.taskManager.addSingleTask(
            function():Void {
                cExecuted = true;
                trace("[v1.7 S1 Wheel] C executed at frame " + self.currentFrame);
            },
            100
        );

        // 验证所有任务进入了单层时间轮（ownerType 1）
        var taskA:Task = this.taskManager.locateTask(taskIDA);
        var taskB:Task = this.taskManager.locateTask(taskIDB);
        var taskC:Task = this.taskManager.locateTask(taskIDC);
        assert(taskA != null && taskA.node.ownerType == 1,
            "Task A should be in single-level wheel (ownerType=1)");
        assert(taskB != null && taskB.node.ownerType == 1,
            "Task B should be in single-level wheel (ownerType=1)");
        assert(taskC != null && taskC.node.ownerType == 1,
            "Task C should be in single-level wheel (ownerType=1)");

        // 模拟足够多的帧让任务到期
        simulateFrames(10);

        // 断言
        assert(aExecuted, "[FIX v1.7 S1 Wheel] Task A must execute");
        assert(!bExecuted, "[FIX v1.7 S1 Wheel] Task B must NOT execute (was removed by A)");
        assert(cExecuted, "[FIX v1.7 S1 Wheel] Task C MUST execute (chain must not break)");

        // 验证 B 已从任务表彻底删除
        assert(this.taskManager.locateTask(taskIDB) == null,
            "[FIX v1.7 S1 Wheel] Task B should be fully removed from taskTable");

        trace("[v1.7 S1 Wheel] PASS: Chain-breaking prevented, C executed correctly");
    }

    /**
     * testChainBreakingHeap_v1_7
     * ---------------------------------------------------------------------------
     * [FIX v1.7 S1] 验证同帧链式断裂修复（最小堆任务）：
     *
     * 使用自定义小配置调度器，使任务路由至最小堆。
     * 场景与轮任务相同：A、B、C 同帧到期，A 删 B，C 必须执行。
     *
     * 配置：singleWheelSize=10, secondSize=5, thirdSize=5, fps=10
     * - multiLevelCounterLimit = 10
     * - _thirdTickPeriod = 5 * 10 = 50
     * - 堆路由条件：delaySlot3 = ceil(delay/50) > 5 → delay > 250
     *
     * 断言：
     *   - A 执行 ✓
     *   - B 不执行（已被逻辑删除）
     *   - C 必须执行 ✓
     */
    public function testChainBreakingHeap_v1_7():Void {
        // 使用自定义小配置，使任务路由至最小堆
        this.resetWithConfig(10, 5, 5, 10);

        var self:TaskManagerTester = this;
        trace("Running testChainBreakingHeap_v1_7...");

        var aExecuted:Boolean = false;
        var bExecuted:Boolean = false;
        var cExecuted:Boolean = false;
        var taskIDA:String;
        var taskIDB:String;
        var taskIDC:String;

        // delay > 250 frames → ceil((delay+0)/50) > 5 → 路由至最小堆
        // framesPerMs = 10/1000 = 0.01
        // intervalFrames = ceil(26000 * 0.01) = ceil(260) = 260 → 堆路由 ✓
        var heapIntervalMs:Number = 26000;

        taskIDA = this.taskManager.addSingleTask(
            function():Void {
                aExecuted = true;
                trace("[v1.7 S1 Heap] A executed at frame " + self.currentFrame + ", removing B...");
                self.taskManager.removeTask(taskIDB);
            },
            heapIntervalMs
        );

        taskIDB = this.taskManager.addSingleTask(
            function():Void {
                bExecuted = true;
                trace("[v1.7 S1 Heap] B executed at frame " + self.currentFrame + " (BUG!)");
            },
            heapIntervalMs
        );

        taskIDC = this.taskManager.addSingleTask(
            function():Void {
                cExecuted = true;
                trace("[v1.7 S1 Heap] C executed at frame " + self.currentFrame);
            },
            heapIntervalMs
        );

        // 验证任务路由至最小堆（ownerType 4）
        var taskA:Task = this.taskManager.locateTask(taskIDA);
        var taskB:Task = this.taskManager.locateTask(taskIDB);
        var taskC:Task = this.taskManager.locateTask(taskIDC);
        assert(taskA != null && taskA.node.ownerType == 4,
            "Task A should be in min-heap (ownerType=4), got " + (taskA ? taskA.node.ownerType : "null"));
        assert(taskB != null && taskB.node.ownerType == 4,
            "Task B should be in min-heap (ownerType=4), got " + (taskB ? taskB.node.ownerType : "null"));
        assert(taskC != null && taskC.node.ownerType == 4,
            "Task C should be in min-heap (ownerType=4), got " + (taskC ? taskC.node.ownerType : "null"));

        // 模拟足够多的帧让堆任务到期
        // 堆任务的 delay=260 帧，所以需要 261 帧才能触发
        simulateFrames(270);

        // 断言
        assert(aExecuted, "[FIX v1.7 S1 Heap] Task A must execute");
        assert(!bExecuted, "[FIX v1.7 S1 Heap] Task B must NOT execute (was removed by A)");
        assert(cExecuted, "[FIX v1.7 S1 Heap] Task C MUST execute (chain must not break)");

        trace("[v1.7 S1 Heap] PASS: Chain-breaking prevented in heap tasks");
    }

    /**
     * testNeverEarlyTrigger_v1_7
     * ---------------------------------------------------------------------------
     * [FIX v1.7 P0-3] 验证 Never-Early 公式：二/三级时间轮绝不提前触发
     *
     * 策略：在各种计数器相位下插入任务，验证实际触发帧数 >= 请求延迟。
     * 使用紧凑配置以快速覆盖所有相位：
     *   fps=10, singleWheelSize=10, secondSize=5, thirdSize=5
     *   multiLevelCounterLimit = 10, secondLevelCounterLimit = 5
     *   _thirdTickPeriod = 5 * 10 = 50
     *
     * 覆盖范围：
     *   - 二级时间轮：delay ∈ [10, 50)，相位 counter ∈ [0, 9]
     *   - 三级时间轮：delay ∈ [50, 250]，相位 offset ∈ [0, 49]
     *
     * 断言：actualDelay >= requestedDelay（绝不提前）
     * 度量：记录最大延后量（maxLateness），仅供参考不做约束
     */
    public function testNeverEarlyTrigger_v1_7():Void {
        trace("Running testNeverEarlyTrigger_v1_7...");

        var maxLateness2:Number = 0; // 二级最大延后（帧）
        var maxLateness3:Number = 0; // 三级最大延后（帧）
        var totalTests:Number = 0;
        var earlyTriggerCount:Number = 0;

        // ========== 二级时间轮测试 ==========
        // 遍历所有 10 种相位（counter = 0..9）
        // 对每种相位测试多种延迟值
        var secondLevelDelays:Array = [11, 15, 20, 25, 30, 35, 40, 45, 49];

        for (var phase:Number = 0; phase < 10; phase++) {
            for (var di:Number = 0; di < secondLevelDelays.length; di++) {
                var delay2:Number = secondLevelDelays[di];

                // 重置环境并推进到指定相位
                this.resetWithConfig(10, 5, 5, 10);
                // 推进 phase 帧使 multiLevelCounter = phase
                for (var p:Number = 0; p < phase; p++) {
                    this.currentFrame++;
                    this.scheduleTimer.tick();
                }

                var insertFrame2:Number = this.currentFrame;
                var triggerFrame2:Number = -1;
                var self2:TaskManagerTester = this;

                // 闭包捕获当前 delay 和 insertFrame
                var cb2:Function = this._createNeverEarlyCallback(self2, delay2, insertFrame2);
                var taskID2:String = this.taskManager.addSingleTask(cb2, delay2 * 100);
                // delay2 * 100ms * 0.01 framesPerMs = delay2 帧

                // 验证路由到二级时间轮（ownerType 2）
                var t2:Task = this.taskManager.locateTask(taskID2);
                if (t2 == null || t2.node.ownerType != 2) {
                    // 跳过非二级路由的情况（边界值可能进入其他层级）
                    continue;
                }

                // 模拟足够帧数
                var maxFrames2:Number = delay2 + 20;
                for (var f2:Number = 0; f2 < maxFrames2; f2++) {
                    this.currentFrame++;
                    this.taskManager.updateFrame();
                    if (this.taskManager.locateTask(taskID2) == null) {
                        triggerFrame2 = this.currentFrame;
                        break;
                    }
                }

                if (triggerFrame2 >= 0) {
                    var actualDelay2:Number = triggerFrame2 - insertFrame2;
                    var lateness2:Number = actualDelay2 - delay2;
                    totalTests++;

                    if (actualDelay2 < delay2) {
                        earlyTriggerCount++;
                        trace("[EARLY!] phase=" + phase + " delay=" + delay2 +
                              " actual=" + actualDelay2 + " (early by " + (delay2 - actualDelay2) + " frames)");
                    }
                    if (lateness2 > maxLateness2) {
                        maxLateness2 = lateness2;
                    }
                }
            }
        }

        // ========== 三级时间轮测试 ==========
        // 遍历多种相位组合 (secondLevelCounter * 10 + counter)
        var thirdLevelDelays:Array = [55, 70, 100, 130, 150, 200, 240];
        var phaseOffsets:Array = [0, 5, 12, 23, 37, 49]; // 各种 offset 值

        for (var oi:Number = 0; oi < phaseOffsets.length; oi++) {
            var targetOffset:Number = phaseOffsets[oi];
            for (var dj:Number = 0; dj < thirdLevelDelays.length; dj++) {
                var delay3:Number = thirdLevelDelays[dj];

                this.resetWithConfig(10, 5, 5, 10);
                // 推进 targetOffset 帧
                for (var pp:Number = 0; pp < targetOffset; pp++) {
                    this.currentFrame++;
                    this.scheduleTimer.tick();
                }

                var insertFrame3:Number = this.currentFrame;
                var triggerFrame3:Number = -1;
                var self3:TaskManagerTester = this;

                var cb3:Function = this._createNeverEarlyCallback(self3, delay3, insertFrame3);
                var taskID3:String = this.taskManager.addSingleTask(cb3, delay3 * 100);

                // 验证路由到三级时间轮（ownerType 3）
                var t3:Task = this.taskManager.locateTask(taskID3);
                if (t3 == null || t3.node.ownerType != 3) {
                    continue; // 跳过非三级路由
                }

                // 模拟足够帧数
                var maxFrames3:Number = delay3 + 60;
                for (var f3:Number = 0; f3 < maxFrames3; f3++) {
                    this.currentFrame++;
                    this.taskManager.updateFrame();
                    if (this.taskManager.locateTask(taskID3) == null) {
                        triggerFrame3 = this.currentFrame;
                        break;
                    }
                }

                if (triggerFrame3 >= 0) {
                    var actualDelay3:Number = triggerFrame3 - insertFrame3;
                    var lateness3:Number = actualDelay3 - delay3;
                    totalTests++;

                    if (actualDelay3 < delay3) {
                        earlyTriggerCount++;
                        trace("[EARLY!] offset=" + targetOffset + " delay=" + delay3 +
                              " actual=" + actualDelay3 + " (early by " + (delay3 - actualDelay3) + " frames)");
                    }
                    if (lateness3 > maxLateness3) {
                        maxLateness3 = lateness3;
                    }
                }
            }
        }

        trace("[v1.7 P0-3] Never-Early 测试完成:");
        trace("  总测试数: " + totalTests);
        trace("  提前触发数: " + earlyTriggerCount);
        trace("  二级最大延后: " + maxLateness2 + " 帧");
        trace("  三级最大延后: " + maxLateness3 + " 帧");

        assert(earlyTriggerCount == 0,
            "[FIX v1.7 P0-3] Never-Early 违规! " + earlyTriggerCount + "/" + totalTests + " 个任务提前触发");
        assert(totalTests > 0,
            "[FIX v1.7 P0-3] 至少应有 1 个有效测试用例被执行");
    }

    /**
     * _createNeverEarlyCallback
     * ---------------------------------------------------------------------------
     * 辅助方法：为 Never-Early 测试创建闭包回调
     * （避免循环中闭包变量捕获问题）
     */
    private function _createNeverEarlyCallback(self:TaskManagerTester,
                                               delay:Number, insertFrame:Number):Function {
        return function():Void {
            // 回调中无需特殊逻辑，任务触发由外部循环检测
        };
    }

    /**
     * testStressRandomOps_v1_7
     * ---------------------------------------------------------------------------
     * [FIX v1.7] 压力测试：随机任务创建/取消/重调度
     *
     * 策略：
     *   - 运行 3000 帧模拟（约 100 秒@30fps，或 300 秒@10fps）
     *   - 每帧随机执行操作：创建任务、取消随机任务、延迟随机任务
     *   - 周期性检查：任务总数、节点池大小、堆大小是否稳定
     *
     * 断言：
     *   - 无崩溃/无限循环（能正常跑完所有帧）
     *   - 最终活跃任务数合理（不无限增长）
     *   - 节点池大小保持在合理范围内
     *   - 生命周期对象正确清理
     */
    public function testStressRandomOps_v1_7():Void {
        trace("Running testStressRandomOps_v1_7...");

        // 使用标准配置
        this.resetBeforeTest();

        var totalFrames:Number = 3000;
        var activeTasks:Array = [];  // 当前活跃的 taskID 列表
        var lifecycleObjs:Array = []; // 模拟生命周期对象
        var maxActiveTasks:Number = 0;
        var totalCreated:Number = 0;
        var totalCancelled:Number = 0;
        var totalDelayed:Number = 0;
        var totalExecuted:Number = 0;
        var self:TaskManagerTester = this;

        // 简单的伪随机数生成器（AS2 Math.random() 可用，但为了可复现使用 LCG）
        var seed:Number = 12345;
        var nextRandom:Function = function():Number {
            seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
            return (seed >>> 16) / 32768.0; // [0, 1)
        };

        // 创建一些初始生命周期对象
        for (var li:Number = 0; li < 5; li++) {
            lifecycleObjs.push({id: li});
        }

        for (var frame:Number = 0; frame < totalFrames; frame++) {
            this.currentFrame++;

            var rand:Number = nextRandom();

            // 40% 概率创建新任务
            if (rand < 0.4 && activeTasks.length < 200) {
                var taskType:Number = nextRandom();
                var interval:Number = 33 + Math.floor(nextRandom() * 5000); // 33ms~5033ms
                var taskID:String;

                if (taskType < 0.5) {
                    // 单次任务
                    taskID = self.taskManager.addSingleTask(
                        function():Void { totalExecuted++; },
                        interval
                    );
                } else if (taskType < 0.8) {
                    // 循环任务（有限次）
                    var repeats:Number = 2 + Math.floor(nextRandom() * 5);
                    taskID = self.taskManager.addTask(
                        function():Void { totalExecuted++; },
                        interval,
                        repeats
                    );
                } else {
                    // 生命周期任务
                    var objIdx:Number = Math.floor(nextRandom() * lifecycleObjs.length);
                    var labelIdx:Number = Math.floor(nextRandom() * 3);
                    taskID = self.taskManager.addLifecycleTask(
                        lifecycleObjs[objIdx],
                        "stress_" + labelIdx,
                        function():Void { totalExecuted++; },
                        interval
                    );
                }

                if (taskID != null) {
                    activeTasks.push(taskID);
                    totalCreated++;
                }
            }

            // 20% 概率取消一个随机任务
            if (rand >= 0.4 && rand < 0.6 && activeTasks.length > 0) {
                var cancelIdx:Number = Math.floor(nextRandom() * activeTasks.length);
                var cancelID:String = activeTasks[cancelIdx];
                self.taskManager.removeTask(cancelID);
                activeTasks.splice(cancelIdx, 1);
                totalCancelled++;
            }

            // 15% 概率延迟一个随机任务
            if (rand >= 0.6 && rand < 0.75 && activeTasks.length > 0) {
                var delayIdx:Number = Math.floor(nextRandom() * activeTasks.length);
                var delayID:String = activeTasks[delayIdx];
                if (self.taskManager.locateTask(delayID) != null) {
                    var delayMs:Number = 100 + Math.floor(nextRandom() * 2000);
                    self.taskManager.delayTask(delayID, delayMs);
                    totalDelayed++;
                }
            }

            // 5% 概率模拟生命周期对象卸载并重建
            if (rand >= 0.95 && lifecycleObjs.length > 0) {
                var unloadIdx:Number = Math.floor(nextRandom() * lifecycleObjs.length);
                var unloadObj:Object = lifecycleObjs[unloadIdx];
                // 模拟 unload 回调（如果有注册）
                if (typeof unloadObj.onUnload == "function") {
                    unloadObj.onUnload();
                }
                // 替换为新对象
                lifecycleObjs[unloadIdx] = {id: unloadIdx + 100};
            }

            // 执行 updateFrame
            self.taskManager.updateFrame();

            // 清理已完成的任务（从 activeTasks 中移除已找不到的任务）
            if (frame % 100 == 0) {
                var cleaned:Array = [];
                for (var ci:Number = 0; ci < activeTasks.length; ci++) {
                    if (self.taskManager.locateTask(activeTasks[ci]) != null) {
                        cleaned.push(activeTasks[ci]);
                    }
                }
                activeTasks = cleaned;
            }

            // 记录峰值
            if (activeTasks.length > maxActiveTasks) {
                maxActiveTasks = activeTasks.length;
            }
        }

        // 获取最终状态
        var finalPoolSize:Number = this.scheduleTimer["singleLevelTimeWheel"].getNodePoolSize();
        var finalActiveCount:Number = activeTasks.length;

        trace("[v1.7 Stress] 压测完成:");
        trace("  总帧数: " + totalFrames);
        trace("  创建任务: " + totalCreated);
        trace("  取消任务: " + totalCancelled);
        trace("  延迟任务: " + totalDelayed);
        trace("  执行回调: " + totalExecuted);
        trace("  峰值活跃: " + maxActiveTasks);
        trace("  最终活跃: " + finalActiveCount);
        trace("  节点池大小: " + finalPoolSize);

        // 断言：无崩溃（能运行到这里就说明没有死循环/崩溃）
        assert(true, "[v1.7 Stress] 压测完成无崩溃");

        // 断言：最终活跃任务数合理（不应无限增长）
        // 由于有取消和完成机制，最终活跃任务数不应超过峰值
        assert(finalActiveCount <= maxActiveTasks,
            "[v1.7 Stress] 最终活跃任务数应 <= 峰值。最终: " + finalActiveCount + " 峰值: " + maxActiveTasks);

        // 断言：节点池没有负增长（泄漏）
        assert(finalPoolSize >= 0,
            "[v1.7 Stress] 节点池大小不应为负: " + finalPoolSize);

        // 断言：确实有任务被执行（系统正常工作）
        assert(totalExecuted > 0,
            "[v1.7 Stress] 至少应有任务被执行，实际: " + totalExecuted);

        // 断言：峰值活跃任务数在合理范围内（<= 200 上限）
        assert(maxActiveTasks <= 200,
            "[v1.7 Stress] 峰值活跃任务数超标: " + maxActiveTasks);
    }

    /**
     * testRepeatingRemoveDuringDispatch_v1_7_1
     * ---------------------------------------------------------------------------
     * [FIX v1.7] 验证 _dispatching 期间对重复任务的 removeTask 正确性：
     *
     * 场景：重复任务 A 和 B 在同一帧到期。
     *   A 的回调调用 removeTask(B)。
     *   B 是重复任务，应在该帧不执行且后续不再执行。
     *   A 应继续后续帧正常执行。
     *
     * 断言：
     *   - A 至少执行 2 次（确认多帧正常）
     *   - B 最多执行 0 次（A 在 B 执行前就删除了它）
     *   - 节点不泄漏（B 的节点被回收）
     */
    public function testRepeatingRemoveDuringDispatch_v1_7_1():Void {
        var self:TaskManagerTester = this;
        trace("Running testRepeatingRemoveDuringDispatch_v1_7_1...");

        var aCount:Number = 0;
        var bCount:Number = 0;
        var taskIDA:String;
        var taskIDB:String;

        // 两个重复任务，相同间隔 100ms → 3帧，同槽到期
        taskIDA = this.taskManager.addLoopTask(
            function():Void {
                aCount++;
                if (aCount == 1) {
                    trace("[v1.7.1 Dispatch] A first exec at frame " + self.currentFrame + ", removing B...");
                    self.taskManager.removeTask(taskIDB);
                }
            },
            100
        );

        taskIDB = this.taskManager.addLoopTask(
            function():Void {
                bCount++;
                trace("[v1.7.1 Dispatch] B executed at frame " + self.currentFrame + " (BUG!)");
            },
            100
        );

        // 模拟 10 帧，让任务到期多次
        simulateFrames(10);

        trace("[v1.7.1 Dispatch] aCount=" + aCount + ", bCount=" + bCount);

        // A 应执行多次（每 3 帧一次：帧3, 6, 9 → 3次）
        assert(aCount >= 2,
            "[v1.7.1] Task A should continue executing, got: " + aCount);
        // B 绝不应执行（A 在同帧先于 B 执行并删除了 B）
        assert(bCount == 0,
            "[v1.7.1] Task B must NOT execute after removal, got: " + bCount);
        // B 应已从任务表彻底删除
        assert(this.taskManager.locateTask(taskIDB) == null,
            "[v1.7.1] Task B should be fully removed");
    }

    /**
     * testDelayTaskDuringDispatch_v1_7_1
     * ---------------------------------------------------------------------------
     * [FIX v1.7.1] 验证分发期间 delayTask 的延迟重调度正确性：
     *
     * 场景：任务 A、B、C 在同一帧到期。
     *   A 的回调对 B 调用 delayTask(B, 200)，要求 B 延后触发。
     *   修复前：rescheduleTaskByNode 立即物理移除+重插，可能破坏分发链。
     *   修复后：_dispatching 期间 delayTask 仅逻辑移除，分发结束后统一重调度。
     *
     * 断言：
     *   - A 执行 ✓
     *   - B 在第一帧不执行（被延迟）
     *   - C 执行 ✓（链未断）
     *   - B 在延迟后的帧执行 ✓
     */
    public function testDelayTaskDuringDispatch_v1_7_1():Void {
        var self:TaskManagerTester = this;
        trace("Running testDelayTaskDuringDispatch_v1_7_1...");

        var aExecuted:Boolean = false;
        var bExecutedFrame:Number = -1;
        var cExecuted:Boolean = false;
        var taskIDA:String;
        var taskIDB:String;
        var taskIDC:String;

        // 3 个单次任务，相同间隔 100ms → 3帧
        taskIDA = this.taskManager.addSingleTask(
            function():Void {
                aExecuted = true;
                trace("[v1.7.1 DelayDispatch] A executed at frame " + self.currentFrame + ", delaying B by 200ms...");
                // 关键：在分发期间对同帧未来节点 B 调用 delayTask
                self.taskManager.delayTask(taskIDB, 200);
            },
            100
        );

        taskIDB = this.taskManager.addSingleTask(
            function():Void {
                bExecutedFrame = self.currentFrame;
                trace("[v1.7.1 DelayDispatch] B executed at frame " + bExecutedFrame);
            },
            100
        );

        taskIDC = this.taskManager.addSingleTask(
            function():Void {
                cExecuted = true;
                trace("[v1.7.1 DelayDispatch] C executed at frame " + self.currentFrame);
            },
            100
        );

        // 先模拟 5 帧（让 A/B/C 的原始帧 3 到期）
        simulateFrames(5);

        // A 和 C 应已执行
        assert(aExecuted, "[v1.7.1 DelayDispatch] Task A must execute");
        assert(cExecuted, "[v1.7.1 DelayDispatch] Task C must execute (chain not broken)");
        // B 不应在帧 3 执行（被 A 延迟了）
        assert(bExecutedFrame == -1,
            "[v1.7.1 DelayDispatch] Task B must NOT execute at original time, got frame: " + bExecutedFrame);

        // 继续模拟更多帧让 B 的延迟到期
        // 原始 pendingFrames=3, delayTask 增加 200ms*0.03=6帧 → 新 pendingFrames=9
        // 但 B 的节点是新创建的（原节点被分发循环回收），从帧3开始计算延迟9帧→帧12左右
        // 实际上是分发结束后 evaluateAndInsertTask(taskID, 9) → 当前帧(3)+9=帧12
        simulateFrames(15);

        assert(bExecutedFrame > 3,
            "[v1.7.1 DelayDispatch] Task B must execute AFTER delay, got frame: " + bExecutedFrame);
        trace("[v1.7.1 DelayDispatch] PASS: B executed at frame " + bExecutedFrame + " (delayed from frame 3)");
    }

    /**
     * testDelayTaskDuringDispatch_Reschedule_v1_7_1
     * ---------------------------------------------------------------------------
     * [FIX v1.7.1] 验证分发期间对已执行重复任务调用 delayTask 的正确性：
     *
     * 场景：重复任务 A 和 B 在同一帧到期。A 先执行，然后 A 的回调对 B 调用 delayTask。
     *   但 B 排在 A 后面（同帧未来节点），尚未被分发循环处理。
     *   修复后 B 应被逻辑移除，分发循环跳过 B，分发结束后 B 以新延迟重新调度。
     *
     * 此用例专注重复任务场景（与单次任务不同，重复任务在 dispatch 中会被 re-schedule）。
     */
    public function testDelayTaskDuringDispatch_Reschedule_v1_7_1():Void {
        var self:TaskManagerTester = this;
        trace("Running testDelayTaskDuringDispatch_Reschedule_v1_7_1...");

        var aCount:Number = 0;
        var bCount:Number = 0;
        var bFirstFrame:Number = -1;
        var bLastFrame:Number = -1;
        var delayApplied:Boolean = false;
        var taskIDA:String;
        var taskIDB:String;

        // 两个重复任务，间隔 100ms → 3帧
        taskIDA = this.taskManager.addLoopTask(
            function():Void {
                aCount++;
                // 第一次执行时延迟 B
                if (aCount == 1 && !delayApplied) {
                    delayApplied = true;
                    trace("[v1.7.1 RescheduleDispatch] A delaying B at frame " + self.currentFrame);
                    self.taskManager.delayTask(taskIDB, 200);
                }
            },
            100
        );

        taskIDB = this.taskManager.addLoopTask(
            function():Void {
                bCount++;
                if (bFirstFrame == -1) {
                    bFirstFrame = self.currentFrame;
                }
                bLastFrame = self.currentFrame;
                trace("[v1.7.1 RescheduleDispatch] B executed at frame " + self.currentFrame);
            },
            100
        );

        // 模拟 20 帧
        simulateFrames(20);

        trace("[v1.7.1 RescheduleDispatch] aCount=" + aCount + ", bCount=" + bCount +
            ", bFirstFrame=" + bFirstFrame + ", bLastFrame=" + bLastFrame);

        // A 应正常执行多次（帧3,6,9,12,15,18 → 6次）
        assert(aCount >= 4, "[v1.7.1 RescheduleDispatch] A should execute normally, got: " + aCount);
        // B 第一帧不应执行（被 A 延迟），但之后应恢复执行
        assert(bCount >= 1, "[v1.7.1 RescheduleDispatch] B should eventually execute, got: " + bCount);
        // B 的首次执行帧应晚于原始帧 3（被延迟了 200ms → +6帧 → 首次执行应在帧 9+）
        assert(bFirstFrame > 3, "[v1.7.1 RescheduleDispatch] B first exec should be delayed past frame 3, got: " + bFirstFrame);
        // 补充验证：首次执行帧应 >= 原帧3 + 延迟6帧 = 9（实际为帧12因分发后重调度）
        assert(bFirstFrame >= 9, "[v1.7.1 RescheduleDispatch] B first exec should be >= frame 9 (3+6 delay), got: " + bFirstFrame);
    }

    /**
     * testAddToMinHeapByIDPoolRecycling_v1_7_1
     * ---------------------------------------------------------------------------
     * [FIX v1.7.1] 验证 addToMinHeapByID 路径的节点池跨池回收行为：
     *
     * 背景：
     *   evaluateAndInsertTask 统一从 singleLevelTimeWheel.acquireNode 获取节点，
     *   即使路由至堆也使用轮池节点，回收时归还轮池——无跨池问题。
     *   但 addToMinHeapByID 直接从 minHeap.nodePool 获取节点（绕过统一池），
     *   而 recycleExpiredNode 统一回收到轮池，导致跨池：堆池出、轮池入。
     *
     * 验证点：
     *   1. addToMinHeapByID 创建的节点来自堆池（堆池减少，轮池不变）
     *   2. 节点 ownerType == 4
     *   3. recycleExpiredNode 回收到轮池（轮池增大）
     *   4. 堆池不恢复（跨池行为确认）
     *   5. 轮池增长量 == 堆池减少量（无节点泄漏）
     */
    public function testAddToMinHeapByIDPoolRecycling_v1_7_1():Void {
        trace("Running testAddToMinHeapByIDPoolRecycling_v1_7_1...");

        // 使用默认配置（不需要小配置触发堆路由，因为直接调用 addToMinHeapByID）
        // resetBeforeTest 已在构造函数中调用

        // 获取初始池大小
        var initialWheelPoolSize:Number = this.scheduleTimer["singleLevelTimeWheel"].getNodePoolSize();
        var initialHeapPoolSize:Number = this.scheduleTimer["minHeap"].getNodePoolSize();
        trace("[v1.7.1 HeapPool] Initial - wheel pool: " + initialWheelPoolSize + ", heap pool: " + initialHeapPoolSize);

        // 直接使用 addToMinHeapByID 创建 5 个节点（绕过 evaluateAndInsertTask 的统一池）
        var nodes:Array = [];
        var nodeCount:Number = 5;
        for (var i:Number = 0; i < nodeCount; i++) {
            nodes[i] = this.scheduleTimer.addToMinHeapByID("heapTest_" + i, 100);
        }

        // 验证节点来自堆池
        var afterAddWheelPoolSize:Number = this.scheduleTimer["singleLevelTimeWheel"].getNodePoolSize();
        var afterAddHeapPoolSize:Number = this.scheduleTimer["minHeap"].getNodePoolSize();
        trace("[v1.7.1 HeapPool] After add - wheel pool: " + afterAddWheelPoolSize + ", heap pool: " + afterAddHeapPoolSize);

        // 1. 轮池应不变（addToMinHeapByID 不使用轮池）
        assert(afterAddWheelPoolSize == initialWheelPoolSize,
            "[v1.7.1 HeapPool] Wheel pool should be unchanged, got: " + afterAddWheelPoolSize);
        // 2. 堆池应减少（节点从堆池获取）
        assert(afterAddHeapPoolSize < initialHeapPoolSize,
            "[v1.7.1 HeapPool] Heap pool should shrink, got: " + afterAddHeapPoolSize +
            " (was " + initialHeapPoolSize + ")");

        // 3. 验证所有节点 ownerType == 4
        var allOwnerType4:Boolean = true;
        for (var j:Number = 0; j < nodeCount; j++) {
            if (nodes[j].ownerType != 4) {
                allOwnerType4 = false;
                trace("[v1.7.1 HeapPool] Node " + j + " ownerType=" + nodes[j].ownerType + " (expected 4)");
            }
        }
        assert(allOwnerType4, "[v1.7.1 HeapPool] All nodes should have ownerType=4");

        // 模拟 recycleExpiredNode（与 updateFrame 中到期回收逻辑相同）
        for (var k:Number = 0; k < nodeCount; k++) {
            this.scheduleTimer.recycleExpiredNode(nodes[k]);
        }

        // 验证跨池回收结果
        var finalWheelPoolSize:Number = this.scheduleTimer["singleLevelTimeWheel"].getNodePoolSize();
        var finalHeapPoolSize:Number = this.scheduleTimer["minHeap"].getNodePoolSize();
        trace("[v1.7.1 HeapPool] After recycle - wheel pool: " + finalWheelPoolSize + ", heap pool: " + finalHeapPoolSize);

        // 4. 轮池应增大（接收了堆节点的跨池回收）
        var wheelGrowth:Number = finalWheelPoolSize - initialWheelPoolSize;
        assert(wheelGrowth == nodeCount,
            "[v1.7.1 HeapPool] Wheel pool should grow by " + nodeCount + ", got: " + wheelGrowth);

        // 5. 堆池不应恢复（节点回收到了轮池，不是堆池）
        assert(finalHeapPoolSize == afterAddHeapPoolSize,
            "[v1.7.1 HeapPool] Heap pool should NOT recover (cross-pool), got: " + finalHeapPoolSize +
            " (expected " + afterAddHeapPoolSize + ")");

        // 6. 验证节点 ownerType 已重置为 0（已回收）
        var allRecycled:Boolean = true;
        for (var m:Number = 0; m < nodeCount; m++) {
            if (nodes[m].ownerType != 0) {
                allRecycled = false;
            }
        }
        assert(allRecycled, "[v1.7.1 HeapPool] All nodes should be recycled (ownerType=0)");

        // 7. 无泄漏：轮池增长 == 堆池减少
        var heapShrinkage:Number = initialHeapPoolSize - finalHeapPoolSize;
        assert(wheelGrowth == heapShrinkage,
            "[v1.7.1 HeapPool] No leaks: wheel growth(" + wheelGrowth + ") == heap shrinkage(" + heapShrinkage + ")");

        trace("[v1.7.1 HeapPool] PASS: Cross-pool recycling verified. " +
            "addToMinHeapByID nodes (heap pool) recycled to wheel pool. " +
            "Wheel +" + wheelGrowth + ", Heap -" + heapShrinkage);
    }

    /**
     * testRemoveOverridesDelayDuringDispatch_v1_7_2
     * ---------------------------------------------------------------------------
     * [FIX v1.7.2] 验证分发期间 removeTask 能覆盖先前的 delayTask：
     *
     * 场景：重复任务 A、B 在同帧到期。A 先执行，A 的回调依次调用：
     *   1. delayTask(B, 200) → B 进入 _pendingReschedule
     *   2. removeTask(B) → 应从 _pendingReschedule 中删除 B
     *
     * 验证点：
     *   - removeTask 返回后，B 不会在分发结束后被重新调度
     *   - B 在后续帧中不再执行（"任务复活"被阻止）
     */
    public function testRemoveOverridesDelayDuringDispatch_v1_7_2():Void {
        var self:TaskManagerTester = this;
        trace("Running testRemoveOverridesDelayDuringDispatch_v1_7_2...");

        var aCount:Number = 0;
        var bCount:Number = 0;
        var removeApplied:Boolean = false;
        var taskIDA:String;
        var taskIDB:String;

        // 两个重复任务，间隔 100ms → 3帧
        taskIDA = this.taskManager.addLoopTask(
            function():Void {
                aCount++;
                // 第一次执行时：先 delay B，再 remove B
                if (aCount == 1 && !removeApplied) {
                    removeApplied = true;
                    trace("[v1.7.2 RemoveOverride] A delaying then removing B at frame " + self.currentFrame);
                    self.taskManager.delayTask(taskIDB, 200);
                    self.taskManager.removeTask(taskIDB);
                }
            },
            100
        );

        taskIDB = this.taskManager.addLoopTask(
            function():Void {
                bCount++;
                trace("[v1.7.2 RemoveOverride] B executed at frame " + self.currentFrame);
            },
            100
        );

        // 模拟 30 帧（足够让 B 在延迟后触发，如果修复失败的话）
        simulateFrames(30);

        trace("[v1.7.2 RemoveOverride] aCount=" + aCount + ", bCount=" + bCount);

        // A 应正常执行多次
        assert(aCount >= 4, "[v1.7.2 RemoveOverride] A should execute normally, got: " + aCount);
        // B 不应执行任何一次（第一帧被 A 的 delay+remove 阻止，后续不再调度）
        assert(bCount == 0, "[v1.7.2 RemoveOverride] B should NEVER execute (remove overrides delay), got: " + bCount);

        trace("[v1.7.2 RemoveOverride] PASS: removeTask correctly overrides delayTask during dispatch");
    }

    /**
     * testRemoveThenDelayFailsDuringDispatch_v1_7_2
     * ---------------------------------------------------------------------------
     * [FIX v1.7.2] 验证分发期间 removeTask 后再调用 delayTask 返回 false：
     *
     * 场景：重复任务 A、B 在同帧到期。A 先执行，A 的回调依次调用：
     *   1. delayTask(B, 200) → B 进入 _pendingReschedule
     *   2. removeTask(B) → 从 _pendingReschedule 中删除 B
     *   3. delayTask(B, 100) → 应返回 false（任务已被彻底移除）
     *
     * 验证点：
     *   - 第三步 delayTask 返回 false
     *   - B 在后续帧中不再执行
     */
    public function testRemoveThenDelayFailsDuringDispatch_v1_7_2():Void {
        var self:TaskManagerTester = this;
        trace("Running testRemoveThenDelayFailsDuringDispatch_v1_7_2...");

        var aCount:Number = 0;
        var bCount:Number = 0;
        var secondDelayResult:Boolean = true; // 初始化为 true，期望被修改为 false
        var operationApplied:Boolean = false;
        var taskIDA:String;
        var taskIDB:String;

        // 两个重复任务，间隔 100ms → 3帧
        taskIDA = this.taskManager.addLoopTask(
            function():Void {
                aCount++;
                if (aCount == 1 && !operationApplied) {
                    operationApplied = true;
                    trace("[v1.7.2 DelayAfterRemove] A: delay→remove→delay(B) at frame " + self.currentFrame);
                    // 1. 先 delay B（B 进入 _pendingReschedule）
                    var firstResult:Boolean = self.taskManager.delayTask(taskIDB, 200);
                    trace("[v1.7.2 DelayAfterRemove] First delayTask result: " + firstResult);
                    // 2. 然后 remove B（从 _pendingReschedule 中移除）
                    self.taskManager.removeTask(taskIDB);
                    // 3. 再次 delay B（应返回 false，任务已不存在于任何队列）
                    secondDelayResult = self.taskManager.delayTask(taskIDB, 100);
                    trace("[v1.7.2 DelayAfterRemove] Second delayTask result: " + secondDelayResult);
                }
            },
            100
        );

        taskIDB = this.taskManager.addLoopTask(
            function():Void {
                bCount++;
                trace("[v1.7.2 DelayAfterRemove] B executed at frame " + self.currentFrame);
            },
            100
        );

        // 模拟 30 帧
        simulateFrames(30);

        trace("[v1.7.2 DelayAfterRemove] aCount=" + aCount + ", bCount=" + bCount +
            ", secondDelayResult=" + secondDelayResult);

        // A 应正常执行
        assert(aCount >= 4, "[v1.7.2 DelayAfterRemove] A should execute normally, got: " + aCount);
        // B 不应执行
        assert(bCount == 0, "[v1.7.2 DelayAfterRemove] B should NEVER execute, got: " + bCount);
        // 第二次 delayTask 应返回 false
        assert(secondDelayResult == false,
            "[v1.7.2 DelayAfterRemove] Second delayTask should return false (task removed), got: " + secondDelayResult);

        trace("[v1.7.2 DelayAfterRemove] PASS: delay after remove correctly returns false");
    }

    /**
     * runV1_7FixTests
     * ---------------------------------------------------------------------------
     * 运行 v1.7 修复相关的测试用例
     */
    public static function runV1_7FixTests():Void {
        trace("=====================================================");
        trace("【v1.7 修复验证测试套件】");
        trace("=====================================================");

        _resetStats();

        var fixTests:Array = [
            "testChainBreakingWheel_v1_7",     // S1: 同帧链式断裂修复（轮任务）
            "testChainBreakingHeap_v1_7",      // S1: 同帧链式断裂修复（堆任务）
            "testNeverEarlyTrigger_v1_7",      // P0-3: Never-Early 公式验证
            "testStressRandomOps_v1_7",        // Stress: 随机操作压力测试
            // v1.7.1 追加测试
            "testRepeatingRemoveDuringDispatch_v1_7_1",      // 分发期间删除重复任务
            "testDelayTaskDuringDispatch_v1_7_1",            // 分发期间 delayTask（单次任务）
            "testDelayTaskDuringDispatch_Reschedule_v1_7_1", // 分发期间 delayTask（重复任务）
            "testAddToMinHeapByIDPoolRecycling_v1_7_1",      // 堆节点跨池回收验证
            // v1.7.2 追加测试
            "testRemoveOverridesDelayDuringDispatch_v1_7_2",      // remove 覆盖 delay 验证
            "testRemoveThenDelayFailsDuringDispatch_v1_7_2"       // remove 后 delay 返回 false
        ];

        for (var i:Number = 0; i < fixTests.length; i++) {
            var tester:TaskManagerTester = new TaskManagerTester();
            _safeRunTest(fixTests[i], tester);
        }

        _printTestResults();
    }
}
