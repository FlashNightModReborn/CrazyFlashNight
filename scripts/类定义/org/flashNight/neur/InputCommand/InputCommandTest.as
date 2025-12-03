import org.flashNight.neur.InputCommand.InputEvent; 
import org.flashNight.neur.InputCommand.InputHistoryBuffer;
import org.flashNight.neur.InputCommand.InputSampler;
import org.flashNight.neur.InputCommand.CommandDFA;
import org.flashNight.neur.InputCommand.CommandRegistry;
import org.flashNight.neur.InputCommand.CommandConfig;
import org.flashNight.neur.InputCommand.InputReplayAnalyzer;

/**
 * InputCommand 模块单元测试
 *
 * 测试新增的优化功能：
 * - InputHistoryBuffer 环形缓冲区
 * - CommandDFA.updateWithHistory 窗口匹配
 * - CommandDFA.updateFast 热路径优化
 * - CommandDFA.updateWithDynamicTimeout 动态超时
 * - InputReplayAnalyzer 离线分析
 *
 * @author FlashNight
 * @version 1.0
 */
class org.flashNight.neur.InputCommand.InputCommandTest {

    // ========== 测试计数 ==========

    private var passCount:Number;
    private var failCount:Number;

    // ========== 测试实例 ==========

    private var registry:CommandRegistry;
    private var dfa:CommandDFA;

    // ========== 构造函数 ==========

    public function InputCommandTest() {
        this.passCount = 0;
        this.failCount = 0;
    }

    // ========== 主入口 ==========

    public function runTests():Void {
        trace("\n=== Running InputCommand Optimization Tests ===\n");

        // 初始化测试环境
        this.setupTestEnvironment();

        // 运行各模块测试
        this.testInputHistoryBuffer();
        this.testCommandDFAUpdateWithHistory();
        this.testCommandDFAUpdateFast();
        this.testCommandDFADynamicTimeout();
        this.testCommandDFAGetAvailableMoves();
        this.testInputReplayAnalyzer();
        this.testIntegration();

        // 输出结果
        trace("\n=== INPUT COMMAND TEST FINAL REPORT ===");
        trace("Tests Passed: " + this.passCount);
        trace("Tests Failed: " + this.failCount);
        trace("Success Rate: " + Math.round(this.passCount / (this.passCount + this.failCount) * 100) + "%");

        if (this.failCount == 0) {
            trace("ALL INPUT COMMAND TESTS PASSED!");
        } else {
            trace("SOME TESTS FAILED!");
        }
        trace("========================================\n");
    }

    // ========== 测试环境初始化 ==========

    private function setupTestEnvironment():Void {
        trace("--- Setting up test environment ---");

        // 使用空手配置创建注册表
        this.registry = new CommandRegistry(64);
        this.registry.loadConfig(CommandConfig.getBarehanded());
        this.registry.compile();

        this.dfa = this.registry.getDFA();

        trace("Registered commands: " + this.dfa.getCommandCount());
        this.dfa.dump();
    }

    // ========== InputHistoryBuffer 测试 ==========

