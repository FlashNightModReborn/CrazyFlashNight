// Tier2ComponentTest.as - Tier 2组件测试套件
import org.flashNight.arki.component.Buff.*;
import org.flashNight.arki.component.Buff.Component.*;
import org.flashNight.neur.Event.EventDispatcher;

/**
 * Tier 2 组件测试套件
 *
 * 测试组件：
 * 1. TimeLimitComponent - 时间限制（门控）
 * 2. TickComponent - 周期触发（门控）
 * 3. EventListenerComponent - 事件监听（非门控）
 * 4. DelayedTriggerComponent - 延迟触发（可配置门控）
 *
 * 组件覆盖情况汇总：
 * ┌──────────────────────────────┬─────────┬──────────┐
 * │ 组件                          │ 门控    │ 测试套件  │
 * ├──────────────────────────────┼─────────┼──────────┤
 * │ TimeLimitComponent           │ ✓       │ Tier2    │
 * │ TickComponent                │ ✓       │ Tier2    │
 * │ EventListenerComponent       │ ✗       │ Tier2    │
 * │ DelayedTriggerComponent      │ 可配置   │ Tier2    │
 * │ StackLimitComponent          │ ✓       │ Tier1    │
 * │ CooldownComponent            │ ✓       │ Tier1    │
 * │ ConditionComponent           │ ✓       │ Tier1    │
 * └──────────────────────────────┴─────────┴──────────┘
 *
 * @author FlashNight
 */
class org.flashNight.arki.component.Buff.test.Tier2ComponentTest {

    private static var testCount:Number = 0;
    private static var passedCount:Number = 0;
    private static var failedCount:Number = 0;

    /**
     * 运行所有Tier2测试
     */
    public static function runAllTests():Void {
        trace("=== Tier 2 Component Test Suite ===\n");

        testCount = 0;
        passedCount = 0;
        failedCount = 0;

        trace("--- TimeLimitComponent Tests ---");
        testTimeLimitBasic();
        testTimeLimitExpiration();
        testTimeLimitWithMetaBuff();

        trace("\n--- TickComponent Tests ---");
        testTickBasic();
        testTickMultipleTriggers();
        testTickMaxLimit();
        testTickTriggerOnAttach();
        testTickWithMetaBuff();

        trace("\n--- EventListenerComponent Tests (Real EventDispatcher) ---");
        testEventListenerBasic();
        testEventListenerFilter();
        testEventListenerStateTransitions();
        testEventListenerDuration();
        testEventListenerManualControl();
        testEventListenerWithMetaBuff();

        trace("\n--- DelayedTriggerComponent Tests ---");
        testDelayedTriggerBasic();
        testDelayedTriggerTiming();
        testDelayedTriggerGate();
        testDelayedTriggerNonGate();
        testDelayedTriggerReset();
        testDelayedTriggerNow();
        testDelayedTriggerWithMetaBuff();

        printTestResults();
    }

    // ==================== Real EventDispatcher ====================

    /**
     * 创建真实的 EventDispatcher 实例
     * 使用游戏中实际的事件系统进行测试
     */
    private static function createRealDispatcher():EventDispatcher {
        return new EventDispatcher();
    }

    // ==================== TimeLimitComponent Tests ====================

    private static function testTimeLimitBasic():Void {
        startTest("TimeLimit Basic Operations");

        try {
            var timeComp:TimeLimitComponent = new TimeLimitComponent(100);

            // 应该是门控组件
            assert(timeComp.isLifeGate() == true, "TimeLimitComponent should be a life gate");

            // 更新50帧，应该存活
            var alive:Boolean = timeComp.update(null, 50);
            assert(alive == true, "Should be alive after 50 frames");

            // 再更新49帧，应该存活
            alive = timeComp.update(null, 49);
            assert(alive == true, "Should be alive after 99 frames");

            trace("  ✓ Basic: 100 frames limit, alive at 50, alive at 99");

            passTest();
        } catch (e) {
            failTest("TimeLimit basic test failed: " + e.message);
        }
    }

