# 地图 hotspot 拓扑收束 — 施工方案（方案 A：扩展 build 派生）

- 起草：2026-06-03；**v2 修订：2026-06-03**（纳入评审 6 点反馈 + boot 编排实地核实，见 §0）
- 触发事件：commit `97845687e`（隧道据点 subway）只改了 Web 侧拓扑 → 地图界面点击无效（选关可进）。根因调查见本文 §1。
- 决策：本轮**不修 subway**，先把收束方案定下来。收束走**方案 A**（SOT=map-panel-data.js + build 期派生 + gate），产物形态取 **A2**（独立 `map_catalog.json` + DataQueryService 消费）。subway 作为收束落地后的首个验证用例。
- 相关先例：2026-05-28 已把 `<npc>/<alias>` 段从 map_panel.xml 迁出，改为 web-SOT + build 派生（下称 **「npc 派生先例」**，见 §3）。本方案是该先例向 `<groups>/<hotspots>` 段的自然延伸。

> 术语约定：本文 §6 的 **A1 / A2** 指"派生产物形态"两个子选项；与触发本方案的 AskUserQuestion 顶层选项「方案 A（扩展 build 派生）」不是同一层级，勿混。npc 段 2026-05-28 迁移本文一律称「npc 派生先例」，不再叫"方案 B"（避免与 §6 子选项撞名）。

---

## 0. v2 修订纪要（评审 6 点 + 实地核实）

施工前评审纠正了 v1 的若干计划细节，均已并入正文：

