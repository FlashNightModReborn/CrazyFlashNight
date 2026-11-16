# Tooltip 测试套件日志留档

本文档记录每次重要改动后的测试运行结果，便于对比查阅性能变化。

---

## 基线：v1.0 — 测试套件初建（2026-03-12）

### 功能测试

| 测试类 | 断言数 | 结果 |
|--------|--------|------|
| TooltipConstantsTest | 50 | 50/50 PASS |
| ItemUseTypesTest | 24 | 24/24 PASS |
| TooltipFormatterTest | 64 | 64/64 PASS |
| TooltipDataSelectorTest | 8 | 8/8 PASS |
| BuilderContractTest | 41 | 41/41 PASS |
| TooltipBridgeTest | 35 | 35/35 PASS |
| TooltipLayoutTest | 15 | 15/15 PASS |
| TooltipIntegrationTest | 28 | 28/28 PASS |
| **合计** | **265** | **265/265 PASS** |

### 性能基准

尚未加入性能测试。

---

## v1.1 — 性能优化：htmlScoresBoth 合并扫描（2026-03-12）

### 改动摘要

1. **StringUtils.htmlScoresBoth()** — 合并 htmlLengthScore + htmlMaxLineScore 为单次扫描
   - 嵌套闭包（isCJKWide/decodeEntity/readTagName/addChar/flushLine）→ 提升为 static 方法
   - 热循环对象分配（{code,advance}/{name,jumpTo}）→ 静态复用对象
   - 旧 API 保持向后兼容（委托 htmlScoresBoth）

2. **TooltipLayout.shouldSplitSmartWithScores()** — 分栏判定 + 评分一次性返回
   - renderItemTooltipSmart 中 desc HTML 从 3 次扫描→1 次
   - estimateMainWidthFromScores 接受预计算评分，跳过重复扫描

3. **TooltipComposer.renderItemTooltipSmart** — 使用 shouldSplitSmartWithScores + estimateMainWidthFromScores

### 预期收益

| 热路径 | 优化前扫描次数 | 优化后扫描次数 | 减少 |
|--------|:---:|:---:|:---:|
| desc HTML 字符扫描 | 3 | 1 | 67% |
| intro HTML 字符扫描 | 1 | 1 | 0% |
| 嵌套闭包创建 /call | 5 | 0 | 100% |
| 热循环对象分配 /tag | 1 | 0 | 100% |

### 功能测试

| 测试类 | 断言数 | 结果 |
|--------|--------|------|
| TooltipConstantsTest | 50 | 50/50 PASS |
| ItemUseTypesTest | 24 | 24/24 PASS |
| TooltipFormatterTest | 64 | 64/64 PASS |
| TooltipDataSelectorTest | 8 | 8/8 PASS |
| BuilderContractTest | 41 | 41/41 PASS |
| TooltipBridgeTest | 35 | 35/35 PASS |
| TooltipLayoutTest | 15 | 15/15 PASS |
| TooltipIntegrationTest | 28 | 28/28 PASS |
| TooltipPerfBenchmark | 10 | 10/10 PASS |
| **合计** | **275** | **275/275 PASS** |

### 性能基准

| 基准项 | 次数 | 耗时 | 单次 |
|--------|------|------|------|
| htmlScoresBoth(short) | 500 | 263ms | 0.526 ms/call |
| htmlScoresBoth(long) | 200 | 936ms | 4.68 ms/call |
| combined(long) | 200 | 904ms | 4.52 ms/call |
| separate(long) | 200 | 1814ms | 9.07 ms/call |
| shouldSplitSmartWithScores | 200 | 1093ms | 5.47 ms/call |
| shouldSplitSmart(旧) | 200 | 966ms | 4.83 ms/call |
| estimateMainWidth(旧) | 200 | 923ms | 4.62 ms/call |
| estimateMainWidthFromScores | 200 | 7ms | 0.035 ms/call |
| renderItemTooltipSmart | 100 | 112ms | 1.12 ms/call |

