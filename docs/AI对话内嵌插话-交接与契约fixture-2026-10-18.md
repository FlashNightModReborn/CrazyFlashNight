# AI 对话内嵌插话 · 交接与契约 fixture

**文档角色**：游戏侧与后端侧共用的冻结样例与期望结果表。协议真源＝《AI对话内嵌插话-需求与协议-2026-10-18.md》（下称《协议》）；本文只把协议落成可执行的请求、SSE、JSONL 与期望行为，不另立语义。
**冻结基线**：游戏仓 `b3705d36fe`（P1 源码），后端仓 `9ccaac9`（B1 源码），2026-10-18；P0 文档基线为 `5b6dc7b8e0` / `8143b1d`，初始文档提交为 `83d55803ca` / `4f2248a`。
**任务协议同步基线**：后端 `80c895f`、游戏仓 Host `c5f90a0779`（2026-10-29，任务 JSONL 统一 `type/no/text`，SSE plan 统一 `{mute,resume,steps}`）。任务段落以该代码为准；日常模式 `add`/`closing` 与 `line` 事件不变。
**使用方式**：
- 后端窗口：用假 LLM 按 §2 的 JSONL 原文回放，断言 §3 的 SSE 顺序与形状，再断言 §4 的 plan/session。
- 游戏窗口：把 §3 的 SSE 序列注入 Host SSE 客户端，断言 §4 的播放序列、输入可用状态、finish/finalize。
- 两侧都不得修改 fixture 来迁就实现；任务段落的 JSONL/plan/Host 应用以文首“任务协议同步基线”的代码为准，其余契约冲突以《协议》为准，停下来报告，不单边改字段。
- fixture 测试不调用真模型；真模型走查属于 P5，单独记录。

---

## 1. 公共约定

- 时序：文中延迟只是示意；规范的是事件顺序与“首句/首段早于 done/plan”。
- `status` 可选；测试不得依赖其数量或文案。若发送，`stage ∈ {connecting, thinking, searching, drafting, waiting}`；可选 `ui_hint` 为 ≤12 字进度提示，只影响等待占位，不写转录。
- `line.interim` 可选；`true` 表示任务草案等待期的后端过渡话。它是正常 `add`（进已播/finalize），但 Host 越过它后仍以最新 `ui_hint` 占位等最终确认对话；缺省/false 为普通台词。
- `line.seq`：每个 turn 从 0 开始单调递增；一个 turn 内不重复。`played[].seq`：同一 session 内不重复。`plan.steps` 不占 `line.seq`，按数组顺序播放。
- `split`：仅当一条模型正文被 165 硬上限拆成多段时出现；`index` 从 0 起，`count` 为总段数。自然多行不带；`line` 与 `plan.steps[].lines[]` 同构。
- 情绪统一用“普通”，避免依赖具体 NPC 白名单；真模型走查再验证真实情绪。
- 请求中 `remaining[].index` 与 `reference_continuation[].index` 固定为 **1..N**，与模型 `no` 同口径；Host 负责与原始绝对行号互转；每轮从当前播放点之后连续重排 1..N。
- `dialogue.kind ∈ {daily, task_pre, task_post}`，且与 `mode` 匹配。
- `reference_continuation[].kind ∈ {add, closing, edit, remove}`；日常未播的结束语用 `closing`。
- 任务 JSONL 统一 `type/no/text`：`{"type":"mute"}` / `{"type":"add","no":0,"text":"…","emo":"…"}` / `{"type":"edit","no":n,"text":"…","emo":"…"}` / `{"type":"keep","no":n}` / `{"type":"remove","no":n}` / `{"type":"continue","no":n}` / `{"type":"end"}`。`add`、`edit` 必须带 `text`+`emo`；其余操作不填 `text`/`emo`；`add` 的 `no` 固定 0，`end`/`mute` 不带 `no`。
- `mute` 可选，缺省 false；需要时必须作为整个输出的第一行，只在玩家内容严重离谱、完全无法接话时使用。禁言时第一条 `add` 用“无视、打断或化解”回应，再按原编号继续。
- `add` 可插在任意两个操作之间，不占原编号；首个原编号操作之前的 `add` 由后端即时推 `line`，其后出现的 `add` 必须进入 `plan.steps`，按位置播放。
- `continue` 之前的原编号必须从 1 开始严格递增，不得跳号、倒序或重复；连续同 `no` 的 `edit` 是唯一拆条例外（合并为同一条改写）。
- `continue(no)` 从原第 no 条保留到组末；`end` 不再保留任何未处理原文；两者必须且只能出现一个并位于最后。缺终止符或 `continue` 非法时，从最后处理的原编号之后保留原文；尚未处理任何原编号则保留全部。跳号编号由后端补成 `remove` 并记日志。
- 任务 plan 统一为 `{"mute":false,"resume":3,"steps":[...]}`：`resume` 为 1..N+1，N+1 表示不接回原尾部；`steps` 有序，可为 `add`/`edit`/`keep`/`remove`，`add` 的 `n=0`，`lines[]` 为 `{text,emotion,split?}`；`keep`/`remove` 不带 `lines`。
- Host 顺序应用 `steps`：`add` 原位插入、`edit` 替换原编号、`keep` 保留原文、`remove` 跳过；`resume` 之前未被 steps 覆盖的原编号按 `remove` 处理，从 `resume` 起接回原文。`resume` 缺失或越界（不在 1..N+1）按从 1 接回；`resume=N+1` 放弃原尾部，下一轮 `remaining` 为空。
- 已收到但未应用的 plan 不应用，转 `reference_continuation`：`add`/`edit`/`remove` 按 steps 顺序携带，`keep` 不产生参考；未播出的 `edit`/`remove` 编号按下一轮 `remaining` 的 1..N 折算，已越过或原编号已不存在（原尾部已放弃）则丢弃。
- 失败/部分断流不发 `plan`；`mute` 独立事件与 `plan.mute` 是同一禁言状态的双通道。
- 请求 `played` 只含本轮玩家发送之前已播出的行；本轮 `$PC` 由 `player_input` 表示，由 finalize 按实际播放写入，不得在 `played` 与 `player_input` 中重复。
- session 只记录真正播放过的行；拆分产生的多段按播放顺序各记一条 assistant，不合并。
- `finalize.transcript` 是该 session 截至当时的全部已播行（含历轮），行结构与请求 `played` 相同；未出现在其中的未播内容不落库。
- Host 对 mutation 的 ack 若带 `rowCount`，只能是 wire 行数；本地增强行数不得回传。
- `close` 的 `finalIndex` 取当前播放点已到达的最大原始行号（增强行不推进），钳在 `[0, wireRowCount-1]`。
- `finalize` 成功响应固定为 `{ok:true,dialogue_instance_id,session_id,appended,total}`；未知 session 且 transcript 为空时 `ok:false`、`session_id:""`。
- `error.valid_lines` 按模型输出行计、拆分前；日常只计 `add`/`closing`，任务只计 `add`/`edit`；`mute`/`keep`/`remove`/`continue`/`end` 不计。
- `reference_continuation` 的 edit/remove index 越界（不在当前 1..N）＝非法请求，后端 422。
- 真取消＝Host 关闭 SSE 连接，不存在独立 cancel 端点；后端断开即取消 LLM/工具，Host 随后 finalize。
- fixture 中固定假 UUID 仅用于断言；真实 Host 使用自己的 UUID。
- `dialogue.group_id` 是 Host 侧不透明标识：当前实现填 Native book 会话的 `requestId`（形如 `nd:N`）；同一组 append 不变，新 book 即新组。后端不据此定位 session。本文旧样例里的 `daily_andy_01` 等只作可读标签。
- `emotion` 可选；Host 取原作立绘表情，缺省 `普通`；后端缺失按 `普通`。它只是语气提示，不参与输入校验。
- 组类型由 Native book 可选 `dialogueKind` 决定，缺省 `daily`；任务前/后由 AS2 入口标记，`stage` 不插话。
- Host 可在每轮结束发 best-effort finalize，并在关闭/组末发最终 finalize；transcript 每次都是全量前缀，按 seq 幂等。关闭/组末那次为权威收尾。
- 进入 closing（`advance_past_end`/`close`）即隐藏输入、真取消在途流并按已播 finalize；已收到未插入的台词不再进本组。

