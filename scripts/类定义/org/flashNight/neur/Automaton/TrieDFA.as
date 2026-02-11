/**
 * TrieDFA - 通用前缀树确定有限状态机 
 *
 * 基于扁平数组实现的高性能 DFA，可用于：
 * - 字符串模式匹配
 * - 输入序列识别（搓招、手势）
 * - 关键词过滤
 * - 协议解析
 *
 * 核心特性：
 * - 扁平化转移表：transitions[state * alphabetSize + symbol] = nextState
 * - O(1) 状态转移查询
 * - 支持多模式前缀树构建
 * - 前缀共享，内存高效
 * - 可扩展的接受状态数据
 *
 * 使用方式：
 *   var dfa:TrieDFA = new TrieDFA(26);  // 26个字母表符号
 *   var id1:Number = dfa.insert([0, 1, 2]);  // 插入模式
 *   var id2:Number = dfa.insert([0, 1, 3]);
 *   dfa.compile();  // 编译完成
 *
 *   var state:Number = TrieDFA.ROOT;
 *   state = dfa.transition(state, 0);  // 输入符号0
 *   state = dfa.transition(state, 1);  // 输入符号1
 *   var matched:Number = dfa.getAccept(state);  // 获取匹配的模式ID
 *
 * @author FlashNight
 * @version 1.1
 */
class org.flashNight.neur.Automaton.TrieDFA {

    // ========== 常量 ==========
    //
    // 注：热路径中应缓存到局部变量使用，避免静态属性访问开销
    // 示例：var ROOT_STATE:Number = ROOT;

    /** 无效值（插入失败时返回） */
    public static var INVALID:Number = -1;

    /** 根状态索引 */
    public static var ROOT:Number = 0;

    /** 无匹配标识（与 ROOT 同值但语义不同） */
    public static var NO_MATCH:Number = 0;

    // ========== 核心数据结构 ==========

    /** 字母表大小（符号种类数） */
    private var alphabetSize:Number;

    /** 当前分配的状态容量 */
    private var stateCapacity:Number;

    /** 实际使用的状态数 */
    private var stateCount:Number;

    /**
     * 扁平化转移表
     * transitions[state * alphabetSize + symbol] = nextState
     * undefined 表示无转移
     */
    private var transitions:Array;

    /**
     * 接受状态表
     * accept[state] = patternId (0 表示非接受状态)
     */
    private var accept:Array;

    /** 下一个可用的模式ID */
    private var nextPatternId:Number;

    /** 是否已编译 */
    private var compiled:Boolean;

    // ========== 可选扩展数据 ==========

    /**
     * 状态深度（从根到该状态的步数）
     * depth[state] = Number
     */
    private var depth:Array;

    /**
     * 状态提示：用于 UI 显示正在匹配哪个模式
     * hint[state] = patternId
     */
    private var hint:Array;

    /**
     * 模式优先级（用于前缀冲突解决）
     * priority[patternId] = Number
     */
    private var priority:Array;

    /**
     * 模式原始序列
     * patterns[patternId] = [symbol1, symbol2, ...]
     */
    private var patterns:Array;

    /**
     * 最大模式长度（用于 findAll 剪枝优化）
     */
    private var maxPatternLen:Number;

    // ========== findAllFast 结果缓冲区 ==========
    //
    // 【重要：复用+覆盖语义】
    // resultPositions 和 resultPatternIds 是预分配的复用缓冲区：
    // - 每次调用 findAllFast() 会从索引 0 开始覆盖写入新结果
    // - 只有 [0, resultCount) 范围内的数据是本次调用的有效结果
    // - 超出 resultCount 的旧数据可能残留，但不应被读取
    // - 如需保留结果供后续使用，必须在下次调用前复制出来
    //
    // 正确用法：
    //   dfa.findAllFast(seq);
    //   for (var i = 0; i < dfa.resultCount; i++) { ... }
    //
    // 错误用法（可能读到脏数据）：
    //   dfa.findAllFast(seq1);
    //   dfa.findAllFast(seq2);  // 此时 seq1 的结果已被覆盖！
    //   // 试图访问 seq1 的结果 -> 错误

