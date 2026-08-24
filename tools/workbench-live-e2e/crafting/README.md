# Crafting 生产闭环工具

状态：`AUTHOR OFFLINE_VERIFIED / AWAITING INDEPENDENT FINAL REVIEW / LIVE_BLOCKED / NOT_DEPLOYED`。

本目录只提供 Crafting 的生产取证、复验与 fail-closed Gate，不修改 Host、AS2、Web 业务实现，也不自行批准上线。共享 `runtime-module-journal` 的既有准入结论只覆盖共享 API；Crafting consumer 仍须取得独立 live receipt，并由不同作者完成终局审阅。

2026-08-24 合并后 current-tree 复核：`bootstrap.js --check` 为 `266/266`（21 个正例、245 个负例）；production closure v9 精确覆盖 260 个文件，browser child 闭合 377 项 module manifest、75 个实际资源与 1,509 次 occurrence。父 manifest 为 `747bb619406029fea707aaa65641953cd6758809e8ebf124839a89f3291c437c`，父 journal 为 `dd05c44cd4510a9a20d9676e92c2863ca18dfd050a4a3176c3cdc6615a6ece58`，父回执为 `ae8280e7256edb099f639d1d8db856cb8fb2aabd2d23f829db386410813f87dd`。闭包除既有字体、catalog、permanent 实体与 generated CSS/JS 外，现精确纳入 overlay terminal/settings 样式、共享 loadout picker，以及上游资产安全修订后的 24 个 AS2 算法锚；独立浏览器仍不把缺少 Host exact-set handler 的空响应冒充字体字节。该结论仍仅为 `OFFLINE_VERIFIED / LIVE_BLOCKED / NOT_DEPLOYED`。下文若仍以“当前”描述 2026-08-08 或更早的 243-file/旧资源数，只是历史合同解释，均由本段取代。

历史审计结果保留如下，均不得替代当前 Gate：

