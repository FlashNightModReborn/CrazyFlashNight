import org.flashNight.naki.DataStructures.*;

/**
 * @class FrameTaskMinHeapTest
 * @package org.flashNight.naki.DataStructures
 * @description Comprehensive test suite for the FrameTaskMinHeap class, including both functional and performance tests.
 *              Incorporates an external taskMap to simulate real-world usage where taskID to node mapping is maintained externally.
 */
class org.flashNight.naki.DataStructures.FrameTaskMinHeapTest {
    private var heap:FrameTaskMinHeap;
    private var taskMap:Object; // External hash map: taskID -> TaskIDNode
    private var scales:Array = [100, 300, 1000, 3000, 10000, 30000, 100000]; // Define the scales for performance testing

    /**
     * @constructor
     * Initializes the test class without creating a heap instance. Each test method initializes the heap and taskMap.
     */
    public function FrameTaskMinHeapTest() {
        // Initialization is handled in each test method via resetHeap()
    }

    /**
     * @method assert
     * Helper function for assertions in tests.
     * @param {Boolean} condition - The condition to evaluate.
     * @param {String} message - The message to display for the assertion.
     */
    private function assert(condition:Boolean, message:String):Void {
        if (condition) {
            trace("PASS: " + message);
        } else {
            trace("FAIL: " + message);
        }
    }

    /**
     * @method resetHeap
     * Resets the heap instance and taskMap to ensure test isolation.
     */
    private function resetHeap():Void {
        this.heap = new FrameTaskMinHeap();
        this.taskMap = {}; // Initialize an empty task map
    }

    //=========================================================================
    // PUBLIC TEST RUNNERS
    //=========================================================================

    /**
     * @method runAllTests
     * 运行所有测试的便捷入口，包括功能测试、堆完整性测试和性能测试。
     * @param includePerformance 是否包含性能测试（默认false，因为性能测试耗时较长）
     */
    public function runAllTests(includePerformance:Boolean):Void {
        var startTime:Number = getTimer();

        trace("╔════════════════════════════════════════════════════════════╗");
        trace("║        FrameTaskMinHeap Complete Test Suite                ║");
        trace("╚════════════════════════════════════════════════════════════╝\n");

        // 1. 功能测试
        runFunctionTests();

        // 2. 堆完整性测试（关键测试）
        runHeapIntegrityTests();

        // 3. 性能测试（可选）
        if (includePerformance) {
            runPerformanceTests();
        } else {
            trace("=== Performance Tests Skipped (pass true to include) ===\n");
        }

        var endTime:Number = getTimer();
        trace("╔════════════════════════════════════════════════════════════╗");
        trace("║        All Tests Completed in " + (endTime - startTime) + " ms");
        trace("╚════════════════════════════════════════════════════════════╝");
    }

    /**
     * @method runQuickTests
     * 快速测试入口，仅运行功能测试和堆完整性测试，跳过耗时的性能测试。
     */
    public function runQuickTests():Void {
        runAllTests(false);
    }

    /**
     * @method runFullTests
     * 完整测试入口，运行所有测试包括性能测试。
     */
    public function runFullTests():Void {
        runAllTests(true);
    }

    /**
     * @method runFunctionTests
     * Executes all functional tests.
     */
    public function runFunctionTests():Void {
        trace("=== Running Functional Tests ===");
        testInsert();
        testFindNodeById();
        testPeekMin();
        testRemoveById();
        testRescheduleTimerByID();
        testTick();
        testEdgeCases();
        trace("=== Functional Tests Completed ===\n");
    }

    /**
     * @method runHeapIntegrityTests
     * Executes comprehensive heap integrity tests to verify bubbleUp, sinkDown,
     * index mapping consistency, and min-heap property.
     * These tests are designed to detect subtle bugs in heap operations.
     */
    public function runHeapIntegrityTests():Void {
        trace("=== Running Heap Integrity Tests ===");

        trace("\n--- BubbleUp Tests ---");
        testBubbleUpDescendingOrder();
        testBubbleUpRandomOrder();
        testBubbleUpLargeScale();
        testBubbleUpAllMethods();

        trace("\n--- SinkDown Tests ---");
        testSinkDownExtractMin();
        testSinkDownRemoveMiddle();
        testSinkDownRemoveRoot();
        testSinkDownRemoveLeaf();

        trace("\n--- Index Mapping Tests ---");
        testIndexMappingAfterInsert();
        testIndexMappingAfterRemoval();
        testIndexMappingAfterExtract();

        trace("\n--- Min-Heap Property Tests ---");
        testMinHeapPropertyAfterInserts();
        testMinHeapPropertyAfterRemovals();
        testMinHeapPropertyAfterExtracts();

        trace("\n--- Edge Case Tests ---");
        testSingleElement();
        testSameFrameTasks();
        testVariousChildCounts();
        testAlternatingOperations();

        trace("\n=== Heap Integrity Tests Completed ===\n");
    }

    /**
     * @method runPerformanceTests
     * Executes all performance tests across multiple scales, utilizing the external taskMap for efficiency.
     */
    public function runPerformanceTests():Void {
        trace("=== Running Performance Tests ===");
        for (var s:Number = 0; s < scales.length; s++) {
            var scale:Number = scales[s];
            trace("\n--- Performance Tests for Scale: " + scale + " ---");

            testInsertPerformance(scale);
            testFindPerformance(scale);
            testPeekMinPerformance(scale);
            testRemovePerformance(scale);
            testReschedulePerformance(scale);
            testTickPerformance(scale);
        }
        trace("\n=== Performance Tests Completed ===\n");
    }

