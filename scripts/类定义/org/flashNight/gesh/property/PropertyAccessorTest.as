import org.flashNight.gesh.property.*;

/**
 * PropertyAccessorTest 类
 * 用于测试 PropertyAccessor 类的功能和性能
 */
class org.flashNight.gesh.property.PropertyAccessorTest {
    private var _testPassed:Number;
    private var _testFailed:Number;

    public function PropertyAccessorTest() {
        this._testPassed = 0;
        this._testFailed = 0;
        trace("=== PropertyAccessor Test Initialized ===");
    }

    /**
     * 运行所有测试
     */
    public function runTests():Void {
        trace("=== Running PropertyAccessor Tests ===");
        this.testBasicSetGet();
        this.testReadOnlyProperty();
        this.testComputedProperty();
        this.testInvalidateCache();
        this.testOnSetCallback();
        this.testValidationFunc(); // 新增的测试用例
        this.testNegativeSetValue(); // 更新后的测试用例
        this.testZeroAndLargeValues();
        this.testMultipleInvalidSets(); // 更新后的测试用例
        this.testMultipleInvalidate();
        this.testCallbackWithComplexLogic();
        this.testPerformance();
        trace("=== Tests Completed ===");
        trace("Tests Passed: " + this._testPassed + ", Tests Failed: " + this._testFailed);
    }

    /**
     * 断言函数
     * @param condition 测试条件
     * @param message 断言消息
     */
    private function assert(condition:Boolean, message:String):Void {
        if (condition) {
            this._testPassed++;
            trace("[PASS] " + message);
        } else {
            this._testFailed++;
            trace("[FAIL] " + message);
        }
    }

    /**
     * 测试基本 set 和 get 功能
     */
    private function testBasicSetGet():Void {
        trace("\n--- Test: Basic Set/Get ---");

        var obj:Object = {};
        var accessor:PropertyAccessor = new PropertyAccessor(obj, "testProp", 10, null, null, null);

        // 初始值
        this.assert(obj.testProp == 10, "Initial value is 10");

        // 设置新值
        obj.testProp = 20;
        this.assert(obj.testProp == 20, "Updated value is 20");
    }

    /**
     * 测试只读属性
     */
    private function testReadOnlyProperty():Void {
        trace("\n--- Test: Read-Only Property ---");

        var obj:Object = {};
        var accessor:PropertyAccessor = new PropertyAccessor(
            obj,
            "readOnlyProp",
            0, // 默认值可以为 0
            function():Number {
                return 42; // 返回固定值
            },
            null,
            null
        );

        // 读取只读属性
        this.assert(obj.readOnlyProp == 42, "Read-only value is 42");

        // 尝试写入只读属性
        obj.readOnlyProp = 50;
        this.assert(obj.readOnlyProp == 42, "Attempt to write read-only property does not change value");
    }

    /**
     * 测试计算属性
     */
    private function testComputedProperty():Void {
        trace("\n--- Test: Computed Property ---");

        var obj:Object = {};
        var baseValue:Number = 5; // 确保在创建 PropertyAccessor 前初始化
        var accessor:PropertyAccessor = new PropertyAccessor(
            obj,
            "computedProp",
            0,
            function():Number {
                return baseValue * 2;
            },
            null,
            null
        );

        // 计算属性
        this.assert(obj.computedProp == 10, "Computed value is 10");

        // 修改基础值
        baseValue = 15;
        accessor.invalidate();
        this.assert(obj.computedProp == 30, "Updated computed value is 30");
    }

    /**
     * 测试缓存失效机制
     */
    private function testInvalidateCache():Void {
        trace("\n--- Test: Cache Invalidate ---");

        var obj:Object = {};
        var accessor:PropertyAccessor = new PropertyAccessor(
            obj,
            "cachedProp",
            100,
            null,
            null,
            null
        );

        // 初始值
        this.assert(obj.cachedProp == 100, "Initial cached value is 100");

        // 更新值
        obj.cachedProp = 200;
        this.assert(obj.cachedProp == 200, "Updated cached value is 200");
    }

