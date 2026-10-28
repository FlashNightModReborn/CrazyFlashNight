# AI 终端 V3.1：开发计划

**文档角色**：跨仓施工与验收计划。产品范围归[需求与协议](AI终端V3.1-需求与协议.md)，模型实际可见文字归[提示词合同](AI终端V3.1-提示词合同.md)。后续模型不得只看任务标题后自行补设计。
**最后核对代码基线**：GAME commit `f3583f627d4f6d256eaccdc4f23883d0490ab4e0`；BACK commit `9892317de0a66c43ceb9f8f291969ccebebaa84e`（2026-10-28）。

## 1. 施工顺序与授权范围

本轮先提交推送整套文档，再实施第二节的候选与前置修复；两步均已完成。其余功能只交付可执行设计，不借本轮授权提前施工。

| 批次 | 内容 | 状态 |
|---|---|---|
| 文档 | 需求、实施计划、提示词逐字合同、后端施工入口 | 已提交推送 |
| 当前修复 | 绑定存档已解锁关卡候选、已完成前置、阶段早期目标匹配 | 已实施并提交；离线测试通过，待真模型与游戏内验证 |
| 查询与历史 | 统一查询、other_npc 归 assistant、跨会话检索 | 待施工 |
| 委托与记忆 | 两入口共享任务概览、长期记忆互斥分支 | 待施工 |
| 图像 | 多 NPC 立绘、八页地图烘焙和任务自动附图 | 待施工 |
| 交付验证 | 真模型最小调用、游戏入口、重打包／发布 | 后续授权范围内执行；本轮不代签 |

后端仓的文件名和运行状态路径继续冻结；不新建第二份 memory.db，不重命名 vector_index_v3、agent_saves 或已有任务文件。共享源码和提示词的改动必须当批同步相应文档状态，已做的与尚未做的分别写清。

## 2. 当前修复：已解锁候选和已完成前置

### 2.1 权威数据足够，不新增实时远端预检

正常同步状态下，已有绑定投影提供 `slot_key`、`progress.tasks_finished`、`progress.tasks_active`、`progress.task_chains_progress` 与 `player.level`。

游戏 `scripts/通信/通信_鸡蛋_任务系统.as` 的完成路径先推进任务链，再将主线任务进度赋为主线链值；`scripts/通信/通信_鸡蛋_XML与JSON解析.as` 的 `isStageUnlocked` 判定是：主线链达到 UnlockCondition，或者任一 AltUnlockCondition 的 chain/min 达标。后端可以用同一轮已绑定事实与本地游戏表确定候选，无需为本修复增加 AS2/Host 协议或正式 runtime 发布。

证据边界：使用最近已同步快照，不保证窗口外尚未同步的瞬时状态。不能把“地图解锁”扩称为无论战斗状态、入口场景等都能立即传送；本修复只保证正常任务候选供给，不新增发布失败条件。

### 2.2 实施入口

BACK 当前关键链：

```text
orchestrator/turn.py 或 dialogue_interject/tools.py
  -> TaskRunner.launch
  -> ToolContext
  -> PrepareTaskContextTool.run
  -> handlers.execute_prepare_task_context
  -> context_builder.prepare_task_context
  -> 普通关卡 / 掉落关卡 / 切磋目标
```

文件级改动目标：

| 文件 | 明确修改 |
|---|---|
| `services/game_data/models.py` | StageInfo 的 unlock_condition 说明改为主线链阈值；补替代解锁路径，不再当作任务 ID |
| `services/game_data/stage_registry.py` | 解析 AltUnlockCondition 单条／多条；合法零门槛与缺失／坏值区分；按游戏加载顺序处理同名定义 |
| `services/tools/base.py`、`services/subagents/task_runner.py` | 将本轮绑定事实传到任务工具，不让关键词或模型参数指定槽位 |
| `services/tools/task/prepare_task_context.py`、`services/agent_tools/handlers.py` | 透传绑定信息，覆盖初拟、重拟和相关后备路径 |
| `services/orchestrator/turn.py`、`services/dialogue_interject/tools.py` | 两入口一致提供绑定事实，日常插话不得漏传 |
| `services/agent_tools/context_builder.py` | `_get_all_stages_for_progress`、`_build_stage_loot_list`、`_build_challenge_targets` 共用已解锁过滤；关键词／随机补足都只能在过滤后的集合里取 |
| `services/agent_tools/task_tools.py` | `_stage_reqs_unlock_ids` 由阈值直抄改为任务链映射＋已完成集合；删除 77 截断，保留回访依赖 |
| `services/agent_tools/validator.py`、`services/agent_tools/fallback.py` | 绑定情况下不再以旧阶段上限拒绝有效关卡；后备草案直接从已过滤候选取，不二次用旧上限筛掉 Alt 已解锁对象 |

