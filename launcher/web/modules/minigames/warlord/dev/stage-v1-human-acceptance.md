# 军阀 GameStage v1 历史真人记录

> 当前不再单独触发 Slice 1 人类验收。Slice 3 已关闭的是旧测试入口下的玩法感知，未代签 GameStage 进入链；该连续旅程现并入 [Slice 6 单一真人验收单](slice-6-human-acceptance.md)。本文件只保留 2026-09-01 既有 Phase C 游玩证据与历史边界。

状态：`HISTORICAL_PHASE_C_EVIDENCE_ONLY / HUMAN_PHASE_C_VICTORY_PASSED /
VNEXT_R9_HUMAN_ACCEPTANCE_FAILED / R10_CANDIDATE_BUILT / HUMAN_ACCEPTANCE_PENDING / NOT_DEPLOYED`。本单只承接机器无法代替的真实
Launcher/WebView2、玩家输入、视觉与转场判断；机器测试结果不在这里重填。自本记录起，
所有实际游玩、手感、观感和旅程连贯性判断均由人类完成；自动化只负责候选身份、构建、
协议/状态机、日志、产物与退出清理，不把 UI 代操作纳入验收管线。

## 2026-09-01 已取得的真人证据

- 最终实际运行的是隔离 candidate
  `tmp/runtime-candidates/v2/warlord-stage-v1-0901b/CRAZYFLASHER7MercenaryEmpire.exe`；
  bootstrap 精确记录其 `runtime/CRAZYFLASHER7MercenaryEmpire.Core.exe`。build identity 为
  `E83BFFBB4DD1E64909D1B4F0EE68B93945447BBEE0978A11E12BCC8DEB0E4303`，payload
  closure 为 `0ADC8472BE9D347663B2BF1A668E1B541BEA7D0DD2AC0676B95D1DEE8B15B0BF`。
- `warlord-stage-v1-0901b` 已通过 v2 integrity-only verifier；它与先前实际运行的
  `warlord-stage-v1-0901` 保持 exact identity/closure，bootstrap EXE 与 Core DLL 逐字节相同。
- 维护者先反馈“游戏本身进行得很成功，没感受到显著的行为差异，玩起来正常”，随后在
  最终 `0901b` 继续完成现役 Phase C 对局。日志记录 3 次 AS2 战斗均为 `finished`，每次都
  `warlord_resume_open_result result=opened`；截图在第 3 战略回合显示红方“我方胜利”。
  因而最终候选的人类证据升级为 `HUMAN_PHASE_C_VICTORY_PASSED`。
- 胜局后 exact panel close 完成，空 binding 的 recovery 投影保持 `inactive`，shadow save
  成功；Flash Player 以 code `0` 退出，Launcher 随后完成正常 shutdown。该证据覆盖现役
  Phase C 战斗、回流、战略终局和退出生命周期，不外推为新 GameStage 一次性结算。
- 截图中的“玩法帮助”右侧 `×` 是军阀面板关闭按钮；游戏顶栏的 `×` 不是该按钮，
  顶栏下方显示“任务已达成 · 可交付”的窄条才是右侧原生状态槽。
- 当轮 `launcher.log` 没有 `warlord_stage_start`，恢复投影只有空 binding 的 `inactive`；
  因此本次不能代签真实 GameStage 军阀纵切、类型化终态或结算返回。
- 原始 ADR 的 Slice 1 要求是 GameStage 入口、WarlordSubStageRunner 与外层只结算一次；
  它没有要求玩家关闭后必须出现“恢复演习”按钮。该整局 recovery/retry/revision+1 扩展后来在 r9
  掩盖返回基地后的 old outer owner 泄漏，现已从工作树删除；后续验收应确认完全没有该按钮或恢复入口。

## 开始前

- 使用交付说明中指定的隔离 candidate 根目录启动，不要混用正式根 EXE。
- 记录 candidate 的 `buildIdentity`、`payloadClosure` 与实际 EXE 路径；三者任一不符即停止。
- 使用可回滚的测试存档。军阀 Web 仍固定 `productionWrites=false`，但正常 GameStage
  返回/结算属于 AS2 现役关卡生命周期，不能据此前端标志假定整段旅程零存档写。
- 本段历史步骤已经 supersede，不再按“正常选关”执行；当前只能从 `其他 → 测试 → 军阀演习测试` 的白名单选关页进入真实 GameStage，默认生产目录不暴露军阀关卡。

## r10 candidate 仍需的一次人类连续旅程

1. 进入演习后确认只出现一个军阀面板，红方是玩家，局面、回合与可执行动作可见；
   Flash 战斗图不得在面板后继续接收误点。
2. 正常游玩至红方取得规则胜利。胜利只应结算一次：Web 关闭一次、AS2 收到
   `CompleteSubStage`、正常关卡结束/返回链继续；不得同时出现失败提示或重复奖励。
3. 完成正常返回基地与可能出现的关卡结算。确认可以继续操作基地，且没有残留面板、
   暂停租约、输入屏障或第二次返回。

## 可选诊断，不阻断 Slice 1

- 若专门测试尚未分出胜负时的面板 `×`，只要求技术关闭不得伪装成玩家失败。
- 不再观察“演习已暂停 / 恢复演习”产品面；它已删除。父 clear、返回基地、restart 或启动失败的
  outer owner retirement 由 `warlord_stage_outer_cancelled` 机器日志和自动回归证明，不要求人类抄 receipt。
- 返回基地后可从测试选关页 first try 打开 Demo 1；若出现恢复提示、Host busy 或必须重试，直接判阻断。

## 通过边界

以下条件必须同时成立：测试专用选关页可进入真实 GameStage；红方胜利只映射一次 `CompleteSubStage`；正常
返回/结算完成；无肉眼可见布局、焦点或输入阻断。任一失败都保持
`HUMAN_ACCEPTANCE_PENDING`，机器门与 candidate 身份不变。

零战棋背景玩家是否看懂术语、目标和帮助，另按[首次游玩观察单](semantic-first-run-review.md)
做一次 10～15 分钟观察；它不与本技术旅程互相代签。

## 最短记录

```text
candidate_exe=
buildIdentity=
payloadClosure=
test_game_stage_entry=passed | failed
red_victory_complete_once=passed | failed
settlement_and_return=passed | failed
visual_focus_input=passed | failed
fresh_demo1_after_return_base=passed | failed
first_blocker=none | <一句话 + 发生步骤>
```
