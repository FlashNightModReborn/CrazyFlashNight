# WS6 事件日志 / 任务树 — 施工设计（2026-06-09）

> 延续 [web 任务面板迁移] 主线最后一块（`log` tab，当前为占位「正在开发中」）。
> 与 [任务系统 AS2 内存驻留审计](../) 结论咬合：WS6 是让审计 Phase 1（description 下沉）变得划算的**消费者**，二者合并施工。
> 协作约束：本文档是 WS6 的 SOT，先于编码；字段名/契约以此为准，改动同步回此文件。

## 0. 一句话方案

任务树/事件日志的数据**按可变性切分单一权威**：

- **静态内容**（树拓扑 + title + description + 明细字段）：build 期从 `data/task/*.json`（游戏权威源）派生出 web 直读目录 `task_catalog.json`，**web 自渲染，零 AS2 传输**。
- **动态进度**（哪些已完成 / 当前进行）：AS2 经 bridge 发一份**小只读叠加**（链进度 + 已完成 id 集 + 当前任务 id），web 叠加状态。
- **剧情对话回放（轻量内联文本，2026-06-09 用户选定）**：web「重播」按钮**按需回传**单任务对话文本行，详情区内联展开纯文本，**不关面板（连续）**。对话文本单权威留 AS2（catalog 不含本体，点击才回传一条任务）。富立绘对话框待对话框整体迁 web 后替换。

> 反模式（明确不做）：把 236 任务全表（含 description/对话）每次开面板经 `LiteJSON.stringify` 过桥；或把可变存档态复制成 C# 可写副本（双写漂移）。

## 1. 数据流架构

```
┌─ 静态（不变，单 SOT = data/task/*.json）──────────────────────────┐
│ data/task/*.json + data/task/text/*.json                          │
│        │ build Step 1e: tools/derive-task-catalog.js              │
│        │   （含闭包校验器：所有 $KEY 必须可解析，否则 exit 1）       │
│        ▼                                                           │
│ launcher/web/modules/tasks/task-catalog.json                      │
│        │ web 直读（import/fetch，类比 map-panel-data.js）           │
│        ▼                                                           │
│ task-panel.js  log tab：渲染任务树 + 事件日志明细                    │
└───────────────────────────────────────────────────────────────────┘
┌─ 动态（可变，单权威 = AS2 存档态）─────────────────────────────────┐
│ _root.task_chains_progress / tasks_finished / tasks_to_do          │
│        │ gameCommand: taskTreeState（小叠加，只读快照）             │
│        ▼  TaskTask 桥 → task_response                              │
│ web 叠加 完成/进行 状态徽章                                          │
└───────────────────────────────────────────────────────────────────┘
┌─ 对话回放（文本单权威 = AS2）──────────────────────────────────────┐
│ web 点「重播」→ gameCommand: taskReplayDialogue {taskId, which}     │
│        ▼ AS2 回传 lines:[{speaker,sub,text}] → web 详情区内联渲染（不关面板） │
│ 原版 Flash 对话框同步渲染（零对话文本过桥）                          │
└───────────────────────────────────────────────────────────────────┘
```

## 2. SOT 与派生 — `tools/derive-task-catalog.js`（build Step 1e）

对标 `tools/derive-map-catalog.js`（Step 1c）：node 脚本读源 → 校验 → 写派生 JSON，失败 `exit 1` 在 build 阶段拦截。

**与 map 派生的差异**：map 的 SOT 是 web JS（`map-panel-data.js`）→ 派生 AS2 JSON；**task 的 SOT 是游戏 JSON（`data/task/*.json`，AS2 也读它）→ 派生 web JSON**。因此 web 拿到的是同一源的**只读投影**，不存在 AS2/web 双源漂移。

**读取**（按 manifest，不读死数据）：
- `data/task/list.xml` → 各 `*_tasks.json` 的 `tasks` 数组合并
- `data/task/text/list.xml` → 各 `*_text(s).json` dictMerge → `task_texts`
- 解析规则镜像 AS2 `TaskUtil.getTaskText`：`$` 前缀查 `task_texts`，否则字面量

