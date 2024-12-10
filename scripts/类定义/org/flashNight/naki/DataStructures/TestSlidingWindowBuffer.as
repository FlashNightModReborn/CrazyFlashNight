import org.flashNight.naki.DataStructures.*;
class org.flashNight.naki.DataStructures.TestSlidingWindowBuffer {
    private var buffer:SlidingWindowBuffer; // 被测试的 SlidingWindowBuffer 实例
    private var assertCount:Number; // 成功断言计数
    private var errorCount:Number; // 失败断言计数

    /**
     * 构造函数
     */
    public function TestSlidingWindowBuffer() {
        this.assertCount = 0;
        this.errorCount = 0;
    }

    /**
     * 运行所有测试
     */
    public function runTests():Void {
        trace("Running tests for SlidingWindowBuffer...");

        this.testInitialization();
        this.testInsert();
        this.testCircularBehavior();
        this.testRecalculate();
        this.testForEach();
        this.testPerformance();

        trace("All tests completed.");
        trace("Assertions passed: " + this.assertCount);
        trace("Assertions failed: " + this.errorCount);
    }

    /**
     * 断言函数
     * @param condition 测试条件
     * @param message 测试消息
     */
    private function assert(condition:Boolean, message:String):Void {
        if (condition) {
            this.assertCount++;
        } else {
            this.errorCount++;
            trace("[Assertion Failed] " + message);
        }
    }

    /**
     * 测试初始化
     */
    private function testInitialization():Void {
        trace("Testing initialization...");

        this.buffer = new SlidingWindowBuffer(5);
        this.assert(this.buffer.max == 0, "Max should be initialized to 0");
        this.assert(this.buffer.min == 0, "Min should be initialized to 0");
        this.assert(this.buffer.average == 0, "Average should be initialized to 0");
        this.assert(this.buffer.data.length == 5, "Buffer should initialize with the correct size");
    }

    /**
     * 测试插入数据
     */
    private function testInsert():Void {
        trace("Testing insert method...");

        this.buffer = new SlidingWindowBuffer(3);

        this.buffer.insert(10);
        this.assert(this.buffer.max == 10, "Max should be updated after first insert");
        this.assert(this.buffer.min == 10, "Min should be updated after first insert");
        this.assert(this.buffer.average == 10, "Average should match first value");

        this.buffer.insert(20);
        this.assert(this.buffer.max == 20, "Max should update to the largest value");
        this.assert(this.buffer.min == 10, "Min should remain the smallest value");
        this.assert(this.buffer.average == 15, "Average should be recalculated correctly");

        this.buffer.insert(5);
        this.assert(this.buffer.max == 20, "Max should remain the largest value");
        this.assert(this.buffer.min == 5, "Min should update to the smallest value");
        this.assert(this.buffer.average == 11.67, "Average should be correct after multiple inserts");
    }

    /**
     * 测试环形缓冲行为
     */
    private function testCircularBehavior():Void {
        trace("Testing circular buffer behavior...");

        this.buffer = new SlidingWindowBuffer(3);

        this.buffer.insert(1);
        this.buffer.insert(2);
        this.buffer.insert(3);
        this.buffer.insert(4); // 应覆盖 1

        this.assert(this.buffer.max == 4, "Max should be updated correctly after overwrite");
        this.assert(this.buffer.min == 2, "Min should reflect the smallest value in the current buffer");
        this.assert(this.buffer.average == 3, "Average should be correct after overwrite");
    }

    /**
     * 测试重新计算 max 和 min
     */
    private function testRecalculate():Void {
        trace("Testing recalculation of max and min...");

        this.buffer = new SlidingWindowBuffer(3);

        this.buffer.insert(10);
        this.buffer.insert(20);
        this.buffer.insert(5);
        this.buffer.insert(15); // 覆盖 10

        this.assert(this.buffer.max == 20, "Max should be recalculated correctly after overwrite");
        this.assert(this.buffer.min == 5, "Min should be recalculated correctly after overwrite");

        // 手动设置以触发重计算
        this.buffer.data[1] = 25; // 更新某个值
        this.buffer.recalculateMinMax();

        this.assert(this.buffer.max == 25, "Max should be updated correctly after manual modification");
        this.assert(this.buffer.min == 5, "Min should remain correct after manual modification");
    }

    /**
     * 测试 forEach 方法
     */
    private function testForEach():Void {
        trace("Testing forEach method...");

        this.buffer = new SlidingWindowBuffer(3);

        this.buffer.insert(10);
        this.buffer.insert(20);
        this.buffer.insert(5);

        var result:Array = [];
        this.buffer.forEach(function(value:Number):Void {
            result.push(value);
        });

        this.assert(result.length == 3, "forEach should iterate through all elements");
        this.assert(result[0] == 10, "forEach should correctly iterate the first element");
        this.assert(result[1] == 20, "forEach should correctly iterate the second element");
        this.assert(result[2] == 5, "forEach should correctly iterate the third element");
    }

    /**
     * 性能测试
     */
    private function testPerformance():Void {
        trace("Testing performance...");

        this.buffer = new SlidingWindowBuffer(1000);
        var startTime:Number, endTime:Number;

        // 插入 1000 次
        startTime = getTimer();
        for (var i:Number = 0; i < 1000; i += 5) {
            this.buffer.insert(i);
            this.buffer.insert(i + 1);
            this.buffer.insert(i + 2);
            this.buffer.insert(i + 3);
            this.buffer.insert(i + 4);
        }
        endTime = getTimer();
        trace("Insertions (unrolled loop): " + (endTime - startTime) + "ms");

        // 遍历测试
        startTime = getTimer();
        this.buffer.forEach(function(value:Number):Void {
            // 模拟操作
            var temp:Number = value * 2;
        });
        endTime = getTimer();
        trace("forEach execution: " + (endTime - startTime) + "ms");
    }
}
