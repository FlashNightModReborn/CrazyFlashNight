import org.flashNight.neur.TimeWheel.SingleLevelTimeWheel;
import org.flashNight.naki.DataStructures.TaskIDNode;
import org.flashNight.naki.DataStructures.TaskIDLinkedList;

class org.flashNight.neur.TimeWheel.SingleLevelTimeWheelTest {
    private var wheel:SingleLevelTimeWheel;

    public function SingleLevelTimeWheelTest() {
        // 在各个测试方法中初始化时间轮
    }

    // 断言辅助方法
    private function assert(condition:Boolean, message:String):Void {
        if (condition) {
            trace("PASS: " + message);
        } else {
            trace("FAIL: " + message);
        }
    }

    // 重置时间轮，确保测试独立性
    private function resetWheel(size:Number):Void {
        this.wheel = new SingleLevelTimeWheel(size);
    }

    // 运行所有功能测试
    public function runFunctionTests():Void {
        trace("=== Running Functional Tests ===");
        testAddTimerByID();
        testAddTimerByNode();
        testRemoveTimerByID();
        testRemoveTimerByNode();
        testRescheduleTimerByID();
        testRescheduleTimerByNode();
        testTick();
        testGetTimeWheelStatus();
        testGetTimeWheelData();
        testNodePoolMethods();
        testEdgeCases();
        trace("=== Functional Tests Completed ===\n");
    }

    // 运行所有性能测试
    public function runPerformanceTests():Void {
        trace("=== Running Performance Tests ===");
        testAddTimerPerformance();
        testRemoveTimerPerformance();
        testTickPerformance();
        testNodePoolPerformance();
        trace("=== Performance Tests Completed ===\n");
    }

    // 测试通过任务ID添加定时器
    private function testAddTimerByID():Void {
        resetWheel(30); // 固定时间轮大小为30
        wheel.addTimerByID("task1", 5);
        wheel.addTimerByID("task2", 3);
        
        var status:Object = wheel.getTimeWheelStatus();
        assert(status.taskCounts[3] == 1, "addTimerByID places task2 at correct slot");
        assert(status.taskCounts[5] == 1, "addTimerByID places task1 at correct slot");
    }

    // 测试通过节点添加定时器
    private function testAddTimerByNode():Void {
        resetWheel(30); // 固定时间轮大小为30
        var node:TaskIDNode = new TaskIDNode("task3");
        wheel.addTimerByNode(node, 7);
        
        var status:Object = wheel.getTimeWheelStatus();
        assert(status.taskCounts[7] == 1, "addTimerByNode places task3 at correct slot");
    }

    // 测试通过任务ID移除定时器
    private function testRemoveTimerByID():Void {
        resetWheel(30); // 固定时间轮大小为30
        wheel.addTimerByID("task1", 5);
        wheel.addTimerByID("task2", 3);
        wheel.removeTimerByID("task2");

        var status:Object = wheel.getTimeWheelStatus();
        assert(status.taskCounts[3] == 0, "removeTimerByID correctly removes task2");
    }

    // 测试通过节点移除定时器
    private function testRemoveTimerByNode():Void {
        resetWheel(30); // 固定时间轮大小为30
        var node:TaskIDNode = wheel.addTimerByID("task1", 5);
        wheel.removeTimerByNode(node);

        var status:Object = wheel.getTimeWheelStatus();
        assert(status.taskCounts[5] == 0, "removeTimerByNode correctly removes task1");
    }

    // 测试通过任务ID重新调度定时器
    private function testRescheduleTimerByID():Void {
        resetWheel(30); // 固定时间轮大小为30
        wheel.addTimerByID("task1", 5);
        wheel.rescheduleTimerByID("task1", 8);

        var status:Object = wheel.getTimeWheelStatus();
        assert(status.taskCounts[5] == 0 && status.taskCounts[8] == 1, "rescheduleTimerByID correctly moves task1");
    }

    // 测试通过节点重新调度定时器
    private function testRescheduleTimerByNode():Void {
        resetWheel(30); // 固定时间轮大小为30
        var node:TaskIDNode = wheel.addTimerByID("task2", 2);
        wheel.rescheduleTimerByNode(node, 6);

        var status:Object = wheel.getTimeWheelStatus();
        assert(status.taskCounts[2] == 0 && status.taskCounts[6] == 1, "rescheduleTimerByNode correctly moves task2");
    }