    /**
     * 位置结果数组（性能版 findAllFast 使用）
     * resultPositions[i] = 第i个匹配的起始位置
     *
     * 注意：复用缓冲区，每次 findAllFast() 调用会覆盖
     * 只有 [0, resultCount) 是有效数据
     */
    public var resultPositions:Array;

    /**
     * 模式ID结果数组（性能版 findAllFast 使用）
     * resultPatternIds[i] = 第i个匹配的模式ID
     *
     * 注意：复用缓冲区，每次 findAllFast() 调用会覆盖
     * 只有 [0, resultCount) 是有效数据
     */
    public var resultPatternIds:Array;

    /**
     * 当前结果数量（性能版 findAllFast 使用）
     * 表示 resultPositions/resultPatternIds 中有效数据的个数
     */
    public var resultCount:Number;

    // ========== 构造函数 ==========

    /**
     * 创建 TrieDFA 实例
     * @param alphabetSize 字母表大小（符号种类数），必须 > 0
     * @param initialCapacity 初始状态容量（默认64）
     */
    public function TrieDFA(alphabetSize:Number, initialCapacity:Number) {
        if (alphabetSize == undefined || alphabetSize <= 0) {
            trace("[TrieDFA] Error: alphabetSize must be > 0");
            alphabetSize = 16;
        }
        if (initialCapacity == undefined || initialCapacity < 16) {
            initialCapacity = 64;
        }

        this.alphabetSize = alphabetSize;
        this.stateCapacity = initialCapacity;
        this.stateCount = 1;  // 根状态占用 0
        this.nextPatternId = 1;  // 0 保留为无匹配
        this.compiled = false;
        this.maxPatternLen = 0;

        // 分配数组
        this.transitions = new Array(initialCapacity * alphabetSize);
        this.accept = new Array(initialCapacity);
        this.depth = new Array(initialCapacity);
        this.hint = new Array(initialCapacity);
        this.priority = [];
        this.patterns = [];

        // 初始化根状态
        this.accept[ROOT] = NO_MATCH;
        this.depth[ROOT] = 0;
        this.hint[ROOT] = NO_MATCH;

        // 初始化 findAllFast 结果缓冲区（预分配合理大小）
        this.resultPositions = new Array(64);
        this.resultPatternIds = new Array(64);
        this.resultCount = 0;
    }

    // ========== 构建阶段 ==========

    /**
     * 插入一个模式序列
     *
     * 采用"前置校验"策略：先完整检查模式合法性，再分配资源。
     * 保证：要么完全成功插入，要么完全不修改任何状态（无半插入）。
     *
     * @param pattern 符号序列 [sym1, sym2, ...]，每个符号必须在 [0, alphabetSize) 范围内
     * @param priorityValue 优先级（可选，用于前缀冲突，越大越优先）
     * @return 模式ID，失败返回 INVALID
     */
    public function insert(pattern:Array, priorityValue:Number):Number {
        // === 阶段1：前置校验（不修改任何状态）===
        if (this.compiled) {
            trace("[TrieDFA] Error: Cannot insert after compile()");
            return INVALID;
        }

        if (pattern == undefined) {
            trace("[TrieDFA] Error: pattern is undefined");
            return INVALID;
        }

        var len:Number = pattern.length;
        if (len == 0) {
            trace("[TrieDFA] Error: Empty pattern");
            return INVALID;
        }

        // 完整检查所有符号是否合法
        var i:Number;
        for (i = 0; i < len; i++) {
            var sym:Number = pattern[i];
            if (sym < 0 || sym >= this.alphabetSize) {
                trace("[TrieDFA] Error: Symbol " + sym + " at index " + i +
                      " out of range [0, " + this.alphabetSize + ")");
                return INVALID;
            }
        }

        // === 阶段2：正式分配资源并插入 ===
        var patternId:Number = this.nextPatternId;
        this.nextPatternId++;

        // 存储模式信息
        this.patterns[patternId] = pattern.slice();  // 复制
        this.priority[patternId] = (priorityValue != undefined) ? priorityValue : 0;

        // 更新最大模式长度
        if (len > this.maxPatternLen) {
            this.maxPatternLen = len;
        }

        // 沿着 Trie 插入
        var state:Number = ROOT;

        for (i = 0; i < len; i++) {
            sym = pattern[i];
            var idx:Number = state * this.alphabetSize + sym;
            var nextState:Number = this.transitions[idx];

            if (nextState == undefined) {
                // 创建新状态
                nextState = this.allocateState();
                this.transitions[idx] = nextState;
                this.depth[nextState] = i + 1;
            }

            // 更新提示信息
            this.updateHint(nextState, patternId, i + 1);

            state = nextState;
        }

        // 标记接受状态
        this.accept[state] = patternId;

        return patternId;
    }

