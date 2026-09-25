# C1-I 输入底座与真实后端装配夹具

本目录包含诊断源码与 C1-I 只读交接夹具。**固定的人验包由`tools/run-c1-input-acceptance.ps1` 启动；直接运行这里的源码构建不自动取得人验资格。** 窗口变化显示连续性补修见 [R12 报告](../../../../docs/reports/统一输入-R12窗口切换显示连续性-2026-09-24.md)。输入接线见 [R11 报告](../../../../docs/reports/统一输入-R11真实交接与人验候选-2026-09-24.md)，操作见[三组人验](../../../../docs/统一输入-C1人力验收-2026-09-24.md)。R10 的分离组件证据见[历史报告](../../../../docs/reports/统一输入-R10底座与隔离装配-2026-09-24.md)。普通 Launcher 不构造这些入口；没有正式 runtime 发布或真实玩家存档访问。

## 三条证据链

| 入口 | 实际执行 | 不证明 |
|---|---|---|
| `InputOwnershipProbe.csproj` | 专用 Raw Input 线程、来源故障、注册被替换、恢复；明确标记的 Shift 注入 | AS2/Web 业务完成、真实硬件完整性、C1 准入 |
| `check-island.py` | 真 Flash Player 20，bootstrap→业务模块、生产整形 service/opener、旧驱动禁用、付费拒绝、协议取消 | 物理点击、Host 协调器和网页的一次完整 handoff |
| `C1IslandHost.csproj` | 同一 DComp 树、WGC world visual、生产 PlayerInfo 缓存、生产资源注释组件、真实整形网页→Host task→AS2 快照、实际网页清理/控制器退休；补验已观察到预期 world/HUD 画面 | 完整物理输入接线、Native 物理交互、IME/Tab、长期图像稳定性、人验通过 |
| `C1IslandHost.csproj --interactive` + `check-live.py` | R11 的实际 Raw→协调器→M/Web/Native 接线；真实 opener／姓名草稿／取消、Native hover、键盘、来源与窗口变化、确切 Web 退休重建 | 机器注入不等于真人硬件或 IME 候选窗体验；不是普通基地、持久写或正式发布 |

三个程序都不能代签对方的边界。尤其 `Received/Presented > 0` 只证明捕获/提交计数，不能证明捕获到的是正确 Flash 内容。检查标记文件只结束诊断等待，不是视觉通过证书。

## 先于游戏类初始化的能力

`bootstrap/C1Bootstrap.as` 不导入游戏类。它先设置不可写/不可删的隔离能力，随后仅加载同目录 `C1Island.swf`，并在加载前设置 `_lockroot`。Host/Python 将两个 SWF 复制到本轮证据目录再启动，实际执行路径与 hash 写入 identity。

旧 `KeyManager`、`FrameTimer`、`CooldownWheel`、`EnhancedCooldownWheel` 与 `VectorAfterimageRenderer` 的构造路径只在该能力存在时禁止旧轮询/驱动/排队。普通入口缺省不受影响；没有在热更新循环中加入周期性的焦点修补。迟到设置能力不能把已经执行过旧域的 VM 变成有效 C1 VM。

`island/C1Island.as` 从真实被动素材、`DressupReferenceManager` 和生产整形 service 建立可丢弃角色；没有完整基地、门、NPC、存档服务。HUD 只调用现役资源投影，不安装含技能/药剂写命令的整套 HUD service。保留的显示心跳只改变诊断色块。

## 构建与验证

在仓库根执行；PowerShell 先 `chcp.com 65001`。AS2 编译使用 Windows PowerShell 5 的既有 CS6 管线，不能用编译 marker 或旧 SWF 代替新鲜 Compiler `0/0`。

