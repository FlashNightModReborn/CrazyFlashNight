# 地图内容工作台

2026-09-06 第二阶段源码：页面／地点／NPC／任务端点／素材与同一 C# 地图域。维护者已确认本轮作者流程修复可行，并于 2026-09-07 授权跟进上游与正式发布；最终身份／共识／部署状态以[运行库记录](../../docs/runtime-build-reproducibility.md)及[两阶段记录](../../docs/地图工作台与CSharp收束-两阶段施工-2026-09-06.md)为准。作者流程确认不代签全部真实游戏旅程。

游戏内入口：**其他 → 工具 → 地图工作台**。本阶段验收用根目录 `地图工作台测试启动.cmd` 的隔离候选；不要把旧正式 Core 与新的 v2 定义／asLoader 混用。不会自动推广候选。

## 作者操作

第一次使用优先阅读[操作指南](../../launcher/web/help/map-workbench.md)：从“挪动基地屋顶再撤销”的零写入练习开始，随后按对象、条件、人物、端点、素材和应用排错分主题学习。游戏内 `?`、左侧“第一次使用：跟着做一遍”和“怎样编辑这类对象？”共用同一只读帮助页，支持搜索、上下文定位、Esc 返回与原焦点恢复。

1. 点击对象树的分类标题，再选“新建”；空页面也能新建地点表现、图块和分层。页面可复制／排序，物理地点只绑定已发布且唯一登记的真实场景。复制页面只产生新表现 ID，不复制人物或导航路由。
2. 在“素材库 / 导入”浏览已登记图片与候选、导入 PNG／WebP／JPEG、裁切，或按发现的发布元件提取静态帧。候选有来源、尺寸、透明背景与对照；文件尚未写入发布目录。来源缺失／变化会显示原因，不能冒充可用图片。
3. 人物身份、人物驻点和头像分别建立。驻点须显式选择真实 NPC 实例；只放头像不代表可对话。现场检索名与历史别名不同于显示名。未接入的驻点仍可做地图表现，但不能成为新任务导航的已就绪证明。
4. 条件编辑器提供全部／任一、链区间、任务状态、基建等级和现役注册事实；外观变化按顺序选择首个满足项。方案 A/B 可独立编辑、复制或从游戏只读事实复制，不修改存档。数字留空是未知；链进度不会自动制造历史任务完成或可交付。
5. 对照两套方案、保存前内容和原因树，检查所有受影响文件后应用；重启候选再看游戏效果。删除被引用对象前会列出任务、驻点和表现。撤回只恢复本批字节，遇后续独立修改或仍被共享引用的新增图片会拒绝覆盖／删除。

默认是属性栏＋大画布；滚轮／+/- 缩放，中键或空格拖动平移，“聚焦所选”“玩家取景”复位。“专注画布”隐藏属性，Esc 返回；关闭保留草稿。图块、头像与地点边框可拖动或填写坐标；相机不改变数据或随倍率扩大 backing canvas。图块变化由 C# 同步关联 hotspot 并集，头像坐标相对地点。分层顺序最终使用 `buttonRect.y`，不是任意拖放原生按钮矩形。

每次打开默认“创作视图”：所有页／分层可选，当前方案隐藏的图块、地点与头像以文字／虚线标记，仍可编辑；单击只选中，至少 3 CSS 像素的拖动才产生移动。切到“玩家预览”后严格显示同一快照的可见性，画布只读；整页隐藏时显示页面名称、原因与返回创作入口，不静默切到基地；仅当前分层隐藏时提示位于画布内，其他可见分层仍可点击。切换只影响子文档呈现，保留草稿、方案、相机与分层，不发业务请求；不修改 C# 结果、条件、导航许可或玩家事实。外观未知时仅基础图／占位，动态室友不猜测性别。

“读取游戏事实”只在真实游戏连接下可用；离线服务器不伪造实时玩家。预览运行同一生产 MapPanel，消费同一 C# snapshot v4，不再使用全部解锁的设计假状态。预览不执行导航。物理地点可进入不代表该地点的具体关卡已解锁，关卡条件仍归现役关卡服务。

## 真源与职责

