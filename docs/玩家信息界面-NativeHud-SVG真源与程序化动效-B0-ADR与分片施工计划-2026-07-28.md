# 玩家信息界面 NativeHud：SVG 真源与程序化动效 B0 / ADR / 分片施工计划

**文档角色**：`flashswf/UI/玩家信息界面` 的**视觉资源与 NativeHud 渲染基座专项 ADR + B0 可执行台账**。本文只权威定义 SVG 真源、受控子集、渲染器准入、运行时烘焙、模拟信号 harness、视觉对照与施工分片；状态所有权、AS2/C# 边界、停止线、显示公式和总体迁移阶段仍以 [玩家信息界面 → C# NativeHud 迁移架构](玩家信息界面-NativeHud迁移-架构设计-2026-06-21.md) 为准。

**最后核对代码基线**：B0-06 最终实现与首轮实现包异构审计修复冻结于 commit `bf8dd2c410267855c8ea12f25a594042b3158479`（2026-07-29）；收尾 merge `8c703c6811ef264da36eb482db524a16a4e64958` 的双亲为该实现基线与 `origin/main=c96f4c3d750561022b706c72a4d53050431e627d`。两份最终报告及同步文档已由 evidence/docs-only commit `81168ece8cd295d8e15b8f6baed46a0da7f9c549`（tree `496faa9afc7de21c082c7440375b4c6b31139d9f`）承载；它精确修改 9 个 evidence/docs 文件、无代码/配置/资产变更，提交后工作树干净，doc governance 与 `git diff --check` 通过。最终 source-freeze 前再次 fetch 发现 `origin/main` 前进到 `232d25ddf96ba39147f3335162d8a2d033c7822f`；merge `2882456c8777246fba8d2f6942ef1027caafc650` 已以 `81168e…c549` 与该远端为双亲无冲突纳入。该上游提交的直接差量只修改贫民窟数据及 `flashswf/arts/things1` 的 XFL/SWF 共 700 个文件，不触及 PlayerInfo、当时已修改的两份 source-freeze 文档、runtime 配置/工具或任一四域输入；`origin/main` 现为 merge 的祖先，ahead/behind=`23/0`。但最终 release prepare 随即 fail-closed 检出该贫民窟数据所派生的 `launcher/web/modules/arena-unit-param-presets.js` 已陈旧；重生成后 `enemyWithParameters` 从 840 增至 848、preset 从 271 增至 272，并新增 `param-b6f7e75f4f3b`（裸体兽化僵尸、`登场动画=坠落`、count=8、唯一来源 `基地门口/贫民窟.xml`）。B0-01A r3 由 verifier 分别绑定 `HEAD`、index、clean-filter worktree 与 source-binary anchor；B0-01B r4-r11 固化恢复安全、实际 runner/parser 的 Git-canonical 自身份、注册 CS6 Debug Player、无引号相对启动、跨完整性级别 authoring 身份与 `Stage.align` requested/reported 语义。B0-04 的资产/证据身份、B0-03b 的新鲜 v2 candidate/production Gate、B0-05 与 B0-06 的机器资格报告只以 §12 和结构化报告为稳定锚，过期临时产物不得回写，且任一 B0 candidate 都不构成正式 runtime。当前 B0-06 报告仍精确绑定 clean 实现基线 `bf8dd2c…8479`、32-file sourceTrace closure 与执行二进制。本切片的两项非文档字节变化是：把 `runtime-github-builder.v2.json` 的 `sourceRef` 更新到 PlayerInfo 目标 tag ref，以及纳入 prepare 枚举的 11 项输出中唯一不一致的上述 registry；另同步专项 ADR、runtime deep doc、Launcher README 与测试指南四份 canonical docs。二者共同使 policy hash、release tree 与 request 身份改变；当前 Index 复算为 policy `0E52F22FD3A42C5770B5B0C7C58E48662097C01CACA8306595991AD61E4DF105`，而 artifact source、producer recipe、toolchain lock 与 build identity 保持不变。双 builder/quorum 绑定本 source-freeze commit/tag；随后另以报告回写提交记录 `-VerifyOnly` 事实，不把回写提交冒充为两类 builder 的被构建源。

**当前裁决状态**：高层方案已接受；`Svg.Skia 5.1.1` 已由 HUD-SVG-005 接受并锁定为 B0 受控子集的生产 renderer。B0-01A 已达到 `placement_closure_frozen`；B0-01B 第七轮的 fresh TestLoader/Debug Player/玩家信息 child 与 11-case raw/crop 已形成 candidate，但人工来源、层、crop 与审美仍未签，所以不是 `oracle_frozen`。B0-02 strict corpus 为 12/12、78 项 fail-closed（其中 58 项值级 grammar），并验证当前 8/8 canonical SVG；B0-04 已冻结 8 SVG（99,564 B）、manifest revision `sha256:c8f58cb7…93871` 与 repo-only provenance。Web、FFDec↔Web、Flash-candidate↔Web 只证明各自 33-PNG/11-PNG 输出的双跑确定性；比较报告因输入路径不同而有不同哈希，且全部无跨 renderer 接受阈值。B0-03b 已达到 `renderer_qualified / candidate_built / NOT_DEPLOYED`；B0-05 已达到 `passed / synthetic_fixed_bounds / split_required`。B0-06 已实现 fixture-only visual state/animation、程序化 HP/MP、MP 双 fragment、HP 固定轮廓与旋转渐变、source-bound path glyph atlas、独立 click-through surface 与 PanelHost 生命周期；HP 三处动态文字采用源红色 Glow，MP 不加 Glow，Skia `sigma=1` / alpha `220` 是 single-pass 近似。formal qualification 为 `passed`、47/47，run `a6aadeb6e3264577bb9da8fe90857a7b`、647,234 B、SHA-256 `65628682…9CD74`；第 3 个 100-cycle warmup group 首次收敛，紧邻 acceptance 的 process/GDI/USER delta=`-3/0/0`。focused 为 136 pass + 3 opt-in skip / 139，clean official full 为 1,737 pass + 3 opt-in skip / 1,740；source-freeze staged snapshot `a7d36f4d0808ffb59e5227aca05265abcc6897d8` 的 Runtime Lane C 为 11/11 exit 0、scalar 567，guardrails 另列 `scripts=3 / unsafeCandidateCases=3`，总耗时 863.010 秒。完整实现包 Kimi `k3 + max` 审计已完成并返回 `REVISE_BEFORE_CLOSEOUT`：3 项 P1 与内部复核发现的 2 项 fail-open/false-green 均已在 `bf8dd2c…8479` 修复，最终增量复审仍待 PASS。evidence/docs-only commit 已闭合；真实游戏 composite、旧 Flash 同屏、真实手点、审美、人类 oracle、本 source-freeze commit/tag 的两正式 builder/quorum 与 K1 最终通过仍是 Exit 阻断；B0 不要求 promotion/部署，真实 `pi_*` 也未接入。

---

## 0. Compact 后恢复卡

### 0.1 一句话目标

把 Flash HUD 中的**静态矢量美术**一次性转换为可审阅、可版本化的 SVG 真源；启动后按真实 viewport / DPI 将静态层烘焙为 PArgb 位图缓存；数值条、裁切、缓动、闪烁与循环光效由 C# 程序状态机组合，不保存逐帧 PNG/SVG。

### 0.2 当前精确状态

- 已完成：本 ADR、B0 分片边界、依赖准入门、runtime build identity 纳入方案与验收词典；Kimi k3/max 的首轮完整文档异构审计见 §9.5。
- 已完成：B0-01A r3 把 HP/MP placement closure/source-binary ancestry 固化入仓；独立 verifier 从 XFL 重建 17 个定义边/18 个路径展开边，复算 Git-canonical digest `6f4bf9f36563c1bd16993c7472c4ebf49321852ab19eebb0bdf6b58df9264368`，并绑定 index/worktree/anchor。它不等于 `oracle_frozen`。
- 已完成：B0-02 隔离资格化的原始依赖/许可/native/payload 审计；当前 strict corpus 已扩至 12/12、78 项 fail-closed（其中 58 项值级 grammar），并验证 8/8 canonical SVG。该历史报告继续保留 `rendererQualified=false`，生产资格另由 B0-03b candidate contract 裁决。
- 已完成窄中间态：B0-01B 第七轮 runner candidate 已绑定 fresh TestLoader、实际 Debug Player、精确 child、11-case raw/crop 与安全恢复；人工复核未签，所以不是 `oracle_frozen`。
- 已完成窄中间态：B0-04 的 8 个 canonical SVG、runtime manifest、repo-only provenance、strict validator 与 Web、FFDec/Web、Flash/Web 诊断已闭合自动结构门；Web 报告以机器字段明确只捕获 canonical static SVG，不含 C# 程序化文字/Glow。一次性 converter 原型按 stop-loss 已移出权威工具树且不进入 build，视觉 Gate 等待人工。
- 已完成：B0-03b 以 fresh v2 candidate `c-c571959c1f2a-08846e81b3-20260728t130535410z-0b23fc7a` 闭合 `Svg.Skia 5.1.1` / `SkiaSharp 3.119.4` 生产包图、共享 strict facade、8 SVG + manifest 的 9 项 embedded resource、notice、窄 artifact-source tree、actual renderer/deps closure、production policy 与全量回归；HUD-SVG-005 已转为 `accepted`，片状态为 `renderer_qualified / NOT_DEPLOYED`。
- 已完成：B0-05 的 typed runtime manifest、viewport-height/576 物理 scale、8-layer atomic raster/PArgb、单 worker latest-wins、16 MiB active+inactive whole-batch LRU、100 churn/3000 current-hit 与 fixed-bounds topology 预检；资格报告为 `passed`，裁决为 `split_required`，但不含生产 widget、实际 layered-window commit 或视觉结论。
- 已完成自动资格、尚未人工退出：B0-06 独立 split surface、fixture widget、程序化 HP/MP、MP 双 fragment、HP 固定轮廓/旋转渐变、path glyph atlas、PanelHost 生命周期与 deterministic C# capture/三方 direct-edge 诊断工具。clean `bf8dd2c…8479` 的 formal qualification 已通过 47/47，C#/Web A/B 与 comparison PNG 闭包也由 [`runtime-qualification.json`](../tools/player-info-hud/evidence/b0-06/runtime-qualification.json) / [`visual-evidence.json`](../tools/player-info-hud/evidence/b0-06/visual-evidence.json) 冻结；完整实现包 Kimi 审计的问题已修复，最终增量复审仍待 PASS。它们都不声称 parity、真实 UiData、游戏 composite、手点或人工视觉结论。
- 未改变：AS2 游戏状态/输入/冷却权威、`FrameBroadcaster` 协议、旧 HUD 可见性与旧 XFL/SWF、药剂拖放命中壳、正式 runtime。fixture surface 是显式 opt-in 的并列诊断面，不会自动隐藏旧 Flash HUD。
- 总体视觉交付严格状态：`canonical_asset_candidate_validated; awaiting_human_review`。不得把结构化验证、FFDec/Web 指标或未签 Flash candidate 写成 `fixture_static_parity`、`fixture_full_parity`、`runtime_integrated`，更不得写成已部署。

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
| HUD-SVG-005 | accepted | `Svg.Skia 5.1.1` 是 B0 受控静态 SVG 子集的锁定生产 renderer；B0-03b 已对真实 8-asset closure 复用唯一 strict facade，并闭合精确包图、embedded/source bytes、actual candidate closure、identity/policy、许可分发与全量回归；不外推为视觉 parity、widget 或部署 |
| HUD-SVG-006 | accepted | 首版 SVG/manifest 作为 Core 的 embedded resource；源文件与依赖共同进入 runtime build identity |
| HUD-SVG-007 | accepted | B0 可 fixture-first，但真实接入仍必须 state-first，不新增第二业务权威 |
| HUD-SVG-008 | accepted | 旧 Flash HUD 在双轨期继续作为独立视觉 oracle 和剩余命中壳 |
| HUD-SVG-009 | accepted | B0 不写双栏装备工作台、药剂管理和旧 XFL；可与另一台机器的装备栏迁移并行 |
| HUD-SVG-010 | accepted | B0-05 的 `synthetic_fixed_bounds` 预检已证明左下 PlayerInfo 与右上 HUD 在单一外接 union 中形成近全屏桥接；B0-06 必须使用独立、紧边界、click-through split surface，不能把 fixture widget 注册进现有 `NativeHudOverlay` |

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

### 0.6 当前双轨下一步

**Oracle 轨**：对 B0-01B 第七轮 Flash candidate 完成人工来源、状态、层隔离、crop 与审美复核，并形成 review receipt。等待人审不阻塞无关结构施工；未签前只能保持 `candidate_captured; awaiting_human_review`，不得写成 `oracle_frozen`。

