# CF7:ME Web Overlay 性能消融测试平台 Peer Review

**审视方**：Kimi Code (kimi-for-coding) 独立 review
**时间**：2026-04-25
**对象**：[launcher/perf/](../launcher/perf/) 性能测试 harness 首次基线（reports/2026-04-25T07-40-07）

## 执行摘要

平台工程思路正确（Playwright + CDP 可重复消融基准 + 区分 headless/真 WebView2），但在统计方法、ablation 粒度、指标解释上存在若干会扭曲决策的陷阱。当前最危险的信号是 `filter-off` 的 +58.6% 反向恶化——它几乎肯定是测量假象，必须被隔离，否则可能误导团队去"保留 filter"这种荒谬结论。

## A. 方法论可信度

### A1. `TaskDuration / sampleMs` 作为主指标

基本成立，但有边界条件：

1. **不含 GPU 进程**：`backdrop-filter` / `mix-blend-mode` 的 fragment shader 成本跑在 GPU 进程，`TaskDuration` 完全感知不到。这正是 panel-map 场景下所有 GPU ablation 信号 < 2% 的根本原因——不是这些属性免费，而是 headless 根本没走 GPU 路径
2. **可能包含一次性的样式风暴**：`!important` 全局注入后，Blink 在下一帧触发全文档 RecalcStyle + Layout。300ms 等待对复杂 DOM 不一定够
3. **更合适的辅助 CDP 指标**：并行采集 `LayoutDuration`、`RecalcStyleDuration`、`ScriptDuration`，计算各自占 `TaskDuration` 的比例。Tracing 应增加 `UpdateLayerTree` 和 `HitTest` 统计

### A2. rAF 间隔在 headless 下的真实状态

判断准确，但原因更微妙：headless Chromium 的 rAF 回调仍会被调用，只是不再与 vsync 同步。`__cf7Perf.frames` 记录的是"主线程调度间隔"，与 GPU 合成负载脱钩。所有用于决策的基线数据必须来自 headed 模式或真 WebView2。

### A3. 样本量与系统性偏差

**单次 4 秒 × 9 ablation × 3 scenario 统计上不够**：

- **Warmup 不足**：建议提高到 2000ms，每场景首次跑前增加 dry-run 预热
- **GC 非确定性**：4 秒窗口内 V8 GC 一次吃几十到几百 ms。建议每个 ablation 重复 **5 次**，去掉最高/最低值取中位数
- **串行污染**：browser.launch 内串行所有 ablation 共享同一 GPU 进程/内存池，nuclear 类大量分配可能影响后续 ablation。建议 scenario 间重启 browser 或 ablation 顺序随机化（shuffle）

## B. 数据反常解读

### B1. mix-blend-off 在 lockbox 下 -26% CPU

**真信号，但机制不是单纯 GPU**：

`mix-blend-mode` 在 Blink 中强制：
1. 元素提升为独立 graphics layer（CPU 端）
2. paint 阶段分配独立 paint record / display item list（CPU 端）
3. layer tree 提交时标记需要 readback（GPU 端 blend）

headless 跳过第 3 步，但 1、2 两步的 CPU 工作仍执行且不菲。更关键：`mix-blend-mode` **阻断 paint phase 合并（coalescing）**——去掉后浏览器可将相邻元素合并到同一 paint chunk，大幅减少 paint invalidation 粒度。

lockbox 扫描线（`.lockbox-panel::before`）的 `mix-blend-mode:screen` + infinite 动画：去掉 blend 后，即使动画改变了 box-shadow 或其他属性，layerization 策略可能改变，浏览器可能将其优化为 composited layer animation。-26% 是 **paint invalidation 减少 + layer setup 简化** 的叠加。

### B2. filter-off +58.6% 反向恶化

**几乎可以肯定是 `*` 选择器引入的 ablation 副作用，而非真实信号**：

`filter` 属性在 Blink 中强制创建新的 stacking context 和 containing block。`* { filter: none !important }` 全局覆盖时：

1. **层叠顺序重组**：大量元素的 containing block 改变，绝对/固定定位元素的坐标参考系变化，触发 Layout
2. **Paint path 降级**：原本因 `filter: drop-shadow()` 隔离在独立 compositing layer 的元素可能回到主 surface
3. **样式 fast-path 失效**：从"有 filter"突变到"filter:none"导致 style diff 走更复杂代码路径

