# Character Build → Skills 收口证据

**状态**：`compiled → candidate_built → candidate_executed → e2e_verified / NOT_DEPLOYED`

**日期**：2026-07-28（UTC+08）

**源码基线**：commit `14a2529e8b88607b03f6dcf428a0a1892e5d8f67`，tree `6b2cae1586e35c2b2fa82ad501f2ab72263badde`。

本文是受 Git 跟踪的持久审计索引。Flash runner 的滚动日志仍位于 `scripts/`，不会被本文冒充成不可变原始件；这里保存 exact runId、结果、时间、大小与 SHA-256，使后续覆盖滚动文件时仍能核对本轮身份。§6 另记录隔离 candidate 的实际进程、专用存档、Host/AS2 日志水位、CDP DOM 与截图哈希，因此本轮可称 `e2e_verified`；candidate 始终为 `NOT_DEPLOYED`，本文不授予 `promoted`、正式部署或 `standard_entry_verified` 结论。

## 1. 能力边界

- Character Build 只在本地 `finalize/canClose` 取得终态后发送 exact `reason=navigate_skills` close。
- Host 对 exact Character instance 先武装 one-shot，再完成 visual retire、AS2 recoverDetach、持久化屏障与 coordinator-settled。
- Host 随后创建独立 typed Skill capability，生成一次性 `openRequestId`；只接受 nonce、`source=nativehud`、`view=manage` 与 panel baseline 全匹配的回包。
- 最终 Skills initData 不含 `trainerSession` 或 `canReturnTrainer=true`，只允许管理玩家自身已学技能、快捷栏与被动；学习、升级仍只能由世界 NPC 的 `world_skill_trainer/trainer` capability 进入。
- 滚动部署只保留旧 Host → 新 AS2 的单向兼容：参数对象缺少 `openRequestId` 时，AS2 发出不带 nonce 的 `nativehud/manage`。新 Host 永远发送 nonce，并继续拒绝无 nonce 回包；显式畸形 token 零发送，教师入口不得携 token。Host 与 SWF 配对部署后应删除该临时分支。

## 2. Fresh TestLoader 行为证据

命令：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\run-skill-migration-tests.ps1 -TimeoutSeconds 240
```

- Focused runId：`fcc94c4c51ee468e82e129144ab8ff20`
- `SkillLoadoutServiceTest`：`50/50`
- `SkillPanelServiceTest`：`48/48`
- Compiler Errors/Warnings：`0/0`
- 32K retry：`0`
- TestLoader 函数体：314 functions，最大 3,380B，全部 `< 60,000B`
- 新增兼容断言明确通过：
  - exact Host `openRequestId` 原样回显；
  - 旧 Host 缺 token 时只发送无 nonce 的 `nativehud/manage`；
  - 非字符串、越界或含非法字符的显式 token 零发送；
  - 普通 manage 与 trainer opener 不自行合成或携带 `openRequestId`。

## 3. 注入层 publish 证据

命令：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\compile_test.ps1 -Target publish -TimeoutSeconds 300 -VerifySwf scripts\asLoader.swf
node tools\swf-function-sizes.js scripts\asLoader.swf --max 60000 --top 15
```

- `scripts/asLoader.swf`：1,061,235 bytes，SHA-256 `33291ED41C14DA709A706831114C2E299C56641DC378D70A8439D7096EF1D45F`
- mtime：`2026-07-28 08:31:22.522 +08:00`
- 9,706 functions；最大 45,868B，全部 `< 60,000B`
- publish 的 compiler errors/warnings 为 `0/0`。
- publish 阶段 `flashlog.txt` 没有刷新，因此 publish 只证明目标 SWF 新鲜与可编译，不代替 §2 的 fresh TestLoader 行为证据。为保存最终 focused 日志身份，publish 后又完整重跑了 §2。

## 4. 滚动文件身份

| 文件 | Bytes | mtime（UTC+08） | SHA-256 |
|---|---:|---|---|
| `scripts/TestLoader.swf` | 38,022 | `2026-07-28 08:31:55.794` | `291DE2186E0C823BF06801B2ECAF950AB071260A749BF1046C3F86B7CDBCB9B1` |
| `scripts/asLoader.swf` | 1,061,235 | `2026-07-28 08:31:22.522` | `33291ED41C14DA709A706831114C2E299C56641DC378D70A8439D7096EF1D45F` |
| `scripts/flashlog.txt` | 7,871 | `2026-07-28 08:31:57.235` | `01FB78281B5B4A88FFF59C7329C5F27ED0D3171FC9DE99D93C8C2DDAF4D0FAB9` |
| `scripts/compile_output.txt` | 7,890 | `2026-07-28 08:31:57.039` | `BFEAFEF89972BA23F31ABCFF079A084C849315775BE9695E73F4AE651BD195BE` |
| `scripts/compiler_errors.txt` | 27 | `2026-07-28 08:31:56.955` | `6D64657E843CFA06C243B6B51F8732C1B5910EBD29940AA7F6F9342B38034FD3` |

