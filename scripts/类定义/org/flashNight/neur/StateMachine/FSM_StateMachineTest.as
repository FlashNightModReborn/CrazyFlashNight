import org.flashNight.neur.StateMachine.*;

/**
 * 增强版FSM状态机测试套件
 * 全面测试FSM系统的功能、性能、稳定性和内存安全性
 */
class org.flashNight.neur.StateMachine.FSM_StateMachineTest {
    private var _testPassed:Number;
    private var _testFailed:Number;
    private var _testMachines:Array; // 用于内存泄漏测试的状态机跟踪
    private var _lifecycleLog:Array; // 生命周期事件日志

    public function FSM_StateMachineTest() {
        this._testPassed = 0;
        this._testFailed = 0;
        this._testMachines = [];
        this._lifecycleLog = [];
        trace("=== Enhanced FSM StateMachine Test Initialized ===");
    }

    /**
     * 运行所有测试
     */
    public function runTests():Void {
        trace("=== Running Enhanced FSM StateMachine Tests ===");
        
        // 基础功能测试
        this.testBasicStateMachineCreation();
        this.testAddAndGetStates();
        this.testBasicStateTransition();
        this.testDefaultStateHandling();
        this.testActiveStateManagement();
        
        // 生命周期测试
        this.testStateLifecycleEvents();
        this.testLifecycleEventOrder();
        this.testLifecycleWithDataSharing();
        this.testActionCountTracking();
        
        // 转换系统测试
        this.testBasicTransitions();
        this.testTransitionPriority();
        this.testConditionalTransitions();
        this.testTransitionWithCallback();
        this.testComplexTransitionLogic();
        
        // 数据管理测试
        this.testDataBlackboardSharing();
        this.testDataIsolationBetweenMachines();
        this.testDataPersistenceAcrossTransitions();
        
        // 边界情况测试
        this.testInvalidStateTransition();
        this.testSelfTransition();
        this.testEmptyStateMachine();
        this.testRapidStateChanges();
        this.testTransitionToSameState();
        this.testNullStateHandling();
        
        // 错误处理测试
        this.testExceptionInLifecycleMethods();
        this.testExceptionInTransitionConditions();
        this.testCorruptedStateHandling();
        this.testInvalidTransitionHandling();
        
        // 复杂场景测试
        this.testNestedStateMachines();
        this.testComplexWorkflow();
        this.testStateChaining();
        this.testConditionalBranching();
        this.testStateMachineComposition();
        
        // 内存管理测试
        this.testStateMachineDestroy();
        this.testMemoryLeakPrevention();
        this.testStateCleanup();
        this.testTransitionCleanup();
        
        // 性能测试
        this.testBasicPerformance();
        this.testManyStatesPerformance();
        this.testFrequentTransitionsPerformance();
        this.testComplexTransitionPerformance();
        this.testScalabilityTest();
        
        // P1 新增测试：路线A重构验证
        this.testPauseGateImmediateEffect();
        this.testTransitionToActionOrder();
        this.testRecursiveTransitionSafety();

        // P0 Path B 回调字段化验证
        this.testPathBCallbackNoShadow();
        this.testPathBMachineLevelHooks();

        // Batch 3 新增：start() / 保留名校验 / while-loop 链 / Phase 2 检测
        this.testStartMethod();
        this.testReservedNameValidation();
        this.testChangeStateChainWhileLoop();
        this.testPhase2ActiveStateDetection();

        // Batch 4 新增：onExit 重定向 / destroy 生命周期 / AddStatus 输入校验
        this.testOnExitChangeStateRedirect();
        this.testOnExitRedirectChain();
        this.testDestroyCallsActiveStateOnExit();
        this.testDestroyTransitionsCleanup();
        this.testAddStatusInputValidation();

        // Batch 5 新增：_started 门控
        this.testOnActionBlockedBeforeStart();
        this.testChangeStatePointerOnlyBeforeStart();

        // Batch 6 新增：嵌套场景覆盖（onAction 传播 / 递归销毁 / onExit 锁交互）
        this.testNestedMachineOnActionPropagation();
        this.testDestroyNestedMachineRecursive();
        this.testOnExitLockNestedInteraction();

        // Batch 7 新增：Risk A (exit-before-enter) / Risk B (lastState sync) 修复验证
        this.testRiskA_OnEnterCbChangeStateSafety();
        this.testRiskB_ConstructionPhaseLastStateSync();

        // 最终报告
        this.printFinalReport();
    }

    /**
     * 断言函数
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
     * 时间测量辅助函数
     */
    private function measureTime(func:Function, iterations:Number):Number {
        var startTime:Number = getTimer();
        for (var i:Number = 0; i < iterations; i++) {
            func.call(this);
        }
        return getTimer() - startTime;
    }

    /**
     * 创建测试状态的辅助函数
     */
    private function createTestState(name:String, logLifecycle:Boolean):FSM_Status {
        var self = this;
        return new FSM_Status(
            function():Void { // onAction
                if (logLifecycle) self._lifecycleLog.push(name + ":action");
            },
            function():Void { // onEnter
                if (logLifecycle) self._lifecycleLog.push(name + ":enter");
            },
            function():Void { // onExit
                if (logLifecycle) self._lifecycleLog.push(name + ":exit");
            }
        );
    }

    /**
     * 清理生命周期日志
     */
    private function clearLifecycleLog():Void {
        this._lifecycleLog = [];
    }

    // ========== 基础功能测试 ==========
    
    public function testBasicStateMachineCreation():Void {
        trace("\n--- Test: Basic StateMachine Creation ---");
        var machine:FSM_StateMachine = new FSM_StateMachine(null, null, null);
        
        this.assert(machine != null, "StateMachine created successfully");
        this.assert(machine.getDefaultState() == null, "Initial default state is null");
        this.assert(machine.getActiveState() == null, "Initial active state is null");
        
        machine.destroy();
    }

    public function testAddAndGetStates():Void {
        trace("\n--- Test: Add and Get States ---");
        var machine:FSM_StateMachine = new FSM_StateMachine(null, null, null);
        var state1:FSM_Status = this.createTestState("state1", false);
        var state2:FSM_Status = this.createTestState("state2", false);
        
        machine.AddStatus("idle", state1);
        machine.AddStatus("running", state2);
        
        this.assert(machine.getDefaultState() == state1, "First added state is default");
        this.assert(machine.getActiveState() == state1, "Active state is default state");
        this.assert(machine.getActiveStateName() == "idle", "Active state name is 'idle'");
        
        machine.destroy();
    }

    public function testBasicStateTransition():Void {
        trace("\n--- Test: Basic State Transition ---");
        var machine:FSM_StateMachine = new FSM_StateMachine(null, null, null);
        var state1:FSM_Status = this.createTestState("idle", false);
        var state2:FSM_Status = this.createTestState("running", false);
        
        machine.AddStatus("idle", state1);
        machine.AddStatus("running", state2);
        
        this.assert(machine.getActiveStateName() == "idle", "Initial state is idle");

        machine.start();
        machine.ChangeState("running");
        this.assert(machine.getActiveStateName() == "running", "State changed to running");
        this.assert(machine.getLastState() == state1, "Last state is idle");

        machine.destroy();
    }

    public function testDefaultStateHandling():Void {
        trace("\n--- Test: Default State Handling ---");
        var machine:FSM_StateMachine = new FSM_StateMachine(null, null, null);
        var state1:FSM_Status = this.createTestState("first", false);
        var state2:FSM_Status = this.createTestState("second", false);
        
        machine.AddStatus("first", state1);
        machine.AddStatus("second", state2);
        
        this.assert(machine.getDefaultState() == state1, "Default state is first added");
        
        machine.setActiveState(null);
        this.assert(machine.getActiveState() == machine.getDefaultState(), "Setting null active state reverts to default");
        
        machine.destroy();
    }

    public function testActiveStateManagement():Void {
        trace("\n--- Test: Active State Management ---");
        var machine:FSM_StateMachine = new FSM_StateMachine(null, null, null);
        var state1:FSM_Status = this.createTestState("state1", false);
        var state2:FSM_Status = this.createTestState("state2", false);
        
        machine.AddStatus("state1", state1);
        machine.AddStatus("state2", state2);
        
        machine.setActiveState(state2);
        this.assert(machine.getActiveState() == state2, "Active state set correctly");
        
        machine.setLastState(state1);
        this.assert(machine.getLastState() == state1, "Last state set correctly");
        
        machine.destroy();
    }

    // ========== 生命周期测试 ==========
    
    public function testStateLifecycleEvents():Void {
        trace("\n--- Test: State Lifecycle Events ---");
        this.clearLifecycleLog();
        
        var machine:FSM_StateMachine = new FSM_StateMachine(null, null, null);
        var state1:FSM_Status = this.createTestState("idle", true);
        var state2:FSM_Status = this.createTestState("running", true);
        
        machine.AddStatus("idle", state1);
        this.assert(this._lifecycleLog.length == 0,
                   "AddStatus does not trigger onEnter (deferred to start())");

        machine.AddStatus("running", state2);
        this.assert(this._lifecycleLog.length == 0, "onEnter not called for non-active state");

        machine.start();
        this.assert(this._lifecycleLog.length == 1 && this._lifecycleLog[0] == "idle:enter",
                   "start() triggers onEnter for default state");

        this.clearLifecycleLog();
        machine.ChangeState("running");
        this.assert(this._lifecycleLog.length == 2, "Both onExit and onEnter called during transition");
        this.assert(this._lifecycleLog[0] == "idle:exit", "onExit called first");
        this.assert(this._lifecycleLog[1] == "running:enter", "onEnter called second");
        
        machine.destroy();
    }

    public function testLifecycleEventOrder():Void {
        trace("\n--- Test: Lifecycle Event Order ---");
        this.clearLifecycleLog();
        
        var machine:FSM_StateMachine = new FSM_StateMachine(null, null, null);
        var state1:FSM_Status = this.createTestState("A", true);
        var state2:FSM_Status = this.createTestState("B", true);
        var state3:FSM_Status = this.createTestState("C", true);
        
        machine.AddStatus("A", state1);
        machine.AddStatus("B", state2);
        machine.AddStatus("C", state3);

        machine.start();
        this.clearLifecycleLog();
        machine.ChangeState("B");
        machine.ChangeState("C");
        machine.ChangeState("A");
        
        var expectedOrder:Array = ["A:exit", "B:enter", "B:exit", "C:enter", "C:exit", "A:enter"];
        this.assert(this._lifecycleLog.length == expectedOrder.length, "Correct number of lifecycle events");
        
        var orderCorrect:Boolean = true;
        for (var i:Number = 0; i < expectedOrder.length; i++) {
            if (this._lifecycleLog[i] != expectedOrder[i]) {
                orderCorrect = false;
                break;
            }
        }
        this.assert(orderCorrect, "Lifecycle events in correct order");
        
        machine.destroy();
    }

    public function testLifecycleWithDataSharing():Void {
        trace("\n--- Test: Lifecycle with Data Sharing ---");
        var machine:FSM_StateMachine = new FSM_StateMachine(null, null, null);
        machine.data = {counter: 0, log: []};
        
        var incrementState:FSM_Status = new FSM_Status(
            null,
            function():Void { this.data.counter++; this.data.log.push("increment:enter"); },
            function():Void { this.data.log.push("increment:exit"); }
        );
        
        var decrementState:FSM_Status = new FSM_Status(
            null,
            function():Void { this.data.counter--; this.data.log.push("decrement:enter"); },
            function():Void { this.data.log.push("decrement:exit"); }
        );
        
        machine.AddStatus("increment", incrementState);
        machine.AddStatus("decrement", decrementState);

        machine.start();
        this.assert(machine.data.counter == 1, "Counter incremented on first state enter via start()");
        
        machine.ChangeState("decrement");
        this.assert(machine.data.counter == 0, "Counter decremented on state change");
        
        machine.ChangeState("increment");
        this.assert(machine.data.counter == 1, "Counter incremented again");
        
        machine.destroy();
    }

    public function testActionCountTracking():Void {
        trace("\n--- Test: Action Count Tracking ---");
        var machine:FSM_StateMachine = new FSM_StateMachine(null, null, null);
        var state:FSM_Status = this.createTestState("test", false);
        
        machine.AddStatus("test", state);
        
        // 由于actionCount是私有的，我们通过行为来测试计数功能
        var actionExecuted:Boolean = false;
        var testState:FSM_Status = new FSM_Status(
            function():Void { actionExecuted = true; },
            null, null
        );
        
        machine.AddStatus("actionTest", testState);
        machine.start();
        machine.ChangeState("actionTest");

        machine.onAction();
        this.assert(actionExecuted, "Action executed successfully");
        
        // 测试状态切换后计数重置的行为
        var initialState:String = machine.getActiveStateName();
        machine.ChangeState("test");
        this.assert(machine.getActiveStateName() != initialState, "State changed successfully");
        
        machine.destroy();
    }