    private function testInputHistoryBuffer():Void {
        trace("\n--- Test: InputHistoryBuffer ---");

        // 测试创建
        var buffer:InputHistoryBuffer = new InputHistoryBuffer(32, 10);
        this.assert(buffer != null, "Buffer created successfully");
        this.assert(buffer.isEmpty(), "New buffer is empty");
        this.assert(buffer.getEventCount() == 0, "Event count is 0");
        this.assert(buffer.getFrameCount() == 0, "Frame count is 0");

        // 测试追加帧
        buffer.appendFrame([InputEvent.DOWN, InputEvent.FORWARD]);
        this.assert(buffer.getEventCount() == 2, "Event count after first frame (got: " + buffer.getEventCount() + ")");
        this.assert(buffer.getFrameCount() == 1, "Frame count after first frame (got: " + buffer.getFrameCount() + ")");

        buffer.appendFrame([InputEvent.A_PRESS]);
        this.assert(buffer.getEventCount() == 3, "Event count after second frame (got: " + buffer.getEventCount() + ")");
        this.assert(buffer.getFrameCount() == 2, "Frame count after second frame (got: " + buffer.getFrameCount() + ")");

        // 测试获取序列
        var seq:Array = buffer.getSequence();
        this.assert(seq.length == 3, "Sequence length is 3 (got: " + seq.length + ")");
        this.assert(seq[0] == InputEvent.DOWN, "First event is DOWN");
        this.assert(seq[1] == InputEvent.FORWARD, "Second event is FORWARD");
        this.assert(seq[2] == InputEvent.A_PRESS, "Third event is A_PRESS");

        // 测试窗口查询
        var windowStart:Number = buffer.getWindowStart(1); // 最近1帧
        this.assert(windowStart == 2, "Window start for 1 frame (got: " + windowStart + ")");

        windowStart = buffer.getWindowStart(2); // 最近2帧
        this.assert(windowStart == 0, "Window start for 2 frames (got: " + windowStart + ")");

        // 测试清空
        buffer.clear();
        this.assert(buffer.isEmpty(), "Buffer is empty after clear");
        this.assert(buffer.getEventCount() == 0, "Event count is 0 after clear");

        // 测试容量限制（帧超限）
        var smallBuffer:InputHistoryBuffer = new InputHistoryBuffer(100, 3);
        smallBuffer.appendFrame([1, 2]);
        smallBuffer.appendFrame([3, 4]);
        smallBuffer.appendFrame([5, 6]);
        smallBuffer.appendFrame([7, 8]); // 这会导致最老帧被丢弃

        this.assert(smallBuffer.getFrameCount() == 3, "Frame count limited to 3 (got: " + smallBuffer.getFrameCount() + ")");
        var smallSeq:Array = smallBuffer.getSequence();
        this.assert(smallSeq[0] == 3, "Oldest events discarded, first is 3 (got: " + smallSeq[0] + ")");

        trace("InputHistoryBuffer tests completed");
    }

    // ========== CommandDFA.updateWithHistory 测试 ==========

    private function testCommandDFAUpdateWithHistory():Void {
        trace("\n--- Test: CommandDFA.updateWithHistory ---");

        // 创建测试单位
        var unit:Object = {};

        // 模拟波动拳输入序列：↘ + A
        // 帧1: DOWN_FORWARD
        this.dfa.updateWithHistory(unit, [InputEvent.DOWN_FORWARD], 15);
        this.assert(unit.commandId == CommandDFA.NO_COMMAND, "No command after first input");

        // 帧2: A_PRESS
        this.dfa.updateWithHistory(unit, [InputEvent.A_PRESS], 15);
        this.assert(unit.commandId != CommandDFA.NO_COMMAND, "Command recognized after complete input");

        var cmdName:String = this.dfa.getCommandName(unit.commandId);
        this.assert(cmdName == "波动拳", "Recognized command is 波动拳 (got: " + cmdName + ")");

        // 测试重复触发保护
        var prevMatchEnd:Number = unit.lastMatchEndPos;
        this.dfa.updateWithHistory(unit, [], 15);
        this.assert(unit.commandId == CommandDFA.NO_COMMAND, "No repeated trigger on same match");

        // 测试新输入能触发新命令
        // 模拟诛杀步：双击前
        unit = {}; // 重置单位
        this.dfa.updateWithHistory(unit, [InputEvent.DOUBLE_TAP_FORWARD], 15);
        this.assert(unit.commandId != CommandDFA.NO_COMMAND, "诛杀步 recognized");
        cmdName = this.dfa.getCommandName(unit.commandId);
        this.assert(cmdName == "诛杀步", "Recognized command is 诛杀步 (got: " + cmdName + ")");

        trace("CommandDFA.updateWithHistory tests completed");
    }

    // ========== CommandDFA.updateFast 测试 ==========

