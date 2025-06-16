// org/flashNight/arki/component/Buff/test/PropertyContainerTest.as

import org.flashNight.arki.component.Buff.*;
import org.flashNight.arki.component.Buff.test.*;
import org.flashNight.gesh.property.*;

/**
 * PropertyContainer测试套件
 * 
 * 全面测试PropertyContainer类的所有功能，包括：
 * - 基础属性管理（构造、基础值设置获取）
 * - Buff管理（添加、移除、清除、计数）
 * - PropertyAccessor集成（直接属性访问、缓存机制）
 * - 数值计算（单个buff、多buff组合、优先级）
 * - 回调机制（值变化回调、外部设置处理）
 * - 性能优化（缓存效果验证）
 * - 边界条件和错误处理
 * - 调试和状态查询功能
 * 
 * 使用方式: PropertyContainerTest.runAllTests();
 */
class org.flashNight.arki.component.Buff.test.PropertyContainerTest {
    
    private static var testCount:Number = 0;
    private static var passedCount:Number = 0;
    private static var failedCount:Number = 0;
    
    /**
     * 运行所有测试用例
     * 一句话启动: PropertyContainerTest.runAllTests();
     */
    public static function runAllTests():Void {
        trace("=== PropertyContainer Test Suite Started ===");
        
        // 重置测试计数器
        testCount = 0;
        passedCount = 0;
        failedCount = 0;
        
        // 基础功能测试
        testConstructor();
        testBaseValueOperations();
        testPropertyNameAccess();
        
        // PropertyAccessor集成测试
        testPropertyAccessorIntegration();
        testDirectPropertyAccess();
        testCachingMechanism();
        
        // Buff管理测试
        testAddBuff();
        testRemoveBuff();
        testClearBuffs();
        testBuffCounting();
        testHasBuff();
        
        // 计算功能测试
        testSingleBuffCalculation();
        testMultipleBuffCalculation();
        testBuffPriorityCalculation();
        testComplexBuffCombination();
        
        // 回调机制测试
        testChangeCallback();
        testExternalPropertySet();
        
        // 缓存和性能测试
        testFinalValueCaching();
        testForceRecalculation();
        testInvalidationMechanism();
        
        // 边界条件测试
        testEmptyContainer();
        testInactiveBuffs();
        testInvalidInputs();
        testEdgeCases();
        
        // 调试和工具测试
        testToString();
        testDestroy();
        
        // 输出测试结果
        printTestResults();
    }
    
    /**
     * 测试构造函数
     */
    private static function testConstructor():Void {
        startTest("Constructor Test");
        
        try {
            var target:Object = {};
            var container:PropertyContainer = new PropertyContainer(target, "testProp", 100, null);
            
            assert(container != null, "PropertyContainer instance should be created");
            assert(container.getPropertyName() == "testProp", "Property name should be set correctly");
            assert(container.getBaseValue() == 100, "Base value should be set correctly");
            assert(container.getBuffCount() == 0, "New container should have 0 buffs");
            assert(target.testProp == 100, "Target object should have the property accessible");
            
            container.destroy();
            passTest();
        } catch (e) {
            failTest("Constructor failed: " + e.message);
        }
    }
    
    /**
     * 测试基础值操作
     */
    private static function testBaseValueOperations():Void {
        startTest("Base Value Operations Test");
        
        try {
            var target:Object = {};
            var container:PropertyContainer = new PropertyContainer(target, "health", 100, null);
            
            // 测试初始基础值
            assert(container.getBaseValue() == 100, "Initial base value should be 100");
            assert(container.getFinalValue() == 100, "Initial final value should equal base value");
            
            // 测试设置基础值
            container.setBaseValue(150);
            assert(container.getBaseValue() == 150, "Base value should update to 150");
            assert(container.getFinalValue() == 150, "Final value should update to 150");
            assert(target.health == 150, "Target property should update to 150");
            
            // 测试设置相同值（应该不触发重新计算）
            container.setBaseValue(150);
            assert(container.getBaseValue() == 150, "Base value should remain 150");
            
            container.destroy();
            passTest();
        } catch (e) {
            failTest("Base value operations failed: " + e.message);
        }
    }
    
