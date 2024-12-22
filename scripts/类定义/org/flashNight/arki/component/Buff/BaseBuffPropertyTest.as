// org/flashNight/arki/component/Buff/BaseBuffPropertyTest.as
import org.flashNight.arki.component.Buff.*;
import org.flashNight.arki.component.Buff.BuffHandle.*;
import org.flashNight.gesh.property.*;
import org.flashNight.naki.DataStructures.Dictionary;

class org.flashNight.arki.component.Buff.BaseBuffPropertyTest {
    private static var _testCount:Number = 0;

    // 简单断言函数
    private static function assertEquals(actual, expected, message:String):Void {
        _testCount++;
        if (actual !== expected) {
            trace("[FAIL] " + message + " | Expected: " + expected + ", Got: " + actual);
        } else {
            trace("[PASS] " + message);
        }
    }

    // 断言 Buff 数组包含预期的 Buff
    private static function assertContainsBuffs(actual:Array, expected:Array, message:String):Void {
        _testCount++;
        var allFound:Boolean = true;
        for (var i:Number = 0; i < expected.length; i++) {
            var found:Boolean = false;
            for (var j:Number = 0; j < actual.length; j++) {
                if (actual[j].getType() === expected[i].getType()) {
                    if (expected[i].getType() === "addition") {
                        if (AdditionBuff(actual[j]).getAddition() === AdditionBuff(expected[i]).getAddition()) {
                            found = true;
                            break;
                        }
                    } else if (expected[i].getType() === "multiplier") {
                        if (MultiplierBuff(actual[j]).getMultiplier() === MultiplierBuff(expected[i]).getMultiplier()) {
                            found = true;
                            break;
                        }
                    } else {
                        // 对于其他类型的 Buff，可以根据需要添加比较逻辑
                        found = true;
                        break;
                    }
                }
            }
            if (!found) {
                allFound = false;
                break;
            }
        }

        if (!allFound) {
            trace("[FAIL] " + message + " | Expected Buffs not found in actual Buffs.");
        } else {
            trace("[PASS] " + message);
        }
    }

    public static function runTests():Void {
        trace("\nRunning BaseBuffProperty Tests...\n");

        // 功能测试
        testFunctionality();

        // 边界情况测试
        testEdgeCases();

        // 实战性场景测试
        testRealWorldScenario();

        // 性能测试
        testPerformance();

        trace("\nTests completed. Total: " + _testCount);
    }

    // 功能性测试覆盖所有公共方法
    private static function testFunctionality():Void {
        trace("== Functional Tests ==");

        var target:Object = {}; // 创建测试对象
        var buffProperty:BaseBuffProperty = new BaseBuffProperty(target, "testProp", 10, null);

        // 测试 getPropName
        assertEquals(buffProperty.getPropName(), "testProp", "getPropName should return 'testProp'");

        // 测试基础值
        assertEquals(buffProperty.getBaseValue(), 10, "Initial Base Value");
        assertEquals(buffProperty.getBuffedValue(), 10, "Initial Buffed Value");

        // 添加 Buff 测试
        var addBuff:AdditionBuff = new AdditionBuff(5);
        buffProperty.addBuff(addBuff);
        assertEquals(buffProperty.getBuffedValue(), 15, "Buffed Value after Addition Buff");

        // 添加乘算 Buff 测试
        var mulBuff:MultiplierBuff = new MultiplierBuff(2);
        buffProperty.addBuff(mulBuff);
        assertEquals(buffProperty.getBuffedValue(), 30, "Buffed Value after Multiplier Buff");

        // 测试 getBuffs
        var currentBuffs:Array = buffProperty.getBuffs();
        var expectedBuffs:Array = [addBuff, mulBuff];
        assertContainsBuffs(currentBuffs, expectedBuffs, "getBuffs should return [AdditionBuff, MultiplierBuff]");

        // 测试移除 Buff
        buffProperty.removeBuff(addBuff);
        assertEquals(buffProperty.getBuffedValue(), 20, "Buffed Value after Removing Addition Buff");

        // 测试移除不存在的 Buff
        var nonExistentBuff:AdditionBuff = new AdditionBuff(10);
        buffProperty.removeBuff(nonExistentBuff); // 应该无影响
        assertEquals(buffProperty.getBuffedValue(), 20, "Buffed Value after Attempting to Remove Non-Existent Buff");

        // 测试清空 Buffs
        buffProperty.clearAllBuffs();
        assertEquals(buffProperty.getBuffedValue(), 10, "Buffed Value after Clearing All Buffs");

        // 测试清空已空 Buffs
        buffProperty.clearAllBuffs(); // 应该无影响
        assertEquals(buffProperty.getBuffedValue(), 10, "Buffed Value after Clearing Already Empty Buffs");

        // 测试设置基础值
        buffProperty.setBaseValue(20);
        assertEquals(buffProperty.getBaseValue(), 20, "Base Value after setBaseValue to 20");
        assertEquals(buffProperty.getBuffedValue(), 20, "Buffed Value after Changing Base Value");

        // 测试通过对象直接修改基础值（应触发缓存失效并更新 Buffed Value）
        target.testProp_base = 30;
        assertEquals(buffProperty.getBuffedValue(), 30, "Buffed Value after Directly Changing Base Value to 30");
    }

