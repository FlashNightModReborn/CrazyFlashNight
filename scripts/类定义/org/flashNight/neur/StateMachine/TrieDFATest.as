import org.flashNight.neur.StateMachine.TrieDFA; 

/**
 * TrieDFA 测试套件
 * 全面测试前缀树DFA的功能、性能、稳定性和边界情况
 *
 * 测试分类：
 * 1. 基础功能测试 - 构造、插入、编译、转移
 * 2. 前置校验测试 - 验证"无半插入"保证
 * 3. 提示策略测试 - hint优先级和长度比较
 * 4. 边界情况测试 - 空模式、越界符号、重复插入
 * 5. 便捷方法测试 - match、findAll
 * 6. 性能测试 - 大规模模式、频繁查询
 *
 * @author FlashNight
 * @version 1.0
 */
class org.flashNight.neur.StateMachine.TrieDFATest {

    private var _testPassed:Number;
    private var _testFailed:Number;
    private var _performanceLog:Array;

    public function TrieDFATest() {
        this._testPassed = 0;
        this._testFailed = 0;
        this._performanceLog = [];
        trace("=== TrieDFA Test Suite Initialized ===");
    }

    /**
     * 运行所有测试
     */
    public function runTests():Void {
        trace("\n=== Running Comprehensive TrieDFA Tests ===\n");

        // 基础功能测试
        this.testBasicCreation();
        this.testSinglePatternInsert();
        this.testMultiplePatternInsert();
        this.testPrefixSharing();
        this.testTransition();
        this.testAcceptStates();

        // 前置校验测试（验证无半插入）
        this.testInsertValidation_Compiled();
        this.testInsertValidation_Undefined();
        this.testInsertValidation_Empty();
        this.testInsertValidation_InvalidSymbol();
        this.testInsertValidation_NoHalfInsert();

        // 提示策略测试
        this.testHintBasic();
        this.testHintPriorityComparison();
        this.testHintLengthComparison();
        this.testHintPrefixConflict();

        // 深度和元数据测试
        this.testDepthTracking();
        this.testPatternMetadata();
        this.testMaxPatternLength();

        // 边界情况测试
        this.testEmptyDFA();
        this.testSingleSymbolPattern();
        this.testLongPattern();
        this.testManyPatterns();
        this.testDuplicatePatterns();
        this.testAlphabetBoundary();

        // 便捷方法测试
        this.testMatch();
        this.testMatchPartial();
        this.testMatchNoMatch();
        this.testFindAll();
        this.testFindAllOverlapping();
        this.testFindAllWithMaxLen();

        // 扩容测试
        this.testAutoExpansion();

        // 调试方法测试
        this.testDump();
        this.testGetTransitionsFrom();

        // 流式输入测试（模拟搓招状态机真实使用）
        this.testStreamingBasic();
        this.testStreamingMultiplePatterns();
        this.testStreamingHintProgression();
        this.testStreamingTimeout();
        this.testStreamingPrefixMatch();

        // 性能测试
        this.testBasicPerformance();
        this.testTransitionPerformance();
        this.testManyPatternsPerformance();
        this.testFindAllPerformance();
        this.testScalability();

        // 最终报告
        this.printFinalReport();
        this.generatePerformanceReport();
    }

    // ========== 断言和工具函数 ==========

    private function assert(condition:Boolean, message:String):Void {
        if (condition) {
            this._testPassed++;
            trace("[PASS] " + message);
        } else {
            this._testFailed++;
            trace("[FAIL] " + message);
        }
    }

    private function assertEq(actual, expected, message:String):Void {
        if (actual === expected) {
            this._testPassed++;
            trace("[PASS] " + message + " (got: " + actual + ")");
        } else {
            this._testFailed++;
            trace("[FAIL] " + message + " (expected: " + expected + ", got: " + actual + ")");
        }
    }

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

    public function testBasicCreation():Void {
        trace("\n--- Test: Basic Creation ---");

        var dfa:TrieDFA = new TrieDFA(10, 32);

        this.assert(dfa != null, "TrieDFA created successfully");
        this.assertEq(dfa.getAlphabetSize(), 10, "Alphabet size is 10");
        this.assertEq(dfa.getStateCount(), 1, "Initial state count is 1 (root)");
        this.assertEq(dfa.getPatternCount(), 0, "Initial pattern count is 0");
        this.assertEq(dfa.isCompiled(), false, "Not compiled initially");
    }

    public function testSinglePatternInsert():Void {
        trace("\n--- Test: Single Pattern Insert ---");

        var dfa:TrieDFA = new TrieDFA(10);
        var id:Number = dfa.insert([1, 2, 3], 5);

        this.assert(id != TrieDFA.INVALID, "Insert returns valid ID");
        this.assertEq(id, 1, "First pattern ID is 1");
        this.assertEq(dfa.getPatternCount(), 1, "Pattern count is 1");
        this.assertEq(dfa.getPatternLength(id), 3, "Pattern length is 3");
        this.assertEq(dfa.getPriority(id), 5, "Priority is 5");

        var pattern:Array = dfa.getPattern(id);
        this.assertEq(pattern.length, 3, "Retrieved pattern length is 3");
        this.assertEq(pattern[0], 1, "Pattern[0] is 1");
        this.assertEq(pattern[1], 2, "Pattern[1] is 2");
        this.assertEq(pattern[2], 3, "Pattern[2] is 3");
    }