    /**
     * 测试设置回调
     */
    private function testOnSetCallback():Void {
        trace("\n--- Test: On Set Callback ---");

        var obj:Object = {};
        var callbackTriggered:Boolean = false;

        var accessor:PropertyAccessor = new PropertyAccessor(
            obj,
            "callbackProp",
            0,
            null,
            function():Void {
                callbackTriggered = true;
            },
            null
        );

        // 设置值并触发回调
        obj.callbackProp = 123;
        this.assert(callbackTriggered, "Callback is triggered");
        this.assert(obj.callbackProp == 123, "Callback property value is correctly updated to 123");
    }

    /**
     * 测试验证函数
     */
    private function testValidationFunc():Void {
        trace("\n--- Test: Validation Function ---");

        var obj:Object = {};
        var accessor:PropertyAccessor = new PropertyAccessor(
            obj,
            "validatedProp",
            50,
            null,
            null,
            function(value:Number):Boolean {
                return value >= 10 && value <= 100; // 验证值必须在 [10, 100] 之间
            }
        );

        this.assert(obj.validatedProp == 50, "Initial validatedProp value is 50");

        obj.validatedProp = 20;
        this.assert(obj.validatedProp == 20, "Value within range updates to 20");

        obj.validatedProp = 200;
        this.assert(obj.validatedProp == 20, "Value out of range does not change (still 20)");

        obj.validatedProp = 5;
        this.assert(obj.validatedProp == 20, "Value below range does not change (still 20)");
    }

    /**
     * 测试设置负值（边界情况）
     */
    private function testNegativeSetValue():Void {
        trace("\n--- Test: Negative Set Value ---");

        var obj:Object = {};
        var accessor:PropertyAccessor = new PropertyAccessor(
            obj,
            "negativeProp",
            50,
            null,
            null,
            function(value:Number):Boolean {
                return value >= 0; // 允许非负值
            }
        );

        // 初始值
        this.assert(obj.negativeProp == 50, "Initial negativeProp value is 50");

        // 尝试设置负值
        obj.negativeProp = -10;
        this.assert(obj.negativeProp == 50, "Attempt to set negative value does not change value");

        // 多次尝试设置负值
        obj.negativeProp = -20;
        this.assert(obj.negativeProp == 50, "Second attempt to set negative value does not change value");
    }

    /**
     * 测试设置零值和大值（边界情况）
     */
    private function testZeroAndLargeValues():Void {
        trace("\n--- Test: Zero and Large Values ---");

        var obj:Object = {};
        var accessor:PropertyAccessor = new PropertyAccessor(
            obj,
            "zeroAndLargeProp",
            0,
            null,
            null,
            null // 不提供验证函数，允许任何数值
        );

        // 初始值为零
        this.assert(obj.zeroAndLargeProp == 0, "Initial zeroAndLargeProp value is 0");

        // 设置零值
        obj.zeroAndLargeProp = 0;
        this.assert(obj.zeroAndLargeProp == 0, "Setting zero value retains 0");

        // 设置一个非常大的值
        var largeValue:Number = 1e+10;
        obj.zeroAndLargeProp = largeValue;
        this.assert(obj.zeroAndLargeProp == largeValue, "Setting large value correctly updates to " + largeValue);
    }

    /**
     * 测试多次设置负值（边界情况）
     */
    private function testMultipleInvalidSets():Void {
        trace("\n--- Test: Multiple Invalid Sets ---");

        var obj:Object = {};
        var accessor:PropertyAccessor = new PropertyAccessor(
            obj,
            "multipleInvalidSetProp",
            100,
            null,
            null,
            function(value:Number):Boolean {
                return value >= 0; // 允许非负值
            }
        );

        // 初始值
        this.assert(obj.multipleInvalidSetProp == 100, "Initial multipleInvalidSetProp value is 100");

        // 多次尝试设置负值
        var attempts:Number = 5;
        for (var i:Number = 1; i <= attempts; i++) {
            obj.multipleInvalidSetProp = -i * 10;
            this.assert(obj.multipleInvalidSetProp == 100, "Attempt " + i + " to set negative value does not change value");
        }
    }