实际新增 `services/stage_access.py`：`BindingFacts` 只读快照、`stage_is_unlocked`（主线 OR 替代链）、`stage_unlock_task_ids`（已完成锚点）与 `matched_stage_for_tags`（阈值 3）；不是新的服务层或第二个权威。测试在 `tests/agent_tools/test_stage_unlock_binding.py`。

### 2.3 候选流程

1. 在回合开始捕获绑定槽位及事实，传给候选构建；未绑定走原有推荐。
2. 对有效关卡按与游戏相同的主线／替代链 OR 规则筛选，不能用七档上界判已解锁。
3. 副本还需满足本地入口配置中的前置任务、所需等级等既有资格；正常／挑战难度只从当前可选集合提供，推荐等级不要误作不存在的硬门槛。
4. 外交非战斗地点沿用现有排除；掉落任务先筛可用关卡，再读取箱子和物品，不能先按物品命中把锁定关卡补回。
5. 既有关键词、势均力敌／轻松应对、阵营标签、随机补足、池大小在合法候选上执行。
6. 切磋能力检查、正式 prepare 与后备候选使用相同资格语义。空池真实返回空，不拿锁定对象补满。

绑定事实缺失字段时仅提供能够从现有事实证明已解锁的关卡；不把缺失当作满进度。这是候选范围，不是新增发布后的拒绝。

### 2.4 阶段早期的势均力敌

原有玩家阶段、奖励预算、物品价格和玩家身份提示保持原值，只调整关卡标签／选取使用的匹配阶段。

工程默认：本阶段已解锁且符合当前任务类型的关卡不足 3 个时，允许从前一阶段的已解锁目标补充势均力敌候选；已有至少 3 个即使用本阶段，不继续向更早阶段递归。此为“有几个可选就用本阶段”的确定性实现，阈值集中定义并测试 0／2／3 边界；若实现选择更精细比例，应先在本节明确真实算法与原因，不能散落多个阈值。

比较对象要排除尚未解锁、类型不符和未开放副本，不能把副本统一视为本阶段。补充候选不能修改实际玩家阶段来连带改变报酬。相同关卡在多处注册只计一次。

### 2.5 前置任务

- 对每个目标关卡，找当前实际满足的解锁路径：主线满足就用主线；否则选一个满足的 Alt 路径。OR 不能拼成多个 AND 前置。
- 根据本地任务 `chain=链名#节点` 查能证明该路径达标的任务 ID，再与当前完成集合相交。优先选最早满足该阈值的已完成锚点，去重。
- 不要求完成“正在打这个关”的后续主线，不抄阈值、不统一减一、不把 ID 截到 77。
- 找不到可信映射时不伪造前置，允许空数组；空数组不要求一个未完成任务。
- 当前只有活动 ID 不等于已完成，不能用来填前置。
- 回访第二段继续以前一段新任务 ID 为前置，这是配对结构，不纳入普通自动关卡前置的已完成交集。
- 未绑定时不能声称已完成；可以按真实链映射生成原有推荐语义，不用已绑定的空快照冒充事实。

### 2.6 校验保持与去除

保留物品／关卡／NPC 名称存在、字段类型、任务结构、合法难度、数量与既有奖励合法性校验；游戏 `taskAvailable`、自动接取 Handoff 守卫不改。

不得把真实解锁过滤再塞进 draft/update/confirm 作一个新拒绝门。绑定情况下，现有 V4 阶段上限、V3R 推荐等级和 V5 中纯当前等级资格不得把有效但意外超当前进度的任务拒绝；真实配置不存在的难度仍拒绝。未绑定的旧推荐语义保持独立，不借本次删光整个校验器。

本批不改 NPC 台词提示词规则；候选实际对象与势均力敌标签变化属于供给数据变化，最终汇报逐项说明，不谎称模型输入完全没变。

### 2.7 测试