    public function testMultiplePatternInsert():Void {
        trace("\n--- Test: Multiple Pattern Insert ---");

        var dfa:TrieDFA = new TrieDFA(5);

        var id1:Number = dfa.insert([0, 1], 1);
        var id2:Number = dfa.insert([0, 2], 2);
        var id3:Number = dfa.insert([1, 2, 3], 3);

        this.assertEq(id1, 1, "First pattern ID is 1");
        this.assertEq(id2, 2, "Second pattern ID is 2");
        this.assertEq(id3, 3, "Third pattern ID is 3");
        this.assertEq(dfa.getPatternCount(), 3, "Pattern count is 3");
    }

    public function testPrefixSharing():Void {
        trace("\n--- Test: Prefix Sharing ---");

        var dfa:TrieDFA = new TrieDFA(5);

        // 插入共享前缀的模式
        dfa.insert([0, 1, 2], 1);     // 状态: ROOT -> S1 -> S2 -> S3(accept)
        dfa.insert([0, 1, 3], 1);     // 共享 ROOT -> S1 -> S2, 新建 S2 -> S4(accept)
        dfa.insert([0, 1, 2, 4], 1);  // 共享到 S3, 新建 S3 -> S5(accept)

        dfa.compile();

        // 验证状态数量（应该少于如果不共享的情况）
        // ROOT(0) + S1 + S2 + S3 + S4 + S5 = 6 states
        this.assertEq(dfa.getStateCount(), 6, "State count reflects prefix sharing");
        this.assertEq(dfa.getPatternCount(), 3, "Pattern count is 3");
    }

    public function testTransition():Void {
        trace("\n--- Test: Transition ---");

        var dfa:TrieDFA = new TrieDFA(5);
        dfa.insert([0, 1, 2], 1);
        dfa.compile();

        var state:Number = TrieDFA.ROOT;

        // 有效转移
        var next1:Number = dfa.transition(state, 0);
        this.assert(next1 != undefined, "Transition on symbol 0 exists");

        var next2:Number = dfa.transition(next1, 1);
        this.assert(next2 != undefined, "Transition on symbol 1 exists");

        var next3:Number = dfa.transition(next2, 2);
        this.assert(next3 != undefined, "Transition on symbol 2 exists");

        // 无效转移
        var invalid:Number = dfa.transition(state, 3);
        this.assertEq(invalid, undefined, "No transition on symbol 3 from root");
    }

    public function testAcceptStates():Void {
        trace("\n--- Test: Accept States ---");

        var dfa:TrieDFA = new TrieDFA(5);
        var id1:Number = dfa.insert([0, 1], 1);
        var id2:Number = dfa.insert([0, 1, 2], 2);
        dfa.compile();

        // 走到 [0, 1] 的接受状态
        var s1:Number = dfa.transition(TrieDFA.ROOT, 0);
        var s2:Number = dfa.transition(s1, 1);
        this.assertEq(dfa.getAccept(s2), id1, "State after [0,1] accepts pattern 1");

        // 走到 [0, 1, 2] 的接受状态
        var s3:Number = dfa.transition(s2, 2);
        this.assertEq(dfa.getAccept(s3), id2, "State after [0,1,2] accepts pattern 2");

        // 中间状态不是接受状态
        this.assertEq(dfa.getAccept(s1), TrieDFA.NO_MATCH, "Intermediate state is not accept");
        this.assertEq(dfa.getAccept(TrieDFA.ROOT), TrieDFA.NO_MATCH, "Root is not accept");
    }

    // ========== 前置校验测试（验证无半插入）==========

    public function testInsertValidation_Compiled():Void {
        trace("\n--- Test: Insert Validation - After Compile ---");

        var dfa:TrieDFA = new TrieDFA(5);
        dfa.insert([0, 1], 1);
        dfa.compile();

        var id:Number = dfa.insert([2, 3], 1);
        this.assertEq(id, TrieDFA.INVALID, "Cannot insert after compile");
        this.assertEq(dfa.getPatternCount(), 1, "Pattern count unchanged");
    }

    public function testInsertValidation_Undefined():Void {
        trace("\n--- Test: Insert Validation - Undefined Pattern ---");

        var dfa:TrieDFA = new TrieDFA(5);
        var id:Number = dfa.insert(undefined, 1);

        this.assertEq(id, TrieDFA.INVALID, "Cannot insert undefined pattern");
        this.assertEq(dfa.getPatternCount(), 0, "Pattern count is 0");
    }

    public function testInsertValidation_Empty():Void {
        trace("\n--- Test: Insert Validation - Empty Pattern ---");

        var dfa:TrieDFA = new TrieDFA(5);
        var id:Number = dfa.insert([], 1);

        this.assertEq(id, TrieDFA.INVALID, "Cannot insert empty pattern");
        this.assertEq(dfa.getPatternCount(), 0, "Pattern count is 0");
    }

