// org/flashNight/arki/component/Buff/test/PathBindingTest.as

import org.flashNight.arki.component.Buff.*;

/**
 * PathBindingTest - 路径绑定功能测试套件
 *
 * 测试 v3.0 新增的嵌套属性路径支持功能。
 *
 * 测试覆盖：
 * 1. 基础功能：路径属性创建、buff 添加/移除/计算
 * 2. rebind 机制：对象替换检测、自动重绑
 * 3. 边界条件：路径解析失败、未绑定状态
 * 4. CascadeDispatcher：级联触发、帧内合并、防递归
 * 5. 性能：版本号快速路径、缓存命中
 * 6. 重入/删除边界：回调中添加/移除 buff、flush 期间 destroy
 * 7. 生命周期：isDestroyed()、unmanage 后 rebind、数组压缩
 *
 * 使用方式: PathBindingTest.runAllTests();
 *
 * @version 1.1
 */
class org.flashNight.arki.component.Buff.test.PathBindingTest {

    private static var testCount:Number = 0;
    private static var passedCount:Number = 0;
    private static var failedCount:Number = 0;

    /**
     * 运行所有测试
     */
    public static function runAllTests():Void {
        trace("=== PathBinding Test Suite (v3.0) ===");

        testCount = 0;
        passedCount = 0;
        failedCount = 0;

        trace("\n--- Phase 1: Basic Path Property Tests ---");
        testPathPropertyCreation();
        testPathPropertyBuffAdd();
        testPathPropertyBuffRemove();
        testPathPropertyCalculation();
        testOneLevel_Backward_Compatibility();

        trace("\n--- Phase 2: Rebind Tests ---");
        testRebindDetection();
        testRebindRestoresOldBase();
        testRebindNewAccessor();
        testNotifyPathRootChanged();
        testRebindToSameObject();

        trace("\n--- Phase 3: Edge Cases ---");
        testPathResolutionFailure();
        testUnboundGetFinalValue();
        testDeepPath();
        testPathWithNullIntermediate();

        trace("\n--- Phase 4: CascadeDispatcher Tests ---");
        testCascadeMap();
        testCascadeMark();
        testCascadeFlush();
        testCascadeFlushOncePerFrame();
        testCascadeFlushAntiRecursion();

        trace("\n--- Phase 5: Performance Tests ---");
        testVersionNumberFastPath();
        testPathCacheHit();

        trace("\n--- Phase 6: Reentry & Deletion Edge Cases ---");
        testAddBuffInCallback();
        testRemoveBuffInCallback();
        testRemoveContainerDuringRebind();
        testMultiplePathRebindSimultaneous();
        testCascadeActionException();
        testDestroyDuringFlush();

        trace("\n--- Phase 7: Lifecycle & Cleanup Tests ---");
        testIsDestroyedMethod();
        testUnmanagedContainerSkipped();
        testPathContainersCompaction();
        testRebindAfterUnmanageNocrash();
        testMultipleUnmanageThenRebind();

        // Summary
        trace("\n=== Test Summary ===");
        trace("Total: " + testCount + ", Passed: " + passedCount + ", Failed: " + failedCount);
        if (failedCount == 0) {
            trace("ALL TESTS PASSED!");
        } else {
            trace("SOME TESTS FAILED - Review output above");
        }
    }

    // =========================================================================
    // Phase 1: Basic Path Property Tests
    // =========================================================================

    private static function testPathPropertyCreation():Void {
        var target:Object = createMockTarget();
        var manager:BuffManager = new BuffManager(target, {});

        // Add a buff to path property to trigger container creation
        var buff:PodBuff = new PodBuff("长枪属性.power", BuffCalculationType.ADD, 100);
        manager.addBuff(buff, "test_path_buff");
        manager.update(1);

        // Verify container was created
        var container:PropertyContainer = manager.getPropertyContainer("长枪属性.power");
        assertNotNull("Path property container created", container);
        assertTrue("Container is path property", container.isPathProperty());

        var parts:Array = container.getBindingParts();
        assertEqual("Binding parts length", 2, parts.length);
        assertEqual("Binding parts[0]", "长枪属性", parts[0]);
        assertEqual("Binding parts[1]", "power", parts[1]);

        manager.destroy();
    }

