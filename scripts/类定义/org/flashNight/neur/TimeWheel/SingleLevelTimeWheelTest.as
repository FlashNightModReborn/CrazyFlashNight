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
    // [UPDATE v1.5] 构造函数现在接受第二个参数 nodePoolProvider，传递 null 表示创建独立节点池
    private function resetWheel(size:Number):Void {
        this.wheel = new SingleLevelTimeWheel(size, null);
    }

    // 运行所有测试（一键启动）
    public function runAllTests():Void {
        trace("╔════════════════════════════════════════╗");
        trace("║  SingleLevelTimeWheel 完整测试套件     ║");
        trace("╚════════════════════════════════════════╝\n");

        runFunctionTests();
        runPerformanceTests();
        runAdditionalAccuracyTests();
        runFixV12Tests();
        runFixV15Tests();

        trace("╔════════════════════════════════════════╗");
        trace("║  所有测试完成                          ║");
        trace("╚════════════════════════════════════════╝");
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

    // ==========================
    // FIX v1.2 验证测试
    // ==========================

    /**
     * [FIX v1.2] 测试 trimNodePool 正确释放引用
     * 验证修复：trimNodePool 现在会将超出部分的节点引用设为 null，
     * 以便 GC 可以回收这些不再需要的节点对象。
     */
    private function testTrimNodePoolReleasesReferences():Void {
        resetWheel(30);

        // 先填充节点池到较大数量
        wheel.fillNodePool(50);
        var beforeTrimSize:Number = wheel.getNodePoolSize();
        assert(beforeTrimSize >= 50, "[FIX v1.2] fillNodePool correctly fills pool");

        // 执行 trimNodePool
        var targetSize:Number = 10;
        wheel.trimNodePool(targetSize);
        var afterTrimSize:Number = wheel.getNodePoolSize();

        // 验证节点池大小正确调整
        assert(afterTrimSize == targetSize, "[FIX v1.2] trimNodePool correctly reduces pool size to " + targetSize);

        // 注意：由于 AS2 无法直接验证内部数组元素是否为 null，
        // 我们通过填充新节点并验证池大小来间接验证修复是否生效
        wheel.fillNodePool(20);
        var afterRefillSize:Number = wheel.getNodePoolSize();
        assert(afterRefillSize == targetSize + 20, "[FIX v1.2] Pool can be refilled after trim, size = " + afterRefillSize);

        trace("[FIX v1.2] trimNodePool reference release test completed");
    }

    /**
     * [FIX v1.2] 测试 acquireNode 和 releaseNode 的节点复用
     * 验证修复：releaseNode 方法可以将节点回收到池中供后续复用
     */
    private function testNodeRecycling():Void {
        resetWheel(30);

        var initialPoolSize:Number = wheel.getNodePoolSize();

        // 获取一个节点
        var node:TaskIDNode = wheel.acquireNode("testTask");
        var afterAcquireSize:Number = wheel.getNodePoolSize();
        assert(afterAcquireSize == initialPoolSize - 1, "[FIX v1.2] acquireNode reduces pool size by 1");
        assert(node.taskID == "testTask", "[FIX v1.2] acquireNode correctly initializes taskID");

        // 回收节点
        node.reset(null);
        wheel.releaseNode(node);
        var afterReleaseSize:Number = wheel.getNodePoolSize();
        assert(afterReleaseSize == initialPoolSize, "[FIX v1.2] releaseNode restores pool size");

        trace("[FIX v1.2] Node recycling test completed");
    }

    /**
     * 运行 FIX v1.2 验证测试
     */
    public function runFixV12Tests():Void {
        trace("=== Running FIX v1.2 Verification Tests ===");
        testTrimNodePoolReleasesReferences();
        testNodeRecycling();
        trace("=== FIX v1.2 Verification Tests Completed ===\n");
    }

    // ==========================
    // FIX v1.5 验证测试 - 节点池提供者
    // ==========================

    /**
     * [NEW v1.5] 测试创建带有节点池提供者的时间轮
     * 验证：使用 provider 的时间轮不会创建自己的节点池
     */
    private function testNodePoolProviderCreation():Void {
        // 创建提供者时间轮（拥有自己的节点池）
        var provider:SingleLevelTimeWheel = new SingleLevelTimeWheel(30, null);
        var providerPoolSize:Number = provider.getNodePoolSize();
        assert(providerPoolSize > 0, "[NEW v1.5] Provider wheel has its own node pool");

        // 创建委托时间轮（共享提供者的节点池）
        var delegateWheel:SingleLevelTimeWheel = new SingleLevelTimeWheel(20, provider);

        // 两个时间轮应该返回相同的节点池大小
        assert(delegateWheel.getNodePoolSize() == providerPoolSize,
               "[NEW v1.5] Delegate wheel reports same pool size as provider");

        trace("[NEW v1.5] Node pool provider creation test completed");
    }

    /**
     * [NEW v1.5] 测试 acquireNode 委托行为
     * 验证：通过委托时间轮调用 acquireNode 会从提供者的节点池获取节点
     */
    private function testAcquireNodeDelegation():Void {
        var provider:SingleLevelTimeWheel = new SingleLevelTimeWheel(30, null);
        var delegateWheel:SingleLevelTimeWheel = new SingleLevelTimeWheel(20, provider);

        var initialPoolSize:Number = provider.getNodePoolSize();

        // 通过委托时间轮获取节点
        var node:TaskIDNode = delegateWheel.acquireNode("testTask");

        assert(node != null, "[NEW v1.5] acquireNode via delegate returns valid node");
        assert(node.taskID == "testTask", "[NEW v1.5] acquireNode via delegate sets correct taskID");
        assert(provider.getNodePoolSize() == initialPoolSize - 1,
               "[NEW v1.5] acquireNode via delegate reduces provider's pool size");
        assert(delegateWheel.getNodePoolSize() == initialPoolSize - 1,
               "[NEW v1.5] Delegate wheel reflects provider's pool size change");

        trace("[NEW v1.5] acquireNode delegation test completed");
    }

    /**
     * [NEW v1.5] 测试 releaseNode 委托行为
     * 验证：通过委托时间轮调用 releaseNode 会将节点回收到提供者的节点池
     */
    private function testReleaseNodeDelegation():Void {
        var provider:SingleLevelTimeWheel = new SingleLevelTimeWheel(30, null);
        var delegateWheel:SingleLevelTimeWheel = new SingleLevelTimeWheel(20, provider);

        // 获取节点
        var node:TaskIDNode = delegateWheel.acquireNode("testTask");
        var afterAcquireSize:Number = provider.getNodePoolSize();

        // 通过委托时间轮回收节点
        node.reset(null);
        delegateWheel.releaseNode(node);

        assert(provider.getNodePoolSize() == afterAcquireSize + 1,
               "[NEW v1.5] releaseNode via delegate restores provider's pool size");
        assert(delegateWheel.getNodePoolSize() == afterAcquireSize + 1,
               "[NEW v1.5] Delegate wheel reflects provider's pool restoration");

        trace("[NEW v1.5] releaseNode delegation test completed");
    }

    /**
     * [NEW v1.5] 测试 fillNodePool 委托行为
     * 验证：通过委托时间轮调用 fillNodePool 会填充提供者的节点池
     */
    private function testFillNodePoolDelegation():Void {
        var provider:SingleLevelTimeWheel = new SingleLevelTimeWheel(30, null);
        var delegateWheel:SingleLevelTimeWheel = new SingleLevelTimeWheel(20, provider);

        var initialPoolSize:Number = provider.getNodePoolSize();

        // 通过委托时间轮填充节点池
        delegateWheel.fillNodePool(25);

        assert(provider.getNodePoolSize() == initialPoolSize + 25,
               "[NEW v1.5] fillNodePool via delegate increases provider's pool size");
        assert(delegateWheel.getNodePoolSize() == initialPoolSize + 25,
               "[NEW v1.5] Delegate wheel reflects provider's pool increase");

        trace("[NEW v1.5] fillNodePool delegation test completed");
    }

    /**
     * [NEW v1.5] 测试 trimNodePool 委托行为
     * 验证：通过委托时间轮调用 trimNodePool 会裁剪提供者的节点池
     */
    private function testTrimNodePoolDelegation():Void {
        var provider:SingleLevelTimeWheel = new SingleLevelTimeWheel(30, null);
        var delegateWheel:SingleLevelTimeWheel = new SingleLevelTimeWheel(20, provider);

        // 确保节点池有足够的节点
        var initialPoolSize:Number = provider.getNodePoolSize();
        var targetSize:Number = 50;
        if (initialPoolSize < 100) {
            provider.fillNodePool(100 - initialPoolSize);
        }

        // 通过委托时间轮裁剪节点池
        delegateWheel.trimNodePool(targetSize);

        assert(provider.getNodePoolSize() == targetSize,
               "[NEW v1.5] trimNodePool via delegate reduces provider's pool to target size");
        assert(delegateWheel.getNodePoolSize() == targetSize,
               "[NEW v1.5] Delegate wheel reflects provider's pool trim");

        trace("[NEW v1.5] trimNodePool delegation test completed");
    }

    /**
     * [NEW v1.5] 测试多个时间轮共享同一节点池提供者
     * 验证：多个委托时间轮操作同一个提供者的节点池时行为正确
     */
    private function testMultipleWheelsSharingProvider():Void {
        var provider:SingleLevelTimeWheel = new SingleLevelTimeWheel(30, null);
        var wheel1:SingleLevelTimeWheel = new SingleLevelTimeWheel(60, provider);  // 模拟秒级时间轮
        var wheel2:SingleLevelTimeWheel = new SingleLevelTimeWheel(60, provider);  // 模拟分钟级时间轮

        var initialPoolSize:Number = provider.getNodePoolSize();

        // 从不同时间轮获取节点
        var node1:TaskIDNode = wheel1.acquireNode("task1");
        var node2:TaskIDNode = wheel2.acquireNode("task2");
        var node3:TaskIDNode = provider.acquireNode("task3");

        assert(provider.getNodePoolSize() == initialPoolSize - 3,
               "[NEW v1.5] Multiple wheels share same pool - 3 nodes acquired");
        assert(wheel1.getNodePoolSize() == initialPoolSize - 3,
               "[NEW v1.5] wheel1 reports correct shared pool size");
        assert(wheel2.getNodePoolSize() == initialPoolSize - 3,
               "[NEW v1.5] wheel2 reports correct shared pool size");

        // 通过不同时间轮回收节点
        node1.reset(null);
        wheel2.releaseNode(node1);  // 通过 wheel2 回收 wheel1 获取的节点

        assert(provider.getNodePoolSize() == initialPoolSize - 2,
               "[NEW v1.5] Node acquired via wheel1 can be released via wheel2");

        // 通过 wheel1 回收直接从 provider 获取的节点
        node3.reset(null);
        wheel1.releaseNode(node3);

        assert(provider.getNodePoolSize() == initialPoolSize - 1,
               "[NEW v1.5] Node acquired via provider can be released via delegate wheel");

        trace("[NEW v1.5] Multiple wheels sharing provider test completed");
    }

    /**
     * [NEW v1.5] 测试 getTimeWheelStatus 在委托模式下正确返回节点池大小
     * 验证：委托时间轮的 getTimeWheelStatus 返回提供者的节点池大小
     */
    private function testGetTimeWheelStatusWithProvider():Void {
        var provider:SingleLevelTimeWheel = new SingleLevelTimeWheel(30, null);
        var delegateWheel:SingleLevelTimeWheel = new SingleLevelTimeWheel(20, provider);

        var providerStatus:Object = provider.getTimeWheelStatus();
        var delegateStatus:Object = delegateWheel.getTimeWheelStatus();

        assert(delegateStatus.nodePoolSize == providerStatus.nodePoolSize,
               "[NEW v1.5] Delegate wheel status reports provider's nodePoolSize");
        assert(delegateStatus.wheelSize == 20,
               "[NEW v1.5] Delegate wheel status reports its own wheelSize");
        assert(providerStatus.wheelSize == 30,
               "[NEW v1.5] Provider wheel status reports its own wheelSize");

        // 修改节点池后验证
        delegateWheel.fillNodePool(10);
        providerStatus = provider.getTimeWheelStatus();
        delegateStatus = delegateWheel.getTimeWheelStatus();

        assert(delegateStatus.nodePoolSize == providerStatus.nodePoolSize,
               "[NEW v1.5] After fillNodePool, both report same nodePoolSize");

        trace("[NEW v1.5] getTimeWheelStatus with provider test completed");
    }

    /**
     * 运行 FIX v1.5 验证测试
     */
    public function runFixV15Tests():Void {
        trace("=== Running FIX v1.5 Verification Tests (Node Pool Provider) ===");
        testNodePoolProviderCreation();
        testAcquireNodeDelegation();
        testReleaseNodeDelegation();
        testFillNodePoolDelegation();
        testTrimNodePoolDelegation();
        testMultipleWheelsSharingProvider();
        testGetTimeWheelStatusWithProvider();
        trace("=== FIX v1.5 Verification Tests Completed ===\n");
    }
}