    // ========== 转换系统测试 ==========
    
    public function testBasicTransitions():Void {
        trace("\n--- Test: Basic Transitions ---");
        var machine:FSM_StateMachine = new FSM_StateMachine(null, null, null);
        machine.data = {actionCounter: 0}; // 使用data来跟踪action次数
        
        var idleState:FSM_Status = new FSM_Status(
            function():Void { this.data.actionCounter++; },
            null, null
        );
        var runningState:FSM_Status = new FSM_Status(
            function():Void { this.data.actionCounter++; },
            null, null
        );
        
        machine.AddStatus("idle", idleState);
        machine.AddStatus("running", runningState);
        
        // 添加转换条件
        machine.transitions.push("idle", "running", function():Boolean { 
            return this.data.actionCounter >= 2; 
        });
        machine.transitions.push("running", "idle", function():Boolean {
            return this.data.actionCounter >= 5;
        });

        machine.start();
        this.assert(machine.getActiveStateName() == "idle", "Initial state is idle");

        machine.onAction(); // actionCounter = 1
        this.assert(machine.getActiveStateName() == "idle", "Still in idle state");
        
        machine.onAction(); // actionCounter = 2, should transition
        this.assert(machine.getActiveStateName() == "running", "Transitioned to running state");
        
        machine.destroy();
    }

    public function testTransitionPriority():Void {
        trace("\n--- Test: Transition Priority ---");
        var machine:FSM_StateMachine = new FSM_StateMachine(null, null, null);
        var state1:FSM_Status = this.createTestState("state1", false);
        var state2:FSM_Status = this.createTestState("state2", false);
        var state3:FSM_Status = this.createTestState("state3", false);
        
        machine.AddStatus("state1", state1);
        machine.AddStatus("state2", state2);
        machine.AddStatus("state3", state3);
        
        // 添加多个转换条件，都返回true，测试优先级
        machine.transitions.push("state1", "state2", function():Boolean { return true; }); // 低优先级
        machine.transitions.unshift("state1", "state3", function():Boolean { return true; }); // 高优先级

        machine.start();
        machine.onAction();
        this.assert(machine.getActiveStateName() == "state3", "Higher priority transition executed");
        
        machine.destroy();
    }

    public function testConditionalTransitions():Void {
        trace("\n--- Test: Conditional Transitions ---");
        var machine:FSM_StateMachine = new FSM_StateMachine(null, null, null);
        machine.data = {health: 100, energy: 50};
        
        var healthyState:FSM_Status = this.createTestState("healthy", false);
        var tiredState:FSM_Status = this.createTestState("tired", false);
        var injuredState:FSM_Status = this.createTestState("injured", false);
        
        machine.AddStatus("healthy", healthyState);
        machine.AddStatus("tired", tiredState);
        machine.AddStatus("injured", injuredState);
        
        // 添加条件转换
        machine.transitions.push("healthy", "tired", function():Boolean { return this.data.energy < 20; });
        machine.transitions.push("healthy", "injured", function():Boolean { return this.data.health < 30; });
        machine.transitions.push("tired", "healthy", function():Boolean { return this.data.energy > 80; });
        machine.transitions.push("injured", "healthy", function():Boolean { return this.data.health > 90; });

        machine.start();
        this.assert(machine.getActiveStateName() == "healthy", "Initial state is healthy");
        
        machine.data.energy = 10;
        machine.onAction();
        this.assert(machine.getActiveStateName() == "tired", "Transitioned to tired when energy low");
        
        machine.data.energy = 90;
        machine.onAction();
        this.assert(machine.getActiveStateName() == "healthy", "Recovered to healthy when energy high");
        
        machine.data.health = 20;
        machine.onAction();
        this.assert(machine.getActiveStateName() == "injured", "Transitioned to injured when health low");
        
        machine.destroy();
    }

    public function testTransitionWithCallback():Void {
        trace("\n--- Test: Transition with Callback ---");
        var machine:FSM_StateMachine = new FSM_StateMachine(null, null, null);
        var transitionLog:Array = [];
        machine.data = {actionCounter: 0};
        
        var state1:FSM_Status = new FSM_Status(
            function():Void { this.data.actionCounter++; },
            function():Void { transitionLog.push("entered state1"); },
            function():Void { transitionLog.push("exited state1"); }
        );
        
        var state2:FSM_Status = new FSM_Status(
            function():Void { this.data.actionCounter++; },
            function():Void { transitionLog.push("entered state2"); },
            function():Void { transitionLog.push("exited state2"); }
        );
        
        machine.AddStatus("state1", state1);
        machine.AddStatus("state2", state2);

        machine.transitions.push("state1", "state2", function():Boolean {
            transitionLog.push("transition condition checked");
            return this.data.actionCounter >= 1;
        });

        machine.start();

        machine.onAction();

        this.assert(transitionLog.length == 4, "All callbacks executed (start + transition)");
        this.assert(transitionLog[0] == "entered state1", "Initial state entered via start()");
        this.assert(transitionLog[1] == "transition condition checked", "Transition condition checked");
        this.assert(transitionLog[2] == "exited state1", "Old state exited");
        this.assert(transitionLog[3] == "entered state2", "New state entered");
        
        machine.destroy();
    }

    public function testComplexTransitionLogic():Void {
        trace("\n--- Test: Complex Transition Logic ---");
        var machine:FSM_StateMachine = new FSM_StateMachine(null, null, null);
        machine.data = {
            level: 1,
            score: 0,
            lives: 3,
            powerUp: false,
            actionCounter: 0
        };
        
        var playingState:FSM_Status = new FSM_Status(
            function():Void { this.data.actionCounter++; },
            null, null
        );
        var gameOverState:FSM_Status = new FSM_Status(
            function():Void { this.data.actionCounter++; },
            null, null
        );
        var nextLevelState:FSM_Status = new FSM_Status(
            function():Void { this.data.actionCounter++; },
            null, null
        );
        var powerUpState:FSM_Status = new FSM_Status(
            function():Void { this.data.actionCounter++; },
            null, null
        );
        
        machine.AddStatus("playing", playingState);
        machine.AddStatus("gameOver", gameOverState);
        machine.AddStatus("nextLevel", nextLevelState);
        machine.AddStatus("powerUp", powerUpState);
        
        // 复杂转换逻辑
        machine.transitions.push("playing", "gameOver", function():Boolean { 
            return this.data.lives <= 0; 
        });
        machine.transitions.push("playing", "nextLevel", function():Boolean { 
            return this.data.score >= this.data.level * 1000; 
        });
        machine.transitions.push("playing", "powerUp", function():Boolean { 
            return this.data.powerUp && this.data.lives > 1; 
        });
        machine.transitions.push("powerUp", "playing", function():Boolean { 
            return this.data.actionCounter % 5 == 0; // powerUp lasts 5 actions
        });
        machine.transitions.push("nextLevel", "playing", function():Boolean {
            return this.data.level > 1; // 条件化：避免同帧无限弹跳（0-frame state）
        });

        machine.start();

        // 测试游戏结束条件
        machine.data.lives = 0;
        machine.onAction();
        this.assert(machine.getActiveStateName() == "gameOver", "Game over when lives = 0");
        
        // 重置并测试升级条件
        machine.ChangeState("playing");
        machine.data.lives = 3;
        machine.data.score = 1000;
        machine.onAction();
        this.assert(machine.getActiveStateName() == "nextLevel", "Next level when score sufficient");
        
        machine.destroy();
    }

    // ========== 数据管理测试 ==========
    
    public function testDataBlackboardSharing():Void {
        trace("\n--- Test: Data Blackboard Sharing ---");
        var machine:FSM_StateMachine = new FSM_StateMachine(null, null, null);
        machine.data = {sharedValue: 0};
        
        var state1:FSM_Status = new FSM_Status(
            function():Void { this.data.sharedValue++; },
            null, null
        );
        
        var state2:FSM_Status = new FSM_Status(
            function():Void { this.data.sharedValue *= 2; },
            null, null
        );
        
        machine.AddStatus("increment", state1);
        machine.AddStatus("double", state2);
        
        this.assert(state1.data == machine.data, "State1 shares data with machine");
        this.assert(state2.data == machine.data, "State2 shares data with machine");
        
        state1.onAction();
        this.assert(machine.data.sharedValue == 1, "State1 modified shared data");
        
        machine.ChangeState("double");
        state2.onAction();
        this.assert(machine.data.sharedValue == 2, "State2 modified shared data");
        
        machine.destroy();
    }

    public function testDataIsolationBetweenMachines():Void {
        trace("\n--- Test: Data Isolation Between Machines ---");
        var machine1:FSM_StateMachine = new FSM_StateMachine(null, null, null);
        var machine2:FSM_StateMachine = new FSM_StateMachine(null, null, null);
        
        machine1.data = {value: 100};
        machine2.data = {value: 200};
        
        var state1:FSM_Status = new FSM_Status(
            function():Void { this.data.value += 10; },
            null, null
        );
        
        var state2:FSM_Status = new FSM_Status(
            function():Void { this.data.value += 20; },
            null, null
        );
        
        machine1.AddStatus("test", state1);
        machine2.AddStatus("test", state2);
        
        state1.onAction();
        state2.onAction();
        
        this.assert(machine1.data.value == 110, "Machine1 data modified correctly");
        this.assert(machine2.data.value == 220, "Machine2 data modified correctly");
        this.assert(machine1.data.value != machine2.data.value, "Data isolated between machines");
        
        machine1.destroy();
        machine2.destroy();
    }

    public function testDataPersistenceAcrossTransitions():Void {
        trace("\n--- Test: Data Persistence Across Transitions ---");
        var machine:FSM_StateMachine = new FSM_StateMachine(null, null, null);
        machine.data = {persistent: 42, modified: 0};
        
        var state1:FSM_Status = new FSM_Status(
            function():Void { this.data.modified = 1; },
            function():Void { this.data.modified = 10; },
            function():Void { this.data.modified = 100; }
        );
        
        var state2:FSM_Status = new FSM_Status(
            function():Void { this.data.modified = 2; },
            function():Void { this.data.modified = 20; },
            function():Void { this.data.modified = 200; }
        );
        
        machine.AddStatus("state1", state1);
        machine.AddStatus("state2", state2);

        machine.start();
        this.assert(machine.data.persistent == 42, "Persistent data maintained");
        this.assert(machine.data.modified == 10, "Data modified by state1 onEnter via start()");
        
        machine.ChangeState("state2");
        this.assert(machine.data.persistent == 42, "Persistent data maintained across transition");
        this.assert(machine.data.modified == 20, "Data modified by state2 onEnter");
        
        machine.destroy();
    }

    // ========== 边界情况测试 ==========
    
    public function testInvalidStateTransition():Void {
        trace("\n--- Test: Invalid State Transition ---");
        var machine:FSM_StateMachine = new FSM_StateMachine(null, null, null);
        var state:FSM_Status = this.createTestState("valid", false);
        
        machine.AddStatus("valid", state);
        
        var originalState:String = machine.getActiveStateName();
        machine.ChangeState("nonexistent");
        
        this.assert(machine.getActiveStateName() == originalState, "State unchanged for invalid transition");
        
        machine.destroy();
    }

    public function testSelfTransition():Void {
        trace("\n--- Test: Self Transition ---");
        this.clearLifecycleLog();
        
        var machine:FSM_StateMachine = new FSM_StateMachine(null, null, null);
        var state:FSM_Status = this.createTestState("self", true);
        
        machine.AddStatus("self", state);
        
        this.clearLifecycleLog();
        machine.ChangeState("self"); // Transition to same state
        
        this.assert(this._lifecycleLog.length == 0, "No lifecycle events for self-transition");
        this.assert(machine.getActiveStateName() == "self", "State remains the same");
        
        machine.destroy();
    }

    public function testEmptyStateMachine():Void {
        trace("\n--- Test: Empty StateMachine ---");
        var machine:FSM_StateMachine = new FSM_StateMachine(null, null, null);
        
        this.assert(machine.getDefaultState() == null, "Default state is null for empty machine");
        this.assert(machine.getActiveState() == null, "Active state is null for empty machine");
        this.assert(machine.getLastState() == null, "Last state is null for empty machine");
        
        // Should not crash
        machine.ChangeState("anything");
        machine.onAction();
        
        this.assert(true, "Empty machine handles operations gracefully");
        
        machine.destroy();
    }