**闭包校验器（关键，审计 Phase 1 前置硬门控）**：
- 对每个任务的 `title` / `description` / `get_conversation` / `finish_conversation`，若值以 `$` 开头则该键**必须存在**于合并后的 `task_texts`，否则 `exit 1`（防 `$KEY` 缺失运行时显示原始键）。
- dup-id 守卫、chain 序号完整性（与 `检查任务数据完整性` 同口径）。

**输出 `task_catalog.json` 形状**：

```jsonc
{
  "version": 1,
  "tasks": {
    "10014": {
      "id": 10014,
      "chain": ["主线", 14],          // [链名, 序号]；无序号链序号为 null
      "type": "主线",                  // = chain[0]
      "title": "解析后的标题",
      "description": "解析后的描述",    // ← 审计 Phase 1 的下沉文本，落在 web 这份
      "npcName": "交付NPC名",           // = finish_npc
      "stageReq": { "name": "...", "difficulty": "..." } | null,
      "itemReqs": [ { "name": "...", "count": 1, "kind": "submit|contain" } ],
      "rewards": [ { "name": "...", "count": 1 } ],
      "getRequirements": [10013],      // 前置任务 id（树排版/前置展示）
      "hasGetConv": true,              // get_conversation 非空（决定「接取对话」重播按钮是否显示）
      "hasFinishConv": true            // finish_conversation 非空
      // 注意：不含对话文本本体（留 AS2，点击才按需回传单任务对话文本行 → web 内联渲染）
    }
  },
  "chains": {                          // 预建链拓扑（web 渲染树直接用）
    "主线": [ /* 按序号升序的 taskId 列表 */ ],
    "大学": [ ... ]
  }
}
```

**不含**：对话文本本体、`finish_remote`（写路径权威字段，留 AS2）、运行态门控字段语义（catalog 仅展示投影）。

## 3. AS2 协议扩展（`TaskPanelService.as`）

新增 2 个 gameCommand（沿用 `task_response` 信封 + `callId`）：

### 3.1 `taskTreeState` — 动态进度小叠加（只读）
```
入: { callId }
出: { task:"task_response", callId, success:true,
      chainsProgress: { 主线: 14, 大学: 3, ... },   // 复制 _root.task_chains_progress（数字）
      finished: [ "0","10014",... ],                 // _root.tasks_finished 中 >0 的 id 键
      active:   [ 10021, 40013, ... ] }              // tasks_to_do 的 id（当前进行）
```
- 纯读 `_root` 存档态，不写。载荷极小（数字 + id 列表），非全表。

### 3.2 `taskReplayDialogue` — 对话回放（轻量内联文本，2026-06-09 用户选定）
```
入: { callId, taskId, which: "get" | "finish" }
出: { task:"task_response", callId, success:true, which, lines:[{speaker,sub,text}] }
    （对话为空回 success:false, error:"no_dialogue"）
```
> 设计变更：原设计为「命令回传 SetDialogue 在 Flash 对话框播 + closePanel」（Option A）；用户选定 **Option B 轻量内联文本**——AS2 按需回传单任务对话文本行，web 详情区内联展开，**不关面板（体验连续）**。富立绘对话框待对话框整体迁 web 后替换本文本态。
- AS2 解析 `getTaskText(get/finish_conversation)` 得对话数组，逐行取 `name/title/text`，`name/title` 经 `_root.getDialogueSpecialString` 解析 `$PC` 等特殊串，回 `{speaker,sub,text}`。
- 按 `taskId` 从 `TaskUtil.tasks` 取（**注意双键**：副本任务用中文 title 键，见审计；这里按 id 取即可）。
- 对话文本仍单权威留 AS2（catalog 不含本体），点击才按需回传【一条任务】的对话，载荷小、懒加载。

> `taskSnapshot` / `taskDetail` 等现有命令不变；log tab 的明细优先走 web catalog（零往返），仅对话重播回传 AS2。

## 4. C# 桥（`TaskTask.cs` + `WebOverlayForm.cs`）

