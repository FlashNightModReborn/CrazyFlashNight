# 军阀战术演习 3D 沙盘（Phase C）

本目录是军阀战术演习的 Launcher Web 正式模块。它保留原 Web Demo v0.1 的确定性规则、战斗、AI、录像和模拟层，彻底替换旧验证 UI，并以 Three.js 正交沙盘承接九节点地图、路线、语义地标、一体化战术徽章、节点拾取和移动过渡。

## 当前状态

`PHASE_B_2_UI_HUMAN_ACCEPTED / PHASE_C_HUMAN_ACCEPTANCE_PASSED / PET_IDENTITY_AND_ECONOMY_OBSERVATION_CONNECTED / RESUME_FIX_PHYSICAL_E2E_PASSED / UPSTREAM_INTEGRATED / MERGED_FLASH_PUBLISH_AND_TESTS_PASSED / PRODUCTION_WRITES_FALSE / FORMAL_RUNTIME_PROMOTED / POST_PROMOTION_AUDIT_PASSED / FORMAL_IDENTITY_LIFECYCLE_SMOKE_PASSED`

Phase B.2 的全屏布局、相机/规划避让、高节点滚动与固定结束按钮已经维护者明确验收。Phase C 在该 UI 上接入 AS2 战斗权威：产品入口固定 `battleAuthority=as2`，战斗命令先冻结，不执行 JS resolver；Host 精确关闭沙盘并释放暂停租约后，串行调用竞技场，再以受校验 receipt 重开同一战略态。该链不写玩家存档、金币、K 点或玩家战宠，`productionWrites` 恒为 `false`。

2026-08-25 首次真实候选旅程已实际进入并完成 AS2 战斗，但没有回到战旗页面。结果文件证明 AS2 在约 17 秒内返回 `finished / winner=blue / errors=[]`；同一时刻 Host 日志明确记录 `[Router] RequestOpenPanel unsupported panel=warlord`。因此旧 `warlord-c3-0825` 只保留为失败证据。恢复动作现改走仅供 `WarlordBattleTask` 使用的 `TryOpenWarlordResumePanel` 内部能力：它校验只读/AS2 权威、请求摘要、session/request 身份、冻结状态/命令和客户端上下文，再经统一 `PanelHost` 打开；通用 `panel_request` 仍拒绝 `warlord`。替代候选 `warlord-c4-resume-0825` 已由维护者确认战斗结束会自动回到战旗页且体验有效。随后整合上游 7 个提交并重新发布合并 AS2 源；合并树 Launcher `4099 passed + 3 explicit opt-in skipped / 4102 total`、Node `75/75`、Edge/CDP `16/16`、共享 Minigame `57/57` 均通过。最终 release source `248cca7be212219655319c666304407b0568e658` 已完成双构建共识、promotion 和远端 audit，当前为 `HUMAN_ACCEPTANCE_PASSED / promoted`；部署后的 formal smoke 只覆盖身份和生命周期，不代签军阀专项 `standard_entry_verified`。

## 权威边界

- `src/core/**`、`src/battle/**`、`src/ai/**`、`src/data/**`、`src/replay/**`、`src/simulation/**` 以 `warlord-tactical-demo-v0.1` 的机械导入为基线。Phase A.6 只增加受限 `CANCEL_PRODUCTION` 状态转换；Phase A.7 只改变 presentation projection 和棋子几何；Phase A.8 只调整棋子缩放呈现策略。战斗、AI、经济、人口、生产推进与部署公式未改。
- `src/ui/App.ts`、旧 `src/ui/styles.css` 和旧 `src/main.ts` 没有导入。
- UI 和 Three.js 都只投影 `GameState`。非战斗战略写入仍通过 `applyCommand()`；产品战斗命令只由 `validateCommand()` 形成冻结请求，accepted receipt 返回前不改战略态。
- 产品战斗播放只消费已接受 receipt 的结果投影，不重新执行 AS2。旧 `BattleRecord.result.eventLog` 与 JS resolver 仅保留给显式 `battleAuthority=fixture` 的开发 harness 和规则回归。
- 八张卡的 `cardId` 就是 `data/merc/pets.xml` 中的 `petId`，产品联合身份为 `petId + Identifier`；旧 `unitTypeId` 仅供 Demo 审计。浏览器头像通过现有 `EnemyPortraits` manifest/resolver 解析，目录内没有复制 portrait 文件或硬编码正式资产 URL。

## 装载结构

