# Launcher runtime v2 可复现构建与发布列车

**文档角色**：Launcher Windows runtime 的身份、构建、证明、排队、promotion 与 CI 策略 canonical deep doc。
**当前正式发布（2026-08-11）**：跨层回包键契约修复（商店购买结算、Loot 快照 balanceSummary 剥离、装备调制 loadout 失败包、角色构筑 reconcile 快照与失败码）release source `a87be26f1d6e80c0ea8883bbc10e46c895c35799`（tag `runtime-build-v2/20260811-cross-layer-wire-contract-v1`）、release tree `32e5b9be67de220eb297e6c568c90546b283c471` 与 request `44A8D5461BE38E0807A7BE1DFEDAD4F5065F7981C590460CAEBAB4153E577A5E` 已完成正式 promotion。无 candidate id 的正式入口复验 `runtimeMode=formal_runtime`、Guardian 总线就绪、Core SHA-256 / build identity / payload closure 与被提升身份一致；AS2 侧修复由同一 tree 的 `scripts/asLoader.swf` 承载，经 fresh trace 门（item-panels NPC 48/48、map-loot 151 断言、equipment-tuning 60/60 + 147/147）与全量 xUnit 3308+3/3311 验证。这些证据不代表物理双屏、物理设备输入、任意业务写或玩家目视签收。下行 P4/P5 与 A1–A6 段只保留为历史记录。
**上一 P4/P5 正式发布（历史明细）**：竞技场 P4/P5 与商城旧档兼容 release source `bf9be8c43b223b84f487464a7e6aa9eb8211630b`（tag `runtime-build-v2/20260808-p4-p5-source-complete-v1`）、release tree `44de7f66421a908723f196718e42867dce601f30` 与 request `424D9CC1975CF099A705C828E354215EF3F568B7198B6B19C13DB019CB25163C` 已完成正式 promotion。无 candidate id 的正式入口通过项目自有 Agent Runtime MCP 完成 Launcher 与 allow-listed Help WebOverlay WGC、strict terminal receipt、supported shutdown、存档不变及无新增残留进程的窄纵切，严格达到 `standard_entry_verified`。商城旧档与竞技场业务正确性由同一 identity/closure 的独立真实 E2E 持有；这些证据不代表物理双屏、物理设备输入、任意业务写或玩家目视签收。
**上一 A1–A6 正式发布（历史明细）**：双栏工作台 A1–A6 release source `730c6be781ddd22bfd7a59a2e7773acce892f105`（tag `runtime-build-v2/20260806-workbench-authority-a1-a6-v2`）、release tree `1434e71d44fe41ad0fa426bc857085f1aff940dd` 与 request `D45D0DEF50E159B8A875DCA922D856BEC69D64A6B779B6B7B7082D68AC6B92CF` 已完成正式 promotion。无 candidate id 的正式入口通过项目自有 Agent Runtime MCP 完成 Launcher 与 allow-listed Help WebOverlay WGC、strict terminal receipt、supported shutdown、存档不变及无新增残留进程的窄纵切，严格达到 `standard_entry_verified`。该状态不代表 Character/Equipment 业务 opener、A1–A6 写操作、物理拖拽、玩家目视签收或所有专项实机旅程；详细闭环见 [双栏工作台治理 ADR](双栏工作台-权威数据与交互能力一致性治理-ADR-2026-08-01.md) §18，F8 记录继续作为历史发布证据。

## 当前迁移状态

当前 consensus 的 artifact source 为 `7EC9CCD5E599A2F5EAD16982CF89C02DF5F2B2FCE5AA7575D8E599CD689D1C0B`、producer recipe `B97998EA7246D6AB667902BCBBD7994DFA5F658A37CFA427D2EEEABA6924DE28`、toolchain lock `7B83229BE93F8244810CDD23DAFD97875B23857E547DE520035FE23B453CB3CD`、policy `CA86E91A0589EAC1F8AD98756D924BE37299BBE829F7E7D7C350815F6D10E668`；build identity `C510ED0C27E78F3FE2552AFA37C3E3B2E673CEC54B8B5AC4E69D516D72BBD8BC`、payload closure `844B898C7B74633DF7392298286E3A354D24F344B2A02DEF9C6E5545DC1ACF81`、manifest SHA-256 `D9A73B81ED30E7EF76D77F350B74DEA5C235A280F323D6E98A52E55B696D3DAE`、promotion 后 Windows worktree consensus bytes SHA-256 `0D1A5B8C5FBD4F77724D0B1B70D22794F4B6B63B97589CA637824994ED36AF37`。production policy receipt SHA-256 为 `A58A0156B0FB08EAA45652C33743667AD8E8A2CA196915A0110F8703AF4305DC`；本地 X509 signer `28DBEAF3761CCF3177FE396596A2557D8A6C9393371CD41DC893FF75A02723B3` / `physical-host-a` 与 GitHub OIDC builder `3E77465E447FC185EB02F5199A41BBA5D44E77F3811581C69B9B79FCFF02931F` / `github-hosted-windows`（run `31441180193`）满足双 signer、双 faultDomain、production receipt 与 v2 strict/full-install verifier，于 `2026-08-10T23:16:53.1411575Z` 完成 promotion。队列为 ACL 收紧的 `C:\qcb11`；cloud 首次 dispatch 即成功，没有恢复或重发。

当前正式部署的 Core EXE SHA-256 为 `55EABB5C3280FDFEE8302843D969C6B6354808F1AF4DC24DB5E2397AA80499D8`，Core DLL SHA-256 为 `E7C940D42974ADEC926F107B283C68ED1920C95F899EEC5A2170AAB79A637A76`。无 candidate id 的正式入口启动复验取得 `runtimeMode=formal_runtime`、33-file integrity、Guardian 总线就绪与 identity/closure 精确匹配；本轮未运行 Agent Runtime MCP 窄纵切与业务专项实机旅程，不声称 `standard_entry_verified` 之外的等级，也不外推任何业务写或玩家目视签收。下行仍以“当前”描述 `bf9be8c43b…` / `730c6be781…` 的段落均按历史列车输入阅读，不覆盖本段。

runtime v2 的工具、schema、队列、本地 X509 证明、GitHub OIDC/Sigstore 证明、promotion 与 CI 状态机已经完成正式闭环；**仓库当前受控部署已是 manifest/consensus v2**。上一 A1–A6 consensus 的 artifact source `066629EB072083E80BAD5629377CADE36E11BE6962309B8A8CBC0EBC789B4451`、producer recipe `B97998EA7246D6AB667902BCBBD7994DFA5F658A37CFA427D2EEEABA6924DE28` 与 toolchain lock `7B83229BE93F8244810CDD23DAFD97875B23857E547DE520035FE23B453CB3CD`，在 policy `5663E9FE9108E25A4E9C5831EA1B53DF040130D3F50386DF3EC88A30F300C61E` 下形成 build identity `E203E4F06F6701F8B583768145AE64F93D2599238C290DD71FD50A9FBAA7B422`；payload closure 为 `F606DF4D2B11579121C7122ECB80734053B0BDF39948921C65B0FDC6CB66800F`，manifest SHA-256 为 `9F96A65006985BA27E2CDEC9B67FCC684974B4FCF3BD33CAA8B1D13BC7480517`，promotion 后 Windows worktree consensus bytes 的 SHA-256 为 `83C5111A56AAFD50790E71FF3122EE13CD075B5CE34043ECDDF1DEE7B07F0EE7`（不是 Git clean-filter 后 LF blob 的字节哈希）。production policy 26/26 receipt SHA-256 为 `C454E4394B0CAB0FC1F8193A4A2D2129AB1734BF4137D00EB2CD4D1C483ECEF4`；本地 X509 signer / `physical-host-b`（keyId `EB5D32E04B6EE8697850314E19698DE1A3FACFFCCC6418A12CF7FEDE6033CDA5`）与 GitHub OIDC builder `EF1DBDFE50A7A18E262ED5C10132C32155CC18BEB0D74E20E71EA6471D11756E` / `github-hosted-windows`（run `31101353810`）的双 signer、双 faultDomain、production receipt 与 v2 strict/full-install verifier 全部满足后，于 `2026-08-06T12:52:12.7937229Z` 完成 promotion。

上一 A1–A6 request 使用 ACL 收紧的 `C:\qw6` 与显式 UTF-8 本地 worker，并且只 dispatch 一次 GitHub run `31101353810`。轮询期间一次瞬时 TLS 超时后只恢复同一 run id，没有重新 dispatch；最终本地与云端有效证明精确绑定同一 source tag/commit/tree、build identity 与 payload closure。首列车 `99919be46d…` / v1 因 `WB112` 五个超限模块在本地 production policy 失败，未 dispatch、未 promotion，作为 superseded / NOT_DEPLOYED 证据保留；此前 F8 与 no-AS2-fallback requests 均只保留为历史。

v1 与一次性 `migration-bootstrap` 现在只保留为历史迁移审计输入。该 marker 曾精确绑定 base `711c469036ad6b1226833faf255499abb1ebf2ed`、旧 artifact closure 与目标 builder registry 字节哈希，并在 legacy deployment 零变化时解决“cloud workflow 必须先进入 default branch”的 bootstrap 悖论；marker 后的首个部署提交已经完成完整 v2 promotion。CI 从此只接受 v2 strict 状态，并永久拒绝 v2 → v1 降级。

