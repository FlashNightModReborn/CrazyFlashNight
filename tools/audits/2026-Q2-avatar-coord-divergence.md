# Stage A.5-1：launcher staticAvatars ↔ source-data center 漂移决策表

- **生成日期**：2026-05-18
- **A5-1 临时 audit 脚本**：`tools/audits/avatar-coord-divergence-scan.js`（**A5-3 已删除**；本表是当时的快照，永久归档）
- **B 前复核入口（持久工具）**：`node tools/audit-map-layout.js --kind avatar --fail-on-review`——其 avatar `status === 'missing'` 的语义就是本表的 **launcher-orphan**（launcher slot 的 `assetUrl` 在 source-data 找不到 entry），可作为 A5-3 / Stage B 启动前的硬门控；上次跑（A5-3 收尾时）`missing:0`、`review:0`，exit 0 通过
- **对账双方**：
- **launcher slot center** = `slot.x + slot.w/2`, `slot.y + slot.h/2`（来自 `launcher/web/modules/map-panel-data.js` 的 `_pageStaticAvatars`，经 `buildStaticAvatarSlot(id, label, hotspotId, centerX, centerY, asset)` 反推）
- **source-data center** = `MapAvatarSourceData.getByAssetUrl(slot.assetUrl).center`（来自 `launcher/web/modules/map-avatar-source-data.js`）

> **签名漂移注**：上述 `buildStaticAvatarSlot(...)` 和 `MapAvatarSourceData.center` 是 A5-1 快照当时的形态。Stage A/B/C 之后，`buildStaticAvatarSlot` 已收窄为 `(id, label, hotspotId, assetName)`（不再带 centerX/centerY），`MapAvatarSourceData` entry 也由 `center/rect` 改为 `hotspotId + relX + relY + size`（hotspot-relative）。本快照保留 A5-1 时点的字段表达供审计追溯，**不**反映当前 schema；最新 schema 见 [agentsDoc/data-schemas.md "launcher/web 端 NPC 头像坐标 schema (Stage C 以后 hotspot-relative)"](../../agentsDoc/data-schemas.md)。

---

## 1. 摘要

| 指标 | 实测值 | 说明 |
|---|---|---|
| 总 staticAvatars 项 | 54 | base 20 + faction 16 + defense 6 + school 12 |
| 普通漂移 (>1px) | **53** | 53/54 = 98% |
| 0 漂移项 (≤1px) | **1** | `researcher_avatar`（faction）：slot center (202.10, 472.00) 与 source center (202.10, 472.00) 精确相等。这是**唯一** non-canonical slot（XML 无对应 npc，researcher 不在 REQUIRED_NPC_NAMES 里），也是唯一在 panel-data 与 source-data 之间无漂移的项——很可能是 panel-data 后期补的、直接同步了 source-data center |
| launcher-orphan | **0** | source-data 完整覆盖所有 launcher slot.assetUrl → **A5-2a 空跳过**（B 前硬门控通过） |
| source-orphan | **0** | source-data 没有未被 launcher 引用的孤儿条目 |
| 漂移方向主导 | **(-X, -Y) 100%** | 53/53 项的 source-data center 都在 slot center 的左上方向 |
| 漂移幅度区间 | 23.63 ~ 29.85 px | 最小：黑铁 23.63；最大：阿波 29.85（**全部 < 30px**） |
| 方向反常项 | **0** | 没有项漂移方向与多数项相反 |
| > 30px 抽检触发 | **0** | 无项需逐项视觉验证 |
| dynamicAvatars | 1（"室友"）不参与本对账 | dynamicAvatars 走自己的 `{x, y, w, h}` schema，不引用 source-data；schema 变化在 Stage C 一并处理 |

**结论**：53/53 漂移项默认 `keep-source`。0 项进入抽检。0 项 `revert-to-panel-data`。

