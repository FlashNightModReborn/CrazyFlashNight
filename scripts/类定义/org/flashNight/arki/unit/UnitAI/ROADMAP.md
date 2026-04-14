# UnitAI 人形怪 AI 系统 — 长期路线图

## 现状总览

48 个 .as 文件，~7500 行代码，HFSM + Utility AI 混合架构。

```
UnitAI/
  BaseUnitAI.as              ← 工厂入口（唯一留根目录的文件）
  core/     (4)              ← 纯数据 + 环境抽象（零行为类依赖）
  combat/   (11+17+9=37)     ← 战斗决策引擎 + 评分修正器 + 策略
  behavior/ (6)              ← 具体单位行为实现
```

## Phase 1: 结构重构 [已完成 2026-04-11]

**目标**: 纯结构变更，零可观察行为变更，为 Phase 2 测试基建铺路。

**产出**:
1. **AIEnvironment 静态门面** — `_root` 访问的唯一入口，全局依赖收敛到 1 个文件
2. **UnitAIData 数据聚合** — 15 个聚合字段，AIContext.build() 零 MC 直读
3. **ThreatAssessor** — 从 ActionArbiter 提取的威胁评估（retreatUrgency/encirclement/spatial）
4. **AmmoHelper** — 弹药比共享计算，消除双实现漂移
5. **全部 _root 隔离** — UnitAI/ 内仅 AIEnvironment.as 包含 `_root`
6. **三层目录** — core/ + combat/ + behavior/，非人形怪 AI 只需 import core/

**Phase 1 未做（明确边界）**:
- MC 写入未收敛（6+ 文件直接写 MC 属性，engage wantFire 读写契约需 Phase 2 先解耦）
- `self._x/方向/待机` 等单位位置仍从 MC 直读
- corneredAggression 仍在 ActionArbiter（依赖 _prepareContext 时序）
- 无 AS2 单测框架（但已具备 Python L1 离线仿真）

---

## Phase 2: 离线调优 + 移动行为优化 [计划中]

### 2.1 核心痛点

**移动行为是当前最大短板**：
- 佣兵很难顺滑溜边，边界附近行为生硬
- 容易被堵死在墙角，脱困逻辑触发延迟且方向选择不够智能
- MovementResolver.applyBoundaryAwareMovement 的多级脱困策略（Phase 0 障碍探测 → Phase 1 X 轴检查 → Phase 2 Z 注入 → Phase 3/4 输出）在简单场景工作，但复杂地形下探测窗口、脱困持续帧、方向优先级等参数难以靠体感调优
- 撤退时的掩护射击 vs 移动优先级平衡（RetreatMovementStrategy 五重门控）

### 2.2 离线仿真路线（基于 mercenary-ai-sim 经验）

`tools/mercenary-ai-sim/` 已验证了离线仿真的可行性：
- Python 碰撞检测（shapely）替代 Flash hitTest
- 批量统计（出口率/平均帧数/卡死率）替代体感评估
- 对抗地图（14 种恶意模式）替代人工构造测试场景
- matplotlib 轨迹可视化替代肉眼观察

**Phase 2 扩展方向**：

#### A. 战斗移动仿真器 (`tools/combat-movement-sim/`)

**当前状态**：已落地，可直接运行 `python tools/combat-movement-sim/run_sim.py --baseline|--chase|--compare`
- 已和当前 AS2 `MovementResolver` 主常量重新对齐：`probe = speed * 5`、`noProgress >= 2`、脱困窗口 `24/36/48`
- 静态撤退场景（9 个）当前基线可达 `success_rate = 100%`
- 动态追逐场景（7 个）当前默认基线已提升到 `3/7`
- 已补入三类状态化近似：**ThreatAssessor 16 帧 pressure 采样**、**EngageMovementStrategy 脉冲式 Z 走位**、**count-first dominantSide / safeX 修正**
- 当前这套默认基线已救回 `chase_pack_open`、`chase_pack_corridor`、`chase_pack_obstacles`
- 当前 compare 内置的是**历史追逐候选包**；在新默认基线上已不再增加通过场景，且会回退部分静态图，因此只保留作回归参考
- 当前默认基线仍失败的红场景为：
  `chase_pack_corner`、`chase_pincer_lane`、`chase_edge_reentry`、`chase_swarm`

从 mercenary-ai-sim 的非战斗寻路扩展到战斗期间的移动决策：

| 维度 | mercenary-ai-sim (已有) | combat-movement-sim (现状) |
|------|------------------------|---------------------------|
| 移动目标 | 门（固定点） | 目标单位（动态/静止） |
| 决策逻辑 | Thinking/Walking/Wandering | Retreat + 多敌追逐压力近似（Threat/Engage surrogate） |
| 碰撞处理 | is_point_valid | applyBoundaryAwareMovement 全套 |
| 关键参数 | idle/walk/wander 时长 | margin、probe、脱困窗口、encirclement/edgeEscape 阈值 |
| 评估指标 | 出口率/超时率 | 卡死率/溜边平滑度/角落逃脱时间/最小敌距/被抓率 |

