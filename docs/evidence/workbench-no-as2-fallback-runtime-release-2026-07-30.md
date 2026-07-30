# 双栏工作台 no-AS2-fallback runtime 发布与只读 snapshot 门证据

**Launcher 发布状态**：`compiled → candidate_built → candidate_executed → e2e_verified → promoted → standard_entry_verified`

**人工验收**：维护者已明确回执当前 cut 的 Flash CS6 GUI 人工验收通过。

**自动 E2E 验收范围**：仅覆盖 production `EQUIPMENT_TUNING` AS2 opener → exact workbench instance → 同实例首个权威 snapshot → supported application shutdown。它不代表 Character Build / 双栏工作台完整业务、preview / commit、普通关闭、持久化或全部子功能专项 standard-entry 验收。

**日期**：2026-07-30（UTC+08）

**源码身份**：source commit `f01f4b121a4ceebd7dae051f14bb511c5ae3f1cb`，release tree `3dfe2dcdb25b26f22a2c36b400524a3b6aca0e28`，受保护 lightweight tag `runtime-build-v2/20260730-workbench-no-as2-fallback-v1`；本地 tag 与远端 `refs/tags/runtime-build-v2/20260730-workbench-no-as2-fallback-v1` 均精确解析到该 source commit。

本文冻结旧 AS2 工作台 fallback、Skill 无 token 兼容与主文件 legacy UI 可达边退役后的 runtime v2 双生产者发布。它把“该 native identity 已正式部署”“当前 cut 的 GUI 人工验收已通过”与“该 identity 下自动运行过哪些产品行为”分开记录。

## 1. 发布身份

- request：`3BEBE136773D2C09022F01E5B3C176A788FE3D84E453F6500C6C560F03184C7B`。
- request file：1,122 bytes，SHA-256 `3B710E7B30D29061A7BF23693390541A1540C5B05B2CAD8CBB2B8EF6A8BFB16B`。
- request commit：`fb0130aa1a719092a57cabfab97d2cbeb49c7dfc`；bundle tree：`d6044c00e994b9dd28f143f7815fd511badd5d4c`。
- artifact source：`D80540591DDB71CD1C935A1EE3DEC7657D64F43BA8CC81FB359E181A6CBAEB2F`。
- producer recipe：`B97998EA7246D6AB667902BCBBD7994DFA5F658A37CFA427D2EEEABA6924DE28`。
- toolchain lock：`7B83229BE93F8244810CDD23DAFD97875B23857E547DE520035FE23B453CB3CD`。
- production policy：`0755D2284266537033A4B862D830EE59E0202E7D9659D2C84F280CD8D606A105`。
- build identity：`58F1C3F3B128B22CEA4EDAEF74B402976D13ACB09D4A934240FCCFF3FA7C0465`。
- payload closure：`B529199F6CC00BC0687E8EED6950C6490F239C56E2A2D4AC27E90366CE2C8CAF`。
- manifest：4,088 bytes，SHA-256 `B921A734A5DE490E8DDD5E2E34BA90949D2E7CB444AF484B7AA1E9D955CB920D`。
- Core DLL：1,683,968 bytes，SHA-256 `565C1F9710421E6B6CC5CB6DDA05DE36B8F1B22B3D7A7CA19617F9786C7D8A4B`。
- promoted consensus record：81,115 bytes，SHA-256 `87AF7A3D2F758B31886743F1071E313D683CCD9355028B2B89B9F97915B503FD`。

native build identity / payload closure 只覆盖 manifest 枚举的 33 个 runtime payload files。外置 Web 与 Flash 字节由冻结 source/tree、各自自动门、四个 SWF 哈希、GUI 回执和实际运行日志共同绑定，不能由 native consensus 单独代证。

## 2. Host、Web、Flash 与 GUI 准入门

### Host / Web