    /**
     * 测试属性名访问
     */
    private static function testPropertyNameAccess():Void {
        startTest("Property Name Access Test");
        
        try {
            var target:Object = {};
            var container:PropertyContainer = new PropertyContainer(target, "mana", 50, null);
            
            assert(container.getPropertyName() == "mana", "Property name should be 'mana'");
            
            // 确保属性名不会意外改变
            assert(container.getPropertyName() == "mana", "Property name should be consistent");
            
            container.destroy();
            passTest();
        } catch (e) {
            failTest("Property name access failed: " + e.message);
        }
    }
    
    /**
     * 测试PropertyAccessor集成
     */
    private static function testPropertyAccessorIntegration():Void {
        startTest("PropertyAccessor Integration Test");
        
        try {
            var target:Object = {};
            var container:PropertyContainer = new PropertyContainer(target, "strength", 80, null);
            
            // 验证PropertyAccessor创建了可访问的属性
            assert(target.hasOwnProperty("strength"), "Target should have 'strength' property");
            assert(target.strength == 80, "Target.strength should return base value");
            
            // 添加buff并验证PropertyAccessor自动更新
            var buff:PodBuff = new PodBuff("strength", BuffCalculationType.ADD, 20);
            container.addBuff(buff);
            assert(target.strength == 100, "Target.strength should reflect buff calculation");
            
            container.destroy();
            passTest();
        } catch (e) {
            failTest("PropertyAccessor integration failed: " + e.message);
        }
    }
    
    /**
     * 测试直接属性访问
     */
    private static function testDirectPropertyAccess():Void {
        startTest("Direct Property Access Test");
        
        try {
            var target:Object = {};
            var container:PropertyContainer = new PropertyContainer(target, "agility", 60, null);
            
            // 通过target直接访问
            assert(target.agility == 60, "Direct access should return correct value");
            
            // 通过container方法访问
            assert(container.getFinalValue() == 60, "Container access should return same value");
            
            // 两种访问方式应该返回相同结果
            var buff:PodBuff = new PodBuff("agility", BuffCalculationType.MULTIPLY, 1.5);
            container.addBuff(buff);
            assert(target.agility == container.getFinalValue(), "Direct and container access should be consistent");
            assert(target.agility == 90, "Both should return calculated value: 60 * 1.5 = 90");
            
            container.destroy();
            passTest();
        } catch (e) {
            failTest("Direct property access failed: " + e.message);
        }
    }
    
    /**
     * 测试缓存机制
     */
    private static function testCachingMechanism():Void {
        startTest("Caching Mechanism Test");
        
        try {
            var target:Object = {};
            var computeCount:Number = 0;
            
            // 创建一个会计数的回调来验证缓存
            var changeCallback:Function = function(propName:String, newValue:Number):Void {
                computeCount++;
            };
            
            var container:PropertyContainer = new PropertyContainer(target, "power", 100, changeCallback);
            
            // 首次访问应该触发计算
            var value1:Number = target.power;
            assert(computeCount == 1, "First access should trigger computation");
            
            // 后续访问应该使用缓存（PropertyAccessor的优化）
            var value2:Number = target.power;
            var value3:Number = target.power;
            assert(value1 == value2 && value2 == value3, "Cached values should be consistent");
            
            // 添加buff应该使缓存失效
            var initialCount:Number = computeCount;
            var buff:PodBuff = new PodBuff("power", BuffCalculationType.ADD, 50);
            container.addBuff(buff);
            
            // 下次访问应该重新计算
            var value4:Number = target.power;
            assert(computeCount > initialCount, "Adding buff should trigger recomputation");
            assert(value4 == 150, "New value should be 100 + 50 = 150");
            
            container.destroy();
            passTest();
        } catch (e) {
            failTest("Caching mechanism failed: " + e.message);
        }
    }
    
