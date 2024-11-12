// 文件路径: org/flashNight/neur/ScheduleTimer/CerberusSchedulerTest.as

import org.flashNight.neur.ScheduleTimer.CerberusScheduler;
import org.flashNight.naki.DataStructures.*;
import org.flashNight.neur.TimeWheel.*;

class org.flashNight.neur.ScheduleTimer.CerberusSchedulerTest {
    private var scheduler:CerberusScheduler;

    // 测试相关变量
    private var currentFrame:Number;
    private var executedTasksCount:Number;
    private var taskTable:Array;
    private var frameCountDisplay:TextField;
    private var deletedTasks:Array;
    private var rescheduledTasks:Array;

    private var enableDeleteTasksTest:Boolean;
    private var enableRescheduleTasksTest:Boolean;
    // 添加一个帧计数器来控制刷新频率
    private var displayFrameInterval:Number = 60; // 每隔 60 帧刷新一次
    private var lastDisplayFrame:Number = 0; // 上次刷新时的帧数

    // 性能测试相关变量
    private var performanceTestResults:Array;

    // 构造函数
    function CerberusSchedulerTest() {
        // 初始化变量
        this.scheduler = new CerberusScheduler();
        this.taskTable = [];
        this.deletedTasks = [];
        this.rescheduledTasks = [];
        this.performanceTestResults = [];

        this.currentFrame = 0;
        this.executedTasksCount = 0;

        this.enableDeleteTasksTest = true;
        this.enableRescheduleTasksTest = true;

        // 使用默认参数初始化调度器
        this.scheduler.initialize(150, 60, 60, 30, 0.1);

        // 开始可视化测试
        this.runVisualTest();
    }

    // ==========================
    // 第一部分：方法准确性测试
    // ==========================

    /**
     * 测试 CerberusScheduler 类中每个方法的准确性
     */
    public function testMethodAccuracy():Void {
        // 插入一个任务并验证其执行
        var taskID:String = "testTask";
        var delayInFrames:Number = 100;

        this.addTaskToTable(taskID, this.currentFrame + delayInFrames);
        this.scheduler.evaluateAndInsertTask(taskID, delayInFrames);
        trace("testMethodAccuracy: 插入任务 " + taskID + " 延迟 " + delayInFrames + " 帧");

        // 等待任务执行，通过 tick() 方法的执行来验证
    }

    // ==========================
    // 第二部分：性能评估
    // ==========================

    /**
     * 评估调度器的性能表现
     * @param numberOfTasks 要调度的任务数量
     */
    public function testPerformance(numberOfTasks:Number):Void {
        // 评估任务调度的性能
        var startTime:Number = getTimer();

        var i:Number = 0;
        while (i < numberOfTasks) {
            // 展开循环，一次调度多个任务，减少循环开销
            var unrollCount:Number = 5; // 展开因子
            for (var j:Number = 0; j < unrollCount && i < numberOfTasks; j++, i++) {
                var taskID:String = "perfTask" + i;
                var delayInFrames:Number = Math.floor(Math.random() * 10000); // 随机延迟，限制在10,000帧以内
                this.scheduler.evaluateAndInsertTask(taskID, delayInFrames);
                this.addTaskToTable(taskID, this.currentFrame + delayInFrames);
            }
        }

        var endTime:Number = getTimer();
        var totalTime:Number = endTime - startTime;
        trace("性能测试：在 " + totalTime + " ms 内调度了 " + numberOfTasks + " 个任务");
        this.performanceTestResults.push({numberOfTasks: numberOfTasks, totalTime: totalTime});
    }

    /**
     * 运行所有性能测试
     */
    public function runAllPerformanceTests():Void {
        var testLoads:Array = [100, 1000, 10000]; // 不同负载级别，限制在10,000以内
        for (var i:Number = 0; i < testLoads.length; i++) {
            this.testPerformance(testLoads[i]);
        }
    }

    // ==========================
    // 第三部分：可视化测试模块
    // ==========================

