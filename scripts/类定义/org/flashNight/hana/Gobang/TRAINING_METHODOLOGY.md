# Gobang AI 自动化调优方法论

## 概述

本文档描述了一套基于 Rapfi 引擎的自动化战术评测与调参闭环，用于在 AVM1 算力约束下持续提升五子棋 AI 的棋力。

## 架构

```
Flash (GobangTrainer) ←XMLSocket→ Node.js (gomokuTask) ←stdin/stdout→ Rapfi CLI
        ↓                                                                ↓
   本地 AI 作答                                                   Rapfi 参考答案
        ↓                                                                ↓
        └────────────── 对比 → 分类报告 → 定位弱点 ──────────────────────┘
```

## 调优循环（每轮 ~30 分钟）

### Step 1: 建立基线（5 分钟）

```
编译 → Trainer.run() → 读取 SUMMARY REPORT
```

记录各分类命中率：
```
must_block: 5/5 (100%)
defense:    8/8 (100%)
double_three: 2/2 (100%)
vcf:        2/2 (100%)
mid_game:   0/2 (0%)     ← 弱点
tactical:   1/1 (100%)
```

### Step 2: 定位弱点（5 分钟）

查看每个 FAIL 的 trace 详情：
```
[Trainer] [FAIL] mid_complex_diagonal | Local:(6,10) P3_myFour | Rapfi:(10,6)
```

分析 AI 的 phaseLabel：
- `P1_myFive` / `P2_blockFive` → 正确的紧急响应
- `P3_myFour` → 走了己方冲四，但可能不是全局最优
- `P4a_blockFour` / `P4combo` → 正确的防守
- `minmax_dN` → 搜索结果，深度 N
- `no_move` → role 不匹配或局面设置错误

**关键指标**：
- 如果 AI 和 Rapfi 答案一致但都不在 expectedMoves 中 → **题目需要更新**
- 如果 AI 的 phaseLabel 是 pre-search 截断而 Rapfi 走了不同的点 → **pre-search 优先级可能过强**
- 如果 AI 走 `minmax_dN` 但答案错误 → **评估函数或搜索深度不足**

### Step 3: 调参/改代码（15 分钟）

按弱点类型选择策略：

**A. 评估函数调参**（GobangEval.as `_initScoreLUT`）
```
场景：AI 低估了某种棋型的价值
方法：调整 _scoreLUT 中的权重
例：THREE 从 200 调到 250 → AI 更重视活三
验证：重跑 Trainer，检查 defense 分类命中率变化
```

**B. 搜索参数调参**（GobangConfig / GobangAI.as DIFFICULTY_TABLE）
```
场景：搜索深度不够导致看不到威胁
方法：调整 pointsLimit（候选数）或 searchDepth
例：depth=4 时 pointsLimit 从 14 提到 16
权衡：更多候选 = 更慢搜索 = 可能超帧预算
```

**C. pre-search 逻辑修改**（GobangMinmax.as `_preSearchTactical`）
```
场景：P3_myFour 优先级过高导致错过防守
方法：在 P3 之前增加对手威胁检查
例：如果对手同时有 combo 威胁，先防守再进攻
风险：改变基础优先级可能导致大面积回归
```

**D. bridge / posWeight 调参**（GobangEval.as 常量）
```
场景：开局/中局位置评估不准
方法：调整 BRIDGE_LINK_BONUS / BRIDGE_SPAN_BONUS / _posWeight
例：增大 posWeight 中心偏好 → 开局更倾向占中
```

### Step 4: 回归验证（5 分钟）

```
清 ASO → 编译 → Trainer.run() → 对比新旧报告
```

**判定标准**：
- 总命中率提升 ≥ 5% → 接受
- 总命中率不变但目标分类提升 → 条件接受（检查其他分类是否回归）
- 任何分类回归 ≥ 2 题 → 拒绝，回滚

## 题库扩展策略

### 来源 1: 对局提取
```
1. 用 GobangGame 下一盘（difficulty=100）
2. 查看 AI Decision Log 中的 FAIL 或 drop
3. 提取该局面到 Trainer 题库
4. 用 Rapfi 确认正确答案
```

### 来源 2: Rapfi 自动生成
```
1. Node.js 端让 Rapfi 自对弈
2. 在评分骤变的位置（如 +500 → -500）切出局面
3. 这些是"转折点"，适合作为战术题
```

### 来源 3: 外部题库
```
1. Tokai 6x6 VCF 题（286 题）→ 嵌入 15x15 棋盘
2. Gomocup 开局库 → 测试开局选择
3. 手工构造边界 case（角落、边缘、跳连等）
```

