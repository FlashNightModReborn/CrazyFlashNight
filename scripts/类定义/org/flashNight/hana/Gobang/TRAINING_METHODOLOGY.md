# Gobang AI 自动化调优方法论

## 概述

本文档记录 Gobang AI 的自动化回归、定向调优和经验沉淀，目标是在 AVM1 / Flash CS6 的约束下，持续提高本地 AI 与 Rapfi 的一致性，同时避免一次性放宽启发式导致的大面积回归。

唯一受支持的自动化入口是仓库根下的 `scripts/gobang_trainer_cycle.ps1`。旧版 `scripts/train_cycle.sh` 已删除：它会绕过 `compile_test.ps1` 的仓库编译互斥、lease、目标归属、fresh Compiler Errors 与不确定状态标记，并直接清理 ASO / 完成标记，无法提供可审计的编译事务证据。

## 架构

```text
gobang_trainer_cycle.ps1
  -> 启动 launcher --bus-only（如未在运行）
  -> 重写 TestLoader.as 为 trainer 入口代码
  -> compile_test.ps1 → Flash CS6 testMovie

Flash (GobangTrainer in testMovie)
  -> ServerManager FSM 自动连接 bus
  -> XMLSocket → C# GomokuTask → Rapfi CLI

本地 AI 与 Rapfi 对同一局面分别作答
  -> GobangTrainer 汇总结果
  -> SUMMARY REPORT / FAIL 列表 → flashlog.txt
  -> gobang_trainer_cycle.ps1 解析结果
  -> 恢复 TestLoader.as → 定位弱点并进入下一轮调优
```

## 调优循环

### Step 1: 建立基线

```text
编译 -> Trainer.run() -> 读取 SUMMARY REPORT
```

关注：

- 总准确率
- 各分类准确率
- FAIL 的 `phaseLabel`

### Step 2: 定位弱点

典型输出：

```text
[Trainer] [FAIL] mid_game_overeval_pivot | Local:(8,9) minmax_d8 | Rapfi:(10,8)
```

常见含义：

- `P1_myFive` / `P2_blockFive`：预搜索强制手
- `P4a_blockFour` / `P4combo`：防守型预搜索截断
- `minmax_dN`：搜索结果，完成深度为 `N`
- `*_review` / `*_threat`：搜索结果被局部确认逻辑二次改写

### Step 3: 改代码 / 调参数

按问题类型选择方向：

- 评估权重：`GobangEval.as` `_initScoreLUT`
- 根候选排序 / 覆盖：`GobangEval.as`、`GobangMinmax.as`
- pre-search 优先级：`GobangMinmax.as` `_preSearchTactical`
- 局部确认：`GobangAI.as`

原则：

- 先缩小触发条件，再增强局部确认
- 先做定向回归，再做全量回归
- 任何新启发式都必须防止误伤已有通过题

### Step 4: 回归验证

```text
定向 trainer-only -> 观察目标题
全量 trainer-only -> 观察总准确率和新增 FAIL
```

接受标准：

- 总准确率提升，且无明显新增回归
- 或目标题稳定修复，且新增回归可控

## 题库扩展策略

### 来源 1: 对局提取

```text
1. 跑 AI vs Rapfi
2. 在评分反转或连续被迫防守处切局面
3. 加入 Trainer 题库
4. 用 Rapfi 验证 expectedMoves
```

### 来源 2: Rapfi 自对弈

```text
1. 让 Rapfi 自对弈
2. 抽取评分骤变局面
3. 转成 Trainer 题
```

### 来源 3: 手工构造

```text
1. 边缘 / 角落 / 跳连
2. 双二 / 双三 / 复合威胁
3. 深搜容易走偏的中盘拐点
```

### 质量控制

- `expectedMoves` 必须经 Rapfi 验证
- 题目尽量跳过开局库干扰
- 如果 AI 与 Rapfi 长期都不走某个 expectedMove，要考虑题面过时

## 关键文件

