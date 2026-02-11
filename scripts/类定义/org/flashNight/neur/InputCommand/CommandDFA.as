import org.flashNight.neur.Automaton.TrieDFA;
import org.flashNight.neur.InputCommand.InputEvent;
import org.flashNight.neur.InputCommand.InputHistoryBuffer;

/**
 * CommandDFA - 搓招指令识别器
 *
 * 基于通用 TrieDFA 的领域特化封装，用于格斗游戏风格的输入序列识别。
 *
 * 职责分离：
 * - TrieDFA: 通用前缀树 DFA 数据结构（Automaton 层）
 * - CommandDFA: 搓招领域的特化逻辑（InputCommand 层）
 *   - 命令元数据管理（名称、动作、序列）
 *   - 角色状态更新（容错计时器、同帧多事件）
 *   - UI 提示接口
 *
 * 版本 2.1 新增：
 * - 基于历史缓冲区的窗口匹配模式 (updateWithHistory)
 * - 从后往前贪心解析，解决前缀冲突
 * - 动态超时支持
 * - 热路径内联优化 (updateFast)
 *
 * @author FlashNight
 * @version 2.1
 */
class org.flashNight.neur.InputCommand.CommandDFA {

    // ========== 常量 ==========

    /** 无效值 */
    public static var INVALID:Number = -1;

    /** 根状态 */
    public static var ROOT_STATE:Number = 0;

    /** 无命令 */
    public static var NO_COMMAND:Number = 0;
    
    /** 默认每步容错帧数 */
    public static var DEFAULT_TIMEOUT:Number = 5;

    /** 默认帧窗口大小（用于历史模式） */
    public static var DEFAULT_FRAME_WINDOW:Number = 15;

    /** 动态超时系数：timeout = BASE + depth * FACTOR */
    public static var TIMEOUT_BASE:Number = 3;
    public static var TIMEOUT_FACTOR:Number = 2;

    // ========== 内部 DFA 引擎 ==========

    /** 底层 TrieDFA 实例 */
    private var dfa:TrieDFA;

    // ========== 命令元数据 ==========

    /** 命令名称 commandName[cmdId] = "波动拳" */
    private var commandName:Array;

    /** 命令动作名 commandAction[cmdId] = "波动拳" (gotoAndPlay用) */
    private var commandAction:Array;

    /** 已注册的命令数量（与 dfa.getPatternCount() 同步） */
    private var commandCount:Number;

    // ========== 历史匹配工作缓冲区（复用避免GC）==========

    /** 匹配位置缓冲区 */
    private var matchPositions:Array;

    /** 匹配模式ID缓冲区 */
    private var matchPatternIds:Array;

    /** 缓冲区容量 */
    private var matchBufferCapacity:Number;

    // ========== 构造函数 ==========

    /**
     * 创建 CommandDFA 实例
     * @param initialCapacity 初始状态容量（默认64）
     */
    public function CommandDFA(initialCapacity:Number) {
        if (initialCapacity == undefined || initialCapacity < 32) {
            initialCapacity = 64;
        }

        // 创建底层 DFA，字母表大小为 InputEvent.COUNT
        this.dfa = new TrieDFA(InputEvent.COUNT, initialCapacity);

        this.commandName = [];
        this.commandAction = [];
        this.commandCount = 0;

        // 索引 0 保留为无命令
        this.commandName[0] = "";
        this.commandAction[0] = "";

        // 初始化匹配缓冲区
        this.matchBufferCapacity = 64;
        this.matchPositions = new Array(this.matchBufferCapacity);
        this.matchPatternIds = new Array(this.matchBufferCapacity);
    }

    // ========== 命令注册（构建阶段）==========

