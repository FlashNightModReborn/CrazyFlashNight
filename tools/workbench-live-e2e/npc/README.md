# NPC Shop A3 生产闭环工具

状态：`AUTHOR OFFLINE_VERIFIED / AWAITING_INDEPENDENT_FINAL_REVIEW / LIVE_BLOCKED / NOT_DEPLOYED`。

本目录只实现 NPC Shop A3 的生产取证和离线复验工具，不修改 Host、AS2、Web 业务实现。共享 runtime admission 已冻结为 `FROZEN-v2 / GO`；这只批准 shared API，不能代替 NPC consumer 独立审阅、live receipt 或 A3 GO。当前离线工具本身不启动 Launcher/Game。

2026-08-24 精确定价约束合并后 current-tree 复核：`bootstrap.js --check` 为 `157/157`；bundle/receipt 升至 v5，并要求 live 命令预先声明 `--expected-buy-rate-permille`，由 initial 与 fresh-restart 权威 snapshot 共同证明场景命中。父 manifest `f7509501db439eaecf439f9f13a2b328a6ceee849062f70e939b2175fc1c5ca7`、journal `0a6790149f55fb663dd94a3d283897a34fb26891999fededf4782cb1897f1c1d`、receipt `853abc923448db1e961020afe2f120b30d4785611dc5102a6bf7c12c5274106d`；browser child 闭合 329 项 module manifest、42 个实际资源与 169 次 occurrence，result `eb2967cf3e2f47357ad8aa3ff59783dac377a39fe5df204c7e25c7597cd81b78`、resource closure `a695da20fa9ff430816449f2ccd908818c3fb11e18e6074fd969f960c00842fc`。production closure / Inventory surface / source contract 为 `v14 / v12 / v10` 并精确覆盖 190 个文件。该结论仍仅为 `OFFLINE_VERIFIED / LIVE_BLOCKED / NOT_DEPLOYED`；本轮真人三次 Andy Law snapshot 可证明 Host/Web 接受与采纳，旧日志未记录倍率值，不能追认成 v5 pricing receipt。下文带日期的 v12/v10/v8、180-file、149/149 等快照保留作历史解释，均不再代表 current tree。

## 唯一入口与当前 Gate

唯一 bootstrap：

```powershell
node tools/workbench-live-e2e/npc/bootstrap.js --check
node tools/workbench-live-e2e/npc/bootstrap.js --verify-bundle <绝对路径\evidence-bundle.json>
```

`--check` 是唯一 canonical 离线 Gate；它在 bootstrap 完成 raw argv 分类、安装模块 journal 后，加载并执行完整测试集：

```powershell
node tools/workbench-live-e2e/npc/bootstrap.js --check
```

`self-test.js` 只允许被 bootstrap 加载，兼容别名 `run-checks.js` 只作为可加载 tombstone；两者直接执行均返回 `NOT_ADMITTED`。历史 33/33 使用旧 shared-adapter blocker、跨 owner 重开和 raw JSON Host 日志，状态固定为 `Superseded / Reopened / NOT_ADMITTED`；其后的 27/27、41/41 也分别缺少后来补齐的 current-tree/candidate producer、完整启动资源、CSS、provider/DOM 和 Host relevant-record 合同，固定为 `Superseded / Reopened`。第三轮 `111/111 PASS`、第四轮 `114/114 PASS` 与第五轮 `119/119 PASS` 已依次被 exact artifact/candidate inventory、raw CDP resource/context、provider v4、PNG palette、终态 observer、精确购买落点、完整 fresh/restart canonical 投影、图标信任边界和机器输出合同取代，均固定标记为 `Superseded / Reopened`；这些历史结果不能作为 current 绿灯。`run-live-journey.js` 与 `verify-live-journey.js` 直接执行同样不获准，必须从 bootstrap 进入。

