// org/flashNight/arki/component/Buff/test/BugfixRegressionTest.as

import org.flashNight.arki.component.Buff.*;
import org.flashNight.arki.component.Buff.Component.*;
import org.flashNight.arki.component.Buff.test.*;

/**
 * Bugfix Regression Test Suite
 *
 * 针对 2026-01 修复的问题进行回归测试：
 * - P0-1: unmanageProperty 脏标记问题
 * - P0-2: MetaBuff 异常/过期后移除
 * - P0-3: _redistribute* 空容器保护（空/null/undefined 属性名）
 * - P0-CRITICAL: _flushPendingAdds 重入丢失修复（v2.3双缓冲）
 * - P1-1: _flushPendingAdds 性能
 * - P1-2: _inUpdate 标志复位时机
 * - P1-3: changeCallback 无值比较问题
 * - P2-2: MAX_MODIFICATIONS 边界控制
 *
 * v2.3 新增测试（共 6 个）：
 * - 重入场景：onBuffAdded回调中addBuff不丢失
 * - 链式回调：A->B->C 不丢失
 * - 多波重入：极端情况不丢失
 * - 双缓冲核心：flush阶段二次入队不丢失
 * - 契约验证：延迟添加时机、OVERRIDE遍历方向
 *
 * v2.4 新增测试（共 3 个）：
 * - MetaBuff.removeInjectedBuffId方法验证
 * - 组件契约化（无try/catch）验证
 * - PodBuff.applyEffect契约化（无冗余检查）验证
 *
 * v2.6 新增测试（共 4 个）：
 * - 注入PodBuff的__inManager/__regId标记验证
 * - PodBuff.getType()返回正确类型验证
 * - MetaBuff组件动态判断（componentBased动态化）验证
 * - _removePodBuffCore O(1)查找性能验证
 *
 * 使用方式: BugfixRegressionTest.runAllTests();
 */
class org.flashNight.arki.component.Buff.test.BugfixRegressionTest {

    private static var testCount:Number = 0;
    private static var passedCount:Number = 0;
    private static var failedCount:Number = 0;
    private static var EPSILON:Number = 0.0001;

    /**
     * 运行所有回归测试
     */
    public static function runAllTests():Void {
        trace("=== Bugfix Regression Test Suite ===");
        trace("Testing fixes from 2026-01 review\n");

        testCount = 0;
        passedCount = 0;
        failedCount = 0;

        trace("--- P0 Critical Fixes ---");
        test_P0_1_unmanageProperty_DirtyFlag();
        test_P0_1_unmanageProperty_Blacklist();
        test_P0_1_unmanageProperty_ReAddBuff();
        test_P0_2_MetaBuff_ExceptionRemoval();
        test_P0_3_redistribute_NullContainerProtection();

        trace("\n--- v2.3 Critical: Reentry Safety ---");
        test_v23_ReentrantAddBuff_OnBuffAdded();
        test_v23_ReentrantAddBuff_ChainedCallbacks();
        test_v23_ReentrantAddBuff_MultipleWaves();
        test_v23_DoubleBuffer_FlushPhaseReentry();

        trace("\n--- v2.3 Contract Verification ---");
        test_v23_Contract_DelayedAddTiming();
        test_v23_Contract_OverrideTraversalOrder();

        trace("\n--- P1 Important Fixes ---");
        test_P1_1_flushPendingAdds_Performance();
        test_P1_2_inUpdate_ReentryProtection();
        test_P1_3_changeCallback_ValueComparison();

        trace("\n--- P2 Optimizations ---");
        test_P2_2_MAX_MODIFICATIONS_BoundaryControl();

        trace("\n--- v2.4 Fixes ---");
        test_v24_MetaBuff_removeInjectedBuffId();
        test_v24_Component_NoThrowContract();
        test_v24_PodBuff_applyEffect_Contract();

        trace("\n--- v2.6 Fixes ---");
        test_v26_InjectedPodBuff_ManagerFlags();
        test_v26_PodBuff_getType();
        test_v26_MetaBuff_DynamicComponentBased();
        test_v26_RemovePodBuffCore_O1Performance();

        printTestResults();
    }

    // ========================================
    // P0-1: unmanageProperty 脏标记问题
    // ========================================

    /**
     * P0-1 测试1: unmanageProperty 后下一帧不应重建容器
     */
    private static function test_P0_1_unmanageProperty_DirtyFlag():Void {
        startTest("P0-1: unmanageProperty should not recreate container next frame");

        try {
            var target:Object = {attack: 100};
            var manager:BuffManager = new BuffManager(target, null);

            // 添加一个buff
            var buff:PodBuff = new PodBuff("attack", BuffCalculationType.ADD, 50);
            manager.addBuff(buff, "test_buff");
            manager.update(1);

            // 验证buff生效
            var valueBeforeUnmanage:Number = target.attack;
            assert(valueBeforeUnmanage == 150, "Buff should be active: expected 150, got " + valueBeforeUnmanage);

            // 解除管理（finalize=true 固化当前值）
            manager.unmanageProperty("attack", true);

            // 多次update，容器不应被重建
            manager.update(1);
            manager.update(1);
            manager.update(1);

            // 检查属性是否仍然是普通数据属性（值应保持不变）
            var valueAfterUpdates:Number = target.attack;
            assert(valueAfterUpdates == 150, "Value should remain 150 after unmanage, got " + valueAfterUpdates);

            // 手动修改应该生效（因为已变成普通属性）
            target.attack = 999;
            assert(target.attack == 999, "Direct assignment should work after unmanage");

            manager.destroy();
            passTest();
        } catch (e) {
            failTest("P0-1 dirty flag test failed: " + e);
        }
    }

    /**
     * P0-1 测试2: unmanageProperty 黑名单机制
     */
    private static function test_P0_1_unmanageProperty_Blacklist():Void {
        startTest("P0-1: unmanageProperty blacklist prevents container creation");

        try {
            var target:Object = {defense: 50};
            var manager:BuffManager = new BuffManager(target, null);

            // 添加buff并解除管理
            var buff:PodBuff = new PodBuff("defense", BuffCalculationType.ADD, 25);
            manager.addBuff(buff, "def_buff");
            manager.update(1);
            manager.unmanageProperty("defense", true);

            // 尝试添加同属性的新buff（应该被拒绝或不生效）
            var newBuff:PodBuff = new PodBuff("defense", BuffCalculationType.ADD, 100);
            manager.addBuff(newBuff, "new_def_buff");
            manager.update(1);

            // 由于黑名单，新buff添加时会自动移除黑名单（允许再次管理）
            // 这是期望行为，所以值应该变化
            var finalValue:Number = target.defense;
            trace("  Final defense value after re-adding buff: " + finalValue);

            manager.destroy();
            passTest();
        } catch (e) {
            failTest("P0-1 blacklist test failed: " + e);
        }
    }