**工程轨**：B0-05 已完成 raster/cache/PArgb 与 fixed-bounds topology 预检，裁决为 `split_required`。B0-06 已实现独立 split surface、fixture visual state、程序化 HP/MP、MP fill 分片、HP 固定轮廓/旋转渐变与 path glyph atlas；最终实现基线 formal qualification、双份视觉确定性及 evidence/docs-only commit 已经闭合。完整实现包 Kimi k3/max 审计已跑完并完成首轮问题修复，尚余本 source-freeze commit/tag 的双 builder/quorum、最终增量复审 PASS，以及人工 oracle/game composite/真实手点/审美签收；自动证据不能越权给出 parity 结论。

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
assetSetRevision + exactManifestSha256 + layerId + pixelWidth + pixelHeight
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
PlayerInfoFixture
  → PlayerInfoSplitSurface-owned PlayerInfoAnimationModel
  → IPlayerInfoVisualStateSource
  → PlayerInfoWidget
```

真实接入仍只有：

```text
AS2 PlayerInfoState(cur/target)
  → frameEnd 批量 FrameBroadcaster.pushUiState
  → NativeHudOverlay full snapshot
  → B1 runtime adapter / IPlayerInfoVisualStateSource
  → PlayerInfoWidget
```

fixture model 与未来 runtime adapter 只能经同一个 getter-only visual-state 接口供 painter 读取；B0 中 `PlayerInfoSplitSurface` 是 `PlayerInfoAnimationModel` 的唯一 owner/推进方，widget 不保存 model，也不暴露 mutation proxy。fixture 代码不得进入生产数据源选择，不得反向写游戏。B0 是总体阶段 4/5 的无业务信号预备切片，不是重开已经完成的“阶段0 行为基线”。

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
          8-layer Format32bppPArgb batch cache
                          │
fixture / PlayerInfoState ── surface-owned visual state machine
                          │  clip / transform / alpha / text
                          ▼
                 PlayerInfoWidget.Paint
                          │
                          ▼
       独立 click-through PlayerInfo split surface
```

`Svg.Skia` 只负责受控静态 SVG → Skia display list / bitmap，不负责业务动画时钟，不启用 JavaScript 包，不把 SVG DOM 暴露为运行态游戏模型。B0-05 已证明 PlayerInfo 不能并入现有 `NativeHudOverlay` 的单一外接 union；独立 surface 只隔离合成/提交，不新建第二状态权威。

---

## 4. Canonical asset contract

### 4.1 当前与目标目录

```text
launcher/src/Guardian/Hud/PlayerInfo/
  PlayerInfoStrictSvg.cs
  PlayerInfoSvgAssetCatalog.cs
  PlayerInfoWidget.cs
  PlayerInfoVisualState.cs
  PlayerInfoAnimationModel.cs
  PlayerInfoFrameCompositor.cs
  PlayerInfoPathGlyphAtlas.cs
  PlayerInfoPathGlyphAtlas.Generated.cs
  PlayerInfoRasterPlan.cs
  PlayerInfoRasterPipeline.cs
  PlayerInfoSvgRasterizer.cs
  PlayerInfoSplitSurface.cs
  Assets/
    player-info.manifest.json
    hp/backplate.svg
    hp/fill.svg
    hp/rim.svg
    mp/backplate.svg
    mp/fill.svg
    mp/rim.svg
    mp/rim-vf70.svg
    mp/rim-vf91.svg

tools/player-info-hud/
  README.md
  run-web-svg-harness.js
  capture-ffdec-reference.ps1
  compare-ffdec-web-svg.js
  compare-flash-web-svg.js
  compare-b0-06-csharp-web-flash.js
  generate-player-info-glyph-atlas.py
  run-b0-05-runtime-qualification.ps1
  run-b0-06-runtime-qualification.ps1
  evidence/
    b0-01/
      closure.json
      source-binary-chain.json
    b0-04/
      conversion-provenance.json
      canonical-validation-report.json
    b0-05/
      runtime-qualification.json
    b0-06/
      glyph-atlas-provenance.json
      runtime-qualification-attempts.json
      runtime-qualification-premerge-v3.json
      visual-evidence-premerge-v3.json
      runtime-qualification.json          # final implementation-base machine qualification
      visual-evidence.json                # final implementation-base deterministic diagnostic index
  renderer-qualification/

launcher/tests/Guardian/Hud/PlayerInfo/
```

`Assets/`、诊断/qualification 工具、B0-04 evidence、生产 `PlayerInfoStrictSvg` / `PlayerInfoSvgAssetCatalog`、raster pipeline，以及 B0-06 的 `PlayerInfoVisualState`、`PlayerInfoAnimationModel`、`PlayerInfoFrameCompositor`、`PlayerInfoPathGlyphAtlas`、`PlayerInfoWidget`、`PlayerInfoSplitSurface` 与专属 focused tests 已形成。`PlayerInfoSplitSurface` 唯一持有/推进 fixture `PlayerInfoAnimationModel`；`PlayerInfoWidget` 只消费注入的 `IPlayerInfoVisualStateSource`，不持有 model 或 mutation proxy。widget 仍是 fixture-only 内部绘制单元，不实现现役 `INativeHudWidget`，也没有真实 UiData adapter；独立 surface 不是 `NativeHudOverlay.RegisterWidget` 的成员。闭包规模很小，B0 不另建一套通用 JSON Schema 目录；manifest/closure 规则由窄 validator 与 focused tests 持有，只有 B2 扩域后出现第二个真实消费者才考虑抽出 schema。现役 SDK glob 已递归收集 `launcher/tests/Guardian/Hud/PlayerInfo/`；这是有意的领域聚合，仍由现有 `Launcher.Tests.csproj` 递归 glob 收集，不新建测试工程。B0-05/B0-06 各自只有窄 qualification runner。qualification 通过 compile link 复用生产 strict facade，不保留第二份 validator。中央高冲突文件（csproj、包版本、lockfile、runtime inputs）只在 B0-03b 集中落盘，没有和 widget/美术实现混片。

### 4.2 Runtime manifest 与 provenance evidence 分离

不得把运行时渲染合同与审计来源混成同一个 embedded blob。否则源 commit、重采 oracle 等非渲染变化会无意义地改变 Core payload。B0 固定为两份合同：

1. **Embedded runtime manifest**：只记录运行时选择与校验所需的 `schemaVersion`、`assetSetId`、内容导出的 `assetSetRevision`、`rasterContractVersion`、每个 SVG SHA-256、原始 bounds/registration/unit scale/canonical `viewBox`、稳定 layer ID/绘制顺序/blend/opacity/cacheability、gauge 方向与 clip 语义/normalized 边界，以及 renderer 精确已验证版本和 SVG feature-set ID。
2. **Repo-only provenance/oracle evidence**：记录原始 XFL 路径、symbol/linkage、完整 placed instance path、源 Git tree/blob ID 与 closure SHA-256、converter/规范化规则版本、独立 oracle 场景和文件 hash，以及 §6.4 的捕获环境。它接受“重新取证即形成新证据 revision”，不进入 Core embedded resource，也不参与运行时资产选择。

两份文件均不得记录本地绝对路径或机器名。runtime manifest 不得记录源 commit、生成时间戳、oracle hash 等与渲染字节无关的字段；相同 runtime 输入重跑必须 byte-stable。provenance evidence 的源身份使用 Git blob/tree OID + SHA-256，不用含糊的“当前 commit”代替实际闭包。

当前 runtime manifest 为 `cf7.player-info-hud.asset-manifest` schema 1，冻结逻辑像素/20 twips、舞台 `1024×64`、全局 MP→HP 绘制顺序、`Svg.Skia 5.1.1` / `SkiaSharp 3.119.4`、8 个 exact asset hash、HP 128 格径向裁切与每 source frame 顺时针 `2.8125°` 的**渐变坐标**旋转、MP 100 格三段 mask correspondence 及 1/70/91 rim/palette 关键变体。运行时 cache identity 必须同时绑定 asset-set revision 与 exact manifest SHA-256；provenance 单独位于 `tools/player-info-hud/evidence/b0-04/`，不嵌入 Core。

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

2026-07-28 的 ignored `tmp/` 隔离预检已取得以下**前置证据**：完整候选图新增 11 个包节点，现有 `SkiaSharp 3.119.4` 未变；producer-shaped win-x64 payload 新增 9 个文件、5,289,528 B，未带入非 Windows native；locked restore、reflect gradient、clip/local `use`、Premul BGRA、独立并发 parse、共享只读 draw 与两批各 500 次 dispose smoke 均通过，漏洞/弃用扫描为零。`renderer_preflight_passed` 只描述这份历史 ignored-tmp spike，不是 §10 的正式交付状态；它随后已被 tracked `isolated_qualification_passed` 取代，且始终不能提前冒称 `renderer_qualified`。

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

### 5.5 B0-03b：生产锁定动作与最终 Gate

B0-02、B0-03a 与 B0-04 结构入口满足后，本片已经单独落盘：

1. `launcher/Directory.Packages.props` 精确固定 `Svg.Skia 5.1.1`，既有 `SkiaSharp` 保持 `3.119.4`；主 csproj 使用无版本 `PackageReference`，win-x64 lock graph 由精确 SDK `10.0.300` 的 force-evaluate + locked restore 生成/复核；
2. 显式嵌入真实 8 SVG + runtime manifest，共 9 个固定 LogicalName；repo-only provenance/oracle evidence 保持 0 项 embedded；
3. `PlayerInfoStrictSvg.cs` 成为生产与 qualification 唯一 strict facade 源；`PlayerInfoSvgAssetCatalog` 绑定完整 manifest、exact source bytes 与最小 raster，qualification fixture 不进入生产选择；
4. `launcher/THIRD-PARTY-NOTICES.txt` 记录完整依赖 attribution、MIT/MS-PL 与 Win32 bundled notice，并以 LF canonical byte 同时进入 artifact source、publish/candidate payload 和 packer 白名单；
5. `tools/validate-player-info-svg-production-contract.ps1` 丢弃调用者注入的 dotnet host，复用正式环境门，locked restore/build 后只对 exact v2 candidate 执行 full canonical + strict/payload/notice/deps Gate；runtime 根或任意后代出现 reparse/junction 会在递归枚举前 fail-closed。随后 renderer-family DLL/native 文件按 candidate 递归实际枚举，相对路径集合 exact=11、每项非空并记录 actual size/hash，实际字节再由 candidate payload closure/build identity 绑定；deps 的 libraries 与唯一 renderer-bearing runtime target 也必须 exact；`--core` 明确为 `policyEligible=false` 的诊断 seam；
6. production policy 以 `candidate-player-info-svg-contract` 调用该门；runtime inputs、workflow trigger、identity/queue/release-state 与 packer 都有对应回归，production contract 的跟踪负例会注入额外 `Svg.Foo.dll`、嵌套 `libHarfBuzzSharp.so` 和 deps `Svg.Foo`，三类都必须 fail-closed。

LF-canonical notice 修复后的 fresh v2 candidate `c-c571959c1f2a-08846e81b3-20260728t130535410z-0b23fc7a` 已通过 candidate production contract、production policy 与本片全量测试，因此 HUD-SVG-005 由 provisional 转为 accepted，并记 `renderer_qualified`。旧 candidate、单独 core 诊断或 B0-02 的 `rendererQualified=false` 报告仍不能代替该 Gate。

### 5.6 Runtime build identity 与 payload closure

`config/build/runtime-inputs.v2.json` 已把 csproj、中央包版本、lockfile 与 `launcher/THIRD-PARTY-NOTICES.txt` 列为 fixed artifact source，并新增只覆盖 `launcher/src/Guardian/Hud/PlayerInfo/Assets` 的窄 `.svg/.json` tree；整个 `launcher/src` 的任意 JSON 没有被顺带扩入。回归现固定：

- 8 SVG + manifest + notice 恰好形成 10 项 PlayerInfo artifact-source 输入，repo-only evidence/provenance 与 qualification fixture 不进入 artifact source；
- 改任一 SVG byte 必改 artifact source / build identity，而 producer recipe、toolchain lock 与 policy 保持不变；index 模式继续忽略未 staged 的 byte；
- 9 项 embedded resource 的 source exact bytes 与 Core assembly 同时由 production contract 校验，真实 candidate payload closure 因而绑定资产内容；
- `.github/workflows/runtime-bundle-integrity.yml` 对 asset/notice 与 production validator/qualification policy 输入均有触发回归；前者经 artifact source，后者是少数显式 policy trigger；
- packer 对 runtime manifest、notice 与 11 个 renderer managed/native 文件使用逐文件白名单，不用 `*.dll` 扩大收编范围；production contract 另从 candidate 递归枚举实际 renderer-family 文件，不能因 expected 白名单存在就漏过额外顶层或嵌套文件。

