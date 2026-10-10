# 共享 HUD 重绘、像素搬运与合成成本

**文档角色**：2026-10-10 成本分解、两项优化的选择依据与候选验证记录。持续绘制合同归源码接口，开发诊断入口归 [flash-compositor README](../launcher/perf/flash-compositor/README.md)。

**最后核对代码基线**：commit `39b0d15488`；本次增量基于 `b5d7592b66db7e17314f6c4edc88c590c93a0f0c` 开始，期间接入的结算友军、书架和其他 Web 提交不涉及被测 HUD 绘制器或 Native 合成器。

## 结论与交付边界

选定并实现两项：共享主 HUD 的脏区域重绘，以及 Native HUD 像素缓冲复用。最终 ABBA 对照中，主 HUD 绘制均值下降约 35%–36%，提交均值下降约 62%–64%；混合负载的夹具进程 CPU 中位数下降约 12%。这证明本机受控呈现负载的 CPU 收益，不是实际战斗 FPS、弱机或功耗收益。

隔离候选已构建并在实际 WGC/D3D 路径执行。此次没有正式 runtime promotion；玩家普通入口继续使用原部署。候选 identity、closure、测试 Core 与候选 Core 的相同哈希，以及每轮完整采样见 [机器证据](evidence/shared-hud-cost-2026-10-10.json)。

最新主线重新封装后的可用候选为 `tmp/runtime-candidates/v2/hud-work-1010-final`。主线的构建配方变化使 build identity 更新，但 43 个 payload 条目与被测 p2 全等，Core 和 Native DLL 的实际字节也相同；最终候选另行通过同一组 7 项 GPU 检查、0 跳过。manifest 的配方/identity 头部随之变化，不能把整个 manifest 称为字节相同。正式 runtime、consensus 和 asLoader 未改；本轮没有新建或删除 worktree。

## 三组成本分解

成本夹具使用生产 HUD 绘制器、真实 PlayerInfo 资源层、生产子弹/效果图集和现有合成 API；自建源窗口与输出窗口，不启动游戏、不接触存档。输出为 1024×576，每组先预热 2 秒，再测量 8 秒；主 HUD 以 30 Hz 触发实际动画和重绘。

| 组别 | 固定刺激 | 能回答的问题 |
|---|---|---|
| 静止 | 源画面、主 HUD 和资源动画时钟均冻结 | 空闲是否仍重绘、搬运或重复合成 |
| 仅 HUD 动画 | 主 HUD 动画及真实资源层动画；没有新 WGC 源帧 | HUD 更新本身的绘制、搬运，以及重新合成世界的成本 |
| 混合呈现 | 同一 HUD，加 30 Hz 源帧、192 个确定性子弹、8 盏动态光、160 个雪粒子 | 世界持续变化时，HUD 优化能否仍产生收益 |

未优化基线中，主 HUD 每次清理并重画约 46.8 万像素，每次约 1.9 ms；整幅提交约 0.58 ms。仅 HUD 动画时虽然没有新源帧，仍因 HUD/资源动画每秒合成约 58 次，世界 GPU 区间约 0.92 ms/次。混合呈现约 30 次/秒，世界 GPU 区间约 1.18 ms/次。

Native 每秒复制约 55 MiB。诊断把缓冲获取与逐行复制分开：基线每秒分别消耗约 9.8 ms 和 3.9 ms CPU。静止组则为零绘制、零复制、零上传、零合成，故没有实施新的空闲降频策略。

世界重绘确实有成本，但“无新 Flash 帧”不能证明世界静止：天气、氛围、子弹、射线、效果、局部光、相机或调色仍可变化。保留世界纹理需要更完整的失效合同，对混合场景也没有同等普遍的收益。因此本轮选择先降低两组动态负载都存在的 CPU 开销，没有加入世界缓存或第三项优化。

## 实现合同

### 主 HUD 脏区域重绘

[NativeHudOverlay](../launcher/src/Guardian/NativeHudOverlay.cs) 仅在完整共享主 HUD 已启用时采用局部重绘，沿用原 33 ms 合并请求与输入路由。组件发出重绘请求时登记其绘制范围；最多保存 16 个矩形，互相分离的区域不会强行扩成一个巨大包围盒。

局部清理使用透明 SourceCopy 填充并保留裁剪区，随后按原层序重画所有与脏区相交的可见组件，包含相交的半透明组件。位置、大小、显隐、增删、呈现后端切换、暂停/恢复、未知请求或范围溢出一律回到全量重绘。消费脏区发生在 Paint 之前，因此绘制期间新发出的请求会保留到下一帧。

[INativeHudWidget.Paint](../launcher/src/Guardian/Hud/INativeHudWidget.cs) 明确调用方裁剪合同；Combo、Notch、Tooltip、引导绘制器和地图内部裁剪改用 Intersect 并正确恢复。容器在每个组件前后保存/恢复 Graphics 状态，避免组件间泄漏。显示数量与实际参与此次绘制的数量分开统计，不能因为某帧没有相交组件就隐藏整个 HUD。