- Launcher 最终 fresh 全量为 `1896 pass + 3 explicit opt-in skip / 1899`、0 fail；3 个显式 opt-in 项没有被伪装成执行通过。
- Web strict audit 为 `0 error / 0 warning`，ratchet `66/66`，profile contract 通过，lazy closure `12/12`，focus integration `15/15`，visual atlas `48/48`。
- Crafting 三视口各 `120/120`；Tuning 三视口各 `115/115`，其中 model `61/61`、runtime `25/25`、confirmation `4/4`、interaction `7/7`、source-marker leaf `2/2`。
- Character standalone 三视口各 `218/218`；production workbench `867/867 + 12/12 storage/lifecycle + 18/18 preparation`；inventory workbench modules `30/30`；dressup `222/222`。
- Loot `77/77 + lazy 6/6`；KShop `135/135`；NPC `106/106 + reduced 2/2`；Skills `150/150`。

### Flash CS6 focused 行为门

四轮均取得唯一闭合的 fresh trace / Output Panel / Compiler Errors 副本，Compiler Errors/Warnings `0/0`，32K retry `0`：

| 领域 | runId | fresh 结果 |
|---|---|---|
| Equipment Tuning | `023878476c2b40148a31e8f895635a15` | EquipmentTuning `55/55` + Inventory `144/144` |
| Item Panels | `eb0e77b5337243f3976548fa7f3a8c37` | EquipmentInventory `28/28` + NPC `46/46` + Inventory `144/144` + Crafting `36/36` |
| Skills | `57e94a734d264d66b6860a870fc2db4b` | SkillLoadout `50/50` + SkillPanel `48/48` |
| Character | `d742450109cf4036882282c3ff4e61c8` | 六套合计 `539/539` |

随后按文件归属精确 publish / verify：

| 目标 | bytes | SHA-256 |
|---|---:|---|
| `CRAZYFLASHER7MercenaryEmpire.swf` | 472,599 | `51EAEC3F27396255028AE17C96C5BFE2FE8545694C962FEC18A7EBB1E095E2EF` |
| `flashswf/UI/玩家信息界面.swf` | 104,788 | `F5654B2932FFD62D703F38330D393163266F9EC6E8DFB0B3D7517E258FEB8990` |
| `flashswf/levels/基地场景合集.swf` | 2,975,861 | `B7F12C7AD9ECBA0C23FFDCCE86C460A1D5C2E9CC1D473A03D56706319E1293A4` |
| `scripts/asLoader.swf` | 1,047,668 | `DB5236FF20598186AFF131324BB22B5F15558FD8766FDB4279B37851658AD0F5` |

本轮确实发布了 main，不能沿用上一冻结 release 的“未编 main”描述。`asLoader.swf` 为 9,593 functions，最大函数体 46,025B，低于本项目 60,000B 准入线；publish 本身不冒充行为证据，行为结论仍由上述 focused TestLoader runs 与 GUI 人工验收持有。

### 主文件 legacy UI 不可达门

- source + published SWF 联合审计：XFL includes `472`、included symbols `472`、reachable symbols `230`；errors `0`、warnings `0`。
- reachability gate 自测 `7/7`。
- AS2 single-ownership：main `0`、asLoader `598`、intersection `0`。
- main 相对退役前同尺寸基线 485,167 bytes 减少 12,568 bytes，即 2.59%。

这些结果证明退役 UI 的 Include / RSL / linkage / placement 可达边没有进入当前主文件 source closure 或已发布 SWF，并证明游戏 class 没有被 main 与 asLoader 双重嵌入。它们是结构与字节闭包证据，不是 Flash 合成压力、FPS、内存或深层渲染成本的直接 profiler 结果。

维护者已经对当前 cut 给出 Flash CS6 GUI 人工验收通过回执；本记录不虚构不存在的截图、逐点击脚本或额外视觉量化。

## 3. Exact isolated candidate 只读 E2E

pinned toolchain baseline 为 `cf7-win-x64-2026-07-22`：.NET SDK `10.0.300`、MSVC compiler `19.44.35228.0`、Windows SDK `10.0.22621.0`、Rust `1.96.0`。

