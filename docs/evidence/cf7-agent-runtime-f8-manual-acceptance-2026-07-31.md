# CF7 Agent Runtime F8 可见游戏/面板人工验收证据

**当前严格状态**：`compiled → candidate_built → candidate_executed → e2e_verified → promoted → standard_entry_verified`

**候选阶段历史状态**：§1–§8 的 exact isolated candidate 在当时为 `e2e_verified / NOT_DEPLOYED`；后续正式发布不反向改写该历史时点。

**日期**：2026-07-31（UTC+08）

**验收目标**：先证明不借助 Codex Computer Use、浏览器自动化或 legacy HTTP，operator 仅通过项目自有 CF7 Agent Runtime MCP，在 exact isolated candidate 中完成可见纵切；再以同一 build identity / payload closure 取得 v2 双故障域共识、promotion，并从无 candidate id 的正式标准入口重复帮助面板与可信 shutdown 旅程。

§1–§8 保留 F8 implementation source/candidate 的原始限定证据；§9 独立记录后续正式 v2 发布与标准入口复验。本文不代表 Wings/Hair 完整产品验收、13/13 GUI capability、多显示器矩阵、Flash pixels/input 或维护者目视签收。

## 1. 冻结身份

| 字段 | exact value |
|---|---|
| source commit | `53caabc90941826ddacf626f536b0f473adbf049` |
| source Git tree | `5ac63ec05fbbc9b89aa14f7f0b5ab25698f9742d` |
| candidate | `c-0f4c92f237ab-98ebd18146-20260731t022411220z-20da007a` |
| build identity | `0F4C92F237ABD7785C957F3CD135ABF2EFB1EB5D9AB5671B869F39D00970675C` |
| payload closure | `54FBCCBA7C90ACF407B09E38FFB874C13DE3CDFB80CF62D0F8D4E239A42962F0` |
| Core SHA-256 | `86DF1F5DC611037DB3A85FD9BA0D43490394F232D25A4F62B59AA4F2B4B6E4FD` |
| production policy receipt | `tmp/manual-agent-acceptance/runtime-policy-f8-final-53ca-20260731T102324.json`；SHA-256 `3CC222798C895D91B619E0170316F2A0B59A76180AC0951D9AC715A211DF3C97` |

candidate 只由该冻结 tree 构建；运行前后均复核实际进程路径、Core、build identity 与 payload closure。截至该 isolated candidate 验收时，正式 runtime/根 bootstrap 未被修改，因此该阶段结论保持 `NOT_DEPLOYED`；后续发布见 §9。

## 2. Source 与 candidate 自动门

- Launcher fresh 全树：**2724 passed + 3 explicit opt-in skipped / 2727 total，0 failed**。3 个 opt-in skip 没有被写成通过。
- TrustedRunner focused：**57/57**。
- 仓库 SDK resolver：**7/7**，精确解析 `.NET SDK 10.0.300`。
- Node CF7 Agent client：**37/37**。
- production policy：**26/26**，exact receipt `tmp/manual-agent-acceptance/runtime-policy-f8-final-53ca-20260731T102324.json`，SHA-256 `3CC222798C895D91B619E0170316F2A0B59A76180AC0951D9AC715A211DF3C97`。
- JSON contract artifacts 均可解析；tracked diff whitespace check 通过。

fresh 全树之前曾暴露并修复测试 harness 的 cancellation registration 竞态和过紧的后台 reconcile 等待；最终 2724/2727 与 TrustedRunner 57/57 是修复后的 clean run，不以 isolated 重跑掩盖失败。

这些自动门证明 F8 source/candidate 的合同与组合，不单独证明可见 E2E；下文 real run 才承担 `candidate_executed → e2e_verified` 的限定结论。

## 3. Production capability truth

F8 不把 static applicability 当作 advertisement。一次 method 真正可用，必须同时满足 authenticated session capability 与当前 exact `SurfaceDescriptor` modes。验收逐项核对：

| surface kind | production observation mode | production input mode | 本轮判定 |
|---|---|---|---|
| Launcher | `window_graphics_capture` | `[]` | WGC frame 可读；structured panel action 不借 input mode |
| WebOverlay | `window_graphics_capture` | `send_input_guarded`、`domain_transaction` | structured opener 后 exact panel target 的 WGC frame 可读 |
| NativeHud | `window_graphics_capture` | `send_input_guarded` | WGC frame 可读并在内存核对 SHA-256；本轮不从 mode 推导或调用 `input.*` |
| Flash | `[]` | `[]` | metadata-only；pixel capture 在 frame source 前固定 `unsupported_for_surface` |