第六轮作者侧 `129/129 PASS` 已被响应双射、双源 raw auxData 与 canonical timeline 修订取代，固定为 `Superseded / Reopened`；第七轮 `134/134 PASS` 又因把战备箱首窗误当完整生产 surface 而固定为 `Superseded / Reopened`。第八轮动态全量 surface 的作者定向结论及随后各次稳定复跑继续保留为历史，不再代表当前树。`v8 / v6 / v4` 的独立串行 `142/142` 作者结果（manifest `88010084818a611a42ad76f1a554f4f432433ed487c784c199554f12c26a724e`，journal `8a6ca312f1e5813bbe0aa97c348faffb32b27797d3fde697d87856d0da7cc163`）已经由不同作者终审判定 `NO-GO / CHANGES REQUIRED`：callable 内死代码仍可伪造关键锚点、browser 子进程未进入独立 module journal，且七个战备箱可访问量边界没有全部动态执行。该结果固定为 `Superseded / Reopened`，不得再作为 A3 绿灯。

此前 production closure / Inventory surface / source contract `v10 / v8 / v6` 的稳定串行 `143/143`（manifest `9c65012f57aea119ab5225680577a3060fa3a074389cf414b5b6f1dff1131bbe`，journal `0135b4b4a994c6341bfcad7ab5131e77275090af65082fa3a4cf793c93c8f011`）因共享生产字节与消费面证据合同变化固定为 `Superseded / Reopened`，不得再作为 current 绿灯。

2026-08-05 的当时修订已升至 production closure / Inventory surface / source contract `v12 / v10 / v8`。八个关键路径除唯一 outer callable 与首层 brace depth 外，还绑定从 callable 入口到关键语句的 comment/string-neutral active-prefix SHA-256，因而嵌套 callable、有括号或无括号的常量分支、常量短路和不可达搬运均不能恢复真实合同。离线测试直接执行 `A∈{0,40,80,120,160,200,240}` 全矩阵，并在 production browser 中分别执行 `containerVersion` 成对漂移、结算入口、预览、提交和最终写分发的独立故障旅程。browser harness 为 `128/128 + reduced-motion 2/2`；browser 子进程以独立三阶段 journal 封闭 322 项显式模块清单、真实 Edge 二进制、35 个实际资源与 106 次原始 occurrence，并冻结完整检查名摘要 `8d28dc65a9965e7a9c652a67e001e90660f224d790232cabc22641b75cb4d1ea`。父 `bootstrap.js --check` 当时作者复跑用时 `583.9s`，结果为 `143/143`、`ADMITTED / OFFLINE_VERIFIED`；父 manifest `5c885c69846aed41ef1eb5deb2ef73c7c28c29c5a14c28ca82793a2f30087c77`、journal `e4a35ef72956e385bf48b16e93595e463af6ebfcd264358afe94266971d452d0`、self-sealed receipt `e808ea6faa7dd7f1ad4281602fc853af323ecbf0f4e60888ae37745fa971bd92`，内嵌 browser receipt `74f6398255544b61759b7608b24782de00f27d8ef7d906dfcf620d036eedb86e` 与 resource closure `bb511b5035884059a6dbbe0c8175cbc12e80e860fbdd506bc5528c1626047f06`。该作者侧证据仍等待不同作者终审，状态保持 `LIVE_BLOCKED / NOT_DEPLOYED`。bundle、verification receipt、pricing constraint、loaded production、trusted timeline、control ACK、provider receipt 与 artifact manifest 当前分别使用 `workbench-live-e2e.npc.bundle.v5`、`workbench-live-e2e.npc.receipt.v5`、`workbench-live-e2e.npc.pricing-constraint.v1`、`workbench-live-e2e.npc.loaded-production.v6`、`workbench-live-e2e.npc.trusted-timeline.v3`、`workbench-live-e2e.npc.control-ack.v2`、`workbench-live-e2e.npc.provider-receipt.v4` 与 `workbench-live-e2e.npc.artifact-manifest.v2`。