- `18/18`（3 个正例、15 个负例）：`Superseded / Reopened`；
- `42/42`（5 个正例、37 个负例）：`Superseded / Reopened`；
- `76/76`（7 个正例、69 个负例）：`Superseded / Reopened`；
- `103/103`（8 个正例、95 个负例）：第三轮修订前基线，`Superseded / Reopened`；
- `137/137`（12 个正例、125 个负例）：第三轮作者侧结果，`Superseded / Reopened`；
- `214/214`（15 个正例、199 个负例）：第四轮作者侧结果，`Superseded / Reopened`；
- 第四轮后独立终审：`NO-GO`，识别出 execution context 差集、Page resource 差集、script/context `auxData` 脱钩、90 槽未冻结、candidate Core EXE 未独立绑定、observer 非终态六个 High；
- 第五轮作者侧离线 Gate：`233/233`（15 个正例、218 个负例），`Superseded / Reopened`；
- 第六轮作者侧离线 Gate：`256/256`（19 个正例、237 个负例），`Superseded / Reopened`；
- 第七轮修订短门：AS2 结构锚 `192/192`、Web production validator `19/19`、Host `CraftingTaskTests` `49/49`，`Superseded / Reopened`；
- 第七轮稳定作者复跑：canonical 在计数前因 `as2-anchor-test.js` 缺少显式 loadable artifact 登记而 `NO-GO`；相邻结构、Web、Host、Panel、Inventory 短门保持通过；
- v7.1 最小修订：check/emit manifest 固定 27 个显式 loadable artifact，`as2-anchor-test.js` 的 exact locator/role/order/bytes/hash 与 journal event/preseal closure 定向门 `5/5`，`READY_FOR_STABLE_RERUN`。
- v7.2 测试上下文修订：保留 27 项生产闭包纯断言，将缺登记、额外 loadable、locator-only、bytes-only、hash-only 五个离线 verifier 负例移入固定参数、只读 stdin 的独立 Node 子进程；定向门 `6/6`，`READY_FOR_STABLE_RERUN`。
- v7.3 严格局部时序修订：`select_recipe` 的两个完整重封等值样本证明 verifier 曾接纳 `operation started == trusted input` 与 `capture == capture filesystem mtime`；作者侧和语义 verifier 均已恢复 README 既定的严格 `<`，并新增两个 fail-closed 负例。定向重封门 `2/2`、v7.2 module-manifest 独立短门 `6/6`；当前自测清单静态口径为 19 个正例、239 个负例、258 项，full canonical 尚未运行，`READY_FOR_STABLE_RERUN`。
- v8.0 完整产物合同修订：preview `acceptedPlan` 新增由真实 `BaseItem` 生成的 `outputPrototype {item,confirmProjection}`，commit 新增写后 `outputReceipt`；提交前精确重算计划，扣料后再次核对真实 delivery，写后以完整 Inventory 投影核对并在任何漂移时回滚。Web/Host/离线 verifier 复用 Inventory 的完整 nested validator，不再只比较身份与数量；稀有度、强化上限、插件元数据、插件签名及可选 balance presence/value 均有负例。结构锚扩大为 `384/384`，Web 为 Inventory `70/70` + Crafting `20/20`，Host focused 为 `286/286`，三视口生产 harness 为 baseline `120/120` + current `15/15` + owner `8/8` + identity `10/10`；canonical full 为 `265/265`（20 个正例、245 个负例），`AUTHOR OFFLINE_VERIFIED`。
- v8.1 浏览器与子进程闭包复核：确认 v8.0 的 browser matrix 未由 canonical 显式绑定生产 runner、实际浏览器文件与服务资源，且 module-manifest 五个负例曾被错误搬回仍有 active journal 的父进程；第一次 full canonical 因 `runtime_module_verify_while_active` 失败，保留为 `NO-GO / Superseded`。
- v8.2 作者侧结果：父门显式绑定生产 `run-crafting-harness.js`、browser bootstrap、280-file module inventory、54 required + 30 optional resource inventory、共享资源闭包与 harness；浏览器子门绑定当前 Edge 文件、三视口四组矩阵、每个场景的完整 check 名称、所有实际成功/失败资源 occurrence。定向 module 门 `6/6`；full canonical `266/266`（21 个正例、245 个负例），manifest `ef2f08716b2075509b636d6ad7b445d3ff75fa27077e5a0d68316312cfcfd1dd`，journal `b76f24ba4b6301f31efd9905fe072bfbedff033c667ce433f4de758de5012086`。后续独立复核确认父回执未持久绑定两个 child receipt，且 isolated child 在首次 journal 复验前已经加载 `self-test.js`；该结果固定为 `Superseded / Reopened`。
- v8.3 当前作者侧结果：共享资源 helper 已从实际 served occurrence 重建资源投影、逐项绑定 request pathname→relative file，并拒绝目录连接越出 root；四组检查名摘要已冻结。isolated child 改为两段 journal：第一段将 21 个受测模块作为 nonloadable current bytes 封闭并复验，确认它们尚未加载；第二段才加载并封闭同一 21 文件，复验后才调用纯 finalizer。父 `offline-check-receipt.v1` 直接投影 browser/isolated 两份 child receipt、Node/Edge、资源与检查名摘要，并以自身摘要封闭。full canonical `266/266`（21 个正例、245 个负例），父 manifest `da5789c4d5cc32d857a23c6e7a9d2d92ffe4cca4b0c439299078f64a94b4709f`、父 journal `4a79262117a9d7ce398eaf2c6282a500fdf7e58397a0651b93883144876a9d5d`、父回执 `3066c4f0f1d702f68b1d47693518dc2c3a2ffc1d23cec5f9401912635d5a2baf`，`AUTHOR OFFLINE_VERIFIED / AWAITING INDEPENDENT FINAL REVIEW`。
- 2026-08-08 current-tree 复跑：在 P4 共享 `arena.css` / `team.css` 与 P5 `ArenaTask` 纳入闭包后，full canonical 仍为 `266/266`（21 个正例、245 个负例）；父 manifest `23c0f8c2b8ebd5072ab6fe314b8cf0559b755923dbf6179dc9134698ea31f06e`、父 journal `03d97acaa94f5a2dcc71150d2b18024f771e3e4b11eeef3f1c9109872dfd08b6`、父回执 `8a53535d0cee466f77a73c2d3097dd6836e750c0b4fe31088c0981c44efe19aa`。browser child 为 373 项 manifest、69 个实际资源、605 次 occurrence，receipt `ac2c8eb63a043aa97816626386eed2988270c70a041957e360653ac9bd5c5499`；isolated child receipt `9d14863aec676dde8d2265e8f1ada71eb86330ee5a3218a41bc53c59a861f1f2`。v8.3 的旧 hashes 保留为历史，不再代表 current tree。