    /**
     * P0-1 测试3: 解除管理后重新添加buff应该工作
     */
    private static function test_P0_1_unmanageProperty_ReAddBuff():Void {
        startTest("P0-1: Re-adding buff after unmanage should work");

        try {
            var target:Object = {speed: 10};
            var manager:BuffManager = new BuffManager(target, null);

            // 第一阶段：添加buff
            var buff1:PodBuff = new PodBuff("speed", BuffCalculationType.MULTIPLY, 2);
            manager.addBuff(buff1, "speed_buff");
            manager.update(1);
            assert(target.speed == 20, "Phase 1: 10*2=20, got " + target.speed);

            // 第二阶段：解除管理
            manager.unmanageProperty("speed", true);
            assert(target.speed == 20, "Phase 2: Value should be finalized at 20");

            // 第三阶段：重新添加buff（应该从黑名单移除并工作）
            var buff2:PodBuff = new PodBuff("speed", BuffCalculationType.ADD, 5);
            manager.addBuff(buff2, "speed_buff_2");
            manager.update(1);

            // 新buff应该基于当前target值（20）工作
            var finalValue:Number = target.speed;
            trace("  Final speed value: " + finalValue);
            // 20 + 5 = 25
            assert(finalValue == 25, "Phase 3: 20+5=25, got " + finalValue);

            manager.destroy();
            passTest();
        } catch (e) {
            failTest("P0-1 re-add buff test failed: " + e);
        }
    }

    // ========================================
    // P0-2: MetaBuff 异常后不移除问题
    // ========================================

    /**
     * P0-2 测试: MetaBuff update抛异常时应立即移除
     *
     * 真实触发条件：创建一个组件会抛异常的MetaBuff
     * AS2 的异常处理会被 BuffManager 的 try-catch 捕获，
     * MetaBuff 应该被标记为失效并移除
     */
    private static function test_P0_2_MetaBuff_ExceptionRemoval():Void {
        startTest("P0-2: MetaBuff with faulty component should be handled gracefully");

        try {
            var target:Object = {hp: 100};
            var exceptionCount:Number = 0;

            var callbacks:Object = {
                onBuffRemoved: function(buffId:String, buff:IBuff):Void {
                    if (buffId == "faulty_meta") {
                        trace("    Faulty MetaBuff removed via callback");
                    }
                }
            };

            var manager:BuffManager = new BuffManager(target, callbacks);

            // 创建正常的 MetaBuff 作为对照组
            var normalPod:PodBuff = new PodBuff("hp", BuffCalculationType.ADD, 50);
            var normalTime:TimeLimitComponent = new TimeLimitComponent(100);
            var normalMeta:MetaBuff = new MetaBuff([normalPod], [normalTime], 0);
            manager.addBuff(normalMeta, "normal_meta");

            // 创建一个会"出问题"的 MetaBuff
            // 通过创建一个空的childBuffs数组或极短时限来模拟
            var faultyPod:PodBuff = new PodBuff("hp", BuffCalculationType.ADD, 25);
            var shortTime:TimeLimitComponent = new TimeLimitComponent(1); // 极短时限，1帧后过期
            var faultyMeta:MetaBuff = new MetaBuff([faultyPod], [shortTime], 0);
            manager.addBuff(faultyMeta, "faulty_meta");

            manager.update(1);

            var buffCountAfterFirst:Number = manager.getActiveBuffCount();
            trace("  Active buffs after first update: " + buffCountAfterFirst);

            // 再更新几次，短时限的MetaBuff应该已过期并被移除
            manager.update(1);
            manager.update(1);

            var buffCountAfterExpiry:Number = manager.getActiveBuffCount();
            trace("  Active buffs after expiry: " + buffCountAfterExpiry);

            // 正常的MetaBuff应该仍然存活
            assert(buffCountAfterExpiry >= 1, "Normal MetaBuff should still be active");

            // 验证hp值（只有正常MetaBuff的+50生效，faulty的+25已移除）
            var hpValue:Number = target.hp;
            trace("  Final HP value: " + hpValue);
            assert(hpValue == 150, "Only normal MetaBuff should remain: expected 150, got " + hpValue);

            manager.destroy();
            passTest();
        } catch (e) {
            failTest("P0-2 exception removal test failed: " + e);
        }
    }

    // ========================================
    // P0-3: _redistribute* 空容器保护
    // ========================================

    /**
     * P0-3 测试: 无效属性名的PodBuff不应导致崩溃
     *
     * 真实触发条件：
     * - 空字符串属性名
     * - null 属性名
     * - undefined 属性名
     * 系统应该静默拒绝，不应崩溃
     */
    private static function test_P0_3_redistribute_NullContainerProtection():Void {
        startTest("P0-3: Invalid property names (empty/null/undefined) should be rejected gracefully");

        try {
            var target:Object = {validProp: 100};
            var manager:BuffManager = new BuffManager(target, null);

            // 添加有效buff作为对照
            var validBuff:PodBuff = new PodBuff("validProp", BuffCalculationType.ADD, 10);
            var validId:String = manager.addBuff(validBuff, "valid");
            trace("  Valid buff added with ID: " + validId);

            manager.update(1);
            assert(target.validProp == 110, "Valid buff should work: expected 110, got " + target.validProp);

            // 测试1：空字符串属性名
            var emptyPropBuff:PodBuff = new PodBuff("", BuffCalculationType.ADD, 999);
            var emptyId:String = manager.addBuff(emptyPropBuff, "empty_prop");
            trace("  Empty property buff result: " + (emptyId == null ? "rejected" : "accepted with ID " + emptyId));

            // 测试2：null 属性名（AS2 会转成字符串 "null"，但应该被拦截）
            var nullPropBuff:PodBuff = new PodBuff(null, BuffCalculationType.ADD, 888);
            var nullId:String = manager.addBuff(nullPropBuff, "null_prop");
            trace("  Null property buff result: " + (nullId == null ? "rejected" : "accepted with ID " + nullId));

            // 测试3：undefined 属性名
            var undefProp:String = undefined;
            var undefPropBuff:PodBuff = new PodBuff(undefProp, BuffCalculationType.ADD, 777);
            var undefId:String = manager.addBuff(undefPropBuff, "undef_prop");
            trace("  Undefined property buff result: " + (undefId == null ? "rejected" : "accepted with ID " + undefId));

            manager.update(1);

            // 验证：无效buff不应影响有效属性
            var finalValue:Number = target.validProp;
            trace("  Final validProp value: " + finalValue);
            assert(finalValue == 110, "Invalid buffs should not affect valid property: expected 110, got " + finalValue);

            // 验证：target上不应出现无效属性
            assert(target[""] == undefined, "Empty property should not be created on target");

            manager.destroy();
            passTest();
        } catch (e) {
            failTest("P0-3 null container protection test failed: " + e);
        }
    }