    /**
     * 注册一个搓招命令
     * @param name 命令显示名称（如"波动拳"）
     * @param sequence 输入事件序列（如 [DOWN, DOWN_FORWARD, FORWARD, A_PRESS]）
     * @param action 动作名（gotoAndPlay参数，默认同name）
     * @param priority 优先级（数字越大越优先，默认0）
     * @return 命令ID，失败返回 INVALID
     */
    public function registerCommand(name:String, sequence:Array, action:String, priority:Number):Number {
        if (this.dfa.isCompiled()) {
            trace("[CommandDFA] Error: Cannot register after build()");
            return INVALID;
        }

        if (sequence == undefined || sequence.length == 0) {
            trace("[CommandDFA] Error: Empty sequence for command: " + name);
            return INVALID;
        }

        // 委托给 TrieDFA 插入模式
        var cmdId:Number = this.dfa.insert(sequence, (priority != undefined) ? priority : 0);

        if (cmdId == TrieDFA.INVALID) {
            return INVALID;
        }

        // 存储命令元数据
        this.commandName[cmdId] = name;
        this.commandAction[cmdId] = (action != undefined) ? action : name;
        this.commandCount = cmdId;

        return cmdId;
    }

    /**
     * 构建 DFA（在所有命令注册完成后调用）
     */
    public function build():Void {
        this.dfa.compile();
        trace("[CommandDFA] Built with " + this.dfa.getPatternCount() + " commands, " +
              this.dfa.getStateCount() + " states");
    }

    // ========== 运行时查询（委托给 TrieDFA）==========

    /**
     * 状态转移
     * @param state 当前状态
     * @param event 输入事件
     * @return 下一状态，无转移返回 undefined
     */
    public function transition(state:Number, event:Number):Number {
        return this.dfa.transition(state, event);
    }

    /**
     * 获取接受状态的命令ID
     * @param state 状态ID
     * @return 命令ID，非接受状态返回 NO_COMMAND (0)
     */
    public function getAcceptedCommand(state:Number):Number {
        return this.dfa.getAccept(state);
    }

    /**
     * 获取状态的 UI 提示命令
     * @param state 状态
     * @return 提示的命令ID
     */
    public function getStateHintCommand(state:Number):Number {
        return this.dfa.getHint(state);
    }

    /**
     * 获取状态的已匹配长度（深度）
     * @param state 状态
     * @return 已匹配的步数
     */
    public function getStateMatchedLength(state:Number):Number {
        return this.dfa.getDepth(state);
    }

    // ========== 命令元数据查询 ==========

    /**
     * 获取命令名称
     */
    public function getCommandName(cmdId:Number):String {
        return this.commandName[cmdId];
    }

    /**
     * 获取命令动作名（gotoAndPlay 用）
     */
    public function getCommandAction(cmdId:Number):String {
        return this.commandAction[cmdId];
    }

    /**
     * 获取命令输入序列
     */
    public function getCommandSequence(cmdId:Number):Array {
        return this.dfa.getPattern(cmdId);
    }

    /**
     * 获取命令序列长度
     */
    public function getCommandLength(cmdId:Number):Number {
        return this.dfa.getPatternLength(cmdId);
    }

    /**
     * 获取命令优先级
     */
    public function getCommandPriority(cmdId:Number):Number {
        return this.dfa.getPriority(cmdId);
    }

    /**
     * 获取命令总数
     */
    public function getCommandCount():Number {
        return this.dfa.getPatternCount();
    }

    /**
     * 获取状态总数
     */
    public function getStateCount():Number {
        return this.dfa.getStateCount();
    }

    /**
     * 获取底层 TrieDFA 实例（高级用法）
     */
    public function getTrieDFA():TrieDFA {
        return this.dfa;
    }

    // ========== 角色状态更新（核心更新逻辑）==========

    /**
     * 更新角色的搓招状态机
     *
     * 角色对象需要包含以下字段：
     * - commandState:Number  当前 DFA 状态
     * - commandId:Number     本帧识别到的命令（完整）
     * - lastCommandId:Number 最近一次完整命令
     * - stepTimer:Number     当前步已经过的帧数
     *
     * @param unit 角色对象
     * @param evList 本帧输入事件列表（Array of InputEvent IDs）
     * @param timeout 容错帧数（可选，默认5）
     */
    public function update(unit:Object, evList:Array, timeout:Number):Void {
        if (timeout == undefined) {
            timeout = DEFAULT_TIMEOUT;
        }

        var state:Number = unit.commandState;
        var timer:Number = unit.stepTimer;

        // 确保初始化
        if (state == undefined) {
            state = ROOT_STATE;
            timer = 0;
        }

        // 重置本帧命令
        unit.commandId = NO_COMMAND;

        // 计时器递增
        timer++;

        // 处理本帧所有输入事件
        var evCount:Number = evList.length;
        for (var i:Number = 0; i < evCount; i++) {
            var ev:Number = evList[i];
            var nextState:Number = this.dfa.transition(state, ev);

            if (nextState != undefined) {
                state = nextState;
                timer = 0; // 成功跨步，重置计时器

                // 检查是否到达接受状态
                var cmd:Number = this.dfa.getAccept(state);
                if (cmd != NO_COMMAND) {
                    unit.commandId = cmd;
                    unit.lastCommandId = cmd;
                    // 可选：识别后是否重置状态
                    // state = ROOT_STATE;
                }
            }
        }

        // 超时检查
        if (timer > timeout) {
            state = ROOT_STATE;
            timer = 0;
        }

        // 回写状态
        unit.commandState = state;
        unit.stepTimer = timer;
    }