```powershell
python launcher/native/world-compositor/input-ownership-fixture/build-island.py
python launcher/native/world-compositor/input-ownership-fixture/build-island.py --check
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/compile_test.ps1 -Target launcher/native/world-compositor/input-ownership-fixture/island/C1Island.xfl -PublishOnly -VerifySwf launcher/native/world-compositor/input-ownership-fixture/C1Island.swf -TimeoutSeconds 180
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/compile_test.ps1 -Target launcher/native/world-compositor/input-ownership-fixture/bootstrap/C1Bootstrap.xfl -PublishOnly -VerifySwf launcher/native/world-compositor/input-ownership-fixture/C1Bootstrap.swf -TimeoutSeconds 180
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run-input-isolation-normal-tests.ps1
python launcher/native/world-compositor/input-ownership-fixture/check-island.py tmp/<全新证据目录>
```

生成器只复制四个真实被动素材的闭包，拒绝 `stop();` 之外的素材脚本；不修改原素材。宏从 `scripts/macros` 按字节派生到忽略目录，保留 BOM，以满足 CS6 的相对 include 规则；不能手改派生宏。失败编译即使重写了 SWF，也不能进入执行步骤。

`audit-bootstrap.py <本轮模块dumpAS2索引> <输出json>` 检查 bootstrap 没有 `DoInitAction`/类/导入/元件，登记实际模块链接类与已知驱动构造门；不是完整交互验收。索引用本机现有 FFDec `-dumpAS2` 从同一 SWF 生成。反编译只用于阅读，不回写 SWF。

