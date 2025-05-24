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
    // 累积的断言结果数组，每个项格式：{passed:Boolean, message:String, frame:Number}
    private var assertions:Array;
    // 额外日志数组（可记录重要调试信息）
    private var logs:Array;

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
     * 在每个测试用例运行前调用，重置当前帧、断言、日志、任务调度器和 TaskManager 实例，
     * 从而确保测试环境隔离，避免多个测试间数据混淆。
     */
    private function resetBeforeTest():Void {
        this.currentFrame = 0;
        this.assertions = [];
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
     * 模拟 numFrames 帧的更新，每帧调用 TaskManager.updateFrame() 更新任务，
     * 同时累计帧数，并每 5 帧输出一次调试信息。
     *
     * @param numFrames 要模拟的帧数。
     */
    private function simulateFrames(numFrames:Number):Void {
        for (var i:Number = 0; i < numFrames; i++) {
            this.currentFrame++;
            this.taskManager.updateFrame();
            // 每 5 帧输出一次调试信息
            if (this.currentFrame % 5 == 0) {
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
     * 添加一条断言结果到 assertions 数组，并在断言失败时输出详细调试信息。
     *
     * @param condition 断言条件，true 表示通过
     * @param message 断言失败时的错误提示
     */
    private function assert(condition:Boolean, message:String):Void {
        this.assertions.push({ passed: condition, message: message, frame: this.currentFrame });
        if (!condition) {
            trace("Assertion failed at frame " + this.currentFrame + ": " + message);
        }
    }

    /**
     * printAssertions
     * ---------------------------------------------------------------------------
     * 输出所有断言结果中未通过的项，便于整体了解测试中的失败情况。
     */
    public function printAssertions():Void {
        for (var i:Number = 0; i < this.assertions.length; i++) {
            var result = this.assertions[i];
            if (!result.passed) {
                trace("Assertion failed: " + result.message + " (at frame " + result.frame + ")");
            }
        }
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
                trace("Non-numeric delay task executed at frame " + self.currentFrame);
            },
            100
        );
        // 使用非数字参数 true 进行延迟
        this.taskManager.delayTask(taskID, true);
        simulateFrames(10);
        assert(!executed, "Task with non-numeric delay (true) should not execute");
        // 通过反射检查内部 pendingFrames（仅供调试）
        var taskObj:Task = this.taskManager.locateTask(taskID);
        if (taskObj != null) {
            trace("Non-numeric delay task pendingFrames: " + taskObj.pendingFrames);
            assert(taskObj.pendingFrames == Infinity, "PendingFrames should be Infinity for non-numeric delay true");
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
     * runAllTests
     * ---------------------------------------------------------------------------
     * 运行所有测试用例，每个测试用例在独立的测试环境中执行，最后输出所有断言结果和调试日志。
     */
    public static function runAllTests():Void {
        trace("Starting TaskManager tests...");
        var tests:Array = [
            "testAddSingleTask", "testAddLoopTask", "testAddOrUpdateTask",
            "testAddLifecycleTask", "testRemoveTask", "testLocateTask",
            "testDelayTask", "testDelayTaskNonNumeric", "testZeroIntervalTask",
            "testNegativeIntervalTask", "testZeroRepeatCount", "testNegativeRepeatCount",
            "testTaskIDUniqueness", "testMixedScenarios", "testConcurrentTasks"
        ];
        for (var i:Number = 0; i < tests.length; i++) {
            trace("-----------------------------------------------------");
            var tester:TaskManagerTester = new TaskManagerTester();
            var methodName:String = tests[i];
            tester[methodName]();
            tester.printAssertions();
            trace("-----------------------------------------------------");
        }
        trace("All tests completed.");
    }
}