固定样例身份：

| 名称 | 值 |
|---|---|
| 日常 `dialogue_instance_id` | `11111111-1111-4111-8111-111111111111` |
| 日常 turn A / turn B | `aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa` / `bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb` |
| 任务 `dialogue_instance_id` | `22222222-2222-4222-8222-222222222222` |
| 任务 turn | `cccccccc-cccc-4ccc-8ccc-cccccccccccc` |
| 当前 NPC | `Andy Law` |
| 玩家 | `$PC` |

---

## 2. Fixture 索引

| 编号 | 场景 | 覆盖契约 |
|---|---|---|
| F-01 | 日常普通 | 多 `add`＋`closing`、逐句可输入、session 映射 |
| F-02 | 日常拆分 | 165 拆分、`split` 标记、前置段暂锁/末段恢复 |
| F-03 | 日常任务草案 | 抑制过渡语、草案后最终对话＋结束语、草案保留 |
| F-04 | 日常中途插入 | 播放中发送、补全当前句、取消在途、参考续写、同 session |
| F-05 | 任务 `continue` 接回 | 有序 `steps`、`keep`/`edit`、`continue` 接回、组末原 finalIndex |
| F-05b | 任务改写拆分 | plan 内 `lines[].split`、任务输入暂锁例外 |
| F-06 | 任务 `remove` 与跳号 | 显式 `remove`、未提及编号补 `remove`、`continue` 接回 |
| F-07 | 任务 `keep` 与缺终止符 | 显式 `keep`、缺 `continue`/`end` 时保留尾部 |
| F-08 | 任务 `end` 整组收束 | `end` 不接回、未处理编号补 `remove`、下一轮 remaining 为空 |
| F-09 | 任务 `mute` | `mute` 首行、`mute` 事件与 `plan.mute`、首句化解、本组后续禁言 |
| F-10 | 零有效 | 修复重试一次、仍零→`error`、回原对话 |
| F-11 | 部分有效后流断 | 已播保留、无 plan、回原对话当前点 |
| F-12 | 关闭/取消 | 真取消、未播不落库、finalize 按已播收尾 |
| F-13 | 赠送精确名成功 | `action(item_grant)`→Host 回执→最终台词；账本/本组明细 |
| F-14 | 赠送超量自动降量 | 传话上限、`floor` 降量、金币/经验 500 取整 |
| F-15 | 赠送 1 个都超限 | 不发 `action`、不记账、模型拒绝 |
| F-16 | 索取精确名 + 点赠送 | `item_claim(pending)`、两按钮、真实扣除、`item_take_accept` |
| F-17 | 索取子 Agent 再查一次 | 金币第一、抽选+池概况、`search` 仅一次、返回命中池 |
| F-18 | 索取拒绝/取消 | 玩家拒绝/模型取消、`item_claim(closed)`、不记账 |
| F-19 | 任务接受直连 | `action(task_accept)` 跳过路由轮、最终台词、不重复弹选项 |
| F-20 | 装备索取与强化度 | 只取背包、最低强化度、选项文案、`item_level`、完成描述三档 |

---

## 3. Fixture 正文

### F-01 日常普通

**请求（关键字段）**

```json
{
  "mode": "daily",
  "dialogue_instance_id": "11111111-1111-4111-8111-111111111111",
  "turn_id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
  "npc": "Andy Law",
  "player_input": "最近怎么样？",
  "session_title": "日常插话 · Andy Law · 2026-10-18 14:03",
  "dialogue": {
    "kind": "daily",
    "group_id": "daily_andy_01",
    "played": [
      {"seq": 0, "role": "npc", "name": "Andy Law", "text": "又是你。", "emotion": "普通"}
    ],
    "remaining": [
      {"index": 1, "name": "Andy Law", "text": "有事说事。", "emotion": "普通"},
      {"index": 2, "name": "Andy Law", "text": "没事就别挡道。", "emotion": "普通"}
    ],
    "reference_continuation": []
  },
  "task_context": null,
  "limits": {"line_hard_max": 165, "line_prompt_max": 135}
}
```

**假 LLM 原文（JSONL）**

```jsonl
{"add":"还能怎么样，老样子。","emo":"普通"}
{"add":"你倒是难得过来一趟。","emo":"普通"}
{"closing":"说吧，想聊什么？","emo":"普通"}
```

**期望 SSE**

```text
event: status
data: {"stage":"thinking"}

event: line
data: {"kind":"add","text":"还能怎么样，老样子。","emotion":"普通","speaker":"Andy Law","seq":0}

event: line
data: {"kind":"add","text":"你倒是难得过来一趟。","emotion":"普通","speaker":"Andy Law","seq":1}

event: line
data: {"kind":"closing","text":"说吧，想聊什么？","emotion":"普通","speaker":"Andy Law","seq":2}

event: done
data: {"dialogue_instance_id":"11111111-1111-4111-8111-111111111111","session_id":"<新 id>","usage":{}}
```

**期望 Host**

- `seq0` 一开始显示即可输入；`seq1`、`seq2` 同理，不等逐字播完。
- 玩家不插话时按 0→1→2 播放；播到 `closing` 开始显示即可输入。
- 点击结束语后的“下一条”关闭本组；继续输入则 `closing` 算已播并开新一轮。
- 成功轮不接回原作剩余 `remaining`（“有事说事。”“没事就别挡道。”不播）；`advance_past_end` 仍按原文最后一行编号发 finish。
- 关闭时 finalize 的 transcript 见 §4.4。

**期望后端**

- 首轮创建 session，种入 `played` 的 `seq0` 与本次 `$PC`；不得重复建 session。
- 无工具调用；三条 AI 行按顺序推送；`done` 后 session 消息顺序为 原作/玩家/AI/AI/AI。
- `usage` 缺失时允许空对象；不得阻塞 `done`。

---

### F-02 日常拆分

**请求**：与 F-01 相同，`player_input` 改为“北边那条路还能走吗？”，`turn_id` 用新值。

**假 LLM 原文（JSONL，单条超 165）**