    private static function testTimeLimitExpiration():Void {
        startTest("TimeLimit Expiration");

        try {
            var timeComp:TimeLimitComponent = new TimeLimitComponent(60);

            // 更新60帧，应该到期
            var alive:Boolean = timeComp.update(null, 60);
            assert(alive == false, "Should expire after exactly 60 frames");

            // 重新测试超过时间
            var timeComp2:TimeLimitComponent = new TimeLimitComponent(30);
            alive = timeComp2.update(null, 50);
            assert(alive == false, "Should expire when delta exceeds remaining");

            trace("  ✓ Expiration: 60 frames → expire, 30 frames + 50 delta → expire");

            passTest();
        } catch (e) {
            failTest("TimeLimit expiration test failed: " + e.message);
        }
    }

    private static function testTimeLimitWithMetaBuff():Void {
        startTest("TimeLimit with MetaBuff");

        try {
            var mockTarget:Object = {atk: 100};
            var manager:BuffManager = new BuffManager(mockTarget, null);

            // 创建60帧持续的攻击Buff
            var atkBuff:PodBuff = new PodBuff("atk", BuffCalculationType.ADD, 50);
            var timeComp:TimeLimitComponent = new TimeLimitComponent(60);
            var metaBuff:MetaBuff = new MetaBuff([atkBuff], [timeComp], 0);

            manager.addBuff(metaBuff, "timed_atk");
            manager.update(1);

            // 初始应该生效
            assert(mockTarget.atk == 150, "Initial atk should be 150, got " + mockTarget.atk);

            // 更新30帧，应该仍然生效
            manager.update(30);
            assert(mockTarget.atk == 150, "Atk should still be 150 after 30 frames");

            // 再更新30帧，应该到期移除
            manager.update(30);
            assert(mockTarget.atk == 100, "Atk should be 100 after expiration, got " + mockTarget.atk);

            trace("  ✓ MetaBuff: atk=150 during buff, atk=100 after 60 frames");

            manager.destroy();
            passTest();
        } catch (e) {
            failTest("TimeLimit+MetaBuff test failed: " + e.message);
        }
    }

    // ==================== TickComponent Tests ====================

    private static function testTickBasic():Void {
        startTest("Tick Basic Operations");

        try {
            var tickCount:Number = 0;
            var tickComp:TickComponent = new TickComponent(
                30,  // 30帧间隔
                function(host:IBuff, count:Number, ctx:Object):Void {
                    tickCount = count;
                },
                0,   // 无限次
                null,
                false
            );

            // 应该是门控组件
            assert(tickComp.isLifeGate() == true, "TickComponent should be a life gate");
            assert(tickComp.getInterval() == 30, "Interval should be 30");
            assert(tickComp.getTickCount() == 0, "Initial tick count should be 0");

            // 更新29帧，不应触发
            var alive:Boolean = tickComp.update(null, 29);
            assert(alive == true, "Should be alive");
            assert(tickCount == 0, "Should not tick yet");

            // 再更新1帧，应触发
            alive = tickComp.update(null, 1);
            assert(alive == true, "Should still be alive");
            assert(tickCount == 1, "Should have ticked once");

            trace("  ✓ Basic: interval=30, tick at 30 frames");

            passTest();
        } catch (e) {
            failTest("Tick basic test failed: " + e.message);
        }
    }