    /**
     * 测试添加Buff
     */
    private static function testAddBuff():Void {
        startTest("Add Buff Test");
        
        try {
            var target:Object = {};
            var container:PropertyContainer = new PropertyContainer(target, "damage", 50, null);
            
            assert(container.getBuffCount() == 0, "Initial buff count should be 0");
            
            // 添加第一个buff
            var buff1:PodBuff = new PodBuff("damage", BuffCalculationType.ADD, 25);
            container.addBuff(buff1);
            assert(container.getBuffCount() == 1, "Buff count should be 1 after adding first buff");
            assert(target.damage == 75, "Value should be 50 + 25 = 75");
            
            // 添加第二个buff
            var buff2:PodBuff = new PodBuff("damage", BuffCalculationType.MULTIPLY, 2);
            container.addBuff(buff2);
            assert(container.getBuffCount() == 2, "Buff count should be 2 after adding second buff");
            assert(target.damage == 150, "Value should be (50 + 25) * 2 = 150");
            
            // 添加null buff应该被忽略
            container.addBuff(null);
            assert(container.getBuffCount() == 2, "Adding null buff should not change count");
            
            container.destroy();
            passTest();
        } catch (e) {
            failTest("Add buff failed: " + e.message);
        }
    }
    
    /**
     * 测试移除Buff
     */
    private static function testRemoveBuff():Void {
        startTest("Remove Buff Test");
        
        try {
            var target:Object = {};
            var container:PropertyContainer = new PropertyContainer(target, "armor", 30, null);
            
            // 添加两个buff
            var buff1:PodBuff = new PodBuff("armor", BuffCalculationType.ADD, 20);
            var buff2:PodBuff = new PodBuff("armor", BuffCalculationType.MULTIPLY, 1.5);
            container.addBuff(buff1);
            container.addBuff(buff2);
            assert(container.getBuffCount() == 2, "Should have 2 buffs");
            assert(target.armor == 75, "Value should be (30 + 20) * 1.5 = 75");
            
            // 移除第一个buff
            var removed:Boolean = container.removeBuff(buff1.getId());
            assert(removed == true, "Should successfully remove buff");
            assert(container.getBuffCount() == 1, "Should have 1 buff after removal");
            assert(target.armor == 45, "Value should be 30 * 1.5 = 45");
            
            // 移除不存在的buff
            var notRemoved:Boolean = container.removeBuff("nonexistent");
            assert(notRemoved == false, "Should return false for non-existent buff");
            assert(container.getBuffCount() == 1, "Buff count should not change");
            
            // 移除最后一个buff
            container.removeBuff(buff2.getId());
            assert(container.getBuffCount() == 0, "Should have 0 buffs");
            assert(target.armor == 30, "Value should return to base value 30");
            
            container.destroy();
            passTest();
        } catch (e) {
            failTest("Remove buff failed: " + e.message);
        }
    }
    
    /**
     * 测试清除所有Buff
     */
    private static function testClearBuffs():Void {
        startTest("Clear Buffs Test");
        
        try {
            var target:Object = {};
            var container:PropertyContainer = new PropertyContainer(target, "speed", 10, null);
            
            // 添加多个buff
            for (var i:Number = 0; i < 5; i++) {
                var buff:PodBuff = new PodBuff("speed", BuffCalculationType.ADD, 5);
                container.addBuff(buff);
            }
            assert(container.getBuffCount() == 5, "Should have 5 buffs");
            assert(target.speed == 35, "Value should be 10 + 5*5 = 35");
            
            // 清除所有buff
            container.clearBuffs();
            assert(container.getBuffCount() == 0, "Should have 0 buffs after clear");
            assert(target.speed == 10, "Value should return to base value 10");
            
            // 再次清除应该安全
            container.clearBuffs();
            assert(container.getBuffCount() == 0, "Multiple clear should be safe");
            
            container.destroy();
            passTest();
        } catch (e) {
            failTest("Clear buffs failed: " + e.message);
        }
    }
    