上一 A1–A6 正式部署对应 source commit `730c6be781ddd22bfd7a59a2e7773acce892f105`、build identity `E203E4F06F6701F8B583768145AE64F93D2599238C290DD71FD50A9FBAA7B422`、payload closure `F606DF4D2B11579121C7122ECB80734053B0BDF39948921C65B0FDC6CB66800F`、Core EXE SHA-256 `86DF1F5DC611037DB3A85FD9BA0D43490394F232D25A4F62B59AA4F2B4B6E4FD` 与 Core DLL SHA-256 `75F35C025BDE29D4D713671763511B425D1AFA5758DD154931AC0FC5C59C4977`，包含双栏工作台 A1–A6、F8 Agent Runtime 与此前正式能力。无 candidate id 的正式根入口以 `formal_runtime` 启动并绑定上述 consensus；`tmp/manual-agent-acceptance/workbench-v2/formal-workbench-20260806T133125Z.json`（SHA-256 `932EB04FC699BC263A4F70980A4BF87CE5F2B9147104429559E38C82F0CA7B8A`）取得 `acceptancePassed=true`、Launcher/Help WebOverlay WGC、one-shot terminal receipt、可信 shutdown、测试存档不变与退出后无新增 Launcher/Core/Flash 进程，故该窄纵切严格达到 `standard_entry_verified`。native identity / closure 只覆盖正式 runtime 文件闭包；Web/Flash 字节与本轮行为另由冻结 source/release tree、production policy、报告和实际窗口绑定。本轮没有 Character/Equipment 业务 opener、A1–A6 写操作、物理拖拽、玩家目视签收或所有专项实机旅程，不能把总体状态外推成这些专项验收。

**PlayerInfo main-space v2 当前状态**：下面保留的旧 F/tag/request/quorum/47-Gate/Kimi 数值均为历史专项证据。qualification 闭包修复后的 F2 `891d9b08dbd826d8b2624c6bdc59082b3db57ecd` / r2 列车自身仍是 non-deployment train；其实现字节随后先被 `730c6be781…`、现被 `bf9be8c43b…` release 包含并进入 formal runtime。B0 仍为 `b0_accepted`，oracle 仍为 `oracle_frozen_for_b0`；本轮 formal smoke 虽观察 Launcher 与 Help WebOverlay WGC，却没有启用 PlayerInfo fixture、观察真实 `pi_*` 或执行 PlayerInfo-specific standard-entry E2E，因此不能从总体 runtime 发布状态外推 PlayerInfo 专项验收。

**r2 非部署可复现闭环**：request `6B5E9BDD5393553871C646952B1266E877D8B8941D50AB510B5387FC1261460D` 绑定 artifact source `6AAF891B6A27681B7493782FF9D85B3527DBD4B25AB086AABEDEEC02A062A4E0`、producer recipe `B97998EA7246D6AB667902BCBBD7994DFA5F658A37CFA427D2EEEABA6924DE28`、toolchain lock `7B83229BE93F8244810CDD23DAFD97875B23857E547DE520035FE23B453CB3CD`、policy `4F3F7749564CD82272B014C5EFF7A962FB63A533185AD3B27612C79CFF12744B` 与 build identity `DAE8A71C0AE04AF1BD89B0076DB1EF6EF5DFEEC51C32843D300D868581568ED1`。本地 X509 signer `EB5D32E04B6EE8697850314E19698DE1A3FACFFCCC6418A12CF7FEDE6033CDA5` / `physical-host-b` 的 23/23 production receipt 为 12,144 B / SHA-256 `91BBF333D4EC65A387D9A7CF94A73F8B43F54A77E05F7C684821F767FAF630D5`；GitHub OIDC signer `1B2F3B53CC50695D620A90CE423BEF3FC55C0866AEE958E7A8042BE682185630` / `github-hosted-windows`（run `30502544175`、artifact `8744105960`、archive digest `9D3B5B760AFEABEB3F7E89D5490421B3F44BAB777EF4A4FA4A4DF4C325D490F3`）的 23/23 receipt 为 11,884 B / SHA-256 `454EA66A721BC59E63E81169F5E4832490788FDC21CC2C37925E9D0B76FB2C9F`。两者独立产出同一 33-file payload closure `051FA840019E24763724B5DA0868486AF94322F3BB990B1354D181989AA94D2C`、Core SHA-256 `6BBE712CB0F97AC127FA3DF18158CA3976D7A03A64DC8121794E7C7C1E18C6CC` 与 manifest SHA-256 `53F44B8188A425728975197CD8B38FF5CE523B0306CA2EB8EE1ECBD76FF77261`。[`runtime-promotion-preflight-main-space-v2.json`](../tools/player-info-hud/evidence/b0-06/runtime-promotion-preflight-main-space-v2.json) 为 15,128 B / SHA-256 `2D0A2A862ADFFF4254FB8AFB910B1529568DABD33350AE8E735AC20F52B47356`，`proofCount=2`；33 表示 manifest 枚举的 payload files，不把 manifest 自身另算成第 34 个 payload。本 closeout 单元同时包含该文件与 current-truth 文档；只有二者在同一提交落盘后才是 tracked evidence，单独的生成文件或文档不得如此称呼。报告的 runtime/release-state mutation、promotion、deployment 与 reusable-as-promotion-input flags 全为 `false`，故它只关闭机器可复现门，不能作为 promotion 输入，也没有执行 candidate、E2E、promotion 或部署。本段不声称在 F2 重跑 historical v1 的 Runtime Lane C。

**F2 隔离候选执行证据**：在上述 `-VerifyOnly` 之后，独立开发启动使用 candidate root basename `c-dae8a71c0ae0-08846e81b3-20260730t004223766z-e8ce2e3c`。其 metadata 绑定 build identity `DAE8A71C0AE04AF1BD89B0076DB1EF6EF5DFEEC51C32843D300D868581568ED1` 与 payload closure `051FA840019E24763724B5DA0868486AF94322F3BB990B1354D181989AA94D2C`，Core SHA-256 为 `6BBE712CB0F97AC127FA3DF18158CA3976D7A03A64DC8121794E7C7C1E18C6CC`。Guardian PID `21628` 从该 exact candidate 启动。用户于 `09:05:48` 点击 `start_game` 后，成功 child Flash PID 为 `20644`，命令行精确加载 human-live worktree 的 `Adobe Flash Player 20.exe` 与 `CRAZYFLASHER7MercenaryEmpire.swf`。同一 attempt 的 Launcher 日志在 `09:05:49.800` 命中 `WaitingGameReady -> Ready`，在 `09:05:58.250` 连续命中 `bootstrap_reveal_ready: Flash reveal cleared` 与 `performing reveal (panel swap)`，并在 `09:05:58.269` 命中 `[RevealProbe] setready.player_info_split 0.3ms`。fixture 选择仍为 `p50`，日志亦命中 `[PlayerInfoSplitSurface] fixture-only surface enabled; case=p50; old Flash HUD remains untouched`。这份证据只把 F2/r2 该历史列车自身从 `candidate_built` 推进到 `candidate_executed / source-ahead / NOT_DEPLOYED`，不证明业务 E2E、真实桌面视觉接受、promotion、标准入口或部署；其实现字节后来被 `9118eb…` 正式 release 包含，也不会反向改写该专项列车当时的状态。

**B0 人类接受与 oracle 冻结**：本 closeout 同提交纳入的 [`runtime-candidate-execution-main-space-v2.json`](../tools/player-info-hud/evidence/b0-06/runtime-candidate-execution-main-space-v2.json) 为 3,960 B / SHA-256 `F7A7B03F0333C61B467B50B1F7003D77764A130C7FE745098B9B0DFE09928E50`；[`human-acceptance-main-space-v2.json`](../tools/player-info-hud/evidence/b0-06/human-acceptance-main-space-v2.json) 为 3,509 B / SHA-256 `FB2ED0D6550F51A715E21FB21D110B7EF5B1B04BD46FBC3D5FEA69653C105831`。维护者在上述可见 `p50` exact candidate 上明确回复“可接受，可继续推进”，关闭 actual game composite、旧 Flash HUD 同屏且 untouched、z-order/occlusion、orb 可见性、HP glow 强度/颜色、MP 横向/基线/蓝条垂直对齐、透明 crop、桌面 click-through、时间表现与整体审美，并接受当场观察到的 144 DPI / dpr 1.5 缩放表现。oracle 决策为 `oracle_frozen_for_b0`，basis=`actual_main_runtime_human_acceptance_plus_source_bound_main_rsl_equivalent_capture`；这关闭 B0 human Exit Gate，但不声明 cross-renderer pixel parity、真实 UiData、额外物理显示器切换、业务 E2E、promotion、标准入口或部署。

**首列 v2 退役记录**：受保护 tag `runtime-build-v2/20260729-player-info-nativehud-b0-v2` 永久冻结到 `40853287e7ed04714d68935c0002f8ad6d8aea05`；q3 request `AC3917AB6AB79EB0C8B766F2E3C82D86E7C5CC05E7FF0867FF5A42B8B222EC4A` 的本地 X509 producer/票有效，状态为 `1/2`。该列车在 production policy 的 23 项中通过 22 项，唯一失败为 `candidate-player-info-svg-contract`：隔离 `RendererQualification.csproj` 漏挂已被 `PlayerInfoStrictSvg.cs` 使用的 `PlayerInfoRasterPlan.cs`，触发 CS0246；失败 receipt 为 12,141 B / SHA-256 `3B812E9576164D8472D16020AD0D88824127CB43F7D07B067C0BBAC108293315`。因此它是“因 production policy 门失败而退役”，不是 producer/request failed；未启动 GitHub builder，未形成 quorum/preflight。旧 tag/q3/CAS/票/失败 receipt 只保留审计，绝不移动、删除、supersede 或复用。