    private static function testTickMultipleTriggers():Void {
        startTest("Tick Multiple Triggers");

        try {
            var tickCount:Number = 0;
            var tickComp:TickComponent = new TickComponent(
                10,  // 10帧间隔
                function(host:IBuff, count:Number, ctx:Object):Void {
                    tickCount = count;
                },
                0,
                null,
                false
            );

            // 一次更新触发多次（大deltaFrames）
            // 35帧 = 3次tick (10,20,30) + 5帧剩余
            tickComp.update(null, 35);
            assert(tickCount == 3, "Should have ticked 3 times, got " + tickCount);
            assert(tickComp.getTickCount() == 3, "getTickCount should be 3");

            // 继续更新15帧：剩余5 + 15 = 20帧 = 2次tick (10,20)
            // 总计 3 + 2 = 5次
            tickComp.update(null, 15);
            assert(tickCount == 5, "Should have ticked 5 times total, got " + tickCount);

            trace("  ✓ Multiple: 35 frames → 3 ticks, +15 frames → 5 ticks total");

            passTest();
        } catch (e) {
            failTest("Tick multiple test failed: " + e.message);
        }
    }

    private static function testTickMaxLimit():Void {
        startTest("Tick Max Limit");

        try {
            var tickCount:Number = 0;
            var tickComp:TickComponent = new TickComponent(
                10,
                function(host:IBuff, count:Number, ctx:Object):Void {
                    tickCount = count;
                },
                3,   // 最多3次
                null,
                false
            );

            assert(tickComp.getMaxTicks() == 3, "Max ticks should be 3");
            assert(tickComp.getRemainingTicks() == 3, "Remaining should be 3");

            // 触发2次
            var alive:Boolean = tickComp.update(null, 25);
            assert(alive == true, "Should be alive after 2 ticks");
            assert(tickComp.getRemainingTicks() == 1, "Remaining should be 1");

            // 触发第3次，应结束
            alive = tickComp.update(null, 10);
            assert(alive == false, "Should end after max ticks");
            assert(tickCount == 3, "Should have ticked exactly 3 times");

            trace("  ✓ MaxLimit: 3 max ticks, ends after 3rd tick");

            passTest();
        } catch (e) {
            failTest("Tick max limit test failed: " + e.message);
        }
    }

    private static function testTickTriggerOnAttach():Void {
        startTest("Tick Trigger On Attach");

        try {
            var tickCount:Number = 0;
            var tickComp:TickComponent = new TickComponent(
                30,
                function(host:IBuff, count:Number, ctx:Object):Void {
                    tickCount = count;
                },
                0,
                null,
                true  // 挂载时触发
            );

            // 调用onAttach
            tickComp.onAttach(null);
            assert(tickCount == 1, "Should tick immediately on attach");
            assert(tickComp.getTickCount() == 1, "Tick count should be 1");

            trace("  ✓ TriggerOnAttach: immediately ticks on attach");

            passTest();
        } catch (e) {
            failTest("Tick trigger on attach test failed: " + e.message);
        }
    }

    private static function testTickWithMetaBuff():Void {
        startTest("Tick with MetaBuff (DoT Simulation)");

        try {
            var mockTarget:Object = {hp: 100};
            var manager:BuffManager = new BuffManager(mockTarget, null);

            // 模拟DoT：每30帧扣10HP，共3次
            var dotDamage:Number = 10;
            var tickComp:TickComponent = new TickComponent(
                30,
                function(host:IBuff, count:Number, ctx:Object):Void {
                    ctx.target.hp -= ctx.damage;
                },
                3,
                {target: mockTarget, damage: dotDamage},
                false
            );
            var metaBuff:MetaBuff = new MetaBuff([], [tickComp], 0);

            manager.addBuff(metaBuff, "poison");

            // 初始HP不变（update(1)不足以触发第一次tick）
            manager.update(1);
            assert(mockTarget.hp == 100, "HP should be 100 initially");

            // 累计30帧：第1次DoT (1+29=30)
            manager.update(29);
            assert(mockTarget.hp == 90, "HP should be 90 after first tick, got " + mockTarget.hp);

            // 累计60帧：第2次DoT
            manager.update(30);
            assert(mockTarget.hp == 80, "HP should be 80 after second tick, got " + mockTarget.hp);

            // 累计90帧：第3次DoT，组件返回false
            manager.update(30);
            assert(mockTarget.hp == 70, "HP should be 70 after third tick, got " + mockTarget.hp);

            // 再update一次让BuffManager处理移除
            manager.update(1);

            // Buff应已移除
            var debugInfo:Object = manager.getDebugInfo();
            assert(debugInfo.metaBuffs == 0, "MetaBuff should be removed after max ticks, got " + debugInfo.metaBuffs);

            trace("  ✓ DoT: 100 → 90 → 80 → 70, buff removed");

            manager.destroy();
            passTest();
        } catch (e) {
            failTest("Tick+MetaBuff test failed: " + e.message);
        }
    }