**业务真实位置**：渲染当前已经走 source-data（[map-panel.js:1009-1023](../../launcher/web/modules/map-panel.js#L1009-L1023) `resolveStaticAvatarRect` 优先返回 source-data.rect，slot 的 (x,y) 是 fallback），所以决策表里所有 `keep-source` 等价于 "当前显示态保留"。Stage B 会删除 slot 的 (x, y)，让 source-data 成为唯一坐标源——此后 launcher-orphan 风险消失。

**reviewOnly 标注**：理科教授（science_prof_avatar）+ 文科老师（arts_teacher_avatar）在 qa-suite [map-ui22](../../launcher/web/modules/map/dev/qa-suite.js#L996-L999) 是 `reviewOnly` 白名单（几何中心落在 hotspot 边界），本决策表延续标注；属性是诊断记录，不改变 `keep-source` 决策。

---

## 2. 决策表

**列说明**：
- **flag**：`!` = `|delta| > 30px`（无）；`↺` = 漂移方向与多数项相反（无）
- **decision**：`keep-source` 默认；`revert-to-panel-data` 反向校正 source-data；`launcher-orphan`/`source-orphan` 见摘要；`reviewOnly` 是附加标签
- **rationale**：默认理由——"美术 XFL 抽出定型，panel-data 是抽前草稿没同步"

| page | slotId | label | hotspot | slot center | source center | delta (Δx, Δy) | |Δ\| | flag | decision | tag |
|---|---|---|---|---|---|---|---|---|---|---|
| base | andy_avatar | Andy Law | basement1 | (497.55,329.40) | (469.40,301.25) | (-28.15,-28.15) | 28.15 |   | keep-source |  |
| base | bartender_avatar | 酒保 | merc_bar | (444.85,136.15) | (416.65,107.90) | (-28.20,-28.25) | 28.25 |   | keep-source |  |
| base | blue_avatar | Blue | basement1 | (620.90,336.80) | (592.75,308.65) | (-28.15,-28.15) | 28.15 |   | keep-source |  |
| base | boy_avatar | Boy | base_garage | (212.95,246.00) | (184.80,217.85) | (-28.15,-28.15) | 28.15 |   | keep-source |  |
| base | chef_avatar | 厨师 | cafeteria | (324.85,431.85) | (295.15,408.25) | (-29.70,-23.60) | 29.70 |   | keep-source |  |
| base | dancer_avatar | 舞女 | merc_bar | (389.55,140.20) | (361.65,112.10) | (-27.90,-28.10) | 28.10 |   | keep-source |  |
| base | diplomat_avatar | 黑铁会外交部长 | base_lobby | (363.25,264.75) | (335.00,236.60) | (-28.25,-28.15) | 28.25 |   | keep-source |  |
| base | gem_contact_avatar | 宝石线人 | base_lobby | (564.15,249.75) | (536.70,221.90) | (-27.45,-27.85) | 27.85 |   | keep-source |  |
| base | king_avatar | King | base_garage | (265.35,217.85) | (237.15,189.75) | (-28.20,-28.10) | 28.20 |   | keep-source |  |
| base | lilith_avatar | 丽丽丝 | infirmary | (621.55,173.80) | (593.55,145.45) | (-28.00,-28.35) | 28.35 |   | keep-source |  |
| base | pig_avatar | Pig | base_garage | (171.55,217.85) | (143.50,190.00) | (-28.05,-27.85) | 28.05 |   | keep-source |  |
| base | schoolgirl_avatar | 学生妹 | base_lobby | (414.10,245.45) | (385.95,217.30) | (-28.15,-28.15) | 28.15 |   | keep-source |  |
| base | shamate_avatar | 杀马特 | base_lobby | (365.95,217.60) | (337.70,189.50) | (-28.25,-28.10) | 28.25 |   | keep-source |  |
| base | sheriff_avatar | 前治安官 | base_lobby | (625.50,237.20) | (597.60,209.20) | (-27.90,-28.00) | 28.00 |   | keep-source |  |
| base | shopgirl_avatar | Shop Girl | armory | (549.95,291.20) | (521.80,263.05) | (-28.15,-28.15) | 28.15 |   | keep-source |  |
| base | thegirl_avatar | The Girl | basement1 | (436.25,332.65) | (408.10,304.50) | (-28.15,-28.15) | 28.15 |   | keep-source |  |
| base | veteran_avatar | 幸存老兵 | base_lobby | (466.50,259.35) | (438.35,231.20) | (-28.15,-28.15) | 28.15 |   | keep-source |  |
| base | weapon_merchant_avatar | 冷兵器商人 | base_garage | (120.50,222.05) | (92.45,193.95) | (-28.05,-28.10) | 28.10 |   | keep-source |  |
| base | wizard_avatar | 格格巫 | infirmary | (567.05,173.80) | (538.90,145.65) | (-28.15,-28.15) | 28.15 |   | keep-source |  |
| base | xiaof_avatar | 小F | armory | (609.15,279.75) | (581.30,251.95) | (-27.85,-27.80) | 27.85 |   | keep-source |  |
| faction | blackdragon_avatar | 黑龙 | blackiron_training | (858.32,126.97) | (831.28,100.21) | (-27.04,-26.76) | 27.04 |   | keep-source |  |
| faction | blackiron_avatar | 黑铁 | blackiron_pavilion | (749.77,239.77) | (726.14,217.27) | (-23.63,-22.50) | 23.63 |   | keep-source |  |
| faction | cowboy_avatar | 牛仔 | fallen_bar | (711.37,471.70) | (683.70,443.40) | (-27.67,-28.30) | 28.30 |   | keep-source |  |
| faction | cyborg_sage_avatar | 假肢仙人 | fallen_street | (175.65,488.45) | (147.55,460.40) | (-28.10,-28.05) | 28.10 |   | keep-source |  |
| faction | director_avatar | director | warlord_tent | (170.85,125.00) | (143.45,97.40) | (-27.40,-27.60) | 27.60 |   | keep-source |  |
| faction | firephoenix_avatar | 火凤 | blackiron_training | (722.36,119.54) | (695.12,92.54) | (-27.24,-27.00) | 27.24 |   | keep-source |  |
| faction | gazer_avatar | gazer | warlord_base | (108.95,168.10) | (81.50,140.15) | (-27.45,-27.95) | 27.95 |   | keep-source |  |
| faction | general_avatar | general | warlord_base | (219.30,170.60) | (190.60,141.95) | (-28.70,-28.65) | 28.70 |   | keep-source |  |
| faction | guitar_avatar | guitar | rock_park | (404.95,186.10) | (377.60,158.70) | (-27.35,-27.40) | 27.40 |   | keep-source |  |
| faction | hitler_avatar | 吸特乐 | fallen_street | (97.90,482.00) | (70.55,453.40) | (-27.35,-28.60) | 28.60 |   | keep-source |  |
| faction | itinerant_avatar | itinerant | firing_range | (134.35,293.60) | (106.60,265.20) | (-27.75,-28.40) | 28.40 |   | keep-source |  |
| faction | keyboard_avatar | keyboard | rock_park | (531.75,187.70) | (503.90,158.70) | (-27.85,-29.00) | 29.00 |   | keep-source |  |
| faction | singer_avatar | singer | rock_park | (468.55,158.50) | (439.50,130.70) | (-29.05,-27.80) | 29.05 |   | keep-source |  |
| faction | surveyor_avatar | surveyor | firing_range | (234.35,264.10) | (207.00,235.95) | (-27.35,-28.15) | 28.15 |   | keep-source |  |
| faction | wingtiger_avatar | 翅虎 | blackiron_training | (813.78,107.31) | (787.38,80.07) | (-26.40,-27.24) | 27.24 |   | keep-source |  |
| defense | abo_avatar | 阿波 | alliance_dock | (241.20,331.65) | (211.35,303.25) | (-29.85,-28.40) | 29.85 |   | keep-source |  |
| defense | artist_avatar | artist | first_defense | (161.65,155.15) | (133.35,126.85) | (-28.30,-28.30) | 28.30 |   | keep-source |  |
| defense | jige_avatar | 机哥 | alliance_dock | (189.45,333.65) | (161.75,306.60) | (-27.70,-27.05) | 27.70 |   | keep-source |  |
| defense | paigu_avatar | 排骨 | alliance_dock | (137.45,332.30) | (109.45,304.45) | (-28.00,-27.85) | 28.00 |   | keep-source |  |
| defense | prophet_avatar | PROPHET | alliance_corridor | (228.45,392.45) | (200.35,364.40) | (-28.10,-28.05) | 28.10 |   | keep-source |  |
| defense | soldier_avatar | soldier | first_defense | (250.70,162.60) | (222.55,134.25) | (-28.15,-28.35) | 28.35 |   | keep-source |  |
| school | arts_teacher_avatar | 文科老师 | arts_class | (810.90,213.10) | (783.05,184.85) | (-27.85,-28.25) | 28.25 |   | keep-source | reviewOnly |
| school | bat_avatar | Bat | union_university | (471.40,529.70) | (442.05,501.00) | (-29.35,-28.70) | 29.35 |   | keep-source |  |
| school | chengzheng_avatar | 程铮 | teaching_interior | (486.65,255.75) | (458.85,227.95) | (-27.80,-27.80) | 27.80 |   | keep-source |  |
| school | dean_avatar | 教导主任 | office | (538.90,104.15) | (510.90,75.55) | (-28.00,-28.60) | 28.60 |   | keep-source |  |
| school | fengyouquan_avatar | 冯佑权 | kendo_club | (593.30,211.90) | (565.20,183.95) | (-28.10,-27.95) | 28.10 |   | keep-source |  |
| school | heizi_avatar | 黑仔 | union_university | (430.05,508.20) | (402.55,480.35) | (-27.50,-27.85) | 27.85 |   | keep-source |  |
| school | kendo_president_avatar | 剑道社长 | kendo_club | (663.30,213.10) | (634.95,184.85) | (-28.35,-28.25) | 28.35 |   | keep-source |  |
| school | pe_teacher_avatar | 体育老师 | university_interior | (539.20,428.65) | (510.90,401.80) | (-28.30,-26.85) | 28.30 |   | keep-source |  |
| school | science_prof_avatar | 理科教授 | science_class | (744.65,212.35) | (716.50,183.95) | (-28.15,-28.40) | 28.40 |   | keep-source | reviewOnly |
| school | tomboy_avatar | Tomboy | union_university | (516.90,513.20) | (489.05,484.90) | (-27.85,-28.30) | 28.30 |   | keep-source |  |
| school | vanshuther_avatar | Vanshuther | workshop | (555.75,327.20) | (528.95,299.40) | (-26.80,-27.80) | 27.80 |   | keep-source |  |
| school | weapon_order_avatar | 武器订购系统 | union_university | (570.40,516.70) | (542.55,488.35) | (-27.85,-28.35) | 28.35 |   | keep-source |  |

---

## 3. 决策方法（per plan Stage A.5-1）

**默认 + 抽检模式**：53 行逐项视觉 review 不现实。规则：

| 场景 | 默认决策 | 抽检触发 |
|---|---|---|
| 漂移 1-30px 且方向与多数项一致 | `keep-source` | **不抽检**——视觉已按 source-data 渲染稳定 |
| 漂移 > 30px | `keep-source` 但标 `抽检` | **逐项 preview.html 视觉验证**，发现错位则 `revert-to-panel-data` |
| 方向与多数项相反 | `keep-source` 但标 `抽检` | 独立视觉验证 |
| 跨 hotspot 边界（qa-suite reviewOnly 白名单内） | `keep-source` + 标 `reviewOnly` | 既有豁免延续 |
| `launcher-orphan` | **B 前必须处理** | 补 source-data entry 或删 launcher slot |
| `source-orphan` | 可延后清理 | A5-2b 落地 |

**本次结果**：53 项全部进入第 1 行（默认 keep-source）；2 项额外加 reviewOnly 标签（科教授 / 文科老师）；0 项进入抽检；0 launcher-orphan；0 source-orphan。

---

## 4. 落地动作

### A5-1（本次）
- [x] 写 audit 脚本 `tools/audits/avatar-coord-divergence-scan.js`
- [x] 跑 audit + 生成本决策表
- [x] 人工 review 完成（按算法 53/53 默认 keep-source，无抽检触发）
- [x] 决策表归档（**永久保留**作审计记录）

### A5-2a（B 前硬门控）
- [x] launcher-orphan 项处理：**0 项 → 空跳过**

### A5-3（**已完成**——临时脚本已删；进 B 前的"最后一刻"复核改走持久工具）
- [x] 删除 audit 脚本 `tools/audits/avatar-coord-divergence-scan.js`（决策表 markdown 保留作历史快照）
- [x] **B 前复核改用** `node tools/audit-map-layout.js --kind avatar --fail-on-review`——只看 `row.status`（[audit-map-layout.js:426](../../tools/audit-map-layout.js#L426)），其中 `status === 'missing'` ⇔ 本表 launcher-orphan（assetUrl 找不到 source entry），exit 1 兜底。**注意**：本表所有 53 个 1-30px 漂移项目前 `authoredStatus = 'review'`（authored slot rect ↔ source rect 差 > 4px），但 `authoredStatus` **不**在 `--fail-on-review` 的判定范围内（汇总 byKind 里的 `review:0` 是 `status`，不是 `authoredStatus`，所以仍 exit 0）。Stage B 删 staticAvatars (x, y) 后 `authoredRect` 概念消失，那些 review 提示一并清零。上次跑 avatar `missing:0`、status `review:0`，exit 0
- [x] **进 B 前最后一刻**：再跑一次 `audit-map-layout --kind avatar --fail-on-review`，确认从 A5-1 快照之后没有新 launcher-orphan 被引入（Session 2 开始时执行，结果：avatar exact=54, missing=0, exit 0）

### A5-2b（B/C 之后可延后）
- [ ] `revert-to-panel-data` 项落地：**0 项 → 空跳过**
- [ ] `source-orphan` 清理：**0 项 → 空跳过**
- [ ] `reviewOnly` 项业务定夺：**理科教授 / 文科老师**——既有 qa-suite 白名单豁免延续，**不在本阶段处理**（独立 TODO 跟进，等待美术 / 边界设计定案）

---

## 5. 与 Stage 0 重叠区处理协同

Stage 0 已修复 9 个 XML ⇄ launcher hotspot 错配项（`tools/audits/2026-Q2-hotspot-mismatch.md`）。本表的所有项 hotspot 现在两端一致——audit 脚本是用 launcher slot 的 hotspotId（B 之后变 source-data 派生）做对账，与 XML 已无独立分歧。

跨 hotspot 边界 NPC（理科教授 / 文科老师）属于 Stage 0 未根治的设计妥协，本表与 qa-suite [map-ui22](../../launcher/web/modules/map/dev/qa-suite.js#L996-L999) `reviewOnly` 白名单协同延续。