    // 边界情况测试
    private static function testEdgeCases():Void {
        trace("== Edge Case Tests ==");

        var target:Object = {};
        var buffProperty:BaseBuffProperty = new BaseBuffProperty(target, "testProp", 0, null);

        // 测试初始 Buffed Value为基础值
        assertEquals(buffProperty.getBuffedValue(), 0, "Initial Buffed Value should be 0");

        // 测试添加多个相同类型的 Buff
        var addBuff1:AdditionBuff = new AdditionBuff(10);
        var addBuff2:AdditionBuff = new AdditionBuff(20);
        buffProperty.addBuff(addBuff1);
        buffProperty.addBuff(addBuff2);
        assertEquals(buffProperty.getBuffedValue(), 30, "Buffed Value after Adding Two Addition Buffs");

        // 测试移除其中一个 Buff
        buffProperty.removeBuff(addBuff1);
        assertEquals(buffProperty.getBuffedValue(), 20, "Buffed Value after Removing One Addition Buff");

        // 测试移除所有 Buff
        buffProperty.removeBuff(addBuff2);
        assertEquals(buffProperty.getBuffedValue(), 0, "Buffed Value after Removing All Buffs");

        // 测试添加负值的 Buff（视业务逻辑可能允许或不允许）
        var negativeAddBuff:AdditionBuff = new AdditionBuff(-5);
        buffProperty.addBuff(negativeAddBuff);
        assertEquals(buffProperty.getBuffedValue(), -5, "Buffed Value after Adding Negative Addition Buff");

        // 测试乘算 Buff 为0
        var zeroMulBuff:MultiplierBuff = new MultiplierBuff(0);
        buffProperty.addBuff(zeroMulBuff);
        assertEquals(buffProperty.getBuffedValue(), 0, "Buffed Value after Adding Multiplier Buff with 0");

        // 测试移除乘算 Buff
        buffProperty.removeBuff(zeroMulBuff);
        assertEquals(buffProperty.getBuffedValue(), -5, "Buffed Value after Removing Multiplier Buff with 0");
    }

    // 实战性场景测试：基于百分比的稳定操作顺序
    private static function testRealWorldScenario():Void {
        trace("== Real-World Scenario Tests ==");

        var startTime:Number = getTimer();
        var endTime:Number;

        var target:Object = {};
        var buffProperty:BaseBuffProperty = new BaseBuffProperty(target, "testProp", 100, null);

        var addCount:Number = 0;
        var removeCount:Number = 0;
        var computeCount:Number = 0;

        // 创建一组 Buff
        var buffs:Array = [];
        for (var i:Number = 0; i < 100; i++) {
            buffs.push(new AdditionBuff(1));
            buffs.push(new MultiplierBuff(1.01)); // 1% increase
        }

        // 固定操作顺序基于百分比
        var totalOperations:Number = 1000;
        var addOperations:Number = Math.floor(totalOperations * 0.15);    // 15% 添加
        var removeOperations:Number = Math.floor(totalOperations * 0.15); // 15% 移除
        var computeOperations:Number = totalOperations - addOperations - removeOperations; // 剩余 70% 计算

        // 确定性操作队列
        var operations:Array = [];
        for (var a:Number = 0; a < addOperations; a++) {
            operations.push("add");
        }
        for (var r:Number = 0; r < removeOperations; r++) {
            operations.push("remove");
        }
        for (var c:Number = 0; c < computeOperations; c++) {
            operations.push("compute");
        }

        // 固定的循环顺序
        for (var j:Number = 0; j < totalOperations; j++) {
            var operation:String = operations[j % operations.length]; // 循环操作顺序
            var buffIndex:Number = j % buffs.length; // 确定性选择 Buff
            var selectedBuff:IBuff = buffs[buffIndex];

            if (operation === "add") { // 添加 Buff
                buffProperty.addBuff(selectedBuff);
                addCount++;
            } else if (operation === "remove") { // 移除 Buff
                buffProperty.removeBuff(selectedBuff);
                removeCount++;
            } else if (operation === "compute") { // 计算 Buffed Value
                var buffedValue:Number = buffProperty.getBuffedValue();
                computeCount++;
            }
        }

        trace("Real-World Scenario: Added Buffs: " + addCount + ", Removed Buffs: " + removeCount + ", Computed Buffed Values: " + computeCount);

        endTime = getTimer();
        // 最终验证 Buffed Value 的合理性
        trace("Final Buffed Value: " + buffProperty.getBuffedValue());
        trace("Time to Real-World Scenario with: " + (endTime - startTime) + "ms");
    }


    // 性能测试
    private static function testPerformance():Void {
        trace("== Performance Tests ==");

        var target:Object = {}; // 创建测试对象
        var buffProperty:BaseBuffProperty = new BaseBuffProperty(target, "testProp", 10, null);

        var startTime:Number;
        var endTime:Number;

        // 添加大量 Buff 性能测试
        startTime = getTimer();
        for (var i:Number = 0; i < 10000; i++) {
            buffProperty.addBuff(new AdditionBuff(1));
        }
        endTime = getTimer();
        trace("Time to add 10,000 Buffs: " + (endTime - startTime) + "ms");

        // 计算 Buffed 值性能测试
        startTime = getTimer();
        buffProperty.getBuffedValue();
        endTime = getTimer();
        trace("Time to compute Buffed Value with 10,000 Buffs: " + (endTime - startTime) + "ms");

        // 移除大量 Buff 性能测试
        startTime = getTimer();
        for (var j:Number = 0; j < 10000; j++) {
            buffProperty.clearAllBuffs();
        }
        endTime = getTimer();
        trace("Time to clear Buffs 10,000 times: " + (endTime - startTime) + "ms");
    }

    // 模拟 AS2 的 getTimer() 方法，用于获取当前时间戳（如未定义）
    private static function getTimer():Number {
        return new Date().getTime();
    }
}