    /**
     * 分配新状态（内部方法）
     */
    private function allocateState():Number {
        var newState:Number = this.stateCount;
        this.stateCount++;

        // 检查容量
        if (newState >= this.stateCapacity) {
            this.expand();
        }

        // 初始化新状态
        this.accept[newState] = NO_MATCH;
        this.hint[newState] = NO_MATCH;

        return newState;
    }

    /**
     * 扩展容量（内部方法）
     */
    private function expand():Void {
        var oldCapacity:Number = this.stateCapacity;
        var newCapacity:Number = oldCapacity * 2;
        trace("[TrieDFA] Expanding capacity to " + newCapacity);

        // 扩展转移表
        var newTransitions:Array = new Array(newCapacity * this.alphabetSize);
        var oldLen:Number = oldCapacity * this.alphabetSize;
        for (var i:Number = 0; i < oldLen; i++) {
            newTransitions[i] = this.transitions[i];
        }
        this.transitions = newTransitions;

        // 扩展 accept/depth/hint 数组（与 transitions 保持一致）
        var newAccept:Array = new Array(newCapacity);
        var newDepth:Array = new Array(newCapacity);
        var newHint:Array = new Array(newCapacity);
        for (var j:Number = 0; j < oldCapacity; j++) {
            newAccept[j] = this.accept[j];
            newDepth[j] = this.depth[j];
            newHint[j] = this.hint[j];
        }
        this.accept = newAccept;
        this.depth = newDepth;
        this.hint = newHint;

        this.stateCapacity = newCapacity;
    }

    /**
     * 更新状态提示（内部方法）
     *
     * 决策策略：
     * 1. 优先级高的模式优先
     * 2. 同优先级下，更长的模式优先（引导玩家继续拓展）
     *
     * @param state 状态
     * @param patternId 当前模式ID
     * @param matchedLen 当前模式在此状态的匹配长度（用于同优先级比较）
     */
    private function updateHint(state:Number, patternId:Number, matchedLen:Number):Void {
        var hintArr:Array = this.hint;
        var currentHint:Number = hintArr[state];

        if (currentHint == undefined || currentHint == NO_MATCH) {
            hintArr[state] = patternId;
            return;
        }

        // 已有提示，比较优先级
        var priorityArr:Array = this.priority;
        var currentPriority:Number = priorityArr[currentHint];
        var newPriority:Number = priorityArr[patternId];
        // 默认优先级为 0（使用常量语义，但此处非热路径，直接用字面量更清晰）
        if (currentPriority == undefined) currentPriority = 0;
        if (newPriority == undefined) newPriority = 0;

        if (newPriority > currentPriority) {
            // 新模式优先级更高
            hintArr[state] = patternId;
        } else if (newPriority == currentPriority) {
            // 同优先级下，比较模式总长度（更长的优先，引导玩家继续拓展）
            // 直接访问数组长度，避免 getPatternLength() 函数调用
            var patternsArr:Array = this.patterns;
            var currentPattern:Array = patternsArr[currentHint];
            var newPattern:Array = patternsArr[patternId];
            var currentLen:Number = (currentPattern != undefined) ? currentPattern.length : 0;
            var newLen:Number = (newPattern != undefined) ? newPattern.length : 0;
            if (newLen > currentLen) {
                hintArr[state] = patternId;
            }
        }
    }