```jsonl
{"add":"北边那条路前几天塌了，现在只能绕南边过去；南边的桥也不稳，晚上没人敢走。你要是真打算去，先去货栈找老周，他知道一条旧路，不过那条路要穿过废楼，白天都容易迷路。别一个人去，带上家伙，也别信路上遇到的任何人，这年头谁都不容易，谁都想从你身上捞点好处。再说了，老周那人嘴碎，但消息准，问他之前先递包烟，别空着手去。要是路上真出了事，就往东边的旧水塔跑，那里地势高，能看见整个厂区，也方便我找人接你。","emo":"普通"}
{"closing":"记住了就早点回来。","emo":"普通"}
```

**期望 SSE（形状）**

```text
event: line
data: {"kind":"add","text":"<段 0>","emotion":"普通","speaker":"Andy Law","seq":0,
       "split":{"index":0,"count":2}}

event: line
data: {"kind":"add","text":"<段 1>","emotion":"普通","speaker":"Andy Law","seq":1,
       "split":{"index":1,"count":2}}

event: line
data: {"kind":"closing","text":"记住了就早点回来。","emotion":"普通","speaker":"Andy Law","seq":2}

event: done
data: {"dialogue_instance_id":"11111111-1111-4111-8111-111111111111","session_id":"<同上>","usage":{}}
```

**断言（不写死切点）**

- 两段按顺序拼接后与原始 add 正文完全一致（不丢字、不重复）。
- 每段 ≤165；切点优先落在 `。`，且 `split.count == 2`。
- `closing` 不带 `split`。
- Host：段 0 输入暂锁（“（暂时不适合插话）”）；段 1 开始显示即恢复；`closing` 开始显示可用。
- session：段 0、段 1 各记一条 assistant，顺序不变。

---

### F-03 日常触发任务草案

**请求**：与 F-01 相同，`player_input` 改为“有没有什么活儿给我？”，`turn_id` 用新值。

**假 LLM 行为**

1. 先产生工具调用 `route_task_draft`（不是 JSONL；由既有任务链生成草案）。
2. prepare 完成（中间结果）时，后端用方向种子单独生成一条过渡话，以 `line(add, interim=true)` 推送；该句不属于下面的 JSONL 假流。
3. 草案就绪后，才输出以下 JSONL：

```jsonl
{"add":"行，那我直说了。","emo":"普通"}
{"add":"城西的补给线断了，我需要有人去看一眼，顺便把货带回来。","emo":"普通"}
{"closing":"接不接，你自己想清楚。","emo":"普通"}
```

**期望 SSE**

```text
event: status
data: {"stage":"thinking"}

event: status
data: {"stage":"drafting"}

event: status
data: {"stage":"drafting","ui_hint":"准备候选中"}

event: status
data: {"stage":"drafting","ui_hint":"拟定委托中"}

event: line
data: {"kind":"add","text":"我这儿正盘算着件事。","emotion":"普通","speaker":"Andy Law","seq":0,"interim":true}

（过渡话只点方向、不报数字；草案终态先到时不发过渡话）

event: line
data: {"kind":"add","text":"行，那我直说了。","emotion":"普通","speaker":"Andy Law","seq":1}

event: line
data: {"kind":"add","text":"城西的补给线断了，我需要有人去看一眼，顺便把货带回来。","emotion":"普通","speaker":"Andy Law","seq":2}

event: line
data: {"kind":"closing","text":"接不接，你自己想清楚。","emotion":"普通","speaker":"Andy Law","seq":3}

event: done
data: {"dialogue_instance_id":"11111111-1111-4111-8111-111111111111","session_id":"<同上>","usage":{}}
```

**期望 Host / 后端**

- 草案生成期间输入锁定并显示“（正在准备…）”；`ui_hint` 到达后占位原位显示该提示。
- 过渡话上屏后即可插话；玩家越过过渡话而最终确认对话未到时，继续显示最新 `ui_hint` 占位，最终对话首句到达时原位替换占位。
- 结束语表达“不接就搁着”，不要求固定措辞。
- 玩家关闭对话后草案仍保留在 `agent_tasks`，终端可继续；不得写 `dialogue_overrides.json`。
- 发布/确认/取消仍走既有任务工具链；本 fixture 不测发布写盘。

---

### F-04 日常中途插入（逐句可输入）

**Turn A（请求同 F-01）**

假 LLM 原文：

```jsonl
{"add":"还能怎么样，老样子。","emo":"普通"}
{"add":"你倒是难得过来一趟。","emo":"普通"}
{"closing":"说吧，想聊什么？","emo":"普通"}
```

Host 行为：

1. `add0` 开始显示，输入即可用。
2. 玩家在 `add0` 播放期间发送“先别说这个，我想问问任务。”。
3. Host 先补全 `add0`，取消 Turn A 在途请求，播 `$PC` 台词，再发 Turn B。
4. `add1` 与 `closing` 未播放，不得进入已播历史/session。

**Turn B 请求（关键字段）**

```json
{
  "mode": "daily",
  "dialogue_instance_id": "11111111-1111-4111-8111-111111111111",
  "turn_id": "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
  "npc": "Andy Law",
  "player_input": "先别说这个，我想问问任务。",
  "session_title": "日常插话 · Andy Law · 2026-10-18 14:03",
  "dialogue": {
    "kind": "daily",
    "group_id": "daily_andy_01",
    "played": [
      {"seq": 0, "role": "npc", "name": "Andy Law", "text": "又是你。", "emotion": "普通"},
      {"seq": 1, "role": "player", "name": "$PC", "text": "最近怎么样？"},
      {"seq": 2, "role": "ai", "name": "Andy Law", "text": "还能怎么样，老样子。", "emotion": "普通"}
    ],
    "remaining": [
      {"index": 1, "name": "Andy Law", "text": "有事说事。", "emotion": "普通"},
      {"index": 2, "name": "Andy Law", "text": "没事就别挡道。", "emotion": "普通"}
    ],
    "reference_continuation": [
      {"kind": "add", "name": "Andy Law", "text": "你倒是难得过来一趟。", "emotion": "普通"},
      {"kind": "closing", "name": "Andy Law", "text": "说吧，想聊什么？", "emotion": "普通"}
    ]
  },
  "task_context": null,
  "limits": {"line_hard_max": 165, "line_prompt_max": 135}
}
```

Turn B 假 LLM：

```jsonl
{"add":"任务是吧，我这儿正好有个跑腿的活儿。","emo":"普通"}
{"closing":"感兴趣就接着往下听。","emo":"普通"}
```

**期望**

- Turn A 的 `add1`/`closing` 从未播放，不得进 session；`add0` 与两轮 `$PC` 都在。
- 仍是一个 session；Turn B 请求不得重复写入相同 `seq` 的已播行。
- 后端提示词能看到 `reference_continuation`，但不得把它当已播历史。
- Turn B 的 `add`/`closing` 开始显示即可输入；无锁整轮策略。

---

### F-05 任务 `continue` 接回（有序计划）

**请求（关键字段）**