| 内容 | 唯一人工真源／执行方 |
| --- | --- |
| 页面、物理地点、人物／驻点、地图条件、表现、素材元数据 | `data/map/map_definition.json` v2；GUI／CLI 同一 C# 内核 |
| 任务接取／交付选谁，固定或跟随 | 该任务原有 `data/task/*.json` 的 `get_endpoint / finish_endpoint` |
| 任务 ID、前置、目标、奖励、对白、链序号、远程交付开关 | 既有任务源与 AS2；地图工作台不编辑 |
| 链进度、历史、活动／可交付、基建、当前场景与生命周期 | AS2 采样有限事实；可交付仍调用 `taskCompleteCheck` |
| 地图规则、人物别名、端点／驻点选择、当前地点与导航资格 | C# `MapDomainService` |
| 接取／完成、背包／奖励、存档、StageRunSession、场景执行 | AS2，执行前再次检查新鲜度与生命周期 |

稳定 `locationId` 是物理地点；页面 `hotspot.id` 是表现。页复制复用 `npcId / placementId / locationId`，只重建页内表现、图块、头像和分层身份。新物理地点不能重复登记同一真实场景。动态室友继续用现役性别事实。

`fixed(npcId,placementId)` 不会在驻点消失后跳去另一处；`followCurrent(npcId)` 必须唯一解析出存在且已接入的驻点，零个、多处或未知均解释不可达。每个 role 迁移时删除对应旧 `*_npc / *_npc_hotspot` 字段，不双写 sidecar。旧空 hotspot 保留任意同名现场匹配，不能无证据改成固定。初始导入的未绑定旧驻点有只读 `legacyWorldAdapter`；新建不能设置，实质改变驻点／人物检索配置会清除。显式绑定后来源未就绪也不能借该兼容标记放行。

`MapWorldCatalog` 在制作期核对 scene environment、资产 locator、XFL／FLA、SWF linkage、主文件真实引用、NPC 实例与来源摘要；脚本化／多重含糊实例显示未就绪。`sceneBinding / worldBinding.runtime` 是内核派生的发布接入记录。运行时只需发布 SWF 与地图／任务数据，不依赖 XFL／FLA。

`avatarSources` 和 XFL 校准信息保留导入来源，不拥有第二套现役坐标。Web 数据脚本只适配 C# 启动投影；Node 审计经 `tools/lib/map-domain.js` 获取同一投影。资源清晰度能力由 C# 基于已验证尺寸、矩形与外观分支计算，不固化旧四页 capability 表。

## 协议和生效边界

`map_domain` 仅 XMLSocket，HTTP／Web 不能伪造实时事实。`hello` 安装 v2 内容与会话；`project` 携带内容摘要、会话、事实 revision、scene epoch、ready 和有界 facts。snapshot v4 供完整地图、HUD、任务端点、NPC 索引及自动续接使用。AS2 同步 getter 只读已确认投影；导航必须 fresh RPC，并在淡出前重查事实签名、场景、会话、路由及调用方生命周期。

结算“前往交付”只登记意图：奖励终态、Web exact close 和 pause lease 释放后重新采样、选择当前优先目标；旧 run 回调不得进入新 run。任务真正完成仍再次检查现役 AS2 条件。HUD `mr` 表示已接受投影变化，使同一地点的可见图块／外观也会刷新；不是游戏逻辑或存档字段。

工作台维护协议为 `panel=map-workbench, domain=map_workbench`，保留 exact panel instance／origin／callId。作者子文档只接受 exact 父子 Window、同源和本轮 session 的 `map-authoring-input / map-authoring-preview`；不安装游戏写桥。模拟事实、草稿、磁盘内容和当前游戏已加载内容分开显示。应用／撤回后须退出启动器并重新打开同一候选，不能只返回游戏标题页；不承诺热更新。

## 文件批次与素材

`MapAuthoringStore / MapAuthoringPlan / MapChangeJournal` 共用摘要 CAS、规范化项目 mutex、引用验证和恢复记录。先写恢复记录，再逐文件原子替换；地图定义最后写入。整个批次不是多文件系统原子事务。启动检查未完成批次，能够证明前／后像则收束，否则拒绝不一致内容；不覆盖外部修改。已持久记录 applied 后，标记清理失败只能查询，不倒转成功批次。

