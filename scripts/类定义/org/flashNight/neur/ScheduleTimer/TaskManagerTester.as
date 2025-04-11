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
 *  1. 模拟多帧更新，调用 TaskManager.updateFrame()，不依赖 MovieClip.onEnterFrame 事件。
 *  2. 为各测试用例提供详细的日志输出，包括当前帧数、重要变量状态以及内部任务表状态。
 *  3. 提供 assert 方法记录每个断言的结果，并在测试结束时统一输出所有失败断言。
 *
 * 注意：
 *  - 为了调试目的，部分私有属性（如 taskTable 和 zeroFrameTasks）通过 bracket 语法来获取内部状态，
 *    请确保编译环境允许反射读取私有属性。
 */
class org.flashNight.neur.ScheduleTimer.TaskManagerTester {
    // 外部任务调度器实例
    private var scheduleTimer:CerberusScheduler;
    // TaskManager 实例
    private var taskManager:TaskManager;
    // 当前帧率（与项目帧计时器一致）
    private var frameRate:Number = 30;
    // 当前帧数计数
    private var currentFrame:Number = 0;
    // 累积的断言结果数组，每个项格式：{passed:Boolean, message:String}
    private var assertions:Array;
    // 额外日志数组（可记录重要调试信息）
    private var logs:Array;

    /**
     * 构造函数
     * -----------------------------------------------------------------------------
     * 初始化 CerberusScheduler、TaskManager，并设置初始参数。
     */
    public function TaskManagerTester() {
        // 初始化调度器
        this.scheduleTimer = new CerberusScheduler();
        var singleWheelSize:Number = 150;
        var multiLevelSecondsSize:Number = 60;
        var multiLevelMinutesSize:Number = 60;
        var precisionThreshold:Number = 0.1;
        this.scheduleTimer.initialize(singleWheelSize, multiLevelSecondsSize, multiLevelMinutesSize, this.frameRate, precisionThreshold);
        
        // 初始化 TaskManager，传入调度器与帧率
        this.taskManager = new TaskManager(this.scheduleTimer, this.frameRate);
        
        // 初始化断言和日志数组
        this.assertions = [];
        this.logs = [];
    }

    /**
     * simulateFrames
     * -----------------------------------------------------------------------------
     * 模拟 n 帧的更新，每帧调用 TaskManager.updateFrame() 并累计帧数，同时输出调试日志。
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
     * -----------------------------------------------------------------------------
     * 输出当前帧数及 TaskManager 内部状态（正常调度任务和零帧任务的键列表）。
     * 利用反射方式获取私有属性。
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
     * -----------------------------------------------------------------------------
     * 添加一条断言结果到 assertions 数组，并在断言不通过时输出详细调试信息。
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
     * -----------------------------------------------------------------------------
     * 输出所有断言结果中未通过的项。
     */
    private function printAssertions():Void {
        for (var i:Number = 0; i < this.assertions.length; i++) {
            var result = this.assertions[i];
            if (!result.passed) {
                trace("Assertion failed: " + result.message + " (at frame " + result.frame + ")");
            }
        }
    }

    // ----------------------------
    // 基本功能测试
    // ----------------------------

    /**
     * testAddSingleTask
     * -----------------------------------------------------------------------------
     * 测试添加单次任务：
     *  - 延迟 100ms 后执行，且任务执行后应被移除（locateTask 返回 null）。
     */
    public function testAddSingleTask():Void {
        trace("Running testAddSingleTask...");
        var executed:Boolean = false;
        var taskID:String = this.taskManager.addSingleTask(function():Void {
            executed = true;
            trace("Single task executed at frame " + this.currentFrame);
        }, 100); // 延迟 100ms
        
        // 模拟 10 帧（约 333ms，足以覆盖 100ms 延迟）
        this.simulateFrames(10);
        
        this.assert(executed, "Single task should execute after specified delay");
        this.assert(this.taskManager.locateTask(taskID) == null, "Single task should be removed after execution");
    }

    /**
     * testAddLoopTask
     * -----------------------------------------------------------------------------
     * 测试添加循环任务：
     *  - 延迟 50ms 执行，模拟 20 帧后任务应执行多次。
     */
    public function testAddLoopTask():Void {
        trace("Running testAddLoopTask...");
        var count:Number = 0;
        var taskID:String = this.taskManager.addLoopTask(function():Void {
            count++;
            trace("Loop task executed, count=" + count + " at frame " + this.currentFrame);
        }, 50); // 每 50ms 执行一次
        
        // 模拟 20 帧（约 666ms）
        this.simulateFrames(20);
        
        this.assert(count > 1, "Loop task should execute multiple times, actual count=" + count);
        // 移除循环任务，防止对后续测试产生影响
        this.taskManager.removeTask(taskID);
    }