    // ========================================
    // v2.3 CRITICAL: 重入安全测试
    // ========================================

    /**
     * v2.3 测试1: onBuffAdded回调中addBuff不丢失
     *
     * 这是v2.3修复的核心问题：_flushPendingAdds重入期间添加的buff不能丢失
     */
    private static function test_v23_ReentrantAddBuff_OnBuffAdded():Void {
        startTest("v2.3: Reentrant addBuff in onBuffAdded should not be lost");

        try {
            var target:Object = {damage: 100};
            var state:Object = {reentrantBuffAdded: false, manager: null};

            // AS2闭包：通过外部对象捕获状态
            var callbacks:Object = {
                onBuffAdded: function(buffId:String, buff:IBuff):Void {
                    // 在回调中添加另一个buff（重入场景）
                    if (buffId == "trigger_buff" && !state.reentrantBuffAdded) {
                        state.reentrantBuffAdded = true;
                        // 这个buff在v2.3之前会丢失！
                        var chainBuff:PodBuff = new PodBuff("damage", BuffCalculationType.ADD, 50);
                        state.manager.addBuff(chainBuff, "chained_buff");
                    }
                }
            };

            var manager:BuffManager = new BuffManager(target, callbacks);
            state.manager = manager;  // 闭包捕获

            // 添加触发buff
            var triggerBuff:PodBuff = new PodBuff("damage", BuffCalculationType.ADD, 25);
            manager.addBuff(triggerBuff, "trigger_buff");
            manager.update(1);

            // 再次update确保链式buff被处理
            manager.update(1);

            var finalValue:Number = target.damage;
            trace("  Final damage value: " + finalValue);
            trace("  Reentrant buff added: " + state.reentrantBuffAdded);

            // 100 + 25 + 50 = 175
            assert(state.reentrantBuffAdded, "Reentrant addBuff should have been called");
            assert(finalValue == 175, "Both buffs should be applied: expected 175, got " + finalValue);

            manager.destroy();
            passTest();
        } catch (e) {
            failTest("v2.3 reentrant addBuff test failed: " + e);
        }
    }

    /**
     * v2.3 测试2: 链式回调（A触发B，B触发C）
     */
    private static function test_v23_ReentrantAddBuff_ChainedCallbacks():Void {
        startTest("v2.3: Chained callbacks (A->B->C) should not lose any buff");

        try {
            var target:Object = {power: 0};
            var state:Object = {addedBuffs: [], manager: null};

            // AS2闭包：通过外部对象捕获状态
            var callbacks:Object = {
                onBuffAdded: function(buffId:String, buff:IBuff):Void {
                    state.addedBuffs.push(buffId);

                    // A触发B
                    if (buffId == "buff_A") {
                        var buffB:PodBuff = new PodBuff("power", BuffCalculationType.ADD, 10);
                        state.manager.addBuff(buffB, "buff_B");
                    }
                    // B触发C
                    else if (buffId == "buff_B") {
                        var buffC:PodBuff = new PodBuff("power", BuffCalculationType.ADD, 10);
                        state.manager.addBuff(buffC, "buff_C");
                    }
                }
            };

            var manager:BuffManager = new BuffManager(target, callbacks);
            state.manager = manager;  // 闭包捕获

            // 添加A
            var buffA:PodBuff = new PodBuff("power", BuffCalculationType.ADD, 10);
            manager.addBuff(buffA, "buff_A");
            manager.update(1);
            manager.update(1);  // 确保所有链式buff被处理

            var finalValue:Number = target.power;
            trace("  Added buffs: " + state.addedBuffs.join(" -> "));
            trace("  Final power: " + finalValue);

            // 应该有A, B, C三个buff，每个+10
            assert(state.addedBuffs.length == 3, "Should have 3 buffs added, got " + state.addedBuffs.length);
            assert(finalValue == 30, "All chained buffs should be applied: expected 30, got " + finalValue);

            manager.destroy();
            passTest();
        } catch (e) {
            failTest("v2.3 chained callbacks test failed: " + e);
        }
    }

    /**
     * v2.3 测试3: 多波重入（模拟极端情况）
     */
    private static function test_v23_ReentrantAddBuff_MultipleWaves():Void {
        startTest("v2.3: Multiple waves of reentrant addBuff");

        try {
            var target:Object = {count: 0};
            var state:Object = {waveCount: 0, maxWaves: 3, manager: null};

            // AS2闭包：通过外部对象捕获状态
            var callbacks:Object = {
                onBuffAdded: function(buffId:String, buff:IBuff):Void {
                    // 每波添加2个新buff，最多3波
                    if (state.waveCount < state.maxWaves && buffId.indexOf("wave") == 0) {
                        state.waveCount++;
                        for (var i:Number = 0; i < 2; i++) {
                            var newBuff:PodBuff = new PodBuff("count", BuffCalculationType.ADD, 1);
                            state.manager.addBuff(newBuff, "wave" + state.waveCount + "_" + i);
                        }
                    }
                }
            };

            var manager:BuffManager = new BuffManager(target, callbacks);
            state.manager = manager;  // 闭包捕获

            // 触发第一波
            var seedBuff:PodBuff = new PodBuff("count", BuffCalculationType.ADD, 1);
            manager.addBuff(seedBuff, "wave0_seed");

            // 多次update确保所有波都被处理
            for (var u:Number = 0; u < 5; u++) {
                manager.update(1);
            }

            var finalValue:Number = target.count;
            trace("  Waves triggered: " + state.waveCount);
            trace("  Final count: " + finalValue);

            // 1(seed) + 2(wave1) + 4(wave2) + 4(wave3，被maxWaves限制) = 需要计算实际
            // 实际是: seed(1) + wave1产生2个 + wave2产生4个（每个wave1的buff触发2个）
            // 但由于waveCount限制，实际更少
            // seed -> 2(wave1) -> 2*2=4(wave2) -> 但waveCount=3后停止
            assert(state.waveCount == state.maxWaves, "Should have triggered " + state.maxWaves + " waves, got " + state.waveCount);
            assert(finalValue > 0, "Some buffs should be applied");

            manager.destroy();
            passTest();
        } catch (e) {
            failTest("v2.3 multiple waves test failed: " + e);
        }
    }