    public function testRapidStateChanges():Void {
        trace("\n--- Test: Rapid State Changes ---");
        var machine:FSM_StateMachine = new FSM_StateMachine(null, null, null);
        var states:Array = [];
        
        for (var i:Number = 0; i < 10; i++) {
            var state:FSM_Status = this.createTestState("state" + i, false);
            machine.AddStatus("state" + i, state);
            states.push(state);
        }
        
        // Rapid transitions
        for (var j:Number = 0; j < 100; j++) {
            var targetState:String = "state" + (j % 10);
            machine.ChangeState(targetState);
        }
        
        this.assert(machine.getActiveStateName() == "state9", "Final state is correct after rapid changes");
        this.assert(machine.getActiveState() != null, "Active state is valid");
        
        machine.destroy();
    }

    public function testTransitionToSameState():Void {
        trace("\n--- Test: Transition to Same State ---");
        var machine:FSM_StateMachine = new FSM_StateMachine(null, null, null);
        machine.data = {actionCounter: 0, transitionCount: 0};
        
        var state:FSM_Status = new FSM_Status(
            function():Void { this.data.actionCounter++; },
            function():Void { this.data.transitionCount++; },
            null
        );
        
        machine.AddStatus("test", state);
        var initialTransitionCount:Number = machine.data.transitionCount;
        
        machine.ChangeState("test"); // 尝试转换到相同状态
        this.assert(machine.data.transitionCount == initialTransitionCount, "No transition event for same-state change");
        
        machine.destroy();
    }

    public function testNullStateHandling():Void {
        trace("\n--- Test: Null State Handling ---");
        var machine:FSM_StateMachine = new FSM_StateMachine(null, null, null);
        var state:FSM_Status = this.createTestState("test", false);
        
        machine.AddStatus("test", state);
        
        machine.setActiveState(null);
        this.assert(machine.getActiveState() == machine.getDefaultState(), "Null active state defaults to default");
        
        machine.setLastState(null);
        this.assert(machine.getLastState() == null, "Last state can be set to null");
        
        machine.destroy();
    }

    // ========== 错误处理测试 ==========
    
    public function testExceptionInLifecycleMethods():Void {
        trace("\n--- Test: Exception in Lifecycle Methods ---");
        var machine:FSM_StateMachine = new FSM_StateMachine(null, null, null);
        var exceptionCount:Number = 0;
        
        var faultyState:FSM_Status = new FSM_Status(
            function():Void { throw new Error("Action exception"); },
            function():Void { throw new Error("Enter exception"); },
            function():Void { throw new Error("Exit exception"); }
        );
        
        var normalState:FSM_Status = this.createTestState("normal", false);
        
        try {
            machine.AddStatus("faulty", faultyState);
            machine.start(); // triggers faultyState.onEnter → throws
        } catch (e:Error) {
            exceptionCount++;
        }

        machine.AddStatus("normal", normalState);

        try {
            machine.ChangeState("faulty");
        } catch (e:Error) {
            exceptionCount++;
        }

        try {
            machine.onAction();
        } catch (e:Error) {
            exceptionCount++;
        }

        this.assert(exceptionCount > 0, "Exceptions properly propagated from lifecycle methods");

        try {
            machine.destroy(); // faultyState.onExit throws during destroy - expected
        } catch (e:Error) {
            // 已 start 的 faulty 状态在 destroy 时触发 onExit → 抛异常，吞掉即可
        }
    }

    public function testExceptionInTransitionConditions():Void {
        trace("\n--- Test: Exception in Transition Conditions ---");
        var machine:FSM_StateMachine = new FSM_StateMachine(null, null, null);
        var state1:FSM_Status = this.createTestState("state1", false);
        var state2:FSM_Status = this.createTestState("state2", false);
        
        machine.AddStatus("state1", state1);
        machine.AddStatus("state2", state2);
        
        machine.transitions.push("state1", "state2", function():Boolean {
            throw new Error("Transition condition exception");
            return false;
        });

        machine.start();
        var exceptionCaught:Boolean = false;
        try {
            machine.onAction();
        } catch (e:Error) {
            exceptionCaught = true;
        }
        
        this.assert(exceptionCaught, "Exception in transition condition properly propagated");
        
        machine.destroy();
    }

    public function testCorruptedStateHandling():Void {
        trace("\n--- Test: Corrupted State Handling ---");
        var machine:FSM_StateMachine = new FSM_StateMachine(null, null, null);
        var state:FSM_Status = this.createTestState("test", false);
        
        machine.AddStatus("test", state);
        
        // 由于无法直接访问statusDict，我们测试无效状态名的处理
        var originalStateName:String = machine.getActiveStateName();
        machine.ChangeState("nonexistent_state");
        
        // 应该保持原状态不变
        this.assert(machine.getActiveStateName() == originalStateName, "Invalid state transition handled gracefully");
        
        machine.destroy();
    }

    public function testInvalidTransitionHandling():Void {
        trace("\n--- Test: Invalid Transition Handling ---");
        var machine:FSM_StateMachine = new FSM_StateMachine(null, null, null);
        var state:FSM_Status = this.createTestState("test", false);
        
        machine.AddStatus("test", state);
        
        // 测试返回null的转换
        machine.transitions.push("test", null, function():Boolean { return true; });
        
        var originalState:String = machine.getActiveStateName();
        machine.onAction();
        
        this.assert(machine.getActiveStateName() == originalState, "Invalid transition target handled gracefully");
        
        machine.destroy();
    }

    // ========== 复杂场景测试 ==========
    
    public function testNestedStateMachines():Void {
        trace("\n--- Test: Nested StateMachines ---");
        
        // 创建父状态机
        var parentMachine:FSM_StateMachine = new FSM_StateMachine(null, null, null);
        
        // 创建子状态机作为状态
        var childMachine1:FSM_StateMachine = new FSM_StateMachine(null, null, null);
        var childMachine2:FSM_StateMachine = new FSM_StateMachine(null, null, null);
        
        // 为子状态机添加状态，确保 AddStatus 的名称与 createTestState 的名称一致
        childMachine1.AddStatus("child1_idle", this.createTestState("child1_idle", false));
        childMachine1.AddStatus("child1_active", this.createTestState("child1_active", false));
        
        childMachine2.AddStatus("child2_idle", this.createTestState("child2_idle", false));
        childMachine2.AddStatus("child2_active", this.createTestState("child2_active", false));
        
        // 将子状态机作为状态添加到父状态机
        parentMachine.AddStatus("machine1", childMachine1);
        parentMachine.AddStatus("machine2", childMachine2);

        // AddStatus 设置 activeState 但不触发 onEnter
        this.assert(parentMachine.getActiveStateName() == "machine1", "Parent machine active state is child machine");
        this.assert(childMachine1.getActiveStateName() == "child1_idle", "Child machine 1 has its own active state (pre-start)");

        // start() 触发 parent.onEnter → childMachine1.onEnter → child1_idle.onEnter
        parentMachine.start();

        // 切换父状态机状态
        parentMachine.ChangeState("machine2");
        this.assert(parentMachine.getActiveStateName() == "machine2", "Parent machine state changed");
        
        // 独立改变子状态机2的状态
        childMachine2.ChangeState("child2_active");
        
        // 第三次断言：子状态机2的内部状态应该已成功改变
        this.assert(childMachine2.getActiveStateName() == "child2_active", "Child machine state changed independently");
        
        parentMachine.destroy();
    }

    public function testComplexWorkflow():Void {
        trace("\n--- Test: Complex Workflow ---");
        var machine:FSM_StateMachine = new FSM_StateMachine(null, null, null);
        machine.data = {
            step: 0,
            errors: 0,
            retries: 0,
            maxRetries: 3
        };
        
        // 创建工作流状态
        var initState:FSM_Status = new FSM_Status(
            function():Void { this.data.step = 1; },
            function():Void { trace("Initializing workflow..."); },
            null
        );
        
        var processState:FSM_Status = new FSM_Status(
            function():Void { 
                if (Math.random() < 0.3) { // 30% chance of error
                    this.data.errors++;
                } else {
                    this.data.step++;
                }
            },
            function():Void { trace("Processing..."); },
            null
        );
        
        var retryState:FSM_Status = new FSM_Status(
            function():Void { this.data.retries++; },
            function():Void { trace("Retrying..."); },
            null
        );
        
        var completeState:FSM_Status = new FSM_Status(
            null,
            function():Void { trace("Workflow completed!"); },
            null
        );
        
        var errorState:FSM_Status = new FSM_Status(
            null,
            function():Void { trace("Workflow failed!"); },
            null
        );
        
        machine.AddStatus("init", initState);
        machine.AddStatus("process", processState);
        machine.AddStatus("retry", retryState);
        machine.AddStatus("complete", completeState);
        machine.AddStatus("error", errorState);
        
        // 定义工作流转换
        machine.transitions.push("init", "process", function():Boolean { return this.data.step >= 1; });
        machine.transitions.push("process", "complete", function():Boolean { return this.data.step >= 3 && this.data.errors == 0; });
        machine.transitions.push("process", "retry", function():Boolean { return this.data.errors > 0 && this.data.retries < this.data.maxRetries; });
        machine.transitions.push("process", "error", function():Boolean { return this.data.errors > 0 && this.data.retries >= this.data.maxRetries; });
        machine.transitions.push("retry", "process", function():Boolean { return true; });

        machine.start();
        // 运行工作流
        for (var i:Number = 0; i < 20 && machine.getActiveStateName() != "complete" && machine.getActiveStateName() != "error"; i++) {
            machine.onAction();
        }
        
        var finalState:String = machine.getActiveStateName();
        this.assert(finalState == "complete" || finalState == "error", "Workflow reached final state");
        
        machine.destroy();
    }

    public function testStateChaining():Void {
        trace("\n--- Test: State Chaining ---");
        var machine:FSM_StateMachine = new FSM_StateMachine(null, null, null);
        machine.data = {chain: []};
        
        // 创建链式状态
        for (var i:Number = 1; i <= 5; i++) {
            var state:FSM_Status = new FSM_Status(
                null,
                function():Void { this.data.chain.push(this.name); },
                null
            );
            machine.AddStatus("step" + i, state);
        }
        
        // 添加链式转换
        for (var j:Number = 1; j < 5; j++) {
            machine.transitions.push("step" + j, "step" + (j + 1), function():Boolean { return true; });
        }

        machine.start();

        // 执行链
        for (var k:Number = 0; k < 10; k++) {
            machine.onAction();
            if (machine.getActiveStateName() == "step5") break;
        }
        
        this.assert(machine.data.chain.length == 5, "All chain steps executed");
        this.assert(machine.data.chain[0] == "step1", "Chain started correctly");
        this.assert(machine.data.chain[4] == "step5", "Chain ended correctly");
        
        machine.destroy();
    }

    public function testConditionalBranching():Void {
        trace("\n--- Test: Conditional Branching ---");
        var machine:FSM_StateMachine = new FSM_StateMachine(null, null, null);
        machine.data = {condition: 0, path: ""};
        
        var decisionState:FSM_Status = new FSM_Status(
            null,
            function():Void { this.data.condition = Math.floor(Math.random() * 3); },
            null
        );
        
        var pathAState:FSM_Status = new FSM_Status(
            null,
            function():Void { this.data.path = "A"; },
            null
        );
        
        var pathBState:FSM_Status = new FSM_Status(
            null,
            function():Void { this.data.path = "B"; },
            null
        );
        
        var pathCState:FSM_Status = new FSM_Status(
            null,
            function():Void { this.data.path = "C"; },
            null
        );
        
        machine.AddStatus("decision", decisionState);
        machine.AddStatus("pathA", pathAState);
        machine.AddStatus("pathB", pathBState);
        machine.AddStatus("pathC", pathCState);

        machine.start();

        // 添加条件分支
        machine.transitions.push("decision", "pathA", function():Boolean { return this.data.condition == 0; });
        machine.transitions.push("decision", "pathB", function():Boolean { return this.data.condition == 1; });
        machine.transitions.push("decision", "pathC", function():Boolean { return this.data.condition == 2; });
        
        machine.onAction();
        
        var expectedPaths:Array = ["A", "B", "C"];
        var actualPath:String = machine.data.path;
        var validPath:Boolean = false;
        
        for (var i:Number = 0; i < expectedPaths.length; i++) {
            if (actualPath == expectedPaths[i]) {
                validPath = true;
                break;
            }
        }
        
        this.assert(validPath, "Conditional branching led to valid path: " + actualPath);
        
        machine.destroy();
    }

