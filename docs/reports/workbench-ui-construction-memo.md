# 双栏工作台视觉系统施工备忘

> **文档角色**：施工期状态备忘，抗会话 compact，记录已拍板的决策、当前轮次范围、待办和风险。
> **创建时间**：2026-07-17
> **关联文档**：
> - `docs/dls-color-system.md`（DLS/θ-域配色 canonical）

> - `agentsDoc/as2-web-panel-migration.md`（迁移护栏）
> - `launcher/web/css/panels.css`

---

## 1. 已拍板的结论

### 1.1 颜色谱系
- **DLS 材料 / 技能延伸**：晶体青 `#3dd5ff`，用于装备调制、技能面板、强化石、DLS 道具。技能被解释为“人体对 DLS / 强化石科技的直接延伸”，因此与调制共享主色。
- **信息 / 控制平面**：电蓝 `#5e8cff`，仅用于帮助、提示、诊断等高亮，不再用于技能面板。
- **DLS 商业入口**：KShop 主强调色 `#3dd5ff`（与技能、调制统一）；价格/余额等交易功能保留琥珀 `#ffd367` / `#ffc447` 作为辅助识别。NPC 金铜 `#e5a64d`、合成锻造琥珀 `#f1b83b` 保持不变。
- **档案**：库存纸白 `#e5e5e5`、情报烫金 `#d8b656`。
- **语义色**：success `#78bc73`、warning `#e5a64d`、danger `#df665b`、info `#5e8cff`、disabled `#646e75`。

### 1.2 架构原则
- 组件只消费语义 token，skin 只覆写 token。
- 共享暗部色板：`--wb-bg/surface/surface-2/line/line-soft/text/muted/accent/accent-soft`。
- 字号下限：中文正文 ≥10px，英文/数字辅助 ≥9px，正文推荐 ≥11px。
- 固定画布内禁止 viewport `@media`；装备调制的 `@media (max-width:900px)` 立即移除。
- 禁止 `transition: all`；统一动效四档 90/140/180–220/800–1000ms。
- 可点击图标 hit 区 ≥24px，主要操作 ≥40–44px。

---

## 2. 本轮施工范围（本次会话）

**目标**：先把 DLS/θ 域颜色 token 和语义色 token 落地，并迁移技能/调制的强调色，使“技能 vs 调制”在世界观-视觉上一致且可区分。

### 2.1 P0（必须完成）
1. 在 `panels.css` 顶层或独立 `dls-tokens.css` 中新增 `--dls-*` / `--theta-*` / `--wb-semantic-*` token 族。
2. 装备调制：把 `--tuning-dls*` 收敛为 `--dls-crystal*`；保持 `#3dd5ff`。
3. 技能面板：把 `--skill-energy` 和相关 `#4ec9f0`、`#63c7de` 进度条收敛到 `--dls-crystal` 色系（`#3dd5ff`）；在 `.skills-panel` 内将 `--theta-kinetic*` 覆写为 `--dls-crystal*` 别名，保持现有 CSS 规则不变。
4. K 点商城 shop 皮肤：把 `#c8ff4c` 及所有 `rgba(200,255,76,…)` 替换为 DLS 晶体青 `#3dd5ff` / `rgba(61,213,255,…)`；文本/边框/背景同步映射为青灰体系；保留价格/结算琥珀作为功能色。
5. 移除 `equipment-tuning` 中的 `@media (max-width:900px)`。
6. 修复 `workbench-shell` 顶栏高度：`grid-template-rows:64px` → `48px`（与 ADR 一致）。
7. 清理所有新增/修改规则中的 `transition: all`，改为显式属性。
8. 验证 `panels.css` 无语法错误，且 `skills` / `equipment-tuning` harness 可正常加载。

### 2.2 P1（已完成）
1. ✅ 统一 scrollbar token：`--wb-scrollbar-track/thumb/border/hover` 已在 root 声明，并在商城/NPC/合成/技能/调制皮肤中覆盖复用。
2. ✅ 为 `crafting` 引入 `--wb-semantic-success/danger` 替换 `#78bc73`、`#df665b`、`#ef786d`；`kshop` 移除按钮改用 `--wb-semantic-danger`。
3. ✅ 降低库存空槽线框对比度：`.inventory-slot-card.empty` 新增 `border-color:rgba(255,255,255,.06)`。

