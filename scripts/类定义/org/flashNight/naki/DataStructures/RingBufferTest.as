/**
 * RingBuffer 测试类（扩展版）
 *
 * 说明：
 * 1. 本测试类涵盖了 org.flashNight.naki.DataStructures.RingBuffer 类所有 public 方法的单元测试。
 * 2. 包含对构造函数、push、pushMany、get（含负索引及边界判断）、pop、peek、clear、reset、
 *    replaceSingle、toArray、toReversedArray、forEach、toString、head、tail、isEmpty、isFull、contains、resize 等方法的测试。
 * 3. 内置性能评测模块使用 getTimer() 评测常用操作的迭代性能。
 * 4. 请将本文件与 RingBuffer 类文件放在相同目录下进行测试。
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
        testReset();
        testReplaceSingle();
        testToReversedArray();
        testHeadTail();
        testIsEmptyAndIsFull();
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
        rb = new org.flashNight.naki.DataStructures.RingBuffer(1);
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
     * 测试 get 方法边界情况及覆盖（溢出）情况
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
     * 测试 reset 方法，使用新数据重置 RingBuffer 状态
     */
    private static function testReset():Void {
        trace(">> testReset");
        var rb:org.flashNight.naki.DataStructures.RingBuffer = new org.flashNight.naki.DataStructures.RingBuffer(5);
        rb.push(10);
        rb.push(20);
        rb.push(30);
        // 使用新数据重置，数组长度小于 capacity
        rb.reset([100, 200]);
        assert(rb.size == 2, "reset 后 size 应为 2");
        assert(rb.get(0) == 100, "reset 后 get(0) 应为 100");
        assert(rb.get(1) == 200, "reset 后 get(1) 应为 200");
        
        // 使用新数据数组长度大于 capacity 时，应只保留最新 capacity 个数据
        rb.reset([1, 2, 3, 4, 5, 6, 7]);
        assert(rb.size == 5, "reset 大数组后 size 应为 5 (capacity 5)");
        // 此时应保留最新 5 个数据，即 [3,4,5,6,7]
        assert(rb.get(0) == 3, "reset 大数组后 get(0) 应为 3");
        assert(rb.get(4) == 7, "reset 大数组后 get(4) 应为 7");
    }

    /**
     * 测试 replaceSingle 方法，用单一数据替换所有内容
     */
    private static function testReplaceSingle():Void {
        trace(">> testReplaceSingle");
        var rb:org.flashNight.naki.DataStructures.RingBuffer = new org.flashNight.naki.DataStructures.RingBuffer(4);
        rb.push("a");
        rb.push("b");
        rb.push("c");
        rb.replaceSingle("single");
        assert(rb.size == 1, "replaceSingle 后 size 应为 1");
        assert(rb.get(0) == "single", "replaceSingle 后 get(0) 应为 'single'");
        assert(rb.head == "single", "replaceSingle 后 head 应为 'single'");
        assert(rb.tail == "single", "replaceSingle 后 tail 应为 'single'");
    }

    /**
     * 测试 toReversedArray 方法，验证逆序输出是否正确
     */
    private static function testToReversedArray():Void {
        trace(">> testToReversedArray");
        var rb:org.flashNight.naki.DataStructures.RingBuffer = new org.flashNight.naki.DataStructures.RingBuffer(5);
        rb.push(1);
        rb.push(2);
        rb.push(3);
        var arr:Array = rb.toArray();
        var rev:Array = rb.toReversedArray();
        // 验证逆序数组第一个元素应为原数组的最后一个元素
        assert(rev[0] == arr[arr.length - 1], "toReversedArray 第一个元素应为 toArray 最后一个");
        // 验证逆序数组最后一个元素应为原数组的第一个元素
        assert(rev[rev.length - 1] == arr[0], "toReversedArray 最后一个元素应为 toArray 第一个");
        
        // 测试空队列情况
        rb.clear();
        arr = rb.toReversedArray();
        assert(arr.length == 0, "空队列 toReversedArray 应返回空数组");
    }

    /**
     * 测试 head 与 tail 属性，验证队列首尾数据是否正确
     */
    private static function testHeadTail():Void {
        trace(">> testHeadTail");
        var rb:org.flashNight.naki.DataStructures.RingBuffer = new org.flashNight.naki.DataStructures.RingBuffer(3);
        rb.push("first");
        rb.push("second");
        rb.push("third");
        assert(rb.head == "first", "head 属性应返回队列首元素 'first'");
        assert(rb.tail == "third", "tail 属性应返回队列尾元素 'third'");
        
        // 覆盖测试：继续 push 元素使得最旧数据被覆盖
        rb.push("fourth"); // 此时队列变为 ["second", "third", "fourth"]
        assert(rb.head == "second", "覆盖后 head 应返回 'second'");
        assert(rb.tail == "fourth", "覆盖后 tail 应返回 'fourth'");
        
        // 空队列测试
        rb.clear();
        assert(rb.head == undefined, "空队列 head 应返回 undefined");
        assert(rb.tail == undefined, "空队列 tail 应返回 undefined");
    }

    /**
     * 测试 isEmpty 与 isFull 方法，判断队列是否为空或已满
     */
    private static function testIsEmptyAndIsFull():Void {
        trace(">> testIsEmptyAndIsFull");
        var rb:org.flashNight.naki.DataStructures.RingBuffer = new org.flashNight.naki.DataStructures.RingBuffer(3);
        // 新建队列应为空
        assert(rb.isEmpty() == true, "新建的队列 isEmpty 应返回 true");
        assert(rb.isFull() == false, "新建的队列 isFull 应返回 false");
        rb.push("A");
        assert(rb.isEmpty() == false, "非空队列 isEmpty 应返回 false");
        assert(rb.isFull() == false, "未满队列 isFull 应返回 false");
        rb.push("B");
        rb.push("C");
        assert(rb.isFull() == true, "满队列 isFull 应返回 true");
        // 弹出所有元素后队列为空
        rb.pop();
        rb.pop();
        rb.pop();
        assert(rb.isEmpty() == true, "弹出所有元素后 isEmpty 应返回 true");
        assert(rb.isFull() == false, "空队列 isFull 应返回 false");
    }

    /**
     * 测试 toArray 与 forEach 方法，确保两者输出一致
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
        // 测试 toString 输出是否包含必要信息
        var str:String = rb.toString();
        assert(str.indexOf("capacity=3") != -1, "toString() 应包含 capacity 信息");
        assert(str.indexOf("size=3") != -1, "toString() 应包含 size 信息");
        assert(str.indexOf("[alpha,beta,gamma]") != -1, "toString() 应包含数据 [alpha,beta,gamma]");
        // contains 方法测试
        assert(rb.contains("beta") == true, "contains('beta') 应为 true");
        assert(rb.contains("delta") == false, "contains('delta') 应为 false");
        // 空队列 contains 测试
        rb.clear();
        assert(rb.contains("alpha") == false, "空队列 contains 应为 false");
    }

    /**
     * 性能评测模块，使用 getTimer() 对常用方法性能进行测试
     */
    private static function performanceTest():Void {
        trace(">> performanceTest");
        var iterations:Number = 100000;
        var rb:org.flashNight.naki.DataStructures.RingBuffer = new org.flashNight.naki.DataStructures.RingBuffer(1000);

        // push 性能测试
        var startTime:Number = getTimer();
        for (var i:Number = 0; i < iterations; i++) {
            rb.push(i);
        }
        var pushDuration:Number = getTimer() - startTime;
        trace("push " + iterations + " 次耗时: " + pushDuration + "ms");

        // pushMany 性能测试
        startTime = getTimer();
        var manyItems:Array = [];
        for (i = 0; i < iterations; i++) {
            manyItems.push(i);
        }
        rb.pushMany(manyItems);
        var pushManyDuration:Number = getTimer() - startTime;
        trace("pushMany " + iterations + " 次耗时: " + pushManyDuration + "ms");

        // get 性能测试
        startTime = getTimer();
        for (i = 0; i < iterations; i++) {
            rb.get(Math.floor(Math.random() * rb.size));
        }
        var getDuration:Number = getTimer() - startTime;
        trace("随机 get " + iterations + " 次耗时: " + getDuration + "ms");

        // pop 性能测试
        startTime = getTimer();
        for (i = 0; i < iterations; i++) {
            rb.pop();
        }
        var popDuration:Number = getTimer() - startTime;
        trace("pop " + iterations + " 次耗时: " + popDuration + "ms");

        // resize 性能测试
        startTime = getTimer();
        for (i = 0; i < 100; i++) {
            rb.resize(1000 + i);
        }
        var resizeDuration:Number = getTimer() - startTime;
        trace("resize 100 次耗时: " + resizeDuration + "ms");

        // 输出性能评测结论（可根据实际需求调整阈值）
        var acceptableThreshold:Number = 100;
        assert(pushDuration < acceptableThreshold, "push 操作性能符合要求");
        assert(getDuration < acceptableThreshold, "随机 get 操作性能符合要求");
    }
}