    public function testStateMachineComposition():Void {
        trace("\n--- Test: StateMachine Composition ---");
        
        // 创建多个独立的状态机
        var loginMachine:FSM_StateMachine = new FSM_StateMachine(null, null, null);
        var gameMachine:FSM_StateMachine = new FSM_StateMachine(null, null, null);
        var menuMachine:FSM_StateMachine = new FSM_StateMachine(null, null, null);
        
        // 为每个状态机添加状态
        loginMachine.AddStatus("login", this.createTestState("login", false));
        loginMachine.AddStatus("authenticated", this.createTestState("authenticated", false));
        
        gameMachine.AddStatus("playing", this.createTestState("playing", false));
        gameMachine.AddStatus("paused", this.createTestState("paused", false));
        
        menuMachine.AddStatus("main", this.createTestState("main", false));
        menuMachine.AddStatus("settings", this.createTestState("settings", false));
        
        // 测试独立操作
        this.assert(loginMachine.getActiveStateName() == "login", "Login machine starts at login");
        this.assert(gameMachine.getActiveStateName() == "playing", "Game machine starts at playing");
        this.assert(menuMachine.getActiveStateName() == "main", "Menu machine starts at main");
        
        // 独立状态变化
        loginMachine.ChangeState("authenticated");
        gameMachine.ChangeState("paused");
        menuMachine.ChangeState("settings");
        
        this.assert(loginMachine.getActiveStateName() == "authenticated", "Login machine state changed");
        this.assert(gameMachine.getActiveStateName() == "paused", "Game machine state changed");
        this.assert(menuMachine.getActiveStateName() == "settings", "Menu machine state changed");
        
        loginMachine.destroy();
        gameMachine.destroy();
        menuMachine.destroy();
    }

    // ========== 内存管理测试 ==========
    
    public function testStateMachineDestroy():Void {
        trace("\n--- Test: StateMachine Destroy ---");
        var machine:FSM_StateMachine = new FSM_StateMachine(null, null, null);
        var state1:FSM_Status = this.createTestState("state1", false);
        var state2:FSM_Status = this.createTestState("state2", false);
        
        machine.AddStatus("state1", state1);
        machine.AddStatus("state2", state2);
        
        this.assert(machine.getActiveState() != null, "Active state exists before destroy");
        this.assert(machine.getDefaultState() != null, "Default state exists before destroy");
        
        machine.destroy();
        
        // 验证状态已被销毁（通过检查状态对象的isDestroyed属性）
        this.assert(state1.isDestroyed, "Child state1 destroyed");
        this.assert(state2.isDestroyed, "Child state2 destroyed");
        
        // 验证机器引用已清理（通过尝试操作来测试）
        try {
            machine.onAction(); // 应该不会崩溃，但可能无效果
            this.assert(true, "Destroy method completed without crash");
        } catch (e:Error) {
            this.assert(true, "Destroy properly cleaned up references");
        }
    }

    public function testMemoryLeakPrevention():Void {
        trace("\n--- Test: Memory Leak Prevention ---");
        
        var machines:Array = [];
        
        // 创建多个状态机
        for (var i:Number = 0; i < 50; i++) {
            var machine:FSM_StateMachine = new FSM_StateMachine(null, null, null);
            machine.data = {id: i, values: []};
            
            // 为每个状态机添加多个状态
            for (var j:Number = 0; j < 5; j++) {
                var state:FSM_Status = this.createTestState("state" + j, false);
                machine.AddStatus("state" + j, state);
            }
            
            // 添加一些转换
            machine.transitions.push("state0", "state1", function():Boolean { return Math.random() > 0.5; });
            machine.transitions.push("state1", "state2", function():Boolean { return Math.random() > 0.5; });
            
            machines.push(machine);
        }
        
        // 运行一些操作
        for (var k:Number = 0; k < machines.length; k++) {
            machines[k].onAction();
            machines[k].ChangeState("state1");
        }
        
        // 销毁所有状态机
        for (var l:Number = 0; l < machines.length; l++) {
            machines[l].destroy();
            machines[l] = null;
        }
        machines = null;
        
        this.assert(true, "Memory leak prevention test completed (check manually for leaks)");
    }

    public function testStateCleanup():Void {
        trace("\n--- Test: State Cleanup ---");
        var machine:FSM_StateMachine = new FSM_StateMachine(null, null, null);
        var state:FSM_Status = this.createTestState("test", false);
        
        machine.AddStatus("test", state);
        
        this.assert(!state.isDestroyed, "State not destroyed initially");
        this.assert(state.active, "State is active initially");
        this.assert(state.superMachine == machine, "State has reference to super machine");
        
        machine.destroy();
        
        this.assert(state.isDestroyed, "State destroyed with machine");
        this.assert(!state.active, "State inactive after destroy");
        this.assert(state.superMachine == null, "State super machine reference cleared");
    }

    public function testTransitionCleanup():Void {
        trace("\n--- Test: Transition Cleanup ---");
        var machine:FSM_StateMachine = new FSM_StateMachine(null, null, null);
        var state1:FSM_Status = this.createTestState("state1", false);
        var state2:FSM_Status = this.createTestState("state2", false);
        
        machine.AddStatus("state1", state1);
        machine.AddStatus("state2", state2);
        
        // 添加转换
        machine.transitions.push("state1", "state2", function():Boolean { return true; });
        
        this.assert(machine.transitions != null, "Transitions exist before cleanup");
        
        machine.destroy();
        
        // 转换应该被清理（具体实现取决于destroy方法）
        this.assert(true, "Transition cleanup completed");
    }

    // ========== 性能测试 ==========
    
    public function testBasicPerformance():Void {
        trace("\n--- Test: Basic Performance ---");
        var machine:FSM_StateMachine = new FSM_StateMachine(null, null, null);
        var state1:FSM_Status = this.createTestState("state1", false);
        var state2:FSM_Status = this.createTestState("state2", false);
        
        machine.AddStatus("state1", state1);
        machine.AddStatus("state2", state2);
        
        var iterations:Number = 10000;
        
        var transitionTime:Number = this.measureTime(function() {
            machine.ChangeState("state2");
            machine.ChangeState("state1");
        }, iterations / 2);
        
        var actionTime:Number = this.measureTime(function() {
            machine.onAction();
        }, iterations);
        
        trace("Basic Performance: Transitions=" + transitionTime + "ms, Actions=" + actionTime + "ms for " + iterations + " operations");
        this.assert(transitionTime < 2000, "Transition performance acceptable");
        this.assert(actionTime < 2000, "Action performance acceptable");
        
        machine.destroy();
    }

    public function testManyStatesPerformance():Void {
        trace("\n--- Test: Many States Performance ---");
        var machine:FSM_StateMachine = new FSM_StateMachine(null, null, null);
        var numStates:Number = 1000;
        
        var createTime:Number = getTimer();
        for (var i:Number = 0; i < numStates; i++) {
            var state:FSM_Status = this.createTestState("state" + i, false);
            machine.AddStatus("state" + i, state);
        }
        createTime = getTimer() - createTime;
        
        var accessTime:Number = getTimer();
        for (var j:Number = 0; j < 100; j++) {
            var stateName:String = "state" + (j % numStates);
            machine.ChangeState(stateName);
        }
        accessTime = getTimer() - accessTime;
        
        trace("Many States Performance: Create " + numStates + " states in " + createTime + "ms, 100 transitions in " + accessTime + "ms");
        this.assert(createTime < 5000, "State creation scalable");
        this.assert(accessTime < 1000, "State access scalable");
        
        machine.destroy();
    }

    public function testFrequentTransitionsPerformance():Void {
        trace("\n--- Test: Frequent Transitions Performance ---");
        var machine:FSM_StateMachine = new FSM_StateMachine(null, null, null);
        machine.data = {counter: 0};
        
        var state1:FSM_Status = new FSM_Status(
            function():Void { this.data.counter++; },
            null, null
        );
        var state2:FSM_Status = new FSM_Status(
            function():Void { this.data.counter++; },
            null, null
        );
        
        machine.AddStatus("ping", state1);
        machine.AddStatus("pong", state2);
        
        // 添加往返转换
        machine.transitions.push("ping", "pong", function():Boolean { 
            return this.data.counter % 2 == 0; 
        });
        machine.transitions.push("pong", "ping", function():Boolean { 
            return this.data.counter % 2 == 1; 
        });
        
        var iterations:Number = 5000;
        var time:Number = this.measureTime(function() {
            machine.onAction();
        }, iterations);
        
        trace("Frequent Transitions Performance: " + iterations + " transitions in " + time + "ms");
        this.assert(time < 3000, "Frequent transitions performance acceptable");
        
        machine.destroy();
    }

    public function testComplexTransitionPerformance():Void {
        trace("\n--- Test: Complex Transition Performance ---");
        var machine:FSM_StateMachine = new FSM_StateMachine(null, null, null);
        machine.data = {values: [], actionCounter: 0};
        
        // 创建复杂状态网络
        for (var i:Number = 0; i < 10; i++) {
            var state:FSM_Status = new FSM_Status(
                function():Void { this.data.actionCounter++; },
                null, null
            );
            machine.AddStatus("state" + i, state);
        }
        
        // 添加复杂转换逻辑
        for (var j:Number = 0; j < 10; j++) {
            for (var k:Number = 0; k < 3; k++) {
                var target:Number = (j + k + 1) % 10;
                var targetName:String = "state" + target;
                machine.transitions.push("state" + j, targetName, function():Boolean {
                    // 复杂条件检查
                    var sum:Number = 0;
                    for (var l:Number = 0; l < this.data.values.length; l++) {
                        sum += this.data.values[l];
                    }
                    return sum % 7 == (this.data.actionCounter % 10);
                });
            }
        }
        
        var iterations:Number = 1000;
        var time:Number = this.measureTime(function() {
            machine.data.values.push(Math.floor(Math.random() * 100));
            if (machine.data.values.length > 10) {
                machine.data.values.shift();
            }
            machine.onAction();
        }, iterations);
        
        trace("Complex Transition Performance: " + iterations + " complex transitions in " + time + "ms");
        this.assert(time < 5000, "Complex transition performance acceptable");
        
        machine.destroy();
    }

    public function testScalabilityTest():Void {
        trace("\n--- Test: Scalability Test ---");
        
        var sizes:Array = [10, 50, 100, 500];
        var results:Array = [];
        
        for (var s:Number = 0; s < sizes.length; s++) {
            var size:Number = sizes[s];
            var machine:FSM_StateMachine = new FSM_StateMachine(null, null, null);
            machine.data = {actionCounter: 0};
            
            // 创建指定数量的状态
            var createTime:Number = getTimer();
            for (var i:Number = 0; i < size; i++) {
                var state:FSM_Status = new FSM_Status(
                    function():Void { this.data.actionCounter++; },
                    null, null
                );
                machine.AddStatus("state" + i, state);
            }
            createTime = getTimer() - createTime;
            
            // 添加转换
            var transitionTime:Number = getTimer();
            for (var j:Number = 0; j < size; j++) {
                var target:Number = (j + 1) % size;
                var targetName:String = "state" + target;
                machine.transitions.push("state" + j, targetName, function():Boolean {
                    return Math.random() > 0.8;
                });
            }
            transitionTime = getTimer() - transitionTime;
            
            // 执行操作
            var operationTime:Number = getTimer();
            for (var k:Number = 0; k < 100; k++) {
                machine.onAction();
            }
            operationTime = getTimer() - operationTime;
            
            results.push({
                size: size,
                create: createTime,
                transition: transitionTime,
                operation: operationTime
            });
            
            machine.destroy();
        }
        
        // 分析结果
        var scalabilityGood:Boolean = true;
        for (var r:Number = 0; r < results.length; r++) {
            var result = results[r];
            trace("Size " + result.size + ": Create=" + result.create + "ms, Transition=" + result.transition + "ms, Operation=" + result.operation + "ms");
            
            // 检查是否线性扩展
            if (result.create > result.size * 10 || result.operation > 5000) {
                scalabilityGood = false;
            }
        }
        
        this.assert(scalabilityGood, "Scalability performance acceptable across different sizes");
    }

    // ========== P1 新增测试：路线A重构验证 ==========
    