### 题目质量控制
- 所有题目的 moves.length >= 10（跳过开局库）
- expectedMoves 必须由 Rapfi 验证（不能只凭人工判断）
- 每个分类至少 5 题（当前最少的 mid_game 只有 2 题，需扩展）
- 定期清理：如果 Rapfi 和 AI 都不选某个 expectedMove → 该答案可能过时

## 关键文件

| 文件 | 用途 |
|------|------|
| `GobangTrainer.as` | 题库 + 评测框架 |
| `gomokuTask.js` | Rapfi 桥接 |
| `GobangEval.as` `_initScoreLUT` | 评估权重 |
| `GobangMinmax.as` `_preSearchTactical` | 战术剪枝优先级 |
| `GobangAI.as` `DIFFICULTY_TABLE` | 难度-搜索参数映射 |
| `GobangAI.as` `_applyDifficultyDrop` | 难度降级保护 |

## Agent 自动化调优工作流

Agent 可以全自动执行以下循环：

```
1. 修改评估权重/搜索参数
2. 清 ASO: find $LOCALAPPDATA/Adobe/Flash\ CS6 -name "*.aso" -path "*/Gobang/*" -delete
3. 触发编译: Start-ScheduledTask CompileTriggerTask
4. 等待 publish_done.marker (~30-40s)
5. 等 Trainer 完成 (~20s after marker)
6. 读取 flashlog.txt 中的 SUMMARY REPORT
7. 对比基线，判断是否接受
8. 如果接受 → 更新基线 → 继续下一轮
9. 如果拒绝 → 回滚 → 尝试不同方向
```

**单轮耗时**：~1 分钟（编译 30s + Trainer 20s + 分析 10s）
**每 30 分钟可以跑 ~20 轮迭代**

## 当前基线 (2026-03-26 R19)

```
Total: 44 | Run: 42 | Skipped: 2 (opening book)
Local AI accuracy: 39/42 (93%)
Rapfi accuracy:    41/42 (98%)
  must_block:   7/7 (100%)
  defense:     14/15 (93%)
  double_three: 2/2 (100%)
  vcf:          2/2 (100%)
  vcf_defense:  2/2 (100%)
  gap_four:     2/2 (100%)
  tactical:     6/6 (100%)
  mid_game:     4/6 (67%)    ← 改善中（0%→67%）
  opening:      2/2 skipped (book覆盖)
```

**18轮自动化迭代成果**：
- 题库: 20→44 题（+24），覆盖 9 个分类
- 准确率: 88%→93%（+5pp）
- mid_game: 0/2→4/6（从0%到67%）
- 开局库: 1109→1111 entries（+4 Rapfi 验证补丁）
- P3 门控: 对手有活三时跳过己方冲四，交给搜索引擎
- LUT 单调性链完整验证

**剩余 3 个 FAIL（不可通过参数调优解决）**：
1. `mid_complex_diagonal` — P4a 截获的已输局面（对手双活四）
2. `mid_p3_should_not_rush` — P4a 截获（对手有活四，必须堵）
3. `def_diag_two_two_block` — 深度不足（d=10 vs Rapfi d=35）

**参数变更汇总**（vs 初始值）：
| 参数 | 初始 | 优化后 | 原因 |
|------|------|--------|------|
| TWO | 10 | 20 | 空间控制（修复 mid_multi_threat） |
| THREE | 100 | 400 | 活三威胁感知（核心改进） |
| BLOCK_THREE | 15 | 100 | 防守意识（>TWO×2=40 单调性） |
| TWO_TWO | 20 | 150 | 交叉二连识别 |
| BLOCK_FOUR | 150 | 900 | 防守权重（>THREE×2=800 单调性） |
| BLOCK_FIVE | 1500 | 100000 | 胜着等同 FIVE |
| BRIDGE_SIDE | 8 | 12 | 连接评估 |
| BRIDGE_LINK | 12 | 18 | 连接评估 |
| BRIDGE_SPAN | 8 | 12 | 跨度评估 |
| posWeight | ×2 | ×4 | 中心偏好 |
| pointsLimit(d100) | 20 | 25 | 候选数扩展 |
| P3 门控 | 无 | opThreeCount===0 | 避免复杂局面误判 |

## 性能优化历史

| 日期 | 优化 | 效果 |
|------|------|------|
| 2026-03-26 | 一维数组展平 | shapeCache 4D→1D, board 2D→1D, 每节点省 ~150 次哈希查找 |
| 2026-03-26 | Bridge 延迟到 top-K | 膨胀收集+重排，省 ~80 次 bridge 调用/root |
| 2026-03-26 | DROP_LOSING_THRESHOLD | score ≤ -1500 时禁止 difficulty drop |