`AUTHOR OFFLINE_VERIFIED` 只说明当前作者已完成 v8.3 代码、定向门与 full canonical；它不等于不同作者终局审阅通过，更不等于 live receipt、部署或 A3 关闭，不改变顶部 `LIVE_BLOCKED / NOT_DEPLOYED` 状态。

## 生产 surface 与 canonical 分工

六阶段 `initial / before_first_start / after_commit / before_restart / after_readback / final` 必须绑定同一个 current-tree production closure。当前精确口径为 243 个 source role；新增条目是 Crafting lazy registry 已声明并由材料来源头像消费的 enemy/shop portrait resolver 与共享 portrait stylesheet，不改变旧合成 fixed journey 的业务步骤：

- Web 执行源 78：入口页 1、JavaScript 48、CSS 29；JavaScript 同时覆盖启动图、lazy registry、Crafting lazy 模块（含 enemy/shop portrait resolver）与 organizer 依赖，CSS 同时覆盖页面 link 与递归 `@import`；
- Web 条件资源与 manifest 23：base-map prewarm WebP 15、CSS 条件图片 6、font-pack manifest 1、icon manifest 1；manifest 再分别约束当前成功安装的 13-font 子集与权威响应实际引用的 PNG/WebP 图标字节；
- Host 13：`CraftingTask`、`InventoryTask`、pending call、bridge、formatter、panel controller、owner lifecycle、overlay、router、log、task registry、XML socket、Program；
- 其余 128：build/policy 14、AS2 19、合成 data 13、物品/装备/插件投影 data 79、SWF 3。AS2 除 Crafting/Inventory/loader 外，必须包含真实 `ItemUtil`、`ArrayInventory`、`BaseItem`、`EquipmentUtil`、`TierSystem`、`EquipmentConfigManager` 及其直接数据加载/投影依赖；data 闭包由 `data/items/list.xml`、`data/items/equipment_mods/list.xml` 与 `data/equipment/equipment_config.xml` 派生，目录缺项、重复或不安全子路径均失败。A5 的跨面板材料→NPCShop 扩展闭包另由相邻 `material-shop/` 适配器组合，不回写本 fixed journey 的步骤语义。

source fingerprint 还携带固定的 `as2AlgorithmContract`：除原有 `ItemUtil.require/acquire/contain/submit/singleRequire/singleAcquire` 与 `ArrayInventory.add/getIndexes/getItemArray/searchFirstKey/getFirstVacancy/getVacancies` 外，新增 `CraftingPanelService.executeCommit/buildPlan/projectOutputDeliveryAfterSubmit/outputReceiptMatchesPrototype/deepEqual`、`InventoryPanelService.buildOutputPrototype/buildOutputReceipt/buildItemProjectionInternal`、`BaseItem.create`、`EquipmentUtil.getMaxLevel`、`TierSystem.getAvailableTierMaterials`、`EquipmentConfigManager.getTierKey`，合计 24 个锚。每个锚必须落在唯一、file-level 的精确目标 class 中，并作为 class-body 直接成员绑定精确 visibility/static modifier；完整 signature（含 return）、return 子段、body 与全成员分别使用审计时写死的 token 数量和 SHA-256。注释和空白变化不改变该锚；class 外、`if`/额外 block、outer function、错误或缺失 modifier、重复/嵌套声明、signature/return/body 漂移，或从被测当前字节动态生成“期望值”都必须失败。