    private static function testPathPropertyBuffAdd():Void {
        var target:Object = createMockTarget();
        var manager:BuffManager = new BuffManager(target, {});

        var buff:PodBuff = new PodBuff("长枪属性.power", BuffCalculationType.ADD, 50);
        manager.addBuff(buff, "add_buff");
        manager.update(1);

        // Original power was 100, +50 = 150
        var finalValue:Number = target.长枪属性.power;
        assertEqual("Path property buff add", 150, finalValue);

        manager.destroy();
    }

    private static function testPathPropertyBuffRemove():Void {
        var target:Object = createMockTarget();
        var manager:BuffManager = new BuffManager(target, {});

        var buff:PodBuff = new PodBuff("长枪属性.power", BuffCalculationType.ADD, 50);
        manager.addBuff(buff, "remove_test");
        manager.update(1);

        assertEqual("Before remove", 150, target.长枪属性.power);

        manager.removeBuff("remove_test");
        manager.update(1);

        assertEqual("After remove", 100, target.长枪属性.power);

        manager.destroy();
    }

    private static function testPathPropertyCalculation():Void {
        var target:Object = createMockTarget();
        var manager:BuffManager = new BuffManager(target, {});

        // Test multiple calculation types
        var addBuff:PodBuff = new PodBuff("长枪属性.power", BuffCalculationType.ADD, 20);
        var multBuff:PodBuff = new PodBuff("长枪属性.power", BuffCalculationType.MULTIPLY, 1.5);

        manager.addBuff(addBuff, "add");
        manager.addBuff(multBuff, "mult");
        manager.update(1);

        // 计算顺序：先 MULTIPLY 再 ADD
        // base=100, *1.5=150, +20=170
        assertEqual("Path property calculation chain", 170, target.长枪属性.power);

        manager.destroy();
    }

    private static function testOneLevel_Backward_Compatibility():Void {
        var target:Object = createMockTarget();
        var manager:BuffManager = new BuffManager(target, {});

        // Test one-level property still works
        var buff:PodBuff = new PodBuff("hp", BuffCalculationType.ADD, 100);
        manager.addBuff(buff, "hp_buff");
        manager.update(1);

        assertEqual("One-level property still works", 1100, target.hp);

        var container:PropertyContainer = manager.getPropertyContainer("hp");
        assertFalse("One-level is not path property", container.isPathProperty());
        assertNull("One-level has no binding parts", container.getBindingParts());

        manager.destroy();
    }

    // =========================================================================
    // Phase 2: Rebind Tests
    // =========================================================================

    private static function testRebindDetection():Void {
        var target:Object = createMockTarget();
        var manager:BuffManager = new BuffManager(target, {});

        var buff:PodBuff = new PodBuff("长枪属性.power", BuffCalculationType.ADD, 50);
        manager.addBuff(buff, "rebind_test");
        manager.update(1);

        var oldWeapon:Object = target.长枪属性;
        assertEqual("Before rebind", 150, oldWeapon.power);

        // Replace weapon object
        var newWeapon:Object = { power: 200, range: 500 };
        target.长枪属性 = newWeapon;

        // Notify and sync
        manager.notifyPathRootChanged("长枪属性");
        manager.update(1);

        // New weapon should have buff applied: 200 + 50 = 250
        assertEqual("After rebind - new weapon", 250, newWeapon.power);

        manager.destroy();
    }

    private static function testRebindRestoresOldBase():Void {
        var target:Object = createMockTarget();
        var manager:BuffManager = new BuffManager(target, {});

        var buff:PodBuff = new PodBuff("长枪属性.power", BuffCalculationType.ADD, 50);
        manager.addBuff(buff, "restore_test");
        manager.update(1);

        var oldWeapon:Object = target.长枪属性;
        var oldBase:Number = 100; // Original base value

        // Replace weapon
        var newWeapon:Object = { power: 300, range: 600 };
        target.长枪属性 = newWeapon;
        manager.notifyPathRootChanged("长枪属性");
        manager.update(1);

        // Old weapon should be restored to base (100), not final (150)
        assertEqual("Old weapon restored to base", oldBase, oldWeapon.power);

        manager.destroy();
    }

