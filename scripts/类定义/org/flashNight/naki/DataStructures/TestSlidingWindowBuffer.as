import org.flashNight.naki.DataStructures.*;

class org.flashNight.naki.DataStructures.TestSlidingWindowBuffer {
    private var buffer:SlidingWindowBuffer; // 被测试的 SlidingWindowBuffer 实例
    private var assertCount:Number; // 成功断言计数
    private var errorCount:Number; // 失败断言计数

    public function TestSlidingWindowBuffer() {
        this.assertCount = 0;
        this.errorCount = 0;
    }

    public function runTests():Void {
        trace("Running tests for SlidingWindowBuffer...");

        this.testInitialization();
        this.testInsert();
        this.testCircularBehavior();
        this.testForEach();
        this.testEdgeCases();
        this.testInvalidInputs();
        this.testMinMaxReplacement();
        this.testUniformInsertions();
        this.testPerformance();

        trace("All tests completed.");
        trace("Assertions passed: " + this.assertCount);
        trace("Assertions failed: " + this.errorCount);
    }

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
     * 初始状态下，缓冲区已满且全为0。
     */
    private function testInitialization():Void {
        trace("Testing initialization...");

        this.buffer = new SlidingWindowBuffer(5);
        // 全0状态下
        // max=0, min=0, average=0, sum=0, count=5
        this.assert(this.buffer.max == 0, "Max should be 0 at initialization");
        this.assert(this.buffer.min == 0, "Min should be 0 at initialization");
        this.assert(this.buffer.average == 0, "Average should be 0 at initialization");
        this.assert(this.buffer.data.length == 5, "Buffer should initialize with the correct size");
    }

    /**
     * 测试插入数据
     * 由于初始即满，插入将替换一个0值
     */
    private function testInsert():Void {
        trace("Testing insert method...");

        this.buffer = new SlidingWindowBuffer(3);
        // 初始状态: data=[0,0,0], min=0, max=0, avg=0 (sum=0,count=3)

        this.buffer.insert(10);
        // 现在的数据还是3个元素，其中一个变为10，其余为0，例如[10,0,0]
        // sum=10, avg=10/3≈3.33，max=10，min=0
        this.assert(this.buffer.max == 10, "Max should update to the largest value after first insert");
        this.assert(this.buffer.min == 0, "Min should remain 0 because other elements are still 0");
        this.assert(this.buffer.average == Math.round((10/3)*100)/100, "Average should be correct after insert (≈3.33)");

        this.buffer.insert(20);
        // 替换下一个旧值0 -> 20，数据可能变为[10,20,0]
        // sum=30, avg=30/3=10, max=20, min=0
        this.assert(this.buffer.max == 20, "Max should be updated to 20");
        this.assert(this.buffer.min == 0, "Min should still be 0");
        this.assert(this.buffer.average == 10, "Average should be 10 after second insert");

        this.buffer.insert(5);
        // 替换下一个旧值0 -> 5，数据变为[10,20,5]
        // sum=35, avg=35/3≈11.67，max=20, min=5（因为现在没有0了）
        this.assert(this.buffer.max == 20, "Max should remain 20");
        this.assert(this.buffer.min == 5, "Min should now update to 5");
        this.assert(this.buffer.average == 11.67, "Average should be about 11.67 after multiple inserts");
    }

    /**
     * 测试环形缓冲行为
     */
    private function testCircularBehavior():Void {
        trace("Testing circular buffer behavior...");

        this.buffer = new SlidingWindowBuffer(3);
        // 初始: [0,0,0], min=0, max=0, avg=0

        this.buffer.insert(1); // [1,0,0], sum=1,avg≈0.33
        this.buffer.insert(2); // [1,2,0], sum=3,avg=1
        this.buffer.insert(3); // [1,2,3], sum=6,avg=2,min=1,max=3
        this.buffer.insert(4); // 替换最早插入的1 ->4, [4,2,3], sum=9,avg=3,min=2,max=4
        this.assert(this.buffer.max == 4, "Max should be updated correctly after overwrite");
        this.assert(this.buffer.min == 2, "Min should reflect the smallest value after overwrite");
        this.assert(this.buffer.average == 3, "Average should be correct after overwrite");
    }

    /**
     * 测试 forEach 方法
     */
    private function testForEach():Void {
        trace("Testing forEach method...");

        this.buffer = new SlidingWindowBuffer(3);
        // 初始：[0,0,0]
        this.buffer.insert(10); // [10,0,0]
        this.buffer.insert(20); // [10,20,0]
        this.buffer.insert(5);  // [10,20,5]

        var result:Array = [];
        this.buffer.forEach(function(value:Number):Void {
            result.push(value);
        });

        // 数据顺序可能是从 head 开始，head的定位需要考虑
        // 假设head指向下一个将要覆盖的元素位置，此时head插入3次后应回到0位置:
        // 初始head=0，插入10后head=1，插入20后head=2，插入5后head=0
        // forEach遍历时会从head开始：head=0 -> 遍历 data[0], data[1], data[2]
        // 当前data=[10,20,5]
        this.assert(result.length == 3, "forEach should iterate through all elements");
        this.assert(result[0] == 10, "forEach should correctly iterate the first element");
        this.assert(result[1] == 20, "forEach should correctly iterate the second element");
        this.assert(result[2] == 5, "forEach should correctly iterate the third element");
    }

