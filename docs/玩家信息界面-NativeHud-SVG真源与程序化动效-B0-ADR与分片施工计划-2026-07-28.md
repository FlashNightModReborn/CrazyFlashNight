# 玩家信息界面 NativeHud：SVG 真源与程序化动效 B0 / ADR / 分片施工计划

**文档角色**：`flashswf/UI/玩家信息界面` 的**视觉资源与 NativeHud 渲染基座专项 ADR + B0 可执行台账**。本文只权威定义 SVG 真源、受控子集、渲染器准入、运行时烘焙、模拟信号 harness、视觉对照与施工分片；状态所有权、AS2/C# 边界、停止线、显示公式和总体迁移阶段仍以 [玩家信息界面 → C# NativeHud 迁移架构](玩家信息界面-NativeHud迁移-架构设计-2026-06-21.md) 为准。

**最后核对代码基线**：commit `7f2431127ba6fec0c8a29d3f0f09ee8d3c79e91d`（2026-07-28）。B0-00 审计入口的历史工作树只含“新增本文 + 同步总体迁移 ADR”两项文档改动；B0-01A r3 由 verifier 分别绑定 `HEAD`、index、clean-filter worktree 与 source-binary anchor；B0-01B r4 静态工具审计则以本行基线核对既有受保护 TestLoader/child 身份。

**当前裁决状态**：高层方案已接受；`Svg.Skia 5.1.1` 是 B0 的唯一候选。B0-01A 已以 Git-canonical r3 证据达到 `placement_closure_frozen`；B0-02 已把 exact lock graph、真实 HP/MP feature anchors、strict facade 和安全/并发/dispose corpus 固化入仓，状态为 `isolated_qualification_passed`。B0-01B r4 捕获工具的恢复安全静态审计已通过，但实际 runner/parser 自身份尚未进入 frozen snapshot，真实 CS6 capture 仍被该 provenance Gate 阻断。B0-01A/02 允许 B0-04 开始转换，但 Flash 截图尚未达到 `oracle_frozen`，`rendererQualified` 仍为 false，不能冒称生产 `renderer_qualified`。仓库当前也**尚未**把该依赖接入 Launcher、产生 canonical SVG、`PlayerInfoWidget` 或新 `pi_*` 协议。本文落盘不等于 B0 代码完成。

---

## 0. Compact 后恢复卡

### 0.1 一句话目标

把 Flash HUD 中的**静态矢量美术**一次性转换为可审阅、可版本化的 SVG 真源；启动后按真实 viewport / DPI 将静态层烘焙为 PArgb 位图缓存；数值条、裁切、缓动、闪烁与循环光效由 C# 程序状态机组合，不保存逐帧 PNG/SVG。

### 0.2 当前精确状态

- 已完成：本 ADR、B0 分片边界、依赖准入门、runtime build identity 纳入方案与验收词典；Kimi k3/max 的首轮完整文档异构审计见 §9.5。
- 已完成：B0-01A r3 把 HP/MP placement closure/source-binary ancestry 固化入仓；独立 verifier 从 XFL 重建 17 个定义边/18 个路径展开边，复算 Git-canonical digest `6f4bf9f36563c1bd16993c7472c4ebf49321852ab19eebb0bdf6b58df9264368`，并绑定 index/worktree/anchor。它不等于 `oracle_frozen`。
- 已完成：B0-02 隔离资格化（10/10、16 项 fail-closed、exact XFL feature anchors、依赖/许可/native/payload 结构化审计）；它不等于生产 `renderer_qualified`。
- 已完成窄中间态：B0-01B r4 静态工具通过 AST、协议/PNG/事务负例与独立恢复安全审计；它尚未冻结实际 runner/parser 自身份，未启动 Flash，也没有 accepted capture。
- 未完成：可重复的独立 Flash 状态截图、生产受控 SVG validator 复用、转换器、canonical SVG、运行时 bake/cache、fixture widget。
- 未接受：`Svg.Skia 5.1.1` 作为生产依赖。它必须先完成 B0-02 生产级 strict facade/corpus Gate；通过后才在 B0-03b 写入中央包版本、项目引用和 lockfile。
- 未改变：AS2 游戏状态/输入/冷却权威、`FrameBroadcaster` 协议、旧 HUD 可见性、药剂拖放命中壳、正式 runtime。
- 总体视觉交付严格状态：`planned`；分片允许另记 `evidence_ready` / `renderer_preflight_passed` 等较窄中间态。不得把这些中间证据写成 `fixture_static_parity`、`fixture_full_parity`、`runtime_integrated`，更不得写成已部署。

### 0.3 权威顺序

1. [AGENTS.md](../AGENTS.md)：仓库硬约束、编译与 runtime 发布口径。
2. [玩家信息界面迁移架构](玩家信息界面-NativeHud迁移-架构设计-2026-06-21.md)：业务权威、停止线、显示公式、总体阶段。
3. **本文**：SVG / renderer / bake / fixture / B0 分片权威。
4. [launcher/README.md](../launcher/README.md)：已经落地的 Launcher 结构与现役验证入口；候选方案不得提前写成现状。
5. 实际代码、新鲜测试输出和冻结发布证据。

若本文与第 2 项冲突，以第 2 项为准并先修本文；若计划与代码现状冲突，以代码和新鲜证据为准并回写两份文档。

### 0.4 冻结决策摘要

| ID | 状态 | 决策 |
|---|---|---|
| HUD-SVG-001 | accepted | SVG 是 HUD 静态矢量美术的 canonical source；运行时位图只是可丢弃派生缓存 |
| HUD-SVG-002 | accepted | 不导出逐帧 PNG，也不把 Flash 时间轴逐帧翻译成 SVG 序列 |
| HUD-SVG-003 | accepted | 动态条、裁切、缓动和明显循环动效用代码表达；SVG 自身不承载动画 |
| HUD-SVG-004 | accepted | 只转换运行时活跃 placement closure；“库里存在”不等于纳入 |
| HUD-SVG-005 | provisional | `Svg.Skia 5.1.1` 是唯一候选；B0-02 通过后才成为锁定生产依赖 |
| HUD-SVG-006 | accepted | 首版 SVG/manifest 作为 Core 的 embedded resource；源文件与依赖共同进入 runtime build identity |
| HUD-SVG-007 | accepted | B0 可 fixture-first，但真实接入仍必须 state-first，不新增第二业务权威 |
| HUD-SVG-008 | accepted | 旧 Flash HUD 在双轨期继续作为独立视觉 oracle 和剩余命中壳 |
| HUD-SVG-009 | accepted | B0 不写双栏装备工作台、药剂管理和旧 XFL；可与另一台机器的装备栏迁移并行 |

`provisional` 只能由对应 Gate 变为 `accepted` 或 `rejected`；不得因“能 restore / 能显示一张 SVG”自动转正。

### 0.5 硬停止线

本文严格区分三种帧口径：`DOM max index` 是 XFL XML 中最大的零基 `DOMFrame@index`；实际 timeline span 要按每层 `max(index + duration)` 取值；`display frame/state` 是 Flash 一基播放头可达状态；`ratio step` 是显示公式的比例格数。四者不得互换。HP/MP/韧性的公式步数分别是 128/100/30，不能由此反推每个 symbol 的 DOM 最大 index 或 timeline span。

- 禁止把 HP/MP/韧性的时间轴状态批量导成发布用 PNG/SVG 帧序列。
- 禁止在真实 viewport、letterbox 和 DPI 未知时制作一套固定倍率“最终 PNG”。
- 禁止让 SVG parser 在每帧或每次数值变化时重新解析/栅格化静态层。
- 禁止在 fixture 阶段新增真实 `pi_*` wire 字段、读取游戏权威或隐藏旧 HUD。
- 禁止转换整座未放置的 Flash library；必须从舞台实例追 active closure。
- 禁止加载脚本、SMIL、`foreignObject`、外部 URL、外部字体、CSS import 或嵌入位图。
- 禁止用同一转换产物自证视觉正确；参考图必须来自独立 Flash/CS6 运行或经人工确认的源截图。
- 禁止把 `launcher/build.ps1` 成功写成部署；发布词典见 §10.3。

### 0.6 Oracle 轨下一张工单

**B0-01A：把已核实的 HP/MP 活跃 placement closure 与 source-binary ancestry 固化入仓。**

输入是当前 XFL/XML、现有 UI/main/asLoader SWF 与 Git 历史；输出是 exact placement 清单、源矩阵/注册点、脚本可达边、source hashes 和 repository ancestry。此片只读旧资产，不引依赖、不改 Launcher、不改 AS2；完成后只可声明 `placement_closure_frozen`，不能声明 `oracle_frozen` 或 SVG parity。

精确 HP/MP 比例状态目前没有安全、确定性的只读注入入口：`/console` 权限过宽，真实存档也不保存可复现实例态。B0-01B 因此另用**测试专用** TestLoader scratch/fixture 驱动已发布 child SWF，固定 HP/MP frame、文字以及三个装饰播放头；静态 corpus 中 light 固定后隐藏并回报 hidden。它不得接生产 `AgentControl`、不得读写真实存档、不得修改旧 XFL。只有截图、实际 loader/player/SWF/closure 身份和人工复核均闭合后才可声明 `oracle_frozen`。

---

## 1. 问题、目标与边界

### 1.1 已核实的资产地面真相