2026-08-08 在 P4 共享 `arena.css` / `team.css` 与 P5 `ArenaTask` 接入后，fresh canonical 仍为 `143/143`、`ADMITTED / OFFLINE_VERIFIED`，用时 `432.7s`：父 manifest `f8ca0b18aa51452de68cbccde2c4dbc382b1d48d8520de6540c800bfd7d44ea0`、journal `403078e01e6d6d02c71f05e42c45415e1191a1c0f32e94084dab09bb4bb66750`、self-sealed receipt `b95c1225baca3f0b08bc8eeaa4d9499b650223933de209bd0bf446d42440437d`；browser child receipt `0fc81d01d72e790b0c1a1f1ada0b7fa7e16db378746b8cb896c6167bae436aa1`、resource closure `880b93fbdbc2f1109affc66cc1911cb80ff60395868543f1184097202156bcf0`，精确绑定 324 项模块、37 个资源和 112 次 occurrence。三份 production Web exact-byte pin 已在语义锚、深度和顺序全部不变的前提下刷新到当前 UTF-8/CRLF 工作树；机器输出分支边界改用 `\r?\n`，仍严格要求 check 分支只写一次 stdout。上段 2026-08-05 的数字固定为历史，不再代表 current tree。

2026-08-11 材料档案→NPC 商店定位/返回接入后的 current canonical 为 `143/143`、`ADMITTED / OFFLINE_VERIFIED`，用时 `237.4s`：父 manifest `8ea46258b1e75b25f97c2970762e3a8cb5b670dc921aa5dc16805e3f5e2dcf30`、journal `92ecac78fe39b0484b33eb433005b1f9aaca18c0a9e77b8cc27ecdb3e432c7d3`、self-sealed receipt `6ef46321526808e71cf4863273982a66ed1ea4ebeb9aed89a8091c29d25eb109`；browser child 为 `129/129 + material-navigation 21/21 + reduced-motion 2/2`，receipt `052256ca320625abaddf77615c4e75db0ca057ad5b3d8b1f78feb3a5276a4775`，精确绑定 326 项模块、39 个资源、157 次 occurrence，resource closure `9ae8fee23cd043c643e41def124eaefdf9ef10424c5b24262f93007572d9a163` 与检查名摘要 `1bd5f22798f515914ac57030c68797d1363e8ac623dba3bee59c518d53b63f5e`。production closure 当前为 180 个文件，`closureSha256=2036d3261c1077e90616ae059afe3b562dac53afc1b463967d1439b741ffb24a`；consumer/adapter/provider 三份 exact-byte pin 与新增返回态写前 fence、active-prefix、深度、唯一性、顺序 mutation-negative 合同共同闭合。该结果仍只属于离线证据，状态保持 `LIVE_BLOCKED / NOT_DEPLOYED`。

bootstrap 必须在加载 suite/runner 前完成 argv 分类：空 argv、未知/重复参数、模式混用、缺值、相对 verify/receipt 路径、非法 seed/target、缺少 bounded-write/fallback 显式授权、缺少 `--expected-buy-rate-permille` 或其值不在整数 `0..1000`，以及 `--purchase-only` 都以 exit 2 拒绝，不能触发业务模块加载。成功的 `--check`、`--verify-bundle`、`--help` 与离线 admission fixture 模式各只允许 stdout 一条 JSON 且 stderr 为空；成功的 live 模式则明确使用 NDJSON：每次等待外部控制时输出一条 `type=control_request`，全部旅程封印完成后恰好输出一条 `type=final_status` 终行，stderr 为空。消费者必须逐行解析并按 `type` 区分控制请求和终态，不能把整个 live stdout 当成单个 JSON。`--check` 的 journal phase 固定为 `domain_loaded → audit_executed → terminal`，`--verify-bundle` 固定为 `domain_loaded → verification_executed → terminal`，live 固定为 `domain_loaded → clone_prepared → first_captured → restart_captured → verification_executed → terminal`。

每份 bundle 都必须携带封印的 `evidence-origin.v1`。唯一 canonical root 是该 bootstrap 所在固定仓库布局向上三级解析得到的仓库根；外部或同名副本根不能通过。`offline_fixture_v1` 只允许 `domain_loaded → terminal`，且 `fullScopeEligible=false`；`npc_a3_purchase_diagnostic_v1` 仅保留为 verifier 的历史/内部非闭合投影，生产 bootstrap 不接纳 `--purchase-only`。只有 `npc_a3_full_live_v1`、`purchase_then_explicit_sale`、完整 live phase、manifest/journal 双哈希和完整 live 证据同时闭合时，才具有 full-scope eligibility。离线 fixture 明确携带 `safeExitUiJourneyVerified=false` 与 `exitMethod=offline_fixture_simulation`，因此永远不能生成 `e2e_verified`、live receipt 或 A3 GO。