    /**
     * testAddOrUpdateTask
     * -----------------------------------------------------------------------------
     * 测试添加或更新任务：
     *  - 首次添加后任务应能执行且任务ID存入对象属性；
     *  - 更新任务后应采用新的回调执行。
     */
    public function testAddOrUpdateTask():Void {
        trace("Running testAddOrUpdateTask...");
        var obj:Object = {};
        var executed:Boolean = false;
        var taskID:String = this.taskManager.addOrUpdateTask(obj, "testLabel", function():Void {
            executed = true;
            trace("First callback executed at frame " + this.currentFrame);
        }, 100);
        
        this.simulateFrames(10);
        this.assert(executed, "AddOrUpdateTask should execute the task (first callback)");
        this.assert(obj.taskLabel["testLabel"] == taskID, "Task ID should be stored in object's taskLabel");
        
        // 更新任务：新回调设置
        var newExecuted:Boolean = false;
        this.taskManager.addOrUpdateTask(obj, "testLabel", function():Void {
            newExecuted = true;
            trace("Updated callback executed at frame " + this.currentFrame);
        }, 50);
        
        this.simulateFrames(10);
        this.assert(newExecuted, "Updated task should execute with new action");
    }

    /**
     * testAddLifecycleTask
     * -----------------------------------------------------------------------------
     * 测试添加生命周期任务：
     *  - 任务为无限循环任务，会多次执行；
     *  - 模拟对象卸载后任务自动清除，且对象内任务标识被移除。
     */
    public function testAddLifecycleTask():Void {
        trace("Running testAddLifecycleTask...");
        var obj:Object = {};
        var count:Number = 0;
        var taskID:String = this.taskManager.addLifecycleTask(obj, "lifecycleLabel", function():Void {
            count++;
            trace("Lifecycle task executed, count=" + count + " at frame " + this.currentFrame);
        }, 50);
        
        // 模拟 20 帧
        this.simulateFrames(20);
        this.assert(count > 1, "Lifecycle task should execute multiple times, actual count=" + count);
        
        // 模拟对象卸载（保护性判断）
        if (typeof obj.onUnload == "function") {
            obj.onUnload();
        } else {
            trace("Warning: obj.onUnload is not defined, manually simulating unload.");
            // 手动调用卸载回调
            obj.onUnload = function():Void {};
            obj.onUnload();
        }
        // 模拟1帧以确保卸载逻辑执行
        this.simulateFrames(1);
        this.assert(this.taskManager.locateTask(taskID) == null, "Lifecycle task should be removed after unload");
        this.assert(obj.taskLabel["lifecycleLabel"] == undefined, "Task label should be cleared on unload");
    }

    /**
     * testRemoveTask
     * -----------------------------------------------------------------------------
     * 测试移除任务：
     *  - 添加单次任务后立即调用 removeTask，
     *  - 模拟多帧后任务不应执行。
     */
    public function testRemoveTask():Void {
        trace("Running testRemoveTask...");
        var executed:Boolean = false;
        var taskID:String = this.taskManager.addSingleTask(function():Void {
            executed = true;
            trace("This task should not execute.");
        }, 100);
        
        // 立即移除任务
        this.taskManager.removeTask(taskID);
        this.simulateFrames(10);
        this.assert(!executed, "Removed task should not execute");
    }

    /**
     * testLocateTask
     * -----------------------------------------------------------------------------
     * 测试任务定位：
     *  - 在任务执行前能通过 locateTask 查到任务，
     *  - 任务执行后则查不到。
     */
    public function testLocateTask():Void {
        trace("Running testLocateTask...");
        var taskID:String = this.taskManager.addSingleTask(function():Void {
            trace("LocateTask: Single task executed.");
        }, 100);
        var task:Task = this.taskManager.locateTask(taskID);
        this.assert(task != null, "Task should be locatable before execution");
        this.simulateFrames(10);
        this.assert(this.taskManager.locateTask(taskID) == null, "Task should not be locatable after execution");
    }

