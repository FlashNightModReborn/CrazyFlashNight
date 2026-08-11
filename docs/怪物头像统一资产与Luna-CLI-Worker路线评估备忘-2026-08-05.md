# 怪物头像统一资产与 Luna CLI Worker 路线评估备忘

**文档角色**：怪物头像共享数据边界、FFDec 离线提取、Luna CLI worker、Edge 人工审批、工程复盘与后续施工恢复的评估备忘。本文用于跨会话恢复和施工前对齐，不替代冻结后的数据 schema、生成器 README、测试矩阵或运行时协议 canonical doc。

**状态**：`P4_CAMPAIGN_AND_SOURCE_CLOSURE_VERIFIED / ORIENTATION_AUDIT_HUMAN_CLOSED / UNIVERSAL_ASSET_PACK_PROMOTED / TEAM_CONSUMER_INTEGRATED / ARENA_ALL_MODE_CONSUMER_INTEGRATED / ARENA_EXACT_IDENTITY_CLOSED / NOT_GAME_E2E_VERIFIED`。当前消费者无关包包含 226 个 identity / 227 个 variant，其中 222 个 variant 具备真人接受证据并生成透明 SVG 主源 + 512px PNG 回退；仅 `Serpent / 黑无常索命` 2 个 identity 仍待真人，`不知火舞` 继续按“不实装”排除，`拟态投影` 与 `锡蒙利范围光环发生器` 分别只走已签别名。原 98 identity Team 子集与 JK `orange / white` 双头像完整保留；透明主体与框体/氛围底色分层。Team 与 Arena 共用 `EnemyPortraits / entity-portrait-art`，两边的佣兵缩略图共用 `MercPortraits` dressup 胸像；Arena 定制赛的 450 条单位记录形成 217 个唯一消费身份，其中怪物 manifest 命中 214/214，`主角-男 / 主角-尾上世莉架 / 主角-文天` 3 个模板按具体单位外观进入纸娃娃路线，合计 217/217 ready、0 显式回退。标准、堕落、爬升卡及右栏对手均已接入头像组，完整态最多显示 4 个实际单位、紧凑态只显示首项；Arena mock-browser 三视口仍须作为固定门。尚未完成真实 Launcher WebView2→Flash 或游戏内视觉 E2E；消费者范围外的 2 个 pending 仍须独立收口。

**最后核对代码基线**：commit `885fddeeecf9940e127987d31710f50e6932d8b3`（2026-08-10）；头像资产包、通用 resolver、Team/Arena 消费者与复审工具已随 `fff104b0f2`（2026-08-09）入库并经 `885fddee` 收尾，不再是未提交工作树差量。

**外部能力核对日期**：2026-08-05。Codex 模型目录和 Multi-agent backend 属于可漂移外部能力；每次正式运行仍须重新 probe，本文记录的是当日已验证事实，不是永久产品承诺。

---

## 0. Compact / 新会话恢复入口

发生上下文 compact、换 Agent 或重新开会话时，先按以下顺序恢复，不要从聊天记忆猜测：

1. 读顶层 [`AGENTS.md`](../AGENTS.md)，确认硬约束和当前 Context Pack。
2. 读本文 §1、§2、§7、§9、§12–§13，恢复已定路线、技术有效性结论、当前证据和下一步边界。
3. 运行 `git status --short`，保留用户已有脏改动；本文不授权清理、格式化或提交无关文件。
4. 若要开始实现，先重新核对：
   - `spawn_agent` 当前实际允许的模型；
   - 可执行 `codex.exe` 路径、版本和 SHA-256；
   - `gpt-5.6-luna + max + image + output schema` 的最小 capability smoke；
   - `data/enemy_properties/list.xml`、`data/items/asset_source_map.xml` 和头像目录的覆盖统计。
5. 没有新鲜 probe 时，不宣称 Luna 原生 subagent 已可用；没有 Edge 导出的完整人审决定时，不宣称头像已完成艺术验收。

可直接交给下一会话的恢复提示：

```text
先读 AGENTS.md 与 docs/怪物头像统一资产与Luna-CLI-Worker路线评估备忘-2026-08-05.md。
当前状态是 TEAM_ASSET_PACK_PROMOTED / TEAM_CONSUMER_INTEGRATED / NOT_GAME_E2E_VERIFIED。
不要修改 Codex 模型缓存或伪造 multi-agent backend；不要让模型直接写生产头像。
先复核工作树、生产 manifest digest、CLI capability 和待办消费者边界，再只执行当前明确授权的 phase。
```

---

## 1. 决策摘要

1. 将怪物头像建设为可被战宠、图鉴、目标列表和后续 Web UI 复用的共享资产，不继续以 `pet_<petId>.png` 作为 canonical 身份。
2. `portraitRef + variantKey` 是共享资产身份；`variantKey=default` 表示无变体。敌人消费者默认 `portraitRef=enemyId`，战宠消费者默认 `portraitRef=Identifier`，即使该 Identifier 没有对应 `enemy_properties` 节点也仍是合法 pet-only 身份。
3. 只有需要跨身份共享时才在所属消费者数据写显式覆盖：敌人定义使用可选 `portraitRef`，战宠定义使用可选 `PortraitRef`。这两个字段只做 consumer → asset identity 映射，不承载 PNG 路径、裁剪、FFDec ID、当前实例状态或 variant 选择。
4. inventory 必须读取 214 个敌人身份与 98 个唯一战宠 Identifier 的并集，保留 `enemyId/petId` consumers，再按最终 `portraitRef` 去重；不能只生成 enemy_properties 集合后直接迁移战宠。
5. FFDec 来源、候选帧、焦点框、裁剪框、输出文件、source hash、逐次模型运行与人工审批证据进入 content-addressed candidate/review 闭包；Web 配置只保存跨实体的展示风格和 context preset。
6. 武装 JK 的橙发 / 白发是实例状态。AS2 / Host 应投影稳定的 `portraitVariant`，Web 不从“橙发 / 白发”等本地化文案反推文件名。
7. 模型只提出帧选择、视觉焦点和 crop；最终像素由确定性 renderer 生成。模型不得默认重绘、补画或直接覆盖生产资产。
8. 现阶段不覆盖 `spawn_agent` 白名单，不改远端模型缓存，也不依赖 `agents.default_subagent_model` 绕过 Luna V1 / Sol-Terra V2 限制。
9. Luna 通过独立顶层 `codex exec` 进程工作，定义为可替换的 `CodexCliLunaWorker` transport，而不是伪装成原生 subagent。
10. 根据维护者实际使用经验，首轮以 **Luna Max** 作为普通提案与独立风格复核的默认配置；Terra 只作对照组，Sol Medium / High 处理异常与争议。
11. 复用现役装备检视器的本机 Edge 大批量审批模式：稳定 ID、source/review digest、持久进度、筛选、结构化决定、partial/stale fail-closed 和人工导出证据。
12. Edge 人审结果只作 QA / promotion 输入，不能由页面点击直接改写生产 resolver 或资产目录。
13. P2/P3、P4 有界 campaign、来源闭包与当前 203 条人类偏好先用于 Team promotion，随后由消费者无关 controller 以 subjects-first / manifest-last 方式扩展为通用包。当前 222 个 variant 均有冻结人审证据并启用现代资产；2 个待人审、唯一 `不知火舞` 未实装项与 2 个回执别名都不暴露模型未签署主体，不得用模型共识冒充人审。
14. 明确人工备注若无法靠通用语义规则稳定满足，可按稳定 `reviewKey` 维护归一化 `requiredFeatureRegion / requiredMustIncludeRegion`。模型结构化结果与确定性 renderer 必须分别证明包含关系，profile hash 必须进入 source closure；该机制只约束构图，不能补画、替代人审或处理来源冲突。
15. 若 adjustment 已明确到 A/B 中的具体帧和移动/缩放，不再启动下一轮 Luna。人工框选页绑定父 receipt、来源角色、candidate hash 与 `sourceHighResolution`，在人类看到的实时 80px 上导出像素正方形；冻结后由确定性 renderer 直接生成最高 4096 母版及派生尺寸。该接受范围仅是所选 frame/crop，仍不授予 production 写入或来源/变体裁决。
16. 本轮已经证明 Luna CLI 集群可以成为受控高吞吐视觉 worker，但没有证明 Luna 能自主完成艺术签署；可复用结论以 §12 为准。未来“怪物知识库与美术导演管线”只进入设计储备，见 [`怪物知识库与美术导演管线-设计储备与维度讨论-2026-08-08.md`](怪物知识库与美术导演管线-设计储备与维度讨论-2026-08-08.md)，不得从本头像任务直接外推为已实施能力。

---

## 2. 当前事实与证据快照

### 2.1 战宠头像现状

2026-08-05 施工前只读审计结果如下。本小节保留迁移前基线，当前 Team 生产状态以 §13 为准：

| 项目 | 数量 / 事实 |
|---|---:|
| `data/merc/pets.xml` 战宠定义 | 111 |
| `launcher/web/assets/pets/` PNG 总数 | 84 |
| `pet_<id>.png` 主头像 | 81 |
| 变体文件 | `pet_46_1.png`、`pet_78_1.png` |
| fallback | `pet_locked.png` |
| 缺主头像 | 30 |
| `80×80` 文件 | 52 |
| 当前尺寸跨度 | 宽 80–558、高 80–557 |

缺主头像 petId：

```text
29, 30, 31, 32, 33, 34, 35,
56, 57, 58, 59, 60, 63, 64, 65, 66, 67, 68, 69, 70,
98, 99, 100, 101, 102, 106, 107, 108, 109, 110
```

当时 Web 在 [`pet-panel.js`](../launcher/web/modules/pet-panel.js) 多处直接拼接 `assets/pets/pet_<petId>.png`，缺图时回退 `pet_locked.png`，尚无共享 `PortraitResolver` 或 variant selector；当前已由 §13 所述共享 resolver 替代并保留 legacy fallback。

武装 JK 的现役语义链：

- `data/merc/pets.xml`：petId `78`、Identifier `敌人-武装JK`。
- [`单位函数_aka_战宠进阶.as`](../scripts/逻辑/单位函数/单位函数_aka_战宠进阶.as)：`切换发型` 在 `发色=橙|白` 间切换，旧 Flash 头像按标签帧 `gotoAndStop`。
- [`PetPanelService.as`](../scripts/类定义/org/flashNight/arki/merc/PetPanelService.as)：Web 状态投影为 `kind=cycle`、`value=<发色>发`。
- 当时 Web 图片 URL 不消费该状态，因此 `pet_78.png` / `pet_78_1.png` 没有形成状态驱动闭环；当前 Team 已保留 orange/white 两个正式 variant，并在 Host 尚未投影稳定字段时使用受控兼容桥。

### 2.2 敌人定义与素材来源覆盖

`data/enemy_properties/list.xml` 当前引用 14 个 XML，共有 215 个根定义，其中 1 个是 `默认`，非默认敌人 214 个。

战宠侧另有一条必须与素材覆盖分开的身份事实：111 个定义只有 98 个唯一 `Identifier`；其中 7 个没有同名 `enemy_properties` 节点，但仍按 §4 的默认规则成为合法 pet-only `portraitRef`：

```text
敌人-暴走改造僵尸、敌人-暴走兽化改造僵尸、敌人-暴走重型改造僵尸、
敌人-暴走爆炸僵尸、敌人-暴走尸母、敌人-不知火舞、敌人-柜员女僵尸
```

按 [`asset_source_map.xml`](../data/items/asset_source_map.xml) 对**唯一身份**分类：