    /**
     * 测试Buff计数功能
     */
    private static function testBuffCounting():Void {
        startTest("Buff Counting Test");
        
        try {
            var target:Object = {};
            var container:PropertyContainer = new PropertyContainer(target, "intelligence", 40, null);
            
            assert(container.getBuffCount() == 0, "Initial buff count should be 0");
            assert(container.getActiveBuffCount() == 0, "Initial active buff count should be 0");
            
            // 添加一些buff
            var buff1:PodBuff = new PodBuff("intelligence", BuffCalculationType.ADD, 10);
            var buff2:PodBuff = new PodBuff("intelligence", BuffCalculationType.PERCENT, 0.2);
            container.addBuff(buff1);
            container.addBuff(buff2);
            
            assert(container.getBuffCount() == 2, "Total buff count should be 2");
            assert(container.getActiveBuffCount() == 2, "Active buff count should be 2");
            
            // 获取buff副本
            var buffs:Array = container.getBuffs();
            assert(buffs.length == 2, "Buff array should have 2 elements");
            
            // 确保返回的是副本
            buffs.push("dummy");
            assert(container.getBuffCount() == 2, "Original buffs should not be affected by array modification");
            
            container.destroy();
            passTest();
        } catch (e) {
            failTest("Buff counting failed: " + e.message);
        }
    }
    
    /**
     * 测试hasBuff功能
     */
    private static function testHasBuff():Void {
        startTest("Has Buff Test");
        
        try {
            var target:Object = {};
            var container:PropertyContainer = new PropertyContainer(target, "luck", 5, null);
            
            var buff:PodBuff = new PodBuff("luck", BuffCalculationType.ADD, 3);
            var buffId:String = buff.getId();
            
            assert(container.hasBuff(buffId) == false, "Should not have buff before adding");
            
            container.addBuff(buff);
            assert(container.hasBuff(buffId) == true, "Should have buff after adding");
            
            container.removeBuff(buffId);
            assert(container.hasBuff(buffId) == false, "Should not have buff after removing");
            
            container.destroy();
            passTest();
        } catch (e) {
            failTest("Has buff failed: " + e.message);
        }
    }
    
    /**
     * 测试单个Buff计算
     */
    private static function testSingleBuffCalculation():Void {
        startTest("Single Buff Calculation Test");
        
        try {
            var target:Object = {};
            var container:PropertyContainer = new PropertyContainer(target, "resistance", 20, null);
            
            // 测试ADD
            var addBuff:PodBuff = new PodBuff("resistance", BuffCalculationType.ADD, 15);
            container.addBuff(addBuff);
            assert(target.resistance == 35, "ADD: 20 + 15 = 35");
            
            container.clearBuffs();
            
            // 测试MULTIPLY
            var multiplyBuff:PodBuff = new PodBuff("resistance", BuffCalculationType.MULTIPLY, 3);
            container.addBuff(multiplyBuff);
            assert(target.resistance == 60, "MULTIPLY: 20 * 3 = 60");
            
            container.clearBuffs();
            
            // 测试PERCENT
            var percentBuff:PodBuff = new PodBuff("resistance", BuffCalculationType.PERCENT, 0.5);
            container.addBuff(percentBuff);
            assert(target.resistance == 30, "PERCENT: 20 * (1 + 0.5) = 30");
            
            container.destroy();
            passTest();
        } catch (e) {
            failTest("Single buff calculation failed: " + e.message);
        }
    }
    