本项减少的是绘制工作。提交仍锁定完整合成位图，Native 仍接收完整 BGRA 数据；没有将局部重绘误写成局部 GPU 上传。

### Native 像素缓冲复用

[Compositor.cpp](../launcher/native/world-compositor/Compositor.cpp) 为五个 HUD 槽各保留至多三个缓冲，缓存总量上限 32 MiB。只有缓存是缓冲唯一所有者时才能借出复用；已发布帧、GPU 工作线程快照和正在写入的生产者持有的缓冲均不可复用。

获取和登记受现有会话互斥保护，像素复制在锁外完成，复制完成后才发布版本。缓冲忙、尺寸超额或缓存已满时沿用普通分配，不等待、不丢帧、不降低更新频率。隐藏图层释放其缓存引用；会话释放回收所有缓存。超出上限的合法大图仍可正常呈现。

复用消除了大部分重复分配/初始化，但不减少复制字节。实际测量中，单独的逐行复制 CPU 时间有所增加；分配获取加复制的总成本仍下降约 54%–56%。报告保留两者，未把总收益描述为 memcpy 提速。

## 最终 ABBA 对照

A 为仅加诊断的冻结基线 `hud-work-1010-b3`，B 为两项优化后的 `hud-work-1010-p2`。顺序 A1 → B1 → B2 → A2，每个独立进程重复两轮、每轮三组负载，共 24 个测量区间。每次运行绑定冻结测试装配和候选；实际加载 Core 的 SHA256 与相应候选完全相同。GPU 测试要求会话显示状态明确为 On，跳过不计通过。

下表为每个变体四次试验的中位数。耗时项取各试验均值的中位数；P95/P99 另外记录在机器证据中。

| 指标 | 仅 HUD：A → B | 混合呈现：A → B |
|---|---:|---:|
| 主 HUD 绘制 CPU ms/次 | 1.913 → 1.229（−35.8%） | 1.919 → 1.250（−34.9%） |
| 主 HUD 提交 CPU ms/次 | 0.577 → 0.209（−63.7%） | 0.575 → 0.219（−61.9%） |
| 主 HUD 绘制 P95 ms | 2.855 → 1.767 | 2.691 → 1.708 |
| 主 HUD 绘制 P99 ms | 3.511 → 2.409 | 3.502 → 2.082 |
| 实际重绘像素/次 | 467,908 → 24,024 | 467,908 → 24,024 |
| 缓冲获取 CPU ms/秒 | 9.844 → 0.047 | 9.779 → 0.045 |
| 逐行复制 CPU ms/秒 | 3.869 → 5.926 | 3.871 → 6.162 |
| 获取与复制合计 CPU ms/秒 | 13.714 → 5.975 | 13.635 → 6.208 |
| 复制 MiB/秒 | 55.249 → 55.303 | 55.280 → 55.322 |
| 实际上传 MiB/秒 | 55.249 → 55.308 | 53.264 → 55.171 |
| 世界 GPU ms/次 | 0.920 → 0.964 | 1.175 → 1.182 |
| HUD 上传/绘制 GPU ms/次 | 0.455 → 0.469 | 0.483 → 0.496 |
| 合成次数/秒 | 58.03 → 58.88 | 30.01 → 30.03 |
| 夹具进程 CPU，单核百分比 | 17.78% → 14.15% | 17.97% → 15.73% |

GPU 均值略有波动，没有证明 GPU 合成收益；上传量未下降。基线混合组存在合并消费多个 HUD 提交的情况，所以不能把复制量与上传量视为严格逐次对应。主 HUD 重绘频率维持约 30 Hz，未用少画帧换取耗时下降。

CPU 进程数据包括夹具驱动、自建窗口与原生工作线程，是一个 CPU 核心的百分比，不是游戏 Host 或整机 CPU 百分比。未采集 DWM、MPO、功耗或热降频。GPU 时间戳只包围世界/效果与 HUD 上传/绘制命令，排除 WGC 捕获、图集首次上传、Present 和物理扫描；不能与 CPU 提交用时混称。

单独启用第一项的中间候选也完成了三轮三组成本测量：主 HUD 绘制约降至 1.23–1.27 ms，而提交仍约 0.60 ms。最终第二项将提交降至约 0.21–0.22 ms，因而两项收益有分别的中间证据。

## 验证与保留的失败

- 像素与生命周期：全量重绘参考对照涵盖透明擦除、重叠、分离区域、移动、显隐、增删、未知请求、暂停恢复和绘制中再次请求；旧后端仍走全量路径。
- 完整生产绘制器 GPU 对照：10 类组件，在 1024×576、1280×720、1536×864 下比较局部重绘与同一状态的全量位图；额外逐组件验证调用方裁剪，保留源无回灌、层序、回退、面板恢复和几何围栏断言。三种尺寸不等同于三种显示器 DPI。
- 像素缓存：五路并发生产者、600 次提交、不同尺寸及 padded stride、提交后立即改写调用方源数组、隐藏清空、超过 32 MiB 的合法大图；核对最终 GPU 像素、复用计数和缓存上限。
- 诊断：启用/关闭不改变像素；测量 epoch 重置隔离，已开始样本全部完成，未出现 disjoint、丢测或 query 错误。最终专项 GPU 共 7 项通过、0 跳过；四次成本进程均实际执行并通过。
- 全量 Host 回归：6923 项通过、22 项按环境条件跳过、0 失败；确认串行测试策略生效，exact SDK 解析器 7/7 通过。保留原有 WindowsBase 版本冲突告警；专项 GPU 的实际执行结果单列，不把全量中的环境跳过计为通过。