正式 runtime producer 输入另以三个不相交 domain 绑定：`artifactSource=298`、`producerRecipe=9`、`toolchainLock=3`。candidate 必须携带真实 `runtime-build-metadata.v2.json` 与 manifest；Gate 重新计算 payload set、payload closure、producer 输入摘要，并将认证 `processPath` 对应的唯一 Core EXE manifest 行、Core DLL 行与两份当前实体的独立 bytes/hash 一起绑定，禁止只信任 runner 自报身份。

职责边界固定为：

- `source-contract.js`：production source inventory、六阶段 current-tree 字节指纹与 source binding；
- `runtime-producer.js`：runtime producer 输入枚举、candidate metadata/manifest/closure 的独立重算；
- `cdp-passive-observer.js`：从 `Debugger.scriptParsed / Debugger.getScriptSource / Page.getResourceTree / Page.getResourceContent` 取得未排序、未预筛的原始加载 occurrence 与实际字节；
- `protocol.js`：执行生产 `panel-runtime.js`、`inventory-runtime.js` 的真实 validator，并核对业务旅程；
- `evidence-verifier.js`：唯一语义判决器；runner、observer、computer-use 回执均不能自行给出 verdict；
- `bootstrap.js`：唯一模块准入、离线检查、live 与 bundle 复验入口。

模块 manifest 按模式保持精确闭包：live/help/verify 为 24 项（23 个 loadable artifact + 当前 Node 可执行文件），emit 为 28 项，check 为 36 项。emit/check 额外登记 `self-test.js`、`as2-anchor-test.js`、`fixtures/valid-bundle.js`、`ack-control.js`；check 再以 nonloadable current bytes 绑定生产 browser runner/bootstrap、module/resource inventory、共享资源闭包、真实 harness，以及 isolated module bootstrap/inventory。其中 `as2-anchor-test.js` 必须以 `root:tools/workbench-live-e2e/crafting/as2-anchor-test.js`、role `offline_gate_dependency`、排序索引 9 和当前 exact bytes/SHA-256 同时出现在 manifest、`loadedFiles/cacheAtRestore` 与从 `self-test.js` 发出的唯一 journal load event。缺失登记、额外未加载模块及 locator-only/bytes-only/hash-only 漂移只在 `isolated-module-contract-bootstrap.js` 的封闭子进程中验证；该子进程的第一份 26-entry manifest 将 21 个受测文件登记为 nonloadable 并在它们尚未进入 cache 时完成 seal/reverify/restore，第二份 26-entry manifest 才将它们作为 loadable 加载并再次 seal/reverify/restore，之后才调用纯负例 finalizer。两段 manifest/journal、Node 实体与结果摘要全部进入 child v2 及父回执。active 时离线 verify 仍必须返回 `runtime_module_verify_while_active`，未声明模块仍必须返回 `runtime_module_external_not_declared`；未知模块策略不使用通配、跳过或兼容回退。

浏览器子门的显式 module manifest 为 374 项：bootstrap/journal/helper、module/resource inventory、共享资源闭包、280 个 Node/runtime 文件、87 个 required/optional Web 资源和当前 Edge 文件。每次运行必须实际观察全部 57 个 required 资源；30 个 dress-up 帧只允许是 manifest 预绑定集合的运行时子集。当前实跑观察到 69 个资源、1152 次 occurrence；唯一允许失败为一次 `/favicon.ico` 与三次显式缺图探针，其他漏读、额外请求、字节漂移、未闭合请求或浏览器路径漂移均失败。三种 viewport 各自必须精确通过 baseline `150`、coverage `15`、fault `8`、identity `10` 与材料商店导航 `11` 项，父门逐组核对唯一名称和完整结果，不只核对总数。