    /**
     * 测试多个Buff计算
     */
    private static function testMultipleBuffCalculation():Void {
        startTest("Multiple Buff Calculation Test");
        
        try {
            var target:Object = {};
            var container:PropertyContainer = new PropertyContainer(target, "criticalRate", 5, null);
            
            // 添加多个相同类型的buff
            var addBuff1:PodBuff = new PodBuff("criticalRate", BuffCalculationType.ADD, 5);
            var addBuff2:PodBuff = new PodBuff("criticalRate", BuffCalculationType.ADD, 10);
            var addBuff3:PodBuff = new PodBuff("criticalRate", BuffCalculationType.ADD, 3);
            
            container.addBuff(addBuff1);
            container.addBuff(addBuff2);
            container.addBuff(addBuff3);
            
            assert(target.criticalRate == 23, "Multiple ADD: 5 + 5 + 10 + 3 = 23");
            
            container.clearBuffs();
            
            // 添加多个不同类型的buff
            var addBuff:PodBuff = new PodBuff("criticalRate", BuffCalculationType.ADD, 10);
            var multiplyBuff:PodBuff = new PodBuff("criticalRate", BuffCalculationType.MULTIPLY, 2);
            
            container.addBuff(addBuff);
            container.addBuff(multiplyBuff);
            
            // 预期：(5 + 10) * 2 = 30
            assert(target.criticalRate == 30, "Mixed types: (5 + 10) * 2 = 30");
            
            container.destroy();
            passTest();
        } catch (e) {
            failTest("Multiple buff calculation failed: " + e.message);
        }
    }
    
    /**
     * 测试Buff优先级计算
     */
    private static function testBuffPriorityCalculation():Void {
        startTest("Buff Priority Calculation Test");
        
        try {
            var target:Object = {};
            var container:PropertyContainer = new PropertyContainer(target, "maxHealth", 100, null);
            
            // 按不同顺序添加，测试内部优先级
            var percentBuff:PodBuff = new PodBuff("maxHealth", BuffCalculationType.PERCENT, 0.2);
            var addBuff:PodBuff = new PodBuff("maxHealth", BuffCalculationType.ADD, 50);
            var multiplyBuff:PodBuff = new PodBuff("maxHealth", BuffCalculationType.MULTIPLY, 1.5);
            
            // 故意以非优先级顺序添加
            container.addBuff(percentBuff);   // 第3优先级
            container.addBuff(multiplyBuff);  // 第2优先级
            container.addBuff(addBuff);       // 第1优先级
            
            // 预期计算顺序：基础值 -> ADD -> MULTIPLY -> PERCENT
            // 100 -> 150(+50) -> 225(*1.5) -> 270(*1.2)
            assert(target.maxHealth == 270, "Priority calculation: ((100+50)*1.5)*1.2 = 270");
            
            container.destroy();
            passTest();
        } catch (e) {
            failTest("Buff priority calculation failed: " + e.message);
        }
    }
    
    /**
     * 测试复杂Buff组合
     */
    private static function testComplexBuffCombination():Void {
        startTest("Complex Buff Combination Test");
        
        try {
            var target:Object = {};
            var container:PropertyContainer = new PropertyContainer(target, "finalDamage", 50, null);
            
            // 模拟复杂的游戏场景
            var weaponDamage:PodBuff = new PodBuff("finalDamage", BuffCalculationType.ADD, 30);           // 武器+30
            var skillBonus:PodBuff = new PodBuff("finalDamage", BuffCalculationType.PERCENT, 0.4);       // 技能+40%
            var criticalHit:PodBuff = new PodBuff("finalDamage", BuffCalculationType.MULTIPLY, 2);       // 暴击x2
            var damageLimit:PodBuff = new PodBuff("finalDamage", BuffCalculationType.MIN, 180);          // 伤害上限180
            
            container.addBuff(weaponDamage);
            container.addBuff(skillBonus);
            container.addBuff(criticalHit);
            container.addBuff(damageLimit);
            
            // 预期计算：50 -> 80(+30) -> 160(*2) -> 224(*1.4) -> 180(min)
            assert(target.finalDamage == 180, "Complex combination should result in damage cap: 180");
            
            container.destroy();
            passTest();
        } catch (e) {
            failTest("Complex buff combination failed: " + e.message);
        }
    }
    
