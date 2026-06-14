# Web Panel 全屏设计对齐审计报告

**审计日期**: 2026-06-11  
**代码基线**: commit `d063d53c2`（2026-05-30）  
**审计范围**: `launcher/web/modules/` 下全部 12 个已注册 panel  
**核心约束**: 固定长宽比、不做多端分辨率适配、全屏体验优先、维持现有视觉语言

---

## 1. 核心发现摘要

当前 12 个已注册 panel 中：

| 分类 | 数量 | 说明 |
|------|------|------|
| **A. 无损全屏就绪** | 4 个 | 已采用「固定设计分辨率 + CSS transform scale」机制，只需极微调或已就绪 |
| **B. 需改造适配** | 6 个 | 当前为弹性布局或无固定比例，需在维持视觉语言前提下补 scale 机制或 redesign |
| **C. 建议维持现状** | 2 个 | 功能属性决定小矩形更合适，强行全屏收益低 |

**关键结论**：任务面板（tasks）之所以全屏体验最好，是因为它采用了**固定 1024×576 设计分辨率 + 整体 transform scale** 的策略——这是其他 panel 应该对齐的**标准范式**。地图（map）、商城（kshop）等面板的"黑屏割裂感"根源在于：**panel 窗口是全屏的，但内容以弹性布局松散填充，没有统一的缩放锚点**，导致大视口下元素分布稀疏、边缘留白失控。

---

## 2. 分类详评

### A. 无损全屏就绪（固定比例缩放已就绪）

这些 panel 已经采用或即将采用「固定设计分辨率 + `--*-scale` CSS 变量 + transform scale」的范式。在固定长宽比约束下，它们可以**零设计改造**地扩展到全屏，仅需工程面微调（如统一 inset、校正对齐方式）。

#### A1. tasks（任务）⭐ 标杆
- **设计分辨率**: 1024×576
- **缩放机制**: `.task-panel-scale-shell { width:1024px; height:576px; transform:scale(var(--task-scale,1)); transform-origin:top left; }`
- **JS 计算**: `updateFitScale()` 按 `Math.min(width/1024, height/576)` 动态写入 `--task-scale`
- **CSS inset**: `#panel-container[data-panel="tasks"] #panel-content { inset:0; }`（已占满全屏）
- **上线状态**: 协议接入完成（2026-05-30），待 Flash fresh trace / 端到端复核标记生产可用
- **审计意见**: **当前唯一完全达标的 panel**。事件日志的 BALDR SKY 风任务树图表视图（chart view）内建了 100%/50%/25% 缩放控件，进一步证明固定画布 + 外部 scale 是正确路线。

#### A2. stage-select（选关）
- **设计分辨率**: 1024×576（从 `StageSelectData` manifest 动态读取，支持多帧尺寸）
- **缩放机制**: `_stageEl.style.transform = 'translate(-50%,-50%) scale(' + scale + ')'`，`scale = Math.min(rect.width/DESIGN_W, rect.height/DESIGN_H)`，clamp 到 `[0.45, maxScale]`
- **CSS inset**: 当前 `inset: 2% 1.5%`（非全屏，四周有边距）
- **上线状态**: 生产可用（Stage 2 runtime，含 FFDec 视觉审计链）
- **审计意见**: **缩放机制已完备，只需将 CSS inset 从 `2% 1.5%` 改为 `0`** 即可无损全屏。Stage 内部以 transform 居中，无视觉副作用。

#### A3. team（战队 = pet + merc）
- **设计分辨率**: 1024×576（pet 与 merc 各自独立）
- **缩放机制**:
  - pet: `.pet-scale-shell { width:1024px; height:576px; transform:scale(var(--pet-scale,1)); transform-origin:center center; position:absolute; top:50%; left:50%; margin:-288px 0 0 -512px; }`
  - merc: `.merc-scale-shell` 同构
- **壳层**: `team-host { position:absolute; inset:0; }`，tab 条注入子视图 header 槽位
- **上线状态**: 生产可用
- **审计意见**: **已就绪**。战队壳层的"薄协调器"设计（不渲染独立顶栏，tab 条嵌入子视图）本身就是为避免二次缩放损失空间。固定比例 + 全屏 inset 与当前行为一致。

#### A4. intelligence（情报）
- **设计分辨率**: 1180×790
- **缩放机制**: `updateFitScale()` 计算 `--intel-scale`，`fitPanelToParent()` 保持 `DESIGN_WIDTH/DESIGN_HEIGHT` 比例，panel 宽高按比例收敛于父容器
- **上线状态**: 生产可用
- **审计意见**: **已就绪**。情报面板的 H5 组件树渲染 + 字体矩阵已经在固定画布空间内设计，scale 机制完整。

---

### B. 需改造适配（弹性布局 → 固定比例 + scale）

