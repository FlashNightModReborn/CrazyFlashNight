# KShop A3 隔离验证工具

状态：`AUTHOR OFFLINE_VERIFIED / AWAITING INDEPENDENT FINAL REVIEW / LIVE_BLOCKED / NOT_DEPLOYED`

本目录提供 KShop A3 的隔离旅程编排、被动观察和证据验签。当前生产树已输出真正的 `event=panel_exact_close_completed`；verifier 要求首进程与重启进程各有且仅有一份同 owner 收据，并验证 `close request → [PanelHost] closed: kshop → completion receipt`。首进程收据必须早于 archive，重启进程收据必须是相关 Host 尾记录。

2026-08-21 字体 Gate E current-tree 复核：`bootstrap.js --check` 为 `249/249`；production closure v8 精确覆盖 205 个文件，browser child 为 `151/151`，闭合 370 项 module manifest、83 个实际资源与 314 次 occurrence。闭包现在同时绑定 `fonts/fonts.xml`、XML-hash catalog/compatibility projection、两项 permanent 实体及 generated CSS/JS；独立浏览器只允许其缺少 Host exact-set handler 所导致的 `cfn-fonts.local` 请求失败。该结论仍仅为 `OFFLINE_VERIFIED / LIVE_BLOCKED / NOT_DEPLOYED`。下文 v7、198-file、150/150 等旧“当前”快照保留作历史解释，均由本段取代。

P5 另增加一条不购买、不领取、不保存的旧存档读回旅程：[`../kshop-legacy-readback.js`](../kshop-legacy-readback.js) 只把显式授权的 seed 逐字节复制到专用 `cf7_agent_*` 槽，绑定 exact candidate 后，以真实 WebView2 和物理 GUI 输入完成同进程两次开关及新进程第三次读回。关闭证据只接受两种现役入口：命中可见且 enabled 的 header close button 的 `isTrusted` 左键 click，或紧邻 exact close request、哈希连续且已经隐藏面板的 Host `panel_esc`；后者在报告中固定标记 `browserIsTrusted:false / physicalInputAttestation:false`，不能冒充浏览器 DOM 物理点击，实际 Escape 操作仍由外部 GUI 执行记录证明。它固定核对 catalog 数量、K 点、历史待领取投影、原始数字字符串、clone 商城字段与玩家原档 SHA-256；任何 KShop 写命令、原档字节变化、clone 商城变化或跨次投影漂移都 fail closed。该入口用于旧存档只读兼容回归，不替代下文带一次购买、SAFEEXIT 和完整 Inventory surface 的 canonical A3 写旅程。关闭判定的纯函数反例先跑 `node tools/workbench-live-e2e/kshop-legacy-readback.self-test.js`，当前为 **7/7**。

```powershell
node tools/workbench-live-e2e/kshop-legacy-readback.js `
  --candidate-root "...\tmp\runtime-candidates\v2\<candidate>" `
  --seed-slot crazyflasher7_saves `
  --slot cf7_agent_p5_kshop_legacy `
  --expected-catalog-count 227 `
  --allow-read-only-live-seed