    // ==================== EventListenerComponent Tests ====================

    private static function testEventListenerBasic():Void {
        startTest("EventListener Basic Operations (Real EventDispatcher)");

        try {
            var dispatcher:EventDispatcher = createRealDispatcher();
            var eventComp:EventListenerComponent = new EventListenerComponent({
                dispatcher: dispatcher,
                eventName: "TestEvent",
                duration: 60
            });

            // 应该是非门控组件
            assert(eventComp.isLifeGate() == false, "EventListenerComponent should NOT be a life gate");
            assert(eventComp.isActive() == false, "Should start in IDLE state");
            assert(eventComp.getDuration() == 60, "Duration should be 60");

            // 挂载组件（订阅事件）
            eventComp.onAttach(null);

            // 卸载组件（取消订阅）
            eventComp.onDetach();

            // 销毁dispatcher
            dispatcher.destroy();

            trace("  ✓ Basic: non-gate, IDLE state, subscribe/unsubscribe works");

            passTest();
        } catch (e) {
            failTest("EventListener basic test failed: " + e.message);
        }
    }

    private static function testEventListenerFilter():Void {
        startTest("EventListener Filter (Real EventDispatcher)");

        try {
            var dispatcher:EventDispatcher = createRealDispatcher();
            var activateCount:Number = 0;

            var eventComp:EventListenerComponent = new EventListenerComponent({
                dispatcher: dispatcher,
                eventName: "TestEvent",
                filter: function(arg:String):Boolean {
                    return arg == "match";
                },
                duration: 0,  // 永久激活
                onActivate: function():Void {
                    activateCount++;
                }
            });

            eventComp.onAttach(null);

            // 发布不匹配的事件
            dispatcher.publish("TestEvent", "nomatch");
            assert(eventComp.isActive() == false, "Should not activate with non-matching arg");
            assert(activateCount == 0, "Activate should not be called");

            // 发布匹配的事件
            dispatcher.publish("TestEvent", "match");
            assert(eventComp.isActive() == true, "Should activate with matching arg");
            assert(activateCount == 1, "Activate should be called once");

            trace("  ✓ Filter: 'nomatch' rejected, 'match' accepted");

            eventComp.onDetach();
            dispatcher.destroy();
            passTest();
        } catch (e) {
            failTest("EventListener filter test failed: " + e.message);
        }
    }

    private static function testEventListenerStateTransitions():Void {
        startTest("EventListener State Transitions (Real EventDispatcher)");

        try {
            var dispatcher:EventDispatcher = createRealDispatcher();
            var activateCount:Number = 0;
            var deactivateCount:Number = 0;
            var refreshCount:Number = 0;

            var eventComp:EventListenerComponent = new EventListenerComponent({
                dispatcher: dispatcher,
                eventName: "Skill",
                duration: 60,
                onActivate: function():Void { activateCount++; },
                onDeactivate: function():Void { deactivateCount++; },
                onRefresh: function():Void { refreshCount++; }
            });

            eventComp.onAttach(null);

            // 初始状态: IDLE
            assert(eventComp.isActive() == false, "Initial state should be IDLE");

            // 触发事件: IDLE → ACTIVE
            dispatcher.publish("Skill");
            assert(eventComp.isActive() == true, "Should be ACTIVE after event");
            assert(activateCount == 1, "onActivate should be called");
            assert(eventComp.getRemaining() == 60, "Remaining should be 60");

            // 再次触发: ACTIVE → refresh
            dispatcher.publish("Skill");
            assert(eventComp.isActive() == true, "Should still be ACTIVE");
            assert(refreshCount == 1, "onRefresh should be called");
            assert(eventComp.getRemaining() == 60, "Remaining should reset to 60");

            // 时间流逝到期: ACTIVE → IDLE
            eventComp.update(null, 60);
            assert(eventComp.isActive() == false, "Should be IDLE after duration expires");
            assert(deactivateCount == 1, "onDeactivate should be called");

            trace("  ✓ Transitions: IDLE→ACTIVE→refresh→IDLE (duration expire)");

            eventComp.onDetach();
            dispatcher.destroy();
            passTest();
        } catch (e) {
            failTest("EventListener state transitions test failed: " + e.message);
        }
    }