Native 只构建本地诊断输出：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File launcher/native/world-compositor/build-dev.ps1 -Target c1fixture -OutDir tmp/c1-native
. ./launcher/resolve-dotnet.ps1
$dotnet = Resolve-Cf7Dotnet -ProjectRoot (Get-Location).Path
& $dotnet build launcher/native/world-compositor/input-ownership-fixture/C1IslandHost.csproj -c Release -o tmp/<新目录>/bin
```

只把本轮 `C1Scene.dll`、`FlashCompositorNative.dll` 配对放进该诊断 `bin`。用解析出的 dotnet 启动 `C1IslandHost.dll <repo绝对路径> <全新证据目录>`；不要修改正式 runtime。主程序新增可选 `ProbeStartVisual`，原 ABI 3 入口保持原路径，`C1Scene.dll` 不属于默认 native 产物。

不带 `--interactive` 的旧组件探针仍使用 `inspect.flag` / `world-inspect.flag`，它们只结束检查等待，不代签视觉通过。`--independent-source` 保留作拓扑对照。实际交接使用 `--interactive`，不能通过脚本强改 `gate.granted` 代替准入。

Raw 探针须先构建独立 `InputOwnershipProbe.csproj`。启动参数仅为全新证据目录；首次确切激活成功后才写 `continue.flag`。程序在自己的前台窗口内执行声明过的机器 Shift 刺激，45 秒上限；`stop.request` 只退出该实例。后续强化的 held 检查要求恢复后真正取得 `Reason=held`，历史只观察到 `snapshot_prefix_pending` 的运行不能代签它。

窗口准备优先用仓库脚本，不要求 Computer Use。CS6 文档切换由 `compile_test.ps1 -Target` 完成；候选运行截图用 `scripts/capture_screenshot.ps1 -TargetProcessId <本轮PID> -WindowHandle <本轮HWND> -OutputPath <证据目录>/scene.png`。省略 HWND 时使用该进程的主窗口。脚本核验 PID 所有权，单次请求激活并核验截图前后的 exact foreground；失败不出合格截图，不循环抢焦点。`-NoActivate` 只观察屏幕矩形，不能排除遮挡；即使前台核验成功，也要读图确认实际内容。`inspect.flag` 不是脚本激活回执，不应自动等同视觉通过。没有任何激活代码接入正式游戏。

## R11 真实交接验证与冻结

`check-live.py <dotnet绝对路径> <bin目录> <全新证据目录> --late-key-negative --disconnect-probe` 使用声明过的机器输入，并核验确切前台和目标窗口。它也包含只验证取消协议的 DOM composition 刺激，不将其写成真实中文输入法通过。`--smoke` 只跑短纵切，不能代替完整矩阵。退出、丢失刺激或 setup 遮挡均判失败。

`freeze-human.py <已构建bin> <全新候选目录>` 复制 x64 运行依赖、SWF 和可执行 Web 字节，初始状态始终为 `UNQUALIFIED`。必须在这个冻结目录实跑通过，再绑定代码闭包、WebView 版本、检查结果和完整文件清单，才可将本机 `tmp/c1-input-human/current.json` 指向它。初次打包缺 native 依赖的失败不能用构建目录的成功抵消。

人验脚本校验 `READY_FOR_HUMAN` 与清单哈希；Host 启动前核验冻结代码闭包，创建每个 WebController 时核验固定 WebView 版本。人验退出只归档身份和诊断记录，不自动升级为人工通过。外部返回首击只激活；控制器退休后保留已确认草稿、丢弃未确认组合；真实断链关闭专用 VM，重新启动才恢复。

下一步是本候选的 IME、Tab、自然切换、窗口／注释与重建延迟体验。普通游戏域 B、动态 AS2 子域、全设备资格、性能与正式部署不随 C1 收口。

## R12 呈现与输入分离

`C1Presentation.cs` 与 `C1Scene.cpp` 保留独立模态底层和不可交互位图，跨越 WebController 的真实退休／重建。位图不登记窗口、不给取消 ACK、不能成为 input owner。页面准备后的两个 animation frame 与 CapturePreview 只作为页面绘制检查；DComp commit completion 不冒称 DWM 已扫描输出。模态底层持续遮挡 AS2，正常取消才撤去；旧异步结果按 controller、round 和 presentation serial 丢弃。

在原 `check-live.py` 命令追加 `--presentation-check`，会增加页面打开时的连续移动／缩放及前后台屏幕像素采样（需本机已有 Pillow）。仅在真实目标窗口可见点采样 AS2 心跳色块；它不是完整屏幕每帧、跨 DPI、实际鼠标拖拽或真人体验的代签。旧 R11 冻结候选同路径会抓到露出，负控应保持失败。冻结包需重新构建并实跑，不能原地修改旧包。

## R13 长宽比与加载活性

修复依据和边界见 [R13 报告](../../../../docs/reports/统一输入-R13长宽比与恢复活性-2026-09-24.md)。在矩阵命令追加 `--aspect-stress --delay-read-probe`，执行三轮宽高变化及声明的真实 snapshot 传输延迟；不改变页面数据生产者，不注入假的准入。Web只读加载按同一 controller／page instance／generation 绑定，过时几何不丢读取，未来轮次和旧页面仍拒绝。C1消费有效意图后保留目标构建，原协调器默认回退合同保留。人验仍经冻结入口，不直接把源码构建视作合格候选。

## B1 前置共享组件与 END 结算

C1 当前源码已消费 Core 的 `CompositionSceneHost` 与默认 `FlashCompositorNative.dll` Scene ABI 1；私有 C1Scene.dll 只为旧客户端保留兼容 shim，新消费者不加载它。已冻结的 R13 人验包不受源码变化影响。

`check-live.py --end-settlement-check` 加入真实 END 意图回程延迟与 Native hover 竞速、空白点击解锁、长于回执期限的合法外部停留／持键，以及丢 prepared 回执的失败检查。注入是显式的，非真人手感证明。详情见 [本批检查点](../../../../docs/reports/统一输入-B1共享底座与冷装配检查点-2026-09-24.md)。

## B1 共享 Host 消费

`C1IslandHost.cs` 现在仅保留参数适配，输入、WebController 生命周期和呈现代码由 [Core UnifiedHost](../../../src/Guardian/UnifiedHost/) 提供。旧三个 partial 文件仅为兼容注释，不再保留复制实现。默认关闭诊断注入；C1 夹具显式启用。模块名、源尺寸和命中坐标统一由封闭 `UnifiedSceneProfile` 提供；当前仅开放 C1。原有冻结包不原地更新，B1 并未因此取得人验资格。
