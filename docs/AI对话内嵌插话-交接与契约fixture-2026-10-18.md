# AI 对话内嵌插话 · 交接与契约 fixture

**文档角色**：游戏侧与后端侧共用的冻结样例与期望结果表。协议真源＝《AI对话内嵌插话-需求与协议-2026-10-18.md》（下称《协议》）；本文只把协议落成可执行的请求、SSE、JSONL 与期望行为，不另立语义。
**冻结基线**：游戏仓 `83d55803ca`（协议/计划），后端仓 `4f2248a`（实施指引），2026-10-18。
**使用方式**：
- 后端窗口：用假 LLM 按 §2 的 JSONL 原文回放，断言 §3 的 SSE 顺序与形状，再断言 §4 的 plan/session。
- 游戏窗口：把 §3 的 SSE 序列注入 Host SSE 客户端，断言 §4 的播放序列、输入可用状态、finish/finalize。
- 两侧都不得修改 fixture 来迁就实现；协议与 fixture 冲突时以《协议》为准，停下来报告，不单边改字段。
- fixture 测试不调用真模型；真模型走查属于 P5，单独记录。

---

## 1. 公共约定

- 时序：文中延迟只是示意；规范的是事件顺序与“首句/首段早于 done/plan”。
- `status` 可选；测试不得依赖其数量或文案。若发送，`stage ∈ {connecting, thinking, searching, drafting, waiting}`。
- `line.seq`：每个 turn 从 0 开始单调递增；一个 turn 内不重复。`played[].seq`：同一 session 内不重复。
- `split`：仅当一条模型正文被 165 硬上限拆成多段时出现；`index` 从 0 起，`count` 为总段数。自然多行不带。
- 情绪统一用“普通”，避免依赖具体 NPC 白名单；真模型走查再验证真实情绪。
- 请求中 `remaining[].index` 与 `reference_continuation[].index` 固定为 **1..N**，与模型 `n` 同口径；Host 负责与原始绝对行号互转。
- `dialogue.kind ∈ {daily, task_pre, task_post}`，且与 `mode` 匹配。
- `reference_continuation[].kind ∈ {add, closing, edit, remove}`；日常未播的结束语用 `closing`。
- 任务 `end` 是原始剩余编号 1..N；缺省＝不接回原文，本轮新增＋改写构成剩余整组。
- 请求 `played` 只含本轮玩家发送之前已播出的行；本轮 `$PC` 由 `player_input` 表示，由 finalize 按实际播放写入，不得在 `played` 与 `player_input` 中重复。
- session 只记录真正播放过的行；拆分产生的多段按播放顺序各记一条 assistant，不合并。
- `finalize.transcript` 是该 session 截至当时的全部已播行（含历轮），行结构与请求 `played` 相同；未出现在其中的未播内容不落库。
- Host 对 mutation 的 ack 若带 `rowCount`，只能是 wire 行数；本地增强行数不得回传。
- `close` 的 `finalIndex` 取当前播放点已到达的最大原始行号（增强行不推进），钳在 `[0, wireRowCount-1]`。
- `finalize` 成功响应固定为 `{ok:true,dialogue_instance_id,session_id,appended,total}`；未知 session 且 transcript 为空时 `ok:false`、`session_id:""`。
- `error.valid_lines` 按模型输出行计、拆分前（add/closing/任务 line），`mute` 不计。
- `reference_continuation` 的 edit/remove index 越界（不在当前 1..N）＝非法请求，后端 422。
- 真取消＝Host 关闭 SSE 连接，不存在独立 cancel 端点；后端断开即取消 LLM/工具，Host 随后 finalize。
- fixture 中固定假 UUID 仅用于断言；真实 Host 使用自己的 UUID。

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
| F-05 | 任务 `end` 接回 | 原编号 1..N、edit、`end`、组末原 finalIndex |
| F-05b | 任务改写拆分 | plan 内 `lines[].split`、任务输入暂锁例外 |
| F-06 | 任务 `remove` | 删除未播仍留剩余、越过才消失 |
| F-07 | 任务 `nochange` 缺失 | `end` 前未提及＝nochange（宽容） |
| F-08 | 任务整组替换 | 无 `end`、原剩余不再播放 |
| F-09 | 任务 `mute` | `mute` 事件、首句化解、本组后续禁言 |
| F-10 | 零有效 | 修复重试一次、仍零→`error`、回原对话 |
| F-11 | 部分有效后流断 | 已播保留、无 plan、回原对话当前点 |
| F-12 | 关闭/取消 | 真取消、未播不落库、finalize 按已播收尾 |

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
2. 草案就绪后，才输出以下 JSONL：

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

