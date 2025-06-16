// org/flashNight/arki/component/Buff/test/BaseBuffTest.as

import org.flashNight.arki.component.Buff.*;
import org.flashNight.arki.component.Buff.test.*;
/**
 * BaseBuff测试套件
 * 
 * 全面测试BaseBuff类的所有功能，包括：
 * - 构造函数行为和ID生成
 * - IBuff接口实现
 * - 默认行为验证
 * - ID唯一性保证
 * - 继承和多态性测试
 */
class org.flashNight.arki.component.Buff.test.BaseBuffTest {
    
    private static var testCount:Number = 0;
    private static var passedCount:Number = 0;
    private static var failedCount:Number = 0;
    
    /**
     * 运行所有测试用例
     */
    public static function runAllTests():Void {
        trace("=== BaseBuff Test Suite Started ===");
        
        // 重置测试计数器
        testCount = 0;
        passedCount = 0;
        failedCount = 0;
        
        // 基础功能测试
        testConstructor();
        testGetId();
        testGetType();
        testIsActive();
        testDestroy();
        testApplyEffect();
        
        // ID唯一性测试
        testIdUniqueness();
        testIdSequential();
        
        // 接口实现测试
        testIBuffInterface();
        
        // 多实例测试
        testMultipleInstances();
        
        // 继承测试
        testInheritance();
        
        // 边界条件测试
        testEdgeCases();
        
        // 输出测试结果
        printTestResults();
    }
    
    /**
     * 测试构造函数行为
     */
    private static function testConstructor():Void {
        startTest("Constructor Test");
        
        try {
            var buff:BaseBuff = new BaseBuff();
            
            // 验证对象创建成功
            assert(buff != null, "BaseBuff instance should be created");
            
            // 验证ID已设置
            assert(buff.getId() != null, "ID should be set after construction");
            assert(buff.getId() != "", "ID should not be empty");
            
            // 验证类型设置
            assert(buff.getType() == "BaseBuff", "Type should be 'BaseBuff'");
            
            passTest();
        } catch (e) {
            failTest("Constructor failed: " + e.message);
        }
    }
    
    /**
     * 测试getId()方法
     */
    private static function testGetId():Void {
        startTest("getId() Method Test");
        
        try {
            var buff:BaseBuff = new BaseBuff();
            var id:String = buff.getId();
            
            // 验证ID格式
            assert(id != null, "ID should not be null");
            assert(id != "", "ID should not be empty string");
            assert(id.length > 0, "ID should have positive length");
            
            // 验证ID是字符串类型的数字
            var numId:Number = Number(id);
            assert(!isNaN(numId), "ID should be convertible to number");
            assert(numId >= 0, "ID should be non-negative");
            
            passTest();
        } catch (e) {
            failTest("getId() test failed: " + e.message);
        }
    }
    
    /**
     * 测试getType()方法
     */
    private static function testGetType():Void {
        startTest("getType() Method Test");
        
        try {
            var buff:BaseBuff = new BaseBuff();
            var type:String = buff.getType();
            
            assert(type == "BaseBuff", "Type should be 'BaseBuff', got: " + type);
            
            // 确保多次调用返回相同结果
            assert(buff.getType() == type, "getType() should return consistent result");
            
            passTest();
        } catch (e) {
            failTest("getType() test failed: " + e.message);
        }
    }
    
    /**
     * 测试isActive()默认行为
     */
    private static function testIsActive():Void {
        startTest("isActive() Default Behavior Test");
        
        try {
            var buff:BaseBuff = new BaseBuff();
            
            // 验证默认激活状态
            assert(buff.isActive() == true, "BaseBuff should be active by default");
            
            // 确保多次调用返回相同结果
            assert(buff.isActive() == true, "isActive() should be consistently true");
            
            passTest();
        } catch (e) {
            failTest("isActive() test failed: " + e.message);
        }
    }
    