    /**
     * @method testInsert
     * Tests the insertion of tasks with various frame delays.
     */
    private function testInsert():Void {
        resetHeap();
        heap.insert("task1", 5);
        taskMap["task1"] = heap.findNodeById("task1"); // Store in taskMap
        heap.insert("task2", 3);
        taskMap["task2"] = heap.findNodeById("task2"); // Store in taskMap
        heap.insert("task3", 10);
        taskMap["task3"] = heap.findNodeById("task3"); // Store in taskMap

        var minFrame:Object = heap.peekMin();
        assert(minFrame.frame == 3, "Insert operations correctly identify the minimum frame index.");

        var tasksAtFrame3:TaskIDLinkedList = minFrame.tasks;
        var firstTask:TaskIDNode = tasksAtFrame3.getFirst();
        assert(firstTask.taskID == "task2", "Insert operations correctly schedule tasks at their intended frames.");
    }

    /**
     * @method testFindNodeById
     * Tests the ability to find tasks by their taskID.
     */
    private function testFindNodeById():Void {
        resetHeap();
        heap.insert("task1", 5);
        taskMap["task1"] = heap.findNodeById("task1"); // Store in taskMap
        heap.insert("task2", 3);
        taskMap["task2"] = heap.findNodeById("task2"); // Store in taskMap

        var node:TaskIDNode = heap.findNodeById("task1");
        assert(node != null && node.taskID == "task1" && node.slotIndex == 5, "FindNodeById correctly locates existing tasks.");

        var nonExistentNode:TaskIDNode = heap.findNodeById("taskX");
        assert(nonExistentNode == null, "FindNodeById returns null for non-existent tasks.");
    }

    /**
     * @method testPeekMin
     * Tests peeking at the minimum frame without removing it.
     */
    private function testPeekMin():Void {
        resetHeap();
        heap.insert("task1", 5);
        taskMap["task1"] = heap.findNodeById("task1"); // Store in taskMap
        heap.insert("task2", 3);
        taskMap["task2"] = heap.findNodeById("task2"); // Store in taskMap
        heap.insert("task3", 10);
        taskMap["task3"] = heap.findNodeById("task3"); // Store in taskMap

        var minFrame:Object = heap.peekMin();
        assert(minFrame.frame == 3, "PeekMin correctly identifies the minimum frame index.");

        var tasksAtFrame3:TaskIDLinkedList = minFrame.tasks;
        var firstTask:TaskIDNode = tasksAtFrame3.getFirst();
        assert(firstTask.taskID == "task2", "PeekMin correctly identifies tasks at the minimum frame.");

        // Test peekMin on empty heap
        heap = new FrameTaskMinHeap();
        taskMap = {}; // Reset taskMap
        var emptyPeek:Object = heap.peekMin();
        assert(emptyPeek == null, "PeekMin returns null for an empty heap.");
    }

    /**
     * @method testRemoveById
     * Tests removing tasks by their taskID using the external taskMap.
     */
    private function testRemoveById():Void {
        resetHeap();
        heap.insert("task1", 5);
        taskMap["task1"] = heap.findNodeById("task1"); // Store in taskMap
        heap.insert("task2", 3);
        taskMap["task2"] = heap.findNodeById("task2"); // Store in taskMap
        heap.insert("task3", 10);
        taskMap["task3"] = heap.findNodeById("task3"); // Store in taskMap

        heap.removeById("task2");
        delete taskMap["task2"]; // Remove from taskMap
        var node:TaskIDNode = heap.findNodeById("task2");
        assert(node == null, "RemoveById correctly deletes the specified task.");

        var minFrame:Object = heap.peekMin();
        assert(minFrame.frame == 5, "Heap correctly updates the minimum frame after removal.");
    }

    /**
     * @method testRescheduleTimerByID
     * Tests rescheduling tasks with a new frame delay using the external taskMap.
     */
    private function testRescheduleTimerByID():Void {
        resetHeap();
        heap.insert("task1", 5);
        taskMap["task1"] = heap.findNodeById("task1"); // Store in taskMap
        heap.insert("task2", 3);
        taskMap["task2"] = heap.findNodeById("task2"); // Store in taskMap

        heap.rescheduleTimerByID("task1", 2);
        var node:TaskIDNode = heap.findNodeById("task1");
        taskMap["task1"] = node; // Update taskMap if node reference changes
        assert(node != null && node.slotIndex == 2, "RescheduleTimerByID correctly updates the task's frame index.");

        var minFrame:Object = heap.peekMin();
        assert(minFrame.frame == 2, "Heap correctly updates the minimum frame after rescheduling.");
    }

    /**
     * @method testTick
     * Tests advancing frames and retrieving due tasks.
     */
    private function testTick():Void {
        resetHeap();
        heap.insert("task1", 2);
        taskMap["task1"] = heap.findNodeById("task1"); // Store in taskMap
        heap.insert("task2", 3);
        taskMap["task2"] = heap.findNodeById("task2"); // Store in taskMap
        heap.insert("task3", 1);
        taskMap["task3"] = heap.findNodeById("task3"); // Store in taskMap

        // Frame 1
        var dueTasks:TaskIDLinkedList = heap.tick();
        assert(dueTasks != null, "Tick correctly retrieves due tasks at frame 1.");
        var firstDueTask:TaskIDNode = dueTasks.getFirst();
        assert(firstDueTask.taskID == "task3", "Tick correctly identifies the due task at frame 1.");

        // Frame 2
        dueTasks = heap.tick();
        assert(dueTasks != null, "Tick correctly retrieves due tasks at frame 2.");
        firstDueTask = dueTasks.getFirst();
        assert(firstDueTask.taskID == "task1", "Tick correctly identifies the due task at frame 2.");

        // Frame 3
        dueTasks = heap.tick();
        assert(dueTasks != null, "Tick correctly retrieves due tasks at frame 3.");
        firstDueTask = dueTasks.getFirst();
        assert(firstDueTask.taskID == "task2", "Tick correctly identifies the due task at frame 3.");

        // Frame 4 (no tasks)
        dueTasks = heap.tick();
        assert(dueTasks == null, "Tick returns null when there are no due tasks.");
    }