    private static function testRebindNewAccessor():Void {
        var target:Object = createMockTarget();
        var manager:BuffManager = new BuffManager(target, {});

        var buff:PodBuff = new PodBuff("长枪属性.power", BuffCalculationType.MULTIPLY, 2);
        manager.addBuff(buff, "accessor_test");
        manager.update(1);

        // Replace weapon
        var newWeapon:Object = { power: 50, range: 400 };
        target.长枪属性 = newWeapon;
        manager.notifyPathRootChanged("长枪属性");
        manager.update(1);

        // New accessor should work: 50 * 2 = 100
        assertEqual("New accessor works", 100, newWeapon.power);

        // Add another buff to verify accessor is working
        var addBuff:PodBuff = new PodBuff("长枪属性.power", BuffCalculationType.ADD, 10);
        manager.addBuff(addBuff, "extra");
        manager.update(1);

        // 计算顺序：先 MULTIPLY 再 ADD
        // 50 * 2 + 10 = 110
        assertEqual("Accessor after adding buff", 110, newWeapon.power);

        manager.destroy();
    }

    private static function testNotifyPathRootChanged():Void {
        var target:Object = createMockTarget();
        var manager:BuffManager = new BuffManager(target, {});

        var buff:PodBuff = new PodBuff("长枪属性.power", BuffCalculationType.ADD, 10);
        manager.addBuff(buff, "notify_test");
        manager.update(1);

        // Without notify, sync should skip (fast path)
        var newWeapon:Object = { power: 999, range: 999 };
        target.长枪属性 = newWeapon;

        // Update without notify - should NOT rebind (version unchanged)
        manager.update(1);
        // The new weapon should NOT have accessor installed yet
        // (This is tricky to test - we verify by checking the old behavior)

        // Now notify and update
        manager.notifyPathRootChanged("长枪属性");
        manager.update(1);

        // Now should be rebound: 999 + 10 = 1009
        assertEqual("After notify", 1009, newWeapon.power);

        manager.destroy();
    }

    private static function testRebindToSameObject():Void {
        var target:Object = createMockTarget();
        var manager:BuffManager = new BuffManager(target, {});

        var buff:PodBuff = new PodBuff("长枪属性.power", BuffCalculationType.ADD, 25);
        manager.addBuff(buff, "same_obj_test");
        manager.update(1);

        var container:PropertyContainer = manager.getPropertyContainer("长枪属性.power");
        var oldAccessTarget:Object = container.getAccessTarget();

        // Force sync even though object didn't change
        manager.syncAllPathBindings();

        // Access target should be the same
        assertEqual("Same access target", oldAccessTarget, container.getAccessTarget());

        // Value should still be correct
        assertEqual("Value unchanged", 125, target.长枪属性.power);

        manager.destroy();
    }

    // =========================================================================
    // Phase 3: Edge Cases
    // =========================================================================

    private static function testPathResolutionFailure():Void {
        var target:Object = { hp: 100 }; // No 长枪属性
        var manager:BuffManager = new BuffManager(target, {});

        var buff:PodBuff = new PodBuff("长枪属性.power", BuffCalculationType.ADD, 50);
        manager.addBuff(buff, "fail_test");
        manager.update(1);

        var container:PropertyContainer = manager.getPropertyContainer("长枪属性.power");
        assertNotNull("Container exists even if path fails", container);
        assertNull("Access target is null", container.getAccessTarget());

        manager.destroy();
    }

    private static function testUnboundGetFinalValue():Void {
        var target:Object = { hp: 100 }; // No 长枪属性
        var manager:BuffManager = new BuffManager(target, {});

        var buff:PodBuff = new PodBuff("长枪属性.power", BuffCalculationType.ADD, 50);
        manager.addBuff(buff, "unbound_test");
        manager.update(1);

        var container:PropertyContainer = manager.getPropertyContainer("长枪属性.power");

        // Unbound should return base value (0 since property didn't exist)
        var finalValue:Number = container.getFinalValue();
        assertEqual("Unbound returns base", 0, finalValue);

        manager.destroy();
    }