    public function testInsertValidation_InvalidSymbol():Void {
        trace("\n--- Test: Insert Validation - Invalid Symbol ---");

        var dfa:TrieDFA = new TrieDFA(5);  // 字母表 [0, 5)

        // 负数符号
        var id1:Number = dfa.insert([-1, 0, 1], 1);
        this.assertEq(id1, TrieDFA.INVALID, "Cannot insert pattern with negative symbol");

        // 越界符号
        var id2:Number = dfa.insert([0, 5, 1], 1);  // 5 >= alphabetSize
        this.assertEq(id2, TrieDFA.INVALID, "Cannot insert pattern with out-of-range symbol");

        // 确认没有半插入
        this.assertEq(dfa.getPatternCount(), 0, "Pattern count remains 0 after invalid inserts");
        this.assertEq(dfa.getStateCount(), 1, "State count remains 1 (only root)");
    }

    public function testInsertValidation_NoHalfInsert():Void {
        trace("\n--- Test: Insert Validation - No Half Insert ---");

        var dfa:TrieDFA = new TrieDFA(5);

        // 先插入一个有效模式
        var id1:Number = dfa.insert([0, 1, 2], 1);
        this.assertEq(id1, 1, "First valid insert succeeds");

        var statesBefore:Number = dfa.getStateCount();
        var patternsBefore:Number = dfa.getPatternCount();

        // 尝试插入一个中途有非法符号的模式
        // [0, 1, 99, 3] - 99 超出字母表
        var id2:Number = dfa.insert([0, 1, 99, 3], 1);
        this.assertEq(id2, TrieDFA.INVALID, "Insert with invalid symbol fails");

        // 关键断言：状态数和模式数应该没有变化
        this.assertEq(dfa.getStateCount(), statesBefore, "State count unchanged after failed insert");
        this.assertEq(dfa.getPatternCount(), patternsBefore, "Pattern count unchanged after failed insert");

        // 验证 DFA 仍然正常工作
        dfa.compile();
        this.assertEq(dfa.match([0, 1, 2]), id1, "Original pattern still matches");
    }

    // ========== 提示策略测试 ==========

    public function testHintBasic():Void {
        trace("\n--- Test: Hint Basic ---");

        var dfa:TrieDFA = new TrieDFA(5);
        var id:Number = dfa.insert([0, 1, 2], 10);
        dfa.compile();

        var s1:Number = dfa.transition(TrieDFA.ROOT, 0);
        var s2:Number = dfa.transition(s1, 1);

        this.assertEq(dfa.getHint(s1), id, "Hint at depth 1 points to pattern");
        this.assertEq(dfa.getHint(s2), id, "Hint at depth 2 points to pattern");
    }

    public function testHintPriorityComparison():Void {
        trace("\n--- Test: Hint Priority Comparison ---");

        var dfa:TrieDFA = new TrieDFA(5);

        // 共享前缀 [0, 1]，不同优先级
        var idLow:Number = dfa.insert([0, 1, 2], 5);    // 低优先级
        var idHigh:Number = dfa.insert([0, 1, 3], 10);  // 高优先级

        dfa.compile();

        // 在共享前缀的状态上，应该提示高优先级的模式
        var s1:Number = dfa.transition(TrieDFA.ROOT, 0);
        var s2:Number = dfa.transition(s1, 1);

        this.assertEq(dfa.getHint(s1), idHigh, "Hint prefers higher priority pattern");
        this.assertEq(dfa.getHint(s2), idHigh, "Hint at shared node prefers higher priority");
    }

    public function testHintLengthComparison():Void {
        trace("\n--- Test: Hint Length Comparison ---");

        var dfa:TrieDFA = new TrieDFA(5);

        // 相同优先级，不同长度
        var idShort:Number = dfa.insert([0, 1, 2], 5);        // 长度 3
        var idLong:Number = dfa.insert([0, 1, 2, 3, 4], 5);   // 长度 5，同优先级

        dfa.compile();

        // 在共享前缀的状态上，应该提示更长的模式（引导玩家继续拓展）
        var s1:Number = dfa.transition(TrieDFA.ROOT, 0);
        var s2:Number = dfa.transition(s1, 1);

        this.assertEq(dfa.getHint(s1), idLong, "Hint prefers longer pattern at same priority");
        this.assertEq(dfa.getHint(s2), idLong, "Hint prefers longer pattern at depth 2");
    }

    public function testHintPrefixConflict():Void {
        trace("\n--- Test: Hint Prefix Conflict ---");

        var dfa:TrieDFA = new TrieDFA(5);

        // 模式A是模式B的前缀，但A有更高优先级
        var idA:Number = dfa.insert([0, 1], 10);         // 短，高优先级
        var idB:Number = dfa.insert([0, 1, 2, 3], 5);    // 长，低优先级

        dfa.compile();

        var s1:Number = dfa.transition(TrieDFA.ROOT, 0);

        // 高优先级应该胜出
        this.assertEq(dfa.getHint(s1), idA, "Higher priority wins over length");
    }

    // ========== 深度和元数据测试 ==========

    public function testDepthTracking():Void {
        trace("\n--- Test: Depth Tracking ---");

        var dfa:TrieDFA = new TrieDFA(5);
        dfa.insert([0, 1, 2, 3], 1);
        dfa.compile();

        this.assertEq(dfa.getDepth(TrieDFA.ROOT), 0, "Root depth is 0");

        var s1:Number = dfa.transition(TrieDFA.ROOT, 0);
        var s2:Number = dfa.transition(s1, 1);
        var s3:Number = dfa.transition(s2, 2);
        var s4:Number = dfa.transition(s3, 3);

        this.assertEq(dfa.getDepth(s1), 1, "Depth at state 1 is 1");
        this.assertEq(dfa.getDepth(s2), 2, "Depth at state 2 is 2");
        this.assertEq(dfa.getDepth(s3), 3, "Depth at state 3 is 3");
        this.assertEq(dfa.getDepth(s4), 4, "Depth at state 4 is 4");
    }