镜像 WS5 的做法：
- `TaskTask.cs` cmd 透传：`treeState→taskTreeState`、`replayDialogue→taskReplayDialogue`（保留 `taskId`/`which`/`callId`）。
- `WebOverlayForm.cs`：`case "treeState":` / `case "replayDialogue":` 加入按 panel 路由到 `_taskTask.HandleWebRequest` 的堆叠 case。
- xUnit：treeState/replayDialogue 的 action+参数透传、`which` 透传、response 保形。

## 5. web — `log` tab 实现（`task-panel.js` + `task_panel.css`）

填充现有 `task-panel-logview` 占位：
1. **加载 catalog**：模块顶层 `fetch('/modules/tasks/task-catalog.json')`（或随面板首次切到 log tab 懒加载），缓存到 `_catalog`。
2. **切到 log tab**：发 `taskTreeState` 取进度叠加 → 用 `_catalog.chains` + 叠加渲染树。
   - 每链一列/一段，节点按序号；状态徽章：已完成（`finished` 命中）/ 进行中（`active` 命中）/ 历史。
   - 镜像原版：`委托` 等无序号链可单列「已完成委托」列表；主线为主干。视觉对齐非 1:1 像素。
3. **点击节点 → 事件日志明细**：从 `_catalog.tasks[id]` 直接渲染（title/description/stageReq/itemReqs/rewards/npcName），**零 AS2 往返**。
4. **对话回放按钮（轻量内联文本）**：`hasGetConv` / `hasFinishConv` 为真才显示「接取对话」/「完成对话」按钮；点击发 `taskReplayDialogue {taskId, which}`，AS2 回传单任务对话文本行，web 在详情区 `.tlv-dialogue` 内联展开（不关面板，连续）。`speaker/sub/text` 经 **`PanelTooltip.convertAS2Html`** 渲染 AS2 htmlText 子集（见下「HTML 渲染」）。

### 5.1 HTML 渲染（2026-06-09，真机暴露对话含 AS2 htmlText）
对话的 `name/title/text` 可含 AS2 htmlText 标记（如 `$PC_TITLE`→`HeroUtil.getHeroTitle()` 回的 `<FONT COLOR='#FFCC00'>动态称号</FONT>`）。直接 `escHtml` 会把标签当字面量显示。
方案：**复用全项目统一的 `PanelTooltip.convertAS2Html`**（tooltip.js，物品/情报/竞技场 tooltip 同款），零新轮子即得 AS2 级兼容。
为后续对话富文本预做铺垫，在**不引入 HTML 解析器/不增复杂度**前提下，把 `convertAS2Html` 从「FONT(color/size)+B/I/U+BR」**加性扩展**到再支持 `<FONT FACE>`（→font-family，白名单字符）+ `<P ALIGN>`（→text-align）——加性、安全、全 panel 受益。
**刻意不做**（留待对话框整体迁 web 的富文本阶段）：`<A HREF>`（asfunction 无法 web 执行+安全面）、`<IMG>`（外链加载/排版/立绘）、`<TEXTFORMAT>`（制表/缩进）、`<LI>`（需列表上下文）——这些需要真正的解析器/布局工作，属对话框迁移范畴。
5. 复用现有：detail 缓存风格、骨架屏、`prefers-reduced-motion` 降级、黑白灰功能层配色、方形 3px 圆角。