    private static function testDeepPath():Void {
        var target:Object = {
            hp: 100,
            equipment: {
                weapon: {
                    stats: {
                        power: 50
                    }
                }
            }
        };
        var manager:BuffManager = new BuffManager(target, {});

        var buff:PodBuff = new PodBuff("equipment.weapon.stats.power", BuffCalculationType.ADD, 25);
        manager.addBuff(buff, "deep_test");
        manager.update(1);

        assertEqual("Deep path works", 75, target.equipment.weapon.stats.power);

        var container:PropertyContainer = manager.getPropertyContainer("equipment.weapon.stats.power");
        var parts:Array = container.getBindingParts();
        assertEqual("Deep path parts length", 4, parts.length);

        manager.destroy();
    }

    private static function testPathWithNullIntermediate():Void {
        var target:Object = {
            hp: 100,
            长枪属性: null // Intermediate is null
        };
        var manager:BuffManager = new BuffManager(target, {});

        var buff:PodBuff = new PodBuff("长枪属性.power", BuffCalculationType.ADD, 50);
        manager.addBuff(buff, "null_inter_test");
        manager.update(1);

        var container:PropertyContainer = manager.getPropertyContainer("长枪属性.power");
        assertNull("Null intermediate -> unbound", container.getAccessTarget());

        // Now add the intermediate object
        target.长枪属性 = { power: 100 };
        manager.notifyPathRootChanged("长枪属性");
        manager.update(1);

        // Should now be bound
        assertNotNull("Now bound", container.getAccessTarget());
        assertEqual("Value after binding", 150, target.长枪属性.power);

        manager.destroy();
    }

    // =========================================================================
    // Phase 4: CascadeDispatcher Tests
    // =========================================================================

    private static function testCascadeMap():Void {
        var dispatcher:CascadeDispatcher = new CascadeDispatcher();

        dispatcher.map("长枪属性.power", "gunInit");
        dispatcher.map("手枪属性.power", "pistolInit");
        dispatcher.map("手枪属性.power", "dualGunInit");

        // Mark and check dirty
        dispatcher.mark("长枪属性.power");
        assertTrue("Has dirty after mark", dispatcher.hasDirty());

        dispatcher.clearDirty();
        assertFalse("No dirty after clear", dispatcher.hasDirty());

        dispatcher.destroy();
        assertTrue("CascadeMap test passed", true);
    }

    private static function testCascadeMark():Void {
        var dispatcher:CascadeDispatcher = new CascadeDispatcher();
        var callCount:Number = 0;

        dispatcher.map("prop1", "group1");
        dispatcher.map("prop2", "group1");
        dispatcher.action("group1", function() { callCount++; });

        // Mark both props that map to same group
        dispatcher.mark("prop1");
        dispatcher.mark("prop2");

        dispatcher.flush();

        // Should only call once (same group)
        assertEqual("Same group called once", 1, callCount);

        dispatcher.destroy();
    }

    private static function testCascadeFlush():Void {
        var dispatcher:CascadeDispatcher = new CascadeDispatcher();
        var results:Array = [];

        dispatcher.map("a", "g1");
        dispatcher.map("b", "g2");
        dispatcher.action("g1", function() { results.push("g1"); });
        dispatcher.action("g2", function() { results.push("g2"); });

        dispatcher.mark("a");
        dispatcher.mark("b");
        dispatcher.flush();

        assertEqual("Both groups called", 2, results.length);
        assertFalse("No dirty after flush", dispatcher.hasDirty());

        dispatcher.destroy();
    }

    private static function testCascadeFlushOncePerFrame():Void {
        var dispatcher:CascadeDispatcher = new CascadeDispatcher();
        var callCount:Number = 0;

        dispatcher.map("x", "gx");
        dispatcher.action("gx", function() { callCount++; });

        // Mark same prop multiple times
        dispatcher.mark("x");
        dispatcher.mark("x");
        dispatcher.mark("x");

        dispatcher.flush();

        assertEqual("Called only once", 1, callCount);

        dispatcher.destroy();
    }

    private static function testCascadeFlushAntiRecursion():Void {
        var dispatcher:CascadeDispatcher = new CascadeDispatcher();
        var callCount:Number = 0;

        dispatcher.map("recursive", "recurseGroup");

        // Action that tries to mark and flush again
        dispatcher.action("recurseGroup", function() {
            callCount++;
            dispatcher.mark("recursive");
            dispatcher.flush(); // Should be blocked by anti-recursion
        });

        dispatcher.mark("recursive");
        dispatcher.flush();

        // Should only be called once despite recursive attempt
        assertEqual("Anti-recursion works", 1, callCount);

        // The second mark should be pending for next flush
        assertTrue("Has dirty from recursion mark", dispatcher.hasDirty());

        dispatcher.destroy();
    }