```

2026-08-05 本轮先按独立终审意见把 production closure 加固到 `production-closure.v7` / `production-inventory-source-anchors.v3`：26 个语义锚点、51 个直接父级/执行位置/不可重绑定/受审 token 摘要断言和 3 个顺序 Gate 同时绑定 KShop 真实 `InventoryCoordinator` 完整构造赋值、同一对象内的最终 `requestInventory` 与 exact-owner physical-surface reader、真实 Inventory mux transport，以及 checkout/claim 的 begin → request → callback → complete/fallback 全 callable。38 个逐锚漂移、8 个注释/字符串/两类正则/marker 假象、15 个 dead-code/nested-function/unreachable 与 22 个外部写入/生效绑定/顺序及等频体漂移反例均已进入 canonical；不同作者的结构终审已给出 `PASS`，但当时 browser 仍是裸子进程，因此该阶段整体 `NO-GO` 痕迹继续保留。
随后补齐 browser 子门：`run-kshop-harness.js` 以可嵌入 API 返回完整结果；独立 `browser-bootstrap.js` 在自己的 runtime journal 内封闭 280 个实际 Node 模块、23 个 builtin、79 个浏览器实际成功消费的 harness/生产 JS/CSS/图片/manifest 文件、固定资源 inventory、共享资源闭包 helper 与真实传给 Chromium launch 的 Edge 路径/字节/hash。HTTP ledger 保留 298 个有序 occurrence，并仅显式接纳唯一 `/favicon.ico` 404；资源缺失、额外、越界、未完成、磁盘漂移、实际 launch 路径不一致或四个 filtered checkout/claim 断言的 ID/detail 漂移都会使父级 canonical 失败。browser 当前为 `150/150`，child manifest 为 366 项。
旧 `241/241`、journal `79ba38f9aef20bc2b2bbb9605b34eb0a5936ce6e4a66e6c42d494fdb266aa5c3`、裸 browser 作者复跑，以及补 manifest 输出前的首个当前树 `249/249` 均固定为 `Superseded / Reopened`。其后 manifest `b33f04e9370c9c23102ff6aafaf2dbda77beeb7623a3bb86db5115258498b564` / journal `d9767ede7040519e9b5eba43966ed58dbb82b35e1bed5332701f01860313dad0` 的 `249/249` 又因共享资源 helper 未从实际 occurrence 重建资源投影、父回执未持久绑定 child receipt 而固定为 `Superseded / Reopened`。2026-08-05 当前稳定串行 `bootstrap.js --check` 用时 `289.7s`，为 `249/249`、`ADMITTED / OFFLINE_VERIFIED`：父 manifest `50172e9ded78ccce344ad16b4b118e48a0b894fe2d6bbe1703a2386e71f59d55`、父 journal `4504caf937835dc3616c16c5f7e130fd490d7eed1a41a140e87601ac898289a2`、父回执 `7697ee9192c6fc0d8b921005a2d14cb841c7357eae20ad8d76b920183d903b55`。父回执直接绑定当前 Node、browser child、Edge、76 个资源/286 个 occurrence、固定 150 项 assertion ID 摘要与各层结果摘要；child receipt 为 `4313f57fc53be1387b1086df12616fc4043d02b8803bc5dfa3633124ac73190e`。这仍是作者侧离线证据，等待不同作者终审；状态保持 `LIVE_BLOCKED / NOT_DEPLOYED`。全程没有启动 Launcher、candidate、游戏或存档，也没有访问外部网络或取得 live capture。

2026-08-08 在 P4 共享 `arena.css` / `team.css` 与 P5 `ArenaTask` 接入后，fresh canonical 仍为 `249/249`、`ADMITTED / OFFLINE_VERIFIED`：父 manifest `35102da6d774c37f02bac26e716f442d6b1ffb832bda160505443154260aa07d`、父 journal `9a5b10d45332ffcd4b58a27de81c285f226e9727c74929ca8573ce79a1a1f8a4`、父回执 `cb03ef2ac02b77522cd639db840add4b17d84644e32dd757cf96232fcc4ed107`；browser child receipt `374fdd93d1ef0a28cea060bc61d8a182d9ce93869073ea70e85a372a7cf01251`，资源闭包 `ee45e731513a7fff3eb2cf338f9794fbd122420b773fae171173591ed17e0ccc`，精确绑定 79 个资源、298 次 occurrence 与 366 项 child manifest。2026-08-05 的数字保留为历史证据，不再代表 current tree。

## 唯一准入入口

唯一入口是 `bootstrap.js`，且只接受以下互斥模式：

```powershell
node tools/workbench-live-e2e/kshop/bootstrap.js --check
node tools/workbench-live-e2e/kshop/bootstrap.js --help
node tools/workbench-live-e2e/kshop/bootstrap.js --emit-offline-admission-fixture
node tools/workbench-live-e2e/kshop/bootstrap.js --verify-bundle "C:\absolute\journey-bundle.json"
```

`run-live-journey.js`、`verify-live-journey.js` 和 `self-test.js` 直接执行均返回 `NOT_ADMITTED`。控制模式不能与 live 参数混用；例如 `--candidate-root X --check` 必须在加载业务模块前拒绝。`--check` 会在同一个尚未 seal 的 journal 内加载 self-test、fixture 与真实 `PanelRequestMux`，执行审计后才记录 `audit_executed → terminal`；`--verify-bundle` 和 live 则必须在同一份未 seal journal 中完成完整业务验证并记录 `verification_executed`，之后才允许 checkpoint、seal、重验与仅处理 seal 后字段的 finalize。成功的 `--check`、`--emit-offline-admission-fixture`、`--verify-bundle` 和 live 机器模式 stdout 各只含一个 JSON 文档；`--help` 是供人阅读的帮助文本，不适用单 JSON 约束。

## 离线证据合同

历史基线 `146/146` 与 `170/170` 均保留为 `Superseded / Reopened` 审计记录，不再代表当前准入结论；资源/Inventory 加固过程中的 `183/183`、`187/187`、`197/197`、`208/208`、`214/214` 也只作为同轮中间审计痕迹保留。v8 新增用例后的数量和状态不得由作者手填，始终以统一稳定窗中当前 `bootstrap.js --check` 的单一 JSON 输出为准：

- production closure：`production-closure.v7` 冻结 **198 个**显式文件：`overlay.html`、22 个启动脚本、1 个 lazy registry、17 个 KShop lazy 模块、7 个入口 CSS 与 22 个递归 import、15 个 base-map idle-prewarm WebP、6 个 CSS 条件图片、font-pack manifest、icon manifest、14 个 Host 启动/route/owner-close 源、14 个 producer/toolchain 输入、10 个 AS2 manifest/source/dependency/SWF、KShop `list.xml + 13 JSON`，以及物品 `list.xml + 52 XML`。其中 `production-inventory-source-anchors.v3` 先词法隔离注释、字符串和 statement-start 正则，再定位唯一 KShop module body、完整 `var _inventoryCoordinator = new InventoryRuntime.InventoryCoordinator({...});` 赋值、真实 `requestInventory`、`commitCheckout` / `onClaim`、两个真实 write callback、reader function、Inventory provider module body与 5 个 provider callable。26 个锚点只能在各自精确 span 内命中一次；51 个结构 Gate 要求 module/function/object 的直接父级和完整签名、reader/classifier 与两个 write callback guard 的首条语句、begin/complete 的已审执行位置、关键 binding 唯一且不可写、consumer/provider 无动态代码，以及 coordinator/checkout/claim 当前可执行 token 摘要完全一致；3 个 Gate 再独立约束 coordinator wiring、checkout 与 claim 的严格顺序。重复或 computed `request`/reader、构造或 assigned-callable 尾部包装、恒失败 request、注释/字符串/正则 decoy、async、后置重赋值、`if(false)`、额外对象块、nested function、不可达 complete、等频条件/body 漂移、begin/complete 乱序或参数漂移均 fail closed。当前物品解析按生产 duplicate-last-wins 规则得到 1600 条声明、1597 个唯一内部名，并与 13 个商店 JSON 的 **227** 个原始目录 occurrence 一起封入 delivery contract。`itemutil-delivery-source-contract.v2` 还结构化提取并绑定 `ItemUtil` / `ArrayInventory` 的 7 个精确函数：词法扫描先忽略字符串与注释，再建立完整 brace-parent 图并定位唯一的全限定目标 class；成员修饰符起点、`function`、参数左括号和函数体左括号的直接父级都必须恰为该 class body，目标不能藏在外层函数、`if`/循环、额外块/对象块或 class 外部。随后才覆盖完整签名和函数体并记录 span、字节数、原始源码 hash 与独立冻结 token 摘要。外层函数、`if(false)`、额外块、class 外部、重复声明、函数体内嵌套、修饰符或换行漂移均有 fail-closed 反例；仅行内注释和不含换行的空白变化作为中性对照被接受。
- browser gate：父级 `--check` manifest 以 `loadable:false` 绑定 runner、真实 harness HTML、child bootstrap、Node module inventory、browser resource inventory 与共享 resource-closure helper 的当前字节。child journal 另封闭 280 个实际 Node 模块、23 个 builtin、79 个实际 served resources 与一个外部 Edge 二进制，共 366 个 manifest entry；runner 返回的 `executablePath` 必须与该二进制精确一致。HTTP ledger 保存全部 298 个有序 occurrence、bytes/hash/MIME/request path，并只允许固定的 `/favicon.ico` 404；资源 exact set、磁盘当前字节、inventory 与 receipt 必须双向一致。self-test 还要求 150 个 assertion ID 全局唯一，并逐项复验四个 filtered checkout/claim ID 的 request route、exact visible projection 与 `{schema, accessibleCapacity:240, responseCount:3}` physical receipt。任何失败、超时、缺失、重复、额外资源、空调用体、只保留同名字符串、child journal 或 executable 漂移都会使 canonical 失败；当前闭包仍等待不同作者终审。
- producer identity：另逐文件绑定当前 runtime-inputs 的 artifact source / producer recipe / toolchain lock（当前分别 **298 / 9 / 3** 个文件），由 canonical producer 同时重算三域 hash 与 build identity。candidate payload manifest 必须逐行绑定实际文件集合、排序、长度和 SHA-256，并重算 canonical payload closure；Core DLL hash、已认证进程路径、candidate root、metadata、producer identity 与 payload closure 必须一致，零文件、额外文件、遗漏、重复、乱序或字节漂移均失败。
- actual loaded closure：每个生命周期都在 observer detach 自有 sourceURL 已执行、CDP 尚未关闭的终态采集完整 Script/Page occurrence。原始 execution-context 必须是全部脚本引用到的精确有序唯一集合，`id + uniqueId + origin + 完整 auxData/main-frame`、脚本关联、顺序和源码字节均须闭合；detach source 必须恰好一份并是终态最后一个 executable，漏项、重复或其后追加 source 均失败。生产脚本仍须按 `overlay.html` 全部 script（含 inline）及 KShop lazy 声明顺序逐项相等。
- Page resource 全局 occurrence 合同：固定层恰为 **85** 项（Document 1、Stylesheet 29、Script 40、base-map idle-prewarm Image 15）；其后只能依次出现当前 CSS `url(...)` 源导出的条件子集、权威 icon 按 catalog/历史项/Inventory 首次出现顺序投影的资源、font-pack manifest 当前安装子集。verifier 直接比较未分组、未排序的整条原始 occurrence 序列；漏项、额外项、重复项、层内或跨层重排均失败。`cfn-fonts.local` 只允许映射文件长度/hash 相等的安装子集；manifest JSON 的 fetch 不伪装成 Page resource；所有条件资源必须用 `Page.getResourceContent` 绑定 URL/type/bytes/hash。
- payload causality：保留不泄露 token 的 wire-length facts，并闭合 Web request → Host panel summary → normalized Flash request → socket response → Web response；长度漂移、未界定 authority family 或明文敏感值均失败。
- Host exact set：Shop/Inventory route、Shop consumer handle、authority binding、Flash send、socket response、Shop receipt、PanelHost open/close 与 completion receipt 必须形成精确 multiset；replay、rejection、near-match、Workbench 或未知相关记录均失败。
- input exact set：每个需要 Web 输入的 request 必须与一份 provider receipt、一个唯一可信 DOM event 形成严格双射。回执保存精确 `(observerId, sequence, eventSha256)`、时间、selector、tag、可见/可用状态、viewport、rect、clientPoint、hit-target、按键/鼠标事实，且 request issuance、provider start、DOM action、provider completion 严格有序；只接受可见且 enabled 的 KShop `BUTTON`、`isTrusted=true`、左键、有限坐标和精确 add/checkout/commit/close selector。右键、隐藏/禁用目标、矩形漂移、键盘、事件复用、额外或无归属输入均失败。
- selection / Inventory closure：选择器按生产 `ItemUtil` 的 type/use 优先级先分类，再只从可负担且等级可用的 `equipment → 背包第一个空位` 目录项中按价格、原始 catalog index 选择。真实最低价 `觉醒晶体`（index 3、price 2）属于 `收集品/材料`，交付到 `收集品栏.材料`，不能由物理 Inventory surface 证明，因而不得成为该旅程候选；当前最低可证明候选是 `蓝色西式校服`（index 79、price 200）。initial、post-commit、restart 各自先精确请求 `[背包 0/50/all, 战备箱 0/100/all]`，独立从首响应导出 `A∈{0,40,80,120,160,200,240}`；`A>100` 才请求 `100/100`，`A>200` 再请求 `200/(A-200)`，`A=0` 禁止发出 `limit=0` 补充请求。每阶段必须闭合完整 `50+A` 物理槽、严格 callId/时间线/owner/session/metadata/revision 合同及无 gap、overlap、reorder、hidden tail；callback 顶层也只接受 `success,v,sessionNonce,snapshots,type,domain,cmd,callId,panel,panelInstanceId`。提交只能改变背包首个空位的耐久语义并取得 fresh lease；同 session 的战备箱完整 item+lease 与 revision 必须稳定。重启后全部耐久语义与 post-commit 相等、session 必须轮换，且每个 session-bound lease 都必须轮换。
- shared helper owner 合同：入口固定为 `readPhysicalInventorySurface(requestFn, {isActive, expectedPanel, expectedPanelInstanceId?}, callback)`。`expectedPanel` 是必填的有界身份，所有响应必须与之精确相等；KShop 同时传入当前 `panelInstanceId`。暂时无法安全取得 instance 的消费者只能依赖其 mux 已完成的 call-owner callback 绑定，helper 仍会捕获首响应 instance 并要求全部补充响应保持完全一致，不能把首响应的任意 panel 当作权威。
- dynamic maximum：装备类上限为 1，信息类上限等于容量约束且购买后按数量递减，堆叠类上限为 999999；commit 与 restart 不得漂移。
- provider/capture：provider receipt v4 逐字节绑定 request artifact 的 owned path、长度和 SHA-256，并保存上述 DOM observation；每个 operation 必须有唯一、严格递增且逐事件封 hash 的 `provider_started → action_completed → [capture_created] → provider_completed` 序列。DOM action 必须引用被动 observer 事件，native action 必须引用可信 provider tool-result 身份；capture 必须反向引用精确 capture event，并绑定 owned path、bytes、hash、`capturedAt`、实际 `fileModifiedAt` 和完整 decoded PNG。超过 capture 时刻 2 秒的陈旧文件、丢失/重复/乱序事件或漂移引用均失败。ack v4 只引用 provider receipt，不内联 capture；截图像素只证明文件完整性与时间链，`captureSemanticContentIndependentlyVerified` 固定为 `false`，作者不得把截图语义自证为真。
- persistence/terminal seal：`global-timeline.v2` 由认证 Host 日志、三阶段 Inventory pair-set 与 provider receipt 共同构成；它必须证明 `final commit response < 完整 post-commit 50+A surface < close request < PanelHost closed < close provider/ack completion < SAFEEXIT request < provider start < action < sv:1 < sv:2 < archive < capture < provider completion/ack < EXIT_CONFIRM request < action < capture < completion/ack < restart open/完整 50+A readback/close < restart close provider/ack completion < supported shutdown residue`。两次 close 均要求 Host completion 严格早于对应 provider/ack completion，首轮 completion 又必须严格早于 SAFEEXIT，重启 completion 必须严格早于 shutdown。其中 `sv:1 → sv:2 → archive` 还支持同一行的精确 offset 顺序。

离线正例收据只能输出：

```text
status=OFFLINE_VERIFIED
liveStatus=LIVE_BLOCKED
deployment=NOT_DEPLOYED
```

fixture 根与 canonical workspace 根不同；即使篡改 `evidenceMode` 并重新封口，也会因 live capture 根、producer 或 runtime binding 不成立而拒绝，不能冒充实跑证据。

## 预定隔离实跑

live 路径尚未执行。它只允许 `cf7_agent_*` 目标槽，并从只读 seed 创建完整 JSON+SOL clone；禁止真实写槽、正式 runtime、`--existing-slot` 和手工修改 SWF。

1. 绑定同一 isolated candidate 的进程路径、core hash、build identity、payload closure 与 producer closure，再创建 clone。
2. 打开首个 KShop owner，取得 fresh `bulkQuery` 与独立闭合的完整 `50+A` Inventory surface。
3. 从权威 catalog 与物品数据动态分类，只选择能由完整物理 Inventory poststate 证明的装备候选；按价格和原始 catalog index 选择，材料/情报/可能进入药剂栏的 mergeable 项必须 fail closed 排除。选择、delivery contract 与一次性授权绑定。
4. 用真实可信输入添加、预览并精确提交一次；验证 token、cart、catalog、delivered、余额、库存 identity multiset 和动态上限。
5. 关闭首个 owner，执行真实 SAFEEXIT/EXIT_CONFIRM，取得独立截图、`sv:1 → sv:2 → archive`、JSON+SOL 与无残留证据。
6. 同 candidate/clone 以新 PID、attempt 与 CDP port 重启，完成 fresh readback，关闭第二个 owner，再走 supported shutdown。

精确 Web 命令 multiset 是：首实例 `bulkQuery×1, saveCart×1, checkoutPreview×1, checkoutCommit×1, close×1`，以及 initial/post-commit 各 `snapshot×N(A)`；重启实例 `bulkQuery×1, close×1` 与 restart `snapshot×N(A)`，其中 `N(A)=1+[A>100]+[A>200]`。三阶段必须各自导出同一个 A 并保存严格有序 callId 集；缺失、重复、额外、阶段逃逸或 surface 内写请求交错均 fail closed。

CDP 注入只观察 `PanelRequestMux.onIssued`、`Bridge.send`、WebView 入站消息、加载资源和真实 DOM 事件，不提供点击、键盘或业务调用方法。control 首选 `launcher_agent_runtime`；仅当当前认证 capability 明确缺少所需动作且调用者显式允许时，才可回退 `codex_computer_use`。checkout 可能已发出后，异常路径必须保留现场并走真实 SAFEEXIT/EXIT_CONFIRM，runner 不得直接 shutdown。

Canonical live 入口（当前未运行）：

```powershell
node tools/workbench-live-e2e/kshop/bootstrap.js `
  --candidate-root "...\tmp\runtime-candidates\v2\<candidate>" `
  --seed-slot cf7_agent_a3_kshop `
  --slot cf7_agent_a3_kshop_run `
  --allow-isolated-purchase `
  --allow-codex-cu-fallback
```