    public function testPatternMetadata():Void {
        trace("\n--- Test: Pattern Metadata ---");

        var dfa:TrieDFA = new TrieDFA(10);
        var id:Number = dfa.insert([1, 2, 3, 4, 5], 42);
        dfa.compile();

        this.assertEq(dfa.getPatternLength(id), 5, "Pattern length is 5");
        this.assertEq(dfa.getPriority(id), 42, "Priority is 42");

        var pattern:Array = dfa.getPattern(id);
        this.assertEq(pattern.length, 5, "Retrieved pattern has correct length");

        // 验证不存在的模式ID
        this.assertEq(dfa.getPatternLength(999), 0, "Non-existent pattern length is 0");
        this.assertEq(dfa.getPriority(999), 0, "Non-existent pattern priority is 0");
    }

    public function testMaxPatternLength():Void {
        trace("\n--- Test: Max Pattern Length ---");

        var dfa:TrieDFA = new TrieDFA(5);

        dfa.insert([0], 1);           // 长度 1
        dfa.insert([0, 1], 1);        // 长度 2
        dfa.insert([0, 1, 2, 3, 4], 1); // 长度 5

        this.assertEq(dfa.getMaxPatternLength(), 5, "Max pattern length is 5");

        dfa.insert([0, 1, 2], 1);     // 长度 3，不改变最大值
        this.assertEq(dfa.getMaxPatternLength(), 5, "Max pattern length unchanged");
    }

    // ========== 边界情况测试 ==========

    public function testEmptyDFA():Void {
        trace("\n--- Test: Empty DFA ---");

        var dfa:TrieDFA = new TrieDFA(5);
        dfa.compile();

        this.assertEq(dfa.getPatternCount(), 0, "Empty DFA has 0 patterns");
        this.assertEq(dfa.getStateCount(), 1, "Empty DFA has 1 state (root)");
        this.assertEq(dfa.match([0, 1, 2]), TrieDFA.NO_MATCH, "Match on empty DFA returns NO_MATCH");

        var results:Array = dfa.findAll([0, 1, 2, 3]);
        this.assertEq(results.length, 0, "findAll on empty DFA returns empty array");
    }

    public function testSingleSymbolPattern():Void {
        trace("\n--- Test: Single Symbol Pattern ---");

        var dfa:TrieDFA = new TrieDFA(5);
        var id:Number = dfa.insert([3], 1);
        dfa.compile();

        this.assertEq(dfa.match([3]), id, "Single symbol pattern matches");
        this.assertEq(dfa.match([3, 3]), TrieDFA.NO_MATCH, "Longer sequence doesn't match exact");
        this.assertEq(dfa.match([2]), TrieDFA.NO_MATCH, "Different symbol doesn't match");
    }

    public function testLongPattern():Void {
        trace("\n--- Test: Long Pattern ---");

        var dfa:TrieDFA = new TrieDFA(3);

        // 创建长度为100的模式
        var longPattern:Array = [];
        for (var i:Number = 0; i < 100; i++) {
            longPattern.push(i % 3);
        }

        var id:Number = dfa.insert(longPattern, 1);
        dfa.compile();

        this.assert(id != TrieDFA.INVALID, "Long pattern inserted successfully");
        this.assertEq(dfa.getPatternLength(id), 100, "Long pattern length is 100");
        this.assertEq(dfa.match(longPattern), id, "Long pattern matches");
    }

    public function testManyPatterns():Void {
        trace("\n--- Test: Many Patterns ---");

        var dfa:TrieDFA = new TrieDFA(10, 16);  // 小初始容量，测试扩容

        var count:Number = 100;
        for (var i:Number = 0; i < count; i++) {
            var pattern:Array = [i % 10, (i + 1) % 10, (i + 2) % 10];
            dfa.insert(pattern, i);
        }

        dfa.compile();

        this.assertEq(dfa.getPatternCount(), count, "All " + count + " patterns inserted");
        this.assert(dfa.getStateCount() > 1, "Multiple states created");
    }

    public function testDuplicatePatterns():Void {
        trace("\n--- Test: Duplicate Patterns ---");

        var dfa:TrieDFA = new TrieDFA(5);

        var id1:Number = dfa.insert([0, 1, 2], 5);
        var id2:Number = dfa.insert([0, 1, 2], 10);  // 相同模式，不同优先级

        dfa.compile();

        // 两个都应该成功插入（作为不同的模式）
        this.assert(id1 != TrieDFA.INVALID, "First duplicate insert succeeds");
        this.assert(id2 != TrieDFA.INVALID, "Second duplicate insert succeeds");
        this.assert(id1 != id2, "Different IDs for duplicate patterns");
        this.assertEq(dfa.getPatternCount(), 2, "Both patterns counted");

        // 匹配应该返回最后一个（因为它覆盖了接受状态）
        this.assertEq(dfa.match([0, 1, 2]), id2, "Match returns last inserted pattern");
    }