    /**
     * 重置角色的搓招状态
     * @param unit 角色对象
     */
    public function resetUnit(unit:Object):Void {
        unit.commandState = ROOT_STATE;
        unit.commandId = NO_COMMAND;
        unit.lastCommandId = NO_COMMAND;
        unit.stepTimer = 0;
    }

    // ========== 基于历史缓冲区的更新模式（v2.1 新增）==========

    /**
     * 【核心优化】基于历史缓冲区的搓招识别
     *
     * 相比 update()，此方法：
     * - 使用滑动窗口而非单状态追踪
     * - 从后往前贪心解析，自动解决前缀冲突
     * - 支持动态超时（基于招式深度）
     *
     * 角色对象需要包含以下字段：
     * - inputHistory:InputHistoryBuffer  输入历史缓冲（需预先创建）
     * - commandId:Number     本帧识别到的命令
     * - lastCommandId:Number 最近一次完整命令
     * - lastMatchEndPos:Number 上次匹配的结束位置（用于避免重复触发）
     *
     * @param unit 角色对象
     * @param frameEvents 本帧输入事件列表
     * @param frameWindow 帧窗口大小（可选，默认15帧）
     */
    public function updateWithHistory(unit:Object, frameEvents:Array, frameWindow:Number):Void {
        if (frameWindow == undefined) {
            frameWindow = DEFAULT_FRAME_WINDOW;
        }

        // 确保历史缓冲区已初始化
        var history:InputHistoryBuffer = unit.inputHistory;
        if (history == undefined) {
            history = new InputHistoryBuffer(
                this.dfa.getMaxPatternLength() * 3,
                frameWindow + 5
            );
            unit.inputHistory = history;
            unit.lastMatchEndPos = -1;
        }

        // 追加本帧事件到历史
        history.appendFrame(frameEvents);

        // 重置本帧命令
        unit.commandId = NO_COMMAND;

        // 获取事件序列和窗口范围
        var seq:Array = history.getSequence();
        var seqLen:Number = seq.length;

        if (seqLen == 0) {
            return;
        }

        // 计算窗口起始位置
        var windowStart:Number = history.getWindowStart(frameWindow);

        // 从后往前贪心解析：找到"结束位置最靠右"的匹配
        var bestCmd:Number = NO_COMMAND;
        var bestEndPos:Number = -1;
        var bestPriority:Number = -1;
        var bestStartPos:Number = -1;

        // 使用 matchAtRaw 从每个可能的起点匹配
        var positions:Array = this.matchPositions;
        var patternIds:Array = this.matchPatternIds;
        var dfaRef:TrieDFA = this.dfa;

        // 从后往前枚举起点
        for (var startPos:Number = seqLen - 1; startPos >= windowStart; startPos--) {
            var count:Number = dfaRef.matchAtRaw(seq, startPos, positions, patternIds, 0);

            // 遍历该起点的所有匹配
            for (var i:Number = 0; i < count; i++) {
                var cmdId:Number = patternIds[i];
                var cmdLen:Number = dfaRef.getPatternLength(cmdId);
                var endPos:Number = startPos + cmdLen;
                var priority:Number = dfaRef.getPriority(cmdId);

                // 选择策略：结束位置最靠右 → 同位置比优先级 → 同优先级比长度
                var isBetter:Boolean = false;

                if (endPos > bestEndPos) {
                    isBetter = true;
                } else if (endPos == bestEndPos) {
                    if (priority > bestPriority) {
                        isBetter = true;
                    } else if (priority == bestPriority && cmdLen > dfaRef.getPatternLength(bestCmd)) {
                        isBetter = true;
                    }
                }

                if (isBetter) {
                    bestCmd = cmdId;
                    bestEndPos = endPos;
                    bestPriority = priority;
                    bestStartPos = startPos;
                }
            }
        }

        // 检查是否是新的匹配（避免同一个匹配重复触发）
        if (bestCmd != NO_COMMAND && bestEndPos > unit.lastMatchEndPos) {
            unit.commandId = bestCmd;
            unit.lastCommandId = bestCmd;
            unit.lastMatchEndPos = bestEndPos;
        }
    }