**Historical v1 非部署闭环**：PlayerInfo B0-03b～B0-06 的旧 v1 build train 在当时停在 `source-ahead / NOT_DEPLOYED`；较新的 `9118eb…` 正式 runtime 已包含后继实现字节，但不会反向改写该旧列车自身的非部署状态。该 v1 的 source-freeze 与 reproducibility/quorum Gate 曾闭合。该 v1 的 source-freeze F 为 commit `cb38600aae51f5019d09f87c33bd9e67d2b1f511`、tree `c74cc66f445921f5fcda1da04a2de0f013fef8ef`；在 F push、tag 冻结与 builder dispatch 时，远端 `main` 和不可变 tag `runtime-build-v2/20260729-player-info-nativehud-b0-v1` 均精确解析到 F，后继 docs 提交只会推进 `main`，该 tag 必须继续永久指向 F。该 v1 request `839C74FD1DF61ACC1DA580041F6FA71CA13A84DF1F43A55237BF9BEEF8648FB2` 绑定 artifact source `A7190F548851A505F9C6ACCE9F132E1741BAB4B47597473801C79DE32589DBC8`、producer recipe `B97998EA7246D6AB667902BCBBD7994DFA5F658A37CFA427D2EEEABA6924DE28`、toolchain lock `7B83229BE93F8244810CDD23DAFD97875B23857E547DE520035FE23B453CB3CD`、policy `0E52F22FD3A42C5770B5B0C7C58E48662097C01CACA8306595991AD61E4DF105` 与 build identity `7687B56106F0C19EFD4463DCA2B69B3892BD3EE39503A3FD5521ED6DB0257A9F`。本地 X509 signer `EB5D32E04B6EE8697850314E19698DE1A3FACFFCCC6418A12CF7FEDE6033CDA5` / `physical-host-b` 与 GitHub OIDC signer `FA7BFFEB064C9B263B3A8BB6CFB5A655891CD9A9065B02D3BD6862DBD42C34F4` / `github-hosted-windows`（run `30440903705`）分别实际构建并对同一 33-file payload closure `AF2E9E5727E9B6ADE056EBE4CA52BE93AD518116F10FF3307DA4409059CC724B`、Core `A45471CF4CB2286CCE3036AB7B6E72A99FD62B62DDBAF16E0E42234AF17FB652` 达成双 signer / 双 faultDomain 共识。production receipt SHA-256 为 `0E4E81E2D5D433277A726920A5FBBBB19CA10FEA3CBB47A66D3D237CEC0B02D0`；[`runtime-promotion-preflight.v2.json`](../tools/player-info-hud/evidence/b0-06/runtime-promotion-preflight.v2.json) 为 `preflight-passed`，且明确 `runtimeMutationPerformed=false`、`releaseStateMutationPerformed=false`、`promotionPerformed=false`、`deploymentPerformed=false`、`reusableAsPromotionInput=false`。因此这不是 promotion、标准入口验收或部署，报告也不能回灌为未来 promotion 输入。

两个实际 builder 均记录 `.NET SDK=10.0.300`：本地成功 worker 的 `[RuntimeBuildEnv]` 行，以及 GitHub run `30440903705` 的 Provision/Produce 日志均命中该值。该日志事实与 identity/closure 共识一起构成资格证据；不能只用本机预检替代 cloud 的 actual toolchain 记录。

生产项目已固定 `Svg.Skia 5.1.1` / `SkiaSharp 3.119.4`、8 个 canonical SVG、runtime manifest、第三方 notice、strict facade/qualification 与 candidate production contract。B0-05/06 的 historical v1 在实现基线 `bf8dd2c410267855c8ea12f25a594042b3158479` 完成 raster/cache、`split_required`、fixture-only split surface、47/47 机器资格和自动视觉闭包；两份旧 v1 最终 JSON 与同步 canonical docs 由 evidence/docs-only commit `81168ece8cd295d8e15b8f6baed46a0da7f9c549` 承载。旧 v1 F 的 parent `2882456c8777246fba8d2f6942ef1027caafc650` 已纳入 `origin/main@232d25ddf96ba39147f3335162d8a2d033c7822f`；旧 v1 F 相对 parent 的非文档字节只有 PlayerInfo source tag 配置与 release prepare 捕获的 `arena-unit-param-presets.js` 机械派生差量，前三域与 build identity 均未漂移。旧 v1 B0-03b candidate、B0-06 实现/视觉报告与 F 双 builder 证据仍是三个不同作用域；historical v1 的最终 K1 曾在 clean G 上取得 `K1_AUTOMATED_GATE=PASS`、P0/P1=0，但 formal owner 位于屏外，机器资格、Kimi PASS 和图像闭包都不证明可见桌面 DWM composition、游戏 z-order/occlusion、实际鼠标透传、审美或人类验收，当时旧 v1 状态最多为 `awaiting_human_acceptance`。该状态已被 main-space v2 取代。main-space v2 已在 clean F `40853287…` 完成 B0-05 32/32、B0-06 48/48、full 1747+3/1750 与正式 visual-evidence.v2，在 clean G `884fbf43…` 完成最终 Kimi `k3/high` PASS，并由 F2/r2 完成双 builder、23/23 policy 与不可复用 `-VerifyOnly` preflight；随后 exact isolated candidate 启动并由维护者接受，故 B0 为 `b0_accepted`。F2/r2 该专项列车自身仍为 `candidate_executed / source-ahead / NOT_DEPLOYED`；较新的 `9118eb…` 正式 release 包含其实现字节，但没有运行 PlayerInfo-specific standard-entry E2E，不能据总体 runtime 发布状态提升该专项验收结论。

该 historical v1 F 已在 clean detached worktree 完成最终复核：11 个 release prepare 输出全部匹配 F tree，doc governance、`git diff --check`、锁定环境 `bootstrap-runtime-build-env.ps1 -VerifyOnly` 与真实远端 admission audit（`Active`、`mainDirectPush=true`、tag creators=`Crazyfs,Flash-Night`）均通过。Runtime Lane C 为 11/11 个入口 exit 0，十个 scalar 套件合计 566，guardrails 单列 `scripts=3 / unsafeCandidateCases=3`，总耗时 831.271 秒；stdout 为 18,488 B / SHA-256 `9BFBDDD521BE54D70E0158CE595C37C54820EE4C66C73C5681AFC56636A524AC`，stderr 为 3,280 B / SHA-256 `F7FA16D6B9927C3B36D6A61FCBC49C00874EAAC41EBFC662F863793E442479C6`。stderr 是测试 fixture 的 Git EOL/clone 诊断，不改变 11/11 退出结论。此前 staged snapshot 的 scalar 567 / 863.010 秒只是一轮提交前历史预检，不得覆盖 clean F 的最终 566 / 831.271 秒。

另有一条不并入 historical v1 PlayerInfo F 的 Arena 传递派生债务：`tools/derive-arena-meta-teams.js` 同样读取 `data/stages/**`，但当前不在 release prepare 中，其 `--check` 只解析/打印、不比较 tracked 字节。只读内存复算得到 `data/arena/meta_teams.json` tracked 3,470,547 B / `635FB515…98F72`、现源应为 3,367,986 B / `26099187…47D3`；`launcher/web/modules/arena-meta-rosters.js` 为 1,291,607 B / `2F677C5F…9453` 对 1,292,790 B / `32F1D6B9…FD65`；以新 meta 继续派生时，policy fixed file `arena-custom-presets.js` 也会从 1,186,819 B / `26A77128…51A5` 变为 1,189,068 B / `21F4020F…68B6`。这条约 5.8 MiB 漂移包含既存 Arena 变化，不应冒充 232d 的单一 PlayerInfo 邻接修复。该 v1 F 只闭合 prepare 当时枚举的字节，并不声称全仓 Web 派生语义新鲜；未来 Arena 专项须让 meta sync check fail-closed、纳入 prepare/policy、完整刷新三文件并跑 custom-match 与标准 Arena harness。旧 v1 B0 的双 builder/`-VerifyOnly` 只证明该 source-freeze 的 native identity、payload 与当时 policy 字节；由于不 promotion/部署且 PlayerInfo native payload 不消费该链，该债务不改写旧 v1 PlayerInfo B0 Exit。historical v1 的最终 K1 曾接受其为 non-blocking 既存债务并移交 Arena 专项；这不表示链路已修复。

Windows EOL materialization 另留一项非阻断 tooling debt：系统 `core.autocrlf=true`，而 `launcher/scripts/dist/hit-number-bundle.js`、`launcher/web/modules/arena-custom-presets.js`、`launcher/web/modules/arena-unit-catalog.js`、`launcher/web/modules/arena-unit-param-presets.js` 当前只有 `text=auto`。TypeScript materialization 与三个 Arena generator 都写 LF；其中 Arena checks 用 LF-built string 比较 raw checkout bytes，fresh CRLF checkout 可能出现内容未变却短暂 dirty 或误报。historical v1 F 已证明四文件的生成后 LF payload 与 HEAD blob payload 相同，no-filter/clean-filter blob OID 均等于 index/HEAD，刷新 stat 后 write-tree 仍为 F tree。本地正式 worker 在 materialize 前固定 `core.autocrlf=false`；GitHub workflow 未记录同一设置，cloud 则由 exact materialization、identity 与 payload verification 证明最终字节未漂移，不能把本地 Git 配置外推给 cloud。后续应独立为四文件声明 `eol=lf` 并加 fresh-checkout 回归，或让 Arena generator check 先 canonicalize；historical v1 的最终 K1 曾接受其为 non-blocking tooling debt，本轮证据仍不冒充该跨机器问题已根治。