**验证方法**：
- 检查 filter-off 的 `RecalcStyleCount` / `LayoutCount` 是否显著高于 baseline
- 做**靶向 ablation**：只对已知用 filter 的元素（`#top-right-tools button`、`#combo-hit-bar` 等）注入 `filter: none`
- 检查 visual-diff 的截图：布局错位证实 Layout 触发

### B3. will-change-off -17.7%

**信号可信，静态审计 2-4% 预估偏低**：

`will-change: transform` 在 Blink 里**立即**将元素提升到 compositing layer，即使没有动画。每个被提升元素：
- 主线程创建 `cc::Layer` 对象
- Layer tree 遍历、属性更新、提交（commit to compositor）有 O(n) CPU 开销
- headless 下虽无 GPU texture 分配，`cc::Layer` 内存管理 + 序列化仍消耗主线程时间

CF7 overlay 的 `will-change` 实际数量可能远超静态审计的 2-3 处。建议 runtime 统计 `document.querySelectorAll('[style*="will-change"], ...')`。

## C. 架构改进建议

### C1. `*` 选择器粒度过粗

当前问题：破坏 CSS 层叠语义、引入全量 RecalcStyle、无法归因。

**两级体系**：
1. **`*` 作一级雷达**：快速扫描发现 >10% 异常信号
2. **靶向 ablation 二级验证**：通过 `getComputedStyle` 遍历，只给实际使用该属性的元素注入 inline style：

```js
const targets = [...document.querySelectorAll('*')].filter(el =>
    getComputedStyle(el).mixBlendMode !== 'normal'
);
targets.forEach(el => el.style.mixBlendMode = 'normal');
```

消除 `*` 全局副作用 + 输出归因列表。

### C2. 缺失场景

当前覆盖 idle / panel-map / panel-lockbox，缺失：

1. **Panel 切换过渡**（200-300ms 动画期 layer 创建/销毁风暴）
2. **Map zoom-pan**（transform 更新 + scene-node 重排）
3. **Lockbox 游玩交互**（hover/inject/finisher 动态状态）
4. **Gobang 面板**（呼吸 + 扫掠 + 准星）
5. **Mouse-burst / 高频 hover**（cursor-feedback.js + 样式重算）
6. **Jukebox canvas 播放态**（需 Bridge 推流，仅 WebView2 模式可测）

### C3. 真 WebView2 自动开 panel

当前 CDP 只能操控 Web 内容，无法触发 C# host `Panels.open()`。

**自动化路径**（按可行性）：
1. **JS 注入**：`page.evaluate(() => Panels.open('map'))` 试调用，依赖 overlay JS 环境完整性
2. **C# host 暴露 automation API**：localhost HTTP/named pipe 接 `POST /automation/open-panel?name=map`
3. **键盘模拟**：`Input.dispatchKeyEvent` 发快捷键

建议路径 1 优先 + 失败回退提示用户。

## D. 后续行动建议

### D1. 优先级 Top-3

**优化 1：`backdrop-filter: blur()` → 纯色半透明背景**
- 覆盖最广、视觉无损（已有 rgba 兜底色）、headless + 真机都有信号
- 预期：非 panel 态 -15-22%，panel 态额外 -5-10%

**优化 2：移除 2 处 `mix-blend-mode: screen`（lockbox + map 扫描线）**
- 当前最强单 ablation 信号（-26%），实施成本极低（改两行 CSS）
- 视觉损失几乎不可见（opacity 0.45-0.55 渐变可替代）
- 预期：panel-lockbox -10-15%，panel-map -5-8%

**优化 3：`will-change` 改 JS 动态管理**
- 实测 -17.7% 远超审计预估，零视觉损失
- 实施：禁止 CSS 常驻 `will-change`，改 JS 动画前 200ms 添加、结束移除
- 预期：全局 -10-18%，map 打开额外 -3-5%

### D2. 单点优化

**唯一的话：移除/替换 `backdrop-filter: blur()`**

理由：覆盖最高（idle 35% iGPU 中头号推手）+ 视觉无损（已有 rgba 半透明兜底）+ 实施成本最低（30 分钟批量替换）+ 风险最低（不涉动画时序、不依赖 Bridge、不影响游戏逻辑）。

mix-blend-off 单场景信号最强但只影响特定面板；will-change-off 需 JS 配合避免动画卡顿。**backdrop-filter 是 low-hanging fruit 中的全局最优解**。

---

*下一轮基线测试建议：headed 模式、5 次重复、2000ms warmup、靶向 ablation 验证 filter-off 异常。*