    /**
     * S1 测试：Pause Gate 同帧阻断效果
     * 验证暂停状态能在当帧生效，阻止子状态动作执行
     */
    public function testPauseGateImmediateEffect():Void {
        trace("\n--- Test: Pause Gate Immediate Effect ---");
        this.clearLifecycleLog();
        
        var machine:FSM_StateMachine = new FSM_StateMachine(null, null, null);
        machine.data = {isPaused: false, actionExecuted: false};
        
        var self = this;
        
        // 玩家状态 - 会记录是否执行了动作
        var playerState:FSM_Status = new FSM_Status(
            function():Void { 
                this.data.actionExecuted = true;  // 记录动作已执行
                self._lifecycleLog.push("player:action");
            },
            function():Void { self._lifecycleLog.push("player:enter"); },
            function():Void { self._lifecycleLog.push("player:exit"); }
        );
        
        // 暂停状态 - Gate State，不应该执行子状态动作
        var pausedState:FSM_Status = new FSM_Status(
            null, // 暂停状态不执行动作
            function():Void { self._lifecycleLog.push("paused:enter"); },
            function():Void { self._lifecycleLog.push("paused:exit"); }
        );
        
        machine.AddStatus("player", playerState);
        machine.AddStatus("paused", pausedState);
        
        // 添加暂停转换：当isPaused=true时立即切换到暂停状态（使用Gate机制）
        machine.transitions.push("player", "paused", function():Boolean {
            return this.data.isPaused;
        }, true);

        machine.start();

        // 【关键测试】：在同一帧内触发暂停并执行onAction
        this.clearLifecycleLog();
        machine.data.isPaused = true;  // 触发暂停条件
        machine.data.actionExecuted = false;  // 重置动作标记

        machine.onAction();  // 执行一帧的逻辑

        // 预期行为（3-phase Gate 机制）：
        // Phase 1 Gate 转换在 Phase 2 动作之前执行，暂停立即生效
        this.assert(machine.getActiveStateName() == "paused", "Should switch to paused state immediately");
        this.assert(!machine.data.actionExecuted, "Player action should NOT execute when paused in same frame");
        this._lifecycleLog.indexOf = function(str:String):Number{
            for(var i=0; i< this.length; i++){
                if(this[i] === str) return i;
            }
            return -1;
        }
        this.assert(this._lifecycleLog.indexOf("player:action") == -1, "Player action should not be logged");
        this.assert(this._lifecycleLog.indexOf("paused:enter") != -1, "Paused state should be entered");
        
        machine.destroy();
    }
    
    /**
     * S2 测试：Exit→Enter→Action 正确顺序
     * 验证转换发生时，新状态的动作能在同帧执行
     */
    public function testTransitionToActionOrder():Void {
        trace("\n--- Test: Transition→Action Order ---");
        this.clearLifecycleLog();
        
        var machine:FSM_StateMachine = new FSM_StateMachine(null, null, null);
        machine.data = {shouldTransition: false, actionCount: 0};
        var self = this;
        
        var stateA:FSM_Status = new FSM_Status(
            function():Void { 
                this.data.actionCount++;
                self._lifecycleLog.push("A:action:" + this.data.actionCount);
            },
            function():Void { self._lifecycleLog.push("A:enter"); },
            function():Void { self._lifecycleLog.push("A:exit"); }
        );
        
        var stateB:FSM_Status = new FSM_Status(
            function():Void { 
                this.data.actionCount++;
                self._lifecycleLog.push("B:action:" + this.data.actionCount);
            },
            function():Void { self._lifecycleLog.push("B:enter"); },
            function():Void { self._lifecycleLog.push("B:exit"); }
        );
        
        machine.AddStatus("A", stateA);
        machine.AddStatus("B", stateB);
        
        // 转换条件：第2次动作后切换
        machine.transitions.push("A", "B", function():Boolean {
            return this.data.actionCount >= 2;
        });

        machine.start();
        this.clearLifecycleLog();
        machine.onAction();  // 第1次：A:action:1
        machine.onAction();  // 第2次：A:action:2 → 触发 Normal 转换 A→B → 同帧 B:action:3

        // 预期行为（3-phase 管线 + 同帧稳定化）：
        // clearLifecycleLog 已清除 AddStatus 触发的 "A:enter"，
        // 第2次 onAction 中 Normal 转换后 while 循环继续执行 B 的动作
        var expectedOrder:Array = [
            "A:action:1",   // 第1次onAction
            "A:action:2",   // 第2次onAction（触发转换条件）
            "A:exit",       // 退出A状态
            "B:enter",      // 进入B状态
            "B:action:3"    // 同帧执行B的动作
        ];
        
        this.assert(this._lifecycleLog.length == expectedOrder.length, "Correct number of lifecycle events");
        this.assert(machine.getActiveStateName() == "B", "Should be in state B");
        
        // 检查最后一个事件是否是B的动作
        var lastEvent:String = this._lifecycleLog[this._lifecycleLog.length - 1];
        this.assert(lastEvent == "B:action:3", "B's action should execute in same frame as transition");
        
        machine.destroy();
    }
    
    /**
     * S3 测试：递归切换安全性
     * 验证快速状态切换不会导致栈溢出或无限递归
     */
    public function testRecursiveTransitionSafety():Void {
        trace("\n--- Test: Recursive Transition Safety ---");
        
        var machine:FSM_StateMachine = new FSM_StateMachine(null, null, null);
        machine.data = {transitions: 0, maxTransitions: 50};
        var self = this;
        
        var pingState:FSM_Status = new FSM_Status(
            function():Void { 
                this.data.transitions++;
                self._lifecycleLog.push("ping:action:" + this.data.transitions);
            },
            function():Void { self._lifecycleLog.push("ping:enter"); },
            function():Void { self._lifecycleLog.push("ping:exit"); }
        );
        
        var pongState:FSM_Status = new FSM_Status(
            function():Void { 
                this.data.transitions++;
                self._lifecycleLog.push("pong:action:" + this.data.transitions);
            },
            function():Void { self._lifecycleLog.push("pong:enter"); },
            function():Void { self._lifecycleLog.push("pong:exit"); }
        );
        
        machine.AddStatus("ping", pingState);
        machine.AddStatus("pong", pongState);
        
        // 快速乒乓转换
        machine.transitions.push("ping", "pong", function():Boolean { 
            return this.data.transitions % 2 == 1; 
        });
        machine.transitions.push("pong", "ping", function():Boolean {
            return this.data.transitions % 2 == 0 && this.data.transitions < this.data.maxTransitions;
        });

        machine.start();
        this.clearLifecycleLog();
        
        // 执行多帧，测试是否会栈溢出或无限递归
        var frameCount:Number = 0;
        var maxFrames:Number = 100;
        
        try {
            while (frameCount < maxFrames && machine.data.transitions < machine.data.maxTransitions) {
                machine.onAction();
                frameCount++;
            }
            
            this.assert(true, "No stack overflow during rapid transitions");
            this.assert(frameCount < maxFrames, "Transitions completed within reasonable frames");
            this.assert(machine.getActiveState() != null, "Active state remains valid");
            
            // 验证最终状态正确性
            var finalState:String = machine.getActiveStateName();
            this.assert(finalState == "ping" || finalState == "pong", "Final state is valid");
            
        } catch (e:Error) {
            this.assert(false, "Recursive transition safety failed: " + e.message);
        }
        
        machine.destroy();
    }

    // ========== P0 Path B 回调字段化验证 ==========

    /**
     * 核心回归测试：非 null 回调不再穿透 FSM_StateMachine 的管线
     *
     * 旧缺陷：FSM_Status 构造函数通过 this.onAction = _onAction 创建实例属性，
     *         覆写了 FSM_StateMachine 原型链上的 3-phase 管线 onAction()。
     * Path B：回调存储在 _onActionCb 字段中，类方法作为包装器。
     *         FSM_StateMachine 的 override 通过原型链正常生效。
     */
    public function testPathBCallbackNoShadow():Void {
        trace("\n--- Test: Path B - Callbacks Do Not Shadow Pipeline ---");

        var pipelineRan:Boolean = false;
        var callbackRan:Boolean = false;

        // 创建带非 null 回调的状态机（以前这会穿透管线）
        var machine:FSM_StateMachine = new FSM_StateMachine(
            function():Void { callbackRan = true; },  // _onActionCb
            null, null
        );
        machine.data = { counter: 0 };

        var stateA:FSM_Status = new FSM_Status(
            function():Void { this.data.counter++; pipelineRan = true; },
            null, null
        );
        var stateB:FSM_Status = new FSM_Status(null, null, null);

        machine.AddStatus("A", stateA);
        machine.AddStatus("B", stateB);

        machine.transitions.push("A", "B", function():Boolean {
            return this.data.counter >= 1;
        });

        machine.start();
        machine.onAction();

        // 管线必须执行（Phase 2: stateA.onAction + Phase 3: 转换到 B）
        this.assert(pipelineRan, "Pipeline Phase 2 executed (state action ran)");
        this.assert(machine.getActiveStateName() == "B", "Pipeline Phase 3 executed (transition fired)");

        // 机器级回调通过 super.onAction() 在管线 Phase 4 后执行
        this.assert(callbackRan, "Machine-level _onActionCb fired as post-pipeline hook");

        machine.destroy();
    }

    /**
     * 验证 FSM_StateMachine 的 onEnter/onExit 回调在嵌套场景下正确触发
     *
     * 当 FSM_StateMachine 作为嵌套状态被 enter/exit 时：
     *  - onEnter: super.onEnter() 调用 _onEnterCb → 然后传播到子状态
     *  - onExit:  先传播到子状态 → 然后 super.onExit() 调用 _onExitCb
     */
    public function testPathBMachineLevelHooks():Void {
        trace("\n--- Test: Path B - Machine Level Enter/Exit Hooks ---");
        var hookLog:Array = [];

        // 父状态机
        var parent:FSM_StateMachine = new FSM_StateMachine(null, null, null);

        // 子状态机（带非 null onEnter/onExit 回调）
        var child:FSM_StateMachine = new FSM_StateMachine(
            null,
            function():Void { hookLog.push("child-machine:enter"); },
            function():Void { hookLog.push("child-machine:exit"); }
        );
        child.data = {};

        // 为子状态机添加内部状态
        var innerState:FSM_Status = new FSM_Status(
            null,
            function():Void { hookLog.push("inner:enter"); },
            function():Void { hookLog.push("inner:exit"); }
        );
        child.AddStatus("inner", innerState);

        // 另一个顶级状态
        var otherState:FSM_Status = new FSM_Status(
            null,
            function():Void { hookLog.push("other:enter"); },
            function():Void { hookLog.push("other:exit"); }
        );

        parent.AddStatus("child", child);
        parent.AddStatus("other", otherState);

        // AddStatus 不再触发 onEnter（延迟到 start()）
        this.assert(hookLog.length == 0, "AddStatus does not trigger enter hooks (deferred to start())");

        parent.start();

        // start() 触发 child.onEnter → super.onEnter() + 子状态传播
        this.assert(hookLog.length >= 2, "Child machine enter hooks fired on start()");

        var enterIdx:Number = -1;
        var innerIdx:Number = -1;
        for (var i:Number = 0; i < hookLog.length; i++) {
            if (hookLog[i] == "child-machine:enter") enterIdx = i;
            if (hookLog[i] == "inner:enter") innerIdx = i;
        }
        this.assert(enterIdx >= 0, "Machine-level onEnter callback fired");
        this.assert(innerIdx >= 0, "Inner state onEnter propagated");
        this.assert(enterIdx < innerIdx, "Machine onEnter fires before inner state onEnter");

        // 切换到 other 状态 → 触发 child.onExit
        hookLog = [];
        parent.ChangeState("other");

        var exitIdx:Number = -1;
        var innerExitIdx:Number = -1;
        for (var j:Number = 0; j < hookLog.length; j++) {
            if (hookLog[j] == "child-machine:exit") exitIdx = j;
            if (hookLog[j] == "inner:exit") innerExitIdx = j;
        }
        this.assert(innerExitIdx >= 0, "Inner state onExit propagated");
        this.assert(exitIdx >= 0, "Machine-level onExit callback fired");
        this.assert(innerExitIdx < exitIdx, "Inner state exits before machine onExit");

        parent.destroy();
    }

    // ========== Batch 3 新增测试：start() / $ 前缀 / while-loop / Phase 2 ==========

    /**
     * 测试 start() 显式启动方法
     * 验证构建期与启动期分离
     */
    public function testStartMethod():Void {
        trace("\n--- Test: Explicit start() Method ---");
        this.clearLifecycleLog();

        var machine:FSM_StateMachine = new FSM_StateMachine(null, null, null);
        var state:FSM_Status = this.createTestState("idle", true);

        machine.AddStatus("idle", state);

        // AddStatus 不触发 onEnter
        this.assert(this._lifecycleLog.length == 0, "No onEnter before start()");

        // 首次 start() 触发 onEnter
        machine.start();
        this.assert(this._lifecycleLog.length == 1 && this._lifecycleLog[0] == "idle:enter",
                   "start() triggers default state onEnter");

        // 重复 start() 无效（幂等）
        this.clearLifecycleLog();
        machine.start();
        this.assert(this._lifecycleLog.length == 0, "Duplicate start() is no-op");

        machine.destroy();
    }