`warlord-panel.js` 是 classic facade：脚本求值时同步调用 `Panels.register('warlord', ...)`，捕获自身 URL；`onOpen` 再动态 `import('./runtime/main.js')`。共享 LazyLoader 只加载 `host-bridge.js`、`portrait-resolver.js` 与该 facade，不需要改造成 module loader。

facade 与 ESM session 共同保证：

- open generation fencing，关闭或重绑后晚到的 import 不得重新挂载；
- `mount / rebind / resize / dispose` 明确生命周期；
- 关闭时释放 timeout、键盘/DOM listener、ResizeObserver、rAF、Three geometry/material/texture/renderer；
- `PanelScale.attach(shell, 1024, 576)` 固定逻辑画布；
- WebGL 初始化失败时切换为可完整操作的九节点 DOM fallback。

外层 `×` 和无内部状态可消费的 Esc 只发送携 active `panelInstanceId` 的 exact Host close；Bridge 投递成功不等于关闭确认。确认缺失时恢复同实例重试权，不本地 retire；generation、instance 与 Host active owner 共同保证迟到 A 不能关闭 replacement B。AS2 handoff 已 prepared 后，关闭按钮与 Esc 等待 Host 完成 exact close，避免 Web 先销毁实例、通用 pause 尚未释放而竞技场已启动。Esc 仍先关闭规则配置或清除棋子编组，不越过当前交互层。

## Phase C AS2 战斗权威边界

`wargame-demo-v0.1.1` resolver 仍只是验证战棋循环、指挥交互和结算节奏的 fixture，不是待调平的产品战斗规则，也不承担与真实 AS2 战果相等的兼容目标。产品入口已改为真实 AS2 MovieClip、AI、子弹和伤害链产生唯一战果；JS resolver 只在显式 fixture harness 可达。AS2 不可用时产品路径 fail closed，不静默回退。

Host 的 `WarlordBattleTask` 对 active panel instance、session、request/input digest、战略快照、邻接、AP、攻宽、棋子归属和卡牌状态做 exact 复验，再从 `PetCatalogLoader` 投影 roster。八张卡分别对应宠物目录 id `12/13/14/15/82/83/84/85`，AS2 以 `_root.宠物库` 复核 `petId + Identifier` 并直接生成该 Identifier。等级按棋子卡牌等级投影；已购升阶必须是正式宠物 `Promotion` 中“基础训练 / 强化药剂 / 超级血清”体质链的合法前缀。AS2 为每枚棋子构造隔离 `宠物属性` 副本并调用真实升阶钩子，不读取玩家战宠快照、托管装备或存档引用，含经济副作用的“常驻淬毒”不进入演习投影，掉落和经验写入继续关闭。

通用 Web Panel 会持有 `_webPanelPauseLease`，所以真实战斗采用异步 handoff：Web 冻结 exact strategic snapshot/input digest → Host 回 prepared ACK → 精确关闭沙盘并释放 pause → AS2 专用场景串行运行 → 返回绑定 request/session/input digest、权威上下文和逐单位身份/升阶/存活/HP 的 receipt → Host 复验后恢复同一沙盘并单次应用。确定未投递的失败返回 `not_started`，恢复冻结态并允许人工重试；一旦请求可能已投递，timeout、断线、非法 receipt 或 owner 漂移进入 `unknown`，保持战略态冻结且禁止自动重跑。近期回放只记录并播放已接受 receipt；若要求同 seed 逐帧重算，必须另行隔离 LCG、PinkNoise、时间线 `random()` 和帧调度。

战旗同时承担战宠经济标定，但 Phase C 只建立 `warlord.pet-economy-observation.v1` 观测回执。它分别记录 `pets.xml Price/KPrice/IncreasePrice` 的目录基础价和 `piece.productionGoldValue` 的战旗战略造价，并汇总双方暴露/损失；二者币种与语义不合并。回执固定 `mode=observe_only`、`settlementPolicy=none`、`writesPlayerState=false`、`currentAs2SessionPriceSampled=false`，因此不扣玩家金币/K 点、不改领养价、不结算战宠损失。未来真实经济结算必须新增版本化的会话价格采样、写入、存档和对账协议，不能把本观测 schema 升格为暗写入口。

## 战术相机与大地图扩展边界

沙盘相机已经是独立于规则核心的 presentation capability：

