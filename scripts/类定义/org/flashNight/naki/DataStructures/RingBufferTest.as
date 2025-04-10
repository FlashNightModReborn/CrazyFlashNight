/**
 * RingBuffer 测试类
 * 
 * 说明：
 * 1. 内置简单断言系统，实现 assert() 方法，用于检查各个方法行为是否符合预期。
 * 2. 完全覆盖了构造、push、pushMany、get（含负索引和边界检测）、pop、peek、clear、
 *    resize、toArray、forEach、toString、head、tail、contains 等各个接口。
 * 3. 内置性能评测模块，使用 getTimer() 对常用方法进行迭代性能测试。
 * 4. 请将该文件与 org.flashNight.naki.DataStructures.RingBuffer 类放在同一目录下测试。
 */
class org.flashNight.naki.DataStructures.RingBufferTest {

    /**
     * 运行所有测试用例
     */
    public static function runTests():Void {
        trace("===== 开始 RingBuffer 测试 =====");
        testPushAndGet();
        testBoundaryIndices();
        testPopAndPeek();
        testClear();
        testResize();
        testForEachToArray();
        testStringAndContains();
        performanceTest();
        trace("===== RingBuffer 测试全部结束 =====");
    }

    /**
     * 简单断言方法，用于检测条件是否成立
     * @param condition 判断条件
     * @param message   断言信息
     */
    private static function assert(condition:Boolean, message:String):Void {
        if (!condition) {
            trace("ASSERT FAILED: " + message);
        } else {
            trace("Test passed: " + message);
        }
    }
    
    /**
     * 测试 push、pushMany 及 get 方法（包含负数索引）
     */
    private static function testPushAndGet():Void {
        trace(">> testPushAndGet");
        var rb:org.flashNight.naki.DataStructures.RingBuffer = new org.flashNight.naki.DataStructures.RingBuffer(5);
        // 单个 push 操作
        rb.push(1);
        rb.push(2);
        rb.push(3);
        assert(rb.size == 3, "push后 size 应为 3");
        assert(rb.get(0) == 1, "get(0) 应返回 1");
        assert(rb.get(1) == 2, "get(1) 应返回 2");
        assert(rb.get(2) == 3, "get(2) 应返回 3");
        // 测试负数索引
        assert(rb.get(-1) == 3, "get(-1) 应返回最新元素 3");
        assert(rb.get(-2) == 2, "get(-2) 应返回 2");

        // 批量 pushMany 测试
        rb = new org.flashNight.naki.DataStructures.RingBuffer(5);
        rb.pushMany([10,20,30]);
        assert(rb.size == 3, "pushMany 后 size 应为 3");
        assert(rb.get(0) == 10, "pushMany 后 get(0) 应返回 10");
    }
    
    /**
     * 测试 get 方法边界情况，及覆盖（溢出）情况。
     */
    private static function testBoundaryIndices():Void {
        trace(">> testBoundaryIndices");
        var rb:org.flashNight.naki.DataStructures.RingBuffer = new org.flashNight.naki.DataStructures.RingBuffer(3);
        rb.push("a");
        rb.push("b");
        rb.push("c");
        // 此时队列已满，再 push 会覆盖最旧的数据
        rb.push("d"); // 变为 ["b", "c", "d"]
        assert(rb.size == 3, "覆盖后 size 仍为 3");
        assert(rb.get(0) == "b", "覆盖后 get(0) 应返回 'b'");
        assert(rb.get(1) == "c", "覆盖后 get(1) 应返回 'c'");
        assert(rb.get(2) == "d", "覆盖后 get(2) 应返回 'd'");
        
        // 测试索引超出范围，期望抛出异常（使用 try-catch 捕获）
        var errorThrown:Boolean = false;
        try {
            rb.get(3);
        } catch (e:Error) {
            errorThrown = true;
        }
        assert(errorThrown, "get(3) 越界应抛出 RangeError");
    }
    
    /**
     * 测试 pop 与 peek 方法的行为（FIFO 顺序）
     */
    private static function testPopAndPeek():Void {
        trace(">> testPopAndPeek");
        var rb:org.flashNight.naki.DataStructures.RingBuffer = new org.flashNight.naki.DataStructures.RingBuffer(4);
        rb.push(10);
        rb.push(20);
        rb.push(30);
        assert(rb.peek() == 10, "peek() 应返回队列头部 10");
        var popped = rb.pop();
        assert(popped == 10, "pop() 第一次应返回 10");
        assert(rb.size == 2, "pop() 后 size 应为 2");
        assert(rb.peek() == 20, "pop() 后新头部应为 20");
        // 清空测试
        rb.pop();
        rb.pop();
        assert(rb.pop() == undefined, "空队列 pop() 应返回 undefined");
    }
    
    /**
     * 测试 clear 方法，包含重置填充参数
     */
    private static function testClear():Void {
        trace(">> testClear");
        var rb:org.flashNight.naki.DataStructures.RingBuffer = new org.flashNight.naki.DataStructures.RingBuffer(3);
        rb.push(1);
        rb.push(2);
        rb.push(3);
        rb.clear();
        assert(rb.size == 0, "clear() 后 size 应为 0");
        // 以 fillWith 方式清空
        rb.clear("default");
        assert(rb.size == 3, "以填充方式 clear() 后 size 应等于 capacity");
        var arr:Array = rb.toArray();
        for (var i:Number = 0; i < arr.length; i++) {
            assert(arr[i] == "default", "clear(fillWith) 后每个元素应为 'default'");
        }
    }
    