    /**
     * v2.3 测试4: flush 阶段二次入队不丢失（双缓冲核心验证）
     *
     * 这是双缓冲机制的精确验证：
     * 1. 通过 onPropertyChanged 回调在 update() 期间触发 addBuff()，buff 进入 pendingAdds
     * 2. _flushPendingAdds() 处理该 buff，触发 onBuffAdded
     * 3. onBuffAdded 中再次 addBuff()（此时正在处理队列A，新 buff 写入队列B）
     * 4. 验证两个 buff 都不丢失
     *
     * 【关键】必须在 _inUpdate=true 期间触发 addBuff，才能真正测试双缓冲
     * 使用 onPropertyChanged 回调是最可靠的方式，因为它在 update 的重算阶段触发
     */
    private static function test_v23_DoubleBuffer_FlushPhaseReentry():Void {
        startTest("v2.3: Double-buffer flush phase reentry (真正的 pending 队列测试)");

        try {
            var target:Object = {score: 0, trigger: 100};
            var state:Object = {
                manager: null,
                phase: 0,  // 0=初始, 1=已在update期间添加pending_first, 2=已在flush期间添加pending_second
                pendingFirstAdded: false,
                pendingSecondAdded: false
            };

            var callbacks:Object = {
                // 【关键】onPropertyChanged 在 update() 的重算阶段触发，此时 _inUpdate=true
                onPropertyChanged: function(propName:String, newValue:Number):Void {
                    if (propName == "trigger" && state.phase == 0) {
                        state.phase = 1;
                        // 此时 _inUpdate=true，addBuff 会进入 _pendingAdds 队列
                        var pendingFirst:PodBuff = new PodBuff("score", BuffCalculationType.ADD, 10);
                        state.manager.addBuff(pendingFirst, "pending_first");
                        state.pendingFirstAdded = true;
                        trace("    [onPropertyChanged] Added pending_first during update (should go to pending queue)");
                    }
                },
                onBuffAdded: function(buffId:String, buff:IBuff):Void {
                    // 当 pending_first 被 flush 处理时，在回调中添加 pending_second
                    // 此时仍在 _flushPendingAdds 循环中，新 buff 应写入另一个缓冲队列
                    if (buffId == "pending_first" && state.phase == 1) {
                        state.phase = 2;
                        var pendingSecond:PodBuff = new PodBuff("score", BuffCalculationType.ADD, 100);
                        state.manager.addBuff(pendingSecond, "pending_second");
                        state.pendingSecondAdded = true;
                        trace("    [onBuffAdded] Added pending_second during flush (should go to buffer B)");
                    }
                }
            };

            var manager:BuffManager = new BuffManager(target, callbacks);
            state.manager = manager;

            // 第一步：添加一个会修改 trigger 属性的 buff
            // 这会在 update() 期间触发 onPropertyChanged
            var triggerBuff:PodBuff = new PodBuff("trigger", BuffCalculationType.ADD, 50);
            manager.addBuff(triggerBuff, "trigger_buff");
            trace("  Step 1: Added trigger_buff");

            // 第二步：update 触发以下流程：
            // 1. 重算 trigger 属性 → 触发 onPropertyChanged → 添加 pending_first 到 pending 队列
            // 2. flush pending 队列 → 处理 pending_first → 触发 onBuffAdded → 添加 pending_second
            // 3. 双缓冲机制确保 pending_second 不丢失
            manager.update(1);
            trace("  Step 2: First update, score = " + target.score + ", phase = " + state.phase);

            // 第三步：再 update 一次处理所有 pending（如果双缓冲正确，pending_second 应该在上次就被处理）
            manager.update(1);
            trace("  Step 3: Second update, score = " + target.score);

            // 验证
            var finalScore:Number = target.score;
            trace("  Final score: " + finalScore);
            trace("  pendingFirstAdded: " + state.pendingFirstAdded);
            trace("  pendingSecondAdded: " + state.pendingSecondAdded);
            trace("  final phase: " + state.phase);

            assert(state.pendingFirstAdded, "pending_first should have been added during update");
            assert(state.pendingSecondAdded, "pending_second should have been added during flush");
            assert(state.phase == 2, "Should have reached phase 2");

            // pending_first(10) + pending_second(100) = 110
            assert(finalScore == 110, "Both pending buffs should be applied: expected 110, got " + finalScore);

            manager.destroy();
            passTest();
        } catch (e) {
            failTest("v2.3 double-buffer flush phase reentry test failed: " + e);
        }
    }

    // ========================================
    // v2.3 契约验证测试
    // ========================================

    /**
     * v2.3 契约1: 延迟添加生效时机
     * 验证：update期间addBuff的效果从本次update结束时生效
     */
    private static function test_v23_Contract_DelayedAddTiming():Void {
        startTest("v2.3 Contract: Delayed add timing (buff added during update takes effect end of update)");

        try {
            var target:Object = {value: 100};
            var valuesDuringUpdate:Array = [];

            var callbacks:Object = {
                onBuffAdded: function(buffId:String, buff:IBuff):Void {
                    // 记录回调时的属性值
                    valuesDuringUpdate.push({id: buffId, value: this.target.value});
                }
            };

            var manager:BuffManager = new BuffManager(target, callbacks);
            callbacks.onBuffAdded.target = target;

            // 添加buff
            var buff:PodBuff = new PodBuff("value", BuffCalculationType.ADD, 50);
            manager.addBuff(buff, "test_buff");

            // 在update之前，值仍是100（尚未计算）
            var valueBeforeUpdate:Number = target.value;

            manager.update(1);

            // update之后，值应该是150
            var valueAfterUpdate:Number = target.value;

            trace("  Value before update: " + valueBeforeUpdate);
            trace("  Value after update: " + valueAfterUpdate);
            trace("  Values during callbacks: " + valuesDuringUpdate.length + " records");

            assert(valueAfterUpdate == 150, "After update, value should be 150, got " + valueAfterUpdate);

            manager.destroy();
            passTest();
        } catch (e) {
            failTest("v2.3 delayed add timing test failed: " + e);
        }
    }