- 鼠标或单指拖拽平移；拖拽超过阈值后不会误判为据点点击；
- 滚轮围绕光标锚点缩放；按钮、`+/-`、方向键/WASD、`0/Home` 和双击提供等价入口；
- `全图` 按 authored map bounds 自动适配，`定位` 聚焦当前据点；
- 相机控件空闲时缩成只保留 `全图 / 定位` 的 108×30px 操作岛；悬停、键盘聚焦或刚发生拖拽/滚轮/快捷键/按钮操作时，读数与 `− / +` 展开 1.4 秒，既保留即时反馈又减少长期遮挡；
- 操作岛固定在沙盘右上槽，结算规划层以明确的右侧保留宽度停在其左边；空闲与展开态都不得依靠 z-index 互相覆盖；
- 相机中心、缩放百分比与 `overview / operational / tactical` LOD 层级可观测；
- 边界据点在战术层级也能居中；节点与棋子标记会分别做缩放级别补偿。Phase A.8 让战术徽章按 `sqrt(cameraZoom)` 渐进增加屏幕尺寸，220% 时约为 1.483 倍，极端近距封顶 1.8 倍；放大能欣赏头像、包边和底盘，又不会按相机倍率线性吞没据点；
- 地图投影原点由 authored node bounds 推导，但保持固定世界单位密度。更大的坐标场会得到更大的 Three 世界，不会被重新挤压回九节点画幅。

当前九节点场景还把重复棋子几何做了共享，沙地使用确定性细纹理与低密度测绘网格。真正进入营/连级数量后仍须按下述边界切换到 instancing、route batching 与聚合 LOD，不能把当前共享几何冒称百节点性能证明。

Phase A.7 把原“透明全身头像直接插在圆柱底座”改成一体化战术徽章：程序化阵营背板裁入头像，配套金属包边、短连接座、八边形低底盘、地面阴影和选择环。头像 identity、拾取 `pieceId` 与移动插值均未改变；背板和裁切遮罩是运行时 CanvasTexture，不新增或复制美术文件。概览层以识别阵营/兵种为主，战术层放大地图与编队间距，而不是按相机倍率放大单枚头像。

Phase A.8 根据人类验收反馈撤销“近似固定屏幕尺寸”的过度补偿。棋子会随战术放大明显长大，但地图内编队间距仍按完整相机倍率展开，因此单位之间的相对空隙增长快于徽章，不会重新压成头像墙。

底部节点面不再把整张图平铺成一排按钮：默认“局部”按图拓扑从当前据点向外广度展开，最多只渲染 6 个节点；“全域”索引同样每页只创建 6 个节点卡。整条导航压到 48px，名称与兵力/归属合并为两层信息，但单卡仍保留至少 40px 点击高度与完整 `aria-label/title`。100 节点合成图验证局部窗口恒定、全域索引为 17 页且选中节点可映射到准确页。它解决 16+ 节点时的 DOM/宽度退化，但百节点产品仍需要小地图、检索和虚拟化索引，分页不是最终的战区情报系统。

## 地图直接指挥

Phase A.5 把“选择 → 预览 → 下令”压成沙盘上的主路径，同时保留左侧复选框和右侧路线按钮作为精确/键盘后备：

- 点击己方棋子建立单选；`Shift/Ctrl` 点击在同一据点内增减选择，双击己方棋子选中该据点全部己方棋子；
- 按住 `Shift` 左键拖拽绘制框选；普通左键或中键拖拽仍然平移相机。框选结果只允许一个起点据点，优先保持既有编组起点，否则按命中数量和 node identity 确定性选组；跨据点命中会明确报告被忽略数量；
- 有编组时，相邻节点由 canonical `validateCommand()` 投影为绿色机动、红色进攻、琥珀容量受限或低亮阻断；点击 Three 节点、底部节点卡或右侧路线按钮都走同一 `MOVE_OR_ATTACK -> applyCommand()`；
- 非相邻或非法目标保留当前编组并显示精确阻断原因。友方容量不足会在下令前后显示实际生效 `X/Y`，不会静默清空整组；
- 命令完成后只跟随“实际收到命令且仍幸存”的棋子，并自动把检查节点移到其当前位置，以便继续点击下一个高亮节点；`Esc` 或沙盘空白点击取消编组，节点点击恢复为只读查看；
- 点击敌方棋子在无编组时只查看其节点；已有编组时则按该棋子所在节点解释为目标意图。战斗播放期间仍由现有写门拒绝新命令。

选择策略只投影 `GameState`，不增加跨节点编组、路径寻路、队形或批量规则。营/连级版本应把大量底层棋子归入编制/命令层级和聚合 LOD，而不是要求玩家直接框选数百枚头像。

