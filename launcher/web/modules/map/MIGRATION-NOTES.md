# Map Panel Refactor — DOM 接管 + 像素级 hittest（2026-05 完工）

## Plan C 修订 (2026-05-26)

完工后实战发现：非 hierarchy 模式稳态下 sceneVisual 全隐藏 + 只剩 backdrop + 头像散落，玩家无法通过可视化定位意图前往的区域。决策回到原版 4 档状态机（pre-refactor drawScene 同款），dimmer 退役。具体见 §11 Plan C。

## 背景

重构前架构：单个 `MapCanvasStageRenderer` 全程驱动三画布（bg / ring / fg），hover 触发 alpha tween 把 `staticAnimating=true`，~140ms 内每帧重画所有 sceneVisual + avatar — panel-map 场景 iGPU 主要热点。命中用矩形 `.map-hotspot` button，被前景遮盖的小区块难选中，与 Flash 原版"PNG alpha 形状命中"不一致。

## 5 个 phase 的层次结构变更

```
.map-stage-frame[data-page-id="..."]
├── canvas#map-stage-canvas           z=2  pointer-events:none
│       bg layer: backdrop 烤底 + 异常层 + (hierarchy) muted 底图
├── .map-stage-dimmer                 z=2  pointer-events:none  NEW (Phase 1B)
│       半透明黑, opacity 0→0.35 transition; 压暗 bg canvas 含 anomaly
├── canvas#map-stage-canvas-ring      z=3  pointer-events:none  (任务环, 不被 dimmer 压暗)
├── #map-stage-content-fit            z=4  transform: translate3d+scale
│   ├── .map-scene-visual-layer       NEW (Phase 1B) pointer-events:none
│   │     └── <div class="map-scene-visual"> × N
│   │           ├── <div class="map-scene-visual-plate">    z=0
│   │           ├── <img class="map-scene-visual-img">      z=1
│   │           └── <div class="map-scene-visual-glow">     z=2
│   ├── .map-avatar-layer             NEW (Phase 2) pointer-events:none
│   │     └── <div class="map-avatar"> × N
│   │           └── <img class="map-avatar-img">
│   ├── .map-hotspot-layer            z=3  (button DOM, pointer-events:none — Phase 1A)
│   │     └── <button class="map-hotspot">  (Tab focus + aria 保留, 无视觉装饰)
│   ├── .map-hotspot-hitcapture       z=4  pointer-events:auto  NEW (Phase 1A)
│   │     (唯一鼠标命中层, 像素级 alpha hittest)
│   └── .map-hotspot-label-layer      z=5  (卡片层, 不动)
└── canvas#map-stage-canvas-fg        z=6  pointer-events:none  (反馈/提示, 不被 dimmer 压暗)
```

## 模块新增

| 文件 | Phase | 职责 |
|------|-------|------|
| `modules/map/map-hittest-engine.js` | 0 | 整页一张 1031×608 hitmap，每 visual 用 ID-color 二值化写入；query 返回 `{visualId, hotspotIds, filterIds}`。alpha 阈值 32，坐标 Math.round + Math.ceil 铁律。 |
| `modules/map/map-hotspot-hitcapture.js` | 1A | 唯一鼠标命中代理层；pointermove rAF 节流 → hit 变化时显式 `BootstrapAudio.playHover()`；pointerdown/up 双重验证保护 click cue；pointercancel/contextmenu/pointerleave 全清理。 |
| `modules/map/map-scene-visual-layer.js` | 1B | sceneVisual 整页全量建 DOM (filter-independent)；syncState 按 hover/current/filter/hierarchy 切 `.is-visible/.is-current/.is-focus`；返回 `domVisibleVisualIds` 喂 canvas 跳过钩子。 |
| `modules/map/map-avatar-layer.js` | 2 | 静态 + 动态头像统一 DOM 层 (`<div.map-avatar><img>`)；syncPage 内置 fingerprint 防 filter 切换闪烁；fallback 字符走 `::after content:attr(data-fallback)`。 |

## 关键设计决策

### 1. 像素级 hittest (Phase 0)

- 每页一张 OffscreenCanvas (回退 HTMLCanvasElement)，dpr=1
- Uint32Array 二值化：alpha > 32 写纯 ID-color，避免 source-over 染色
- 后 visual 覆盖前 visual（与 drawScenes z 顺序一致）
- 坐标契约：临时 canvas `Math.ceil(rect.w/h)`，主 hitmap 偏移 `Math.round(rect.x/y)`，query `Math.round(pageX/Y)`
- 必须传整页 `page.sceneVisuals` 给 `ensurePage` (filter 过滤在 query 后由调用方做)，否则切 filter 后缺图