| 资产 | 审计快照 | 工程含义 |
|---|---|---|
| `LIBRARY/sprite/主角hp显示界面.xml` | 约 1.00 MB；145 个 `DOMFrame` 节点，DOM max index 129；132 个 shape、6 个 symbol instance；首帧含长 duration | 大量空间来自手工时间轴状态，不应等量转成图片 |
| `LIBRARY/sprite/主角mp显示界面.xml` | 约 92.4 KB，DOM max index 100，含 shape tween | 应保留形状语义并把 morph/clip 参数化 |
| `LIBRARY/UI重构/主角韧性UI.xml` | 约 75.3 KB，DOM max index 30 | 可由比例 + 少量破韧状态程序化 |
| `LIBRARY/sprite/Symbol 1859.xml`（经验） | 约 43.5 KB，DOM max index 100 | 连续进度无需按时间轴状态复制资产 |
| `LIBRARY/UI重构/血槽相关/血槽光效.xml` | 约 115.4 KB，DOM max index 150，约 101 个 shape | 循环相位比逐状态摆放更可维护 |
| `DOMDocument.xml` | 舞台为 1024×64 / 30fps，注册两个 `DOMBitmapItem`；主体大量使用路径、渐变、矩阵和 symbol | 只支持“HP/MP 值得验证 SVG-first”的假设，不能外推整个 HUD 均为纯矢量 |

这些数字是 B0 范围判断证据，不是运行时 placement 证明。最终转换清单必须由 B0-01A 从舞台 placed instance 向下追闭包。

两个 bitmap payload 并未缺失：`bitmap1804 → bin/M 2 1716646761.dat`（69 B），`bitmap1805 → bin/M 1 1716646761.dat`（81 B）。已核实 B0 的 HP/MP 子闭包分别只有 10/5 个 symbol、均为 0 个 `BitmapFill`；整座 HUD 中作为二者同级直接实例的 `sprite/玩家必要信息界面` 子闭包则命中 4 个 `BitmapFill`、2 个唯一 bitmap。因此它不阻断 B0 的 HP/MP 纵切，但 B2 扩到“玩家必要信息”时必须重新审计并按 §1.3 另裁，不能因 `LIBRARY/image/` 不存在就误报 payload 缺失。

“active closure”也不能退化为首帧图搜索：`视觉系统_fs_显示列表引擎.as:75-77` 会显式推进 HP 下的 `血槽内动画`、`网格动画`、`血槽光效`。三者 timeline span 分别为 100/11/216；其中 `血槽光效` 的 DOM max index 虽为 150，长 duration 令 span 达 216，正说明帧口径必须分开。B0 静态纵切可以把它们列为 deferred effect 并冻结首帧，但 B0-01A provenance 必须保留这三条脚本可达边，不能把它们误报为 unused。

### 1.2 目标

- 让美术形状、渐变、描边、裁切、层级、注册点和语义 layer ID 成为可 diff 的文本真源。
- 把“美术是什么”与“数值如何变化/动画如何走”分离。
- 让 SVG 解析成本只发生在冷启动、首次尺寸或 DPI 桶变化时，稳态绘制走现有 NativeHud 位图路径。
- 在真实 AS2 信号接入前，用确定性 fixture 跑通布局、比例、异常值、DPI、透明度和缓存生命周期。
- 每一片独立可审阅、可回退、可陈述未验证项，支持跨机器并行和会话 compact 后恢复。

### 1.3 非目标

- B0 不迁移输入、冷却、技能装备、药剂拖放或任何写权威。
- B0 不删除/改空旧 SWF，不修改旧玩家 HUD/主 XFL placement，也不把测试发布物当游戏资产；B0-01B 允许精确发布 TestLoader 测试目标，只有 §6.4 来源新鲜性无法闭合时才允许对独立玩家信息 UI XFL 做一次精确 publish/verify 取证。
- B0 不建设通用 Flash/XFL → SVG 编译器；只支持玩家信息 HUD 实际命中的受控子集。
- B0 不把原生 bitmap 强行“描摹矢量化”。若后续闭包确有不可消除的 raster，须另开 ADR；不能用 `<image>` 偷渡进当前子集。
- B0 不决定攻击模式未知标签、第五药剂视觉槽等业务行为；沿用总体迁移 ADR。

---

## 2. ADR：资源、行为与权威切线

### 2.1 SVG 是真源，位图是缓存

canonical 文件保存 SVG + manifest，不保存每个倍率的发布 PNG。B0 只有单一 premultiplied BGRA/PArgb 与单一色彩合同，运行时派生位图的 cache key 保持为：

```text
assetSetDigest + layerId + pixelWidth + pixelHeight
+ rendererIdentity + rasterContractVersion
```

像素尺寸最终必须吸收 viewport、letterbox、DPI 和 HUD scale；不得只按 “100% / 125%” 文本标签缓存。若未来真的引入第二种 alpha/color contract，必须先递增 `rasterContractVersion` 并再决定是否扩 key，不为假想模式预埋恒定字段。当前 widget `Paint` 的 `dpr` 参数仍固定传入 `1.0f`，所以 B0-05 必须先冻结“1024×64 逻辑 HUD → overlay 最终物理像素”的 scale contract，不能直接把现有 `dpr` 当真。布局/DPI 改变时异步生成新 key，生成成功后原子换入；失败时保留上一张可用缓存或旧 Flash HUD，不能显示半张/空白层。

### 2.2 时间轴不再是资产容器

Flash 帧只在转换期承担两种角色：

1. **视觉 oracle**：选取离散状态对照新 renderer。
2. **行为取证**：提取比例映射、关键状态和循环相位。

发布资产不保留完整时间轴。HP/MP 等条由 normalized state 驱动 clip/geometry；旧 128/100 格映射先作为“虚拟帧状态机”程序化复刻，以保持双轨行为，再在单独行为 ADR 中讨论是否改为时间制连续 easing。

### 2.3 B0 fixture-first 不推翻 state-first

B0 fixture 只提供测试输入：

```text
PlayerInfoFixture → PlayerInfoVisualState → PlayerInfoWidget
```

真实接入仍只有：

```text
AS2 PlayerInfoState(cur/target)
  → frameEnd 批量 FrameBroadcaster.pushUiState
  → NativeHudOverlay full snapshot
  → PlayerInfoWidget
```

fixture adapter 与 runtime adapter 只能实现同一个只读 visual-state 接口；fixture 代码不得进入生产数据源选择，不得反向写游戏。B0 是总体阶段 4/5 的无业务信号预备切片，不是重开已经完成的“阶段0 行为基线”。

### 2.4 首版使用 embedded resource

首版 canonical SVG 和 manifest 通过显式 `EmbeddedResource` 进入 Core：

- 源 SVG/JSON 进入 artifact source hash；
- 编译后的资源进入 Core DLL，因而进入 payload closure；
- 运行时不依赖松散文件相对路径，也不存在“源码变了但安装目录漏复制”的第二闭包；
- 正式替换仍须走 immutable request、双 signer / 双 faultDomain、promotion 与标准入口复核。

若未来需要独立皮肤包或热替换，再另立带签名 asset bundle 协议；B0 不预埋未受控 override 目录。

### 2.5 SVG 不承载 runtime text DOM 与图标系统

- HP/MP 数字、`%`、`/` 等固定字符集优先保存为 SVG path glyph atlas，由代码排版并程序化实现 glow；不使用 runtime `<text>` 或机器字体 fallback。
- 角色名和任意中文不塞入 SVG；到 B2 再冻结 NativeHud 字体、fallback 与测量合同。
- 静态字样若无法消除，转换为 path。
- 技能/药剂/物品图标继续服从各自图标真源与 linkage/缓存管线；本 ADR 不把 raster icon 包一层 SVG 冒充矢量真源。
- B0 首纵切只覆盖 HP/MP 的静态壳、填充、遮罩和必要文字布局框。

---

## 3. 目标拓扑

```text
作者侧 / 一次性迁移                         Runtime / 每次启动

active XFL placement closure
  ├─ XFL/XML geometry + matrix
  └─ 独立 Flash oracle screenshots
            │
            ▼
player-info-hud converter ── validate/fail-closed
            │
            ├─ canonical *.svg
            ├─ runtime manifest ───────────────┐
            └─ repo-only provenance/oracle     │
                                               ▼
                                    Core embedded resources
                         │
                Svg.Skia parse to SKPicture
                         │  只在首次尺寸/DPI key
                         ▼
             Format32bppPArgb Bitmap cache
                         │
fixture / PlayerInfoState ── visual state machine
                         │  clip / transform / alpha / text
                         ▼
                PlayerInfoWidget.Paint
```

`Svg.Skia` 只负责受控静态 SVG → Skia display list / bitmap，不负责业务动画时钟，不启用 JavaScript 包，不把 SVG DOM 暴露为运行态游戏模型。

---

## 4. Canonical asset contract

### 4.1 计划目录

```text
launcher/src/Guardian/Hud/PlayerInfo/
  PlayerInfoWidget.cs
  PlayerInfoVisualState.cs
  PlayerInfoAnimationModel.cs
  PlayerInfoSvgRasterizer.cs
  Assets/
    player-info.manifest.json
    hp/backplate.svg
    hp/fill.svg
    hp/rim.svg
    mp/backplate.svg
    mp/fill.svg
    mp/rim.svg

tools/player-info-hud/
  README.md
  fixtures/
  evidence/
    b0-01/
      closure.json
      source-binary-chain.json
      oracle-manifest.json
  src/

launcher/tests/Guardian/Hud/PlayerInfo/
```

这是目标形态，不代表目录已存在。闭包规模很小，B0 不另建一套通用 JSON Schema 目录；manifest/closure 规则由窄 validator 与 focused tests 持有，只有 B2 扩域后出现第二个真实消费者才考虑抽出 schema。测试子目录是有意建立 PlayerInfo 专属 fixture/corpus 边界；B0-03b 必须验证现役 test runner 会递归收集它，若不会则沿用 `launcher/tests/Guardian/` 平铺，不为目录美观另造入口。中央高冲突文件（csproj、包版本、lockfile、runtime inputs）只能在 B0-03b 单独落，不和 widget/美术混一片。

### 4.2 Runtime manifest 与 provenance evidence 分离

不得把运行时渲染合同与审计来源混成同一个 embedded blob。否则源 commit、重采 oracle 等非渲染变化会无意义地改变 Core payload。B0 固定为两份合同：