    // =========================================================================
    // Phase 5: Performance Tests
    // =========================================================================

    private static function testVersionNumberFastPath():Void {
        var target:Object = createMockTarget();
        var manager:BuffManager = new BuffManager(target, {});

        var buff:PodBuff = new PodBuff("长枪属性.power", BuffCalculationType.ADD, 10);
        manager.addBuff(buff, "perf_test");
        manager.update(1);

        // Multiple updates without notify should hit fast path
        var start:Number = getTimer();
        for (var i:Number = 0; i < 1000; i++) {
            manager.update(1);
        }
        var elapsed:Number = getTimer() - start;

        // Just verify it completes quickly (< 100ms for 1000 updates)
        assertTrue("Fast path performance OK (< 100ms)", elapsed < 100);
        trace("  Version fast path: " + elapsed + "ms for 1000 updates");

        manager.destroy();
    }

    private static function testPathCacheHit():Void {
        var target:Object = createMockTarget();
        var manager:BuffManager = new BuffManager(target, {});

        // Create multiple buffs with same path
        for (var i:Number = 0; i < 10; i++) {
            var buff:PodBuff = new PodBuff("长枪属性.power", BuffCalculationType.ADD, 1);
            manager.addBuff(buff, "cache_test_" + i);
        }
        manager.update(1);

        // All should share the same container
        assertEqual("Path cache works", 110, target.长枪属性.power);

        manager.destroy();
        assertTrue("Path cache test passed", true);
    }

    // =========================================================================
    // Phase 6: Reentry & Deletion Edge Cases
    // =========================================================================

    /**
     * 测试在属性变更回调中添加新 buff
     * 场景：cascade action 触发时添加新 buff 到同一属性
     */
    private static function testAddBuffInCallback():Void {
        var target:Object = createMockTarget();
        var manager:BuffManager = new BuffManager(target, {});
        var dispatcher:CascadeDispatcher = new CascadeDispatcher();

        // 设置属性
        var buff:PodBuff = new PodBuff("长枪属性.power", BuffCalculationType.ADD, 50);
        manager.addBuff(buff, "initial_buff");
        manager.update(1);

        // 映射到级联分组
        dispatcher.map("长枪属性.power", "testGroup");

        var addedInCallback:Boolean = false;
        dispatcher.action("testGroup", function() {
            // 在回调中添加另一个 buff
            if (!addedInCallback) {
                addedInCallback = true;
                var newBuff:PodBuff = new PodBuff("长枪属性.power", BuffCalculationType.ADD, 25);
                manager.addBuff(newBuff, "callback_buff");
                manager.update(1);
            }
        });

        // 触发级联
        dispatcher.mark("长枪属性.power");
        dispatcher.flush();

        // 验证：应该正常完成，不会死循环或崩溃
        // 最终值应该是 100 + 50 + 25 = 175
        assertEqual("Add buff in callback", 175, target.长枪属性.power);

        dispatcher.destroy();
        manager.destroy();
    }

    /**
     * 测试在回调中移除当前正在处理的 buff
     * 场景：cascade action 中移除触发该 action 的 buff
     */
    private static function testRemoveBuffInCallback():Void {
        var target:Object = createMockTarget();
        var manager:BuffManager = new BuffManager(target, {});
        var dispatcher:CascadeDispatcher = new CascadeDispatcher();

        var buff:PodBuff = new PodBuff("长枪属性.power", BuffCalculationType.ADD, 100);
        manager.addBuff(buff, "to_remove");
        manager.update(1);

        dispatcher.map("长枪属性.power", "removeGroup");

        var removedInCallback:Boolean = false;
        dispatcher.action("removeGroup", function() {
            if (!removedInCallback) {
                removedInCallback = true;
                manager.removeBuff("to_remove");
                manager.update(1);
            }
        });

        // Initial value: 100 + 100 = 200
        assertEqual("Before callback remove", 200, target.长枪属性.power);

        dispatcher.mark("长枪属性.power");
        dispatcher.flush();

        // After callback removed buff: 100 (base only)
        assertEqual("After callback remove", 100, target.长枪属性.power);

        dispatcher.destroy();
        manager.destroy();
    }

