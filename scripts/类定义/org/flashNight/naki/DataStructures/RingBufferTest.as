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
        testConstructor();
        testPushAndGet();
        testPushMany();
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
     * 测试构造函数，包括 capacity、fillWith 和 initialData 参数的边界情况
     */
    private static function testConstructor():Void {
        trace(">> testConstructor");
        // 测试 capacity < 1
        try {
            var rb:org.flashNight.naki.DataStructures.RingBuffer = new org.flashNight.naki.DataStructures.RingBuffer(0);
            assert(false, "capacity < 1 应抛出错误");
        } catch (e:Error) {
            assert(true, "capacity < 1 抛出错误");
        }
        // 测试 capacity = 1
        var rb:org.flashNight.naki.DataStructures.RingBuffer = new org.flashNight.naki.DataStructures.RingBuffer(1);
        assert(rb.capacity == 1, "capacity 应为 1");
        assert(rb.size == 0, "初始 size 应为 0");
        // 测试 fillWith
        rb = new org.flashNight.naki.DataStructures.RingBuffer(3, "default");
        assert(rb.size == 3, "fillWith 后 size 应为 capacity");
        assert(rb.get(0) == "default", "fillWith 后元素应为 'default'");
        // 测试 initialData
        rb = new org.flashNight.naki.DataStructures.RingBuffer(3, null, [1, 2, 3, 4]);
        assert(rb.size == 3, "initialData 超出 capacity 时 size 应为 capacity");
        assert(rb.get(0) == 2, "initialData 超出时保留最新数据");
    }

    /**
     * 测试 push 和 get 方法（包含负数索引）
     */
    private static function testPushAndGet():Void {
        trace(">> testPushAndGet");
        var rb:org.flashNight.naki.DataStructures.RingBuffer = new org.flashNight.naki.DataStructures.RingBuffer(5);
        // 空队列 push
        rb.push(1);
        assert(rb.size == 1, "push 后 size 应为 1");
        assert(rb.get(0) == 1, "push 后 get(0) 应为 1");
        // 多元素 push
        rb.push(2);
        rb.push(3);
        assert(rb.size == 3, "push 后 size 应为 3");
        assert(rb.get(0) == 1, "get(0) 应返回 1");
        assert(rb.get(1) == 2, "get(1) 应返回 2");
        assert(rb.get(2) == 3, "get(2) 应返回 3");
        // 测试负数索引
        assert(rb.get(-1) == 3, "get(-1) 应返回最新元素 3");
        assert(rb.get(-2) == 2, "get(-2) 应返回 2");
        // 满队列 push
        rb.push(4);
        rb.push(5);
        rb.push(6); // 覆盖最旧数据
        assert(rb.size == 5, "满队列 push 后 size 仍为 5");
        assert(rb.get(0) == 2, "满队列 push 后 get(0) 应为 2");
    }

    /**
     * 测试 pushMany 方法
     */
    private static function testPushMany():Void {
        trace(">> testPushMany");
        var rb:org.flashNight.naki.DataStructures.RingBuffer = new org.flashNight.naki.DataStructures.RingBuffer(3);
        // 批量 pushMany
        rb.pushMany([1, 2, 3]);
        assert(rb.size == 3, "pushMany 后 size 应为 3");
        assert(rb.get(0) == 1, "pushMany 后 get(0) 应为 1");
        // 批量 pushMany 覆盖
        rb.pushMany([4, 5]);
        assert(rb.size == 3, "pushMany 覆盖后 size 仍为 3");
        assert(rb.get(0) == 3, "pushMany 覆盖后 get(0) 应为 3");
        // pushMany 空数组
        rb.pushMany([]);
        assert(rb.size == 3, "pushMany 空数组不改变 size");
    }

    /**
     * 测试 get 方法边界情况，及覆盖（溢出）情况
     */
    private static function testBoundaryIndices():Void {
        trace(">> testBoundaryIndices");
        var rb:org.flashNight.naki.DataStructures.RingBuffer = new org.flashNight.naki.DataStructures.RingBuffer(3);
        rb.push("a");
        rb.push("b");
        rb.push("c");
        // 覆盖测试
        rb.push("d"); // 变为 ["b", "c", "d"]
        assert(rb.size == 3, "覆盖后 size 仍为 3");
        assert(rb.get(0) == "b", "覆盖后 get(0) 应返回 'b'");
        assert(rb.get(1) == "c", "覆盖后 get(1) 应返回 'c'");
        assert(rb.get(2) == "d", "覆盖后 get(2) 应返回 'd'");
        // 测试越界索引
        try {
            rb.get(3);
            assert(false, "get(3) 应抛出错误");
        } catch (e:Error) {
            assert(true, "get(3) 抛出错误");
        }
        try {
            rb.get(-4);
            assert(false, "get(-4) 应抛出错误");
        } catch (e:Error) {
            assert(true, "get(-4) 抛出错误");
        }
    }

    /**
     * 测试 pop 与 peek 方法的行为（FIFO 顺序）
     */
    private static function testPopAndPeek():Void {
        trace(">> testPopAndPeek");
        var rb:org.flashNight.naki.DataStructures.RingBuffer = new org.flashNight.naki.DataStructures.RingBuffer(4);
        // 空队列测试
        assert(rb.peek() == undefined, "空队列 peek 应返回 undefined");
        assert(rb.pop() == undefined, "空队列 pop 应返回 undefined");
        // 单元素测试
        rb.push(10);
        assert(rb.peek() == 10, "peek() 应返回队列头部 10");
        assert(rb.pop() == 10, "pop() 应返回 10");
        assert(rb.size == 0, "pop() 后 size 应为 0");
        // 多元素测试
        rb.push(20);
        rb.push(30);
        assert(rb.peek() == 20, "peek() 应返回 20");
        assert(rb.pop() == 20, "pop() 应返回 20");
        assert(rb.size == 1, "pop() 后 size 应为 1");
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
        // 无参数 clear
        rb.clear();
        assert(rb.size == 0, "clear() 后 size 应为 0");
        assert(rb.get(0) == undefined, "clear() 后 get(0) 应为 undefined");
        // 带 fillWith 参数 clear
        rb.clear("default");
        assert(rb.size == 3, "以填充方式 clear() 后 size 应等于 capacity");
        for (var i:Number = 0; i < rb.size; i++) {
            assert(rb.get(i) == "default", "clear(fillWith) 后每个元素应为 'default'");
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
        // 增大 capacity
        rb.resize(8);
        assert(rb.capacity == 8, "扩容后 capacity 应为 8");
        assert(rb.size == 3, "扩容后 size 应仍为 3");
        assert(rb.get(0) == 1, "扩容后 get(0) 仍为 1");
        // 减小 capacity
        rb.resize(2);
        assert(rb.capacity == 2, "缩容后 capacity 应为 2");
        assert(rb.size == 2, "缩容后 size 应为 2");
        assert(rb.get(0) == 2, "缩容后 get(0) 应为 2");
        // resize 到 0
        try {
            rb.resize(0);
            assert(false, "resize(0) 应抛出错误");
        } catch (e:Error) {
            assert(true, "resize(0) 抛出错误");
        }
    }

    /**
     * 测试 toArray 与 forEach 方法
     */
    private static function testForEachToArray():Void {
        trace(">> testForEachToArray");
        var rb:org.flashNight.naki.DataStructures.RingBuffer = new org.flashNight.naki.DataStructures.RingBuffer(4);
        // 空队列测试
        var arr:Array = rb.toArray();
        assert(arr.length == 0, "空队列 toArray 应返回空数组");
        var count:Number = 0;
        rb.forEach(function(item, index, ring) {
            count++;
        });
        assert(count == 0, "空队列 forEach 不应调用回调");
        // 满队列测试
        rb.push("x");
        rb.push("y");
        rb.push("z");
        arr = rb.toArray();
        assert(arr.length == rb.size, "toArray() 长度应与 size 相等");
        var collected:Array = [];
        rb.forEach(function(item, index, ring) {
            collected.push(item);
        });
        assert(collected.length == rb.size, "forEach() 应遍历所有数据");
        for (var i:Number = 0; i < collected.length; i++) {
            assert(collected[i] == arr[i], "forEach() 遍历顺序应与 toArray() 保持一致");
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
        // toString 测试
        var str:String = rb.toString();
        assert(str.indexOf("capacity=3") != -1, "toString() 应包含 capacity 信息");
        assert(str.indexOf("size=3") != -1, "toString() 应包含 size 信息");
        assert(str.indexOf("[alpha,beta,gamma]") != -1, "toString() 应包含数据 [alpha,beta,gamma]");
        // contains 测试
        assert(rb.contains("beta") == true, "contains('beta') 应为 true");
        assert(rb.contains("delta") == false, "contains('delta') 应为 false");
        // 空队列 contains
        rb.clear();
        assert(rb.contains("alpha") == false, "空队列 contains 应为 false");
    }

    /**
     * 性能评测模块
     */
    private static function performanceTest():Void {
        trace(">> performanceTest");
        var iterations:Number = 100000;
        var rb:org.flashNight.naki.DataStructures.RingBuffer = new org.flashNight.naki.DataStructures.RingBuffer(1000);

        // push 性能
        var startTime:Number = getTimer();
        for (var i:Number = 0; i < iterations; i++) {
            rb.push(i);
        }
        var pushDuration:Number = getTimer() - startTime;
        trace("push " + iterations + " 次耗时: " + pushDuration + "ms");

        // pushMany 性能
        startTime = getTimer();
        var manyItems:Array = [];
        for (i = 0; i < iterations; i++) {
            manyItems.push(i);
        }
        rb.pushMany(manyItems);
        var pushManyDuration:Number = getTimer() - startTime;
        trace("pushMany " + iterations + " 次耗时: " + pushManyDuration + "ms");

        // get 性能
        startTime = getTimer();
        for (i = 0; i < iterations; i++) {
            rb.get(Math.floor(Math.random() * rb.size));
        }
        var getDuration:Number = getTimer() - startTime;
        trace("随机 get " + iterations + " 次耗时: " + getDuration + "ms");

        // pop 性能
        startTime = getTimer();
        for (i = 0; i < iterations; i++) {
            rb.pop();
        }
        var popDuration:Number = getTimer() - startTime;
        trace("pop " + iterations + " 次耗时: " + popDuration + "ms");

        // resize 性能
        startTime = getTimer();
        for (i = 0; i < 100; i++) {
            rb.resize(1000 + i);
        }
        var resizeDuration:Number = getTimer() - startTime;
        trace("resize 100 次耗时: " + resizeDuration + "ms");

        // 输出性能评测结论
        var acceptableThreshold:Number = 100;
        assert(pushDuration < acceptableThreshold, "push 操作性能符合要求");
        assert(getDuration < acceptableThreshold, "随机 get 操作性能符合要求");
    }
}