`FlashTopLevel` 等内部模型名不改变实际嵌入式 `WS_CHILD` 归属。`FlashSnapshotKeyframe` 只是 reserved/diagnostic enum，不是 production frame source。若以后需要 Flash pixels/input，必须另立 off-screen top-level + compositor ADR，不能恢复 BitBlt fallback。

production activator map 为空；Welcome/session capability 不含 `window.activate`。v1 registry/schema 中保留该 method 只维持冻结合同，不表示本 candidate advertise 或可调用它。

所有 production panel producer 统一使用至少 144-bit CSPRNG opaque instance ID。本轮打开的 exact help panel instance 为 `panel_LBIeoY-dgrxurL6gELRDvCbH`，匹配 `^panel_[A-Za-z0-9_-]{24}$`，且与动作前实例不同；fallback、Loot 或其他 producer 不得回退到时间戳/递增 counter。

## 4. Pure Agent Runtime MCP 可见纵切

验收驱动通过 candidate 的项目自有 MCP `stdio` adapter 建立 authenticated pipe。最终 `acceptancePassed=true`、`acceptanceFailures=[]`，共完成 **57** 次 MCP `tools/call`，并依次完成：

1. MCP `initialize → notifications/initialized → tools/list`，随后通过 `session.status` 取得 opaque lifecycle ref。
2. 签发 metadata observation grant，枚举 exact session surfaces；核对 production capability 不含 `window.activate`。
3. 对 Flash 使用 metadata grant 调用 `window.list/window.state`，确认目标可见且 `observationModes=[] / inputModes=[]`；另用 pixels grant 请求 capture，精确得到 `unsupported_for_surface`，没有 frame、fallback 或重试。
4. 对 Launcher 与 NativeHud 分别取得 WGC observation，经 bounded `content.read` 在内存拼接并复核 contract `contentHash`。Launcher SHA-256 为 `B1E849FF2472C276DA5C41B424C4395ED49C0C3A3FAD59A7A3AAE2B421E5CB22`；NativeHud SHA-256 为 `3E23CE959D6AC2F1A94832A8293048F314AB4E66365871CDB20C803BE49E0494`。
5. 绑定新鲜 Launcher WGC pixels observation/frame，取得 purpose=`structured_action`、capability=`panel.open`、actionLimit=1 的专用 one-shot lease；以 allow-list key 打开帮助面板。terminal receipt 为 `outcome=input_dispatched / evidenceKind=broker_dispatch / reconcileKind=none`，exact instance 为 `panel_LBIeoY-dgrxurL6gELRDvCbH`。operator 没有提交 native keyboard/mouse packet；结构化 route 的源码与自动门也固定不进入 native input guard。
6. 重新观察并绑定新产生的 exact WebOverlay/help panel instance，读取 WGC 内容并只在内存核对 SHA-256 `C86D95D8577C648515247B020A8791CA19147467EFCA670597384A11A8735439`；可见窗口保持 **12011 ms**，供维护者直接观察。
7. operator 撤销 grants 并结束 MCP stdin；trusted wrapper 随后经 Agent Runtime 取得专用 shutdown lease、发送一次 `session.shutdown`，再严格核验 terminal receipt、同一 exact owned process 正常退出及清理结果。

operator transcript 只允许项目 Agent Runtime/MCP lifecycle 与下列 CF7 tools：`session.status`、`observation.grant.issue`、`observation.grant.revoke`、`window.list`、`window.state`、`observation.capture`、`content.read`、`lease.acquire`、`panel.open`。wrapper 的单次 `session.shutdown` 由独立 trusted completion evidence 绑定。审计结果必须同时满足：

- Codex Computer Use 调用数：**0**；
- Browser/Chrome control 调用数：**0**；
- legacy HTTP 高权限 route 调用数：**0**；
- `input.*` 调用数：**0**；
- `window.activate` 调用数：**0**；
- operator 提交的 native keyboard/mouse packet 数：**0**；本轮未宣称安装系统级 packet hook。

像素 handle 为短生命周期、bounded read；字节只在验收 client 内存中计算 hash。本轮没有 persistence/export grant，没有写 PNG、data URL、视频或其他像素 artifact；final report 的 `screenshotPath` 必须为 `null`。可见性来自真实 candidate 窗口保持，不以截屏文件冒充人工观察。

## 5. Retry 与 shutdown 边界