    /**
     * 测试destroy()方法
     */
    private static function testDestroy():Void {
        startTest("destroy() Method Test");
        
        try {
            var buff:BaseBuff = new BaseBuff();
            
            // 验证destroy()方法可以被调用而不出错
            buff.destroy();
            
            // 验证destroy()后对象状态仍然正常
            assert(buff.getId() != null, "ID should still be accessible after destroy");
            assert(buff.getType() == "BaseBuff", "Type should still be accessible after destroy");
            assert(buff.isActive() == true, "isActive should still work after destroy");
            
            passTest();
        } catch (e) {
            failTest("destroy() test failed: " + e.message);
        }
    }
    
    /**
     * 测试applyEffect()基础行为
     */
    private static function testApplyEffect():Void {
        startTest("applyEffect() Base Implementation Test");
        
        try {
            var buff:BaseBuff = new BaseBuff();
            
            // 创建模拟的参数（可以为null，因为基类实现为空）
            var calculator:IBuffCalculator = null;
            var context:BuffContext = null;
            
            // 验证applyEffect()可以被调用而不出错
            buff.applyEffect(calculator, context);
            
            passTest();
        } catch (e) {
            failTest("applyEffect() test failed: " + e.message);
        }
    }
    
    /**
     * 测试ID唯一性
     */
    private static function testIdUniqueness():Void {
        startTest("ID Uniqueness Test");
        
        try {
            var buff1:BaseBuff = new BaseBuff();
            var buff2:BaseBuff = new BaseBuff();
            var buff3:BaseBuff = new BaseBuff();
            
            var id1:String = buff1.getId();
            var id2:String = buff2.getId();
            var id3:String = buff3.getId();
            
            // 验证所有ID都不相同
            assert(id1 != id2, "ID1 and ID2 should be different: " + id1 + " vs " + id2);
            assert(id1 != id3, "ID1 and ID3 should be different: " + id1 + " vs " + id3);
            assert(id2 != id3, "ID2 and ID3 should be different: " + id2 + " vs " + id3);
            
            passTest();
        } catch (e) {
            failTest("ID uniqueness test failed: " + e.message);
        }
    }
    
    /**
     * 测试ID顺序递增
     */
    private static function testIdSequential():Void {
        startTest("ID Sequential Generation Test");
        
        try {
            var buff1:BaseBuff = new BaseBuff();
            var buff2:BaseBuff = new BaseBuff();
            
            var id1:Number = Number(buff1.getId());
            var id2:Number = Number(buff2.getId());
            
            // 验证ID是递增的
            assert(id2 > id1, "Second ID should be greater than first: " + id2 + " > " + id1);
            assert(id2 == id1 + 1, "IDs should be sequential: " + id2 + " should equal " + (id1 + 1));
            
            passTest();
        } catch (e) {
            failTest("ID sequential test failed: " + e.message);
        }
    }
    
    /**
     * 测试IBuff接口实现
     */
    private static function testIBuffInterface():Void {
        startTest("IBuff Interface Implementation Test");
        
        try {
            var buff:BaseBuff = new BaseBuff();
            var iBuff:IBuff = IBuff(buff); // 转型测试
            
            // 验证接口方法可用
            assert(iBuff.getId() != null, "getId() should work through IBuff interface");
            assert(iBuff.getType() == "BaseBuff", "getType() should work through IBuff interface");
            assert(iBuff.isActive() == true, "isActive() should work through IBuff interface");
            
            // 验证方法调用不出错
            iBuff.applyEffect(null, null);
            iBuff.destroy();
            
            passTest();
        } catch (e) {
            failTest("IBuff interface test failed: " + e.message);
        }
    }
    
