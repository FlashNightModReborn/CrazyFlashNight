# Equipment Tuning write-journey-v4

状态：`AUTHOR OFFLINE_VERIFIED / AWAITING_INDEPENDENT_FINAL_REVIEW / LIVE_BLOCKED / NOT_DEPLOYED`。

本目录只提供 A3 Equipment 调制的生产写旅程工具、证据合同和离线负例。它不修改 Host、Web、AS2 或存档业务实现；截至 2026-08-04 未运行真实写旅程，也没有访问或改写真实玩家存档。

## 当前门槛

- 历史作者自测 `244/244`、`306/306`、`324/324`、`360/360`、第四轮 `404/404`、第五轮 `444/444` 及第六轮 `489/489` 全部保留为 `Superseded / Reopened` 审计痕迹，不删除既有 before/preview/commit/fresh/restart、50 槽背包、lease/version/epoch/sequence 或旧反例合同。第七轮 `503/503`（正例 19、负例 484）也固定为 `Superseded / Reopened`：它虽关闭 Page 跨分组重排、raw tool detach 后置、非权威 icon 注入和旧 PNG 重放四个阻断，但尚未把真实浏览器执行放入独立子进程 journal。2026-08-05 当前 canonical 作者离线门为 `504/504`（正例 20、负例 484），父 manifest `aaec44e743374d19a233310377846db2d848ffd91f5d10a294696bca2344d101`、父 journal `3167bf206fddcd1bc21c222a023c10d67d91e850f9fc649e036d964d4e536596`、父回执 `9ec8a85399ed8dee5fa750e76a5cd4070dfc9d219905a9141908b1bf7c3c17e2`；该结果只允许记为 `AUTHOR OFFLINE_VERIFIED`，须由不同作者重新审阅后才可形成独立结论。
- browser 子门由 `browser-bootstrap.js` 在自己的 module journal 内运行真正的 Equipment harness：三档 viewport（`1024×576`、`1366×768`、`1920×1080`）各为 `129/129`，检查名集合完全相同且固定摘要为 `a7b945b04933e4a3769a9908b0c4ce99b184b234b31f6605e0c9d873dd7b6db9`，同时覆盖 normal/reduced motion。子进程闭合 280 个实际 Node 模块、23 个 builtin、38 个成功消费的本机资源及真正传给 Edge 的可执行文件，共 325 个 manifest entry；child manifest 为 `06f7b711d51287551ec0c7800e390354dbf9f00a5a1682f3dd5fc6533195ad9d`，child journal 为 `17f8c6a846eb58be2eb77f95e51facab83ca17d38eb63dea09e7d42b39e2b079`，child receipt 为 `3b79ceb16f7da62444397e9609345fc93c0db4f2c7a2e0d31fd020ffc4585f47`。HTTP ledger 共保存 115 个有序 occurrence，其中 114 个 served、1 个为唯一接纳的 `/favicon.ico` 失败；父级回执直接投影 child receipt、资源闭包、实际 Edge、检查名与结果摘要并以自身摘要封闭。资源缺失、额外、路由/顺序/字节漂移、目录连接越界、非当前 Edge、检查名或任一断言漂移都会使 canonical 失败。
- `bootstrap.js --check` 只证明本工具的同步 module closure、journal 和离线语义负例达到 `OFFLINE_VERIFIED / LIVE_BLOCKED / NOT_DEPLOYED`；不是 live receipt、生产 admission 或 GO。bootstrap 在加载业务模块前将 argv 精确分类为 check、纯 help、fixture emit、绝对路径 bundle verify 或 live，混用控制参数一律以 usage 失败。纯 help 不输出离线通过声明。直接执行 runner/verifier/self-test 都是 `NOT_ADMITTED`；`ack-control.js` 只是独立的闭合 ack 生产器，不是验证入口。每个成功入口的 stdout 恰好包含一个 JSON 文档。
- journal profile 按入口闭合：check/fixture emit 只能是 `domain_loaded -> audit_executed -> terminal`，外部 bundle verify 只能是 `domain_loaded -> verification_executed -> terminal`，live 只能是 `domain_loaded -> clone_prepared -> first_captured -> restart_captured -> verification_executed -> terminal`，纯 help 只能是 `domain_loaded -> terminal`。`--check`、`--verify-bundle` 与 live `finalize` 都先执行对应 verifier，验证成功才 seal/reverify/restore；`--verify-bundle` 只在当前 verification admission 成功后持久化 receipt。live pre-seal 除完整 bundle 投影外，还冻结 12 组 request/provider receipt/capture event/ack/PNG capture、4 个 native event、两份 transcript JSON/JSONL、两份最终 Host 日志与 persistence sidecar 的精确 path/role/raw bytes/bytes/hash；post-seal 重新读取当前磁盘并同时对照 ACK/provider/event reference、artifact manifest 与冻结原字节，额外、缺失、替换、重排、role/ref/hash/内容漂移均失败关闭。
- production closure 当前固定为 159 个文件：页面与 55 个生产 JS、27 个 CSS，icon/font manifest、JetBrains fallback、15 个必需预热图片、4 个条件 CSS 图片，以及相关 Host、runtime csproj/input descriptor/producer recipe/toolchain lock、AS2、`equipment_mods/list.xml` 声明的全部数据子文件和 `scripts/asLoader.swf`。producer input 固定口径仍为 `297/9/3`。`page-resource-contract.v2` 由当前树重新计算，精确枚举 Document、Script、Stylesheet、实际 `icons/manifest.json` Fetch、15 个必需图片、4 个条件图片、font manifest 的 13 条字体路由（LXGW 必需）与 icon manifest 的 1575 个名称路由。动态图标名称只允许从已经完成 strict request/response 配对且 owner/domain/callId/success 与完整 Equipment/Inventory payload 均验证通过的 authority response 导出；任意 transcript 元数据、request、diagnostic 或其他 bundle 字段都不能授权或污染图标路由。运行时 Page occurrence 必须等于一条 canonical 全局序列：Document → scripts → styles → fixed → 实际出现的 conditional → icon-manifest Fetch → authority icons → 实际出现的 fonts；每项的 URL/type/MIME/frame/source bytes/hash 均参与同一次比较，漏项、额外、重复或跨分组重排都失败。first/restart 的 `loaded-production.v6` 原样持久化全部 `Runtime.executionContextCreated`、`Debugger.scriptParsed` 与 `Page.getResourceTree` occurrence；每条 script 的 raw `executionContextAuxData` 必须存在并与其引用的 canonical context 完全相等，context 引用集合及顺序必须精确。所有工具脚本以唯一 `sourceURL` 与 raw source 双向闭合；raw `Runtime.evaluate` occurrence 必须逐项精确投影 `toolSourcePlan`，`detach` 同时是唯一末项、最终 raw tool occurrence 和整个 raw script stream 末项，detach 后出现任何工具或生产 script 都失败。终止观察后才生成最终 loaded closure。
- candidate 不是靠与 current closure 并列两个摘要建立关系。工具按 `runtime-inputs.v2.json` 精确枚举并用现役 producer 函数重算 artifactSource、producerRecipe、toolchainLock 与 build identity；随后重读候选 `runtime-build-metadata.v2.json`、`cf7-runtime-manifest.tsv` 及 payload 全文件，重算 payload closure、核对 Core DLL，并要求 authenticated `processPath` 在 manifest 与当前 payload 中恰有一个大小写精确、bytes/hash 一致的普通文件行；process 与 Core 的 path/hash 必须相互独立。该 runtime file binding 再同 current inputs、runId 与 candidate identity 一起封闭。当前源码、producer 配方、toolchain、metadata、manifest、payload、process/Core、candidate root 任一漂移都拒绝。
- Inventory 三次请求都固定为 `背包 / offset=0 / limit=50 / filterKey=all / scope=all`，initial、commit、refresh、restart 四份响应都必须是物理槽 `0..49` 的 canonical 全背包。除版本字段外的 header/facet 必须全程不变；只允许目标物理槽的语义投影变化，所有非目标槽必须逐字段相同。全部 50 个 slotLease 必须在 commit mutation 时轮换、commit 到 refresh 保持稳定、进程重启时再次轮换；不能以 equipment 筛选视图或仅目标槽比较冒充不变量证明。
- current source 还要求每个 first/restart owner 各有且仅有一条 `event=panel_exact_close_completed panel=workbench panelInstanceId=<exact>`，发生在对应 close input 之后。first/restart 都必须在该 exact-close 之后取得 provider capture、provider completion、ack，并在 terminal observer detach 被 raw script stream 证明之后才形成 loaded closure；first loaded closure 必须早于 SAFEEXIT，restart loaded closure 必须早于 authenticated shutdown。Host 行只允许零个或一个生产格式 `HH:mm:ss.fff ` 前缀并从行首精确解析；错误 owner、重复、缺失或任何 extra relevant record 均失败关闭。
- 所有跨层边界投影到同一条可比较时间线；每个 control 都要求 `request < operation start <= exact input < trusted capturedAt <= actual PNG fileModifiedAt < provider completion < ack`。全局链进一步固定 close、terminal loaded capture、`SAFEEXIT input < sv:1 < sv:2 < archive < SAFEEXIT capture/completion/ack < disk capture`、EXIT_CONFIRM、首次 residue、restart open、restart close、restart terminal loaded capture、authenticated shutdown 与最终 residue 的严格次序；每一对相邻边界都有逆序负例。重启 shutdown 证据必须绑定 exact PID、authenticated session digest、成功响应和自身摘要；Host 时间只接受一次精确午夜 rollover，普通回退、第二次 rollover、未来或超窗记录均失败关闭。
- CDP 输入事件不仅绑定 `isTrusted/button/type`，还绑定可见、可用的 `BUTTON`、步骤唯一 exact selector、viewport、元素 rect、实际 `clientX/clientY` 与 `elementFromPoint` 命中；隐藏、disabled、错标签、错 selector、越界点或非命中目标均拒绝。
- 上述阻断解除后，仍需维护者明确提供隔离 candidate、专用 `cf7_agent_*` seed/target 和一次性写授权。

