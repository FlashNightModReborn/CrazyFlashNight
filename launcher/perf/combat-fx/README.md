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

这是 renderer 验证，不代表游戏中枪口对齐、落地切换、面板/DRS 全链和弱机净性能已验收。
