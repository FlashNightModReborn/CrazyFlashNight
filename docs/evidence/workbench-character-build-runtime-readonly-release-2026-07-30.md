# 双栏工作台与角色构筑 runtime 发布及只读 snapshot 门证据

**Launcher 发布状态**：`compiled → candidate_built → candidate_executed → e2e_verified → promoted → standard_entry_verified`

**该状态的验收范围**：仅覆盖 production `EQUIPMENT_TUNING` AS2 opener → exact workbench instance → 同实例首个权威 snapshot → supported application shutdown；不代表角色构筑或双栏工作台完整业务验收。

**日期**：2026-07-30（UTC+08）

**源码身份**：source commit `9118eb5097ab073d26a9806138f9fabf28e3ca79`，release tree `f99f685b341a4fdc1ea6773ebdb989ec405a4a7a`，lightweight immutable tag `runtime-build-v2/20260730-workbench-character-build-v1`。

本文冻结本轮 Launcher runtime v2 双生产者发布、exact candidate 与无参数正式入口的同范围只读纵切。它把“该身份已经正式部署”与“哪些产品行为实际在该身份下运行过”分开记录。

## 1. 发布身份

- request：`F5992FE5AFA3B74024CACEFCA1BACD311C1A3EE7C50CF3D08145A3E49BC211BC`。
- artifact source：`4C64B933141FE3C3E52C232749A2E6307F665C198AF203689CE38E1B601D738A`。
- producer recipe：`B97998EA7246D6AB667902BCBBD7994DFA5F658A37CFA427D2EEEABA6924DE28`。
- toolchain lock：`7B83229BE93F8244810CDD23DAFD97875B23857E547DE520035FE23B453CB3CD`。
- production policy：`307749EF01596E8DA67E6E980F411EA2C0A9E1A35359168F0AC03523F2D37621`。
- build identity：`EB60E241929B5F88110C4EAE218DFD98569AE657F2B765179DBF644F0EEE0255`。
- payload closure：`889FC7A800CFE738EAA99992CD6C5689AA65ECFEF3F406A617B3A1A344F4520B`。
- manifest SHA-256：`DB0E22B8F2B57BAF3FB5F225AEA08278F1747F7790206FEF931EEB8E6F218BC2`。
- Core DLL SHA-256：`9DE1C5249EA5827AB8CE7C19CAE0CAE8724809BE2BC7DE4F600AD2F7AB78F336`。

native identity / closure 只覆盖 manifest 枚举的 33 个 runtime payload files。外置 Web 与 Flash 字节另由冻结 source/tree、production policy 和实际运行日志绑定，不能由 consensus 单独代证。

## 2. 自动门与 candidate 构建

- 冻结树的最终 fresh 自动汇总为 Launcher `1902 pass + 3 explicit opt-in skip / 1905`、0 fail；Crafting `119/119`、Intelligence `30/30`、Tuning 三视口各 `115/115`、Character standalone 三视口各 `218/218`、workbench `867/867 + 12/12 + 18/18`、inventory modules `31/31`、dressup `222/222`、preparation leaf `10/10`、KShop `135/135`、item-grid matrix `20/20`、ratchet `66/66`，strict audit `0 error / 0 warning`。精确范围与 Flash 证据以 [测试指南](../../agentsDoc/testing-guide.md) 为准。
- pinned 环境为 `cf7-win-x64-2026-07-22`：.NET SDK `10.0.300`、MSVC `19.44.35228.0`、Windows SDK `10.0.22621.0`、Rust `1.96.0`。
- 本地 X509 candidate、GitHub hosted candidate 与独立 execution twin 均通过 33-file RuntimeBundleV2，并对同一 build identity、payload closure 和 Core SHA-256 达成一致。
- production receipt 绑定最终 cloud candidate，`26/26` passed；receipt 为 14,973 bytes，SHA-256 `2CBB619F6FD5E17F04434E96637E522DA5D0FA411230527201DC9E020E609ADB`。本地 `26/26` preflight receipt 只作前置诊断，没有复用为 promotion 输入。

同一 request 的首次隐藏本地 worker 未显式初始化 UTF-8，中文 bundle path 被错误代码页解码并 fail-closed；保留失败记录后，以显式 UTF-8 wrapper 重跑同一请求才成功。这是既有 portability debt 的复现，不表示 worker 已根治跨代码页问题。