canonical 离线验证：

```powershell
node tools/workbench-live-e2e/equipment/bootstrap.js --check
node tools/workbench-live-e2e/equipment/bootstrap.js --verify-bundle <absolute-journey-bundle.json>
```

生产入口（仅在全部门槛解除后）：

```powershell
node tools/workbench-live-e2e/equipment/bootstrap.js `
  --candidate-root <immutable-isolated-candidate> `
  --allow-isolated-commit `
  --allow-codex-cu-fallback
```

没有 existing-slot、reseed、正式 runtime 或真实存档捷径。目标存档始终由 frozen clone guard 创建为专用副本；失败后保留 durable recovery 状态，禁止覆盖或手工清理。

commit 控制请求一经签发就按“可能已写入”处理：即使 ack 或后续证据丢失，也不得用普通 shutdown 代替真实 SAFEEXIT。只有 commit 尚未授权，或 SAFEEXIT 已完成后的只读重启，才允许使用受支持的 `agent_control shutdown`。

## 固定旅程

第一次进程只允许以下业务命令：

1. Equipment `snapshot`
2. Inventory `snapshot`
3. candidate A `preview`
4. candidate B `preview`
5. candidate B `commit`
6. Inventory `snapshot`
7. 同一来源重新选择后的 Equipment `snapshot`
8. Equipment `detach`
9. 确认 first owner 的唯一 exact Host close-completion receipt
10. 取得 close capture/completion/ack，执行被 raw script stream 证明的 terminal observer detach，并冻结 first loaded closure
11. Launcher 原生 `SAFEEXIT`，等待唯一 `sv:1 -> sv:2 -> archive -> disk`
12. Launcher 原生 `EXIT_CONFIRM`

第二次进程只读：Equipment `snapshot`、Inventory `snapshot`、Equipment `detach`，确认该 owner 的唯一 exact Host close-completion receipt，取得 close capture/completion/ack，并在 terminal observer detach 后冻结 restart loaded closure；随后才使用受支持的 authenticated `agent_control shutdown`。任何 tooltip、reconcile、重试、额外写命令、跨 panel/view owner、复用 callId/fid 或额外进程都会失败关闭。

最终插件必须来自 `tools/equipment-tuning/fixtures/item-identity-triple.json` 的 canonical all-distinct 集合，并同时证明内部名、显示名、图标名三字段。证据还绑定候选 A/B 替换、Web callId 到 AS2 fid、完整 before/after/material plan、刷新快照、磁盘记录、SAFEEXIT archive 和全新进程重启读回。

## 控制面

Runner 不调用 Equipment 业务 API，也不合成浏览器输入。它在运行目录的 `control/requests/` 写入闭合请求，外部 computer-use 控制器完成真实 UI 操作后，通过 `ack-control.js` 写入一次性 ack。

优先级由可验证 capability 决定：只有实际启动进程合同证明 `agentRuntimeAdmission=true` 才可使用 `launcher_agent_runtime`。当前 Equipment runner 只实现并验证了 authenticated legacy HTTP 生命周期下的 `codex_computer_use` fallback；该合同明确证明 `agentRuntimeAdmission=false`，因此必须有命令行显式授权，且不能凭操作员声明提升能力。Launcher Agent Runtime computer-use 的优先 transport 接入属于 shared candidate，完成共享终审前不得在本目录冒充已可用。

`commit_candidate_b` 还必须携带 runner 生成的一次性 authorization decision。12 个 control ack 每一个都必须引用控制器预先写入 `control/provider-receipts/<requestId>.json` 的 `provider-receipt.v5`；receipt 不再自报截图时间、路径或摘要，只精确引用 transport adapter 在 PNG 原子写完并读取实际 stat/字节后生成的 `control/capture-events/<requestId>.json` / `provider-capture-event.v1`。capture event 绑定 issuer、真实 `toolResultSource`、request digest、唯一 providerEventId、`capturedAt`、实际 `fileModifiedAt`、PNG path/bytes/hash/dimensions、自摘要，并强制 `captureSemanticContentIndependentlyVerified=false`；transport 原始 capture event 是拍摄时间权威，mtime 只是同次文件写入的辅证，不能单独冒充权威。receipt 的 operation id 闭合 action/result、start/input、capture-event reference 与 completion。8 个 Web 操作逐一绑定 passive transcript 中唯一的 trusted DOM event；4 个原生步骤逐一绑定 `control/native-input-events/<requestId>.json` 的 provider-owned raw event。12 个 input eventRef、capture event identity/reference 与 PNG path/bytes 全部唯一，并严格要求 `request < start <= input < capturedAt <= fileModifiedAt < completion < ack`；旧 v4 receipt、旧截图、错序、跨 request 引用或 event/PNG/mtime 任一不匹配都失败关闭，`pageTime` 不参与跨进程权威时钟。每个 input event 继续闭合 exact selector、标签、可见/可用状态、viewport/rect/point/hit-test、key/button/repeat。`ack-control.js` 不接收、生成或复制截图/capture event，只校验并引用 provider 已预写的 receipt/event/capture；bundle、当前文件、冻结字节与最终 manifest 必须一致。

全部 12 个 control request 都强制 `requiresCaptureSha256=true`，每一步必须拥有不同的 provider-owned PNG capture；`SAFEEXIT` 与 `EXIT_CONFIRM` 的图像也必须彼此不同。校验不再停留于 8-byte 文件头，而是有界检查 chunk 边界与 CRC、唯一 IHDR、PLTE/IDAT/IEND 顺序、无文件或 deflate stream 尾随字节、尺寸/色深，并精确消费压缩流、inflate 到唯一期望行大小、执行 PNG filter 0–4 的逐行重建与像素摘要。indexed PNG 的 1/2/4/8-bit packed sample 逐像素解包并拒绝任何越界 palette index；图像至少为 `320x180`。所有 control request 的签发顺序、event/provider/ack 时序以及“前一 ack 不晚于下一 request”都是 closed partial order。`ack-control.js` 不执行 UI、不证明输入可信、不证明 Host/AS2 成功、不证明 SAFEEXIT 或持久化；ack、截图或时间戳本身都不是业务成功证据，业务成功只能由独立 CDP、Host log、磁盘和重启读回共同证明。

## Authority 与隐私边界

被动观察器在持久化前完成两套独立计算：

- 从真实 preview request 的完整 source（含原始 lease）及 canonical preview intent 计算 `sourceKeyRef` / `intentKeyRef`；
- 从 Web `preview_issued` / `commit_issued` 的原始 diagnostics 再计算同名 refs。

Verifier 要求两套 refs 与 Host structured settled receipt 三方一致。refs 为 UTF-8 SHA-256 的前 12 bytes、格式 `sha256_<24 lowercase hex>`。原始 lease、tuning token、transaction id、sourceKey 和 intentKey 均不得进入 transcript、bundle、receipt 或 Host evidence。即使伪造 Host 与 Web refs 为相同值，也会因 request-derived binding 不一致而失败。

## 证据边界

bundle 必须显式且互斥地声明证据模式：

- `offline_fixture` 必须带固定 fixture provenance、`safeExitUiJourneyVerified=false` 与模拟退出方法；它只能产生 `OFFLINE_VERIFIED / LIVE_BLOCKED / NOT_DEPLOYED`，不可被升级成 live 结论。
- `live_capture` 必须没有 fixture provenance，必须证明当前仓库 root、隔离 candidate、runtime producer/provider 条件和真实原生 SAFEEXIT 旅程；通过后才可产生 `e2e_verified / LIVE_VERIFIED / NOT_DEPLOYED`。

live receipt 仍固定保留以下限制：

- `physicalInputAttestation=false`
- `safeExitUiJourneyVerified=true`
- `captureSemanticContentIndependentlyVerified=false`
- `operatorAckTimestampsAreSelfReported=true`
- `rawAuthorityMaterialPublished=false`

它不证明物理键鼠来源、双屏行为、截图业务语义或正式部署。按 2026-08-05 本地单机、单操作者比例裁决，A3 不再等待四领域同 candidate 的联合 live；只保留本目录直接对应的一条 Equipment current-tree 旅程：同树 isolated candidate、专用 seed/target 与一次性写授权、生产 Host/AS2 delivery、一个三名分离候选的 preview、一次 commit、fresh snapshot、SAFEEXIT/archive、未重播种重启读回及零关联残留。候选替换与旧 token 拒绝继续由 current-tree 自动门证明。computer-use 无法直接命中 WebView2 子窗口时可使用本机候选页面输入通道；必须记录输入信任边界，但物理 `isTrusted`/hit-test 属于 A5，不阻断 A3 authority/data 与存档读回。当前 `504/504`、该 live receipt 与一次独立终审全部通过前，本目录保持 `NOT_DEPLOYED`，不关闭 A3。
