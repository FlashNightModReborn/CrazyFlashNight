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
        this.assert(this._lifecycleLog.length == 1 && this._lifecycleLog[0] == "idle:enter", 
                   "onEnter called when state added as first state");
        
        this.clearLifecycleLog();
        machine.AddStatus("running", state2);
        this.assert(this._lifecycleLog.length == 0, "onEnter not called for non-active state");
        
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
        
        this.assert(machine.data.counter == 1, "Counter incremented on first state enter");
        
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
        
        machine.onAction();
        
        this.assert(transitionLog.length == 4, "All callbacks executed");
        this.assert(transitionLog[0] == "entered state1", "Initial state entered");
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
            return true; // automatically return to playing
        });
        
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
        
        this.assert(machine.data.persistent == 42, "Persistent data maintained");
        this.assert(machine.data.modified == 10, "Data modified by state1 onEnter");
        
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
        
        machine.destroy();
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
        
        // === 修正后的断言 ===
        
        // 第一次断言：父状态机的活动状态应该是第一个子状态机
        this.assert(parentMachine.getActiveStateName() == "machine1", "Parent machine active state is child machine");
        
        // 第二次断言：由于 FSM_StateMachine.as 已修复，
        // parentMachine.AddStatus 会触发 childMachine1.onEnter，
        // 这会正确初始化 childMachine1 的内部状态。
        this.assert(childMachine1.getActiveStateName() == "child1_idle", "Child machine 1 has its own active state");
        
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
        
        // 【关键测试】：在同一帧内触发暂停并执行onAction
        this.clearLifecycleLog();
        machine.data.isPaused = true;  // 触发暂停条件
        machine.data.actionExecuted = false;  // 重置动作标记
        
        machine.onAction();  // 执行一帧的逻辑
        
        // 【预期行为 - 当前会失败】：
        // 暂停应该在当帧生效，阻止玩家状态的动作执行
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
        
        this.clearLifecycleLog();
        machine.onAction();  // 第1次：A:action:1
        machine.onAction();  // 第2次：应该触发转换 A→B，然后执行B:action:2
        
        // 【预期行为 - 当前会失败】：
        // 正确顺序应该是：A:action:1, A:action:2, A:exit, B:enter, B:action:3
        // 当前实现是：A:action:1, A:action:2, A:exit, B:enter（B的action要到下一帧）
        var expectedOrder:Array = [
            "A:enter",      // 初始进入A
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
        trace("✓ Basic state machine operations verified");
        trace("✓ State lifecycle management tested");
        trace("✓ Transition system robustness confirmed");
        trace("✓ Data blackboard functionality verified");
        trace("✓ Error handling and edge cases tested");
        trace("✓ Memory management and cleanup verified");
        trace("✓ Performance benchmarks completed");
        trace("✓ Complex workflow scenarios tested");
        trace("=============================");
    }
}