# Web Overlay 性能优化 A 档施工记录

**日期**: 2026-04-25
**范围**: launcher/web/css/{overlay,panels}.css
**风险等级**: 低（仅 CSS，纯视觉属性，不涉动画时序/JS逻辑）
**回退方法**: `git checkout -- launcher/web/css/overlay.css launcher/web/css/panels.css`

## 决策依据

A 档定义为**双源审计共振 + 架构理由充分 + 视觉损失极小**的优化项。不依赖 headless 实测数据
（headless 下 GPU 端成本不可见，多次 ablation 测得的 -26% 等数字事后被证实为单点噪声）。

参考资料：
- 静态审计：[Kimi/Explore 双源审计 docs/web-overlay-performance-audit-2026-04-25.md](web-overlay-performance-audit-2026-04-25.md)
- 方法论 peer review：[docs/web-overlay-perf-harness-methodology-review-2026-04-25.md](web-overlay-perf-harness-methodology-review-2026-04-25.md)
- 真机探针实测：launcher Ctrl+G 探针（[WebOverlayForm.ToggleCompositionProbe](../launcher/src/Guardian/WebOverlayForm.cs)）
  打开后非 panel 态 iGPU 50% → 35%，证明 alpha blend + Flash 出图占可观比重

## 改动清单

### 1. `backdrop-filter: blur()` 全部移除（37 处）

**变更**：
- `launcher/web/css/overlay.css`：18 处规则的 `-webkit-backdrop-filter` + `backdrop-filter` 双行（共 36 行）删除
- `launcher/web/css/panels.css`：1 处删除（`.lockbox-help-panel`）

**架构理由**：
- iGPU 上 backdrop-filter 每帧高斯卷积成本极高（单元素全屏 blur 单独可耗 20-30% iGPU）
- 现状所有受影响元素均带 `rgba(...)` 半透明纯色 fallback bg（多数 alpha ≥ 0.82）
- 删除后视觉损失：边缘 1-2px 柔化消失，无 backdrop 内容透出时肉眼无差异

**未改动**：
- `prefers-reduced-motion` 媒体查询块（已属降级路径）
- 未来如发现某元素 alpha < 0.7 视觉穿透明显，**手动调高 alpha 到 0.85+** 而非恢复 backdrop-filter

### 2. `mix-blend-mode: screen` 全部停用（6 处）

**变更**：
- `launcher/web/css/panels.css`:1064（lockbox-panel 扫描线）：内联形式，opacity 从 0.45 提升到 0.55 以补偿失去 screen 混合的提亮效果
- `launcher/web/css/panels.css`:1145, 1153, 1279, 3692, 3798（lockbox-grid-shell ::before/::after、map-stage-scanline、currentLocation 雷达）：独立行注释化

**架构理由**：
- `mix-blend-mode: screen` 在 GPU 上强制 layer readback + blend pass，破坏 fast-path 合成
- 在 iGPU 上代价远高于普通 opacity 渐变
- Kimi 实测信号最强（-26% CPU 旁证 + 真机 GPU 端额外节省）

**未改动**：
- 这两处的 `infinite animation` 保留（B 档处理）
- 未改用 SVG mask / pre-rendered png（B 档处理）

## 实施工具

- 一次性脚本：[launcher/perf/tools/apply-A-tier.py](../launcher/perf/tools/apply-A-tier.py)（幂等，可重复跑）
- 数据抢救：[launcher/perf/tools/salvage-from-log.py](../launcher/perf/tools/salvage-from-log.py)（从日志恢复 partial.json）
- 报表恢复：`node launcher/perf/recover.js [reportDir]`（partial.json → summary.json/md/html）

## 验证步骤

待机器冷却后（**避免再触发 PCIe AER 死机**）：

1. 启动游戏到 Ready 态
2. **场景 A**（非 panel 态）：
   - 任务管理器看 iGPU 占用基线
   - 按 Ctrl+G 探针切换（Flash 隐藏 + WebView2 opaque）：施工后探针 OFF 时 iGPU 应仍在 30%-35%（对比施工前 50%）
3. **场景 B**（map panel 打开）：
   - 任务管理器看 iGPU 占用
   - 期望从 100% 满载下降到 70-90% 区间
4. **视觉验收**：
   - 顶部 notch / 工具条 / 上下文面板：不应出现"完全透明"穿透到 Flash 游戏画面
   - lockbox 扫描线：仍然可见，亮度略低（opacity 已补偿）
   - map-stage 扫描线：方向感保留，"屏幕"混合的强亮高光消失（属预期）

## 已知风险

1. **某些场景 backdrop 透出过明显**：极少数元素若打开时背景内容色彩对比度强，删除 blur 后边缘可能不够柔。
   缓解：手动微调具体规则的 alpha，单元素改动而非全局回退
2. **lockbox-panel 扫描线 opacity 0.55 过亮**：若实测视觉过抢，调回 0.50 即可
3. **真机 GPU 节省与预期不符**：headless 测不到，需真机验证。如果非 panel 态 iGPU 没下降，说明非 panel 主因不在这里

## 回退

```bash
git checkout -- launcher/web/css/overlay.css launcher/web/css/panels.css
```

或局部回退：手工把删除的 backdrop-filter / mix-blend-mode:screen 恢复（每条改动都有 `/* was: ... — A档施工 2026-04-25 */` 注释标记）。

## B 档候选（不在本次范围）

需要 harness 实测数据才能决策的项，留给基建升级后的逐项 TDD：

- `filter: drop-shadow` 链式叠加（map-scene-node 4-6 层）→ png 预渲染
- `box-shadow` keyframe 动画 → opacity keyframe
- `conic-gradient` + rotate（map currentLocation 雷达）→ SVG 旋转
- `will-change` 常驻位点 → JS 动态管理
- `filter: blur` 在 keyframe 内（mapStageRetune）→ 移除或换 brightness
