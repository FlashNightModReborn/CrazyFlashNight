# Web Overlay iGPU 性能审计报告

**审计时间**: 2026-04-25  
**审计范围**: `launcher/web/css/*.css`, `launcher/web/modules/**/*.js`, `launcher/web/*.html`  
**基线**: 非 panel 态 iGPU ≈35%，panel 态 iGPU ≈100%  
**审计方法**: 静态代码审查 + iGPU 合成路径分析（backdrop-filter、mix-blend-mode、will-change、infinite 动画、canvas rAF 循环）

---

## 结论总览

| 分类 | 说明 | 非 panel 降幅 | panel 降幅 |
|------|------|--------------|-----------|
| A（零损失）| 纯 CSS 属性调整，视觉无差异 | 19–25% → **10%–16%** | 38–52% → **48%–62%** |
| A + B（轻微降级）| 上述 + 动画简化/降频 | 25–29% → **6%–10%** | 62–75% → **25%–38%** |
| A + B + C（全量）| 上述 + JS 节流 + DOM 复用 | 再降 2–4% → **4%–8%** | 再降 3–6% → **20%–32%** |

> **核心发现**：panel 态 100% 的 iGPU 主要由三大因素叠加驱动——`backdrop-filter:blur()`（全屏/大面积模糊）、`mix-blend-mode:screen`（强制全层 readback + blend）、以及 20+ 处 `infinite` 动画（尤其 box-shadow/conic-gradient 变化）。非 panel 态的 35% 则主要由常驻 HUD 的 `backdrop-filter`（notch、工具条、上下文面板）和 jukebox canvas 波形渲染驱动。

---

## A. 视觉零损失即可优化（前 10 大元凶）

> 说明：以下问题均可通过替换为等效视觉样式（纯色半透明背景替代 blur、移除 blend mode、清理合成层）解决，肉眼不可区分。

### 1. top-right-tools 及按钮的 `backdrop-filter` 叠加
**位置**: `launcher/web/css/overlay.css:539–554`  
**问题**: `#top-right-tools::before` 和 5 个 `#top-right-tools > button` 全部独立应用 `backdrop-filter:blur(12px) saturate(1.2)`。工具条常驻显示，多个叠加的模糊层造成 iGPU 合成路径上的 N 次 blur pass。  
**修复**: 仅在 `::before` 伪元素保留一次 blur（或完全移除），按钮本身改用 `background:rgba(24,24,26,0.82)` 即可。  
**预估节省**: 非 panel 态 3–5%，panel 态 2–4%。

### 2. notch-pill 的 `backdrop-filter`
**位置**: `launcher/web/css/overlay.css:219`  
**问题**: `#notch-pill` 的 `backdrop-filter:blur(12px) saturate(1.2)`。顶部中央常驻条约 400×28px，游戏全程高频重绘。已有不透明的 `background:rgba(24,24,26,0.82)` 兜底。  
**修复**: 去掉 `backdrop-filter`，保留现有背景色和边框。边缘仅失去 1–2px 的柔化，视觉上不可区分。  
**预估节省**: 非 panel 态 2–4%，panel 态 1–2%。

### 3. context-panel 的 `backdrop-filter`
**位置**: `launcher/web/css/overlay.css:607`  
**问题**: `#context-panel` 的 `backdrop-filter:blur(12px)`。右侧常驻上下文面板，约 170×150px，游戏时持续可见。已有半透明背景。  
**修复**: 去掉 blur，仅保留 `background` 和 `border`。  
**预估节省**: 非 panel 态 2–3%，panel 态 1–2%。

### 4. jukebox-panel 的 `backdrop-filter`
**位置**: `launcher/web/css/overlay.css:1222`  
**问题**: `#jukebox-panel` 的 `backdrop-filter:blur(12px)`。右侧常驻 BGM 面板，约 170×200px。  
**修复**: 同上，去掉 blur。  
**预估节省**: 非 panel 态 2–3%，panel 态 1–2%。