受控 1-byte sensitivity 证明把 `hp.fill` 从 13,460 B / `44E12F…` 改为 13,461 B / `97F1A171…`：artifact source `4502F490…→1902DF44…`、build identity `C571959C…→71CB5FA3…`、Core `3262F0CB…→96E704D1…`、payload closure `C60757A6…→626EB2D5…` 同时变化，而 producer recipe `B97998EA…` 与 toolchain `7B83229B…` 不变。实验 byte 已精确恢复，Worktree=Index，canonical dev pointer 重新指向 C571 candidate。

正式发布仍遵守 [runtime build reproducibility](runtime-build-reproducibility.md) v2；B0 日常开发停在 isolated candidate 即可，不要求每片 promotion。

### 5.7 一次性准入证据与长期生产门

production policy 不会因为存在新的 launcher xUnit 就自动执行它，因此 B0-03b 同时建立了两层：

- **当前单片准入证据**：完整 renderer corpus、依赖/许可/native/payload、9 embedded、source exact bytes、notice、candidate 实际 DLL/native/deps exact closure 与防御负例，已由 §12 的 fresh v2 candidate + policy/全量测试闭合；
- **长期回流保护**：`candidate-player-info-svg-contract` 已接入 `Get-Cf7ProductionChecks`，对每个待签 receipt 的 exact candidate 重跑 locked production contract；policy 自测固定其项目根、candidate 根、锁定 SDK 与 fail-closed 调用。

两类正式 builder 的 locked restore 与一致 identity/closure 仍是独立的正式发布/B0 Exit 门；本地 candidate 或 production policy 通过不能替代真实跨 faultDomain 证据。B0 最终只授权证明 quorum、不授权部署，因此使用现役 `promote-runtime-bundle.ps1 -VerifyOnly -ReportPath <absolute-new-json>` 重放同一 production 验证链并留下 `cf7-runtime-promotion-preflight.v2`；该报告明确不可作为 promotion 输入，且 runtime/release-state/promotion/deployment 均不改变。不得另造平行 verifier，正式 promotion 仍必须去掉 VerifyOnly 重新跑全链。该 policy/构建门槛变化已同步 runtime/testing canonical docs；只补 xUnit 或只取得一次 candidate 报告都不得写成“已 promotion / 已部署”。

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

B0-04 实际执行触发了上述 stop-loss：窄 converter 先以相同输入 A/B 产生 7/7 字节相同的 6-asset seed（revision `sha256:02d4f01e…e42035`），随后发现把 authoring 时间线全部泛化为长期转换器的维护成本高于 8 个目标资产，因此不把原型纳入 build 或仓库权威。最终 canonical 集由该 seed、XFL exact edge/gradient/matrix 与 FFDec 二进制交叉参考人工收敛为 8 个 SVG：补入 MP `装饰信息` source frame 69/90 对应的 `rim-vf70`/`rim-vf91`，将 HP Bevel 展开为命名矢量渐变组，对两个 determinant=0 的径向渐变分别采用已登记的 first-stop solid，HP 红色填充只旋转 `hp-fill-gradient-0003` 的 gradient transform 而不旋转轮廓。`conversion-provenance.json` 明确不声称 converter 可复现、Adobe filter 像素精确或视觉已接受。

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
- 本片临时替换的是 tracked template 生成的 `scripts/TestLoader.as`；CS6 authoring target 只能是 `scripts/TestLoader/TestLoader.xfl`，产物只能是 fresh `scripts/TestLoader.swf`，后者再加载既有 child `flashswf/UI/玩家信息界面.swf`。`compile_action.jsfl` 必须关闭已打开的 exact TestLoader 文档并从磁盘重开后才 publish；发布后 IDE 再次留下 `TestLoader.xfl` 标签不代表使用旧内存。B0-01B 不修改、不发布玩家信息 UI XFL、main 或 asLoader；只有 §6.4 的 ancestry/runtime-load 绑定仍无法闭合时，才另开精确 UI XFL publish/verify 取证。
- TestLoader 在 draw 前显式固定 `_root._quality="MEDIUM"`，与现役 `引擎_lsy_常数.as` 一致；manifest 和每个 case 的 trace 都记录实际 `_quality`，不靠播放器默认值决定抗锯齿、渐变或 filter 基线。
- case 只允许 `empty/min_step/p25/p50/p75/p99/full` 与 MP 结构断点 `mp_vf34/mp_vf35/mp_vf70/mp_vf91`。后四项分别精确覆盖 MP topology hard cut 的两侧与 palette 阈值，不能只由普通百分比抽样代替。HP 使用 `max=12800`、MP 使用 `max=10000`，让所有目标帧都能由整数精确表达；模板不接受任意 CLI 数值。
- 调用现役 `.刷新显示()` 后把 target/current frame 对齐；固定 `网格动画/血槽内动画/血槽光效` 三个相位，静态 corpus 再隐藏 deferred `血槽光效` 并回报 hidden，同时在 closure 中保留其脚本可达边；隐藏韧性/经验/技能/药剂等非本纵切层。
- 在 Flash 内用透明 `BitmapData(1024,64,true,0x00000000)` identity draw child；manifest 写 `background=transparent_argb_0`、`compositeBackgroundId=null`。每个 case trace 精确 raw/max/ratio、target/current frame、三个相位、visibility，以及刷新后的 HP 当前/最大/百分比、MP 当前/最大/百分比和实际存在的合并显示文本；runner 独立计算期望帧/文本并拒绝偏差。
- ARGB 物理记录携带 `runId/caseId/row/part/partCount/b64`。runner 先记录 flashlog watermark，只接受精确一个同 runId 的 start→complete 闭合块、每个 case 恰好一组 state 与 64×8 条连续 PART、无重复/越序/未知字段/未知类型且无 failure sentinel；每行 Base64 解码后必须精确重编码为同一 canonical 字节串，旧播放器迟到输出不得进入本轮块。
- scratch transaction 必须复用现役 mutex、BOM、source backup/restore sidecar 与 installed/original SHA 校验；在 source marker 建立后、编译前还必须为既有 `scripts/TestLoader.swf` 建立持久 sidecar/byte backup。只有 compile 子进程返回、全局 uncertain marker 不存在且 compiled identity 已冻结时才允许自动恢复；恢复顺序固定为 SWF → AS → sidecar/backup cleanup → mutex release，任一 late-write/identity drift 保留材料并写 uncertain marker。固定用 `compile_test.ps1 -Target test -PublishOnly -VerifySwf scripts/TestLoader.swf`，再由 runner 启动精确播放器；runner 只管理自己 `Start-Process -PassThru` 得到的 PID。先写 ignored `tmp/`，人工确认状态/隔离层/crop 后才把 accepted PNG/manifest 晋升到 repo evidence。

r4 静态工具已用 3,584 条 PART、最大物理行 829 字符、10 条 canonical summary、2 轮逐像素 PNG/crop round-trip、3 类 SWF 恢复事务和 2 类恢复负例完成独立审计；ValidateOnly 明确未启动 Flash，原 `TestLoader.as`/`TestLoader.swf` 字节与 mtime 未变。r5 进一步把 `capture-flash-oracle.ps1` 与 `flash-oracle-protocol.ps1` 的实际 raw bytes、Git blob OID/bytes/SHA 和候选 snapshot 交叉绑定；真实 capture 在建立 mutex/事务前及持锁期间都要求两文件 `HEAD=index=clean-filter`。r6/r7 允许 watermark/final snapshot 合法为空，但最终协议仍必须精确闭合 START→COMPLETE；r8 只接受唯一注册 `\FlashCS6Task` 的 `Flash.exe` 同根 `Players/Debug/FlashPlayerDebugger.exe`，并在 admission、prelaunch、owned PID、自然退出与持锁恢复阶段复验任务 action、路径、长度、mtime、SHA-256 与 Authenticode。r9 将 corpus 扩为 11 case（5,632 PART、14 条 canonical summary），并固定 `WorkingDirectory=scripts/`、单一无空格/无引号 token `TestLoader.swf`；纯 launch plan 必须把二者反解为精确 `$loaderSwfPath`，静态合同拒绝绝对路径、引号、路径分量或第二个 `ArgumentList`。

2026-07-28 的前四轮真实 capture 都在 fresh TestLoader publish 后停止，未生成 candidate。前三轮依次发现空 `byte[]` binder、空 trace 字符串 binder、错误 release standalone player；修复后第四轮由 CS6 15 秒生成 fresh `scripts/TestLoader.swf`（387,374 B → 389,093 B），再启动注册 Debug Player `11,2,202,228`，但全局 `flashlog.txt` 自 player start 起仍为 0 B，180 秒后由 exact owned-PID cleanup 回收。运行后 `TestLoader.as`/`TestLoader.swf`/installed command 均恢复到运行前 SHA-256 与 mtime，且无 scratch/uncertain/recovery marker。随后检查 Player 的“最近打开”记录，确认旧调用实际传入尾部带字面引号的 `TestLoader.swf"`；同一播放器用不带引号的 release SWF 绝对路径 8 秒产生 15,042 B trace，用 r9 的 `scripts/` cwd + `TestLoader.swf` token 8 秒产生 15,019 B trace。故第四轮并未执行目标 SWF，根因不是 `mm.cfg`/trust、CS6 未重启或 XFL 内存陈旧。

r9 提交并取得 `strictToolIdentity=strict` 后进行了第五轮：CS6 17 秒生成 fresh `scripts/TestLoader.swf`（387,374 B → 389,159 B），但 runner 在启动 Player 前发现唯一仍存活的 Flash authoring PID 16952 的 PowerShell `.Path` 为空，按身份门 fail-closed。随后以只需 `PROCESS_QUERY_LIMITED_INFORMATION` 的 `QueryFullProcessImageNameW` 对同一 PID 取到注册 `\FlashCS6Task` action 的精确路径；原 AS/SWF 已恢复且无 marker。r10 必须只替换进程路径读取机制，继续要求唯一 Flash PID、注册路径相同以及文件长度/mtime/SHA/签名身份；提交并复验 strict 后重采。仍不得通过延长超时、改用 release player或把窗口截图冒充 accepted oracle 来绕过。

r10 提交并再次取得 `strictToolIdentity=strict` 后进行了第六轮：CS6 15 秒生成相同 389,159 B fresh SWF，注册 Debug Player 随后真实执行 TestLoader 与 child，写出 4,463,997 B flashlog；START/CHILD、11 组 STATE、5,632 条 PART 与 COMPLETE 均存在。parser 在第一个 START 字段即因 `stageAlign` 期望 `TL`、运行时回读 `LT` 而拒绝，未晋升 candidate；原 AS/SWF 又精确恢复且无 marker。AS2 模板仍显式赋值 `Stage.align="TL"`，Adobe Player 11.2 将等价枚举顺序规范化为 `"LT"`。r11 将二者作为 requested/reported 两个事实固定；用第六轮完整 trace 重放已通过 11 case、exact child binding 与 14 条 canonical summary。提交并复验 strict 后仍须重新捕获，不能直接把失败轮日志晋升。