- 定义与任务源摘要均必须匹配；任务源由 taskId 定位，浏览器不能传路径。
- 仅补丁选中任务对象的端点，其他任务与非端点字段受保护；撤回恢复原字节／BOM／换行。
- JSON 请求最多 256 KiB、256 个操作；批次最多 128 个文件、前后备份合计 32 MiB。
- 图片最多 16 MiB、4096 单边／1600 万像素，仅静态解码。发布必须实际为 WebP，不接受改后缀。Skia 无损往返逐 RGBA 校验；透明 RGB 需要时复用既有 Pillow exact 转换器，不放宽像素门。
- SWF 提取只接受目录发现的 linkage＋源 SHA，明确 1–512 帧与 0.125–2 倍率，实际帧数再校验；依赖外部 ImportAssets 的元件明确拒绝。数字 SpriteId 仅作为该摘要下临时定位，不成为内容身份。FFDec 隐藏子进程有超时与输出边界，绝不改 SWF。
- `tmp/map-workbench/assets` 是内容寻址候选；应用只新增 `launcher/web/assets/map/imported/<sha256>.webp`。已有共享图片不随对象删除清除；撤回新增图片前检查恢复后的地图引用及其他 Web／data 文本引用。
- `tmp/map-workbench/changes` 与 `pending` 是恢复依据，仍需撤回／对账时不要清理。写入结果未知只查原操作，不自动重放。来源目录可重新读取而保留草稿。

旧地图 XML、catalog／NPC registry／HUD sidecar 与加载／生成链已删除。旧头像／图块导出命令仅保留退役提示，不再覆写 JS 或依赖固定 SpriteId；地图图片从工作台候选流程接入。`task-catalog.json` 仍供事件日志使用，其端点检查与 NPC 显示名来自同一 C# 域。

## CLI 与离线验证

需要仓库锁定 .NET SDK，统一经 `launcher/resolve-dotnet.ps1`。静态图片使用现役 SkiaSharp；精确透明像素兜底复用现有 Python＋Pillow。SWF 提取另需现有 `tools/ffdec/ffdec-cli.exe` 及其运行依赖；不自动安装新依赖。

```powershell
powershell -NoProfile -File tools/map-workbench/run.ps1 -Command read
powershell -NoProfile -File tools/map-workbench/run.ps1 -Command validate-content
powershell -NoProfile -File tools/map-workbench/run.ps1 -Command serve
# 本项目作者服务：http://127.0.0.1:18765/；按钮会真实写入项目
```

CLI `MapWorkbench.dll <命令> <项目根> [端口]` 的 `api` 从 stdin 接收 JSON，stdout 返回一条 `{success,data|error}`。`read/catalog/project/render-definition/validate-content/hud` 是检查或投影入口；`api` 支持 `read/catalog/preview/apply/query/undo/recover/asset-inspect/asset-crop/asset-extract/open-source`。preview 接收 `expectedDigest, expectedTaskDigest, changes, facts, compareFacts`；apply 增加操作编号但不把模拟事实写入项目。changes 支持 `kind,id,pageId,action,values`，`action` 为 edit/create/copy/delete/reorder；任务只接受端点 edit。

`project` 是纯离线向量入口；`validate-content` 只读验证，不运行恢复。`read/catalog/preview` 的作者维护入口会先检查／恢复历史未完成批次；普通无未完成批次的 preview 不改内容。离线 serve 只在显式启动时监听回环，验证 Host／Origin，JSON 与二进制上传分开限流；不成为常驻服务。

自动界面写入测试必须在独立副本：

```powershell
# 初次迁移施工时先 build CLI，再用 migrate-v2.js --prepared；已是 v2 的项目直接复制当前定义
powershell -NoProfile -File tools/map-workbench/new-test-fixture.ps1
# 使用返回的 fixtureRoot；它只复制地图所需源码／数据／Web，不复制玩家存档
powershell -NoProfile -File tools/map-workbench/run.ps1 -Command serve -ProjectRoot <fixtureRoot> -Port 18766
# 另一个终端
$env:MAP_WORKBENCH_FIXTURE = '<fixtureRoot>'
node tools/map-workbench/test-ui-v2.js
node tools/map-workbench/test-ui-mutations.js
node tools/map-workbench/test-ui-npc.js
node tools/map-workbench/test-help.js
node tools/map-workbench/test-view-modes.js
```