```json
{
  "mode": "task",
  "dialogue_instance_id": "22222222-2222-4222-8222-222222222222",
  "turn_id": "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
  "npc": "Andy Law",
  "player_input": "这活儿我接了，先跟我说说细节。",
  "session_title": "任务插话 · 北边仓库 · 任务前 · 2026-10-18 14:10",
  "dialogue": {
    "kind": "task_pre",
    "group_id": "task_200124_pre",
    "played": [
      {"seq": 0, "role": "npc", "name": "Andy Law", "text": "你来了。", "emotion": "普通"},
      {"seq": 1, "role": "npc", "name": "Andy Law", "text": "先别急着走。", "emotion": "普通"}
    ],
    "remaining": [
      {"index": 1, "name": "Andy Law", "text": "你先别急着答应。", "emotion": "普通"},
      {"index": 2, "name": "Andy Law", "text": "北边仓库昨晚丢了东西。", "emotion": "普通"},
      {"index": 3, "name": "Andy Law", "text": "去把清单上的货找回来。", "emotion": "普通"},
      {"index": 4, "name": "Andy Law", "text": "回来之前别让我等太久。", "emotion": "普通"}
    ],
    "reference_continuation": []
  },
  "task_context": {
    "completed": {
      "task_id": 200123, "title": "南边哨站补给", "npc": "Andy Law",
      "objectives": ["送回 3 箱弹药"], "rewards": ["金币 1200"], "outcome": "玩家已送回 3 箱弹药"
    },
    "upcoming": {
      "task_id": 200124, "title": "北边仓库失窃", "npc": "Andy Law",
      "objectives": ["找回失窃货物", "返回交付"], "rewards": ["金币 2400", "声望 10"]
    }
  },
  "limits": {"line_hard_max": 165, "line_prompt_max": 135}
}
```

**假 LLM 原文（JSONL）**

```jsonl
{"type":"add","no":0,"text":"你倒是爽快。","emo":"普通"}
{"type":"keep","no":1}
{"type":"edit","no":2,"text":"北边仓库昨晚丢了一批货。","emo":"普通"}
{"type":"continue","no":3}
```

**期望 SSE**

```text
event: status
data: {"stage":"thinking"}

event: line
data: {"kind":"add","text":"你倒是爽快。","emotion":"普通","speaker":"Andy Law","seq":0}

event: plan
data: {"mute":false,"resume":3,"steps":[
  {"n":1,"kind":"keep"},
  {"n":2,"kind":"edit","lines":[{"text":"北边仓库昨晚丢了一批货。","emotion":"普通"}]}
]}

event: done
data: {"dialogue_instance_id":"22222222-2222-4222-8222-222222222222","session_id":"<新 id>","usage":{}}
```

**期望 Host 播放序列**

1. `add`：“你倒是爽快。”
2. `steps[0]` `keep n=1`：原文“你先别急着答应。”
3. `steps[1]` `edit n=2`：改写“北边仓库昨晚丢了一批货。”
4. 从 `resume=3` 接回原第 3、4 条原文。
5. 每句开始显示即可输入（禁言除外）；组末点击“下一条”关闭。
6. 组末 finish 用 **AS2 原始最后一行的 finalIndex**，不是增强行数；AS2 `advance_past_end` 校验通过。

**期望后端**

- 首个原编号操作之前的 `add no=0` 已即时推 `line`，不得重复出现在 `steps`；`keep 1`、`edit 2` 按输出顺序进入 `steps`。
- `continue 3` 归一化为 `resume=3`，不产生 step；原第 3、4 条不再出现在 `steps`。
- 整轮正常结束才发 `plan`；`line` 可以先于 `plan` 推送。
- session：`$PC`=user；`add`=assistant；原剩余 1=assistant；改写 2=assistant（保留原说话人）；接回的 3、4 按实际播放追加。

**边界：plan 已应用后中途插入**

若玩家在原文 1 播放中插话（plan 已应用、改写 2 未播）：下一轮 `remaining` 从原文 2 起重排（原文 2→index 1、原文 3→2、原文 4→3）；`reference_continuation` 携带 `{"kind":"edit","index":1,"name":"Andy Law","text":"北边仓库昨晚丢了一批货。","emotion":"普通"}`。`keep` 不产生参考，`resume` 之后的原文 3、4 仍留在 `remaining`。

**边界：原编号操作后的 add**

首个原编号操作之后出现的 `add` 不进 `line`，必须按输出顺序进入 `steps`，由 Host 按位置插入：

```jsonl
{"type":"add","no":0,"text":"前缀即时回应。","emo":"普通"}
{"type":"edit","no":1,"text":"改写 1。","emo":"普通"}
{"type":"add","no":0,"text":"插在 1 和 2 之间。","emo":"普通"}
{"type":"keep","no":2}
{"type":"continue","no":3}
```

```json
{"mute":false,"resume":3,"steps":[
  {"n":1,"kind":"edit","lines":[{"text":"改写 1。","emotion":"普通"}]},
  {"n":0,"kind":"add","lines":[{"text":"插在 1 和 2 之间。","emotion":"普通"}]},
  {"n":2,"kind":"keep"}
]}
```

SSE 顺序：`status` → `line`（“前缀即时回应。”）→ `plan` → `done`；`steps` 中不再出现该前缀 `add`。Host 播放：前缀 → 改写 1 → 插入 → 原文 2 → 原文 3、4。

---

### F-05b 任务改写拆分

**假 LLM 原文**：在 F-05 基础上，把 `no:3` 的改写写成一条超过 165 的正文，并用 `continue 4` 收尾（被改写的条目必须在 `continue` 之前）。

```jsonl
{"type":"add","no":0,"text":"你倒是爽快。","emo":"普通"}
{"type":"keep","no":1}
{"type":"keep","no":2}
{"type":"edit","no":3,"text":"<超过 165 的正文>","emo":"普通"}
{"type":"continue","no":4}
```

**期望 plan 形状**

```json
{"mute":false,"resume":4,"steps":[
  {"n":1,"kind":"keep"},
  {"n":2,"kind":"keep"},
  {"n":3,"kind":"edit","lines":[
    {"text":"<段 0>","emotion":"普通","split":{"index":0,"count":2}},
    {"text":"<段 1>","emotion":"普通","split":{"index":1,"count":2}}
  ]}
]}
```

**期望 Host**

- 播放 `n:3` 时，段 0 输入暂锁，段 1 开始显示即恢复；任务 plan 内的 `add` 若同样被 165 拆分，也按段暂锁。
- 播放序列：`add` → 原文 1（keep）→ 原文 2（keep）→ 改写 3 段 0/段 1（edit）→ 原文 4（resume=4）。
- 段 0、段 1 各按一条播放行计入已播；原第 3 条不再出现在下一轮剩余列表。
- 播完段 1 后从 `resume=4` 接回原第 4 条；组末 finish 仍用原始 finalIndex。
- 模型也可把同一条拆成连续两条 `edit no=3`（每条都带 `text`+`emo`）；后端合并为同一 step 的多段 `lines`。若各段本身 ≤165，则不带 `split` 标记，Host 按自然多行逐段播放；连续 `edit` 之间插入 `add` 会打断合并，后续重复 `edit no=3` 按重复编号忽略并记日志。

---