### 2.3 P2（部分完成）
- ✅ **统一状态机枚举**：`workbench.js` 新增 `WorkbenchState`（idle/loading/ready/pending/warning/error/disconnected，busy 为遗留同义词），`setStatus` 增加 `normalizeState` 校验并导出枚举。
- ✅ **彻底移除战备箱卡片级调制按钮**：经反馈，compact 态下 hover 显示仍造成干扰，现完全移除卡片上的“调制”入口，仅保留顶栏“装备调制”开关。相关 CSS、JS、harness 已同步清理。
- ✅ **丢弃按钮仅在选中/聚焦时显示且键盘可达**：`.inventory-discard-btn` 不再随 hover 出现，仅在卡片被选中（`.workbench-source-selected`）、卡片处于 focus-within 或按钮自身获得焦点时显示；隐藏态只使用 `opacity:0 + pointer-events:none`，避免拦截鼠标，同时保留 Tab 焦点入口。
- ✅ **再次点击来源格可取消选择**：`InteractionBroker.isSelectedNode(node)` 用于识别当前来源；`inventory-workbench.js` 再次点击同一格时显式 `clearSelection()`，不会误走 same-slot 操作，也不会产生库存写入。
- ✅ **紧凑商城分离视觉尺寸与命中尺寸**：加购按钮保留 24×24 的透明点击/键盘焦点区，16×16 晶体青角标由伪元素绘制；物品图仍是视觉主体，hover/pressed 反馈作用于小角标，键盘 focus 额外显示命中区轮廓。
- ✅ **技能预览状态样式完成合并**：`ok` / `blocked` 保留轻量渐变，`updating` 保留 DLS inset/glow；移除同 specificity 重复声明，避免后写规则覆盖新视觉。
- ✅ **合成目录固定卡片高度**：`.crafting-recipe-card` 固定 `height:78px`；`.crafting-catalog-view` 加 `overflow:hidden`、grid 加 `flex:1 1 auto`，确保条目多时出现滚动而不是挤压卡片。
- ✅ **可访问性名称与说明分离**：`skills.js` 中关键控件保留稳定的 `aria-label` 作为可访问名称，说明文本改回 `title`（鼠标悬停提示）/ `aria-describedby`，避免覆盖名称；`crafting.js`、`kshop.js`、`kshop-views.js`、`npcshop.js` 中原本只有 `title` 的无名元素仍迁移为 `aria-label`。
- ✅ **全局 hitbox 下限**：`panels.css` base 层新增规则，工作台内所有 `button`/`[role="button"]` 最小 24×24；主操作按钮（primary CTA）最小高 40px。
- ⏸️ **拆分 `panels.css` 为 base/components/skins/features/utilities 五段 + cascade layers**：本轮未执行。文件 14k+ 行，物理拆分需要逐段验证所有 harness 和 AS2 面板的视觉回归，建议作为独立“CSS 架构重构”专题施工。
- ⏸️ **抽取 `WorkbenchHeader / PaneChrome / FlowRail / SecondaryPage / WorkbenchDialog / EntityTilePrimitives / AuthorityPreviewPanel`**：本轮未执行。这些组件与 `DualPaneShell` 的 view 契约、状态管理深度耦合，直接抽取会触及多个生产面板的 JS 结构，建议随 cascade layers 重构同步进行。

---

## 3. 已知风险

- `panels.css` 14,265 行，变量名冲突可能导致旧皮肤失效。每次改完必须 Grep 检查 `--dls-*`、`--theta-*`、`--tuning-dls*` 的引用是否完整。
- 技能面板重新收敛到 `#3dd5ff` 后，与调制面板主色相同，但布局/图标/交互密度差异足以区分；需在 harness 中确认能量条、选中态、FlowRail 都可读且不显得过于接近调制。
- 装备调制的 `@media` 移除后，紧凑模式下候选网格可能变窄；需确认 `.item-grid-compact` 已有回退。
- 顶栏 64px → 48px 会释放约 16px 纵向空间，可能让某些面板 body 内元素重新获得空间，也可能让原本依赖 64px 的自定义元素错位。

