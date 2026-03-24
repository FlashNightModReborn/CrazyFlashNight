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

### 与当前路由器的差异
| 分布 | 树 | 当前路由器 | severity | 建议 |
|------|-----|-----------|----------|------|
| sawTooth20 | NATIVE | INTRO | 1.77 | 放行（收益 < classify 税） |
| nearSorted1 | NATIVE | INTRO | 1.83 | 边界，可保持 INTRO 但净收益很小 |

### Flash 实测数据
见 `data/phase0/flash-benchmarks.md`，全部 25 种分布的 native vs IntroSort 耗时。