### 5.2 图表视图（BALDR SKY 风任务树，2026-06-09 用户选定「完整」）
动机：列表是线性展示，看不出**任务线之间的前置依赖顺序**（原版实现草率）。参照 BALDR SKY SCENARIO CHART 的六边形节点+连线图，空间化呈现前置关系。
数据实证（`node` 分析 data/task）：238 任务但 **237/238 仅 0-1 个前置**（最多 2），跨链边仅 28(11%)、且**绝大多数是「主线里程碑→侧链入口」**——是清爽的**主干+分支**结构，**不是缠绕 DAG**。故布局用「拓扑深度分行 + 按链分列 + 前置连线」即可，**无需 dagre/Sugiyama 重型算法**。
- **数据**：catalog 加回 `req`（前置 id；之前点4瘦身删过，图表需要，约 +3KB）。委托等无序号链不入图（无前置顺序，列表展示）。
- **布局**（web 运行时算，`computeChartLayout(mode)`）：主线列居中、其余链交替左右分列；y=拓扑深度（最长前置链，memo+占位防环）；边=每节点 req→自身（含跨链虚线）。
- **章节模式**：仅留 链头/尾 + 分支点(跨链出边) + 合并点(入度≥2) + 进行中，y 按 kept 子集紧凑 rank，边走「最近 kept 祖先」折叠线性段。详细模式=全节点。
- **渲染**：DOM 六边形(clip-path flat-top) + 一层 SVG 画边（238 节点 DOM 可承受，节点是真 DOM→点击复用事件委托）。状态色黑白灰真值（已完成银/进行中白发光/未解锁暗），**选中=白环放大+辉光（不动焦点橙，与列表选中同语言）**。
- **缩放**：100/50/25% 用 CSS `zoom`（WebView2=Chromium 支持，reflow 滚动区，省手算尺寸）。大图(主线78节点≈5800px高)靠拖拽平移+缩放浏览。
- **拖拽平移（2026-06-09 用户反馈：滚动条不直观）**：左键拖拽视口平移取代滚动条（隐藏滚动条视觉、`grab/grabbing` 光标、保留滚轮）。`mousedown` 记快照→`document` 级 `mousemove/mouseup`（处理拖出视口）→改 `scrollLeft/Top`；「点击 vs 拖拽」按 4px 阈值判定，超阈值才平移并置 `_chartDragMoved` 抑制随后的 `click`（防误选节点），`onClose` 清理 document 监听。
- **交互**：事件日志内「列表/图表」分段切换；点六边形→`selectLogNode`（与列表共用）→右侧明细+内联对话；选中同步高亮 hex 并 scrollIntoView。
- **集成**：列表/图表共用同一右侧 `tlv-detail`+`renderLogDetail`；左栏 `tlv-left` 宽度按 `data-logview` 切换（列表 320px、图表 flex 占大）。
- **任务线配色（2026-06-09 制作组：暴露 config，opus 给默认，写手后续调）**：三杠杆经 CSS 自定义属性下发——`--hex-rim`(外环=链身份主区分)/`--hex-num`(数字)/`--hex-face`(节点面，可选链覆盖)。`CHART_CHAIN_STYLE`(task-panel.js 顶部，写手可改)按链给 {rim,num,face?}；默认 rim+num 区分链、face 仍由状态(已完成/进行中/未接取)驱动，故**链色(环/数字)与状态(面)正交互不抢读**。阵营链(黑铁会/铁枪会)按要求预留"黑底白字"模板(face 黑+num 白，状态靠辉光/暗淡)。颜色取低饱和，不抢焦点橙(仅提交NPC)。**3 杠杆足够**：rim 主分 + num special + face override，可清晰区分 10+ 链。
- **对话回放进度门控（2026-06-09 真机发现"完成对话对未完成任务也冒出"）**：catalog 的 hasGetConv/hasFinishConv 是静态(任务是否定义对话)；renderLogDetail 再按进度过滤——接取对话仅"已接取(active/done)"显示，完成对话仅"已完成(done)"显示，避免回放未到达剧情=剧透/语义不通。徽章三态(进行中/已完成/未接取)。
- **重开重置（修"图表退出重进，按钮停在图表"）**：DOM 复用→onOpen 须重置 `_logView/_chartZoom/_chartMode` + canvas zoom + **三组工具栏分段按钮 .active**(`resetChartToolbarButtons`：列表/详细/100%) + 拖拽态；`onClose` 清拖拽 document 监听。

## 6. 文件清单

| 文件 | 改动 |
|---|---|
| `tools/derive-task-catalog.js` | **新增** 派生脚本（含闭包校验器） |
| `launcher/build.ps1` | **新增** Step 1e 调用派生 + Step 7 资产校验加 `task-catalog.json` |
| `launcher/web/modules/tasks/task-catalog.json` | **派生产物**（不手写，build 生成） |
| `scripts/类定义/org/flashNight/arki/task/TaskPanelService.as` | **新增** handleTreeState / handleReplayDialogue + 注册（cp+Edit 保 BOM） |
| `launcher/src/Tasks/TaskTask.cs` | cmd 透传 treeState / replayDialogue |
| `launcher/src/Guardian/WebOverlayForm.cs` | case 路由 |
| `launcher/tests/Tasks/TaskTaskTests.cs` | +xUnit facts |
| `launcher/web/modules/tasks/task-panel.js` | log tab 渲染 + catalog 消费 + 重播 |
| `launcher/web/css/task_panel.css` | 任务树/日志样式 |
| `launcher/web/modules/tasks/dev/harness.html` | mock catalog + treeState/replayDialogue + QA |
| `launcher/README.md` / `agentsDoc/testing-guide.md` / `agentsDoc/data-schemas.md` | 协议 + 派生表 + QA 计数 |