这些 panel 当前采用弹性布局（flex/grid/auto-fill）或无固定比例填充，在"固定长宽比 + 全屏"约束下会出现元素分布失控、留白不均、文字过大/过小等问题。需要在维持视觉语言（Cyberpunk 2077 战术风 / 军事简报风）的前提下，补入固定设计分辨率 + scale 机制。

#### B1. map（地图）⚠️ 最高优先级
- **当前布局**: 弹性 flex row，左侧 `.map-stage-shell`（`max-width:1380px`）+ 右侧 `.map-rail-shell`
- **缩放机制**: 无全局固定比例。`syncStageLayout()` 按 activePage 尺寸和可用空间计算 `_stageScale = Math.min(widthScale, heightScale, STAGE_MAX_SCALE=1.3)`，仅作用于 stage 内部 canvas/DOM 层
- **割裂感来源**:
  1. `max-width:1380px` 在大视口（如 1920×1080）下 stage 仅占宽度 72%，两侧留白
  2. 右侧 rail 固定逻辑宽度，不会随视口等比缩放
  3. stage 与 rail 的相对比例随视口变化，没有统一锚点
- **改造方案**（三选一，推荐方案一）：
  - **方案一：固定设计分辨率 + 全局 scale（推荐）**
    - 选定统一设计分辨率（建议 1600×900 或 1920×1080，覆盖最大页 base/faction/defense/school）
    - 将整个 `.map-panel` 包入 `.map-panel-scale-shell`（类似 task-panel）
    - stage、rail、header 全部在固定像素空间内设计，通过 `--map-scale` 统一缩放
    - 优点：彻底消除割裂感，所有元素比例恒定；与任务面板范式一致
    - 成本：**高** — 需要重新计算所有热点坐标、avatar 槽位、filter 按钮位置；canvas renderer 需要适配 scale 后的坐标系；max-width 逻辑需废除
  - **方案二：stage 填满 + rail 可折叠**
    - 去掉 `max-width:1380px`，stage 填满可用宽度
    - rail 改为可折叠/浮动，hover 时展开
    - 保持现有弹性布局，但减少留白
    - 优点：改动面小，不需要重算坐标
    - 缺点：不服从"固定长宽比"约束，大屏幕上元素仍会被拉伸；与审计目标不一致
  - **方案三：维持现状 + 降低预期**
    - 接受地图作为"有边距的全屏 panel"
    - 仅微调 padding/gap 让视觉更紧凑
    - 不推荐，与用户诉求相悖
- **成本评估**: 方案一约 **3-5 人日**（含坐标重算、canvas 适配、QA 回归）
- **上线状态**: 生产可用

#### B2. kshop（K点商城）
- **当前布局**: 弹性 `display:flex; flex-direction:column; height:100%`
  - body: `display:flex; flex:1`
  - grid: `grid-template-columns:repeat(auto-fill, minmax(200px,1fr))`（列数随宽度变化）
  - sidebar: 固定 `width:270px; min-width:220px`
- **缩放机制**: 无
- **问题**: 全屏下 grid 列数会随宽度增加（200px minmax → 大视口下可能出现 8-10 列），卡片被拉宽；sidebar 固定宽度在超大视口下显得过窄
- **改造方案**:
  - 固定设计分辨率（建议 1280×720 或 1440×810）
  - 将 grid 改为固定列数（如 4 列或 5 列），卡片固定尺寸
  - sidebar 改为固定像素宽度（如 300px）
  - 整体包入 scale-shell，`--kshop-scale` 统一缩放
  - 维持 cyberpunk 卡片风格、scanline、斜切角语言
- **成本评估**: **1-2 人日**（布局重排 + CSS 调整，无复杂坐标计算）
- **上线状态**: 生产可用

#### B3. arena（竞技场）
- **当前布局**: 需要确认。PanelLayoutCatalog 已将其设为 **小矩形 1024×720**（`ScalePanelSize(1024, 720)` 居中）
- **缩放机制**: `arena-panel.js` 中无显式 DESIGN_W/H 或 scale 逻辑。需确认 CSS 中 `.arena-panel` 是否有 scale 应用
- **问题**: 如果 CSS 无 scale，当前小矩形在大视口下会被物理放大（因为 PanelLayoutCatalog 的 ScalePanelSize 是按 `anchor.Height/576` 缩放的，但 Web 内容本身不感知 scale）
- **改造方案**:
  - 确认 CSS 中是否已有 `--arena-scale` 或类似机制
  - 如无，补入固定 1024×720 + transform scale 机制
  - 将 PanelLayoutCatalog 中 arena 改为全屏（`return anchorScreenRect;`），让 Web 端自主缩放
  - 或保持小矩形但确保 Web 端按 panelRect 正确 scale
- **成本评估**: **0.5-1 人日**（如已有部分机制）或 **1-2 人日**（如从零补）
- **上线状态**: 生产可用