    /**
     * @method testEdgeCases
     * Tests various edge cases to ensure robustness.
     */
    private function testEdgeCases():Void {
        resetHeap();

        // Attempt to remove a non-existent task
        heap.insert("task1", 5);
        taskMap["task1"] = heap.findNodeById("task1"); // Store in taskMap
        heap.removeById("taskX"); // Non-existent
        var node:TaskIDNode = heap.findNodeById("task1");
        assert(node != null, "RemoveById gracefully handles non-existent task IDs without affecting existing tasks.");

        // Attempt to reschedule a non-existent task
        heap.rescheduleTimerByID("taskY", 10); // Non-existent
        var existingNode:TaskIDNode = heap.findNodeById("task1");
        assert(existingNode.slotIndex == 5, "RescheduleTimerByID gracefully handles non-existent task IDs without affecting existing tasks.");

        // Insert duplicate task IDs (assuming overwrite is allowed)
        heap.insert("task1", 3);
        taskMap["task1"] = heap.findNodeById("task1"); // Update taskMap
        var updatedNode:TaskIDNode = heap.findNodeById("task1");
        assert(updatedNode != null && updatedNode.slotIndex == 3, "Inserting a duplicate task ID updates the existing task's frame index.");
    }

    /**
     * @method testInsertPerformance
     * Measures the time taken to insert a large number of tasks using the addTimerByID method with loop unrolling.
     * @param {Number} scale - The number of inserts to perform.
     */
    private function testInsertPerformance(scale:Number):Void {
        resetHeap();
        var startTime:Number = getTimer();
        var i:Number = 0;
        var totalInserts:Number = scale;
        var unrollFactor:Number = 4;

        // Calculate the number of full unrolled iterations
        var fullIterations:Number = Math.floor(totalInserts / unrollFactor);
        var remaining:Number = totalInserts % unrollFactor;

        // Loop unrolled by a factor of 4
        for (i = 0; i < fullIterations * unrollFactor; i += unrollFactor) {
            // Insert Task 1
            var taskID1:String = "task" + i;
            var node1:TaskIDNode = heap.addTimerByID(taskID1, Math.floor(Math.random() * 1000));
            taskMap[taskID1] = node1;

            // Insert Task 2
            var taskID2:String = "task" + (i + 1);
            var node2:TaskIDNode = heap.addTimerByID(taskID2, Math.floor(Math.random() * 1000));
            taskMap[taskID2] = node2;

            // Insert Task 3
            var taskID3:String = "task" + (i + 2);
            var node3:TaskIDNode = heap.addTimerByID(taskID3, Math.floor(Math.random() * 1000));
            taskMap[taskID3] = node3;

            // Insert Task 4
            var taskID4:String = "task" + (i + 3);
            var node4:TaskIDNode = heap.addTimerByID(taskID4, Math.floor(Math.random() * 1000));
            taskMap[taskID4] = node4;
        }

        // Handle any remaining inserts
        for (; i < totalInserts; i++) {
            var taskID:String = "task" + i;
            var node:TaskIDNode = heap.addTimerByID(taskID, Math.floor(Math.random() * 1000));
            taskMap[taskID] = node;
        }

        var endTime:Number = getTimer();
        trace("Insert Performance (" + scale + "): " + (endTime - startTime) + " ms using addTimerByID with loop unrolling");
    }

    /**
     * @method testFindPerformance
     * Measures the time taken to find a large number of tasks by their taskID using the external taskMap with loop unrolling.
     * @param {Number} scale - The number of finds to perform.
     */
    private function testFindPerformance(scale:Number):Void {
        resetHeap();
        // Insert 'scale' number of tasks
        for (var i:Number = 0; i < scale; i++) {
            var taskID:String = "task" + i;
            var node:TaskIDNode = heap.addTimerByID(taskID, Math.floor(Math.random() * 1000));
            taskMap[taskID] = node; // Store in taskMap
        }

        var startTime:Number = getTimer();
        var j:Number = 0;
        var unrollFactorFind:Number = 4;
        var fullIterationsFind:Number = Math.floor(scale / unrollFactorFind);
        var remainingFind:Number = scale % unrollFactorFind;

        // Loop unrolled by a factor of 4
        for (j = 0; j < fullIterationsFind * unrollFactorFind; j += unrollFactorFind) {
            var nodeA:TaskIDNode = taskMap["task" + j];
            var nodeB:TaskIDNode = taskMap["task" + (j + 1)];
            var nodeC:TaskIDNode = taskMap["task" + (j + 2)];
            var nodeD:TaskIDNode = taskMap["task" + (j + 3)];
            // Optionally perform operations with nodeA, nodeB, nodeC, nodeD
            // For testing, we're just accessing the nodes
        }

        // Handle any remaining finds
        for (; j < scale; j++) {
            var nodeE:TaskIDNode = taskMap["task" + j];
            // Optionally perform operations with nodeE
        }

        var endTime:Number = getTimer();
        trace("Find Performance (" + scale + "): " + (endTime - startTime) + " ms using taskMap with loop unrolling");
    }

    /**
     * @method testPeekMinPerformance
     * Measures the time taken to repeatedly peek at the minimum frame with loop unrolling.
     * @param {Number} scale - The number of peek operations to perform.
     */
    private function testPeekMinPerformance(scale:Number):Void {
        resetHeap();
        // Insert 'scale' number of tasks
        for (var i:Number = 0; i < scale; i++) {
            var taskID:String = "task" + i;
            var delay:Number = Math.floor(Math.random() * 1000);
            var node:TaskIDNode = heap.addTimerByID(taskID, delay);
            taskMap[taskID] = node; // Store in taskMap
        }

        var startTime:Number = getTimer();
        var totalPeeks:Number = scale; // Number of peek operations
        var peekUnrollFactor:Number = 4;
        var fullIterationsPeek:Number = Math.floor(totalPeeks / peekUnrollFactor);
        var remainingPeek:Number = totalPeeks % peekUnrollFactor;

        // Loop unrolled by a factor of 4
        for (var j:Number = 0; j < fullIterationsPeek * peekUnrollFactor; j += peekUnrollFactor) {
            heap.peekMin();
            heap.peekMin();
            heap.peekMin();
            heap.peekMin();
        }

        // Handle any remaining peeks
        for (; j < totalPeeks; j++) {
            heap.peekMin();
        }

        var endTime:Number = getTimer();
        trace("PeekMin Performance (" + totalPeeks + "): " + (endTime - startTime) + " ms with loop unrolling");
    }