### F-06 任务 `remove` 与跳号

**假 LLM 原文**

```jsonl
{"type":"add","no":0,"text":"这事不好办。","emo":"普通"}
{"type":"keep","no":1}
{"type":"remove","no":2}
{"type":"continue","no":3}
```

**期望 SSE（顺序）**

```text
event: status
data: {"stage":"thinking"}

event: line
data: {"kind":"add","text":"这事不好办。","emotion":"普通","speaker":"Andy Law","seq":0}

event: plan
data: {"mute":false,"resume":3,"steps":[
  {"n":1,"kind":"keep"},
  {"n":2,"kind":"remove"}
]}

event: done
data: {"dialogue_instance_id":"22222222-2222-4222-8222-222222222222","session_id":"<同上>","usage":{}}
```

**期望**

- 播放：`add` → 原文 1（keep）→ 跳过原文 2（remove）→ 从 `resume=3` 接回 3、4。
- 若玩家在 `add` 播放中插话、`plan` 尚未应用：原剩余 2 仍在下一轮剩余列表；已收未应用的 plan 转参考续写，`keep` 不产生参考，`remove n=2` 折算为下一轮 `remaining` 的 `{"kind":"remove","index":2}`。
- 只有播放进度真正越过原剩余 2 后，它才从剩余列表消失（已应用但未越过的 remove 继续作为参考）。
- session 不记录被 remove 且未播放的原台词。

**边界：跳过原编号**

模型漏写编号时，后端补 `remove` 并记日志（`原编号未提及，按 remove 兜底`），不整段打回：

```jsonl
{"type":"keep","no":1}
{"type":"edit","no":3,"text":"只改第 3 条","emo":"普通"}
{"type":"continue","no":4}
```

```json
{"mute":false,"resume":4,"steps":[
  {"n":1,"kind":"keep"},
  {"n":2,"kind":"remove"},
  {"n":3,"kind":"edit","lines":[{"text":"只改第 3 条","emotion":"普通"}]}
]}
```

Host 播放：原文 1 → 跳过原文 2 → 改写 3 → 原文 4；没有前缀 `add` 时事件只有 `status`/`plan`/`done`，仅凭完整 `plan` 也算成功轮。

---

### F-07 任务 `keep` 与缺终止符

**假 LLM 原文**

```jsonl
{"type":"add","no":0,"text":"……","emo":"普通"}
{"type":"keep","no":1}
{"type":"keep","no":2}
{"type":"edit","no":3,"text":"清单就压在柜台底下。","emo":"普通"}
{"type":"continue","no":4}
```

**期望 plan**

```json
{"mute":false,"resume":4,"steps":[
  {"n":1,"kind":"keep"},
  {"n":2,"kind":"keep"},
  {"n":3,"kind":"edit","lines":[{"text":"清单就压在柜台底下。","emotion":"普通"}]}
]}
```

**期望**

- 原编号 1、2 用显式 `keep` 保留，按输出顺序进入 `steps`；不得再把未提及项当作“隐含保留”。
- 播放：`add` → 原文 1（keep）→ 原文 2（keep）→ 改写 3（edit）→ 原文 4（resume=4）。

**边界：缺终止符**

没有 `continue`/`end` 时按兜底继续，不整段打回：

```jsonl
{"type":"keep","no":1}
{"type":"edit","no":2,"text":"合法","emo":"普通"}
```

```json
{"mute":false,"resume":3,"steps":[
  {"n":1,"kind":"keep"},
  {"n":2,"kind":"edit","lines":[{"text":"合法","emotion":"普通"}]}
]}
```

- `resume=3`＝从最后处理的原编号之后保留原文；后端记 `fallback_continue` 与“缺少 continue/end”日志。
- 若整轮只有前缀 `add`、没有处理任何原编号，则 `resume=1`、`steps=[]`，保留全部原文。
- `continue` 编号非法（≤已处理编号或越界）同样按最后处理编号之后接回，并记录日志；不会因此吞掉后续原文。

---

### F-08 任务 `end` 整组收束

**假 LLM 原文**

```jsonl
{"type":"add","no":0,"text":"……","emo":"普通"}
{"type":"edit","no":1,"text":"这事我只跟你说一遍。","emo":"普通"}
{"type":"remove","no":2}
{"type":"remove","no":3}
{"type":"remove","no":4}
{"type":"end"}
```

**期望 plan**

```json
{"mute":false,"resume":5,"steps":[
  {"n":1,"kind":"edit","lines":[{"text":"这事我只跟你说一遍。","emotion":"普通"}]},
  {"n":2,"kind":"remove"},
  {"n":3,"kind":"remove"},
  {"n":4,"kind":"remove"}
]}
```

**期望**

- 播放：`add` → 改写 1；不播放原剩余 2、3、4，也不接回原文。
- `end` 不再保留未处理原文；模型漏写的原编号由后端补 `remove`（此例已显式写全）。
- 组在 `steps` 播完后结束；finish 仍用 AS2 原始最后一行的 `finalIndex`。
- `resume=5=N+1`：Host 放弃原尾部，下一轮 `remaining` 为空；未播原文 2、3、4 不再转参考续写。
- 若 plan 已应用而玩家在 `add` 播放中插话：尚未播放的改写 1 也因原编号已不存在而丢弃（Host 记日志），下一轮 `reference_continuation` 为空。
- session 只记录实际播放的 `add` 与改写 1；未播放的原文不落库。

---

### F-09 任务 `mute`

**假 LLM 原文**

```jsonl
{"type":"mute"}
{"type":"add","no":0,"text":"行了，这事不用你操心。","emo":"普通"}
{"type":"continue","no":1}
```

**期望 SSE**

```text
event: status
data: {"stage":"thinking"}

event: mute
data: {"mute":true}

event: line
data: {"kind":"add","text":"行了，这事不用你操心。","emotion":"普通","speaker":"Andy Law","seq":0}

event: plan
data: {"mute":true,"resume":1,"steps":[]}

event: done
data: {"dialogue_instance_id":"22222222-2222-4222-8222-222222222222","session_id":"<同上>","usage":{}}
```

**期望 Host**

- `mute` 事件先到；首句 `add` 用 NPC 口吻无视、打断或化解玩家的话，然后从 `resume=1` 接回原剩余 1..4。
- 本组后续输入禁用并显示“（NPC名）暂时不打算让你插话”；组结束/关闭后重置。
- 禁言是任务模式唯一的整组锁；不影响任务状态机，不写持久数据。

**期望后端**

- `mute` 可选且缺省 false；契约要求它必须是整个输出的第一行，解析器遇到该行即推 `mute` 事件，`plan.mute=true`。
- 不得因为禁言而丢弃 `add`/`continue`；`plan.steps=[]` 表示原剩余全部按 `resume=1` 保留。
- 只有 `mute` 的控制行也属于有效输出（不触发 `no_valid_lines`）；`valid_lines` 不计 `mute`，此例 add 计 1。

---

### F-10 零有效

**假 LLM 原文（示意）**

```text
{"add":"未闭合
[1,2,3]
```

**期望**