r11 提交 `a6490be9…8869` 后的第七轮已取得 `strictToolIdentity=head_index_clean_filter_equal` 并成功生成 candidate `20260728T101414Z-d643ecd574a147009c8ada8d6ee1dc9d`：CS6 15 秒生成 389,160 B fresh TestLoader SWF（SHA-256 `ace5b6dc…10b2`），注册 Debug Player `11,2,202,228` 自然退出，实际 child SHA-256 `450b1f9a…a615` 精确命中；fresh flashlog 为 4,463,997 B、精确 run block 为 4,458,323 B；11 个 raw 均为 1024×64，10 个 crop 为 278×45，`empty` crop 为 280×45；manifest 为 61,487 B、SHA-256 `dcc9e11a…bf472`。原 TestLoader AS/SWF 均按事务精确恢复。该 manifest 的 `humanReview.status=required`、四项 checks 仍为 null，所以状态只能是 `candidate_captured; awaiting_human_review`，不能写成 `oracle_frozen`。

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
- `PlayerInfoAnimationModel.WantsAnimationTick` 仅在 ratio 过渡或有限动效时为真，由 `PlayerInfoSplitSurface.UpdateAnimationTimer()` 读取；widget 不拥有动画时钟。B0 未启用永久环境光效。
- `PlayerInfoWidget.TryHitTest` 必须恒返回 false；B0 是只读镜像，不能因 NativeHud overlay 自身可命中而吞掉游戏区点击。
- decorative loop 不得无条件把整层永久拉进高频 repaint；B0 默认静态首帧，B3 再用测量决定 tick rate。
- 当前 overlay 最短重绘约 33 ms，单个 widget 请求动画仍会重画全部可见 widget 并提交 union；B3 永久环境动画必须先通过全 union 成本门，必要时另做局部子合成。
- B0-05 的 test-only fixed-bounds probe 已作出显式裁决：1024×576 下，右上现役固定块 `252×32@(724,0)` 与完整 PlayerInfo stage `1024×64@(0,512)` 会提交整个 1024×576；即使只取 canonical 紧 envelope `282×46@(0,512)`，外接提交仍为 `982×564`、占 viewport 93.90%，相对两个可见矩形精确并集放大 26.33×。因此 HUD-SVG-010 为 `split_required`；B0-06 不得把 `PlayerInfoWidget` 注册进现有 `NativeHudOverlay`，必须使用独立紧边界 click-through surface。
- bake 在后台线程完成，UI 线程只做短事务换入；所有 `SK*`/Bitmap 所有权和 dispose 路径必须单测。
- `TryUseCurrent` 只在所有权锁内借用 current batch；Bitmap 不得逃逸，回调内 `Request/Dispose` 必须 fail-closed，且回调不得同步等待另一线程的 pipeline mutation，避免可重入 Monitor 提前销毁或跨线程互等。`Dispose` 必须丢弃排队通知，并在非观察者线程调用时等待正在执行的通知退出；返回后不得再投递旧 `BatchPublished`。B0-05 的 `Dispose` 对 active raster worker 只发 cancel，不冒充同步终止；并发 shutdown 的资源终点是随后 `await WaitForIdleAsync()`，B0-06 接入 surface 时必须显式 drain，或先另行转正为可证明无自等死的同步释放合同。
- 输出统一为 `Format32bppPArgb`，覆盖透明边、半透明渐变和 premultiplied BGRA 对照。
- B0-05 的 PlayerInfo 专用管线只缓存原子 8-layer batch；active+inactive 合计 16 MiB，单 worker latest-wins，旧 batch 只在新 batch 完整成功后换入。它沿用 byte-budget/LRU 范式，不创建无预算全局字典，也不冒充通用 `BitmapLruCache` 实例。

### 7.4 B0-06 已实现边界

- `CF7_PLAYER_INFO_FIXTURE_CASE=<allowlisted-case>` 是唯一进程入口；空值保持完全不创建，`--bus-only`、`useNativeHud=false` 或非 exact allowlist 值均 fail-closed。现役 11 case 是 `empty/min_step/p25/p50/p75/p99/full/mp_vf34/mp_vf35/mp_vf70/mp_vf91`，只供 fixture/取证，不是用户配置或生产数据源选择。
- `PlayerInfoFixtureInput → surface-owned PlayerInfoAnimationModel / IPlayerInfoVisualStateSource → PlayerInfoWidget` 保持只读单向关系；surface 是 model 的唯一 owner/推进方，widget 不持有 model 或任何写代理。`PlayerInfoWidget.TryHitTest` 恒 false，不实现真实 UiData consumer，也不存在 `pi_*`。`PlayerInfoSplitSurface` 是单独的 `OverlayBase` / `IPanelHudCompanion` HWND，按 tight bounds 定位、继承 click-through/`HTTRANSPARENT`，不会改变现役 NativeHud union。
- MP fill 在 bake 时按 manifest 的两个 clip binding 生成独立、不可变、由 batch 所有的 PArgb fragment；合成器按虚拟帧建立 mask。HP 把固定覆盖轮廓与 `hp-fill-gradient-0003` 坐标旋转分开，不能旋转轮廓。数字使用由 XFL/SWF 来源与生成器身份约束的 Aero/LCD Std path glyph atlas，不读取机器字体，不新增运行时字体依赖；focused Gate 要求 UTF-8 无 BOM，把 checkout CRLF clean 为 canonical LF、拒绝 lone CR，再按 path/canonical byte length/SHA-256 校验 `PlayerInfoPathGlyphAtlas.Generated.cs` 与 provenance，任一漂移都 fail-closed。effect policy 以 typed disposition 固定为一个 B0 `ImplementedActive` 层和两个 `DeferredB3` HP 层；HP 的 3 个动态文字布局使用 source-red `SKColor(255,0,0,220)`、`sigma=1` Glow，MP 文字不加 Glow。源 XFL 的红色、blur 2、strength 1.5 语义被保留为依据，但 alpha/sigma 是 Skia single-pass 近似，不声称 Adobe filter 像素精确。`PlayerInfoCompositionRecipe` 只冻结当前七个文字布局与 HP paint source，compositor 对 disposition/ID 漂移 fail-closed，不建立通用效果图。
- Program 只在全部入口条件满足后发布 surface ownership，并明确记录“old Flash HUD remains untouched”；fixture 创建失败即清理候选并保留旧 HUD。PanelHost 开/关会 suspend/resume 该 companion；Resume 先置 `_resumePending`，只有 viewport/plan 有效且 `Pipeline.Request(plan)` 已建立时才清除，布局暂时无效或 request 失败会等下一次布局事件重试，不能出现“Host 已恢复但 surface 永久隐藏”的假成功。启动先透明 precommit，reveal 后 ready，owner 隐藏/关闭时停止 timer，shutdown 先 `BeginShutdown`，再等待 raster pipeline idle 后 dispose，旧 batch/迟到通知不得越过终点。
- 2026-07-29 切换到 ChatGPT App 并完成本地授权后，Computer Use 已恢复初始化、`list_apps/list_windows`、显式窗口激活、UIA 标题读取与截图；它枚举并前台捕获到 Flash CS6 当前活动文档 `TestLoader.xfl`，Output 面板显示 `Compile | done.`。被 ChatGPT 遮挡时的首次捕获误取前台桌面，显式激活 Flash 后才得到正确画面，因此后续必须先激活目标窗口再采；Flash CS6 的 UIA 树也只暴露窗口/标题栏。当前没有独立 Test Movie/SWF 播放窗口，所以该证据能确认 authoring 文档，不能确认运行时实际加载的 SWF，更不能把自动截图“补算”为真实手点、游戏 composite 或审美接受；这些仍须人类签收。

### 7.5 B1 visual-state 接口与字段草案审阅

2026-07-29 对 B0→B1 交接面完成一次显式审阅，结论为 `reviewed_draft_not_integrated`：

- 接受当前 `internal IPlayerInfoVisualStateSource` 作为 B0 内部渲染 seam：它只有 `PlayerInfoVisualState VisualState { get; }`，没有 setter、事件、总线依赖或反向写游戏状态的能力。B0 中 `PlayerInfoSplitSurface` 唯一持有并推进 `PlayerInfoAnimationModel`，`PlayerInfoWidget` 只读消费注入接口；B1 不得把 adapter 的可变 snapshot 直接泄漏给 painter。
- B1 wire 草案只保留总体 ADR §2.1 已登记的四个原值字段：`pi_hp`、`pi_hpMax`、`pi_mp`、`pi_mpMax`。C# 仍按冻结公式生成 `cur/target` 与 41-tick 等完整缓动序列；不新增影子 frame、百分比文本或通用 CharacterBuild stats 适配。
- 这四个名称只是经审阅的协议草案，不是本轮 schema/runtime 事实。当前 `launcher/src` 没有 `pi_*` 字段、`IUiDataConsumer` 实现或 PlayerInfo adapter；B0 fixture allowlist 也不能作为生产入口。因此本结论不得写成 `runtime integrated`。
- B1 在落第一行协议代码前必须另行冻结：frameEnd 原子 snapshot 边界、epoch/sequence 的生成与比较规则、断线/重连/切场景的失效与全量重同步、乱序/重复/缺包处置，以及 invalid 值究竟由 AS2 发布层还是 C# adapter 裁决。未完成这些决策时，`invalid_input` 不能被改称 `stale`，也不能用 last-known-good 无限掩盖旧 epoch。

---

## 8. Fixture harness 与验收矩阵

### 8.1 Fixture 场景

- SVG conformance：奇偶/非零填充、自交/孔洞、local `use`、负 scale/旋转/斜切/nested matrix；
- paint：solid、linear/radial、`spreadMethod=reflect`、多 stop alpha、layer opacity、clipPath 边缘；
- HP/MP：0、1 个最小格、25%、50%、75%、99%、100%；MP 另固定虚拟帧 34/35、70、91，覆盖 topology hard cut 两侧与 palette 阈值；
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

在登记的 Windows x64 基线机上。B0-05 报告 `tools/player-info-hud/evidence/b0-05/runtime-qualification.json` 的测量种类严格为 `synthetic_fixed_bounds`：

- 接受报告为 canonical LF、无 BOM 的 run `68c5252325594787aa5e6daf0cb856e8`，705,417 B，SHA-256 `217F28CDD6257B2CF374B9717CF87585A46277CEFD9B4AFD29C60993E0D4C624`。它把 pre-commit HEAD `1bb3307c193de569172b16d7a68ba3b3443f5c8e`、37-file executable source closure `6B6B72A124ACF405BD31B498313086AF5FFDDBD1B0755B7F227C501A17870C38`、执行中的 test DLL、Core、exact 11-file win-x64 renderer target closure、独立枚举的 exact 15-file test-output renderer-family closure及 10 项 actual-loaded 子集分别绑定；text-free corpus 未加载的 HarfBuzz managed/native 仍保留为 target input，不冒充已执行。runner 从 raw samples 独立重算 nearest-rank summary/p95 与 31 个 exact Gate，不信任报告内的 `passed` 字段。
- B0-05 已分路径通过 UI 请求门：4 次 cold queue、4 次 inactive-cache lookup、100 次 pending coalescing、3000 次 steady current-hit 的 p95 分别为 `0.7128 / 0.3309 / 0.0013 / 0.0001 ms`，各自门限分别为 `4 / 1 / 4 / 4 ms`；不得用 3000 次廉价命中稀释前三类路径。每个 viewport 先排除一次 size-specific JIT/native warmup，再按 viewport round-robin 执行 20 次 fresh SVG parse+raster+PArgb full-batch；`1024×576@100% / 1600×900@125% / 1920×1080@150% / 1280×960 host→1280×720 content@175%` 的逐 viewport p95 为 `61.5230 / 66.0620 / 67.5230 / 62.5188 ms ≤ 100 ms`。这是**进程已预热、资产工作新鲜**的口径，不冒充 process-start cold；max 只作诊断。active+inactive 峰值 `3,273,576 B ≤ 16 MiB`。
- B0-05 已通过：100 次 pending replacement/coalescing 只发布最新 key；3000 次**当前 key 管线请求**的 parse/raster/publish delta=`0/0/0`，最大并发 worker=1、fault=0、dispose=`5 batch / 40 layer`，dispose 后 cache/worker/desired/current 均归零。同一完整 run 的端点诊断为 GDI object delta=0、process handle `+12`、USER handle `+2`；这些端点与 CPU/alloc/GC/working-set 均不是 repeated-draw 趋势 Gate，不能把它们归因于 100 次 coalescing，也不能外推为窗口稳态或无 native leak。
- B0-05 几何 probe 的 bounds 来自 B0-01A placement 与 B0-04 typed manifest；它没有创建生产 widget、没有跑 overlay tick、没有调用 `UpdateLayeredWindow`。它只足以接受 `split_required`，不得冒充真实提交性能。
- B0-06 在“全部现役 NativeHud widget 可见 + 视觉矩阵最大 viewport/DPI”下跑 fixture hidden/enabled 的 3000 visual-step A/B。现有 `NativeHudOverlay` 不得因独立 PlayerInfo surface 改变 union；对有可比提交样本的相同工作负载，其 commit p95 回退不得超过 10%。若 hidden 侧提交数为 0，只比较计数/绝对值，禁止对 0 分母制造相对通过。
- B0-06 的 PlayerInfo split surface 单独记录 `repaintRequest / paint / commit / UpdateLayeredWindow` count 与 p50/p95/p99/max、tight surface 像素/字节；每个可见状态步最多 1 次 repaint、1 次 paint、1 次 commit，UI 同步工作 p95 `≤4 ms`，实际 split commit p95 必须 `<33 ms`。相对门与绝对门是独立拒绝条件，不得沉默放宽。
- B0-06 同时记录进程 CPU、managed allocation/GC、working-set、process/GDI/USER handle delta；前四项只诊断，handle 无净增长和长循环无单向线性增长仍是 Gate。idle 3000 tick 中 PlayerInfo split surface 的 repaint/commit 必须为 0；永久装饰 tick 不属于 B0。
- B0-06 专用 runner 已实现 exact SDK 10.0.300、locked restore、单一 opt-in STA HWND/ULW test、fresh runId、canonical LF/无 BOM、报告源/二进制/renderer closure 自身份和 runner 侧重算；测试合同固定 3000 visible visual steps、3000 idle ticks和独立 100 次真实 HWND/surface acceptance lifecycle。lifecycle acceptance 前先在同一 STA/owner 上运行 1–5 个完整 100-cycle excluded warmup group；只有 GDI/USER/process handle 的全部 checkpoint 均不高于该组起点、端点 delta 均不为正且三类都无正向单调趋势时才首次收敛。首次收敛后立即运行一个新的、相邻的 100-cycle acceptance group；若五组仍不收敛，后续只能标 `diagnostic_after_warmup_cap`、`acceptanceMeasurementEligible=false`，第 47 个 `surface_lifecycle_warmup_converged` Gate 必须失败。
- 两个被拒的 pre-merge run 已由 `runtime-qualification-attempts.json` 固化：v1 run `12f54a0…a3069cb6` 为 622,378 B / SHA-256 `01E68211…D867F`，USER `+2`、process `+35` 且 USER 呈正向趋势，仅 43/46；v2 run `4c3101b…43ae` 为 629,595 B / SHA-256 `C3FB74E7…2011`，固定一组 100-cycle warmup 后 acceptance 仍为 USER `+1`、process `+3` 且二者均呈正向趋势，也仅 43/46。没有为通过而放宽原始零增长或趋势门。
- pre-origin-sync v3 报告 `runtime-qualification-premerge-v3.json` 作为历史冻结输入保留：run `261978174b6346228b5f8ba4fd750019`、647,307 B、SHA-256 `21BD10F720280057F0A2F801B35619803AE29D8411F8D8E0AD2335A74BCA717D`，47/47、0 failure。它只证明旧 base/sourceTrace closure，不再冒充最终接受报告。
- 最终实现基线报告 [`runtime-qualification.json`](../tools/player-info-hud/evidence/b0-06/runtime-qualification.json) 为 canonical LF、无 BOM，绑定 base commit `bf8dd2c410267855c8ea12f25a594042b3158479`、32-file sourceTrace Git blob closure、exact SDK 10.0.300 与执行二进制；run `a6aadeb6e3264577bb9da8fe90857a7b`、647,234 B、SHA-256 `656286825CE9717D0DC31BDF9DFE00F3ECB57AB515C5C130601BDF23D319CD74`，47/47、0 failure。三个 warmup group 的 process/GDI/USER endpoint delta 依次为 `+37/0/+1`、`+1/0/+1`、`-8/0/0`，第三组首次满足完整 envelope；紧邻 acceptance group 为 `-3/0/0` 且三类趋势全 false。NativeHud hidden/enabled commit p95=`7.3485/7.2711 ms`、相对变化 `-1.0533%`；split surface/request/paint/observer-commit/ULW-only p95=`3.5610/0.0474/2.1808/1.0918/0.2001 ms`；3000 visible 的 request/paint/commit 均为 3000、ULW 失败为 0，3000 idle 均为 0。报告的 `oldFlashHudVisibilityObserved=false` 只表示自动 runner 没有观察旧 HUD，不能代签真实同屏可见性。