run 目录采用完整、排序、大小写敏感的 path/role/bytes/SHA-256 清单；未知文件、缺失、重复、重排、role drift、非普通文件或 symlink 均拒绝。candidate 也按真实目录枚举并与 metadata/manifest 声明的 payload exact set 双向闭合，额外 payload 与遗漏同样拒绝。live 收口是两阶段的：先对 raw evidence、业务语义和 artifact 投影执行完整 pre-seal 验证并冻结 receipt/projection；随后只允许写 module journal、最终 bundle/manifest 与冻结投影派生的 receipt/status。finalizer 只复核 journal、最终 exact artifact set 和冻结投影，绝不重新执行业务语义验证；任何 pre-seal 后漂移都不能产出 receipt。

## 固定生产旅程

独立审阅批准后，唯一预期命令形态为：

```powershell
node tools/workbench-live-e2e/npc/bootstrap.js `
  --candidate-root <隔离-candidate-绝对路径> `
  --seed-slot cf7_agent_a3_kshop `
  --slot cf7_agent_a3_npc_run `
  --expected-buy-rate-permille 1000 `
  --allow-isolated-commit `
  --allow-codex-cu-fallback
```

`--expected-buy-rate-permille` 是必填场景约束：缺失、小数、负数、超过 1000，或 initial/restart 任一权威 snapshot 与声明值不同都必须失败；声明值和两次观察值进入 v5 bundle/receipt。`--sale-slot`、`--expected-sale-item`、`--expected-sale-pre-quantity` 是可选约束。默认先选择 fresh 背包 `physicalSlot=0 / 砍刀 / quantity=1`；若该对象不安全或不存在，再从 fresh post-purchase Inventory 中确定性选择一个名称唯一、未强化、未占阶位/插件槽且不是本次购买物的 lease-bound 背包项。最终授权始终冻结 container、physicalSlot、itemName、slotLease、preQuantity 与 quantity=1。

固定顺序：

1. bootstrap 首先安装显式模块 journal；
2. 在克隆写入前冻结 candidate identity，准备专用 JSON + 全量 SOL clone/recovery；
3. 启动 first PID，窄 CDP Runtime 只被动观察 `https://overlay.local/overlay.html`；
4. 由真实 NPC 入口打开一次面板，严格观察同 owner 的首个 `Inventory snapshot request < NPC snapshot request`；Inventory 必须先完成本阶段动态全量 pair-set，NPC 与每份 Inventory 响应都必须通过现役 Host/Web exact schema，且初次 NPC snapshot 的 `buyRatePermille` 必须命中启动前声明的场景约束；
5. 动态选择不同于出售对象的 unlocked/affordable catalog 项，取得 purchase preview，并只 commit 一次；
6. 使用 purchase commit 返回的 fresh NPC state，并在同一 owner 上重新探测一份独立、完整的 post-purchase Inventory surface；
7. 在同一 panelInstance 选择精确 lease-bound 出售项，取得最终 one-unit preview，并只 commit 一次；
8. 使用 sale commit 返回的 fresh NPC state，并重新探测独立、完整的 post-sale Inventory surface，随后只关闭一次首面板；exact close settled 后立即执行一次 `seal detach_hooks → final production capture → transport detach`，此后不再执行 observer tool source；
9. observer 已断开后，由已选 computer-use provider 执行可见原生 `SAFEEXIT`，两项原生退出控制均显式跳过 observer health；外部 provider receipt 与 Host 同一 first 行号域共同证明 `final commit response < close/detach/loaded < SAFEEXIT < sv:1 < sv:2 < archive → JSON/SOL`，随后由 provider 执行 `EXIT_CONFIRM` 并证明 PID、端口、rendezvous、credential 全部清零；
10. 同一 candidate、同一 clone fresh restart，严格观察新 owner 的首个 `Inventory snapshot request < NPC snapshot request`，再次独立探测完整 surface，并要求 fresh-PID `buyRatePermille` 仍与声明值完全一致，再只读核对并关闭；
11. 通过 supported `agent_control shutdown` 退出 restart，复核零残留、seed 不变、clone/recovery 安全释放；
12. 两个 lifecycle 都必须在 authenticated terminal suffix 中各出现一次 `panel_exact_close_completed panel=npcshop panelInstanceId=<exact>`；只有真实 `live_capture`、full-live sealed origin、完整购买与明确出售、terminal journal seal、bundle 复验与原生 SAFEEXIT UI 证据同时闭合，才可能生成 `e2e_verified / LIVE_CAPTURE_VERIFIED / NOT_DEPLOYED` receipt。生产入口不接纳 purchase-only；离线 fixture 固定停在 `OFFLINE_VERIFIED / LIVE_BLOCKED / NOT_DEPLOYED`。