| 范围 | unique | duplicate | conflict | missing |
|---|---:|---:|---:|---:|
| 214 个非默认敌人 | 210 | 1 | 2 | 1 |
| 98 个唯一战宠 Identifier | 90 | 0 | 2 | 6 |
| 默认 identity 并集（221） | 211 | 1 | 2 | 7 |

解释：

- `unique` 可以进入自动来源解析。
- `duplicate` 是同一 linkageId 在同源内有多个 symbolName，必须审计选择。
- `conflict` 是跨 SWF 冲突，禁止“第一条命中”。
- duplicate/conflict 作为同一身份下的 `sourceCandidateKey` 走来源选择，不直接变成产品 `variantKey`；人工选中后仍写一个 `default` 头像。只有消费者能提供明确运行时状态选择器时，两个来源才允许升级为正式变体。该契约及 source-choice generator/reviewer 已在 P4 实证，后续仍不得回退为“第一条命中”。
- 初始 inventory 中非默认敌人唯一 source missing 是 `敌人-Serpent`；最终 r168 证明它只有属性定义和 save-repair allowlist，`units.json`、asset map、FLA/SWF export 均无可实例化敌人根。FLA 的 `Serpent/*` 是 ArmsArius 内部肢体零件，不能据此复用 ArmsArius 头像。
- 初始 6 个 pet-only identity source missing 已由后续来源解析/内嵌 `man` 救援逐项收口；最终只剩 `敌人-不知火舞`，其 `pets.xml` 有“不考虑实装”注释且命名 FLA 只位于 `flashswf/unused`。r168 将 Serpent 与不知火舞都归为“未来实装前排除”，actionable missing=0；`敌人-柜员女僵尸` 虽没有敌人属性节点，但 source map 唯一命中，因此身份缺口与素材缺口不能混为一类。
- 221 是按当前默认规则得到的 union；未来显式共享 `portraitRef` 可能继续去重。实现前应重新生成机器清单，不把本文快照当实时数据库。

`asset_source_map.xml` 由 [`tools/linkage_scanner/scan_linkage.py`](../tools/linkage_scanner/scan_linkage.py) 生成，文件头明确 `DO NOT EDIT MANUALLY`。`symbolName` 只在库名与 linkageIdentifier 不同时输出，不能因字段缺失就推断为文档根 symbol。

### 2.3 已有可复用工具

- `tools/ffdec/`：本地 FFDec CLI / JAR。
- [`tools/bake-icons-offline.py`](../tools/bake-icons-offline.py)：source map 解析、SymbolClass / characterId、`-selectid`、批量导出、超时和 fallback。
- [`tools/bake-dressup-offline.py`](../tools/bake-dressup-offline.py)：纸娃娃素材离线生成。
- [`tools/bake-dialogue-portraits.py`](../tools/bake-dialogue-portraits.py)：对话头像帧标签、alpha bounds、manifest / report。
- [`tools/export-map-avatar-assets.py`](../tools/export-map-avatar-assets.py)：地图头像资产与渲染元数据。
- [`tools/asset_timeline_export.py`](../tools/asset_timeline_export.py)：时间线、去重与 hold 语义共用层。
- [`tools/build-equipment-inspector-review.js`](../tools/build-equipment-inspector-review.js) 与 [`tools/open-equipment-inspector-review.js`](../tools/open-equipment-inspector-review.js)：全量候选构建和本机 Edge 人工审批。

结论：头像工程应复用 / 抽取这些脚手架，不新建一套无 provenance、无超时、无 digest 的 FFDec wrapper。

### 2.4 Codex / Luna 能力快照

当日已验证：