## 7. 契约与不变量

- C1 **单 SOT**：`task-catalog.json` 是 `data/task/*.json` 的派生只读投影，**永不手写**；改任务数据只改源 JSON，build 重派生。
- C2 **闭包性**：catalog 内任何引用文本的 `$KEY` 在派生时已校验存在于 `task_texts`；缺失 = build fail，不进 launcher。
- C3 **可变性切分**：catalog 只含静态展示投影；进度/完成/进行态只来自 `taskTreeState` 实时读 `_root`，**绝不缓存进 catalog**。
- C4 **对话单权威**：对话文本只在 AS2；catalog 仅持 `hasGetConv/hasFinishConv` 布尔，点击才按需回传【单条任务】对话文本行 web 内联渲染（不批量、不进 catalog）。
- C5 **双键陷阱**（审计）：`taskReplayDialogue` 按 id 取任务即可；副本任务（菲尼克斯/锡蒙利 Lv*）的中文 title 双键是 stage-select 活路径，**勿删**。
- C6 **死数据**：派生脚本只读 manifest 内文件，天然不含 `mercenary_tasks_old.json` / `easteregg_*`。

## 8. 分阶段与风险

| 阶段 | 内容 | 风险 | 收益 |
|---|---|---|---|
| Phase 0 | 零风险清洗（删死数据文件 + `rewards_disabled`/`genshin_impact`） | 极低（审计已验证零引用） | 去噪 |
| Phase A | `derive-task-catalog.js` + build Step 1e + 闭包校验器 | 低（纯新增派生，可独立跑验证） | WS6 + 审计 Phase1 地基 |
| Phase C | AS2 `taskTreeState` + `taskReplayDialogue` + C# 桥 + 测试 | 低（只读叠加 + 命令回传，复用 WS5 模式） | 协议就绪 |
| Phase B | web log tab（树渲染 + 明细 + 重播） | 中（新 UI，harness 可 headless 预览） | WS6 落地 |
| Phase D（**已降级，收益证伪**） | AS2 `task_texts` 剔除 description 键 | 高（委托板仍同步读 description，须先迁；且需 SWF 重载+手测） | **仅 ~16KB**（2026-06-09 实测：description 极小，task_texts 97% 是对话 438KB＝真正大头但 must-stay。原估 150-250KB 系高估一个数量级，已作废） |

> Phase A–C 不触动 AS2 运行态 `task_texts`（getTaskText 缺键已天然降级），可安全先上；Phase D 是收尾的内存兑现，单独验证。

## 9. 测试计划

- `derive-task-catalog.js`：自带 `--check` 干跑（不写文件，只校验闭包/dup/chain），CI/build gate。
- `TaskTaskTests.cs`：treeState/replayDialogue 桥接 facts。
- harness `?qa=1`：mock catalog + treeState/replayDialogue；新增 task-ui25+（切 tab→渲染树、点节点→明细、重播按钮可见性按 hasConv、空对话不发请求）。
- `node tools/run-tasks-harness.js --shot`：Edge headless 截图 log tab。
- 人工手测：游戏内切「事件日志」tab、点节点看明细、点重播看 Flash 对话框、副本任务对话正常。

## 10. 与既有系统一致性

- 派生管线对齐 build Step 1b/1c/1d（`derive-*.js` + exit-1 gate）。
- web 直读派生数据对齐 `map-panel-data.js` / `stage-select-data.js`（面板 import/fetch 自有数据）。
- 协议信封 `task_response` + `callId` 双层桥对齐 WS1–WS5。
- SOT 纪律对齐 map_catalog（单源派生，删手写权威）。