本地 X509 candidate、GitHub hosted candidate 与用于运行的 local-dev execution twin 均对同一 33-file build identity、payload closure、manifest 与 Core SHA-256 达成一致。execution twin 为：

`tmp/runtime-candidates/v2/c-58f1c3f3b128-08846e81b3-20260730t112022884z-260326e4`

其 `runtime-build-metadata.v2.json` 为 624 bytes、SHA-256 `DA64C3B30BADF2E0CE6A7CC1D07DABF6C2259D4B8713CBB94A2F7A6AB07AE1E2`。

exact candidate run 从 `2026-07-30T11:21:55.596Z` 至 `2026-07-30T11:22:32.913Z`，取得：

- status：`snapshot_gate_reached`；runtime mode：`isolated_candidate`；runtime PID：`13580`。
- attempt：`f463cb2c793940d6970831b70cc3239e`。
- fresh handoff：报告行 `1685`；真实 title-frame receipt：报告行 `1693`。
- `gameEnteredObserved=true`，Host exact 观察同一 attempt，enter request count 为 `1`。
- workbench instance：`panel.8deee2cd8bfcc54.1`。
- view session：`tuning.ms7fceiw.ar9zkd`。
- snapshot call：`tune.tune.ms7fcein.7gpbst.1.1`，`writeEpoch=0`。
- `productionOpenerOnly=true`、`uiBusinessClicks=false`、`businessWritesAttempted=false`、`businessCommandsSent=[]`、`stopAfterSnapshot=true`。
- snapshot 后重新核验进程路径、Core、build identity 与 payload closure；`agent_control/shutdown` 返回 `success=true / shutdown_requested`。

候选报告：

- JSON：13,328 bytes，SHA-256 `F4E81E9C7D95F90B0CE29303415AEAFA99BB424A1F2376708AF90BA3259F5DE6`。
- Markdown：1,517 bytes，SHA-256 `C55995EACF4D3E8BCDD98D63E7D935BB761FCF4CBDC03B030AFD78B2AB0560F4`。

因此，该 candidate 只在“正式 opener 到同实例首个权威 Tuning snapshot”的窄只读范围内达到 `e2e_verified`。

## 4. v2 双 signer / 双 faultDomain、receipt 与 promotion

- 本地 X509 signer：keyId `EB5D32E04B6EE8697850314E19698DE1A3FACFFCCC6418A12CF7FEDE6033CDA5`，certificate thumbprint `141A0B12F18A1C25C2BF4A32B3C279F81C44D007`，faultDomain `physical-host-b`。
- 本地 attestation canonical payload SHA-256：`369465F4B24D8718AACA3FBD3D7FAD69350AB003A56873CC5D0361915C6452DC`；attestation 为 12,921 bytes，SHA-256 `3D9BAF8818339A3D5CC7D2D3CEA941872DD55AC97003746FFDBD1D3EEDDFC3D6`。
- 本地 result 为 17,434 bytes，SHA-256 `0BBD86EAC61FE5D0D5B4026F797928FCB168561BF9993FD41E041991D4D6B937`。
- GitHub OIDC/Sigstore signer：builder identity `7FFC35F8EDAD03FA477FC9D6BDF86C0FCA8A5CCB591F0CEB56577C0B85BDE9E7`，faultDomain `github-hosted-windows`，runner class `github-hosted-windows-2022`。
- GitHub proof canonical payload SHA-256：`A3192F54BF3CF6E77C8CCE7141CE970272830EFF6C86ABA33DF0FB13BE4273C4`。
- GitHub Actions run `30538330223` / attempt `1` 为 `completed / success`；API `head_sha`、workflow provenance 与 source tag 都绑定 `f01f4b121a4ceebd7dae051f14bb511c5ae3f1cb`。
- cloud artifact ID `8757705992`，23,225,698 bytes，SHA-256 `8BB1FD24188BC2E0B7D432A8D8FF9F2492E62311B28CDFE1412E90C425236BC4`。
- verified GitHub proof：37,087 bytes，SHA-256 `87BEC60CAF2722E529C51945EBEAB32308163F90D883DF82DC9197D2C1F64286`。
- envelope：5,294 bytes，SHA-256 `F56355A79CDE11E3721B7B425F21DAE429DB8527505880EFB8CA167054A6D078`；Sigstore bundle：12,890 bytes，SHA-256 `045035E511B8FE63CF4AFF527D87829188A6247288D8F4CD2AA829C43BE6BF19`。
- cloud candidate archive：23,292,163 bytes，SHA-256 `0BE233E4FB4C1E9A7B533B2DF8F6708E70209B730CACAEEFF6D4702D7C6C0EE0`。