    /**
     * 编译 DFA（在所有模式插入完成后调用）
     * 可以在这里进行额外的优化（如失败链接等）
     */
    public function compile():Void {
        if (this.compiled) {
            trace("[TrieDFA] Warning: Already compiled");
            return;
        }

        this.compiled = true;
        trace("[TrieDFA] Compiled: " + (this.nextPatternId - 1) + " patterns, " +
              this.stateCount + " states, alphabet=" + this.alphabetSize +
              ", maxPatternLen=" + this.maxPatternLen);
    }

    // ========== 运行时查询 ==========

    /**
     * 状态转移（核心方法）
     * @param state 当前状态
     * @param symbol 输入符号
     * @return 下一状态，无转移返回 undefined
     */
    public function transition(state:Number, symbol:Number):Number {
        return this.transitions[state * this.alphabetSize + symbol];
    }

    /**
     * 获取接受状态的模式ID
     * @param state 状态
     * @return 模式ID，非接受状态返回 NO_MATCH (0)
     */
    public function getAccept(state:Number):Number {
        var result:Number = this.accept[state];
        return (result != undefined) ? result : NO_MATCH;
    }

    /**
     * 获取状态的提示模式ID
     * @param state 状态
     * @return 提示的模式ID
     */
    public function getHint(state:Number):Number {
        var result:Number = this.hint[state];
        return (result != undefined) ? result : NO_MATCH;
    }

    /**
     * 获取状态深度
     * @param state 状态
     * @return 深度（从根的步数），根状态返回 0
     */
    public function getDepth(state:Number):Number {
        var result:Number = this.depth[state];
        // 根状态深度为 0，与 ROOT 常量值一致
        return (result != undefined) ? result : ROOT;
    }

    /**
     * 获取模式原始序列
     * @param patternId 模式ID
     * @return 符号数组
     */
    public function getPattern(patternId:Number):Array {
        return this.patterns[patternId];
    }

    /**
     * 获取模式长度
     * @param patternId 模式ID
     * @return 长度
     */
    public function getPatternLength(patternId:Number):Number {
        var p:Array = this.patterns[patternId];
        return (p != undefined) ? p.length : 0;
    }

    /**
     * 获取模式优先级
     * @param patternId 模式ID
     * @return 优先级
     */
    public function getPriority(patternId:Number):Number {
        var p:Number = this.priority[patternId];
        return (p != undefined) ? p : 0;
    }

    // ========== 信息查询 ==========

    /**
     * 获取字母表大小
     */
    public function getAlphabetSize():Number {
        return this.alphabetSize;
    }

    /**
     * 获取状态数量
     */
    public function getStateCount():Number {
        return this.stateCount;
    }

    /**
     * 获取模式数量
     */
    public function getPatternCount():Number {
        return this.nextPatternId - 1;
    }

    /**
     * 获取最大模式长度
     */
    public function getMaxPatternLength():Number {
        return this.maxPatternLen;
    }

    /**
     * 是否已编译
     */
    public function isCompiled():Boolean {
        return this.compiled;
    }

    // ========== 便捷方法 ==========

    /**
     * 匹配整个序列
     * @param sequence 输入符号序列
     * @return 匹配的模式ID，不匹配返回 NO_MATCH
     */
    public function match(sequence:Array):Number {
        // 缓存到局部变量，减少属性访问开销
        var trans:Array = this.transitions;
        var alphaSize:Number = this.alphabetSize;
        var acceptArr:Array = this.accept;
        // 缓存常量到局部变量（热路径优化 + 避免裸字面量）
        var ROOT_STATE:Number = ROOT;      // = 0
        var NO_MATCH_VAL:Number = NO_MATCH; // = 0

        var state:Number = ROOT_STATE;
        var len:Number = sequence.length;
        var nextState:Number;

        for (var i:Number = 0; i < len; i++) {
            // 直接展开 transition()，避免函数调用
            nextState = trans[state * alphaSize + sequence[i]];
            if (nextState == undefined) {
                return NO_MATCH_VAL;
            }
            state = nextState;
        }

        // 直接展开 getAccept()
        var result:Number = acceptArr[state];
        return (result != undefined) ? result : NO_MATCH_VAL;
    }