## 节点语义模型与主题迁移预览

当前低多边形地标直接由 `NodeKind` 决定，不把美术语义写进规则：

- `hq`：指挥掩体、屋顶与通信桅杆；
- `supply`：堆叠补给箱与标杆；
- `economy`：双储罐和联通管线；
- `choke`：双塔关门；
- `command`：雷达桅杆与天线盘；
- `depot`：军需帐篷与货箱。

`MapTheme` 把地表色相、细纹、雾、背景、三组光源、网格、等高线、路线和中立节点颜色收束为呈现令牌。`desert` 是军阀演习默认主题；`tundra` 是同一拓扑、模型、棋子和规则上的迁移预览。主题切换不会进入 `GameState`、录像或确定性摘要，也不会改变任何规则随机序列。

## 生产队列与部署调度

生产规则没有改动：每个槽是 FIFO 队列，只有队首推进；队首完成后若据点驻军容量或实际人口上限不足，会保持 `waiting_deployment` 并堵住同槽后续订单。失稳取消、金币不退、预留人口释放等行为仍完全由原规则核心负责。

Phase A.6 另增加玩家误排撤销：只在该阵营尚未提交的结算规划中开放，并且订单必须仍是 `building` 且 `remainingRounds` 等于卡牌完整工期，也就是从未获得任何生产进度。合法撤销全额返还订单冻结的金币成本并释放预留人口；队尾可按 `orderId` 精确撤销而不改变队首。一旦跨回合推进或进入 `waiting_deployment` 即永久锁定。该规则与节点失稳的系统取消不同，后者仍不退金币。

右侧生产台把这些状态直接投影出来：

- 行动阶段显示紧凑队列监控；统一结算规划时展开队首头像、生产进度、后续订单链、据点容量和人口阻断原因；
- 当前检查据点之外的订单仍进入“全网在制”头像带；每单显示头像、据点/槽号、队列位置、进度及可撤销/受阻标记。点击头像只定位真实 node/slot，不切换 `AUTO/EXACT`，也不产生排产或撤销命令；
- 队尾订单同样带头像缩略图，不再只靠兵种名称区分；
- 默认 `AUTO` 会在全部稳定、激活的己方生产据点中组合一条合法 `ENQUEUE_PRODUCTION`，依次偏好未受阻槽、较低剩余工期、较短队列、较大部署余量，再以 node/slot identity 确定性决胜；
- 玩家从任意地图节点直接点击兵种“排产”即可完成自动选址与入队，不再需要先找生产点、再点 radio；成功回执会明确写出实际据点和槽号；
- `EXACT` 保留生产据点下拉框和逐槽选择。点击任一槽会切入精确模式，后续排产严格使用该 node/slot；
- 自动与精确路径在提交前都调用同一个 `validateCommand()`，成功后仍只走 `applyCommand()`。UI 不拥有金币、人口、生产进度或部署写权。
- 新入队且尚未开工的订单会同时显示“撤销上一单”和订单内撤销入口；两者都提交同一个 `CANCEL_PRODUCTION`，成功回执明确列出退款与释放人口。仅点选 `EXACT` 槽位不会创建订单。

生产据点用单一下拉框承接扩容，DOM 只展开当前查看据点的槽位，不把未来大量生产节点铺成第二条卡片墙。“全网在制”最多创建 6 个紧凑单元；订单更多时保留 5 个确定性头像与一个 `+N` 汇总，避免排产量线性吞噬右栏。它是当前小规模订单的监视/定位面，不替代百级生产网络需要的搜索、告警与虚拟化。当前规则仍没有拖拽重排、跨槽迁移或已开工订单取消命令，本轮也没有用 UI 伪造这些能力。

纯相机策略用 10×10、100 节点合成坐标场验证全图适配、缩放和越界钳制。这只证明 presentation/camera 数学没有九节点硬编码，不代表当前规则核心已经支持 100 个真实节点；`NodeId`、地图规则、节点导航和战斗编制仍是当前九节点规格。

营/连级地图进入产品施工前还需单独冻结：通用节点 identity/schema、图数据加载与版本、虚拟化节点检索、Three instancing/route batching、空间索引、overview LOD 聚合、编制/命令层级以及对应确定性与性能预算。当前相机、动态 bounds、状态只读投影和 LOD 输出为这些工作保留扩展面，但不提前伪造业务规则。