副本位于驱动器根下 `cf7-map-ui-fixtures/ui-<随机编号>`，规避 Windows 长路径；均为独立拷贝，不用 hardlink。测试经同一 C# HTTP 内核和生产 MapPanel，成功后恢复副本的定义与任务原字节。`test-browser.js / test-viewport.js` 旧命令名转到安全副本测试，不再修改当前工作区。

`test-help.js` 同时覆盖旧草稿冲突：画布显示明确暂停原因与处理按钮、编辑锁定、最小／大视口按钮可达、导出／关闭重开保留原草稿、冲突时不发预览请求、显式放弃后恢复生产预览，以及未知写入只能先查询原操作。该测试仅改独立浏览器上下文，不清理作者实际留下的草稿。

`test-ui-mutations.js` 另把应用请求和返回分开挂起，覆盖面板先关闭、后台随后写完、面板重开／整个文档重建后查询原操作，确认已保存草稿自动收尾且零重复应用；旧返回迟到也不得清除新草稿。测试仍只写独立副本并精确撤回原字节。

`test-view-modes.js` 在独立副本验证初始进度下隐藏页面／分层／图块／头像可创作、玩家预览严格隐藏与明确原因、单击零修改／拖动落草稿、同一 C# snapshot 与导航门不变、A/B／相机／草稿保留、明确页签选择与迟到重绘隔离、未知头像占位，以及三个视口的文字／按钮／分层滚动可达性。不执行 apply，不改内容文件或作者实际浏览器草稿。

其他机器门：

- `node tools/map-workbench/test-domain.js`：冻结第一阶段的 552 组进度／交通工具向量、8,921 项断言，以及未知／循环／固定／跟随边界。
- `node tools/map-workbench/test-core.js`：冻结 v1 单文件回执与 HUD 投影的 18 项兼容／改名层级回归检查，不作为 v2 产品验收。
- `node tools/map-workbench/test-upstream-compat.js`：真实 NPC 初始化源码前缀的 9 项兼容路径，守未接管 NPC 的主线／支线旧行为与已接管驻点的单一 presence 边界；仍需独立 CS6 门。
- C# `MapDomainCoreTests / MapDomainSessionTests / MapAuthoringContentTests / MapWorkbenchTaskTests / MapCatalogTests / MapHudPayloadParseTests`：新鲜度、原任务补丁、恢复、共享素材、边界与旧入口退役；`MapTaskResponseTests` 另验真实回包消费者的编号匹配、乱序／重复、导航关闭结果及最大正整数编号。
- `scripts/run-map-domain-tests.ps1`：实际 CS6 focused 26/26，包含地图 snapshot／导航的延迟、乱序、成功／失败与数字请求编号保留，真实 wire 需带 Host 原始正整数 `callId`；`run-map-loot-tests.ps1`、`run-boot-sequencer-tests.ps1` 覆盖周边生命周期与启动，随后单独 `compile_test.ps1 -Target publish`。
- `webview-smoke/MapWebViewSmoke.csproj`：隐藏窗口、禁用 GPU 的实际 WebView2 启动注入、snapshot v4 作者子文档和来源／对象隔离；不进入玩家存档或自动游玩。
- 地图、Tasks／Stage Select、Workbench strict、panel contracts、Launcher 全量、文档治理与候选闭包另按[测试指南](../../agentsDoc/testing-guide.md)执行。

一次性 `migrate-v2.js` 从冻结 Git 树导入原阈值和坐标；默认只写 tmp，`--apply` 必须精确匹配旧定义字节并通过 C# 制作／发布闭包补全。它不是日常作者写入口，不会覆盖后来编辑的地图。

机器证据不代签新地点的玩家入口、NPC 真实互动或人类视觉判断；按第二阶段设计的三条自然旅程完成独立验收后，才另行授权发布。