这些是 B0 的可审阅初值。修改阈值必须在台账记录测量机器、样本和原因，不能沉默放宽。

### 8.4 结构化结果

harness 输出 JSON + 人读摘要，至少含：

```text
assetSetRevision / exactManifestSha256 / rendererVersion / viewport / physicalScale
scenario / semanticAssertions / visualMetrics
coldBakeMs / cacheBytes / handleDelta / result
widgetPaintCount+Ms / unionRepaintCount+Ms / layeredCommitCount+Ms
processCpuMs / allocatedBytes / gcCounts / workingSetDelta
```

截图只能作为报告附件；没有结构化结果不能声称 Gate 通过。

### 8.5 B0-06 视觉取证状态

`PlayerInfoB006VisualCaptureTests` 已实现 opt-in、空输出目录、production compositor 直出的结构化捕获：11 case 的 1024×64 透明 full-stage 与 tight crop，四组 viewport/content/DPI 的 full/half/empty，以及 HP full→empty 41 次变化加初始态的 contact sheet。manifest 明确只到 `structural_capture_complete / fixture_only`，排除 Flash/Web parity、阈值、游戏 composite、人工接受、真实 UiData 和部署。

正式收尾在两个独立空目录各运行一次 C# capture，并与两份 Web capture 分别形成 direct C#↔Web、C#↔Flash 诊断；`csharp-web-flash` 三输入报告本身只输出这两条 direct edge 的 RGBA8/固定深色背景指标、overlay/diff/side-by-side 与输入闭包，不设阈值、不在该报告内计算 Web↔Flash 边、不作传递推断。独立的 `compare-flash-web-svg.js` 另提供 Flash-candidate↔Web supplemental diagnostic；它同样不设阈值、不给 parity/oracle 接受结论。Web report 以 `capturedLayerScope=canonical_static_svg_layers_only`、`csharpProgrammaticDynamicTextIncluded=false`、`csharpProgrammaticGlowIncluded=false` 精确声明范围；三个 comparison consumer 都 exact-validate 并传播这些字段，所以 C#↔Web 指标有意包含“完整 C# fixture composite 对 Web 静态层”的范围差。

pre-origin-sync `visual-evidence-premerge-v3.json` 继续作为历史输入保留。最终索引 [`visual-evidence.json`](../tools/player-info-hud/evidence/b0-06/visual-evidence.json) 为 7,783 B / SHA-256 `6ED4A8662A4426C0C1EFD7B236406332D526991C6D3730E98546814F4B0EE9D6`，绑定 base commit `bf8dd2c410267855c8ea12f25a594042b3158479`：C# A/B 各 36 文件、834,893 B，完整 directory closure 均为 `44C22A04…E06F`，manifest 均为 162,661 B / `ADE926A6…E08`，35-PNG 子闭包为 672,232 B / `3C3901A6…907E`；Web A/B 各 12 文件、120,439 B，完整 closure 均为 `2F18FAAB…6F6`，report 均为 5,644 B / `7826B89D…F97F`；direct A/B 各有 66 PNG，排除自引用 report 后为 1,470,180 B / closure `5207F27B…C234`，两份 report 因保留 `-a/-b` 输入路径而分别为 184,472 B / `519CF97B…83C1` 与 `081B05E2…B356`。

FFDec binary reference 另冻结 23 files / 22 PNG：PNG-only 为 245,587 B，30,433 B report 计入后完整目录为 276,020 B / closure `AEC84002…E59`，reference revision `sha256:a8369211…79c0`；FFDec↔Web A/B 的 33-PNG 子闭包均为 698,799 B / `BC2A83D1…9E08A`，Flash-candidate↔Web A/B 的 33-PNG 子闭包均为 661,944 B / `6141D387…C185`。各 A/B report 因输入路径不同而保留不同哈希，不能写成“34/34 全文件相同”。该状态仍为 `final_tree_diagnostic_awaiting_human_review`；FFDec、未签 Flash candidate、headless Web 和 C# offscreen capture 都只是诊断，人类还必须查看透明 crop、真实游戏 composite、关键比例/平滑、旧 HUD 同屏与手工鼠标透传。原始图片当前只存在 integration worktree 的 ignored `tmp/`，在人工终审完成并另行打包前禁止清理该 worktree；Git 中的索引与哈希不能代替可观看原件。

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
| B0-05 | typed manifest/planner、`PlayerInfoSvgRasterizer` + PArgb bridge + 16 MiB atomic-batch LRU + test-only fixed-bounds probe/结构化报告 | DPI/alpha/perf/cache/dispose 门通过，GDI/USER/process handle 仅作端点诊断；拓扑裁决为 `split_required` | 不接真实 UiData，不新增生产 PlayerInfo widget，不测实际 ULW |
| B0-06 | fixture-only `PlayerInfoWidget`、HP/MP clip/虚拟帧缓动、独立 click-through split surface、Web/C#/Flash layout harness | 全视觉矩阵 + 双 surface 3000 tick/实际 ULW；旧 HUD 未隐藏 | 不新增真实 `pi_*`，不注册进现有 NativeHud union |
| B0-07 | Kimi k3 异构对抗、问题处置、决策转正、B0 验收记录、B1 接口冻结、人工视觉/UI验收 | §9.4 + §11 exit checklist 全满足 | 不顺手扩韧性/经验，不由自动指标代签审美 |

依赖关系：B0-01A、B0-02、B0-03a 在 B0-00 后可并行；B0-01B 等 B0-01A，但可与 B0-02 并行。B0-04 明确依赖 B0-01A + B0-02 后方可开始；其 `canonical_asset_candidate_validated` 结构入口足以启动 B0-03b，也足以在 B0-03b 后启动 B0-05。B0-01B 的 accepted oracle/人工签收只阻断 B0-04 视觉 Exit、B0-06 parity 结论和最终 B0 接受，不阻断 B0-03b/05 的无关结构施工。B0-06 已闭合 MP fill 独立 mask fragment、HP 固定轮廓/旋转渐变、path glyph atlas、独立 surface、正式 qualification、双份视觉确定性与 evidence/docs-only containing commit；其最终退出仍依赖本独立最小配置切片冻结 source commit/tag 并完成双 builder/quorum，以及 B0-04 人工 oracle Exit、真实游戏 composite/手点、Kimi K1 和最终人类视觉/UI签收。

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
- 共享高冲突文件：csproj、`Directory.Packages.props`、`packages.lock.json`、`runtime-inputs.v2.json`、workflow、`Program.cs`、`PanelHostController.cs`、`launcher/README.md`。包图/identity 文件只在 B0-03b 集中修改；B0-06 只为独立 fixture surface 触及 Program/PanelHost 生命周期，不顺带改协议或现役 widget。开片和收尾都先确认另一机器没有同文件未落变更；B0-03a 只碰 resolver/setup-check 及其 focused test/docs，不夹带包图。
- B0-06 已先冻结 pre-merge 记录，再在独立 clean worktree 集中纳入当时的 `origin/main`，并从最终实现基线重建 qualification/视觉身份；pre-merge 哈希继续只作历史审计。后续每次收尾仍须先 `fetch`、确认 merge-base/ahead-behind 与工作树干净，再优先使用 no-op/fast-forward/普通 merge，禁止在未冻结候选输入的脏工作树上连续 rebase。
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

### 9.6 B0-07 最终实现包完整异构审计（K1 首轮）

最终实现包完整只读审计已于 2026-07-29 运行，满足“必须有一轮覆盖代码、资产、结构化测试与视觉报告的异构对抗”的执行要求，但首轮结论是 `REVISE_BEFORE_CLOSEOUT / K1_AUTOMATED_GATE=FAIL`，不能据此勾选最终 K1；修复后的 closeout 增量仍须由同一 `k3 + max` 配置复审到 PASS。

| 字段 | 证据 |
|---|---|
| CLI / session | Kimi Code CLI `0.29.1`，binary SHA-256 `D8F142445DAB79F4D98DD924FF53B684C252664AD7A3F4A7A91D58AE87F611BC`；`session_91083cff-5ea7-4121-a24a-0650f23f3026` |
| 模型 / thinking | `kimi-code/k3`、`thinkingEffort=max`、`thinkingKeep=all`；153 次 request 的 provider/model/alias/effort/keep 全部一致，未降 effort、换模型或提前终止；临时 max 配置结束后恢复原文件 |
| 只读与时间 | 2026-07-29 07:55:28.528 +08 至 08:37:20.192 +08，exit 0；278 次工具调用均为只读，审计前后仓库保持 clean |
| 输入 / prompt | 输入实现基线 `0fe999a20e435d4197ae8cbe6457b82a4f9f9ee0` 及完整代码/资产/证据包；prompt 8,450 B，SHA-256 `A1DAEF76556CB154D666D5E60DA0EA26B451C769B2B7F1800418D7D6213BFFB3` |
| 原始输出 | ignored archive `tmp/kimi-b0-final-audit-0fe999a20e/session.zip`，1,621,067 B / `3AC22FA6BE339E472AD5AB4DD829A35B74CA5B27984CD6E11F4585D5048444FD`；stdout 40,312 B / `4183CC70FA9E22ED24506E9107C38EFE79914D9FFCB6576CC44780EA1D8B651C`；stderr 910,028 B / `041D071AEDBC2B7B596E3774C87E9BC94E9C95487291478F47B5C7B936C8A4E2`；final response 23,594 UTF-8 B / `7574A39AEF82EC1415808DA2D3DBAE8A3DA02471EB49D7CD8D96ABDCA09C8016` |
| 首轮裁决 | P0=0；3 项 P1，结论 `REVISE_BEFORE_CLOSEOUT`；不得把“完整审计已运行”偷换成“K1 已通过” |