    // ========== 底层匹配原语 ==========

    /**
     * 【底层原语】从指定起点尝试匹配，将结果写入调用方提供的并行数组
     *
     * 这是 DFA 匹配的核心"乐高积木"，供调用方实现各种扫描策略：
     * - 正序匹配、倒序匹配
     * - 窗口匹配 [from, to)
     * - 自定义短路退出策略
     *
     * 语义：对指定 startIndex，找出所有从该位置开始的匹配（不同长度）
     * 匹配按"从短到长"顺序写入（因为沿 DFA 路径逐步前进）
     *
     * @param sequence   输入符号序列
     * @param startIndex 匹配起始位置
     * @param positions  输出数组：匹配起点（调用方提供，可复用）
     * @param patternIds 输出数组：匹配的模式ID（调用方提供，可复用）
     * @param offset     从并行数组的哪个下标开始写入
     * @return           本次从该起点新增的匹配数量
     */
    public function matchAtRaw(
        sequence:Array,
        startIndex:Number,
        positions:Array,
        patternIds:Array,
        offset:Number
    ):Number {
        var len:Number = sequence.length;
        if (startIndex < 0 || startIndex >= len) {
            return 0;
        }

        // 缓存到局部变量，减少属性访问开销
        var trans:Array = this.transitions;
        var alphaSize:Number = this.alphabetSize;
        var acceptArr:Array = this.accept;
        var maxLen:Number = this.maxPatternLen;
        // 缓存常量（热路径优化 + 避免裸字面量）
        var ROOT_STATE:Number = ROOT;       // = 0
        var NO_MATCH_VAL:Number = NO_MATCH; // = 0

        var state:Number = ROOT_STATE;
        var limit:Number = startIndex + maxLen;
        if (limit > len) limit = len;

        var idx:Number = offset;
        var nextState:Number;
        var matched:Number;

        for (var i:Number = startIndex; i < limit; i++) {
            nextState = trans[state * alphaSize + sequence[i]];
            if (nextState == undefined) {
                break;
            }
            state = nextState;

            matched = acceptArr[state];
            if (matched != undefined && matched != NO_MATCH_VAL) {
                positions[idx] = startIndex;
                patternIds[idx] = matched;
                idx++;
            }
        }

        return idx - offset;
    }

    // ========== 基于 matchAtRaw 的高层方法 ==========
    //
    // 【维护须知 - 内联代码同步】
    //
    // findAllFast() 和 findAllFastInRange() 的内层循环是 matchAtRaw() 的内联副本。
    // 这是为了消除热路径上的函数调用开销（len=1000 时节省 1000 次调用，实测提升 3x）。
    //
    // ⚠️ 如果修改匹配逻辑，必须同步更新以下三处：
    //    1. matchAtRaw()           - 底层原语，供自定义扫描策略使用
    //    2. findAllFast()          - 全序列扫描的内联版本
    //    3. findAllFastInRange()   - 范围扫描的内联版本
    //
    // 内联核心逻辑（三处必须一致）：
    // ┌─────────────────────────────────────────────────────────────┐
    // │  state = ROOT_STATE;                                        │
    // │  limit = start + maxLen;                                    │
    // │  if (limit > len) limit = len;                              │
    // │                                                             │
    // │  for (i = start; i < limit; i++) {                          │
    // │      nextState = trans[state * alphaSize + sequence[i]];    │
    // │      if (nextState == undefined) break;                     │
    // │      state = nextState;                                     │
    // │                                                             │
    // │      matched = acceptArr[state];                            │
    // │      if (matched != undefined && matched != NO_MATCH_VAL) { │
    // │          positions[idx] = start;                            │
    // │          patternIds[idx] = matched;                         │
    // │          idx++;                                             │
    // │      }                                                      │
    // │  }                                                          │
    // └─────────────────────────────────────────────────────────────┘

