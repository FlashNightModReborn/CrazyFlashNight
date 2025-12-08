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
        this.testInputHistoryBufferAdvanced();
        this.testInputSamplerDoubleTap();
        this.testInputSamplerDoubleTapTimeout();
        this.testInputSamplerDoubleTapBack();
        this.testInputSamplerDoubleTapDecoupled();
        this.testInputSamplerCKeyEdge();
        this.testCommandDFAUpdateWithHistory();
        this.testCommandDFAPrefixConflict();
        this.testCommandDFAUpdateFast();
        this.testCommandDFADynamicTimeout();
        this.testCommandDFADynamicTimeoutLongPattern();
        this.testCommandDFAGetAvailableMoves();
        this.testInputReplayAnalyzer();
        this.testInputReplayAnalyzerFilters();
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

    // ========== InputHistoryBuffer 高级测试 ==========

    private function testInputHistoryBufferAdvanced():Void {
        trace("\n--- Test: InputHistoryBuffer Advanced ---");

        // 测试事件容量限制
        var eventLimitBuffer:InputHistoryBuffer = new InputHistoryBuffer(8, 10);
        eventLimitBuffer.appendFrame([1, 2, 3]); // 3 events
        eventLimitBuffer.appendFrame([4, 5, 6]); // 6 events
        eventLimitBuffer.appendFrame([7, 8]);    // 8 events (满)
        eventLimitBuffer.appendFrame([9, 10]);   // 会导致旧事件被淘汰

        this.assert(eventLimitBuffer.getEventCount() <= 8,
            "Event count limited to capacity (got: " + eventLimitBuffer.getEventCount() + ")");

        // 测试 getWindowStartByTime
        var timeBuffer:InputHistoryBuffer = new InputHistoryBuffer(32, 10);
        timeBuffer.appendFrame([1], 100);
        timeBuffer.appendFrame([2], 105);
        timeBuffer.appendFrame([3], 110);

        var startByTime:Number = timeBuffer.getWindowStartByTime(105);
        this.assert(startByTime == 1, "getWindowStartByTime returns correct position (got: " + startByTime + ")");

        startByTime = timeBuffer.getWindowStartByTime(999);
        this.assert(startByTime == timeBuffer.getEventCount(),
            "getWindowStartByTime returns end for future timestamp (got: " + startByTime + ")");

        // 测试 getFrameRange 边界
        var rangeBuffer:InputHistoryBuffer = new InputHistoryBuffer(32, 10);
        rangeBuffer.appendFrame([1, 2]);
        rangeBuffer.appendFrame([3, 4]);
        rangeBuffer.appendFrame([5, 6]);

        var range:Object = rangeBuffer.getFrameRange(1, 2);
        this.assert(range.start == 2, "getFrameRange start correct (got: " + range.start + ")");
        this.assert(range.end == 4, "getFrameRange end correct (got: " + range.end + ")");

        // 边界情况：fromFrame >= toFrame
        range = rangeBuffer.getFrameRange(2, 2);
        this.assert(range.start == range.end, "getFrameRange empty when from==to");

        range = rangeBuffer.getFrameRange(5, 3);
        this.assert(range.start == range.end, "getFrameRange empty when from>to");

        // 测试多次 clear 后的一致性
        var clearBuffer:InputHistoryBuffer = new InputHistoryBuffer(32, 10);
        clearBuffer.appendFrame([1, 2]);
        clearBuffer.clear();
        clearBuffer.appendFrame([3, 4]);
        clearBuffer.clear();
        clearBuffer.appendFrame([5, 6]);

        this.assert(clearBuffer.getEventCount() == 2,
            "Event count correct after multiple clear (got: " + clearBuffer.getEventCount() + ")");
        this.assert(clearBuffer.getFrameCount() == 1,
            "Frame count correct after multiple clear (got: " + clearBuffer.getFrameCount() + ")");

        var clearSeq:Array = clearBuffer.getSequence();
        this.assert(clearSeq[0] == 5 && clearSeq[1] == 6,
            "Sequence correct after multiple clear");

        trace("InputHistoryBuffer Advanced tests completed");
    }

    // ========== InputSampler 双击检测测试 ==========

    /**
     * 测试 InputSampler 基础双击检测（前方向）
     * 验证边沿检测逻辑：释放 -> 在窗口内再次按下 -> 触发事件
     */
    private function testInputSamplerDoubleTap():Void {
        trace("\n--- Test: InputSampler DoubleTap Basic ---");

        var sampler:InputSampler = new InputSampler();

        // 构造假 unit（面向右，doubleTapRunDirection 不设置）
        var unit:Object = {
            方向: "右",
            左行: false,
            右行: false,
            上行: false,
            下行: false,
            动作A: false,
            动作B: false
        };

        // 帧1：按住前（右）
        unit.右行 = true;
        var events1:Array = sampler.sample(unit);
        var hasDoubleTap1:Boolean = this.arrayContains(events1, InputEvent.DOUBLE_TAP_FORWARD);
        this.assert(!hasDoubleTap1, "Frame 1: No DOUBLE_TAP on first press");
        this.assert(this.arrayContains(events1, InputEvent.FORWARD), "Frame 1: FORWARD event present");

        // 帧2-3：保持按住
        var events2:Array = sampler.sample(unit);
        var hasDoubleTap2:Boolean = this.arrayContains(events2, InputEvent.DOUBLE_TAP_FORWARD);
        this.assert(!hasDoubleTap2, "Frame 2: No DOUBLE_TAP while holding");

        var events3:Array = sampler.sample(unit);
        var hasDoubleTap3:Boolean = this.arrayContains(events3, InputEvent.DOUBLE_TAP_FORWARD);
        this.assert(!hasDoubleTap3, "Frame 3: No DOUBLE_TAP while still holding");

        // 帧4：释放前方向
        unit.右行 = false;
        var events4:Array = sampler.sample(unit);
        var hasDoubleTap4:Boolean = this.arrayContains(events4, InputEvent.DOUBLE_TAP_FORWARD);
        this.assert(!hasDoubleTap4, "Frame 4: No DOUBLE_TAP on release");
        this.assert(!this.arrayContains(events4, InputEvent.FORWARD), "Frame 4: No FORWARD after release");

        // 帧5-6：空帧（模拟短暂间隔）
        sampler.sample(unit);
        sampler.sample(unit);

        // 帧7：再次按下前方向（在窗口内，应触发双击）
        unit.右行 = true;
        var events7:Array = sampler.sample(unit);
        var hasDoubleTap7:Boolean = this.arrayContains(events7, InputEvent.DOUBLE_TAP_FORWARD);
        this.assert(hasDoubleTap7, "Frame 7: DOUBLE_TAP_FORWARD triggered on second press within window");

        // 帧8：继续按住（不应再次触发）
        var events8:Array = sampler.sample(unit);
        var hasDoubleTap8:Boolean = this.arrayContains(events8, InputEvent.DOUBLE_TAP_FORWARD);
        this.assert(!hasDoubleTap8, "Frame 8: No repeated DOUBLE_TAP while holding");

        // 帧9：继续按住
        var events9:Array = sampler.sample(unit);
        var hasDoubleTap9:Boolean = this.arrayContains(events9, InputEvent.DOUBLE_TAP_FORWARD);
        this.assert(!hasDoubleTap9, "Frame 9: No repeated DOUBLE_TAP while still holding");

        trace("InputSampler DoubleTap Basic tests completed");
    }

    /**
     * 测试双击超时（超过窗口不触发）
     */
    private function testInputSamplerDoubleTapTimeout():Void {
        trace("\n--- Test: InputSampler DoubleTap Timeout ---");

        var sampler:InputSampler = new InputSampler();
        // 默认 doubleTapWindow = 12 帧

        var unit:Object = {
            方向: "右",
            左行: false,
            右行: false,
            上行: false,
            下行: false,
            动作A: false,
            动作B: false
        };

        // 第一次按下并释放
        unit.右行 = true;
        sampler.sample(unit); // 帧1：按下

        unit.右行 = false;
        sampler.sample(unit); // 帧2：释放（记录时间戳）

        // 等待超过 doubleTapWindow（12帧）
        for (var i:Number = 0; i < 13; i++) {
            sampler.sample(unit); // 帧3-15：空帧
        }

        // 第二次按下（超出窗口，不应触发）
        unit.右行 = true;
        var events:Array = sampler.sample(unit); // 帧16
        var hasDoubleTap:Boolean = this.arrayContains(events, InputEvent.DOUBLE_TAP_FORWARD);
        this.assert(!hasDoubleTap, "No DOUBLE_TAP when exceeding window (13 frames gap)");

        // 验证仍然有普通 FORWARD 事件
        this.assert(this.arrayContains(events, InputEvent.FORWARD), "FORWARD event still present");

        trace("InputSampler DoubleTap Timeout tests completed");
    }

    /**
     * 测试后方向双击（对称性验证）
     */
    private function testInputSamplerDoubleTapBack():Void {
        trace("\n--- Test: InputSampler DoubleTap Back ---");

        var sampler:InputSampler = new InputSampler();

        // 面向右时，左行 = 后方向
        var unit:Object = {
            方向: "右",
            左行: false,
            右行: false,
            上行: false,
            下行: false,
            动作A: false,
            动作B: false
        };

        // 第一次按下后方向
        unit.左行 = true;
        var events1:Array = sampler.sample(unit);
        this.assert(this.arrayContains(events1, InputEvent.BACK), "Frame 1: BACK event present");
        this.assert(!this.arrayContains(events1, InputEvent.DOUBLE_TAP_BACK), "Frame 1: No DOUBLE_TAP_BACK on first press");

        // 释放
        unit.左行 = false;
        sampler.sample(unit);

        // 短暂间隔
        sampler.sample(unit);
        sampler.sample(unit);

        // 第二次按下（在窗口内）
        unit.左行 = true;
        var events5:Array = sampler.sample(unit);
        this.assert(this.arrayContains(events5, InputEvent.DOUBLE_TAP_BACK), "DOUBLE_TAP_BACK triggered within window");

        // 测试面向左时的后方向（右行变成后）
        sampler.reset();
        unit.方向 = "左";
        unit.左行 = false;
        unit.右行 = false;

        // 第一次按下后方向（面向左时，右行 = 后）
        unit.右行 = true;
        sampler.sample(unit);

        // 释放
        unit.右行 = false;
        sampler.sample(unit);

        // 短暂间隔
        sampler.sample(unit);

        // 第二次按下
        unit.右行 = true;
        var eventsBack:Array = sampler.sample(unit);
        this.assert(this.arrayContains(eventsBack, InputEvent.DOUBLE_TAP_BACK), "DOUBLE_TAP_BACK works when facing left");

        trace("InputSampler DoubleTap Back tests completed");
    }

    /**
     * 测试与 doubleTapRunDirection 解耦
     * 验证即使 doubleTapRunDirection 持续有值，也不会产生连续双击事件
     */
    private function testInputSamplerDoubleTapDecoupled():Void {
        trace("\n--- Test: InputSampler DoubleTap Decoupled from doubleTapRunDirection ---");

        var sampler:InputSampler = new InputSampler();

        var unit:Object = {
            方向: "右",
            左行: false,
            右行: true,  // 持续按住右
            上行: false,
            下行: false,
            动作A: false,
            动作B: false,
            doubleTapRunDirection: 1  // 外部奔跑系统设置的双击方向
        };

        var doubleTapCount:Number = 0;

        // 模拟10帧持续按住方向，doubleTapRunDirection 始终为 1
        for (var i:Number = 0; i < 10; i++) {
            var events:Array = sampler.sample(unit);
            if (this.arrayContains(events, InputEvent.DOUBLE_TAP_FORWARD)) {
                doubleTapCount++;
                trace("  Frame " + (i + 1) + ": DOUBLE_TAP_FORWARD detected");
            }
        }

        // 帧1：doubleTapRunDirection 从 0→1 边沿触发一次 DOUBLE_TAP_FORWARD
        // 帧2-10：保持为1，非边沿，不再触发
        this.assert(doubleTapCount == 1,
            "Exactly 1 DOUBLE_TAP on edge (0→1), no repeated events during hold (got: " + doubleTapCount + ")");

        // 测试 doubleTapRunDirection = -1 的情况
        sampler.reset();
        unit.doubleTapRunDirection = -1;
        unit.右行 = false;
        unit.左行 = true;  // 持续按住后方向

        doubleTapCount = 0;
        for (var j:Number = 0; j < 10; j++) {
            var events2:Array = sampler.sample(unit);
            if (this.arrayContains(events2, InputEvent.DOUBLE_TAP_BACK)) {
                doubleTapCount++;
                trace("  Frame " + (j + 1) + ": DOUBLE_TAP_BACK detected");
            }
        }

        // 帧1：doubleTapRunDirection 从 0→-1 边沿触发一次 DOUBLE_TAP_BACK
        // 帧2-10：保持为-1，非边沿，不再触发
        this.assert(doubleTapCount == 1,
            "Exactly 1 DOUBLE_TAP_BACK on edge (0→-1), no repeated events during hold (got: " + doubleTapCount + ")");

        // 验证正常双击仍然有效（即使 doubleTapRunDirection 有值）
        sampler.reset();
        unit.doubleTapRunDirection = 1;
        unit.左行 = false;
        unit.右行 = false;

        // 第一次按下
        unit.右行 = true;
        sampler.sample(unit);

        // 释放
        unit.右行 = false;
        sampler.sample(unit);

        // 短暂间隔
        sampler.sample(unit);

        // 第二次按下
        unit.右行 = true;
        var finalEvents:Array = sampler.sample(unit);
        this.assert(this.arrayContains(finalEvents, InputEvent.DOUBLE_TAP_FORWARD),
            "DoubleTap still works correctly with proper press-release-press sequence");

        trace("InputSampler DoubleTap Decoupled tests completed");
    }

    /**
     * 测试 C 键（换弹键）边沿检测
     * 验证：false→true 时产出 C_PRESS，长按和 true→false 帧不重复产出
     */
    private function testInputSamplerCKeyEdge():Void {
        trace("\n--- Test: InputSampler C Key Edge Detection ---");

        var sampler:InputSampler = new InputSampler();

        var unit:Object = {
            方向: "右",
            左行: false,
            右行: false,
            上行: false,
            下行: false,
            动作A: false,
            动作B: false,
            动作C: false
        };

        // 帧1：C 键未按下，不应产出 C_PRESS
        var events1:Array = sampler.sample(unit);
        this.assert(!this.arrayContains(events1, InputEvent.C_PRESS),
            "Frame 1: No C_PRESS when C key is not pressed");

        // 帧2：C 键按下（false→true 边沿），应产出 C_PRESS
        unit.动作C = true;
        var events2:Array = sampler.sample(unit);
        this.assert(this.arrayContains(events2, InputEvent.C_PRESS),
            "Frame 2: C_PRESS triggered on false→true edge");

        // 帧3：C 键继续按住（长按），不应再次产出 C_PRESS
        var events3:Array = sampler.sample(unit);
        this.assert(!this.arrayContains(events3, InputEvent.C_PRESS),
            "Frame 3: No C_PRESS while holding (first hold frame)");

        // 帧4：C 键继续按住
        var events4:Array = sampler.sample(unit);
        this.assert(!this.arrayContains(events4, InputEvent.C_PRESS),
            "Frame 4: No C_PRESS while still holding");

        // 帧5：C 键继续按住
        var events5:Array = sampler.sample(unit);
        this.assert(!this.arrayContains(events5, InputEvent.C_PRESS),
            "Frame 5: No C_PRESS on extended hold");

        // 帧6：C 键释放（true→false），不应产出 C_PRESS
        unit.动作C = false;
        var events6:Array = sampler.sample(unit);
        this.assert(!this.arrayContains(events6, InputEvent.C_PRESS),
            "Frame 6: No C_PRESS on release (true→false)");

        // 帧7：C 键仍未按下
        var events7:Array = sampler.sample(unit);
        this.assert(!this.arrayContains(events7, InputEvent.C_PRESS),
            "Frame 7: No C_PRESS when key remains released");

        // 帧8：C 键再次按下，应再次产出 C_PRESS
        unit.动作C = true;
        var events8:Array = sampler.sample(unit);
        this.assert(this.arrayContains(events8, InputEvent.C_PRESS),
            "Frame 8: C_PRESS triggered on second press");

        // 统计总共产出 C_PRESS 的次数（应该正好是 2 次）
        sampler.reset();
        unit.动作C = false;

        var cPressCount:Number = 0;
        var totalFrames:Number = 20;

        // 模拟：按下5帧 -> 释放5帧 -> 按下5帧 -> 释放5帧
        for (var i:Number = 0; i < totalFrames; i++) {
            if (i == 0) unit.动作C = true;      // 第1次按下
            if (i == 5) unit.动作C = false;     // 释放
            if (i == 10) unit.动作C = true;     // 第2次按下
            if (i == 15) unit.动作C = false;    // 释放

            var events:Array = sampler.sample(unit);
            if (this.arrayContains(events, InputEvent.C_PRESS)) {
                cPressCount++;
                trace("  C_PRESS detected at frame " + (i + 1));
            }
        }

        this.assert(cPressCount == 2,
            "Total C_PRESS count should be exactly 2 (got: " + cPressCount + ")");

        trace("InputSampler C Key Edge Detection tests completed");
    }

    /**
     * 辅助方法：检查数组是否包含指定元素
     */
    private function arrayContains(arr:Array, value:Number):Boolean {
        for (var i:Number = 0; i < arr.length; i++) {
            if (arr[i] == value) return true;
        }
        return false;
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

    // ========== CommandDFA 前缀冲突测试 ==========

    private function testCommandDFAPrefixConflict():Void {
        trace("\n--- Test: CommandDFA Prefix Conflict ---");

        // 创建一个专用的测试 DFA，包含前缀冲突的招式
        // 短招: [FORWARD, A_PRESS] → "短招" (priority: 5)
        // 长招: [FORWARD, A_PRESS, B_PRESS] → "长招" (priority: 10)
        var testDFA:CommandDFA = new CommandDFA(32);

        testDFA.registerCommand("短招", [InputEvent.FORWARD, InputEvent.A_PRESS], "短招", 5);
        testDFA.registerCommand("长招", [InputEvent.FORWARD, InputEvent.A_PRESS, InputEvent.B_PRESS], "长招", 10);
        testDFA.build();

        trace("  Prefix conflict DFA built with " + testDFA.getCommandCount() + " commands");

        // 测试场景1：只输入短招序列 → 应该识别短招
        var unit1:Object = {};
        testDFA.updateWithHistory(unit1, [InputEvent.FORWARD], 15);
        testDFA.updateWithHistory(unit1, [InputEvent.A_PRESS], 15);

        this.assert(unit1.commandId != CommandDFA.NO_COMMAND, "Short pattern recognized");
        var cmdName:String = testDFA.getCommandName(unit1.commandId);
        this.assert(cmdName == "短招", "Recognized 短招 when only short input (got: " + cmdName + ")");

        // 测试场景2：输入完整长招序列 → 应该识别长招（因为优先级更高且更长）
        var unit2:Object = {};
        testDFA.updateWithHistory(unit2, [InputEvent.FORWARD], 15);
        testDFA.updateWithHistory(unit2, [InputEvent.A_PRESS], 15);

        // 此时短招已匹配，记录 lastMatchEndPos
        var shortMatchEnd:Number = unit2.lastMatchEndPos;

        testDFA.updateWithHistory(unit2, [InputEvent.B_PRESS], 15);

        // 长招匹配应该更新 commandId（因为 endPos 更靠右）
        this.assert(unit2.commandId != CommandDFA.NO_COMMAND, "Long pattern recognized");
        cmdName = testDFA.getCommandName(unit2.commandId);
        this.assert(cmdName == "长招", "Recognized 长招 when full input (got: " + cmdName + ")");
        this.assert(unit2.lastMatchEndPos > shortMatchEnd, "Long pattern endPos > short pattern endPos");

        // 测试场景3：同一位置的优先级比较
        // 创建两个同长度但不同优先级的招式
        var priorityDFA:CommandDFA = new CommandDFA(32);
        priorityDFA.registerCommand("低优先级", [InputEvent.DOWN, InputEvent.A_PRESS], "低优先级", 1);
        priorityDFA.registerCommand("高优先级", [InputEvent.DOWN, InputEvent.A_PRESS], "高优先级", 100);
        priorityDFA.build();

        var unit3:Object = {};
        priorityDFA.updateWithHistory(unit3, [InputEvent.DOWN], 15);
        priorityDFA.updateWithHistory(unit3, [InputEvent.A_PRESS], 15);

        // 注意：实际上 TrieDFA 对重复模式的处理是后注册的覆盖先注册的
        // 这里主要测试 updateWithHistory 的选择逻辑正确性
        this.assert(unit3.commandId != CommandDFA.NO_COMMAND, "Duplicate pattern matched");
        trace("  Matched command: " + priorityDFA.getCommandName(unit3.commandId));

        trace("CommandDFA Prefix Conflict tests completed");
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

    // ========== CommandDFA 动态超时长招测试 ==========

    private function testCommandDFADynamicTimeoutLongPattern():Void {
        trace("\n--- Test: CommandDFA Dynamic Timeout Long Pattern ---");

        // 创建包含长招的测试 DFA
        // 长招: [DOWN, DOWN_FORWARD, FORWARD, A_PRESS] → 4步
        var longDFA:CommandDFA = new CommandDFA(32);
        longDFA.registerCommand("长招",
            [InputEvent.DOWN, InputEvent.DOWN_FORWARD, InputEvent.FORWARD, InputEvent.A_PRESS],
            "长招", 10);
        longDFA.build();

        var unit:Object = {};

        // 输入前3步
        longDFA.updateWithDynamicTimeout(unit, [InputEvent.DOWN]);
        var depth1:Number = longDFA.getTrieDFA().getDepth(unit.commandState);

        longDFA.updateWithDynamicTimeout(unit, [InputEvent.DOWN_FORWARD]);
        var depth2:Number = longDFA.getTrieDFA().getDepth(unit.commandState);

        longDFA.updateWithDynamicTimeout(unit, [InputEvent.FORWARD]);
        var depth3:Number = longDFA.getTrieDFA().getDepth(unit.commandState);

        trace("  Depth progression: " + depth1 + " -> " + depth2 + " -> " + depth3);

        // 深度3时，动态超时 = 3 + 3*2 = 9 帧
        // 模拟8帧无输入（应该还在容错范围内）
        for (var i:Number = 0; i < 8; i++) {
            longDFA.updateWithDynamicTimeout(unit, []);
        }
        this.assert(unit.commandState != CommandDFA.ROOT_STATE,
            "Long pattern state preserved with 8 empty frames at depth 3");

        // 再输入最后一步，应该能完成
        longDFA.updateWithDynamicTimeout(unit, [InputEvent.A_PRESS]);
        this.assert(unit.commandId != CommandDFA.NO_COMMAND,
            "Long pattern completed after long pause");

        var cmdName:String = longDFA.getCommandName(unit.commandId);
        this.assert(cmdName == "长招", "Recognized 长招 (got: " + cmdName + ")");

        // 测试超时边界
        var unit2:Object = {};
        longDFA.updateWithDynamicTimeout(unit2, [InputEvent.DOWN]);
        longDFA.updateWithDynamicTimeout(unit2, [InputEvent.DOWN_FORWARD]);
        longDFA.updateWithDynamicTimeout(unit2, [InputEvent.FORWARD]);

        // 模拟10帧无输入（超过深度3的容错 9 帧）
        for (var j:Number = 0; j < 10; j++) {
            longDFA.updateWithDynamicTimeout(unit2, []);
        }
        this.assert(unit2.commandState == CommandDFA.ROOT_STATE,
            "State reset after exceeding dynamic timeout for depth 3");

        trace("CommandDFA Dynamic Timeout Long Pattern tests completed");
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

    // ========== InputReplayAnalyzer 过滤测试 ==========

    private function testInputReplayAnalyzerFilters():Void {
        trace("\n--- Test: InputReplayAnalyzer Filters ---");

        var analyzer:InputReplayAnalyzer = new InputReplayAnalyzer(this.registry);

        // 创建包含多种招式的测试序列
        var testSequence:Array = [
            InputEvent.DOWN_FORWARD, InputEvent.A_PRESS,  // 波动拳 (priority 10, tags: 空手,远程,必杀)
            InputEvent.NONE,
            InputEvent.DOUBLE_TAP_FORWARD,                 // 诛杀步 (priority 5, tags: 空手,移动,基础)
            InputEvent.NONE,
            InputEvent.DOWN, InputEvent.B_PRESS            // 能量喷泉 (priority 7, tags: 空手,近战,消耗)
        ];

        // 测试 minPriority 过滤
        var highPriorityReport:Object = analyzer.analyze(testSequence, {minPriority: 8});
        trace("  High priority (>=8) matches: " + highPriorityReport.totalMatches);

        // 应该只有波动拳通过（priority 10）
        var foundOnlyHighPriority:Boolean = true;
        for (var i:Number = 0; i < highPriorityReport.commands.length; i++) {
            var cmd:Object = highPriorityReport.commands[i];
            if (cmd.priority < 8) {
                foundOnlyHighPriority = false;
                trace("  Unexpected low priority command: " + cmd.name + " (priority: " + cmd.priority + ")");
            }
        }
        this.assert(foundOnlyHighPriority, "minPriority filter works correctly");

        // 测试 filterTags 过滤
        var moveTagReport:Object = analyzer.analyze(testSequence, {filterTags: ["移动"]});
        trace("  '移动' tag matches: " + moveTagReport.totalMatches);

        var foundMoveTag:Boolean = false;
        for (var j:Number = 0; j < moveTagReport.commands.length; j++) {
            if (moveTagReport.commands[j].name == "诛杀步") {
                foundMoveTag = true;
            }
        }
        this.assert(foundMoveTag, "filterTags finds 诛杀步 with '移动' tag");

        // 测试 filterMask 过滤
        var moveMask:Number = this.registry.getGroupMask("移动类");
        trace("  移动类 mask: 0x" + moveMask.toString(16));

        var maskReport:Object = analyzer.analyze(testSequence, {filterMask: moveMask});
        trace("  filterMask matches: " + maskReport.totalMatches);

        // 应该只包含移动类的招式
        var allInMask:Boolean = true;
        for (var k:Number = 0; k < maskReport.commands.length; k++) {
            var cmdId:Number = maskReport.commands[k].cmdId;
            if (!this.registry.isCommandInMask(cmdId, moveMask)) {
                allInMask = false;
                trace("  Command not in mask: " + maskReport.commands[k].name);
            }
        }
        this.assert(allInMask, "filterMask works correctly");

        // 测试组合过滤
        var combinedReport:Object = analyzer.analyze(testSequence, {
            filterTags: ["空手"],
            minPriority: 6
        });
        trace("  Combined filter (空手 + priority>=6) matches: " + combinedReport.totalMatches);

        // 空手且优先级>=6 的应该是：波动拳(10), 燃烧指节(8), 能量喷泉(7)
        // 但测试序列中只有波动拳和能量喷泉
        this.assert(combinedReport.totalMatches >= 1, "Combined filter returns results");

        // 测试空结果
        var emptyReport:Object = analyzer.analyze(testSequence, {minPriority: 999});
        this.assert(emptyReport.totalMatches == 0, "No matches with impossible filter");

        trace("InputReplayAnalyzer Filters tests completed");
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
        this.assert(matchCount >= 1, "findMatchesInWindow found at least 1 match");

        // 构造特定历史序列，验证窗口匹配
        var testBuffer:InputHistoryBuffer = new InputHistoryBuffer(64, 30);
        testBuffer.appendFrame([InputEvent.DOWN_FORWARD]);
        testBuffer.appendFrame([InputEvent.A_PRESS]);

        var testMatchCount:Number = this.dfa.findMatchesInWindow(testBuffer, 10);
        this.assert(testMatchCount >= 1, "Window match found 波动拳 in constructed history");

        // 验证匹配结果内容
        var foundHadouken:Boolean = false;
        var dfaRef = this.dfa.getTrieDFA();
        for (var i:Number = 0; i < dfaRef.resultCount; i++) {
            var cmdId:Number = dfaRef.resultPatternIds[i];
            var cmdName:String = this.dfa.getCommandName(cmdId);
            if (cmdName == "波动拳") {
                foundHadouken = true;
            }
        }
        this.assert(foundHadouken, "Window match correctly identified 波动拳");

        // 测试 clearHistory
        sampler.clearHistory();
        var clearedInfo:Object = sampler.getHistoryInfo();
        this.assert(clearedInfo.eventCount == 0, "History cleared successfully");

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