本地 X509 worker 的首次隐藏 PowerShell 尝试也保留为 portability debt：父进程未显式初始化 UTF-8，中文 bundle 路径被错误代码页解码，historical v1 request `839C74FD1DF61ACC1DA580041F6FA71CA13A84DF1F43A55237BF9BEEF8648FB2` 按合同 fail-closed，`failure.json` 记录 `本地开发启动.cmd` 被解码为乱码。没有删除这份失败记录；随后对同一 request 使用显式 `chcp 65001`、`[Console]::OutputEncoding` 与 `$OutputEncoding` UTF-8 wrapper，`builder-local-b` 才成功生成上述 X509 proof。成功证明该受控 wrapper 有效，不证明正式 worker 入口的代码页 portability 已根治；后续须把 UTF-8 初始化固化进正式入口并增加中文路径 fresh-process 回归。historical v1 的最终 K1 曾接受其为 non-blocking portability debt，仍须由独立治理片根治。

历史 `chest-s0-a8a-local-r3/r4` 是 2026-07-18 基于 `a8a760a3cc` 的同机未注册诊断；S0 已从当前源码与 required-assets policy 退役，这些旧 artifactSource/buildIdentity/payloadClosure 只留在 Git 历史和旧 ADR 中，不代表当前工作树、release evidence 或待恢复的发布输入。

2026-07-19 本机构建阻塞已经解除：锁定 bootstrapper FileVersion `17.14.37502.11` 已把 side-by-side Build Tools 安装到 `C:\Program Files (x86)\CF7VS\BT1736`，cl `19.44.35228.0`、link `14.44.35228.0` 与 Windows SDK `rc` 均通过 lock 中的精确版本和 SHA-256 门；`bootstrap-runtime-build-env.ps1 -VerifyOnly` 与 `check-runtime-build-env.ps1` 均 exit `0`。安装后还修复了 Windows PowerShell 5.1 对 `vswhere` 顶层 JSON 数组的函数返回包装：现在逐实例输出，旧 VS 与 BT1736 不会被拼成一个虚假 `installationPath`，同一进程即可重新发现 side-by-side 实例。

2026-07-19 的 `AE1FC1EF… / 172A85C6…` 23-file diagnostic candidate 曾在临时开发目录完成基础启动、map/tasks/NPC 与早期 loot claim/close/unpause/存盘诊断，并暴露 `TransparencyKey` 点击穿透、claim-all 收束与 terminal late-ack 问题；它不含后续修复，也不代表以 `b072f97841ccb30e167c14495241ae64d9054e22` 为 upstream base 的本轮发布。该 candidate 及其后的 FCA19/B2AF/231388 等合并前 loot diagnostic candidate 均已退役。本轮人类 E2E 最初使用的隔离 candidate 位于 `tmp/runtime-candidates/v2/c-2a0cddb077b7-08846e81b3-20260721t100014612z-f32a40a3`，绑定 build identity `2A0CDDB077B760328B3141EFFFEEE3996841FA1CE49AD09E5D7339417F60A107`、payload closure `3B837DCDBC69AA47074E635DACACAE3B80263023E6032AC1FDF209768B1C150C` 与 Core SHA-256 `0F58BF864B8DE9C7FCEA098D7E1EEA1996BDE38D85D87E844B047B53F5247232`；corrected Agent entry、正常 NativeHud、同实例 organizer、普通 suspend/same-anchor 内容不变 reopen/final claim 已在该候选完成，因此它在当时达到 `e2e_verified / NOT_DEPLOYED`。随后同一 build identity / payload closure 经 source commit `c60aab2386aee4516608397373ae4c59148c5f77` 的 immutable request、production receipt、`builder-local-b` + GitHub OIDC quorum 与 strict verifier 完成 promotion；prewarm-held 正式入口 attempt `4eae1360cedd413fa3175db6a8997158` 又取得 fresh title marker、exact attempt receipt，完成真实 loot 两次 claim、terminal close/unpause 与存盘，故唯一 canary 达到 `standard_entry_verified`。此前一次正式入口 attempt 因 reveal watchdog 先于真实 title receipt 而以 `title_frame_not_observed` 失败，保留为换机/冷启动 portability 历史观察，不覆盖后续成功结论。隔离 candidate 的 25-file native payload 不含 `launcher/web`，外部 Web 字节仍由源码哈希与 WebView2 实机日志独立绑定，不能由 native identity/closure 代证。

## 不变量

- 单个进程、机器名或自由填写的 `BuilderId` 都不构成独立 builder；正式 quorum 至少需要两个不同签名身份和两个不同 `faultDomain`。
- producer 只生产二进制 payload，不运行生成器或产品政策审计；政策变化不能污染 payload 身份。
- request JSON 没有自由命令字段，只冻结 Git tree 与政策身份；但 Git bundle 本身含 producer/MSBuild/Cargo 源码，worker 会在 builder 账户下执行该冻结 commit 的构建代码。因此共享 queue 是受控写入信任边界，必须限制写权限；四域复算与 promotion 能阻止错误产物晋级，不能判断源码业务意图，也不能把恶意 queue writer 沙箱成无 RCE 能力。
- candidate、CAS 与 attestation 都不能直接覆盖正式部署；只有 promotion 能事务写入根 bootstrap、`runtime/`、manifest 与 release consensus。
- strict/promotion 状态逐文件验证字节闭包；日常 native 源码可以处于 `source-ahead` 而不立刻 promotion。事后 Audit 在部署字节未变时不读取 payload blob，也不声称验证源码内容语义；只有正式部署闭包变化才必须携带完整新共识。
- 工具链不匹配、证明不足、相同故障域、分叉 payload、脏部署或无效政策 receipt 都 fail-closed；禁止伪造第二 builder、手改 hash/receipt/attestation 或复制单机 candidate 到正式 runtime。

## 开发到正式验收状态机

| 状态 | 最小证据 | 明确不代表 |
|------|----------|------------|
| `compiled` | 编译命令成功，输出仍可位于 `bin/obj` 或其他临时目录 | candidate 已生成、运行时已加载新字节 |
| `candidate_built` | producer 返回唯一 immutable `candidateRoot`，metadata/manifest 的 build identity 与 payload closure 自洽 | 已执行、已部署 |
| `candidate_executed` | 推荐由 `automation/dev.ps1` 按当前 Worktree build identity 精确选择后启动；低层诊断也可用 `automation/start.ps1 -CandidateRoot <absolute candidateRoot>`。两者都须确认 `runtimeMode=isolated_candidate`，且实际 process path、Core SHA-256、build identity、payload closure 全部匹配 | 领域 E2E 已通过、正式入口已更新 |
| `e2e_verified` | 在上述已绑定 candidate 进程中完成受影响领域的真实 Web→Host→AS2→回包 / 写后回读门 | promotion 或正式验收 |
| `promoted` | 唯一 promotion 入口完成事务替换、v2 consensus 与 full-install `--verify-only` | 标准玩家入口已实际加载该身份 |
| `standard_entry_verified` | promotion 后无参数运行 `automation/start.ps1` / 根 bootstrap，确认 `runtimeMode=formal_runtime`、正式 Core 路径/SHA-256/build identity/payload closure 与被提升身份一致，并完成受影响领域 smoke | — |

状态只能按 `compiled → candidate_built → candidate_executed → e2e_verified → promoted → standard_entry_verified` 报告；允许因任务范围停在中间，但不得跨级命名。只有同一身份已达到 `promoted` 且随后达到 `standard_entry_verified`，才可称“已部署 / 正式验收”。日常开发显式走 `automation/dev.ps1`：它按当前 Worktree 身份精确复用/生成隔离 candidate，但始终为 `NOT_DEPLOYED`。`automation/start.ps1` 无参数只消费正式根部署，不得猜测或自动选择 `launcher/bin`、`tmp/runtime-candidates/` 中的“最新”输出；`start.ps1 -CandidateRoot` 仅保留为指定精确候选的低层诊断兼容入口，不再推荐手工直启 Core。

## v2 四域身份

`config/build/runtime-inputs.v2.json` 是输入域清单。四域互斥，发现同一路径同时属于两个域会失败。

| 身份 | 内容 | 变化后的动作 |
|------|------|--------------|
| `artifactSourceHash` | C#、C/C++、Rust 与项目/包输入等真正影响 payload 的源码；PlayerInfo 另以窄树只纳入 `Assets/**/*.svg` + runtime manifest，并固定纳入第三方 notice | 必须重新构建 |
| `producerRecipeHash` | 纯 producer、native build、环境门与确定性参数（含 `sol_parser/.cargo/config.toml` 的 `/Brepro` 链接参数） | 必须重新构建 |
| `toolchainLockHash` | runtime toolchain lock、`global.json`、Rust toolchain | 必须重新构建并重新取得环境资格 |
| `policyHash` | 生成器、审计器、队列/证明/promotion/CI 规则及已派生发布资产 | 新 request + 新政策 receipt；前三域未变时可复用同一 build identity/CAS payload |