#### B4. lockbox（开锁小游戏）
- **当前布局**: 复杂多层游戏界面，弹性 flex/grid 混合
- **CSS inset**: `#panel-container[data-panel="lockbox"] #panel-content { inset:1.2% 1.6%; }`
- **缩放机制**: 需要确认 `lockbox-panel.js` 中是否有固定比例 scale
- **问题**: 游戏网格、trace rail、buffer slot 等元素位置敏感，弹性布局下大视口会导致游戏区域过度拉伸，影响操作精度
- **改造方案**:
  - 固定设计分辨率（建议 1280×720，覆盖当前最复杂布局）
  - 游戏核心区域（grid-shell、trace rail）固定像素定位
  - UI chrome（header、help panel）随 scale-shell 缩放
  - 维持当前 cyberpunk 游戏风格（trace frame、cell selected 发光、result card 动效）
- **成本评估**: **2-3 人日**（游戏布局重排，需确保 hit-test 和动画在 scale 后正确）
- **上线状态**: 生产可用

#### B5. pinalign（定位小游戏）
- **当前布局**: 相对简单的定位游戏
- **CSS inset**: `#panel-container[data-panel="pinalign"] #panel-content { inset:1.2% 1.4%; }`
- **缩放机制**: 待确认
- **改造方案**: 固定分辨率（建议 800×600 或 1024×576）+ scale-shell
- **成本评估**: **0.5-1 人日**
- **上线状态**: 生产可用

#### B6. gobang（五子棋小游戏）
- **当前布局**: 棋盘游戏
- **PanelLayoutCatalog 目标**: 720×720（注释中，未启用）
- **缩放机制**: 待确认
- **改造方案**: 棋盘天然适合固定正方形分辨率（如 720×720 或 800×800）+ scale
- **成本评估**: **0.5-1 人日**
- **上线状态**: 生产可用

---

### C. 建议维持现状（功能属性决定小矩形更合适）

#### C1. jukebox（BGM 点歌器）
- **当前状态**: PanelLayoutCatalog 已启用小矩形 880×620（`ScalePanelSize` 按高度比例缩放）
- **CSS**: `jukebox/jukebox-panel.js` 使用百分比/弹性布局，与 panelRect 大小解耦
- **功能属性**: 非核心游戏 loop，纯粹的音乐列表浏览。展开内容量有限，不需要全屏
- **审计意见**: **维持小矩形**。强行全屏会导致列表区域过度拉伸、大量无意义留白。当前设计已是 Phase 5 优化后的合理状态。

#### C2. help（帮助系统）
- **当前状态**: PanelLayoutCatalog 全屏（`return anchorScreenRect`），注释中预留 720×540 小矩形
- **布局**: Markdown 渲染 + 文本为主
- **功能属性**: 信息查阅，非交互密集型
- **审计意见**: **建议改为小矩形 + 保持弹性**。帮助内容以文字为主，弹性布局对长文本阅读更友好。固定比例反而可能导致文字过大或过小。可启用 PanelLayoutCatalog 中注释的 `Centered(anchorScreenRect, 720, 540)`，让 Web 端保持自然流式布局。

---

## 3. 工程面统一改造规范

为避免各 panel 各自为战、scale 机制碎片化，建议统一以下规范：

### 3.1 标准 Scale-Shell 范式（所有 B 类 panel 必须遵循）

```css
/* 以 kshop 为例 */
.kshop-panel-scale-shell {
    width: 1280px;          /* 固定设计分辨率宽度 */
    height: 720px;          /* 固定设计分辨率高度 */
    transform: scale(var(--kshop-scale, 1));
    transform-origin: center center;  /* 或 top left，按视觉需求 */
    position: absolute;
    top: 50%; left: 50%;
    margin: -360px 0 0 -640px;  /* -H/2, -W/2 */
}
```

```js
// JS 统一计算（所有 panel 复用同一模式）
function updateFitScale(designW, designH, el, cssVarName) {
    var width = el.clientWidth || el.offsetWidth || 0;
    var height = el.clientHeight || el.offsetHeight || 0;
    if (!width || !height) return;
    var scale = Math.min(width / designW, height / designH);
    if (!isFinite(scale) || scale <= 0) scale = 1;
    el.style.setProperty(cssVarName, scale.toFixed(4));
}
```

### 3.2 PanelLayoutCatalog 统一策略