- 带 JSON 特征但无法解析的坏行仍记录并跳过；零条有效时后端可做**一次**修复性重试（把原输出/错误位置给模型，要求只重发 JSONL）。
- 重试仍零条有效：`error`，`code="no_valid_lines"`，`valid_lines=0`；不发 `line`/`plan`/`done`。
- 注意：完全无 JSON 特征的裸台词自 2026-10-22 起按 `add` 兜底接收（情绪留空），不再属于零有效。
- 任务模式只要解析出任意控制操作（如 `mute`/`keep`/`continue`/`end`），本轮就不是“零有效输出”，会正常发 `plan`；此时 `valid_lines` 可能为 0，但不触发 `no_valid_lines`。
- Host：本次 `$PC` 已播并保留在 session；不播任何额外 NPC 台词；无视这次玩家说话，直接回原对话当前点继续（日常同样）。
- 原对话已到末尾则正常结束。
- 不得写入覆盖层；不得把修复重试的中间文本当台词。

---

### F-11 部分有效后流中断

**假 LLM 原文**

```jsonl
{"add":"你先听我说。","emo":"普通"}
```

随后连接中断/畸形事件。

**期望 SSE（日常）**

```text
event: status
data: {"stage":"thinking"}

event: line
data: {"kind":"add","text":"你先听我说。","emotion":"普通","speaker":"Andy Law","seq":0}

event: error
data: {"code":"stream_failed","message":"…","valid_lines":1}
```

**期望 Host**

- 已收到的 `add` 照常播放；不得补写、不重试整段。
- 日常：播完已收 `add` 后回原对话剩余部分继续。
- 任务模式：没有完整 `plan` 就不应用任何改写，播完已收 `add` 后回原对话当前点继续。
- session：已播 `add` 保留；未收到的内容不落库；`$PC` 已播保留。

**期望后端**

- 部分有效不推不完整 `plan`；已推 `line` 保留。
- 客户端断开/流失败时取消 LLM/工具；不得在 `error` 后继续写 AI 消息。

**任务模式变体：只收到改写后断流**

```jsonl
{"type":"edit","no":1,"text":"改写到一半","emo":"普通"}
```

```text
event: status
data: {"stage":"thinking"}

event: error
data: {"code":"stream_failed","message":"…","valid_lines":1}
```

- 任务 `edit` 不即时推 `line`，只计 `valid_lines`；没有完整 `plan`，Host 不应用该改写，也不补台词。
- Host 停在本轮 `$PC`，失败收尾后回原对话当前点；原剩余 1..N 不变。
- `mute`/`keep`/`remove`/`continue`/`end` 是控制操作，不计入 `valid_lines`。

---

### F-12 关闭/取消

**场景 A：日常播放中关闭**

- Host 已播 `$PC` 与 `add0`；`add1`/`closing` 未播，流未结束。
- Host 关闭对话 UI：真取消在途请求，发 finalize，transcript 含原作已播、两轮 `$PC`、`add0`。
- 期望：`add1`/`closing` 不落库；session 无孤儿；输入 UI 复位；再次打开同组是新 session（新 `dialogue_instance_id`）。
- finalize 回执：`{ok:true,dialogue_instance_id,session_id,appended,total}`；重复调用 `appended=0`、`total` 不变。

**场景 B：任务播放中提前关闭**

- Host 用 `close` 结束；`finalIndex` 取当前播放点已到达的最大原始行号（增强行不推进），钳在 `[0, wireRowCount-1]`。
- Host 一进入 closing（含组末 `advance_past_end`）就取消在途插话并 finalize，不等待后续 hide；已收到未插入的台词不再进本组。
- 期望：任务前 `AddTask` 已先于对话、任务后奖励已先于 finish_conversation，提前关闭不破坏任务状态。
- 不得用 `advance_past_end` 冒充提前关闭；组末才用原始最后一行 `finalIndex`。
- finalize 仍按实际已播 transcript 对账；未播改写/新增不落库；响应形状同场景 A。

---

### F-13 赠送精确名成功

**请求（关键字段）**

```json
{
  "mode": "daily",
  "dialogue_instance_id": "11111111-1111-4111-8111-111111111111",
  "turn_id": "dddddddd-dddd-4ddd-8ddd-dddddddddddd",
  "npc": "Andy Law",
  "player_input": "你要是手头宽裕，送我点药呗。",
  "dialogue": {"kind": "daily", "group_id": "daily_andy_items", "played": [], "remaining": [], "reference_continuation": []},
  "task_context": null,
  "limits": {"line_hard_max": 165, "line_prompt_max": 135}
}
```

**工具轮（假 LLM）**

```text
tool_call: give_item_to_player({"name":"普通hp药剂","quantity":3,"keyword":"","instruction":""})
```

池命中精确名；单价 250，阶段 1、好感 40 → 上限 30000，总价 750 通过；实际数量 3。

**期望 SSE（第一轮）**

```text
event: status
data: {"stage":"thinking"}

event: action
data: {"action_id":"<uuid>","kind":"item_grant","npc":"Andy Law","item_name":"普通hp药剂","quantity":3,"requested_quantity":3}

（Host 执行 AS2 成功并 POST action-result；后端继续）

event: line
data: {"kind":"add","text":"拿着，别浪费。","emotion":"普通","speaker":"Andy Law","seq":0}

event: done
data: {"dialogue_instance_id":"11111111-1111-4111-8111-111111111111","session_id":"<新 id>","usage":{}}
```

**期望 Host**

- 收到 `action` 后调 AS2 `npcItemGrant`，成功才回执；回执前不把“已赠送”当已发生。
- AS2 成功后左下消息显示“Andy Law赠送了你3个普通hp药剂”。
- 最终台词在回执成功后才上屏；若 AS2 失败/回执超时，不显示“已赠送”，按失败拒绝。

**期望后端**

- 工具结果成功：`已成功赠送 3 个普通hp药剂`；账本 `give/普通hp药剂 +3`；本组明细 `第1轮：3个普通hp药剂`。
- 同一 action_id 重复回执只生效一次。

---

### F-14 赠送超量自动降量

**工具轮**

```text
tool_call: give_item_to_player({"name":"普通hp药剂","quantity":200,"keyword":"","instruction":""})
```

单价 250，上限 30000 → 200×250=50000 超限；降为 `30000//250=120`。若物品为金币，50000 → 30000（已按 500 取整）。

**期望 SSE**

- `action.quantity=120`，`requested_quantity=200`；最终台词只能说 120 个，并说明“多了拿不了/只给这些”。
- 账本/本组明细记 120，不记 200。

**期望后端**

- 工具结果：`已成功赠送 120 个普通hp药剂（原请求 200，因价值上限调整）`。
- 金币/经验值降量后再 `//500*500`；降到 0 走 F-15。

---

### F-15 赠送 1 个都超限

**工具轮**

```text
tool_call: give_item_to_player({"name":"测试物品-单价超上限","quantity":1,...})
```

测试物品单价 40000 > 阶段 1 上限 30000。

**期望 SSE**

- 不发 `action`；工具结果为 `你选择了赠送测试物品-单价超上限，因价值过高，赠送失败。`
- 最终 LLM 只输出角色化的拒绝台词（如“这我可给不起。”），不得说已送。
- 账本/本组明细不变。