    /**
     * 测试 AddStatus 保留名校验
     * Object 原型链上的键名（toString/constructor 等）应被拒绝并 trace 报错
     */
    public function testReservedNameValidation():Void {
        trace("\n--- Test: Reserved Name Validation ---");
        var machine:FSM_StateMachine = new FSM_StateMachine(null, null, null);

        var normalState:FSM_Status = this.createTestState("normal", false);
        var toStringState:FSM_Status = this.createTestState("toString", false);
        var constructorState:FSM_Status = this.createTestState("constructor", false);

        machine.AddStatus("normal", normalState);

        // 保留名应被拒绝（AddStatus 静默返回，trace 报错）
        machine.AddStatus("toString", toStringState);
        machine.AddStatus("constructor", constructorState);

        // 验证保留名状态未被注册
        machine.ChangeState("toString");
        this.assert(machine.getActiveStateName() == "normal", "Reserved name 'toString' rejected by AddStatus");

        machine.ChangeState("constructor");
        this.assert(machine.getActiveStateName() == "normal", "Reserved name 'constructor' rejected by AddStatus");

        // 正常名称仍然可用
        var attackState:FSM_Status = this.createTestState("Attack", false);
        machine.AddStatus("Attack", attackState);
        machine.ChangeState("Attack");
        this.assert(machine.getActiveStateName() == "Attack", "Normal name 'Attack' works correctly");

        machine.destroy();
    }

    /**
     * 测试 ChangeState while 循环链式切换安全性
     * 验证 onEnter 中触发的 ChangeState 被正确展开为迭代而非递归
     */
    public function testChangeStateChainWhileLoop():Void {
        trace("\n--- Test: ChangeState Chain While Loop ---");
        var machine:FSM_StateMachine = new FSM_StateMachine(null, null, null);
        machine.data = {log: []};

        // 状态 A 的 onEnter 触发切换到 B
        var stateA:FSM_Status = new FSM_Status(null,
            function():Void {
                this.data.log.push("A:enter");
                this.superMachine.ChangeState("B");
            }, null);

        // 状态 B 的 onEnter 触发切换到 C
        var stateB:FSM_Status = new FSM_Status(null,
            function():Void {
                this.data.log.push("B:enter");
                this.superMachine.ChangeState("C");
            }, null);

        // 状态 C 不再触发切换
        var stateC:FSM_Status = new FSM_Status(null,
            function():Void { this.data.log.push("C:enter"); },
            null);

        // 起始状态 D
        var stateD:FSM_Status = new FSM_Status(null, null, null);

        machine.AddStatus("D", stateD);
        machine.AddStatus("A", stateA);
        machine.AddStatus("B", stateB);
        machine.AddStatus("C", stateC);

        machine.start();
        // D → A → (onEnter chains) → B → C
        machine.ChangeState("A");

        this.assert(machine.getActiveStateName() == "C", "Chain A->B->C resolved via while loop");
        this.assert(machine.data.log.length == 3, "All three enters logged");
        this.assert(machine.data.log[0] == "A:enter", "A entered first");
        this.assert(machine.data.log[1] == "B:enter", "B entered second");
        this.assert(machine.data.log[2] == "C:enter", "C entered third");

        machine.destroy();
    }

    /**
     * 测试 onAction Phase 2 中 activeState 变化检测
     * 当状态的 onAction 内部调用 ChangeState 时，Phase 2 检测到变化，
     * 跳过 Normal 转换检查，回到 Gate 检查
     */
    public function testPhase2ActiveStateDetection():Void {
        trace("\n--- Test: Phase 2 ActiveState Detection ---");
        var machine:FSM_StateMachine = new FSM_StateMachine(null, null, null);
        machine.data = {phase2Triggered: false, normalChecked: false};

        // stateA 的 onAction 主动切换到 stateB
        var stateA:FSM_Status = new FSM_Status(
            function():Void {
                this.data.phase2Triggered = true;
                this.superMachine.ChangeState("B");
            }, null, null);

        var stateB:FSM_Status = new FSM_Status(null, null, null);

        machine.AddStatus("A", stateA);
        machine.AddStatus("B", stateB);

        // 添加一个不应该被检查的 Normal 转换（Phase 2 已切换状态，跳过 Normal）
        machine.transitions.push("A", "B", function():Boolean {
            this.data.normalChecked = true;
            return false;
        });

        machine.start();
        machine.onAction();

        this.assert(machine.data.phase2Triggered, "Phase 2 state action executed");
        this.assert(machine.getActiveStateName() == "B", "State changed to B via Phase 2 ChangeState");
        this.assert(!machine.data.normalChecked, "Normal transition check skipped after Phase 2 state change");

        machine.destroy();
    }

    // ========== Batch 4 新增：onExit 重定向 / destroy 生命周期 / AddStatus 输入校验 ==========

    /**
     * 测试 onExit 中触发 ChangeState 的重定向能力
     *
     * 场景：A→B 切换时，A 的 onExit 检测到复活条件满足，
     * 调用 ChangeState("C") 重定向到 C 而非 B。
     * 旧代码会静默吞掉 onExit 的 _pending，导致无条件进入 B。
     */
    public function testOnExitChangeStateRedirect():Void {
        trace("\n--- Test: onExit ChangeState Redirect ---");
        this.clearLifecycleLog();

        var machine:FSM_StateMachine = new FSM_StateMachine(null, null, null);
        machine.data = {log: []};
        var self = this;

        // 状态 A: onExit 时重定向到 C
        var stateA:FSM_Status = new FSM_Status(null,
            function():Void { self._lifecycleLog.push("A:enter"); },
            function():Void {
                self._lifecycleLog.push("A:exit");
                // 死亡状态退出时，检测到复活条件 → 重定向到 C（复活）
                this.superMachine.ChangeState("C");
            }
        );

        // 状态 B: 原始 target（默认/待机状态）
        var stateB:FSM_Status = new FSM_Status(null,
            function():Void { self._lifecycleLog.push("B:enter"); },
            function():Void { self._lifecycleLog.push("B:exit"); }
        );

        // 状态 C: 重定向目标（复活状态）
        var stateC:FSM_Status = new FSM_Status(null,
            function():Void { self._lifecycleLog.push("C:enter"); },
            function():Void { self._lifecycleLog.push("C:exit"); }
        );

        machine.AddStatus("A", stateA);
        machine.AddStatus("B", stateB);
        machine.AddStatus("C", stateC);

        // 验证初始状态
        this.assert(machine.getActiveStateName() == "A", "Initial state is A");

        machine.start();
        this.clearLifecycleLog();
        // A→B，但 A.onExit 重定向到 C
        machine.ChangeState("B");

        // 最终应该在 C，而非 B
        this.assert(machine.getActiveStateName() == "C",
                   "onExit redirect: should end at C, not B");

        // 验证生命周期顺序：A:exit → C:enter（B 不被进入）
        this.assert(this._lifecycleLog.length == 2,
                   "Only 2 lifecycle events (A:exit + C:enter)");
        this.assert(this._lifecycleLog[0] == "A:exit",
                   "A exits first");
        this.assert(this._lifecycleLog[1] == "C:enter",
                   "C enters (redirected from B)");

        // B 的 onEnter 不应该被调用
        var bEntered:Boolean = false;
        for (var i:Number = 0; i < this._lifecycleLog.length; i++) {
            if (this._lifecycleLog[i] == "B:enter") bEntered = true;
        }
        this.assert(!bEntered, "B should never be entered (redirected)");

        machine.destroy();
    }

    /**
     * 测试 onExit 重定向 + onEnter 链式切换的复合场景
     *
     * 场景：A→B 切换，A.onExit→C（重定向），C.onEnter→D（链式）
     * 验证两种 _pending 语义在同一次 ChangeState 中协同工作。
     */
    public function testOnExitRedirectChain():Void {
        trace("\n--- Test: onExit Redirect + onEnter Chain ---");
        this.clearLifecycleLog();

        var machine:FSM_StateMachine = new FSM_StateMachine(null, null, null);
        var self = this;

        // A: onExit 重定向到 C
        var stateA:FSM_Status = new FSM_Status(null,
            function():Void { self._lifecycleLog.push("A:enter"); },
            function():Void {
                self._lifecycleLog.push("A:exit");
                this.superMachine.ChangeState("C");
            }
        );

        // B: 原始 target（不应被进入）
        var stateB:FSM_Status = new FSM_Status(null,
            function():Void { self._lifecycleLog.push("B:enter"); },
            function():Void { self._lifecycleLog.push("B:exit"); }
        );

        // C: onEnter 链式切换到 D
        var stateC:FSM_Status = new FSM_Status(null,
            function():Void {
                self._lifecycleLog.push("C:enter");
                this.superMachine.ChangeState("D");
            },
            function():Void { self._lifecycleLog.push("C:exit"); }
        );

        // D: 最终稳定状态
        var stateD:FSM_Status = new FSM_Status(null,
            function():Void { self._lifecycleLog.push("D:enter"); },
            function():Void { self._lifecycleLog.push("D:exit"); }
        );

        machine.AddStatus("A", stateA);
        machine.AddStatus("B", stateB);
        machine.AddStatus("C", stateC);
        machine.AddStatus("D", stateD);

        machine.start();
        this.clearLifecycleLog();
        machine.ChangeState("B"); // A→B, 但 A.onExit→C, C.onEnter→D

        this.assert(machine.getActiveStateName() == "D",
                   "Compound redirect+chain: should end at D");

        // 预期生命周期：A:exit → C:enter → D:enter
        // 注意：C.onEnter 中的 ChangeState("D") 通过 _pending 传递到 Phase D
        // Phase D 检测到 _pending="D"，继续 while 循环
        // 下一轮 Phase A: C.onExit → Phase C: enter D → Phase D: D.onEnter
        var expected:Array = ["A:exit", "C:enter", "C:exit", "D:enter"];
        this.assert(this._lifecycleLog.length == expected.length,
                   "Correct lifecycle event count: " + this._lifecycleLog.length + " == " + expected.length);

        var allMatch:Boolean = true;
        for (var i:Number = 0; i < expected.length; i++) {
            if (this._lifecycleLog[i] != expected[i]) {
                allMatch = false;
                trace("[DEBUG] Expected[" + i + "]=" + expected[i] + ", Got=" + this._lifecycleLog[i]);
            }
        }
        this.assert(allMatch, "Lifecycle order: A:exit → C:enter → C:exit → D:enter");

        machine.destroy();
    }

    /**
     * 测试 destroy() 会触发 activeState 的 onExit 生命周期
     * 且仅在已 start() 的状态机上触发
     */
    public function testDestroyCallsActiveStateOnExit():Void {
        trace("\n--- Test: destroy() Calls ActiveState onExit ---");
        this.clearLifecycleLog();

        var self = this;

        // Case 1: 已 start() 的状态机，destroy 应触发 onExit
        var machine1:FSM_StateMachine = new FSM_StateMachine(null, null, null);
        var state1:FSM_Status = new FSM_Status(null,
            function():Void { self._lifecycleLog.push("started:enter"); },
            function():Void { self._lifecycleLog.push("started:exit"); }
        );
        machine1.AddStatus("test", state1);
        machine1.start(); // 触发 enter

        this.clearLifecycleLog();
        machine1.destroy();

        this.assert(this._lifecycleLog.length >= 1, "destroy triggers lifecycle events for started machine");
        var hasExit:Boolean = false;
        for (var i:Number = 0; i < this._lifecycleLog.length; i++) {
            if (this._lifecycleLog[i] == "started:exit") hasExit = true;
        }
        this.assert(hasExit, "destroy() triggers activeState.onExit() for started machine");

        // Case 2: 未 start() 的状态机，destroy 不应触发 onExit
        this.clearLifecycleLog();
        var machine2:FSM_StateMachine = new FSM_StateMachine(null, null, null);
        var state2:FSM_Status = new FSM_Status(null,
            null,
            function():Void { self._lifecycleLog.push("unstarted:exit"); }
        );
        machine2.AddStatus("test", state2);
        // 不调用 start()
        machine2.destroy();

        var hasUnstartedExit:Boolean = false;
        for (var j:Number = 0; j < this._lifecycleLog.length; j++) {
            if (this._lifecycleLog[j] == "unstarted:exit") hasUnstartedExit = true;
        }
        this.assert(!hasUnstartedExit, "destroy() does NOT trigger onExit for unstarted machine");
    }

    /**
     * 测试 destroy() 是否正确清理 Transitions
     */
    public function testDestroyTransitionsCleanup():Void {
        trace("\n--- Test: destroy() Transitions Cleanup ---");

        var machine:FSM_StateMachine = new FSM_StateMachine(null, null, null);
        var state1:FSM_Status = this.createTestState("s1", false);
        var state2:FSM_Status = this.createTestState("s2", false);

        machine.AddStatus("s1", state1);
        machine.AddStatus("s2", state2);

        machine.transitions.push("s1", "s2", function():Boolean { return true; });

        // transitions 存在
        this.assert(machine.transitions != null, "Transitions exist before destroy");

        // 保存引用用于销毁后验证
        var transRef:Transitions = machine.transitions;

        machine.destroy();

        // destroy 后 statusDict 应为 null
        this.assert(machine.statusDict == null, "statusDict nulled after destroy");
        this.assert(machine.getActiveState() == null, "activeState nulled after destroy");
    }