    /**
     * testDelayTask
     * -----------------------------------------------------------------------------
     * 测试任务延迟：
     *  - 为单次任务增加额外 50ms 延迟（总延迟 150ms），
     *  - 在延迟期间任务不执行，延迟到位后任务执行。
     */
    public function testDelayTask():Void {
        trace("Running testDelayTask...");
        var executed:Boolean = false;
        var taskID:String = this.taskManager.addSingleTask(function():Void {
            executed = true;
            trace("Delayed task executed at frame " + this.currentFrame);
        }, 100);
        
        // 为任务增加 50ms 延迟
        this.taskManager.delayTask(taskID, 50);
        
        // 模拟 3 帧（约 3 * (1000/30)=100ms左右）
        this.simulateFrames(3);
        trace("After 3 frames, delay task executed? " + executed);
        this.assert(!executed, "Task should not execute before total delay (150ms)");
        
        // 模拟 2 帧，达到总共 5 帧左右（约 166ms）
        this.simulateFrames(2);
        trace("After additional 2 frames, delay task executed? " + executed);
        this.assert(executed, "Task should execute after additional delay");
    }

    // ----------------------------
    // 边界条件测试
    // ----------------------------

    /**
     * testZeroIntervalTask
     * -----------------------------------------------------------------------------
     * 测试间隔为 0 的任务：
     *  - 应立即执行，且返回的任务ID为 null。
     */
    public function testZeroIntervalTask():Void {
        trace("Running testZeroIntervalTask...");
        var executed:Boolean = false;
        var taskID:String = this.taskManager.addSingleTask(function():Void {
            executed = true;
            trace("Zero interval task executed immediately at frame " + this.currentFrame);
        }, 0);
        this.assert(executed, "Task with zero interval should execute immediately");
        this.assert(taskID == null, "Zero interval task should return null ID");
    }

    /**
     * testNegativeIntervalTask
     * -----------------------------------------------------------------------------
     * 测试负间隔任务：
     *  - 负间隔同样应立即执行，且返回的任务ID为 null。
     */
    public function testNegativeIntervalTask():Void {
        trace("Running testNegativeIntervalTask...");
        var executed:Boolean = false;
        var taskID:String = this.taskManager.addSingleTask(function():Void {
            executed = true;
            trace("Negative interval task executed immediately at frame " + this.currentFrame);
        }, -10);
        this.assert(executed, "Task with negative interval should execute immediately");
        this.assert(taskID == null, "Negative interval task should return null ID");
    }

    /**
     * testZeroRepeatCount
     * -----------------------------------------------------------------------------
     * 测试重复次数为 0 的任务：
     *  - 任务不应执行。
     *  - 输出当前计数用于调试验证。
     */
    public function testZeroRepeatCount():Void {
        trace("Running testZeroRepeatCount...");
        var count:Number = 0;
        var taskID:String = this.taskManager.addTask(function():Void {
            count++;
            trace("Zero repeat count task executed, count=" + count + " at frame " + this.currentFrame);
        }, 50, 0);
        this.simulateFrames(10);
        trace("TestZeroRepeatCount: final count = " + count);
        this.assert(count == 0, "Task with zero repeat count should not execute, actual count=" + count);
    }

    /**
     * testNegativeRepeatCount
     * -----------------------------------------------------------------------------
     * 测试重复次数为负数的任务：
     *  - 任务同样不应执行。
     *  - 输出当前计数用于调试验证。
     */
    public function testNegativeRepeatCount():Void {
        trace("Running testNegativeRepeatCount...");
        var count:Number = 0;
        var taskID:String = this.taskManager.addTask(function():Void {
            count++;
            trace("Negative repeat count task executed, count=" + count + " at frame " + this.currentFrame);
        }, 50, -5);
        this.simulateFrames(10);
        trace("TestNegativeRepeatCount: final count = " + count);
        this.assert(count == 0, "Task with negative repeat count should not execute, actual count=" + count);
    }

    /**
     * testTaskIDUniqueness
     * -----------------------------------------------------------------------------
     * 测试任务 ID 的唯一性：
     *  - 多次添加任务应返回不同的任务ID。
     */
    public function testTaskIDUniqueness():Void {
        trace("Running testTaskIDUniqueness...");
        var taskID1:String = this.taskManager.addSingleTask(function():Void {}, 100);
        var taskID2:String = this.taskManager.addSingleTask(function():Void {}, 100);
        trace("Task IDs: " + taskID1 + ", " + taskID2);
        this.assert(taskID1 != taskID2, "Task IDs should be unique, got: " + taskID1 + " and " + taskID2);
    }

