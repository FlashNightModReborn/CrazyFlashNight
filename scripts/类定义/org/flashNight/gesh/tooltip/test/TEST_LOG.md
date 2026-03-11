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