    /**
     * 【热路径优化】内联版状态更新
     *
     * 将 TrieDFA 的 transition/getAccept 操作内联，
     * 消除函数调用开销，适用于每帧更新场景。
     *
     * @param unit 角色对象
     * @param evList 本帧输入事件列表
     * @param timeout 容错帧数（可选）
     */
    public function updateFast(unit:Object, evList:Array, timeout:Number):Void {
        // 缓存到局部变量，减少属性访问
        var trans:Array = this.dfa["transitions"];
        var acceptArr:Array = this.dfa["accept"];
        var alphaSize:Number = this.dfa["alphabetSize"];

        // 缓存常量
        var ROOT:Number = ROOT_STATE;
        var NO_CMD:Number = NO_COMMAND;

        if (timeout == undefined) timeout = DEFAULT_TIMEOUT;

        var state:Number = unit.commandState;
        var timer:Number = unit.stepTimer;

        if (state == undefined) { state = ROOT; timer = 0; }

        unit.commandId = NO_CMD;
        timer++;

        var evCount:Number = evList.length;
        for (var i:Number = 0; i < evCount; i++) {
            // 内联 transition()
            var nextState:Number = trans[state * alphaSize + evList[i]];
            if (nextState != undefined) {
                state = nextState;
                timer = 0;
                // 内联 getAccept()
                var cmd:Number = acceptArr[state];
                if (cmd != undefined && cmd != NO_CMD) {
                    unit.commandId = cmd;
                    unit.lastCommandId = cmd;
                }
            }
        }

        if (timer > timeout) { state = ROOT; timer = 0; }

        unit.commandState = state;
        unit.stepTimer = timer;
    }

    /**
     * 【动态超时版】状态更新
     *
     * 超时时间根据当前匹配深度动态调整：
     * - 输入越深，允许的停顿帧数越多
     * - timeout = TIMEOUT_BASE + depth * TIMEOUT_FACTOR
     *
     * @param unit 角色对象
     * @param evList 本帧输入事件列表
     */
    public function updateWithDynamicTimeout(unit:Object, evList:Array):Void {
        var state:Number = unit.commandState;
        var timer:Number = unit.stepTimer;

        if (state == undefined) {
            state = ROOT_STATE;
            timer = 0;
        }

        unit.commandId = NO_COMMAND;
        timer++;

        var evCount:Number = evList.length;
        for (var i:Number = 0; i < evCount; i++) {
            var ev:Number = evList[i];
            var nextState:Number = this.dfa.transition(state, ev);

            if (nextState != undefined) {
                state = nextState;
                timer = 0;

                var cmd:Number = this.dfa.getAccept(state);
                if (cmd != NO_COMMAND) {
                    unit.commandId = cmd;
                    unit.lastCommandId = cmd;
                }
            }
        }

        // 动态超时：根据当前深度计算
        var depth:Number = this.dfa.getDepth(state);
        var dynamicTimeout:Number = TIMEOUT_BASE + depth * TIMEOUT_FACTOR;

        if (timer > dynamicTimeout) {
            state = ROOT_STATE;
            timer = 0;
        }

        unit.commandState = state;
        unit.stepTimer = timer;
    }

