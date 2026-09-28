# Combat FX GPU 夹具

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