1. **Embedded runtime manifest**：只记录运行时选择与校验所需的 `schemaVersion`、`assetSetId`、内容导出的 `assetSetRevision`、`rasterContractVersion`、每个 SVG SHA-256、原始 bounds/registration/unit scale/canonical `viewBox`、稳定 layer ID/绘制顺序/blend/opacity/cacheability、gauge 方向与 clip 语义/normalized 边界，以及 renderer 精确已验证版本和 SVG feature-set ID。
2. **Repo-only provenance/oracle evidence**：记录原始 XFL 路径、symbol/linkage、完整 placed instance path、源 Git tree/blob ID 与 closure SHA-256、converter/规范化规则版本、独立 oracle 场景和文件 hash，以及 §6.4 的捕获环境。它接受“重新取证即形成新证据 revision”，不进入 Core embedded resource，也不参与运行时资产选择。

两份文件均不得记录本地绝对路径或机器名。runtime manifest 不得记录源 commit、生成时间戳、oracle hash 等与渲染字节无关的字段；相同 runtime 输入重跑必须 byte-stable。provenance evidence 的源身份使用 Git blob/tree OID + SHA-256，不用含糊的“当前 commit”代替实际闭包。

### 4.3 稳定语义 ID

首纵切固定使用语义而非 Flash 临时库名，例如：

```text
hp.backplate / hp.fill / hp.rim / hp.highlight / hp.clip
mp.backplate / mp.fill / mp.rim / mp.highlight / mp.clip
```

转换器可以读取旧 symbol 名，但产物 ID 由 manifest 显式映射，不能依赖遍历顺序、库序号或自动生成的 `Symbol 1859`。

### 4.4 受控 SVG 子集

**B0 core 允许**：

- `svg`、`g`、`defs`、`path`、基础几何；
- `linearGradient`、`radialGradient`、`stop`；
- `clipPath`；
- `fill`、`stroke`、`opacity`、`fill-rule`、`clip-rule`；
- `viewBox`、`preserveAspectRatio`、显式 transform matrix；
- gradient units/transform、stop alpha，以及素材实际需要的 `spreadMethod="reflect"`；
- 仅指向同文件 `#id` 的 `use`，且 converter 可选择展开。

**必须单项 Gate 后才允许**：`mask`、`pattern`、filter primitive、blend mode。首版能用几何/alpha layer 表达时不启用这些特性。

**一律拒绝**：

- script、事件属性、SMIL/CSS animation、`foreignObject`；
- `image`、外部 stylesheet、`@import`、外部字体；
- HTTP/file/data URL、跨文件 href、DTD/entity；
- runtime `<text>`、系统字体 fallback；
- 未知元素/属性、超出深度/节点/尺寸上限的文档。

validator 必须先于 renderer，遇到未知特性 fail-closed；不允许“忽略警告后看起来差不多”。

现存 Glow、Bevel 与 HP `blendMode="overlay"` 不得静默丢失：数字 Glow 归 glyph/native 绘制，静态 Bevel 必须展开为路径/渐变或使 B0 失败，overlay 光效显式标为 B3 程序化职责。B0 可用独立 mask 排除该 deferred effect 做静态 parity，但只能声明 `fixture_static_parity`，不能写“全效果 1:1”。

### 4.5 数值与规范化

- 保留路径和矩阵所需精度，B0-01B 先用 oracle 证明允许的 decimal rounding，禁止肉眼决定全局小数位。
- 渐变默认落为 `userSpaceOnUse` + 显式 transform，避免 object-bounding-box 在不同 renderer 下漂移。
- 负 scale、旋转中心、注册点和 nested matrix 必须先合成测试，再决定是否 flatten。
- canonicalizer 固定属性顺序、ID、换行、颜色格式和数字格式；默认 `--check` 只报 drift，显式 `--write` 才覆盖。
- 初次转换后 SVG 成为维护真源；旧 XFL 保留为 provenance/oracle。以后不会在每次 build 隐式从 XFL 重生成并覆盖人工维护。

---

## 5. Renderer 准入与依赖治理

### 5.1 候选