| panel | 建议 Catalog 行为 | 理由 |
|-------|------------------|------|
| tasks | `return anchorScreenRect;` | 已就绪，保持全屏 |
| stage-select | `return anchorScreenRect;` | 缩放就绪，只需 CSS inset:0 |
| team | `return anchorScreenRect;` | 已就绪 |
| intelligence | `return anchorScreenRect;` | 已就绪 |
| map | `return anchorScreenRect;` | 改造后全屏 |
| kshop | `return anchorScreenRect;` | 改造后全屏 |
| arena | `return anchorScreenRect;` | 改造后全屏，或保持小矩形但 Web 端自主 scale |
| lockbox | `return anchorScreenRect;` | 改造后全屏 |
| pinalign | `return anchorScreenRect;` | 改造后全屏 |
| gobang | `return anchorScreenRect;` | 改造后全屏 |
| jukebox | `ScalePanelSize(880, 620)` | 维持小矩形 |
| help | `ScalePanelSize(720, 540)` | 改为小矩形，弹性文本布局 |

### 3.3 CSS `#panel-content` inset 统一

当前各 panel 的 `#panel-content` inset 不统一：
- tasks: `inset: 0`
- stage-select: `inset: 2% 1.5%`
- lockbox: `inset: 1.2% 1.6%`
- pinalign: `inset: 1.2% 1.4%`
- 默认: `inset: 4% 6%`

**建议**: 所有 A/B 类 panel（全屏类）统一为 `inset: 0`。scale-shell 的 margin 居中负责视觉边距，不需要外层再套 inset。

---

## 4. 施工优先级建议

按「用户收益 / 改造成本」排序：

| 优先级 | panel | 动作 | 预估工时 | 阻塞项 |
|--------|-------|------|---------|--------|
| **P0** | stage-select | CSS inset → 0 | 0.5h | 无 |
| **P0** | arena | 确认/补 scale 机制 | 0.5-1d | 需确认当前 CSS |
| **P1** | kshop | 固定分辨率 1280×720 + scale-shell | 1-2d | 无 |
| **P1** | map | 方案一：固定分辨率 + 全局 scale | 3-5d | 坐标重算、canvas 适配 |
| **P2** | lockbox | 固定分辨率 + scale-shell | 2-3d | 游戏 hit-test 验证 |
| **P2** | pinalign | 固定分辨率 + scale-shell | 0.5-1d | 无 |
| **P2** | gobang | 固定分辨率 + scale-shell | 0.5-1d | 无 |
| **P3** | help | 改为小矩形 720×540 | 0.5d | 无 |
| **P3** | jukebox | 维持现状 | 0 | 无 |

---

## 5. 风险与注意事项

1. **Canvas 坐标系**: map 和 lockbox 使用 Canvas 渲染，全局 scale 后需要确保鼠标 hit-test、粒子效果、动画坐标正确转换。建议在 scale-shell 上使用 `transform` 而非 `zoom`，因为 transform 不改变元素的布局尺寸（getBoundingClientRect 已含 transform），而 zoom 会影响子元素的像素计算。

2. **Tooltip 尺寸**: 当前 tooltip 单独走 `transform:scale(var(--cf7-overlay-scale))`（基于 `vpH/864`）。如果 panel 内容也做了全局 scale，需要确保 tooltip 的缩放与 panel 内容缩放解耦，避免双重缩放。

3. **DPI 与高分辨率**: 固定设计分辨率 + transform scale 在 4K 屏幕（3840×2160）下 scale 因子可能达到 2-3，文字和边框可能因过度放大而模糊。建议核心文字使用 `transform: scale()` 配合 `-webkit-font-smoothing: antialiased`，或在 scale ≥ 2 时考虑切换更高分辨率的素材。

4. **PanelHostController 焦点**: 全屏 panel 的 `ResumeForPanel` 会剥 `WS_EX_NOACTIVATE` 并 `SetForegroundWindow(this)`。如果多个 panel 快速切换，需确保 `ForceIdleState` 正确复位，避免焦点残留。

5. **Flash 背景透明**: 全屏 panel 打开时，WebOverlayForm 背景设为 Black（不透明），Flash 被遮罩。如果 map 等 panel 改造后仍希望"露出部分 Flash 背景"营造沉浸感，需要重新评估——但用户已明确"全屏最好"，此点可忽略。

---

## 6. 下一步行动

如需立即开工，建议按以下顺序执行：

1. **立刻**: 调 `stage-select` CSS inset → 0（5 分钟收益）
2. **第一轮（1-2 天）**: 完成 arena/kshop 的 scale 机制补全，确立标准范式
3. **第二轮（3-5 天）**: 攻坚 map 的全屏改造（工作量最大、用户体感提升最明显）
4. **第三轮（2-3 天）**: 收尾 lockbox/pinalign/gobang/help 的适配
5. **验证**: 每轮改造后跑对应 browser harness + 游戏内端到端手测，确保无 regression

---

*本审计基于 launcher/web 源码静态分析 + C# PanelLayoutCatalog + CSS/JS 运行时行为推断。具体施工前建议对每个 B 类 panel 的 dev/harness.html 做一轮实际视口（1024×576 / 1366×768 / 1920×1080）截图对比，验证改造前的基线状态。*