本地 production preflight 为 `26/26` passed，15,235 bytes，SHA-256 `0764B58E4175CFE42205E8F79EA4B03AFD846DB120D74FB0EDD635725FAE49D6`；它只作前置诊断，没有复用为 promotion 输入。

最终 cloud production receipt 为 `26/26` passed，15,357 bytes，SHA-256 `C9F225466717594F6675512841A194A94A29938A905B13ED28D093713322DDA8`；receipt 的 tracked state before/after 相同，candidate payload closure 在验证前后保持不变。promoted consensus 的 `policyReceiptSha256` 精确绑定该值。

不可复用的 `-VerifyOnly` preflight 为 15,128 bytes，SHA-256 `430F59D66EE1CD6EF323F27E11027824BBFECCD5AFFE7B5CADB1A0948758A702`；状态为 `preflight-passed`，且：

```text
runtimeMutationPerformed=false
releaseStateMutationPerformed=false
promotionPerformed=false
deploymentPerformed=false
reusableAsPromotionInput=false
```

正式 promotion 于 `2026-07-30T11:42:21.7606896Z` 完成，写入根 bootstrap、`runtime/**`、manifest 与 `config/build/runtime-release-consensus.json`。上一正式闭包保存在可恢复目录：

`tmp/runtime-promotions/20260730T114147629Z-f07a84a95dd444cc8411706d74209a3d/previous`

promotion 后重新执行只读核验，RuntimeBundleV2 为 33 files / coherent，GitHub attestation replay 精确命中 source 与 payload，RuntimeConsensus 为 schema v2 / 2 signers / 2 faultDomains；三者均 exit `0`。

## 5. Formal standard-entry：保留失败关闭，再取得全新成功

### 第一次正式入口：watchdog 先到，fail-closed

无参数标准入口的第一次 run 从 `2026-07-30T11:44:17.462Z` 至 `2026-07-30T11:44:52.547Z`，runtime mode 为 `formal_runtime`，runtime PID `18824`，attempt 为 `bfb6bfe515f14af58f9b4096c8c539dd`。

该轮取得 fresh handoff，但在进入 `agent_enter` 前：

```text
19:44:51.961 [LaunchFlow] Flash reveal watchdog fired after 10000ms, force-revealing
19:44:51.969 [XmlSocket:JSON] ... "task":"bootstrap_reveal_ready"
19:44:51.970 [LaunchFlow] bootstrap_reveal_ready: not waiting, ignored
```

真实 `bootstrap_reveal_ready` 只比 watchdog 晚约 8 ms。runner 没有把 watchdog 冒充 title-frame receipt，而是以 `title_frame_not_observed` 停止；该轮没有调用 enter，没有打开 workbench，也没有取得 snapshot。失败后仍通过 supported `agent_control/shutdown` 清理。

原始失败报告保留为：

- JSON：8,103 bytes，SHA-256 `2B6BA657C446E1816139766BF0CBB5D513BC5045E0E32D81ADED52B55E0765C6`。
- Markdown：1,165 bytes，SHA-256 `0B33CD7D7C3C89E824461A242A769778064325FD1310823359890FF092887FF1`。
- 退出后 Launcher log snapshot：336,763 bytes，SHA-256 `BDD79A83C2E599AF2BA67A71B9BD8FA27BDBF9AB59C36D792DFC01D4BFA3B48E`。