    private static function testEventListenerDuration():Void {
        startTest("EventListener Duration (Permanent vs Timed) (Real EventDispatcher)");

        try {
            var dispatcher:EventDispatcher = createRealDispatcher();
            var deactivateCount:Number = 0;

            // duration=0 永久激活
            var eventComp:EventListenerComponent = new EventListenerComponent({
                dispatcher: dispatcher,
                eventName: "Skill",
                duration: 0,  // 永久
                onDeactivate: function():Void { deactivateCount++; }
            });

            eventComp.onAttach(null);
            dispatcher.publish("Skill");

            assert(eventComp.isActive() == true, "Should be ACTIVE");

            // 大量时间流逝，不应自动停用
            eventComp.update(null, 10000);
            assert(eventComp.isActive() == true, "Should still be ACTIVE (permanent)");
            assert(deactivateCount == 0, "onDeactivate should not be called");

            // 必须手动停用
            eventComp.deactivate();
            assert(eventComp.isActive() == false, "Should be IDLE after manual deactivate");
            assert(deactivateCount == 1, "onDeactivate should be called on manual deactivate");

            trace("  ✓ Duration: 0=permanent, must manually deactivate");

            eventComp.onDetach();
            dispatcher.destroy();
            passTest();
        } catch (e) {
            failTest("EventListener duration test failed: " + e.message);
        }
    }

    private static function testEventListenerManualControl():Void {
        startTest("EventListener Manual Control (Real EventDispatcher)");

        try {
            var dispatcher:EventDispatcher = createRealDispatcher();
            var activateCount:Number = 0;
            var deactivateCount:Number = 0;

            var eventComp:EventListenerComponent = new EventListenerComponent({
                dispatcher: dispatcher,
                eventName: "Skill",
                duration: 100,
                onActivate: function():Void { activateCount++; },
                onDeactivate: function():Void { deactivateCount++; }
            });

            eventComp.onAttach(null);

            // 手动激活
            eventComp.activate();
            assert(eventComp.isActive() == true, "Should be ACTIVE after manual activate");
            assert(activateCount == 1, "onActivate should be called");

            // 重复手动激活，不应重复触发
            eventComp.activate();
            assert(activateCount == 1, "onActivate should not be called again");

            // 手动停用
            eventComp.deactivate();
            assert(eventComp.isActive() == false, "Should be IDLE after manual deactivate");
            assert(deactivateCount == 1, "onDeactivate should be called");

            // 重复手动停用，不应重复触发
            eventComp.deactivate();
            assert(deactivateCount == 1, "onDeactivate should not be called again");

            // 运行时修改duration
            eventComp.setDuration(200);
            assert(eventComp.getDuration() == 200, "Duration should be updated to 200");

            trace("  ✓ Manual: activate/deactivate, setDuration works");

            eventComp.onDetach();
            dispatcher.destroy();
            passTest();
        } catch (e) {
            failTest("EventListener manual control test failed: " + e.message);
        }
    }