    /**
     * @method testRemovePerformance
     * Measures the time taken to remove a large number of tasks using the external taskMap with loop unrolling.
     * @param {Number} scale - The number of removals to perform.
     */
    private function testRemovePerformance(scale:Number):Void {
        resetHeap();
        // Insert 'scale' number of tasks
        for (var i:Number = 0; i < scale; i++) {
            var taskID:String = "task" + i;
            var node:TaskIDNode = heap.addTimerByID(taskID, Math.floor(Math.random() * 1000));
            taskMap[taskID] = node; // Store in taskMap
        }

        var startTime:Number = getTimer();
        var j:Number = 0;
        var unrollFactorRemove:Number = 4;
        var fullIterationsRemove:Number = Math.floor(scale / unrollFactorRemove);
        var remainingRemove:Number = scale % unrollFactorRemove;

        // Loop unrolled by a factor of 4
        for (j = 0; j < fullIterationsRemove * unrollFactorRemove; j += unrollFactorRemove) {
            // Remove Task 1
            var currentTaskID1:String = "task" + j;
            var node1:TaskIDNode = taskMap[currentTaskID1];
            if (node1 != null) {
                heap.removeDirectly(node1); // Direct removal using node reference
                delete taskMap[currentTaskID1]; // Remove from taskMap
            }

            // Remove Task 2
            var currentTaskID2:String = "task" + (j + 1);
            var node2:TaskIDNode = taskMap[currentTaskID2];
            if (node2 != null) {
                heap.removeDirectly(node2); // Direct removal using node reference
                delete taskMap[currentTaskID2]; // Remove from taskMap
            }

            // Remove Task 3
            var currentTaskID3:String = "task" + (j + 2);
            var node3:TaskIDNode = taskMap[currentTaskID3];
            if (node3 != null) {
                heap.removeDirectly(node3); // Direct removal using node reference
                delete taskMap[currentTaskID3]; // Remove from taskMap
            }

            // Remove Task 4
            var currentTaskID4:String = "task" + (j + 3);
            var node4:TaskIDNode = taskMap[currentTaskID4];
            if (node4 != null) {
                heap.removeDirectly(node4); // Direct removal using node reference
                delete taskMap[currentTaskID4]; // Remove from taskMap
            }
        }

        // Handle any remaining removals
        for (; j < scale; j++) {
            var currentTaskID:String = "task" + j;
            var node:TaskIDNode = taskMap[currentTaskID];
            if (node != null) {
                heap.removeDirectly(node); // Direct removal using node reference
                delete taskMap[currentTaskID]; // Remove from taskMap
            }
        }

        var endTime:Number = getTimer();
        trace("Remove Performance (" + scale + "): " + (endTime - startTime) + " ms using taskMap with loop unrolling");
    }

    /**
     * @method testReschedulePerformance
     * Measures the time taken to reschedule a large number of tasks using the external taskMap with loop unrolling.
     * @param {Number} scale - The number of reschedules to perform.
     */
    private function testReschedulePerformance(scale:Number):Void {
        resetHeap();
        // Insert 'scale' number of tasks
        for (var i:Number = 0; i < scale; i++) {
            var taskID:String = "task" + i;
            var node:TaskIDNode = heap.addTimerByID(taskID, Math.floor(Math.random() * 1000));
            taskMap[taskID] = node; // Store in taskMap
        }

        var startTime:Number = getTimer();
        var j:Number = 0;
        var unrollFactorReschedule:Number = 4;
        var fullIterationsReschedule:Number = Math.floor(scale / unrollFactorReschedule);
        var remainingReschedule:Number = scale % unrollFactorReschedule;

        // Loop unrolled by a factor of 4
        for (j = 0; j < fullIterationsReschedule * unrollFactorReschedule; j += unrollFactorReschedule) {
            // Reschedule Task 1
            var currentTaskID1:String = "task" + j;
            var node1:TaskIDNode = taskMap[currentTaskID1];
            if (node1 != null) {
                heap.rescheduleTimerByNode(node1, Math.floor(Math.random() * 1000)); // Direct reschedule using node reference
            }

            // Reschedule Task 2
            var currentTaskID2:String = "task" + (j + 1);
            var node2:TaskIDNode = taskMap[currentTaskID2];
            if (node2 != null) {
                heap.rescheduleTimerByNode(node2, Math.floor(Math.random() * 1000)); // Direct reschedule using node reference
            }

            // Reschedule Task 3
            var currentTaskID3:String = "task" + (j + 2);
            var node3:TaskIDNode = taskMap[currentTaskID3];
            if (node3 != null) {
                heap.rescheduleTimerByNode(node3, Math.floor(Math.random() * 1000)); // Direct reschedule using node reference
            }

            // Reschedule Task 4
            var currentTaskID4:String = "task" + (j + 3);
            var node4:TaskIDNode = taskMap[currentTaskID4];
            if (node4 != null) {
                heap.rescheduleTimerByNode(node4, Math.floor(Math.random() * 1000)); // Direct reschedule using node reference
            }
        }

        // Handle any remaining reschedules
        for (; j < scale; j++) {
            var currentTaskID:String = "task" + j;
            var node:TaskIDNode = taskMap[currentTaskID];
            if (node != null) {
                heap.rescheduleTimerByNode(node, Math.floor(Math.random() * 1000)); // Direct reschedule using node reference
            }
        }

        var endTime:Number = getTimer();
        trace("Reschedule Performance (" + scale + "): " + (endTime - startTime) + " ms using taskMap with loop unrolling");
    }