    /**
     * 测试边缘和极端情况
     */
    private function testEdgeCases():Void {
        trace("Testing edge cases...");

        // Test buffer size of 1
        this.buffer = new SlidingWindowBuffer(1);
        this.buffer.insert(100);
        this.assert(this.buffer.max == 100, "Max should be 100 for buffer size 1 after insert");
        this.assert(this.buffer.min == 100, "Min should be 100 for buffer size 1 after insert");
        this.assert(this.buffer.average == 100, "Average should be 100 for buffer size 1 after insert");

        this.buffer.insert(200);
        this.assert(this.buffer.max == 200, "Max should update to 200 for buffer size 1 after second insert");
        this.assert(this.buffer.min == 200, "Min should update to 200 for buffer size 1 after second insert");
        this.assert(this.buffer.average == 200, "Average should be 200 for buffer size 1 after second insert");

        // Test buffer size of 0
        this.buffer = new SlidingWindowBuffer(0);
        this.assert(this.buffer.data.length == 1, "Buffer size should default to 1 when initialized with 0");
        this.assert(this.buffer.max == 0, "Max should be 0 for buffer size defaulting to 1");
        this.assert(this.buffer.min == 0, "Min should be 0 for buffer size defaulting to 1");
        this.assert(this.buffer.average == 0, "Average should be 0 for buffer size defaulting to 1");

        // Test inserting identical values multiple times
        this.buffer = new SlidingWindowBuffer(3);
        this.buffer.insert(5);
        this.buffer.insert(5);
        this.buffer.insert(5);
        this.assert(this.buffer.max == 5, "Max should be 5 after uniform insertions");
        this.assert(this.buffer.min == 5, "Min should be 5 after uniform insertions");
        this.assert(this.buffer.average == 5, "Average should be 5 after uniform insertions");
    }

    /**
     * 测试无效输入
     */
    private function testInvalidInputs():Void {
        trace("Testing invalid inputs...");

        // Test negative buffer size
        this.buffer = new SlidingWindowBuffer(-5);
        // Depending on implementation, buffer might default to size=1 or throw an error
        // Since current class does not handle, we might need to check for specific behavior
        // For demonstration, assuming it defaults to size=1
        this.assert(this.buffer.size == 1, "Buffer size should default to 1 when initialized with negative size");

        // Test non-integer buffer size
        this.buffer = new SlidingWindowBuffer(3.5);
        this.assert(this.buffer.size == 3, "Buffer size should be floored to 3 when initialized with 3.5");

        // Test inserting non-number values
        this.buffer = new SlidingWindowBuffer(3);
        // Insert a string
        this.buffer.insert(Number("test"));
        this.assert(isNaN(this.buffer.max) || this.buffer.max == 0, "Max should handle non-number insertions appropriately");
        this.assert(isNaN(this.buffer.min) || this.buffer.min == 0, "Min should handle non-number insertions appropriately");
        this.assert(isNaN(this.buffer.average) || this.buffer.average == 0, "Average should handle non-number insertions appropriately");
    }

    /**
     * 测试替换当前的 min 和 max
     */
    private function testMinMaxReplacement():Void {
        trace("Testing min and max replacement...");

        this.buffer = new SlidingWindowBuffer(3);
        this.buffer.insert(10); // [10,0,0]
        this.buffer.insert(20); // [10,20,0]
        this.buffer.insert(5);  // [10,20,5]
        // Current min=5, max=20

        this.buffer.insert(25); // Replace 10 with 25 -> [25,20,5]
        this.assert(this.buffer.max == 25, "Max should update to 25 after inserting a new maximum");
        this.assert(this.buffer.min == 5, "Min should remain 5 after inserting a higher value");

        this.buffer.insert(2); // Replace 20 with 2 -> [25,2,5]
        this.assert(this.buffer.max == 25, "Max should remain 25 after inserting a lower value");
        this.assert(this.buffer.min == 2, "Min should update to 2 after inserting a new minimum");

        this.buffer.insert(30); // Replace 5 with 30 -> [25,2,30]
        this.assert(this.buffer.max == 30, "Max should update to 30 after inserting a new maximum");
        this.assert(this.buffer.min == 2, "Min should remain 2 after inserting a higher value");
    }

    /**
     * 测试插入相同值多次
     */
    private function testUniformInsertions():Void {
        trace("Testing uniform insertions...");

        this.buffer = new SlidingWindowBuffer(4);
        this.buffer.insert(7); // [7,0,0,0]
        this.buffer.insert(7); // [7,7,0,0]
        this.buffer.insert(7); // [7,7,7,0]
        this.buffer.insert(7); // [7,7,7,7]
        this.assert(this.buffer.max == 7, "Max should be 7 after uniform insertions");
        this.assert(this.buffer.min == 7, "Min should be 7 after uniform insertions");
        this.assert(this.buffer.average == 7, "Average should be 7 after uniform insertions");

        this.buffer.insert(7); // Overwrite first 7 -> [7,7,7,7]
        this.assert(this.buffer.max == 7, "Max should remain 7 after overwriting with the same value");
        this.assert(this.buffer.min == 7, "Min should remain 7 after overwriting with the same value");
        this.assert(this.buffer.average == 7, "Average should remain 7 after overwriting with the same value");
    }

    /**
     * 性能测试
     */
    private function testPerformance():Void {
        trace("Testing performance...");

        this.buffer = new SlidingWindowBuffer(10000);
        var startTime:Number, endTime:Number;

        // 插入 10000 次
        startTime = getTimer();
        for (var i:Number = 0; i < 10000; i++) {
            this.buffer.insert(i);
        }
        endTime = getTimer();
        trace("Insertions: " + (endTime - startTime) + "ms");

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