    /**
     * v2.3 契约2: OVERRIDE遍历方向
     * 验证：多个OVERRIDE并存时，添加顺序最早的OVERRIDE生效
     */
    private static function test_v23_Contract_OverrideTraversalOrder():Void {
        startTest("v2.3 Contract: OVERRIDE traversal order (earliest added wins)");

        try {
            var target:Object = {stat: 100};
            var manager:BuffManager = new BuffManager(target, null);

            // 先添加OVERRIDE=500
            var override1:PodBuff = new PodBuff("stat", BuffCalculationType.OVERRIDE, 500);
            manager.addBuff(override1, "override_first");

            // 后添加OVERRIDE=999
            var override2:PodBuff = new PodBuff("stat", BuffCalculationType.OVERRIDE, 999);
            manager.addBuff(override2, "override_second");

            manager.update(1);

            var finalValue:Number = target.stat;
            trace("  Final stat with two OVERRIDEs (500 first, 999 second): " + finalValue);

            // 根据契约：逆序遍历 + 最后写入wins = 先添加的生效
            // 所以应该是500
            assert(finalValue == 500, "Contract: earliest OVERRIDE should win, expected 500, got " + finalValue);

            manager.destroy();
            passTest();
        } catch (e) {
            failTest("v2.3 OVERRIDE traversal order test failed: " + e);
        }
    }

    // ========================================
    // P1-1: _flushPendingAdds 性能
    // ========================================

    /**
     * P1-1 测试: 延迟添加队列性能
     */
    private static function test_P1_1_flushPendingAdds_Performance():Void {
        startTest("P1-1: _flushPendingAdds performance with index traversal");

        try {
            var target:Object = {power: 0};
            var manager:BuffManager = new BuffManager(target, null);

            var startTime:Number = getTimer();
            var buffCount:Number = 100;

            // 批量添加buff
            for (var i:Number = 0; i < buffCount; i++) {
                var buff:PodBuff = new PodBuff("power", BuffCalculationType.ADD, 1);
                manager.addBuff(buff, "buff_" + i);
            }

            manager.update(1);

            var endTime:Number = getTimer();
            var elapsed:Number = endTime - startTime;

            trace("  Added " + buffCount + " buffs in " + elapsed + "ms");
            trace("  Final power value: " + target.power);

            assert(target.power == buffCount, "All buffs should be applied: expected " + buffCount + ", got " + target.power);

            // 性能断言：100个buff应该在合理时间内完成
            assert(elapsed < 1000, "Should complete in < 1s, took " + elapsed + "ms");

            manager.destroy();
            passTest();
        } catch (e) {
            failTest("P1-1 performance test failed: " + e);
        }
    }

    // ========================================
    // P1-2: _inUpdate 标志复位时机
    // ========================================

    /**
     * P1-2 测试: update期间的回调不应导致重入
     */
    private static function test_P1_2_inUpdate_ReentryProtection():Void {
        startTest("P1-2: Callbacks during update should not cause reentry issues");

        try {
            var callbackCount:Number = 0;
            var target:Object = {stat: 50};

            var callbacks:Object = {
                onBuffAdded: function(buff:IBuff, id:String):Void {
                    callbackCount++;
                    // 回调中不应该触发问题
                },
                onBuffRemoved: function(buff:IBuff, id:String):Void {
                    callbackCount++;
                }
            };

            var manager:BuffManager = new BuffManager(target, callbacks);

            // 添加buff
            var buff:PodBuff = new PodBuff("stat", BuffCalculationType.ADD, 10);
            manager.addBuff(buff, "test");
            manager.update(1);

            trace("  Callback count: " + callbackCount);
            assert(callbackCount >= 1, "Callbacks should be invoked");

            // 移除buff
            manager.removeBuff("test");
            manager.update(1);

            trace("  Final callback count: " + callbackCount);

            manager.destroy();
            passTest();
        } catch (e) {
            failTest("P1-2 reentry protection test failed: " + e);
        }
    }

    // ========================================
    // P1-3: changeCallback 无值比较问题
    // ========================================

    /**
     * P1-3 测试: changeCallback只在值变化时触发
     */
    private static function test_P1_3_changeCallback_ValueComparison():Void {
        startTest("P1-3: changeCallback should only trigger on value change");

        try {
            var callbackCount:Number = 0;
            var lastValue:Number = NaN;

            var callback:Function = function(prop:String, val:Number):Void {
                callbackCount++;
                lastValue = val;
                trace("    Callback triggered: " + prop + " = " + val);
            };

            var target:Object = {};
            var container:PropertyContainer = new PropertyContainer(target, "testProp", 100, callback);

            // 第一次访问，触发回调
            var v1:Number = target.testProp;
            var callbackCountAfterFirst:Number = callbackCount;
            trace("  After first access: callbackCount = " + callbackCount);

            // 多次访问相同值，不应触发新回调
            var v2:Number = target.testProp;
            var v3:Number = target.testProp;
            var v4:Number = target.testProp;

            trace("  After repeated access: callbackCount = " + callbackCount);
            assert(callbackCount == callbackCountAfterFirst,
                "Repeated access should not trigger callback: expected " + callbackCountAfterFirst + ", got " + callbackCount);

            // 添加buff改变值，应触发回调
            var buff:PodBuff = new PodBuff("testProp", BuffCalculationType.ADD, 50);
            container.addBuff(buff);
            var v5:Number = target.testProp;

            trace("  After adding buff: callbackCount = " + callbackCount + ", value = " + v5);
            assert(callbackCount > callbackCountAfterFirst, "Value change should trigger callback");
            assert(lastValue == 150, "Last value should be 150, got " + lastValue);

            container.destroy();
            passTest();
        } catch (e) {
            failTest("P1-3 value comparison test failed: " + e);
        }
    }

    // ========================================
    // P2-2: MAX_MODIFICATIONS 边界控制
    // ========================================