### 2. hitcapture click 安全语义 (Phase 1A)

| 步骤 | 行为 |
|------|------|
| pointerdown 命中 + enabled + 非busy | 临时设 `data-audio-cue=transition`，记 `pendingNavigateId` |
| pointerup 同位 | 保留 attr → click capture 代理播 transition cue |
| pointerup 异位 (拖到透明区) | removeAttribute → 代理看不到 attr → 不播 cue + onClick(id) 也不 navigate |
| pointercancel / contextmenu (右键) / pointerleave | 全清理 |

### 3. 音效路径 (Phase 1A 关键修正)

- **hover cue**：hitcapture 在 hit null→非null 时**显式** `BootstrapAudio.playHover()`，**不依赖** `overlay-audio-bindings.js` 的 mouseover 代理（因 `.map-hotspot` 已 `pointer-events:none`，mouseover 不再命中 button）
- **click cue**：仍走 `overlay-audio-bindings.js` 的 click capture 代理；attr 只在 pointerdown→pointerup 同位窗口内存在
- **键盘 Tab + Enter**：浏览器在 focus 的 `.map-hotspot` button 上派发 click，button 自身 `data-audio-cue="transition"` 属性永远在，照常播 transition cue

### 4. canvas 双钩子短路 (Phase 1B)

- `drawScenes` 入口：`if (state.skipDomScenes) return` — 非 hierarchy 模式整层短路
- `drawScene` 入口：`if (state.canvasSkipVisualIds.indexOf(scene.id) >= 0) return` — hierarchy 模式跳过 DOM 已显示的 focus visual，防止 plate/glow 双绘
- canvas 实际渲染分支：
  - 非 hierarchy：sceneVisuals **0 张**（全部 DOM）
  - hierarchy：muted 底图 (除 focus 外的所有 visuals)，DOM 显 focus 那一张

### 5. dimmer overlay (Phase 1B)

- `.map-stage-dimmer` 与 bg canvas 同 z=2，DOM 顺序在后 → 显示其上；ring canvas (z=3) 不被覆盖
- `hasFocusDim = !hierarchy && !!hoverHotspotId` — 仅非 hierarchy + 有 hover 触发
- opacity 0→0.35，140ms cubic-bezier(0,0,0.2,1) 过渡
- **接受 anomaly 一起被压暗**（因 anomaly 画在 bg canvas，dimmer 必然覆盖）— 产品决策

### 6. hierarchy 模式的双绘防护 (Phase 1B 关键)

- `MapSceneVisualLayer.syncState` 返回 `domVisibleVisualIds`（只含 DOM 实际 visible 的）
- `buildCanvasRenderState` 把它喂 `canvasSkipVisualIds` 字段
- `drawScene` 入口 `indexOf` 短路
- 结果：hierarchy 模式下任一 visual 要么由 DOM 画 (focus)，要么由 canvas 画 (muted 底图)，**永远不会双绘**

### 7. avatar 迁移 (Phase 2)

- 静态 + 动态头像统一 `<div.map-avatar>` wrapper
- `syncPage(page, slots)` 内部用 fingerprint (slot id/kind/assetUrl/hotspotId/rect 拼串) 防 filter 切换闪烁
- 动态头像 URL 在 syncPage 时一次性解析；roommateGender 变化 → applyPage → syncPage → fingerprint 不同 → 重建
- focus / muted 视觉对齐 canvas `drawAvatar`：scale 1.04、lift -1px、box-shadow 加亮/降饱和

### 8. 视觉装饰彻底清除 (Phase 2)

砍除 `.map-hotspot` 全部矩形装饰：
- `:hover`、`:focus`、`.is-hover`、`.is-busy`、`.is-current`、`.is-muted`、`.is-relation` 样式块
- `::before` 四角靶标括号
- `::after` busy 发射环
- `.map-hotspot-sheen` 高光层
- `@keyframes mapHotspotTargeting` / `mapHotspotBusyWave`

保留：
- `pointer-events:none` (Phase 1A)
- `:focus-visible` outline (键盘 a11y)
- `:disabled` cursor

