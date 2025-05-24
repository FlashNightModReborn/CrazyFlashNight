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
}