1. **MapPanelLoader 硬失败**（§7.1）：map_panel.xml 只剩 avatar_visibility 时，现有 [MapPanelLoader.load](../scripts/类定义/org/flashNight/gesh/xml/LoadXml/MapPanelLoader.as#L44) 的 `data.groups==undefined && data.hotspots==undefined` 守卫会判失败。→ 拆 `MapAvatarVisibilityLoader`（或放宽该守卫），并把 `MapPanelCatalog` 拆成 `applyFromCatalogJson()` + `applyAvatarVisibilityFromXml()`。
2. **map_catalog 失败不可静默降级**（§7.3）：npc 派生先例失败只丢红点 → 静默降级可接受；**map_catalog 是导航权威**，失败必须明确报错 + 让 map panel 不可用（safe-zero 已保证 navigate 拒绝，但需额外用户可见报错）。
3. **派生脚本走公开 API**（§5/§8）：用 `MapPanelData.exportManifest().unlockGroups` / `getPageOrder()` / `getPage()` / `getHotspotUnlockGroup()`，**不读** `_unlockGroups`/`_pageUnlockGroups` 私有变量。已核对公开 API 足够：40 hotspot、8 个非 base group、subway→defense、base group 为空，符合 base 特例。
4. **术语统一**（见上）：npc 段迁移改称「npc 派生先例」，不与 §6 的 A1/A2 撞名。
5. **验证清单补强**（§12）：加 DataQueryTask/DataCache/XmlDataLoader 的 xUnit + C# build 覆盖；加**任务完成条 / Native HUD 的 tdh 直达导航回归**（[通信_鸡蛋_任务系统.as:527-537](../scripts/通信/通信_鸡蛋_任务系统.as#L527) 经 `MapPanelService.resolveDeliverableState` → `canNavigateToHotspot` → 也吃 `NAVIGATE_TARGETS`）。
6. **心智模型变更 + 文档治理**（§10）：以后改 hotspot 拓扑**不需要 AS2 重编译**，但**仍需跑 build/derive 刷新 `map_catalog.json`**；canonical docs（[agentsDoc/data-schemas.md](../agentsDoc/data-schemas.md)）须同步并跑 `node tools/validate-doc-governance.js`。**subway 收尾别忘**（§10 步骤 5）。

**实地核实（v1 未知、影响 A2 工作量）**：catalog 的 boot 编排**不在 source 树的普通 .as 里**，而在 [scripts/asLoader/LIBRARY/asLoader.xml:522-567](../scripts/asLoader/LIBRARY/asLoader.xml#L522)（asLoader 时间轴帧脚本，可经 asLoader 重编译）。顺序为 `MapPanelLoader → applyFromXml → DataQueryService.query("task_npc_registry") → applyFromQuery`。**A2 必须改这段 boot**（把 catalog 来源从 MapPanelLoader 换成 `DataQueryService.query("map_catalog")`，并保持"catalog 先于 npc registry"依赖序）。这是 A2 相较 A1 的额外工作量，但 asLoader 已开、可重编译，成本可接受。

---

## 1. 根因（为什么 subway 点击无效）

地图导航的**运行时授权**在 AS2，不在 Web：

- Web 点击 hotspot → `requestNavigate` → Bridge `cmd:navigate, targetId:"subway"`
  （[map-panel.js:584](../launcher/web/modules/map-panel.js#L584)）
- → C# [MapTask.cs](../launcher/src/Tasks/MapTask.cs)（**纯透传桥**，不读 xml）
- → AS2 [MapPanelService.navigateToHotspot()](../scripts/类定义/org/flashNight/arki/map/MapPanelService.as#L88)：
  ```as
  if (MapPanelCatalog.NAVIGATE_TARGETS[hotspotId] == undefined) return false; // ← subway 在此被拒
  ```
- `NAVIGATE_TARGETS` 由 [data/map/map_panel.xml](../data/map/map_panel.xml) 构建，其中**没有 subway** → 导航被拒 → 点击无反应。

**选关能进**：走完全独立的另一条路 [StageSelectPanelService.as](../scripts/类定义/org/flashNight/arki/stageSelect/StageSelectPanelService.as)，直接用 `frameLabel`（中文 scene 名）驱动 `淡出跳转帧`，**不查 NAVIGATE_TARGETS**。所以隧道据点选关正常。

**澄清**：fs 猜的"两边跳到不是一个图"不成立 —— Web hotspot 的 `sceneName` 与选关 `rootFadeTransitionFrame` 都是 `地图-隧道据点`，一致；D 指导的"清缓存"无关（这块没缓存）。

---

## 2. 当前拓扑被写三份（要消灭的维护成本）

| 层 | 文件 | 拓扑内容 | 改它要不要重编译 |
|---|---|---|---|
| AS2 运行时 | [data/map/map_panel.xml](../data/map/map_panel.xml) `<groups>/<hotspots>` | hotspot→group/frame、group→page/label/lockedReason | 否（运行期读 XML） |
| AS2 编译期 | [MapPanelCatalog.REQUIRED_HOTSPOT_IDS / REQUIRED_GROUP_IDS](../scripts/类定义/org/flashNight/arki/map/MapPanelCatalog.as#L43) | hotspot/group id 的"金标准集合"，`setEquals` 精确校验 XML | **是** |
| Web | [map-panel-data.js](../launcher/web/modules/map-panel-data.js) `_unlockGroups`/`_pageUnlockGroups`/`_pages[].hotspots[].sceneName` | 同一套拓扑 + 渲染专属（rect/visual/avatar/layout） | 否（JS） |

加一个 hotspot 要**同步改 3 处、其中 1 处涉及 SWF 重编译**；任一处漏改：
- 漏 XML → catalog `setEquals` 失败 → **整张表回退空 → 全图导航挂**；
- 漏 REQUIRED → 同上；
- 漏 Web → **subway 这种半落地（本次）**。

**已验证缺口**：`tools/` 与 `launcher/tests/` 中**没有任何工具读 map_panel.xml，也没有跨层 hotspot 集合一致性校验**。现有 audit（[audit-map-taskmarkers.js](../tools/audit-map-taskmarkers.js) 等）只校验 NPC↔hotspot 与几何，**不校验 hotspot 存在性集合**。

---

## 3. 先例：npc/alias 段已收束（本方案的模板）

[data/map/map_panel.xml:77-85](../data/map/map_panel.xml#L77) 的注释记录了 2026-05-28 的迁移：

> `task_npcs / aliases` 段已迁出本文件。真相源 = `map-panel-data.js` 的 staticAvatars/dynamicAvatars，
> 派生入口 = [tools/derive-task-npc-registry.js](../tools/derive-task-npc-registry.js)（build.ps1 Step 1b 自动跑），
> 派生产物 = `data/map/task_npc_registry.json`，AS2 经 `DataQueryService.query("task_npc_registry", ...)` 启动期拉取。
> 派生失败 → exit 1 在 build 阶段拦截。

机制三件套：**web 单源 → build 期派生 JSON → AS2 经 DataQueryService 消费 + 失败 gate**。
本方案把同一机制套到 `<groups>/<hotspots>`。

---

## 4. 目标 / 非目标

**目标**
- 拓扑（hotspot id ↔ group ↔ page ↔ frame ↔ unlock-group）收敛为**单一真相源 = map-panel-data.js**。
- 加/改 hotspot 只需编辑 map-panel-data.js 一处；build 自动派生 AS2 侧消费数据；任一层不一致 → build exit 1。
- 取消 `REQUIRED_*_IDS` 硬编码集合带来的**强制重编译**与**手工三处同改**。

**非目标（本方案不动）**
- 运行时权威**不统一**（也无法统一）：导航是 in-Flash 时间轴动作（`淡出跳转帧`）、snapshot 是运行态+存档态，必须留在 AS2。收束的是**配置编写源头（build 期）**，不是运行时。
- 不照搬战宠 102f09a2 的 **C# 直答**模式（理由见 §9）。
- `<avatar_visibility>` 段**保持手写**在 map_panel.xml（半静态门控，已有 [audit-map-avatar-visibility.js](../tools/audit-map-avatar-visibility.js) 守门）。
- Web 侧渲染专属数据（rect/sceneVisual/staticAvatar/layout/preview）**保持手写**在 map-panel-data.js —— 它们 AS2 不需要。

---

## 5. 真相源字段映射（web → AS2 catalog）已核实可派生

### 5.1 groups（→ `REQUIRED_GROUP_IDS` + group meta）

| catalog 需要 | web 来源 | 备注 |
|---|---|---|
| group.id | `_unlockGroups[g].id` | 8 个可锁组 |
| group.label | `_unlockGroups[g].label` | |
| group.lockedReason | `_unlockGroups[g].lockedReason` | 非 base 必填，已满足 |
| group.page | `_pageUnlockGroups` 反查：含该 g 的 page key | 唯一确定 |
| **base 组** | ⚠️ web `_unlockGroups` **无 base 项** | **派生脚本硬编码注入** `{id:base, page:base, label:基地, 无 lockedReason}`，性质同 npc 派生里硬编码 ALIASES |

### 5.2 hotspots（→ `NAVIGATE_TARGETS` + `HOTSPOT_PAGES` + `GROUPED_HOTSPOT_IDS` + `REQUIRED_HOTSPOT_IDS`）

| catalog 需要 | web 来源 | 备注 |
|---|---|---|
| hotspot.id | `_pages[page].hotspots[].id` | |
| hotspot.frame | `_pages[page].hotspots[].sceneName` | 即中文 scene 名 |
| hotspot.group | `getHotspotUnlockGroup(page,id)`（= `_pageUnlockGroups[page].hotspots[id]`） | ⚠️ base 页 `_pageUnlockGroups` 无条目 → 返回空 → **派生时空值映射为 `"base"`**（base 页所有 hotspot → group base） |

> 已核实：`_pageUnlockGroups` 无 `base` 键 → base hotspot `getHotspotUnlockGroup` 恒空 → web 端 `enabled=true`（base 永解锁）。派生规则因此确定：**非 base 页每个 hotspot 必有 unlock group；base 页一律 group=base。**

结论：**100% 可派生**，仅 2 处 base 特例需硬编码，与既有 npc 派生脚本同范式。

---

## 6. 设计：派生产物形态（推荐 A2）

- **A1**：派生重生成 map_panel.xml 的 `<groups>/<hotspots>` 段（avatar_visibility 仍手写）。
  - ✗ 缺点：手写 + 生成混在同一 XML，易误编辑生成段；diff 噪声大。
- **A2（推荐）**：派生独立 JSON `data/map/map_catalog.json`，AS2 `MapPanelCatalog` 改读它（经 DataQueryService，**完全对齐 2026-05-28 npc 迁出先例**）；map_panel.xml 仅保留 `<avatar_visibility>`。
  - ✓ 与现有派生机制同构（一个 build step、一个 DataQueryService key、一套 gate）。
  - ✓ 避免混合 XML。
  - ✓ catalog 加载逻辑（构建 NAVIGATE_TARGETS/HOTSPOT_PAGES/GROUPED_HOTSPOT_IDS）几乎不变，只换数据源 + 字段名。

`map_catalog.json` 形态（草案）：
```json
{
  "groups": [
    { "id": "base", "page": "base", "label": "基地" },
    { "id": "defense", "page": "defense", "label": "第一防线", "lockedReason": "第一防线尚未开放" }
  ],
  "hotspots": [
    { "id": "first_defense", "group": "defense", "frame": "地图-第一防线防区" },
    { "id": "subway", "group": "defense", "frame": "地图-隧道据点" }
  ]
}
```

---

## 7. AS2 + C# + boot 改造

### 7.1 MapPanelCatalog 拆分（评审点 1）

- 拆成两个入口，职责分离：
  - `applyFromCatalogJson(raw)`：吃 DataQueryService("map_catalog") 的 result（含 groups/hotspots）→ 构建 `NAVIGATE_TARGETS` / `HOTSPOT_PAGES` / `GROUPED_HOTSPOT_IDS` / `UNLOCK_META`。
  - `applyAvatarVisibilityFromXml(raw)`：吃 avatar_visibility loader 的 data → 构建可见性表（即现有 `parseAvatarVisibility` 部分独立出来）。
- 保留**结构校验**：group 有 id/page/label、非 base 有 lockedReason、page∈VALID_PAGE_IDS；hotspot 有 id/group/frame、group 已声明、id 不重复。失败 → trace + 回退空表 + return false（"坏数据尽早硬失败"不变）。
- **删除** `setEquals(…, REQUIRED_HOTSPOT_IDS / REQUIRED_GROUP_IDS)` 的"精确集合相等"自检 + 移除两个 REQUIRED 常量（集合正确性改由派生期保证，§8）。
- `resolveHotspotIdByFrameName` / `resolvePageId` / `GROUPED_HOTSPOT_IDS` 逻辑**不变**，只换输入来源。

> ⚠️ 取消 REQUIRED 后，**加 hotspot 不再需要改 AS2、不需要重编译**——消除"三处同改"中的编译耦合。

### 7.2 Loader（评审点 1）

map_panel.xml 瘦身后只剩 avatar_visibility，现有 [MapPanelLoader.load 守卫](../scripts/类定义/org/flashNight/gesh/xml/LoadXml/MapPanelLoader.as#L44)（`groups==undefined && hotspots==undefined` → 判失败）会误杀。两选一：
- **（推荐）** 新建 `MapAvatarVisibilityLoader extends BaseXMLLoader`（路径 data/map/map_panel.xml，守卫改判 `avatar_visibility==undefined`），MapPanelLoader 弃用；
- 或就地放宽 MapPanelLoader 守卫为 `avatar_visibility==undefined`。
推荐前者：命名与新职责对齐，避免"叫 PanelLoader 实际只读 avatar"误导。

### 7.3 C# DataQueryTask("map_catalog")（评审点 2：失败不可静默）

- C# 侧同 npc 派生先例：`DataCache.GetMapCatalog()` 经 `XmlDataLoader.LoadMapCatalog(projectRoot)` 读 `data/map/map_catalog.json` + 缓存 + error 串；`DataQueryTask` 加 `case "map_catalog"` → 失败 `BuildError`。C# 行为与 task_npc_registry 一致。
- **差异在 AS2 boot 消费语义**：npc registry 失败 = 静默降级（只丢红点）；**map_catalog 是导航权威**，query/applyFromCatalogJson 任一失败 → ① 不继续 npc registry（依赖 catalog）；② `_root.发布消息("[错误] 地图配置加载失败，地图面板不可用")` 用户可见报错；③ catalog 留安全零表 → navigate 自然被拒（已有逻辑）。**绝不沿用 npc 的"静默"分支。**

### 7.4 boot 编排（asLoader.xml:522-567，实地核实）

现状顺序 `MapPanelLoader → applyFromXml → query(task_npc_registry) → applyFromQuery`。改为：
```
MapAvatarVisibilityLoader.load → applyAvatarVisibilityFromXml
DataQueryService.query("map_catalog") → applyFromCatalogJson   ← 新；失败=硬报错(§7.3)，不降级
  └─(成功后)→ DataQueryService.query("task_npc_registry") → applyFromQuery  ← 保持依赖序：catalog 先 ready
```
依赖约束不变：MapTaskNpcRegistry.applyFromQuery 读 `Catalog.HOTSPOT_PAGES`，故必须在 applyFromCatalogJson 成功之后。改完经 asLoader 重编译。

---

## 8. build.ps1 接线 + gate

新增 **Step 1c**（紧随现有 [Step 1b](../launcher/build.ps1#L106)）：
- 新脚本 `tools/derive-map-catalog.js`：vm 沙箱载入 map-panel-data.js（同 derive-task-npc-registry.js 手法），**只走公开 API**（评审点 3）：`MapPanelData.exportManifest().unlockGroups` + `getPageOrder()` + `getPage(page)` + `getHotspotUnlockGroup(page,id)`，**不读** `_unlockGroups`/`_pageUnlockGroups` 私有变量 → 按 §5 映射 + base 特例 → 输出 `data/map/map_catalog.json`。
- 派生期校验（失败即 `exit 1`，build 阶段拦截）：
  1. 每个非 base 页 hotspot 必有 unlock group；
  2. hotspot id / group id 全局唯一；
  3. frame（sceneName）非空；
  4. group.page ∈ {base,faction,defense,school}；
  5. **（关键新增）** hotspot 的 frame 在 `data/environment/scene_environment.xml` 有对应 `<BackgroundURL>`（可选强校验，防"加了 hotspot 但没建场景"）。
- 这套 gate **正好拦住 subway 这类**：subway 一旦只出现在 web 而 scene/派生不自洽，build 直接红。

---

## 9. 为什么不照搬战宠 102f09a2 的 C# 直答

战宠目录能 C# 直答（C# 读 pets.xml 直接答 Web、Flash 不参与），因为它是**纯静态、无存档态、查询不触发 Flash 动作**（代码注释自陈"参照 IntelligenceTask"）。地图两点本质不同：

1. 导航是 **in-Flash 时间轴动作**（`淡出跳转帧`），C# 无法直答；
2. snapshot 是**运行态+存档态**，必须 AS2 出。

且地图**已经选了**正确的收束路线（npc 派生先例 / build 派生，SOT=map-panel-data.js）。再引入 C# 当拓扑权威会：多一个角色、与既定 SOT 方向打架、且仍去不掉 AS2 为导航读 catalog。**故 C# 直答路线不取**（注：本方案 C# 仅做 `map_catalog` 的"读派生 JSON 转发"，不是"读 xml 直答业务"，与战宠 C# 直答性质不同）。

> 备选深水区（本方案不含，单独权衡）：让地图 navigate 像选关一样**直接传 frame 名**，去掉 AS2 对 NAVIGATE_TARGETS 的导航依赖。代价是改服务端二次鉴权（`canNavigateToHotspot` 查 group 解锁）的安全模型，不与本次混做。

---

## 10. 迁移步骤（建议顺序）

1. **写派生脚本** `tools/derive-map-catalog.js`（公开 API，§8）+ 单测，先**只生成、不接入**，人工 diff `map_catalog.json` vs 现有 map_panel.xml 的 groups/hotspots，确认 1:1 等价（含 base 特例）。
2. **接 build.ps1 Step 1c** + gate。
3. **C# 改造**（§7.3）：DataCache/XmlDataLoader 读 map_catalog.json + DataQueryTask `case "map_catalog"`；xUnit；`dotnet build` + `dotnet test`。
4. **AS2 + boot 改造**（§7.1/7.2/7.4）：拆 Catalog、删 REQUIRED、拆/建 avatar loader、改 asLoader.xml boot（map_catalog 失败硬报错）；asLoader 重编译；游戏内回归现有全部 hotspot 导航 + **tdh 直达导航**（§12）。
5. **map_panel.xml 瘦身**：删 `<groups>/<hotspots>`，仅留 `<avatar_visibility>`（+ 注释指向 SOT + map_catalog.json，仿 npc 段先例）。
6. **canonical docs 同步**（评审点 6）：更新 [agentsDoc/data-schemas.md](../agentsDoc/data-schemas.md)（map_panel.xml schema 摘要、MapPanelLoader 行项、新增 map_catalog 派生条目）→ 跑 `node tools/validate-doc-governance.js` 通过。
7. **subway 收尾验证**：仅编辑 map-panel-data.js（subway 已在）→ 跑 build → map_catalog.json 自动含 subway → 游戏内地图点击隧道据点可进。**首个"加图只改一处"用例闭环。**

> **心智模型变更（评审点 6，需广播给协作者）**：收束后改 hotspot 拓扑**不再需要 AS2 重编译**，但**仍需跑 `build.ps1`/`node tools/derive-map-catalog.js` 刷新 `data/map/map_catalog.json`**——"改 JS 即生效"只对纯 Web 渲染层成立，拓扑层仍有 build 派生这一步。

---

## 11. 风险与回滚

| 风险 | 缓解 |
|---|---|
| 派生 JSON 与原 XML 不等价（漏字段/特例） | 步骤 1 强制人工 1:1 diff；gate 校验；先并存不接入 |
| 取消 REQUIRED 后丢失"坏数据硬失败" | 校验从"集合相等"转为"派生期结构校验 + 运行期结构校验"，硬失败语义保留，只是不再钉死集合 |
| **⚠ catalog socket-race（v2 发现并修复，2026-06-03）** | **真实回归**：catalog 从旧版"本地文件加载"（MapPanelLoader，零 socket 依赖）改为 socket query（DataQueryService）。`sendTaskWithCallback` 在 socket 未连接时**立即**回 `{success:false,error:"socket not connected"}`（不排队）。boot frame ~64 可能早于 socket 建连（frame_4 的 bootstrap_handshake 异步+重试），导致**关键** catalog query 失败 → catalog 空 → 地图只剩 base 页。旧版 task_npc_registry 没踩雷仅因它嵌在 MapPanelLoader 文件加载回调里、靠文件 IO 延迟把 socket 等到了。**修复**：asLoader.xml boot 增加 socket-ready 轮询门（`DataQueryService.isAvailable()`，200ms×50≈10s），就绪后再 query；task_npc_registry 嵌在 catalog 成功后（socket 必然已连）。**需重新 asLoader 重编译。** |
| 症状鉴别（empty-catalog vs 正确锁态） | "4 区域闪现→只剩 base" 有两因：① catalog 空（上行 race / query 失败，伴随 boot 报错 toast + base 房间也点不动）；② 存档本就只解锁 base（faction/defense/school 未达解锁门槛 → 正确隐藏；"闪现"是 web 静态 manifest 预渲染，非 bug）。鉴别：看 boot 是否弹 "[错误] 地图配置加载失败…" + base 房间能否进。subway 在 defense 组，需 p_main≥14 + 一种载具才解锁 |
| AS2 改动需重编译 | asLoader 已开，重编译可行；本方案一次性付出，换取后续加图零 AS2 改动 |
| 回滚 | 各步独立提交；最坏回退到"map_panel.xml 手写 groups/hotspots + REQUIRED" 的当前状态 |

---

## 12. 验证清单

- [x] 人工 diff = 1:1 等价（除 subway：web SOT 有、旧 xml 无 → 正是本次要修的；9 group / 39 旧 hotspot 全等）
- [x] `node tools/derive-map-catalog.js` 生成 map_catalog.json，含全部 40 hotspot / 9 group（含 base），subway→defense→地图-隧道据点；幂等（unchanged 不刷 mtime）
- [x] **C#（评审点 5）**：`dotnet build` 通过；`dotnet test` 全绿（576/576，含 8 个新 MapCatalogTests：解析 / 缺失文件 / 空 hotspots / 空 groups / Cache 成功 / Cache error 缓存 / Query 成功 / Query 缺失=success:false 含 "map_catalog unavailable"）
- [x] **文档治理（评审点 6）**：data-schemas.md 已同步；`node tools/validate-doc-governance.js` → `ok`
- [~] AS2 compile：TestLoader smoke `0 个错误 0 个警告`（新鲜 8:52:06）——但 smoke 编译的是 TestLoader 非 asLoader，**boot 改动需 asLoader 重编译方为真凭据**（见下"待人工"）
- [ ] **待人工：asLoader 重编译**（asLoader.xml boot 改动 + 三个改动类进 asLoader.swf）
- [ ] **待人工·游戏内**：现有全部 hotspot 导航回归正常（base/faction/defense/restricted/school）
- [ ] **待人工·游戏内（评审点 5）**：任务完成条 / Native HUD 刘海屏 tdh 直达导航回归（`resolveDeliverableState` → `canNavigateToHotspot` → `NAVIGATE_TARGETS`，[通信_鸡蛋_任务系统.as:527](../scripts/通信/通信_鸡蛋_任务系统.as#L527)）
- [ ] **待人工·失败注入**：临时把 map_catalog.json 改坏/删除 → 进游戏应明确报错 + 地图面板不可用（**非**静默降级，§7.3）
- [ ] **待人工·游戏内**：subway 地图点击 → 进入隧道据点（收束闭环验证）
- [ ] **待人工·游戏内**：锁区提示（lockedReason）仍正确显示

---

## 附：本方案涉及文件

- 改：`scripts/类定义/org/flashNight/arki/map/MapPanelCatalog.as`（拆 applyFromCatalogJson + applyAvatarVisibilityFromXml、删 REQUIRED）
- 改：`scripts/asLoader/LIBRARY/asLoader.xml`（boot 编排 §7.4，需重编译）
- 改/新：`scripts/类定义/org/flashNight/gesh/xml/LoadXml/MapAvatarVisibilityLoader.as`（新；或就地放宽 MapPanelLoader）
- 改：`launcher/build.ps1`（+Step 1c）
- 改：`launcher/src/Tasks/DataQueryTask.cs`（+case map_catalog）、`launcher/src/Data/DataCache.cs`、`launcher/src/Data/XmlDataLoader.cs`（+LoadMapCatalog）
- 改：`data/map/map_panel.xml`（瘦身留 avatar_visibility）
- 改：`agentsDoc/data-schemas.md`（schema 摘要 + map_catalog 条目）
- 新：`tools/derive-map-catalog.js`、`data/map/map_catalog.json`（派生产物）、`launcher/tests/Tasks/MapCatalogTests.cs`（或并入现有）
- 单源（SOT，不改结构）：`launcher/web/modules/map-panel-data.js`
- 不动：`MapTask.cs`（透传桥，导航/快照仍透传 Flash）、`StageSelectPanelService.as`、Web 渲染专属数据
