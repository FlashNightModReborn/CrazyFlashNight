# 怪物头像统一资产与 Luna CLI Worker 路线评估备忘

**文档角色**：怪物头像共享数据边界、FFDec 离线提取、Luna CLI worker、Edge 人工审批与后续施工恢复的评估备忘。本文用于跨会话恢复和施工前对齐，不替代未来冻结后的数据 schema、生成器 README、测试矩阵或运行时协议 canonical doc。

**状态**：`ROUTE_RECOMMENDED / PILOT_REQUIRED / NOT_IMPLEMENTED`。本文确认推荐路线和禁止项；尚未实现头像 manifest、CLI worker adapter、Edge 头像审批器或任何生产消费者迁移，也未完成艺术验收。

**最后核对代码基线**：commit `f6868722433ddedd0fd39b1dc8595e48d9d18f2c`（2026-08-05）。

**外部能力核对日期**：2026-08-05。Codex 模型目录和 Multi-agent backend 属于可漂移外部能力；每次正式运行仍须重新 probe，本文记录的是当日已验证事实，不是永久产品承诺。

---

## 0. Compact / 新会话恢复入口

发生上下文 compact、换 Agent 或重新开会话时，先按以下顺序恢复，不要从聊天记忆猜测：

1. 读顶层 [`AGENTS.md`](../AGENTS.md)，确认硬约束和当前 Context Pack。
2. 读本文 §1、§2、§7、§9、§12，恢复已定路线、当前证据和下一步边界。
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
当前状态是 ROUTE_RECOMMENDED / PILOT_REQUIRED / NOT_IMPLEMENTED。
不要修改 Codex 模型缓存或伪造 multi-agent backend；不要让模型直接写生产头像。
先复核工作树、CLI capability 和覆盖统计，再只执行当前明确授权的 phase。
```

---

## 1. 决策摘要

1. 将怪物头像建设为可被战宠、图鉴、目标列表和后续 Web UI 复用的共享资产，不继续以 `pet_<petId>.png` 作为 canonical 身份。
2. `data/enemy_properties` 适合作为**头像语义身份锚点**，但不承载 PNG 路径、CSS、裁剪坐标、FFDec characterId 或当前宠物实例状态。
3. 普通敌人的 `portraitRef` 默认等于敌人节点名；只有共享别名、冲突、缺失、专用 portrait symbol 或变体集合需要显式覆盖，避免为 210 个普通条目重复写指针。
4. FFDec 来源、候选帧、焦点框、裁剪框、输出文件、source hash、模型与人工审批证据进入生成 manifest；Web 配置只保存跨实体的展示风格和 context preset。
5. 武装 JK 的橙发 / 白发是实例状态。AS2 / Host 应投影稳定的 `portraitVariant`，Web 不从“橙发 / 白发”等本地化文案反推文件名。
6. 模型只提出帧选择、视觉焦点和 crop；最终像素由确定性 renderer 生成。模型不得默认重绘、补画或直接覆盖生产资产。
7. 现阶段不覆盖 `spawn_agent` 白名单，不改远端模型缓存，也不依赖 `agents.default_subagent_model` 绕过 Luna V1 / Sol-Terra V2 限制。
8. Luna 通过独立顶层 `codex exec` 进程工作，定义为可替换的 `CodexCliLunaWorker` transport，而不是伪装成原生 subagent。
9. 根据维护者实际使用经验，首轮以 **Luna Max** 作为普通提案与独立风格复核的默认配置；Terra 只作对照组，Sol Medium / High 处理异常与争议。
10. 复用现役装备检视器的本机 Edge 大批量审批模式：稳定 ID、source/review digest、持久进度、筛选、结构化决定、partial/stale fail-closed 和人工导出证据。
11. Edge 人审结果只作 QA / promotion 输入，不能由页面点击直接改写生产 resolver 或资产目录。
12. 首轮只批准 capability pilot 和代表性视觉 pilot；在契约、黄金参考和人工审批器冻结前，不进行一键全量生成。

---

## 2. 当前事实与证据快照

### 2.1 战宠头像现状

2026-08-05 只读审计结果：

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

当前 Web 在 [`pet-panel.js`](../launcher/web/modules/pet-panel.js) 多处直接拼接 `assets/pets/pet_<petId>.png`，缺图时回退 `pet_locked.png`，尚无共享 `PortraitResolver` 或 variant selector。

武装 JK 的现役语义链：

- `data/merc/pets.xml`：petId `78`、Identifier `敌人-武装JK`。
- [`单位函数_aka_战宠进阶.as`](../scripts/逻辑/单位函数/单位函数_aka_战宠进阶.as)：`切换发型` 在 `发色=橙|白` 间切换，旧 Flash 头像按标签帧 `gotoAndStop`。
- [`PetPanelService.as`](../scripts/类定义/org/flashNight/arki/merc/PetPanelService.as)：Web 状态投影为 `kind=cycle`、`value=<发色>发`。
- 当前 Web 图片 URL 不消费该状态，因此 `pet_78.png` / `pet_78_1.png` 没有形成状态驱动闭环。

### 2.2 敌人定义与素材来源覆盖

`data/enemy_properties/list.xml` 当前引用 14 个 XML，共有 215 个根定义，其中 1 个是 `默认`，非默认敌人 214 个。

按 [`asset_source_map.xml`](../data/items/asset_source_map.xml) 分类：

| 范围 | unique | duplicate | conflict | missing |
|---|---:|---:|---:|---:|
| 214 个非默认敌人 | 210 | 1 | 2 | 1 |
| 111 个战宠 Identifier | 103 | 0 | 2 | 6 |

解释：

- `unique` 可以进入自动来源解析。
- `duplicate` 是同一 linkageId 在同源内有多个 symbolName，必须审计选择。
- `conflict` 是跨 SWF 冲突，禁止“第一条命中”。
- 非默认敌人唯一 missing 是 `敌人-Serpent`。
- 战宠 missing 为暴走改造僵尸系列、暴走尸母与不知火舞等 6 项；实现前应重新生成清单，不把本文快照当实时数据库。

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

- 不在评估阶段批量生成或覆盖生产头像。
- 不要求模型直接编辑像素、补画缺失身体或重做美术。
- 不把 FFDec 第一帧默认当作头像帧。
- 不把旧 81 张头像全部无条件当作黄金标准；其中存在尺寸和构图漂移。
- 不通过修改 Codex 模型缓存、伪造 `multi_agent_version`、patch 二进制或全局 `config.toml` 绕过产品限制。
- 不在一个 phase 同时完成 schema、全量资产、Web/AS2 协议和所有消费者迁移。
- 不以脚本退出 0、模型 confidence 或自动几何门代替人类艺术验收。

---

## 4. 数据权威与三层边界

| 层 | 权威内容 | 禁止承载 |
|---|---|---|
| `data/enemy_properties` | 稳定 `portraitRef`、语义共享别名、可用 variant set / source alias | 输出文件路径、CSS、裁剪框、characterId、模型分数、当前实例变体 |
| 生成 portrait manifest | SWF / linkage / characterId / frame、source hash、焦点与裁剪、输出、模型和审核 provenance | 随手维护的业务状态、消费者专用 DOM / CSS |
| Web context 配置 | 画布、mask、padding、安全区、背景、显示尺寸、fallback、不同 UI context preset | 每怪物复制一份身份和 crop 真源 |

### 4.1 默认与覆盖

- 普通项：`portraitRef = enemyId`，不写冗余 XML。
- 共享头像：显式将 `portraitRef` 指向稳定共享身份。
- 来源冲突：使用单独、可审计的 source override；优先修复 linkage 真源并重新生成 map，不手改生成 map。
- 专用头像 symbol：允许 portrait source 与战斗根 MovieClip 分离。
- 变体：静态定义只声明 variant set；当前选择由运行时实例状态投影。

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

## 5. 候选 manifest 概念草案

以下只展示信息闭包，不是冻结字段名：

```json
{
  "schema": "cf7.enemy-portrait-candidates.v1",
  "batchId": "portrait-pilot-001",
  "inputDigest": "...",
  "generator": {
    "version": "...",
    "ffdecVersion": "...",
    "workerTransport": "codex-cli",
    "modelRequested": "gpt-5.6-luna",
    "reasoningEffort": "max",
    "promptDigest": "..."
  },
  "entries": [
    {
      "enemyId": "敌人-武装JK",
      "portraitRef": "敌人-武装JK",
      "variantKey": "orange",
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
      "automatedGates": [],
      "humanDecision": null
    }
  ]
}
```

约束：

- 几何坐标必须声明坐标系和范围，禁止同时混用 source pixels、CSS pixels 和归一化坐标。
- `characterId/frame` 必须来自实际 SWF 解析，不由模型猜。
- 模型只能选择 controller 提供的候选 ID / frame；未知候选必须返回错误而不是发明路径。
- 每个输出绑定内容 hash；原图 URI 不变但字节变化时，旧决定自动失效。
- candidate manifest 与 production manifest 分离；只有 promotion 过程能生成正式 manifest。

---

## 6. 端到端流水线

```text
enemy_properties identity / overrides
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
- probe 至少覆盖固定文本响应、图片输入和 output schema；任一失败则整批 fail-closed。
- 不允许静默降级成 Terra、较低 reasoning effort 或无图片模型。