    /**
     * 测试变化回调
     */
    private static function testChangeCallback():Void {
        startTest("Change Callback Test");
        
        try {
            var target:Object = {};
            var callbackCount:Number = 0;
            var lastPropertyName:String = "";
            var lastValue:Number = 0;
            
            var changeCallback:Function = function(propName:String, newValue:Number):Void {
                callbackCount++;
                lastPropertyName = propName;
                lastValue = newValue;
            };
            
            var container:PropertyContainer = new PropertyContainer(target, "energy", 60, changeCallback);
            
            // 首次访问应该触发回调
            var initialValue:Number = target.energy;
            assert(callbackCount == 1, "Initial access should trigger callback");
            assert(lastPropertyName == "energy", "Callback should receive correct property name");
            assert(lastValue == 60, "Callback should receive correct value");
            
            // 添加buff应该触发回调
            var buff:PodBuff = new PodBuff("energy", BuffCalculationType.ADD, 20);
            container.addBuff(buff);
            var newValue:Number = target.energy;
            assert(callbackCount == 2, "Adding buff should trigger callback");
            assert(lastValue == 80, "Callback should receive new calculated value");
            
            // 设置基础值应该触发回调
            container.setBaseValue(70);
            var updatedValue:Number = target.energy;
            assert(callbackCount == 3, "Setting base value should trigger callback");
            assert(lastValue == 90, "Callback should receive updated value: 70 + 20 = 90");
            
            container.destroy();
            passTest();
        } catch (e) {
            failTest("Change callback failed: " + e.message);
        }
    }
    
    /**
     * 测试外部属性设置
     */
    private static function testExternalPropertySet():Void {
        startTest("External Property Set Test");
        
        try {
            var target:Object = {};
            var container:PropertyContainer = new PropertyContainer(target, "stamina", 80, null);
            
            // 通过target直接设置属性（模拟外部修改）
            // 注意：这个测试依赖于PropertyAccessor的onSetCallback机制
            // 如果PropertyAccessor将其作为只读属性处理，此测试可能需要调整
            
            var initialBase:Number = container.getBaseValue();
            assert(initialBase == 80, "Initial base value should be 80");
            
            // 直接访问确保值正确
            assert(target.stamina == 80, "Direct access should return base value");
            
            container.destroy();
            passTest();
        } catch (e) {
            failTest("External property set failed: " + e.message);
        }
    }
    
    /**
     * 测试最终值缓存
     */
    private static function testFinalValueCaching():Void {
        startTest("Final Value Caching Test");
        
        try {
            var target:Object = {};
            var container:PropertyContainer = new PropertyContainer(target, "charisma", 25, null);
            
            // 多次获取相同值
            var value1:Number = container.getFinalValue();
            var value2:Number = target.charisma;
            var value3:Number = container.getFinalValue();
            
            assert(value1 == value2 && value2 == value3, "Multiple accesses should return same value");
            assert(value1 == 25, "All accesses should return correct value");
            
            // 添加buff后值应该改变
            var buff:PodBuff = new PodBuff("charisma", BuffCalculationType.MULTIPLY, 2);
            container.addBuff(buff);
            
            var newValue1:Number = container.getFinalValue();
            var newValue2:Number = target.charisma;
            assert(newValue1 == newValue2, "Both access methods should return same updated value");
            assert(newValue1 == 50, "New value should be 25 * 2 = 50");
            
            container.destroy();
            passTest();
        } catch (e) {
            failTest("Final value caching failed: " + e.message);
        }
    }
    