`buildIdentityHash = SHA256(artifactSourceHash + producerRecipeHash + toolchainLockHash)`，故意不含 `policyHash`。`releaseTreeOid` 冻结完整 Git tree，`requestId = SHA256(releaseTreeOid + policyHash)`；两者分别回答“发布哪棵树”和“用哪套政策批准”。

native 源码前缀内的非二进制契约文档也必须显式绑定，不能因为扩展名不是 `.cs` 就落在 release descriptor 之外。当前 [`launcher/src/AgentRuntime/Contracts/README.md`](../launcher/src/AgentRuntime/Contracts/README.md) 作为 C# 对照实现的发布约束固定归入 `policyHash`；它会改变 request/receipt，但不进入 `artifactSourceHash`，也不会冒充 DLL 字节变化。这里采用单文件绑定，不把整个 `launcher/src/**/*.md` 扩成构建输入。

`policyHash` 与日常审计触发集合不是同一个集合。`config/build/native-change-gate.v1.json` 联合前三域、payload、全局 native 扩展/入口名和 release 信任链路径，回答“这次 push/PR 是否值得启动 native/runtime 事后审计”；广义内容 policy 不因此变成 native。命中源码边界但未改部署字节时，Audit 成功报告 `source-ahead`，不要求即时 promotion。生成器、审计器和派生发布资产仍留在 `policyHash`，下一次正式 release 再用当时完整 release tree 建 request 与 receipt。

`payloadClosureHash` 对根 `CRAZYFLASHER7MercenaryEmpire.exe` 与 `runtime/**` 的实际 payload 文件有序计算，明确排除 `runtime/cf7-runtime-manifest.tsv`、证明与 release record。这样 manifest/policy 元数据变化不会被误判成二进制失衡；manifest v2 再记录四个构建字段中的前三个、`buildIdentityHash`、`payloadClosureHash`、工具链可读名和逐文件大小/SHA-256。

## producer 与政策闸门

发布链分成三个职责，不能重新合并：

1. `tools/prepare-launcher-release-assets.ps1` 只恢复锁定的 TypeScript/字典依赖并派生受跟踪发布资产。`save_schema.json` 默认保留；只有显式 `-SaveSchemaSource` 才从指定 canonical save 重建，避免私有存档和时间戳偷偷进入发布。
2. `launcher/build-runtime-candidate.ps1` 是纯 payload producer：先执行精确环境门，再在 job 独占的 native/Cargo/MSBuild/temp 目录构建 miniaudio、Rust parser、bootstrap 与 FDD Core，生成不可覆盖的 v2 candidate。candidate 尚无正式 consensus，因此这里只同步、有界等待 bootstrap `--verify-runtime-only` 并检查真实 exit code；失败会保留/输出受限日志，成功必须删除 `logs/`。它不跑 Web/数据产品审计，也不签名。
3. `tools/validate-launcher-release-policy.ps1` 是只读政策门：绑定 `releaseTreeOid` 与四域身份，验证 tracked tree 在审计前后未变化，按需严格验证 candidate，并把每项结果写成 `cf7-runtime-policy-validation.v2` production receipt。它既支持 clean commit 的 `Worktree` 身份，也支持工作树逐字节 materialize 同一 staged tree 的 `Index` 身份；candidate 始终按磁盘 payload 复核。候选优化检查会丢弃调用者注入的 `CF7_DOTNET_EXE`，重新运行锁定工具链门禁并只接受其选出的 host；门禁不产出精确 host 就禁止签发。`candidate-player-info-svg-contract` 同样丢弃调用者 dotnet 注入，使用锁定 SDK 做 locked restore，并对 exact candidate 核对 full canonical manifest、9 项 embedded resource/source bytes、strict 最小 raster、notice exact bytes 与禁用依赖；runtime 根或任意后代若是 reparse/junction，会在递归枚举前 fail-closed。随后实际 renderer-family DLL/native 相对路径集合须 exact=11、每项非空并记录 actual size/hash；这些实际字节再由 candidate payload closure/build identity 绑定。deps libraries 与唯一 renderer-bearing runtime target 也须精确相等；额外顶层 DLL、嵌套 native 文件或 deps library/runtime-target 都 fail-closed。只有 candidate 模式可 `policyEligible=true`，直接 Core 只作诊断。`required-web-runtime-assets` 必须覆盖生产懒加载闭包；地图资源箱必须逐项包含 `modules/loot/loot-runtime.js`、`loot-state.js`、`loot-view.js`、`loot-organizer.js` 与 `loot-panel.js`，任一缺失都 fail-closed 并在 receipt 点名。`panel-cross-layer-contracts` 使用的契约 JSON、validator 与变异测试脚本全部进入 `policyHash`，同时由 native change gate 和 GitHub workflow paths 触发事后审计，避免 sparse materialize 缺少门禁输入或未来只改契约却漏审。子审计 stdout/stderr 只进入人类/CI 日志，不能混入结构化 `checks[]`。receipt 只能写未跟踪路径。

`launcher/build.ps1` 只是人工兼容编排器：prepare → pure producer → policy。它只写隔离 candidate，最多把状态推进到 `candidate_built`，不写根 bootstrap 或正式 `runtime/`；它适合已准备好的本地 tree 做完整候选检查，但不是多机发布协议，也不会替代签名 worker、immutable request 或 quorum。

未提交工作树的可见功能检查统一走 `automation/dev.ps1`（或根 `本地开发启动.cmd`）。它重算当前 Worktree build identity，只复用同身份且闭包唯一的 candidate；无命中时以 `-SkipPrepare -SkipPolicy -BuilderId local-dev` 新建隔离 candidate。`-Status` 只读报告匹配/过期/同身份闭包分叉，`-ReuseOnly` 禁止构建，`-ForceBuild` 强制新建但仍拒绝分叉闭包，`-BuildOnly` 只选择/构建并验证而不启动。忽略的 `tmp/runtime-dev/active.v1.json` 只是 repository-relative 选择索引，不授予信任，每次执行前仍重验字节身份。

`dev.ps1` 最终把精确 candidate 交给 `automation/start.ps1 -CandidateRoot`。该低层入口只接受当前仓库 `tmp/runtime-candidates/v2/` 下的 canonical 非 reparse producer 输出，严格核对完整安装哨兵、candidate metadata、runtime manifest、`buildIdentityHash`、`payloadClosureHash` 与 Core SHA-256，再调用 candidate 自身 bootstrap `--verify-runtime-only`；Core 启动后仍按同一身份反向自检，并显式使用当前完整安装根加载工作树 Web。只有报告/日志中的 `runtimeMode=isolated_candidate`、`processPath`、`coreSha256`、`buildIdentity`、`payloadClosure` 全部与预选 candidate 一致，才能报告 `candidate_executed`。目录 walk-up、候选树外搬运、reparse 别名或 marker/身份漂移一律 fail-closed；该模式始终 `NOT_DEPLOYED`，不产生签名、receipt 或 promotion 权限，也不得把 candidate 手工复制进正式 `runtime/`。

prepare 中的派生器必须字节幂等；例如 save-repair dictionary 仅在结构内容变化时刷新 `generated.at`。重复 prepare 因时间戳制造 diff 属于构建门故障，不能要求维护者提交无语义的时间漂移。

## 精确环境与隔离输出

