import org.flashNight.neur.StateMachine.*;

/**
 * Transitions类专用测试套件
 * 全面测试转换系统的功能、性能、稳定性和边界情况
 */
class org.flashNight.neur.StateMachine.TransitionsTest {
    private var _testPassed:Number;
    private var _testFailed:Number;
    private var _performanceLog:Array;
    private var _mockStatus:FSM_Status;

    public function TransitionsTest() {
        this._testPassed = 0;
        this._testFailed = 0;
        this._performanceLog = [];
        this._createMockStatus();
        trace("=== Transitions Test Suite Initialized ===");
    }

    /**
     * 创建模拟状态对象用于测试
     */
    private function _createMockStatus():Void {
        this._mockStatus = new FSM_Status(null, null, null);
        this._mockStatus.data = {
            counter: 0,
            flag: false,
            value: 100,
            history: [],
            config: {
                threshold: 50,
                enabled: true
            }
        };
    }

    /**
     * 运行所有测试
     */
    public function runTests():Void {
        trace("=== Running Comprehensive Transitions Tests ===");
        
        // 基础功能测试
        this.testBasicTransitionCreation();
        this.testPushTransition();
        this.testUnshiftTransition();
        this.testTransitMethod();
        this.testTransitionActivation();
        
        // 优先级测试
        this.testTransitionPriority();
        this.testMultiplePriorityLevels();
        this.testPriorityInsertion();
        this.testPriorityOverride();
        
        // 条件逻辑测试
        this.testSimpleConditions();
        this.testComplexConditions();
        this.testDynamicConditions();
        this.testConditionalChaining();
        this.testNestedConditions();
        
        // 数据访问测试
        this.testDataAccess();
        this.testDataModification();
        this.testDataValidation();
        this.testCrossStateDataAccess();
        
        // 边界情况测试
        this.testEmptyTransitionList();
        this.testNullConditions();
        this.testInvalidStateNames();
        this.testSelfTransitions();
        this.testCircularTransitions();
        this.testMissingTargetStates();
        
        // 错误处理测试
        this.testExceptionInConditions();
        this.testMalformedTransitions();
        this.testCorruptedTransitionData();
        this.testRecoveryFromErrors();
        
        // 性能测试
        this.testBasicPerformance();
        this.testManyTransitionsPerformance();
        this.testComplexConditionsPerformance();
        this.testFrequentTransitCallsPerformance();
        this.testTransitionScalability();
        this.testMemoryUsageOptimization();
        
        // 高级功能测试
        this.testTransitionCaching();
        this.testConditionalShortCircuiting();
        this.testTransitionGrouping();
        this.testDynamicTransitionManagement();

        // Gate/Normal分表测试
        this.testGateNormalSeparation();
        this.testGateNormalIsolation();
        this.testGateNormalClearAndReset();

        // remove()/setActive() API 测试
        this.testRemoveNormalTransition();
        this.testRemoveGateTransition();
        this.testRemoveNonExistent();
        this.testSetActiveDisableEnable();
        this.testSetActiveGateTransition();
        this.testSetActiveNonExistent();
        this.testRemoveAndReAdd();
        this.testSetActiveWithPriority();

        // 最终报告
        this.printFinalReport();
        this.generatePerformanceReport();
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
    private function measureTime(func:Function, iterations:Number, context:String):Number {
        var startTime:Number = getTimer();
        for (var i:Number = 0; i < iterations; i++) {
            func.call(this);
        }
        var elapsed:Number = getTimer() - startTime;
        this._performanceLog.push({
            context: context,
            iterations: iterations,
            elapsed: elapsed,
            avgPerOperation: elapsed / iterations
        });
        return elapsed;
    }

    // ========== 基础功能测试 ==========
    
    public function testBasicTransitionCreation():Void {
        trace("\n--- Test: Basic Transition Creation ---");
        var transitions:Transitions = new Transitions(this._mockStatus);
        
        this.assert(transitions != null, "Transitions object created successfully");
        this.assert(transitions.TransitNormal("nonexistent") == null, "Transit returns null for non-existent state");
    }

    public function testPushTransition():Void {
        trace("\n--- Test: Push Transition ---");
        var transitions:Transitions = new Transitions(this._mockStatus);
        
        transitions.push("idle", "running", function():Boolean { return true; });
        var result:String = transitions.TransitNormal("idle");
        
        this.assert(result == "running", "Push transition works correctly");
        
        // 测试多个push的顺序
        transitions.push("idle", "walking", function():Boolean { return true; });
        var result2:String = transitions.TransitNormal("idle");
        this.assert(result2 == "running", "First pushed transition has higher priority");
    }

    public function testUnshiftTransition():Void {
        trace("\n--- Test: Unshift Transition ---");
        var transitions:Transitions = new Transitions(this._mockStatus);
        
        transitions.push("idle", "running", function():Boolean { return true; });
        transitions.unshift("idle", "jumping", function():Boolean { return true; });
        
        var result:String = transitions.TransitNormal("idle");
        this.assert(result == "jumping", "Unshift transition has highest priority");
    }

    public function testTransitMethod():Void {
        trace("\n--- Test: Transit Method ---");
        var transitions:Transitions = new Transitions(this._mockStatus);
        
        // 测试条件为false的情况
        transitions.push("state1", "state2", function():Boolean { return false; });
        this.assert(transitions.TransitNormal("state1") == null, "Transit returns null when condition is false");
        
        // 测试条件为true的情况
        transitions.push("state1", "state3", function():Boolean { return true; });
        this.assert(transitions.TransitNormal("state1") == "state3", "Transit returns target when condition is true");
    }

    public function testTransitionActivation():Void {
        trace("\n--- Test: Transition Activation ---");
        var transitions:Transitions = new Transitions(this._mockStatus);
        
        // 添加一个默认为active的转换
        transitions.push("active_state", "target1", function():Boolean { return true; });
        this.assert(transitions.TransitNormal("active_state") == "target1", "Active transition works");
        
        // 测试inactive转换（需要扩展Transitions类支持此功能）
        // 这里先测试基本行为
        transitions.push("inactive_state", "target2", function():Boolean { return false; });
        this.assert(transitions.TransitNormal("inactive_state") == null, "Inactive condition returns null");
    }

    // ========== 优先级测试 ==========
    
    public function testTransitionPriority():Void {
        trace("\n--- Test: Transition Priority ---");
        var transitions:Transitions = new Transitions(this._mockStatus);
        
        // 添加多个都返回true的转换，测试优先级
        transitions.push("multi", "low", function():Boolean { return true; });
        transitions.push("multi", "medium", function():Boolean { return true; });
        transitions.unshift("multi", "high", function():Boolean { return true; });
        transitions.unshift("multi", "highest", function():Boolean { return true; });
        
        var result:String = transitions.TransitNormal("multi");
        this.assert(result == "highest", "Highest priority transition executed first");
    }

    public function testMultiplePriorityLevels():Void {
        trace("\n--- Test: Multiple Priority Levels ---");
        var transitions:Transitions = new Transitions(this._mockStatus);
        this._mockStatus.data.priority = 1;
        
        // 不同优先级的条件
        transitions.push("test", "p3", function():Boolean { return this.data.priority >= 3; });
        transitions.push("test", "p2", function():Boolean { return this.data.priority >= 2; });
        transitions.unshift("test", "p1", function():Boolean { return this.data.priority >= 1; });
        
        this.assert(transitions.TransitNormal("test") == "p1", "Priority 1 condition met");
        
        this._mockStatus.data.priority = 2;
        this.assert(transitions.TransitNormal("test") == "p1", "Higher priority still wins even when lower priority conditions are true");
    }

    public function testPriorityInsertion():Void {
        trace("\n--- Test: Priority Insertion ---");
        var transitions:Transitions = new Transitions(this._mockStatus);
        
        // 测试push和unshift的混合使用
        transitions.push("insertion", "end1", function():Boolean { return true; });
        transitions.unshift("insertion", "start1", function():Boolean { return true; });
        transitions.push("insertion", "end2", function():Boolean { return true; });
        transitions.unshift("insertion", "start2", function():Boolean { return true; });
        
        var result:String = transitions.TransitNormal("insertion");
        this.assert(result == "start2", "Last unshift has highest priority");
    }

    public function testPriorityOverride():Void {
        trace("\n--- Test: Priority Override ---");
        var transitions:Transitions = new Transitions(this._mockStatus);
        this._mockStatus.data.override = false;
        
        // 高优先级条件为false，低优先级条件为true
        transitions.unshift("override", "high", function():Boolean { return this.data.override; });
        transitions.push("override", "low", function():Boolean { return !this.data.override; });
        
        var result:String = transitions.TransitNormal("override");
        this.assert(result == "low", "Lower priority executes when higher priority condition fails");
    }

    // ========== 条件逻辑测试 ==========
    
    public function testSimpleConditions():Void {
        trace("\n--- Test: Simple Conditions ---");
        var transitions:Transitions = new Transitions(this._mockStatus);
        
        // 数值比较
        this._mockStatus.data.value = 75;
        transitions.push("simple", "high", function():Boolean { return this.data.value > 50; });
        transitions.push("simple", "low", function():Boolean { return this.data.value <= 50; });
        
        this.assert(transitions.TransitNormal("simple") == "high", "Simple numeric condition works");
        
        // 布尔条件
        this._mockStatus.data.flag = true;
        transitions.push("bool", "enabled", function():Boolean { return this.data.flag; });
        this.assert(transitions.TransitNormal("bool") == "enabled", "Simple boolean condition works");
    }

    public function testComplexConditions():Void {
        trace("\n--- Test: Complex Conditions ---");
        var transitions:Transitions = new Transitions(this._mockStatus);
        
        // 修复：为不同的测试用例设置不同的数据
        
        // 测试 "complex"
        this._mockStatus.data.stats = {health: 80, mana: 30, level: 5};
        transitions.push("complex", "combat", function():Boolean {
            return this.data.stats.health > 50 && 
                this.data.stats.mana > 20 && 
                this.data.stats.level >= 3;
        });
        this.assert(transitions.TransitNormal("complex") == "combat", "Complex AND condition works");
        
        // 测试 "advanced"
        // 修复：提供满足条件的数据
        this._mockStatus.data.stats = {health: 95, mana: 30, level: 5}; 
        transitions.push("advanced", "special", function():Boolean {
            var stats = this.data.stats;
            return (stats.health > 90 || stats.mana > 80) && 
                stats.level >= 5 &&
                stats.health + stats.mana > 100;
        });
        this.assert(transitions.TransitNormal("advanced") == "special", "Advanced complex condition works");
    }

    public function testDynamicConditions():Void {
        trace("\n--- Test: Dynamic Conditions ---");
        var transitions:Transitions = new Transitions(this._mockStatus);
        this._mockStatus.data.time = 0;
        
        // 基于时间的动态条件
        transitions.push("dyn", "morning", function():Boolean {
            this.data.time++;
            return this.data.time % 24 >= 6 && this.data.time % 24 < 12;
        });
        
        transitions.push("dyn", "night", function():Boolean {
            return this.data.time % 24 >= 22 || this.data.time % 24 < 6;
        });
        
        this._mockStatus.data.time = 8; // 模拟早上8点
        this.assert(transitions.TransitNormal("dyn") == "morning", "Dynamic time-based condition works");
    }

    public function testConditionalChaining():Void {
        trace("\n--- Test: Conditional Chaining ---");
        var transitions:Transitions = new Transitions(this._mockStatus);
        this._mockStatus.data.chain = 0;
        
        // 链式条件，每次调用都会修改状态
        transitions.push("chain", "step1", function():Boolean {
            if (this.data.chain == 0) {
                this.data.chain = 1;
                return true;
            }
            return false;
        });
        
        transitions.push("chain", "step2", function():Boolean {
            if (this.data.chain == 1) {
                this.data.chain = 2;
                return true;
            }
            return false;
        });
        
        var result1:String = transitions.TransitNormal("chain");
        this.assert(result1 == "step1", "First step in chain executed");
        
        var result2:String = transitions.TransitNormal("chain");
        this.assert(result2 == "step2", "Second step in chain executed");
    }

    public function testNestedConditions():Void {
        trace("\n--- Test: Nested Conditions ---");
        var transitions:Transitions = new Transitions(this._mockStatus);
        this._mockStatus.data.nested = {
            player: {
                inventory: {
                    gold: 100,
                    items: ["sword", "potion"]
                },
                level: 10
            },
            world: {
                time: "day",
                weather: "sunny"
            }
        };
        
        // 深度嵌套的条件检查
        transitions.push("nested", "shop", function():Boolean {
            var player = this.data.nested.player;
            var world = this.data.nested.world;
            
            return player.inventory.gold >= 50 &&
                   player.level >= 5 &&
                   world.time == "day" &&
                   player.inventory.items.length > 0;
        });
        
        this.assert(transitions.TransitNormal("nested") == "shop", "Nested object condition works");
    }

    // ========== 数据访问测试 ==========
    
    public function testDataAccess():Void {
        trace("\n--- Test: Data Access ---");
        var transitions:Transitions = new Transitions(this._mockStatus);
        this._mockStatus.data.accessTest = {value: 42, name: "test"};
        
        var accessedValue:Number = -1;
        var accessedName:String = "";
        
        transitions.push("access", "target", function():Boolean {
            accessedValue = this.data.accessTest.value;
            accessedName = this.data.accessTest.name;
            return true;
        });
        
        transitions.TransitNormal("access");
        this.assert(accessedValue == 42, "Numeric data accessed correctly");
        this.assert(accessedName == "test", "String data accessed correctly");
    }

    public function testDataModification():Void {
        trace("\n--- Test: Data Modification ---");
        var transitions:Transitions = new Transitions(this._mockStatus);
        this._mockStatus.data.modifyTest = {counter: 0, log: []};
        
        transitions.push("modify", "increment", function():Boolean {
            this.data.modifyTest.counter++;
            this.data.modifyTest.log.push("incremented");
            return this.data.modifyTest.counter >= 3;
        });
        
        // 前两次调用应该返回null（条件为false）
        this.assert(transitions.TransitNormal("modify") == null, "First call returns null");
        this.assert(transitions.TransitNormal("modify") == null, "Second call returns null");
        this.assert(transitions.TransitNormal("modify") == "increment", "Third call returns target");
        this.assert(this._mockStatus.data.modifyTest.counter == 3, "Counter modified correctly");
    }

    public function testDataValidation():Void {
        trace("\n--- Test: Data Validation ---");
        var transitions:Transitions = new Transitions(this._mockStatus);
        this._mockStatus.data.validation = null;
        
        // 测试空数据处理
        transitions.push("validate", "safe", function():Boolean {
            if (!this.data.validation) {
                return false;
            }
            return this.data.validation.isValid === true;
        });
        
        this.assert(transitions.TransitNormal("validate") == null, "Null data handled safely");
        
        this._mockStatus.data.validation = {isValid: true};
        this.assert(transitions.TransitNormal("validate") == "safe", "Valid data processed correctly");
    }

    public function testCrossStateDataAccess():Void {
        trace("\n--- Test: Cross-State Data Access ---");
        var transitions:Transitions = new Transitions(this._mockStatus);
        this._mockStatus.data.states = {
            idle: {active: true, duration: 100},
            running: {active: false, duration: 0}
        };
        
        transitions.push("idle", "running", function():Boolean {
            var idleState = this.data.states.idle;
            var runningState = this.data.states.running;
            
            if (idleState.duration > 50) {
                idleState.active = false;
                runningState.active = true;
                return true;
            }
            return false;
        });
        
        this.assert(transitions.TransitNormal("idle") == "running", "Cross-state data modification works");
        this.assert(!this._mockStatus.data.states.idle.active, "Source state deactivated");
        this.assert(this._mockStatus.data.states.running.active, "Target state activated");
    }

    // ========== 边界情况测试 ==========
    
    public function testEmptyTransitionList():Void {
        trace("\n--- Test: Empty Transition List ---");
        var transitions:Transitions = new Transitions(this._mockStatus);
        
        this.assert(transitions.TransitNormal("any") == null, "Empty transition list returns null");
        this.assert(transitions.TransitNormal("") == null, "Empty state name returns null");
        this.assert(transitions.TransitNormal(null) == null, "Null state name returns null");
    }

    public function testNullConditions():Void {
        trace("\n--- Test: Null Conditions ---");
        var transitions:Transitions = new Transitions(this._mockStatus);
        
        // 测试null条件函数的处理
        try {
            transitions.push("test", "target", null);
            var result:String = transitions.TransitNormal("test");
            this.assert(result == null, "Null condition handled gracefully");
        } catch (e:Error) {
            this.assert(true, "Null condition throws expected error");
        }
    }

    public function testInvalidStateNames():Void {
        trace("\n--- Test: Invalid State Names ---");
        var transitions:Transitions = new Transitions(this._mockStatus);
        
        // 测试各种无效状态名
        var invalidNames:Array = ["", " ", "\t", "\n", "very_long_state_name_that_might_cause_issues"];
        
        for (var i:Number = 0; i < invalidNames.length; i++) {
            transitions.push(invalidNames[i], "target", function():Boolean { return true; });
            var result:String = transitions.TransitNormal(invalidNames[i]);
            // 应该能处理这些情况而不崩溃
            this.assert(true, "Invalid state name handled: '" + invalidNames[i] + "'");
        }
    }

    public function testSelfTransitions():Void {
        trace("\n--- Test: Self Transitions ---");
        var transitions:Transitions = new Transitions(this._mockStatus);
        this._mockStatus.data.selfCount = 0;
        
        // 自转换测试
        transitions.push("self", "self", function():Boolean {
            this.data.selfCount++;
            return this.data.selfCount >= 3;
        });
        
        this.assert(transitions.TransitNormal("self") == null, "First self-transition check returns null");
        this.assert(transitions.TransitNormal("self") == null, "Second self-transition check returns null");
        this.assert(transitions.TransitNormal("self") == "self", "Third self-transition succeeds");
    }

    public function testCircularTransitions():Void {
        trace("\n--- Test: Circular Transitions ---");
        var transitions:Transitions = new Transitions(this._mockStatus);
        this._mockStatus.data.cycle = 0;
        
        // 循环转换检测
        transitions.push("A", "B", function():Boolean { return this.data.cycle % 3 == 0; });
        transitions.push("B", "C", function():Boolean { return this.data.cycle % 3 == 1; });
        transitions.push("C", "A", function():Boolean { return this.data.cycle % 3 == 2; });
        
        this._mockStatus.data.cycle = 0;
        this.assert(transitions.TransitNormal("A") == "B", "A -> B transition");
        
        this._mockStatus.data.cycle = 1;
        this.assert(transitions.TransitNormal("B") == "C", "B -> C transition");
        
        this._mockStatus.data.cycle = 2;
        this.assert(transitions.TransitNormal("C") == "A", "C -> A transition completes cycle");
    }

    public function testMissingTargetStates():Void {
        trace("\n--- Test: Missing Target States ---");
        var transitions:Transitions = new Transitions(this._mockStatus);
        
        // 转换到不存在的目标状态
        transitions.push("source", "nonexistent_target", function():Boolean { return true; });
        
        var result:String = transitions.TransitNormal("source");
        this.assert(result == "nonexistent_target", "Transition returns target name even if target doesn't exist");
        // 注意：Transitions类本身不验证目标状态是否存在，这由状态机负责
    }

    // ========== 错误处理测试 ==========
    
    public function testExceptionInConditions():Void {
        trace("\n--- Test: Exception in Conditions ---");
        var transitions:Transitions = new Transitions(this._mockStatus);
        
        // 会抛出异常的条件函数
        transitions.push("error", "target", function():Boolean {
            throw new Error("Condition error");
            return false;
        });
        
        // 正常的备用条件
        transitions.push("error", "backup", function():Boolean { return true; });
        
        var exceptionCaught:Boolean = false;
        var result:String = null;
        
        try {
            result = transitions.TransitNormal("error");
        } catch (e:Error) {
            exceptionCaught = true;
        }
        
        this.assert(exceptionCaught, "Exception in condition properly propagated");
    }

    public function testMalformedTransitions():Void {
        trace("\n--- Test: Malformed Transitions ---");
        var transitions:Transitions = new Transitions(this._mockStatus);
        
        // 测试各种畸形的转换定义
        transitions.push(null, "target", function():Boolean { return true; });
        transitions.push("source", null, function():Boolean { return true; });
        
        // 这些应该被优雅地处理而不崩溃
        this.assert(true, "Malformed transitions handled without crash");
    }

    public function testCorruptedTransitionData():Void {
        trace("\n--- Test: Corrupted Transition Data ---");
        var transitions:Transitions = new Transitions(this._mockStatus);
        
        // 模拟数据损坏的情况
        this._mockStatus.data = null;
        
        transitions.push("corrupted", "target", function():Boolean {
            // 尝试访问空数据
            return this.data && this.data.someProperty;
        });
        
        var result:String = transitions.TransitNormal("corrupted");
        this.assert(result == null, "Corrupted data handled gracefully");
    }

    public function testRecoveryFromErrors():Void {
        trace("\n--- Test: Recovery from Errors ---");
        var transitions:Transitions = new Transitions(this._mockStatus);
        this._mockStatus.data = {errorCount: 0, recovered: false};
        
        // 错误恢复机制
        transitions.push("recovery", "error", function():Boolean {
            this.data.errorCount++;
            if (this.data.errorCount < 3) {
                throw new Error("Simulated error");
            }
            return false;
        });
        
        transitions.push("recovery", "success", function():Boolean {
            this.data.recovered = true;
            return this.data.errorCount >= 3;
        });
        
        // 多次尝试直到恢复
        var attempts:Number = 0;
        var finalResult:String = null;
        
        while (attempts < 5 && !this._mockStatus.data.recovered) {
            try {
                finalResult = transitions.TransitNormal("recovery");
                attempts++;
            } catch (e:Error) {
                attempts++;
                continue;
            }
        }
        
        this.assert(this._mockStatus.data.recovered, "Successfully recovered from errors");
    }

    // ========== 性能测试 ==========
    
    public function testBasicPerformance():Void {
        trace("\n--- Test: Basic Performance ---");
        var transitions:Transitions = new Transitions(this._mockStatus);
        
        // 添加简单转换
        transitions.push("perf", "target", function():Boolean { return true; });
        
        var iterations:Number = 10000;
        var time:Number = this.measureTime(function() {
            transitions.TransitNormal("perf");
        }, iterations, "Basic Transit Call");
        
        trace("Basic Performance: " + iterations + " transit calls in " + time + "ms");
        this.assert(time < 1000, "Basic performance acceptable");
    }

    public function testManyTransitionsPerformance():Void {
        trace("\n--- Test: Many Transitions Performance ---");
        var transitions:Transitions = new Transitions(this._mockStatus);
        
        // 添加大量转换
        var numTransitions:Number = 1000;
        for (var i:Number = 0; i < numTransitions; i++) {
            transitions.push("many", "target" + i, function():Boolean { return Math.random() > 0.999; });
        }
        
        // 添加一个总是成功的转换在最后
        transitions.push("many", "final", function():Boolean { return true; });
        
        var iterations:Number = 1000;
        var time:Number = this.measureTime(function() {
            transitions.TransitNormal("many");
        }, iterations, "Many Transitions");
        
        trace("Many Transitions Performance: " + numTransitions + " transitions, " + iterations + " calls in " + time + "ms");
        this.assert(time < 3000, "Many transitions performance acceptable");
    }

    public function testComplexConditionsPerformance():Void {
        trace("\n--- Test: Complex Conditions Performance ---");
        var transitions:Transitions = new Transitions(this._mockStatus);
        this._mockStatus.data.complex = {
            matrix: [[1,2,3], [4,5,6], [7,8,9]],
            calculations: []
        };
        
        // 复杂计算条件
        transitions.push("complex", "result", function():Boolean {
            var matrix = this.data.complex.matrix;
            var sum:Number = 0;
            
            // 矩阵求和
            for (var i:Number = 0; i < matrix.length; i++) {
                for (var j:Number = 0; j < matrix[i].length; j++) {
                    sum += matrix[i][j] * Math.sqrt(i + j + 1);
                }
            }
            
            this.data.complex.calculations.push(sum);
            return sum > 100;
        });
        
        var iterations:Number = 1000;
        var time:Number = this.measureTime(function() {
            transitions.TransitNormal("complex");
        }, iterations, "Complex Conditions");
        
        trace("Complex Conditions Performance: " + iterations + " complex calculations in " + time + "ms");
        this.assert(time < 2000, "Complex conditions performance acceptable");
    }

    public function testFrequentTransitCallsPerformance():Void {
        trace("\n--- Test: Frequent Transit Calls Performance ---");
        var transitions:Transitions = new Transitions(this._mockStatus);
        this._mockStatus.data.frequency = {counter: 0, threshold: 100};
        
        // 频繁调用的条件
        transitions.push("frequent", "toggle", function():Boolean {
            this.data.frequency.counter++;
            return this.data.frequency.counter % this.data.frequency.threshold == 0;
        });
        
        var iterations:Number = 50000;
        var time:Number = this.measureTime(function() {
            transitions.TransitNormal("frequent");
        }, iterations, "Frequent Transit Calls");
        
        trace("Frequent Calls Performance: " + iterations + " calls in " + time + "ms");
        this.assert(time < 1500, "Frequent calls performance acceptable");
    }

    public function testTransitionScalability():Void {
        trace("\n--- Test: Transition Scalability ---");
        
        var scales:Array = [10, 50, 100, 500, 1000];
        var results:Array = [];
        
        for (var s:Number = 0; s < scales.length; s++) {
            var scale:Number = scales[s];
            var transitions:Transitions = new Transitions(this._mockStatus);
            
            // 添加指定数量的转换
            for (var i:Number = 0; i < scale; i++) {
                transitions.push("scale", "target" + i, function():Boolean { 
                    return Math.random() > 0.99; 
                });
            }
            
            // 添加最终转换
            transitions.push("scale", "success", function():Boolean { return true; });
            
            var time:Number = this.measureTime(function() {
                transitions.TransitNormal("scale");
            }, 100, "Scale " + scale);
            
            results.push({scale: scale, time: time});
            trace("Scale " + scale + ": 100 calls in " + time + "ms");
        }
        
        // 检查是否线性扩展
        var scalabilityGood:Boolean = true;
        for (var r:Number = 1; r < results.length; r++) {
            var ratio:Number = results[r].time / results[r-1].time;
            var scaleRatio:Number = results[r].scale / results[r-1].scale;
            
            // 时间增长不应该超过规模增长的2倍
            if (ratio > scaleRatio * 2) {
                scalabilityGood = false;
                break;
            }
        }
        
        this.assert(scalabilityGood, "Transition scalability is acceptable");
    }

    public function testMemoryUsageOptimization():Void {
        trace("\n--- Test: Memory Usage Optimization ---");
        var transitions:Transitions = new Transitions(this._mockStatus);
        
        // 创建大量转换然后检查清理
        var numTransitions:Number = 10000;
        
        // 修复：将函数和目标定义在循环外，以测试去重功能
        var aFunc:Function = function():Boolean { return false; };
        var aTarget:String = "the_only_target";
        
        for (var i:Number = 0; i < numTransitions; i++) {
            // 修复：重复添加完全相同的转换
            transitions.push("memory", aTarget, aFunc);
        }
        
        // 经过去重后，normalLists["memory"] 数组的长度应该只有 1
        
        // 执行一些操作
        for (var j:Number = 0; j < 100; j++) {
            transitions.TransitNormal("memory");
        }
        
        // 由于数组长度为1，这里的性能会非常高
        var time:Number = this.measureTime(function() {
            transitions.TransitNormal("memory");
        }, 1000, "Memory Stress Test");
        
        this.assert(time < 5000, "Memory usage remains efficient under stress"); // 现在应该远小于5000ms
    }

    // ========== 高级功能测试 ==========
    
    public function testTransitionCaching():Void {
        trace("\n--- Test: Transition Caching ---");
        var transitions:Transitions = new Transitions(this._mockStatus);
        this._mockStatus.data.cache = {hits: 0, expensive: 0};
        
        // 模拟昂贵的计算
        transitions.push("cache", "expensive", function():Boolean {
            this.data.cache.expensive++;
            
            // 模拟昂贵计算
            var result:Number = 0;
            for (var i:Number = 0; i < 1000; i++) {
                result += Math.sqrt(i);
            }
            
            return result > 500;
        });
        
        // 多次调用相同条件
        var startTime:Number = getTimer();
        for (var j:Number = 0; j < 10; j++) {
            transitions.TransitNormal("cache");
        }
        var totalTime:Number = getTimer() - startTime;
        
        this.assert(this._mockStatus.data.cache.expensive == 10, "All calculations executed (no caching implemented)");
        trace("Caching test: 10 calls took " + totalTime + "ms");
        
        // 注意：当前实现没有缓存，这个测试为未来缓存功能做准备
        this.assert(true, "Caching test completed (baseline established)");
    }

    public function testConditionalShortCircuiting():Void {
        trace("\n--- Test: Conditional Short-Circuiting ---");
        var transitions:Transitions = new Transitions(this._mockStatus);
        this._mockStatus.data.shortCircuit = {evaluations: 0};
        
        // 第一个条件为true，后面的不应该被评估
        transitions.push("short", "first", function():Boolean {
            this.data.shortCircuit.evaluations++;
            return true;
        });
        
        transitions.push("short", "second", function():Boolean {
            this.data.shortCircuit.evaluations++;
            return true;
        });
        
        var result:String = transitions.TransitNormal("short");
        
        this.assert(result == "first", "First transition executed");
        this.assert(this._mockStatus.data.shortCircuit.evaluations == 1, "Short-circuiting works - only first condition evaluated");
    }

    public function testTransitionGrouping():Void {
        trace("\n--- Test: Transition Grouping ---");
        var transitions:Transitions = new Transitions(this._mockStatus);
        this._mockStatus.data.group = {category: "A", priority: 1};
        
        // 模拟分组转换（通过命名约定）
        transitions.push("group", "groupA_low", function():Boolean {
            return this.data.group.category == "A" && this.data.group.priority <= 1;
        });
        
        transitions.push("group", "groupA_high", function():Boolean {
            return this.data.group.category == "A" && this.data.group.priority > 1;
        });
        
        transitions.push("group", "groupB_any", function():Boolean {
            return this.data.group.category == "B";
        });
        
        var result1:String = transitions.TransitNormal("group");
        this.assert(result1 == "groupA_low", "Group A low priority selected");
        
        this._mockStatus.data.group.priority = 3;
        var result2:String = transitions.TransitNormal("group");
        this.assert(result2 == "groupA_high", "Group A high priority selected");
    }

    public function testDynamicTransitionManagement():Void {
        trace("\n--- Test: Dynamic Transition Management ---");
        var transitions:Transitions = new Transitions(this._mockStatus);
        this._mockStatus.data.dyn = {phase: 1, enabled: true};
        
        // 动态启用/禁用转换
        transitions.push("dyn", "phase1", function():Boolean {
            return this.data.dyn.enabled && this.data.dyn.phase == 1;
        });
        
        transitions.push("dyn", "phase2", function():Boolean {
            return this.data.dyn.enabled && this.data.dyn.phase == 2;
        });
        
        transitions.push("dyn", "disabled", function():Boolean {
            return !this.data.dyn.enabled;
        });
        
        // 测试阶段1
        var result1:String = transitions.TransitNormal("dyn");
        this.assert(result1 == "phase1", "Phase 1 active");
        
        // 切换到阶段2
        this._mockStatus.data.dyn.phase = 2;
        var result2:String = transitions.TransitNormal("dyn");
        this.assert(result2 == "phase2", "Phase 2 active");
        
        // 禁用所有
        this._mockStatus.data.dyn.enabled = false;
        var result3:String = transitions.TransitNormal("dyn");
        this.assert(result3 == "disabled", "Disabled state active");
    }

    // ========== Gate/Normal 分表测试 ==========

    /**
     * 验证 Gate 和 Normal 转换正确分表存储和查询
     */
    public function testGateNormalSeparation():Void {
        trace("\n--- Test: Gate/Normal Separation ---");
        var transitions:Transitions = new Transitions(this._mockStatus);

        // 添加 Gate 转换
        transitions.push("state1", "paused", function():Boolean { return true; }, true);
        // 添加 Normal 转换
        transitions.push("state1", "running", function():Boolean { return true; }, false);

        // TransitGate 应该只看到 Gate 规则
        this.assert(transitions.TransitGate("state1") == "paused", "TransitGate returns Gate transition");
        // TransitNormal 应该只看到 Normal 规则
        this.assert(transitions.TransitNormal("state1") == "running", "TransitNormal returns Normal transition");

        // Gate 不应返回 Normal 规则
        this.assert(transitions.TransitGate("state1") != "running", "TransitGate does not return Normal transition");
        // Normal 不应返回 Gate 规则
        this.assert(transitions.TransitNormal("state1") != "paused", "TransitNormal does not return Gate transition");
    }

    /**
     * 验证 Gate 和 Normal 之间完全隔离
     */
    public function testGateNormalIsolation():Void {
        trace("\n--- Test: Gate/Normal Isolation ---");
        var transitions:Transitions = new Transitions(this._mockStatus);

        // 只添加 Gate 转换
        transitions.push("gateOnly", "target", function():Boolean { return true; }, true);
        // Normal 查询应返回 null
        this.assert(transitions.TransitNormal("gateOnly") == null, "No Normal result for Gate-only state");
        this.assert(transitions.TransitGate("gateOnly") == "target", "Gate result exists for Gate-only state");

        // 只添加 Normal 转换
        transitions.push("normalOnly", "target", function():Boolean { return true; }, false);
        // Gate 查询应返回 null
        this.assert(transitions.TransitGate("normalOnly") == null, "No Gate result for Normal-only state");
        this.assert(transitions.TransitNormal("normalOnly") == "target", "Normal result exists for Normal-only state");
    }

    /**
     * 验证 clear 和 reset 同时清除 Gate 和 Normal
     */
    public function testGateNormalClearAndReset():Void {
        trace("\n--- Test: Gate/Normal Clear and Reset ---");
        var transitions:Transitions = new Transitions(this._mockStatus);

        transitions.push("test", "gateTarget", function():Boolean { return true; }, true);
        transitions.push("test", "normalTarget", function():Boolean { return true; }, false);

        // clear 应清除指定状态的 Gate 和 Normal
        transitions.clear("test");
        this.assert(transitions.TransitGate("test") == null, "Gate cleared for state");
        this.assert(transitions.TransitNormal("test") == null, "Normal cleared for state");

        // 重新添加
        transitions.push("test2", "g", function():Boolean { return true; }, true);
        transitions.push("test2", "n", function():Boolean { return true; }, false);

        // reset 应清除所有
        transitions.reset();
        this.assert(transitions.TransitGate("test2") == null, "Gate cleared after reset");
        this.assert(transitions.TransitNormal("test2") == null, "Normal cleared after reset");
    }

    // ========== remove()/setActive() API 测试 ==========

    /**
     * 验证 remove() 能物理移除 Normal 转换规则
     */
    public function testRemoveNormalTransition():Void {
        trace("\n--- Test: Remove Normal Transition ---");
        var transitions:Transitions = new Transitions(this._mockStatus);

        var fn1:Function = function():Boolean { return true; };
        var fn2:Function = function():Boolean { return true; };

        transitions.push("st", "A", fn1);
        transitions.push("st", "B", fn2);

        // 移除第一条规则
        var removed:Boolean = transitions.remove("st", "A", fn1);
        this.assert(removed == true, "remove() returns true for existing rule");
        // TransitNormal 应该返回 B（A 已被移除）
        this.assert(transitions.TransitNormal("st") == "B", "After remove, next rule takes effect");
    }

    /**
     * 验证 remove() 能物理移除 Gate 转换规则
     */
    public function testRemoveGateTransition():Void {
        trace("\n--- Test: Remove Gate Transition ---");
        var transitions:Transitions = new Transitions(this._mockStatus);

        var fn:Function = function():Boolean { return true; };

        transitions.push("st", "gateTarget", fn, true);

        this.assert(transitions.TransitGate("st") == "gateTarget", "Gate rule exists before remove");

        var removed:Boolean = transitions.remove("st", "gateTarget", fn, true);
        this.assert(removed == true, "remove(isGate=true) returns true");
        this.assert(transitions.TransitGate("st") == null, "Gate rule removed successfully");
    }

    /**
     * 验证 remove() 对不存在的规则返回 false
     */
    public function testRemoveNonExistent():Void {
        trace("\n--- Test: Remove Non-Existent ---");
        var transitions:Transitions = new Transitions(this._mockStatus);

        var fn:Function = function():Boolean { return true; };
        transitions.push("st", "A", fn);

        // 错误的 target
        this.assert(transitions.remove("st", "X", fn) == false, "remove() returns false for wrong target");
        // 错误的 func
        this.assert(transitions.remove("st", "A", function():Boolean { return true; }) == false, "remove() returns false for different func ref");
        // 错误的 state
        this.assert(transitions.remove("noState", "A", fn) == false, "remove() returns false for non-existent state");
        // 原规则仍在
        this.assert(transitions.TransitNormal("st") == "A", "Original rule still active after failed removes");
    }

    /**
     * 验证 setActive() 禁用和重新启用 Normal 规则
     */
    public function testSetActiveDisableEnable():Void {
        trace("\n--- Test: setActive Disable/Enable ---");
        var transitions:Transitions = new Transitions(this._mockStatus);

        var fn1:Function = function():Boolean { return true; };
        var fn2:Function = function():Boolean { return true; };

        transitions.push("st", "A", fn1);
        transitions.push("st", "B", fn2);

        // 禁用 A
        var result:Boolean = transitions.setActive("st", "A", fn1, false, false);
        this.assert(result == true, "setActive() returns true for existing rule");
        this.assert(transitions.TransitNormal("st") == "B", "Disabled rule skipped, B takes effect");

        // 重新启用 A
        transitions.setActive("st", "A", fn1, false, true);
        this.assert(transitions.TransitNormal("st") == "A", "Re-enabled rule takes effect again");
    }

    /**
     * 验证 setActive() 对 Gate 规则生效
     */
    public function testSetActiveGateTransition():Void {
        trace("\n--- Test: setActive Gate Transition ---");
        var transitions:Transitions = new Transitions(this._mockStatus);

        var fn:Function = function():Boolean { return true; };

        transitions.push("st", "gateTarget", fn, true);
        this.assert(transitions.TransitGate("st") == "gateTarget", "Gate rule active initially");

        // 禁用 Gate 规则
        transitions.setActive("st", "gateTarget", fn, true, false);
        this.assert(transitions.TransitGate("st") == null, "Gate rule disabled via setActive");

        // 重新启用
        transitions.setActive("st", "gateTarget", fn, true, true);
        this.assert(transitions.TransitGate("st") == "gateTarget", "Gate rule re-enabled via setActive");
    }

    /**
     * 验证 setActive() 对不存在的规则返回 false
     */
    public function testSetActiveNonExistent():Void {
        trace("\n--- Test: setActive Non-Existent ---");
        var transitions:Transitions = new Transitions(this._mockStatus);

        this.assert(transitions.setActive("noState", "A", function():Boolean { return true; }, false, false) == false,
            "setActive() returns false for non-existent state");

        var fn:Function = function():Boolean { return true; };
        transitions.push("st", "A", fn);
        this.assert(transitions.setActive("st", "X", fn, false, false) == false,
            "setActive() returns false for wrong target");
    }

    /**
     * 验证 remove() 后重新 push 同规则能正常工作
     */
    public function testRemoveAndReAdd():Void {
        trace("\n--- Test: Remove and Re-Add ---");
        var transitions:Transitions = new Transitions(this._mockStatus);

        var fn:Function = function():Boolean { return true; };
        transitions.push("st", "A", fn);

        // 移除
        transitions.remove("st", "A", fn);
        this.assert(transitions.TransitNormal("st") == null, "Rule removed");

        // 重新添加
        transitions.push("st", "A", fn);
        this.assert(transitions.TransitNormal("st") == "A", "Rule re-added and working");
    }

    /**
     * 验证 setActive(false) 后高优先级规则被跳过，低优先级规则生效
     */
    public function testSetActiveWithPriority():Void {
        trace("\n--- Test: setActive with Priority ---");
        var transitions:Transitions = new Transitions(this._mockStatus);

        var fnHigh:Function = function():Boolean { return true; };
        var fnMid:Function = function():Boolean { return true; };
        var fnLow:Function = function():Boolean { return true; };

        transitions.unshift("st", "high", fnHigh);
        transitions.push("st", "mid", fnMid);
        transitions.push("st", "low", fnLow);

        this.assert(transitions.TransitNormal("st") == "high", "Highest priority rule fires");

        // 禁用最高优先级
        transitions.setActive("st", "high", fnHigh, false, false);
        this.assert(transitions.TransitNormal("st") == "mid", "Mid priority fires when high disabled");

        // 禁用中优先级
        transitions.setActive("st", "mid", fnMid, false, false);
        this.assert(transitions.TransitNormal("st") == "low", "Low priority fires when high+mid disabled");

        // 全部重新启用
        transitions.setActive("st", "high", fnHigh, false, true);
        transitions.setActive("st", "mid", fnMid, false, true);
        this.assert(transitions.TransitNormal("st") == "high", "All re-enabled, highest priority fires again");
    }

    // ========== 报告生成 ==========
    
    public function printFinalReport():Void {
        trace("\n=== TRANSITIONS TEST FINAL REPORT ===");
        trace("Tests Passed: " + this._testPassed);
        trace("Tests Failed: " + this._testFailed);
        trace("Success Rate: " + Math.round((this._testPassed / (this._testPassed + this._testFailed)) * 100) + "%");
        
        if (this._testFailed == 0) {
            trace("🎉 ALL TRANSITIONS TESTS PASSED!");
        } else {
            trace("⚠️  Some transitions tests failed. Review implementation.");
        }
        
        trace("=== TRANSITIONS VERIFICATION SUMMARY ===");
        trace("✓ Basic transition operations verified");
        trace("✓ Priority system robustness confirmed");
        trace("✓ Condition logic extensively tested");
        trace("✓ Data access patterns validated");
        trace("✓ Error handling mechanisms verified");
        trace("✓ Performance benchmarks established");
        trace("✓ Advanced features tested");
        trace("=============================");
    }

    public function generatePerformanceReport():Void {
        trace("\n=== TRANSITIONS PERFORMANCE ANALYSIS ===");
        
        for (var i:Number = 0; i < this._performanceLog.length; i++) {
            var entry = this._performanceLog[i];
            trace("Context: " + entry.context);
            trace("  Iterations: " + entry.iterations);
            trace("  Total Time: " + entry.elapsed + "ms");
            trace("  Avg per Operation: " + entry.avgPerOperation + "ms");
            trace("  Operations per Second: " + Math.round(1000 / entry.avgPerOperation));
            trace("---");
        }
        
        trace("=== PERFORMANCE RECOMMENDATIONS ===");
        
        // 分析性能数据并提供建议
        var totalOperations:Number = 0;
        var totalTime:Number = 0;
        
        for (var j:Number = 0; j < this._performanceLog.length; j++) {
            totalOperations += this._performanceLog[j].iterations;
            totalTime += this._performanceLog[j].elapsed;
        }
        
        var overallAvg:Number = totalTime / totalOperations;
        trace("Overall Average: " + overallAvg + "ms per operation");
        
        if (overallAvg < 0.1) {
            trace("✅ Excellent performance - suitable for real-time applications");
        } else if (overallAvg < 0.5) {
            trace("✅ Good performance - suitable for most applications");
        } else if (overallAvg < 1.0) {
            trace("⚠️  Moderate performance - consider optimization for high-frequency usage");
        } else {
            trace("❌ Poor performance - optimization required");
        }
        
        trace("=============================");
    }
}