### 9. canvas 死代码清理 (Phase 3)

- 删 `drawAvatars` / `drawAvatar` (Phase 2 后无 caller)
- 删 `drawSceneGlow` (Phase 3 drawScene 简化后无 caller)
- 删 `fallbackChar` (仅 drawAvatar 用)
- 删 `hasAny` / `hasBusy` (drawScene 简化后无用)
- `buildStaticRenderKey` 删 `staticAvatars` / `dynamicAvatars` 签名字段 — **这是消除 hover→avatar tween→renderStatic 重画的最后路径**
- `drawScene` 简化：硬编码 hierarchy muted 值 (alpha 0.74, bri 0.74, sat 0.8)，删除 focus/muted/transform 死分支

### 10. 已决策保留：sharpen worker

`MapCanvasStageRenderer` 的 sharpen worker (modules/workers/sharpen-worker.js + ensureSharpenWorker/loadSharpenedImage) **保留**。理由：
- hierarchy 模式 canvas 仍绘制 muted 底图，sharpen 仍生效
- 非 hierarchy 模式 canvas 不画 scene → sharpen 自然不触发
- 真机测试未发现退化，无紧迫退役理由

## 关键文件路径

### 模块
- [map-hittest-engine.js](map-hittest-engine.js)
- [map-hotspot-hitcapture.js](map-hotspot-hitcapture.js)
- [map-scene-visual-layer.js](map-scene-visual-layer.js)
- [map-avatar-layer.js](map-avatar-layer.js)

### 关键改动主战场
- [map-panel.js](../../map-panel.js) — DOM 注入、layer mount/syncPage/syncState 接线
- [map-canvas-stage-renderer.js](../../map-canvas-stage-renderer.js) — drawScenes/drawScene 短路、buildStaticRenderKey、updateDrawSummary
- [panels.css](../../../css/panels.css) — `.map-scene-visual*` / `.map-stage-dimmer` / `.map-avatar*` 新增；`.map-hotspot::before/::after/.sheen` 删除

### QA 用例
- ui31a-d (Phase 0) — pixel hittest engine 边缘/重叠/filter/坐标边界
- ui32a-c (Phase 1B) — DOM scene 层非 hierarchy 短路 / hierarchy 双绘防护 / current+hover 不同位 + dimmer
- ui6 / ui10 / ui22 (Phase 2) — 头像断言迁到 `state.avatarLayer.{staticVisibleCount, currentDynamicAvatarUrl}`

## 不动的边界（铁律）

- `.map-hotspot-overlay-label` 卡片层（DOM + CSS + hover bridge）
- canvas-stage-renderer：backdrop / ring canvas / fg canvas / 反馈 markers/tips/hints / retune / pageEnter / reduceMotion
- `_hotspotStateLookup` / `_enabledLookup` / `_unlockFlags`
- `aria-label` / `aria-disabled` / `aria-busy`
- focus/blur → setHotspotHover 链路（键盘等价）
- 任务环 (taskRings) 仍由 ring canvas 渲染，套住 DOM avatar 中心

## 性能数据

| 指标 | baseline | Phase 1B | Phase 2 | Phase 3 |
|------|----------|----------|---------|---------|
| ui1 canvasDraws | 4 | 2 | 2 | 2 |
| 真机 iGPU "3D" 估值 | ~60-80% | ~40-55% | ~30-40% | 同 Phase 2 |
| canvas drawSummary.staticAvatarCount | 真实头像数 | 真实头像数 | 永远 0 | 永远 0 |

## 回滚边界

- Phase 0/1A 完全可独立回滚（0 视觉变化）
- Phase 1B/2 关联强 (avatar 与 scene 共用 dimmer 假设)；建议捆绑回滚
- Phase 3 是清理，回滚需重新启用 drawAvatars/drawSceneGlow + buildStaticRenderKey 字段 + 4-branch 分支
- Plan C 回滚需恢复 `skipDomScenes` 字段 + drawScene hierarchy-only 硬编码 + dimmer toggle

---

## 11. Plan C — 状态机回归 + dimmer 退役 (2026-05-26)

### 触发问题

非 hierarchy 模式 (绝大多数浏览场景) 稳态视觉：
- `drawScenes` 入口 `skipDomScenes` 整层短路 → canvas 不画 scene
- DOM scene layer 只在 isFocus 时显示
- 结果：稳态地图只剩 backdrop + 散落的头像，玩家无法可视化定位想去哪个区域