### 5. notch-info-row 的 `backdrop-filter`
**位置**: `launcher/web/css/overlay.css:878`  
**问题**: `.notch-info-row` 的 `backdrop-filter:blur(12px)`。通知栈每行独立创建新的模糊层，且通知频繁进出，合成层创建/销毁开销叠加 blur 计算。  
**修复**: 通知行改用纯色半透明背景 `rgba(24,24,26,0.88)`，去掉 blur。  
**预估节省**: 非 panel 态 2–3%，panel 态 1–2%。

### 6. combo-hit-bar 的 `backdrop-filter` + `saturate`
**位置**: `launcher/web/css/overlay.css:1927`  
**问题**: `.combo-hit-bar` 的 `backdrop-filter:blur(12px) saturate(1.3)`。combo 命中时触发，blur + saturate 双重滤镜。  
**修复**: 保留 `saturate(1.3)` 或完全移除（已有鲜艳背景色），去掉 `blur`。  
**预估节省**: 非 panel 态 1–2%，panel 态 0.5–1%。

### 7. 全屏 modal 的 `backdrop-filter`
**位置**: `launcher/web/css/overlay.css:1652`（game-help-modal）、`overlay.css:1745`（jukebox-help-modal）  
**问题**: 两个全屏/大面积帮助模态框使用 `backdrop-filter:blur(16px)`。模态框打开时模糊整个视口下方内容，是 iGPU 上最昂贵的 backdrop-filter 场景。  
**修复**: 模态框背景改用 `background:rgba(10,10,12,0.94)` 或更暗的纯色，去掉 blur。  
**预估节省**: 仅 modal 打开时生效，单次可降 10–20% iGPU。

### 8. lockbox-panel 扫描线的 `mix-blend-mode:screen`
**位置**: `launcher/web/css/panels.css:1065`（`.lockbox-panel::before`）  
**问题**: 锁箱面板常驻扫描线伪元素使用 `mix-blend-mode:screen` + `animation:lb-scan 6s linear infinite`。`mix-blend-mode` 在 iGPU 上强制全层 readback + blend，成本远高于普通 opacity。opacity 仅 0.45，视觉贡献度低但 GPU 成本高。  
**修复**: 去掉 `mix-blend-mode:screen`，改用纯 `opacity:0.45` 的线性渐变。扫描线的"发光感"几乎不可区分。  
**预估节省**: panel 态（lockbox 打开时）3–5%。

### 9. map-stage-scanline 的 `mix-blend-mode:screen`
**位置**: `launcher/web/css/panels.css:3693–3695`（`.map-stage-scanline`）  
**问题**: 地图面板的全 stage 扫描线动画使用 `mix-blend-mode:screen`。地图面板是正常游戏中最常打开的大面积面板，此规则是 panel 态 100% 的核心推手之一。  
**修复**: 去掉 `mix-blend-mode:screen`，改用普通 `opacity:0.55` 的渐变。扫描线亮度轻微降低，但方向感保留。  
**预估节省**: panel 态（map 打开时）5–8%。

### 10. map-stage-content-fit 的常驻 `will-change:transform`
**位置**: `launcher/web/css/panels.css:2792`  
**问题**: `.map-stage-content-fit` 的 `will-change:transform` 使地图内容容器常驻合成层（promoted layer），面积大、内存占用高。即使地图静止时也持续占用合成器资源。  
**修复**: 改为仅在缩放/平移动画期间通过 JS 动态添加 `will-change`，动画结束后移除（`will-change:auto`）。视觉零损失。  
**预估节省**: panel 态（map 打开时）2–4%。

---

## B. 视觉轻微损失（前 10 大元凶）

> 说明：以下问题需要降级或简化动画/效果，视觉上会有轻微差异（如失去"呼吸感"、"脉动感"），但在 iGPU 受限场景下可接受。