    /**
     * @method testTickPerformance
     * Measures the time taken to process a large number of frame ticks with loop unrolling.
     * @param {Number} scale - The number of ticks to perform (should match the number of inserted tasks).
     */
    private function testTickPerformance(scale:Number):Void {
        resetHeap();
        // Insert 'scale' number of tasks with varying delays
        for (var i:Number = 0; i < scale; i++) {
            var taskID:String = "task" + i;
            var delay:Number = Math.floor(Math.random() * 1000);
            var node:TaskIDNode = heap.addTimerByID(taskID, delay);
            taskMap[taskID] = node; // Store in taskMap
        }

        var startTime:Number = getTimer();
        var ticksProcessed:Number = 0;

        while (heap.peekMin() != null) {
            heap.tick();
            ticksProcessed++;
        }

        var endTime:Number = getTimer();
        trace("Tick Performance (" + ticksProcessed + "): " + (endTime - startTime) + " ms to process ticks with loop unrolling");
    }

    //=========================================================================
    // HEAP INTEGRITY TESTS - BubbleUp
    //=========================================================================

    /**
     * 测试倒序插入（最坏情况：每次都需要上浮到堆顶）
     * 覆盖：bubbleUp 多次迭代，验证堆结构和提取顺序
     */
    private function testBubbleUpDescendingOrder():Void {
        resetHeap();
        var n:Number = 20;

        // 倒序插入：20, 19, 18, ..., 1
        for (var i:Number = n; i >= 1; i--) {
            heap.insert("task" + i, i);
        }

        // 验证堆顶是最小值
        var minFrame:Object = heap.peekMin();
        var expectedMin:Number = heap.currentFrame + 1;
        assert(minFrame.frame == expectedMin,
               "BubbleUp descending: heap top should be " + expectedMin + ", got " + minFrame.frame);

        // 验证索引映射一致性
        var mappingValid:Boolean = verifyIndexMapping();
        assert(mappingValid, "BubbleUp descending: index mapping should be consistent");

        // 验证最小堆性质
        var heapValid:Boolean = verifyMinHeapProperty();
        assert(heapValid, "BubbleUp descending: min-heap property should hold");

        // 验证按正确顺序提取
        var lastFrame:Number = -1;
        var extractCount:Number = 0;
        while (heap.peekMin() != null) {
            var frame:Number = heap.peekMin().frame;
            assert(frame >= lastFrame,
                   "BubbleUp descending: extraction order violated at count " + extractCount);
            lastFrame = frame;
            heap.tick();
            extractCount++;
        }
        assert(extractCount == n, "BubbleUp descending: should extract " + n + " tasks, got " + extractCount);
    }

    /**
     * 测试随机顺序插入
     * 覆盖：bubbleUp 不同深度
     */
    private function testBubbleUpRandomOrder():Void {
        resetHeap();
        var delays:Array = [50, 20, 80, 10, 60, 30, 90, 5, 70, 40, 100, 15, 25, 35, 45];

        for (var i:Number = 0; i < delays.length; i++) {
            heap.insert("task" + i, delays[i]);
        }

        // 验证索引映射一致性
        var mappingValid:Boolean = verifyIndexMapping();
        assert(mappingValid, "BubbleUp random: index mapping should be consistent");

        // 验证最小堆性质
        var heapValid:Boolean = verifyMinHeapProperty();
        assert(heapValid, "BubbleUp random: min-heap property should hold");

        // 验证提取顺序正确
        var sortedDelays:Array = delays.slice();
        sortedDelays.sort(function(a, b) { return a - b; });

        var extractedFrames:Array = [];
        while (heap.peekMin() != null) {
            extractedFrames.push(heap.peekMin().frame);
            heap.tick();
        }

        // 由于多个任务可能在同一帧，我们只验证顺序是递增的
        var orderCorrect:Boolean = true;
        for (var j:Number = 1; j < extractedFrames.length; j++) {
            if (extractedFrames[j] < extractedFrames[j-1]) {
                orderCorrect = false;
                break;
            }
        }
        assert(orderCorrect, "BubbleUp random: extraction order should be ascending");
    }

    /**
     * 测试大规模插入 - 触发4叉堆的多层结构
     * 覆盖：remaining >= 5（4个子节点的情况）
     */
    private function testBubbleUpLargeScale():Void {
        resetHeap();
        var n:Number = 100;

        // 倒序插入确保每次都需要上浮
        for (var i:Number = n; i >= 1; i--) {
            heap.insert("task" + i, i);
        }

        // 验证索引映射
        var mappingValid:Boolean = verifyIndexMapping();
        assert(mappingValid, "BubbleUp large scale: index mapping should be consistent");

        // 验证堆性质
        var heapValid:Boolean = verifyMinHeapProperty();
        assert(heapValid, "BubbleUp large scale: min-heap property should hold");

        // 验证提取顺序
        var lastFrame:Number = -1;
        var count:Number = 0;
        while (heap.peekMin() != null) {
            var frame:Number = heap.peekMin().frame;
            if (frame < lastFrame) {
                assert(false, "BubbleUp large scale: order violated at position " + count +
                              ", expected >= " + lastFrame + " but got " + frame);
                return;
            }
            lastFrame = frame;
            heap.tick();
            count++;
        }
        assert(count == n, "BubbleUp large scale: should extract " + n + " tasks");
    }