    public function testAlphabetBoundary():Void {
        trace("\n--- Test: Alphabet Boundary ---");

        var dfa:TrieDFA = new TrieDFA(3);  // 字母表 [0, 1, 2]

        // 边界有效值
        var id1:Number = dfa.insert([0], 1);
        var id2:Number = dfa.insert([2], 1);  // 最大有效符号

        this.assert(id1 != TrieDFA.INVALID, "Symbol 0 is valid");
        this.assert(id2 != TrieDFA.INVALID, "Symbol 2 (max) is valid");

        // 边界无效值
        var id3:Number = dfa.insert([3], 1);  // 越界
        this.assertEq(id3, TrieDFA.INVALID, "Symbol 3 is invalid (out of range)");
    }

    // ========== 便捷方法测试 ==========

    public function testMatch():Void {
        trace("\n--- Test: Match ---");

        var dfa:TrieDFA = new TrieDFA(5);
        var id1:Number = dfa.insert([0, 1, 2], 1);
        var id2:Number = dfa.insert([3, 4], 2);
        dfa.compile();

        this.assertEq(dfa.match([0, 1, 2]), id1, "Match [0,1,2] returns id1");
        this.assertEq(dfa.match([3, 4]), id2, "Match [3,4] returns id2");
    }

    public function testMatchPartial():Void {
        trace("\n--- Test: Match Partial ---");

        var dfa:TrieDFA = new TrieDFA(5);
        dfa.insert([0, 1, 2], 1);
        dfa.compile();

        // 部分匹配不应该返回结果
        this.assertEq(dfa.match([0, 1]), TrieDFA.NO_MATCH, "Partial match [0,1] returns NO_MATCH");
        this.assertEq(dfa.match([0]), TrieDFA.NO_MATCH, "Partial match [0] returns NO_MATCH");
    }

    public function testMatchNoMatch():Void {
        trace("\n--- Test: Match No Match ---");

        var dfa:TrieDFA = new TrieDFA(5);
        dfa.insert([0, 1, 2], 1);
        dfa.compile();

        this.assertEq(dfa.match([1, 2, 3]), TrieDFA.NO_MATCH, "Completely different sequence");
        this.assertEq(dfa.match([0, 2, 1]), TrieDFA.NO_MATCH, "Wrong order");
        this.assertEq(dfa.match([0, 1, 2, 3]), TrieDFA.NO_MATCH, "Too long");
        this.assertEq(dfa.match([]), TrieDFA.NO_MATCH, "Empty sequence");
    }

    public function testFindAll():Void {
        trace("\n--- Test: FindAll ---");

        var dfa:TrieDFA = new TrieDFA(5);
        var id1:Number = dfa.insert([0, 1], 1);
        var id2:Number = dfa.insert([2, 3], 2);
        dfa.compile();

        var results:Array = dfa.findAll([0, 1, 2, 3]);

        this.assertEq(results.length, 2, "Found 2 matches");

        // 验证第一个匹配
        this.assertEq(results[0].position, 0, "First match at position 0");
        this.assertEq(results[0].patternId, id1, "First match is pattern 1");

        // 验证第二个匹配
        this.assertEq(results[1].position, 2, "Second match at position 2");
        this.assertEq(results[1].patternId, id2, "Second match is pattern 2");
    }

    public function testFindAllOverlapping():Void {
        trace("\n--- Test: FindAll Overlapping ---");

        var dfa:TrieDFA = new TrieDFA(5);
        var id1:Number = dfa.insert([0, 1], 1);
        var id2:Number = dfa.insert([1, 2], 2);
        dfa.compile();

        // 序列 [0, 1, 2] 包含重叠的 [0,1] 和 [1,2]
        var results:Array = dfa.findAll([0, 1, 2]);

        this.assertEq(results.length, 2, "Found 2 overlapping matches");
        this.assertEq(results[0].position, 0, "First match at position 0");
        this.assertEq(results[1].position, 1, "Second match at position 1");
    }

    public function testFindAllWithMaxLen():Void {
        trace("\n--- Test: FindAll With MaxLen Optimization ---");

        var dfa:TrieDFA = new TrieDFA(5);
        dfa.insert([0], 1);           // 长度 1
        dfa.insert([0, 1], 2);        // 长度 2
        dfa.insert([0, 1, 2], 3);     // 长度 3 (最大)
        dfa.compile();

        this.assertEq(dfa.getMaxPatternLength(), 3, "Max pattern length is 3");

        // findAll 应该利用 maxPatternLen 进行剪枝
        var longSeq:Array = [0, 1, 2, 0, 1, 2, 0, 1, 2];
        var results:Array = dfa.findAll(longSeq);

        this.assert(results.length > 0, "Found matches in long sequence");
    }

    // ========== 扩容测试 ==========

    public function testAutoExpansion():Void {
        trace("\n--- Test: Auto Expansion ---");

        var dfa:TrieDFA = new TrieDFA(5, 4);  // 很小的初始容量

        // 插入足够多的模式来触发扩容
        var insertedCount:Number = 0;
        for (var i:Number = 0; i < 20; i++) {
            var pattern:Array = [];
            for (var j:Number = 0; j <= i; j++) {
                pattern.push(j % 5);
            }
            var id:Number = dfa.insert(pattern, i);
            if (id != TrieDFA.INVALID) {
                insertedCount++;
            }
        }

        dfa.compile();

        this.assertEq(insertedCount, 20, "All 20 patterns inserted despite small initial capacity");
        this.assert(dfa.getStateCount() > 4, "States expanded beyond initial capacity");
    }