    // ----------------------------
    // 混合真实场景测试
    // ----------------------------

    /**
     * testMixedScenarios
     * -----------------------------------------------------------------------------
     * 混合测试：
     *  - 同时添加单次任务、循环任务、生命周期任务；
     *  - 模拟一定帧数后验证各任务的执行情况；
     *  - 移除循环任务后验证其停止执行；
     *  - 延迟生命周期任务后检查任务执行暂停；
     *  - 模拟对象卸载后验证生命周期任务被清除。
     */
    public function testMixedScenarios():Void {
        trace("Running testMixedScenarios...");
        var singleExecuted:Boolean = false;
        var loopCount:Number = 0;
        var lifecycleCount:Number = 0;
        var obj:Object = {};

        // 添加单次任务
        var singleTaskID:String = this.taskManager.addSingleTask(function():Void {
            singleExecuted = true;
            trace("Mixed scenario: Single task executed at frame " + this.currentFrame);
        }, 100);

        // 添加循环任务
        var loopTaskID:String = this.taskManager.addLoopTask(function():Void {
            loopCount++;
            trace("Mixed scenario: Loop task executed, count=" + loopCount + " at frame " + this.currentFrame);
        }, 50);

        // 添加生命周期任务
        var lifecycleTaskID:String = this.taskManager.addLifecycleTask(obj, "mixedLabel", function():Void {
            lifecycleCount++;
            trace("Mixed scenario: Lifecycle task executed, count=" + lifecycleCount + " at frame " + this.currentFrame);
        }, 50);

        this.simulateFrames(20);
        trace("Mixed scenario: After 20 frames, singleExecuted=" + singleExecuted + ", loopCount=" + loopCount + ", lifecycleCount=" + lifecycleCount);
        this.assert(singleExecuted, "Single task should execute once");
        this.assert(loopCount > 1, "Loop task should execute multiple times, actual count=" + loopCount);
        this.assert(lifecycleCount > 1, "Lifecycle task should execute multiple times, actual count=" + lifecycleCount);

        // 移除循环任务后
        this.taskManager.removeTask(loopTaskID);
        var prevLoopCount:Number = loopCount;
        trace("Mixed scenario: Removed loop task at frame " + this.currentFrame + ", prevLoopCount=" + prevLoopCount);
        this.simulateFrames(10);
        trace("Mixed scenario: After additional 10 frames, loopCount=" + loopCount);
        this.assert(loopCount == prevLoopCount, "Loop task should stop after removal, expected " + prevLoopCount + ", got " + loopCount);

        // 对生命周期任务增加延迟，检查是否暂停执行
        this.taskManager.delayTask(lifecycleTaskID, 100);
        var prevLifecycleCount:Number = lifecycleCount;
        trace("Mixed scenario: Delayed lifecycle task at frame " + this.currentFrame + ", prevLifecycleCount=" + prevLifecycleCount);
        this.simulateFrames(5);
        trace("Mixed scenario: After delay, lifecycleCount=" + lifecycleCount);
        this.assert(lifecycleCount == prevLifecycleCount, "Lifecycle task should pause during delay, expected " + prevLifecycleCount + ", got " + lifecycleCount);

        // 模拟对象卸载
        if (typeof obj.onUnload == "function") {
            obj.onUnload();
        } else {
            trace("Mixed scenario: obj.onUnload not defined, simulating unload manually.");
            obj.onUnload = function():Void {};
            obj.onUnload();
        }
        this.simulateFrames(1);
        this.assert(this.taskManager.locateTask(lifecycleTaskID) == null, "Lifecycle task should be removed after unload");
    }

    /**
     * runAllTests
     * -----------------------------------------------------------------------------
     * 运行所有测试用例，并在测试结束后输出所有断言结果和完整的调试日志。
     */
    public function runAllTests():Void {
        trace("Starting TaskManager tests...");
        this.testAddSingleTask();
        this.testAddLoopTask();
        this.testAddOrUpdateTask();
        this.testAddLifecycleTask();
        this.testRemoveTask();
        this.testLocateTask();
        this.testDelayTask();
        this.testZeroIntervalTask();
        this.testNegativeIntervalTask();
        this.testZeroRepeatCount();
        this.testNegativeRepeatCount();
        this.testTaskIDUniqueness();
        this.testMixedScenarios();
        trace("All tests completed.");
        this.printAssertions();
    }
}
