import org.flashNight.naki.DataStructures.TaskMinHeap;
import org.flashNight.naki.DataStructures.HeapNode;

class org.flashNight.naki.DataStructures.TaskMinHeapTest {
    private var heap:TaskMinHeap;

    public function TaskMinHeapTest() {
        // 初始化时不创建堆实例，测试方法中进行初始化
    }

    // 断言辅助函数
    private function assert(condition:Boolean, message:String):Void {
        if (condition) {
            trace("PASS: " + message);
        } else {
            trace("FAIL: " + message);
        }
    }

    // 重置堆实例，确保每个测试的独立性
    private function resetHeap():Void {
        this.heap = new TaskMinHeap();
    }

    // 功能测试入口
    public function runFunctionTests():Void {
        trace("=== Running Functional Tests ===");
        testInsert();
        testFind();
        testPeekMin();
        testRemove();
        testUpdate();
        testExtractMin();
        testEdgeCases();
        trace("=== Functional Tests Completed ===\n");
    }

    // 性能测试入口
    public function runPerformanceTests():Void {
        trace("=== Running Performance Tests ===");
        testInsertPerformance();
        testFindPerformance();
        testPeekMinPerformance();
        testRemovePerformance();
        testUpdatePerformance();
        testExtractMinPerformance();
        trace("=== Performance Tests Completed ===\n");
    }

    // 测试插入操作
    private function testInsert():Void {
        resetHeap();
        heap.insert("task1", 10);
        heap.insert("task2", 5);
        heap.insert("task3", 20);
        var minTask:HeapNode = heap.peekMin();
        assert(minTask.priority == 5 && minTask.taskID == "task2", "Insert operations maintain correct min heap");
    }

    // 测试查找操作
    private function testFind():Void {
        resetHeap();
        heap.insert("task1", 10);
        heap.insert("task2", 5);
        var task:HeapNode = heap.find("task2");
        assert(task != null && task.taskID == "task2" && task.priority == 5, "Find operation correctly locates existing task");
        
        var nonExistentTask:HeapNode = heap.find("taskX");
        assert(nonExistentTask == null, "Find operation correctly returns null for non-existent task");
    }

    // 测试查看堆顶任务
    private function testPeekMin():Void {
        resetHeap();
        heap.insert("task1", 10);
        heap.insert("task2", 5);
        var minTask:HeapNode = heap.peekMin();
        assert(minTask.taskID == "task2" && minTask.priority == 5, "PeekMin correctly identifies the minimum priority task");
        
        heap = new TaskMinHeap(); // 重置为空堆
        var emptyPeek:HeapNode = heap.peekMin();
        assert(emptyPeek == null, "PeekMin returns null for empty heap");
    }

    // 测试删除操作
    private function testRemove():Void {
        resetHeap();
        heap.insert("task1", 10);
        heap.insert("task2", 5);
        heap.insert("task3", 20);
        heap.remove("task2");
        var task:HeapNode = heap.find("task2");
        var newMin:HeapNode = heap.peekMin();
        assert(task == null && newMin.taskID == "task1" && newMin.priority == 10, "Remove operation correctly deletes the specified task and updates the min heap");
    }

    // 测试更新优先级
    private function testUpdate():Void {
        resetHeap();
        heap.insert("task1", 10);
        heap.insert("task2", 5);
        heap.update("task1", 3);
        var minTask:HeapNode = heap.peekMin();
        assert(minTask.taskID == "task1" && minTask.priority == 3, "Update operation correctly updates the task priority and rebalances the heap");
    }

    // 测试提取堆顶任务
    private function testExtractMin():Void {
        resetHeap();
        heap.insert("task1", 10);
        heap.insert("task2", 5);
        heap.insert("task3", 20);
        var minTask:HeapNode = heap.extractMin();
        assert(minTask.taskID == "task2" && heap.peekMin().taskID == "task1", "ExtractMin correctly removes and returns the minimum priority task");
        
        // 提取剩余任务
        var secondMin:HeapNode = heap.extractMin();
        var lastTask:HeapNode = heap.peekMin();
        assert(secondMin.taskID == "task1" && lastTask.taskID == "task3", "ExtractMin correctly updates the heap after multiple extractions");
    }