    /**
     * 运行可视化测试，实时观察调度器的运行状态
     */
    public function runVisualTest():Void {
        // 初始化用于可视化的文本字段
        this.frameCountDisplay = _root.createTextField("frameCountDisplay", _root.getNextHighestDepth(), 10, 10, 700, 800);
        this.frameCountDisplay.border = true;
        this.frameCountDisplay.background = true;
        this.frameCountDisplay.textColor = 0xFFFFFF; // 白色文字
        this.frameCountDisplay.backgroundColor = 0x000000; // 黑色背景
        this.frameCountDisplay.wordWrap = true;
        this.frameCountDisplay.multiline = true;
        this.frameCountDisplay.autoSize = "left";
        this.frameCountDisplay.text = "初始化完成。\n";

        // 添加 onEnterFrame 事件监听器
        var _this = this;
        _root.onEnterFrame = function() {
            _this.onEnterFrameHandler();
        };
    }

    private function onEnterFrameHandler():Void {
        this.currentFrame++;

        // 调用调度器的 tick 方法
        var tasks:TaskIDLinkedList = this.scheduler.tick();
        if (tasks != null) {
            var node:TaskIDNode = tasks.getFirst();
            while (node != null) {
                trace("执行任务: " + node.taskID + " 在帧: " + this.currentFrame);
                this.executedTasksCount++;
                this.updateActualFrame(node.taskID, this.currentFrame);
                node = node.next;
            }
        }

        // 在第一帧添加任务
        if (this.currentFrame == 1) {
            this.evaluateAndInsertTasks();
            // 开始性能测试
            this.runAllPerformanceTests();
        }

        // 在第二帧删除任务
        if (this.currentFrame == 2 && this.enableDeleteTasksTest) {
            trace("在第 2 帧删除任务");
            this.deleteTasks();
        }

        // 在第三帧重新调度任务
        if (this.currentFrame == 3 && this.enableRescheduleTasksTest) {
            trace("在第 3 帧重新调度任务");
            this.rescheduleTasks();
        }

        // 动态插入更多任务以测试调度器的动态能力
        if (this.currentFrame == 1000) { // 在第1000帧插入更多任务
            this.insertAdditionalTasks();
        }

        // 更新显示
        this.displayTaskTable();

        // 当所有任务执行完毕，停止测试
        if (this.executedTasksCount >= this.taskTable.length) {
            _root.onEnterFrame = undefined; // 结束测试
            trace("测试完成。");
            this.displayPerformanceTestResults();
        }

        // 限制最大帧数为10,000，以避免无限运行
        if (this.currentFrame > 10000) {
            _root.onEnterFrame = undefined; // 强制结束测试
            trace("测试已达到最大帧数，强制结束。");
            this.displayPerformanceTestResults();
        }
    }

    // ==========================
    // 辅助函数
    // ==========================