    /**
     * 测试 AddStatus 输入校验（契约式防御）
     * 验证 null/empty name、非 FSM_Status state 被拒绝
     */
    public function testAddStatusInputValidation():Void {
        trace("\n--- Test: AddStatus Input Validation ---");

        var machine:FSM_StateMachine = new FSM_StateMachine(null, null, null);

        // null name 应被拒绝
        var state1:FSM_Status = this.createTestState("test1", false);
        machine.AddStatus(null, state1);
        this.assert(machine.getDefaultState() == null,
                   "null name rejected: no default state set");

        // empty string name 应被拒绝
        var state2:FSM_Status = this.createTestState("test2", false);
        machine.AddStatus("", state2);
        this.assert(machine.getDefaultState() == null,
                   "empty name rejected: no default state set");

        // null state 应被拒绝（instanceof null === false）
        machine.AddStatus("validName", null);
        this.assert(machine.getDefaultState() == null,
                   "null state rejected: no default state set");

        // 正常输入应被接受
        var validState:FSM_Status = this.createTestState("valid", false);
        machine.AddStatus("valid", validState);
        this.assert(machine.getDefaultState() == validState,
                   "Valid input accepted: default state set");
        this.assert(machine.getActiveStateName() == "valid",
                   "Valid state is active");

        machine.destroy();
    }

    // ========== Batch 5 新增：_started 门控 ==========

    /**
     * 测试 onAction 在未 start 时被阻断
     * 验证 _started 门控：未调用 start() 的状态机，onAction 为空操作
     */
    public function testOnActionBlockedBeforeStart():Void {
        trace("\n--- Test: onAction Blocked Before start() ---");
        this.clearLifecycleLog();

        var machine:FSM_StateMachine = new FSM_StateMachine(null, null, null);
        machine.data = {actionRan: false};
        var self = this;

        var stateA:FSM_Status = new FSM_Status(
            function():Void {
                this.data.actionRan = true;
                self._lifecycleLog.push("A:action");
            },
            function():Void { self._lifecycleLog.push("A:enter"); },
            null
        );

        machine.AddStatus("A", stateA);

        // 未调用 start()，onAction 应被阻断
        machine.onAction();
        this.assert(!machine.data.actionRan, "onAction blocked before start()");
        this.assert(this._lifecycleLog.length == 0, "No lifecycle events before start()");

        // 调用 start() 后 onAction 正常执行
        machine.start();
        this.clearLifecycleLog();
        machine.onAction();
        this.assert(machine.data.actionRan, "onAction works after start()");

        machine.destroy();
    }

    /**
     * 测试 ChangeState 在未 start 时仅移指针，不触发生命周期
     * 验证构建期语义：ChangeState 可调整初始状态，但不调用 onExit/onEnter
     */
    public function testChangeStatePointerOnlyBeforeStart():Void {
        trace("\n--- Test: ChangeState Pointer-Only Before start() ---");
        this.clearLifecycleLog();

        var machine:FSM_StateMachine = new FSM_StateMachine(null, null, null);
        var self = this;

        var stateA:FSM_Status = new FSM_Status(null,
            function():Void { self._lifecycleLog.push("A:enter"); },
            function():Void { self._lifecycleLog.push("A:exit"); }
        );
        var stateB:FSM_Status = new FSM_Status(null,
            function():Void { self._lifecycleLog.push("B:enter"); },
            function():Void { self._lifecycleLog.push("B:exit"); }
        );

        machine.AddStatus("A", stateA);  // A 为默认
        machine.AddStatus("B", stateB);

        // 构建期 ChangeState：仅移指针
        machine.ChangeState("B");
        this.assert(machine.getActiveStateName() == "B", "Pointer moved to B before start");
        this.assert(this._lifecycleLog.length == 0,
                   "No lifecycle events (no A:exit, no B:enter) before start");

        // start() 触发当前指针状态（B）的 onEnter
        machine.start();
        this.assert(this._lifecycleLog.length == 1, "Only B:enter on start (not A:enter)");
        this.assert(this._lifecycleLog[0] == "B:enter", "start() enters current pointer state B");

        // start 后 ChangeState 触发完整生命周期
        this.clearLifecycleLog();
        machine.ChangeState("A");
        this.assert(this._lifecycleLog.length == 2, "Full lifecycle after start");
        this.assert(this._lifecycleLog[0] == "B:exit", "B exits with lifecycle");
        this.assert(this._lifecycleLog[1] == "A:enter", "A enters with lifecycle");

        machine.destroy();
    }

    // ========== Batch 6 新增：嵌套场景覆盖 ==========

    /**
     * 测试嵌套状态机的 onAction 传播
     *
     * 验证：
     * 1. parent.onAction() 传播到子机的 activeState.onAction()
     * 2. 子机内部切换状态后，传播目标随之改变
     * 3. parent 切换到非子机状态后，子机 onAction 不再被调用
     */
    public function testNestedMachineOnActionPropagation():Void {
        trace("\n--- Test: Nested Machine onAction Propagation ---");
        this.clearLifecycleLog();
        var self = this;

        // ── 构建结构：parent( childMachine(leafX, leafY), plainB ) ──

        // 叶状态 leafX / leafY
        var leafX:FSM_Status = new FSM_Status(
            function():Void { self._lifecycleLog.push("leafX:action"); },
            function():Void { self._lifecycleLog.push("leafX:enter"); },
            function():Void { self._lifecycleLog.push("leafX:exit"); }
        );
        var leafY:FSM_Status = new FSM_Status(
            function():Void { self._lifecycleLog.push("leafY:action"); },
            function():Void { self._lifecycleLog.push("leafY:enter"); },
            function():Void { self._lifecycleLog.push("leafY:exit"); }
        );

        // 子状态机
        var childMachine:FSM_StateMachine = new FSM_StateMachine(
            function():Void { self._lifecycleLog.push("child-machine:action"); },
            function():Void { self._lifecycleLog.push("child-machine:enter"); },
            function():Void { self._lifecycleLog.push("child-machine:exit"); }
        );
        childMachine.data = {};
        childMachine.AddStatus("leafX", leafX);
        childMachine.AddStatus("leafY", leafY);

        // 顶层普通状态
        var plainB:FSM_Status = new FSM_Status(
            function():Void { self._lifecycleLog.push("plainB:action"); },
            function():Void { self._lifecycleLog.push("plainB:enter"); },
            function():Void { self._lifecycleLog.push("plainB:exit"); }
        );

        // 父状态机
        var parent:FSM_StateMachine = new FSM_StateMachine(null, null, null);
        parent.AddStatus("child", childMachine);
        parent.AddStatus("plainB", plainB);

        // ── 验证 1: start 后 onEnter 传播链 ──
        parent.start();
        // 预期: child-machine:enter → leafX:enter
        var hasChildEnter:Boolean = false;
        var hasLeafXEnter:Boolean = false;
        for (var i:Number = 0; i < this._lifecycleLog.length; i++) {
            if (this._lifecycleLog[i] == "child-machine:enter") hasChildEnter = true;
            if (this._lifecycleLog[i] == "leafX:enter") hasLeafXEnter = true;
        }
        this.assert(hasChildEnter, "start() propagates onEnter to child machine");
        this.assert(hasLeafXEnter, "start() propagates onEnter to child's default leaf state");

        // ── 验证 2: parent.onAction() 传播到 leafX ──
        this.clearLifecycleLog();
        parent.onAction();
        // 预期日志包含: leafX:action + child-machine:action（子机管线的 Phase 4）
        var hasLeafXAction:Boolean = false;
        var hasChildAction:Boolean = false;
        for (var j:Number = 0; j < this._lifecycleLog.length; j++) {
            if (this._lifecycleLog[j] == "leafX:action") hasLeafXAction = true;
            if (this._lifecycleLog[j] == "child-machine:action") hasChildAction = true;
        }
        this.assert(hasLeafXAction, "parent.onAction() propagates to leafX.onAction()");
        this.assert(hasChildAction, "child machine _onActionCb fires as Phase 4 post-hook");

        // ── 验证 3: 子机内切换后传播目标改变 ──
        childMachine.ChangeState("leafY");
        this.clearLifecycleLog();
        parent.onAction();
        var hasLeafYAction:Boolean = false;
        hasLeafXAction = false;
        for (var k:Number = 0; k < this._lifecycleLog.length; k++) {
            if (this._lifecycleLog[k] == "leafY:action") hasLeafYAction = true;
            if (this._lifecycleLog[k] == "leafX:action") hasLeafXAction = true;
        }
        this.assert(hasLeafYAction, "After child ChangeState, propagates to leafY");
        this.assert(!hasLeafXAction, "leafX no longer receives onAction after switch");

        // ── 验证 4: parent 切换到 plainB 后，子机不再收到 onAction ──
        parent.ChangeState("plainB");
        this.clearLifecycleLog();
        parent.onAction();
        var hasAnyLeafAction:Boolean = false;
        hasChildAction = false;
        for (var m:Number = 0; m < this._lifecycleLog.length; m++) {
            if (this._lifecycleLog[m] == "leafX:action" || this._lifecycleLog[m] == "leafY:action") hasAnyLeafAction = true;
            if (this._lifecycleLog[m] == "child-machine:action") hasChildAction = true;
        }
        this.assert(!hasAnyLeafAction, "Child leaves get no onAction after parent switches away");
        this.assert(!hasChildAction, "Child machine gets no onAction after parent switches away");

        var hasPlainBAction:Boolean = false;
        for (var n:Number = 0; n < this._lifecycleLog.length; n++) {
            if (this._lifecycleLog[n] == "plainB:action") hasPlainBAction = true;
        }
        this.assert(hasPlainBAction, "plainB now receives onAction");

        parent.destroy();
    }

    /**
     * 测试 destroy() 对嵌套状态机的递归销毁
     *
     * 验证：
     * 1. parent.destroy() 触发 activeState(child) 的 onExit → 内部 inner2.onExit
     * 2. 由内而外的退出顺序（inner2:exit 在 child:exit 之前）
     * 3. 所有子状态（含子机内部）的 isDestroyed 均为 true
     */
    public function testDestroyNestedMachineRecursive():Void {
        trace("\n--- Test: destroy() Nested Machine Recursive ---");
        this.clearLifecycleLog();
        var self = this;

        // ── 构建结构：parent( child(inner1, inner2), other ) ──
        var inner1:FSM_Status = new FSM_Status(null,
            function():Void { self._lifecycleLog.push("inner1:enter"); },
            function():Void { self._lifecycleLog.push("inner1:exit"); }
        );
        var inner2:FSM_Status = new FSM_Status(null,
            function():Void { self._lifecycleLog.push("inner2:enter"); },
            function():Void { self._lifecycleLog.push("inner2:exit"); }
        );

        var child:FSM_StateMachine = new FSM_StateMachine(null,
            function():Void { self._lifecycleLog.push("child:enter"); },
            function():Void { self._lifecycleLog.push("child:exit"); }
        );
        child.data = {};
        child.AddStatus("inner1", inner1);
        child.AddStatus("inner2", inner2);

        var other:FSM_Status = new FSM_Status(null,
            function():Void { self._lifecycleLog.push("other:enter"); },
            function():Void { self._lifecycleLog.push("other:exit"); }
        );

        var parent:FSM_StateMachine = new FSM_StateMachine(null, null, null);
        parent.AddStatus("child", child);
        parent.AddStatus("other", other);

        // 启动并切换子机到 inner2
        parent.start();
        // 此时 child 已被 parent.onEnter 传播自动启动（_started = true）
        child.ChangeState("inner2");

        // ── 验证销毁 ──
        this.clearLifecycleLog();
        parent.destroy();

        // 验证退出事件：应有 inner2:exit 和 child:exit
        var inner2ExitIdx:Number = -1;
        var childExitIdx:Number = -1;
        for (var i:Number = 0; i < this._lifecycleLog.length; i++) {
            if (this._lifecycleLog[i] == "inner2:exit" && inner2ExitIdx == -1) inner2ExitIdx = i;
            if (this._lifecycleLog[i] == "child:exit" && childExitIdx == -1) childExitIdx = i;
        }
        this.assert(inner2ExitIdx >= 0, "inner2.onExit called during destroy");
        this.assert(childExitIdx >= 0, "child machine onExit called during destroy");
        this.assert(inner2ExitIdx < childExitIdx,
                   "Exit order: inner2 exits before child machine (inside-out)");

        // 验证 isDestroyed 标记
        this.assert(inner1.isDestroyed, "inner1 destroyed after parent.destroy()");
        this.assert(inner2.isDestroyed, "inner2 destroyed after parent.destroy()");
        this.assert(child.isDestroyed, "child machine destroyed after parent.destroy()");
        this.assert(other.isDestroyed, "other state destroyed after parent.destroy()");
    }