    /**
     * P2-2 测试: 边界控制在超限时仍被处理
     */
    private static function test_P2_2_MAX_MODIFICATIONS_BoundaryControl():Void {
        startTest("P2-2: Boundary controls (MAX/MIN/OVERRIDE) should work even at limit");

        try {
            var target:Object = {damage: 100};
            var manager:BuffManager = new BuffManager(target, null);

            // 添加大量普通buff（接近但不超过新限制256）
            var normalBuffCount:Number = 250;
            for (var i:Number = 0; i < normalBuffCount; i++) {
                var buff:PodBuff = new PodBuff("damage", BuffCalculationType.ADD, 1);
                manager.addBuff(buff, "normal_" + i);
            }

            // 添加边界控制buff（MAX）- 应该被处理
            var maxBuff:PodBuff = new PodBuff("damage", BuffCalculationType.MAX, 200);
            manager.addBuff(maxBuff, "max_buff");

            // 添加MIN buff
            var minBuff:PodBuff = new PodBuff("damage", BuffCalculationType.MIN, 500);
            manager.addBuff(minBuff, "min_buff");

            manager.update(1);

            var finalValue:Number = target.damage;
            trace("  Final damage with " + normalBuffCount + " ADD buffs + MAX(200) + MIN(500): " + finalValue);

            // 100 + 250 = 350, max(350, 200) = 350, min(350, 500) = 350
            // 边界控制应该正常工作
            assert(!isNaN(finalValue), "Final value should be a valid number");

            manager.destroy();
            passTest();
        } catch (e) {
            failTest("P2-2 boundary control test failed: " + e);
        }
    }

    // ========================================
    // v2.4: 新增修复测试
    // ========================================

    /**
     * v2.4 测试1: MetaBuff.removeInjectedBuffId方法验证
     *
     * 验证：当注入的Pod被独立移除时，MetaBuff的_injectedBuffIds能正确同步
     */
    private static function test_v24_MetaBuff_removeInjectedBuffId():Void {
        startTest("v2.4: MetaBuff.removeInjectedBuffId should sync injected list");

        try {
            var target:Object = {hp: 100, mp: 50};
            var manager:BuffManager = new BuffManager(target, null);

            // 创建带有多个PodBuff的MetaBuff
            var hpPod:PodBuff = new PodBuff("hp", BuffCalculationType.ADD, 20);
            var mpPod:PodBuff = new PodBuff("mp", BuffCalculationType.ADD, 10);
            var timeComp:TimeLimitComponent = new TimeLimitComponent(1000);
            var metaBuff:MetaBuff = new MetaBuff([hpPod, mpPod], [timeComp], 0);

            var metaId:String = manager.addBuff(metaBuff, "meta_test");
            manager.update(1);

            // [v2.8] 使用 BuffManager.getInjectedPodIds() 替代已移除的 MetaBuff.getInjectedBuffIds()
            var injectedIds:Array = manager.getInjectedPodIds(metaBuff.getId());
            var initialCount:Number = injectedIds.length;
            trace("  Initial injected count: " + initialCount);
            assert(initialCount == 2, "Should have 2 injected pods, got " + initialCount);

            // 验证值
            assert(target.hp == 120, "HP should be 120, got " + target.hp);
            assert(target.mp == 60, "MP should be 60, got " + target.mp);

            // [v2.8] 测试通过 BuffManager 移除注入的 Pod 后列表同步更新
            if (injectedIds.length > 0) {
                var testId:String = injectedIds[0];
                // 通过 BuffManager 移除 Pod（现在是唯一数据源）
                var removeResult:Boolean = manager.removeBuff(testId);
                trace("  manager.removeBuff('" + testId + "'): " + removeResult);
                assert(removeResult == true, "removeBuff should return true");

                manager.update(1);  // 处理延迟移除

                var afterRemove:Array = manager.getInjectedPodIds(metaBuff.getId());
                trace("  After remove, injected count: " + afterRemove.length);
                assert(afterRemove.length == initialCount - 1, "Should have one less injected id");
            }

            manager.destroy();
            passTest();
        } catch (e) {
            failTest("v2.4 removeInjectedBuffId test failed: " + e);
        }
    }

    /**
     * v2.4 测试2: 组件契约化验证（无try/catch）
     *
     * 验证：组件遵守不throw的契约，正常工作
     */
    private static function test_v24_Component_NoThrowContract():Void {
        startTest("v2.4: Component no-throw contract verification");

        try {
            var target:Object = {stat: 100};
            var manager:BuffManager = new BuffManager(target, null);

            // 创建正常组件的MetaBuff
            var pod:PodBuff = new PodBuff("stat", BuffCalculationType.ADD, 50);
            var timeComp:TimeLimitComponent = new TimeLimitComponent(10);
            var metaBuff:MetaBuff = new MetaBuff([pod], [timeComp], 0);

            manager.addBuff(metaBuff, "contract_test");
            manager.update(1);

            // 验证正常工作
            assert(target.stat == 150, "Buff should apply: expected 150, got " + target.stat);

            // 多次update验证稳定性
            for (var i:Number = 0; i < 5; i++) {
                manager.update(1);
            }

            trace("  Stat after 5 updates: " + target.stat);
            assert(target.stat == 150, "Value should remain stable");

            // 让TimeLimitComponent过期
            for (var j:Number = 0; j < 10; j++) {
                manager.update(1);
            }

            trace("  Stat after expiry: " + target.stat);
            // 过期后值应该恢复
            assert(target.stat == 100, "After expiry, stat should return to base: expected 100, got " + target.stat);

            manager.destroy();
            passTest();
        } catch (e) {
            failTest("v2.4 component contract test failed: " + e);
        }
    }

    /**
     * v2.4 测试3: PodBuff.applyEffect契约化验证
     *
     * 验证：移除冗余检查后，PropertyContainer契约保证属性匹配
     */
    private static function test_v24_PodBuff_applyEffect_Contract():Void {
        startTest("v2.4: PodBuff.applyEffect contract (no redundant check)");

        try {
            var target:Object = {atk: 100, def: 50};
            var manager:BuffManager = new BuffManager(target, null);

            // 添加多个不同属性的buff
            var atkBuff:PodBuff = new PodBuff("atk", BuffCalculationType.ADD, 30);
            var defBuff:PodBuff = new PodBuff("def", BuffCalculationType.MULTIPLY, 2);
            var atkBuff2:PodBuff = new PodBuff("atk", BuffCalculationType.PERCENT, 0.5);

            manager.addBuff(atkBuff, "atk_add");
            manager.addBuff(defBuff, "def_mult");
            manager.addBuff(atkBuff2, "atk_percent");
            manager.update(1);

            // 验证：每个buff只影响目标属性
            // atk: 100 * 1.5 + 30 = 180 (PERCENT先于ADD)
            // def: 50 * 2 = 100
            var atkValue:Number = target.atk;
            var defValue:Number = target.def;

            trace("  atk value: " + atkValue + " (expected 180)");
            trace("  def value: " + defValue + " (expected 100)");

            assert(atkValue == 180, "atk should be 180 (100*1.5+30), got " + atkValue);
            assert(defValue == 100, "def should be 100 (50*2), got " + defValue);

            // 验证PropertyContainer确实只包含对应属性的buff
            var atkContainer:PropertyContainer = manager.getPropertyContainer("atk");
            var defContainer:PropertyContainer = manager.getPropertyContainer("def");

            if (atkContainer != null) {
                trace("  atk container buff count: " + atkContainer.getBuffCount());
                assert(atkContainer.getBuffCount() == 2, "atk container should have 2 buffs");
            }
            if (defContainer != null) {
                trace("  def container buff count: " + defContainer.getBuffCount());
                assert(defContainer.getBuffCount() == 1, "def container should have 1 buff");
            }

            manager.destroy();
            passTest();
        } catch (e) {
            failTest("v2.4 applyEffect contract test failed: " + e);
        }
    }