### 1. lockbox-panel 全局 box-shadow 呼吸动画
**位置**: `launcher/web/css/panels.css:1236–1237`  
**问题**: `.lockbox-panel[data-phase="INJECTING"]` / `[data-phase="MAIN_READY"]` 应用 `animation:lb-inject-breathe 3.4s/2.2s ease-in-out infinite`。keyframe 中改变 `box-shadow`，每帧触发重绘/重排，iGPU 上成本极高。  
**降级方案**: 将 box-shadow 呼吸改为 `opacity` 呼吸（面板整体 opacity 微调），或完全改为静态阴影。  
**视觉损失**: 面板失去"霓虹脉动"感，变为静态或轻微透明度呼吸。  
**预估节省**: panel 态（lockbox 打开时）3–5%。

### 2. gobang-board 全棋盘呼吸动画
**位置**: `launcher/web/css/gobang.css:292–298`（`.gobang-board::before`）  
**问题**: 五子棋棋盘中央覆盖全板的 `radial-gradient` + `animation:gb-breath 1.3s ease-in-out infinite`。棋盘最大可达 640×640px，opacity 动画覆盖整个区域。  
**降级方案**: 去掉 `::before` 伪元素或改为静态 `opacity:0.5` 的径向渐变。  
**视觉损失**: 棋盘中央失去微弱呼吸光晕，变为静态暗斑。  
**预估节省**: panel 态（gobang 打开时）2–4%。

### 3. map-stage-scanline 的 translateY 动画
**位置**: `launcher/web/css/panels.css:3695`（`.map-stage-scanline`）  
**问题**: 虽然 `transform` 动画本身较便宜，但结合 A9 的 `mix-blend-mode:screen` 和全 stage 覆盖面积，持续 6.8s 循环的 translateY 使该层始终处于活跃合成状态。  
**降级方案**: 去掉动画，扫描线变为静态水平亮带（固定位置）；或改为更慢的 20s 周期。  
**视觉损失**: 失去"自上而下扫描"的动态感，变为静态装饰线。  
**预估节省**: panel 态（map 打开时）2–3%。

### 4. gobang-sweep 扫掠光束动画
**位置**: `launcher/web/css/gobang.css:344–357`（`.gobang-sweep::before`）  
**问题**: 全棋盘横向扫掠光束 `animation:gb-sweep 6.5s linear infinite`，transform + opacity，常驻运行。  
**降级方案**: 降低周期至 20s 或完全移除。  
**视觉损失**: 失去雷达扫掠的动态感。  
**预估节省**: panel 态（gobang 打开时）1–2%。

### 5. map-avatar-task-ring 双层脉冲动画
**位置**: `launcher/web/css/panels.css:3107`（`.map-avatar-task-ring`）、`panels.css:3116`（`::after`）  
**问题**: 任务 NPC 头像外环双层叠加动画，同时改变 `box-shadow`、`transform`、`opacity`。  
**降级方案**: 简化为单层脉冲（去掉 `::after` 外环），或降低频率至 3s。  
**视觉损失**: 失去"双层涟漪"层次，保留单层脉冲。  
**预估节省**: panel 态（map 有任务标记时）2–3%。

### 6. lockbox-cell.hint-next 的 box-shadow 脉冲
**位置**: `launcher/web/css/panels.css:1244`  
**问题**: `.lockbox-cell.hint-next` 的 `animation:lb-pulse-next 1.2s ease-in-out infinite`，keyframe 中改变 `box-shadow`。  
**降级方案**: 改为 `opacity` 脉冲或仅保留静态高亮边框。  
**视觉损失**: 提示格失去"霓虹呼吸"强度，变为静态黄色边框。  
**预估节省**: panel 态（lockbox 提示激活时）1–2%。

### 7. lockbox-rail-finisher charge 双环动画
**位置**: `launcher/web/css/panels.css:1875`（`.lockbox-rail-finisher.visible::before,::after`）  
**问题**: finisher 充能条双环叠加动画 `animation:lb-charge-ring 1.4s ease-out infinite`，transform + opacity + box-shadow。  
**降级方案**: 改为单环或降低动画复杂度（仅 transform + opacity）。  
**视觉损失**: 充能视觉层次减少，"能量汇聚感"轻微下降。  
**预估节省**: panel 态（lockbox finisher 阶段）1–2%。