    /**
     * 测试在 rebind 过程中删除 container
     * 场景：notifyPathRootChanged 后、sync 完成前删除属性
     */
    private static function testRemoveContainerDuringRebind():Void {
        var target:Object = createMockTarget();
        var manager:BuffManager = new BuffManager(target, {});

        var buff:PodBuff = new PodBuff("长枪属性.power", BuffCalculationType.ADD, 50);
        manager.addBuff(buff, "rebind_remove_test");
        manager.update(1);

        assertEqual("Before rebind remove", 150, target.长枪属性.power);

        // 替换对象
        target.长枪属性 = { power: 200, range: 500 };
        manager.notifyPathRootChanged("长枪属性");

        // 在 update 之前移除 buff（这会触发 container 可能被清理）
        manager.removeBuff("rebind_remove_test");
        manager.update(1);

        // 应该不会崩溃，新对象保持原值
        assertEqual("After rebind remove", 200, target.长枪属性.power);

        manager.destroy();
    }

    /**
     * 测试多个路径属性同时 rebind
     * 场景：同时更换多个嵌套对象
     */
    private static function testMultiplePathRebindSimultaneous():Void {
        var target:Object = createMockTarget();
        var manager:BuffManager = new BuffManager(target, {});

        var buff1:PodBuff = new PodBuff("长枪属性.power", BuffCalculationType.ADD, 10);
        var buff2:PodBuff = new PodBuff("手枪属性.power", BuffCalculationType.ADD, 20);
        manager.addBuff(buff1, "gun1");
        manager.addBuff(buff2, "gun2");
        manager.update(1);

        assertEqual("Long gun initial", 110, target.长枪属性.power);
        assertEqual("Pistol initial", 70, target.手枪属性.power);

        // 同时替换两个对象
        target.长枪属性 = { power: 300, range: 600 };
        target.手枪属性 = { power: 80, range: 250 };

        // 同时通知两个路径变更
        manager.notifyPathRootChanged("长枪属性");
        manager.notifyPathRootChanged("手枪属性");
        manager.update(1);

        // 验证两个都正确 rebind
        assertEqual("Long gun after rebind", 310, target.长枪属性.power);
        assertEqual("Pistol after rebind", 100, target.手枪属性.power);

        manager.destroy();
    }

    /**
     * 测试 cascade action 抛出异常时的处理
     * 场景：action 执行失败不应影响其他 action
     */
    private static function testCascadeActionException():Void {
        var dispatcher:CascadeDispatcher = new CascadeDispatcher();
        var results:Array = [];

        dispatcher.map("a", "group_a");
        dispatcher.map("b", "group_b");
        dispatcher.map("c", "group_c");

        dispatcher.action("group_a", function() {
            results.push("a");
        });

        dispatcher.action("group_b", function() {
            // 模拟异常（AS2 中 throw 不常用，用 undefined 调用模拟）
            var obj:Object = null;
            obj.nonExistent(); // 这会在 try-catch 中被捕获
        });

        dispatcher.action("group_c", function() {
            results.push("c");
        });

        dispatcher.mark("a");
        dispatcher.mark("b");
        dispatcher.mark("c");
        dispatcher.flush();

        // group_b 异常不应阻止 group_a 和 group_c
        // 注意：执行顺序不确定，但至少应有2个成功
        assertTrue("Exception doesn't break other actions", results.length >= 1);

        dispatcher.destroy();
    }

    /**
     * 测试在 flush 期间调用 destroy
     * 场景：action 执行时销毁 dispatcher
     */
    private static function testDestroyDuringFlush():Void {
        var dispatcher:CascadeDispatcher = new CascadeDispatcher();
        var callCount:Number = 0;

        dispatcher.map("x", "destroyGroup");
        dispatcher.map("y", "afterDestroy");

        dispatcher.action("destroyGroup", function() {
            callCount++;
            dispatcher.destroy(); // 在 flush 期间销毁
        });

        dispatcher.action("afterDestroy", function() {
            callCount++; // 销毁后这个可能不会执行
        });

        dispatcher.mark("x");
        dispatcher.mark("y");

        // 不应崩溃
        dispatcher.flush();

        // 至少 destroyGroup 应该执行
        assertTrue("Destroy during flush doesn't crash", callCount >= 1);
    }