    /**
     * 【性能版】查找序列中的所有匹配（多模式匹配）
     *
     * 零 GC 开销版本：使用预分配的并行数组存储结果，避免对象创建。
     * 结果存储在 resultPositions、resultPatternIds、resultCount 中。
     *
     * 【热路径全内联】
     * 将 matchAtRaw 逻辑完全展开，消除每个起点的函数调用开销。
     * 对于 len=1000 的序列，节省 1000 次函数调用，实测提升约 3 倍。
     *
     * 【重要：复用+覆盖语义】
     * - 每次调用会从索引 0 开始覆盖写入，之前的结果会丢失
     * - 只有 [0, resultCount) 范围内是有效数据
     * - 如需保留结果，必须在下次调用前复制
     *
     * 时间复杂度：O(L * maxPatternLen)，其中 L 为序列长度
     *
     * 使用方式：
     *   dfa.findAllFast(sequence);
     *   for (var i = 0; i < dfa.resultCount; i++) {
     *       var pos = dfa.resultPositions[i];
     *       var pid = dfa.resultPatternIds[i];
     *   }
     *
     * @param sequence 输入符号序列
     * @return 匹配数量（同时存储在 resultCount 中）
     *
     * @see matchAtRaw 底层原语（本方法为其内联版本）
     * @see findAllFastInRange 范围版本（内层逻辑相同，修改时需同步）
     */
    public function findAllFast(sequence:Array):Number {
        // === 热路径优化：所有变量缓存到局部，避免 this 属性访问 ===
        var positions:Array = this.resultPositions;
        var patternIds:Array = this.resultPatternIds;
        var trans:Array = this.transitions;
        var acceptArr:Array = this.accept;
        var alphaSize:Number = this.alphabetSize;
        var maxLen:Number = this.maxPatternLen;
        var len:Number = sequence.length;

        // 缓存静态常量到局部变量（避免静态属性访问开销）
        var ROOT_STATE:Number = ROOT;       // = 0
        var NO_MATCH_VAL:Number = NO_MATCH; // = 0

        // 预声明循环变量（避免循环内重复分配）
        var count:Number = 0;
        var state:Number;
        var nextState:Number;
        var matched:Number;
        var limit:Number;
        var i:Number;

        // === 主循环：遍历每个可能的起始位置 ===
        for (var start:Number = 0; start < len; start++) {
            // ┌─── 内联 matchAtRaw 核心逻辑（修改时需同步三处）───┐
            state = ROOT_STATE;
            limit = start + maxLen;
            if (limit > len) limit = len;

            for (i = start; i < limit; i++) {
                nextState = trans[state * alphaSize + sequence[i]];
                if (nextState == undefined) {
                    break;  // 无转移，提前退出当前起点
                }
                state = nextState;

                matched = acceptArr[state];
                if (matched != undefined && matched != NO_MATCH_VAL) {
                    positions[count] = start;
                    patternIds[count] = matched;
                    count++;
                }
            }
            // └─── 内联结束 ───┘
        }

        this.resultCount = count;
        return count;
    }