| 文件 | 用途 |
|------|------|
| `GobangTrainer.as` | 题库与评测框架 |
| `TestLoader.as` | 由 `gobang_trainer_cycle.ps1` 自动重写（注入 trainer 代码），运行后恢复 |
| `gobang_trainer_cycle.ps1` | 外层训练脚本：启动 bus、重写 TestLoader、触发编译、等待 summary、解析结果、恢复 TestLoader |
| `launcher/src/Tasks/GomokuTask.cs` | Rapfi 桥接（C# Guardian Launcher，替代旧 `gomokuTask.js`） |
| `tools/cfn-cli.sh` | CLI 工具：`start-bus`/`stop-bus`/`status`/`console`/`wait` |
| `GobangEval.as` | 评估权重、桥接分、候选生成 |
| `GobangMinmax.as` | 根搜索、预搜索、根短名单收集 |
| `GobangAI.as` | 难度参数、局部确认、threat refine |

## Agent 自动化调优工作流

### 推荐入口（2026-03-26）

全量 trainer-only：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/gobang_trainer_cycle.ps1 -Mode trainer_only -Json
```

定向题面：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/gobang_trainer_cycle.ps1 -Mode trainer_only -Problems mid_complex_diagonal,def_diag_two_two_block -Json
```

前缀整簇：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/gobang_trainer_cycle.ps1 -Mode trainer_only -Problems 'mid_game_overeval_pivot*','def_diagonal_three_center*' -Json
```

脚本行为：

```text
1. 生成 scripts/testloader_options.txt
2. 在仓库编译 mutex 内建立持久 scratch marker + recovery sidecar，再把 TestLoader 切到 trainer_only
3. 调用 scripts/compile_test.ps1
4. 等待 fresh flashlog.txt 中本轮唯一 runId 的 START → END 闭合块
5. 校验 Total/Run/Skipped、Local/分类汇总精确一次且非零，要求本地 AI 全部通过并交叉核对分类分子/分母
6. 要求 fresh compile output/errors、Compiler Errors 0/0、32K retry=0，再输出 JSON
7. 按 installed/original SHA-256 恢复 TestLoader，最后清 marker/sidecar 和 options
```

补充：

- `GobangTrainer.filterProblemsByName()` 现支持 `*` 后缀前缀匹配，可一次跑完整回归簇
- `gobang_trainer_cycle.ps1` 会把 `[Trainer] [RAPFI_DIFF]` 汇总进 JSON，便于持续跟踪“本地过题但 Rapfi 不同”的局面
- `-Problems` 只接受 identifier 或单个尾随 `*`；不存在的过滤结果会因 `Run=0` 失败，`50/51` 之类部分通过也会非零退出，不能靠缺少 `[FAIL]` 文本假绿
- child compile 成功后若没有唯一 END，脚本会写 `compile_state_uncertain.marker`；停止本轮自启 bus、恢复 scratch 与释放仓库 mutex 的顺序均在同一事务内。自启 bus 的 readiness 与 shutdown 绑定精确 Core PID / `launcher_ports.json` PID：先发 `/shutdown` 并等待该 PID 退出，超时才硬杀精确 PID；只清理由同一 PID（及已观察端口）证明归属的端口文件

### 为什么需要外层脚本

- `compile_test.ps1` 默认只轮询 30 秒，更适合 smoke
- 当前源码静态定义 68 题；旧 49 题的 `70~95s` 不得外推到现题库
- 训练是否完成必须以本轮唯一 runId 的闭合块、完整 summary schema、Compiler Errors 0/0 与 retry=0 共同判定，不能只看 `publish_done.marker`

### 现行迭代循环

```text
1. 修改评估权重 / 候选排序 / 局部确认逻辑
2. 先跑 -Problems 定向回归
3. 再跑全量 trainer-only
4. 若出现新 FAIL，优先收紧触发条件而不是继续放宽启发式
```

**2026-03-27 R36 历史单轮耗时**

- 全量：`~84s`
- 定向双题：`~10~15s`

**2026-03-27 R36 当轮有效 trainer-only 迭代**：约 `14` 轮，未超过 30 轮上限

## 当前题库静态事实（2026-07-25）

- `loadBuiltinProblems()` 含 68 个唯一 literal `addProblem`
- 分类定义数：`must_block=7 / defense=30 / double_three=2 / vcf=2 / mid_game=13 / vcf_defense=2 / gap_four=2 / tactical=8 / opening=2`
- opening book 静态命中 3 题，其中 `mid_avoid_distant_move` 的 category 是 `mid_game`；因此源码静态预期为 `Total=68 / Run=65 / Skipped=3`
- 静态计数不是 fresh CS6 行为证据；Local/Rapfi 通过率、分类 summary、`RAPFI_DIFF` 与耗时须由不带 `-Problems` 的完整 runner 重测后记录

## 当前动态基线（2026-07-25，68 题施工树）

不带 `-Problems` 执行完整 `gobang_trainer_cycle.ps1`，得到 runId `a3813e87797643539b16b3d20de1d584`：

```text
Total: 68 | Run: 65 | Skipped: 3 (opening book)
Local AI accuracy: 60/65 (92%)
Rapfi accuracy:    58/65 (89%)
elapsed:           208s
Compiler Errors:   0/0
32K retry:         0
```

当前 5 个本地失败为：

1. `mid_complex_diagonal`
2. `mid_p3_should_not_rush`
3. `def_diag_two_two_block`
4. `mid_post_book_response`
5. `def_t_precursor_cross`

另有 6 个 `RAPFI_DIFF`。完整 runner 因本地并非 `65/65` 按契约 exit 1；这是**正确的红基线**，不能只凭 compiler `0/0` 写成通过。`GobangTrainer.as` 已与施工基线 commit `3d33fd238032e4ffc81cc91b41223b7ac67415f9` 做 byte-exact 对照，内容未变，因此这些失败不是本轮维护性 runner 改造引入的 AI 变化。

runner 自身另以两个方向验证：`-Problems mb_open_four_h`（runId `f1c0945522384b3c8962d62dddf23556`）得到 Local/Rapfi `1/1` 且 exit 0；不存在的过滤项（runId `88f4201913d74e7caa31164617eb5d34`）得到 `Run=0` 并按预期 fail closed。两轮均为 fresh compiler `0/0`、retry `0`，且 scratch、Core PID、端口文件和 marker 完整回收。

## 历史动态基线（2026-03-27 R36，53 题快照）

```text
Total: 53 | Run: 51 | Skipped: 2 (opening book)
Local AI accuracy: 51/51 (100%)
Rapfi accuracy:    49/51 (96%)
  must_block:   7/7 (100%)
  defense:     20/20 (100%)
  double_three: 2/2 (100%)
  vcf:          2/2 (100%)
  vcf_defense:  2/2 (100%)
  gap_four:     2/2 (100%)
  tactical:     6/6 (100%)
  mid_game:    10/10 (100%)
  opening:      2/2 skipped (book覆盖)