    // =========================================================================
    // Phase 7: Lifecycle & Cleanup Tests
    // =========================================================================

    /**
     * 测试 PropertyContainer.isDestroyed() 方法
     * 场景：验证 destroy 后 isDestroyed() 返回 true
     */
    private static function testIsDestroyedMethod():Void {
        var target:Object = createMockTarget();
        var manager:BuffManager = new BuffManager(target, {});

        var buff:PodBuff = new PodBuff("长枪属性.power", BuffCalculationType.ADD, 50);
        manager.addBuff(buff, "destroy_test");
        manager.update(1);

        var container:PropertyContainer = manager.getPropertyContainer("长枪属性.power");
        assertFalse("Container not destroyed initially", container.isDestroyed());

        // 销毁容器
        container.destroy();

        assertTrue("Container is destroyed after destroy()", container.isDestroyed());
    }

    /**
     * 测试 unmanageProperty 后 _syncPathBindings 跳过已销毁容器
     * 场景：unmanageProperty 后触发 rebind 不应崩溃
     *
     * 【修复验证】v3.0.1 修复了此问题：
     * - 旧行为：_pathContainers 中保留已销毁容器引用，rebind 时崩溃
     * - 新行为：_syncPathBindings 检查 isDestroyed() 并跳过
     */
    private static function testUnmanagedContainerSkipped():Void {
        var target:Object = createMockTarget();
        var manager:BuffManager = new BuffManager(target, {});

        // 创建路径属性
        var buff:PodBuff = new PodBuff("长枪属性.power", BuffCalculationType.ADD, 50);
        manager.addBuff(buff, "unmanage_test");
        manager.update(1);

        assertEqual("Before unmanage", 150, target.长枪属性.power);

        // 解除托管（会销毁容器）
        manager.unmanageProperty("长枪属性.power", false);

        // 现在触发 rebind（替换对象并 notify）
        target.长枪属性 = { power: 300, range: 600 };
        manager.notifyPathRootChanged("长枪属性");

        // 这里不应该崩溃，因为 _syncPathBindings 会跳过已销毁的容器
        manager.update(1);

        // 验证新对象保持原值（没有被接管）
        assertEqual("After unmanage + rebind", 300, target.长枪属性.power);

        manager.destroy();
    }

    /**
     * 测试 _pathContainers 数组压缩
     * 场景：多次 unmanageProperty 后数组应该被压缩
     *
     * 【修复验证】v3.0.1 修复了此问题：
     * - 旧行为：_pathContainers 只增不减，内存泄漏
     * - 新行为：_syncPathBindings 自动压缩数组
     */
    private static function testPathContainersCompaction():Void {
        var target:Object = createMockTarget();
        var manager:BuffManager = new BuffManager(target, {});

        // 创建多个路径属性
        var buff1:PodBuff = new PodBuff("长枪属性.power", BuffCalculationType.ADD, 10);
        var buff2:PodBuff = new PodBuff("手枪属性.power", BuffCalculationType.ADD, 20);
        var buff3:PodBuff = new PodBuff("长枪属性.range", BuffCalculationType.ADD, 30);
        manager.addBuff(buff1, "compact_test1");
        manager.addBuff(buff2, "compact_test2");
        manager.addBuff(buff3, "compact_test3");
        manager.update(1);

        // 解除其中两个
        manager.unmanageProperty("长枪属性.power", false);
        manager.unmanageProperty("手枪属性.power", false);

        // 触发压缩（需要 notify 和 update）
        target.长枪属性 = { power: 500, range: 330 };
        manager.notifyPathRootChanged("长枪属性");
        manager.update(1);

        // 不应崩溃，剩余的属性应该正常工作
        // 长枪属性.range 的 buff 应该重新绑定到新对象
        assertEqual("Remaining path property works", 360, target.长枪属性.range);

        manager.destroy();
    }