    // ========== 调试方法测试 ==========

    public function testDump():Void {
        trace("\n--- Test: Dump ---");

        var dfa:TrieDFA = new TrieDFA(5);
        dfa.insert([0, 1], 5);
        dfa.insert([2, 3, 4], 10);
        dfa.compile();

        // dump() 只是打印，不返回值，验证不崩溃即可
        dfa.dump();
        this.assert(true, "dump() executed without error");
    }

    public function testGetTransitionsFrom():Void {
        trace("\n--- Test: GetTransitionsFrom ---");

        var dfa:TrieDFA = new TrieDFA(5);
        dfa.insert([0, 1], 1);
        dfa.insert([0, 2], 2);
        dfa.insert([0, 3], 3);
        dfa.compile();

        // 从根状态应该只有一个转移（到符号0）
        var rootTransitions:Array = dfa.getTransitionsFrom(TrieDFA.ROOT);
        this.assertEq(rootTransitions.length, 1, "Root has 1 transition");
        this.assertEq(rootTransitions[0].symbol, 0, "Root transition is on symbol 0");

        // 从符号0后的状态应该有3个转移（到1, 2, 3）
        var s1:Number = dfa.transition(TrieDFA.ROOT, 0);
        var s1Transitions:Array = dfa.getTransitionsFrom(s1);
        this.assertEq(s1Transitions.length, 3, "State after 0 has 3 transitions");
    }

    // ========== 流式输入测试（模拟搓招状态机）==========

    /**
     * 测试基础流式输入：逐符号推进状态，验证最终识别
     */
    public function testStreamingBasic():Void {
        trace("\n--- Test: Streaming Basic ---");

        var dfa:TrieDFA = new TrieDFA(5);
        // 模拟波动拳：↓↘→A (符号序列 [3, 4, 1, 0])
        var patternId:Number = dfa.insert([3, 4, 1, 0], 10);
        dfa.compile();

        // 模拟逐帧输入
        var state:Number = TrieDFA.ROOT;
        var frameInputs:Array = [3, 4, 1, 0];  // 每帧一个输入

        for (var i:Number = 0; i < frameInputs.length; i++) {
            var sym:Number = frameInputs[i];
            var nextState:Number = dfa.transition(state, sym);

            this.assert(nextState != undefined, "Frame " + i + ": transition exists for symbol " + sym);

            // 中间状态不应该是接受状态
            if (i < frameInputs.length - 1) {
                this.assertEq(dfa.getAccept(nextState), TrieDFA.NO_MATCH,
                    "Frame " + i + ": intermediate state is not accept");
            }

            state = nextState;
        }

        // 最终状态应该是接受状态
        this.assertEq(dfa.getAccept(state), patternId, "Final state accepts the pattern");
    }

    /**
     * 测试多模式下的流式识别：验证正确区分不同招式
     */
    public function testStreamingMultiplePatterns():Void {
        trace("\n--- Test: Streaming Multiple Patterns ---");

        var dfa:TrieDFA = new TrieDFA(5);
        // 模拟多个招式
        var wave:Number = dfa.insert([3, 4, 0], 10);    // 波动拳 ↓↘A
        var dash:Number = dfa.insert([1, 1], 5);        // 诛杀步 →→
        var back:Number = dfa.insert([2, 0], 5);        // 后撤 ←A
        dfa.compile();

        // 测试波动拳输入序列
        var state1:Number = TrieDFA.ROOT;
        state1 = dfa.transition(state1, 3);
        state1 = dfa.transition(state1, 4);
        state1 = dfa.transition(state1, 0);
        this.assertEq(dfa.getAccept(state1), wave, "Wave pattern recognized");

        // 测试诛杀步输入序列
        var state2:Number = TrieDFA.ROOT;
        state2 = dfa.transition(state2, 1);
        state2 = dfa.transition(state2, 1);
        this.assertEq(dfa.getAccept(state2), dash, "Dash pattern recognized");

        // 测试后撤输入序列
        var state3:Number = TrieDFA.ROOT;
        state3 = dfa.transition(state3, 2);
        state3 = dfa.transition(state3, 0);
        this.assertEq(dfa.getAccept(state3), back, "Back pattern recognized");
    }

    /**
     * 测试 hint 在流式输入过程中的变化
     */
    public function testStreamingHintProgression():Void {
        trace("\n--- Test: Streaming Hint Progression ---");

        var dfa:TrieDFA = new TrieDFA(5);
        // 一个长招式：↓↘→→A (5步)
        var longPattern:Number = dfa.insert([3, 4, 1, 1, 0], 10);
        dfa.compile();

        var state:Number = TrieDFA.ROOT;
        var inputs:Array = [3, 4, 1, 1, 0];

        for (var i:Number = 0; i < inputs.length; i++) {
            state = dfa.transition(state, inputs[i]);

            // 每一步的 hint 都应该指向我们的模式
            var hintId:Number = dfa.getHint(state);
            this.assertEq(hintId, longPattern, "Frame " + i + ": hint points to correct pattern");

            // 深度应该逐步增加
            var depth:Number = dfa.getDepth(state);
            this.assertEq(depth, i + 1, "Frame " + i + ": depth is " + (i + 1));
        }
    }