**核心模块**:
1. `movement_resolver.py` — 复刻 MovementResolver.applyBoundaryAwareMovement
   - Phase 0: blockedAhead + noProgress + stuck 三触发器
   - edgeEscape → X优先对角 → 纯Z滑行 → 反向退步 → pushOut 兜底
   - 脱困窗口递增机制
2. `combat_sim.py` — 撤退/追逐主循环，含多敌威胁中心、16 帧 pressure 采样、脉冲式 strafe、safeX/edgeEscape 近似、PackEscapePlanner 承诺窗口
3. `param_scanner.py` — 参数网格搜索 + 综合评分排序
4. `scenario_gen.py` — 对抗场景生成器
   - 墙角陷阱（三面封闭 + 敌人堵口）
   - 狭窄通道对冲
   - L 形/U 形拐角追逐
   - 多敌包围 / 双侧夹击 / 贴边再入场
5. `visualize.py` — 轨迹绘制 + 对比图输出

**数据源充足的理由**:
- MovementResolver 330 行，逻辑完全自包含（只依赖 UnitAIData + Mover 的碰撞探测）
- 边界距离（bndLeftDist/bndRightDist/bndUpDist/bndDownDist）是纯数值
- 脱困状态（_unstuckUntilFrame, _noProgressCount, _probeFailCount）是纯数值
- 碰撞探测（Mover.isDirectionWalkable）可用 shapely 精确复刻
- 已有 14 种对抗地图生成器可直接复用

#### B. 参数扫描框架

```python
# 示例：扫描 MovementResolver 的关键参数
param_grid = {
    "margin": [60, 80, 100, 120],
    "probe_speed_mult": [4.0, 5.0, 6.0],
    "unstuck_base_window": [12, 24, 36, 48],
    "no_progress_threshold": [2, 3, 4, 5],
    "encirclement_evade_threshold": [0.2, 0.25, 0.35],
    "edge_escape_margin": [60, 80, 100],
    "pressure_dominance_ratio": [1.05, 1.15, 1.3],
    "pack_escape_window": [12, 20, 28],
    "threat_sample_interval": [12, 16, 20],
    "kite_x_threshold": [160, 180, 220],
    "evade_nearby_count": [1, 2, 3],
    "strafe_gap_base": [8, 12, 16],
}

# 每组参数跑 N 次 × M 个场景 → 统计指标
metrics = {
    "stuck_rate": "卡死超过 3 秒的比例",
    "corner_escape_frames": "角落脱困平均帧数",
    "edge_smoothness": "溜边轨迹的方向变化频率（越低越平滑）",
    "caught_rate": "动态追逐被抓比例",
    "avg_min_enemy_dist": "动态追逐最近敌距（越高越好）",
}
```

#### C. 调优结果回写 AS2

离线找到的最优参数 → 直接更新 MovementResolver.as 的常量：
- `MARGIN` (当前硬编码 80)
- 脱困窗口基数 (当前 24/36/48 三档)
- noProgress 阈值 (当前 2)
- probeFailCount 触发值 (当前 3)
- probe 距离倍率 (当前 `speed * 5`)

#### D. 下一阶段离线重点：ThreatAssessor + EngageMovementStrategy

在 `MovementResolver` 几何层已能稳定复现之后，下一阶段不再只盯脱困常量，而是校准：
- `ThreatAssessor.scanRange / nearbyRange / encirclement` 对多敌压力的判定口径
- `EngageMovementStrategy.safeX / edgeEscapeX / enemyDominantSide` 的选边逻辑
- `HeroCombatModule` 的走打合成在多敌压力下何时应让位给纯移动
- 若继续推进离线层，优先级应转向**更完整迁移 EngageMovementStrategy / HeroCombatModule 组合逻辑**，而不是继续堆局部启发式
- 当前默认基线已能覆盖 `open / corridor / obstacles` 三类动态追逐；继续突破需要补“绕最近敌人的缺口突围”和“走打冲突裁决”

优先吃掉的红场景：
1. `chase_pack_corner` — 角落多敌压迫下仍缺少更完整的逃逸-重定位组合
2. `chase_pincer_lane` — safeX 已接近正确，但仍缺“绕最近敌人的缺口突围”组合
3. `chase_edge_reentry` — 贴边出生后“回场内”与“重新加速脱离”之间仍会断档
4. `chase_swarm` — 无安全区蜂群场景仍需要更强的全局缺口规划/持久生存策略

### 2.3 MC 写入解耦（Phase 2 后期）

前置条件：离线仿真稳定后，再做代码层面的解耦。

