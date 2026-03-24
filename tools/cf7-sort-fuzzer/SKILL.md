# SortRouter Fuzzer Skill

## 前置条件
- Flash CS6 已启动，TestLoader 已打开
- `tools/cf7-sort-fuzzer/` 已 `npm install`

## 快速迭代循环

### 1. 运行 fuzzer（纯 TS，无需 Flash）
```bash
cd tools/cf7-sort-fuzzer && npm run fuzz
```
输出 top candidates 到 `data/corpus/corpus-summary.json`。

### 2. 生成 benchmark harness
```bash
npm run harness-gen          # 默认 batch A (安全分布)
npm run harness-gen -- B     # batch B (危险分布)
```
生成 `SortProbe.as` benchmark 代码。

### 3. Flash 标注
1. 确认 `scripts/TestLoader.as` 指向 `SortProbe.run()`
2. 清除 ASO 缓存:
   ```bash
   rm "$LOCALAPPDATA/Adobe/Flash CS6/zh_CN/Configuration/Classes/aso/org/flashNight/naki/Sort/org.flashNight.naki.Sort.SortProbe.aso"
   ```
3. 触发编译:
   ```bash
   powershell -ExecutionPolicy Bypass -File scripts/compile_test.ps1
   ```
4. 如超 30s，用长轮询（见 Phase 3.3 方案）

### 4. 训练决策树
```bash
npm run train
```
输出管线优化建议报告。

### 5. 根据报告修改 SortRouter.as
Agent 通过 Edit 工具修改阈值或插入新 stage。

### 6. 回归验证
修改 TestLoader.as → `SortRouterTest.runQuickTests()`，触发编译验证 67 条断言。

## 已有成果

### Phase 0 发现
- Flash native sort: **最左 pivot + Hoare 双指针分区**
- **无三路分区、无 insertion sort cutoff、无内省保护**
- Hoare 对重复值有隐式均衡化效果（organPipe 11ms vs mountain 1387ms）

### Phase 2 决策树 (99.5% accuracy)
```
根: endGap ≤ 5150?
├─ 是 → turns ≤ 20? → headViol ≤ 127? → endGap/sampleOrder 细分
└─ 否 → turns ≤ 0? → antiCnt ≤ 16? → INTRO/NATIVE
```
特征集: endGap, turns, headViol, sampleOrder, antiCnt（5 个）

### 与当前路由器的差异（需进一步复测）
| 分布 | 树 | 当前路由器 | 单次 severity | 状态 |
|------|-----|-----------|--------------|------|
| sawTooth20 | NATIVE | INTRO | 1.77 | 需多 seed × 多 rep 复测 + router_total 对比 |
| nearSorted1 | NATIVE | INTRO | 1.83 | 当前路由器 8/8 必拦目标，不宜轻易放行 |

**注意**：树的"建议放行"本质上是复述 severity < 5 的标签阈值，不是独立证据。
边界样本（sawTooth20 / nearSorted1 / fewUnique10）需要：
1. 8 seeds × 3-5 reps 的稳定性实测
2. router_total = classify + chosen_sort 的真实测量
3. 只在"多 seed 下 router_total 明显劣于 native_total，且不削弱 uniq 安全网"时才考虑变更

**uniq 特征**：树未使用 uniq 不等于路由器中冗余。uniq 是低基数早停和 desc-plateau
鸽巢守卫的核心，模型自身对重复值输入存在盲区，正是 uniq 覆盖的区域。保留。

### Flash 实测数据
见 `data/phase0/flash-benchmarks.md`，全部 25 种分布的 native vs IntroSort 耗时。
注意：当前数据为 n=10000 单次 benchmark，边界样本的结论需要多 rep 确认。