**期望 Host/后端**

- Host 不执行 AS2；后端不记账；日志记录 `gift_value_exceeded` 与实际单价/上限。

---

### F-16 索取精确名 + 点赠送

**第一轮请求**：同 F-13，`player_input` 改为“我这儿有些药，你要吗？”；工具轮：

```text
tool_call: request_item_from_player({"name":"普通hp药剂","quantity":2,"keyword":"","instruction":""})
```

**期望 SSE（第一轮）**

```text
event: status
data: {"stage":"thinking"}

event: item_claim
data: {"state":"pending","claim_id":"<uuid>","npc":"Andy Law","item_name":"普通hp药剂","quantity":2}

event: line
data: {"kind":"add","text":"行，给我两瓶。","emotion":"普通","speaker":"Andy Law","seq":0}

event: done
```

**期望 Host（第一轮）**

- 收到 claim 后查 AS2 持有：假设背包 5 瓶 → 按钮“赠送2个普通hp药剂（当前持有5）”可用，“不赠送”可用；输入框保持“说点什么…”。
- 两按钮在本轮最后一条 add 上显示；claim 跨轮保留。

**玩家点“赠送”**

- Host 先调 AS2 `npcItemTake` 扣 2 瓶（金币则扣金币）；成功后才发第二轮请求：

```json
{
  "mode": "daily",
  "turn_id": "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee",
  "player_input": "【赠送2个普通hp药剂 给Andy Law】",
  "action": {"kind":"item_take_accept","action_id":"<uuid>","claim_id":"<uuid>","item_name":"普通hp药剂","quantity":2}
}
```

**期望 SSE（第二轮）**

```text
event: item_claim
data: {"state":"closed","claim_id":"<uuid>","npc":"Andy Law","item_name":"普通hp药剂","quantity":2}

event: line
data: {"kind":"add","text":"算你识相。","emotion":"普通","speaker":"Andy Law","seq":0}

event: done
```

**期望后端**

- 校验 claim 匹配；账本 `receive/普通hp药剂 +2`；清 claim；最终 LLM 看到“玩家已经把2个普通hp药剂交给了你”，并附物品信息块。
- 第一轮索取工具结果原文：`你现在要索取物品：2个普通hp药剂，该物品确认有效，可以索取。现在，请用符合你身份且符合上下文的语句，向玩家索要物品或询问玩家是否要把该物品给你。`（后附物品信息块）
- 扣除失败：不发成功 action，不记账；Host 提示失败，claim 保留或按失败矩阵关闭，模型按失败回应。

---

### F-17 索取子 Agent 再查一次

**工具轮**

```text
tool_call: request_item_from_player({"name":"","quantity":1,"keyword":"治疗","instruction":"能回血的消耗品"})
```

**解析**

- 关键词“治疗”在索取池无命中；抽选 10–20 条，索取池抽选**金币固定第一位**；附本轮候选之外剩余池的分类计数（武器/防具/消耗品/材料/其他/金币）与有效池总数。
- 子 Agent 第一轮返回 `{"action":"search","keyword":"药剂"}`；后端只再查一次，得“普通hp药剂”等候选。
- 子 Agent 第二轮返回 `{"action":"pick","name":"普通hp药剂"}`。

**期望**

- 只发一次 `search`；第二轮不再允许 search；返回名必须命中索取池。
- 成功后走 F-16 的 claim 流程；找不到则 `item_claim` 不出现，工具结果告诉模型“无法索取”。

---

### F-18 索取拒绝/取消

**场景 A：玩家点“不赠送”**

- Host 发 `action.kind=item_take_decline`，`player_input="【不赠送】"`。
- 后端清 claim、发 `item_claim(closed)`、不记账；最终 LLM 看到“玩家拒绝赠送”，只回应，不再弹选项。

**场景 B：玩家打字“不行”，模型取消**

- 请求不带 action；prompt 带 pending claim 块。
- 模型工具轮调用 `cancel_item_request()`；后端清 claim、发 `item_claim(closed)`，工具结果“索取已取消”；最终 LLM 正常回话。
- 账本不变；最近拒绝信息保留 2–3 轮。

---

### F-19 任务接受直连

**请求（关键字段）**

```json
{
  "mode": "task",
  "dialogue_instance_id": "22222222-2222-4222-8222-222222222222",
  "turn_id": "ffffffff-ffff-4fff-8fff-ffffffffffff",
  "npc": "Andy Law",
  "player_input": "我接了",
  "dialogue": {"kind": "task_pre", "group_id": "task_text_key", "played": [], "remaining": [], "reference_continuation": []},
  "task_context": {"completed": null, "upcoming": {"task_id": 200124, "title": "…", "npc": "Andy Law", "objectives": ["…"], "rewards": ["…"]}},
  "action": {"kind": "task_accept", "action_id": "<uuid>"}
}
```

**期望**

- 后端在进入 LLM 前执行现有 `_run_confirm`；不注册 `route_task_confirm`，不产生路由轮。
- 发布成功：结果块“这份委托已经正式派给玩家了”；最终 LLM 只输出 `type=add` 的确认台词，并以 `end` 收束（`remaining` 为空，无原剩余可保留）。
- 发布失败：结果块说明失败；模型正常回应（仍按任务 JSONL `type/no/text`）；Host 本轮不再重复弹“我接了/我不接”。
- 只对插话输入条生效；终端手打“我接了”仍走原链路。

---

### F-20 装备索取与强化度

**场景**

- 日常插话，NPC 索取 `M4A1`，数量 1。
- 玩家持有：穿戴中 `M4A1` +10；背包内 `M4A1` +2、`M4A1` +6。
- 可索取只看背包：Y=2，最低强化度 Z=2；穿戴中的 +10 不参与，也不会被扣。

**第一轮 claim 与选项**

```text
event: item_claim
data: {"state":"pending","claim_id":"<uuid>","npc":"Andy Law","item_name":"M4A1","quantity":1}
```

- Host 按钮：`赠送 1 个 M4A1 （当前持有2个;强化度为2）`，可用；`不赠送` 可用；输入框保持“说点什么…”。
- 若背包最低强化度为 1（未强化），按钮退回 `赠送1个M4A1（当前持有1）`，不显示强化度。

**玩家点赠送**

- Host 重新查询背包，扣掉 +2 那一件（不是穿戴中的 +10，也不是 +6），成功后发：

```json
{
  "action": {"kind":"item_take_accept","action_id":"<uuid>","claim_id":"<uuid>","item_name":"M4A1","quantity":1,"item_level":2}
}
```

**期望后端**

- 校验 claim 与数量（装备固定 1）；账本 `receive/M4A1 +1`，不记强化度；清 claim；发 `item_claim(closed)`。
- 最终 LLM 看到：`玩家把 1 个 M4A1（强化度2，经过了一定幅度的强化）交给了你`，附物品信息块；最近成功块保留 2–3 轮同样信息。
- 描述分档：Z<5 `经过了一定幅度的强化`；5≤Z≤8 `经过了较高成本的强化`；Z≥9 `经过了极高成本的强化`；Z≤1 不加强化度与描述。

**失败边界**