    // 测试时间轮的tick功能
    private function testTick():Void {
        resetWheel(30); // 固定时间轮大小为30
        wheel.addTimerByID("task1", 0);
        wheel.addTimerByID("task2", 1);

        var tasks:TaskIDLinkedList = wheel.tick();
        assert(tasks != null && tasks.getFirst().taskID == "task1", "tick retrieves tasks at current pointer");

        tasks = wheel.tick();
        assert(tasks != null && tasks.getFirst().taskID == "task2", "tick retrieves tasks at next pointer");
    }

    // 测试获取时间轮状态的方法
    private function testGetTimeWheelStatus():Void {
        resetWheel(30); // 固定时间轮大小为30
        wheel.addTimerByID("task1", 2);
        var status:Object = wheel.getTimeWheelStatus();
        assert(status.currentPointer == 0, "getTimeWheelStatus returns correct currentPointer");
        assert(status.wheelSize == 30, "getTimeWheelStatus returns correct wheelSize");
        assert(status.taskCounts[2] == 1, "getTimeWheelStatus returns correct taskCounts");
    }

    // 测试获取时间轮数据的方法
    private function testGetTimeWheelData():Void {
        resetWheel(30); // 固定时间轮大小为30
        var data:Object = wheel.getTimeWheelData();
        assert(data.currentPointer == 0, "getTimeWheelData returns correct currentPointer");
        assert(data.wheelSize == 30, "getTimeWheelData returns correct wheelSize");
    }

    // 测试节点池相关的方法
    private function testNodePoolMethods():Void {
        resetWheel(30); // 固定时间轮大小为30
        var initialPoolSize:Number = wheel.getNodePoolSize();
        wheel.fillNodePool(5);
        var afterFillSize:Number = wheel.getNodePoolSize();
        assert(afterFillSize == initialPoolSize + 5, "fillNodePool correctly increases node pool size");

        wheel.trimNodePool(initialPoolSize);
        var afterTrimSize:Number = wheel.getNodePoolSize();
        assert(afterTrimSize == initialPoolSize, "trimNodePool correctly trims node pool size");
    }

    // 测试边界情况和异常处理
    private function testEdgeCases():Void {
        resetWheel(30); // 固定时间轮大小为30

        // 移除不存在的任务
        wheel.removeTimerByID("nonExistentTask");
        assert(true, "removeTimerByID handles non-existent task gracefully");

        // 重新调度不存在的任务
        wheel.rescheduleTimerByID("nonExistentTask", 5);
        assert(true, "rescheduleTimerByID handles non-existent task gracefully");

        // 添加负延迟的任务
        wheel.addTimerByID("negativeDelayTask", -1);
        var status:Object = wheel.getTimeWheelStatus();
        assert(status.taskCounts[29] == 1, "addTimerByID with negative delay wraps around correctly");

        // 延迟超过轮子大小的任务
        wheel.addTimerByID("largeDelayTask", 35); // 35 % 30 = 5
        status = wheel.getTimeWheelStatus();
        assert(status.taskCounts[5] == 1, "addTimerByID with large delay wraps around correctly");

        // 多次tick超过轮子大小
        for (var i:Number = 0; i < 60; i++) { // 60 ticks, wheelSize = 30, should wrap around twice
            wheel.tick();
        }
        assert(wheel.getTimeWheelStatus().currentPointer == 0, "tick wraps around wheel correctly after multiple overflows");
    }

    // 添加定时器的性能测试（手动展开循环）
    private function testAddTimerPerformance():Void {
        resetWheel(30); // 固定时间轮大小为30
        var startTime:Number = getTimer();
        var i:Number = 0;
        var limit:Number = 10000;

        // 手动展开循环，每次处理4个添加操作
        while (i < limit) {
            wheel.addTimerByID("task" + i, Math.floor(Math.random() * 30));
            i++;
            if (i < limit) {
                wheel.addTimerByID("task" + i, Math.floor(Math.random() * 30));
                i++;
            }
            if (i < limit) {
                wheel.addTimerByID("task" + i, Math.floor(Math.random() * 30));
                i++;
            }
            if (i < limit) {
                wheel.addTimerByID("task" + i, Math.floor(Math.random() * 30));
                i++;
            }
        }

        var endTime:Number = getTimer();
        trace("Add Timer Performance: " + (endTime - startTime) + " ms for 10,000 adds (loop unrolled by 4)");
    }