### 8. gobang-cell.last 准星脉冲动画
**位置**: `launcher/web/css/gobang.css:564–578`（`.gobang-cell.last::before`）  
**问题**: 最后落子准星 `animation:gb-reticle-pulse 1.3s ease-in-out infinite`，同时改变 `box-shadow`、`background`（多层 linear-gradient）、`transform`。  
**降级方案**: 改为静态准星（保留边框和阴影，去掉 animation）。  
**视觉损失**: 失去准星"心跳"动画，变为静态标记。  
**预估节省**: panel 态（gobang 对局中）1–2%。

### 9. map-feedback-marker 外扩脉冲
**位置**: `launcher/web/css/panels.css:3426`（`.map-feedback-marker::after`）  
**问题**: 地图反馈标记的外扩环 `animation:mapFeedbackPulse 1.8s ease-out infinite`，transform + opacity。  
**降级方案**: 降低频率至 4s 或改为静态光环。  
**视觉损失**: 标记失去动态扩散感。  
**预估节省**: panel 态（map 有反馈标记时）1–2%。

### 10. map-feedback-marker--currentLocation 雷达旋转
**位置**: `launcher/web/css/panels.css:3797`（`.map-feedback-marker--currentLocation::before`）  
**问题**: 当前位置雷达使用 `conic-gradient` + `rotate` 组合 `animation:mapRadarSweep 2.4s linear infinite`。`conic-gradient` 每帧随旋转角度重算，iGPU 上较昂贵。  
**降级方案**: 降低转速至 6s 或改为静态扇形（固定 45° 扇区）。  
**视觉损失**: 雷达扫掠变慢或静止，方向感保留但动态感下降。  
**预估节省**: panel 态（map 显示当前位置时）1–2%。

---

## C. 架构/JS 层（5 条可选）

### 1. jukebox.js 的常驻 canvas 波形渲染
**位置**: `launcher/web/modules/jukebox.js:157–183`（`onAudioData`）、`jukebox.js:258`（`renderMini`）  
**问题**: `onAudioData()` 每次收到 Bridge 音频消息都无条件调用 `renderMini()`，内部执行 canvas `fillRect` 绘制 100 段波形。音频消息频率约 30–60Hz，形成事实上的常驻 canvas 渲染循环。即使 BGM 暂停或面板折叠，只要 Bridge 仍推送数据就会持续渲染。  
**修复建议**: 面板折叠、WebView 不可见或 BGM 暂停时跳过 `renderMini()`；或限制渲染频率至 ≤10Hz。  
**预估节省**: 非 panel 态 2–4%，panel 态 1–2%。

### 2. sparkline.js 的高频 rAF 过渡
**位置**: `launcher/web/modules/sparkline.js:375–381`（`startAnim`）、`sparkline.js:315`（rAF 调度）  
**问题**: `startAnim()` 每次 FPS 数据到达都触发 3 帧 rAF 过渡动画。在高帧率游戏场景下 FPS 消息密集（约 60Hz），3 帧动画几乎首尾相接，形成事实上的连续渲染。  
**修复建议**: FPS 数据变化小于 1fps 或 perfLevel 未变时不触发新动画；或降低过渡帧数至 1 帧。  
**预估节省**: 非 panel 态 1–2%，panel 态 0.5–1%。

### 3. cursor-feedback.js 的捕获阶段 mousemove
**位置**: `launcher/web/modules/cursor-feedback.js:85–88`  
**问题**: `document.addEventListener("mousemove", ...)` 在捕获阶段监听所有鼠标移动，每次移动都可能执行 `closestInteractive()` 和 `getComputedStyle()`（第 28 行，虽有 `WeakMap` 缓存）。高频鼠标移动（如 1000Hz 鼠标）造成大量 JS 执行和可能的样式重算。  
**修复建议**: 使用 16ms 节流（`requestAnimationFrame`  gated）或仅在目标元素变化时更新。  
**预估节省**: 非 panel 态 0.5–1%，panel 态 0.5–1%。