- 本地 app-server `model/list` 包含 `gpt-5.6-luna`，支持 `text + image`，支持到 `max` reasoning effort。
- 有效 `configRequirements` 为 `null`；用户配置没有 `[agents]` 模型限制。
- Luna Max 顶层 `codex exec --ephemeral` smoke 成功并返回预期固定字符串。
- 当前 ChatGPT App 会话中的 `spawn_agent(model="gpt-5.6-luna")` 明确失败，候选只列 `gpt-5.6-sol` 和 `gpt-5.6-terra`。
- OpenAI Codex 已合并 [#32751](https://github.com/openai/codex/pull/32751)，要求 spawned-agent model 与 active multi-agent backend 兼容；相关 Luna 问题 [#34301](https://github.com/openai/codex/issues/34301) 在核对时仍为 open。
- [社区复现](https://community.openai.com/t/gpt-5-6-luna-is-advertised-for-custom-agents-but-rejected-by-sol-terra-multi-agent-v2/1389020) 记录 Sol / Terra V2 与 Luna V1 的冲突、默认配置无效、模型缓存会被远端恢复，以及 custom-agent 假阳性风险。社区回复不等于永久官方产品承诺；真正可依赖的是当前工具行为、合并代码和每次运行的新鲜 probe。

Windows 可执行文件观察：

- ChatGPT App WindowsApps 包内 `codex.exe` 可被发现，但从当前 Agent shell 直接执行返回 `Access is denied`。
- 已安装 VS Code 扩展内的 `codex.exe`（CLI `0.146.0-alpha.9.2`）可执行，并完成过 Luna Max 顶层 smoke。
- 版本化扩展目录不是长期路径合同；正式 worker 必须用显式路径配置与 capability probe，不能盲取 PATH 第一项。

---

## 3. 目标与非目标

### 3.1 目标

- 统一怪物头像身份和资产生成方式，供多个消费者复用。
- 保留怪物 / 变体语义，同时让视觉构图按 context 统一。
- 批量利用 FFDec 和 Luna Max，但让每个结果可复现、可追溯、可人工否决。
- 将人类注意力集中在构图、视觉焦点和异常来源，而不是重复找文件和手工缩放。
- 支持断点续跑、单批重试、增量重建和未来 transport 替换。
- 让 compact 后的新 Agent 可以从仓库文档恢复，而不依赖聊天记录或平台私有记忆。

### 3.2 非目标

- 本评估/复盘文档本身不授权再次批量生成、覆盖或 promotion 生产头像；后续运行必须拥有明确 phase 授权和新鲜闭包。
- 不要求模型直接编辑像素、补画缺失身体或重做美术。
- 不把 FFDec 第一帧默认当作头像帧。
- 不把旧 81 张头像全部无条件当作黄金标准；其中存在尺寸和构图漂移。
- 不通过修改 Codex 模型缓存、伪造 `multi_agent_version`、patch 二进制或全局 `config.toml` 绕过产品限制。
- 不在一个 phase 同时完成 schema、全量资产、Web/AS2 协议和所有消费者迁移。
- 不以脚本退出 0、模型 confidence 或自动几何门代替人类艺术验收。

---

## 4. 数据权威与四层边界

| 层 | 权威内容 | 禁止承载 |
|---|---|---|
| 消费者定义（`enemy_properties` / `pets.xml`） | 默认身份输入与可选显式 `portraitRef` / `PortraitRef` 覆盖 | 输出路径、crop、characterId、模型分数、当前实例变体 |
| identity inventory | `portraitRef + variantKey`、`consumers[]`、来源分类与 required variant 闭包 | 模型建议、人工决定、消费者 DOM / CSS |
| candidate / review / production manifests | SWF / linkage / characterId / frame、source hash、焦点与裁剪、输出、逐次运行与审核 provenance、promotion evidence | 随手维护的运行时业务状态、消费者专用 DOM / CSS |
| Web context 配置 | 画布、mask、padding、安全区、背景、显示尺寸、fallback、不同 UI context preset | 每怪物复制一份身份和 crop 真源 |

### 4.1 默认与覆盖

- 普通敌人：`portraitRef = enemyId`，不写冗余 XML。
- 普通战宠：`portraitRef = Identifier`，不要求 Identifier 命中 `enemy_properties`；pet-only 身份照常进入 inventory。
- 共享头像：在所属消费者定义显式将 `portraitRef` / `PortraitRef` 指向稳定共享身份。
- 来源冲突：使用单独、可审计的 source override；优先修复 linkage 真源并重新生成 map，不手改生成 map。
- 专用头像 symbol：允许 portrait source 与战斗根 MovieClip 分离。
- 变体：identity inventory / production manifest 声明 allowed/required variant；当前选择由运行时实例状态投影。无变体统一使用 `variantKey=default`。
- 合并顺序：先建立 enemy/pet consumer records，再应用显式 identity override，最后按 `portraitRef + variantKey` 去重；任何 consumer 必须且只能落到一个最终身份。

### 4.2 武装 JK 示例语义

概念上应得到：

```text
enemyId = 敌人-武装JK
portraitRef = 敌人-武装JK
variantSet = hair_color
runtime portraitVariant = orange | white
```

`orange` / `white` 是稳定协议键；“橙发 / 白发”只是展示文案。未来精确 XML / wire 字段仍须 ADR 冻结，本文不提前把示例命名变成正式 schema。

### 4.3 母版与派生图

- 母版应透明、无 UI 边框和底色，保留足够安全余量。
- 圆形 / 方形 mask、稀有度底板、背景和 frame 属于 context 展示层。
- 不只提交 32 / 48 / 80px 终端小图；应保留能重新派生的较高分辨率母版和 crop provenance。
- PNG 母版、WebP 派生和精确尺寸仍是开放项，须通过代表性 pilot 比较后冻结。
- 非人形单位使用“视觉焦点”契约，不能强制套用人脸检测。

---

## 5. 候选 manifest 契约

P0 已冻结身份键、消费者映射、逐次模型运行 provenance 和 candidate / review / production 分层；后续 schema 可以增补字段，但不得改变下列闭包：

```json
{
  "schema": "cf7.enemy-portrait-candidates.v1",
  "batchId": "portrait-pilot-001",
  "inputDigest": "...",
  "controller": {
    "version": "...",
    "ffdecVersion": "..."
  },
  "runs": [
    {
      "runId": "proposal-...",
      "role": "proposal",
      "workerTransport": "codex-cli",
      "executableVersion": "codex-cli ...",
      "executableSha256": "...",
      "capabilityProbeDigest": "...",
      "modelRequested": "gpt-5.6-luna",
      "reasoningEffort": "max",
      "inputDigest": "...",
      "promptDigest": "...",
      "outputSchemaDigest": "...",
      "stdoutDigest": "...",
      "resultDigest": "...",
      "status": "accepted"
    },
    {
      "runId": "independent-review-...",
      "role": "independent_review",
      "workerTransport": "codex-cli",
      "modelRequested": "gpt-5.6-luna",
      "reasoningEffort": "max",
      "promptDigest": "...",
      "resultDigest": "...",
      "status": "accepted"
    }
  ],
  "entries": [
    {
      "portraitRef": "敌人-武装JK",
      "variantKey": "orange",
      "consumers": [
        { "kind": "enemy", "enemyId": "敌人-武装JK" },
        { "kind": "pet", "petId": 78, "identifier": "敌人-武装JK" }
      ],
      "source": {
        "swf": "flashswf/arts/new/武装JK.swf",
        "sourceSha256": "...",
        "linkageId": "敌人-武装JK",
        "characterId": 0,
        "frame": 0
      },
      "selection": {
        "focalBox": [0.0, 0.0, 1.0, 1.0],
        "cropBox": [0.0, 0.0, 1.0, 1.0],
        "confidence": 0.0,
        "flags": []
      },
      "outputs": [],
      "automatedGates": []
    }
  ]
}
```

约束：

- 几何坐标必须声明坐标系和范围，禁止同时混用 source pixels、CSS pixels 和归一化坐标。
- `characterId/frame` 必须来自实际 SWF 解析，不由模型猜。
- 模型只能选择 controller 提供的候选 ID / frame；未知候选必须返回错误而不是发明路径。
- 稳定资产 / 审阅单元固定为 `portraitRef + variantKey`；`enemyId`、`petId` 和 `Identifier` 只属于 `consumers[]`，不得重新充当共享资产主键。
- 每个实际模型进程必须各占一个 `runs[]` 记录；A/B、重试和未来的 Terra / Sol escalation 不得合并成一个笼统的 `generator` 或 prompt digest。
- 每个 run 绑定实际可执行文件绝对路径、版本与 hash、请求 model / effort、capability probe、输入 / 图片 / prompt / schema、PID、退出 / timeout、stdout 与最终结构化结果；具体大字段可外置，但内容 hash 必须进入闭包。
- 每个输出绑定内容 hash；原图 URI 不变但字节变化时，旧决定自动失效。
- candidate manifest 一经生成即不可被人审回写；人审决定单独存放并同时绑定 candidate、source 和 review digest。candidate、review 与 production manifest 分离，只有 promotion 过程能生成正式 manifest。
- `pet_46_1.png` 当前只视为未分类 legacy alternate；没有消费者或素材证据前，不得把它推导为 required variant。

---

## 6. 端到端流水线

```text
enemy_properties + pets.xml consumer identities / overrides
        ↓
应用 override 后按 portraitRef + variantKey 去重
        ↓
asset_source_map + SymbolClass resolution
        ↓
按 source SWF 分组的 FFDec 候选帧导出
        ↓
空白过滤 / alpha bbox / 近似帧去重 / contact sheet
        ↓
Luna Max A：帧与 crop 提案
        ↓
确定性 renderer：母版 + 32/48/80px 预览
        ↓
Luna Max B：独立风格与主体复核
        ↓
自动闭包 / 几何 / 缺图 / conflict gates
        ↓
本机 Edge 人工批量审批
        ↓
单一 controller promotion
        ↓
共享 PortraitResolver → 战宠 / 图鉴 / 其他消费者
```

FFDec 风险必须显式处理：

- 空白首帧；
- 父时间线 `stop()` 与自播放子 MovieClip；
- 攻击、死亡、背面或过渡帧；
- 武器、粒子和大特效遮挡主体；
- mask、filter、blend、注册点和嵌套变换；
- 巨大边界、舞台外对象和多主体；
- FFDec 与 Flash Player 的渲染差异。

因此模型输入应是已渲染的候选帧 / contact sheet 和确定性元数据，不是让模型直接浏览 XFL XML 后猜视觉焦点。

---

## 7. Luna CLI Worker 兼容层

### 7.1 为什么不用原生 `spawn_agent`

当前 Sol / Terra 父线程使用 multi-agent V2，Luna 目录元数据属于 V1。Codex 主线已加入 active-backend compatibility filter。该限制发生在 child 创建前：

- 改 `agents.default_subagent_model` 不授予兼容能力；
- custom agent 名称被识别不等于真实 child 创建成功；
- 修改本地模型缓存会被权威远端目录覆盖；
- 伪造 backend 或 patch Codex 会把后续升级、通信协议和审计边界绑到私有 hack。

独立 `codex exec -m gpt-5.6-luna` 是顶层 Luna 任务，不进入 Sol / Terra V2 的 spawned-child 路径，因而是现阶段更稳定的 transport 边界。

### 7.2 可替换接口

业务流水线只依赖：

```text
PortraitWorker.probe() -> CapabilityReport
PortraitWorker.run(batch) -> PortraitWorkerResult
```

首期实现：

```text
CodexCliLunaWorker
```

未来 Luna 若原生支持 V2，再增加：

```text
NativeSpawnLunaWorker
```

通过 `transport=cli|native` 选择。迁移前对同一黄金集双跑；native 没有证明等价前，CLI 保持可用 fallback。

### 7.3 CLI 路径与 capability probe

- 使用任务专用本机配置或环境变量，例如 `CF7_PORTRAIT_CODEX_EXE`；不要 repurpose `CODEX_HOME`。
- 不把某个 `OpenAI.Codex_<version>` 或 VS Code 扩展版本目录写进仓库合同。
- discovery 只能作为引导，选中候选前必须真实运行 `<exe> --version`。
- 每次正式 campaign 记录 executable 绝对路径、文件 SHA-256、CLI 版本、请求模型 / effort 和 probe 结果。
- 静态 probe 覆盖实际使用的 CLI 参数、版本和可执行文件 hash；真实 capability run 再覆盖固定结构化任务、图片输入和 output schema。任一必需门失败则整批 fail-closed。
- 不允许静默降级成 Terra、较低 reasoning effort 或无图片模型。

### 7.4 建议调用形态

```powershell
<codex.exe> exec `
  --ephemeral `
  --ignore-user-config `
  --ignore-rules `
  -m gpt-5.6-luna `
  -c 'model_reasoning_effort="max"' `
  -c 'approval_policy="never"' `
  -s read-only `
  -C <isolated-worker-cwd> `
  --skip-git-repo-check `
  -i <contact-sheet.png> `
  --output-schema <portrait-result.schema.json> `
  --json `
  -
```

实现时必须使用进程 API 的 argv 数组和 stdin，不拼 shell 字符串。理由：

- 避免 Windows 引号、中文路径和命令长度问题；
- 避免 prompt 中 `$()`、反引号或其他文本被 shell 执行；
- stdout JSONL、stderr、PID、timeout 和退出码可以分别处理。

### 7.5 进程与结果闭包

一个 worker 成功至少要求：

1. 可追踪的真实 PID 启动成功。
2. 指定 Luna Max 的请求被 CLI 接受。
3. 在 deadline 内出现最终 agent message；只有启动事件或中间 delta 不算完成。
4. 进程正常退出，但退出 0 本身不够。
5. 最终 JSON 通过 schema。
6. `batchId/inputDigest/promptDigest` 与请求一致。
7. 每个输入实体精确出现一次，零漏项、零多项、零重复项。
8. 所有候选 ID、frame 和路径都来自输入白名单。
9. controller 将结果写入隔离 candidate shard 后再次读取验证。

CLI 在 WebSocket 请求超时后可能先输出可恢复的顶层 `error` / `item.error`，再回退 HTTPS 并以合法 `agent_message + turn.completed + exit 0` 收束。controller 只在唯一成功终态和完整业务闭包同时成立时接收，并把这些中间诊断逐条 hash 记入 run；`turn.failed`、完成后 error、缺最终消息、JSONL / schema / 白名单错误仍 fail-closed。

失败策略：

- 普通格式、闭包或特征占比错误最多使用 3 次有界尝试；每次都是新 PID，第二次起只回传结构化 controller 失败字段和实际/目标占比，不回传另一角色结果。
- 第三次失败、模型拒绝、图片不可读或闭包不完整进入异常队列。
- 不能无限重试，也不能由 controller 补写模型漏掉的业务结论。
- timeout 必须终止精确 worker 进程并检查没有遗留子进程；不得杀宽泛进程名或其他 Codex 会话。

### 7.6 并发和批量

- FFDec 以 source SWF 为批次，避免每个敌人重复解析同一 SWF。
- Luna 以 contact sheet 为批次，建议首轮每进程 4–8 个实体；巨大 Boss / 多主体可单独一批。
- Luna A 与 Luna B 使用独立进程和不同职责提示，不共享前一模型的解释文本。
- controller 提供 `--max-concurrency 1..12` 的全局有界队列，不设小批次栅栏。r7 在本机以 Standard Luna 并发 6 运行，6 条首尝试同时起 PID、零 429/孤儿；含一次闭包抄写重试的墙钟为 732.747 秒，对照 r6 并发 2 / 零重试的 1278.110 秒缩短约 42.7%，无重试主体由最慢分片约束在 476.290 秒。
- `--service-tier standard|fast` 必须显式记录。r8 以 Fast、并发上限 6 跑一个两行小批次，实际只有 A/B 两个独立进程：153.884/187.115 秒，零 429、重试、transport 诊断或孤儿。它证明 Fast 路由可执行，但因输入行数与 r7 不同，不能把官方标称约 1.5× 速度与 GPT-5.6 约 2.5× ChatGPT 配额倍率当作本项目同输入倍率；官方边界见 [Codex Speed](https://learn.chatgpt.com/docs/agent-configuration/speed)。后续完整 atlas / 两阶段实证已覆盖该早期样本，当前基线按阶段拆分，不再使用单一全链路并发值。
- P4 首 shard r2 以 3 个四行小批 × A/B 真正跑满 Fast 6，墙钟 443.8 秒；两个 proposal 首输出被 controller 门控后各用新 PID 修复，因此共 8 attempts、6 个最终接受，0 429/timeout/orphan/survivor，一条修复 attempt 发生可恢复 TLS 重连。该结果支持继续 Fast 6 收集样本，但连接和修复尾延迟已经明确反对立刻提高并发。
- r145 selection-only Fast6 证明 8/8 首答、exit 0、零 timeout/orphan/survivor；同样 Fast6 用于精确 localization 时却出现多轮几何修复、WebSocket timeout→HTTP fallback 和最终 short-axis failure。r149 Fast3 回落后 8 作业/11 attempts 严格闭合，13/13 candidate/orientation 一致；r158/r160 尾批再次以 selection Fast6 4/4 首答和 localization Fast3 4/4 首答通过。故当前冻结 Luna Max / Fast / selection concurrency 6 / localization concurrency 3 / timeout 600 秒，并发 8 未授权。
- worker 只读 source，输出独立 shard；正式 manifest 只由单一 controller 合并。
- 主指标是 `cost/time per human-approved portrait` 和最差分位质量，不是每分钟发起的调用数。

---

## 8. 模型职责与下限优先

维护者对 Luna 的实际观察是：不开 Max 时上下限波动大；本任务更重视可控下限而不是偶发上限。该项目经验优先于通用模型宣传，首轮路由因此冻结为：

| 角色 | 默认模型 | 说明 |
|---|---|---|
| 候选帧 / crop 提案 | Luna Max | 严格 schema、明确候选、批量处理 |
| 独立风格复核 | Luna Max（独立进程） | 只看图、参考和结构化契约，不看 A 的理由 |
| 异常裁决 | Sol Medium / High | wrong subject、复杂 Boss、来源冲突、两路分歧 |
| 试验对照 | Terra Max | 与 Sol Medium / High 比较，不预设生产席位 |
| 最终艺术签署 | 人类 Edge 审批 | 模型 confidence 不能替代 |

为什么不让同一 Luna 自审：

- 同一上下文容易延续首次选择的假设；
- 解释文本会诱导 reviewer 顺从；
- 独立输入仍不能消除同模型相关性错误，但能暴露明显不一致。

首轮模型比较重点看下限：

- 最差 10% 的人工通过率；
- wrong subject / wrong pose / 严重截断率；
- 同输入重复运行的 crop 离散度与 IoU；
- JSON 无效、漏项和重试率；
- 两路 Luna 分歧率；
- 每 100 张需要打开原始 frame context 的数量；
- 每张最终获批头像的时间和使用量。

---

## 9. Edge 人工审批器复用

### 9.1 现役装备审批器提供的能力

仓库已有正式的全量离线装备检视审批流，入口见 [`agentsDoc/testing-guide.md`](../agentsDoc/testing-guide.md) 与 [`launcher/README.md`](../launcher/README.md)：

```text
node tools/build-equipment-inspector-review.js
node tools/test-equipment-inspector-review.js
node tools/open-equipment-inspector-review.js --check
node tools/open-equipment-inspector-review.js
```

其关键模式可直接复用：

- 稳定 ID，不按展示名错误去重；
- `sourceDigest` 绑定输入和真实素材字节；
- `reviewDigest` 绑定候选、构图指标和 gate；
- 每个 artifact 内容 hash 校验；
- partial、stale、缺文件、越界 URI、hash 不符 fail-closed；
- 独立 Edge persistent profile 和按 digest 隔离的 localStorage；
- pending / reviewed / warning 等筛选、搜索、备注；
- 决定 JSON 导入 / 导出；
- 自动阻断项不能用整行按钮批量签署；
- 人审决定只作 QA 证据，不改生产 resolver。

### 9.2 头像审批数据模型

稳定审核单元：

```text
portraitRef + variantKey
```

每行建议显示：

```text
旧头像或黄金参考 | Luna 候选 A/B/C | 32px | 48px | 80px | 原始 frame/contact sheet
```

- 有旧头像：同实体新旧对照，但旧图只作参考，不能掩盖既有错误。
- 无旧头像：按人形、兽形、飞行、巨大 Boss、无头部视觉焦点等类别选择已批准黄金参考。
- 武装 JK：orange / white 是两个 required variant。
- conflict / duplicate / low-confidence / Luna disagreement：强制打开原始 frame context，禁止整行批量通过。

建议状态：

| 状态 | 含义 |
|---|---|
| `pass` | 当前候选通过 |
| `adjustment` | 主体 / 帧正确，需要调 crop / 留白 |
| `wrong_pose` | 帧或姿态不适合作头像 |
| `wrong_subject` | 选错主体、武器或特效 |
| `source` | 缺少合适来源或候选帧 |
| `variant_mismatch` | 状态与头像变体映射错误 |

### 9.3 黄金参考

不能把现有 81 张主头像整体当作同质标准。先人工选约 20–30 张黄金参考，并按至少以下类别分组：

- 普通人形；
- 大体型人形；
- 小型战宠；
- 四足 / 兽形；
- 飞行单位；
- 巨型 Boss；
- 多主体 / 装载体；
- 无明确头部、以武器 / 核心 / 眼部为视觉焦点的怪物；
- 状态变体。

风格检查记录：主体占比、焦点位置、头顶 / 左右留白、头像 / 半身深度、朝向、关键肢体截断、背景 / alpha、与同类参考的偏差。几何指标可自动计算；“焦点是否正确”仍需视觉模型和人类判断。

---

## 10. 状态阶梯与验收边界

建议统一使用：

```text
source_resolved
→ frames_extracted
→ candidate_proposed
→ deterministic_rendered
→ automated_checked
→ human_reviewed
→ promoted
→ consumer_verified
```

严格含义：

- `source_resolved`：来源闭合，不等于 frame 合适。
- `frames_extracted`：FFDec 产物存在且 hash 正确，不等于视觉正确。
- `candidate_proposed`：模型 JSON 合法，不等于候选可用。
- `deterministic_rendered`：小图已派生，不等于风格通过。
- `automated_checked`：尺寸、alpha、边界和闭包门通过，不等于艺术验收。
- `human_reviewed`：当前 digest 的 required 项已人工处置，不等于生产路径已切换。
- `promoted`：审核通过候选被单一 promotion 写入正式 manifest / assets。
- `consumer_verified`：具体消费者 fallback、variant 和实际尺寸已验证；不能从一个面板外推所有入口。

所有消费者必须有缺图 fallback；manifest 加载失败不得让 panel 空白或 JS 抛异常。新旧 resolver 切换必须可审计，不能用“文件恰好存在”冒充协议闭合。

---

## 11. 分阶段施工建议

### P0：路线与契约准备

- **已完成**：本文已冻结消费者并集、portrait identity、默认 / override、variant、母版 / context、fallback、逐次运行 provenance 和 promotion 边界。
- **已完成**：`agentsDoc/data-schemas.md` 的 enemy properties 数量已从错误的 11 修正为实际 14。
- 后续 phase 不得把宠物专属 `Identifier` 丢出 inventory，也不得把消费者 ID 重新提升为共享审阅键。

### P1：CLI worker capability pilot

- **已完成**：[`tools/portrait-worker/`](../tools/portrait-worker/) 已实现显式 CLI path、版本 / hash / 参数 probe、argv + stdin、JSONL、仓库 JSON Schema、controller 二次闭包、最多一次新 PID 重试、timeout exact PID tree 回收、正常退出子进程检查和不可覆盖证据目录。
- **已完成**：纯本地对抗测试 **8/8**，覆盖最后 agent message、未知候选拒绝、A/B 不同 PID、格式失败新进程重试、可恢复 transport 诊断留 hash、`turn.failed`、非法候选和 timeout 子进程树回收。
- **已完成**：当前源码的真实固定 12 项 fixture + `pet_locked.png` 最终报告为 `tmp/portrait-worker/capability-pilot-20260805T132349308Z/report.json`，14,888 B，SHA-256 `4FA30DFDD3A5BAF46D4A05834E9B63B9FD9ED1FC1A241AAF4A9F4F3B95606F8D`，状态 `capability_verified / productionReady=false`。该路径受 `.gitignore` 管理，是本机可复核证据而非 tracked production artifact；旧 `...T114054801Z` 报告因 worker export surface 改变只保留为历史证据。
- 当前 run 绑定 controller source closure `DC45F4587D592E7FE72C0FE4D76762DEE2CFB73113F46DDBE34ACC3EE9A4545E`、Node `v20.12.2`、Codex CLI `0.146.0-alpha.9.2` / SHA-256 `ECD7A3EAFF5E42723DBBA03B5C91514B3986B5DB5CBCA8F34619620B5356F31F`、probe digest `0978E0B2BF0EA48E8614018B9735C71CDB14A194DA90EA32F365436A5AAD10C7`、fixture digest `2221638A75706DC9CC1760C06064312AA10EE3DFE63E7E3C346CA0D200CADF79` 与 schema digest `21AA68DCD5D60CD0BF5B9D5BE88027CFE5632D8EFD7317D6E4E52C05A980F217`。
- A=`proposal` PID `11712` / 130,794 ms，B=`independent_review` PID `29788` / 131,618 ms；两者各记录 5 条 WebSocket timeout → HTTPS fallback 可恢复诊断，均首次进程 exit 0、零 observed descendant / orphan / survivor，通过 exact closure、不同 role prompt digest 和语义一致门。该结果只证明 P1 固定 fixture 的 transport / schema / controller 能力，不证明 FFDec、真实头像选择质量或艺术接受。

### P2：FFDec + 代表性头像 pilot

- **已完成自动部分**：冻结 14 个 identity / 15 个审核单元；12 个可选单元覆盖人形、兽形、飞行、巨大 / 特效 Boss、nested animation 与武装 JK orange/white，另保留 duplicate `敌人-唐头肌肉男`、conflict `敌人-巨臂僵尸`、missing `敌人-Serpent` 三个不可签名来源门。
- **已完成来源净化**：11 个 unique identity 均从 linkage 根首帧解析到唯一命名 `man` 实例并直接导出内部 Sprite，零 root fallback，排除了根级血条 / 等级 / 名字；武装 JK 的 `man` 时间线可见 orange / white 双状态，旧参考实际对应 `pet_78.png=white`、`pet_78_1.png=orange`。P2 用视觉 A/B 提案并要求人确认，不从本地化文案猜状态。
- **已完成候选闭包**：最终批位于 `tmp/portrait-pilot/p2-batched-final-20260805T150000Z/`；`candidate-manifest.json` 为 151,697 B / SHA-256 `3D81F82EB1F2CD63300AC31103EB5EC52B393C31A06DCFAC74BB368C2F9634D9`，manifest digest `6BCA7A2E0F6B2E717C2FA77FC5765F6C39EFF86148C64C9DF2BCBB73E90D6BA4`，source digest `F6AAB5826EA2B3AE3E0E003517CE07DFAEF5235F22DACA257801222E82F076D1`。FFDec `21.1.1` 按 9 个 source SWF 分组，形成 58 张去空 / 去重候选 PNG、15 行总联系表和 3 张各 4 行模型联系表。
- **已完成 Luna A/B**：`model-report.json` 为 51,571 B / SHA-256 `7699A06B217DDE27A2EBAB3CF4773172AD25B7FCA3C5E5C5651A89A4D78ED229`，report digest `589373F0B8A99CE0651F9C5025622DC6AC324BEDFD2D3383927F7B759D0BF3EF`。6 个 Luna Max 首次 PID `10324/4024/31668/17188/29832/7908` 分别耗时 184,261–334,731 ms，每次各留 5 条可恢复 transport 诊断，零重试、孤儿或 survivor；A/B 仅 6/12 同帧，10/12 因帧 / crop 分歧或风险标记进入人审高亮，未被 controller 强制合并。
- **已完成确定性派生与自动门**：`render-report.json` 为 47,565 B / SHA-256 `CC0B9BA75FCB8E9328D8EE122DEB7108EB5603206ED764B52AEEC312BE6CDAC0`，render digest `3B0590CDC01C9E65C5F59FD1AD60C15261305E516E5329F9405F4F3FD9480CF4`；共 24 条 A/B 512 母版 + 80/48/32 PNG 与 80px lossless WebP，PNG 总量 2,754,549 B、WebP 80px 总量 102,708 B，二者口径不同，不外推压缩率。当前严格达到 `automated_checked`，不等于 FFDec 与游戏像素完全等价、构图可接受或艺术验收。

### P3：Edge 头像审批器与特征精修

- **首轮 reviewer 与人审闭包已完成**：最小 dev-only portrait reviewer 复用稳定 ID、source/review digest、artifact hash、按 digest 隔离的 localStorage、筛选、结构化状态和 stale / partial fail-closed。P2 `review-data.json` 为 123,540 B / SHA-256 `F7187739F0CC5D26E799BD917580DC4D92340F8C8CF10B2C387FE1E540BC625B`，review digest `F6F72319D10EFB6806BBE800BCE01C7E69DEBEECBB4D159BD6C987F5A6F8C8A5`；15/15 决定已导出并由 `verify-review-decisions.js` 生成 receipt digest `CC27338E9E659A2BF0C6BFCF21F1C92951E6E727DD13FF532D2F405C5D66AAC5`。12 个 eligible 全部是 `adjustment`，3 个来源阻断全部是 `source`，状态严格为 `human_reviewed_refinement_required / productionReady=false`，不是艺术通过。
- **首轮反馈已冻结为精修输入**：核心否决原因不是简单 crop 数值，而是候选没有明确抓住角色身份特征并给特写。人形默认以头、脸、发型和必要肩颈作为头像特征；非人单位必须推理身份特征，不能机械选择几何中心、最长肢体、尾巴、武器或特效。三头犬的三头是不可拆分特征组；飞行器只有完整轮廓本身构成身份时才用 `full_subject`；机器人锁定黄色中央核心盘，蜘蛛锁定躯干而非长尾。
- **清晰度路线已改为“SVG 几何 + 精确选帧像素”**：首轮 `zoom=2` 候选只继续作为联系表、模型坐标输入和回缩保真度 oracle，不再作为最终像素母版。诊断证明 FFDec `sprite:svg` 可绑定 canvas/坐标，却会漏掉武装 JK 的帧级橙发颜色变换，因此 SVG 禁止作为最终像素。renderer 编译仓库内 `SelectedSpriteFrameExporter.java`，调用 FFDec `FrameExporter` API，只导出所选 `man` 精确帧的自适应高倍 PNG；按模型 viewBox 保留不超过 4096、且至少 1024 的最大真实裁切母版，再 Lanczos 派生 512/80/48/32 和 80px lossless WebP。每帧先回缩到绑定 P2 候选并通过预乘 alpha RGBA MAE≤8；透明 GIF 调色板残留 RGB 被忽略，真实颜色、半透明边缘和轮廓仍受门控。失败尝试写独立 `vN` 目录，不覆盖证据。
- **导出落盘与反馈已收口**：r7 按钮的多次点击实际生成 canonical 文件和多份版本化归档，最终 2,569 B 决策通过 controller 校验；“没反应”是保存成功反馈不够醒目，不是空白或写入失败。新版 reviewer 在保存期间锁定按钮，sticky 状态条显示 canonical/归档精确路径，并由 Edge 回归证明三次快速点击只触发一次原生保存；普通浏览器环境才回退下载。
- **P3 r7 人审已冻结**：批次 `tmp/portrait-pilot/p3-feature-hires-r7-20260806T090000Z/` 的 15/15 决定为 10 pass、R06/R08 adjustment、3 source；decision SHA-256 `4E4CC5B968AFC8DE36E6252850FBA1B35C911AFB139412918D393B1EC0E83815`，receipt digest `6AF3DE119BD3010EF09368ED8743AB47C4680852CABED26C4E40CF02A9CEEDE6`。该状态严格为 `human_reviewed_refinement_required`，不是整组艺术通过。
- **选择性 r8 人审已冻结**：批次 `tmp/portrait-pilot/p3-selective-r8-fast6-20260806T014119Z/` 的 R08 为 `pass`、R06 为 `adjustment`；canonical 与归档均为 838 B / SHA-256 `C2817F53E581C193D0302356375688D7E090FBF09899A8380679AE185FE8002D`，receipt digest `E1E5DA72167F95B0D445E26AA8E008D710DDD598C6266A5D8D033654D42CD663`。R06 人工要求沿用 Luna B 在低分辨率下的尺度倾向，但必须平移并完整保留三颗机械头。
- **r9 自动拒绝、r10 人审已冻结**：r9 的自然语言反馈虽让 A/B 都声称选择完整三头簇，但 512 像素证据仍显示最右头触边，因此没有把同一缺陷再次推给维护者。`feature-refinement.v1.json` 随后为 R06 增加稳定 `reviewKey` 的人工维护锚点，controller 输出校验与 renderer 映射校验同时要求 box 覆盖到候选最右端。r10 批次 `tmp/portrait-pilot/p3-selective-r10-fast6-20260806T021124Z/` 的 manifest/source/model/render/review digest 为 `41D22BDB…C22D / 66CA5D65…98DA / D3C717BF…8C03 / AC723FE2…BF76 / B1078B55…2D5E`；Fast A/B 首次 PID `30552/4340` 分别 86.783/116.392 秒，零 recoverable transport 诊断或孤儿，选帧不同但构图区域完全一致；2/2 高分辨率渲染最大预乘 RGBA MAE 2.2229。维护者最终判断为 `adjustment`，明确“Luna B 构图更好但可能仍需适当放大”；decision SHA-256 `B6776E9D8B3679CB36AFD7E46CA2566061EBEED0F58939FCCBF0596B15ACF71B`，receipt digest `37DD19F1646989B884B363DAB240DDD6EC3D1D76FAF0E1D2633674DCDE2564CD`。
- **人工框选加速支路已真实闭环**：`build/open/verify-framing-guidance.js` 与 `framing-guidance.html/js/css` 将冻结的 adjustment 行变成 A/B 选择 + 完整候选图上的可拖拽/四角缩放/滚轮/键盘像素正方形；允许受限透明越界，右侧 256/80px 直接映射父批 FFDec 高分辨率帧。真实批 `tmp/portrait-pilot/p3-human-framing-hires-r11-20260806T024409Z/` 的维护者导出选择 Luna B `e05-c01/f1` 并收紧到三颗机械头；guidance receipt digest `8CE26419A92D6D8F6E5CB653C0FB8163AD7A9FD7C870C893464D6CC598F59D5B`。数据、localStorage、导出与回执分别绑定 parent receipt、guidance digest、source role、candidate id/hash 和 crop；未确认、stale、错误 hash、非正方形、可见面积不足、低于 1024 真实来源像素和重复保存均拒绝。
- **无模型直接重渲染已真实闭环**：`tmp/portrait-pilot/p3-human-guided-r12-20260806T025309Z/` 消费上述冻结框选，复用绑定 `sourceHighResolution`，实际保留 `2169×2169` 真实来源像素，无放大、无 Luna 重跑，再派生 512/80/48/32 PNG 和 80px lossless WebP；最大预乘 RGBA MAE `2.2229`，render report digest `AE71414F6490534AFBAE25740CA9476D667566B3CD87859BEE2A8A4B690AF82A`。代表集汇总 `tmp/portrait-pilot/representative-closure-r13-20260806T031054Z/` 随后闭合 12/12 eligible、保留 3 source blocker，digest `7B552BD531A775A80669365E8737357807824E9A9D0A87E48C59681ACD814639`；这授权继续异常队列，不等于全量 campaign 或 production promotion。
- 本轮 Luna A/B 仍是代表集精修，不是冻结黄金集后的完整 Luna / Terra / Sol blind benchmark；后者须在新一轮人审形成可接受黄金参考后另行启动。

### P4：全量生成与异常队列

- **inventory 已冻结**：`campaign-inventory-r2-20260806T035243Z/portrait-inventory.json` / digest `DC2637DC…A6FF` 读取 215 条 enemy record、111 条 pet record / 98 个非占位 Identifier，得到 221 identity / 222 review unit；211 unique + 3 人工选源 = 214 可解析，7 missing，0 待选源，0 manual maintenance。该数字只属于当前 digest，不写死成未来发布门。
- **来源选择已冻结**：`source-choice-r1-20260806T030347Z` 的 3 个身份全部选择可渲染命名来源，receipt `FE00136C…803`；选中后仍是 `portraitRef + default`。7 个 missing、无唯一 `man`、专用 symbol、未分类 legacy alternate 和真正状态 variant 继续分队列，禁止混为产品变体。
- **有界首 shard 已到真人评价前**：`campaign-shard-r2-fast6-20260806T035300Z` 从三个高覆盖 SWF 各取 4 个新身份，12/12 精确命中内部 `man`；两个无命名 `man` 的火精灵进入 `resolutionAnomalies`，未回退外层根。manifest/source/model/render/review digest 为 `C8848F60…EFC25 / 8E5E9056…446A / F3A75BD9…9CA2 / 0F09FE46…B03 / 17C1660F…49C3`；24 路高倍渲染最大 MAE `5.5505`，Edge reviewer 自动回归与 preflight 均通过。r1 曾以 12288px 中间全帧上限在唐装剑侠 B 路只能保留约 993px 真源裁切而正确失败；campaign 专用 profile 提升到 16384px 后，r2 的 24 路最大容量需求约 14564px，仍守住至少 1024 真源裁切、最多 4096 保留母版和禁止放大。
- **三轮人审与扩容门已冻结**：r2/r6 都是 3/12 pass、9/12 adjustment；r16 为 4/12 pass、7/12 adjustment、1/12 source。r16 的 7 个框选中 6 个放宽或保持原尺度，直接否定“所有后续都应机械收紧”的假设。累计 24 个真实框选中位倍率 `1.1665925×`、范围 `0.637628–2.345799×`，feedback digest `7FB97C80…A2F4`。人审页不设 6 行上限；扩容只看 `下一批候选身份数 × 估计失败率 ≤ 6`，模型小批最多 4、Fast 并发最多 6。当前 `24 × 0.666667 = 16.000008 > 6`，所以下一批仍为 12 身份 / 3 source groups。
- **第三轮框选与来源负例已闭合**：r16 receipt `A44E72EE…E7E1` 精确冻结 4 pass、7 adjustment、1 source；7 项 framing receipt `692FDB37…E3CD` 经无模型高分辨率重渲染为 report `AEB72A4E…7605`，最大 MAE `5.1761`。`拟态投影` 明确要求拒绝多人重叠帧、先选单人帧再只框完整头部；它保持 source 异常语义，并进入后续视觉图谱负例，不伪装成 pass 或普通 crop。
- **r22 的 12 个框选与 T800 复合修正已闭合**：单页 guidance `campaign-guidance-r24-r22-all-adjustments-20260806T082340Z` 的 receipt 为 `6CE05FF6…7034`；12 个框选由 `render-framing-guidance.py` 无模型重渲染为 report `59895BCF…526F`，最大 MAE `5.9191`。T800 再由 `render-guided-orientation-adjustment.py` 精确绑定 r22 人审、r24 guidance 与该 human-guided report，只对人工框选 supersample 执行 `flip_x_after_human_crop`；report `6F2E167E…8FE`，最终 master 对人工框选 master 镜像 MAE `0`。累计 feedback `6B258CAA…F48B` 现含 36 个框选，中位倍率 `1.349859×`、范围 `0.637628–4.474963×`；r22 的 0/12 pass 令 `24 × 1 = 24 > 6`，下一批不翻倍。
- **v5 shard 人审与 10 个框选已闭合**：`attach-feedback-atlas-v3.py` 动态覆盖此前 48/48 标签：10 pass、36 guided correction、1 orientation-only、1 source anomaly；T800 final 替换原 guided master 且 `guidedOrientationCount=1`，不重复计 adjustment。profile v5 把可识别度置于最高优先级：头通常是主焦点；头弱时允许标志性武器结构、核心或身体特质进入复合焦点；主焦点需位于甜区并留安全范围，弱组件必要时允许顶边/侧边受控裁切。`campaign-shard-r29-v5-feedback-fast6-20260806T085057Z` 的 manifest/source/atlas/model/render/review digest 为 `6B18D88D…D9E7 / D42CB984…821F / 6AD5ECDA…E0A7 / 32FAE269…DEB8 / 0F3D266D…42C0 / 30488E36…0148`。Fast 6 的 6 个 A/B 作业全部首次接受，墙钟 `257.8s`、最长 `257.2s`，0 repair/429/timeout/orphan/survivor，A/B 同候选 4/12；24 路标准高分辨率渲染全部通过主 MAE 门，最大 `6.7576≤8`。人审 receipt `15EE7AF1…8882` 冻结 2 pass、10 adjustment；单页 guidance/receipt/render digest 为 `47847745…C39 / 0A212268…835A / 00D0C11B…E558`。feedback `00BD6B05…A7CD` 现含 46 个真实框选，并以失败率 `0.833333` 计算 `24 × 0.833333 = 19.999992 > 6`，下一 shard 仍推荐 12 身份。
- **v6 shard 人审、框选与方向修正已闭合**：`campaign-shard-r35-v6-feedback-fast6-20260806T093839Z` 的 12 行决定全部是 adjustment，receipt `7CA7FF3A…23D2`。12 项在单页 `campaign-guidance-r37-r35-all-adjustments-20260806T102030Z` 冻结，guidance/receipt 为 `F1C857C5…0A07 / C6301D7D…E86D`；方舟妖姬按维护者后续指令采用当前 `e10-c03/f25` 人工头像，覆盖旧 frame 13 备注。同帧超过 Pillow 默认像素阈值且命中既有二值 GIF alpha 表示差，版本化人工框选 renderer 仍把解码上限绑定 16384²，并只对该精确行采用核心 IoU `0.8674`、重心差 `0.00863` 的例外；12 行无模型 render digest `14D48C31…807B`。恶魔骑士、火焰骑士、重型改造僵尸、铠甲勇士的框选后水平翻转均为 MAE 0。累计 feedback `BC4D213E…70B0` 含 58 个真实框选，失败率 1 令 `24 × 1 = 24 > 6`，下一 shard 禁止翻倍。
- **身份别名裁决与黑无常边界已冻结**：历史 source 备注“先找到单人帧、严格只放头、隔离身体避免审核问题”对应 `敌人-拟态投影::default`。维护者确认它与方舟妖姬是同一单位换皮，可复用一个头像；`freeze-portrait-alias-decision.js` 将来源人审、目标框选/渲染和 `e10-c03/f25` 目标产物绑定为 receipt `1B28306B…7DBC`。该回执明确 `敌人-黑无常索命::default` 不在别名内，仍维持 `named_man_missing_root_fallback_forbidden` 独立异常；别名也只要求未来 consumer `portraitRef` 映射，未写生产 XML。
- **v7 shard 自动阶段与后续人审已闭合**：profile v7 与 atlas v3 覆盖 72/72 人类标签：12 pass、58 guided correction、1 orientation-only、5 guided orientation、1 source anomaly，atlas SHA `6B5D2579…A6DE`；manifest/source/model digest 为 `8ADAB72B…4C17 / 3548E3BB…F539 / 684BA9B8…CA79`。Luna Max Fast 6 共 7 次尝试完成 6 个作业，仅 independent batch-03 因 `RESULT_FEATURE_TOO_SMALL` 修复一次，最长 `239.212s`，0 timeout/orphan/survivor，A/B 同候选 10/12。标准 renderer 在变异犬 proposal 先以 MAE `9.1626>8` fail-closed；隔离 24 路诊断 `7DB1F610…DE6D` 证明只该身份 `e06-c05/f64` 的 A/B 两行超限，二值 alpha 半透明占比 `0.099746`、核心 IoU `0.969183`、重心差 `0.005252`。最终 diagnostic-bound renderer 保留全局 MAE=8，22/24 主门 + 2/24 精确例外，render digest `9F64A19E…C179`。review digest `7EBCF7DC…AF00` 通过 12 行/355 artifact Edge harness/open preflight；后续 receipt `E71AE9BE…235E` 与 r45 人工框选/渲染已闭合 2 pass、10 adjustment。
- **v12 紧凑检索 shard 人审已闭合并进入框选**：r52 的 2 pass / 10 adjustment 已完成 r53 人工框选、r54 无模型渲染和 r55 累计反馈，完整证据现为 96 标签 / 78 真实框选。v10/r57 与 v11/r59 均未生成 model report：后者完整 atlas 输入在两次 300 秒 timeout 后虽正确识别盗贼枪手头部地标，仍以短轴 `0.518136<0.54` 被门控。v12 只把 head short floor 降到 0.50；`derive-compact-model-atlas-v1.py` 仍绑定完整 atlas `9BAD8273…C492D` 和全部回执，但单次偏好图只检索全部 16 pass、最新 10 adjustment、全部 1 anomaly 与全量统计，patch `14,691→4,720`。r62 manifest/source/model/render/review digest 为 `F52067D2…47B0 / 9ED1651C…6241 / 64B896A5…DE67 / 763FD489…14E7 / 6483A638…4974`；Fast 6 用 12 attempts 完成 6/6 作业，4 次几何修复、2 次 timeout、0 orphan/survivor，A/B 同候选 6/12、9/12 高亮。24 路标准渲染最大 MAE `5.4067≤8`。维护者冻结 3 pass / 9 adjustment 的 receipt `A2A99F57…A4BE5`；9 项单页 guidance `26C093C5…BB720` 已通过 123 artifact Edge harness/open preflight，当前等待真人框选。
- **v6 shard 自动阶段与后续人审已闭合**：profile v6 与 atlas v3 绑定五轮 60/60 标签，覆盖 12 pass、46 guided correction、1 orientation-only、1 source anomaly；manifest/source/atlas/model/render/review digest 为 `30FFBB2F…9B93 / DC6A669E…53A4 / D4B94AB3…F616 / 2DE2F6B2…8167 / 255C5723…A8DF / 353F0C13…DEA2`。Fast 6 最终 6/6 接受但共 10 次尝试、墙钟 `825.169s`：1 次值非法、2 次特征占比过小、1 次 timeout，0 orphan/survivor，A/B 同候选 6/12；这轮不支持再提高并发。渲染先发现 179,763,336px 精确帧超过 Pillow 默认硬阈值但仍低于 16384² 合同；版本化 controller 将上限精确绑定到 manifest，而非无限解码。24 路中 23 路通过主 MAE；方舟妖姬 proposal `e10-c03/f25` 的真实 MAE `11.4235`，只因 GIF 二值 alpha 无法表达精确 PNG 的 13.14% 半透明，经核心 IoU `0.8674`、重心差 `0.00863` 的逐角色例外通过。Edge harness/open preflight 验证 12 行/352 artifact；后续 receipt `7CA7FF3A…23D2` 与 r37 人工框选/渲染已闭合 12 adjustment。
- **半透明 fidelity 例外已收窄并保真记录**：24 个高分辨率行中 20 行通过预乘 RGBA MAE≤8；`普通僵尸蛆/e05-c05/f13` 与 `拟态投影/e12-c01/f1` 的 A/B 四行因 GIF 二值 alpha 无法表示精确 PNG 半透明而超限。`render-feature-fidelity-v2.py` 只允许这两个 `reviewKey + candidateId + frame + role`，实体核心 IoU 分别 `0.94871 / 0.832995`、重心偏差均小于 0.007；报告保留真实最大 MAE `23.2791`，不提高全局阈值。两次中间报告因旧 allowlist / digest 自引用被归档为 rejected，最终 v4 报告才进入 review closure。
- **24 身份扩容与全部人类数据复用已实证**：r116 在剩余来源稀疏时把 24 identity 分布到 17 个实际 SWF，仍保持 6 个四行模型批、首帧唯一 `man` 和 24/24 可运行；manifest/source digest `69FD564B…FB71 / 178BF325…AE7B`。r117 atlas v5 绑定 144/144 当前决定并单列诺亚 superseded negative，完整 atlas SHA `44FAD051…A743`；r118-v2 compact v3 将 20,709 个 32px patch 减到 6,313，检索 45 个 review key，manifest/source digest `C6A827BC…9FF4 / EA4F0654…06DD`。selection-only 一次输出只有 prompt digest 相邻字符转置，r119 只按精确转置恢复，recovery/model/lock digest `E93596CE…3B67 / 41B93B7D…E08A / 1E62DBE2…8C8F5`；24 行 A/B 候选一致 13 行。r122 的 24 张原生高分辨率定位 view digest 为 `E1A8956E…B61C`。
- **r125 已完成人审并进入分路纠错**：r121 的 12 个首答全部 transport/schema 有效，24/24 锁帧、23/24 方向一致，但 6 个作业只因 feature occupancy 被严格运行拒绝，且 3/12 缺完整进程退出证据；first-answer report `66F03685…606F` 保留两项 false gate，只允许 7 个精确 role-row 进入真人判断。r123 诊断 48 路中 46 路通过全局 MAE≤8，独狼 A/B 为 `8.214529`；r124 以 alpha MAE `1.850344`、核心 IoU `0.985041`、重心差 `0.001401`、双向 edge recall `0.993615/0.992822` 证明精确矢量/栅格对应，evidence `CB533EA5…A17`，不改变全局阈值。r125 fresh renderer 闭合 48/48、5 个 flip、7 行 occupancy human-review recovery 与 2 行独狼近阈值证据，render/review digest `8E531D95…2F46 / 4BC613FF…2832`。真人回执 `106A8816…EAFE` 为 16 pass / 6 adjustment / 2 wrong_pose。6 条 adjustment 的 r127 guidance/receipt 为 `72842662…EC85 / 47042E62…44F6`，r128 有界大帧无模型 render `479AF12F…1580`，最大 MAE `4.161664≤8`；汽车炸弹以更晚人工语义锁定车尾发动机而非车头。ArmsArius 的源 `e19-c01/f1` 已朝右，r121 A/B 却都错误 `flip_x`；r129 在人工框选后再次镜像恢复朝右，report `51AB99AF…A355`、MAE 0，该样本必须计为 `model_flip_false_positive`。黑白无常 r130 `expand_search` 后由精确人类动作指令收敛到 `血腥死 / Symbol 597 / DefineSprite 591 / frame 249 / flip_x`；r133 A/B 几何 IoU `0.966149 / 0.948909`，r134 有界大帧 render `B7BFC006…4CD`，最终 pass receipt `01F0D648…B458`，方向一致性 receipt `38042FCC…535`。迷你黑洞保留 frame 10，r136 从两路 4096px supersample 生成 gamma `0.50/0.75/1.00` 共 6 个 alpha 候选，黑底合成 max error≤1，dataset `3266ABA3…A8FE`；Edge 回归已过，等待真人选择。
- **尾批并发分层与 168 标签复用已实证**：迷你黑洞最终选择 `independent_review-g075 / gamma 0.75`，r140 将它和黑白无常的两条旧 `wrong_pose` 保留为负例并冻结当前 pass。r143 将 99 条历史框选与 6 条新增框选合并为 105 条；r144 atlas v6 闭合 168 条当前标签（58 pass / 109 adjustment / 1 source）和 3 条 superseded negative，atlas SHA `A93D4846…C29B`；r145 compact v4 将 24,721 patch 降到 9,499。48 identity 扩容目标在可用池尾部被 r142 明确钳制为 13 个唯一 `man`，另有 6 个缺源 identity，历史重叠为 0。selection-only Fast6 的 8/8 首答、exit、orphan/timeout 门通过，墙钟 `504.4s`；但 localization Fast6 出现多轮几何修复、WebSocket timeout→HTTP fallback，最终 7/8 严格闭合并失败，digest `CCCECC32…C3E`。回落 Fast3 且将 structural short-axis floor 明示为 `0.35` 后，r149 以 11 次 attempt 严格闭合 8 个作业，13/13 candidate/orientation 一致，model digest `BEAF4154…D43`。r151 有界 `16384²` render/review digest `23B9A6A1…4B51 / AFE58534…85C4`，13 行 Edge/open preflight 已通过并打开可见页。当前结论是“选帧 Fast6、精确定位 Fast3”，不是全链路 Fast6，更不支持继续提高到 8。
- override / alias 可能让最终产物数少于身份数；必须以当次 inventory digest 为准，禁止再用 210 代表全量。
- promotion 先发布内容寻址 subjects 和 receipt，最后以单文件替换切换 manifest；中断时旧或新 manifest 的运行时引用必须完整，重跑收敛 exact fileset。它不是整目录或多文件事务原子性证明。

### P5：消费者迁移

- 解析与舞台已抽为消费者无关组件：正式入口是 `EnemyPortraits / entity-portrait-art`，旧 `PortraitResolver / team-portrait-art` 只作 Team 兼容；identity/provenance 仍只来自 manifest，布局与业务权威仍由领域消费者持有。
- 佣兵头像另抽为共享 `MercPortraits`：只读消费 `id/gender/height/face/hair/equips` 与 dressup manifest，以 `空手站立` battle rig 生成可缓存胸像；Team 名册/右栏和 Arena 对手共用，同 key 并发合并，旧字段或渲染失败降级为默认外观/剪影，不改变佣兵权威。
- Team 试点已完成：`pet-panel.js` 的名册、世界候选、右栏详情、商店卡与商店预览按 `portraitRef + variantKey` 解析，现代资产失败会逐级回退 SVG→PNG→旧 `pet_<id>.png`→`pet_locked.png`；`merc-panel.js` 的卡片与右栏改用共享佣兵胸像，培养页 live canvas 仍保留完整换装预览。
- JK 优先消费 Host/AS2 稳定 `portraitVariant`；在当前旧 Team snapshot 还未投影该字段时，仅作兼容桥读取 `schemeStatus[切换发型]`。
- Arena 全模式消费者试点已接入正式 P4/P5：自定义目录/已选阵容、标准/堕落/爬升卡及右栏对手都按 roster 类型分流到 `EnemyPortraits` 或 `MercPortraits`；隐藏警报卡不挂载头像，避免身份剧透。完整态每排 2 张，并按阵容顺序展示最多 4 个单位小头像（余量以 `+N` 标记）；紧凑态每排 3 张且仅显示同组首项。密度切换只改变可见投影，不重新抽取阵容或请求 Host；两态都保留人数、等级与经济语义。
- Arena AS2 仅把佣兵 preview 的只读外观投影从 `name/level/equips/skills` 扩为 `id/name/level/gender/height/face/hair/equips/skills`；没有改变 card capability、经济复算、扣款、入场 roster 或战斗权威。定制单位目录 v2 另从静态 `units.json.data` 派生 `主角-*` 的只读 dressup actor，同样不回写游戏数据。通用 production 现已闭合 222 个 human-accepted variant；Arena 消费身份覆盖为 217/217、0 回退锁定图。
- 本阶段证明全目录与全挑战模式组件接通、已有闭合结果全部 promotion、主角模板正确分流、mock-browser 和结构治理；Arena exact identity 已自动闭合，但 mock 页面仍不等于真实 Launcher WebView2→Flash 或游戏内视觉 E2E。
- **Arena 五项直接缺口已完成人审、方向修正与增量投产**：r214 单阶段 Fast3 在有效多模态输出后仅因锯片短轴占比门失败关闭；selection-only 恢复报告/锁分别为 `5C6E8AFE…A609 / 288CBDB7…A28F`，5/5 锁帧。r215 重新绑定原生高分辨率 localization view（source/view digest `72EF7D61…90A3 / 0F86957F…C1C`），Fast3 仍因 feature occupancy 严格失败，failure digest `CB907667…F5B7`；版本化 first-answer 恢复器重新核对 manifest、视图、A/B 角色和全部模型产物后生成仅供人审的 report `AA29F63A…2AAA`，明确保留 `strictFeatureOccupancyAccepted=false`、`humanArtAcceptance=false`、`productionWrites=false`。诊断限定 renderer 为 10 张 A/B 预览标出 5 条 occupancy bypass，render digest `389F7ED3…5B36`；5 行 reviewer 的 review digest `9A5E98AC…037A`，154 个绑定产物通过 Edge、原生保存、重复点击抑制和 open preflight。真人回执 `9D9A4385…8D64` 为 4 pass + 1 adjustment；家用机器人备注“翻转后可用”由 v2 方向修正器生成镜像，report `F2BBDAAD…2EE9`，未重新裁框或调用模型。r219 增量 controller 当时通过 staging 目录切换写入五项，并在进程内 shared manifest 复验失败时尝试回滚；后续复核确认两次目录 rename 之间存在 live root 缺失窗口，现已由 subjects-first / manifest-last publisher 替代，因此该历史批次不得再外推为 crash-atomic。
- **第六项由人类签署 identity alias 闭合**：`敌人-锡蒙利范围光环发生器` 的 linkage 根只到 57×3、6 个可见黑像素的单帧退化逻辑对象，无法证明独立可见怪物；维护者明确批准复用已有真人接受头像 `敌人-锡蒙利::default`。`freeze-arena-portrait-alias-v1.py` 将单位 ID、源帧退化证据和不可变目标 SVG/PNG 绑定为 receipt `AF29A2B5…9ED`；manifest 只登记 alias，不复制主体。

该工程将跨数据、工具、Web、AS2 / Host 协议、资产与文档，明显超过 [`agentsDoc/agent-harness.md`](../agentsDoc/agent-harness.md) 的普通任务软上限，必须按 phase 拆分并保持每阶段独立可验证。

---

## 12. 本轮工程复盘：技术有效性与复用契约

### 12.1 可以确认的技术结论

本轮可以确认的是“受控 Luna 集群路线有效”，而不是“模型已能无人值守完成头像美术”。证据边界如下：

| 结论 | 证据 | 不得外推为 |
|---|---|---|
| 独立 Luna CLI worker transport 可用 | capability fixture、真实多模态 A/B、精确 PID/exit/orphan/schema 闭包均完成 | 原生 `spawn_agent` 已兼容 Luna，或 CLI 路径永久稳定 |
| 高吞吐选帧可用 | selection-only 在 Fast6 多轮闭合，尾批仍保持首答有效 | 所有视觉任务都适合 Fast6 |
| 精确定位可用但更敏感 | localization 在 Fast6 出现修复、timeout 与闭包失败，回落 Fast3 后严格闭合 | Fast6/8 可直接用于定位，或并发越高越快 |
| 人类反馈可被后续批次复用 | 203 条当前偏好、112 条去重几何进入版本化 atlas；C06→C03 supersession 作为负例保留，内部主体 17 项最终全部闭合 | 已完成模型训练、微调或对未知分布的盲测证明 |
| 模型与确定性工具可以形成生产闭环 | 222 个 variant 具有人类接受证据，透明 SVG/PNG、通用 manifest、resolver 与 Team/Arena mock-browser 闭合；Arena exact identity 217/217 | 已完成真实 WebView2→Flash、消费者范围外 2 个 pending、或全游戏艺术验收 |

因此，“Luna 技术有效”的精确含义是：它能在明确候选、结构化 schema、版本化人类偏好、确定性验证与单一 controller 管理下，以显著低于旗舰模型的席位承担批量视觉推理。模型共识、confidence、进程退出 0 和 mock-browser 通过均不能单独替代来源事实、像素闭包或人类签署。

### 12.2 后续头像施工必须复用的最小链路

1. **冻结身份清单**：从消费者数据重新生成 inventory，以 `portraitRef + variantKey` 为审阅身份并绑定 digest；禁止复用文档中的旧数量充当实时数据库。
2. **重新 capability probe**：记录 CLI 路径、版本/hash、模型、effort、service tier、schema、timeout 与实际可用 transport；probe 失败即停止，不静默换模型。
3. **按来源分组提取**：同一 SWF 只解析一次；优先命名 `man` 或经闭包证明的内部主体，禁止为省事退回带血条/等级的怪物根。
4. **拆分选帧与定位**：当前执行基线是 Luna Max/Fast、selection Fast6、localization Fast3、单进程 600 秒；新环境必须先用代表批复验，不能把该值当永久硬编码。
5. **模型只返回结构化意图**：候选、方向、feature/must-include 几何与理由进入独立 shard；模型不得直接写生产图、CSS 或 manifest。
6. **确定性高分辨率渲染**：从精确帧生成有界母版和派生尺寸，校验 alpha、边缘、方向、可见面积、最小真源裁切与 artifact hash；例外必须绑定精确实体和证据，不能抬高全局阈值。
7. **把人类修正变成数据**：pass、框选、方向、换帧、错主体、来源异常和被取代决定分别保留；当前决定与 superseded negative 不重复计数。
8. **减少无意义复议**：人工已经选定帧和框时直接无模型重渲染；扩容使用 `下一批身份数 × 预计复议率 ≤ 6`，不是给页面设置六行上限。
9. **单一 controller promotion**：只有完整 receipt、source/review/render digest 与 required entity closure 通过后，才能先发布内容寻址 subjects 与 receipt，再以单文件替换切换 manifest 这一唯一运行时权威；任一中断点保持当前 manifest 引用完整并允许重跑收敛，不能称为整包事务原子。
10. **逐消费者验收**：Team、Arena 和未来图鉴分别验证 fallback、variant、尺寸、剧透门与实际游戏画面；一个消费者的 harness 不外推到另一个消费者。

### 12.3 已验证的失败模式

- **来源层错误无法靠提示词修复**：多人根、血条/等级、无命名主体、错误 variant 或不存在的素材必须先进入来源/选帧分支。
- **A/B 一致不等于正确**：ArmsArius 两路共同误翻转证明同模型存在相关性错误；方向必须保留源图事实与人工反例。
- **更严格的几何门可能不可实现**：occupancy、must-include 和 safe margin 必须先通过可实现性不等式，不能消耗模型重试后才发现合同矛盾。
- **完整偏好图不一定更好**：atlas 变长会带来超时和注意力稀释；compact retrieval 必须继续绑定完整 atlas 与全部回执，而不是删掉历史证据。
- **低分辨率正确不代表母版清晰**：模型定位 view、审核小图和最终矢量/高倍帧必须分层，禁止把联系表截图放大成生产资产。
- **透明度格式差异会制造假失败**：GIF 二值 alpha 与精确 PNG/SVG 的差异只能用实体核心、边缘和精确 allowlist 收窄处理，不能全局放宽 fidelity 门。
- **保存反馈也是产品链路**：人审按钮必须有明确的保存中、成功路径和版本归档反馈；“页面点了没反应”会直接破坏人工证据闭包。

### 12.4 复用入口与新任务边界

- 新批次规范入口：[`怪物头像生产管线-可复用运行手册-2026-08-09.md`](怪物头像生产管线-可复用运行手册-2026-08-09.md)
- worker/controller：[`tools/portrait-worker/`](../tools/portrait-worker/)
- campaign、review、feedback atlas 与 promotion：[`tools/portrait-pilot/`](../tools/portrait-pilot/)
- 非生产 schema 与当前执行基线：[`agentsDoc/data-schemas.md`](../agentsDoc/data-schemas.md)
- 当前验证入口：[`agentsDoc/testing-guide.md`](../agentsDoc/testing-guide.md)
- 未来语义内容工程：[`怪物知识库与美术导演管线-设计储备与维度讨论-2026-08-08.md`](怪物知识库与美术导演管线-设计储备与维度讨论-2026-08-08.md)

新的怪物知识提取虽然可以复用 worker、digest、独立 shard、单 controller、Edge 人审和自适应扩容，但它是新的文本/多源证据工作负载。头像 selection Fast6 / localization Fast3 只构成调度先验，不能免除新任务自己的 capability、质量和并发 pilot。

---

## 13. 下一会话从哪里开始

P0–P4 的代表集、来源裁决、203 条偏好 / 112 条几何与最终来源排除继续作为 promotion 来源。当前通用生产包 `launcher/web/assets/enemy-portraits/manifest.json` 的 digest 为 `EFDBD928…06E5`、receipt digest 为 `17FC0D9B…0EDF`，闭合 226 identity / 227 variant / 222 human-accepted variant / 2 pending / 1 excluded / 2 aliases，并完整保留 98 identity 的 Team 子集。r219 supplemental closure digest 为 `C70B03A8…8AD3`，基础 manifest digest `EED4D8DC…01D0` 及其 receipt 原始字节由 closure 自包含压缩冻结，不再依赖 ignored tmp。随仓 evidence pack 精确闭合 353 条显式 records + 211 条 digest-bound selected-master 派生记录 = 564 条，其中 560 条属于 `tmp/portrait-pilot` 生产证据、4 条是 tracked controller provenance；25 项不可稳定重建的 JSON/PNG 原始字节进入逐 blob 校验 sidecar。subjects exact-set 由 442 个唯一 runtime 引用与 runtime manifest 的 17 条 preserved 声明组成，其中 12 条仅作 orientation source、5 条 SVG reconstruction basis 同时属于最终 runtime；evidence pack 的 `preservedSubjects` 只含前 12 条。去重并集恰为 454，与 disk/tracked 一致且 extra/missing 为 0。设置 `CF7_PORTRAIT_EVIDENCE_ONLY=1` 的两级 checker 已用于 clean-checkout 语义复验；full-build 回归只证明进程内 promotion assembly，显式不启动父进程 audit hook 无法覆盖的四个历史 verifier 子进程，后者由真实 normal supplement promotion 与 standalone checks 覆盖。promotion 生成器会剥离 FFDec 自闭合空 filter 并写入兼容变换 provenance；这修复了霜精之王 SVG 在 Chromium 中请求成功却全空的问题，resolver 同时保留透明 SVG 像素为空时转 PNG 的运行时保险。Arena 的 217 个消费身份中怪物 manifest 命中 214/214，主角纸娃娃 3/3，合计 217/217 ready、0 受控回退；本次基础与增量阶段的精确回滚位置记录在对应 promotion 输出，不把 ignored backup 路径写成 clean-checkout 权威证据。

原 6 个 Arena 回退项曾按消费身份精确分为 5 个 `no_manifest_entry` 和 1 个 `pending_human_review`；r219 以五项真人接受主体和一项签名 alias 全部关闭，覆盖审计现为 217/217。原 `敌人-lady` 消费拼写仍统一到具有人审资产的精确身份 `敌人-Lady`，3 个 `主角-*` 身份仍通过消费者分流闭合。`敌人-Serpent / 敌人-黑无常索命` 两个 production pending 当前不在这 217 个 Arena 消费身份中，仍须独立收口；未来缺口仍必须分别走素材 rescue、消费者分流或签名 alias，不能直接复用近似头像。

17 个缺失命名 `man` 的身份已完成内部主体救援、定位、人审和 production，而不是退回带 UI 的怪物根。`prepare-internal-subject-rescue-v1.py` 遍历根时间轴及最多三层内部 `DefineSprite`，将复杂度仅用作 high / medium / low 召回先验，并硬排除血条、等级、名字、area 与人物文字信息路径。r184 首轮为 10 pass / 6 adjustment / 1 wrong_subject；六项由 r185 人工框选与 r186 确定性大帧重渲染闭合，霜精之王再由 r187 执行人工框选后的明确翻转。`敌人-dude` 的 C06 只有下肢，旧决定以精确归档和 reconfirmation receipt 保留为负例；r194 对 C03 完整紫色人形的 1/1 pass 是当前唯一决定。v9 反馈 digest `F0A96D6F…0F88E` 闭合 203 条当前标签 / 112 条几何，并明确拒绝继续使用只覆盖 186 条状态的旧 compact atlas。

Luna Max Fast6 随后以 5 小批 × A/B = 10 个独立进程逐行检查全部复杂度层，10/10 首试接受、10 个不同 PID，模型墙钟 `312.224s`。model report digest `2EB883F9…BD94F2`：17/17 都判断存在连贯可辨的怪物主体，16/17 具体 sprite/frame 一致，唯一分歧为 `敌人-闪6特工`——A 选 `sprite 343/frame 37`，B 选根时间轴直连且与 Animate 截图相符的 `sprite 288/frame 5`。因此可以把这 17 项的共同根因表述为“素材封装遗漏统一 `man` 命名”，但 A/B 共识仍不是艺术接受。

人工主体页 review digest `109C2FE3…375FE` 当时通过真实 Edge harness/open preflight：17 张身份卡展示全部 113 个候选、A/B 理由与唯一分歧，模型预选数为 0；17/17 人工决定、后续定位/框选以及 C03 复确认现均已闭合。该页的历史 `awaiting_human_subject_selection` 状态已被 v9 反馈闭包和 `41189961…F7B47` 生产 manifest 取代，不能继续作为当前阻断状态。

尾项批 `team-gap-r171→r173→r174` 当时绑定 186 条偏好，以 Lady/方舟爪豪的首帧 depth-3 内部主体与巨臂僵尸的命名 `man` 避开血条/等级。localization report `B85A017B…326D9` 为 3/3 candidate 与 3/3 orientation 一致，有界大帧 render `EE541E37…7CE4D9` 输出 6 路候选；最终 review digest `CCF52F3A…983D7A` 的 3 条决定全部为 pass，人审回执 digest `8BE01410…E58A6CD`，并在当时写入 Team 包；该历史记录只说明产物闭合，不证明现行或旧版 publisher 具备整包事务原子性。

promotion 的旧朝向传播缺陷实际分为两层。第一层是直接 pass 模型行的 `orientationAction=flip_x` 曾未稳定传到 SVG；第二层是普通人工 framing report 只保存未翻转源空间 crop、没有方向字段，旧 promotion 因而把“人类重新框选”误当成 `keep`，丢失所选 Luna A/B 行已经给出的 flip。第二层确定性影响 4 项：`凤凰眷属大火精灵`、`凤凰眷属火精灵`、`汽车炸弹`、`王牌霜精`。基础 resolver 先按“显式人工后裁切方向 > 显式 correction > 所选模型行方向继承 > legacy 未评估”闭合，再由全量视觉审计把 217 项升级为模型保持或真人方向证据；SVG 与 512px PNG 回退必须同时服从最终动作，不再由人工 crop 的存在与否隐式决定方向。

第一轮确定性传播审计覆盖 217/217 且三类 mismatch 均为 0，但仍有 140 项因早期批次无方向字段标为 `legacy_orientation_unassessed`。后者不是 140 个已知错误，所以对最终 production PNG 发起全量视觉审计，而不是按缺字段批量翻转。

全量视觉审计 r202 把 217 张最终 512px PNG 分为 28 组（每组最多 8 项），用 Luna Max / Fast6 执行 A/B 两套独立盲审；56/56 进程首试完成，无 retry / timeout / orphan。manifest / report digest 为 `77C7B2F6…133A / CB6EF3AE…68F4`：188 项方向判断一致、200 项动作一致；其中仅 178 项满足“两路都 keep 且最低 confidence≥0.75”的模型闭合门，11 项两路都建议镜像，另 28 项分歧、含混或低置信度。模型审计没有修改 production，也不能替代真人艺术判断。

r204 真人方向页 digest `D4555C91…1FA0` 只呈现上述 39 个风险项，左右两栏使用同一 production PNG 的当前/镜像 512px 与 80px 对照，无默认选择。完整导出已由回执 `15828B45…243` 严格闭合为 34 keep / 5 relative `flip_x`；五项为 `ArmsArius`、`忍者BOSS`、`忍者兵`、`汽车炸弹`、`重盾骑士`。这里的 `flip_x` 是“对 r202 生产像素再镜像一次”，不是覆盖基础 `orientationAction`；因此汽车炸弹、重盾骑士和 ArmsArius 从原 flip 回到 keep，忍者兵与忍者 BOSS 从 keep 变为 flip。

最终 r210 `cf7.portrait-orientation-propagation-audit.v1` digest `0D6B0C7F…22C3` 覆盖当时 217/217：0 action mismatch、0 SVG mismatch、0 PNG fallback mismatch、0 legacy visual audit required；178 项由 r202 双路高置信度保持闭合，39 项由 r204 真人裁决闭合。r210 额外绑定空 filter 兼容修复后的当时 promotion controller 与 manifest，生产包同时保留 r202 所需的 434 个素材绑定 / 432 个唯一文件。r219 合法扩展 controller 与 manifest 后，r220 digest `1A10ECD4…DC2A` 曾从原 217 项来源追加五项 supplement 人审选择闭合 222/222；随后 evidence/publisher controller 继续演进，r220 也转为历史快照。当前 r221 digest `DDC843A4…0576` 绑定最终 production manifest 与当前三个 promotion controller，覆盖 222/222，三类 mismatch 与 legacy 仍为 0，来源计数为 178 model keep / 39 human audit / 4 direct pass / 1 explicit human flip。由于 r202 原先引用 live manifest 和当时控制器，r207 artifact-supersession receipt `12D8EF1F…865D` 先冻结 7 个引用对应的 4 份原始字节；旧审计复验必须显式传入该回执，缺回执仍按哈希漂移失败，不能静默放宽。

推荐起点：

1. 在真实战队与竞技场标准/堕落/爬升/定制赛执行 WebView2→Flash 手工视觉验收，特别核对 JK 状态切换、佣兵 battle-rig 胸像、基础五个真人相对镜像项、家用机器人 supplement `flip_x`、透明主体、隐藏卡剧透门、完整/紧凑密度、小尺寸识别度和长目录滚动。
2. 保留 manifest check、Arena 覆盖审计、两套三视口 mock-browser、r221 当前传播审计、r210/r220 历史基线、r202 显式 supersession 复验与人审/来源 digest 闭包作为后续新增怪物的固定 promotion 门，不以模型共识替代人审。
3. 下一轮只处理剩余三项生产 pending：`Serpent` 继续服从“无可实例化成品来源”的排除证据，`唐头肌肉男` 与 `黑无常索命` 分别建立独立来源/主体救援；Arena 另外 8 个非 manifest identity 与 1 个大小写债务走消费者分流或签名 alias。禁止把这 17 项已经闭合的内部主体结果外推给不同来源债务。

---

## 14. 尚未冻结的问题

1. 专用 portrait symbol 与战斗 root symbol 的优先级。
2. 20–30 张黄金参考的具体名单与类别阈值。
3. P4 当前执行基线是 Luna Max / Fast / selection 并发 6 / localization 并发 3 / timeout 600 秒。Fast6 selection 已通过调度门，但 Fast6 localization 命中 transport 与首答闭包回落条件；继续提高到 8 没有授权，后续应分阶段记录 timeout、首答闭合率和真人通过率。
4. 稳定、可执行 Codex CLI 的安装 / 发现方式。
5. P2 已采用最小 dev-only portrait reviewer；是否与装备审批器抽共享框架留待人审反馈后决定。
6. Arena 目录 38px 头像舞台与覆盖率控件已进入 mock-browser 试点；真实游戏中的尺寸、对比度、长列表辨识和最终美术门仍待人工签收。
7. 非 Web / Flash 消费者是否需要 PNG-only 输出。
8. Host/AS2 何时向 Team snapshot 正式投影稳定 `portraitVariant`；投影前的中文 `schemeStatus` 解析只是受控兼容桥。

这些问题必须由 pilot 证据回答，不能在 compact 后被误记成已决策。

---

## 15. 关联资料

仓库内：

- [`怪物头像生产管线-可复用运行手册-2026-08-09.md`](怪物头像生产管线-可复用运行手册-2026-08-09.md)
- [`agentsDoc/data-schemas.md`](../agentsDoc/data-schemas.md)
- [`agentsDoc/as2-web-panel-migration.md`](../agentsDoc/as2-web-panel-migration.md)
- [`agentsDoc/testing-guide.md`](../agentsDoc/testing-guide.md)
- [`agentsDoc/agent-harness.md`](../agentsDoc/agent-harness.md)
- [`launcher/README.md`](../launcher/README.md)
- [`怪物知识库与美术导演管线-设计储备与维度讨论-2026-08-08.md`](怪物知识库与美术导演管线-设计储备与维度讨论-2026-08-08.md)
- [`tools/linkage_scanner/README.md`](../tools/linkage_scanner/README.md)
- [`tools/build-equipment-inspector-review.js`](../tools/build-equipment-inspector-review.js)
- [`launcher/web/modules/equipment-inspector-review/dev/review.js`](../launcher/web/modules/equipment-inspector-review/dev/review.js)

外部当前证据：

- [Codex PR #32751：Restrict spawned-agent models to the active backend](https://github.com/openai/codex/pull/32751)
- [Codex issue #34301：Sol / Terra threads cannot spawn Luna](https://github.com/openai/codex/issues/34301)
- [OpenAI Developer Community 复现与 custom-agent 假阳性说明](https://community.openai.com/t/gpt-5-6-luna-is-advertised-for-custom-agents-but-rejected-by-sol-terra-multi-agent-v2/1389020)
- [Codex Subagents 文档](https://learn.chatgpt.com/docs/agent-configuration/subagents)
- [Codex CLI 参考](https://learn.chatgpt.com/docs/developer-commands?surface=cli#cli-codex-exec)