first/restart 实际加载集合都必须精确为 JavaScript 46、CSS 29；script occurrence 另含唯一 Overlay page occurrence与每次工具注入 occurrence。observer 必须先完整保留所有原始 `Debugger.scriptParsed`（包括空 URL），其中原始 params 与原始 `executionContextAuxData` 是不可变 script-side 真源；`Runtime.executionContextCreated` 的原始 context 与 `auxData` 另作不可变 context-side 真源。后到 context 只能补齐独立 `contextOrigin` 投影，不能覆盖 script-side 原值。verifier 对两边 required keys、逐字段及深比较全部复核，再把 execution context 收窄为 script 首次引用顺序的精确投影；任一侧缺失、错配、覆盖、额外未使用 context、缺失 context 或重排均失败。随后对每个 `scriptId` 调用 `Debugger.getScriptSource` 闭合起止位置、sourceMap URL、source bytes/hash/method。`Runtime.evaluate / Page.addScriptToEvaluateOnNewDocument` 使用由 `observerId + sequence + label` 唯一推导的稳定 `cf7-evidence://...` source URL，并由 tool plan 逐项绑定；`detach` 必须是 plan 与 raw script stream 的最终 occurrence，随后才允许冻结 `loadedProduction`。匿名、未知、重复、漏执行、终态后仍有 occurrence 或重排都失败。

`Page.getResourceTree` 的每个 frame/resource occurrence 也以原始对象、frame/resource 序号、URL、type、MIME 与条件资源读取结果全量保留。原始流必须按四层闭合：固定 `Document 1 + Script 46 + CSS 29 + base prewarm Image 15`；实际成功加载的 6 条件 CSS 资源子序列；当前 manifest 已安装且实际成功路由的 Font 子序列；由本生命周期成功 Crafting recipe/output/material 与 Inventory item/mod 响应推导的精确 icon 资源。CSS 清单只能从该原始流按原顺序派生，不能另造一份已筛选事实；条件 CSS、Font 与 icon 必须由 `Page.getResourceContent` 绑定 current bytes。缺失、重复、未登记的非 CSS 资源、额外或 foreign URL、重排、跨 frame/context、错误获取方法、读取失败、字节与 current-tree/manifest 不一致均失败。

## 90 槽 Inventory postcondition

Inventory request 顺序固定为 `背包 offset=0 limit=50`，随后 `战备箱 offset=0 limit=40`。背包必须是 `capacity/access/view=50`；战备箱生产容量必须是 400，当前首个已解锁 40 格页面按物理槽 `0..39` 投影，不能用假 `capacity=40` 代替。两容器都必须经过真实 `inventory-runtime.js` nested validator。

commit postcondition 不再只累计产物 identity 数量，而是按真实 AS2 `ItemUtil.submit(requirements) -> ItemUtil.singleAcquire(output)` 顺序模拟：

- requirement 名不得重复，也不得与 output 自引用；这两种未来输入在当前 AS2 字典规划中存在覆盖歧义，Gate 直接拒绝；
- 装备强化需求从最低槽取第一件强化等级达标装备，装备数量需求从最低槽取前 N 件；普通栈从最低同名背包槽依次扣除；
- AS2 preview 依据实际 `ItemUtil.contain` 扣料计划为每项材料投影 `storageKind`，并在虚拟执行扣料后投影 `outputDelivery {available,storageKind,mode,physicalSlot,quantity}`；可提交预览还必须携 exact `acceptedPlan` 与严格 `outputPrototype {item,confirmProjection}`。commit 在首次写入前重算并精确比较完整计划，真实扣料后再以 `ItemUtil.singleRequire` 核对 delivery，写后返回 `outputReceipt`；任何阶段不一致都回滚，不允许 Host/Web 按名称猜路由；
- live runner 在任何 commit 授权、控制请求或点击之前，必须按固定的七次只读顺序取得 fresh Crafting preview 与一次完整 90 槽 Inventory，并调用与 postcondition 相同的 planner。当前可观测面只接纳全部扣料都明确落在 50 格背包、且产物 authoritative delivery 与确定性背包 merge/insert 完全一致的计划；材料/情报 collection、药剂栏、`bag_and_drug`、`unavailable` 或任一无法证明的 route 均在 commit 前 fail-closed，负例必须证明零 commit 控制请求和零 commit 业务请求；
- 产物装备进入消耗后的第一空槽；普通栈合并最低同名背包槽，否则进入消耗后的第一空槽。预览 `outputDelivery` 的 mode/slot/quantity 必须与这一 planner 精确相同；
- verifier 的预期 output 槽只能由 preview `outputPrototype` 与 commit `outputReceipt` 组成，不得把 after-readback 克隆成自身期望值。receipt 的完整 item 与稳定 confirm 字段必须等于 prototype，仅允许 merge 数量与真实 `lastUpdate` 按合同变化；装备 insert 与普通栈 merge 都有正例，rarity、max enhancement、mod metadata/signature、balance presence/value 漂移均必须拒绝；
- 预期 shadow bag 必须与 after-commit 50 槽逐字段一致；40 个战备箱槽不得变化；除 `slotLeaseRef` 外所有非参与槽保持精确不变，输出 merge 的 `lastUpdate` 只能单调推进；
- after-commit 与 fresh restart 的完整 90 槽、item、`confirmProjection`、facets、容量和窗口必须一致；跨进程只忽略 `slotLeaseRef / snapshotSeq / containerVersion / containerEpoch`。