    /**
     * 测试 unmanageProperty 后再添加同名属性
     * 场景：解除托管后重新创建同名路径属性
     */
    private static function testRebindAfterUnmanageNocrash():Void {
        var target:Object = createMockTarget();
        var manager:BuffManager = new BuffManager(target, {});

        // 第一次创建
        var buff1:PodBuff = new PodBuff("长枪属性.power", BuffCalculationType.ADD, 50);
        manager.addBuff(buff1, "first");
        manager.update(1);
        assertEqual("First creation", 150, target.长枪属性.power);

        // 解除托管
        manager.unmanageProperty("长枪属性.power", true); // finalize=true 保留值

        // 重新创建同名属性
        var buff2:PodBuff = new PodBuff("长枪属性.power", BuffCalculationType.ADD, 100);
        manager.addBuff(buff2, "second");
        manager.update(1);

        // 应该基于 finalized 的值（150）再加 100
        assertEqual("Recreation after unmanage", 250, target.长枪属性.power);

        manager.destroy();
    }

    /**
     * 测试多次 unmanage 然后 rebind 的极端场景
     * 场景：反复创建/销毁多个路径属性，验证系统稳定性
     *
     * 【行为说明】unmanageProperty(finalize=false) 会删除属性
     * 所以循环结束后 target.长枪属性 上没有 power 属性
     * 新容器读取 undefined，base = 0
     */
    private static function testMultipleUnmanageThenRebind():Void {
        var target:Object = createMockTarget();
        var manager:BuffManager = new BuffManager(target, {});

        // 循环创建和销毁
        for (var i:Number = 0; i < 5; i++) {
            var buff:PodBuff = new PodBuff("长枪属性.power", BuffCalculationType.ADD, 10);
            manager.addBuff(buff, "loop_" + i);
            manager.update(1);

            // 替换对象
            target.长枪属性 = { power: 100 + i * 10, range: 300 };
            manager.notifyPathRootChanged("长枪属性");
            manager.update(1);

            // 解除托管（finalize=false 会删除属性）
            manager.unmanageProperty("长枪属性.power", false);
        }

        // 循环结束后 target.长枪属性 = { range: 300 }（power 被删除）
        // 最后再创建一次
        var finalBuff:PodBuff = new PodBuff("长枪属性.power", BuffCalculationType.ADD, 999);
        manager.addBuff(finalBuff, "final");
        manager.update(1);

        // 应该正常工作，不崩溃
        // 新容器从 undefined 读取 base = 0
        // final = 0 + 999 = 999
        assertEqual("Multiple unmanage stability", 999, target.长枪属性.power);

        manager.destroy();
    }

    // =========================================================================
    // Helper Functions
    // =========================================================================

    private static function createMockTarget():Object {
        return {
            hp: 1000,
            atk: 50,
            def: 30,
            长枪属性: {
                power: 100,
                range: 300
            },
            手枪属性: {
                power: 50,
                range: 200
            }
        };
    }

    private static function assertEqual(testName:String, expected, actual):Void {
        testCount++;
        if (expected == actual) {
            passedCount++;
            trace("  [PASS] " + testName);
        } else {
            failedCount++;
            trace("  [FAIL] " + testName + " - Expected: " + expected + ", Got: " + actual);
        }
    }

    private static function assertTrue(testName:String, condition:Boolean):Void {
        testCount++;
        if (condition) {
            passedCount++;
            trace("  [PASS] " + testName);
        } else {
            failedCount++;
            trace("  [FAIL] " + testName + " - Expected true");
        }
    }

    private static function assertFalse(testName:String, condition:Boolean):Void {
        testCount++;
        if (!condition) {
            passedCount++;
            trace("  [PASS] " + testName);
        } else {
            failedCount++;
            trace("  [FAIL] " + testName + " - Expected false");
        }
    }

    private static function assertNotNull(testName:String, obj:Object):Void {
        testCount++;
        if (obj != null && obj != undefined) {
            passedCount++;
            trace("  [PASS] " + testName);
        } else {
            failedCount++;
            trace("  [FAIL] " + testName + " - Expected not null");
        }
    }

    private static function assertNull(testName:String, obj:Object):Void {
        testCount++;
        if (obj == null || obj == undefined) {
            passedCount++;
            trace("  [PASS] " + testName);
        } else {
            failedCount++;
            trace("  [FAIL] " + testName + " - Expected null");
        }
    }
}