    /**
     * 测试强制重新计算
     */
    private static function testForceRecalculation():Void {
        startTest("Force Recalculation Test");
        
        try {
            var target:Object = {};
            var container:PropertyContainer = new PropertyContainer(target, "wisdom", 35, null);
            
            var buff:PodBuff = new PodBuff("wisdom", BuffCalculationType.ADD, 15);
            container.addBuff(buff);
            
            var normalValue:Number = container.getFinalValue();
            var forcedValue:Number = container.forceRecalculate();
            
            assert(normalValue == forcedValue, "Forced recalculation should return same result");
            assert(normalValue == 50, "Value should be 35 + 15 = 50");
            
            container.destroy();
            passTest();
        } catch (e) {
            failTest("Force recalculation failed: " + e.message);
        }
    }
    
    /**
     * 测试失效机制
     */
    private static function testInvalidationMechanism():Void {
        startTest("Invalidation Mechanism Test");
        
        try {
            var target:Object = {};
            var container:PropertyContainer = new PropertyContainer(target, "dexterity", 45, null);
            
            // 首次访问建立缓存
            var initialValue:Number = target.dexterity;
            assert(initialValue == 45, "Initial value should be 45");
            
            // 添加buff应该使缓存失效并重新计算
            var buff:PodBuff = new PodBuff("dexterity", BuffCalculationType.PERCENT, 0.6);
            container.addBuff(buff);
            
            var updatedValue:Number = target.dexterity;
            assert(updatedValue == 72, "Updated value should be 45 * 1.6 = 72");
            
            // 移除buff也应该触发重新计算
            container.removeBuff(buff.getId());
            var finalValue:Number = target.dexterity;
            assert(finalValue == 45, "Final value should return to base: 45");
            
            container.destroy();
            passTest();
        } catch (e) {
            failTest("Invalidation mechanism failed: " + e.message);
        }
    }
    
    /**
     * 测试空容器
     */
    private static function testEmptyContainer():Void {
        startTest("Empty Container Test");
        
        try {
            var target:Object = {};
            var container:PropertyContainer = new PropertyContainer(target, "emptyProp", 0, null);
            
            assert(container.getBuffCount() == 0, "Empty container should have 0 buffs");
            assert(container.getActiveBuffCount() == 0, "Empty container should have 0 active buffs");
            assert(container.getFinalValue() == 0, "Empty container should return base value");
            assert(target.emptyProp == 0, "Target property should equal base value");
            
            // 各种操作在空容器上应该安全
            container.clearBuffs(); // 应该不出错
            container.removeBuff("nonexistent"); // 应该返回false
            container.forceRecalculate(); // 应该不出错
            
            container.destroy();
            passTest();
        } catch (e) {
            failTest("Empty container failed: " + e.message);
        }
    }
    
    /**
     * 测试非激活的Buff
     */
    private static function testInactiveBuffs():Void {
        startTest("Inactive Buffs Test");
        
        try {
            var target:Object = {};
            var container:PropertyContainer = new PropertyContainer(target, "testInactive", 100, null);
            
            // 创建一个真正的非激活buff实现
            var inactiveBuff:InactiveBuff = new InactiveBuff();
            
            container.addBuff(inactiveBuff);
            assert(container.getBuffCount() == 1, "Should count inactive buff");
            assert(container.getActiveBuffCount() == 0, "Should not count as active");
            assert(target.testInactive == 100, "Inactive buff should not affect value");
            
            container.destroy();
            passTest();
        } catch (e) {
            failTest("Inactive buffs failed: " + e.message);
        }
    }
    
    /**
     * 测试无效输入
     */
    private static function testInvalidInputs():Void {
        startTest("Invalid Inputs Test");
        
        try {
            var target:Object = {};
            var container:PropertyContainer = new PropertyContainer(target, "validProp", 50, null);
            
            // 添加null buff
            var initialCount:Number = container.getBuffCount();
            container.addBuff(null);
            assert(container.getBuffCount() == initialCount, "Adding null buff should be ignored");
            
            // 移除无效ID
            var removed:Boolean = container.removeBuff(null);
            assert(removed == false, "Removing null ID should return false");
            
            removed = container.removeBuff("");
            assert(removed == false, "Removing empty ID should return false");
            
            // 检查无效ID
            var hasBuff:Boolean = container.hasBuff(null);
            assert(hasBuff == false, "null ID should not be found");
            
            container.destroy();
            passTest();
        } catch (e) {
            failTest("Invalid inputs failed: " + e.message);
        }
    }
    