    // 测试边界情况
    private function testEdgeCases():Void {
        resetHeap();
        
        // 尝试删除不存在的任务
        heap.insert("task1", 10);
        heap.remove("taskX");
        assert(heap.peekMin().taskID == "task1", "Remove operation handles non-existent task IDs gracefully");
        
        // 尝试更新不存在的任务
        heap.update("taskY", 15);
        assert(heap.peekMin().taskID == "task1" && heap.peekMin().priority == 10, "Update operation handles non-existent task IDs gracefully");
        
        // 尝试插入重复的任务 ID
        heap.insert("task1", 5); // 假设允许重复插入
        var task:HeapNode = heap.find("task1");
        assert(task.priority == 5, "Insert operation updates the priority for duplicate task IDs if allowed");
    }

    // 插入性能测试
    private function testInsertPerformance():Void {
        resetHeap();
        var startTime:Number = getTimer();
        for (var i:Number = 0; i < 10000; i++) {
            heap.insert("task" + i, Math.random() * 10000);
        }
        var endTime:Number = getTimer();
        trace("Insert Performance: " + (endTime - startTime) + " ms for 10,000 inserts");
    }

    // 查找性能测试
    private function testFindPerformance():Void {
        resetHeap();
        // 先插入10000个任务
        for (var i:Number = 0; i < 10000; i++) {
            heap.insert("task" + i, i);
        }
        var startTime:Number = getTimer();
        for (var j:Number = 0; j < 10000; j++) {
            heap.find("task" + j);
        }
        var endTime:Number = getTimer();
        trace("Find Performance: " + (endTime - startTime) + " ms for 10,000 finds");
    }

    // 查看堆顶性能测试
    private function testPeekMinPerformance():Void {
        resetHeap();
        heap.insert("task1", 10);
        heap.insert("task2", 5);
        heap.insert("task3", 20);

        var startTime:Number = getTimer();
        for (var i:Number = 0; i < 10000; i++) {
            heap.peekMin();
        }
        var endTime:Number = getTimer();
        trace("PeekMin Performance: " + (endTime - startTime) + " ms for 10,000 peek operations");
    }

    // 删除和更新性能测试
    private function testRemovePerformance():Void {
        resetHeap();
        // 先插入5000个任务
        for (var i:Number = 0; i < 5000; i++) {
            heap.insert("task" + i, Math.random() * 10000);
        }
        var startTime:Number = getTimer();
        for (var j:Number = 0; j < 5000; j++) {
            heap.update("task" + j, Math.random() * 10000);
            heap.remove("task" + j);
        }
        var endTime:Number = getTimer();
        trace("Remove and Update Performance: " + (endTime - startTime) + " ms for 5,000 removals and updates");
    }

    // 更新优先级性能测试
    private function testUpdatePerformance():Void {
        resetHeap();
        // 先插入5000个任务
        for (var i:Number = 0; i < 5000; i++) {
            heap.insert("task" + i, Math.random() * 10000);
        }
        
        var startTime:Number = getTimer();
        for (var j:Number = 0; j < 5000; j++) {
            heap.update("task" + j, Math.random() * 10000);
        }
        var endTime:Number = getTimer();
        trace("Update Performance: " + (endTime - startTime) + " ms for 5,000 updates");
    }


    // 批量提取性能测试
    private function testExtractMinPerformance():Void {
        resetHeap();
        // 先插入10000个任务
        for (var i:Number = 0; i < 10000; i++) {
            heap.insert("task" + i, Math.random() * 10000);
        }
        var startTime:Number = getTimer();
        while (heap.peekMin() != null) {
            heap.extractMin();
        }
        var endTime:Number = getTimer();
        trace("Extract Performance: " + (endTime - startTime) + " ms to empty the heap");
    }
}