驱动的 bounded retry 只允许两个 canonical retryable transient：pixel capture 的 `capture_unavailable`，以及 structured lease acquisition 的 `input_not_quiescent`；response 还必须同时给出 `retryable=true / reconcileKind=none`。两条路径的 attempt 数、总时间与 backoff 都有硬上限。未知 reason、transport ambiguity、terminal receipt、mutation、`unknown`、stale generation 与 `unsupported_for_surface` 均不重试。

`session.shutdown` action **绝不重试**。本轮只发送一次 shutdown；trusted wrapper 若丢失 response，必须把该 isolated run 判为失败并进入 bounded exact-child recovery，禁止发第二次，也不得伪造 completion evidence。只有仍保有可对账 lifecycle 的普通 developer connection 才可按通用合同另行使用 `action.get`，不能把该规则误套成 trusted wrapper 重连。验收只在严格 receipt、同一 exact process exit code 0、无 forced recovery 且 residue compare clean 时计为成功。

## 6. 原始证据与清理

| artifact | path / identity |
|---|---|
| final report | `tmp/manual-agent-acceptance/agent-runtime-help-20260731T022753Z.json`；SHA-256 `486C3B2B82996791D3371098E823265C265C865883AFA0B5922A42B8D0AACF19` |
| MCP/CF7 transcript | `tmp/manual-agent-acceptance/agent-runtime-help-20260731T022753Z.jsonl`；SHA-256 `B3BA1B721C4EF89723152A45FCDE1CA05EFAB901211F79E0CD929AFA93CE59E6` |
| trusted completion evidence | `tmp/manual-agent-acceptance/agent-runtime-help-20260731T022753Z-completion.json`；SHA-256 `CA6BA5ECBDD7DE362D6A375BEF54FB50E3BE917DF7154B3CC1C5640B7D58F67C` |
| before/after residue + source-save compare | `tmp/manual-agent-acceptance/residue-compare-f8-final-53ca-attempt1.json`；SHA-256 `2C76FF28503AE5344FBBE4EE394C600A0A7330251EE9BED1F90A6005E8196072` |

退出后不存在本次 exact candidate Guardian/Core/Flash/热键 helper 进程、`launcher_ports.json`、live bootstrap request、credential 或 rendezvous 残留；candidate 运行前后的 source tree、detached source save 与正式 deployment snapshot 逐项相同。`tmp/manual-agent-acceptance/residue-compare-f8-final-53ca-attempt1.json` 记录 `pathsUnchanged=true`、`bootstrapFilesUnchanged=true`、`credentialFilesUnchanged=true`、`noResidualDelta=true`。

## 7. 历史阶段不得拼接

- F7 C1 `dd84230a1d262c6478591cae2d11051b7a8aa7b1` / tree `7362881e96d8ed0f9c20ccae580426c522f14946` 的 candidate 取得 production policy 26/26，但真实运行在无前台环境以 `trusted_runner_credential_timeout` fail closed，只达到 `candidate_built / NOT_DEPLOYED`。
- `7f1c21d9db` 的历史 candidate `c-ce978031dd4e-885840ecfd-20260731t004137289z-b4dd0870`（identity `CE978031DD4E8A1F2E4C646013D3D5E0EA6635005AF277766AC977E62FB39536` / closure `0CFB1667C6E82F2B0D0CB1B2B1048426A3E374D8FA21B492801C8A4E351A2D99`）证明过早期 visible structured panel/WebOverlay 路径；它早于 F8 Flash/activation advertise 收口，只作历史诊断。

两者的成功或失败均不补 F8 字段，也不与本轮 transcript、进程或 hash 拼接。

## 8. 明确未覆盖

- 当前机器只有一块显示器；没有完成窗口跨两块物理显示器、混合 DPI 的迁移矩阵。
- 没有宣称 CF7 GUI v1 production 13/13；static applicability 不是 capability advertisement。
- 没有验证 Flash pixels/input；F8 对它的正确结果就是 metadata-only + `unsupported_for_surface`。
- 没有执行 `input.*`、`window.activate`、Hair transaction、Wings 玩家授权、legacy HTTP、UAC/security desktop 或 foreign modal 旅程。
- §1–§8 的 isolated candidate 当时没有取得 immutable release request、local X509 + GitHub Hosted OIDC/Sigstore 双 signer/双 faultDomain、v2 promotion 或同身份 standard-entry 复核；这些后续阶段由 §9 独立闭合。

因此 §1–§8 的最高结论仍只是：F8 exact isolated candidate 已在单显示器交互环境通过纯 CF7 Agent Runtime MCP 完成上述可见纵切，达到限定 `e2e_verified / NOT_DEPLOYED`。同一 identity / closure 的后续正式列车已由 §9 推进到 `standard_entry_verified`，但不会反向把候选阶段写成当时已部署。