这是一条有意收窄的安全 Gate，不声称覆盖 282 个生产配方的所有 collection/药剂投递。协议已经投影这些真实能力，但 live 证据尚未读取药剂栏/collection；若后续需要通用准入，必须先增加对应权威读回并扩展同一 planner，不能仅因 AS2 声称路由可用就由 Web 或 verifier 外推成功。

## 唯一入口

离线 Gate：

```powershell
node tools/workbench-live-e2e/crafting/bootstrap.js --check
```

live journey：

```powershell
node tools/workbench-live-e2e/crafting/bootstrap.js `
  --candidate-root <隔离-candidate-绝对路径> `
  --seed-slot cf7_agent_a3_crafting_seed `
  --target-slot cf7_agent_a3_crafting_run `
  --craft-count 1 `
  --allow-isolated-commit `
  --allow-codex-cu-fallback
```

production bundle 复验：

```powershell
node tools/workbench-live-e2e/crafting/bootstrap.js `
  --verify-bundle <绝对路径\journey-bundle.json> `
  --receipt <绝对路径\verification-receipt.json>
```

`--receipt` 可省略；路径必须是绝对路径，控制模式不可混用。`--emit-offline-admission-fixture` 只用于审计 bootstrap/journal 本身，不能生成 live verdict。`isolated-module-contract-bootstrap.js` 仅允许由 canonical self-test 通过只读 stdin fixture 内部调用，不是独立 Gate，也不能生成 live verdict。

下列文件直接执行均为 `SUPERSEDED / NOT_ADMITTED` 并返回 2：

- `self-test.js`、`run-checks.js`、`fixtures/valid-bundle.js`；
- `run-live-journey.js`、`verify-live-journey.js`；
- `run-crafting.js`、`run-session-checks.js`、`verify-receipt.js`、`verify-session-evidence.js`。

`ack-control.js` 是外部控制提供方写入回执的辅助入口，不是另一个 Gate。`passive-recorder.js` 只保留被动 observer 的兼容导出。

## Computer Use 与 provider receipt

当前生产进程合同由实际 argv 和 PID-bound credential 共同证明：`legacyHttpAutomationArg=true`、`agentRuntimeAdmission=false`，credential capabilities 必须精确等于当前七项 legacy allowlist。因此当前 Crafting 路径不可声明 Launcher Agent Runtime 可达；只有启动命令显式给出 `--allow-codex-cu-fallback` 时，才允许选择 `codex_computer_use`。任何手工翻转 capability、额外或缺失 credential capability、隐式降级都会 fail-closed。

15 个控制步骤必须各有一个精确 request、ack、独立的 `workbench-live-e2e.crafting.provider-receipt.v5` receipt 与独立的 `provider-capture-event.v1`。provider receipt 必须绑定：

