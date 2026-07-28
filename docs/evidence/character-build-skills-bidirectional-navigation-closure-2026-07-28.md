# Character Build ↔ Skills 双向导航正式关闭证据

**状态**：`compiled → candidate_built → candidate_executed → e2e_verified → promoted → standard_entry_verified`

**日期**：2026-07-28（UTC+08）

**源码身份**：commit `c4faf14460238c7ea3e85983f31dee8be1b79afa`，tree `88e9e76fbb0534c69f363a36ab838e6ecfa2d958`，immutable tag `runtime-build-v2/20260728-character-build-skills-bidirectional-v1`（annotated tag object `9ae01139fb9c7d1e847f2aaf42282c60c7a5b0d9`，peel 后精确回到源码 commit）。

**正式部署记录**：promotion commit `45b9748baa68786a52557239d5bd7c52869970f7`。

本文只冻结本轮最终双向导航、运行时发布与正式入口证据。较早的单向 Character Build → Skills candidate 仍由 [character-build-skills-navigation-closure-2026-07-28.md](character-build-skills-navigation-closure-2026-07-28.md) 维护；B4 装备/药剂写入与重启读回仍由 [character-build-b4-2026-07-27.md](character-build-b4-2026-07-27.md) 维护，历史身份不得拼接到本文。

## 1. 最终能力边界

- 原生 HUD“装备”通过 exact workbench preflight 打开新的 Character Build session。
- Character Build 的“技能配置”先完成 finalize、visual retire、AS2 recoverDetach 与 Host settled，再以一次性 nonce 打开 `source=nativehud / view=manage` 的 Skills。
- 该 Skills instance 只获得 `canReturnCharacterBuild` 展示能力，不携带 `trainerSession` 或 `canReturnTrainer`，不能学习或升级技能。
- 显式“← 返回构筑”关闭 exact Skills instance，等待 visual 与 Skill coordinator 双 settled，再经新的 workbench nonce 创建 fresh Character Build session。
- `×`、物理 Esc 与 backdrop 始终是普通关闭到游戏，不消费返回能力；返回成功后只恢复稳定“技能配置”焦点，不复活旧 DOM、槽位或候选 session。

## 2. Exact isolated candidate E2E

### 2.1 身份

- detached root：`E:\cf7-e2e\character-skills-c4faf14460\resources`。
- candidate root：`E:\cf7-e2e\character-skills-c4faf14460\resources\tmp\runtime-candidates\v2\c-4e5eee4ab5be-08846e81b3-20260728t053352636z-899adab6`。
- 实际候选 Core PID：`18236`；退出后进程已消失。
- Core DLL SHA-256：`16DF387268E8052A0B66B2F49DD8645DB38C37EB23430D4AC0CB46527A3B9BA0`。
- manifest SHA-256：`72932CB04FFF5239B2862A291D85C672F55497CC629DB30B05C79B82FC32E33F`。
- build identity：`4E5EEE4AB5BE0CC8D084254C54F23AC4D6269C11CFED987409EA6BBE171CE191`。
- payload closure：`7460D8D4FC4416EDBDDFE7577403CBA7233ECC347BDF2D605BC5D2252AF39507`。
- 验收期间进程路径、Core bytes、manifest、identity 与 closure 始终未变化；candidate 只在隔离根执行。

### 2.2 人类可见流程

使用 ChatGPT App 的 Windows Computer Use 对实际游戏窗口执行键盘/原生 HUD 操作：

1. 从游戏内原生 HUD 点击“装备”，进入“角色构筑”；
2. 通过“技能配置”进入“我的技能”，确认存在“← 返回构筑”，不存在教师学习/升级界面；
3. 显式返回后出现 fresh Character Build，15 个装备/药剂槽的可访问名称与数量逐项一致，`equipmentUnchanged=true`；
4. 再次进入 Skills 后按物理 Esc，直接回游戏；
5. 再次从原生 HUD 打开并进入 Skills，激活右上 `×`，直接回游戏。

截图未提交二进制；原始件保存在 `E:\cf7-e2e\character-skills-c4faf14460\evidence-gui`，逐文件哈希见 §5。

### 2.3 候选日志正链与负链

候选日志：`E:\cf7-e2e\character-skills-c4faf14460\resources\logs\launcher.log`，124,399 bytes，SHA-256 `17D0E55961A2869DD2631C3351864B902C7474A1B270A789A10FE0CA471AEF7C`。