- 主线 20 时地铁站不进入池，21 时进入；完成集合含任务 20、不含 21，写盘前置应为 20。
- 同阶段前期不能看到该阶段末尾才解锁的关卡。
- Alt 单条／多条 OR、跳号节点、任务 ID 大于 77、同名后定义覆盖、缺失与零门槛。
- 普通、掉落、切磋、副本、关键词命中与随机补足、后备草案均使用同一可用范围。
- 势均力敌 0／2／3 个本阶段目标、阶段 1、前一阶段也无候选；奖励参数不变。
- 未绑定、缺绑定字段、不同槽位、仅活动不完成、回访第二段不能提前领取。
- 有效但锁定的模型输出不会因新增当前资格检查而生成失败；非法名称／难度仍被现有合法性校验拒绝。
- 终端和插话 launch/prepare 的真实传参用测试捕获，不仅测试独立 helper。

## 3. 统一查询与历史施工

### 3.1 角色修正先行

只改 `services/dialogue_interject/sessions.py::map_played_line` 的 other_npc 分支 role 为 assistant；`【名字：台词】` 原样保留。更新 sessions/finalize 的精确行测试，不新增数据库迁移。历史查询以当前正确角色语义为前提，不承诺修复旧行。

### 3.2 注册与执行器

- 修改 `services/tools/route/route_search.py` 的 schema/description，以及 `services/orchestrator/turn.py` 的 Route 数据结构与路由解析；不能仅改 schema 而解析层仍丢 requests。
- 两端路由解析处理完整 requests 数组；不能因为目前“仅处理第一个路由”而丢同一次查询内其他项目。
- 现有 `services/orchestrator/search_prefetch.py` 承担 knowledge/items/stages 的数据查询；扩展为一个类型化结果结构，文本与图片分开。
- `services/memory/store.py` 增加按 slot＋NPC/role 的只读跨 session 查询，使用已有表和参数化 SQL，不建第二个库。
- `services/dialogue/view.py` 复用基础／覆盖层合并读取；读取任务资料与“可编辑对话候选”分离，不能误排所有已完成任务，也不混入不存在的编辑权限。
- `services/portraits/provider.py` 复用现有立绘 manifest 查表；允许批量取图并保留 NPC 对应关系。

建议内部每项结果包含 `id`、`kind`、`text`、`source`、命中关键词及可选 `image` 引用，外层另有计数和分页说明；实际图片由消息层编码，不在检索文本中放 base64。

### 3.3 分块预算与排序初值

| 类型 | 工程初值 | 说明 |
|---|---|---|
| knowledge | 3600 字 | 沿用现有池与单条预算 |
| items / stages | 各 1200 字 | 沿用现有结构化片段 |
| npc_history | 6000 字 | 含相邻上下文，合并重复窗口 |
| player_history | 4000 字 | 只含 user 原话和出处 |
| npc_dialogues 日常 | 12000 字／页 | 完整组优先，超出明确分页，不静默漏组 |
| npc_dialogues 任务 | 6000 字 | 关键词、进度相关性选片段；无额外关键词时仍提供相关任务资料 |

这些预算作用于类型块，同一交流回合的所有同类请求及深搜补查共用；不再追加一个最终总字数切片。摘要最终输出不强制 400 字，也不截到 1000 字。任何新默认参数在测试中钉住，但不得冒充用户逐字给定的数字。

分页通过需求中的 `requests[].cursor` 与结果 `next_cursor` 继续读取。下一次交流回合重新获得本类预算；同轮深搜翻页不重置预算，用尽后保留继续位置，不循环空查。日常单组超过一页时按完整台词行分段，游标记录组与行偏移，结果标记该组尚未返回完；不能反复跳过同一大组。游标绑定槽位、NPC、查询关键词与数据版本，不能用于跨槽或换查询扩大范围。

### 3.4 深搜原文返回

`services/subagents/search_runner.py` 移除 `_FINDINGS_MAX_CHARS` 总截断；`services/subagents/prompts.py` 按提示词合同替换 SEARCH_RUNNER_SYSTEM 和首查材料拼接。

搜索 Agent 有已有材料的编号索引；最终输出 raw/result_ids 或 summary/text。选择原文时程序提取源块，不能让模型输出一份改写后文本再称原文。未知编号不读任意路径，按已有结果处理并记录异常；不为格式修复额外烧一整轮总结。轮限耗尽时保留已经查询到的有效资料，不把已查内容清空。