    private static function testEventListenerWithMetaBuff():Void {
        startTest("EventListener with MetaBuff (Controller Pattern) (Real EventDispatcher)");

        try {
            var mockTarget:Object = {atk: 100};
            var dispatcher:EventDispatcher = createRealDispatcher();
            var manager:BuffManager = new BuffManager(mockTarget, null);

            var isBuffActive:Boolean = false;

            // 创建事件监听组件
            var eventComp:EventListenerComponent = new EventListenerComponent({
                dispatcher: dispatcher,
                eventName: "BurstSkill",
                duration: 60,
                onActivate: function():Void {
                    isBuffActive = true;
                },
                onDeactivate: function():Void {
                    isBuffActive = false;
                }
            });

            // 控制器MetaBuff（永久，无PodBuff）
            var controllerMeta:MetaBuff = new MetaBuff([], [eventComp], 0);
            manager.addBuff(controllerMeta, "controller");
            manager.update(1);

            // 验证初始状态
            assert(eventComp.isActive() == false, "Should start IDLE");

            // 发布事件激活
            dispatcher.publish("BurstSkill");
            assert(eventComp.isActive() == true, "Should be ACTIVE after event");
            assert(isBuffActive == true, "Callback should set isBuffActive=true");

            // 时间流逝
            manager.update(30);
            assert(eventComp.isActive() == true, "Should still be ACTIVE");

            // 到期停用
            manager.update(30);
            assert(eventComp.isActive() == false, "Should be IDLE after duration");
            assert(isBuffActive == false, "Callback should set isBuffActive=false");

            // 控制器本身应该仍然存在（非门控）
            var debugInfo:Object = manager.getDebugInfo();
            assert(debugInfo.metaBuffs == 1, "Controller MetaBuff should still exist");

            trace("  ✓ Controller Pattern: event→ACTIVE→duration→IDLE, controller persists");

            manager.destroy();
            dispatcher.destroy();
            passTest();
        } catch (e) {
            failTest("EventListener+MetaBuff test failed: " + e.message);
        }
    }

    // ==================== DelayedTriggerComponent Tests ====================

    private static function testDelayedTriggerBasic():Void {
        startTest("DelayedTrigger Basic Operations");

        try {
            var triggerCount:Number = 0;
            var delayComp:DelayedTriggerComponent = new DelayedTriggerComponent(
                60,  // 60帧延迟
                function(host:IBuff, ctx:Object):Void {
                    triggerCount++;
                },
                null,
                true  // 门控
            );

            // 验证初始状态
            assert(delayComp.getDelay() == 60, "Delay should be 60");
            assert(delayComp.getRemaining() == 60, "Remaining should be 60");
            assert(delayComp.hasTriggered() == false, "Should not be triggered initially");
            assert(delayComp.getProgress() == 0, "Progress should be 0");
            assert(delayComp.isLifeGate() == true, "Should be a life gate by default");

            trace("  ✓ Basic: delay=60, remaining=60, not triggered, progress=0");

            passTest();
        } catch (e) {
            failTest("DelayedTrigger basic test failed: " + e.message);
        }
    }

    private static function testDelayedTriggerTiming():Void {
        startTest("DelayedTrigger Timing");

        try {
            var triggerCount:Number = 0;
            var delayComp:DelayedTriggerComponent = new DelayedTriggerComponent(
                60,
                function(host:IBuff, ctx:Object):Void {
                    triggerCount++;
                },
                null,
                true
            );

            // 更新30帧，不应触发
            var alive:Boolean = delayComp.update(null, 30);
            assert(alive == true, "Should be alive after 30 frames");
            assert(triggerCount == 0, "Should not trigger yet");
            assert(delayComp.getRemaining() == 30, "Remaining should be 30");
            assert(delayComp.getProgress() == 0.5, "Progress should be 0.5");

            // 再更新29帧，仍不应触发
            alive = delayComp.update(null, 29);
            assert(alive == true, "Should be alive after 59 frames");
            assert(triggerCount == 0, "Should still not trigger");

            // 再更新1帧，应该触发
            alive = delayComp.update(null, 1);
            assert(alive == false, "Should return false (gate)");
            assert(triggerCount == 1, "Should trigger exactly once");
            assert(delayComp.hasTriggered() == true, "Should be marked as triggered");

            // 再次update不应重复触发
            alive = delayComp.update(null, 100);
            assert(triggerCount == 1, "Should not trigger again");

            trace("  ✓ Timing: 30→alive, 59→alive, 60→trigger, no re-trigger");

            passTest();
        } catch (e) {
            failTest("DelayedTrigger timing test failed: " + e.message);
        }
    }