## 依赖与可复验闭包

- Node engine：`>=22.0.0`
- TypeScript：精确 `5.8.3`
- Three.js：精确 `0.185.1`，MIT
- `package-lock.json` 固定 npm integrity；禁止提交 `node_modules`。
- `npm run build` 从安装包复制 `three.module.min.js`、其依赖的 `three.core.min.js` 和许可证，编译 `runtime/**`，并生成 `runtime-manifest.json` 与 `vendor/manifest.json`。manifest 为每个 runtime/vendor 文件记录字节数和 SHA-256。

规则身份：`wargame-demo-v0.1.1`。其中 `baseRulesVersion=wargame-demo-v0.1`，`rulesExtensionVersion=phase-a-production-cancel-v1`；旧录像不会被误标为兼容新取消命令。

```powershell
chcp.com 65001 | Out-Null
Set-Location launcher/web/modules/minigames/warlord
npm ci --ignore-scripts --no-audit --no-fund
npm test
npm run test:browser
npm run serve
```

开发页：

`http://127.0.0.1:4178/modules/minigames/warlord/dev/harness.html?qa=1`

可附加：`preset=all-units`、`difficulty=easy|normal|hard|extreme`、`seed=...`、`theme=desert|tundra`、`webgl=0`。`qa=1` 会执行 48px 局部/全域节点导航与 40px 命中区、九节点、八卡、六类语义地标、主题重绑、Three/fallback、战术徽章样式与屏幕缩放上限、棋子射线单选/双击同据点全选、Shift 框选、非法目标保留、Three 节点直接下令与幸存编组链式移动、头像 identity、1024×576 顶栏/卡片可读性与 overflow、全锚铺满、相机闲置/操作/聚焦三级披露、相机展开态与规划条零交叠、拖拽/缩放/复位与误点抑制、高节点压力下行动正文原生滚动与固定结束按钮、输入控件快捷键隔离、关闭重开，以及“非生产节点→一键全网自动排产→全网订单头像定位→全额撤销→再次排产→只选择精确槽位而不误下单→提交规划”的完整循环检查。

`npm run test:browser` 使用项目自带的 Microsoft Edge/CDP runner 和一次性 loopback 端口/profile，等待 QA 终态，抓取 1024×576、1366×768、1920×1080 全图截图、1024×576 双棋子编组/合法目标命令态、语义地标战术近距、AUTO 生产台、EXACT 生产台和冻原迁移预览，并将 QA、console、runtime、network、命令意图/战术相机/主题/生产状态与清理结果写入被忽略的 `artifacts/browser-qa/summary.json`。该命令在 Node 20 使用实验性 WebSocket 开关；它仍是普通 Edge harness 证据，不是 WebView2 证据。

2026-08-24 Phase A.8 fresh 机器闭包为：runtime build `68` 文件、vendor `4` 文件，runtime verifier `71` 文件；Node `69/69`，纯相机测试锁定 220% 约 1.483 倍、极端近距最高 1.8 倍的渐进美术缩放，生产 presenter 继续锁定跨 node/slot/queuePosition 的头像订单投影；32 局模拟完成，红 `17` / 蓝 `15`、淘汰 `29` / 回合上限 `3`、`invalidStateCount=0`、`commandGuardHitCount=0`，战果数字与 Phase A.7 相同；Edge/CDP `15/15`，完整循环继续覆盖订单头像定位、撤销与 EXACT 不误下单，截图场景同时排入 `4` 种单位并投影 `4/4` 头像，220% 战术近距聚焦红方总部四枚徽章并记录 `pieceScreenGrowth≈1.483`。三视口无溢出，console/runtime/network/external failure 均为 `0`，browser/server/profile 均清理。应用内 Browser runtime 在本机没有可用 browser instance，因此可见证据来自项目 Edge runner；这些结果停在普通浏览器候选层，等待维护者实际操作验收。

2026-08-24 Phase B.1 fresh 源码门为：包内 build/verifier/Node 继续 `68 + 4 / 71 / 69/69`，Edge/CDP 继续 `15/15`；共享 Minigame QA 全套 `57/57`，其中 Warlord `3/3` 锁定 closure、同 seed 终局和 read-only exact close；Launcher focused `260/260`，全量 `4059 passed + 3 explicit opt-in skipped / 4062 total`，文档治理与 minigame final-state 均通过。以上证明 Launcher 源码闭包与普通浏览器候选，不证明真实 WebView2、AS2、部署或正式入口。