    // 移除定时器的性能测试（手动展开循环）
    private function testRemoveTimerPerformance():Void {
        resetWheel(30); // 固定时间轮大小为30
        var insertLimit:Number = 5000;
        for (var i:Number = 0; i < insertLimit; i++) {
            wheel.addTimerByID("task" + i, Math.floor(Math.random() * 30));
        }

        var startTime:Number = getTimer();
        var j:Number = 0;
        var removeLimit:Number = 5000;

        // 手动展开循环，每次处理4个移除操作
        while (j < removeLimit) {
            wheel.removeTimerByID("task" + j);
            j++;
            if (j < removeLimit) {
                wheel.removeTimerByID("task" + j);
                j++;
            }
            if (j < removeLimit) {
                wheel.removeTimerByID("task" + j);
                j++;
            }
            if (j < removeLimit) {
                wheel.removeTimerByID("task" + j);
                j++;
            }
        }

        var endTime:Number = getTimer();
        trace("Remove Timer Performance: " + (endTime - startTime) + " ms for 5,000 removals (loop unrolled by 4)");
    }

    // tick操作的性能测试（手动展开循环，扩展到10000次）
    private function testTickPerformance():Void {
        resetWheel(30); // 固定时间轮大小为30
        var insertLimit:Number = 10000;
        for (var i:Number = 0; i < insertLimit; i++) {
            wheel.addTimerByID("task" + i, Math.floor(Math.random() * 30));
        }

        var startTime:Number = getTimer();
        var k:Number = 0;
        var tickLimit:Number = 10000;

        // 手动展开循环，每次处理4个tick操作
        while (k < tickLimit) {
            wheel.tick();
            k++;
            if (k < tickLimit) {
                wheel.tick();
                k++;
            }
            if (k < tickLimit) {
                wheel.tick();
                k++;
            }
            if (k < tickLimit) {
                wheel.tick();
                k++;
            }
        }

        var endTime:Number = getTimer();
        trace("Tick Performance: " + (endTime - startTime) + " ms for 10,000 ticks (loop unrolled by 4)");
    }

    // 节点池方法的性能测试（手动展开循环）
    private function testNodePoolPerformance():Void {
        resetWheel(30); // 固定时间轮大小为30
        var startTime:Number = getTimer();

        var fillLimit:Number = 10000;
        var i:Number = 0;

        // 手动展开循环，每次处理4个填充操作
        while (i < fillLimit) {
            wheel.fillNodePool(4);
            i += 4;
        }

        var midTime:Number = getTimer();

        var trimLimit:Number = 1000;
        var j:Number = 0;

        // 手动展开循环，每次处理4个修剪操作
        while (j < trimLimit) {
            wheel.trimNodePool(4);
            j += 4;
        }

        var endTime:Number = getTimer();
        trace("fillNodePool Performance: " + (midTime - startTime) + " ms for filling 10,000 nodes (loop unrolled by 4)");
        trace("trimNodePool Performance: " + (endTime - midTime) + " ms for trimming to 1,000 nodes (loop unrolled by 4)");
    }

    // 增强的准确性评估测试
    private function testPracticalTaskCombinations():Void {
        resetWheel(30); // 固定时间轮大小为30

        // 添加多个任务到不同的槽位
        wheel.addTimerByID("taskA", 5);
        wheel.addTimerByID("taskB", 10);
        wheel.addTimerByID("taskC", 15);
        wheel.addTimerByID("taskD", 25);
        wheel.addTimerByID("taskE", 30); // 30 % 30 = 0
        wheel.addTimerByID("taskF", -5); // (-5 % 30 + 30) % 30 = 25

        var status:Object = wheel.getTimeWheelStatus();
        assert(status.taskCounts[0] == 1, "Practical Task Combination: taskE placed at slot 0");
        assert(status.taskCounts[5] == 1, "Practical Task Combination: taskA placed at slot 5");
        assert(status.taskCounts[10] == 1, "Practical Task Combination: taskB placed at slot 10");
        assert(status.taskCounts[15] == 1, "Practical Task Combination: taskC placed at slot 15");
        assert(status.taskCounts[25] == 2, "Practical Task Combination: taskD and taskF placed at slot 25");

        // Reschedule some tasks
        wheel.rescheduleTimerByID("taskA", 20);
        wheel.rescheduleTimerByID("taskB", -10); // (-10 % 30 + 30) % 30 = 20

        status = wheel.getTimeWheelStatus();
        assert(status.taskCounts[5] == 0, "Practical Task Combination: taskA removed from slot 5");
        assert(status.taskCounts[10] == 0, "Practical Task Combination: taskB removed from slot 10");
        assert(status.taskCounts[20] == 2, "Practical Task Combination: taskA and taskB placed at slot 20");
        assert(status.taskCounts[25] == 2, "Practical Task Combination: taskD and taskF remain at slot 25");
    }

    // 运行增强的准确性评估测试
    private function runAdditionalAccuracyTests():Void {
        trace("=== Running Practical Task Combinations Test ===");
        testPracticalTaskCombinations();
        trace("=== Practical Task Combinations Test Completed ===\n");
    }
}