候选固定为 [`Svg.Skia 5.1.1`](https://www.nuget.org/packages/Svg.Skia/5.1.1)，上游仓库为 [wieslawsoltes/Svg.Skia](https://github.com/wieslawsoltes/Svg.Skia)。选择理由是它以 SkiaSharp 为后端、能输出 `SKPicture`/位图，并声明 SVG 1.1 静态基线与 SVG 2 静态子集。

这不是“当前最新版本自动跟随”策略。版本升级必须另开依赖审计和视觉回归；禁止 floating range。

### 5.2 B0-02 必查闭包

仓库当前直接锁定 `SkiaSharp 3.119.4`。`Svg.Skia 5.1.1` 的 NuGet 闭包至少涉及：

- `SkiaSharp >= 3.119.2`；
- `HarfBuzzSharp` 及 Win32/macOS/Linux native assets；
- `Svg.Animation`、`Svg.Custom`、`Svg.Model`、`Svg.SceneGraph`、`ShimSkiaSharp`、`ExCSS`。

许可也不是“全闭包 MIT”：[`Svg.Custom 5.1.1` NuGet metadata](https://api.nuget.org/v3-flatcontainer/svg.custom/5.1.1/svg.custom.nuspec) 使用 MS-PL；至少 Win32 HarfBuzz native package 的 NuGet 元数据要求 license acceptance。B0-02 必须把实际 lock graph 的每个包、许可和分发义务逐项审阅，不得只抄顶层 [`Svg.Skia` metadata](https://api.nuget.org/v3-flatcontainer/svg.skia/5.1.1/svg.skia.nuspec) 的 MIT。

因此不能把它当成“只多一个 DLL”。B0-02 必须记录：

- 最终 Windows x64 restore graph、实际解析版本、包 hash、license、deprecated/vulnerability 结果；
- publish 后新增/变化文件与字节数，非目标平台 native asset 是否进入 payload；
- 与现有 SkiaSharp 3.119.4 ABI/NativeAssets 的一致性；
- 未引用 `Svg.Skia.JavaScript`，脚本执行路径不可达；
- trimmed/single-file 设置若有变化时的反射与资源保留行为；
- 失败 SVG、恶意外链、超深 XML、重复 parse/dispose 的结果。

2026-07-28 的 ignored `tmp/` 隔离预检已取得以下**前置证据**：完整候选图新增 11 个包节点，现有 `SkiaSharp 3.119.4` 未变；producer-shaped win-x64 payload 新增 9 个文件、5,289,528 B，未带入非 Windows native；locked restore、reflect gradient、clip/local `use`、Premul BGRA、独立并发 parse、共享只读 draw 与两批各 500 次 dispose smoke 均通过，漏洞/弃用扫描为零。该结果只允许记为 `renderer_preflight_passed`，因为生产 validator/wrapper、从 HP/MP closure 提取的真实 feature qualification corpus、identity/policy 尚未入仓，不能提前记 `renderer_qualified`。

预检同时证明**不能依赖库默认值**：`DisableDtdProcessing` 默认为 false，external resource policy 默认为 Enabled，broken-image placeholder 默认开启，外部 JavaScript 子开关默认开启（即使总 JavaScript 开关默认关闭），alpha 默认 Unpremul；仅把 external resources 设为 Disabled 时，外部 `<image>` 会静默得到空画面而不是 fail-closed。`<text>` 与 Gaussian blur 也会实际渲染，所以“renderer 支持”绝不等于 B0 子集准入。

B0-02 的 tracked qualification 随后以精确 SDK 10.0.300 完成 locked restore、0 warning/0 error build 和 **10/10** 行为测试：真实 XFL 锚定 HP `#FF0000→#330000`、MP `#66FFFF→#0033CC` 的 reflect radial feature，16 项负例覆盖 DTD/entity、外链/data、未知 grammar、超深/超尺寸与 path complexity；空 picture、BGRA/Premul/stride、8-way 独立 parse+raster、8-way shared-readonly draw 和 1000 次 dispose 均通过。结构化报告同时冻结 11 个新增包的 license/nupkg hash、0 vulnerable/deprecated 和 producer-shaped 9 文件/5,289,528 B；状态精确为 `isolated_qualification_passed`、`rendererQualified=false`。B0-03b 仍须把同一合同复用到生产代码、真实 canonical asset 和 policy gate 后，才能转正 HUD-SVG-005。

### 5.3 B0-02 strict facade 硬合同

B0-02 的生产资格必须用同一份 immutable bytes 完成两段式处理：

1. **先独立验证**：校验 embedded SHA-256 与 byte 上限；XML 固定 `DtdProcessing.Prohibit`、`XmlResolver=null`；对元素、属性和值做精确 allowlist；href 只准同文档 `#id`；固定 byte/node/depth/dimension/path-complexity 上限；拒绝 text/image/style/import/script/event/animation/foreignObject、file/http/data/cross-file href 和任何未知项。
2. **再显式渲染**：全进程设置 DTD 禁止；使用 `SecureStatic`、`ExternalResources.Disabled`、`PreserveUnknownElements=false`；JavaScript 总开关和 external 子开关双禁，broken-image placeholder、SVG fonts、text references 显式关闭；输出固定 `Bgra8888/Premul`；synthetic base URI 不指向文件系统；空 picture 或 bounds/stride/byte-count 不符立即失败。
3. **收束所有权**：每次 bake 只有一个 mutable owner；`SKSvg`/picture/canvas/bitmap 在 raster 完成前保持有效，成功、取消、异常路径均有确定 dispose。共享只读 draw 可以有证据地复用，parse/load 不共享可变对象。

任一核心 HP/MP 特性渲染错误、存在不可接受的 native 冲突/闭包膨胀、上述 facade 无法真正 fail-closed，状态改为 `rejected` 并修订 ADR；不得退回逐帧 PNG。

### 5.4 B0-03a：独立 SDK 精确命中微切片

这是现役环境一致性缺陷，不依赖 `Svg.Skia` 是否通过，B0-00 后即可独立施工：

1. `launcher/resolve-dotnet.ps1` 对当前 `global.json` 的 `rollForward: disable` 只接受精确 `10.0.300`；缺失/未知策略 fail-closed；
2. 返回 host 前在 repo root 实跑 `dotnet --version` 并要求精确命中；
3. `launcher/setup-check.ps1` 复用同一 resolver，删除其重复的 latest-patch/same-band 判断和误导话术；
4. 增加纯 selector 回归：only-10.0.301、only-10.0.400、missing/unsupported policy 必须拒绝，10.0.300+10.0.301 必须选 exact；再跑本机 exact-positive 集成检查；
5. 两类正式 builder 最终仍各自记录实际 `dotnet --version=10.0.300`；这一步是 builder 资格证据，不因本机测试通过而省略。

本片不改 `PackageReference`、lockfile、SVG 或 manifest。正式 runtime 的 `tools/check-runtime-build-env.ps1` 已有独立精确门，本修复不得弱化它。

### 5.5 B0-03b：通过后的生产锁定动作

B0-02 通过、B0-04 已产生真实 canonical HP/MP asset、B0-03a 通过后，本片单独完成：

1. 在 `launcher/Directory.Packages.props` 加精确 `PackageVersion`；
2. 在 `launcher/CRAZYFLASHER7MercenaryEmpire.csproj` 加无版本 `PackageReference`；
3. 用精确 SDK 先 `restore --force-evaluate -r win-x64` 更新 lock，再以 `--locked-mode -r win-x64` 复核；提交 `launcher/packages.lock.json`；
4. 把真实 `Assets/**/*.svg` 与 runtime manifest JSON 纳入显式 `EmbeddedResource`，repo-only provenance/oracle evidence 不嵌入 Core；
5. 更新依赖审计记录、third-party notice、`launcher/README.md`、本文决策状态；
6. 新鲜 restore/test/build，记录实际依赖闭包，不手写推断值。

不再为尚不存在的 production asset 设计 `notRuntimeSelectable` 占位标志。B0-02 的 qualification fixture 留在隔离 corpus；B0-03b 直接针对 B0-04 的真实 canonical asset 验证资源、identity 和 payload closure。

### 5.6 Runtime build identity 与 payload closure

`config/build/runtime-inputs.v2.json` 已把 csproj、中央包版本和 lockfile 列为 fixed artifact source；包引用变更会进入身份。当前 `launcher/src` tree 只纳入 `.cs`，所以 B0-03b 必须：

- 优先增加只覆盖 `launcher/src/Guardian/Hud/PlayerInfo/Assets` 的窄范围 artifact-source tree，纳入 `.svg/.json`，不把整个 `launcher/src` 的任意 JSON 顺带扩入；
- 加回归证明改任一 SVG byte 会改变 artifact source / build identity；
- 证明 embedded resource 改变 Core，从而改变 payload closure；
- 核对 `.github/workflows/runtime-bundle-integrity.yml` 的 native path gate 确实会被资产与包文件触发；若修改 gate，同片更新其测试；
- 禁止仅依赖 Core 输出“碰巧变化”掩盖 artifact source 漏收源资产。

正式发布仍遵守 [runtime build reproducibility](runtime-build-reproducibility.md) v2；B0 日常开发停在 isolated candidate 即可，不要求每片 promotion。

### 5.7 一次性准入证据与长期生产门

当前 production policy 不会因为存在新的 launcher xUnit 就自动执行它。B0 必须同时建立：

- **一次性准入证据**：完整 renderer corpus、依赖/许可/native/payload、两类 builder 的 locked restore 与一致 identity/closure；
- **长期回流保护**：快速、确定性的 SVG grammar/hash/closure contract auditor，接入 `Get-Cf7ProductionChecks`，或有同等级 production policy 检查。

若新增 production check，它属于 policy/构建门槛变化，必须同步 runtime/testing canonical docs 和 policy 自测。只补 xUnit 不得写成“正式 promotion 已受保护”。

---

## 6. Flash → SVG 转换策略

### 6.1 输入闭包

从主舞台的玩家 HUD placed instance 出发，递归记录：

- instance path、symbol/linkage、layer/depth、frame/span；
- local matrix、color transform、alpha、blend；
- shape geometry、fill/stroke、gradient matrix；
- mask/clip 关系、registration point、bounds；
- 被脚本按帧/标签访问的状态。
- 首帧未自动播放但被现役 AS2 `play/nextFrame/goto*` 或显示列表引擎显式推进的 descendant；静态 B0 可以 defer 行为，不能从 source closure 删除。

库中未被 active placement、attachMovie linkage 或已核实运行路径触达的 symbol 默认排除。`<elements/>` 空层、历史帧脚本和“看起来像第五槽”的素材都不能仅凭存在进入闭包。

### 6.2 转换产物分三类

1. **静态 canonical SVG**：壳、边框、底纹、填充纹理、独立高光。
2. **manifest 行为参数**：bounds、pivot、clip direction、虚拟帧范围、关键状态。
3. **测试 oracle**：从 Flash 独立捕获的少量透明 crop，只用于测试/人工审阅，不进 runtime。

### 6.3 确定性与 fail-closed

- 相同 closure、显式语义映射、converter 与规范化规则版本必须生成 byte-identical canonical SVG + runtime manifest；provenance/oracle evidence 独立 canonicalize，重新捕获 oracle 时显式递增 evidence revision，不得带动无功能变化的 Core payload。
- converter 输出 unsupported-feature report；报告非空时该 symbol 不得标为完成。
- 转换器只实现 B0 命中的 feature，不因单个边缘素材扩张成通用 XFL 引擎。
- 自动转换成本高于手工重建且 closure 很小时，可以依据 oracle 手工建立 canonical SVG；但必须补 provenance、语义 ID 和视觉 Gate，不能省略审计。
- FFDec/SWF 导出可作交叉检查，不作为唯一真源；XFL 矩阵/实例语义优先。
- converter 是离线作者工具；提交确定化 SVG 后，runtime producer 不运行转换器。若未来改为构建时生成，必须另行把工具及版本纳入 producer recipe 并证明双 builder 字节确定性。
- XFL、发布 SWF 与运行截图的新鲜性无法相互证明时，oracle 只能标 candidate；需要时按 AGENTS 规则对 `玩家信息界面.xfl` 做精确 CS6 target publish/verify，不能用旧 SWF 反证新 XFL。

### 6.4 独立 Flash oracle 的可复核来源

每张 accepted oracle 必须由 `oracle-manifest.json` 绑定以下证据，缺一项只能标 `candidate`：

- XFL 根目录的 closure SHA-256、每个 active XML 的 SHA-256、Git blob/tree OID；
- 实际取图所用玩家信息 UI SWF 的路径/SHA-256，以及本场景**实际**加载它的 loader SWF 路径/SHA-256（可能是 main、asLoader、TestLoader 或其他 loader，只记录真实链）；若由本轮 CS6 publish 生成，记录精确 `-Target <玩家信息界面.xfl> -PublishOnly -VerifySwf <对应.swf>`、CS6 版本/publish profile 和新鲜 Output/IDE 复核，不把 marker 或 exit 0 单独当成功；
- 播放器/宿主名称、文件版本与可执行文件 SHA-256，Windows 版本、viewport、Windows scale/DPI、Flash stage scale/alignment；
- 可重复的进入场景与状态设置方式、HP/MP 原值与 max、ratio、目标/当前虚拟帧、采集时播放头是否冻结；
- 截图方式、源画布尺寸、精确 crop rectangle、透明/底色处理、composite 背景 ID，以及原图与 crop 各自 SHA-256；
- 人工复核者对“状态正确、未混入别的 HUD 层、裁切未吃边”的确认；人工审美验收仍独立于自动 hash/像素指标。

当前 B0-01A r3 已持久化并由独立 verifier 复核：HP/MP active closure 共 16 个 XML/文档文件，HP 10 个 symbol、MP 5 个 symbol，其中两个共享；17 个 authored definition edge 沿 HP/MP 路径展开为 18 个 runtime edge，closure 内同时为 0 `BitmapFill` / 0 `DOMBitmapInstance`。Git-canonical closure digest 为 `6f4bf9f36563c1bd16993c7472c4ebf49321852ab19eebb0bdf6b58df9264368`。现有 child SWF SHA-256 为 `450B1F9A8B445EE3E28C63682EA00124A191F56D05D759B8590210FC0066A615`，其生成提交 `9845dd9084f7b285dbbf1ed603dad7b201a6a324` 中的 16 个 Git blob 与当前 HEAD 逐项相同。这是可审计的 **repository ancestry**，不是可复现构建 receipt；只有实际 capture manifest 还能证明进程加载了该 child，并绑定实际 loader（本方案为 TestLoader）、player/crop 与人工确认时，才足以免于为“冻结旧 oracle”重新 publish。main/asLoader 仅在真实参与加载的场景中记录，不能强填。

同一转换器产物不得反向生成这套 oracle。B0-01A 只冻结 closure/ancestry；B0-01B 使用 TestLoader 的受控 scratch transaction 驱动现有 child SWF，不修改旧 XFL，也不接生产 Host/真实存档。fixture 只接受固定 case ID，直接固定 HP/MP 显示帧、文字与 `grid/inner/light` 相位，回传/trace 精确状态后再捕获；`/console`、任意数值注入和 live slot 都禁止作为 oracle。若 test-only host 无法给出与实际 Flash 足够一致的来源，或现有 SWF 与当前 XFL 之间失去可证明绑定，只能保存 `candidate`，直至补齐精确 UI XFL publish/verify 与 runtime-load 绑定。人工确认是 accepted oracle 的附加必需条件，不能替代任何 provenance 缺口。

### 6.5 B0-01B 最小捕获实现

固定采用“TestLoader 测试壳 + 独立 UI SWF + AVM1 `BitmapData.draw`”，不扩生产控制面：

- 工具代码上限为三个窄文件：tracked `TestLoader.as.template`、一个 PowerShell capture runner，以及确有需要时的 decoder/self-test；优先把 self-test 留在 runner，超过上限先停片复审。
- Manifest 保存 repo-relative `flashswf/UI/玩家信息界面.swf`；从 `scripts/TestLoader.swf` 加载的 AS2 runtime URL 固定为 `../flashswf/UI/玩家信息界面.swf`。只在 `MovieClipLoader.onLoadInit` 后继续，并回报/校验 child `_url`。模板 include 现役玩家信息显示公式，把 `_root.控制目标` 指向 `_root.gameworld.oracleHero` 内存 fixture；不 monkey-patch `TargetCacheManager`/`StringUtils`，不得调用 SharedObject/SaveManager/ServerManager、网络或 console。
- TestLoader 在 draw 前显式固定 `_root._quality="MEDIUM"`，与现役 `引擎_lsy_常数.as` 一致；manifest 和每个 case 的 trace 都记录实际 `_quality`，不靠播放器默认值决定抗锯齿、渐变或 filter 基线。
- case 只允许 `empty/min_step/p25/p50/p75/p99/full`。HP 使用 `max=12800`、MP 使用 `max=10000`，让最小格与 99% 都能由整数精确表达；模板不接受任意 CLI 数值。
- 调用现役 `.刷新显示()` 后把 target/current frame 对齐；固定 `网格动画/血槽内动画/血槽光效` 三个相位，静态 corpus 再隐藏 deferred `血槽光效` 并回报 hidden，同时在 closure 中保留其脚本可达边；隐藏韧性/经验/技能/药剂等非本纵切层。
- 在 Flash 内用透明 `BitmapData(1024,64,true,0x00000000)` identity draw child；manifest 写 `background=transparent_argb_0`、`compositeBackgroundId=null`。每个 case trace 精确 raw/max/ratio、target/current frame、三个相位、visibility，以及刷新后的 HP 当前/最大/百分比、MP 当前/最大/百分比和实际存在的合并显示文本；runner 独立计算期望帧/文本并拒绝偏差。
- ARGB 物理记录携带 `runId/caseId/row/part/partCount/b64`。runner 先记录 flashlog watermark，只接受精确一个同 runId 的 start→complete 闭合块、每个 case 恰好一组 state 与 64×8 条连续 PART、无重复/越序/未知字段/未知类型且无 failure sentinel；每行 Base64 解码后必须精确重编码为同一 canonical 字节串，旧播放器迟到输出不得进入本轮块。
- scratch transaction 必须复用现役 mutex、BOM、source backup/restore sidecar 与 installed/original SHA 校验；在 source marker 建立后、编译前还必须为既有 `scripts/TestLoader.swf` 建立持久 sidecar/byte backup。只有 compile 子进程返回、全局 uncertain marker 不存在且 compiled identity 已冻结时才允许自动恢复；恢复顺序固定为 SWF → AS → sidecar/backup cleanup → mutex release，任一 late-write/identity drift 保留材料并写 uncertain marker。固定用 `compile_test.ps1 -Target test -PublishOnly -VerifySwf scripts/TestLoader.swf`，再由 runner 启动精确播放器；runner 只管理自己 `Start-Process -PassThru` 得到的 PID。先写 ignored `tmp/`，人工确认状态/隔离层/crop 后才把 accepted PNG/manifest 晋升到 repo evidence。

r4 静态工具已用 3,584 条 PART、最大物理行 829 字符、10 条 canonical summary、2 轮逐像素 PNG/crop round-trip、3 类 SWF 恢复事务和 2 类恢复负例完成独立审计；ValidateOnly 明确未启动 Flash，原 `TestLoader.as`/`TestLoader.swf` 字节与 mtime 未变。它仍缺实际 `capture-flash-oracle.ps1` 与 `flash-oracle-protocol.ps1` 的 frozen/Git-canonical 自身份记录；补齐前不得运行可晋升为 accepted 的 capture。

该路径不经过桌面合成，原始透明像素不受窗口遮挡、DWM 或 Windows scale 改写；manifest 仍须记录播放器/Windows 身份，并明确 `captureMethod=AVM1 BitmapData.draw`、逻辑画布与矩阵。窗口截图只作 fallback；FFDec sprite 导出只作交叉检查，二者都不能自行补齐 accepted provenance。

---

## 7. 程序化显示与动效

### 7.1 B0 首纵切：HP / MP

静态缓存只含 backplate/fill texture/rim/highlight。每帧变化只更新：

- normalized ratio 与异常值钳制；
- 虚拟 frame target；
- 当前虚拟 frame 的平滑状态；
- clip geometry / transform；
- 数字文本。

首版行为分成“既有 AS2 parity”与“B0 新增的防御性输入合同”；两者均已回写总体迁移 ADR §2.1，不能把新增收紧伪装成旧行为：

- HP：128 格逆向，空/满边界与无 `%` 文本保持；
- MP：100 格逆向、五位补零和有 `%` 文本保持；
- HP/MP 平滑严格复刻现有式：`step=max(1,min(ceil(distance*0.2),ceil(distance/30*2),distance))`。变量名中的“30”是调参量，不是“最多 30 tick”的保证；从 128 格突变按当前式需要 41 tick，测试必须固定完整序列；
- **B0 新增收紧**：`max<=0` 或任一输入为 NaN/Infinity 时，保留 last-known-good、停止推进该 gauge 并暴露结构化 `invalid_input` 诊断，不能渲成 0；只有有限且 `max>0` 的合法输入才计算 ratio 并 clamp 到 `[0,1]`。这不声称 AS2 已有同样防御。B0 尚无 epoch/sequence 合同，不把数值非法混称 `stale`；旧 snapshot 的判定留到 B1 生命周期合同。

MP 的 shape tween 不保存 101 份路径。B0-01A/B0-04 应提取最少关键 path/guide，以 normalized parameter 插值或 clip；若无法稳定插值，先用经验证的单 mask 几何达到 oracle parity，再决定是否需要第二关键形。

### 7.2 后续程序化优先级

1. HP/MP/经验等比例裁切；
2. HP/MP/韧性平滑与破韧状态；
3. 受伤/低血提示等有限状态；经验条“升级闪满”仅在 B2 真机证明旧效果实际可见后才立项，当前 `.frame=100` 影子写入不作为迁移合同；
4. `血槽光效` 这类循环相位；
5. skill/drug cooldown、buff 倒计时等独立子系统。

先冻结视觉 parity，再优化“明显值得”的动画；每次优化只替代一个旧时间轴职责，并保留 before/after oracle。程序化不等于同时改行为。

### 7.3 Runtime 约束

- 静态层稳态零 SVG parse/raster；只 draw 已缓存 PArgb bitmap。
- `PlayerInfoWidget.WantsAnimationTick` 仅在 ratio 过渡、有限动效或确有启用的环境光效时为真。
- `PlayerInfoWidget.TryHitTest` 必须恒返回 false；B0 是只读镜像，不能因 NativeHud overlay 自身可命中而吞掉游戏区点击。
- decorative loop 不得无条件把整层永久拉进高频 repaint；B0 默认静态首帧，B3 再用测量决定 tick rate。
- 当前 overlay 最短重绘约 33 ms，单个 widget 请求动画仍会重画全部可见 widget 并提交 union；B3 永久环境动画必须先通过全 union 成本门，必要时另做局部子合成。
- 玩家 HUD 位于左下，而现有 NativeHud 还分布在顶部/侧边；单一 `Rectangle.Union` 很可能把 composed bitmap 膨胀到近全屏。B0-05 必须用 test-only inline `INativeHudWidget` no-op/fixed-bounds probe（不新增生产 widget）记录 hidden/enabled 的 union 像素面积、viewport 占比与 commit 基线，并在“接受实测预算、分岛 surface/局部子合成、保持 Flash/停止”之间作显式裁决；B0-06 再以真实 `PlayerInfoWidget` 重跑完整 A/B，不能等实现后失败再删门。
- bake 在后台线程完成，UI 线程只做短事务换入；所有 `SK*`/Bitmap 所有权和 dispose 路径必须单测。
- 输出统一为 `Format32bppPArgb`，覆盖透明边、半透明渐变和 premultiplied BGRA 对照。
- 复用/扩展现有 byte-budget `BitmapLruCache` 与 `NativeHudPrewarm`，不另建无预算全局字典。

---

## 8. Fixture harness 与验收矩阵

### 8.1 Fixture 场景

- SVG conformance：奇偶/非零填充、自交/孔洞、local `use`、负 scale/旋转/斜切/nested matrix；
- paint：solid、linear/radial、`spreadMethod=reflect`、多 stop alpha、layer opacity、clipPath 边缘；
- HP/MP：0、1 个最小格、25%、50%、75%、99%、100%；
- 突降、突升、连续抖动、中途反向、相同值重复包；
- `max=0`、负数、超上限、NaN/Infinity/缺字段、重复 invalid 与 last-known-good；旧 snapshot/epoch 场景留到 B1；
- 进入战斗、切场景、overlay suspend/resume；
- viewport/DPI 变更、反复 resize、缓存淘汰后重建；
- 透明渐变、负 scale/nested matrix、clip 边界和 1px fringe；
- renderer load 失败、manifest/hash 不匹配、后台 bake 取消与 dispose 竞态。

### 8.2 视觉矩阵

至少覆盖：

- viewport：`1024×576`、`1600×900`、`1920×1080`、一个 4:3；
- Windows scale：`100% / 125% / 150% / 175%`；
- HP/MP 关键状态与一次完整平滑序列；
- 透明背景 crop 和实际游戏画面 composite 各一套。

不以全屏逐像素相等作唯一门。结构断言固定 bounds/pivot/layer order/ratio；视觉门结合 alpha coverage、边缘/渐变差异、感知差异和人工 overlay review。抗锯齿容差必须由 oracle corpus 标定，不能为过测试临时放宽。

### 8.3 B0 暂定性能门

在登记的 Windows x64 基线机上：

- 触发 bake 的 UI 线程同步工作目标 `≤ 4 ms`；
- HP/MP 全静态层 cold bake p95 目标 `≤ 100 ms`，在后台完成；
- warm cache lookup/换入目标 `≤ 1 ms`；
- HP/MP cache byte budget 暂定 `≤ 16 MiB`；
- 100 次 viewport/DPI churn 后 GDI/Skia handle 无净增长，native/managed 内存回到有界平台；
- 稳态 3000 tick 无 SVG parse/raster，静止时 widget 不请求动画 tick；
- B0-05 先用 test-only no-op/fixed-bounds probe 跑 geometry/commit 预检，probe bounds 必须来自 B0-01A placement contract；它只为提前裁决合成拓扑，不得冒充真实 widget 性能；
- 在“全部现役 NativeHud widget 可见 + 视觉矩阵最大 viewport/DPI”下，分别跑 fixture hidden/enabled 的 3000 tick A/B：同一 overlay tick 内 HP/MP 更新至多合并成 1 次 repaint request、1 次全 union repaint 和 1 次 `UpdateLayeredWindow` commit，不得形成自激式额外提交；
- 结构化记录 `nativeHud.repaintSource.PlayerInfoWidget`、每类 `nativeHud.paintSource.*`、`nativeHud.animTick`、`nativeHud.commit`，以及 `PlayerInfoWidget.Paint`、全 union paint、`CommitBitmap/UpdateLayeredWindow` 的 count/p50/p95/p99/max、union 像素面积/viewport 占比；同时记录进程 CPU、managed allocation/GC 和 working-set/native-handle delta。CPU/alloc/GC/working-set 在 B0 只作诊断记录，不设脆弱硬阈值；handle 无净增长和长循环无单向线性增长仍是 Gate。现有 telemetry 若没有整段时长，B0-06 增加 `renderCommitMs` 而不是只数事件；
- B0-05 先冻结 feature-off 基线与噪声带，B0-06 开测前由该切片评审锁定报告阈值；相对门和绝对门是两个独立拒绝条件：enabled 相对 hidden 的 union+commit p95 回退不超过 10%，且 enabled p95 低于约 33 ms 重绘间隔，任一失败都不能自动判通过。若几何决定的 union 膨胀使初始门不可达，B0-05 必须在实现前记录样本并由维护者裁决分岛/局部合成、经证据修订阈值或停止；若只是基线抖动，先扩大样本/固定后台负载，不得事后删除 Gate 或沉默放宽；
- idle A/B 额外跑 3000 tick，PlayerInfo 归因的 repaint/commit 必须为 0；永久装饰 tick 不属于 B0。

这些是 B0 的可审阅初值。修改阈值必须在台账记录测量机器、样本和原因，不能沉默放宽。

### 8.4 结构化结果

harness 输出 JSON + 人读摘要，至少含：

```text
assetSetDigest / rendererVersion / viewport / physicalScale
scenario / semanticAssertions / visualMetrics
coldBakeMs / cacheBytes / handleDelta / result
widgetPaintCount+Ms / unionRepaintCount+Ms / layeredCommitCount+Ms
processCpuMs / allocatedBytes / gcCounts / workingSetDelta
```

截图只能作为报告附件；没有结构化结果不能声称 Gate 通过。

---

## 9. 分片施工计划

### 9.1 B0 分片

| Slice | 范围与产物 | Gate | 明确不做 |
|---|---|---|---|
| B0-00 | 本 ADR + 原迁移文档入口同步 | doc governance、链接、diff check | 不写代码/依赖 |
| B0-01A | HP/MP active placement closure、矩阵/注册点、脚本可达边、source hashes、source-binary ancestry | exact 16-file 清单人工复核；unused library/BitmapFill 未混入；`placement_closure_frozen` | 不采截图、不改 XFL/AS2/Launcher |
| B0-01B | TestLoader scratch fixture + `BitmapData.draw` 独立 Flash oracle manifest/crops | 固定 case 可重采；child/实际 TestLoader/player/crop 身份齐；人工确认；`oracle_frozen` | 不用 `/console`、真实存档或生产 AgentControl；不导出发布帧序列 |
| B0-02 | 隔离 renderer conformance + HP/MP feature qualification corpus、strict facade、完整 NuGet/native/license/security/size 审计 | core subset（含 reflect gradient）全绿；malformed/external resource fail-closed；危险默认值显式封死；dispose/alpha 通过 | 不写生产 PackageReference，不生成 runtime-selectable asset |
| B0-03a | exact SDK resolver/setup-check 合同与回归 | only-10.0.301 等负例拒绝；repo-root `dotnet --version=10.0.300` | 不改包/lockfile/资产 |
| B0-04 | 窄范围 XFL→SVG converter/validator + HP/MP canonical SVG/manifest | byte-stable；unsupported=0；oracle 视觉评审通过 | 不做通用转换器 |
| B0-03b | 生产依赖锁定、真实 asset embedded resource、runtime inputs、identity 回归、production contract gate、README/测试文档同步 | locked restore；改 SVG 必改 identity/Core closure；native/policy gate 触发 | 不做 widget/业务协议，不放 qualification 占位资产 |
| B0-05 | `PlayerInfoSvgRasterizer` + PArgb bridge + byte-budget cache/prewarm + test-only fixed-bounds union probe | DPI/alpha/perf/handle/dispose 门通过；合成拓扑先裁决 | 不接真实 UiData，不新增生产 PlayerInfo widget |
| B0-06 | fixture-only `PlayerInfoWidget`、HP/MP clip/虚拟帧缓动、layout harness | 全视觉矩阵 + 3000 tick；旧 HUD 未隐藏 | 不新增真实 `pi_*` |
| B0-07 | Kimi k3 异构对抗、问题处置、决策转正、B0 验收记录、B1 接口冻结、人工视觉/UI验收 | §9.4 + §11 exit checklist 全满足 | 不顺手扩韧性/经验，不由自动指标代签审美 |

依赖关系：B0-01A、B0-02、B0-03a 在 B0-00 后可并行；B0-01B 等 B0-01A，但可与 B0-02 并行。B0-04 明确依赖 B0-01A + B0-02 后方可开始，并须等 B0-01B 的 accepted oracle 才能通过视觉 Gate。B0-03b 等 B0-02 + B0-03a + B0-04；B0-05 等 B0-03b + B0-04；B0-06 等 B0-04/05。

### 9.2 B0 后续

| Phase | 目标 | 进入条件 | 退出条件 |
|---|---|---|---|
| B1 | 建立/接通 HP/MP `PlayerInfoState(cur/target)` 与 frameEnd UiData，双轨可见对照 | B0 accepted；协议字段审阅 | 实机 HP/MP parity，断线/重连/场景切换无旧 snapshot 污染 |
| B2 | 韧性、经验、等级、姓名、SP、弹药、攻击模式、buff 与技能/药剂只读显示 | B1 稳定；各子系统权威/图标边界确认 | 总体 ADR §2.4 验收表闭合 |
| B3 | 逐个把破韧/血槽光效/cooldown 等已证明存在的明显动效程序化；升级闪满须先由 B2 真机证明 | 对应静态 parity 已冻结 | 每项独立 before/after 证据、性能不回退 |
| B4 | 隐藏旧可见 HUD、观察、最终退役旧显示壳 | 药剂/装备主线解除剩余命中耦合；观察门通过 | 旧 placement/facade 按总体 ADR 安全收敛 |

### 9.3 与另一台机器的施工边界

- 装备栏/双栏工作台机器：拥有物品投影、装备/药剂交互、管理面板及相关协议。
- 本 B0：只读旧玩家 HUD，拥有新 `PlayerInfo` C# 目录、HUD SVG/manifest、专用 converter/harness。
- 共享高冲突文件：csproj、`Directory.Packages.props`、`packages.lock.json`、`runtime-inputs.v2.json`、workflow、`launcher/README.md`。只在 B0-03b 集中修改，开片前先确认另一机器没有同文件未落变更；B0-03a 只碰 resolver/setup-check 及其 focused test/docs，不夹带包图。
- B0/B1 可并行于装备栏迁移；只有 B4 的药剂命中壳退场受物品/药剂主线阻塞。
- 任何“顺手改旧药剂槽/装备槽”的需求移交对应主线，不扩 B0。

每片控制在约 6–8 个文件、单片可独立验证；中央依赖片与业务实现片不得合并成一个大提交。

### 9.4 B0-07 强制异构对抗与人工终审

B0 完成前必须使用本机 Kimi Code 的 `kimi-code/k3`，以其配置支持的最高思考强度 `max` 做至少一轮**完整、只读**异构对抗；不得因运行慢而终止思考、降 effort、换模型或把局部 smoke 冒充完整审计。审计 prompt 必须同时提供本 ADR、总体迁移 ADR、代码/资产 diff、结构化测试与视觉报告，并逐项挑战：

- 是否为一个 HP/MP 纵切引入了过度抽象、重复 cache/状态权威或通用转换器；
- 依赖、manifest、validator、所有权/dispose、production gate 是否形成不必要的长期维护负担；
- fixture 与未来真实 UiData 的交互、异常值、resize/DPI、加载/失败 fallback 是否违背用户直觉；
- HP/MP 层级、比例、裁切、透明边、渐变、数字排版、HUD 密度和游戏内 composite 是否视觉不协调；
- 性能门是否漏掉 NativeHud 的全 union repaint/commit，而非只测局部 rasterizer。

证据至少记录：CLI 版本、model、effort、session ID、prompt SHA-256、输入 commit/worktree digest、开始/结束时间、原始输出 SHA-256、逐条 `accept/reject/defer` 处置与复核测试。Kimi 配额不足、服务不可用或无法配置 `k3 + max` 是明确 `blocked`，不能用同构 subagent 替代。

Kimi 通过也不代替人类。B0 最终视觉/UI包必须交由人类查看透明 crop、游戏 composite、关键比例和平滑录制，并取得明确接受；在此之前台账最多为 `awaiting_human_acceptance`，§11.3 不得全勾、目标不得报完成。人类提出的审美/交互修改须回到对应 B0 切片复测，再重新出终审包。

### 9.5 B0-00 文档建设异构审计记录

首轮完整审计已于 2026-07-28 完成，满足“文档建设完成前至少一轮”的独立门；它不包含尚不存在的实现 diff/视觉报告，**不替代** B0-07 对最终实现包的再次完整审计。

| 字段 | 证据 |
|---|---|
| CLI / session | Kimi Code CLI `0.29.1`；`session_aa721404-6bc0-4f6b-8ce8-4d638777bd01` |
| 模型 / thinking | `kimi-code/k3`；session wire 的 `config.update` 与每次 `llm.request` 均记录 `thinkingEffort=max`、`thinkingKeep=all`，不依赖模型自述；结束后用户配置恢复原值 |
| 只读与时间 | `READ_ONLY=true`；2026-07-28 12:39:27.818 +08 至 12:58:34.532 +08，exit 0；未降 effort、换模型或提前终止 |
| 输入身份 | HEAD `ea1af623eb297c6bc875d731a3bc85d459ba598a`；审计前工作树只有本两份文档；当时本文 SHA-256 `FE587E4EE18B45F76221FC4CB7E87D6FDDB0F8928F8DB9ABAE9AAB3912BC5FF8`、总体 ADR `BEC3EBA1FA862CC2A9F0C17A7CED339D255639C0266FDD8F0D8749DC93B458FD` |
| Prompt / output | prompt `4B2D2766F6647CF75D7167F6E948BCC9A7DFCCBA4C8AD8179D00EB6AF9E53E98`；stdout `8997996261CB6AF68B1C9F03D22F1874A0005255889DBC6300FA5AF8E68C6361`；stderr `237B80C51CA5EBFA9BF08ED1671A1B7964AD62FEBDBEAEE9181D81C1D131454B` |
| 原始 session archive | 本机 ignored `tmp/kimi-b0-doc-audit-019fa6d6/session.zip`，318,424 B，SHA-256 `72528A40332A452C3C88E0664E4BA44E4C290216177986D337DE902873E1B4C5`；仓库只保留核实后的裁决，不提交冗长思考流 |
| 总体结论 | `修订后可施工`；P0=0，B0-00=Yes |

逐条处置：

| 发现 | 裁决 | 落点 |
|---|---|---|
| 经验条 `.frame=100` 疑似死写，不应预造“升级闪满” | accept | 总体 ADR §2.1/§2.4/C1 与本文 §7/§9 已降级为 B2 真机待证 |
| exact SDK 缺陷与 renderer 无关 | accept，并补充复核到 `setup-check.ps1` 的重复算法 | §5.4/B0-03a 独立微切片 |
| 左下 HUD 会令单一 union 近全屏 | accept | §7.3、§8.3、§11.1 在 B0-05 前置面积测量与 stop-loss |
| 错误交叉引用、经验 clamp、依赖/并行措辞、点击透传、双性能门裁决不清 | accept | §0.5、总体 ADR §2.1、§7.3、§8.3、§9.1/§12 |
| cache key 的 alpha/color 恒定字段、独立 schema 目录过度 | accept | §2.1/§4.1 删除；真实第二模式/消费者出现后再扩 |
| qualification fixture 不应发明运行时标志 | accept 目标、调整手段 | 不把 test fixture 冒充 production identity；改为 B0-04 先产真实 asset，B0-03b 再直接接线 |
| CPU/GC/working-set 不宜设脆弱硬阈值 | partial accept | 保留诊断记录；handle 无净增长与长循环无单向增长仍是 Gate |
| 自动化/Kimi 不能代签审美、裁切、平滑与鼠标透传 | accept | §9.4/§11.3 继续保留最终人工阻断门 |

---

## 10. 验证与结论词典

### 10.1 每片最低验证

| 改动面 | 最低门 |
|---|---|
| 仅文档 | `node tools/validate-doc-governance.js` + `git diff --check` |
| converter / validator | deterministic fixture、unsupported fail-closed、contract/hash tests |
| NuGet / csproj / runtime inputs | locked restore、依赖审计、`launcher/tests/run_tests.ps1`、runtime identity/path gate 回归 |
| raster/cache/widget | focused unit + 全 launcher tests + fixture visual/perf/handle matrix |
| AS2 UiData（B1 起） | AS2 focused tests、新鲜 Flash 证据、C# snapshot tests、真实 candidate E2E |
| 正式发布 | runtime v2 immutable request → 双 signer/双 faultDomain → promotion → 标准入口同身份复核 |

实际新增命令和测试入口必须在对应代码片同步 [testing-guide](../agentsDoc/testing-guide.md) 与 `launcher/README.md`；本文不提前虚构尚不存在的命令。

### 10.2 视觉结论

- `planned`：只有 ADR/计划。
- `placement_closure_frozen`：active placement、脚本可达边、source hashes 与 repository ancestry 已冻结；尚无 accepted 截图。
- `oracle_frozen`：独立 Flash 参考截图、状态、运行时/SWF/crop 身份与人工来源复核均冻结。
- `renderer_preflight_passed`：隔离 restore/ABI/payload/synthetic corpus 已过，只证明继续投入合理。
- `renderer_qualified`：候选连同生产 strict facade、从 HP/MP closure 提取的真实 feature qualification corpus 与依赖 Gate 均通过，但尚无 canonical asset/生产接线；B0-04/03b 仍须对最终 SVG 重跑。
- `fixture_static_parity`：模拟信号下静态美术、HP/MP 变化、缓存和性能门通过；显式 deferred overlay/环境动效尚未闭合。
- `fixture_full_parity`：纳入已承诺动效后的 fixture 全视觉门通过。
- `runtime_integrated`：真实 `PlayerInfoState/UiData` 接通且双轨通过。
- `awaiting_human_acceptance`：自动 Gate 与最终异构审计已完成，但视觉/UI 人工签收尚未取得；不得报 B0 完成。
- `b0_accepted`：§11.3 全部闭合且人类已明确接受最终视觉/UI包；仍不蕴含任何 Launcher 发布状态。

这些词不替代 Launcher 发布状态。

### 10.3 Launcher 结论

统一使用：

```text
compiled → candidate_built → candidate_executed
→ e2e_verified → promoted → standard_entry_verified
```

`launcher/build.ps1` 最多证明 `candidate_built`。未到 `standard_entry_verified` 不称“已部署 / 正式验收”；任一 fixture parity 不代表任何一档正式 runtime 状态。

### 10.4 Flash 结论

B0 默认只读旧玩家 HUD XFL。B0-01B 可在受控 scratch transaction 中精确编译 TestLoader 测试目标；只有仍无法证明 XFL/SWF/oracle 新鲜性时，才追加独立的精确 UI XFL publish 取证。任一 TestLoader/UI publish 都必须按实际目标单独表述，不得外推为 main/asLoader 已编译。B1 以后若改 `.as`/XFL：

- `.as` 保持 UTF-8 BOM；
- `compile_test.ps1` 退出 0 或 marker 不等于编译成功；
- 按实际目标选择 asLoader/TestLoader/独立 UI XFL/main，并取得新鲜 trace/Output/IDE 证据；
- 不手改 SWF。

---

## 11. 风险、退路与 B0 Exit Gate

### 11.1 风险登记

| 风险 | 处置 |
|---|---|
| Svg.Skia 闭包远大于预期或带来多平台 native payload | B0-02 先测 publish diff；不通过则 reject 并修 ADR |
| Svg.Skia 默认允许外部资源/placeholder，DTD、外部 JS 子开关与 alpha 默认值不满足合同 | B0-02 按 §5.3 对同一 immutable bytes 先独立 validator、再显式 secure renderer；任何 silent-empty/unknown fallback 均失败 |
| gradient/mask/transform 与 Flash 不一致 | core corpus + 独立 oracle；复杂 feature 默认不准入 |
| HP 边框 placement 使用 `exportAsBitmap=true` + Bevel，Flash oracle 含派生 raster/filter 语义 | 不把它误判为源 bitmap；B0-01B 单列 oracle 差异，B0-04 将 Bevel 展开为矢量/渐变或失败，透明边按实图标定 |
| PArgb 转换产生黑边/色晕 | 透明边、半透明 gradient、BGRA premultiply 专项测试 |
| converter 变成无底洞 | 只做 HP/MP active subset；允许有 provenance 的手工 canonical SVG |
| DPI/resize 导致缓存抖动或陈旧图 | pixel-size key、取消旧 bake、原子换入、byte-budget LRU |
| Skia/Bitmap 释放竞态或 native leak | 明确所有权；100 次 churn + 3000 tick + handle delta Gate |
| 自生成 golden 自证正确 | Flash 独立捕获 + 人工 overlay review；转换输出不可作唯一 oracle |
| 旧 SWF/截图与当前 XFL 无可证明绑定 | 按 §6.4 标 candidate；必要时精确 publish/verify 独立 UI XFL，再以 SWF/播放器/crop hash 冻结 |
| 现役系统没有安全的精确 HP/MP 只读注入，误用 `/console`/真实槽会污染 oracle 或游戏状态 | B0-01A/01B 拆分；只用 TestLoader scratch 固定 case，禁止生产 AgentControl、任意 console 与 live save；捕获失败不冒称 `oracle_frozen` |
| 整座 HUD 的 `玩家必要信息界面` 含 BitmapFill | HP/MP closure 明确排除且当前为 0 bitmap；B2 扩域时重新审计两个 `bin/*.dat` payload，不用 `<image>` 偷渡 |
| fixture-first 误接成第二状态权威 | adapter 接口隔离；B0 禁止真实 `pi_*` 与 AS2 写路径 |
| asset 未进 build identity | runtime-input regression：改任一 SVG 必改 identity 与 Core closure |
| `resolve-dotnet.ps1`/`setup-check.ps1` 与 `rollForward:disable` 口径不一致 | 独立 B0-03a 统一为精确 SDK 命中并做 only-10.0.301 等负例；两 builder 记录实际 `dotnet --version` |
| 与装备栏机器冲突 | B0-03b 集中共享文件；其余只写新目录；旧 XFL 只读 |
| 程序化动画顺手改变手感 | 先复刻虚拟帧语义；优化一项一 ADR/证据 |
| 左下 PlayerInfo 与顶部/侧边 widget 被单一外接 union 合成，HP/MP 过渡时近全屏提交 | B0-05 先量 hidden/enabled union 面积与 commit；裁决接受实测预算、分岛/局部子合成或停止，不因实现完成后才发现而放宽门 |
| 永久动效使所有 NativeHud widget 常态 union 重绘 | B0 默认静态；B3 先测全 union，超预算则局部子合成或保持静态 |
| 资产损坏导致战斗信息全空 | 双轨期加载失败即隐藏 Native widget、保留 Flash；B4 退壳前补不依赖 SVG 的最小 GDI 数字/条形 fail-safe |

### 11.2 Stop-loss

- renderer 不能稳定覆盖 core subset：停止 B0-03b，不把候选写入生产；修订 HUD-SVG-005。
- 某一视觉必须依赖禁用 SVG 特性：优先拆几何层/代码效果；仍不可行则单项 ADR，不全局放开。
- 自动 converter 成本明显高于资产本身：停止扩张 parser，手工建立少量 canonical SVG 并保留 provenance。
- 性能不达标：先证明是 parse、raster、PArgb copy、cache 或 repaint；不得以提交预烘多倍率帧序列掩盖。
- 参考图无法独立重采：该资产不进入 accepted，保持旧 Flash oracle。
- 环境配置经安全排查后仍不可完成，或 Kimi `k3 + max` 因配额/服务不可用无法完成强制审计：状态记为 `blocked`，不得以降级模型或弱化 Gate 绕过。
- 自动 Gate 和 Kimi 均完成但尚无人类最终验收：状态记为 `awaiting_human_acceptance`；人类提出修改就退回对应切片重测，不得由自动指标或 Kimi 代签。

### 11.3 B0 Exit Gate

- [x] HP/MP active placement closure 已持久化并独立复核，达到 `placement_closure_frozen`；unused library 未混入，整座 HUD 的 BitmapFill 未误算进本纵切。
- [ ] §6.4 oracle provenance、accepted corpus 与人工来源/crop 复核完整，达到 `oracle_frozen`。
- [ ] `Svg.Skia` 决策由 provisional 转为 accepted，或已有修订 ADR 明确替代候选。
- [x] 依赖/许可证/native/security/payload-size 审计有结构化证据。
- [x] B0-03a exact SDK selector/setup-check 的 only-10.0.301 等负例与 repo-root exact-positive 通过。
- [ ] 两类正式 builder 可 locked restore，并对同一冻结源形成一致 build identity / payload closure。
- [ ] canonical SVG/manifest byte-stable，受控子集 validator fail-closed。
- [ ] SVG/JSON 与包图进入 artifact source；改资产会改变 build identity 与 Core payload closure。
- [ ] production policy 有快速 SVG grammar/hash/closure 回流保护，不能只靠一次性 xUnit。
- [ ] runtime 只在新尺寸/DPI key bake，稳态不 parse/raster。
- [ ] 物理 scale contract 已冻结；PArgb、透明边、DPI、cache、dispose/perf 门通过。
- [ ] 最大 viewport/DPI 的 3000 tick A/B 已覆盖完整 NativeHud union repaint/commit；计数/UI p95/union 面积与 handle/长循环 Gate 满足 §8.3，CPU/alloc/GC/working-set 已记录供诊断。
- [ ] fixture HP/MP 静态视觉矩阵与虚拟帧缓动通过，deferred effect 有显式清单，旧 HUD 未隐藏。
- [ ] `PlayerInfoWidget.TryHitTest` 恒 false 的 focused test 与真实窗口鼠标透传手点均通过。
- [ ] `launcher/README.md`、testing guide、总体迁移 ADR 与本台账同步现状。
- [ ] B1 的 visual-state 接口和真实字段草案已审阅，但尚未被误报为 runtime integrated。
- [ ] §9.5 文档级 K0 的问题已有逐条 disposition；B0-07 针对最终代码/资产/结构化测试/视觉报告的 K1 也以 `kimi-code/k3`、`max` 完整结束并可复核，均未降 effort/换模型。
- [ ] 人类已明确接受最终透明 crop、游戏 composite、关键比例、平滑与 UI 交互；自动指标或 Kimi 不代签。

---

## 12. 施工台账与恢复协议

### 12.1 当前台账

| Slice | 状态 | 已有产物/证据 | 未验证 | 下一步 |
|---|---|---|---|---|
| B0-00 | completed | 本 B0-00 commit：两份 ADR 同步；§9.5 k3/max 文档审计；doc governance、链接与 diff check | 无代码/视觉/生产依赖结论 | B0-01A / B0-02 / B0-03a 可并行 |
| B0-01A | completed (`placement_closure_frozen`) | r3：16-file exact closure、HP/MP/shared=10/5/2、17 authored/18 expanded edge、14 timeline、0 BitmapFill/DOMBitmapInstance；Git-canonical digest `6f4bf9…4368`；index/clean-filter/anchor/source-binary verifier 全绿并经独立复审 ACCEPT | actual TestLoader/player load、截图/crop 与人工来源确认归 B0-01B；不声称 `oracle_frozen` | B0-01B 可开始；B0-04 可开始但视觉 Gate 等 01B |
| B0-01B | `capture_tool_recovery_safe`; capture blocked by tool-identity Gate | r4 三文件静态工具；PART **3584**、max **829**、canonical summary **10**、PNG round-trip **2**、SWF recovery **3**、recovery negative **2**；AST/ValidateOnly 与独立恢复安全审计 ACCEPT；原 TestLoader AS/SWF 未变且未启动 Flash | runner/protocol frozen + Git blob 自身份；真实截图/manifest；人工来源、层、crop 与审美确认 | 先补工具自身份并复审；随后才运行精确测试捕获 |
| B0-02 | completed (`isolated_qualification_passed`) | exact SDK + locked restore；build 0 warning/error；行为 **10/10**、fail-closed **16**；HP/MP XFL feature anchors；11 包 license/nupkg + 9 文件/5,289,528 B payload 结构化报告 | `rendererQualified=false`；生产 facade/canonical/policy/许可接受仍归 B0-03b | B0-04 可开始；禁止提前写生产 PackageReference |
| B0-03a | completed | resolver/setup-check 共用 exact 合同；selector + repo-root 集成 **7/7**；setup-check **5/5**；三项首轮并发时序失败隔离复跑 **3/3**，随后全量 xUnit **1257/1257** | 正式 builder 的 10.0.300 证据仍归 B0-03b/发布链 | 继续 B0-01B/B0-04；待真实资产后进 B0-03b |
| B0-04 | ready; exit_waits_B0-01B | B0-01A r3 closure + B0-02 isolated subset 已满足进入条件；无 canonical asset | converter/validator/canonical SVG 与 accepted oracle parity | 开窄 converter/asset 片；视觉结论等 accepted oracle |
| B0-03b | blocked_by_B0-02/03a/04 | 现有 SkiaSharp/runtime inputs 基线 | 生产锁定与 identity 回归 | 等 renderer/SDK/真实 asset |
| B0-05 | blocked_by_B0-03b/04 | 可复用 cache/prewarm/PArgb 范式 | 专用 rasterizer 生命周期、test-only fixed-bounds union/commit 预检与拓扑裁决 | 等依赖/资产 |
| B0-06 | blocked_by_B0-04/05 | NativeHud widget 接口可复用 | fixture parity | 等渲染基座 |
| B0-07 | blocked_by_B0-06 | §9.5 已完成文档建设 k3/max 审计 | 最终实现包 k3/max 再审、全 Exit Gate、人工接受 | 等全片 |

每完成一片，必须在**同一提交**更新此表的状态、产物、确切测试计数/报告、未验证项、下一片；不能只在聊天中留进度。

### 12.2 恢复搜索锚

```powershell
chcp.com 65001 | Out-Null
rg -n -F "HUD-SVG-005" docs
rg -n -F "主角hp显示界面" flashswf/UI/玩家信息界面
rg -n -F "pushUiState" scripts launcher/src
rg -n -F "WantsAnimationTick" launcher/src/Guardian/Hud
rg -n -F "SkiaSharp" launcher/Directory.Packages.props launcher/packages.lock.json
rg -n -F '"includeExtensions"' config/build/runtime-inputs.v2.json
```

行号只作审阅快照；恢复时以 ID、symbol、协议字面量和路径为锚。

### 12.3 下次会话开场

> 三条无冲突工单可并行：B0-01A 把已核实的 HP/MP placement/source-binary chain 固化入仓；B0-02 把 isolated preflight 收敛成生产 strict facade/真实 corpus Gate；B0-03a 独立修 exact SDK resolver/setup-check。B0-01B 只在 01A 后用 TestLoader scratch 捕获，不接 `/console`、真实存档或生产 AgentControl；任何一片完成都在同提交回写 §12。

---

## 13. 关联资料

- [玩家信息界面 → C# NativeHud 迁移架构](玩家信息界面-NativeHud迁移-架构设计-2026-06-21.md)
- [Launcher 子系统 source of truth](../launcher/README.md)
- [验证矩阵](../agentsDoc/testing-guide.md)
- [runtime build reproducibility v2](runtime-build-reproducibility.md)
- [技术栈收敛决策](tech-stack-rationalization.md)
- [文档治理](../agentsDoc/documentation-governance.md)
- [`Svg.Skia` upstream](https://github.com/wieslawsoltes/Svg.Skia)
- [`Svg.Skia 5.1.1` NuGet](https://www.nuget.org/packages/Svg.Skia/5.1.1)