## 5. Host 与 Web 自动门边界

- Launcher Release 全量：`1548/1548`。
- Character→Skills、Router/PanelHost/WebOverlay 三类定向：`141/141`。
- Panel runtime：`20/20`；send-false 用例直接锁定 callback 在 `request()` 返回前同步发生、返回 truthy callId、response/entry/return callId 同一且 pending 归零。
- Host 测试覆盖 exact arm-before-close、atomic consume、deferred-open 丢弃、nonce/source/view/baseline、send-false/timeout/navigation/socket/competing-panel 撤销、manage pending/active 时教师拒绝与 scoped cleanup。
- Character Build workbench 三视口合计 `630/630`，storage hidden-body `4/4`，合计 `634/634`；slot transition `18/18`。
- CSS bundle：18 imports、17,158 行、646,605 bytes、SHA-256 `c629efdd46e0ddf758025f315aea3416cebd1a696faee1796e59507d82be044d`。
- Skill policy：`47/47`；Skills browser 三视口合计 `396/396`（各 `132/132`）。
- 最终 Web Node 要求集 `345/345`，另有 shared primitives `9/9`；完整 browser 矩阵 `1,412/1,412`，strict UI audit `0 error / 0 warning`。

以上计数来自全部 Web 修订合入后的同一最终工作树。后续隔离 candidate 的执行与 E2E 证据见 §6。

## 6. 隔离 candidate 与真实 Character Build → Skills E2E

### 6.1 Candidate 身份

- 干净 detached worktree：`E:\cf7-e2e\character-skills-14a2529e8b\resources`。
- source commit/tree 与本文头部完全一致；验收前后 tracked status 均为空，主工作区未提交的 `launcher/web/modules/arena-unit-param-presets.js` 没有进入 candidate。
- `automation/dev.ps1 -BuildOnly`：`candidate_built / NOT_DEPLOYED`；candidate action 为 `reused`，随后由 v2 integrity verifier 重新核验。
- candidate root：`E:\cf7-e2e\character-skills-14a2529e8b\resources\tmp\runtime-candidates\v2\c-a4f5eaded66f-08846e81b3-20260728t011451580z-ec3b7b81`。
- 实际 Core 进程：上述 candidate 下 `runtime\CRAZYFLASHER7MercenaryEmpire.Core.exe`，最终验收 PID `20756`。
- Core DLL SHA-256：`01656974A3E3C24BCF75C61546942C0DC822F16C19DD3E9C61F5D6A2F40D934D`。
- build identity：`A4F5EADED66FE38EC7CF4C4395811FC117A566996F43AC02D369909C31E8FB53`。
- payload closure：`C03E82C4030A04DA235AF6FE9A375C0EBA7A503329B205882CB39B0D053F87F8`。
- runtime mode：`isolated_candidate`；deployment status：`NOT_DEPLOYED`。
- `launcher_ports.json` 将 PID `20756` 绑定到 HTTP `1192` / socket `1924`；实际进程路径、Core bytes、manifest、build identity 与 payload closure 在业务动作前后均一致。

### 6.2 专用存档与进入游戏

- 只读 seed：主工作区 `saves/crazyflasher7_saves.json`，15,211 bytes，mtime `2026-07-05 13:00:24 +08:00`，SHA-256 `C8DDC515245E2DB9AAB726739A2A6FB7BEBB2707529DA638B4A348387E2FA365`。
- 写目标仅为隔离 worktree 的 `cf7_agent_character_skills_14a2529e8b` 专用 clone；主工作区 seed 在验收后保持上述大小、mtime 与哈希。
- 最终 attempt：`9374b370a5284584a814ebfc8de77782`。Launcher save、AS2 runtime save 与 `gameEnteredAttemptId` 三者均为该 exact slot/attempt，`readyForRuntimeAutomation=true`。
- unattended 报告（相对隔离 worktree）：`tmp/character-skills-e2e/unattended-cdp.json`，SHA-256 `FCF698614703F34C5DA5E72459CF0D723C5F9E0D9130BD25B5D0D92F7782B443`；结果 `snapshot_gate_reached`、runtime identity verified、`businessWritesAttempted=false`、business command 数量为 `0`。
- 首个探索进程 PID `18400` 因 reveal watchdog 比真实 title-frame receipt 早约 0.48 秒而被 runner fail-closed；该轮已关闭且不计入 E2E。最终 PID `20756` 的 fresh handoff、真实 title-frame、单次 `agentEnterResolvedSave` 与 runtime-ready 均自然通过。

### 6.3 构筑入口与点击前权威门