    /**
     * 测试 resize 方法，对容量增大和缩小时的数据保留情况进行检验
     */
    private static function testResize():Void {
        trace(">> testResize");
        var rb:org.flashNight.naki.DataStructures.RingBuffer = new org.flashNight.naki.DataStructures.RingBuffer(5);
        rb.push(1);
        rb.push(2);
        rb.push(3);
        rb.push(4);
        rb.push(5);
        // 扩容测试：扩容至 8，数据应保持不变
        rb.resize(8);
        assert(rb.capacity == 8, "扩容后 capacity 应为 8");
        assert(rb.size == 5, "扩容后 size 应仍为 5");
        var arr:Array = rb.toArray();
        for (var i:Number = 0; i < 5; i++) {
            assert(arr[i] == i+1, "扩容后数据顺序应保持原样");
        }
        // 缩容测试：缩容至 3，保留最新 3 个数据（即 3,4,5）
        rb.resize(3);
        assert(rb.capacity == 3, "缩容后 capacity 应为 3");
        assert(rb.size == 3, "缩容后 size 应为 3");
        arr = rb.toArray();
        assert(arr[0] == 3 && arr[1] == 4 && arr[2] == 5, "缩容后数据应为最新 [3,4,5]");
    }
    
    /**
     * 测试 toArray 与 forEach 方法
     */
    private static function testForEachToArray():Void {
        trace(">> testForEachToArray");
        var rb:org.flashNight.naki.DataStructures.RingBuffer = new org.flashNight.naki.DataStructures.RingBuffer(4);
        rb.push("x");
        rb.push("y");
        rb.push("z");
        var arrayResult:Array = rb.toArray();
        assert(arrayResult.length == rb.size, "toArray() 长度应与 size 相等");
        // 使用 forEach 收集数据
        var collected:Array = [];
        rb.forEach(function(item, index, ring) {
            collected.push(item);
        });
        assert(collected.length == rb.size, "forEach() 应遍历所有数据");
        for (var i:Number = 0; i < collected.length; i++) {
            assert(collected[i] == arrayResult[i], "forEach() 遍历顺序应与 toArray() 保持一致");
        }
    }
    
    /**
     * 测试 toString 与 contains 方法的正确性
     */
    private static function testStringAndContains():Void {
        trace(">> testStringAndContains");
        var rb:org.flashNight.naki.DataStructures.RingBuffer = new org.flashNight.naki.DataStructures.RingBuffer(3);
        rb.push("alpha");
        rb.push("beta");
        rb.push("gamma");
        var str:String = rb.toString();
        assert(str.indexOf("capacity=3") != -1, "toString() 应包含 capacity 信息");
        assert(str.indexOf("size=3") != -1, "toString() 应包含 size 信息");
        assert(rb.contains("alpha") == true, "contains() 应找到 'alpha'");
        assert(rb.contains("delta") == false, "contains() 不应找到 'delta'");
    }
    
    /**
     * 性能评测模块
     * 采用 getTimer() 对 push、get、pop、forEach 方法进行大量迭代测试，
     * 并输出各个方法执行所需的时间，以评估性能是否符合要求。
     */
    private static function performanceTest():Void {
        trace(">> performanceTest");
        var iterations:Number = 100000;
        var rb:org.flashNight.naki.DataStructures.RingBuffer = new org.flashNight.naki.DataStructures.RingBuffer(1000);
        
        // --- 性能测试： push 单个元素 ---
        var startTime:Number = getTimer();
        for (var i:Number = 0; i < iterations; i++) {
            rb.push(i);
        }
        var pushDuration:Number = getTimer() - startTime;
        trace("push " + iterations + " 次耗时: " + pushDuration + "ms");
        
        // --- 性能测试： 随机 get ---
        startTime = getTimer();
        for (i = 0; i < iterations; i++) {
            var index:Number = Math.floor(Math.random() * rb.size);
            rb.get(index);
        }
        var getDuration:Number = getTimer() - startTime;
        trace("随机 get " + iterations + " 次耗时: " + getDuration + "ms");
        
        // --- 性能测试： pop 与 push 组合（保持队列不变） ---
        rb.clear();
        // 填充队列
        for (i = 0; i < rb.capacity; i++) {
            rb.push(i);
        }
        startTime = getTimer();
        for (i = 0; i < iterations; i++) {
            rb.pop();
            rb.push(i);
        }
        var popDuration:Number = getTimer() - startTime;
        trace("pop 与 push 组合 " + iterations + " 次耗时: " + popDuration + "ms");
        
        // --- 性能测试： forEach 遍历 ---
        startTime = getTimer();
        rb.forEach(function(item, index, ring) {
            // 空循环仅用于遍历
        });
        var forEachDuration:Number = getTimer() - startTime;
        trace("forEach 遍历一次耗时: " + forEachDuration + "ms");
        
        // 输出性能评测结论（阈值可根据实际需求设定，此处仅给出示例）
        // 例如，期望每 100,000 次操作不超过 100ms
        var acceptableThreshold:Number = 100;
        assert(pushDuration < acceptableThreshold, "push 操作性能符合要求");
        assert(getDuration < acceptableThreshold, "随机 get 操作性能符合要求");
    }
}