    private function testCommandDFAUpdateFast():Void {
        trace("\n--- Test: CommandDFA.updateFast ---");

        var unit:Object = {};

        // 使用 updateFast 测试波动拳
        this.dfa.updateFast(unit, [InputEvent.DOWN_FORWARD], 5);
        this.assert(unit.commandState != CommandDFA.ROOT_STATE, "State advanced after DOWN_FORWARD");
        this.assert(unit.commandId == CommandDFA.NO_COMMAND, "No command yet");

        this.dfa.updateFast(unit, [InputEvent.A_PRESS], 5);
        this.assert(unit.commandId != CommandDFA.NO_COMMAND, "Command recognized with updateFast");

        var cmdName:String = this.dfa.getCommandName(unit.commandId);
        this.assert(cmdName == "波动拳", "波动拳 recognized with updateFast (got: " + cmdName + ")");

        // 测试超时
        unit = {};
        this.dfa.updateFast(unit, [InputEvent.DOWN_FORWARD], 5);
        var stateAfterInput:Number = unit.commandState;

        // 模拟6帧无输入（超过5帧超时）
        for (var i:Number = 0; i < 6; i++) {
            this.dfa.updateFast(unit, [], 5);
        }
        this.assert(unit.commandState == CommandDFA.ROOT_STATE, "State reset after timeout");

        trace("CommandDFA.updateFast tests completed");
    }

    // ========== CommandDFA.updateWithDynamicTimeout 测试 ==========

    private function testCommandDFADynamicTimeout():Void {
        trace("\n--- Test: CommandDFA.updateWithDynamicTimeout ---");

        var unit:Object = {};

        // 动态超时：timeout = BASE(3) + depth * FACTOR(2)
        // 深度1时：timeout = 3 + 1*2 = 5
        // 深度2时：timeout = 3 + 2*2 = 7

        // 测试深度1的超时
        this.dfa.updateWithDynamicTimeout(unit, [InputEvent.FORWARD]); // 前
        var depth:Number = this.dfa.getTrieDFA().getDepth(unit.commandState);
        trace("  Depth after FORWARD: " + depth);

        // 深度1，超时应为5帧
        for (var i:Number = 0; i < 5; i++) {
            this.dfa.updateWithDynamicTimeout(unit, []);
        }
        this.assert(unit.commandState != CommandDFA.ROOT_STATE, "State not reset within dynamic timeout");

        // 再过一帧，应该超时
        this.dfa.updateWithDynamicTimeout(unit, []);
        this.assert(unit.commandState == CommandDFA.ROOT_STATE, "State reset after dynamic timeout exceeded");

        trace("CommandDFA.updateWithDynamicTimeout tests completed");
    }

    // ========== CommandDFA.getAvailableMoves 测试 ==========

    private function testCommandDFAGetAvailableMoves():Void {
        trace("\n--- Test: CommandDFA.getAvailableMoves ---");

        // 从根状态获取可用移动
        var moves:Array = this.dfa.getAvailableMoves(CommandDFA.ROOT_STATE);
        this.assert(moves.length > 0, "Root state has available moves (got: " + moves.length + ")");

        trace("  Available moves from root:");
        for (var i:Number = 0; i < moves.length; i++) {
            var move:Object = moves[i];
            trace("    " + move.name + " -> state " + move.nextState +
                  (move.leadsToAccept ? " [ACCEPT]" : ""));
        }

        // 验证移动结构
        var firstMove:Object = moves[0];
        this.assert(firstMove.symbol != undefined, "Move has symbol");
        this.assert(firstMove.name != undefined, "Move has name");
        this.assert(firstMove.nextState != undefined, "Move has nextState");

        trace("CommandDFA.getAvailableMoves tests completed");
    }

    // ========== InputReplayAnalyzer 测试 ==========

