# Character Build → Skills 收口证据

**状态**：源码与自动门闭合；`NOT_CANDIDATE_BUILT / NOT_DEPLOYED`

**日期**：2026-07-28（UTC+08）

**源码基线**：`21ad8a272a3bd85f77f3bb891fe55f8981c272b8` 加本文所述未提交工作树；最终提交身份另由 Git 历史冻结。

本文是受 Git 跟踪的持久审计索引。Flash runner 的滚动日志仍位于 `scripts/`，不会被本文冒充成不可变原始件；这里保存 exact runId、结果、时间、大小与 SHA-256，使后续覆盖滚动文件时仍能核对本轮身份。本文不授予 candidate、promotion、部署或正式入口验收结论。

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

以上计数来自全部 Web 修订合入后的同一最终工作树。没有新 immutable candidate 的实际 Core 路径、build identity、payload closure 与进程证据，因此本文不能称 `candidate_built`、`candidate_executed` 或 `e2e_verified`。

## 6. K3 最终异构裁决

- 固定 session：`02ad8c0c-9375-43be-af95-55252bf03be0`。
- 固定参数：`kimi-code/k3 --thinking --plan --max-steps-per-turn 100`；未降级模型或思考强度。
- Round 4 最终裁决：`GO`，`0 Blocker / 0 High / 0 Medium / 4 Low（非阻断）`。
- 明确结论：`本轮 1–7 源码施工可收口`。
- 审阅重新确认 Character Build → Skills 与刘海屏 `SKILLS` 同义，只能以 `nativehud/manage` 管理玩家自身已学技能、快捷栏与被动；`trainerSession`、`canReturnTrainer`、教师学习或升级能力均不可由该入口获得。
- 候选与人类 E2E 边界不被异构 GO 冒充：本节记录时仍为 `NOT_CANDIDATE_BUILT / NOT_DEPLOYED`。