首次静止夹具没有冻结资源动画，已修正并保留旧探索报告；不能采用那次结果证明空闲开销。新增 native 头文件曾命中构建输入域重叠，已将私有辅助类放回既有 Compositor.cpp，没有放宽构建政策。首次 C# 编译暴露 WinForms 属性序列化诊断，已按内部属性语义修正。

一次过宽的 GPU 过滤条件误选到旧性能试验，已停止该轮独占测试进程，原记录标为 aborted；随后使用准确过滤条件重跑。中断轮不计套件通过。

实际游戏取样使用独立克隆槽、零恢复重试和正常关闭。基线与最终优化候选均已进入游戏，但两侧都在斗兽场转场 cover 请求之后未得到推进，各自两个 case 均未开始战斗；因此没有实际战斗成本结论。两轮均正常退出，26 个非目标存档文件前后哈希不变。原始状态、日志和保护哈希留在 `tmp/hud-work-cost-20261010/live/`。这条入口缺口与 HUD 成本结论分开保留，没有扩大施工范围去修转场。

## 诊断与复现

### 2026-10-10 试玩日志复核与发布授权

维护者试玩后反馈“玩了一圈感觉没问题”，并授权日志无阻断项时走正式发布列车。20:26:06–20:31:14 的新鲜日志指向 `hud-work-1010-final` 的实际 Core 路径，与保留候选的身份和字节一致；不使用 9 月的旧 focus recording 代签。未见 HUD Paint 异常、世界渲染故障、未处理异常或保存失败，面板关闭后共享主 HUD 恢复，Flash 与输入 broker 正常退出，输入 consumed/completed 同为 806、invalid=0。

保留两项观察：结算材料面板与返场交接出现 3719 ms 的 Flash 长帧，期间主 HUD 处于暂停、Host 仍持续记录状态，随后转场完成；退出阶段有一次终端 shutdown 请求被取消，随后进程正常退出。当前没有将其归因为本批 HUD 改动，也没有以这次试玩证明稳定 30 FPS、弱机或全部业务旅程。具体计数与日志摘要见[试玩复核证据](evidence/shared-hud-playtest-2026-10-10.json)。本段是发布准入依据，正式部署状态仍以对应 promotion/consensus 为准。

### 计时入口

日常诊断仍用现有 `CF7_PLAYER_HUD_PROFILE=1` 开关：新增主 HUD 的 paint/commit 统计与 `[WorldHudCost]` 累计记录。Native GPU query 默认关闭，开启后异步轮询且使用 DONOTFLUSH；环满只丢测量、不丢渲染帧。统计为累计值，跨日志行比较须按 profile id 和计数差值计算。

可选 native 导出为 `ProbeSetHudCostSampling`、`ProbeGetHudCostStats`；本轮配对结构为 168 字节。旧 ABI 12 和既有 HUD 统计结构未改变。`AllocationCpuMs` 表示缓冲获取成本，包含缓存查询或新分配；`CopyCpuMs` 仅表示逐行复制，`CachedBytes` 是当前缓存持有字节数。字段缺失的旧模块仍可正常呈现，不能用于本专项计时。

成本入口位于 [OpaqueHudGpuTests.Costs.cs](../launcher/tests/Guardian/OpaqueHudGpuTests.Costs.cs)，只在显式给出候选和全新报告路径时执行。例：

```powershell
chcp.com 65001 | Out-Null
. ./launcher/resolve-dotnet.ps1
$dotnet = Resolve-Cf7Dotnet -ProjectRoot (Get-Location).Path
$env:CF7_TEST_SHARED_WORLD_CANDIDATE = Join-Path (Get-Location).Path 'tmp/runtime-candidates/v2/<candidate-leaf>'
$env:CF7_HUD_COST_PROJECT = (Get-Location).Path
$env:CF7_HUD_COST_REPORT = Join-Path (Get-Location).Path 'tmp/<new-run>/cost.json'
$env:CF7_HUD_COST_REPEATS = '3'
& $dotnet test launcher/tests/Launcher.Tests.csproj -c Release --filter 'FullyQualifiedName~MeasureSharedHudPaintTransportAndMixedComposition'
Remove-Item Env:CF7_HUD_COST_REPORT, Env:CF7_HUD_COST_PROJECT, Env:CF7_HUD_COST_REPEATS, Env:CF7_TEST_SHARED_WORLD_CANDIDATE
```

运行后必须核对报告的实际 Core 与候选 Core 哈希、identity/closure、采样完整性和非跳过结果；做 A/B 时冻结各自测试目录，不能让旧候选配上新 Core。原始四轮报告及中间候选数据已纳入本次机器证据，原始日志、TRX 和像素图留在本机临时目录。