    /**
     * 【性能版】在指定范围内查找所有匹配
     *
     * 只扫描 [from, to) 范围内的起始位置，适用于：
     * - 窗口匹配：只关心最近 N 个输入
     * - 避免 slice 数组的 GC 开销
     *
     * 【热路径全内联】同 findAllFast，消除函数调用开销。
     *
     * @param sequence 输入符号序列
     * @param from     起始位置（包含）
     * @param to       结束位置（不包含）
     * @return 匹配数量（同时存储在 resultCount 中）
     *
     * @see matchAtRaw 底层原语（本方法为其内联版本）
     * @see findAllFast 全序列版本（内层逻辑相同，修改时需同步）
     */
    public function findAllFastInRange(sequence:Array, from:Number, to:Number):Number {
        var len:Number = sequence.length;

        // 边界修正（快速路径：无效范围直接返回）
        if (from < 0) from = 0;
        if (to > len) to = len;
        if (from >= to) {
            this.resultCount = 0;
            return 0;
        }

        // === 热路径优化：所有变量缓存到局部 ===
        var positions:Array = this.resultPositions;
        var patternIds:Array = this.resultPatternIds;
        var trans:Array = this.transitions;
        var acceptArr:Array = this.accept;
        var alphaSize:Number = this.alphabetSize;
        var maxLen:Number = this.maxPatternLen;

        // 缓存静态常量
        var ROOT_STATE:Number = ROOT;       // = 0
        var NO_MATCH_VAL:Number = NO_MATCH; // = 0

        // 预声明循环变量
        var count:Number = 0;
        var state:Number;
        var nextState:Number;
        var matched:Number;
        var limit:Number;
        var i:Number;

        // === 主循环：仅遍历 [from, to) 范围 ===
        for (var start:Number = from; start < to; start++) {
            // ┌─── 内联 matchAtRaw 核心逻辑（修改时需同步三处）───┐
            state = ROOT_STATE;
            limit = start + maxLen;
            if (limit > len) limit = len;

            for (i = start; i < limit; i++) {
                nextState = trans[state * alphaSize + sequence[i]];
                if (nextState == undefined) {
                    break;
                }
                state = nextState;

                matched = acceptArr[state];
                if (matched != undefined && matched != NO_MATCH_VAL) {
                    positions[count] = start;
                    patternIds[count] = matched;
                    count++;
                }
            }
            // └─── 内联结束 ───┘
        }

        this.resultCount = count;
        return count;
    }

    /**
     * 【便捷版】从指定起点尝试匹配，返回对象数组
     *
     * 主要用于非热路径 / 调试场景。
     * 内部调用 matchAtRaw，有 GC 开销。
     *
     * @param sequence   输入符号序列
     * @param startIndex 匹配起始位置
     * @return Array of {position:Number, patternId:Number}
     */
    public function matchAt(sequence:Array, startIndex:Number):Array {
        var positions:Array = [];
        var patternIds:Array = [];
        var count:Number = this.matchAtRaw(sequence, startIndex, positions, patternIds, 0);

        var results:Array = new Array(count);
        for (var i:Number = 0; i < count; i++) {
            results[i] = {position: positions[i], patternId: patternIds[i]};
        }
        return results;
    }

    /**
     * 【兼容版】查找序列中的所有匹配（多模式匹配）
     *
     * 返回对象数组，便于使用但有 GC 开销。
     * 内部调用 findAllFast 后包装结果。
     *
     * @param sequence 输入符号序列
     * @return Array of {position:Number, patternId:Number}
     */
    public function findAll(sequence:Array):Array {
        // 调用性能版
        var count:Number = this.findAllFast(sequence);

        // 包装为对象数组
        var results:Array = new Array(count);
        var positions:Array = this.resultPositions;
        var patternIds:Array = this.resultPatternIds;

        for (var i:Number = 0; i < count; i++) {
            results[i] = {position: positions[i], patternId: patternIds[i]};
        }

        return results;
    }

    // ========== 调试方法 ==========

    /**
     * 打印 DFA 结构信息
     */
    public function dump():Void {
        trace("===== TrieDFA Dump =====");
        trace("Alphabet size: " + this.alphabetSize);
        trace("States: " + this.stateCount);
        trace("Patterns: " + (this.nextPatternId - 1));
        trace("Max pattern length: " + this.maxPatternLen);
        trace("Compiled: " + this.compiled);

        for (var pid:Number = 1; pid < this.nextPatternId; pid++) {
            var p:Array = this.patterns[pid];
            trace("  [" + pid + "] " + p.join(",") + " (priority: " + this.priority[pid] + ", len: " + p.length + ")");
        }
        trace("========================");
    }

    /**
     * 获取状态的所有有效转移
     * @param state 状态
     * @return Array of {symbol:Number, nextState:Number}
     */
    public function getTransitionsFrom(state:Number):Array {
        var result:Array = [];
        var base:Number = state * this.alphabetSize;

        for (var sym:Number = 0; sym < this.alphabetSize; sym++) {
            var next:Number = this.transitions[base + sym];
            if (next != undefined) {
                result.push({symbol: sym, nextState: next});
            }
        }

        return result;
    }
}