### 7.4 建议调用形态

```powershell
<codex.exe> exec `
  --ephemeral `
  --ignore-user-config `
  -m gpt-5.6-luna `
  -c 'model_reasoning_effort="max"' `
  -c 'approval_policy="never"' `
  -s read-only `
  -C <isolated-worker-cwd> `
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

失败策略：

- 普通格式 / 暂时错误最多用全新进程重试 1 次。
- 第二次失败、模型拒绝、图片不可读或闭包不完整进入异常队列。
- 不能无限重试，也不能由 controller 补写模型漏掉的业务结论。
- timeout 必须终止精确 worker 进程并检查没有遗留子进程；不得杀宽泛进程名或其他 Codex 会话。

### 7.6 并发和批量

- FFDec 以 source SWF 为批次，避免每个敌人重复解析同一 SWF。
- Luna 以 contact sheet 为批次，建议首轮每进程 4–8 个实体；巨大 Boss / 多主体可单独一批。
- Luna A 与 Luna B 使用独立进程和不同职责提示，不共享前一模型的解释文本。
- 初始同时运行 2–3 个 Luna CLI 进程；按 rate limit、内存、延迟和每张获批成本调节，不盲目拉满并发。
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
enemyId + portraitVariant
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

- 本文作为路线备忘。
- 冻结消费者清单、portrait identity、variant、母版 / context、fallback 和 promotion 边界。
- 修复 `agentsDoc/data-schemas.md` 当前仍写 enemy properties 11 文件而实际 list 为 14 的文档漂移。

### P1：CLI worker capability pilot

- 实现 transport 抽象、CLI path probe、版本 / hash、stdin / JSONL、schema、timeout 和孤儿进程门。
- 只用固定小图 / fixture 和 10–20 个结构化任务，不接生产 manifest。
- 验证 Luna Max A / B 独立性、失败语义和重试闭包。

### P2：FFDec + 代表性头像 pilot

- 选择 12–20 个代表实体：人形、兽形、飞行、巨大 Boss、特效遮挡、nested animation、武装 JK 两变体，以及至少一项 conflict / missing。
- 对照 Flash / 游戏可见结果，验证 FFDec 渲染差异。
- 比较母版尺寸、PNG / WebP 派生和 32 / 48 / 80px 可读性。

### P3：Edge 头像审批器

- 抽取装备审批器公共模式或建立同约束的 portrait reviewer。
- 先冻结黄金参考，再进行 blind Luna / Terra / Sol 比较。
- 人工导出的决定必须绑定 source / review digest。

### P4：全量生成与异常队列

- 先生成 210 个 unique 来源。
- duplicate、conflict、missing、专用 symbol 和 variant 单独进入异常队列。
- promotion 原子写正式 manifest / assets，失败保持上一正式版本。

### P5：消费者迁移

- 先把战宠面板从 `pet_<petId>.png` 迁到共享 resolver，并完成武装 JK variant 闭环。
- 再逐个迁移图鉴和其他入口；每个消费者独立验证 fallback、尺寸和 variant。
- 不把全量素材生成与所有消费者协议改动塞进同一提交。

该工程将跨数据、工具、Web、AS2 / Host 协议、资产与文档，明显超过 [`agentsDoc/agent-harness.md`](../agentsDoc/agent-harness.md) 的普通任务软上限，必须按 phase 拆分并保持每阶段独立可验证。

---

## 12. 下一会话从哪里开始

若维护者批准正式开工，下一会话只做 **P0 契约冻结或 P1 CLI worker pilot**，不要直接跑全量 FFDec。

推荐起点：

1. `git status --short`，确认并保护所有用户改动。
2. 复核本文 §2 快照；生成一份机器可读 inventory report，而不是继续把动态计数硬编码进文档。
3. 决定 P1 的 worker 放置位置、输入 / 输出 schema 和 candidate tmp 目录。
4. 决定稳定 CLI 获取方式；不把 WindowsApps / VS Code 版本目录写死进仓库。
5. 写 capability fixture 和 fail-closed 测试，再实现并发调度。
6. P1 全部通过后，才选 P2 代表实体和黄金参考。

开始前必须再次明确授权范围：

- 只做文档 / schema；
- 只做 CLI adapter / tests；
- 或进入 FFDec / 头像 pilot。

没有明确扩权时，P1 不得顺带修改 `enemy_properties`、PetPanel wire、生产头像或 consumer resolver。

---

## 13. 尚未冻结的问题

1. 母版精确尺寸与 PNG / WebP 双产物策略。
2. `portraitRef`、variant set 和 source override 的最终 XML / manifest 字段名。
3. 专用 portrait symbol 与战斗 root symbol 的优先级。
4. 20–30 张黄金参考的具体名单与类别阈值。
5. Luna Max 批大小、并发上限和 timeout 的实测值。
6. 稳定、可执行 Codex CLI 的安装 / 发现方式。
7. output schema 是否由仓库 JSON Schema、TypeScript 类型或两者共同生成。
8. Edge reviewer 是否抽共享框架，还是先复制最小 dev-only 页面再收敛。
9. candidate → production promotion 的原子写入、回滚和清理策略。
10. 非 Web / Flash 消费者是否需要 PNG-only 输出。

这些问题必须由 pilot 证据回答，不能在 compact 后被误记成已决策。

---

## 14. 关联资料

仓库内：

- [`agentsDoc/data-schemas.md`](../agentsDoc/data-schemas.md)
- [`agentsDoc/as2-web-panel-migration.md`](../agentsDoc/as2-web-panel-migration.md)
- [`agentsDoc/testing-guide.md`](../agentsDoc/testing-guide.md)
- [`agentsDoc/agent-harness.md`](../agentsDoc/agent-harness.md)
- [`launcher/README.md`](../launcher/README.md)
- [`tools/linkage_scanner/README.md`](../tools/linkage_scanner/README.md)
- [`tools/build-equipment-inspector-review.js`](../tools/build-equipment-inspector-review.js)
- [`launcher/web/modules/equipment-inspector-review/dev/review.js`](../launcher/web/modules/equipment-inspector-review/dev/review.js)

外部当前证据：

- [Codex PR #32751：Restrict spawned-agent models to the active backend](https://github.com/openai/codex/pull/32751)
- [Codex issue #34301：Sol / Terra threads cannot spawn Luna](https://github.com/openai/codex/issues/34301)
- [OpenAI Developer Community 复现与 custom-agent 假阳性说明](https://community.openai.com/t/gpt-5-6-luna-is-advertised-for-custom-agents-but-rejected-by-sol-terra-multi-agent-v2/1389020)
- [Codex Subagents 文档](https://learn.chatgpt.com/docs/agent-configuration/subagents)
- [Codex CLI 参考](https://learn.chatgpt.com/docs/developer-commands?surface=cli#cli-codex-exec)