```

R36 当时本地 AI 已无剩余 FAIL：

1. `def_diagonal_three_center`：稳定命中期望集 `(4,10)`，Rapfi 为 `(5,8)`
2. `mid_game_overeval_pivot`：已修复为 `(10,8) minmax_d8_pivot`，与 Rapfi 一致

R36 当时稳定的 `RAPFI_DIFF` 观察列表：

1. `def_h_gap_four`：本地 `(5,7) minmax_d8`，Rapfi `(6,6)`，当前 expected 为 `(5,7)|(4,7)`
2. `def_diag_cross_two_line`：本地 `(4,8) P4a_blockFour(2)_cal`，Rapfi `(8,4)`，当前 expected 为 `(7,7)|(7,4)|(4,8)`

## R36 迭代成果（历史快照）

### 目标一：`mid_complex_diagonal`

结果：已修复。

做法：

- 把 `P4a_blockFour(2)` 的选择性复核从“只看一个 alternative”扩展为“扫描根短名单并逐个浅确认”
- 当浅确认完全打平时，再做一次更深确认
- 若仍完全打平，允许后出现的等价候选覆盖前者，用来消除根排序对固定端点的偏置

效果：

- R36 全量回归中稳定命中 Rapfi 一致的 `(10,6)`
- phase 为 `P4a_blockFour(2)_review_cal`

### 目标二：`def_diag_two_two_block`

结果：已修复。

做法：

- 允许 `threat-defense refine` 在 `d10+` 且棋盘上确有紧急威胁时，对 `minmax_d*` 结果做一次局部防守确认
- 在候选评分里加入“多方向拦截”奖励：显式奖励同时挡住对手多个 `TWO / TWO_TWO / THREE` 方向的点

效果：

- 全量回归中命中可接受答案集 `(6,7)|(7,7)`
- R36 当时稳定落在 `(7,7) minmax_d10_threat`

### 全量收益

- R36 基线从上一轮的 `47/47 (100%)` 扩展到 `51/51 (100%)`
- `defense` 从 `18/18` 扩展到 `20/20`
- `mid_game` 从 `8/8` 扩展到 `10/10`

## 参数与逻辑变更汇总

| 位置 | 变更 |
|------|------|
| `TestLoader.as` | 新增 `trainer_only` 与题面过滤读取 |
| `gobang_trainer_cycle.ps1` | 新增 `-Problems`，并规范化逗号分隔题面名，同时汇总 `RAPFI_DIFF` |
| `GobangMinmax.as` | 新增根短名单收集接口 `collectRootMoves` |
| `GobangAI.as` `_reviewMultiBlockFourMove` | `P4a_blockFour(2)` 改为“根短名单 + 浅确认 + 深确认 + 去偏置” |
| `GobangAI.as` `_refineThreatDefenseMove` | 仅在 `d10+` 且棋盘有紧急威胁时开放 deep threat refine，并限制 root-only 候选不能覆盖直接防守点 |
| `GobangAI.as` `_scoreThreatDefenseCandidate` | 新增多方向拦截奖励，补足 `TWO_TWO` 类防守点的候选评分 |
| `GobangTrainer.as` | 新增 `mid_game_overeval_pivot*` / `def_diagonal_three_center*` 回归簇，并支持 `*` 前缀过滤 |

## 本轮经验

- `trainer_only + -Problems` 是必须的。没有定向入口，就很难在 30 轮预算内完成有效迭代。
- `P4a_blockFour(2)` 不能直接关掉，必须做成窄触发的选择性复核。
- 多活四替代点不能只搜一个 `alternative`。真正稳定的流程是：
  - 先拿根短名单
  - 逐个做浅确认
  - 平分时再做深确认
  - 如果仍完全打平，再显式消除固定 flatPos 顺序偏置
- `threat-defense refine` 绝不能全局放开。它一旦覆盖普通 `d8` 中盘，会误伤 `mid_multi_threat_coverage` 这类本来已经正确的进攻题。
- `TWO_TWO` 防守不能只看“落子后对手还有没有 THREE+”。还必须显式衡量“这个点在落子前拦住了多少个二/三方向”。
- 回归簇不一定都该做成“单点断言”。像 `def_diagonal_three_center*` 这类中心对角防守，更适合保留一小组可接受防守点，把真正的 AI/Rapfi 分歧交给 `RAPFI_DIFF` watchlist。

## 下一轮方向

1. 题库建设
   - 继续扩 `mid_game_overeval_pivot*` 和 `def_diagonal_three_center*`，优先补同型但更靠边的局面
   - 把当前通过的 cluster 题面再做 1 到 2 个非对称变体，防止只学会平移/镜像
2. Rapfi 差异跟踪
   - R36 当时本地 AI 为 `51/51`，Rapfi 为 `49/51`
   - 先围绕 `def_h_gap_four` 与 `def_diag_cross_two_line` 做根候选排序和 expected 复核，再决定是向 Rapfi 靠拢还是扩 expected

## 性能优化历史

| 日期 | 优化 | 效果 |
|------|------|------|
| 2026-03-26 | 一维数组展平 | `shapeCache` / `board` 降低哈希与索引开销 |
| 2026-03-26 | Bridge 延迟到 top-K | 根候选改为膨胀收集后重排 |
| 2026-03-26 | `DROP_LOSING_THRESHOLD` | 大劣势时禁止 difficulty drop 误导走法 |