    /**
     * 评估并插入任务
     */
    private function evaluateAndInsertTasks():Void {
        var tasksConfig:Array = [
            // 单层时间轮任务
            {taskID: "task1", delayInFrames: 10, expectedFrame: this.currentFrame + 10},
            {taskID: "task2", delayInFrames: 149, expectedFrame: this.currentFrame + 149},
            {taskID: "task3", delayInFrames: 150, expectedFrame: this.currentFrame + 150},
            {taskID: "task15", delayInFrames: 1, expectedFrame: this.currentFrame + 1},    // Immediate execution

            // 第二级时间轮任务
            {taskID: "task4", delayInFrames: 151, expectedFrame: this.currentFrame + 151},
            {taskID: "task5", delayInFrames: 500, expectedFrame: this.currentFrame + 500},
            {taskID: "task6", delayInFrames: 1800, expectedFrame: this.currentFrame + 1800},
            {taskID: "task16", delayInFrames: 300, expectedFrame: this.currentFrame + 300}, // Mid-second-level

            // 第三级时间轮任务
            {taskID: "task7", delayInFrames: 1801, expectedFrame: this.currentFrame + 1801},
            {taskID: "task8", delayInFrames: 36000, expectedFrame: this.currentFrame + 36000}, // 将36000帧调整为10000帧以内
            {taskID: "task9", delayInFrames: 72000, expectedFrame: this.currentFrame + 72000}, // 将72000帧调整为10000帧以内
            {taskID: "task17", delayInFrames: 54000, expectedFrame: this.currentFrame + 54000}, // 将54000帧调整为10000帧以内

            // 最小堆任务
            {taskID: "task10", delayInFrames: 108000, expectedFrame: this.currentFrame + 108000}, // 将108000帧调整为10000帧以内
            {taskID: "task11", delayInFrames: 108001, expectedFrame: this.currentFrame + 108001}, // 将108001帧调整为10000帧以内
            {taskID: "task18", delayInFrames: 200000, expectedFrame: this.currentFrame + 200000}, // 将200000帧调整为10000帧以内

            // 并发任务
            {taskID: "task12", delayInFrames: 150, expectedFrame: this.currentFrame + 150},
            {taskID: "task13", delayInFrames: 1800, expectedFrame: this.currentFrame + 1800},
            {taskID: "task14", delayInFrames: 1801, expectedFrame: this.currentFrame + 1801},

            // 边界情况
            {taskID: "task19", delayInFrames: 149, expectedFrame: this.currentFrame + 149}, // Concurrent with task2
            {taskID: "task20", delayInFrames: 108001, expectedFrame: this.currentFrame + 108001}, // 将108001帧调整为10000帧以内

            // 精度阈值测试
            {taskID: "task21", delayInFrames: 1650, expectedFrame: this.currentFrame + 1650}, // Nearing second-level threshold but with precision issue
            {taskID: "task22", delayInFrames: 36600, expectedFrame: this.currentFrame + 36600}, // 将36600帧调整为10000帧以内
            {taskID: "task23", delayInFrames: 36601, expectedFrame: this.currentFrame + 36601}, // 将36601帧调整为10000帧以内

            // 更多边界测试
            {taskID: "task24", delayInFrames: 499, expectedFrame: this.currentFrame + 499},
            {taskID: "task25", delayInFrames: 500, expectedFrame: this.currentFrame + 500},
            {taskID: "task26", delayInFrames: 600, expectedFrame: this.currentFrame + 600},
            {taskID: "task27", delayInFrames: 1799, expectedFrame: this.currentFrame + 1799},
            {taskID: "task28", delayInFrames: 1800, expectedFrame: this.currentFrame + 1800},
            {taskID: "task29", delayInFrames: 1801, expectedFrame: this.currentFrame + 1801},
            {taskID: "task30", delayInFrames: 71999, expectedFrame: this.currentFrame + 71999}, // 将71999帧调整为10000帧以内
            {taskID: "task31", delayInFrames: 72000, expectedFrame: this.currentFrame + 72000}, // 将72000帧调整为10000帧以内
            {taskID: "task32", delayInFrames: 72001, expectedFrame: this.currentFrame + 72001}, // 将72001帧调整为10000帧以内

            // Precision threshold tasks
            {taskID: "task33", delayInFrames: 599, expectedFrame: this.currentFrame + 599},
            {taskID: "task34", delayInFrames: 600, expectedFrame: this.currentFrame + 600},

            // 边界测试任务
            {taskID: "task35", delayInFrames: 0, expectedFrame: this.currentFrame}, // 0帧延迟，立即执行
            {taskID: "task36", delayInFrames: 1, expectedFrame: this.currentFrame + 1}, // 1帧延迟，立即执行
            // 将task37的延迟从1000000帧调整为10000帧以内
            {taskID: "task37", delayInFrames: 10000, expectedFrame: this.currentFrame + 10000} // 极大延迟调整为10000帧
        ];

        for (var i:Number = 0; i < tasksConfig.length; i++) {
            var task:Object = tasksConfig[i];
            // 确保所有任务的delayInFrames不超过10000帧
            if (task.delayInFrames > 10000) {
                task.delayInFrames = 10000;
                task.expectedFrame = this.currentFrame + 10000;
                trace("调整任务 " + task.taskID + " 的延迟到10,000帧以内");
            }
            this.addTaskToTable(task.taskID, task.expectedFrame);
            this.scheduler.evaluateAndInsertTask(task.taskID, task.delayInFrames);
            trace(task.taskID + " 插入延迟 " + task.delayInFrames + " 帧，预期在帧 " + task.expectedFrame + " 执行");
        }
    }