（草案生成期间不得出现任何 line；不得出现“我去准备一下”之类过渡台词）

event: line
data: {"kind":"add","text":"行，那我直说了。","emotion":"普通","speaker":"Andy Law","seq":0}

event: line
data: {"kind":"add","text":"城西的补给线断了，我需要有人去看一眼，顺便把货带回来。","emotion":"普通","speaker":"Andy Law","seq":1}

event: line
data: {"kind":"closing","text":"接不接，你自己想清楚。","emotion":"普通","speaker":"Andy Law","seq":2}

event: done
data: {"dialogue_instance_id":"11111111-1111-4111-8111-111111111111","session_id":"<同上>","usage":{}}
```

**期望 Host / 后端**

- 草案生成期间输入锁定并显示“（正在准备…）”；最终对话第一句开始显示才恢复可用。
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

### F-05 任务 `end` 接回

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
{"add":"你倒是爽快。","emo":"普通"}
{"n":2,"line":"北边仓库昨晚丢了一批货。","emo":"普通"}
{"end":3}
```

**期望 SSE**

```text
event: line
data: {"kind":"add","text":"你倒是爽快。","emotion":"普通","speaker":"Andy Law","seq":0}

event: plan
data: {"mute":false,"end":3,"edits":[
  {"n":2,"kind":"edit","lines":[{"text":"北边仓库昨晚丢了一批货。","emotion":"普通"}]}
]}

event: done
data: {"dialogue_instance_id":"22222222-2222-4222-8222-222222222222","session_id":"<新 id>","usage":{}}
```

**期望 Host 播放序列**

1. `add`：“你倒是爽快。”
2. 原剩余 1：原文“你先别急着答应。”
3. 原剩余 2：改写“北边仓库昨晚丢了一批货。”
4. 从 `end=3` 接回原剩余 3、4 原文。
5. 每句开始显示即可输入（禁言除外）；组末点击“下一条”关闭。
6. 组末 finish 用 **AS2 原始最后一行的 finalIndex**，不是增强行数；AS2 `advance_past_end` 校验通过。

**期望后端**

- `end=3` 按相对编号映射；`n=1` 未提及且在 `end` 前 → nochange。
- 计划完整才发 `plan`；`add` 可以先于 `plan` 推送。
- session：`$PC`=user；`add`=assistant；原剩余 1=assistant；改写 2=assistant（保留原说话人）；接回的 3、4 按实际播放追加。

---

### F-05b 任务改写拆分

**假 LLM 原文**：在 F-05 基础上，把 `n:3` 的改写写成一条超过 165 的正文（`end=4`，被改写的条目必须在 `end` 之前）。

```jsonl
{"add":"你倒是爽快。","emo":"普通"}
{"n":3,"line":"<超过 165 的正文>","emo":"普通"}
{"end":4}
```

**期望 plan 形状**

```json
{"mute":false,"end":4,"edits":[
  {"n":3,"kind":"edit","lines":[
    {"text":"<段 0>","emotion":"普通","split":{"index":0,"count":2}},
    {"text":"<段 1>","emotion":"普通","split":{"index":1,"count":2}}
  ]}
]}
```

**期望 Host**

- 播放 `n:3` 时，段 0 输入暂锁，段 1 开始显示即恢复；这是任务模式唯一的逐段暂锁。
- 段 0、段 1 各按一条播放行计入已播；原第 3 条不再出现在下一轮剩余列表。
- 播完段 1 后从 `end=4` 接回原第 4 条；组末 finish 仍用原始 finalIndex。

---

### F-06 任务 `remove`

**假 LLM 原文**

```jsonl
{"add":"这事不好办。","emo":"普通"}
{"n":2,"remove":true}
{"end":3}
```

**期望 plan**

```json
{"mute":false,"end":3,"edits":[{"n":2,"kind":"remove"}]}
```

**期望**

- 播放：`add` → 原剩余 1 原文 → 跳过原剩余 2 → 从 `end=3` 接回 3、4。
- 若玩家在 `add` 播放中插话、`plan` 尚未应用：原剩余 2 仍在下一轮剩余列表；`remove` 意图只进参考续写。
- 只有播放进度真正越过原剩余 2 后，它才从剩余列表消失。
- session 不记录被 remove 且未播放的原台词。

---

### F-07 任务 `nochange` 缺失