- 新机器先运行 `tools/bootstrap-runtime-build-env.ps1`；已有环境用 `-VerifyOnly`。若已有实例的精确 MSVC 字节不匹配，bootstrap 不会用旧实例的同名 component ID 冒充锁定 payload，而会走锁定 bootstrapper 的专用 side-by-side 目录；只有工具字节已匹配、仅缺 SDK 时才对该实例执行 `modify`。Windows PowerShell 5.1 下必须逐个输出 `vswhere` 解析到的实例，禁止把顶层 JSON 数组作为单个 `Object[]` 返回后拼接安装路径。正式 producer 每次仍会重跑 `tools/check-runtime-build-env.ps1`。断网复用已有精确匹配 candidate 不需要云端；断网重建则必须预先安装通过锁定门的工具链，并已缓存 NuGet/Cargo 依赖。
- `config/build/runtime-toolchain.lock.json` 锁定 .NET SDK/host、Roslyn/MSBuild、MSVC `cl/link`、Windows SDK `rc`、Rust `rustc/cargo` 及 bootstrapper 入口字节；NuGet 图由 `launcher/packages.lock.json` 固定，其中 PlayerInfo 生产直接引用为 `Svg.Skia 5.1.1`，既有 `SkiaSharp` 保持 `3.119.4`，分发 notice 以 LF canonical byte 同时进入 artifact source 与 candidate payload。Visual Studio 安装器只是尽力补齐组件，不能把会移动的在线 channel 伪装成已固定 payload；最终资格始终以 `cl/link/rc` 的版本与 SHA-256 精确门为准。`.NET` provisioning 脚本也必须使用 `dotnet/install-scripts` 官方仓库的完整 commit URL 并固定 SHA-256，禁止重新使用会因 Authenticode 重签而变字节的 `https://dot.net/v1/dotnet-install.ps1`。
- 当前基线 `cf7-win-x64-2026-07-22` 为 .NET SDK `10.0.300`、Visual Studio Build Tools `17.14.36` / installer `17.14.37502.11` / MSVC toolset `14.44.35207`（cl `19.44.35228.0`、link `14.44.35228.0`）、Windows SDK `10.0.22621.0`、Rust `1.96.0`；精确 SHA 只以 lock JSON 为准。2026-07-22 已核验 `dot.net` 当前脚本的 Microsoft Authenticode 签名有效，去除签名块后与官方 `dotnet/install-scripts@4a37a9f9d1a061fc389d6515100336db4e51710e` 源码逐行相同，因此 provisioning 改用该不可变源码字节。2026-07-19 本机 BT1736 的 bootstrap `-VerifyOnly` 与独立环境门均为 exit `0`。
- producer 清除外部编译/链接/Rust 注入变量；miniaudio 源先规范化为 LF，再用固定 `/pathmap`、`/experimental:deterministic`、`/Brepro`；Rust 每次 clean + locked；managed publish 不带 PDB/SourceLink。
- candidate 默认位于 `tmp/runtime-candidates/v2/c-<identity-prefix>-<builder-hash>-<run-token>/`，完整 build identity / builder label 只存 metadata 与证明，避免目录名把 legacy `MAX_PATH` 撑爆；producer 在编译前后都做 259 字符预算门，已存在目录不覆盖。native / Cargo / MSBuild / `TMP` / `TEMP` 的 job 工作根默认位于环境门规范化后的 machine-local `[IO.Path]::GetTempPath()/cf7-runtime-build-work/job-<token>/`，避免仓库位于 `Program Files (x86)` 等含括号路径时把 CMD 元字符传给 VsDevCmd；`CF7_RUNTIME_WORK_ROOT` 只能覆盖为短的本机绝对目录，卷根、UNC/映射网络盘、reparse point、仓库内/祖先、CMD 元字符或 projected MAX_PATH 超限均 fail-closed。队列 worker 从 request Git bundle 创建隔离 clone；输出按 job 分离，不再共享 `launcher/bin/Release`、Cargo target、MSBuild obj/bin 或临时目录。

## 本地 builder enrollment 与证明

每台本地发布机一次性执行：

```powershell
chcp.com 65001 | Out-Null
$entry = .\tools\register-runtime-builder.ps1 `
  -BuilderId <builder-id> -FaultDomain <physical-fault-domain>
```

脚本在 `Cert:\CurrentUser\My` 创建 3072-bit、不可导出的 RSA 私钥，只把 public certificate/`keyId`/epoch/faultDomain 写到 `tmp/runtime-builder-enrollment/`，**不会自动改 registry**。维护者核对机器与故障域后，才把 entry 合入 `config/build/runtime-builders.v2.json`。私钥不得导出或跨机复制；轮换/撤销通过新 epoch/key 或 `enabled=false` 完成。两台 VM 若共享同一宿主、磁盘或管理员边界，不得宣称两个 faultDomain。

tracked registry 继续保留 `builder-local-a` / `physical-host-a` 与 `builder-local-b` / `physical-host-b` 两张公钥；本次 consensus 实际采用 `builder-local-a` 的 keyId `28DBEAF3761CCF3177FE396596A2557D8A6C9393371CD41DC893FF75A02723B3` / `physical-host-a` 和 GitHub Actions run `30364763726` 的 OIDC builder identity `1BDD1B0F419E0CA384E59986DBC1C9C9195A01CFEAF0838E116A8AD13B9BCEC3` / `github-hosted-windows`。任一单独本地票都仍不构成 quorum，也不授权单机 promotion。

本次 local proof 使用已注册的 `builder-local-a` 3072-bit CurrentUser 不可导出 RSA key：keyId `28DBEAF3761CCF3177FE396596A2557D8A6C9393371CD41DC893FF75A02723B3`、thumbprint `647AFE92BD801518AF25F2A2EE1845E6847C2118`、epoch `1`；未复制或导出私钥。不同故障域的第二票由 GitHub hosted OIDC/Sigstore 提供，双 faultDomain quorum 已满足；dirty staged/unstaged/untracked 工作树仍不能冒充 source commit。

worker 使用该 CurrentUser certificate 对 canonical payload inventory 做 RS256 签名。验证端只信 tracked registry 中启用且 epoch/faultDomain/certificate 全匹配的 key；旧式自由文本 builder ID 不再计入 v2 quorum。

## immutable request、队列与 CAS

需要跨机器时，所有 worker 指向同一具备原子目录 rename 语义且仅受信维护者可写的 `-QueueRoot`（例如 ACL 收紧且共享名前缀足够短的 SMB 共享）；默认 `tmp/runtime-build-queue` 只适合路径预算允许的单仓本地演练。目录包含 `requests/`、`leases/`、`results/` 与 `cas/candidates/`，不进 Git。QueueRoot 本身也受传统文件 259 字符、目录 247 字符预算约束，因为 CAS final path 保留完整 build identity 与 payload closure，失败记录还允许 128 字符 diagnostic 文件名；request 与 worker（包括 DryRun）都必须在建目录、取证书或编译前 fail-fast，复制时再按实际 payload 路径复核。Windows 本机正式队列应给每趟列车分配经预算检查的专用短根（例如本列车使用 `C:\qf8`），不要在 `%LOCALAPPDATA%` 后继续拼 release-id 深目录；worker 没有 RequestId 过滤，含未 `ready` / `superseded` request 的根不得直接混跑下一列车。队列可以共享，但 worker 的隔离 checkout 默认放在本机短路径 `%LOCALAPPDATA%\CF7\runtime-build-checkouts`；worker 会清除外部 `GIT_INDEX_FILE/GIT_DIR/GIT_WORK_TREE/object/config-count` 上下文，并在 materialize 前固定 local Git `core.autocrlf=false`、`core.longpaths=true`，避免 worker 账户的全局换行策略改变 Worktree identity。checkout/candidate 目录只使用 request、worker 的短哈希并预检 MAX_PATH；包含 legacy 深路径的本机 checkout 通过扩展路径形式安全清理。只用 `-CheckoutRoot` 或 `CF7_RUNTIME_CHECKOUT_ROOT` 覆盖，不要把 checkout 放进共享队列、网络盘或层级很深的项目目录。

最终 tree 已提交时使用 `Treeish`；只有纯本地双 builder 才可用 `Index` snapshot。需要 GitHub cloud builder 时必须先提交，并让 request 与 cloud workflow 使用同一 full commit：

```powershell
$request = .\tools\new-runtime-build-request.ps1 `
  -QueueRoot <queue-root> -SourceKind Treeish -Treeish <full-commit>
$requestId = $request.requestId
```

request 内含完整 frozen `releaseTreeOid`、四域 hash、build identity、source/request commit，以及只覆盖四个 v2 identity domain 精确 Git blob 子树的 `source.bundle`、`bundleTreeOid` 与 bundle SHA；大型无关 tracked asset 仍由 `releaseTreeOid` 绑定，但不会塞进 worker bundle。冻结 stage-0 条目时固定 `core.quotepath=false`，路径字段必须按仓库中的 UTF-8 字面值比对，不能让机器级 Git 配置把中文路径转成 C 风格转义文本。worker clone 后复核 `bundleTreeOid`，相同 tree+policy 幂等复用；tree 已过时就创建新 request 并用 `-SupersedeRequestId <old-id>` 标记旧列车，不删除历史。

每台已 enrollment 的本地机器运行：

```powershell
.\tools\invoke-runtime-build-worker.ps1 `
  -QueueRoot <queue-root> -WorkerId <builder-id> `
  -CertificateThumbprint <thumbprint> -Once
# 常驻机器可改用 -Watch；状态查询：
.\tools\get-runtime-build-request-status.ps1 `
  -QueueRoot <queue-root> -RequestId $requestId