---

## 4. 验证方式

1. **静态检查**：Grep 确认无 `--tuning-dls` 残留、无未定义 `--dls-*`、无 `@media (max-width:900px)` 残留。
2. **Harness 加载**：启动本地 HTTP server，打开 `modules/skills/dev/harness.html` 与 `modules/equipment-tuning/dev/harness.html`，确认无 CSS/JS 报错、面板渲染完整。
3. **视觉快照（人工）**：在 1024×576、1366×768、1920×1080 三视口下检查技能与调制颜色区分度。
4. **回归**：如时间允许，快速打开 `kshop` / `npcshop` / `crafting` harness，确认非目标面板不受 token 变更影响。

---

## 5. 变更清单模板

每完成一项在此回填：

| # | 任务 | 状态 | 关键文件/行号 | 备注 |
|---|---|---|---|---|
| 1 | 新增 DLS/θ token | 完成 | `launcher/web/css/panels.css:151` 起 | 新增 `:root` token 块，含 `--dls-*`、`--theta-*`、`--wb-semantic-*`、`--wb-scrollbar-*` |
| 2 | 技能强调色迁移 | 完成→收敛 | `panels.css:13510` 起 | 先迁移到 `--theta-kinetic`（`#5e8cff`），根据反馈后重新收敛到 `--dls-crystal`（`#3dd5ff`）；`.skills-panel` 内覆写 `--theta-kinetic*` 为 DLS 别名 |
| 2a | KShop 主强调色迁移 | 完成 | `panels.css:12462` 起 | 方案 A：shop 皮肤从荧光绿 `#c8ff4c` 整体迁移到 DLS 晶体青；结算/价格保留琥珀功能色 |
| 3 | 调制变量收敛 | 完成 | `panels.css:13920` 起 | `--tuning-dls*` 全部收敛到 `--dls-crystal*`，移除自引用 |
| 4 | 移除 @media | 完成 | 原 `panels.css:14287` | 移除了 `max-width:900px` 视口媒体查询，保留 `prefers-reduced-motion` |
| 5 | 顶栏高度修复 | 完成 | `panels.css:2770` | 新增 `--wb-header-height:48px`，`grid-template-rows` 改用变量 |
| 6 | transition:all 清理 | 完成 | 本次修改未引入 `transition:all` | 现有规则已使用显式属性列表；后续新规则必须保持 |
| 7 | Harness 验证 | 完成 | `modules/skills/dev/harness.html`、`modules/equipment-tuning/dev/harness.html`、`modules/kshop/dev/harness.html` | Edge headless 截图 + QA 通过（skills 126/126，tuning 56/56） |
| 8 | scrollbar token 统一 | 完成 | `panels.css` 多处 | 商城/NPC/合成/技能/调制皮肤均覆盖 `--wb-scrollbar-*` |
| 9 | 语义色替换 | 完成 | `panels.css:13407` 起 crafting，`panels.css:3273` kshop remove | `--wb-semantic-success/danger` |
| 10 | 空槽对比度 | 完成 | `panels.css:12226` | `.inventory-slot-card.empty` 新增 `border-color:rgba(255,255,255,.06)` |
| 11 | 状态机枚举 | 完成 | `launcher/web/modules/workbench.js` | 新增 `WorkbenchState` + `normalizeState` |
| 12 | 可访问性名称与说明分离 | 完成 | `skills.js/crafting.js/kshop.js/kshop-views.js/npcshop.js` | skills.js 保留 title 作为补充说明，其余无名元素 title 迁移为 `aria-label` |
| 13 | hitbox 下限 | 完成 | `panels.css:2902` 起 | button/role=button 最小 24×24，主 CTA 最小高 40px |
| 14 | CSS cascade layers / 组件抽取 | 本轮暂缓 | — | 文件 14k+ 行，需独立架构专题 |
