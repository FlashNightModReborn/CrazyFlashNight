# Stage 0 — XML ⇄ launcher hotspot 错配决策表

脚本：`tools/audits/hotspot-mismatch-scan.js`（Stage 0-1 创建，Stage 0-2 删除）
首跑时间：2026-05-18
落地验证：2026-05-18（重跑 audit 后 mismatches=0/54）

## 统计

- XML `<npc>` 节点数：54
- 落地前：在 launcher 找到匹配 slot 但 hotspot 不一致：**9** 项
- 落地后：mismatches=0，全部清零
- 在 launcher 找不到任何匹配 slot：0 项（Stage A.5 audit 会处理）

## 决策表（落地前快照）

| # | NPC | page | XML.hotspot | launcher.hotspotId | source.center | containing (runtime) | status | decision |
|---|---|---|---|---|---|---|---|---|
| 1 | 杀马特 | base | `base_garage` | `base_lobby` | (337.70, 189.50) | `base_roof`, `base_lobby`, `merc_bar` | launcher-side-ambiguous | fix-xml |
| 2 | 格格巫 | base | `merc_bar` | `infirmary` | (538.90, 145.65) | `base_roof`, `infirmary`, `dormitory` | launcher-side-ambiguous | fix-xml |
| 3 | 丽丽丝 | base | `merc_bar` | `infirmary` | (593.55, 145.45) | `base_roof`, `infirmary`, `dormitory` | launcher-side-ambiguous | fix-xml |
| 4 | Shop Girl | base | `basement1` | `armory` | (521.80, 263.05) | `base_roof`, `base_lobby`, `basement1`, `armory` | fully-ambiguous | fix-xml |
| 5 | 小F | base | `basement1` | `armory` | (581.30, 251.95) | `base_roof`, `base_lobby`, `armory` | launcher-side-ambiguous | fix-xml |
| 6 | 黑龙 | faction | `blackiron_pavilion` | `blackiron_training` | (831.28, 100.21) | `blackiron_training` | unique | fix-xml |
| 7 | 体育老师 | school | `university_playground` | `university_interior` | (510.90, 401.80) | `university_interior` | unique | fix-xml |
| 8 | 冯佑权 | school | `teaching_interior` | `kendo_club` | (565.20, 183.95) | `kendo_club` | unique | fix-xml |
| 9 | Vanshuther | school | `university_interior` | `workshop` | (528.95, 299.40) | `workshop` | unique | fix-xml |

## 决策落地说明

**全部 9 项决策为 `fix-xml`**。裁决依据：

1. **4 项 unique（黑龙 / 体育老师 / 冯佑权 / Vanshuther）**：runtime rect 唯一命中 = launcher.hotspotId，且 XML.hotspot 不在 containing 内。算法决定性给出 fix-xml。

2. **4 项 launcher-side-ambiguous（杀马特 / 格格巫 / 丽丽丝 / 小F）**：XML.hotspot 几何上不在任何 containing 内（被排除），launcher.hotspotId 在 containing 内。即使存在重叠区，XML 一侧已被点包含检查排除。launcher 的 hotspotId 是 containing 列表中的合理候选，且业务语义对齐（格格巫/丽丽丝在医务室；杀马特在大厅；小F 在武器库）。

3. **1 项 fully-ambiguous（Shop Girl）**：source.center (521.80, 263.05) 同时落在 basement1 和 armory 内。XML 的 basement1 是 floor 级别概念，armory 是 sub-area 武器库；Shop Girl 业务上是武器铺店员，armory 是更具体且语义对齐的归属。launcher 与渲染一致，标 fix-xml。

**重叠区 tie-breaker 应用记录**：杀马特 / 格格巫 / 丽丽丝 / 小F 这 4 项标 launcher-side-ambiguous 是因为 `base_roof` 等大型 sceneVisual rect 覆盖范围广，但 `base_roof` 是屋顶视觉层、不是 NPC 物理归属候选。算法 status 仅反映几何包含关系，业务裁决排除 base_roof 后均落到 launcher.hotspotId。

## 决策说明（参考）

- `fix-xml`：XML 的 hotspot 错了，改 `data/map/map_panel.xml` 对应 `<npc>` 节点的 `hotspot` 属性
- `fix-launcher`：launcher 的 hotspotId 错了，改 `launcher/web/modules/map-panel-data.js` 对应 `_pageStaticAvatars` def 第 3 字段（或 `dynamicAvatars` 的 hotspotId）
- `business-defer`：业务上需要保持当前不一致或待美术介入，本次跳过

## 决策方法（参考）

1. **status=unique**：runtime rect 唯一命中 → 业务真实 = containing 列里那个 hotspot
   - 若 = XML.hotspot → `fix-launcher`
   - 若 = launcher.hotspotId → `fix-xml`
   - 若都不是 → 视觉裁决（preview.html）+ 标 `business-defer` 等待业务定夺
2. **status=xml-side-ambiguous / launcher-side-ambiguous / fully-ambiguous**：
   - 多重命中区涉及业务设计意图，**不能用面积大小自动判定**
   - 必须 preview.html 翻 page 视觉确认 NPC 头像在哪个 hotspot 色块内
   - 必要时游戏内开 NPC 对应任务测任务环跳转目标
   - 综合判定后填决策
3. **status=no-hit**：source.center 不落在任何 hotspot 内（罕见，可能 hotspot rect 太小或数据漂移）
   - 视觉裁决 + 标 `business-defer` 升级

## 后续

- Stage 0-2：删除 `tools/audits/hotspot-mismatch-scan.js`（本文件作为 Stage 0 永久审计记录保留）
- Stage A 重写后的 `tools/audit-map-taskmarkers.js` 将接管"XML.npc.hotspot === slot.hotspotId"这条断言，作为长期守门