- 为只读自动验收，最终候选仅通过进程环境加入 `CF7_WEBVIEW2_ARGS=--remote-debugging-port=0`；没有修改代码或持久配置。精确连接 Overlay target `https://overlay.local/overlay.html`，不是 Bootstrap target。
- 关闭 runner 打开的调制工作台后，通过固定 `agent_control/openCharacterBuild` opener 进入 `profile=battlebox / view=build / source=agent_control`，未注入任意 panel initData。
- 新鲜日志水位 `501 → 525` 内依次出现：
  - production `panel_request`：`panel=workbench`、`profile=battlebox`、`view=build`、`source=agent_control`；
  - `[PanelHost] opened: workbench`；
  - `event=character_build_panel_bound panelInstanceId=panel.8deec4736daf777.2`；
  - `event=character_build_snapshot_accepted phase=initial authorityApplied=true`。
- CDP 点击前只存在一个可见且可用的 `[data-header-action="skills"]`，文案为“技能配置”；页面标题为“角色构筑”，active panel 为 `workbench`。

### 6.4 真实点击后的 Host/AS2 正链

点击前日志水位为 `525`，点击后总量为 `566`，41 条 fresh records 中依次出现：

1. close payload 为 exact `reason=navigate_skills`；
2. `event=character_build_skills_navigation_armed`；
3. `detach recovery required ... reason=normal_close`；
4. `[PanelHost] closed: workbench`；
5. `-> Flash host-only recovery`；
6. `recoverDetach` 回包为 `success=true / persistence.changed=false / pauseReleased=true / recoveryState=settled`；
7. `detach recovery proof consumed`；
8. `event=skill_panel_open_requested source=character_build`；
9. AS2 `panel_request` 同时含一次性 `openRequestId`、`panel=skills`、`source=nativehud`、`initData.view=manage`；
10. `event=skill_panel_opened view=manage` 与 `[PanelHost] opened: skills`；
11. Skills snapshot 路由到 `SkillTask`，发送 exact `action=skillSnapshot / view=manage`。

同一 41 条 fresh records 对以下负向模式匹配数为 `0`：

```text
character_build_skills_navigation_cancelled
skill_panel_open_failed
skill_panel_open_rejected
skill_panel_open_fallback
skill_panel_open_cancelled
detach recovery fatal-blocked
detach recovery did not settle
character_build_shutdown_fence result=blocked
source=world_skill_trainer
"view":"trainer"
trainerSession
canReturnTrainer
```

### 6.5 最终 Skills DOM 与视觉证据

- Console 的真实 open command：`source=nativehud`、`view=manage`、`writeState=idle`；没有 trainer capability 字段。
- 最终只显示一个 Skills panel，active panel 为 `skills`，`data-skill-view=manage`。
- `SkillsPanel.debugState()`：`view=manage`、`coordinator.view=manage`、`coordinator.trainerSession=""`、`state=idle`、`pendingCount=0`、`snapshotRevision=0`、`schemaError=""`。
- 页面显示“我的技能”“已学技能库”、9 个已学技能与 12 格快捷栏。
- `.skills-trainer-view`、`.skills-trainer-actions`、`.skills-trainer-commit`、`.skills-level-stepper`、`.skills-switch-manage-btn`、`.skills-switch-trainer-btn` 均为 `0`；文本中没有教师、学习/升级或“返回研习”。
- 构筑页截图（相对隔离 worktree）：`tmp/character-skills-e2e/character-build-before-skills.png`，SHA-256 `E5ED6780AFDABE3BCDDBA6AAE591339B4F3F6B4B9CB8285C81365C9A275BE716`。
- Skills settled 截图（相对隔离 worktree）：`tmp/character-skills-e2e/skills-manage-settled.png`，SHA-256 `E0F83012A0483D06B5F7D78EA5E2025169B31A62B22349AC2F2AE2C41E2E29E4`。
- 两张图均来自实际 1600×900 candidate 窗口；人工视觉复核未见溢出、遮挡或双面板残留。验收后先正常关闭 Skills，再由 `agent_control/shutdown` 关闭 candidate，进程已退出。

因此源码基线 `14a2529e8b` 已达到 `e2e_verified / NOT_DEPLOYED`。本轮没有 promotion，也没有从正式 bootstrap/runtime 标准入口执行，不能称 `promoted` 或 `standard_entry_verified`。

## 7. K3 最终异构裁决

- 固定 session：`02ad8c0c-9375-43be-af95-55252bf03be0`。
- 固定参数：`kimi-code/k3 --thinking --plan --max-steps-per-turn 100`；未降级模型或思考强度。
- Round 4 最终裁决：`GO`，`0 Blocker / 0 High / 0 Medium / 4 Low（非阻断）`。
- 明确结论：`本轮 1–7 源码施工可收口`。
- 审阅重新确认 Character Build → Skills 与刘海屏 `SKILLS` 同义，只能以 `nativehud/manage` 管理玩家自身已学技能、快捷栏与被动；`trainerSession`、`canReturnTrainer`、教师学习或升级能力均不可由该入口获得。
- K3 的 GO 只裁决源码复杂度、维护成本、交互与视觉边界，不冒充 §6 的真实 candidate E2E；candidate 仍为 `NOT_DEPLOYED`。