- **ActionCommand** — arbiter.tick() 的输出从直写 MC 改为返回命令对象
- **ActionApplier** — 集中执行 MC 写入（`self.动作A/B/左行/右行/上行/下行`）
- 解耦后 arbiter.tick() 可在离线环境零 MC 运行，仿真覆盖面从"移动"扩展到"完整决策"

### 2.4 测试框架

基于 Phase 1 的 AIEnvironment mock + UnitAIData 聚合字段：

```
测试层级:
  L1: 离线仿真（Python，秒级反馈，参数扫描）  ← Phase 2 重点
  L2: AS2 单元测试（mock AIEnvironment，帧级验证）
  L3: 实时调优（Launcher WebSocket 下发参数，游戏内热替换）
```

---

## Phase 3: 量化评估 + A/B 测试 [远期]

### 3.1 A/B 测试基建

Phase 2 完成后具备条件：
- 离线仿真 → 参数候选集
- Launcher WebSocket → 实时下发参数
- DecisionTrace → 决策日志采集

A/B 框架：
1. 随机分配佣兵到 A/B 组（不同人格参数集）
2. 采集 DecisionTrace 日志 + 战斗统计
3. 对比指标：存活时间、伤害输出、卡死频率、玩家干预频率

### 3.2 量化指标体系

| 维度 | 指标 | 数据源 |
|------|------|--------|
| 移动质量 | 卡死率、溜边平滑度、角落逃脱时间 | 离线仿真 + MovementResolver 日志 |
| 战斗效率 | 有效战斗时间比、DPS 利用率 | ActionArbiter 决策日志 |
| 行为表现力 | 人格分化度、决策多样性 | Boltzmann 分布熵 |
| 系统健壮性 | NaN 级联率、状态机死锁率 | 防御性断言 |

### 3.3 人格系统增强

基于 A/B 数据的人格参数校准：
- 勇气/反应/healEagerness 等参数对行为的实际影响量化
- 个性化移动风格（激进冲锋 vs 保守溜边 vs 闪避优先）
- 武器偏好与站位的协同调优

---

## 关键文件索引

### core/ — 纯数据层
| 文件 | 行数 | 职责 |
|------|------|------|
| AIEnvironment.as | ~140 | _root 访问唯一入口 |
| UnitAIData.as | ~420 | 数据黑板 + 聚合字段 |
| AIContext.as | ~220 | 每 tick 快照（零 MC 直读） |
| BaseUnitBehavior.as | ~50 | 行为基类（暂停检查） |

### combat/ — 战斗决策引擎
| 文件 | 行数 | 职责 |
|------|------|------|
| ActionArbiter.as | ~480 | Utility AI 主控（collect→filter→score→select） |
| ActionExecutor.as | ~370 | 动作执行 + commit 契约 |
| ThreatAssessor.as | ~110 | 威胁评估（retreatUrgency/encirclement） |
| MovementResolver.as | ~330 | **边界感知移动（Phase 2 重点调优目标）** |
| WeaponEvaluator.as | ~440 | 武器切换评估 |
| DecisionTrace.as | ~450 | 决策日志（4 级详细度） |
| PipelineFactory.as | ~290 | 评分管线 + 策略工厂 |
| combat/scoring/ | 17 文件 | 评分修正器（Boltzmann 前） |
| combat/strategies/ | 9 文件 | 候选策略 + 过滤器 |

### behavior/ — 单位行为
| 文件 | 行数 | 职责 |
|------|------|------|
| HeroCombatBehavior.as | ~400 | 英雄/佣兵 HFSM 主循环 |
| HeroCombatModule.as | ~470 | chase/engage 子状态机 |
| MecenaryBehavior.as | ~540 | 佣兵非战斗行为（寻路/溜边） |
| EnemyBehavior.as | ~390 | 敌人行为（无 Utility AI） |
| CombatModule.as | ~200 | 敌人战斗子状态机 |
| PickupModule.as | ~180 | 拾取物寻路 |

---

## 已有离线工具

| 工具 | 位置 | 状态 | 用途 |
|------|------|------|------|
| mercenary-ai-sim | tools/mercenary-ai-sim/ | 已验证 | 非战斗寻路离线仿真 + BFS 对比 |
| combat-movement-sim | tools/combat-movement-sim/ | 已落地（需持续对齐 AS2 基线） | 战斗移动离线仿真 + 参数扫描 + 动态追逐对抗 |

---

## 修改历史

- 2026-04-11: Phase 1 完成（Step 1-6），创建本文档
- 2026-04-14: combat-movement-sim 与当前 AS2 基线重新对齐；补充动态追逐红场景与下一阶段离线重点
- 2026-04-14: 引入加权压力判定与 PackEscapePlanner；确认当前 heuristic ceiling 约为动态追逐 3/7
- 2026-04-14: 引入 ThreatAssessor 采样滞后与 EngageMovementStrategy 脉冲走位近似；默认动态追逐基线提升到 3/7，旧 candidate 包退化为回归参考