逐条处置：

| 发现 | 裁决 | 落点与复核 |
|---|---|---|
| HP 动态文字 Glow 误用黑色，与源 Flash 默认红色不符 | accept | 三个 HP layout 改为 source-red Glow，MP 明确无 Glow；`sigma=1` / alpha `220` 标为 Skia 近似并由 focused tests 固定 |
| `PlayerInfoPathGlyphAtlas.Generated.cs` 与 provenance 没有机器可执行同步门 | accept | 新增 BOM/UTF-8/canonical-LF/path/byte-length/SHA-256 fail-closed Gate，任一 Generated/provenance 漂移即失败 |
| Web capture 未声明不含 C# 程序化文字/Glow | accept | report 增加 3 个精确 scope 字段，Web capture 与全部三个 comparison consumer exact-validate/传播；direct metrics 显式登记范围差 |
| 后续独立复核发现 split-surface cancellation test 可因未观察到 cancel 而 false-green | accept | 改成可控阻塞 rasterizer，必须观察一次 cancellation、零 fault、`LastFault=null`；释放只在 `finally` |
| 后续独立复核发现另两个 comparison consumer 对 scope 字段 fail-open | accept | FFDec/Web、Flash/Web 与 direct comparator 全部改成缺失/漂移即拒绝；重新双跑并冻结 33-PNG closure |
| 测试命名与少量死代码增加维护噪音 | accept | parity test 改名为 consistency，移除未用参数、死 helper 与冗余 cache trim；不扩通用效果图/转换器 |

修复冻结于 `bf8dd2c410267855c8ea12f25a594042b3158479`；随后 focused 为 136 pass + 3 opt-in skip / 139，clean official full 为 1,737 pass + 3 opt-in skip / 1,740，formal qualification 47/47，Runtime Lane C 11/11。dirty/负载态曾暴露多个既有 wall-clock flaky，隔离复跑仍可复现；未发现指向 PlayerInfo 的定向证据，故不据此修改 PlayerInfo，根因与长期稳定性仍未裁决，不能据 clean full 反推“时序稳定性已修复”。最终增量复审必须覆盖本节 disposition、两份最终 JSON、evidence/docs-only containing commit、后续 source-freeze 配置差量与不可变 tag、双 builder/quorum 的结构化 `-VerifyOnly` 证据及同步后的 canonical docs；只有明确 PASS 后 §11.3 的 K1 才可勾选。

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
- `candidate_captured`：自动捕获闭环、实际 loader/player/SWF/状态与恢复证据已形成，但人工来源/层/crop/审美检查尚未签署。
- `canonical_asset_candidate_validated`：canonical SVG/manifest 的 exact closure、strict grammar、hash/revision 与确定性诊断已通过自动门；不代表视觉已接受。
- `awaiting_human_review`：某个 candidate 的明确人工检查仍为空；它可以与 `candidate_captured` 或 `canonical_asset_candidate_validated` 组合，不得简写成已通过。
- `oracle_frozen`：独立 Flash 参考截图、状态、运行时/SWF/crop 身份与人工来源复核均冻结。
- `isolated_qualification_passed`：隔离 restore/ABI/payload/synthetic corpus 与当前 strict corpus 已过，`rendererQualified=false`；只证明继续投入合理。
- `renderer_qualified`：B0-03b 已把同一 production strict facade 复用于当前 8 个 canonical asset，并闭合精确包图、embedded resource、runtime identity/payload、长期 policy 与许可分发门；不代表视觉或 widget parity。
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
| HP 边框 placement 使用 `exportAsBitmap=true` + Bevel，Flash oracle 含派生 raster/filter 语义 | 不把它误判为源 bitmap；B0-04 candidate 已在 `hp.rim` 的 `hp-rim-static-bevel-expanded` 组展开为矢量渐变，但不声称 Adobe filter 像素精确，透明边/审美仍待人工 |
| HP 时间线只旋转红色 fill 的 gradient transform，若 harness/生产误转整个轮廓会形成小幅像素漂移 | manifest 精确点名 `hp-fill-gradient-0003`，按 `R×M` 只旋转渐变坐标；Web harness 显式拒绝方向/pivot 漂移 |
| MP 两处径向渐变矩阵 determinant=0，通用 SVG renderer 无唯一等价解释 | provenance 分别命名源 layer/frame/shape/fill，candidate 固定为 first-stop solid；不把 fallback 写成 oracle 事实，人工不接受就退片 |
| MP `装饰信息` 在 source frame 69/90 改变几何/颜色，单一 rim 会丢关键状态 | 保留 `mp.rim`、`mp.rim-vf70`、`mp.rim-vf91` 三个 authored key variant；manifest 以 virtual frame 1/70/91 切换，不保存逐帧序列 |
| `mp.fill` 当前单个 SVG 同时含左右槽/装饰/背景四个 group，而左右 mask 绑定不同几何 | B0-06 在 bake 侧按稳定 group ID 生成独立 immutable fragment，或先正式拆 canonical asset/递增 revision；禁止对扁平整图套 union mask 后声称 parity |
| HP fill 的 source 时间线只旋转渐变坐标，当前静态位图同时包含固定轮廓与渐变 | B0-06 使用固定 coverage/contour + 程序化旋转渐变或等价 texture paint；禁止旋转整张 bitmap，未闭合前不声明 HP 动态 parity |
| path glyph atlas 的 source SWF、FFDec 导出字节或 generator 身份漂移，机器字体又会引入版本与许可差异 | 已从 source-bound child SWF 经 FFDec 21.1.1 导出 LCD Std/Aero，生成 `0-9 / %MP-` 的最小 path/advance/baseline atlas；provenance 的 canonical LF output 为 10,331 B、SHA-256 `B15CA80E…5D66`，provenance 文件 SHA-256 `9486BEEB…DC3D`。runtime 不分发 TTF、不使用系统/GDI font；focused Gate 要求 UTF-8 无 BOM、CRLF→LF clean、lone CR 拒绝，并按 path/canonical bytes/SHA 校验，任何源 SWF、导出、generator 或产物改变都必须重生成并重跑 |
| PArgb 转换产生黑边/色晕 | 透明边、半透明 gradient、BGRA premultiply 专项测试 |
| converter 变成无底洞 | 只做 HP/MP active subset；允许有 provenance 的手工 canonical SVG |
| DPI/resize 导致缓存抖动或陈旧图 | pixel-size key、取消旧 bake、原子换入、byte-budget LRU |
| Skia/Bitmap 释放竞态或 native leak | 明确所有权；100 次 churn + 3000 tick + handle delta Gate |
| 自生成 golden 自证正确 | Flash 独立捕获 + 人工 overlay review；转换输出不可作唯一 oracle |
| 旧 SWF/截图与当前 XFL 无可证明绑定 | 按 §6.4 标 candidate；必要时精确 publish/verify 独立 UI XFL，再以 SWF/播放器/crop hash 冻结 |
| 现役系统没有安全的精确 HP/MP 只读注入，误用 `/console`/真实槽会污染 oracle 或游戏状态 | B0-01A/01B 拆分；只用 TestLoader scratch 固定 case，禁止生产 AgentControl、任意 console 与 live save；捕获失败不冒称 `oracle_frozen` |
| CS6 已 fresh publish、Debug Player owned PID 正常响应但 trace 保持 0 B | 已定位为旧 `ArgumentList` 留下尾部字面 `"`，实际未加载 SWF；r9 固定 `scripts/` cwd + 无引号 `TestLoader.swf` token 并反向解析到精确目标。正式重采仍按 exact PID fail-closed 并恢复 TestLoader AS/SWF，不延长超时掩盖、也不回退 release player |
| 高完整性 Flash authoring 存活但 `Get-Process.Path` 为空 | r10 用 `OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION)` + `QueryFullProcessImageNameW` 读取精确路径，并继续与唯一 `\FlashCS6Task` action 和磁盘 identity 交叉绑定；不因 MainModule 不可读而把进程身份降级为名称 |
| 模板请求 `Stage.align="TL"`，Player 11.2 回读 `"LT"` | r11 分别冻结 requested/reported token，parser 只接受实测 `"LT"`；仍要求 `noScale`、500×500 runtime stage 与 1024×64 identity draw，不把任意 align 值当等价 |
| 整座 HUD 的 `玩家必要信息界面` 含 BitmapFill，且初看 `LIBRARY/image/` 不存在易误判 payload 缺失 | HP/MP closure 明确排除且当前为 0 bitmap；两个小位图 payload 实际位于 `bin/M 2 1716646761.dat` 与 `bin/M 1 1716646761.dat`。B2 扩域时重新审计引用闭包和精确 CS6 publish fidelity，不用 `<image>` 偷渡，也不能按“缺图”或“已安全”任一方向先验裁决 |
| fixture-first 误接成第二状态权威 | surface 唯一持有/推进 fixture model，widget 仅 getter-only 消费；B0 禁止真实 `pi_*` 与 AS2 写路径 |
| 上游 CharacterBuild 的 `PlayerInfoSnapshotBuilder` / `loadout_response` 被误当成 HUD 状态源 | 该链路是 9 组 / 47 行低频 stats 投影，缺 current HP/MP、cur/target、epoch/sequence；B0-06 只接显式 fixture → `PlayerInfoVisualState`，禁止 groups 通用适配或复用 `CharacterBuildTask`。其 `stats_unavailable` allowlist 与嵌套 schema 两项 medium 独立跟踪，不借 B0 修补 |
| asset 未进 build identity | runtime-input regression：改任一 SVG 必改 identity 与 Core closure |
| `resolve-dotnet.ps1`/`setup-check.ps1` 与 `rollForward:disable` 口径不一致 | 独立 B0-03a 统一为精确 SDK 命中并做 only-10.0.301 等负例；两 builder 记录实际 `dotnet --version` |
| 与装备栏机器冲突 | B0-03b 集中共享文件；其余只写新目录；旧 XFL 只读 |
| 程序化动画顺手改变手感 | 先复刻虚拟帧语义；优化一项一 ADR/证据 |
| 左下 PlayerInfo 与顶部/侧边 widget 被单一外接 union 合成，HP/MP 过渡时近全屏提交 | B0-05 已测得 tight envelope 仍占 viewport 93.90%、放大 26.33×，接受 `split_required`；B0-06 用独立 click-through surface 并实测双 surface，不得回并现有 union |
| 永久动效使所有 NativeHud widget 常态 union 重绘 | B0 默认静态；B3 先测全 union，超预算则局部子合成或保持静态 |
| 资产损坏导致战斗信息全空 | 双轨期加载失败即隐藏 Native widget、保留 Flash；B4 退壳前补不依赖 SVG 的最小 GDI 数字/条形 fail-safe |
| Computer Use 已恢复但遮挡态抓错前台窗口，或误把 authoring 文档截图当成已运行 SWF | 操作前先显式激活目标窗口并核对返回 title；本轮只确认 Flash CS6 打开 `TestLoader.xfl`，没有独立 Test Movie/SWF 窗口。无头 Edge 只做 Web/SVG 诊断，实际 HWND/ULW 由专用 STA qualification 测；运行时加载身份仍以 loader/player/SWF trace 为准，真实 composite、手点、层级遮挡与审美必须由人类验收 |

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
- [x] `Svg.Skia` 决策由 provisional 转为 accepted，或已有修订 ADR 明确替代候选。
- [x] 依赖/许可证/native/security/payload-size 审计有结构化证据。
- [x] B0-03a exact SDK selector/setup-check 的 only-10.0.301 等负例与 repo-root exact-positive 通过。
- [ ] 两类正式 builder 可 locked restore，并对同一本 source-freeze commit/tag 形成一致 build identity / payload closure；本提交已把 `runtime-github-builder.v2.json` 的 `sourceRef` 精确更新为 `refs/tags/runtime-build-v2/20260729-player-info-nativehud-b0-v1`，但尚待 clean-tree 域复算、远端不可变 tag 指向、policy/request/admission、两类 builder 与 quorum 实证。最终以同一 production promotion 验证链的 `-VerifyOnly` 报告留证，不执行 promotion/deployment，也不把报告回灌为发布输入。
- [x] canonical SVG/manifest exact closure 已冻结；8 个 SVG 共 99,564 B，asset-set revision `sha256:c8f58cb7…93871`、exact manifest SHA-256 `1006f90e…5630`；strict corpus 12/12、78/78 fail-closed（其中 58 项值级 grammar），Web 两次输出闭包 A↔B 12/12 字节相同。
- [x] SVG/JSON 与包图进入 artifact source；改资产会改变 build identity 与 Core payload closure。
- [x] production policy 有快速 SVG grammar/hash/closure 回流保护，不能只靠一次性 xUnit。
- [x] B0-05 raster pipeline 只在新 7-field batch key bake；3000 次 current-key 请求的 parse/raster/publish delta=`0/0/0`。这不等于真实 widget tick 已测。
- [x] 物理 scale 已冻结为 Flash content viewport height / 576，monitor DPI 只作 physical-coordinate telemetry；PArgb、透明边、四 viewport/letterbox、16 MiB cache、100 churn、dispose 与 synthetic bake 门通过。
- [x] fixed-bounds topology 报告已接受 `split_required`；B0-06 不得把 PlayerInfo 注册进现有 `NativeHudOverlay` union。
- [x] B0-06 正式 qualification 已在最终实现基线以 3000 visible + 3000 idle + 独立 100 lifecycle acceptance 覆盖完整 NativeHud union 与独立 split surface；计数/UI p95/union 面积、真实 ULW、handle/长循环 Gate 满足 §8.3，CPU/alloc/GC/working-set 已记录。`runtime-qualification.json` 为 47/47、0 failure，并绑定 exact source/binary/renderer closure。
- [x] fixture HP/MP 的 11-case 静态矩阵已由最终实现基线的两份独立 C# capture、两份 Web capture 和两份 direct-edge comparison 绑定；41-tick HP full→empty 仅由 C# A/B 的 contact sheet 固定，Web/direct 不冒称覆盖该时序。deferred effect 有显式清单，代码未隐藏旧 HUD。`visual-evidence.json` 证明 C# 36-file、Web 12-file 与 direct 66-PNG A/B 各自确定；Web 精确声明 static-only、不含 C# 文字/Glow，FFDec/Flash supplemental 只冻结各自 33-PNG 双跑闭包。该勾选只关闭 offscreen/declared-DPI 自动确定性；实际 compositor clock、mixed-DPI 桌面、旧 HUD 同屏、游戏 composite、跨 renderer parity 与人工审美仍未验证。
- [ ] `PlayerInfoWidget.TryHitTest` 恒 false 的 focused test 与 surface `HTTRANSPARENT` 自动合同已通过；真实桌面窗口鼠标透传仍须人类手点，前两项不得代签最后一项。人类手点证据状态：`pending_human_desktop_clickthrough`。
- [x] `launcher/README.md`、testing guide、runtime build canonical doc、总体迁移 ADR 与本台账已同步最终实现基线结果；evidence/docs-only commit `81168ece…c549` 的 doc governance 与 `git diff --check` 均通过。
- [x] evidence/docs-only 后继 commit `81168ece8cd295d8e15b8f6baed46a0da7f9c549`（tree `496faa9a…d9f`）已形成，两份最终 JSON 均被 Git 跟踪；提交精确修改 7 份文档与 2 份 JSON、无代码/配置/资产变更，提交后 clean-tree、doc governance 与 `git diff --check` 已复核。
- [x] B1 的 visual-state 接口和四字段草案已按 §7.5 审阅，结论为 `reviewed_draft_not_integrated`；epoch/sequence、重连与 invalid 边界明确留给 B1，当前 runtime 仍无 `pi_*`/UiData adapter。
- [ ] §9.5 文档级 K0 的问题已有逐条 disposition；§9.6 的完整实现包 K1 首轮已以 `kimi-code/k3`、`max` 可复核运行并完成问题修复，但 closeout 增量尚未复审到 PASS，不能提前勾选。
- [ ] 人类已明确接受最终透明 crop、游戏 composite、关键比例、平滑与 UI 交互；自动指标或 Kimi 不代签。