    /**
     * 测试所有插入方法（insert, insertNode, addTimerByID, addTimerByNode）
     * 验证它们都产生正确的堆结构
     */
    private function testBubbleUpAllMethods():Void {
        resetHeap();

        // 使用 insert
        heap.insert("insert1", 50);
        heap.insert("insert2", 10);

        // 使用 addTimerByID
        var node1:TaskIDNode = heap.addTimerByID("addById1", 30);
        var node2:TaskIDNode = heap.addTimerByID("addById2", 5);

        // 使用 insertNode（需要先创建节点）
        var node3:TaskIDNode = heap.addTimerByID("insertNode1", 40);
        heap.removeDirectly(node3);
        node3.reset("insertNode1_new");
        heap.insertNode(node3, 20);

        // 使用 addTimerByNode
        var node4:TaskIDNode = heap.addTimerByID("addByNode1", 60);
        heap.removeDirectly(node4);
        node4.reset("addByNode1_new");
        heap.addTimerByNode(node4, 15);

        // 验证索引映射
        var mappingValid:Boolean = verifyIndexMapping();
        assert(mappingValid, "BubbleUp all methods: index mapping should be consistent");

        // 验证堆性质
        var heapValid:Boolean = verifyMinHeapProperty();
        assert(heapValid, "BubbleUp all methods: min-heap property should hold");

        // 验证堆顶是最小值（应该是5）
        var minFrame:Object = heap.peekMin();
        assert(minFrame.frame == heap.currentFrame + 5,
               "BubbleUp all methods: min should be 5, got " + (minFrame.frame - heap.currentFrame));
    }

    //=========================================================================
    // HEAP INTEGRITY TESTS - SinkDown
    //=========================================================================

    /**
     * 测试连续提取最小值
     * 覆盖：extractTasksAtMinFrame 的 sinkDown
     */
    private function testSinkDownExtractMin():Void {
        resetHeap();
        var delays:Array = [5, 3, 8, 1, 6, 2, 9, 4, 7, 10, 15, 12, 18, 11, 14];

        for (var i:Number = 0; i < delays.length; i++) {
            heap.insert("task" + i, delays[i]);
        }

        // 统计堆中唯一帧的数量（因为每个delay都是唯一的，所以等于delays.length）
        var uniqueFrames:Number = heap["heapSize"];

        var lastFrame:Number = -1;
        var extractedFrameCount:Number = 0;
        while (heap.peekMin() != null) {
            // 每次提取前验证堆性质
            var heapValid:Boolean = verifyMinHeapProperty();
            if (!heapValid) {
                assert(false, "SinkDown extract: heap property violated before extraction " + extractedFrameCount);
                return;
            }

            var frame:Number = heap.peekMin().frame;
            assert(frame >= lastFrame,
                   "SinkDown extract: frame " + frame + " should be >= " + lastFrame);
            lastFrame = frame;

            var extracted:TaskIDLinkedList = heap.tick();
            if (extracted != null) {
                extractedFrameCount++;
            }

            // 提取后验证索引映射
            if (heap.peekMin() != null) {
                var mappingValid:Boolean = verifyIndexMapping();
                if (!mappingValid) {
                    assert(false, "SinkDown extract: index mapping invalid after extraction " + extractedFrameCount);
                    return;
                }
            }
        }
        assert(extractedFrameCount == uniqueFrames, "SinkDown extract: should extract all " + uniqueFrames + " unique frames, got " + extractedFrameCount);
    }

    /**
     * 测试删除中间节点
     * 覆盖：removeNode 的 sinkDown
     */
    private function testSinkDownRemoveMiddle():Void {
        resetHeap();
        // 插入20个任务
        for (var i:Number = 1; i <= 20; i++) {
            heap.insert("task" + i, i * 10);
            taskMap["task" + i] = heap.findNodeById("task" + i);
        }

        // 删除中间的任务（第7, 10, 13个）
        var nodesToRemove:Array = ["task7", "task10", "task13"];
        for (var j:Number = 0; j < nodesToRemove.length; j++) {
            var taskId:String = nodesToRemove[j];
            var node:TaskIDNode = taskMap[taskId];
            if (node != null) {
                heap.removeDirectly(node);
                delete taskMap[taskId];

                // 每次删除后验证
                var mappingValid:Boolean = verifyIndexMapping();
                assert(mappingValid, "SinkDown remove middle: mapping valid after removing " + taskId);

                var heapValid:Boolean = verifyMinHeapProperty();
                assert(heapValid, "SinkDown remove middle: heap property valid after removing " + taskId);
            }
        }

        // 记录删除后堆中的唯一帧数量
        var remainingFrames:Number = heap["heapSize"];

        // 验证剩余任务按正确顺序提取
        var lastFrame:Number = -1;
        var extractedCount:Number = 0;
        while (heap.peekMin() != null) {
            var frame:Number = heap.peekMin().frame;
            assert(frame >= lastFrame,
                   "SinkDown remove middle: order violated at count " + extractedCount);
            lastFrame = frame;

            var extracted:TaskIDLinkedList = heap.tick();
            if (extracted != null) {
                extractedCount++;
            }
        }
        assert(extractedCount == remainingFrames, "SinkDown remove middle: should extract " + remainingFrames + " frames, got " + extractedCount);
    }

    /**
     * 测试删除根节点（通过removeNode而非tick）
     */
    private function testSinkDownRemoveRoot():Void {
        resetHeap();
        for (var i:Number = 1; i <= 15; i++) {
            heap.insert("task" + i, i * 5);
            taskMap["task" + i] = heap.findNodeById("task" + i);
        }

        // 连续删除根节点3次
        for (var j:Number = 0; j < 3; j++) {
            var minFrame:Object = heap.peekMin();
            if (minFrame != null) {
                var rootNode:TaskIDNode = minFrame.tasks.getFirst();
                heap.removeDirectly(rootNode);

                var mappingValid:Boolean = verifyIndexMapping();
                assert(mappingValid, "SinkDown remove root: mapping valid after removal " + (j+1));

                var heapValid:Boolean = verifyMinHeapProperty();
                assert(heapValid, "SinkDown remove root: heap property valid after removal " + (j+1));
            }
        }
    }

