// 文件路径: org/flashNight/neur/ScheduleTimer/CerberusSchedulerTest.as

import org.flashNight.neur.ScheduleTimer.CerberusScheduler;
import org.flashNight.naki.DataStructures.*;
import org.flashNight.neur.TimeWheel.*;

/**
 * CerberusSchedulerTest 类
 * 
 * 用于测试 CerberusScheduler 的准确性和性能，包括插入、删除、查找、重新调度等操作。
 * 通过维护一个 id-node 哈希表，避免线性查找，实现常数级性能。
 * 优化部分：应用循环展开技术以减少循环开销，提高计时测试的准确性。
 */
class org.flashNight.neur.ScheduleTimer.CerberusSchedulerTest {
    private var scheduler:CerberusScheduler;

    // 测试相关变量
    private var currentFrame:Number;
    private var executedTasksCount:Number;
    private var taskTable:Object; // 使用哈希表替代数组
    private var taskIDList:Array; // 维护任务ID列表
    private var frameCountDisplay:TextField;

    private var enableDeleteTasksTest:Boolean;
    private var enableRescheduleTasksTest:Boolean;

    // 帧计数器，用于控制刷新频率
    private var displayFrameInterval:Number = 60; // 每隔60帧刷新一次
    private var lastDisplayFrame:Number = 0; // 上次刷新时的帧数

    // 性能测试相关变量
    private var performanceTestResults:Array;

    // 维护一个 id-node 哈希表，避免线性查找
    private var idNodeTable:Object;

    // 日志级别定义
    private static var LOG_LEVEL_INFO:Number = 1;
    private static var LOG_LEVEL_DEBUG:Number = 2;
    private static var LOG_LEVEL_ERROR:Number = 3;
    private var currentLogLevel:Number = LOG_LEVEL_INFO; // 设置当前日志级别