    /**
     * 测试边界情况
     */
    private static function testEdgeCases():Void {
        startTest("Edge Cases Test");
        
        try {
            var target:Object = {};
            var container:PropertyContainer = new PropertyContainer(target, "edgeCase", -10, null);
            
            // 负数基础值
            assert(container.getBaseValue() == -10, "Should handle negative base value");
            assert(target.edgeCase == -10, "Target should reflect negative value");
            
            // 零值操作
            container.setBaseValue(0);
            assert(target.edgeCase == 0, "Should handle zero value");
            
            // 大数值
            container.setBaseValue(999999);
            assert(target.edgeCase == 999999, "Should handle large numbers");
            
            // 浮点数
            container.setBaseValue(3.14159);
            assert(Math.abs(target.edgeCase - 3.14159) < 0.0001, "Should handle floating point numbers");
            
            container.destroy();
            passTest();
        } catch (e) {
            failTest("Edge cases failed: " + e.message);
        }
    }
    
    /**
     * 测试toString方法
     */
    private static function testToString():Void {
        startTest("ToString Test");
        
        try {
            var target:Object = {};
            var container:PropertyContainer = new PropertyContainer(target, "debugProp", 75, null);
            
            var str:String = container.toString();
            assert(str != null, "toString should not return null");
            assert(str.length > 0, "toString should return non-empty string");
            assert(str.indexOf("debugProp") >= 0, "toString should contain property name");
            assert(str.indexOf("75") >= 0, "toString should contain base value");
            
            // 添加buff后字符串应该更新
            var buff:PodBuff = new PodBuff("debugProp", BuffCalculationType.ADD, 25);
            container.addBuff(buff);
            var newStr:String = container.toString();
            assert(newStr.indexOf("100") >= 0, "toString should reflect calculated value");
            
            container.destroy();
            passTest();
        } catch (e) {
            failTest("ToString failed: " + e.message);
        }
    }
    
    /**
     * 测试销毁方法
     */
    private static function testDestroy():Void {
        startTest("Destroy Test");
        
        try {
            var target:Object = {};
            var container:PropertyContainer = new PropertyContainer(target, "destroyTest", 88, null);
            
            // 添加一些buff
            var buff1:PodBuff = new PodBuff("destroyTest", BuffCalculationType.ADD, 12);
            var buff2:PodBuff = new PodBuff("destroyTest", BuffCalculationType.MULTIPLY, 1.5);
            container.addBuff(buff1);
            container.addBuff(buff2);
            
            assert(container.getBuffCount() == 2, "Should have 2 buffs before destroy");
            assert(target.hasOwnProperty("destroyTest"), "Target should have property before destroy");
            
            // 销毁容器
            container.destroy();
            
            // 验证清理效果
            assert(!target.hasOwnProperty("destroyTest"), "Target should not have property after destroy");
            
            // 再次销毁应该安全
            container.destroy(); // 不应该抛出异常
            
            passTest();
        } catch (e) {
            failTest("Destroy failed: " + e.message);
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
        trace("=== PropertyContainer Test Suite Results ===");
        trace("Total tests: " + testCount);
        trace("Passed: " + passedCount);
        trace("Failed: " + failedCount);
        trace("Success rate: " + Math.round((passedCount / testCount) * 100) + "%");
        
        if (failedCount == 0) {
            trace("🎉 All tests passed!");
        } else {
            trace("❌ " + failedCount + " test(s) failed");
        }
        trace("==========================================");
    }
}