    /**
     * 使用 findAllFastInRange 进行窗口匹配
     *
     * 适用于需要一次性检测窗口内所有可能匹配的场景。
     * 结果直接从 dfa.resultPositions/resultPatternIds 读取。
     *
     * @param history 输入历史缓冲区
     * @param frameWindow 帧窗口大小
     * @return 匹配数量
     */
    public function findMatchesInWindow(history:InputHistoryBuffer, frameWindow:Number):Number {
        var seq:Array = history.getSequence();
        var from:Number = history.getWindowStart(frameWindow);
        return this.dfa.findAllFastInRange(seq, from, seq.length);
    }

    /**
     * 获取当前状态可走的所有分支（用于 UI 提示/训练模式）
     *
     * @param state 当前状态
     * @return Array of {symbol:Number, name:String, nextState:Number, leadsToAccept:Boolean}
     */
    public function getAvailableMoves(state:Number):Array {
        var transitions:Array = this.dfa.getTransitionsFrom(state);
        var moves:Array = [];

        for (var i:Number = 0; i < transitions.length; i++) {
            var t:Object = transitions[i];
            var sym:Number = t.symbol;
            var nextState:Number = t.nextState;

            moves.push({
                symbol: sym,
                name: InputEvent.getName(sym),
                nextState: nextState,
                leadsToAccept: this.dfa.getAccept(nextState) != NO_COMMAND,
                hintCmd: this.dfa.getHint(nextState)
            });
        }

        return moves;
    }

    // ========== UI 提示接口 ==========

    /**
     * 获取出招提示信息（供 UI 层调用）
     *
     * @param unit 角色对象
     * @return Object {
     *   type: "completed"|"in_progress"|"idle"|"none",
     *   cmdId: Number,
     *   name: String,
     *   matched: Number,
     *   total: Number,
     *   nextEvents: Array
     * }
     */
    public function getHint(unit:Object):Object {
        var cmd:Number = unit.commandId;
        var state:Number = unit.commandState;

        // 本帧刚完成命令
        if (cmd != undefined && cmd != NO_COMMAND) {
            return {
                type: "completed",
                cmdId: cmd,
                name: this.commandName[cmd],
                matched: this.dfa.getPatternLength(cmd),
                total: this.dfa.getPatternLength(cmd),
                nextEvents: []
            };
        }

        // 正在搓招中
        if (state != undefined && state != ROOT_STATE) {
            var hintCmd:Number = this.dfa.getHint(state);
            var matchedLen:Number = this.dfa.getDepth(state);

            if (hintCmd != NO_COMMAND && matchedLen > 0) {
                var seq:Array = this.dfa.getPattern(hintCmd);
                var total:Number = this.dfa.getPatternLength(hintCmd);
                var nextEvents:Array = [];

                for (var i:Number = matchedLen; i < total; i++) {
                    nextEvents.push(seq[i]);
                }

                return {
                    type: "in_progress",
                    cmdId: hintCmd,
                    name: this.commandName[hintCmd],
                    matched: matchedLen,
                    total: total,
                    nextEvents: nextEvents
                };
            }
        }

        // 空闲状态，显示最近命令
        var lastCmd:Number = unit.lastCommandId;
        if (lastCmd != undefined && lastCmd != NO_COMMAND) {
            return {
                type: "idle",
                cmdId: lastCmd,
                name: this.commandName[lastCmd],
                matched: 0,
                total: this.dfa.getPatternLength(lastCmd),
                nextEvents: []
            };
        }

        // 无状态
        return {
            type: "none",
            cmdId: NO_COMMAND,
            name: "",
            matched: 0,
            total: 0,
            nextEvents: []
        };
    }

    // ========== 调试方法 ==========

    /**
     * 打印 DFA 结构信息（调试用）
     */
    public function dump():Void {
        trace("===== CommandDFA Dump =====");
        trace("Commands: " + this.dfa.getPatternCount());
        trace("States: " + this.dfa.getStateCount());

        var count:Number = this.dfa.getPatternCount();
        for (var cmdId:Number = 1; cmdId <= count; cmdId++) {
            trace("  [" + cmdId + "] " + this.commandName[cmdId] +
                  " = " + InputEvent.sequenceToString(this.dfa.getPattern(cmdId)) +
                  " -> " + this.commandAction[cmdId] +
                  " (priority: " + this.dfa.getPriority(cmdId) + ")");
        }
        trace("===========================");
    }
}