- 同一 `runId / requestId / step / transport`；
- transport 对应的独立 `issuer / toolResultSource` 和唯一 provider operation id；该 operation id 由 receipt v5 的 request、action/result、输入、capture-event 引用与时序投影确定性推导；
- provider 实际读取的 request 文件精确字节 SHA-256，而不是重序列化后的等价对象；
- 精确 `startedAt / inputEvidence.observedAt / capture-event.capturedAt / completedAt`；
- Web DOM 输入与 transcript 中唯一 `(observerId, sequence, eventSha256)` 的全字段投影，或 native 输入的显式 `eventRef=null / tagName=NATIVE`；
- provider 自己预写的固定 receipt、capture-event 与 `control/captures/<requestId>.png` 路径；
- capture-event 必须在 receipt 前封存并由 receipt 精确引用其文件 SHA-256 与事件摘要；事件绑定当前 PNG 的 SHA-256、bytes、width、height、精确 filesystem mtime、request/step/provider 身份，且 `captureSemanticContentIndependentlyVerified` 必须固定为 `false`。

每步必须严格满足 `request < operation started < trusted DOM/native input < capture < capture filesystem mtime < provider completed < ack`，且全部落在 request TTL 内；15 个 request digest、provider operation id、provider capture-event id、input evidence digest 与 capture digest 均不得复用，Web eventRef 还必须构成无缺口、无额外、无复用的一一映射。陈旧/乱序事件、错误引用、PNG 替换、bytes/hash/dimensions/mtime 漂移或把语义标志伪装为 true 都必须失败。

ack helper 只引用 provider 已写入且已经 capture-event/receipt 双重封存的当前截图，不接受、复制或重命名调用方传入的截图；artifact manifest 必须同时收录 capture、capture-event 与 provider receipt。每个步骤（不限于 SAFEEXIT/EXIT_CONFIRM）都必须有独立全屏 PNG，最小为 `320x180`。PNG 会完整检查 signature、chunk 顺序、CRC、所有 IDAT 的 zlib 输入必须恰好消费完毕、inflate 长度必须精确、扫描行 filter `0..4` 必须可逆重建；indexed PNG 的每个像素还必须落在 PLTE 范围内。尾随/拼接 zlib 流、任意尾字节、截断 deflate、非法 filter/palette、空壳、过小尺寸、错误路径/摘要、复用或调包均失败。

trusted click 还必须证明精确 selector、`BUTTON`、可见且可用、正面积 DOMRect、viewport、实际 client point、坐标位于 rect/viewport 内、`elementFromPoint` 命中同一目标以及 `event.isTrusted=true`。

CDP observer 只记录真实 `Bridge.send` 和只读页面证据，不点击 DOM、不调用业务 API、不制造 provider receipt。外部 computer-use 回执只是控制来源证明，不能替代 Host、Flash、持久化或重启读回证据。

## Host、请求绑定与唯一时间线

当前 Host 日志只接受 `HH:mm:ss.fff ` 的 `LogManager` formatter。每个 first/restart 生命周期都从已认证 terminal boundary 后取样，先分类再核对精确 multiset：ingress、panel request、route、call-bound dispatch、Flash dispatch、same-fid response、incoming close、exact close completion。near-match、额外/重复 family、`rejected message from a non-ready Web document`、deferred/race 或不带当前时间前缀的 relevant 行均为失败。

每个 response 必须同时绑定原请求的 `fid + cmd`；只复用 fid 但返回另一操作不能通过。Crafting v1 没有 `transactionId`，写权限链固定为 `preview craftTokenRef + acceptedPlan -> precommit 90-slot admission -> commit expectedCraftTokenRef + exact acceptedPlan echo -> fresh Crafting/Inventory postcondition`，任何伪造 transaction 字段或计划漂移都会失败。

所有 Host 本地时间、transcript 时间、provider receipt 时间、文件/归档时间与 shutdown/residue 时间被归入同一受信时间线。Host 的 `HH:mm:ss.fff` 按 authenticated snapshot 的本地日期有状态重建：只允许一次精确 `23:xx -> 00:xx` rollover，普通回退、第二次 rollover、未来日志或超过边界的窗口都失败，不能用文件顺序代替真实时间。

全局 Gate 固定为以下 48 个边界、47 组相邻严格顺序；缺失、额外、重排、时间不可比，或任意相邻项不满足严格 `<`，均返回 `global_partial_order_invalid`：