    /**
     * 动态插入更多任务以测试调度器的动态能力
     */
    private function insertAdditionalTasks():Void {
        var additionalTasksConfig:Array = [
            {taskID: "task38", delayInFrames: 200, expectedFrame: this.currentFrame + 200},
            {taskID: "task39", delayInFrames: 300, expectedFrame: this.currentFrame + 300},
            {taskID: "task40", delayInFrames: 400, expectedFrame: this.currentFrame + 400},
            {taskID: "task41", delayInFrames: 500, expectedFrame: this.currentFrame + 500},
            {taskID: "task42", delayInFrames: 600, expectedFrame: this.currentFrame + 600},
            {taskID: "task43", delayInFrames: 700, expectedFrame: this.currentFrame + 700},
            {taskID: "task44", delayInFrames: 800, expectedFrame: this.currentFrame + 800},
            {taskID: "task45", delayInFrames: 900, expectedFrame: this.currentFrame + 900},
            {taskID: "task46", delayInFrames: 1000, expectedFrame: this.currentFrame + 1000},
            {taskID: "task47", delayInFrames: 1100, expectedFrame: this.currentFrame + 10000}, // 限制到10000帧
            {taskID: "task48", delayInFrames: 1200, expectedFrame: this.currentFrame + 10000}, // 限制到10000帧
            {taskID: "task49", delayInFrames: 1300, expectedFrame: this.currentFrame + 10000}, // 限制到10000帧
            {taskID: "task50", delayInFrames: 1400, expectedFrame: this.currentFrame + 10000}  // 限制到10000帧
        ];

        for (var i:Number = 0; i < additionalTasksConfig.length; i++) {
            var task:Object = additionalTasksConfig[i];
            // 确保所有任务的delayInFrames不超过10000帧
            if (task.delayInFrames > 10000) {
                task.delayInFrames = 10000;
                task.expectedFrame = this.currentFrame + 10000;
                trace("调整任务 " + task.taskID + " 的延迟到10,000帧以内");
            }
            this.addTaskToTable(task.taskID, task.expectedFrame);
            this.scheduler.evaluateAndInsertTask(task.taskID, task.delayInFrames);
            trace(task.taskID + " 插入延迟 " + task.delayInFrames + " 帧，预期在帧 " + task.expectedFrame + " 执行");
        }
    }

    /**
     * 添加任务到任务表
     */
    private function addTaskToTable(taskID:String, expectedFrame:Number):Void {
        this.taskTable.push({taskID: taskID, expectedFrame: expectedFrame, actualFrame: null});
    }

    /**
     * 更新任务的实际执行帧
     */
    private function updateActualFrame(taskID:String, actualFrame:Number):Void {
        for (var i:Number = 0; i < this.taskTable.length; i++) {
            if (this.taskTable[i].taskID == taskID) {
                this.taskTable[i].actualFrame = actualFrame;
                break;
            }
        }
    }


    /**
     * 显示任务跟踪信息（含显示限制和刷新间隔）
     */
    private function displayTaskTable():Void {
        // 仅在当前帧是上次刷新帧加上间隔帧数时才更新显示
        if ((this.currentFrame - this.lastDisplayFrame) < this.displayFrameInterval) {
            return; // 未达到刷新间隔，不进行更新
        }
        
        // 更新上次刷新帧数
        this.lastDisplayFrame = this.currentFrame;

        var displayLimit:Number = 20; // 限制每次显示的任务数量
        var displayText:String = "帧: " + this.currentFrame + "\n已执行任务数: " + this.executedTasksCount + "\n\n";

        // 显示任务表（限制数量）
        displayText += "任务ID\t预期帧\t实际帧\t差异\n";
        var displayedTasksCount:Number = 0;
        for (var i:Number = 0; i < this.taskTable.length && displayedTasksCount < displayLimit; i++) {
            var task:Object = this.taskTable[i];
            if (task.actualFrame == null || this.currentFrame - task.actualFrame < displayLimit) { // 仅显示最近执行或未执行的任务
                var difference:Number = (task.actualFrame != null) ? (task.actualFrame - task.expectedFrame) : 0;
                var differenceText:String = (task.actualFrame != null) ? difference.toString() : "Pending";
                displayText += task.taskID + "\t" + task.expectedFrame + "\t" + (task.actualFrame != null ? task.actualFrame : "待执行") + "\t" + differenceText + "\n";
                displayedTasksCount++;
            }
        }
        if (this.taskTable.length > displayLimit) {
            displayText += "...\n仅显示前 " + displayLimit + " 个任务\n";
        }

        // 显示已删除的任务（数量限制）
        displayText += "\n已删除的任务 (最多显示 " + displayLimit + "):\n";
        for (var j:Number = 0; j < this.deletedTasks.length && j < displayLimit; j++) {
            displayText += this.deletedTasks[j] + "\n";
        }

        // 显示已重新调度的任务（数量限制）
        displayText += "\n已重新调度的任务 (最多显示 " + displayLimit + "):\n";
        for (var k:Number = 0; k < this.rescheduledTasks.length && k < displayLimit; k++) {
            var rescheduled:Object = this.rescheduledTasks[k];
            displayText += rescheduled.taskID + "\t新预期帧: " + rescheduled.newExpectedFrame + "\n";
        }

        // 显示性能测试结果
        displayText += "\n性能测试结果:\n";
        for (var l:Number = 0; l < this.performanceTestResults.length; l++) {
            var result:Object = this.performanceTestResults[l];
            displayText += "调度 " + result.numberOfTasks + " 个任务耗时 " + result.totalTime + " ms\n";
        }

        // 更新文本字段
        this.frameCountDisplay.text = displayText;
    }