2026-08-24 Phase B.2 fresh 源码门为：包内 build/verifier/Node 继续 `68 + 4 / 71 / 69/69`；Edge/CDP 增至 `16/16`，新增压力场景注入 `14` 个额外行动节点，证明正文产生真实滚动而“结束红方行动”的屏幕位置不变，并在展开相机后证明相机卡与规划条矩形零交叠、右上锚定不漂移。三视口继续无 overflow，console/runtime/network/external failure 均为 `0`；共享 Minigame QA `57/57`、minigame final-state 通过；Launcher 全量 `4060 passed + 3 explicit opt-in skipped / 4063 total`。这些结果证明源码与普通 Edge 候选的布局合同，不代签真实 WebView2 人类观感、AS2 战斗、candidate、promotion 或部署。

2026-08-25 上游整合后的 Phase C fresh 门为：包内 runtime `70`、vendor `4`、closure `73`、Node `75/75`；本机 Node `20.12.2` 低于包声明 `>=22`，只记兼容性实跑。Edge/CDP `16/16`、共享 Minigame QA `57/57`、Warlord `3/3` 与 minigame final-state 均通过。Arena calibration checks `14` 项与 Agent entry contract 通过。仓库 resolver `7/7`，精确 .NET SDK `10.0.300`；Launcher Release/xUnit 为 `4099 passed + 3 explicit opt-in skipped / 4102 total`，testhost 串行。Flash CS6 从合并 AS2 源重新 publish：`225` 份 `.as` BOM 门、fresh Compiler `0/0`，`asLoader.swf` 为 `1,141,507` bytes / SHA-256 `690C1C871FFF915BCEFC17158146B79F805D70A69793014095343019F0454539`；publish-only 未刷新 `flashlog.txt`，不构成新增行为 trace。人类行为证据绑定替代候选 `warlord-c4-resume-0825`（identity `1044015BB54FA8BD989E812F8C7C381A84EF2E5007D53419C26DFE89D2FED4C7` / closure `BDB6E561A330841B923C37F2AA9EDAA39D61CB601DFEE6BC9B4E644EDB62B8E5`）。正式 runtime 现绑定 tag `runtime-build-v2/20260825-warlord-as2-battle-v2`、identity `6482B71F2811065A5537F5CDCB0E338D44C23C2BECDC13987D9924B289EC8C59` 与 closure `4B46C47478DAC64E038F574F2636AFDFF9E0E6EA16F807171FF5F31E21237062`；双构建、38/38 policy、promotion、远端 audit 及正式身份/生命周期 smoke 均通过。

## 验收层级

1. Node：原 39 条 AC/AI 测试必须保持名称和行为；新增 presenter/lifecycle/portrait mapping/production projection/selection policy 测试不得替代它们。
2. 普通浏览器：Edge/CDP harness QA、console/runtime/network 零错误、三视口截图、WebGL 与强制 fallback。
3. Launcher 源码：共享 lazy registry、Overlay CSS、Host 精确关闭、测试菜单、focused tests 与 minigame QA 总入口。
4. Launcher 候选：实际 `https://overlay.local` 动态 import/MIME、WebView2 键鼠、关闭/重开与 GPU 资源释放。
5. AS2 源码：冻结 request/receipt、petId+Identifier、隔离升阶、暂停交接、`not_started/unknown`、只读经济观测与 receipt 回放的静态/单元合同。
6. AS2 物理链：Flash CS6 fresh 发布、真实竞技场 runner、逐单位结果和战后自动恢复已完成；二次交战、最终返回基地以及玩家存档/货币/战宠无污染仍是更宽的后续旅程。
7. 人类感知：沙盘 UI 与 AS2 战斗结束自动返回均已获维护者验收，且体验评价有效；该候选感知与随后 formal runtime 身份/生命周期 smoke 分属不同证据层，不能拼接成部署后的军阀业务 E2E。

当前已完成第 3 层、第 4 层 Warlord 面板主旅程、Phase B.2 UI 人类验收、第 5 层源码合同、第 6 层 AS2 战斗和恢复主闭环，以及正式 runtime 的双构建共识、promotion、post-promotion audit 与身份/生命周期 smoke，状态为 `HUMAN_ACCEPTANCE_PASSED / promoted`。战宠经济当前只有 observe-only 双刻度标定，不授权任何正式玩家状态结算；二次交战、最终回基地、持久状态无污染和部署后军阀业务标准入口未由本次最窄证据覆盖。