- 点击时背包已无该装备、只剩穿戴中、或扣除失败：按“持有不足/扣除失败”处理，不记账、不说已收到，claim 保留或关闭，模型按失败回应。
- 装备数量固定 1；模型请求多件时按 1 件处理并在工具结果说明。

---

## 4. 期望结果表

### 4.1 输入可用性

| Fixture | 输入可用状态 |
|---|---|
| F-01 | `add0`/`add1`/`closing` 各自开始显示即可用 |
| F-02 | 段 0 暂锁；段 1 开始显示恢复；`closing` 开始显示可用 |
| F-03 | 草案生成中禁用“（正在准备…）”；最终 `add0` 开始显示恢复 |
| F-04 | `add0` 开始显示可用；发送即补全并取消；Turn B 各句开始显示可用 |
| F-05/F-06/F-07/F-08 | 任务每个 step（新增/改写/保留原文）开始显示即可用 |
| F-05b | 改写段 0 暂锁；段 1 开始显示恢复 |
| F-09 | 本组后续禁用并显示禁言提示 |
| F-10/F-11 | 回原对话后随原对话解锁；任务断流无 AI 行时直接回当前点 |
| F-12 | 关闭后复位；再次打开为新会话 |

### 4.2 播放/计划

| Fixture | 顺序/结果 |
|---|---|
| F-01 | add→add→closing |
| F-02 | 段0→段1→closing（拼接等于原文） |
| F-03 | 草案完成后 add→add→closing，无过渡台词 |
| F-04 | Turn A 只播 add0；Turn B 播 add→closing；add1/closing 不播 |
| F-05 | add→原文1（keep）→改写2→原文3→原文4（resume=3） |
| F-05b | add→原文1→原文2→改写3段0→段1→原文4（resume=4） |
| F-06 | add→原文1→跳过2→原文3→原文4；跳号例：原文1→跳过2→改写3→原文4 |
| F-07 | add→原文1→原文2→改写3→原文4；缺终止符例：原文1→改写2→原文3→原文4 |
| F-08 | add→改写1，结束（显式 remove 2/3/4；resume=5，下一轮 remaining 空） |
| F-09 | mute→add→原文1.. |
| F-10 | 无 AI 行，回原对话 |
| F-11 | add0→回原对话当前点；任务 edit 断流：无 AI 行→回当前点 |
| F-12 | 关闭；未播不写 |

### 4.3 session/finalize

| 场景 | 期望 |
|---|---|
| 首次插入 | 创建 session，种入首次插入前已播原作；`$PC` 作为 user |
| 后续轮 | 复用同一 `dialogue_instance_id`；不重复写相同 `seq` |
| 其他 NPC 原作 | user，`【NPC名：台词】` |
| 当前 NPC 原作/改写/AI | assistant |
| 未播 add/closing/edit/remove | 不写 |
| 已收未应用 plan | 转 `reference_continuation`：add/edit/remove 按 steps 顺序，keep 不产生；未播编号按下一轮 remaining 折算 |
| `resume=N+1` | 放弃原尾部；下一轮 remaining 为空，未播 edit/remove 不再折算参考 |
| 取消/关闭 | finalize 以已播 transcript 幂等收尾 |
| 每轮结束 | 允许 best-effort finalize；transcript 为前缀，后端按 seq 幂等追加 |
| 重复 finalize | 幂等，不重复追加 |
| 进入 closing | 立即取消在途流并 finalize；closing 中不再接受插话 |
| 新组重播（日常） | 新 `dialogue_instance_id`＝新 session |

### 4.4 finalize 样例（F-01 关闭时）

```json
{
  "dialogue_instance_id": "11111111-1111-4111-8111-111111111111",
  "turn_id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
  "transcript": [
    {"seq": 0, "role": "npc", "name": "Andy Law", "text": "又是你。", "emotion": "普通"},
    {"seq": 1, "role": "player", "name": "$PC", "text": "最近怎么样？"},
    {"seq": 2, "role": "ai", "name": "Andy Law", "text": "还能怎么样，老样子。", "emotion": "普通"},
    {"seq": 3, "role": "ai", "name": "Andy Law", "text": "你倒是难得过来一趟。", "emotion": "普通"},
    {"seq": 4, "role": "ai", "name": "Andy Law", "text": "说吧，想聊什么？", "emotion": "普通"}
  ]
}
```

- `transcript` 是全量已播行；`seq` 唯一且顺序稳定。
- 后端以它为准覆盖/对齐 session 消息；未播内容不得出现在 session。

---

## 5. 两侧自测入口

### 5.1 后端

- 假 LLM：按 §3 原文逐行 yield；记录每行完成时间，断言首条有效 `line` 早于 `done`/`plan`。
- 解析器：JSONL 围栏/非 JSON/括号剥离/165 拆分/`split`/情绪回落；任务 `type/no/text`、`mute` 首行、`add no=0`、`edit`/`keep`/`remove`/`continue` 的 `no`、越界编号记录后跳过。
- 计划：F-05/F-05b/F-06/F-07/F-08/F-09 的 `mute`/`resume`/`steps` 逐字段断言；跳号补 `remove`、缺终止符/非法 `continue` 兜底、`n`/`resume` 越界宽容、终止符后的内容忽略。
- SSE：事件顺序、`seq`、`split`、`mute` 先于 `line`、`done`/`error`；失败/部分断流无 `plan`；`valid_lines` 只计 `add`/`edit`（日常 `add`/`closing`）。
- session：F-01/F-04/F-12 的创建、复用、幂等 finalize、未播不写。
- 以上全部离线；不调用真实模型、不写生产数据目录（用临时 data root）。

### 5.2 游戏侧

- 假 SSE：按 §3 事件注入 Host SSE 客户端；断言播放顺序、输入可用/暂锁/禁言、取消、finish/finalize。
- Native 会话：本地追加行不改 `WireRowCount`；组末 `finalIndex` 用 AS2 原始最后一行；提前关闭用 `close`。
- 任务 plan：F-05/F-05b/F-06/F-07/F-08 按 `steps` 顺序应用；`resume` 前未覆盖编号按 `remove`；`resume` 缺失/越界从 1 接回；`resume=N+1` 放弃尾部（下一轮 `remaining` 空）。
- 参考续写：已收未应用 plan 转 `reference_continuation`（add/edit/remove 有序、keep 不产生、未播编号折算）；原尾部已放弃时丢弃 edit/remove。
- 输入控件：先做 G0-1 spike；IME、Enter、焦点、点击不误触。
- 以上不要求真模型；真机 IME 与视觉属于 P5/作者验收。

---

## 6. 变更控制

- 本文与《协议》已冻结。任何字段/语义变更：先改《协议》与本文，再改两侧实现；不得只改一侧。
- 任务协议 2026-10-29 的整批修订（后端 `80c895f` / Host `c5f90a0779`）已同步到本文；后续语义变更仍按上一句的顺序执行。
- 发现 fixture 与协议冲突：停下来报告，不修改 fixture 迁就实现。
- 新增 fixture 只能追加编号；既有编号的语义变更必须随协议修订整批同步本文与两侧断言，不得只改字段名或只改一侧。