首轮双向正链：

```text
15:03:29.601 event=character_build_open_requested source=nativehud_equipment
15:03:29.705 [PanelHost] opened: workbench
15:03:29.832 event=character_build_panel_bound ... instance=.1
15:03:29.856 event=character_build_snapshot_accepted ... sessionGeneration=1
15:07:30.529 event=character_build_skills_navigation_armed ... instance=.1
15:07:30.602 [PanelHost] closed: workbench
15:07:30.627 event=skill_panel_open_requested source=character_build
15:07:30.648 event=skill_panel_open_accepted view=manage source=character_build
15:07:30.729 [PanelHost] opened: skills
15:10:19.423 event=skills_character_build_navigation_armed ... instance=.2
15:10:19.510 [PanelHost] closed: skills
15:10:19.510 event=character_build_open_requested source=skills_return
15:10:19.607 [PanelHost] opened: workbench
15:10:19.701 event=character_build_panel_bound ... instance=.3
15:10:19.725 event=character_build_snapshot_accepted ... sessionGeneration=2
```

普通关闭负链：

- 物理 Esc 在 `15:12:25.804` 只产生 `[PanelHost] closed: skills`，其后没有 `source=skills_return`；
- `×` 在 `15:26:18.817` 只产生 `[PanelHost] closed: skills`，其后没有 `source=skills_return`；
- 下一次 Character Build 打开明确来自 `source=nativehud_equipment`，不是隐式返回。

## 3. v2 双故障域发布

- request：`BBCC17C7E46AC852BA0F1D12AA9434188C7775BEA8F593C13B13710783183548`。
- GitHub hosted run：`30333045634`，success，API tag、workflow `GITHUB_SHA` 与 run `headSha` 均绑定 `c4faf14460238c7ea3e85983f31dee8be1b79afa`。
- GitHub OIDC/Sigstore builder identity：`3B32F64D834C2A9961A7C4EA57AD998E0A463360F703904601C1A33823F675BC`，faultDomain `github-hosted-windows`。
- 本地 X509 keyId：`28DBEAF3761CCF3177FE396596A2557D8A6C9393371CD41DC893FF75A02723B3`，faultDomain `physical-host-a`；私钥保持 CurrentUser 不可导出。
- verified cloud proof：`C:\cf7q2\cloud\run-30333045634\verified-github-proof.v2.json`，SHA-256 `6FB4B9DE5587384B23B255E628DA001410472AD2BC483110BFA3F153DCFAF66F`。
- production policy receipt：`C:\cf7q2\policy\release-cloud.v2.json`，22/22 passed，SHA-256 `C5E683CDD3958B9CF7503DBD08C309CC6EA6E6EFF92F3203B78682AF9C1BE9C3`。
- promotion 时间：`2026-07-28T07:32:13.5124981Z`。
- promotion 只改写 `config/build/runtime-release-consensus.json`、`runtime/CRAZYFLASHER7MercenaryEmpire.Core.dll` 与 `runtime/cf7-runtime-manifest.tsv`；旧正式闭包留在可恢复目录 `tmp/runtime-promotions/20260728T073149955Z-a9150cd065bb4e8c8cd36d5081b498b9/previous`。
- promotion 后 Worktree 与 staged 两种模式均通过 `RuntimeBundleV2`、GitHub attestation replay 与 `RuntimeConsensus`；staged 结论为 `schema=v2 / signers=2 / faultDomains=2 / payload=7460…9507`。

## 4. Formal standard entry

无参数执行根 `automation/start.ps1`，输出并实际启动：

```text
Runtime Mode    : formal_runtime
Deployment Root : main repo
Core SHA256     : 16DF387268E8052A0B66B2F49DD8645DB38C37EB23430D4AC0CB46527A3B9BA0
Build Identity  : 4E5EEE4AB5BE0CC8D084254C54F23AC4D6269C11CFED987409EA6BBE171CE191
Payload Closure : 7460D8D4FC4416EDBDDFE7577403CBA7233ECC347BDF2D605BC5D2252AF39507
Deployment      : FORMAL_RUNTIME
```