主交流 Agent 的普通查询直接回复轮和深搜汇合轮都使用同一多模态附件装配器，图片项不经过搜索 Agent。现有 reasoning_content 逐轮回传保留；修改消息形状后必须复跑相关模型 profile 锁测。

## 4. 委托概览与长期记忆施工

### 4.1 委托装配共用

在 `services/agent_tools/finished_tasks.py` 内维护共享只读构建器，返回精简任务记录及关联关卡，不在每个入口各写一套筛选。

- 用 `_merged_docs(..., slot_only=True)` 读取本档任务；未绑定不套用本档逻辑。
- 完成态优先；未完成细分 active 与未接。所有未完条目保留名称、简介、要求；不再按 MAX_ACTIVE_TASKS_PER_TURN 只展开三条。
- 未完成 `_unfinished_task_lines` 原来没有任务对话，不新增；已完成 `_task_lines` 不再拼完成对话，但保留完成事实和可选接取对话。
- `services/orchestrator/context.py`／prompts 接新块，避免旧 published highlight 与新块重复同一任务；发布即时回执保留。
- `services/dialogue_interject/context.py::DailyBlocks` 和 `build_user_context` 接同一构建器，daily/task 都有；当前 Host task_context 与共享概览按任务 ID 去重，不用一次性会话替代持久事实。
- 任务关系只能来自已加载记录与同步投影；不能引入“模型说完成就改变状态”的写路径。

### 4.2 记忆分支

`services/memory/long_term.py::build_chat_tool` 继续按程序状态构造三种形状，新增入口格式参数或分离前缀，终端用 meta，插话用 JSONL；`format_block` 的关键记录说明可供回忆，不只供去重。

逐字替换以提示词合同为准。`services/dialogue_interject/prompts.py` 的索取待处理、日常和任务三处工具指南都要去掉一刀切“重要信息”门槛。工具未注册时，相关指令不进入最终 tool-free 回复轮。

存储仍最多20条，existing entry_no 的更新／融合不变；不新增重要性判别器。单轮从19到20后若还有模型调用，应按更新快照重新生成满额工具与指南；未发生下一次模型调用则无需凭空加一轮。

## 5. 图片链与地图派生施工

### 5.1 固定底图与节点 manifest

拟新增生成器 `tools/bake-stage-select-ai-overviews.js`；拟新增资源目录 `launcher/web/assets/stage-select/ai-overviews/`。文件名固定为对应区域名 `.webp`，伴随 `manifest.json`；版本写入 manifest 字段。这些路径是待施工设计，不是现存产物。

复用 `tools/capture-stage-select-experience.js` 的本地服务／Edge／生产 DOM／真实 GLB 入口，但更改捕获目标：

1. 只迭代需求白名单八页，视口1280×720，固定字体与默认相机，独立空存储。
2. 严格等待本页要求的真实渲染器与字体就绪；3D页意外fallback不当成成功底图。
3. 捕获中性底图，另输出与该镜头一致的节点投影、标签和建筑选择位置；不能只取Canvas后丢DOM标签。
4. 输出WebP及源码／模型／镜头／字体／底图哈希；`--check` 校验八页集合与映射一致性。
5. 运行时按当前存档合成可见标签／锁定／任务目标；重用既有标签规范，不将全解锁图作为最终结果。
6. 默认镜头不随玩家localStorage取景变化；加载结果和缓存必须绑定区域、目标集合及状态，不串档。

有同名多节点时保留数组；AVP等无选关节点的关卡只供文字，禁止补一个猜测的坐标。副本可生成任务不等于必有本版地图图像。

### 5.2 后端消费

可在 `services/portraits/provider.py` 旁新增地图provider，但先复用公共图像消息组装，不创建第二份LLM客户端。

- 查询输出图像引用与说明；消息层编码为user content数组中的text/image_url。
- 任务草案、未完成任务、任务插话上下文各自产生结构化关卡集合，经一个附图函数按区域去重。
- `services/dialogue_interject/llm.py` 不再无条件 `send_image=False`；终端 `_stream_simple`／汇合链也要传入所需图片。
- 已明确无视觉能力时，从本轮查询kind枚举及指南移除两种图片类型，自动附图也不发送；保留已有文字内容，不写一段要求模型自行判断图像能力的说明，不新增自动切换模型或OCR服务。能力未知时沿既有profile试发／不支持处理。
- 同一NPC图片请求、同一区域多任务、深搜混合图文必须有请求级断言，不能只检查provider返回了路径。