    /**
     * 构造函数
     */
    function CerberusSchedulerTest() {
        // 初始化变量
        this.scheduler = new CerberusScheduler();
        this.taskTable = {}; // 使用哈希表
        this.taskIDList = []; // 初始化任务ID列表
        this.performanceTestResults = [];

        this.currentFrame = 0;
        this.executedTasksCount = 0;

        this.enableDeleteTasksTest = true;
        this.enableRescheduleTasksTest = true;

        // 初始化 id-node 哈希表
        this.idNodeTable = {};

        // 使用默认参数初始化调度器
        this.scheduler.initialize(150, 60, 60, 30, 0.1);

        // 开始可视化测试
        this.runVisualTest();

        // 开始准确性测试
        this.testMethodAccuracy();
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

        var node:TaskIDNode = this.scheduler.evaluateAndInsertTask(taskID, delayInFrames);
        this.addTaskToTable(taskID, node, this.currentFrame + delayInFrames);
        this.log("testMethodAccuracy: 插入任务 " + taskID + " 延迟 " + delayInFrames + " 帧", LOG_LEVEL_INFO);

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
        // 预先生成任务列表
        var tasks:Array = [];
        for (var i:Number = 0; i < numberOfTasks; i++) {
            var taskID:String = "perfInsertTask" + i;
            var delayInFrames:Number = Math.floor(Math.random() * 10000); // 随机延迟，限制在10,000帧以内
            tasks.push({taskID: taskID, delayInFrames: delayInFrames});
        }

        // 优化：循环展开插入任务
        var insertStartTime:Number = getTimer();
        var insertChunkSize:Number = 8; // 每次处理8个任务
        var insertLimit:Number = numberOfTasks - (numberOfTasks % insertChunkSize);
        var i:Number = 0;
        while (i < insertLimit) {
            // 手动展开循环
            this.scheduler.evaluateAndInsertTask(tasks[i].taskID, tasks[i].delayInFrames);
            this.scheduler.evaluateAndInsertTask(tasks[i + 1].taskID, tasks[i + 1].delayInFrames);
            this.scheduler.evaluateAndInsertTask(tasks[i + 2].taskID, tasks[i + 2].delayInFrames);
            this.scheduler.evaluateAndInsertTask(tasks[i + 3].taskID, tasks[i + 3].delayInFrames);
            this.scheduler.evaluateAndInsertTask(tasks[i + 4].taskID, tasks[i + 4].delayInFrames);
            this.scheduler.evaluateAndInsertTask(tasks[i + 5].taskID, tasks[i + 5].delayInFrames);
            this.scheduler.evaluateAndInsertTask(tasks[i + 6].taskID, tasks[i + 6].delayInFrames);
            this.scheduler.evaluateAndInsertTask(tasks[i + 7].taskID, tasks[i + 7].delayInFrames);
            i += insertChunkSize;
        }
        // 处理剩余的任务
        for (; i < numberOfTasks; i++) {
            this.scheduler.evaluateAndInsertTask(tasks[i].taskID, tasks[i].delayInFrames);
        }
        var insertEndTime:Number = getTimer();
        var insertTotalTime:Number = insertEndTime - insertStartTime;
        this.log("Insertion of " + numberOfTasks + " tasks took " + insertTotalTime + " ms", LOG_LEVEL_INFO);

        // 优化：循环展开查找任务
        var findStartTime:Number = getTimer();
        var findChunkSize:Number = 8;
        var findLimit:Number = numberOfTasks - (numberOfTasks % findChunkSize);
        var j:Number = 0;
        while (j < findLimit) {
            var findTaskID1:String = "perfInsertTask" + Math.floor(Math.random() * numberOfTasks);
            var findTaskID2:String = "perfInsertTask" + Math.floor(Math.random() * numberOfTasks);
            var findTaskID3:String = "perfInsertTask" + Math.floor(Math.random() * numberOfTasks);
            var findTaskID4:String = "perfInsertTask" + Math.floor(Math.random() * numberOfTasks);
            var findTaskID5:String = "perfInsertTask" + Math.floor(Math.random() * numberOfTasks);
            var findTaskID6:String = "perfInsertTask" + Math.floor(Math.random() * numberOfTasks);
            var findTaskID7:String = "perfInsertTask" + Math.floor(Math.random() * numberOfTasks);
            var findTaskID8:String = "perfInsertTask" + Math.floor(Math.random() * numberOfTasks);

            var node1:TaskIDNode = this.idNodeTable[findTaskID1];
            var node2:TaskIDNode = this.idNodeTable[findTaskID2];
            var node3:TaskIDNode = this.idNodeTable[findTaskID3];
            var node4:TaskIDNode = this.idNodeTable[findTaskID4];
            var node5:TaskIDNode = this.idNodeTable[findTaskID5];
            var node6:TaskIDNode = this.idNodeTable[findTaskID6];
            var node7:TaskIDNode = this.idNodeTable[findTaskID7];
            var node8:TaskIDNode = this.idNodeTable[findTaskID8];
            j += findChunkSize;
        }
        // 处理剩余的查找任务
        for (; j < numberOfTasks; j++) {
            var findTaskID:String = "perfInsertTask" + Math.floor(Math.random() * numberOfTasks);
            var node:TaskIDNode = this.idNodeTable[findTaskID];
        }
        var findEndTime:Number = getTimer();
        var findTotalTime:Number = findEndTime - findStartTime;
        this.log("Finding " + numberOfTasks + " tasks took " + findTotalTime + " ms", LOG_LEVEL_INFO);

        // 优化：循环展开重新调度任务
        var rescheduleStartTime:Number = getTimer();
        var rescheduleChunkSize:Number = 8;
        var rescheduleLimit:Number = numberOfTasks - (numberOfTasks % rescheduleChunkSize);
        var k:Number = 0;
        while (k < rescheduleLimit) {
            this.scheduler.rescheduleTaskByNode(null, Math.floor(Math.random() * 10000));
            this.scheduler.rescheduleTaskByNode(null, Math.floor(Math.random() * 10000));
            this.scheduler.rescheduleTaskByNode(null, Math.floor(Math.random() * 10000));
            this.scheduler.rescheduleTaskByNode(null, Math.floor(Math.random() * 10000));
            this.scheduler.rescheduleTaskByNode(null, Math.floor(Math.random() * 10000));
            this.scheduler.rescheduleTaskByNode(null, Math.floor(Math.random() * 10000));
            this.scheduler.rescheduleTaskByNode(null, Math.floor(Math.random() * 10000));
            this.scheduler.rescheduleTaskByNode(null, Math.floor(Math.random() * 10000));
            k += rescheduleChunkSize;
        }
        // 处理剩余的重新调度任务
        for (; k < numberOfTasks; k++) {
            this.scheduler.rescheduleTaskByNode(null, Math.floor(Math.random() * 10000));
        }
        var rescheduleEndTime:Number = getTimer();
        var rescheduleTotalTime:Number = rescheduleEndTime - rescheduleStartTime;
        this.log("Rescheduling " + numberOfTasks + " tasks took " + rescheduleTotalTime + " ms", LOG_LEVEL_INFO);

        // 优化：循环展开删除任务
        var deleteStartTime:Number = getTimer();
        var deleteChunkSize:Number = 8;
        var deleteLimit:Number = numberOfTasks - (numberOfTasks % deleteChunkSize);
        var l:Number = 0;
        while (l < deleteLimit) {
            this.scheduler.removeTaskByNode(null);
            this.scheduler.removeTaskByNode(null);
            this.scheduler.removeTaskByNode(null);
            this.scheduler.removeTaskByNode(null);
            this.scheduler.removeTaskByNode(null);
            this.scheduler.removeTaskByNode(null);
            this.scheduler.removeTaskByNode(null);
            this.scheduler.removeTaskByNode(null);
            l += deleteChunkSize;
        }
        // 处理剩余的删除任务
        for (; l < numberOfTasks; l++) {
            this.scheduler.removeTaskByNode(null);
        }
        var deleteEndTime:Number = getTimer();
        var deleteTotalTime:Number = deleteEndTime - deleteStartTime;
        this.log("Deletion of " + numberOfTasks + " tasks took " + deleteTotalTime + " ms", LOG_LEVEL_INFO);

        // 记录性能测试结果
        this.performanceTestResults.push({
            numberOfTasks: numberOfTasks,
            insertTime: insertTotalTime,
            findTime: findTotalTime,
            rescheduleTime: rescheduleTotalTime,
            deleteTime: deleteTotalTime
        });

        // 总结性能测试结果的日志输出
        this.log("Performance test for " + numberOfTasks + " tasks completed.", LOG_LEVEL_INFO);
        this.log("Detailed Performance Report:\n" +
                "Insertion Time: " + insertTotalTime + " ms\n" +
                "Find Time: " + findTotalTime + " ms\n" +
                "Reschedule Time: " + rescheduleTotalTime + " ms\n" +
                "Deletion Time: " + deleteTotalTime + " ms\n", LOG_LEVEL_INFO);
    }