## 权威证据与控制边界

每个 NPC/Inventory 请求与响应集合必须形成双向一一对应：每个非 close 请求恰有一个更晚的同 owner/domain/cmd/callId 响应，每个响应也必须恰好反向匹配一个更早请求；额外、重复、提前或任一身份字段不匹配的响应均拒绝。闭合序列为：

`Web Bridge.send(after PanelRequestMux onIssued) → Host structured panel envelope → exact domain route → authority_flash_call_bound(webCallId→fid) → redacted Task command → same-fid success response → Web owner response`。

raw JSON authority 日志、缺 binding、缺同 fid response、重复 fid、legacy `buy/batchSell`、foreign/late write 都 fail-closed。`tradeCommit` 的 authority tail 直接按当前 `AuthorityLogFormatter` 投影：不仅字段集合和数量，字段出现顺序、known/unknown 数量及每个 present/ref/refCount 也必须与真实请求/响应精确一致；合法可选尾字段按 formatter 的实际位置出现，缺失、额外、重复、乱序或 hash 不符都拒绝。preview token 只能使用一次。

购买目标只允许 equipment，并冻结安全整数 `buyRatePermille` 与 `floor((basePrice × quantity) × buyRatePermille / 1000)` 的运算顺序、unitPrice、quantity、total、balance、catalog `maxQuantity`、purchaseLimit、`maxAffordable`、`maxByCapacity` 与 destination；旧浮点 `buyMultiplier` 必须被 exact schema 拒绝。金额、rate 与各步中间值都必须是 safe integer，只有 `netDelta/projectedBalance` 可为有符号值；余额不足 preview 的负预计余额仍是合法 blocked projection。每个 initial / purchase-post / sale-post / restart 阶段都必须从首批精确请求 `背包 offset=0/limit=50/filterKey=all + 战备箱 offset=0/limit=100/filterKey=all` 开始；背包固定 `physical/access/view=50、pageSize=50、slots 0..49`，战备箱固定 `physical=400、pageSize=40`，可访问量 `A∈{0,40,…,240}`。仅当 `A>100` 才追加 `offset100/limit100`，仅当 `A>200` 才追加 `offset200/limit(A-200)`；`A=0` 的首响应必须是 `limit=0/slots=[]/locked=true`，且禁止发送 limit-0 supplement。每个 probe response 必须严格早于下一 supplement request，同阶段全部 pair 共享 sessionNonce、capacity、A、epoch、version，按 `(phase,pairOrdinal,container,physicalSlot)` 合并后必须无缺页、隐藏尾部、重叠、断口或乱序，期间不得穿插写入。

合法购买落点不再接受“任意空格”：它精确复现生产链 `NPC commit → ItemUtil.acquire → ArrayInventory.getVacancies()` 的唯一首个空背包格，且物品类别和完整 catalog 身份必须匹配；当前 fixture 因 slot 0 已占用而固定落到 slot 1，错误空格一律拒绝。购买后必须在完整 `50+A` 格 item + confirmProjection 中只出现一个正确目标槽变化；出售同样绑定 source coordinate、container、lease、identity、quantity、动态 eligible/protected count、价格公式和余额变化，并证明除唯一源槽外所有背包与战备箱格语义不变。相同 epoch/version 的纯读必须保持逐格 item/lease 稳定，被写目标必须失效旧 lease；fresh restart 比较保留完整 NPC catalog/selection/layout/views 和完整 `50+A` Inventory 权威语义，要求 sessionNonce 与全部 NPC/Inventory slot lease 逐格轮换。容量、A、尾部 item/lease、rarity、catalog 或任意未经授权字段漂移都 fail-closed。