```

worker 具有单机 mutex、request lease、heartbeat/TTL 与失败记录；抢到 lease 后从 Git bundle 隔离 clone、复核 frozen tree/identity、调用纯 producer、签名并发布结果。失败时会在删除短 checkout 前把非 reparse、单文件 ≤1 MiB、总计 ≤2 MiB 的 bootstrap diagnostics 写到该 request 的 `_failures` 记录；若 queue I/O 已不可用、失败记录本身无法落盘，worker 只追加固定告警并保留原始构建错误，不能让二次诊断写失败覆盖首因或转成成功。CAS 地址是 `buildIdentityHash/payloadClosureHash`；发布前后都严格复核 candidate，key 对同一 build identity 出现分叉 closure 会作为 equivocation 拒绝。状态退出码固定为 `0=active 全 ready`、`10=pending/empty`、`20=failed/invalid`、`30=只有 superseded`。status 只统计 queue 内本地 X509 result；采用 local + GitHub 时显示 `1/2` 是正常的，最终 combined quorum 由 promotion 把该本地 proof 与外部 verified GitHub proof 一起计算。

推荐把便宜、可离线完成的失败门前移：先取得本地 X509 candidate/proof，再对**该本地 candidate** 跑一次 production policy preflight；这份 preflight receipt 只用于提前暴露 source、CSS、inventory 等政策问题，因为 receipt 绑定具体 `candidateRoot`，不能拿去批准稍后选中的 cloud candidate。preflight 通过后再消耗 GitHub hosted build；cloud proof 到手并选定最终 cloud candidate 后，仍须针对该 cloud candidate 重新签正式 production policy receipt，promotion 只接受后者。这样不削弱双故障域和最终 receipt 约束，同时避免本地即可发现的政策失败拖到云构建之后。

## GitHub hosted 独立故障域

`.github/workflows/runtime-cloud-builder.yml` 提供第二种 producer：只接受人工 `workflow_dispatch`，并在分配 hosted runner 前要求 `github.run_attempt == 1`，且 `github.actor_id` 必须是 `Crazyfs` 的 `91271520` 或 `Flash-Night` 的 `138298913`；失败后重新 dispatch，不能用 rerun 按钮绕过首次运行约束。授权只限制正式发布能力和 Actions 消耗，不构成第二人审批：两名授权发布者中的任一人都可以独立触发。从一次性 source tag dispatch full source commit 后，workflow 在明确的 `windows-2022` / VS 2022 runner family 精确 checkout、配置锁定工具链、运行纯 producer 并验证 v2 candidate；运行时还复核 `RUNNER_ENVIRONMENT`、`RUNNER_OS` 与 `ImageOS=win22`。`windows-2025` 自 2026-06 起已被 GitHub 迁到 VS 2026，不能再承载当前 17.14/v143 锁。checkout 先只取 config/materializer seed，再由 `runtime-inputs.v2.json` 展开四域精确文件集合；禁止为约 9 MiB 的 producer 输入铺开约 4.5 GiB 工作树并挤占 hosted runner 的安装/构建空间。Index 固定文件的存在性必须用 Git object 查询，不能比较受 `core.quotepath` 影响的展示文本；sparse-checkout 的标准输入固定为 UTF-8，因此根目录中文入口在无用户级 Git/终端配置的干净 hosted runner 上也必须可复现 materialize。producer 失败时上传独立 bootstrap/Visual Studio setup diagnostics。独立 `attest` job 仅对 deterministic envelope 调用 `actions/attest`；权限限定为 `id-token: write` / `attestations: write`，使用 GitHub OIDC + Sigstore/SLSA keyless provenance，不保存长期私钥。

`config/build/runtime-github-builder.v2.json` 固定 repository、signer workflow、release source ref、`github-hosted-windows-2022` runner class 与 `github-hosted-windows` faultDomain。日常 release train 使用一次性、单路径段的 `refs/tags/runtime-build-v2/<release-id>`：cloud config、dispatch helper、envelope/attestation verifier 与 admission audit 都拒绝其他命名空间及嵌套 tag，保证 `sourceRef` 必定受 creation + immutability ruleset 保护。tag 必须精确指向 source commit，helper 在 dispatch 前经 GitHub API 解析并 peel annotated tag、拒绝目标不等；workflow 再断言 `GITHUB_REF` 与 `GITHUB_SHA` 分别等于该 tag 和 requested full commit，helper 定位/等待 run 时也要求 `headSha` 相等。由此 GitHub 实际执行的 workflow 字节与被四域政策 hash 绑定的 workflow 字节来自同一 commit，证明同时绑定 tag、full commit 与 tree。远端 creation ruleset 只允许两个授权发布账号创建新 tag，再由无 bypass 的 update/deletion ruleset 冻结已创建 tag；不要删除或移动已经出具证明的 tag。runner 镜像的小版本仍由 GitHub 滚动维护；任何工具字节变化都会被 toolchain lock fail-closed，必须显式轮换基线，不能自动放宽。最短触发、等待、取回与验真命令是：

```powershell
$cloud = .\tools\invoke-runtime-github-build.ps1 -SourceCommitOid <full-commit>
# promotion 使用：-CandidateRoot $cloud.candidateRoot -ExternalAttestationPath $cloud.proofPath

# 进程或网络中断后，复用同一已完成 run；helper 会重验 run / artifact metadata 后续传 .partial：
$cloud = .\tools\invoke-runtime-github-build.ps1 `
  -SourceCommitOid <full-commit> -ResumeRunId <run-id>

# 只用于受控恢复/离线 transport fixture；不会绕过 metadata、双层解压或 Sigstore 验真：
$cloud = .\tools\invoke-runtime-github-build.ps1 `
  -SourceCommitOid <full-commit> -ResumeRunId <run-id> `
  -PreDownloadedArtifactArchive <outer-artifact.zip>
```

helper 只触发固定 workflow，用精确 `run-name`、`headSha` 与 dispatch 前 run ID 集定位本次同 commit run；`-ResumeRunId` 不重新 dispatch，但仍以同一套 identity 门重验指定 run。run 成功后，helper 查询该 run 的官方 Actions artifact metadata，要求唯一精确名称、artifact/run ID、`workflow_run.head_sha`、大小、未过期状态与 `sha256:<64hex>` digest 全部成立；随后用 GitHub CLI token 只向官方 API 换取短期 HTTPS redirect，不记录 token 或 signed URL。外层 ZIP 默认经 HTTPS 流式传输，奇数次直连、偶数次系统代理，失败只保留 `artifact-download/artifact-<id>.zip.partial`；重试发送 `Range`，严格要求 `206`、起止字节、总长和 `Content-Length` 与 metadata 一致，每约 5 MiB 只报告 received/expected 字节数。完整大小和 SHA-256 都通过后才把 partial 改名。

外层 Actions ZIP 必须恰好包含根目录三文件 `runtime-candidate.v2.zip`、`runtime-build-envelope.v2.json`、`runtime-build-envelope.v2.sigstore.json`，并通过 entry count、路径、大小、link/reparse 与 case-collision 门；之后内层 candidate 再走原有 safe extractor，最后调用 `verify-runtime-github-attestation.ps1`。`-PreDownloadedArtifactArchive` 只是 transport 测试/恢复 seam：仍查询所选 run 的 exact metadata、校验外层大小/digest，并走相同的外层/内层解压和 Sigstore verifier，不能成为离线信任旁路。验证器通过 `gh attestation verify` 同时钉住 repository、workflow、source-ref、commit/tree、envelope/candidate inventory 与全部身份字段，并输出可直接交给 promotion 的 normalized proof。下载 artifact 本身不可信；只有该验证通过后才算 GitHub producer。推荐 quorum 是“一个注册本地 X509 builder + GitHub OIDC builder”；两个注册本地 builder 也可，但必须拥有不同 key 和真实不同 faultDomain。

`test-invoke-runtime-github-build.ps1` 的确定性默认套件通过预下载 seam 覆盖 exact metadata、outer/inner 恶意 ZIP、digest/run/head 负例、恢复选 run 与最终 verifier，并静态钉住 Range/长度/文件模式/进度契约；它不伪造 TLS 或把本地 HTTP 冒充 GitHub/Azure 网络行为。修改下载器后，除离线套件外还要用一个未过期的真实 Actions artifact 执行默认 helper，或受控构造 partial 后跑真实 HTTPS `206` 续传，确认最终 outer SHA-256 与 GitHub metadata 相等。

Actions artifact 只是短期交接介质：unsigned candidate/envelope 保留 1 天；失败 bootstrap diagnostics 保留 7 天；signed candidate/envelope/Sigstore bundle 保留 7 天。超过 signed 窗口仍未 promotion 时重新 dispatch，不能把 artifact retention 当长期证据仓。promotion 后 tracked v2 consensus 内嵌的验证材料才是仓库审计记录。

## 政策 receipt 与 promotion

在与 request tree 完全一致、tracked 内容干净的工作树中运行：

```powershell
.\tools\prepare-launcher-release-assets.ps1 -ReleaseTreeOid <full-commit>
# 若生成物变化：审阅、提交，再用新 commit 建 request；不得对旧 request 继续发布。
.\tools\validate-launcher-release-policy.ps1 `
  -ReleaseTreeOid $request.releaseTreeOid `
  -CandidateRoot <verified-candidate> `
  -ReceiptPath tmp\runtime-policy-receipts\release.v2.json
```

promotion 自动读取 queue 中匹配 build identity 的本地签名结果，并可追加已 normalized 的 GitHub proof：

```powershell
.\tools\promote-runtime-bundle.ps1 `
  -QueueRoot <queue-root> -RequestId $requestId `
  -CandidateRoot <verified-candidate> `
  -PolicyReceiptPath tmp\runtime-policy-receipts\release.v2.json `
  -ExternalAttestationPath tmp\runtime-cloud-result\verified-github-proof.v2.json
```

若某个验收门只要求证明“同一冻结源已有两张真实 builder 票且闭包一致”，但明确**不授权部署**，必须复用同一 promotion 验证链的 `-VerifyOnly` 出口，不能另写第二套 quorum 解析器：

```powershell
$reportDir = [IO.Path]::GetFullPath('tmp\runtime-promotion-preflight')
New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
.\tools\promote-runtime-bundle.ps1 `
  -QueueRoot <queue-root> -RequestId $requestId `
  -CandidateRoot <verified-candidate> `
  -PolicyReceiptPath tmp\runtime-policy-receipts\release.v2.json `
  -ExternalAttestationPath tmp\runtime-cloud-result\verified-github-proof.v2.json `
  -VerifyOnly `
  -ReportPath (Join-Path $reportDir 'preflight.v2.json')