    /**
     * 测试输入中断后重新开始（模拟超时重置）
     */
    public function testStreamingTimeout():Void {
        trace("\n--- Test: Streaming Timeout ---");

        var dfa:TrieDFA = new TrieDFA(5);
        var patternId:Number = dfa.insert([3, 4, 1, 0], 10);
        dfa.compile();

        // 输入前两步
        var state:Number = TrieDFA.ROOT;
        state = dfa.transition(state, 3);
        state = dfa.transition(state, 4);
        this.assertEq(dfa.getDepth(state), 2, "Progressed to depth 2");

        // 模拟超时：重置到根状态
        state = TrieDFA.ROOT;
        this.assertEq(dfa.getDepth(state), 0, "Reset to root (depth 0)");

        // 重新完整输入
        state = dfa.transition(state, 3);
        state = dfa.transition(state, 4);
        state = dfa.transition(state, 1);
        state = dfa.transition(state, 0);
        this.assertEq(dfa.getAccept(state), patternId, "Pattern recognized after reset");
    }

    /**
     * 测试前缀模式的识别（短招和长招共享前缀）
     */
    public function testStreamingPrefixMatch():Void {
        trace("\n--- Test: Streaming Prefix Match ---");

        var dfa:TrieDFA = new TrieDFA(5);
        // 短招：↓A
        var shortPattern:Number = dfa.insert([3, 0], 5);
        // 长招：↓A→A（前缀包含短招）
        var longPattern:Number = dfa.insert([3, 0, 1, 0], 10);
        dfa.compile();

        // 输入 ↓A
        var state:Number = TrieDFA.ROOT;
        state = dfa.transition(state, 3);
        state = dfa.transition(state, 0);

        // 此时应该识别到短招
        this.assertEq(dfa.getAccept(state), shortPattern, "Short pattern recognized at [3,0]");

        // 继续输入 →A
        state = dfa.transition(state, 1);
        this.assertEq(dfa.getAccept(state), TrieDFA.NO_MATCH, "Intermediate state after [3,0,1]");

        state = dfa.transition(state, 0);
        this.assertEq(dfa.getAccept(state), longPattern, "Long pattern recognized at [3,0,1,0]");
    }

    // ========== 性能测试 ==========

    public function testBasicPerformance():Void {
        trace("\n--- Test: Basic Performance ---");

        var dfa:TrieDFA = new TrieDFA(10);
        dfa.insert([0, 1, 2, 3, 4], 1);
        dfa.compile();

        var iterations:Number = 10000;
        var self = this;

        var time:Number = this.measureTime(function() {
            var s:Number = TrieDFA.ROOT;
            s = dfa.transition(s, 0);
            s = dfa.transition(s, 1);
            s = dfa.transition(s, 2);
            s = dfa.transition(s, 3);
            s = dfa.transition(s, 4);
            dfa.getAccept(s);
        }, iterations, "Basic 5-step transition");

        trace("Basic Performance: " + iterations + " traversals in " + time + "ms");
        this.assert(time < 1000, "Basic traversal performance acceptable");
    }

    public function testTransitionPerformance():Void {
        trace("\n--- Test: Transition Performance ---");

        var dfa:TrieDFA = new TrieDFA(100);

        // 创建有很多分支的DFA
        for (var i:Number = 0; i < 100; i++) {
            dfa.insert([i], i);
        }
        dfa.compile();

        var iterations:Number = 100000;

        var time:Number = this.measureTime(function() {
            dfa.transition(TrieDFA.ROOT, iterations % 100);
        }, iterations, "Single transition");

        trace("Transition Performance: " + iterations + " single transitions in " + time + "ms");
        this.assert(time < 500, "Single transition performance acceptable");
    }

    public function testManyPatternsPerformance():Void {
        trace("\n--- Test: Many Patterns Performance ---");

        var dfa:TrieDFA = new TrieDFA(20);

        // 插入1000个不同的模式
        var insertStart:Number = getTimer();
        for (var i:Number = 0; i < 1000; i++) {
            var pattern:Array = [
                i % 20,
                (i * 7) % 20,
                (i * 13) % 20
            ];
            dfa.insert(pattern, i);
        }
        var insertTime:Number = getTimer() - insertStart;

        var compileStart:Number = getTimer();
        dfa.compile();
        var compileTime:Number = getTimer() - compileStart;

        trace("Insert 1000 patterns: " + insertTime + "ms");
        trace("Compile: " + compileTime + "ms");

        this.assert(insertTime < 2000, "Insert 1000 patterns in acceptable time");
        this.assert(compileTime < 100, "Compile in acceptable time");
    }