## 3. Exact isolated candidate 只读 E2E

execution twin 位于末级目录为 `resources` 的独立 detached worktree，启动 exact candidate 后取得：

- runtime mode：`isolated_candidate`。
- Guardian PID：`35544`。
- attempt：`7b4006c491384ffe9bfc1e7c24269e8e`。
- `gameEnteredObserved=true`，且只发送一次 enter。
- workbench instance：`panel.8deedee5e1a83ca.1`。
- view session：`tuning.ms6zd8so.2pau6o`。
- snapshot call：`tune.tune.ms6zd8sn.812ixy.1.1`，`writeEpoch=0`。
- `productionOpenerOnly=true`、`uiBusinessClicks=false`、`businessWritesAttempted=false`、`businessCommandsSent=[]`、`stopAfterSnapshot=true`。
- snapshot 后再次核验进程路径、Core SHA-256、build identity 与 payload closure，随后由 `agent_control/shutdown` 请求 supported application shutdown；PID 与端口文件均消失。

成功尝试之前保留两次 fail-closed 诊断：一次因隔离树尚无 seed shadow 而拒绝运行；一次因 reveal watchdog 早于真实 title-frame receipt 而以 `title_frame_not_observed` 停止。成功尝试重新取得 fresh handoff、真实 title receipt、exact slot/attempt、单次 enter 与同实例 snapshot，没有复用失败轮次。

候选报告：

- JSON：13,163 bytes，SHA-256 `DE7A178A28BFCD080D72C376B142ADF25A506D87EF91B61D1CD55D3FBCF1DADE`。
- Markdown：1,448 bytes，SHA-256 `E1C690F0861A6E501A880F4858711DDCD0337AD1FCDC1BF4E47B18912307DBE2`。

因此，本发布把 accepted candidate E2E scope 明确定义为“正式 opener 到同实例首个权威 snapshot 的只读纵切”，并在该窄范围内达到 `e2e_verified`。

## 4. v2 双 signer / 双 faultDomain 与 promotion

- 本地 X509 signer：keyId `28DBEAF3761CCF3177FE396596A2557D8A6C9393371CD41DC893FF75A02723B3`，certificate thumbprint `647AFE92BD801518AF25F2A2EE1845E6847C2118`，faultDomain `physical-host-a`；私钥保持 CurrentUser 不可导出。
- GitHub OIDC/Sigstore signer：builder identity `AC20F09BE9C7138A9C3B5BECCC39944C434FF52C49A3EDF3268647E54599D72D`，faultDomain `github-hosted-windows`，runner class `github-hosted-windows-2022`。
- GitHub Actions run `30511825565` / attempt 1 为 `success`，run `headSha`、workflow `GITHUB_SHA` 与 API-resolved source tag 均绑定 source commit `9118eb5097ab073d26a9806138f9fabf28e3ca79`。
- cloud artifact ID `8747447101`，23,226,199 bytes，SHA-256 `33857F2D5DBC8C56097EB84035A214C1C6CB37444A13170E77452F8A4AB76436`。
- GitHub proof 为 36,963 bytes，SHA-256 `54AE60CFAA1D4C83588A80E0AC68DE132AFBC4A14B30521937F9D70C53D8179B`；envelope SHA-256 `67FFA0A8EC149243746C887E4DD22111B5F59A8325146B6FFAA6582ECBD8ADC4`，Sigstore bundle SHA-256 `0E032305115155EEA4A45A96407AA5807B198A11C530CF18E053C6DC76EB2710`。

最初等待 cloud run 时 GitHub API 曾返回瞬时 EOF；恢复动作只对已经成功的 run `30511825565` 使用 `-ResumeRunId`，没有重新 dispatch 或 rerun。

不可复用的 `-VerifyOnly` preflight 为 15,128 bytes，SHA-256 `55E7F434176D0DB0162CDC9CE4A6E16B432DAA76BA48A746517288E7E307D852`；状态为 `preflight-passed`，且 `runtimeMutationPerformed=false`、`releaseStateMutationPerformed=false`、`promotionPerformed=false`、`deploymentPerformed=false`、`reusableAsPromotionInput=false`。