**假 LLM 原文**

```jsonl
{"add":"……","emo":"普通"}
{"n":3,"line":"清单就压在柜台底下。","emo":"普通"}
{"end":4}
```

**期望 plan**

```json
{"mute":false,"end":4,"edits":[
  {"n":3,"kind":"edit","lines":[{"text":"清单就压在柜台底下。","emotion":"普通"}]}
]}
```

**期望**

- `end` 之前未提及的 `n=1`、`n=2` 按 nochange 处理，不得当作 remove。
- 播放：`add` → 原文 1、2 → 改写 3 → `end=4` 接回原文 4。
- 后端只记录缺失项为隐含 nochange；不整段打回。

---

### F-08 任务整组替换（无 `end`）

**假 LLM 原文**

```jsonl
{"add":"……","emo":"普通"}
{"n":1,"line":"这事我只跟你说一遍。","emo":"普通"}
{"n":2,"remove":true}
```

**期望 plan**

```json
{"mute":false,"end":null,"edits":[
  {"n":1,"kind":"edit","lines":[{"text":"这事我只跟你说一遍。","emotion":"普通"}]},
  {"n":2,"kind":"remove"}
]}
```

**期望**

- 播放：`add` → 改写 1；不播放原剩余 3、4，也不接回原文。
- 组在增强序列播完后结束；finish 仍用 AS2 原始最后一行的 `finalIndex`。
- session 只记录实际播放的 `add` 与改写 1；未播放的原文 3、4 不落库。
- 下一轮剩余列表仍按原剩余中未越过的条目计算（若还有下一轮）。

---

### F-09 任务 `mute`

**假 LLM 原文**

```jsonl
{"mute":true}
{"add":"行了，这事不用你操心。","emo":"普通"}
{"end":1}
```

**期望 SSE**

```text
event: mute
data: {"mute":true}

event: line
data: {"kind":"add","text":"行了，这事不用你操心。","emotion":"普通","speaker":"Andy Law","seq":0}

event: plan
data: {"mute":true,"end":1,"edits":[]}

event: done
data: {"dialogue_instance_id":"22222222-2222-4222-8222-222222222222","session_id":"<同上>","usage":{}}
```

**期望 Host**

- `mute` 事件先到；首句 `add` 用 NPC 口吻无视/化解玩家的话，然后从原剩余 1 接回。
- 本组后续输入禁用并显示“（NPC名）暂时不打算让你插话”；组结束/关闭后重置。
- 禁言是任务模式唯一的整组锁；不影响任务状态机，不写持久数据。

**期望后端**

- `mute` 行最先解析并尽早推 `mute` 事件；`plan.mute=true`。
- 不得因为禁言而丢弃 `add`/`end`。

---

### F-10 零有效

**假 LLM 原文（示意）**

```text
好的，我明白了。玩家想和我聊天，我应该先安抚他，然后再……
（这里不是 JSONL）
```

**期望**

- 后端可做**一次**修复性重试（把原输出/错误位置给模型，要求只重发 JSONL）。
- 重试仍零条有效：`error`，`code="no_valid_lines"`，`valid_lines=0`；不发 `line`/`plan`/`done`。
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

**期望 SSE**

```text
event: line
data: {"kind":"add","text":"你先听我说。","emotion":"普通","speaker":"Andy Law","seq":0}

event: error
data: {"code":"stream_failed","message":"…","valid_lines":1}
```

**期望 Host**

- 已收到的 `add` 照常播放；不得补写、不重试整段。
- 任务模式：没有完整 `plan` 就不应用任何改写，播完已收 `add` 后回原对话当前点继续。
- 日常：播完已收 `add` 后回原对话剩余部分继续。
- session：已播 `add` 保留；未收到的内容不落库；`$PC` 已播保留。

**期望后端**

- 部分有效不推不完整 `plan`；已推 `line` 保留。
- 客户端断开/流失败时取消 LLM/工具；不得在 `error` 后继续写 AI 消息。

---

### F-12 关闭/取消

**场景 A：日常播放中关闭**

- Host 已播 `$PC` 与 `add0`；`add1`/`closing` 未播，流未结束。
- Host 关闭对话 UI：真取消在途请求，发 finalize，transcript 含原作已播、两轮 `$PC`、`add0`。
- 期望：`add1`/`closing` 不落库；session 无孤儿；输入 UI 复位；再次打开同组是新 session（新 `dialogue_instance_id`）。
- finalize 回执：`{ok:true,dialogue_instance_id,session_id,appended,total}`；重复调用 `appended=0`、`total` 不变。