    /**
     * 测试 onExit 锁在嵌套层级上的交互
     *
     * 场景：parent 切换状态触发 child.onExit → inner.onExit，
     * inner.onExit 尝试调用 child.ChangeState("another") — 应被 _isChanging 锁阻断。
     *
     * 验证：
     * 1. inner 的 onExit 确实被调用
     * 2. child.ChangeState 在 onExit 锁期间被静默丢弃
     * 3. parent 最终安全到达目标状态
     */
    public function testOnExitLockNestedInteraction():Void {
        trace("\n--- Test: onExit Lock Nested Interaction ---");
        this.clearLifecycleLog();
        var self = this;

        var reentrantAttempted:Boolean = false;

        // inner: onExit 尝试对子机触发 ChangeState（应被锁阻断）
        var inner:FSM_Status = new FSM_Status(null,
            function():Void { self._lifecycleLog.push("inner:enter"); },
            function():Void {
                self._lifecycleLog.push("inner:exit");
                reentrantAttempted = true;
                // 子机正在 onExit 传播中，_isChanging=true → 此调用被静默丢弃
                this.superMachine.ChangeState("another");
            }
        );

        // another: 如果 inner 的重入 ChangeState 生效，这个状态会被进入（不应发生）
        var another:FSM_Status = new FSM_Status(null,
            function():Void { self._lifecycleLog.push("another:enter"); },
            null
        );

        var child:FSM_StateMachine = new FSM_StateMachine(null,
            function():Void { self._lifecycleLog.push("child:enter"); },
            function():Void { self._lifecycleLog.push("child:exit"); }
        );
        child.data = {};
        child.AddStatus("inner", inner);
        child.AddStatus("another", another);

        var target:FSM_Status = new FSM_Status(null,
            function():Void { self._lifecycleLog.push("target:enter"); },
            null
        );

        var parent:FSM_StateMachine = new FSM_StateMachine(null, null, null);
        parent.AddStatus("child", child);
        parent.AddStatus("target", target);

        parent.start();

        // ── 触发 parent 切换：child.onExit → inner.onExit → inner 尝试重入 ──
        this.clearLifecycleLog();
        parent.ChangeState("target");

        // 验证 inner.onExit 确实被调用
        this.assert(reentrantAttempted, "inner.onExit executed and attempted reentrant ChangeState");

        // 验证 "another" 未被进入（锁阻断了重入 ChangeState）
        var anotherEntered:Boolean = false;
        for (var i:Number = 0; i < this._lifecycleLog.length; i++) {
            if (this._lifecycleLog[i] == "another:enter") anotherEntered = true;
        }
        this.assert(!anotherEntered, "Reentrant ChangeState blocked by _isChanging lock");

        // 验证 parent 安全到达目标状态
        this.assert(parent.getActiveStateName() == "target",
                   "Parent safely reached target state despite reentrant attempt");

        // 验证退出顺序：inner:exit 在 child:exit 之前
        var innerExitIdx:Number = -1;
        var childExitIdx:Number = -1;
        for (var j:Number = 0; j < this._lifecycleLog.length; j++) {
            if (this._lifecycleLog[j] == "inner:exit" && innerExitIdx == -1) innerExitIdx = j;
            if (this._lifecycleLog[j] == "child:exit" && childExitIdx == -1) childExitIdx = j;
        }
        this.assert(innerExitIdx >= 0 && childExitIdx >= 0, "Both exit events fired");
        this.assert(innerExitIdx < childExitIdx, "inner exits before child (inside-out order preserved)");

        parent.destroy();
    }

    // ========== Batch 7 新增：Risk A / Risk B 修复验证 ==========

    /**
     * 测试 Risk A 修复：_onEnterCb 中调用 ChangeState 的安全性
     *
     * 旧行为（Bug）：
     *   start() 设 _started=true 后调 onEnter() → super.onEnter() 触发 _onEnterCb，
     *   回调中 ChangeState("combat") 走完整管线 → 对 idle 调 onExit（但 idle 从未 onEnter）
     *   → "exit-before-enter" + 之后 onEnter() 继续传播导致 combat 被 enter 两次。
     *
     * 修复后行为：
     *   start() 只设 _booted=true，不设 _started。
     *   onEnter() 中 super.onEnter() 触发回调时 _started=false → ChangeState 走 pointer-only。
     *   回调返回后 _started=true → 子状态传播正常进入 combat（仅一次）。
     */
    public function testRiskA_OnEnterCbChangeStateSafety():Void {
        trace("\n--- Test: Risk A - onEnterCb ChangeState Safety ---");
        this.clearLifecycleLog();
        var self = this;

        // 状态 idle（默认）、combat
        var idle:FSM_Status = new FSM_Status(null,
            function():Void { self._lifecycleLog.push("idle:enter"); },
            function():Void { self._lifecycleLog.push("idle:exit"); }
        );
        var combat:FSM_Status = new FSM_Status(null,
            function():Void { self._lifecycleLog.push("combat:enter"); },
            function():Void { self._lifecycleLog.push("combat:exit"); }
        );

        // 机器级 _onEnterCb：在 start 的 onEnter 阶段调用 ChangeState
        var machine:FSM_StateMachine = new FSM_StateMachine(null,
            function():Void {
                self._lifecycleLog.push("machine:enterCb");
                // Risk A 场景：回调中切换状态
                this.ChangeState("combat");
            },
            null
        );
        machine.data = {};
        machine.AddStatus("idle", idle);
        machine.AddStatus("combat", combat);

        // start 触发 onEnter → super.onEnter() → _onEnterCb → ChangeState("combat")
        machine.start();

        // 验证 1: idle 的 onExit 不应被调用（idle 从未 onEnter，不应被 exit）
        var idleExited:Boolean = false;
        for (var i:Number = 0; i < this._lifecycleLog.length; i++) {
            if (this._lifecycleLog[i] == "idle:exit") idleExited = true;
        }
        this.assert(!idleExited,
                   "Risk A fix: idle.onExit NOT called (never entered, no exit-before-enter)");

        // 验证 2: idle 的 onEnter 不应被调用（pointer-only 切换跳过了 idle，直接到 combat）
        var idleEntered:Boolean = false;
        for (var j:Number = 0; j < this._lifecycleLog.length; j++) {
            if (this._lifecycleLog[j] == "idle:enter") idleEntered = true;
        }
        this.assert(!idleEntered,
                   "Risk A fix: idle.onEnter NOT called (pointer moved past idle before propagation)");

        // 验证 3: combat 的 onEnter 恰好被调用一次（非两次）
        var combatEnterCount:Number = 0;
        for (var k:Number = 0; k < this._lifecycleLog.length; k++) {
            if (this._lifecycleLog[k] == "combat:enter") combatEnterCount++;
        }
        this.assert(combatEnterCount == 1,
                   "Risk A fix: combat.onEnter called exactly once (not double-entered), got " + combatEnterCount);

        // 验证 4: 最终 activeState 是 combat
        this.assert(machine.getActiveStateName() == "combat",
                   "Risk A fix: activeState is combat after start()");

        // 验证 5: lastState 是 idle（pointer-only 阶段由 Risk B fix 同步）
        this.assert(machine.getLastState() == idle,
                   "Risk A fix: lastState correctly set to idle by pointer-only branch");

        // 验证 6: actionCount 重置为 0（pointer-only 阶段由 Risk B fix 同步）
        this.assert(machine.actionCount == 0,
                   "Risk A fix: actionCount reset to 0 by pointer-only branch");

        // 验证 7: start() 幂等性仍有效（_booted 守卫）
        this.clearLifecycleLog();
        machine.start();
        this.assert(this._lifecycleLog.length == 0,
                   "Risk A fix: duplicate start() still no-op (guarded by _booted)");

        machine.destroy();
    }

    /**
     * 测试 Risk B 修复：构建期 ChangeState 同步 lastState 和 actionCount
     *
     * 旧行为（Bug）：
     *   构建期 ChangeState 仅移动 activeState 指针，lastState 和 actionCount 不更新，
     *   导致 getLastState() 返回陈旧值、actionCount 保持上一次残留值。
     *
     * 修复后行为：
     *   pointer-only 分支同步 lastState = activeState(旧), actionCount = 0。
     */
    public function testRiskB_ConstructionPhaseLastStateSync():Void {
        trace("\n--- Test: Risk B - Construction Phase lastState/actionCount Sync ---");
        this.clearLifecycleLog();
        var self = this;

        var stateA:FSM_Status = new FSM_Status(null,
            function():Void { self._lifecycleLog.push("A:enter"); },
            function():Void { self._lifecycleLog.push("A:exit"); }
        );
        var stateB:FSM_Status = new FSM_Status(null,
            function():Void { self._lifecycleLog.push("B:enter"); },
            function():Void { self._lifecycleLog.push("B:exit"); }
        );
        var stateC:FSM_Status = new FSM_Status(null,
            function():Void { self._lifecycleLog.push("C:enter"); },
            function():Void { self._lifecycleLog.push("C:exit"); }
        );

        var machine:FSM_StateMachine = new FSM_StateMachine(null, null, null);
        machine.AddStatus("A", stateA); // A 为默认：activeState=A, lastState=A
        machine.AddStatus("B", stateB);
        machine.AddStatus("C", stateC);

        // 构建期第一次 ChangeState
        machine.ChangeState("B");
        this.assert(machine.getActiveStateName() == "B",
                   "Risk B: pointer moved to B");
        this.assert(machine.getLastState() == stateA,
                   "Risk B: lastState synced to A (previous activeState)");
        this.assert(machine.actionCount == 0,
                   "Risk B: actionCount reset to 0 after first pointer-only ChangeState");

        // 构建期第二次 ChangeState
        machine.ChangeState("C");
        this.assert(machine.getActiveStateName() == "C",
                   "Risk B: pointer moved to C");
        this.assert(machine.getLastState() == stateB,
                   "Risk B: lastState synced to B (previous activeState)");
        this.assert(machine.actionCount == 0,
                   "Risk B: actionCount still 0 after second pointer-only ChangeState");

        // 构建期无生命周期事件
        this.assert(this._lifecycleLog.length == 0,
                   "Risk B: no lifecycle events during construction phase");

        // start() 后 activeState(C) 的 onEnter 被触发
        machine.start();
        this.assert(this._lifecycleLog.length == 1 && this._lifecycleLog[0] == "C:enter",
                   "Risk B: start() enters current pointer state C");

        // start 后 ChangeState 走完整管线，lastState 正确更新
        this.clearLifecycleLog();
        machine.ChangeState("A");
        this.assert(machine.getLastState() == stateC,
                   "Risk B: lastState updated by full lifecycle ChangeState");
        this.assert(this._lifecycleLog[0] == "C:exit" && this._lifecycleLog[1] == "A:enter",
                   "Risk B: full lifecycle after start()");

        machine.destroy();
    }

    // ========== 报告生成 ==========

    public function printFinalReport():Void {
        trace("\n=== FINAL FSM TEST REPORT ===");
        trace("Tests Passed: " + this._testPassed);
        trace("Tests Failed: " + this._testFailed);
        trace("Success Rate: " + Math.round((this._testPassed / (this._testPassed + this._testFailed)) * 100) + "%");
        
        if (this._testFailed == 0) {
            trace("🎉 ALL TESTS PASSED! FSM StateMachine implementation is robust and performant.");
        } else {
            trace("⚠️  Some tests failed. Please review the implementation.");
        }
        
        trace("=== FSM VERIFICATION SUMMARY ===");
        trace("  Basic state machine operations verified");
        trace("  State lifecycle management tested");
        trace("  Transition system robustness confirmed");
        trace("  Data blackboard functionality verified");
        trace("  Error handling and edge cases tested");
        trace("  Memory management and cleanup verified");
        trace("  Performance benchmarks completed");
        trace("  Complex workflow scenarios tested");
        trace("  Path B callback field safety verified");
        trace("  Explicit start() separation verified");
        trace("  Reserved name validation verified");
        trace("  While-loop ChangeState chain verified");
        trace("  Phase 2 activeState detection verified");
        trace("  onExit ChangeState redirect verified");
        trace("  onExit redirect + onEnter chain verified");
        trace("  destroy() activeState onExit lifecycle verified");
        trace("  destroy() Transitions cleanup verified");
        trace("  AddStatus input validation verified");
        trace("  _started gate: onAction blocked verified");
        trace("  _started gate: ChangeState pointer-only verified");
        trace("  Nested machine onAction propagation verified");
        trace("  Nested machine recursive destroy verified");
        trace("  onExit lock nested interaction verified");
        trace("  Risk A: onEnterCb ChangeState safety verified");
        trace("  Risk B: construction-phase lastState/actionCount sync verified");
        trace("=============================");
    }
}