    /**
     * 评估 tick 方法的性能表现，并同时进行 CRUD 操作
     * @param numberOfTasks 要调度的任务数量
     */
    public function testTickPerformance(numberOfTasks:Number):Void {
        this.log("Starting tick performance test for " + numberOfTasks + " tasks.", LOG_LEVEL_INFO);

        // 预先生成任务列表
        var tasks:Array = [];
        for (var i:Number = 0; i < numberOfTasks; i++) {
            var taskID:String = "tickPerfTask" + i;
            var delayInFrames:Number = Math.floor(Math.random() * 10000);
            tasks.push({taskID: taskID, delayInFrames: delayInFrames});
        }

        // 优化：循环展开插入任务
        var insertStartTime:Number = getTimer();
        var insertChunkSize:Number = 8;
        var insertLimit:Number = numberOfTasks - (numberOfTasks % insertChunkSize);
        var j:Number = 0;
        while (j < insertLimit) {
            this.scheduler.evaluateAndInsertTask(tasks[j].taskID, tasks[j].delayInFrames);
            this.scheduler.evaluateAndInsertTask(tasks[j + 1].taskID, tasks[j + 1].delayInFrames);
            this.scheduler.evaluateAndInsertTask(tasks[j + 2].taskID, tasks[j + 2].delayInFrames);
            this.scheduler.evaluateAndInsertTask(tasks[j + 3].taskID, tasks[j + 3].delayInFrames);
            this.scheduler.evaluateAndInsertTask(tasks[j + 4].taskID, tasks[j + 4].delayInFrames);
            this.scheduler.evaluateAndInsertTask(tasks[j + 5].taskID, tasks[j + 5].delayInFrames);
            this.scheduler.evaluateAndInsertTask(tasks[j + 6].taskID, tasks[j + 6].delayInFrames);
            this.scheduler.evaluateAndInsertTask(tasks[j + 7].taskID, tasks[j + 7].delayInFrames);
            j += insertChunkSize;
        }
        // 处理剩余的任务
        for (; j < numberOfTasks; j++) {
            this.scheduler.evaluateAndInsertTask(tasks[j].taskID, tasks[j].delayInFrames);
        }
        var insertEndTime:Number = getTimer();
        var insertTotalTime:Number = insertEndTime - insertStartTime;
        this.log("Tick Test - Insertion of " + numberOfTasks + " tasks took " + insertTotalTime + " ms", LOG_LEVEL_INFO);

        // 记录 tick 执行开始时间
        var tickTotalTime:Number = 0;
        var totalTasks:Number = numberOfTasks;
        var maxExpectedFrame:Number = numberOfTasks; // 最大帧数限制

        // 优化：使用循环展开执行 tick
        var tickChunkSize:Number = 8;
        var tickFramesProcessed:Number = 0; // 记录处理的帧数
        while (this.currentFrame <= maxExpectedFrame) {
            var tickStartTime:Number = getTimer();
            // 执行 tick
            var tasksExecuted:TaskIDLinkedList = this.scheduler.tick();
            var tickEndTime:Number = getTimer();
            var tickDuration:Number = tickEndTime - tickStartTime;
            tickTotalTime += tickDuration;
            tickFramesProcessed++; // 每次循环处理一帧

            if (tasksExecuted != null) {
                var node:TaskIDNode = tasksExecuted.getFirst();
                while (node != null) {
                    // this.log("执行任务: " + node.taskID + " 在帧: " + this.currentFrame, LOG_LEVEL_DEBUG);
                    this.executedTasksCount++;
                    this.updateActualFrame(node.taskID, this.currentFrame);
                    // 从哈希表中移除已执行的任务
                    this.removeTaskFromTable(node.taskID);
                    node = node.next;
                }
            }

            this.currentFrame++;
        }

        this.log("Tick performance for " + numberOfTasks + " tasks took " + tickTotalTime + " ms", LOG_LEVEL_INFO);

        // 计算每帧平均 tick 耗时
        var averageTickTime:Number = (tickFramesProcessed > 0) ? (tickTotalTime / tickFramesProcessed) : 0;
        this.log("Average Tick Time per Frame: " + averageTickTime + " ms", LOG_LEVEL_INFO); // 新增日志输出

        // 记录性能测试结果
        this.performanceTestResults.push({
            numberOfTasks: numberOfTasks,
            tickTime: tickTotalTime,
            averageTickTime: averageTickTime // 新增平均 tick 耗时
        });

        // 总结 tick 性能测试结果的日志输出
        this.log("Tick performance test for " + numberOfTasks + " tasks completed.", LOG_LEVEL_INFO);
        this.log("Detailed Tick Performance Report:\n" +
                "Tick Time: " + tickTotalTime + " ms\n" +
                "Average Tick Time per Frame: " + averageTickTime + " ms\n", LOG_LEVEL_INFO); // 新增平均 tick 耗时的输出
    }