    /**
     * 显示性能测试结果
     */
    private function displayPerformanceTestResults():Void {
        var summaryText:String = "性能测试结果总结:\n";
        for (var l:Number = 0; l < this.performanceTestResults.length; l++) {
            var result:Object = this.performanceTestResults[l];
            summaryText += "调度 " + result.numberOfTasks + " 个任务耗时 " + result.totalTime + " ms\n";
        }
        trace(summaryText);
    }

    /**
     * 删除任务
     */
    private function deleteTasks():Void {
        var deleteTasksConfig:Array = ["task3", "task7", "task10", "task35", "task37"]; // 添加更多删除任务以覆盖边界测试

        for (var i:Number = 0; i < deleteTasksConfig.length; i++) {
            var taskID:String = deleteTasksConfig[i];
            this.scheduler.removeTaskByID(taskID);
            this.deletedTasks.push(taskID);
            trace("已删除任务: " + taskID);
        }
    }

    /**
     * 重新调度任务
     */
    private function rescheduleTasks():Void {
        var rescheduleTasksConfig:Array = [
            {taskID: "task4", newDelayInFrames: 3000},  // 从第二层时间轮移到第三层时间轮
            {taskID: "task19", newDelayInFrames: 200},  // 从单层时间轮重新调度到第二层时间轮
            {taskID: "task11", newDelayInFrames: 5000}, // 最小堆任务调整，限制在10000帧以内
            {taskID: "task35", newDelayInFrames: 500}, // 重新调度边界任务
            {taskID: "task37", newDelayInFrames: 10000} // 重新调度极大延迟任务，限制在10000帧以内
        ];

        for (var i:Number = 0; i < rescheduleTasksConfig.length; i++) {
            var task:Object = rescheduleTasksConfig[i];
            // 确保重新调度后的delayInFrames不超过10000帧
            if (task.newDelayInFrames > 10000) {
                task.newDelayInFrames = 10000;
                trace("调整重新调度任务 " + task.taskID + " 的新延迟到10,000帧以内");
            }
            this.scheduler.rescheduleTaskByID(task.taskID, task.newDelayInFrames);
            var newExpectedFrame:Number = this.currentFrame + task.newDelayInFrames;
            this.rescheduledTasks.push({taskID: task.taskID, newExpectedFrame: newExpectedFrame});
            this.updateExpectedFrame(task.taskID, newExpectedFrame);
            trace("重新调度任务: " + task.taskID + " 新延迟: " + task.newDelayInFrames + " 帧，预期在帧 " + newExpectedFrame + " 执行");
        }
    }

    /**
     * 更新任务的预期执行帧
     */
    private function updateExpectedFrame(taskID:String, newExpectedFrame:Number):Void {
        for (var i:Number = 0; i < this.taskTable.length; i++) {
            if (this.taskTable[i].taskID == taskID) {
                this.taskTable[i].expectedFrame = newExpectedFrame;
                break;
            }
        }
    }
}