```text
commit_response
< close_request < close_operation_started < close_dom_input < close_exact_completion
< close_capture < close_capture_mtime < close_provider_completed < close_ack
< safeexit_request < safeexit_operation_started < safeexit_native_input
< sv1 < sv2 < archive < safeexit_capture < safeexit_capture_mtime
< safeexit_provider_completed < safeexit_ack
< archive_disk < first_loaded
< exit_confirm_request < exit_confirm_operation_started < exit_confirm_native_input
< exit_confirm_capture < exit_confirm_capture_mtime
< exit_confirm_provider_completed < exit_confirm_ack
< first_clean_residue
< restart_open_request < restart_open_operation_started < restart_open_native_input
< restart_open_capture < restart_open_capture_mtime
< restart_open_provider_completed < restart_open_ack
< restart_close_request < restart_close_operation_started < restart_close_dom_input
< restart_close_exact_completion < restart_close_capture < restart_close_capture_mtime
< restart_close_provider_completed < restart_close_ack < restart_loaded
< restart_shutdown_request < restart_shutdown_completion < final_clean_residue
```

15 个 control request/ack 还须独立保持严格串行与 TTL；每个 provider v5 receipt/capture-event 的六阶段时序同时由局部合同和上述全局链交叉约束。

不再用多个互不绑定的“局部顺序通过”拼成最终结论。

## live journey 与持久化

runner 从 live 权威 snapshot 选择 `canCraftOne=true` 且满足可选 `--category / --recipe-index` 的配方，并把最终 selector 写入一次性授权、request、transcript、Host 映射和 receipt。固定旅程为：

1. journal 安装显式 manifest，在任何克隆写入前绑定 candidate；
2. 准备 `cf7_agent_*` 专用 JSON、全量 SOL 克隆、锁与恢复记录；
3. 首次启动，读取 Crafting snapshot/preview；
4. commit 前通过 organizer 读取背包 50 格与战备箱 40 格，再返回 Crafting 获取 fresh token/acceptedPlan；随后在任何 commit 授权、控制请求或点击之前，以同一 planner 验证 exact 七次只读顺序、90 槽和 authoritative route，不能证明即停止；
5. 仅提交一次，随后读取 fresh Crafting 与 Inventory，并按 submit→acquire 模拟验证精确 90 槽差量；
6. exact close 后通过可见 `SAFEEXIT -> sv:1 -> sv:2 -> archive` 落盘；确认磁盘稳定后先执行带终端 sourceURL 的 observer detach 并冻结 loaded closure，再执行 `EXIT_CONFIRM` 和零残留证明；
7. 同一 candidate、同一 clone 新进程重启，只读复验 Crafting/Inventory、session freshness 与持久化字节；
8. exact close 后先执行 terminal detach/final loaded capture，再做 authenticated shutdown、最终零残留、seed 不变、释放 clone；实际语义验证必须先执行，随后记录 `verification_executed`，再 seal/reverify/restore journal；封存后只允许绑定 journal、闭合文件 manifest 并输出，receipt 只能在 journal admission 成功后落盘。

disk、archive、afterCommit、afterRestart 与 artifact JSON 的规范路径、SHA-256 和 bytes 必须一致。commit 可能到达权威端后的失败不得重新播种或直接结束进程；若可见恢复也不可用，则保留 clone、锁和 recovery 证据并 fail-closed。

## verdict 边界

`offline_fixture` 只可在 canonical `--check` 的显式 test-only 路径中使用，并必须携带 synthetic/non-live provenance、`safeExitUiJourneyVerified=false` 与 `exitMethod=offline_fixture_simulation`；常规 verifier 必须拒绝给它 live verdict。只有 `evidenceMode=live_capture`、`evidenceClass=production_capture`、`safeExitUiJourneyVerified=true`、`exitMethod=safeexit_ui` 且上述 source/candidate、实际加载、Host、provider、持久化、重启、零残留和 journal 全部通过，才可产生 `e2e_verified / NOT_DEPLOYED` receipt。

离线 Gate 通过不代表 live E2E、部署或最终审阅通过。当前仍禁止据此自行签署 GO；终局结论由不同作者复核。