    /**
     * 测试多实例创建
     */
    private static function testMultipleInstances():Void {
        startTest("Multiple Instances Test");
        
        try {
            var buffs:Array = [];
            var numInstances:Number = 10;
            
            // 创建多个实例
            for (var i:Number = 0; i < numInstances; i++) {
                buffs.push(new BaseBuff());
            }
            
            // 验证所有实例都正常工作
            for (var j:Number = 0; j < buffs.length; j++) {
                var buff:BaseBuff = BaseBuff(buffs[j]);
                assert(buff.getId() != null, "Instance " + j + " should have valid ID");
                assert(buff.getType() == "BaseBuff", "Instance " + j + " should have correct type");
                assert(buff.isActive() == true, "Instance " + j + " should be active");
            }
            
            // 验证所有ID都是唯一的
            for (var k:Number = 0; k < buffs.length; k++) {
                for (var l:Number = k + 1; l < buffs.length; l++) {
                    var buff1:BaseBuff = BaseBuff(buffs[k]);
                    var buff2:BaseBuff = BaseBuff(buffs[l]);
                    assert(buff1.getId() != buff2.getId(), 
                           "Instances " + k + " and " + l + " should have different IDs");
                }
            }
            
            passTest();
        } catch (e) {
            failTest("Multiple instances test failed: " + e.message);
        }
    }
    
    /**
     * 测试继承行为
     */
    private static function testInheritance():Void {
        startTest("Inheritance Test");
        
        try {
            // 创建一个测试子类
            var testBuff:TestBuff = new TestBuff();
            
            // 验证继承的方法
            assert(testBuff.getId() != null, "Inherited getId() should work");
            assert(testBuff.isActive() == true, "Inherited isActive() should work");
            
            // 验证重写的方法
            assert(testBuff.getType() == "TestBuff", "Overridden getType() should work");
            
            // 验证子类可以作为IBuff使用
            var iBuff:IBuff = IBuff(testBuff);
            assert(iBuff.getType() == "TestBuff", "Polymorphism should work");
            
            passTest();
        } catch (e) {
            failTest("Inheritance test failed: " + e.message);
        }
    }
    
    /**
     * 测试边界条件
     */
    private static function testEdgeCases():Void {
        startTest("Edge Cases Test");
        
        try {
            // 测试快速连续创建
            var buff1:BaseBuff = new BaseBuff();
            var buff2:BaseBuff = new BaseBuff();
            var buff3:BaseBuff = new BaseBuff();
            
            // 验证即使快速创建，ID仍然唯一
            assert(buff1.getId() != buff2.getId(), "Rapid creation should still have unique IDs");
            assert(buff2.getId() != buff3.getId(), "Rapid creation should still have unique IDs");
            
            // 测试方法的防护性
            var buff:BaseBuff = new BaseBuff();
            
            // 多次调用destroy()
            buff.destroy();
            buff.destroy();
            buff.destroy();
            
            // 验证对象仍然正常
            assert(buff.getId() != null, "Multiple destroy() calls should not break object");
            
            passTest();
        } catch (e) {
            failTest("Edge cases test failed: " + e.message);
        }
    }
    
    // ============= 测试工具方法 =============
    
    private static function startTest(testName:String):Void {
        testCount++;
        trace("Running test " + testCount + ": " + testName);
    }
    
    private static function passTest():Void {
        passedCount++;
        trace("  ✓ PASSED");
    }
    
    private static function failTest(message:String):Void {
        failedCount++;
        trace("  ✗ FAILED: " + message);
    }
    
    private static function assert(condition:Boolean, message:String):Void {
        if (!condition) {
            throw new Error("Assertion failed: " + message);
        }
    }
    
    private static function printTestResults():Void {
        trace("=== BaseBuff Test Suite Results ===");
        trace("Total tests: " + testCount);
        trace("Passed: " + passedCount);
        trace("Failed: " + failedCount);
        trace("Success rate: " + Math.round((passedCount / testCount) * 100) + "%");
        
        if (failedCount == 0) {
            trace("🎉 All tests passed!");
        } else {
            trace("❌ " + failedCount + " test(s) failed");
        }
        trace("=====================================");
    }
}