    /**
     * 测试删除叶子节点
     */
    private function testSinkDownRemoveLeaf():Void {
        resetHeap();
        // 插入构造特定堆结构
        var delays:Array = [10, 20, 30, 40, 50, 60, 70, 80];
        for (var i:Number = 0; i < delays.length; i++) {
            heap.insert("task" + i, delays[i]);
            taskMap["task" + i] = heap.findNodeById("task" + i);
        }

        // 删除最后插入的几个（叶子节点）
        var leafTasks:Array = ["task7", "task6", "task5"];
        for (var j:Number = 0; j < leafTasks.length; j++) {
            var node:TaskIDNode = taskMap[leafTasks[j]];
            if (node != null) {
                heap.removeDirectly(node);

                var mappingValid:Boolean = verifyIndexMapping();
                assert(mappingValid, "SinkDown remove leaf: mapping valid after removing " + leafTasks[j]);

                var heapValid:Boolean = verifyMinHeapProperty();
                assert(heapValid, "SinkDown remove leaf: heap property valid after removing " + leafTasks[j]);
            }
        }
    }

    //=========================================================================
    // INDEX MAPPING TESTS
    //=========================================================================

    /**
     * 验证插入后 frameIndexToHeapIndex 映射的正确性
     */
    private function testIndexMappingAfterInsert():Void {
        resetHeap();
        var delays:Array = [30, 10, 50, 20, 40, 5, 25, 35, 15, 45];

        for (var i:Number = 0; i < delays.length; i++) {
            heap.insert("task" + i, delays[i]);

            // 每次插入后验证映射
            var valid:Boolean = verifyIndexMapping();
            assert(valid, "Index mapping insert: valid after inserting task" + i + " with delay " + delays[i]);
        }
    }

    /**
     * 验证删除后索引映射的一致性
     */
    private function testIndexMappingAfterRemoval():Void {
        resetHeap();
        for (var i:Number = 1; i <= 15; i++) {
            heap.insert("task" + i, i * 10);
            taskMap["task" + i] = heap.findNodeById("task" + i);
        }

        // 删除多个节点
        var toRemove:Array = ["task7", "task3", "task12", "task1", "task15"];
        for (var j:Number = 0; j < toRemove.length; j++) {
            var node:TaskIDNode = taskMap[toRemove[j]];
            if (node != null) {
                heap.removeDirectly(node);
                delete taskMap[toRemove[j]];

                var valid:Boolean = verifyIndexMapping();
                assert(valid, "Index mapping removal: valid after removing " + toRemove[j]);
            }
        }
    }

    /**
     * 验证提取后索引映射的一致性
     */
    private function testIndexMappingAfterExtract():Void {
        resetHeap();
        for (var i:Number = 1; i <= 20; i++) {
            heap.insert("task" + i, i);
        }

        // 提取一半的任务
        for (var j:Number = 0; j < 10; j++) {
            heap.tick();

            if (heap.peekMin() != null) {
                var valid:Boolean = verifyIndexMapping();
                assert(valid, "Index mapping extract: valid after extraction " + (j+1));
            }
        }
    }

    //=========================================================================
    // MIN-HEAP PROPERTY TESTS
    //=========================================================================

    /**
     * 验证多次插入后堆的最小堆性质
     */
    private function testMinHeapPropertyAfterInserts():Void {
        resetHeap();
        var delays:Array = [25, 10, 45, 5, 30, 15, 50, 20, 35, 8, 40, 12, 55, 18, 28, 3, 60, 22, 38, 7];

        for (var i:Number = 0; i < delays.length; i++) {
            heap.insert("task" + i, delays[i]);

            var valid:Boolean = verifyMinHeapProperty();
            assert(valid, "Min-heap property insert: valid after inserting " + delays[i]);
        }
    }

    /**
     * 验证删除后堆的最小堆性质
     */
    private function testMinHeapPropertyAfterRemovals():Void {
        resetHeap();
        for (var i:Number = 0; i < 25; i++) {
            heap.insert("task" + i, (i * 7) % 50 + 1); // 伪随机延迟
            taskMap["task" + i] = heap.findNodeById("task" + i);
        }

        // 删除一些节点
        var toRemove:Array = [5, 12, 3, 20, 8, 15, 0, 24];
        for (var j:Number = 0; j < toRemove.length; j++) {
            var taskId:String = "task" + toRemove[j];
            var node:TaskIDNode = taskMap[taskId];
            if (node != null) {
                heap.removeDirectly(node);

                var valid:Boolean = verifyMinHeapProperty();
                assert(valid, "Min-heap property removal: valid after removing " + taskId);
            }
        }
    }

    /**
     * 验证提取后堆的最小堆性质
     */
    private function testMinHeapPropertyAfterExtracts():Void {
        resetHeap();
        for (var i:Number = 0; i < 30; i++) {
            heap.insert("task" + i, (i * 11) % 60 + 1);
        }

        var count:Number = 0;
        while (heap.peekMin() != null && count < 20) {
            heap.tick();
            count++;

            if (heap.peekMin() != null) {
                var valid:Boolean = verifyMinHeapProperty();
                assert(valid, "Min-heap property extract: valid after extraction " + count);
            }
        }
    }

    //=========================================================================
    // EDGE CASE TESTS
    //=========================================================================

    /**
     * 测试只有一个元素的情况
     */
    private function testSingleElement():Void {
        resetHeap();
        heap.insert("task1", 5);

        assert(heap.peekMin().frame == heap.currentFrame + 5, "Single element: correct frame");

        var valid:Boolean = verifyIndexMapping();
        assert(valid, "Single element: index mapping valid");

        // tick到该帧前一帧（tick使用前缀++，所以4次tick后currentFrame=4，第5次tick时currentFrame变为5并提取）
        for (var i:Number = 0; i < 4; i++) {
            heap.tick();
        }

        var tasks:TaskIDLinkedList = heap.tick(); // 第5次tick：currentFrame变为5，提取frame=5的任务
        assert(tasks != null, "Single element: should be extracted");
        assert(heap.peekMin() == null, "Single element: heap should be empty after extraction");
    }