该轮是有效的 fail-closed 诊断，不计入 `standard_entry_verified`，也没有被第二轮成功覆盖或改写。

### 第二次正式入口：全新 attempt 成功

全新第二轮从无参数 `automation/start.ps1` 启动，运行区间为 `2026-07-30T11:46:54.319Z` 至 `2026-07-30T11:47:29.931Z`：

```text
Runtime Mode    : formal_runtime
Core SHA256     : 565C1F9710421E6B6CC5CB6DDA05DE36B8F1B22B3D7A7CA19617F9786C7D8A4B
Build Identity  : 58F1C3F3B128B22CEA4EDAEF74B402976D13ACB09D4A934240FCCFF3FA7C0465
Payload Closure : B529199F6CC00BC0687E8EED6950C6490F239C56E2A2D4AC27E90366CE2C8CAF
Deployment      : FORMAL_RUNTIME
```

- runtime PID：`20872`。
- attempt：`8baf52bbcceb452da32da641e58d2922`。
- fresh handoff：报告行 `2154`；真实 title-frame receipt：报告行 `2162`。
- `gameEnteredObserved=true`，exact attempt runtime ack 成立，enter request count 为 `1`。
- workbench instance：`panel.8deee305515213f.1`。
- view session：`tuning.ms7g8hnx.ypc4j3`。
- snapshot call：`tune.tune.ms7g8hns.hwg463.1.1`，`writeEpoch=0`。
- `productionOpenerOnly=true`、`uiBusinessClicks=false`、`businessWritesAttempted=false`、`businessCommandsSent=[]`、`stopAfterSnapshot=true`。
- snapshot 后重新核验正式进程路径与完整身份，并由 `agent_control/shutdown` 取得 `success=true / shutdown_requested`。

正式成功报告：

- JSON：13,203 bytes，SHA-256 `E41875E20FE29430C6135E03E3ED9557341E70F40F4E7785F78D9E5ED6A7C710`。
- Markdown：1,432 bytes，SHA-256 `8D765C197497908EDADF0F32E593CE83A2CC801456ED71C3BA475FB861740217`。

因此，同一 promoted identity 在本证据定义的窄只读范围内达到 `standard_entry_verified`。

## 6. 明确未覆盖

本轮自动 candidate / formal smoke 没有：

- 点击调制业务控件，或发送 preview / commit / mutation；两轮成功报告均为 `writeEpoch=0`、`businessWritesAttempted=false`。
- 验证业务持久化、存档写入、Launcher 重启回读或游戏 `SAFEEXIT`。专用 shadow save 的 seed 属于 harness 准备，不是业务写验收；`agent_control/shutdown` 只证明 supported application shutdown。
- 验证普通面板 `×`、Esc、backdrop close 或返回上层。
- 在该 promoted identity 下专项运行 Character Build、Materials / Intelligence 往返、Skills 管理、Crafting、KShop、NPC、Loot、dressup、PlayerInfo `pi_*` 或完整双栏工作台写旅程。
- 重跑 B0-05 / B0-06 formal、B0-06 visual capture，或把它们的 explicit opt-in skip 写成通过。
- 做 Flash 深层显示列表、合成层、GPU、DWM、FPS、内存、长会话或多 DPI 的量化 profiler；本轮只能陈述 legacy UI 不可达、main 字节减少与 GUI 人工验收通过。

GUI 人工回执不扩张自动 E2E 范围；自动门通过也不替代未运行的业务旅程。旧 release 的候选、写后回读或视觉证据不与本 identity 拼接。本文结论只由本轮冻结 source/tree、Host/Web/CS6 门、四个 SWF 字节、双生产者 consensus、exact candidate、保留的标准入口失败关闭和随后全新成功共同推出。