CDP observer 不点击、不键入、不调用 `Bridge.send`/`Panels.open`/业务 API；真实输入必须由 provider 产生。每条鼠标证据必须保存真实 event `clientX/clientY/button=0`、精确 selector、`BUTTON`、visible/enabled、viewport、rect 与 `elementFromPoint` 命中结果；键盘证据只接受各步骤冻结的精确键值。由 DOM 中心点推算、缺 enabled/hit-test 或宽泛 selector 的证据均拒绝。

生产 closure 在 clone 前和 restart 后各捕获一次，当前精确覆盖 190 个文件：Overlay 页面、页面声明的 20 个启动脚本（含 NPC lazy registry）与 14 个 lazy 依赖、页面声明的 10 个样式入口及 `css/panels.css` 递归 `@import` 图（当前合计 36 个样式资源）、NPC/Inventory/PanelHost/PanelBridge/pending-owner/XmlSocket/authority formatter 等 Host 依赖、AS2 源与 `scripts/asLoader.swf`、shops/items canonical list 及其全部实际子文件。

closure 还从 `config/build/runtime-inputs.v2.json` 的 canonical producer 当场枚举并重算三个域，文件数量固定为 `artifactSource=302 / producerRecipe=9 / toolchainLock=3`，再计算 build identity；三个域哈希、build identity 必须同时与 candidate metadata、manifest、process identity、全部 payload bytes、`coreSha256/payloadClosure`、runId 和真实打开的唯一 shop JSON 一致。不能用调用方填写的 recipe/toolchain 字段替代 producer 结果。first/restart 必须通过 CDP 保存所有 `Debugger.scriptParsed`、execution context 和页面 resource tree 的原始 occurrence 流，包括空 URL 脚本。每个 script occurrence 不可变保存完整 raw `Debugger.scriptParsed.params` 及其中独立的 `executionContextAuxData`；execution-context occurrence 另存 raw `Runtime.executionContextCreated.context.auxData`，后到的 context 只补 context origin，绝不覆盖 script 原始字段。两路 auxData 都精确为 `frameId/isDefault/type`，按 script 首次引用形成的 context ID 集合与 context occurrence 集合必须一致，随后再深比较两路 raw auxData；缺失、分歧、额外 context 或重排均拒绝。每个脚本还精确绑定 scriptId、URL、contextId、frame/origin、顺序及 `Debugger.getScriptSource` bytes/hash。

raw Page resource 合同分三层：必需层是主 Document、current-tree 的 36 个 CSS、34 个生产 Script，以及 `page-base.webp + 14` 个 base sceneVisual idle prewarm；条件层只接纳 current-tree `skins.css` 可见资产的实际出现子集，以及 `cfn-fonts.local` 的 13 个 manifest 映射字体子集，字体按实际 bytes/hash 绑定而不伪称 current-tree 文件；动态层只消费前述严格双射已经验证、且业务成功的 pair，再从 NPC `snapshot/tradeCommit` catalog/views item.icon 与 Inventory `snapshot` 已占用格 item.icon 投影，绝不重新扫描 raw transcript；随后通过真实 `launcher/web/icons/manifest.json` 展开静态、逐帧或 nested-layer 资源。普通 `panel_cmd`、outbound bridge、preview、孤儿响应或任意额外 `icon/iconName` 字段都不具备图标权威；额外 envelope 字段、未投影图标名或对应 Page resource 均拒绝。未知图标、未知字体、漏图、额外资源、重复、乱序、child frame、MIME/source bytes/hash 漂移同样 fail-closed。observer 自己的 evaluate/addScript 注入各使用唯一 sourceURL 并封印 source bytes/hash；`detach_hooks` 必须恰好一次、是最终 tool plan 且在保存 closure 前已进入 raw occurrence，transport detach 不再生成脚本。缺失、重复、乱序、外来或匿名脚本、额外 registry/script/style 及 digest 漂移均拒绝。

