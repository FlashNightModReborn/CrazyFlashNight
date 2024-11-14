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
     * Executes all performance tests, utilizing the external taskMap for efficiency.
     */
    public function runPerformanceTests():Void {
        trace("=== Running Performance Tests ===");
        testInsertPerformance();
        testFindPerformance();
        testPeekMinPerformance();
        testRemovePerformance();
        testReschedulePerformance();
        testTickPerformance();
        trace("=== Performance Tests Completed ===\n");
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
     * Measures the time taken to insert a large number of tasks using the addTimerByID method.
     */
    private function testInsertPerformance():Void {
        resetHeap();
        var startTime:Number = getTimer();
        for (var i:Number = 0; i < 10000; i++) {
            var taskID:String = "task" + i;
            // Directly add the timer and obtain the node without needing a separate lookup
            var node:TaskIDNode = heap.addTimerByID(taskID, Math.floor(Math.random() * 1000));
            taskMap[taskID] = node; // Store the created node in taskMap for direct access
        }
        var endTime:Number = getTimer();
        trace("Insert Performance: " + (endTime - startTime) + " ms for 10,000 inserts using addTimerByID");
    }


    /**
     * @method testFindPerformance
     * Measures the time taken to find a large number of tasks by their taskID using the external taskMap.
     */
    private function testFindPerformance():Void {
        resetHeap();
        // Insert 10,000 tasks
        for (var i:Number = 0; i < 10000; i++) {
            var taskID:String = "task" + i;
            heap.insert(taskID, Math.floor(Math.random() * 1000));
            taskMap[taskID] = heap.findNodeById(taskID); // Store in taskMap
        }

        var startTime:Number = getTimer();
        for (var j:Number = 0; j < 10000; j++) {
            var currentTaskID:String = "task" + j;
            var node:TaskIDNode = taskMap[currentTaskID]; // Direct access using taskMap
            // Optionally, perform some operation with node
        }
        var endTime:Number = getTimer();
        trace("Find Performance: " + (endTime - startTime) + " ms for 10,000 finds using taskMap");
    }

    /**
     * @method testPeekMinPerformance
     * Measures the time taken to repeatedly peek at the minimum frame.
     */
    private function testPeekMinPerformance():Void {
        resetHeap();
        // Insert a few tasks
        heap.insert("task1", 5);
        taskMap["task1"] = heap.findNodeById("task1"); // Store in taskMap
        heap.insert("task2", 3);
        taskMap["task2"] = heap.findNodeById("task2"); // Store in taskMap
        heap.insert("task3", 10);
        taskMap["task3"] = heap.findNodeById("task3"); // Store in taskMap

        var startTime:Number = getTimer();
        for (var i:Number = 0; i < 10000; i++) {
            heap.peekMin();
        }
        var endTime:Number = getTimer();
        trace("PeekMin Performance: " + (endTime - startTime) + " ms for 10,000 peek operations");
    }

    /**
     * @method testRemovePerformance
     * Measures the time taken to remove a large number of tasks using the external taskMap.
     */
    private function testRemovePerformance():Void {
        resetHeap();
        // Insert 5,000 tasks
        for (var i:Number = 0; i < 5000; i++) {
            var taskID:String = "task" + i;
            heap.insert(taskID, Math.floor(Math.random() * 1000));
            taskMap[taskID] = heap.findNodeById(taskID); // Store in taskMap
        }

        var startTime:Number = getTimer();
        for (var j:Number = 0; j < 5000; j++) {
            var currentTaskID:String = "task" + j;
            var node:TaskIDNode = taskMap[currentTaskID];
            if (node != null) {
                heap.removeDirectly(node); // Direct removal using node reference
                delete taskMap[currentTaskID]; // Remove from taskMap
            }
        }
        var endTime:Number = getTimer();
        trace("Remove Performance: " + (endTime - startTime) + " ms for 5,000 removals using taskMap");
    }

    /**
     * @method testReschedulePerformance
     * Measures the time taken to reschedule a large number of tasks using the external taskMap.
     */
    private function testReschedulePerformance():Void {
        resetHeap();
        // Insert 5,000 tasks
        for (var i:Number = 0; i < 5000; i++) {
            var taskID:String = "task" + i;
            heap.insert(taskID, Math.floor(Math.random() * 1000));
            taskMap[taskID] = heap.findNodeById(taskID); // Store in taskMap
        }

        var startTime:Number = getTimer();
        for (var j:Number = 0; j < 5000; j++) {
            var currentTaskID:String = "task" + j;
            var node:TaskIDNode = taskMap[currentTaskID];
            if (node != null) {
                heap.rescheduleTimerByNode(node, Math.floor(Math.random() * 1000)); // Direct reschedule using node reference
            }
        }
        var endTime:Number = getTimer();
        trace("Reschedule Performance: " + (endTime - startTime) + " ms for 5,000 reschedules using taskMap");
    }

    /**
     * @method testTickPerformance
     * Measures the time taken to process a large number of frame ticks.
     */
    private function testTickPerformance():Void {
        resetHeap();
        // Insert 10,000 tasks with varying delays
        for (var i:Number = 0; i < 10000; i++) {
            var taskID:String = "task" + i;
            heap.insert(taskID, Math.floor(Math.random() * 1000));
            taskMap[taskID] = heap.findNodeById(taskID); // Store in taskMap
        }

        var startTime:Number = getTimer();
        while (heap.peekMin() != null) {
            heap.tick();
        }
        var endTime:Number = getTimer();
        trace("Tick Performance: " + (endTime - startTime) + " ms to process 10,000 ticks");
    }
}