    /**
     * 测试多次缓存失效
     */
    private function testMultipleInvalidate():Void {
        trace("\n--- Test: Multiple Invalidate ---");

        var obj:Object = {};
        var computeCount:Number = 0;
        var accessor:PropertyAccessor = new PropertyAccessor(
            obj,
            "multipleInvalidateProp",
            0,
            function():Number {
                computeCount++;
                return computeCount * 10;
            },
            null,
            null
        );

        // 初始计算
        this.assert(obj.multipleInvalidateProp == 10, "Initial multipleInvalidateProp value is 10");

        // 多次使缓存失效并重新计算
        var invalidateTimes:Number = 3;
        for (var i:Number = 1; i <= invalidateTimes; i++) {
            accessor.invalidate();
            this.assert(obj.multipleInvalidateProp == (i + 1) * 10, "After invalidate " + i + ", value is " + ((i + 1) * 10));
        }

        // 确认计算次数
        this.assert(computeCount == 4, "computeFunc called 4 times");
    }

    /**
     * 测试回调函数中的复杂逻辑
     */
    private function testCallbackWithComplexLogic():Void {
        trace("\n--- Test: Callback with Complex Logic ---");

        var obj:Object = {};
        var callbackCounter:Number = 0;

        var accessor:PropertyAccessor = new PropertyAccessor(
            obj,
            "complexCallbackProp",
            0,
            null,
            function():Void {
                // 复杂逻辑示例：递增计数器
                callbackCounter++;
            },
            null
        );

        // 设置值多次，触发回调
        obj.complexCallbackProp = 10;
        obj.complexCallbackProp = 20;
        obj.complexCallbackProp = 30;

        this.assert(callbackCounter == 3, "Callback triggered 3 times");
        this.assert(obj.complexCallbackProp == 30, "complexCallbackProp correctly updated to 30");
    }

    /**
     * 性能测试
     */
    private function testPerformance():Void {
        trace("\n--- Test: Performance ---");

        var obj:Object = {};
        var iterations:Number = 100000;
        var accessor:PropertyAccessor = new PropertyAccessor(
            obj,
            "performanceProp",
            0,
            null,
            null,
            null
        );

        var startTime:Number = getTimer();

        // 混合读写性能测试
        for (var i:Number = 0; i < iterations; i++) {
            obj.performanceProp = i;
            var val:Number = obj.performanceProp;
        }

        var endTime:Number = getTimer();
        trace("Performance Test Completed in " + (endTime - startTime) + " ms for " + iterations + " iterations.");

        // 额外的读性能测试
        accessor.invalidate(); // 确保缓存失效
        var readStartTime:Number = getTimer();

        for (var j:Number = 0; j < iterations; j++) {
            var readVal:Number = obj.performanceProp;
        }

        var readEndTime:Number = getTimer();
        trace("Read Performance Test Completed in " + (readEndTime - readStartTime) + " ms for " + iterations + " read iterations.");

        // 额外的写性能测试
        var writeAccessor:PropertyAccessor = new PropertyAccessor(
            obj,
            "writePerformanceProp",
            0,
            null,
            null,
            null
        );

        var writeStartTime:Number = getTimer();

        for (var k:Number = 0; k < iterations; k++) {
            obj.writePerformanceProp = k;
        }

        var writeEndTime:Number = getTimer();
        trace("Write Performance Test Completed in " + (writeEndTime - writeStartTime) + " ms for " + iterations + " write iterations.");
    }
}