---

## 12. 施工台账与恢复协议

### 12.1 当前台账

| Slice | 状态（内部施工标签；对外结论仍只用 §10 词典） | 已有产物/证据 | 未验证 | 下一步 |
|---|---|---|---|---|
| B0-00 | completed | 本 B0-00 commit：两份 ADR 同步；§9.5 k3/max 文档审计；doc governance、链接与 diff check | 无代码/视觉/生产依赖结论 | B0-01A / B0-02 / B0-03a 可并行 |
| B0-01A | completed (`placement_closure_frozen`) | r3：16-file exact closure、HP/MP/shared=10/5/2、17 authored/18 expanded edge、14 timeline、0 BitmapFill/DOMBitmapInstance；Git-canonical digest `6f4bf9…4368`；index/clean-filter/anchor/source-binary verifier 全绿并经独立复审 ACCEPT | actual TestLoader/player load、截图/crop 与人工来源确认归 B0-01B；不声称 `oracle_frozen` | B0-01B 可开始；B0-04 可开始但视觉 Gate 等 01B |
| B0-01B | `candidate_captured; awaiting_human_review` | 第七轮：strict r11；CS6 **15 秒** fresh TestLoader **389,160 B**；Debug Player `11,2,202,228` 自然退出；child SHA `450b1f…a615`；**11 raw + 11 crop**、4,458,323 B run block；manifest SHA `dcc9e11a…bf472`；AS/SWF 精确恢复、无 marker | 人工来源、状态、层隔离、crop 与审美确认；未到 `oracle_frozen` | 保留 candidate 与对比包供人审；有修改则重采/重跑 |
| B0-02 | completed (`isolated_qualification_passed`) | 原依赖审计 exact SDK + locked restore、10/10/16；当前 strict 增量为 **12/12**、fail-closed **78**（值级 **58**），并验证 canonical **8/8**；11 包 license/nupkg + 9 文件/5,289,528 B payload | 历史报告固定 `rendererQualified=false`；生产资格不得回写该证据 | B0-03b 已以 compile link 复用同一 validator/facade，禁止旁路 |
| B0-03a | completed | resolver/setup-check 共用 exact 合同；selector + repo-root 集成 **7/7**；setup-check **5/5**；三项首轮并发时序失败隔离复跑 **3/3**，随后全量 xUnit **1257/1257** | 正式 builder 的 10.0.300 证据仍归 B0-03b/发布链 | 继续 B0-01B/B0-04；待真实资产后进 B0-03b |
| B0-04 | `canonical_asset_candidate_validated; awaiting_human_review` | **8 SVG / 99,564 B**，manifest SHA `1006f90e…5630`，revision `c8f58cb7…93871`；12/12 + 78 fail-closed（值级 58）；Web 两次输出闭包 A↔B **12/12**，FFDec/Web 与 Flash/Web 比较器各自的 **33-PNG** 子闭包 A↔B 一致，report 因输入路径不同保留不同哈希；provenance/工具边界已落盘 | 跨 renderer 像素并不相同且无接受阈值；Flash candidate 人工复核、Bevel/singular-gradient/MP variants/HP gradient rotation 的视觉接受；不声称 parity | 允许 B0-03b/05 的结构施工；视觉结论等人签 |
| B0-03b | completed (`renderer_qualified`) | candidate `c-c571959c1f2a-08846e81b3-20260728t130535410z-0b23fc7a`；identity `C571959C1F2AC98341C798E4AD2B6529F0C9972320AE534A0794ADD89812AFEC`；payload `C60757A6636898DB0CEE803D50128C40C2BD9A2DAE14DC7F899646BB30954FB8`；Core `3262F0CB4655CA3BCFD5F2AABB65BFA8C4A5A3BEB69A34E86DF934FCC0C49ED9`；contract 9 resources / 8 assets / 11 actual files / 11 deps / 1 target / notice `1E69FF5A…9287`，防御矩阵 8/8；production policy 22/22；identity 107、queue 17、release-policy 61、release-state 48/0、xUnit 1261/1261（新增 warning 0）、focused 4/4、packer 177 pass + 1 skip、qualification build 0 warning/0 error；1-byte sensitivity 与精确恢复通过 | 两正式 builder / 跨 faultDomain 一致性、promotion、标准入口、B0-04 人工视觉；candidate 为 `NOT_DEPLOYED`；上游正式 Core `DADE2CC2…CCA1` 不包含该 source-ahead candidate | renderer 锁定继续供 B0-05/06 使用；不得把后续源码外推为该 candidate |
| B0-05 | completed (`raster_pipeline_qualified; split_required`) | typed 8-asset manifest/planner；strict viewBox 四边校验；8-layer atomic `PlayerInfoSvgRasterizer`/PArgb；single-worker latest-wins + active/inactive 16 MiB whole-batch LRU；canonical-LF 报告 `cf7.player-info-hud.b0-05-runtime-qualification` run `68c5252325594787aa5e6daf0cb856e8`、705,417 B、SHA-256 `217F28CD…4C624`，以 pre-commit HEAD `1bb3307…b3443f5c8e` + index/worktree blobs 绑定 37-file closure `6B6B72A1…70C38`、执行 test DLL `8249BDDC…60836`、Core、exact 11-file win-x64 target / exact 15-file test-output renderer-family closure与 10 项 actual-loaded 子集；HarfBuzz managed/native 仅绑定 target、未冒充 loaded。raw samples、nearest-rank summaries 与 31/31 exact Gate 均由 runner 独立复算，0 failure、`passed / synthetic_fixed_bounds`；四类 UI p95 `0.7128/0.3309/0.0013/0.0001 ms`，四 viewport 各 20 次 per-viewport-warmup/round-robin fresh-asset full-batch p95 `61.5230/66.0620/67.5230/62.5188 ms`，peak `3,273,576 B`，3000 current-hit delta `0/0/0`，GDI endpoint delta 0（diagnostic），dispose `5 batch / 40 layer`，worker/fault `1/0`；tight topology `982×564 / 93.90% / 26.33×`。LF 修正后的首个旧采样 run `ae96d30…` 曾以 1600×900 p95 `103.2472 ms` 正确失败；审计确认旧合同只预热 1024 且把四 viewport 分段连续采样，随后在**不抬阈值、不改生产热路径**前提下改为逐 viewport 预热 + round-robin，最终报告才获接受。最终 focused 68 pass + 1 opt-in skip / 69；专用报告 1/1；无测试并发全量 1325 pass + 1 opt-in skip / 1326；全量重建后的 test DLL 仍为 929,280 B / `8249BDDC…60836`，与报告相同；production/runner build 0 error（既有 WindowsBase warning），qualification build 0 warning/0 error | 无生产 widget、实际 `UpdateLayeredWindow`、完整 NativeHud 3000 A/B、视觉/人审、UiData/部署；GDI/USER/process handle/内存仅端点诊断 | B0-06 实现独立 split surface；不回并现有 NativeHud union |
| B0-06 | `qualification_final_tree_passed; automated_visual_frozen; human_exit_pending` | 已实现单表驱动的 11-case `PlayerInfoFixtureInput`、surface 独占的 visual state/41-tick HP 式动画、getter-only widget seam、MP 双 fragment、HP 固定轮廓/旋转渐变、Aero/LCD Std path glyph atlas、source-red HP Glow/MP no-Glow、typed effect policy、窄 composition recipe、恒 false hit-test widget、带可靠 resume pending 的独立 click-through `PlayerInfoSplitSurface`、PanelHost companion 与 Program allowlist opt-in；代码未发起旧 Flash HUD 修改/隐藏。clean `bf8dd2c…8479` 的 `runtime-qualification.json` 为 47/47，run `a6aadeb6…57a7b`、647,234 B、SHA `65628682…9CD74`；focused 为 136 pass + 3 opt-in skip / 139，clean official full 为 1,737 pass + 3 opt-in skip / 1,740。`visual-evidence.json` 已由 `81168ece…c549` 冻结 C# 36-file、Web 12-file、direct 66-PNG 及 supplemental 33-PNG 双跑闭包，并机器声明 Web static-only scope；staged snapshot `a7d36f4d…97d8` 的 Runtime Lane C 11/11 exit 0、scalar 567，guardrails `scripts=3 / unsafeCandidateCases=3`，总耗时 863.010 秒 | 远端不可变 tag、两 builder/quorum、旧 Flash 同屏可见性、B0-04 oracle 人签、真实游戏 composite、真实手点、审美与最终 Kimi K1 PASS 尚未完成；promotion/标准入口/部署不属于 B0 Exit，预期仍为 `NOT_DEPLOYED`；不声称 `fixture_static_parity` 或 `fixture_full_parity` | 提交本 source-freeze 最小切片并冻结 tag；完成双 builder/quorum `-VerifyOnly`、报告回写与 Kimi 最终增量复审，最后交人工 |
| B0-07 | `k1_revision_applied; final_delta_reaudit_pending; human_review_pending` | §9.5 已完成文档建设 k3/max 审计；§9.6 已完成最终实现包完整审计，3 项 Kimi P1 与 2 项独立复核问题已修复于 `bf8dd2c…8479`；Computer Use 已恢复并确认 Flash 当前打开 `TestLoader.xfl`；evidence/docs-only commit 为 `81168ece…c549` | K1 最终增量 PASS、全 Exit Gate、运行时 SWF 身份复核、游戏 composite/真实手点/审美与人类接受；自动桌面控制仍不能代签 | 冻结本 source commit/tag、取得双 builder/quorum 并回写结构化报告；再让 k3/max 覆盖最终差量，最后人工终审 |