每个 control request 写入 owned run 目录；provider 必须先把操作回执写到 `control/provider-receipts/<requestId>.json`，并将截图直接写到 `control/captures/<requestId>.png`；接管者再用 `ack-cu.js --provider-receipt-file <该精确路径>` 引用同一 requestId。helper 不复制或生成 provider 回执及截图。`commit_checkout` 必须携带同一 authorization decision id；`safe_exit` 与 `exit_confirm` 必须附完整可解码的真实 PNG 及可信 capture event，工具会复验精确 owned path、媒体类型、全部字节、SHA-256、图像结构、像素摘要、decoded dimensions、捕获时刻和文件 mtime。截图语义仍需独立验收，本工具不会从 PNG 存在性推导界面内容正确。

## 文件职责

- `bootstrap.js`：唯一准入、互斥模式、canonical manifest 与 module journal。
- `run-live-journey.js`：clone、candidate、control、SAFEEXIT、重启与 artifact 编排。
- `generic-opener.js`：RuntimeGuard、CloneSaveGuard、LauncherObservation 的 KShop glue。
- `cdp-client.js` / `cdp-passive-observer.js`：固定 CDP endpoint 与只观察采集。
- `production-closure.js`：当前树 closure、producer binding 与实际加载字节合同。
- `control-channel.js` / `ack-cu.js` / `png-contract.js`：one-shot control、provider receipt、ack 与完整 PNG 解码通道。
- `evidence-verifier.js`：closed-field、exact-multiset、persistence 与 terminal seal 验签。
- `fixtures/valid-bundle.js` / `self-test.js`：production-shaped 离线正例与对抗反例。

即使未来 live bundle 通过，本工具的结论也只覆盖该 isolated clone、该 candidate identity 与该单商品单次旅程；不外推为部署、真实玩家存档、物理输入、物理双屏、任意商城商品或完整 KShop 产品验收。