## 9. 后续正式 v2 发布与标准入口复验

### 9.1 不可变请求与双故障域共识

| 字段 | exact value |
|---|---|
| release source commit | `6f3d50a52413c747b05b74be88d6ee46650f4597` |
| release Git tree | `253e57f6d20a90fef6addfa744d0487d88f00dfb` |
| immutable tag | `runtime-build-v2/20260731-agent-runtime-wings-f8-v1` |
| request ID | `A9B33601805709DBB5EAE6DAF312C2B7B0B502096FDD3BDCEA9CBE26D8B1299C` |
| request commit / bundle tree | `b3730af5ae92b064248248cc8dce0d2a0284fb99` / `1a22fc0a68fd1408e6bdc9805e77b48d06e6bd80` |
| source bundle SHA-256 | `C8BE97FA8686DA829A9515D3136BC848A205732B350DBCAE958504CCCD4385D4` |
| artifact / recipe / toolchain / policy | `98000EBA762749C28583579271362FBED9E2E5FFE202FFF5FB0B0D8028456893` / `B97998EA7246D6AB667902BCBBD7994DFA5F658A37CFA427D2EEEABA6924DE28` / `7B83229BE93F8244810CDD23DAFD97875B23857E547DE520035FE23B453CB3CD` / `33A18135EEB9094F305C63ADA887600230C18AD49FA0AE151E469A4F68DDC09F` |
| build identity / payload closure | `0F4C92F237ABD7785C957F3CD135ABF2EFB1EB5D9AB5671B869F39D00970675C` / `54FBCCBA7C90ACF407B09E38FFB874C13DE3CDFB80CF62D0F8D4E239A42962F0` |