### 5.3 打包闭包

GAME `tools/cf7-packer` 必须纳入底图和manifest并通过现有闭包审计；BACK `scripts/build_full_zip.py` 的精简资源白名单也需补入新地图资源。单exe仍读取旁边游戏资源；模型、图片或浏览器开发依赖不得临时塞进exe运行时依赖。

构建缓存／中性底图是静态资料；动态存档标记图是运行派生物，不提交真实玩家数据，不写进分发包。不重命名已有冻结目录。

## 6. 提示词改动清单与装配检查

下列每项必须对照提示词合同的完整新文本，不允许只凭本表自己发挥：

| 改动 | 适用路径 | 不变部分 |
|---|---|---|
| route_search description/schema 与查询指南 | 终端／日常插话／任务插话 | 非查询任务、交易和委派的既有权限 |
| 搜索 Agent 工作与最终返回格式 | deep=true的文本 | 图片不经该Agent；首次查询不重复 |
| 查询结果＋多图 user 消息 | 普通查询与深搜回复 | 本入口台词格式、reasoning回传 |
| 同档NPC任务概览 | 绑定的全部交流入口 | 未发布草案独立、状态来自事实 |
| 三种记忆工具与指南 | 每个入口按真实记忆状态 | 存储上限、摘要轮维护印象 |
| other_npc角色 | 历史／finalize | 【名字：台词】内容不改、不迁移 |

最终消息快照必须覆盖：工具开启／关闭、无草案／有草案／索取中、daily／task_pre／task_post、未绑定／绑定、记忆空／19／20、纯文字／单图／多图／不支持图像、普通／深搜原文／深搜总结。无关分支整段不出现，不用否定句描述缺席工具。

## 7. 验证与交付

后端先激活项目虚拟环境，再运行 `python -m pytest tests/`。新增测试优先扩展现有 `tests/agent_tools/`、`tests/game_data/`、`tests/dialogue_interject/`、`tests/orchestrator/`、`tests/memory/` 与 `tests/llm/`；真实模型调用留到离线测试通过且获授权后，最少必要次数，不为多拿证据重复消费。

游戏文档运行：

```text
node tools/validate-doc-governance.js
git diff --check
```

地图实际施工后运行现有stage-select harness与新生成器check，并在浏览器核对八页图片、锁定、中文可读性和多标记；Host／AS2协议若最终有变化，再走对应源码、单测、编译和正式授权路线。本轮候选修复设计不要求修改这些协议。

提交前复核只包含本批文件，不收未跟踪的Full zip、真实存档或并行修改；先文档提交推送，再代码修复提交。跨仓引用在GAME三份正文与BACK施工入口互相可找到，不在AGENTS.md追加长篇版本记录。

## 8. 本轮实施回写

- 文档：已提交推送（GAME `f3583f627d`；BACK `fe23624`）。
- 当前候选与前置修复：已实施并提交（BACK `9892317`）。新增 21 项离线测试，全量 `python -m pytest tests/` 1,154 通过（本批前 1,133）。
  - 候选池：绑定态按主线链值／AltUnlockCondition 过滤，关键词、随机补足、掉落、切磋与后备草案共用同一已解锁范围；未绑定维持旧推荐口径。
  - 前置任务：按已满足的解锁路径取已完成任务链锚点，去重后写入；不再抄阈值、不再截断到 77，找不到映射时允许空数组。
  - 阶段早期匹配：仅当本阶段已解锁目标不足 3 个时退回上一阶段，阶段 1 不继续回退；奖励与玩家阶段不变。
  - 校验：绑定态跳过 V4 阶段上限、V3R 推荐等级与 V5 纯等级资格；物品／关卡／NPC 名称、结构、难度与奖励合法性校验保留，游戏 `taskAvailable` 与接取守卫不改。
- 证据边界：仅离线单测与既有集成测试通过；未跑真模型、未进游戏、未重打包、未发布，也未复验窗口外尚未同步的瞬时状态。
- 其余V3.1：只设计，未实施。
- 运行／打包／正式发布：未执行。