- Guardian PID `14780`，HTTP `1192`；最终由 `agent_control/shutdown` 正常退出。
- save slot `crazyflasher7_saves2`，attempt `d508d2dac3964c6fa92ba98675bfdc15`；`gameEnteredObserved=true`、runtime ack 同 attempt、`readyForRuntimeAutomation=true`。
- 真实 GUI 再次完成“原生装备 → Character Build → Skills manage → 返回构筑 → Esc 回游戏”；Skills 有“← 返回构筑”且无 teacher UI。
- 正式日志 `logs/launcher.log` 在关闭后为 242,675 bytes，SHA-256 `3E6B04CB912200270424E79526F13B8C7F80B14B0CD84B5FE2761DDF7782780F`。
- fresh marker 依次为 `15:39:59 nativehud_equipment` → `15:42:34 character_build_skills_navigation_armed` → `skill_panel_open_accepted view=manage` → `15:49:05 skills_character_build_navigation_armed` → `source=skills_return` → 新 `.3` workbench snapshot；`15:52:40` 的 Character Esc 只关闭 workbench 并回游戏。

因此该同一身份已达到 `standard_entry_verified`；这是 promotion 后无参数正式入口、运行身份、Host/AS2 日志与实际 GUI 的联合结论，不由 consensus 单独推出。

## 5. GUI 原始件哈希

| 文件 | Bytes | SHA-256 |
|---|---:|---|
| `01-character-build-from-native-hud.png` | 67,618 | `720203FBA1C1364894558C463CB574ED3ED6CFC7E13E31DE6E4EB30D3D3E2E1F` |
| `02-skills-manage-from-character-build.png` | 81,755 | `456FB866920F4F400650D9CD69B94C9103C058ACC2A513896E80385D6450DB39` |
| `03-character-build-returned-from-skills.png` | 67,881 | `CB9CE2F87D152910289E3C01BA10068B63925FF44C188335ECB9C516F9EA6ECC` |
| `04-skills-physical-esc-returns-game.png` | 86,397 | `D6D75B4AE28F976597AC14B2B26A3D6A7694F4248BB7ED09D49CD8E1EB8D5A8E` |
| `05-skills-close-button-returns-game.png` | 86,327 | `68EBE8EBAC1FB9E8ACC27B0D399BED75E7A893AD46D8DF0FA89448EAB071C425` |
| `06-formal-standard-entry-character-build.png` | 67,312 | `514480696434947DBE7D8E7A5261B407F52E9F4EF4E683BF0C21232FD7F28F51` |
| `07-formal-standard-entry-skills-manage.png` | 81,452 | `7207AB834D048E2A208E298D7AE62F1E460E0DF72DE652F94865B20B705EC623` |
| `08-formal-standard-entry-returned-character-build.png` | 79,206 | `805F220762948E8B557F9250AFA3B73F77398BFF82B6A143547136947229A631` |
| `09-formal-standard-entry-character-build-esc-return-game.png` | 98,064 | `4BDB1DD75310093DC543C5BFCAF4E62524DFCA7CFA9966E6A1777DF66C87D0B2` |

## 6. 自动门与 K3 边界

- 本轮 fresh 自动门的最终计数仍以 [角色构筑专题 §9](../角色构筑-Web双栏工作台-工程落地规划-2026-07-26.md#9-验证矩阵与当前证据) 为单一索引；Flash、Host、Web、Panel runtime 与 strict UI audit 均已通过。
- Kimi Code 固定使用 `kimi-code/k3 --thinking --plan`，session `bc2345d4-42eb-47aa-9b03-5ea627bd5e3c`；未降低思考强度、切换模型或允许写工作树。
- 最终异构裁决为 `GO：0 Blocker / 0 High / 0 Medium`，覆盖过度设计、维护复杂度、交互与视觉边界；K3 的裁决不代替本文 candidate/formal GUI 证据。
- 三项 Low（source tag、nested-crafting 早期 fail-close 双判定、facade 字符串 ratchet）均不增加新状态机；其中 source tag 已按本次 immutable 发布关闭，后两项由现有行为门约束，保留为非阻断维护观察。

## 7. 最终结论

源码 `c4faf14460` 的角色构筑 ↔ 玩家自身技能双向导航已在同一 immutable identity 下完成候选执行、真实 GUI、普通关闭负链、双 signer / 双 faultDomain promotion 与无参数正式入口复验。教师能力未被扩大，装备/药剂状态未被导航改变，当前严格状态为 `standard_entry_verified`。