```

`ReportPath` 必须是项目根内、父目录已存在、目标尚不存在的绝对 long path；其祖先不得是 reparse point/8.3 alias，并且不得落入 `.git`、`config/build`、queue、candidate、live deployment、任一四域输入树或 payload 输入。脚本声明的唯一仓内输出是以 CreateNew 写一份 canonical UTF-8/LF 的 `cf7-runtime-promotion-preflight.v2`：`status=preflight-passed`、`reportCreated=true`，同时明确 `runtimeMutationPerformed=false`、`releaseStateMutationPerformed=false`、`promotionPerformed=false`、`deploymentPerformed=false`、`reusableAsPromotionInput=false`；这不对 Git/gh 自身在仓外的实现缓存作无范围断言。报告绑定 request 五域、candidate manifest/逐文件 payload closure、policy receipt hash、去重后的 signer/faultDomain/proof 摘要；不含时间戳、本机绝对路径、用户名或机器名。写前和写后都会重验 request/bundle、registry、receipt、proof、worktree/tree、candidate closure/manifest 与 live deployment cleanliness；窗口漂移会删除本轮新报告并失败。该报告只能作验收证据，正式 promotion 必须不带 `-VerifyOnly/-ReportPath` 重新执行全链和事务检查。

promotion 重新验证 request/worktree/receipt/candidate/所有证明，要求至少两个不同 signer identity + faultDomain 且五项共同产物字段（前三域、build identity、payload closure）全等；随后在 `tmp/runtime-promotions/` 组装 next/previous，事务替换正式 runtime、bootstrap 与 `config/build/runtime-release-consensus.json`。v2 consensus 内嵌 policy receipt 与全部签名/Provenance proof；正式安装完成后同步、有界等待 full-install bootstrap `--verify-only` 并检查真实 exit code，两个 verify 模式同时出现会按 CLI 误用拒绝。任何失败或 120 秒超时都进入自动回滚，previous 保留供人工恢复。

## CI 事后 Audit 状态机

`.github/workflows/runtime-bundle-integrity.yml` 是事后审计器，不是 required status context。它监听 `main` push、目标为 `main` 的可选 PR，以及获授权发布者的 `workflow_dispatch`；不再监听 `merge_group`，也不申请 Actions/Checks API 权限。静态 `paths` 只覆盖 native gate 的扩展名、基名、固定路径和前缀，再联合 artifact source、producer recipe、toolchain lock 与 payload roots/trees；PlayerInfo 的 assets/notice 由 artifact-source 路径触发，production validator 与 qualification corpus 是少数显式追加的 policy trigger。纯 docs/data/Flash/XFL/Web-only 变化不启动 Windows runner。修改 native gate 或 runtime input descriptor 时必须同步 workflow paths 与回归，避免“配置认为需要审计、GitHub 却未触发”的裂缝。

该 `paths` 过滤只用于常规成本控制。GitHub.com 对 path filter 的生成 diff 只检查前 3,000 个文件；匹配文件落在窗口之外时 workflow 可能不启动，而超过 1,000 个 commit 或 diff 生成超时会让 workflow 总是启动。故超大提交下既可能漏审，也可能让纯内容提交占用 runner；这不会改变正式 release 的 immutable tag / quorum / receipt / promotion 安全边界。官方行为见 [Git diff comparisons](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#git-diff-comparisons)。

job 名为 `audit-native-runtime`。所有事件都以 job-level `github.run_attempt == 1` 在 runner 分配前拒绝 rerun；`workflow_dispatch` 再限制为 `Crazyfs` / `Flash-Night` 的固定 actor ID，并传入 `-ForceDeploymentVerification`，强制当前 HEAD 走 integrity、source identity 与 strict consensus 全链，作为明确的 release-readiness 检查。push/PR 则用于对真实 diff 做低成本被动审计。它不解析外部成功绿灯锚，也不把某次 Actions success 变成服务端准入权。

`tools/classify-runtime-release-state.ps1 -Mode Audit` 先完成 Git path safety 与 native binding 检查，再计算 `deploymentChanged`：

| 状态 | 条件 | 行为 |
|------|------|------|
| `source-ahead` | native/release 输入发生变化，但根 EXE、`runtime/**`、runtime release consensus 与 builder registry 等部署闭包未变 | exit 0；输出 `state=source-ahead mode=Audit deploymentChanged=false`；不运行 verifier，不下载或重哈希 payload。这是正常开发态，不要求即时 promotion |
| deployment unchanged 但路径/绑定非法 | 危险 Git path、symlink/gitlink/mode/case collision，或新增/修改 native 对象未被 descriptor/payload/canonical release control 绑定 | 失败报警；修复边界，不用 descriptor 漏列绕过审计 |
| deployment changed | 根 bootstrap、`runtime/**`、manifest/consensus、builder registry 等正式部署闭包变化 | 运行逐文件 v2 integrity + strict signed consensus；缺少匹配 promotion、证明不足、闭包分叉或 v2 → v1 时失败 |

push 红灯发生时提交已经进入 `main`；workflow 只能报警，不能回滚。PR 事件可以提供提前反馈，但仓库不要求 PR，也不会把该检查设为 merge gate。正式 release 的可靠边界仍是 immutable source tag、local X509 + GitHub OIDC 双生产者、production receipt 与 promotion，而不是一次普通 CI success。

`config/build/main-branch-admission.v2.json` 描述远端仅有的三条不依赖 Actions 的 ruleset：`main-global-ref-integrity-v1` 无 bypass 地禁止删除与 non-fast-forward；`runtime-source-tag-creation-v1` 只允许两个授权发布账号创建 `runtime-build-v2/*`；`runtime-source-tag-immutability-v1` 无 bypass 地禁止已有 source tag update/deletion。没有身份 gate、Require PR、CODEOWNER 或 required status check。所有 write collaborator 都能 fast-forward 直推，包括 native 路径；GitHub Free 公开仓库没有本方案可用的服务端 path push restriction，完整残余风险见 [contribution-workflow.md](contribution-workflow.md)。

## 验证矩阵与诊断

```powershell
.\tools\test-runtime-dev-entry.ps1
.\tools\test-runtime-entry-guardrails.ps1
.\tools\test-runtime-build-v2.ps1
.\tools\test-runtime-release-policy.ps1
.\tools\test-runtime-build-queue.ps1
.\tools\test-runtime-github-attestation.ps1
.\tools\test-invoke-runtime-github-build.ps1
.\tools\test-main-branch-admission.ps1
.\tools\test-runtime-release-state.ps1
.\tools\test-runtime-build-consensus.ps1   # v1 migration guard
.\tools\test-runtime-release-consensus-v2.ps1

# Supplemental；不计入下述 Runtime Lane C 11/11 与 scalar 566
.\tools\test-resolve-runtime-trusted-base.ps1
.\tools\test-submit-contribution.ps1
.\launcher\tests\run_tests.ps1
```

在 historical v1 detached clean source-freeze F `cb38600aae51f5019d09f87c33bd9e67d2b1f511`、Windows PowerShell 5.1 上，当时最近一次完整 Runtime Lane C 复跑为 **11/11 个入口 exit 0**：其中十个会输出 scalar 计数的套件合计 **566** 项，`test-runtime-entry-guardrails.ps1` 另报告 `scripts=3 / unsafeCandidateCases=3`，总耗时 **831.271 秒**。完整 stdout 为 18,488 B / SHA-256 `9BFBDDD521BE54D70E0158CE595C37C54820EE4C66C73C5681AFC56636A524AC`，stderr 为 3,280 B / SHA-256 `F7FA16D6B9927C3B36D6A61FCBC49C00874EAAC41EBFC662F863793E442479C6`。`test-resolve-runtime-trusted-base.ps1` 是单列 supplemental，当时最近独立历史基线为 **9/9**，未在该次 11 项执行中复跑，也不计入 11 个入口或 566。Lane 自身不含环境 bootstrap，也不能单独替代真实双 builder；该 historical v1 轮另由 F request `839C74FD1DF61ACC1DA580041F6FA71CA13A84DF1F43A55237BF9BEEF8648FB2` 的 X509 + GitHub OIDC proof 与 promotion `-VerifyOnly` preflight 闭合非部署 quorum。该结论仍不产生 promotion、正式 runtime 变更或标准入口验收，也不批准当前 v2。

- candidate：`tools/verify-runtime-bundle-v2.ps1 -DeploymentRoot <candidate>`；只审字节闭包才加 `-IntegrityOnly`。
- 提交态由 classifier 按 manifest header 分流；手工 v2 复核用 `tools/verify-runtime-bundle-v2.ps1 -Staged` + `tools/verify-runtime-consensus.ps1 -Staged`。
- `artifactSourceHash` / `producerRecipeHash` / `toolchainLockHash` 不等：构建身份不同，不比较闭包。
- build identity 相同而 `payloadClosureHash` 不同：真实可复现性失败或 signer equivocation，停止 promotion 并逐文件定位，不任选其一。
- `policyHash` 不同但 build identity/closure 相同：建立新 request、重新跑政策 receipt；允许复用已验证 CAS，不重编 payload。
- native 源码变化且部署闭包未变：Audit 应以 `source-ahead` 成功；不要为了“追平源码”在每次 push 后抢构建锁、改 manifest 或立即 promotion。
- 部署闭包变化但无匹配 v2 consensus：事后 Audit 必须失败；不要靠重跑 Actions、手改 hash 或补文档把红灯洗绿。

升级 SDK/编译器是显式维护事件：人工核对官方来源，更新 lock 与 bootstrapper hash，在不同故障域重建并取得新 quorum，同轮更新本文与 Launcher 文档。不得关闭 hash 校验来迁就某台机器的自动 servicing。