正式 promotion 于 `2026-07-30T04:13:56.5873119Z` 完成，写入根 bootstrap、`runtime/**`、manifest 与 `config/build/runtime-release-consensus.json`。上一正式闭包保存在可恢复目录：

`tmp/runtime-promotions/20260730T041329340Z-1b428fcd64c6411eaf2ab263ba0a0ce3/previous`

promotion 后 RuntimeBundleV2、GitHub attestation replay、双 signer / 双 faultDomain RuntimeConsensus 均为 exit `0`。

## 5. Formal standard-entry 同范围 smoke

无参数标准入口首次冷启动仍因 watchdog 早于真实 title receipt 而以 `title_frame_not_observed` fail-closed；该轮未 enter、未打开业务面板，也不计入通过证据。

全新第二轮从无参数 `automation/start.ps1` 启动：

```text
Runtime Mode    : formal_runtime
Core SHA256     : 9DE1C5249EA5827AB8CE7C19CAE0CAE8724809BE2BC7DE4F600AD2F7AB78F336
Build Identity  : EB60E241929B5F88110C4EAE218DFD98569AE657F2B765179DBF644F0EEE0255
Payload Closure : 889FC7A800CFE738EAA99992CD6C5689AA65ECFEF3F406A617B3A1A344F4520B
Deployment      : FORMAL_RUNTIME
```

- Guardian PID：`19468`。
- attempt：`9539e5f3f6d44b7daf487d8985465972`。
- `gameEnteredObserved=true`，exact attempt runtime ack 成立，enter request count 为 `1`。
- workbench instance：`panel.8deedf185ae47f9.1`。
- view session：`tuning.ms706a88.88aiex`。
- snapshot call：`tune.tune.ms706a86.k5q7pz.1.1`，`writeEpoch=0`。
- snapshot 后再次核验正式进程路径与完整身份，并完成 supported application shutdown；端口文件消失，Guardian 与 Flash 进程均无残留。

正式报告：

- JSON：13,086 bytes，SHA-256 `B8C4FA7DD7E0855B3D9B50D84D599749FD67A44639692F7AFD35D472DA092290`。
- Markdown：1,418 bytes，SHA-256 `423155DD91A073A46303F427BFD3D5AAA1A3670290139F0875DACC8BD62502DB`。
- 退出后 Launcher 日志：912,818 bytes，SHA-256 `EEEBC492A0855B78787A29BC0D5630F1556D6C1BC30BF1A12B68A7C9577689F5`。

因此，同一 promoted identity 在上述窄范围内达到 `standard_entry_verified`。

## 6. 明确未覆盖

本轮没有：

- 点击调制业务控件或发送 preview / commit，也没有验证交换、强化、进阶、插件装卸、批量卸下、未知写 reconcile 或乐观同步。
- 验证存档、重启回读或游戏 `SAFEEXIT`。`agent_control/shutdown` 只证明 supported application shutdown 与进程退出。
- 验证普通面板 `×`、Esc、backdrop close 或返回上层。
- 对 Character Build、Materials / Intelligence 返回、B7 全旅程或 PlayerInfo `pi_*` 做专项实机运行。
- 做人工视觉、截图、DPI、pinch、长会话、内存或性能验收。

`9118eb…` 已满足旧文档约定的正式 Host / `asLoader.swf` 配对部署退役触发条件，但 exact source 仍保留 Skill opener 缺 `openRequestId` 时面向旧 Host 的单向兼容分支。新 Host 对无 nonce 回包继续 fail-closed，因此这不是本次 release 的权限扩张；它是后续独立 source/release 必须删除并保留回归的清理债务，本次证据不把它冒写成已移除。

PlayerInfo F2/r2 自身仍是历史 non-deployment train；其实现字节被较新的 `9118eb…` release 包含并进入 formal runtime，但本轮没有启用 PlayerInfo fixture 或观察真实 `pi_*`。B0 仍为 `b0_accepted` / `oracle_frozen_for_b0`，不能从总体 runtime 的 `standard_entry_verified` 外推 PlayerInfo 专项验收。

旧 release 的候选、写后回读或人工视觉证据不与本身份拼接。本文结论只由本轮冻结 source/tree、production policy、双生产者 consensus、exact candidate 与正式入口同范围运行共同推出。