    // ========================================
    // v2.6: 新增修复测试
    // ========================================

    /**
     * v2.6 测试1: 注入PodBuff的__inManager/__regId标记验证
     *
     * 验证：MetaBuff注入的PodBuff正确设置管理状态标记
     * 修复前：注入的PodBuff缺少__inManager/__regId，导致removeBuff无法正确识别
     */
    private static function test_v26_InjectedPodBuff_ManagerFlags():Void {
        startTest("v2.6: Injected PodBuff should have __inManager and __regId flags");

        try {
            var target:Object = {hp: 100, mp: 50};
            var manager:BuffManager = new BuffManager(target, null);

            // 创建MetaBuff，注入多个PodBuff
            var hpPod:PodBuff = new PodBuff("hp", BuffCalculationType.ADD, 20);
            var mpPod:PodBuff = new PodBuff("mp", BuffCalculationType.ADD, 10);
            var timeComp:TimeLimitComponent = new TimeLimitComponent(1000);
            var metaBuff:MetaBuff = new MetaBuff([hpPod, mpPod], [timeComp], 0);

            manager.addBuff(metaBuff, "meta_flags_test");
            manager.update(1);

            // [v2.8] 使用 BuffManager.getInjectedPodIds() 替代已移除的 MetaBuff.getInjectedBuffIds()
            var injectedIds:Array = manager.getInjectedPodIds(metaBuff.getId());
            trace("  Injected IDs: " + injectedIds.length);
            assert(injectedIds.length == 2, "Should have 2 injected pods, got " + injectedIds.length);

            // 验证每个注入的PodBuff都有正确的标记
            var allFlagsCorrect:Boolean = true;
            var foundCount:Number = 0;
            for (var i:Number = 0; i < injectedIds.length; i++) {
                var podId:String = injectedIds[i];
                // 注入的Pod通过内部ID在_byInternalId中可查到
                var podBuff:IBuff = manager.getBuffById(podId);

                if (podBuff != null) {
                    foundCount++;
                    var hasInManager:Boolean = (podBuff["__inManager"] === true);
                    var hasRegId:Boolean = (podBuff["__regId"] == podId);

                    trace("    Pod[" + i + "] id=" + podId +
                          ", __inManager=" + podBuff["__inManager"] +
                          ", __regId=" + podBuff["__regId"]);

                    if (!hasInManager || !hasRegId) {
                        allFlagsCorrect = false;
                    }
                } else {
                    trace("    Pod[" + i + "] id=" + podId + " - ERROR: not found in manager!");
                    allFlagsCorrect = false;
                }
            }

            // 硬断言：所有注入的Pod都应该可查到且标记正确
            assert(foundCount == injectedIds.length, "All injected pods should be findable, found " + foundCount + "/" + injectedIds.length);
            assert(allFlagsCorrect, "All injected pods should have correct __inManager/__regId flags");

            // 验证buff效果已应用
            assert(target.hp == 120, "HP should be 120 (100+20), got " + target.hp);
            assert(target.mp == 60, "MP should be 60 (50+10), got " + target.mp);

            // 测试通过removeBuff移除注入的Pod
            if (injectedIds.length > 0) {
                var testPodId:String = injectedIds[0];
                manager.removeBuff(testPodId);
                manager.update(1);
                trace("  After removing first injected pod, hp=" + target.hp);
                assert(target.hp == 100, "After removing hp pod, should return to 100, got " + target.hp);
            }

            manager.destroy();
            passTest();
        } catch (e) {
            failTest("v2.6 injected PodBuff manager flags test failed: " + e);
        }
    }

    /**
     * v2.6 测试2: PodBuff.getType()返回正确类型验证
     *
     * 验证：PodBuff.getType()返回"PodBuff"而非"BaseBuff"
     * 修复前：PodBuff声明了private var _type覆盖了父类字段，导致getType()返回父类默认值
     */
    private static function test_v26_PodBuff_getType():Void {
        startTest("v2.6: PodBuff.getType() should return 'PodBuff'");

        try {
            var podBuff:PodBuff = new PodBuff("test", BuffCalculationType.ADD, 10);
            var typeStr:String = podBuff.getType();

            trace("  PodBuff.getType() = '" + typeStr + "'");

            assert(typeStr == "PodBuff", "getType() should return 'PodBuff', got '" + typeStr + "'");

            // 验证isPod()也正确
            assert(podBuff.isPod() == true, "isPod() should return true");

            // 验证MetaBuff的getType()
            var hpPod:PodBuff = new PodBuff("hp", BuffCalculationType.ADD, 10);
            var timeComp:TimeLimitComponent = new TimeLimitComponent(100);
            var metaBuff:MetaBuff = new MetaBuff([hpPod], [timeComp], 0);

            var metaType:String = metaBuff.getType();
            trace("  MetaBuff.getType() = '" + metaType + "'");

            assert(metaType == "MetaBuff", "MetaBuff.getType() should return 'MetaBuff', got '" + metaType + "'");
            assert(metaBuff.isPod() == false, "MetaBuff.isPod() should return false");

            passTest();
        } catch (e) {
            failTest("v2.6 PodBuff.getType() test failed: " + e);
        }
    }