**关键对比**：
- 合并扫描 vs 分开扫描：904ms vs 1814ms → **快 2.0x**
- estimateMainWidth 预计算评分 vs 重新扫描：7ms vs 923ms → **快 132x**
- 端到端 renderItemTooltipSmart：1.12 ms/call（< 50ms 阈值）

### 附加修复

- **ObjectUtil.toString → stringify**：修复 AS2 编译器将 `toString` 解析为 `Object.prototype.toString`（实例方法）而非声明的静态方法的 bug，消除了 54 个级联编译错误

---

## v2.0 — sqrt 公式宽度估算（2026-03-15）

### 改动摘要

`estimateMainWidthFromMetrics` 从 smoothstep 均匀度插值替换为 sqrt 面积公式：

```
W = sqrt(r × totalScore × PIX_PER_UNIT × LINE_HEIGHT)
r = RATIO_MIN + smoothstep(totalScore / RATIO_SCORE_CAP) × (RATIO_MAX - RATIO_MIN)
```

参数（2 轮 config sweep + 帕累托前沿分析确定）：
- PIX_PER_UNIT=6.0, LINE_HEIGHT=15（Phase 2/3 校准）
- RATIO_MIN=0.618, RATIO_MAX=1.5, RATIO_SCORE_CAP=300

### TDD 过程

1. **红灯**：4 个宽度断言 FAIL（dominator W=650>450, heavyGun W=650>450, sparse W=504>350, longUniform W=385>370）
2. **调参**：phase7 config sweep，8+10 组参数，帕累托前沿选出 Config B
3. **绿灯**：318/318 ALL PASSED
4. **验证**：1558 真实物品全量分布验证

### 真实数据分布验证（749 split 物品）

| 指标 | 旧算法 | sqrt 公式 | 改善 |
|------|--------|----------|------|
| W/H 0.8-1.5 理想占比 | 0.1% | **81%** | +81pp |
| W/H 2.0+ 过扁占比 | 94.7% | **11.7%** | -83pp |
| meanPenalty | 1.92 | **0.17** | -91% |
| PIX 灵敏度 (5.5→7.0) | N/A | **< 6%** | 字体鲁棒 |

### 功能测试

| 测试类 | 断言数 | 结果 |
|--------|--------|------|
| TooltipRegressionTest | 32 | 32/32 PASS |
| TooltipConstantsTest | 50 | 50/50 PASS |
| ItemUseTypesTest | 24 | 24/24 PASS |
| TooltipFormatterTest | 64 | 64/64 PASS |
| TooltipDataSelectorTest | 8 | 8/8 PASS |
| BuilderContractTest | 41 | 41/41 PASS |
| TooltipBridgeTest | 35 | 35/35 PASS |
| TooltipLayoutTest | 22 | 22/22 PASS |
| TooltipIntegrationTest | 28 | 28/28 PASS |
| TooltipPerfBenchmark | 14 | 14/14 PASS |
| **合计** | **318** | **318/318 PASS** |

### 性能基准

| 基准项 | 次数 | 耗时 | 单次 |
|--------|------|------|------|
| htmlScoresBoth(short) | 500 | 72ms | 0.14 ms/call |
| htmlScoresBoth(long) | 200 | 454ms | 2.27 ms/call |
| estimateMainWidth(旧入口) | 200 | 455ms | 2.28 ms/call |
| estimateMainWidthFromScores | 200 | 523ms | 2.62 ms/call |
| estimateMainWidthFromMetrics | 200 | **1ms** | **0.005 ms/call** |
| renderItemTooltipSmart | 100 | 61ms | 0.61 ms/call |

性能守卫：fromMetrics 1ms < 50ms 阈值 ✅

### 已知限制

39 个物品（5.2%）W/H > 2.5，为 MIN_W=150 clamp 导致的结构性问题（极短描述+极少行数），不可通过 sqrt 参数优化解决。

---

## 模板（复制此段用于后续记录）

```
## vX.X — 描述（日期）

### 改动摘要
- ...

### 功能测试

| 测试类 | 断言数 | 结果 |
|--------|--------|------|
| ... | ... | ... |

### 性能基准

| 基准项 | 次数 | 耗时 | 单次 |
|--------|------|------|------|
| ... | ... | ... | ... |
```