**上游整合复核（2026-07-29）**：B0-05 commit `27364dbc9ff579200ae0dbc9d2d5c6c10151c479` 所在的 PlayerInfo integration line 在独立 worktree 以 merge commit `b199a0c4310da830278f42fea5756f459ff53653` 纳入 `origin/main@ef31b39069272304f5831b9028b786ce333aa62e`；`b199a0c…` 的双亲依次为 `27364d…` 与 `ef31b3…`，并不是把 `27364d…` 合入当时的远端 main。三处文档冲突按“上游正式 runtime 真值优先、PlayerInfo source-ahead/`NOT_DEPLOYED` 边界保留”解决；自动合并的 release policy 同时保留上游 workbench closure 与 PlayerInfo candidate contract。合并树通过 doc governance、release policy `61/61`、release-state `48/0`、runtime consensus `15` assertions、PlayerInfo production contract 与防御矩阵 `8/8`、全量 xUnit `1651 pass + 1 opt-in skip / 1652`，PlayerInfo focused 为 `69 pass + 1 opt-in skip / 70`。这些是合并兼容性证据，不重写 B0-05 报告所绑定的 pre-merge 37-file closure/test DLL，也不把当时正式 Core `DADE2CC2…CCA1` 外推为已包含 PlayerInfo。

**B0-06 收尾整合复核（2026-07-29）**：实现与 Kimi P1 修复冻结于 commit `bf8dd2c410267855c8ea12f25a594042b3158479`；其 clean tree 上完整 Launcher 回归为 1,737 pass + 3 opt-in skip / 1,740，focused 为 136 pass + 3 opt-in skip / 139，formal qualification 与全部视觉 A/B 取得上述最终自动证据。随后远端推进到 `origin/main=c96f4c3d750561022b706c72a4d53050431e627d`；独立 clean worktree 以 merge commit `8c703c6811ef264da36eb482db524a16a4e64958` 将其纳入 PlayerInfo integration line，双亲为 `bf8dd2c…8479` 与 `c96f4c…627d`。该远端增量只修改 `agentsDoc/workbench-ui-system.md` 并新增双栏工作台 ADR，与本轮 9 个 evidence/docs 路径无交集；merge 后 `origin/main` 是 HEAD 祖先，ahead/behind=`21/0`，doc governance 与 `git diff --check` 通过，故不重写仍绑定 `bf8dd2c…8479` 的机器/视觉报告。此前 dirty/并发负载态曾在 Loot/Skill/GameLaunch/CharacterBuild 等非 PlayerInfo wall-clock tests 暴露时序失败，其中一项 Skill 隔离 20 次为 13 pass/7 fail；因此这里只记录 clean official 通过，不声称既有时序敏感性已消失，也未据此修改 PlayerInfo 生产代码。收尾完成前还须再次 fetch/祖先关系/干净树复核；若远端变化则先冻结并集中整合后重跑受影响门。

**B0-06 evidence/docs 冻结复核（2026-07-29）**：commit `81168ece8cd295d8e15b8f6baed46a0da7f9c549`（tree `496faa9afc7de21c082c7440375b4c6b31139d9f`）以 `8c703c…4958` 为唯一父提交，只修改 7 份文档与 2 份最终 JSON；`git diff-tree` 无代码、配置或资产路径。提交前后 `git diff --check` 与 `node tools/validate-doc-governance.js` 均 exit 0，提交后工作树干净；紧邻本 source-freeze 切片的 fetch/祖先复核仍为 `origin/main=c96f4c…627d`、ahead/behind=`22/0`。因此两份报告继续绑定 `bf8dd2c…8479` 的实现/执行闭包，而 `81168e…c549` 只负责持久化证据与治理状态。

**最终 source-freeze 前上游整合复核（2026-07-29）**：fetch 后新增远端 commit `232d25ddf96ba39147f3335162d8a2d033c7822f`，主题为贫民窟兽化登场动画；其 700-file 直接差量只落在 `data/stages/基地门口/贫民窟.xml`、`flashswf/arts/things1.swf` 与 `flashswf/arts/things1/**`，与 PlayerInfo、当时两份 source-freeze docs、runtime 配置/工具及四域输入的交集均为 0。merge `2882456c8777246fba8d2f6942ef1027caafc650`（tree `1bf4e2f657aaefe71c2267ac3fcd48ce8ba4554b`）以 `81168e…c549` 与 `232d25…822f` 为双亲无冲突形成；F 的唯一命名 stash `e46ba9ee2a620f8bdc83c7b63a138e0ece0052c9` 随后以 `--index` 原样恢复且仍保留备份。合并后 `origin/main` 是 HEAD 祖先，ahead/behind=`23/0`；prepare 前恢复的 staged snapshot tree 为 `19c931f6406ff6fd2fba66ea1485c0583be8424e`，四域与 merge 前复算逐项相同。该 snapshot 不是最终 F：随后的首次候选 prepare 正确检出上游 stage 数据对应的 arena parameter registry 尚未重生成，故必须先纳入 prepare 所治理的该差量后再冻结；这只闭合 prepare 当前枚举的生成物，不代表 `data/stages/**` 所有 Web 派生链均已闭合。

**B0 source-freeze staged-tree 预检（2026-07-29）**：merge 前/后、prepare 前的 staged input tree 分别为 `5b242c72bcb9a9b521f0f5fa2d24aa9519167e87` 与 `19c931f6406ff6fd2fba66ea1485c0583be8424e`；同步起初两份 source-freeze 文档后的 tree 为 `29745d38674e55c6ac6710008876484f16896532`。对该首次候选输入执行 release prepare 时，11 个 tracked outputs 中唯有 `launcher/web/modules/arena-unit-param-presets.js` 与 tree 不同，门以 exit 1 拒绝陈旧输出；该文件的精确语义差量是 metadata `840→848`、`271→272` 与新增 `param-b6f7e75f4f3b`，无删除或既有 preset 改写。把这一机械派生输出纳入后的 staged tree 为 `81493965fada78b904fc1c857146dd53e1cbdd62`；同步同事实到专项 ADR/runtime deep doc 后的 `f326e6c255fbc12bd386353707ac443f7bbd81d6` 已通过 11-output prepare 且零未暂存残留。随后因识别 meta-team 盲点又只更新 Launcher README、测试指南及两份 source-freeze docs，不再改变配置、派生 registry 或任一身份域；完成这四份 canonical docs 后的 staged snapshot `a7d36f4d0808ffb59e5227aca05265abcc6897d8` 已通过 doc governance、`git diff --cached --check`、11-output release prepare、锁定环境门与 Runtime Lane C 11/11（scalar 567；guardrails `scripts=3 / unsafeCandidateCases=3`；总耗时 863.010 秒），真实远端 admission audit 也再次得到 `Active`、`mainDirectPush=true`、tag creators=`Crazyfs,Flash-Night`。相对 E，artifact source `A7190F548851A505F9C6ACCE9F132E1741BAB4B47597473801C79DE32589DBC8`、producer recipe `B97998EA7246D6AB667902BCBBD7994DFA5F658A37CFA427D2EEEABA6924DE28`、toolchain lock `7B83229BE93F8244810CDD23DAFD97875B23857E547DE520035FE23B453CB3CD` 与 build identity `7687B56106F0C19EFD4463DCA2B69B3892BD3EE39503A3FD5521ED6DB0257A9F` 逐项不变；policy 从 `405CE99C7362514BD3C964403560F7B253F7C7F95AF0E6BD7AB06BD88729BDE2` 旋转为 `0E52F22FD3A42C5770B5B0C7C58E48662097C01CACA8306595991AD61E4DF105`。中间值 `3CA1C204…A90EDBF` 只对应尚未纳入 prepare-governed 差量的 snapshot，不得作为 F 最终政策身份。本段随后仅以证据措辞补记 `a7d36f4d…97d8` 的结果，不把该 snapshot 冒充尚未产生的 F commit；F commit/full SHA、clean-tree 复核、远端最终祖先关系与 tag 精确指向，以及 request、两类 candidate/proof 与 quorum，均留给后继外部事实补证。

**Arena 传递派生债务（不并入 PlayerInfo F，2026-07-29）**：只读内存复算确认 `tools/derive-arena-meta-teams.js` 同样读取 `data/stages/**`，但当前不在 release prepare 中，且其 `--check` 只解析并打印摘要、不比较 tracked 字节。因此 `data/arena/meta_teams.json` 当前 tracked 为 3,470,547 B / `635FB515…98F72`、按现源应为 3,367,986 B / `26099187…47D3`；`launcher/web/modules/arena-meta-rosters.js` 为 1,291,607 B / `2F677C5F…9453` 对 1,292,790 B / `32F1D6B9…FD65`。用新 meta 继续派生时，policy fixed file `arena-custom-presets.js` 也会从 1,186,819 B / `26A77128…51A5` 变为 1,189,068 B / `21F4020F…68B6`。这是一条包含 2026-07-05 以来既存广泛漂移的约 5.8 MiB Arena 治理债务，不能伪装成 232d 的单一 PlayerInfo 邻接修复；本 F 只纳入 prepare 当前枚举 11 项中的真实差量，并明确不声称“全仓 Web 派生闭包已同步”。后续 Arena 专项必须把 meta generator 的 sync check 改为 fail-closed、纳入 prepare/policy，完整重生成三文件并跑 custom-match p1/p2/pve 与标准 Arena harness。B0 的两 builder/`-VerifyOnly` 只验证本 source-freeze 的 native identity、payload 与当前 policy 字节，不能代证这条 Web 语义新鲜度；由于 B0 不 promotion/部署且 PlayerInfo native payload 不消费该链，本债务不改写 PlayerInfo B0 Exit 定义，但必须进入最终 Kimi delta 审计，禁止静默遗忘。

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

> Oracle 轨保留 B0-01B 第七轮 candidate，等待人类签署来源、状态、层隔离、crop 与审美 review receipt；不得用 FFDec/Web/Flash-Web 指标代签。工程轨的 clean `bf8dd2c…8479` 已通过 47/47 formal qualification，`81168ece…c549` 已冻结 `runtime-qualification.json` / `visual-evidence.json` 及 C#/Web/direct/supplemental A/B；fixture state/widget、MP fragment、HP 固定轮廓/旋转渐变、path glyph atlas 与独立 click-through surface 不注册进现有 NativeHud union，代码也不隐藏/修改旧 Flash HUD。最终上游已由 `2882456c…c650` 纳入到 `origin/main@232d25dd…822f`，远端现为祖先、ahead/behind=`23/0`；该 700-file 贫民窟/things1 直接差量与 PlayerInfo/runtime 四域交集为 0。首次候选 prepare 已正确捕获其 stage 数据派生 registry 陈旧并 fail-closed；当前切片除把 `runtime-github-builder.v2.json` 更新到 `runtime-build-v2/20260729-player-info-nativehud-b0-v1` 外，也纳入 prepare 枚举的 11 项输出中唯一不一致的 `arena-unit-param-presets.js`，policy 复算为 `0E52F22F…DF105`，build identity 仍为 `7687B561…7A9F`。另有不由 prepare 管理的 Arena meta-team 传递派生既存债务已显式登记，不把它冒称为本 F 已闭合，也不把约 5.8 MiB 广泛刷新偷渡进 PlayerInfo。staged snapshot `a7d36f4d…97d8` 已完成 prepare/governance/环境门、Runtime Lane 11/11 与真实 admission audit；本段随后只补记证据措辞。下一步复核该 docs-only 尾差量后提交 F，在 clean detached worktree 重跑 commit/tree/四域、prepare/governance/Runtime Lane 与远端最终祖先门，再 push F 并创建只指向 F 的不可变 tag。两个正式 builder 对该同一 F 源形成 quorum `-VerifyOnly` 报告后，以单独 G 提交回写报告，再让 Kimi `k3 + max` 覆盖最终差量、处置和结构化证据到明确 PASS；最后利用已恢复的 Computer Use 辅助检查 TestLoader/运行器，但旧 HUD 同屏、游戏 composite、手点与审美仍由人类签收。B0 不要求 promotion、标准入口或部署；双 builder、一致 K1 与人签未完成前 Exit 仍不勾，任何自动结果也不得冒称 parity 或代替人签。每完成一片都在同提交回写 §12。

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