    public function testFindAllPerformance():Void {
        trace("\n--- Test: FindAll Performance ---");

        var dfa:TrieDFA = new TrieDFA(10);

        // 插入一些模式
        for (var i:Number = 0; i < 50; i++) {
            dfa.insert([i % 10, (i + 1) % 10], i);
        }
        dfa.compile();

        // 创建长序列
        var sequence:Array = [];
        for (var j:Number = 0; j < 1000; j++) {
            sequence.push(j % 10);
        }

        var iterations:Number = 100;
        var time:Number = this.measureTime(function() {
            dfa.findAll(sequence);
        }, iterations, "FindAll on 1000-symbol sequence");

        trace("FindAll Performance: " + iterations + " calls on 1000-symbol sequence in " + time + "ms");
        this.assert(time < 3000, "FindAll performance acceptable");
    }

    public function testScalability():Void {
        trace("\n--- Test: Scalability ---");

        var scales:Array = [10, 50, 100, 500];
        var results:Array = [];

        for (var s:Number = 0; s < scales.length; s++) {
            var scale:Number = scales[s];
            var dfa:TrieDFA = new TrieDFA(20);

            var insertStart:Number = getTimer();
            for (var i:Number = 0; i < scale; i++) {
                dfa.insert([i % 20, (i * 3) % 20, (i * 7) % 20], i);
            }
            dfa.compile();
            var insertTime:Number = getTimer() - insertStart;

            var matchStart:Number = getTimer();
            for (var j:Number = 0; j < 1000; j++) {
                dfa.match([j % 20, (j * 3) % 20, (j * 7) % 20]);
            }
            var matchTime:Number = getTimer() - matchStart;

            results.push({scale: scale, insert: insertTime, match: matchTime});
            trace("Scale " + scale + ": Insert " + insertTime + "ms, 1000 matches " + matchTime + "ms");
        }

        // 验证可扩展性（重点关注匹配性能，插入是构建阶段操作）
        var scalabilityGood:Boolean = true;

        // 策略1：匹配时间应该保持相对稳定（因为 DFA 转移是 O(1)）
        // 允许最大匹配时间不超过最小匹配时间的 3 倍
        var minMatchTime:Number = results[0].match;
        var maxMatchTime:Number = results[0].match;
        for (var r:Number = 1; r < results.length; r++) {
            if (results[r].match < minMatchTime) minMatchTime = results[r].match;
            if (results[r].match > maxMatchTime) maxMatchTime = results[r].match;
        }

        // 避免除零：如果最小时间为0，用1ms作为下界
        if (minMatchTime < 1) minMatchTime = 1;

        // 匹配时间波动应在合理范围内（3倍容忍度）
        if (maxMatchTime > minMatchTime * 3) {
            scalabilityGood = false;
            trace("  [Warning] Match time variance too high: min=" + minMatchTime + "ms, max=" + maxMatchTime + "ms");
        }

        // 策略2：最大规模（500 patterns）的匹配时间应该在绝对可接受范围内
        var maxScaleMatchTime:Number = results[results.length - 1].match;
        var absoluteThreshold:Number = 50; // 50ms 绝对上限
        if (maxScaleMatchTime > absoluteThreshold) {
            scalabilityGood = false;
            trace("  [Warning] Max scale match time exceeds threshold: " + maxScaleMatchTime + "ms > " + absoluteThreshold + "ms");
        }

        this.assert(scalabilityGood, "Scalability is acceptable");
    }

    // ========== 报告生成 ==========

    public function printFinalReport():Void {
        trace("\n=== TRIEDFA TEST FINAL REPORT ===");
        trace("Tests Passed: " + this._testPassed);
        trace("Tests Failed: " + this._testFailed);
        trace("Success Rate: " + Math.round((this._testPassed / (this._testPassed + this._testFailed)) * 100) + "%");

        if (this._testFailed == 0) {
            trace("ALL TRIEDFA TESTS PASSED!");
        } else {
            trace("Some TrieDFA tests failed. Review implementation.");
        }

        trace("\n=== TRIEDFA VERIFICATION SUMMARY ===");
        trace("* Basic DFA operations verified");
        trace("* Insert validation (no half-insert) confirmed");
        trace("* Hint priority/length strategy tested");
        trace("* Prefix sharing optimization verified");
        trace("* Edge cases and boundaries handled");
        trace("* Convenience methods (match, findAll) tested");
        trace("* Performance benchmarks established");
        trace("* Auto-expansion mechanism verified");
        trace("=============================\n");
    }

    public function generatePerformanceReport():Void {
        trace("\n=== TRIEDFA PERFORMANCE ANALYSIS ===");

        for (var i:Number = 0; i < this._performanceLog.length; i++) {
            var entry = this._performanceLog[i];
            var avgMs:Number = entry.avgPerOperation;
            // AS2 兼容的小数格式化
            var avgMsStr:String = this.formatNumber(avgMs, 4);
            var opsPerSec:Number = (avgMs > 0) ? Math.round(1000 / avgMs) : 0;

            trace("Context: " + entry.context);
            trace("  Iterations: " + entry.iterations);
            trace("  Total Time: " + entry.elapsed + "ms");
            trace("  Avg per Operation: " + avgMsStr + "ms");
            trace("  Operations per Second: " + opsPerSec);
            trace("---");
        }

        trace("=============================\n");
    }

    /**
     * AS2 兼容的数字格式化（替代 toFixed）
     */
    private function formatNumber(num:Number, decimals:Number):String {
        if (num == undefined || isNaN(num)) return "0";
        var factor:Number = Math.pow(10, decimals);
        var rounded:Number = Math.round(num * factor) / factor;
        return String(rounded);
    }
}