Host 证据不再由 runner 筛选或自造 terminal 行。`host-evidence.v4` 保存显式 UTC offset；每条原始 Host record 必须保留 `HH:mm:ss.fff` 前缀与 body，并按 session 只允许一次合法的 23→00 跨日，普通回退、第二次跨日或缺时间均拒绝。每个 PID 保存 shared Launcher API 产生的 authenticated `startBoundary + closeSettledSnapshot + terminalSnapshot`，三个 snapshot 和所有 timeline boundary 的 sessionPid 必须与该 lifecycle 实际 runtime PID 完全一致并构成无缝扩展；共享 API 的合法 tail 上限固定为 2000。verifier 从完整连续后缀派生 relevant multiset，逐项精确计数 panel ingress、route、call-bound、Task send、XmlSocket response、Web receipt、`PanelHost opened/closed` 与 exact close completion。首生命周期严格要求 `Web request → Host panel/route/binding/send/response → Web response → close → observer detach/loaded → SAFEEXIT provider/Host → sv:1 → sv:2 → archive → EXIT_CONFIRM → residue`；随后严格连接 restart PID/CDP/observer/open/readback/close/detach/loaded/terminal、supported shutdown、residue、disk/post-closure 与 lock release。重启 completion 必须是 shutdown 前 close-settled snapshot 与 terminal suffix 中的最后一条 relevant Host 记录；额外 rejection/close/read、near-match、缺失、重复或未知记录均 fail-closed。

上述顺序由唯一 `CANONICAL_TIMELINE_ORDER` 定义生命周期 spine，同时生成 `trustedTimeline.orderedEvents` 与 verifier 的严格 timestamp 链：first 必须是 `close settled → observer detach_hooks → loaded production capture → SAFEEXIT → save/archive → EXIT_CONFIRM → residue`，随后才连接 restart。每个阶段每个 Inventory probe/supplement 的 callId、pairOrdinal、requestAt、responseAt 另以精确 `trustedTimeline.inventoryEvents` 封印，并与 lifecycle spine 合并成无时间碰撞的全局严格链；因此补页既属于 exact request multiset，也不能从全局 timeline 消失。receipt 不再维护第二套自描述顺序；旧版把首次 detach/loaded 放到 EXIT_CONFIRM 后的列表必须拒绝。该 timeline 将 Inventory 全量读取、Host、provider、save、archive、EXIT_CONFIRM、first residue、restart close、supported shutdown、restart residue 与 lock release 绑定到同一时钟域。两次 residue 均保存 PID、可执行路径、HTTP/CDP/agent-control 三端口、credential 与稳定采样；supported shutdown 的请求、真实响应 artifact、完成点和响应成功语义缺一不可。seed、archive 和 restart 的磁盘证据各保存完整 manifest，必须至少含一份 JSON 和一份 SOL，并绑定规范化路径、bytes、digest、slot locator 与整个 artifact set 的 `sourceSetSha256`。

