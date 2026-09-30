# Combat FX GPU 夹具

射线提交分桶的 CPU 对照源为 `launcher/native/world-compositor/RayBucketSelfTest.cpp`，
使用固定 MSVC 工具链独立编译运行，输出每个场景的旧/新提交序列、批次及上传字节。
生产与测试共用 `RayPassBuckets.h`；Shader 的 pass 过滤仍是核对对象。此计数不等于 GPU 耗时。
`--rays` 的最高容量档仅保留一条可见射线和一枚可见子弹，其余放在视口外，
验证扩容后的接收、裁剪与清理；不能把该档报告成全屏吞吐量或实战资格。

在两个自有无边框窗口之间使用真实 Windows Graphics Capture、D3D11 shader 和合成输出，
验证弹壳/子弹/枪火分层、命中特效像素、局部光场、世界/天气受光、相机变换、叠加上限、清理与真实夜间预设。
不会启动游戏或读写存档。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File launcher/native/world-compositor/build-dev.ps1 -OutDir tmp/native-out-combat-fx
. ./launcher/resolve-dotnet.ps1
$fxDotnet = Resolve-Cf7Dotnet -ProjectRoot (Get-Location).Path
& $fxDotnet build launcher/perf/combat-fx/CombatFxProbe.csproj -c Release
& $fxDotnet launcher/perf/combat-fx/bin/Release/net10.0-windows/CombatFxProbe.dll . tmp/native-out-combat-fx/FlashCompositorNative.dll tmp/combat-fx-validation/gpu
```

输出 `probe.json`、PNG，失败时非零退出并留下 `failure.txt`。测试先用红/蓝色块和
现有普通子弹作像素断言，再上传实际源图集绘制全部样式预览。
读取使用显式诊断 `ProbeGrabCompositeFrame`（全部 pass 之后、Present 之前），
不会把原来的 `ProbeGrabLatestFrame` 源截图误当作合成输出。
普通运行没有新增逐帧 CPU readback。

局部光先在已知棋盘源上核对中心/半径外/移动后的像素，再用全黑源隔离天气受光，
再加载生产 `hardlight-dusk-v4` 的 L0/L5，读取通用枪火真实参数，检查最暗夜景的中心与周围可见度、
相对源材质的暖色贡献，以及出生到消失的逐 tick 光照。夜视按生产的矩阵路径检查绿色色向，
不把普通光照 LUT 的环境蓝色当成局部灯必须继承的色调。额外分别采样无灯与 16 灯的 90 个呈现帧，报告 CPU submit/present
中位数和 P95；它们不是 GPU 时间戳，也不是游戏 FPS。场景/设备不同不能直接比较该数字。

装备光源夹具还覆盖手电锥体的轴内/轴外、旋转与镜像，激光束带内材质提亮/束外不变、半宽 0.5 的 45 度细束无采样断点，以及清空后还原。ABI 9 使用 16-float 灯记录，并验证持灯者身体/脚下补光、近身光缩小后的背后边界、偏离枪口且旋转的近身光。相同材质的前向采样须持续衰减，径向采样须消除等亮圆心，交界区逐点受单灯峰值参考约束；激光验证窄核心、横向柔化、红色贡献与无近身光。`probe.json.proof.equipmentLights` 和 `equipment-*.png` 保存这一层证据。AS2 锚点、插件合成与常驻预算分别由 focused CS6 runner 和 Host 测试验证。

这是 renderer 验证，不代表游戏中枪口对齐、落地切换、面板/DRS 全链和弱机净性能已验收。

常驻径向夹具从真实 `CombatFxFrame` 解析器和 `CombatFxEngine` 构造 kind=0 快照，再驱动实际 DLL；核对蓝色身体光与红色兵器光的独立颜色、径向衰减、范围外不变、镜头移动与清空。对应输出为 `equipment-body-and-blade-radials.png`、`equipment-radials-camera.png`。AS2 的贡献数/灯数及 payload CPU 计时由自发光 focused suite 记录，不把该计时或本工具的 submit/present 时间称为游戏 FPS。

若输出目录含 `equipment-lighting-wires.json`，额外执行亮度校准：输入由 [自发光导出器](../../../tools/equipment-emissive/README.md) 从成功的真实 XML/素材 suite 提取，包含 `blue-set`、`blue-same`、`blue-blood` 三条完整 `;l,...` 快照。夹具保留源间相对位置，将身体中心平移到固定材质采样点，经真实 parser/engine/DLL 对照旧蓝晶参数及普通枪火。检查近身和脚边提亮、组合峰值、局部范围外不变，输出 `proof.equipmentVisibility`、输入 SHA-256 和 `equipment-visible-*.png`。该可选校准不更改生产 native shader；RGB 加权亮度只作同材质对照，不宣称物理光度或实战人眼验收。

## 嵌入拓扑启动回归

原生射线结构/颜色修复的实际 XML 对照使用 `scripts/run-ray-reference.ps1` 取得本轮 CS6 trace，
然后运行 `CombatFxProbe <project> <native-dll> <fresh-output> --reference <trace>`。
它输出八门四个时相、特斯拉和谐振波的真实长度与斜向版本，并记录颜色/像素包围。
额外四个 RGB24 高位奇整数（洋红、紫、粉、白）在真实 shader 中单独与黑色调色板控制组对照，
检查每个应存在的颜色通道，防止 float32 加 0.5 导致进位丢色。原版 AS2 参考板由该 TestLoader 保留，
按其[说明](../../../scripts/test-runners/ray-visual/reference.md)查看。
这组输出用于原/新结构审查，不要求不同表现 RNG 的特斯拉逐像素相同。

`--startup` 独立运行启动与恢复门，不执行上面的视觉图集。它创建有边框父窗口 S、实际子 HWND 和由 S 拥有的 layered/noactivate 输出 P；WGC 捕获 S，P 创建后保持隐藏，直到收到尺寸匹配且时间戳不早于裁剪 fence 的新帧才显示。几何解析复用生产 `WorldCompositorController` 的 capture-frame/crop 函数；不把 WGC 已返回尺寸当作捕获已启动。

```powershell
# 使用上面解析出的 exact SDK；两个输出目录都必须是本轮全新目录。
& $fxDotnet launcher/perf/combat-fx/bin/Release/net10.0-windows/CombatFxProbe.dll . <旧DLL绝对路径> tmp/world-capture-0929/startup-before --startup
& $fxDotnet launcher/perf/combat-fx/bin/Release/net10.0-windows/CombatFxProbe.dll . <新DLL绝对路径> tmp/world-capture-0929/startup-after --startup
```

每轮包含三次独立 native session；初始源为现场的 1600×900，再改为 1280×720。每个 session 检查隐藏 P 的首次出帧、`Active(false)` 后源持续绘制但捕获/呈现计数停止、恢复时 capture generation 增长及新鲜帧、`HoldViewport` 后尺寸变化与新裁剪。首次/恢复等帧保留 10 秒期限；只在真实几何变更时按生产方式更新 fence，shader 初始化、generation 0、atlas 未就绪均不能提前移出等待窗口。失败以非零退出，并在释放 native session 前立即落下 `deadline_failed` 与末次计数；native 析构等待单独记录，不能用稍后成功补写该轮通过。

`startup-identity.json` 绑定实际 DLL 绝对路径和 SHA-256、Host/夹具模块路径、PID 与拓扑边界；`startup-events.jsonl` 按阶段即时记录时间、S/child/P HWND、尺寸、fence、native state、capture generation 和 received/presented；`startup-probe.json` 汇总九个阶段及失败原因。比较旧 DLL 与新 DLL 必须各自真实运行，不把负控失败或静态源码推断当成通过证据。

这是生产渲染启动拓扑的受控回归：子 HWND 来自同进程测试控件，重绘 fence 来自该控件绘制后 `GdiFlush`，未接真实 Flash、跨进程输入桥、AS2 scene/capability/灯合成调度或玩家存档；没有申请去除系统捕获边框。它不能代签真实 Launcher 标准入口、输入、内容正确性或人类视觉验收。现有 [Flash compositor 嵌入夹具](../flash-compositor/README.md) 可用于独立的真实素材/嵌入内容证据。

## 真实地图素材上的射线受光标定

`--field <CS6-trace>` 使用输出目录中的 `source.png` 作静态 WGC 源，按 `(160,205,1024,576)` 裁剪到视口，不修改原图。当前底图为只读 FFDec 导出的 `基地场景-基地车库`：车、地面与原帧占位 NPC 是美术素材，不是玩家存档截图。输出目录必须新建，并预置 `old-ray-lights.json`，明确保存本轮前的射线照明配置。旧照明使用旧配置及当前引擎，不能称为旧二进制复跑；此处标准长束不触发新旧短束宽度上限的差异。

```powershell
# 先准备新的输出目录，复制只读导出的原始 PNG 和明确版本的旧灯光配置。
# native/Host 构建仍按上面的统一入口执行，不由此模式自动触发。
& $fxDotnet launcher/perf/combat-fx/bin/Release/net10.0-windows/CombatFxProbe.dll . <本轮DLL绝对路径> <输出目录> --field <本轮CS6-trace>
```

输入使用 `[RAY_GPU_SCENE] <key>` 与 `[RAY_GPU_WIRE] <F7>`。必需场景为 `flame_field`、`thermal_field`、`prism_field`、`tesla_age0`、`bagua_age0`；可选读取强化热能、电弧不同年龄、基础电弧、符纹不同年龄和谐振波。每个场景独立重放全部真 F7 包，采用 CS6 从实际子弹 XML 与预设解析出的完整配置。原点仅通过摄像机平移统一到 `(240,300)`；束体几何和 RNG 不重写。火束场景应为真实 `620/14` 配置，不能拿画廊预设代替实际武器。

`index.html` 可切换 L0 无灯、原手电、原镭射、束体，以及旧/新灯光各自的环境光单独画面和合成画面。手电保留 `1000/260/1.45` 与人物中心 `(185,300)` 的 `140/1.15` 近身光；镭射保留 `750/28/.85`。全部场景使用相同底图、L0 和束体几何。`field-identity.json` 记录 PNG/trace/native/Core/夹具 SHA；`lighting-before.json`、`lighting-after.json` 保存精确配置；每个场景 JSON 保存完整配置、光记录、几何 hash、输入包与 ROI 指标，即使后续场景失败也保留已完成证据。

ROI 分近身、脚下、远近地面和上侧，剔除束心前方的 ±24 像素。指标来自真实 GPU 合成读回：sRGB 加权亮度增量、sRGB 解码后的线性亮度增量、超过 1 级的增亮面积及至少 10 级的有效面积。这里先输出标定值，结构断言只覆盖输入、几何一致、资源就绪和清理；不凭尚未核对的 ROI 宣称亮度体验通过，也不改变既有夹具阈值。真实游戏角色定位、动态战斗、交互与存档不在本入口的证据范围内。

`--reference <CS6-trace>` 为独立的黑底束体参考板入口，调用 `RayReferenceGallery`，不加载地图底图；其美术对照与 `--field` 的环境受光证据分别保存。

## 射线通道与高射速重放

`scripts/run-ray-rate-tests.ps1` 在 TestLoader 中产生 `[RAY_RATE_SCENE]` / `[RAY_RATE_WIRE]`。
把本轮 trace 交给 `CombatFxProbe <project> <ABI12-native-dll> <fresh-output> --channels <trace>`，
即可按 30 Hz 经真实 F7 parser、RayVisualEngine、WorldLightComposer 和 GPU 重放。
保留真实配置的线宽、透明度、分支与灯光；计时内不做图片读回，不使用旧数组压力夹具的压细/降透明。

每个场景即时保存 JSON，最后写 `channel-proof.json`，包含 AS2 trace/native/Core 摘要、活跃通道、
绘制记录、灯数量、Host 解析至提交耗时分位、节拍超时和实际呈现次数。worker Present 观测可能重复上一采样，
不是 GPU timestamp；此进程也不同时运行 Flash、AI 和真实 socket。AS2 完整结算层的覆盖边界归同域 runner 说明，
不能把两套分离计时相加后称为游戏 FPS，亦不能直接把 ray record 数量当作武器射速上限。

`--reference` 额外生成 `tesla-motion/index.html`：真实 XML 束体参数的原生 60 帧动态样张，
使用固定展示长度与显式的连发时钟，支持暂停和逐帧查看。它用于美术判断；真实射击/复用时序由 `--channels` 验证。


## 联弹首次建层与换场景回归

`scripts/run-chain-aggregate-tests.ps1` 通过真实 `对象联弹初始化` / `registerGroup` 产生
`[CHAIN_SCENE_CASE]` 与 `[CHAIN_SCENE_WIRE]`。包含 XM214 次级穿刺插件、M1014 次级穿刺，
以及真穿刺与普通弹对照；覆盖能力先授予后懒建层、清场后无再次授予、暂停呈现与断连。

```powershell
& $fxDotnet launcher/perf/combat-fx/bin/Release/net10.0-windows/CombatFxProbe.dll . <配套DLL路径> <新输出目录> --chain-scenes <本轮CS6-trace>
```

此入口经生产 F8 parser / ChainVisualEngine / 原生图集实际读回 8 组情形的 16 帧，
验证正确样式、非空像素和清理。`chain-scene-proof.json` 保存 trace/Core/native/catalog 哈希。
不进入玩家存档，不覆盖完整开枪入口/战斗 AI 或实战帧率；现场验收仍需原武器重试。

## 性能收束的成本与缓存对照

`--host-costs <项目根> <新输出目录>` 是 CPU-only 入口，不创建窗口或进入存档。
它经生产 F8 parser、ChainVisualEngine、FrameTask 联弹合成及原生记录打包，重放相同的
出生、多个八单元组、镜像、暂停和运动；三档各先预热至少一秒，再取七个样本。
`host-costs.json` 绑定实际 Core 哈希、输入/输出哈希、分配量、耗时和严格语法接受结果。
不包含 F5 解析、socket、HUD、native setter、GPU、完整 Flash、功耗或游戏 FPS。

旧 Core 对照可在保留其依赖目录后，用
`-p:BaselineCorePath=<绝对旧Core.dll路径>` 构建同一夹具；只改变测试程序集的引用，
输出中的 `coreSha256` 必须与冻结的旧 Core 相同。生产构建不使用此参数。
短进程的 tiered JIT 阶段会扰动时间，保留原始记录，先预热并交替运行旧/新；
不把分配下降直接当作 CPU 时间或整机收益。

`--caches` 使用真实 WGC/D3D 和可选 `ProbeGetWorkStats` 验证静态光场命中、
特效缓冲复用、首次/缓存输出像素相同，以及灯位置/能量、镜头、调色参与参数、
视口、清灯、恢复和新会话的失效路径。旧 ABI12 的生产导出和 Stats 布局保持不变；
该附加诊断的计数是实际 worker 工作次数，不是 GPU 时间戳。

```powershell
& $fxDotnet launcher/perf/combat-fx/bin/Release/net10.0-windows/CombatFxProbe.dll --host-costs . tmp/perf-cost-new
& $fxDotnet launcher/perf/combat-fx/bin/Release/net10.0-windows/CombatFxProbe.dll . <配套DLL路径> tmp/perf-cache-new --caches
```

这两条入口没有目标轻薄本的传感器数据，也没有完整游戏同时运行；热稳态包功耗、
有效单核频率、限频原因与 Flash 帧间隔仍需在目标机器记录。
本批实现、对照与候选状态归[性能收束施工记录](../../../docs/战斗表现性能收束-施工-2026-09-30.md)。