### 决策

回到 pre-refactor [bff839013 drawScene line 1116-1141](https://example/...) 的 4 档状态机：

| 状态 | alpha | bri | sat | 视觉 |
|------|-------|-----|-----|------|
| 稳态 (无 focus) | 1.0 | 1.0 | 1.0 | 全原色 |
| 有 focus，本 visual 不含 focus hotspot | 0.42 | 0.58 | 0.7 | 深 muted |
| hierarchy 模式 (非 focus) | 0.74 | 0.74 | 0.8 | 中度 muted |
| isFocus | — | — | — | 由 DOM scene layer 画 lift+glow，canvas 跳过 |

canvas 全模式都画 scene；`canvasSkipVisualIds`（DOM 已显示的 focus visualId）仍是双绘防护单一职责，跳过 DOM focus 那张即可。

### dimmer 退役

- `.map-stage-frame.has-focus-dim` toggle 删除（`MapSceneVisualLayer.syncState` 不再调）
- `.map-stage-dimmer` DOM 元素 + 基础 styles 保留 (`opacity:0` 永远生效)，留 future 改回路径
- `.has-focus-dim .map-stage-dimmer { opacity:0.35 }` CSS rule 删除
- 焦点压暗改由 canvas per-scene muted (0.42/0.58/0.7) 提供 → 副作用：anomaly 不再被一起压暗（原方案因 anomaly 在 bg canvas 接受被压暗，Plan C 解除）

### 改动文件

| 文件 | 改动 |
|------|------|
| [map-canvas-stage-renderer.js drawScene](../../map-canvas-stage-renderer.js) | 恢复 4 档状态机（替换 hierarchy-only 硬编码） |
| [map-canvas-stage-renderer.js drawScenes](../../map-canvas-stage-renderer.js) | 删 `if (state.skipDomScenes) return` 短路 |
| [map-canvas-stage-renderer.js buildStaticRenderKey](../../map-canvas-stage-renderer.js) | 删 `state.skipDomScenes ? 'S' : ''` 签名字段 |
| [map-canvas-stage-renderer.js updateDrawSummary](../../map-canvas-stage-renderer.js) | 删 `skipDomScenes` 输出字段 + 简化 scenePaintedCount |
| [map-panel.js buildCanvasRenderState](../../map-panel.js) | 删 `skipDomScenes` 计算 + 字段 |
| [map-scene-visual-layer.js syncState](map-scene-visual-layer.js) | 删 `_stageFrameEl.classList.toggle('has-focus-dim', …)` |
| [map-scene-visual-layer.js debugState](map-scene-visual-layer.js) | `dimActive` 永远 false |
| [panels.css `.has-focus-dim` rule](../../../css/panels.css) | 删除 |
| [panels.css `.map-avatar-img`](../../../css/panels.css) | `object-fit: cover` → `fill` (顺手修 NPC PROPHET/阿波 非方形 PNG 错位 bug) |
| [qa-suite ui32a/b/c](dev/qa-suite.js) | 断言迁移到 Plan C: 删 skipDomScenes / dimActive 期望，新增 scenePainted = total - domVisible 校验 |

### 性能影响

- 稳态：canvas 多画 ~14 张 scene (cached backdrop drawImage + 13-14 scene drawImage via bakedCache) → ~3-6ms 入场 + 切 page / filter / hover-set 时一次 repaint，hover 期间静止
- buildStaticRenderKey 已包含 hoverHotspotId/currentHotspotId/focusHotspotId/busyLookup → hover 切换会重画 canvas 一次 (~5-8ms)，但 hover 期间无 tween 重画（DOM 层接管 transition），收益保留
- 比 baseline (~60-80% iGPU) 仍优；比 Phase 3 (~30-40%) 略增 (~35-50%)，可接受换稳态可见性

### 头像 object-fit:fill 顺修

旧 canvas drawAvatar 用 `drawImage(image, x, y, w, h)` 把整张 PNG 拉伸进 44×44 (变形但保全部内容); DOM `<img object-fit:cover>` 保持宽高比+裁剪填充 → 切掉非方形 PNG 的关键部分。仅 2 个 avatar PNG 非方形 (PROPHET 54×116, 阿波 97×67) 暴露问题，其余 52 个 (44×44) 三种 fit 等价。改回 `object-fit:fill` 与旧 canvas 1:1。