控制优先探测 `launcher_agent_runtime`。只有 provider-owned receipt 明确记录 unavailable reason、fallback authorization 和 capability 结果，且命令显式包含 `--allow-codex-cu-fallback`，才允许使用 `codex_computer_use`。每个 ACK 只能纯引用 provider 在 run 目录中预先写入的 `provider-receipt.v4` 与 provider-owned capture；不得承载或重述 capability、fallback reason/authorization 等准入语义。receipt 必须逐字段绑定 issuer、transport、由完整 canonical 投影确定的 operation ID、tool-result source、真实 request bytes/hash、step、owned artifact、capture bytes/hash/尺寸和 provider `details`，并严格满足 `request issued < provider started < input < capture < provider completed < ACK < expiry`；相邻控制还必须满足 `previous ACK < next request`。每一步 frozen target 都是精确 selector/tag/event/origin：capability/fallback 是封闭 non-input，open/SAFEEXIT/EXIT_CONFIRM/restart-open 是对应的原生 control，其余 DOM 控制绑定当前 catalogIndex、physicalSlot、结算、commit、数量和关闭 selector。DOM 操作还必须一对一绑定 transcript 的 `(observerId, sequence, eventSha256)` 与原始 event 的 clientX/clientY、可见/启用状态、selector/tag、viewport/rect、elementFromPoint、key/button；native/non-input 操作使用各自封闭 schema。每个 control 的 request、provider artifact、operation ID、capture path 和截图内容都必须唯一。`ack-control.js` 只验证并引用 `--provider-receipt`，不搬运截图、不制造 provider 结果。截图除完整 PNG chunk/CRC/IHDR/IDAT/IEND、无尾随 chunk/压缩流、精确 inflate 行长、filter 0–4 unfilter、像素闭包及 1/2/4/8-bit indexed PNG 的逐像素 palette 边界验证外，还必须至少 320×180；截断流、压缩尾、非法 filter、越界 palette index、魔数伪图、1×1 与 64×64 图均不获准。runner 不再写 `native_control SAFEEXIT/EXIT_CONFIRM` 自报事件。

commit 可能到达权威端后的失败禁止直接 shutdown、重播种或删除 clone；工具保留 lock/recovery，等待可见 SAFEEXIT 恢复。commit 前失败才允许 supported shutdown 后安全释放。

生产消费端不是旁路 fixture：`npcshop.js` 必须显式委托 `NpcShopRuntime.createPhysicalInventoryAdapter`，而 `npcshop-runtime.js` 中的内部 adapter 才拥有初始背包/战备箱窗口、exact NPC owner、同一个 `InventoryCoordinator`、完整 physical-surface reader、detached receipt 与 cleanup；对外只暴露一个 factory，主 façade 不再复制这套生命周期。首次打开与成功 commit 后都必须经该 adapter 取得并保留完整 `surface.windows + surface.snapshots` receipt；refresh 只重新 `open()`，不得 `resetWindow`，因此共享 physical-surface 投影会保留调用者当前页，容量缩小时才有界收缩。production closure v14 同时绑定 façade consumer、adapter 与共享 provider 三份 bytes/hash/语义锚点；inventory-surface v12 / source-anchor v10 还绑定 requestFn 同步返回 bounded expectedCallId、同步 callback 在返回后才处理、response 精确回显该 callId、异常/无效返回单次收口、一次至三批物理 surface 收据，以及精确 visible follow-up。source-anchor v10 的 callable 定位和 needle 计数排除注释/字符串假象，并用 outer-callable depth、anchor depth 与 active-prefix digest 联合锁定 retry click、reset、paired version 和 `openSettlement/requestTradePreview/commitTrade/write` 四个写前调用点。缺 façade 委托、adapter exact owner/初始窗口/页码保留/收据复制、provider 返回值、回显等值、重试接线、任一写前 gate 或旧 `return reject` 形态都不得通过。`npcshop` harness 必须断言两条刷新路径都实际发出完整补页序列（当前 fixture `A=240`）并保留 4 个 raw windows、2 个 merged snapshots、290 个槽位，同时证明翻到战备箱后页后 quick-transfer 与交易后 refresh 都不跳回首屏；canonical `--check` 必须通过独立 browser bootstrap 实际运行该 harness，不能只做源码字符串命中、只保留 UI 前 40 格，或用父进程 admission 冒充 browser 子进程闭包。

每个 Inventory response 的键集合严格等于 `{success,v,sessionNonce,snapshots,type,domain,cmd,callId,panel,panelInstanceId}`，`success=true`、`v=1`，且与请求 exact owner/call 配对；缺键、额外键、错误版本、失败 envelope、额外 pair、`A=100` 非法边界、缺 tail、callId 漂移、request 不晚于前一 response 或 response 不晚于本 request 均 fail-closed。当前 v14/v12/v10 canonical 只准得出作者侧 `OFFLINE_VERIFIED / LIVE_BLOCKED / NOT_DEPLOYED`；仍需不同作者终审与后续同候选 live receipt。

离线通过不代表 stable canonical、同候选 live E2E、真实存档、promotion 或标准入口验收完成。