**场景 B：任务播放中提前关闭**

- Host 用 `close` 结束；`finalIndex` 取当前播放点已到达的最大原始行号（增强行不推进），钳在 `[0, wireRowCount-1]`。
- 期望：任务前 `AddTask` 已先于对话、任务后奖励已先于 finish_conversation，提前关闭不破坏任务状态。
- 不得用 `advance_past_end` 冒充提前关闭；组末才用原始最后一行 `finalIndex`。
- finalize 仍按实际已播 transcript 对账；未播改写/新增不落库；响应形状同场景 A。

---

## 4. 期望结果表

### 4.1 输入可用性

| Fixture | 输入可用状态 |
|---|---|
| F-01 | `add0`/`add1`/`closing` 各自开始显示即可用 |
| F-02 | 段 0 暂锁；段 1 开始显示恢复；`closing` 开始显示可用 |
| F-03 | 草案生成中禁用“（正在准备…）”；最终 `add0` 开始显示恢复 |
| F-04 | `add0` 开始显示可用；发送即补全并取消；Turn B 各句开始显示可用 |
| F-05/F-06/F-07/F-08 | 任务每句（新增/改写/原文）开始显示即可用 |
| F-05b | 改写段 0 暂锁；段 1 开始显示恢复 |
| F-09 | 本组后续禁用并显示禁言提示 |
| F-10/F-11 | 回原对话后随原对话解锁 |
| F-12 | 关闭后复位；再次打开为新会话 |

### 4.2 播放/计划

| Fixture | 顺序/结果 |
|---|---|
| F-01 | add→add→closing |
| F-02 | 段0→段1→closing（拼接等于原文） |
| F-03 | 草案完成后 add→add→closing，无过渡台词 |
| F-04 | Turn A 只播 add0；Turn B 播 add→closing；add1/closing 不播 |
| F-05 | add→原文1→改写2→原文3→原文4 |
| F-05b | add→原文1→原文2→改写3段0→段1→原文4 |
| F-06 | add→原文1→跳过2→原文3→原文4 |
| F-07 | add→原文1→原文2→改写3→原文4 |
| F-08 | add→改写1，结束（不播原文3/4） |
| F-09 | mute→add→原文1.. |
| F-10 | 无 AI 行，回原对话 |
| F-11 | add0→回原对话当前点 |
| F-12 | 关闭；未播不写 |

### 4.3 session/finalize

| 场景 | 期望 |
|---|---|
| 首次插入 | 创建 session，种入首次插入前已播原作；`$PC` 作为 user |
| 后续轮 | 复用同一 `dialogue_instance_id`；不重复写相同 `seq` |
| 其他 NPC 原作 | user，`【NPC名：台词】` |
| 当前 NPC 原作/改写/AI | assistant |
| 未播 add/closing/edit/remove | 不写 |
| 取消/关闭 | finalize 以已播 transcript 幂等收尾 |
| 重复 finalize | 幂等，不重复追加 |
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
- 解析器：JSONL 围栏/非 JSON/括号剥离/165 拆分/`split`/情绪回落。
- 计划：F-05/F-05b/F-06/F-07/F-08 的 plan 逐字段断言；`n`/`end` 越界宽容。
- SSE：事件顺序、`seq`、`split`、`mute` 先于 `line`、`done`/`error`。
- session：F-01/F-04/F-12 的创建、复用、幂等 finalize、未播不写。
- 以上全部离线；不调用真实模型、不写生产数据目录（用临时 data root）。

### 5.2 游戏侧

- 假 SSE：按 §3 事件注入 Host SSE 客户端；断言播放顺序、输入可用/暂锁/禁言、取消、finish/finalize。
- Native 会话：本地追加行不改 `WireRowCount`；组末 `finalIndex` 用 AS2 原始最后一行；提前关闭用 `close`。
- 任务 plan：F-05/F-05b/F-06/F-07/F-08 的播放序列与“已越过”标记。
- 输入控件：先做 G0-1 spike；IME、Enter、焦点、点击不误触。
- 以上不要求真模型；真机 IME 与视觉属于 P5/作者验收。

---

## 6. 变更控制

- 本文与《协议》已冻结。任何字段/语义变更：先改《协议》与本文，再改两侧实现；不得只改一侧。
- 发现 fixture 与协议冲突：停下来报告，不修改 fixture 迁就实现。
- 新增 fixture 只能追加编号；不得改写既有编号的期望语义。