    private function testInputReplayAnalyzer():Void {
        trace("\n--- Test: InputReplayAnalyzer ---");

        var analyzer:InputReplayAnalyzer = new InputReplayAnalyzer(this.registry);

        // 创建测试序列：波动拳 + 诛杀步
        // 波动拳: DOWN_FORWARD, A_PRESS
        // 诛杀步: DOUBLE_TAP_FORWARD
        var testSequence:Array = [
            InputEvent.DOWN_FORWARD,
            InputEvent.A_PRESS,
            InputEvent.NONE,
            InputEvent.DOUBLE_TAP_FORWARD
        ];

        // 分析
        var report:Object = analyzer.analyze(testSequence);

        trace("  Sequence length: " + report.sequenceLength);
        trace("  Total matches: " + report.totalMatches);

        this.assert(report.sequenceLength == 4, "Sequence length is 4");
        this.assert(report.totalMatches >= 2, "At least 2 matches found (got: " + report.totalMatches + ")");

        // 检查命令
        var foundHadouken:Boolean = false;
        var foundDash:Boolean = false;

        for (var i:Number = 0; i < report.commands.length; i++) {
            var cmd:Object = report.commands[i];
            trace("  Found: " + cmd.name + " @ pos " + cmd.position);
            if (cmd.name == "波动拳") foundHadouken = true;
            if (cmd.name == "诛杀步") foundDash = true;
        }

        this.assert(foundHadouken, "波动拳 found in analysis");
        this.assert(foundDash, "诛杀步 found in analysis");

        // 测试统计
        this.assert(report.stats["波动拳"] != undefined, "Stats contain 波动拳");
        this.assert(report.stats["诛杀步"] != undefined, "Stats contain 诛杀步");

        // 测试快速计数
        var count:Number = analyzer.countMatches(testSequence);
        this.assert(count >= 2, "countMatches returns correct count");

        // 测试位置查找
        var hadoukenCmd:Number = this.registry.getCommandId("波动拳");
        var positions:Array = analyzer.findCommandPositions(testSequence, hadoukenCmd);
        this.assert(positions.length >= 1, "findCommandPositions found 波动拳");

        // 打印报告
        trace("\n" + analyzer.generateReport(testSequence));

        trace("InputReplayAnalyzer tests completed");
    }

    // ========== 集成测试 ==========

    private function testIntegration():Void {
        trace("\n--- Test: Integration ---");

        // 测试 InputSampler 与历史缓冲集成
        var sampler:InputSampler = new InputSampler();
        sampler.enableHistory(64, 30);

        this.assert(sampler.isHistoryEnabled(), "History enabled");
        this.assert(sampler.getHistoryBuffer() != null, "History buffer created");

        // 模拟单位
        var mockUnit:Object = {
            方向: "右",
            左行: false,
            右行: true,
            上行: false,
            下行: true,
            动作A: true,
            动作B: false
        };

        // 采样
        var events:Array = sampler.sampleWithHistory(mockUnit);
        trace("  Sampled events: " + sampler.eventsToString(events));

        // 检查历史
        var historyInfo:Object = sampler.getHistoryInfo();
        this.assert(historyInfo.enabled, "History info shows enabled");
        this.assert(historyInfo.eventCount > 0, "History has events");
        this.assert(historyInfo.frameCount == 1, "History has 1 frame");

        // 测试完整流程：采样 -> 历史 -> 匹配
        var buffer:InputHistoryBuffer = sampler.getHistoryBuffer();

        // 模拟更多帧
        mockUnit.下行 = false;
        mockUnit.右行 = false;
        mockUnit.动作A = false;
        sampler.sampleWithHistory(mockUnit);

        mockUnit.动作A = true; // 再次按A
        sampler.sampleWithHistory(mockUnit);

        trace("  History frames: " + buffer.getFrameCount());
        trace("  History events: " + buffer.getEventCount());

        // 使用 findMatchesInWindow 检测
        var matchCount:Number = this.dfa.findMatchesInWindow(buffer, 10);
        trace("  Matches in window: " + matchCount);

        trace("Integration tests completed");
    }

    // ========== 断言辅助 ==========

    private function assert(condition:Boolean, message:String):Void {
        if (condition) {
            trace("[PASS] " + message);
            this.passCount++;
        } else {
            trace("[FAIL] " + message);
            this.failCount++;
        }
    }
}