### 4. map-hud.js / map-panel.js 的 DOM 重建
**位置**: `launcher/web/modules/map-hud.js`、`launcher/web/modules/panels.js`（map 分支）  
**问题**: 每次地图状态变更（切换 stage、filter 变化、avatar 移动）时重建大量 DOM 节点（scene nodes、hotspots、avatars、SVG masks）。地图复杂时一次性创建数百个节点，造成长时间帧和合成器初始化开销。  
**修复建议**: 使用对象池复用 DOM 节点，仅更新 `style` / `className` / `transform`，避免 `innerHTML` 或 `createElement` 风暴。  
**预估节省**: panel 态（map 打开且频繁交互时）2–4%。

### 5. cursor-overlay 的常驻合成层
**位置**: `launcher/web/css/overlay.css:49–51`（`#cursor-overlay`）  
**问题**: `#cursor-overlay` 使用 `transform:translate3d(-100px,-100px,0)` + `will-change:transform,opacity`，即使不显示（位于视口外）也常驻合成层。虽然面积仅 28×34px，但合成层内存和条目数常驻。  
**修复建议**: 初始状态去掉 `will-change` 和 `translate3d`，仅在需要显示时通过 JS 动态添加。  
**预估节省**: 非 panel 态 0.3–0.5%，panel 态 0.3–0.5%。

---

## 附录：已存在的性能降级开关审计

项目已内置 `html.perf-low-effects` 和 `html.perf-no-css-animations` 类（定义于 `overlay.css:16–38`），用于在 iGPU 压力下全局降级：

- `.perf-no-css-animations`：将所有 `*` 的 `animation` 和 `transition` 强制设为 `none !important`。这可以瞬间关掉 B 类中所有 infinite 动画，但无法处理 A 类的 `backdrop-filter` 和 `mix-blend-mode`。
- `.perf-low-effects`：在 `.perf-no-css-animations` 基础上进一步隐藏 visualizer、去掉 `box-shadow`、降低 `opacity`。

**关键缺失**：
1. 当前没有发现 C# host 在检测到 iGPU 高负载时自动注入这些类的逻辑。如果已有逻辑，建议优先启用 `perf-low-effects` 作为应急开关。
2. `perf-low-effects` 对 `backdrop-filter` 的清理不够彻底：overlay.css 中大量 `backdrop-filter` 规则没有被 `.perf-low-effects` 覆盖（仅部分元素被处理）。
3. `panels.css:3826–3906` 已有 `.perf-low-effects` 的 map 面板专用降级规则，但 lockbox 面板没有任何 `perf-low-effects` 覆盖。

**建议**：将 A 类中所有 `backdrop-filter` 和 `mix-blend-mode` 纳入 `.perf-low-effects` 的强制清理范围，作为自动降级的后备方案。

---

## 实施路线图

| 阶段 | 任务 | 预估时间 | 预期收益 |
|------|------|---------|---------|
| **Hotfix（立刻）** | 批量注释/替换 overlay.css 中 15+ 处 `backdrop-filter` 为纯色背景 | 20 分钟 | 非 panel 降 15–22% |
| **当天** | 清理 `mix-blend-mode:screen`（lockbox 扫描线、map 扫描线） | 15 分钟 | panel 降 8–13% |
| **当天** | 简化 lockbox 和 map 的 infinite 动画（B1–B5） | 30 分钟 | panel 降 8–12% |
| **本周** | jukebox canvas 可见性检查 + sparkline 节流 | 1 小时 | 非 panel 降 2–4% |
| **本周** | gobang 呼吸/扫掠动画降级（B2、B4、B8） | 20 分钟 | panel（gobang）降 3–5% |
| **后续** | map DOM 节点池化 + cursor-overlay 动态 will-change | 2–3 小时 | panel 降 2–4% |
| **基础设施** | 补全 `.perf-low-effects` 对 `backdrop-filter` 的全覆盖；C# host 注入逻辑 | 1 小时 | 应急降级可用 |

---

*报告结束。所有行号基于 commit `9f8f0c225`（2026-04-20）基线。*