    private static function testDelayedTriggerGate():Void {
        startTest("DelayedTrigger Gate Behavior (isGate=true)");

        try {
            var triggered:Boolean = false;
            var delayComp:DelayedTriggerComponent = new DelayedTriggerComponent(
                30,
                function(host:IBuff, ctx:Object):Void {
                    triggered = true;
                },
                null,
                true  // 门控
            );

            assert(delayComp.isLifeGate() == true, "Should be a life gate");

            // 触发时应返回false终结buff
            var alive:Boolean = delayComp.update(null, 30);
            assert(alive == false, "Gate component should return false on trigger");
            assert(triggered == true, "Callback should be executed");

            // 已触发后继续返回false
            alive = delayComp.update(null, 1);
            assert(alive == false, "Should continue returning false after trigger");

            trace("  ✓ Gate: isLifeGate=true, returns false on trigger");

            passTest();
        } catch (e) {
            failTest("DelayedTrigger gate test failed: " + e.message);
        }
    }

    private static function testDelayedTriggerNonGate():Void {
        startTest("DelayedTrigger Non-Gate Behavior (isGate=false)");

        try {
            var triggered:Boolean = false;
            var delayComp:DelayedTriggerComponent = new DelayedTriggerComponent(
                30,
                function(host:IBuff, ctx:Object):Void {
                    triggered = true;
                },
                null,
                false  // 非门控
            );

            assert(delayComp.isLifeGate() == false, "Should not be a life gate");

            // 触发时应返回true继续存活
            var alive:Boolean = delayComp.update(null, 30);
            assert(alive == true, "Non-gate component should return true on trigger");
            assert(triggered == true, "Callback should be executed");

            // 已触发后继续返回true
            alive = delayComp.update(null, 100);
            assert(alive == true, "Should continue returning true after trigger");

            trace("  ✓ Non-Gate: isLifeGate=false, returns true on trigger");

            passTest();
        } catch (e) {
            failTest("DelayedTrigger non-gate test failed: " + e.message);
        }
    }

    private static function testDelayedTriggerReset():Void {
        startTest("DelayedTrigger Reset");

        try {
            var triggerCount:Number = 0;
            var delayComp:DelayedTriggerComponent = new DelayedTriggerComponent(
                30,
                function(host:IBuff, ctx:Object):Void {
                    triggerCount++;
                },
                null,
                false  // 非门控，方便测试reset
            );

            // 第一次触发
            delayComp.update(null, 30);
            assert(triggerCount == 1, "Should trigger once");
            assert(delayComp.hasTriggered() == true, "Should be triggered");

            // 重置
            delayComp.reset();
            assert(delayComp.hasTriggered() == false, "Should not be triggered after reset");
            assert(delayComp.getRemaining() == 30, "Remaining should reset to delay");

            // 可以再次触发
            delayComp.update(null, 30);
            assert(triggerCount == 2, "Should trigger again after reset");

            trace("  ✓ Reset: triggered→reset→triggered again");

            passTest();
        } catch (e) {
            failTest("DelayedTrigger reset test failed: " + e.message);
        }
    }

