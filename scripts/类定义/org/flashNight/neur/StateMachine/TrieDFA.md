# TrieDFA - 通用前缀树确定有限状态机

> **版本**: 1.1
> **作者**: FlashNight
> **测试状态**: 230/230 PASSED (100%)

---

## 目录

1. [概述](#概述)
2. [背景知识：为什么需要这个组件](#背景知识为什么需要这个组件)
3. [核心概念图解](#核心概念图解)
4. [技术选型：为什么选择 Trie + DFA](#技术选型为什么选择-trie--dfa)
5. [核心特性](#核心特性)
6. [数据结构](#数据结构)
7. [API 参考](#api-参考)
8. [使用示例](#使用示例)
9. [性能分析](#性能分析)
10. [设计决策](#设计决策)
11. [维护须知](#维护须知)
12. [测试报告](#测试报告)

---

## 概述

TrieDFA 是基于扁平数组实现的高性能确定有限状态机（DFA），专为 ActionScript 2 环境优化。

**一句话解释**：这是一个"序列识别器"，你告诉它要识别哪些输入序列（比如搓招指令），它就能在玩家输入时快速判断是否匹配。

### 应用场景

| 场景 | 说明 |
|------|------|
| **搓招识别** | 格斗游戏中识别玩家输入的招式序列 |
| **手势识别** | 识别触摸/鼠标轨迹形成的手势 |
| **关键词过滤** | 文本中的敏感词检测 |
| **协议解析** | 解析固定格式的命令序列 |

### 核心优势

```
┌─────────────────────────────────────────────────────────────┐
│  O(1) 状态转移  │  前缀共享  │  零 GC 压力  │  流式处理  │
└─────────────────────────────────────────────────────────────┘
```

---

## 背景知识：为什么需要这个组件

### 问题场景

假设你在做一个格斗游戏，玩家可以通过输入特定的方向键序列来释放招式：

```
波动拳: ↓ → ↘ + A键
升龙拳: → ↓ ↘ + A键
龙卷风: ↓ ← ↙ + B键
```

现在问题来了：**玩家每按一个键，你怎么知道他正在输入哪个招式？什么时候算完成？**

### 最朴素的方法（为什么不行）

```actionscript
// 方法1：直接比较数组
if (inputHistory == [DOWN, RIGHT, DOWN_RIGHT, A]) {
    释放波动拳();
}
```

**问题**：
- 每次输入都要和所有招式逐一比较 → **太慢**
- 招式越多越慢 → **不可扩展**
- 无法处理"正在输入中"的状态 → **无法做 UI 提示**

### 更好的思路

我们需要一个"记住当前进度"的结构：

```
玩家按下 ↓  → "你可能在输入波动拳或龙卷风，继续..."
玩家按下 →  → "更像波动拳了，继续..."
玩家按下 ↘  → "波动拳前摇完成，等待攻击键..."
玩家按下 A  → "波动拳确认！"
```

这就是**状态机**的思想：用"当前状态"记住进度，每次输入只需要做一次判断。

---

## 核心概念图解

### 什么是状态机（State Machine）

状态机就像一张"地图"，告诉你：**从当前位置出发，看到什么就往哪里走**。

```
┌─────────────────────────────────────────────────────────────────┐
│                        状态机类比                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   想象你在玩一个迷宫游戏：                                        │
│                                                                 │
│   - 你站在某个房间（当前状态）                                    │
│   - 房间有几扇门，每扇门上写着一个符号（可能的输入）                │
│   - 你看到一个符号，就走对应的门（状态转移）                       │
│   - 有些房间是"终点"（接受状态），到达就算完成                     │
│                                                                 │
│           ┌───┐                                                 │
│     ↓     │ 1 │                                                 │
│   ┌───┐ ──┤   │                                                 │
│   │ 0 │   └───┘                                                 │
│   │起点│     │ →                                                │
│   └───┘     ▼                                                   │
│           ┌───┐    ↘    ┌───┐    A    ╔═══╗                     │
│           │ 2 │ ───────→│ 3 │ ───────→║ 4 ║ ← 终点！            │
│           └───┘         └───┘         ╚═══╝   （波动拳）         │
│                                                                 │
│   状态0 --↓--> 状态1 --→--> 状态2 --↘--> 状态3 --A--> 状态4      │
│   （起点）                                          （波动拳！）  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**关键术语**：

| 术语 | 含义 | 例子 |
|------|------|------|
| **状态（State）** | 当前进度 | "已输入 ↓→" |
| **符号（Symbol）** | 一次输入 | 按下 ↘ 键 |
| **转移（Transition）** | 从一个状态到另一个状态 | 输入 ↘ 后进入下一状态 |
| **接受状态（Accept）** | 匹配完成的状态 | 波动拳输入完成！ |

### 什么是前缀树（Trie）

**Trie**（发音同 "try"）是一种专门用来存储"一堆序列"的结构，**共享相同的开头部分**。

```
┌─────────────────────────────────────────────────────────────────┐
│                     前缀树的核心思想                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   假设有三个招式：                                               │
│     波动拳: ↓ → A                                               │
│     升龙拳: ↓ → B                                               │
│     龙卷风: ↓ ← A                                               │
│                                                                 │
│   如果分开存储：                     如果用前缀树：               │
│   ┌──────────────┐                  ┌──────────────┐           │
│   │ ↓ → A        │                  │     ↓        │ ← 共享！   │
│   │ ↓ → B        │                  │    / \       │           │
│   │ ↓ ← A        │                  │   →   ←      │           │
│   └──────────────┘                  │  / \   \     │           │
│   存储 9 个节点                      │ A   B   A    │           │
│                                     └──────────────┘           │
│                                     存储 6 个节点               │
│                                                                 │
│   ✓ 省内存：相同前缀只存一份                                     │
│   ✓ 快查找：顺着树走就行，不用遍历所有招式                        │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 什么是 DFA

**DFA（Deterministic Finite Automaton，确定有限状态机）** 是状态机的一种：

- **确定**：每个状态对于每个输入，最多只有一条出路（不会有歧义）
- **有限**：状态数量是有限的

```
┌─────────────────────────────────────────────────────────────────┐
│                    DFA vs 普通状态机                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   普通状态机（NFA）：一个输入可能有多条路                         │
│                                                                 │
│        A                                                        │
│   ┌─────────→ 状态1                                             │
│   │                                                             │
│   状态0                         → 不确定走哪条，需要都试试        │
│   │                                                             │
│   └─────────→ 状态2                                             │
│        A                                                        │
│                                                                 │
│   ─────────────────────────────────────────────                 │
│                                                                 │
│   DFA：一个输入只有一条路                                        │
│                                                                 │
│        A                                                        │
│   状态0 ─────────→ 状态1        → 确定的，直接走，快！            │
│                                                                 │
│        B                                                        │
│   状态0 ─────────→ 状态2                                        │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**TrieDFA = Trie + DFA**：用前缀树的结构来构建确定有限状态机。

---

## 技术选型：为什么选择 Trie + DFA

### 备选方案对比

我们面对"识别多个输入序列"这个问题时，有多种技术方案：

| 方案 | 实现复杂度 | 查询时间 | 内存占用 | 流式支持 | 适用场景 |
|------|----------|---------|---------|---------|---------|
| **暴力遍历** | 低 | O(模式数 × 长度) | 低 | 差 | 模式很少（<5个） |
| **哈希表** | 低 | O(长度) | 中 | 差 | 只需精确匹配 |
| **正则表达式** | 中 | 不确定 | 高 | 差 | 复杂模式匹配 |
| **Trie 树** | 中 | O(长度) | 中 | 好 | 多模式前缀匹配 |
| **Trie + DFA** | 中 | O(长度) | 中 | **极好** | 流式输入识别 |
| **Aho-Corasick** | 高 | O(长度) | 高 | 好 | 文本多模式搜索 |

### 为什么 Trie + DFA 最适合搓招识别

#### 需求分析

搓招识别有几个特殊需求：

1. **流式输入**：玩家是一个键一个键按的，不是一次性输入完整序列
2. **实时响应**：每帧都可能有输入，必须快速判断
3. **中途提示**：想告诉玩家"你已经输入了波动拳的前两步"
4. **多招式共存**：可能有几十个招式，且很多共享前缀

#### 各方案的问题

```
┌─────────────────────────────────────────────────────────────────┐
│                     方案问题分析                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ❌ 暴力遍历                                                     │
│     每次输入都要检查所有招式的所有位置                            │
│     100个招式 × 每帧检查 = 卡顿                                  │
│                                                                 │
│  ❌ 哈希表                                                       │
│     只能判断"完整序列是否匹配"                                   │
│     无法知道"当前输入到哪一步了"                                 │
│     玩家输入 ↓→ 时，无法提示"继续按↘就是波动拳"                  │
│                                                                 │
│  ❌ 正则表达式                                                   │
│     AS2 的正则性能差                                            │
│     无法获取中间状态                                             │
│     每次都要从头匹配                                             │
│                                                                 │
│  ✓ Trie + DFA                                                   │
│     ✓ 记住当前进度（状态）                                       │
│     ✓ 每次输入只做一次查表                                       │
│     ✓ 天然支持中途提示（hint）                                   │
│     ✓ 共享前缀节省内存                                          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

#### 性能保证

```
传统方法：每次输入检查所有招式
  100个招式 × 平均5步 = 500次比较/帧

TrieDFA：每次输入只查一次表
  1次数组索引 = 1次比较/帧

差距：500倍！
```

### 为什么用扁平数组而不是嵌套对象

这是实现层面的优化选择：

```
┌─────────────────────────────────────────────────────────────────┐
│                   存储方式对比                                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  方式1：嵌套对象（传统 Trie 实现）                               │
│                                                                 │
│    state0 = {                                                   │
│      children: {                                                │
│        "↓": state1,                                             │
│        "→": state2                                              │
│      }                                                          │
│    }                                                            │
│                                                                 │
│    查找过程：state0.children["↓"]                                │
│    → 访问对象属性 → 哈希计算 → 查找 → 返回                        │
│    → 多次内存跳转，缓存不友好                                    │
│                                                                 │
│  ────────────────────────────────────────                       │
│                                                                 │
│  方式2：扁平数组（TrieDFA 实现）                                 │
│                                                                 │
│    transitions = [                                              │
│      /* state0, sym0 */ undefined,                              │
│      /* state0, sym1 */ 1,        // ↓ -> state1                │
│      /* state0, sym2 */ 2,        // → -> state2                │
│      /* state1, sym0 */ undefined,                              │
│      /* state1, sym1 */ ...                                     │
│    ]                                                            │
│                                                                 │
│    查找过程：transitions[state * alphabetSize + symbol]          │
│    → 一次乘法 + 一次加法 + 一次数组访问                           │
│    → 连续内存，缓存友好                                          │
│                                                                 │
│  性能差距：在 AS2 中约 3-5 倍                                    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 核心特性

### 1. 扁平化转移表

传统 Trie 使用嵌套对象存储子节点，每次转移需要哈希查找。TrieDFA 使用扁平数组：

```
transitions[state * alphabetSize + symbol] = nextState
```

**优势**：
- 单次数组索引 vs 哈希查找
- 缓存友好的连续内存布局
- 可预测的 O(1) 访问时间

### 2. 前缀共享

共享前缀的模式复用相同的状态节点：

```
模式: [0,1,2], [0,1,3], [0,1,2,4]

        ROOT
         │
         0
         │
         1 ─────────┐
        / \         │
       2   3        │
       │            │
       4            │

状态数: 6 (而非 10)
```

### 3. 零 GC 压力设计

`findAllFast` 系列方法使用预分配的并行数组存储结果：

```actionscript
// 预分配缓冲区
public var resultPositions:Array;   // 匹配位置
public var resultPatternIds:Array;  // 模式 ID
public var resultCount:Number;      // 有效结果数

// 使用方式（无对象创建）
dfa.findAllFast(sequence);
for (var i = 0; i < dfa.resultCount; i++) {
    var pos = dfa.resultPositions[i];
    var pid = dfa.resultPatternIds[i];
}
```

### 4. Hint 提示系统

在匹配过程中提供实时反馈，告诉玩家正在接近哪个招式：

```actionscript
var state = dfa.transition(state, input);
var hintId = dfa.getHint(state);  // 当前最可能完成的模式
var depth = dfa.getDepth(state);  // 已匹配的步数
```

**决策策略**：
1. 优先级高的模式优先
2. 同优先级下，更长的模式优先（引导玩家继续拓展）

---

## 数据结构

### 常量

| 常量 | 值 | 说明 |
|------|----|----|
| `INVALID` | -1 | 无效值（插入失败返回） |
| `ROOT` | 0 | 根状态索引 |
| `NO_MATCH` | 0 | 无匹配标识 |

### 内部数组

```
┌──────────────────────────────────────────────────────────────┐
│ transitions[state * alphabetSize + symbol] = nextState       │
│   └─ 扁平化转移表，undefined 表示无转移                        │
├──────────────────────────────────────────────────────────────┤
│ accept[state] = patternId                                    │
│   └─ 接受状态表，0 表示非接受状态                              │
├──────────────────────────────────────────────────────────────┤
│ depth[state] = Number                                        │
│   └─ 状态深度（从根到该状态的步数）                            │
├──────────────────────────────────────────────────────────────┤
│ hint[state] = patternId                                      │
│   └─ 状态提示（用于 UI 显示正在匹配哪个模式）                  │
├──────────────────────────────────────────────────────────────┤
│ priority[patternId] = Number                                 │
│   └─ 模式优先级（用于前缀冲突解决）                            │
├──────────────────────────────────────────────────────────────┤
│ patterns[patternId] = [symbol1, symbol2, ...]                │
│   └─ 模式原始序列                                             │
└──────────────────────────────────────────────────────────────┘
```

---

## API 参考

### 构造函数

```actionscript
public function TrieDFA(alphabetSize:Number, initialCapacity:Number)
```

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| alphabetSize | Number | 必需 | 字母表大小（符号种类数） |
| initialCapacity | Number | 64 | 初始状态容量 |

### 构建阶段

#### insert()

```actionscript
public function insert(pattern:Array, priorityValue:Number):Number
```

插入一个模式序列。采用"前置校验"策略，保证原子性（要么完全成功，要么不修改任何状态）。

**返回值**: 模式 ID，失败返回 `INVALID`

**错误情况**:
- 已编译后调用
- pattern 为 undefined
- pattern 为空数组
- 符号超出 [0, alphabetSize) 范围

#### compile()

```actionscript
public function compile():Void
```

编译 DFA。在所有模式插入完成后调用，之后不能再插入新模式。

### 运行时查询

#### transition()

```actionscript
public function transition(state:Number, symbol:Number):Number
```

核心状态转移方法。返回下一状态，无转移返回 `undefined`。

#### getAccept()

```actionscript
public function getAccept(state:Number):Number
```

获取接受状态的模式 ID。非接受状态返回 `NO_MATCH`。

#### getHint() / getDepth()

```actionscript
public function getHint(state:Number):Number
public function getDepth(state:Number):Number
```

获取状态的提示模式 ID 和深度。

### 便捷匹配方法

#### match()

```actionscript
public function match(sequence:Array):Number
```

匹配整个序列，返回模式 ID 或 `NO_MATCH`。

#### findAll()

```actionscript
public function findAll(sequence:Array):Array
```

查找序列中的所有匹配，返回对象数组 `[{position, patternId}, ...]`。

每次调用会创建新数组和对象，适合匹配次数较少或对 GC 不敏感的场景。

#### findAllFast()

```actionscript
public function findAllFast(sequence:Array):Number
```

零 GC 版本的全序列匹配。结果写入内部复用缓冲区：

| 属性 | 说明 |
|------|------|
| `resultPositions[i]` | 第 i 个匹配的起始位置 |
| `resultPatternIds[i]` | 第 i 个匹配的模式 ID |
| `resultCount` | 有效匹配数量 |

**返回值**: 匹配数量（等于 `resultCount`）

**重要**: 下次调用 `findAllFast` 或 `findAllFastInRange` 会覆盖缓冲区内容！如需保留结果，必须在下次调用前复制。

#### findAllFastInRange()

```actionscript
public function findAllFastInRange(sequence:Array, from:Number, to:Number):Number
```

在 `[from, to)` 范围内查找匹配，结果同样写入 `resultPositions` / `resultPatternIds` 缓冲区。

| 参数 | 说明 |
|------|------|
| sequence | 输入序列 |
| from | 起始位置（含），负数会被钳制为 0 |
| to | 结束位置（不含），超出长度会被钳制 |

**返回值**: 匹配数量

**重要**: 与 `findAllFast` 共享同一缓冲区，调用会相互覆盖。

### 底层原语

#### matchAtRaw()

```actionscript
public function matchAtRaw(
    sequence:Array,
    startIndex:Number,
    positions:Array,
    patternIds:Array,
    offset:Number
):Number
```

底层匹配原语，从指定位置尝试匹配所有可能的模式。供调用方实现自定义扫描策略（正序、倒序、跳跃等）。

**参数说明**:

| 参数 | 说明 |
|------|------|
| sequence | 输入序列 |
| startIndex | 从此位置开始尝试匹配 |
| positions | 调用方提供的位置数组，匹配结果写入此数组 |
| patternIds | 调用方提供的模式 ID 数组，匹配结果写入此数组 |
| offset | 从数组的第 offset 个位置开始写入（用于累积多次调用的结果） |

**返回值**: 本次调用写入的匹配条数

**写入逻辑**:
```actionscript
// 每找到一个匹配：
positions[offset + i] = startIndex;  // 匹配位置（都是 startIndex）
patternIds[offset + i] = patternId;  // 匹配到的模式 ID
// 返回 i（写入的条数）
```

**注意**: 同一个 `startIndex` 可能匹配多个模式（如 `[0,1]` 和 `[0,1,2]` 都是有效模式时）。

---

## 使用示例

### 基础用法

```actionscript
// 创建 DFA（字母表大小 10）
var dfa:TrieDFA = new TrieDFA(10);

// 插入模式
var hadouken:Number = dfa.insert([2, 3, 6, 0], 10);  // ↓↘→A
var shoryuken:Number = dfa.insert([6, 2, 3, 0], 15); // →↓↘A

// 编译
dfa.compile();

// 匹配
var result:Number = dfa.match([2, 3, 6, 0]);
if (result == hadouken) {
    trace("波动拳!");
}
```

### 流式输入（搓招状态机）

```actionscript
class ComboMatcher {
    private var dfa:TrieDFA;
    private var state:Number;
    private var timeout:Number = 0;

    public function onInput(symbol:Number):Void {
        // 检查超时
        if (getTimer() - timeout > 500) {
            state = TrieDFA.ROOT;
        }
        timeout = getTimer();

        // 状态转移
        var next:Number = dfa.transition(state, symbol);
        if (next == undefined) {
            state = TrieDFA.ROOT;
            return;
        }
        state = next;

        // 检查匹配
        var matched:Number = dfa.getAccept(state);
        if (matched != TrieDFA.NO_MATCH) {
            executeMove(matched);
            state = TrieDFA.ROOT;
        }

        // 显示提示
        var hint:Number = dfa.getHint(state);
        showHintUI(hint, dfa.getDepth(state));
    }
}
```

### 高性能批量匹配

```actionscript
// 使用 findAllFast 避免 GC
dfa.findAllFast(inputSequence);

// 直接访问结果缓冲区
for (var i:Number = 0; i < dfa.resultCount; i++) {
    var pos:Number = dfa.resultPositions[i];
    var pid:Number = dfa.resultPatternIds[i];
    processMatch(pos, pid);
}

// 注意：下次调用会覆盖结果！
// 如需保留，必须先复制
```

### 倒序匹配

```actionscript
// 使用 matchAtRaw 实现倒序扫描
var positions:Array = [];
var patternIds:Array = [];
var count:Number = 0;

for (var pos:Number = sequence.length - 1; pos >= 0; pos--) {
    count += dfa.matchAtRaw(sequence, pos, positions, patternIds, count);
}
```

---

## 性能分析

### 基准测试结果

| 操作 | 迭代次数 | 总时间 | 平均时间 | 吞吐量 |
|------|----------|--------|----------|--------|
| 5步转移 | 10,000 | 76ms | 0.0076ms | 131,579/s |
| 单次转移 | 100,000 | 366ms | 0.0037ms | 273,224/s |
| findAll (1000符号) | 100 | 321ms | 3.21ms | 312/s |
| findAllFast (1000符号) | 100 | 212ms | 2.12ms | 472/s |

### findAllFast vs findAll

```
findAll (对象创建):     405ms
findAllFast (并行数组): 280ms
加速比: 1.45x
```

### 可扩展性

| 模式数 | 插入时间 | 1000次匹配时间 |
|--------|----------|----------------|
| 10 | 0ms | 5ms |
| 50 | 1ms | 6ms |
| 100 | 3ms | 6ms |
| 500 | 9ms | 5ms |

**结论**: 匹配时间与模式数量基本无关（O(1) 转移的优势）。

---

## 设计决策

### 1. 为什么用扁平数组而非嵌套对象？

AS2 中对象属性访问涉及哈希查找，而数组索引是直接的内存偏移计算。对于高频调用的状态转移，这个差异很显著。

### 2. 为什么需要 compile() 阶段？

分离构建和运行阶段允许：
- 在构建阶段进行一次性优化
- 防止运行时意外修改 DFA 结构
- 未来可扩展（如添加失败链接实现 Aho-Corasick）

### 3. 重复模式的处理

相同模式可以插入多次，后者覆盖前者的接受状态。这是有意的设计：
- 允许运行时"更新"模式的优先级
- 简化实现（无需检测重复）

### 4. NO_MATCH 与 ROOT 同值

两者都是 0，但语义不同：
- `ROOT` 用于状态上下文
- `NO_MATCH` 用于匹配结果上下文

代码中应始终使用语义常量而非字面量 0。

---

## 维护须知

### 内联代码同步

`findAllFast()` 和 `findAllFastInRange()` 的内层循环是 `matchAtRaw()` 的内联副本，用于消除热路径上的函数调用开销。

**修改匹配逻辑时，必须同步更新以下三处**：

1. `matchAtRaw()` - 底层原语
2. `findAllFast()` - 全序列扫描
3. `findAllFastInRange()` - 范围扫描

内联核心逻辑：

```actionscript
state = ROOT_STATE;
limit = start + maxLen;
if (limit > len) limit = len;

for (i = start; i < limit; i++) {
    nextState = trans[state * alphaSize + sequence[i]];
    if (nextState == undefined) break;
    state = nextState;

    matched = acceptArr[state];
    if (matched != undefined && matched != NO_MATCH_VAL) {
        positions[idx] = start;
        patternIds[idx] = matched;
        idx++;
    }
}
```

### 结果缓冲区语义

`resultPositions` 和 `resultPatternIds` 是**复用缓冲区**：

```actionscript
// 正确用法
dfa.findAllFast(seq);
for (var i = 0; i < dfa.resultCount; i++) { ... }

// 错误用法（读到脏数据）
dfa.findAllFast(seq1);
dfa.findAllFast(seq2);  // seq1 的结果已被覆盖！
// 试图访问 seq1 的结果 -> 错误
```

---

## 测试报告

### 测试执行代码

```actionscript
import org.flashNight.neur.StateMachine.TrieDFATest;

var test:TrieDFATest = new TrieDFATest();
test.runTests();
```

### 测试结果摘要

```
=== TRIEDFA TEST FINAL REPORT ===
Tests Passed: 230
Tests Failed: 0
Success Rate: 100%
ALL TRIEDFA TESTS PASSED!

=== TRIEDFA VERIFICATION SUMMARY ===
* Basic DFA operations verified
* Insert validation (no half-insert) confirmed
* Hint priority/length strategy tested
* Prefix sharing optimization verified
* Edge cases and boundaries handled
* Convenience methods (match, findAll) tested
* Performance benchmarks established
* Auto-expansion mechanism verified
* Expand preserves accept/depth/hint arrays
```

### 详细测试日志

<details>
<summary>点击展开完整测试日志</summary>

```
=== TrieDFA Test Suite Initialized ===

=== Running Comprehensive TrieDFA Tests ===


--- Test: Basic Creation ---
[PASS] TrieDFA created successfully
[PASS] Alphabet size is 10 (got: 10)
[PASS] Initial state count is 1 (root) (got: 1)
[PASS] Initial pattern count is 0 (got: 0)
[PASS] Not compiled initially (got: false)

--- Test: Single Pattern Insert ---
[PASS] Insert returns valid ID
[PASS] First pattern ID is 1 (got: 1)
[PASS] Pattern count is 1 (got: 1)
[PASS] Pattern length is 3 (got: 3)
[PASS] Priority is 5 (got: 5)
[PASS] Retrieved pattern length is 3 (got: 3)
[PASS] Pattern[0] is 1 (got: 1)
[PASS] Pattern[1] is 2 (got: 2)
[PASS] Pattern[2] is 3 (got: 3)

--- Test: Multiple Pattern Insert ---
[PASS] First pattern ID is 1 (got: 1)
[PASS] Second pattern ID is 2 (got: 2)
[PASS] Third pattern ID is 3 (got: 3)
[PASS] Pattern count is 3 (got: 3)

--- Test: Prefix Sharing ---
[TrieDFA] Compiled: 3 patterns, 6 states, alphabet=5, maxPatternLen=4
[PASS] State count reflects prefix sharing (got: 6)
[PASS] Pattern count is 3 (got: 3)

--- Test: Transition ---
[TrieDFA] Compiled: 1 patterns, 4 states, alphabet=5, maxPatternLen=3
[PASS] Transition on symbol 0 exists
[PASS] Transition on symbol 1 exists
[PASS] Transition on symbol 2 exists
[PASS] No transition on symbol 3 from root (got: undefined)

--- Test: Accept States ---
[TrieDFA] Compiled: 2 patterns, 4 states, alphabet=5, maxPatternLen=3
[PASS] State after [0,1] accepts pattern 1 (got: 1)
[PASS] State after [0,1,2] accepts pattern 2 (got: 2)
[PASS] Intermediate state is not accept (got: 0)
[PASS] Root is not accept (got: 0)

--- Test: Insert Validation - After Compile ---
[TrieDFA] Compiled: 1 patterns, 3 states, alphabet=5, maxPatternLen=2
[TrieDFA] Error: Cannot insert after compile()
[PASS] Cannot insert after compile (got: -1)
[PASS] Pattern count unchanged (got: 1)

--- Test: Insert Validation - Undefined Pattern ---
[TrieDFA] Error: pattern is undefined
[PASS] Cannot insert undefined pattern (got: -1)
[PASS] Pattern count is 0 (got: 0)

--- Test: Insert Validation - Empty Pattern ---
[TrieDFA] Error: Empty pattern
[PASS] Cannot insert empty pattern (got: -1)
[PASS] Pattern count is 0 (got: 0)

--- Test: Insert Validation - Invalid Symbol ---
[TrieDFA] Error: Symbol -1 at index 0 out of range [0, 5)
[PASS] Cannot insert pattern with negative symbol (got: -1)
[TrieDFA] Error: Symbol 5 at index 1 out of range [0, 5)
[PASS] Cannot insert pattern with out-of-range symbol (got: -1)
[PASS] Pattern count remains 0 after invalid inserts (got: 0)
[PASS] State count remains 1 (only root) (got: 1)

--- Test: Insert Validation - No Half Insert ---
[PASS] First valid insert succeeds (got: 1)
[TrieDFA] Error: Symbol 99 at index 2 out of range [0, 5)
[PASS] Insert with invalid symbol fails (got: -1)
[PASS] State count unchanged after failed insert (got: 4)
[PASS] Pattern count unchanged after failed insert (got: 1)
[TrieDFA] Compiled: 1 patterns, 4 states, alphabet=5, maxPatternLen=3
[PASS] Original pattern still matches (got: 1)

--- Test: Hint Basic ---
[TrieDFA] Compiled: 1 patterns, 4 states, alphabet=5, maxPatternLen=3
[PASS] Hint at depth 1 points to pattern (got: 1)
[PASS] Hint at depth 2 points to pattern (got: 1)

--- Test: Hint Priority Comparison ---
[TrieDFA] Compiled: 2 patterns, 5 states, alphabet=5, maxPatternLen=3
[PASS] Hint prefers higher priority pattern (got: 2)
[PASS] Hint at shared node prefers higher priority (got: 2)

--- Test: Hint Length Comparison ---
[TrieDFA] Compiled: 2 patterns, 6 states, alphabet=5, maxPatternLen=5
[PASS] Hint prefers longer pattern at same priority (got: 2)
[PASS] Hint prefers longer pattern at depth 2 (got: 2)

--- Test: Hint Prefix Conflict ---
[TrieDFA] Compiled: 2 patterns, 5 states, alphabet=5, maxPatternLen=4
[PASS] Higher priority wins over length (got: 1)

--- Test: Depth Tracking ---
[TrieDFA] Compiled: 1 patterns, 5 states, alphabet=5, maxPatternLen=4
[PASS] Root depth is 0 (got: 0)
[PASS] Depth at state 1 is 1 (got: 1)
[PASS] Depth at state 2 is 2 (got: 2)
[PASS] Depth at state 3 is 3 (got: 3)
[PASS] Depth at state 4 is 4 (got: 4)

--- Test: Pattern Metadata ---
[TrieDFA] Compiled: 1 patterns, 6 states, alphabet=10, maxPatternLen=5
[PASS] Pattern length is 5 (got: 5)
[PASS] Priority is 42 (got: 42)
[PASS] Retrieved pattern has correct length (got: 5)
[PASS] Non-existent pattern length is 0 (got: 0)
[PASS] Non-existent pattern priority is 0 (got: 0)

--- Test: Max Pattern Length ---
[PASS] Max pattern length is 5 (got: 5)
[PASS] Max pattern length unchanged (got: 5)

--- Test: Empty DFA ---
[TrieDFA] Compiled: 0 patterns, 1 states, alphabet=5, maxPatternLen=0
[PASS] Empty DFA has 0 patterns (got: 0)
[PASS] Empty DFA has 1 state (root) (got: 1)
[PASS] Match on empty DFA returns NO_MATCH (got: 0)
[PASS] findAll on empty DFA returns empty array (got: 0)

--- Test: Single Symbol Pattern ---
[TrieDFA] Compiled: 1 patterns, 2 states, alphabet=5, maxPatternLen=1
[PASS] Single symbol pattern matches (got: 1)
[PASS] Longer sequence doesn't match exact (got: 0)
[PASS] Different symbol doesn't match (got: 0)

--- Test: Long Pattern ---
[TrieDFA] Expanding capacity to 128
[TrieDFA] Compiled: 1 patterns, 101 states, alphabet=3, maxPatternLen=100
[PASS] Long pattern inserted successfully
[PASS] Long pattern length is 100 (got: 100)
[PASS] Long pattern matches (got: 1)

--- Test: Many Patterns ---
[TrieDFA] Expanding capacity to 32
[TrieDFA] Compiled: 100 patterns, 31 states, alphabet=10, maxPatternLen=3
[PASS] All 100 patterns inserted (got: 100)
[PASS] Multiple states created

--- Test: Duplicate Patterns ---
[TrieDFA] Compiled: 2 patterns, 4 states, alphabet=5, maxPatternLen=3
[PASS] First duplicate insert succeeds
[PASS] Second duplicate insert succeeds
[PASS] Different IDs for duplicate patterns
[PASS] Both patterns counted (got: 2)
[PASS] Match returns last inserted pattern (got: 2)

--- Test: Alphabet Boundary ---
[PASS] Symbol 0 is valid
[PASS] Symbol 2 (max) is valid
[TrieDFA] Error: Symbol 3 at index 0 out of range [0, 3)
[PASS] Symbol 3 is invalid (out of range) (got: -1)

--- Test: Match ---
[TrieDFA] Compiled: 2 patterns, 6 states, alphabet=5, maxPatternLen=3
[PASS] Match [0,1,2] returns id1 (got: 1)
[PASS] Match [3,4] returns id2 (got: 2)

--- Test: Match Partial ---
[TrieDFA] Compiled: 1 patterns, 4 states, alphabet=5, maxPatternLen=3
[PASS] Partial match [0,1] returns NO_MATCH (got: 0)
[PASS] Partial match [0] returns NO_MATCH (got: 0)

--- Test: Match No Match ---
[TrieDFA] Compiled: 1 patterns, 4 states, alphabet=5, maxPatternLen=3
[PASS] Completely different sequence (got: 0)
[PASS] Wrong order (got: 0)
[PASS] Too long (got: 0)
[PASS] Empty sequence (got: 0)

--- Test: FindAll ---
[TrieDFA] Compiled: 2 patterns, 5 states, alphabet=5, maxPatternLen=2
[PASS] Found 2 matches (got: 2)
[PASS] First match at position 0 (got: 0)
[PASS] First match is pattern 1 (got: 1)
[PASS] Second match at position 2 (got: 2)
[PASS] Second match is pattern 2 (got: 2)

--- Test: FindAll Overlapping ---
[TrieDFA] Compiled: 2 patterns, 5 states, alphabet=5, maxPatternLen=2
[PASS] Found 2 overlapping matches (got: 2)
[PASS] First match at position 0 (got: 0)
[PASS] Second match at position 1 (got: 1)

--- Test: FindAll With MaxLen Optimization ---
[TrieDFA] Compiled: 3 patterns, 4 states, alphabet=5, maxPatternLen=3
[PASS] Max pattern length is 3 (got: 3)
[PASS] Found matches in long sequence

--- Test: FindAllFast Basic ---
[TrieDFA] Compiled: 1 patterns, 4 states, alphabet=5, maxPatternLen=3
[PASS] FindAllFast found 1 match (got: 1)
[PASS] resultCount is 1 (got: 1)
[PASS] Match position is 0 (got: 0)
[PASS] Matched pattern ID is 1 (got: 1)

--- Test: FindAllFast Multiple ---
[TrieDFA] Compiled: 2 patterns, 5 states, alphabet=5, maxPatternLen=2
[PASS] FindAllFast found 2 matches (got: 2)
[PASS] First match at position 0 (got: 0)
[PASS] First match is pattern 1 (got: 1)
[PASS] Second match at position 2 (got: 2)
[PASS] Second match is pattern 2 (got: 2)

--- Test: FindAllFast Consistency with FindAll ---
[TrieDFA] Compiled: 3 patterns, 6 states, alphabet=5, maxPatternLen=3
[PASS] Both methods find same count: 6 (got: 6)
[PASS] Both methods return identical results

--- Test: FindAllFast Reuse (No GC Pressure) ---
[TrieDFA] Compiled: 2 patterns, 5 states, alphabet=5, maxPatternLen=2
[PASS] First call: 2 matches (got: 2)
[PASS] Second call: 1 match (got: 1)
[PASS] resultCount updated to 1 (got: 1)
[PASS] Third call: 0 matches (got: 0)
[PASS] resultCount updated to 0 (got: 0)
[PASS] Buffer reuse works correctly

--- Test: MatchAtRaw Basic ---
[TrieDFA] Compiled: 1 patterns, 4 states, alphabet=5, maxPatternLen=3
[PASS] matchAtRaw found 1 match (got: 1)
[PASS] Match position is 0 (got: 0)
[PASS] Matched pattern ID is 1 (got: 1)

--- Test: MatchAtRaw Multiple Matches at Same Position ---
[TrieDFA] Compiled: 2 patterns, 4 states, alphabet=5, maxPatternLen=3
[PASS] matchAtRaw found 2 matches at same position (got: 2)
[PASS] First match is shorter pattern (got: 1)
[PASS] Second match is longer pattern (got: 2)

--- Test: MatchAtRaw Boundary Cases ---
[TrieDFA] Compiled: 1 patterns, 3 states, alphabet=5, maxPatternLen=2
[PASS] Negative startIndex returns 0 (got: 0)
[PASS] Out of range startIndex returns 0 (got: 0)
[PASS] startIndex == length returns 0 (got: 0)

--- Test: MatchAtRaw With Offset ---
[TrieDFA] Compiled: 2 patterns, 5 states, alphabet=5, maxPatternLen=2
[PASS] First matchAtRaw found 1 match (got: 1)
[PASS] Second matchAtRaw found 1 match (got: 1)
[PASS] Total matches is 2 (got: 2)
[PASS] First match at position 0 (got: 0)
[PASS] Second match at position 2 (got: 2)

--- Test: MatchAt Convenience Method ---
[TrieDFA] Compiled: 2 patterns, 4 states, alphabet=5, maxPatternLen=3
[PASS] matchAt returns 2 matches (got: 2)
[PASS] First result position is 0 (got: 0)
[PASS] Second result position is 0 (got: 0)

--- Test: FindAllFastInRange Basic ---
[TrieDFA] Compiled: 2 patterns, 5 states, alphabet=5, maxPatternLen=2
[PASS] Found 2 matches in range [0, 4) (got: 2)

--- Test: FindAllFastInRange Boundary Cases ---
[TrieDFA] Compiled: 1 patterns, 3 states, alphabet=5, maxPatternLen=2
[PASS] Negative from is clamped to 0 (got: 1)
[PASS] to > length is clamped to length (got: 2)
[PASS] from >= to returns 0 (got: 0)
[PASS] from > to returns 0 (got: 0)

--- Test: FindAllFastInRange Window Matching ---
[TrieDFA] Compiled: 2 patterns, 5 states, alphabet=5, maxPatternLen=2
[PASS] Window [4, 10) contains 2 matches (got: 2)
[PASS] First match at position 4 (got: 4)
[PASS] Second match at position 8 (got: 8)

--- Test: Reverse Order Matching (using matchAtRaw) ---
[TrieDFA] Compiled: 2 patterns, 5 states, alphabet=5, maxPatternLen=2
[PASS] Reverse scan found 2 matches (got: 2)
[PASS] First match (from right) at position 2 (got: 2)
[PASS] First match is pattern 2 (got: 2)
[PASS] Second match (from right) at position 0 (got: 0)
[PASS] Second match is pattern 1 (got: 1)

--- Test: Auto Expansion ---
[TrieDFA] Compiled: 20 patterns, 21 states, alphabet=5, maxPatternLen=20
[PASS] All 20 patterns inserted despite small initial capacity (got: 20)
[PASS] States expanded beyond initial capacity

--- Test: Expand Preserves Metadata (accept/depth/hint) ---
[PASS] Pattern 1 inserted after expansion
[PASS] Pattern 2 inserted after expansion
[PASS] Pattern 3 inserted after expansion
[TrieDFA] Compiled: 3 patterns, 16 states, alphabet=5, maxPatternLen=5
[PASS] Pattern1 transition at depth 1 exists
[PASS] Pattern1 depth at step 1 (got: 1)
[PASS] Pattern1 hint at depth 1 is valid
[PASS] Pattern1 transition at depth 2 exists
[PASS] Pattern1 depth at step 2 (got: 2)
[PASS] Pattern1 hint at depth 2 is valid
[PASS] Pattern1 transition at depth 3 exists
[PASS] Pattern1 depth at step 3 (got: 3)
[PASS] Pattern1 hint at depth 3 is valid
[PASS] Pattern1 transition at depth 4 exists
[PASS] Pattern1 depth at step 4 (got: 4)
[PASS] Pattern1 hint at depth 4 is valid
[PASS] Pattern1 transition at depth 5 exists
[PASS] Pattern1 depth at step 5 (got: 5)
[PASS] Pattern1 hint at depth 5 is valid
[PASS] Pattern1 accept state correct after expansion (got: 1)
[PASS] Pattern2 transition at depth 1 exists
[PASS] Pattern2 depth at step 1 (got: 1)
[PASS] Pattern2 transition at depth 2 exists
[PASS] Pattern2 depth at step 2 (got: 2)
[PASS] Pattern2 transition at depth 3 exists
[PASS] Pattern2 depth at step 3 (got: 3)
[PASS] Pattern2 transition at depth 4 exists
[PASS] Pattern2 depth at step 4 (got: 4)
[PASS] Pattern2 transition at depth 5 exists
[PASS] Pattern2 depth at step 5 (got: 5)
[PASS] Pattern2 accept state correct after expansion (got: 2)
[PASS] Pattern3 transition at depth 1 exists
[PASS] Pattern3 depth at step 1 (got: 1)
[PASS] Pattern3 transition at depth 2 exists
[PASS] Pattern3 depth at step 2 (got: 2)
[PASS] Pattern3 transition at depth 3 exists
[PASS] Pattern3 depth at step 3 (got: 3)
[PASS] Pattern3 transition at depth 4 exists
[PASS] Pattern3 depth at step 4 (got: 4)
[PASS] Pattern3 transition at depth 5 exists
[PASS] Pattern3 depth at step 5 (got: 5)
[PASS] Pattern3 accept state correct after expansion (got: 3)
[PASS] State count 16 exceeds initial capacity 4

--- Test: Dump ---
[TrieDFA] Compiled: 2 patterns, 6 states, alphabet=5, maxPatternLen=3
===== TrieDFA Dump =====
Alphabet size: 5
States: 6
Patterns: 2
Max pattern length: 3
Compiled: true
  [1] 0,1 (priority: 5, len: 2)
  [2] 2,3,4 (priority: 10, len: 3)
========================
[PASS] dump() executed without error

--- Test: GetTransitionsFrom ---
[TrieDFA] Compiled: 3 patterns, 5 states, alphabet=5, maxPatternLen=2
[PASS] Root has 1 transition (got: 1)
[PASS] Root transition is on symbol 0 (got: 0)
[PASS] State after 0 has 3 transitions (got: 3)

--- Test: Streaming Basic ---
[TrieDFA] Compiled: 1 patterns, 5 states, alphabet=5, maxPatternLen=4
[PASS] Frame 0: transition exists for symbol 3
[PASS] Frame 0: intermediate state is not accept (got: 0)
[PASS] Frame 1: transition exists for symbol 4
[PASS] Frame 1: intermediate state is not accept (got: 0)
[PASS] Frame 2: transition exists for symbol 1
[PASS] Frame 2: intermediate state is not accept (got: 0)
[PASS] Frame 3: transition exists for symbol 0
[PASS] Final state accepts the pattern (got: 1)

--- Test: Streaming Multiple Patterns ---
[TrieDFA] Compiled: 3 patterns, 8 states, alphabet=5, maxPatternLen=3
[PASS] Wave pattern recognized (got: 1)
[PASS] Dash pattern recognized (got: 2)
[PASS] Back pattern recognized (got: 3)

--- Test: Streaming Hint Progression ---
[TrieDFA] Compiled: 1 patterns, 6 states, alphabet=5, maxPatternLen=5
[PASS] Frame 0: hint points to correct pattern (got: 1)
[PASS] Frame 0: depth is 1 (got: 1)
[PASS] Frame 1: hint points to correct pattern (got: 1)
[PASS] Frame 1: depth is 2 (got: 2)
[PASS] Frame 2: hint points to correct pattern (got: 1)
[PASS] Frame 2: depth is 3 (got: 3)
[PASS] Frame 3: hint points to correct pattern (got: 1)
[PASS] Frame 3: depth is 4 (got: 4)
[PASS] Frame 4: hint points to correct pattern (got: 1)
[PASS] Frame 4: depth is 5 (got: 5)

--- Test: Streaming Timeout ---
[TrieDFA] Compiled: 1 patterns, 5 states, alphabet=5, maxPatternLen=4
[PASS] Progressed to depth 2 (got: 2)
[PASS] Reset to root (depth 0) (got: 0)
[PASS] Pattern recognized after reset (got: 1)

--- Test: Streaming Prefix Match ---
[TrieDFA] Compiled: 2 patterns, 5 states, alphabet=5, maxPatternLen=4
[PASS] Short pattern recognized at [3,0] (got: 1)
[PASS] Intermediate state after [3,0,1] (got: 0)
[PASS] Long pattern recognized at [3,0,1,0] (got: 2)

--- Test: Basic Performance ---
[TrieDFA] Compiled: 1 patterns, 6 states, alphabet=10, maxPatternLen=5
Basic Performance: 10000 traversals in 93ms
[PASS] Basic traversal performance acceptable

--- Test: Transition Performance ---
[TrieDFA] Expanding capacity to 128
[TrieDFA] Compiled: 100 patterns, 101 states, alphabet=100, maxPatternLen=1
Transition Performance: 100000 single transitions in 484ms
[PASS] Single transition performance acceptable

--- Test: Many Patterns Performance ---
[TrieDFA] Compiled: 1000 patterns, 61 states, alphabet=20, maxPatternLen=3
Insert 1000 patterns: 25ms
Compile: 0ms
[PASS] Insert 1000 patterns in acceptable time
[PASS] Compile in acceptable time

--- Test: FindAll Performance ---
[TrieDFA] Compiled: 50 patterns, 21 states, alphabet=10, maxPatternLen=2
FindAll Performance: 100 calls on 1000-symbol sequence in 416ms
[PASS] FindAll performance acceptable

--- Test: FindAllFast Performance ---
[TrieDFA] Compiled: 50 patterns, 21 states, alphabet=10, maxPatternLen=2
FindAllFast Performance: 100 calls on 1000-symbol sequence in 271ms
[PASS] FindAllFast performance acceptable

--- Test: FindAll vs FindAllFast Comparison ---
[TrieDFA] Compiled: 50 patterns, 31 states, alphabet=10, maxPatternLen=3
  FindAll (object creation): 494ms
  FindAllFast (parallel arrays): 358ms
  Speedup: 1.38x
[PASS] FindAllFast is faster or equal to FindAll

--- Test: Scalability ---
[TrieDFA] Compiled: 10 patterns, 31 states, alphabet=20, maxPatternLen=3
Scale 10: Insert 1ms, 1000 matches 5ms
[TrieDFA] Compiled: 50 patterns, 61 states, alphabet=20, maxPatternLen=3
Scale 50: Insert 1ms, 1000 matches 6ms
[TrieDFA] Compiled: 100 patterns, 61 states, alphabet=20, maxPatternLen=3
Scale 100: Insert 3ms, 1000 matches 6ms
[TrieDFA] Compiled: 500 patterns, 61 states, alphabet=20, maxPatternLen=3
Scale 500: Insert 14ms, 1000 matches 7ms
[PASS] Scalability is acceptable

=== TRIEDFA TEST FINAL REPORT ===
Tests Passed: 230
Tests Failed: 0
Success Rate: 100%
ALL TRIEDFA TESTS PASSED!

=== TRIEDFA VERIFICATION SUMMARY ===
* Basic DFA operations verified
* Insert validation (no half-insert) confirmed
* Hint priority/length strategy tested
* Prefix sharing optimization verified
* Edge cases and boundaries handled
* Convenience methods (match, findAll) tested
* Performance benchmarks established
* Auto-expansion mechanism verified
* Expand preserves accept/depth/hint arrays
=============================


=== TRIEDFA PERFORMANCE ANALYSIS ===
Context: Basic 5-step transition
  Iterations: 10000
  Total Time: 93ms
  Avg per Operation: 0.0093ms
  Operations per Second: 107527
---
Context: Single transition
  Iterations: 100000
  Total Time: 484ms
  Avg per Operation: 0.0048ms
  Operations per Second: 206612
---
Context: FindAll on 1000-symbol sequence
  Iterations: 100
  Total Time: 416ms
  Avg per Operation: 4.16ms
  Operations per Second: 240
---
Context: FindAllFast on 1000-symbol sequence
  Iterations: 100
  Total Time: 271ms
  Avg per Operation: 2.71ms
  Operations per Second: 369
---
Context: FindAll vs FindAllFast Comparison
  Iterations: 200
  Total Time: 494ms
  Avg per Operation: 2.47ms
  Operations per Second: 405
---
=============================



```

</details>

---

## 更新日志

| 版本 | 日期 | 变更 |
|------|------|------|
| 1.1 | - | 添加 `findAllFast`、`matchAtRaw`、`findAllFastInRange` 零 GC 方法 |
| 1.0 | - | 初始版本：基础 DFA 功能、hint 系统、前置校验 |