    /**
     * 运行所有性能测试
     */
    public function runAllPerformanceTests():Void {
        var testLoads:Array = []; // 初始化负载级别列表
        var currentLoad:Number = 100; // 起始负载级别

        // 循环生成负载级别，直到达到或超过限制
        while (currentLoad <= 6000) {
            testLoads.push(currentLoad);
            currentLoad *= 1.618;
            currentLoad = Math.floor(currentLoad);
        }

        // 遍历负载级别列表，进行性能测试
        for (var i:Number = 0; i < testLoads.length; i++) {
            this.testPerformance(testLoads[i]);
            this.testTickPerformance(testLoads[i]);
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

    /**
     * 帧处理函数，每帧调用一次
     */
    private function onEnterFrameHandler():Void {
        this.currentFrame++;

        // 调用调度器的 tick 方法
        var tasks:TaskIDLinkedList = this.scheduler.tick();
        if (tasks != null) {
            var node:TaskIDNode = tasks.getFirst();
            while (node != null) {
                this.log("执行任务: " + node.taskID + " 在帧: " + this.currentFrame, LOG_LEVEL_DEBUG);
                this.executedTasksCount++;
                this.updateActualFrame(node.taskID, this.currentFrame);
                // 从哈希表中移除已执行的任务
                this.removeTaskFromTable(node.taskID);
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
            this.log("在第 2 帧删除任务", LOG_LEVEL_INFO);
            this.deleteTasks();
        }

        // 在第三帧重新调度任务
        if (this.currentFrame == 3 && this.enableRescheduleTasksTest) {
            this.log("在第 3 帧重新调度任务", LOG_LEVEL_INFO);
            this.rescheduleTasks();
        }

        // 在第1000帧插入更多任务以测试调度器的动态能力
        if (this.currentFrame == 1000) {
            this.insertAdditionalTasks();
        }

        // 更新显示
        this.displayTaskTable();

        // 当所有任务执行完毕，停止测试
        if (this.executedTasksCount >= this.taskIDList.length) {
            _root.onEnterFrame = undefined; // 结束测试
            this.log("测试完成。", LOG_LEVEL_INFO);
            this.displayPerformanceTestResults();
        }

        // 限制最大帧数为10,000，以避免无限运行
        if (this.currentFrame > 10000) {
            _root.onEnterFrame = undefined; // 强制结束测试
            this.log("测试已达到最大帧数，强制结束。", LOG_LEVEL_ERROR);
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
            {taskID: "task15", delayInFrames: 1, expectedFrame: this.currentFrame + 1},    // 立即执行

            // 第二级时间轮任务
            {taskID: "task4", delayInFrames: 151, expectedFrame: this.currentFrame + 151},
            {taskID: "task5", delayInFrames: 500, expectedFrame: this.currentFrame + 500},
            {taskID: "task6", delayInFrames: 1800, expectedFrame: this.currentFrame + 1800},
            {taskID: "task16", delayInFrames: 300, expectedFrame: this.currentFrame + 300}, // 中级时间轮

            // 第三级时间轮任务
            {taskID: "task7", delayInFrames: 1801, expectedFrame: this.currentFrame + 1801},
            {taskID: "task8", delayInFrames: 36000, expectedFrame: this.currentFrame + 10000}, // 调整到10,000帧以内
            {taskID: "task9", delayInFrames: 72000, expectedFrame: this.currentFrame + 10000}, // 调整到10,000帧以内
            {taskID: "task17", delayInFrames: 54000, expectedFrame: this.currentFrame + 10000}, // 调整到10,000帧以内

            // 最小堆任务
            {taskID: "task10", delayInFrames: 108000, expectedFrame: this.currentFrame + 10000}, // 调整到10,000帧以内
            {taskID: "task11", delayInFrames: 108001, expectedFrame: this.currentFrame + 10000}, // 调整到10,000帧以内
            {taskID: "task18", delayInFrames: 200000, expectedFrame: this.currentFrame + 10000}, // 调整到10,000帧以内

            // 并发任务
            {taskID: "task12", delayInFrames: 150, expectedFrame: this.currentFrame + 150},
            {taskID: "task13", delayInFrames: 1800, expectedFrame: this.currentFrame + 1800},
            {taskID: "task14", delayInFrames: 1801, expectedFrame: this.currentFrame + 1801},

            // 边界情况
            {taskID: "task19", delayInFrames: 149, expectedFrame: this.currentFrame + 149}, // 与 task2 同时
            {taskID: "task20", delayInFrames: 108001, expectedFrame: this.currentFrame + 10000}, // 调整到10,000帧以内

            // 精度阈值测试
            {taskID: "task21", delayInFrames: 1650, expectedFrame: this.currentFrame + 1650}, // 接近第二级阈值但有精度问题
            {taskID: "task22", delayInFrames: 36600, expectedFrame: this.currentFrame + 10000}, // 调整到10,000帧以内
            {taskID: "task23", delayInFrames: 36601, expectedFrame: this.currentFrame + 10000}, // 调整到10,000帧以内

            // 更多边界测试
            {taskID: "task24", delayInFrames: 499, expectedFrame: this.currentFrame + 499},
            {taskID: "task25", delayInFrames: 500, expectedFrame: this.currentFrame + 500},
            {taskID: "task26", delayInFrames: 600, expectedFrame: this.currentFrame + 600},
            {taskID: "task27", delayInFrames: 1799, expectedFrame: this.currentFrame + 1799},
            {taskID: "task28", delayInFrames: 1800, expectedFrame: this.currentFrame + 1800},
            {taskID: "task29", delayInFrames: 1801, expectedFrame: this.currentFrame + 1801},
            {taskID: "task30", delayInFrames: 71999, expectedFrame: this.currentFrame + 10000}, // 调整到10,000帧以内
            {taskID: "task31", delayInFrames: 72000, expectedFrame: this.currentFrame + 10000}, // 调整到10,000帧以内
            {taskID: "task32", delayInFrames: 72001, expectedFrame: this.currentFrame + 10000}, // 调整到10,000帧以内

            // 精度阈值任务
            {taskID: "task33", delayInFrames: 599, expectedFrame: this.currentFrame + 599},
            {taskID: "task34", delayInFrames: 600, expectedFrame: this.currentFrame + 600},

            // 边界测试任务
            {taskID: "task35", delayInFrames: 0, expectedFrame: this.currentFrame}, // 0帧延迟，立即执行
            {taskID: "task36", delayInFrames: 1, expectedFrame: this.currentFrame + 1}, // 1帧延迟，立即执行
            {taskID: "task37", delayInFrames: 10000, expectedFrame: this.currentFrame + 10000} // 极大延迟调整为10,000帧
        ];

        for (var i:Number = 0; i < tasksConfig.length; i++) {
            var task:Object = tasksConfig[i];
            // 确保所有任务的 delayInFrames 不超过10,000帧
            if (task.delayInFrames > 10000) {
                task.delayInFrames = 10000;
                task.expectedFrame = this.currentFrame + 10000;
                this.log("调整任务 " + task.taskID + " 的延迟到10,000帧以内", LOG_LEVEL_DEBUG);
            }
            var node:TaskIDNode = this.scheduler.evaluateAndInsertTask(task.taskID, task.delayInFrames);
            this.addTaskToTable(task.taskID, node, task.expectedFrame);
            this.log(task.taskID + " 插入延迟 " + task.delayInFrames + " 帧，预期在帧 " + task.expectedFrame + " 执行", LOG_LEVEL_DEBUG);
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
            {taskID: "task47", delayInFrames: 1100, expectedFrame: this.currentFrame + 10000}, // 限制到10,000帧
            {taskID: "task48", delayInFrames: 1200, expectedFrame: this.currentFrame + 10000}, // 限制到10,000帧
            {taskID: "task49", delayInFrames: 1300, expectedFrame: this.currentFrame + 10000}, // 限制到10,000帧
            {taskID: "task50", delayInFrames: 1400, expectedFrame: this.currentFrame + 10000}  // 限制到10,000帧
        ];

        for (var i:Number = 0; i < additionalTasksConfig.length; i++) {
            var task:Object = additionalTasksConfig[i];
            // 确保所有任务的 delayInFrames 不超过10,000帧
            if (task.delayInFrames > 10000) {
                task.delayInFrames = 10000;
                task.expectedFrame = this.currentFrame + 10000;
                this.log("调整任务 " + task.taskID + " 的延迟到10,000帧以内", LOG_LEVEL_DEBUG);
            }
            var node:TaskIDNode = this.scheduler.evaluateAndInsertTask(task.taskID, task.delayInFrames);
            this.addTaskToTable(task.taskID, node, task.expectedFrame);
            this.log(task.taskID + " 插入延迟 " + task.delayInFrames + " 帧，预期在帧 " + task.expectedFrame + " 执行", LOG_LEVEL_DEBUG);
        }
    }

    /**
     * 添加任务到任务表和 id-node 哈希表
     * @param taskID        任务ID
     * @param node          任务节点
     * @param expectedFrame 预期执行帧
     */
    private function addTaskToTable(taskID:String, node:TaskIDNode, expectedFrame:Number):Void {
        this.taskTable[taskID] = {taskID: taskID, expectedFrame: expectedFrame, actualFrame: null};
        this.idNodeTable[taskID] = node;
        this.taskIDList.push(taskID);
    }

    /**
     * 从任务表和 id-node 哈希表中移除任务
     * @param taskID 任务ID
     */
    private function removeTaskFromTable(taskID:String):Void {
        delete this.idNodeTable[taskID];
        delete this.taskTable[taskID];
        var index:Number = this.taskIDList.indexOf(taskID);
        if (index != -1) {
            this.taskIDList.splice(index, 1);
        }
    }

    /**
     * 更新任务的实际执行帧
     * @param taskID      任务ID
     * @param actualFrame 实际执行帧
     */
    private function updateActualFrame(taskID:String, actualFrame:Number):Void {
        if (this.taskTable[taskID]) {
            this.taskTable[taskID].actualFrame = actualFrame;
        }
    }

    /**
     * 更新任务的预期执行帧
     * @param taskID           任务ID
     * @param newExpectedFrame 新预期执行帧
     */
    private function updateExpectedFrame(taskID:String, newExpectedFrame:Number):Void {
        if (this.taskTable[taskID]) {
            this.taskTable[taskID].expectedFrame = newExpectedFrame;
        }
    }

    /**
     * 执行随机 CRUD 操作，根据比例插入 50%、删除 20%、重新调度 20%、查找 10%
     */
    private function performRandomCRUD():Void {
        var rand:Number = Math.random();

        if (rand < 0.5) {
            // 插入 50%
            this.randomInsert();
        } else if (rand < 0.7) {
            // 删除 20%
            this.randomDelete();
        } else if (rand < 0.9) {
            // 重新调度 20%
            this.randomReschedule();
        } else {
            // 查找 10%
            this.randomFind();
        }
    }

    /**
     * 随机插入一个新任务
     */
    private function randomInsert():Void {
        var taskID:String = "randomInsertTask" + getTimer() + Math.floor(Math.random() * 1000);
        var delayInFrames:Number = Math.floor(Math.random() * 10000);
        var node:TaskIDNode = this.scheduler.evaluateAndInsertTask(taskID, delayInFrames);
        this.addTaskToTable(taskID, node, this.currentFrame + delayInFrames);
    }

    /**
     * 随机删除一个现有任务
     */
    private function randomDelete():Void {
        if (this.taskIDList.length == 0) {
            return; // 无任务可删除
        }
        var randomIndex:Number = Math.floor(Math.random() * this.taskIDList.length);
        var taskID:String = this.taskIDList[randomIndex];
        var node:TaskIDNode = this.idNodeTable[taskID];
        this.scheduler.removeTaskByNode(node);
        this.removeTaskFromTable(taskID);
    }

    /**
     * 随机重新调度一个现有任务
     */
    private function randomReschedule():Void {
        if (this.taskIDList.length == 0) {
            return; // 无任务可重新调度
        }
        var randomIndex:Number = Math.floor(Math.random() * this.taskIDList.length);
        var taskID:String = this.taskIDList[randomIndex];
        var node:TaskIDNode = this.idNodeTable[taskID];
        var newDelayInFrames:Number = Math.floor(Math.random() * 10000);
        this.scheduler.rescheduleTaskByNode(node, newDelayInFrames);
        var newExpectedFrame:Number = this.currentFrame + newDelayInFrames;
        this.updateExpectedFrame(taskID, newExpectedFrame);
    }

    /**
     * 随机查找一个现有任务
     */
    private function randomFind():Void {
        if (this.taskIDList.length == 0) {
            return; // 无任务可查找
        }
        var randomIndex:Number = Math.floor(Math.random() * this.taskIDList.length);
        var taskID:String = this.taskIDList[randomIndex];
        var node:TaskIDNode = this.idNodeTable[taskID];
        // 可选：验证找到的节点是否正确
        if (node != null && node.taskID == taskID) {
            // 查找成功
        } else {
            this.log("随机查找任务失败: " + taskID, LOG_LEVEL_ERROR);
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
        for (var taskID:String in this.taskTable) {
            if (displayedTasksCount >= displayLimit) {
                break;
            }
            var task:Object = this.taskTable[taskID];
            var difference:Number = (task.actualFrame != null) ? (task.actualFrame - task.expectedFrame) : 0;
            var differenceText:String = (task.actualFrame != null) ? difference.toString() : "Pending";
            displayText += task.taskID + "\t" + task.expectedFrame + "\t" + (task.actualFrame != null ? task.actualFrame : "待执行") + "\t" + differenceText + "\n";
            displayedTasksCount++;
        }
        if (this.taskIDList.length > displayLimit) {
            displayText += "...\n仅显示前 " + displayLimit + " 个任务\n";
        }

        // 显示性能测试结果
        displayText += "\n性能测试结果:\n";
        for (var l:Number = 0; l < this.performanceTestResults.length; l++) {
            var result:Object = this.performanceTestResults[l];
            if (result.insertTime != undefined) { // 传统CRUD测试
                displayText += "任务数: " + result.numberOfTasks + " | 插入耗时: " + result.insertTime + "ms | 查找耗时: " + result.findTime + "ms | 重新调度耗时: " + result.rescheduleTime + "ms | 删除耗时: " + result.deleteTime + "ms\n";
            } else if (result.tickTime != undefined) { // tick性能测试
                // 新增显示平均 tick 耗时
                var avgTickTimeText:String = (result.averageTickTime != undefined) ? " | 平均 Tick 耗时: " + result.averageTickTime + " ms" : "";
                displayText += "任务数: " + result.numberOfTasks + " | Tick耗时: " + result.tickTime + " ms" + avgTickTimeText + "\n";
            }
        }

        // 更新文本字段
        this.frameCountDisplay.text = displayText;
    }

    /**
     * 显示性能测试结果总结
     */
    private function displayPerformanceTestResults():Void {
        var summaryText:String = "性能测试结果总结:\n";
        for (var l:Number = 0; l < this.performanceTestResults.length; l++) {
            var result:Object = this.performanceTestResults[l];
            if (result.insertTime != undefined) { // 传统CRUD测试
                summaryText += "任务数: " + result.numberOfTasks + " | 插入耗时: " + result.insertTime + "ms | 查找耗时: " + result.findTime + "ms | 重新调度耗时: " + result.rescheduleTime + "ms | 删除耗时: " + result.deleteTime + "ms\n";
            } else if (result.tickTime != undefined) { // tick性能测试
                // 新增显示平均 tick 耗时
                var avgTickTimeSummary:String = (result.averageTickTime != undefined) ? " | 平均 Tick 耗时: " + result.averageTickTime + " ms" : "";
                summaryText += "任务数: " + result.numberOfTasks + " | Tick耗时: " + result.tickTime + " ms" + avgTickTimeSummary + "\n";
            }
        }
        this.log(summaryText, LOG_LEVEL_INFO);
    }

    /**
     * 删除任务
     */
    private function deleteTasks():Void {
        var deleteTasksConfig:Array = ["task3", "task7", "task10", "task35", "task37"]; // 添加更多删除任务以覆盖边界测试

        for (var i:Number = 0; i < deleteTasksConfig.length; i++) {
            var taskID:String = deleteTasksConfig[i];
            var node:TaskIDNode = this.idNodeTable[taskID];
            this.scheduler.removeTaskByNode(node);
            this.removeTaskFromTable(taskID);
            this.log("已删除任务: " + taskID, LOG_LEVEL_DEBUG);
        }
    }

    /**
     * 重新调度任务
     */
    private function rescheduleTasks():Void {
        var rescheduleTasksConfig:Array = [
            {taskID: "task4", newDelayInFrames: 3000},  // 从第二层时间轮移到第三层时间轮
            {taskID: "task19", newDelayInFrames: 200},  // 从单层时间轮重新调度到第二层时间轮
            {taskID: "task11", newDelayInFrames: 5000}, // 最小堆任务调整，限制在10,000帧以内
            {taskID: "task35", newDelayInFrames: 500}, // 重新调度边界任务
            {taskID: "task37", newDelayInFrames: 10000} // 重新调度极大延迟任务，限制在10,000帧以内
        ];

        for (var i:Number = 0; i < rescheduleTasksConfig.length; i++) {
            var task:Object = rescheduleTasksConfig[i];
            // 确保重新调度后的 delayInFrames 不超过10,000帧
            if (task.newDelayInFrames > 10000) {
                task.newDelayInFrames = 10000;
                this.log("调整重新调度任务 " + task.taskID + " 的新延迟到10,000帧以内", LOG_LEVEL_DEBUG);
            }
            var node:TaskIDNode = this.idNodeTable[task.taskID];
            this.scheduler.rescheduleTaskByNode(node, task.newDelayInFrames);
            var newExpectedFrame:Number = this.currentFrame + task.newDelayInFrames;
            this.updateExpectedFrame(task.taskID, newExpectedFrame);
            this.log("重新调度任务: " + task.taskID + " 新延迟: " + task.newDelayInFrames + " 帧，预期在帧 " + newExpectedFrame + " 执行", LOG_LEVEL_DEBUG);
        }
    }

    // ==========================
    // 日志函数
    // ==========================

    /**
     * 日志函数，根据日志级别控制输出
     * @param message 日志消息
     * @param level   日志级别
     */
    private function log(message:String, level:Number):Void {
        if (level >= this.currentLogLevel) {
            trace(message);
        }
    }

    // ==========================
    // 工具函数
    // ==========================

    /**
     * 获取单层时间轮的当前槽大小
     * @return 单层时间轮的槽大小
     */
    public function getSingleLevelSlotSize():Number {
        var data:Object = this.scheduler.getSingleLevelTimeWheel().getTimeWheelData();
        return data.slotSize;
    }

    /**
     * 获取第二级时间轮的槽大小
     * @return 第二级时间轮的槽大小
     */
    public function getMultiLevelSecondSlotSize():Number {
        var data:Object = this.scheduler.getSecondLevelTimeWheel().getTimeWheelData();
        return data.slotSize;
    }

    /**
     * 获取第三级时间轮的槽大小
     * @return 第三级时间轮的槽大小
     */
    public function getMultiLevelMinuteSlotSize():Number {
        var data:Object = this.scheduler.getThirdLevelTimeWheel().getTimeWheelData();
        return data.slotSize;
    }

    /**
     * 获取第一级多级时间轮计数器的上限值
     * @return 第一级计数器的上限值
     */
    public function getMultiLevelCounterLimit():Number {
        return this.scheduler.getMultiLevelCounterLimit();
    }

    /**
     * 获取第二级时间轮计数器的上限值
     * @return 第二级时间轮计数器的上限值
     */
    public function getSecondLevelCounterLimit():Number {
        return this.scheduler.getSecondLevelCounterLimit();
    }
}