    /**
     * 测试所有任务在同一帧
     */
    private function testSameFrameTasks():Void {
        resetHeap();
        for (var i:Number = 0; i < 10; i++) {
            heap.insert("task" + i, 5);
        }

        // 应该只有一个帧索引在堆中
        var heapSize:Number = heap["heapSize"];
        assert(heapSize == 1, "Same frame: heap should have size 1, got " + heapSize);

        var valid:Boolean = verifyIndexMapping();
        assert(valid, "Same frame: index mapping valid");

        // tick到该帧前一帧（tick使用前缀++，所以4次tick后currentFrame=4，第5次tick时currentFrame变为5并提取）
        for (var j:Number = 0; j < 4; j++) {
            heap.tick();
        }

        var tasks:TaskIDLinkedList = heap.tick(); // 第5次tick：currentFrame变为5，一次性提取所有任务
        assert(tasks != null, "Same frame: should get tasks");

        var taskCount:Number = tasks.getSize();
        assert(taskCount == 10, "Same frame: should have 10 tasks, got " + taskCount);
    }

    /**
     * 测试4叉堆各种子节点数量情况
     * 覆盖：remaining = 2, 3, 4, >=5
     */
    private function testVariousChildCounts():Void {
        resetHeap();

        // 插入21个任务，确保覆盖各种子节点情况
        // 4叉堆：节点0有子节点1,2,3,4；节点1有子节点5,6,7,8；...
        for (var i:Number = 21; i >= 1; i--) {
            heap.insert("task" + i, i);
        }

        // 验证堆结构
        var mappingValid:Boolean = verifyIndexMapping();
        assert(mappingValid, "Various children: index mapping valid");

        var heapValid:Boolean = verifyMinHeapProperty();
        assert(heapValid, "Various children: min-heap property valid");

        // 验证提取顺序
        var lastFrame:Number = -1;
        var count:Number = 0;
        while (heap.peekMin() != null) {
            var frame:Number = heap.peekMin().frame;
            assert(frame >= lastFrame,
                   "Various children: order violated at " + count + ", expected >= " + lastFrame + " got " + frame);
            lastFrame = frame;
            heap.tick();
            count++;
        }
        assert(count == 21, "Various children: should extract 21 tasks");
    }

    /**
     * 测试交替插入和删除操作
     */
    private function testAlternatingOperations():Void {
        resetHeap();

        // 插入一些任务
        for (var i:Number = 0; i < 10; i++) {
            heap.insert("task" + i, (i + 1) * 10);
            taskMap["task" + i] = heap.findNodeById("task" + i);
        }

        // 交替删除和插入
        for (var j:Number = 0; j < 5; j++) {
            // 删除一个
            var removeId:String = "task" + (j * 2);
            var node:TaskIDNode = taskMap[removeId];
            if (node != null) {
                heap.removeDirectly(node);
                delete taskMap[removeId];
            }

            // 插入一个新的
            var newId:String = "newtask" + j;
            heap.insert(newId, j + 1);
            taskMap[newId] = heap.findNodeById(newId);

            // 验证
            var mappingValid:Boolean = verifyIndexMapping();
            assert(mappingValid, "Alternating ops: mapping valid at iteration " + j);

            var heapValid:Boolean = verifyMinHeapProperty();
            assert(heapValid, "Alternating ops: heap property valid at iteration " + j);
        }

        // 提取一些
        for (var k:Number = 0; k < 3; k++) {
            heap.tick();

            if (heap.peekMin() != null) {
                var valid:Boolean = verifyIndexMapping();
                assert(valid, "Alternating ops: mapping valid after extract " + k);
            }
        }
    }

    //=========================================================================
    // HELPER METHODS FOR VERIFICATION
    //=========================================================================

    /**
     * 验证 frameIndexToHeapIndex 映射的一致性
     * 对于堆中每个位置，其帧索引的映射应指回该位置
     * @return true 如果映射一致，false 否则
     */
    private function verifyIndexMapping():Boolean {
        var heapArray:Array = heap["heap"];
        var heapSize:Number = heap["heapSize"];
        var frameIndexToHeapIndex:Object = heap["frameIndexToHeapIndex"];

        for (var i:Number = 0; i < heapSize; i++) {
            var frameIndex:Number = heapArray[i];
            var mappedIndex:Number = frameIndexToHeapIndex[frameIndex];

            if (mappedIndex != i) {
                trace("  [DEBUG] Index mapping error: heap[" + i + "]=" + frameIndex +
                      " maps to " + mappedIndex + " instead of " + i);
                return false;
            }
        }
        return true;
    }

    /**
     * 验证4叉最小堆性质：父节点 <= 所有子节点
     * @return true 如果堆性质成立，false 否则
     */
    private function verifyMinHeapProperty():Boolean {
        var heapArray:Array = heap["heap"];
        var heapSize:Number = heap["heapSize"];

        for (var i:Number = 0; i < heapSize; i++) {
            var parentValue:Number = heapArray[i];

            // 4叉堆：子节点索引是 4*i+1, 4*i+2, 4*i+3, 4*i+4
            for (var c:Number = 1; c <= 4; c++) {
                var childIndex:Number = 4 * i + c;
                if (childIndex < heapSize) {
                    var childValue:Number = heapArray[childIndex];
                    if (parentValue > childValue) {
                        trace("  [DEBUG] Min-heap property violated: parent[" + i + "]=" + parentValue +
                              " > child[" + childIndex + "]=" + childValue);
                        return false;
                    }
                }
            }
        }
        return true;
    }
}