    private static function testDelayedTriggerNow():Void {
        startTest("DelayedTrigger triggerNow");

        try {
            var triggerCount:Number = 0;
            var delayComp:DelayedTriggerComponent = new DelayedTriggerComponent(
                100,  // 长延迟
                function(host:IBuff, ctx:Object):Void {
                    triggerCount++;
                },
                null,
                true
            );

            // 只过了10帧
            delayComp.update(null, 10);
            assert(triggerCount == 0, "Should not trigger yet");
            assert(delayComp.getRemaining() == 90, "Remaining should be 90");

            // 立即触发
            var success:Boolean = delayComp.triggerNow(null);
            assert(success == true, "triggerNow should return true");
            assert(triggerCount == 1, "Should trigger immediately");
            assert(delayComp.hasTriggered() == true, "Should be marked triggered");
            assert(delayComp.getRemaining() == 0, "Remaining should be 0");

            // 再次调用triggerNow应返回false
            success = delayComp.triggerNow(null);
            assert(success == false, "triggerNow should return false when already triggered");
            assert(triggerCount == 1, "Should not trigger again");

            trace("  ✓ triggerNow: immediate trigger, no re-trigger");

            passTest();
        } catch (e) {
            failTest("DelayedTrigger triggerNow test failed: " + e.message);
        }
    }

    private static function testDelayedTriggerWithMetaBuff():Void {
        startTest("DelayedTrigger with MetaBuff (Delayed Explosion)");

        try {
            var mockTarget:Object = {hp: 100};
            var manager:BuffManager = new BuffManager(mockTarget, null);

            // 模拟延迟爆炸：60帧后造成50伤害
            var delayComp:DelayedTriggerComponent = new DelayedTriggerComponent(
                60,
                function(host:IBuff, ctx:Object):Void {
                    ctx.target.hp -= ctx.damage;
                },
                {target: mockTarget, damage: 50},
                true  // 爆炸后移除buff
            );

            var metaBuff:MetaBuff = new MetaBuff([], [delayComp], 0);
            manager.addBuff(metaBuff, "delayed_bomb");

            // 初始HP不变（update(1)后remaining=59）
            manager.update(1);
            assert(mockTarget.hp == 100, "HP should be 100 initially");

            // 30帧后HP仍不变（累计31帧，remaining=29）
            manager.update(30);
            assert(mockTarget.hp == 100, "HP should still be 100 after 31 frames");

            // 再28帧（累计59帧，remaining=1）仍未爆炸
            manager.update(28);
            assert(mockTarget.hp == 100, "HP should be 100 before explosion (59 frames)");

            // 再1帧（累计60帧）触发爆炸
            manager.update(1);
            assert(mockTarget.hp == 50, "HP should be 50 after explosion, got " + mockTarget.hp);

            // Buff应已移除
            manager.update(1);
            var debugInfo:Object = manager.getDebugInfo();
            assert(debugInfo.metaBuffs == 0, "MetaBuff should be removed after explosion");

            trace("  ✓ Delayed Explosion: HP=100→100→50, buff removed");

            manager.destroy();
            passTest();
        } catch (e) {
            failTest("DelayedTrigger+MetaBuff test failed: " + e.message);
        }
    }

    // ==================== 工具方法 ====================

    private static function startTest(testName:String):Void {
        testCount++;
        trace("🧪 Test " + testCount + ": " + testName);
    }

    private static function passTest():Void {
        passedCount++;
        trace("  ✅ PASSED\n");
    }

    private static function failTest(message:String):Void {
        failedCount++;
        trace("  ❌ FAILED: " + message + "\n");
    }

    private static function assert(condition:Boolean, message:String):Void {
        if (!condition) {
            throw new Error("Assertion failed: " + message);
        }
    }

    private static function printTestResults():Void {
        trace("\n=== Tier 2 Component Test Results ===");
        trace("📊 Total tests: " + testCount);
        trace("✅ Passed: " + passedCount);
        trace("❌ Failed: " + failedCount);
        trace("📈 Success rate: " + Math.round((passedCount / testCount) * 100) + "%");

        if (failedCount == 0) {
            trace("🎉 All Tier 2 component tests passed!");
        } else {
            trace("⚠️  " + failedCount + " test(s) failed.");
        }
        trace("=========================================");
    }
}