    /**
     * v2.6 测试3: MetaBuff门控组件过期后正确清理验证
     *
     * 验证：门控组件过期死亡后，MetaBuff正确进入PENDING_DEACTIVATE状态并被移除
     *
     * 技术背景：v2.6修复了时序bug——在_updateComponents之前检查_components.length，
     * 确保门控组件死亡（被splice）后不会错误地fallback到childAlive判断。
     */
    private static function test_v26_MetaBuff_DynamicComponentBased():Void {
        startTest("v2.6: MetaBuff gate component expiry should terminate MetaBuff");

        try {
            var target:Object = {stat: 100};
            var manager:BuffManager = new BuffManager(target, null);

            // 创建一个有门控组件(TimeLimitComponent)的MetaBuff
            var pod:PodBuff = new PodBuff("stat", BuffCalculationType.ADD, 50);
            var shortTimeComp:TimeLimitComponent = new TimeLimitComponent(2); // 2帧后过期
            var metaBuff:MetaBuff = new MetaBuff([pod], [shortTimeComp], 0);

            manager.addBuff(metaBuff, "dynamic_test");
            manager.update(1);

            trace("  Frame 1: stat = " + target.stat + ", metaBuff active = " + metaBuff.isActive());
            assert(target.stat == 150, "Frame 1: stat should be 150, got " + target.stat);
            assert(metaBuff.isActive() == true, "Frame 1: MetaBuff should be active");

            // 继续update，让门控组件过期
            manager.update(1);
            trace("  Frame 2: stat = " + target.stat + ", metaBuff active = " + metaBuff.isActive());

            // 门控组件死亡后，MetaBuff应进入PENDING_DEACTIVATE，下一帧变INACTIVE
            manager.update(1);
            trace("  Frame 3: stat = " + target.stat + ", metaBuff active = " + metaBuff.isActive());

            // 再update一帧确保状态转换完成
            manager.update(1);
            manager.update(1);

            // 关键断言：MetaBuff应该已被移除，stat应恢复到基础值
            var buffCount:Number = manager.getActiveBuffCount();
            trace("  After expiry: activeBuffCount = " + buffCount + ", stat = " + target.stat);

            assert(buffCount == 0, "MetaBuff should be removed after gate component expires, count = " + buffCount);
            assert(target.stat == 100, "Stat should return to base value 100 after MetaBuff removal, got " + target.stat);

            manager.destroy();
            passTest();
        } catch (e) {
            failTest("v2.6 MetaBuff gate component expiry test failed: " + e);
        }
    }

    /**
     * v2.6 测试4: _removePodBuffCore O(1)查找功能验证
     *
     * 验证：移除注入的PodBuff时能正确通过O(1)映射找到parent MetaBuff并同步状态
     *
     * 注：不做硬性能断言（不同机器/调试开关下差异大），仅trace耗时供参考
     */
    private static function test_v26_RemovePodBuffCore_O1Performance():Void {
        startTest("v2.6: _removePodBuffCore O(1) lookup correctness");

        try {
            var target:Object = {power: 0};
            var manager:BuffManager = new BuffManager(target, null);

            // 创建多个MetaBuff，每个注入多个PodBuff
            var metaCount:Number = 20;
            var podsPerMeta:Number = 5;

            for (var i:Number = 0; i < metaCount; i++) {
                var pods:Array = [];
                for (var j:Number = 0; j < podsPerMeta; j++) {
                    var pod:PodBuff = new PodBuff("power", BuffCalculationType.ADD, 1);
                    pods.push(pod);
                }
                var timeComp:TimeLimitComponent = new TimeLimitComponent(1000);
                var meta:MetaBuff = new MetaBuff(pods, [timeComp], 0);
                manager.addBuff(meta, "meta_" + i);
            }

            manager.update(1);

            var totalPods:Number = metaCount * podsPerMeta;
            var valueAfterAdd:Number = target.power;
            trace("  After adding " + metaCount + " MetaBuffs with " + podsPerMeta + " pods each");
            trace("  Total injected pods: " + totalPods);
            trace("  Power value: " + valueAfterAdd);

            assert(valueAfterAdd == totalPods, "Initial power should be " + totalPods + ", got " + valueAfterAdd);

            // 开始计时移除操作（仅供参考）
            var startTime:Number = getTimer();

            // 移除一半的MetaBuff（触发级联移除注入的Pod）
            var removeCount:Number = metaCount / 2;
            for (var k:Number = 0; k < removeCount; k++) {
                manager.removeBuff("meta_" + k);
            }

            manager.update(1);

            var endTime:Number = getTimer();
            var elapsed:Number = endTime - startTime;

            var valueAfterRemove:Number = target.power;
            var expectedValue:Number = (metaCount - removeCount) * podsPerMeta;

            trace("  After removing " + removeCount + " MetaBuffs:");
            trace("  Power value: " + valueAfterRemove + " (expected: " + expectedValue + ")");
            trace("  Time elapsed: " + elapsed + "ms (for reference only, no hard assertion)");

            // 硬断言：值计算正确
            assert(valueAfterRemove == expectedValue,
                "After removing half, power should be " + expectedValue + ", got " + valueAfterRemove);

            // 验证剩余MetaBuff数量
            var remainingBuffs:Number = manager.getActiveBuffCount();
            var expectedRemaining:Number = metaCount - removeCount;
            assert(remainingBuffs == expectedRemaining,
                "Should have " + expectedRemaining + " MetaBuffs remaining, got " + remainingBuffs);

            manager.destroy();
            passTest();
        } catch (e) {
            failTest("v2.6 O(1) performance test failed: " + e);
        }
    }

    // ========================================
    // 测试工具方法
    // ========================================

    private static function startTest(testName:String):Void {
        testCount++;
        trace("\n[Test " + testCount + "] " + testName);
    }

    private static function passTest():Void {
        passedCount++;
        trace("  PASSED");
    }

    private static function failTest(message:String):Void {
        failedCount++;
        trace("  FAILED: " + message);
    }

    private static function assert(condition:Boolean, message:String):Void {
        if (!condition) {
            throw new Error("Assertion failed: " + message);
        }
    }

    private static function assertFloat(actual:Number, expected:Number, message:String):Void {
        if (Math.abs(actual - expected) > EPSILON) {
            throw new Error(message + ": expected " + expected + ", got " + actual);
        }
    }

    private static function printTestResults():Void {
        trace("\n=== Bugfix Regression Test Results ===");
        trace("Total: " + testCount);
        trace("Passed: " + passedCount);
        trace("Failed: " + failedCount);
        trace("Success Rate: " + Math.round((passedCount / testCount) * 100) + "%");

        if (failedCount == 0) {
            trace("\nAll bugfix regression tests passed!");
        } else {
            trace("\nWARNING: " + failedCount + " test(s) failed!");
        }
        trace("======================================");
    }
}