本地票由 CurrentUser 不可导出 X509 keyId `28DBEAF3761CCF3177FE396596A2557D8A6C9393371CD41DC893FF75A02723B3`、thumbprint `647AFE92BD801518AF25F2A2EE1845E6847C2118` 在 `physical-host-a` 生成；队列 `C:\qf8` 关闭继承，只允许当前 Administrator、Administrators 与 SYSTEM FullControl。GitHub Hosted 票来自 run [`30602046108`](https://github.com/FlashNightModReborn/CrazyFlashNight/actions/runs/30602046108)、artifact `8782307580`，OIDC builder identity `2E05B5577CC8D2895DC56FC8778A05D09C440302832A05DD4AE551589C9AE918` / `github-hosted-windows`；artifact archive 为 23,719,566 bytes / SHA-256 `44FCAC67D301504DC9570773598CD5150D92DFA169E9E1A1CC91A430B86280D8`。两票的 source ref/commit/tree、identity、closure 与 33-file payload 全部一致。

正式 production policy 26/26 receipt 为 `tmp/runtime-policy-receipts/f8-cloud-final-run30602046108.json`，SHA-256 `DA46C6E99CB02A268099ACB709C80B60E8B2D821134E1D32C9C84CB288EEC38C`。本地 preflight receipt `f8-local-preflight-a9b336-20260731.json` 和 `tmp/runtime-promotion-preflight/f8-a9b336-run30602046108.json` 只作支持性证据；后者虽通过 signer=2 / faultDomain=2 / fileCount=33，仍明确 `promotionPerformed=false`、`deploymentPerformed=false`、`reusableAsPromotionInput=false`，不能单独冒充 deployment。

### 9.2 Promotion 字节

唯一 promotion 入口于 `2026-07-31T03:56:21.4933374Z` 原子写入正式 bootstrap/runtime/manifest/consensus。严格 v2 bundle 与 consensus verifier 均通过，当前关键摘要为：

| artifact | SHA-256 / size |
|---|---|
| root bootstrap | `55EABB5C3280FDFEE8302843D969C6B6354808F1AF4DC24DB5E2397AA80499D8` / 310,784 bytes |
| Core EXE | `86DF1F5DC611037DB3A85FD9BA0D43490394F232D25A4F62B59AA4F2B4B6E4FD` / 261,120 bytes |
| Core DLL | `0CEA0C64C037090ADAB4E9C38294075E58F1D298615DD447677D0D6725A9271E` / 3,150,336 bytes |
| manifest | `A0A7CA0C992149DC2F9A4D5DDC60C2CAAC2EDC8BBC7907B0CF8EE4C7D5E694E4` |
| consensus（promotion 后 Windows worktree bytes；非 Git clean-filter blob hash） | `8E6292039E0BD01C7F1C0ADD1AE28DF840D676D4A8FB959337BBDAB07D285F26` |

根 bootstrap、Core EXE 与多数 payload 字节相对上一 formal bundle 相同；本次 tracked deployment 差量精确为 Core DLL、manifest 与 consensus。上一 bundle 的可恢复副本保留在 `tmp/runtime-promotions/20260731T035551270Z-a1ae4de95c394e98a2d6ca0d8da8f742/previous`，不得把它误称新 payload 或删除。

### 9.3 正式标准入口 pure-MCP 旅程

正式 harness 不传 candidate id 或 `-CandidateRoot`，经 `tools/cf7-agent/unattended.js --adapter mcp --slot cf7_agent_equipment_tuning` 调用 formal `automation/start.ps1`；wrapper 仅传 `-UnattendedSlot` / `-UnattendedAdapter`，不选择隔离 candidate。报告绑定 promotion 后 consensus、Core EXE、Core DLL、source/tag/request/tree/identity/closure，并在旅程前后要求三项 tracked promotion 状态完全一致。

| artifact | path / SHA-256 |
|---|---|
| formal report | `tmp/manual-agent-acceptance/formal-f8/agent-runtime-help-20260731T040942Z.json` / `4D7206C3183685806F6D9B82B8C100D99D44A2098C1A536441542A9CBD826A86` |
| MCP/CF7 transcript | 同目录 `agent-runtime-help-20260731T040942Z.jsonl` / `2C9B2B09AD41F89B62BE9060FB000796C552777D9A20A85CB05E7A4700230FBB` |
| trusted completion | 同目录 `agent-runtime-help-20260731T040942Z-completion.json` / `D47164F886098975936FB2620418401C3BA319475D9DAB01C21B247177FF0F27` |
| residue before / after | `formal-residue-before-run.json` / `8495459C794F352FFB646EB39836051007A67DE819CD38B4E0FB26468D8F3E11`；`formal-residue-after-run.json` / `AEDDF16C41968F51922E48703D2F9CF2092F52CF3481B0E043FABFCABD8EE5B9` |
| residue comparison | `formal-residue-comparison.json` / `0FF8B6E09C35749A1A3C8D3505DA321D1AE76703D121C4D4F633452B45F1B9D9` |

结果为 `acceptancePassed=true`、`runtimeMode=formal_runtime`、wrapper exit 0、forced cleanup=false。operator 共执行 57 次 MCP call，只使用 `content.read`、`lease.acquire`、`observation.capture`、grant issue/revoke、`panel.open`、`session.status`、`window.list`、`window.state`；没有调用 Codex Computer Use、browser/Chrome、legacy privileged HTTP、`input.*` 或 `window.activate`。帮助面板 exact instance `panel_-clB6-04T-5-jrLaQGT5gA0F` 保持可见 12009 ms；Launcher、NativeHud、WebOverlay WGC 内存哈希分别为 `6DB81B6DA51671278E58D9040704AB9B2C4C8C0AD3BD466B557EAD087E35357E`、`3E23CE959D6AC2F1A94832A8293048F314AB4E66365871CDB20C803BE49E0494`、`EB4130ACDF352336C6C3EF20B5FB9277D6537982E4AF14990F61AF5DCECB8A31`。Flash 仍只暴露 metadata，pixel capture 精确拒绝为 `unsupported_for_surface`；没有 persistence/export、截图或其他像素文件。

trusted wrapper 经同一 Agent Runtime 协议只发送一次 shutdown，completion 绑定正式进程路径、identity/closure 与成功 receipt。source/formal save slot SHA-256 均保持 `5B4066C6F481A7BB574BA318813D35D7F16A0EF88244D49BA02BC9CA77CE46C3`。residue comparison 为 `newRelevantProcesses=[]`、paths/bootstrap/credentials unchanged、`noResidualDelta=true`；baseline 原本已有历史 headless Flash PID `35372`，因此正确表述是“无新增残留差量”，不是“系统中没有任何 Flash 进程”。

由此，同一 identity / closure 已完整经过 `promoted → standard_entry_verified`。该结论只覆盖单显示器 Help-panel 只读纵切；报告明确 `visibleDwellRequiresHumanObservation=true`，机器证据证明窗口保持但不能代签维护者亲眼接受。物理双屏/混合 DPI、“13/13”、Flash pixels/input、Wings 玩家授权、Hair transaction、security modal 与完整产品纵切仍未覆盖。
