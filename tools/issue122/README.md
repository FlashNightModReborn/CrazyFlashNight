# Issue #122 索引路径诊断

**文档角色**：隔离诊断工具的运行入口。源码基线为 `137ab0dba7e860817838d02dd535f4609acd1262`；2026-09-28 本地补充判定保护、实际后端核验及低角度覆盖。

本工具使用真实 GLB、生产 Three.js/GLTFLoader/后处理与独立 Windows WebView2 窗口。
它不启动游戏、不消费玩家槽位、不编译 Flash，也不构建或部署正式 runtime。
独立窗口正常不能代签生产 WebOverlay/Flash 入口；原故障截图的精确游览坐标未保存，补充低角度只是诊断覆盖。

## Windows 本机入口

先进入隔离 worktree，使用仓库 SDK resolver 构建小工具。所需版本为 `.NET 10.0.300`、WebView2 `1.0.3856.49` 与 Newtonsoft.Json `13.0.3`。
本机依赖已缓存时可仅使用本地包源：

```powershell
. ./launcher/resolve-dotnet.ps1
$probeDotnet = Resolve-Cf7Dotnet -ProjectRoot (Get-Location).Path
& $probeDotnet restore tools/issue122/windows-webview2/Issue122.WebView2.csproj --source "$env:USERPROFILE/.nuget/packages" --ignore-failed-sources
& $probeDotnet build tools/issue122/windows-webview2/Issue122.WebView2.csproj -c Release --no-restore
& $probeDotnet tools/issue122/windows-webview2/bin/Release/net10.0-windows/Issue122.WebView2.dll --self-test classification-tests.json
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/issue122/windows-webview2/run-local.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/issue122/windows-webview2/run-local.ps1 -Adapter high-performance
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/issue122/windows-webview2/run-local.ps1 -CameraSet low
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/issue122/windows-webview2/run-local.ps1 -CameraSet low -Adapter high-performance
```

每次运行自动选择一个全新输出目录，分别建立 GPU/software profile，窗口不主动激活。
高性能请求只给本轮 GPU WebView2 传 `--force-high-performance-gpu`；实际是否切到独显必须读 `unmaskedRenderer`，不写系统 GPU 偏好。
当前已有包源不能满足 restore 时应报告缺项，不自动安装 SDK 或更换锁定版本。
父 runner 只管理自己启动的探针进程，并给整轮 240 秒截止；逐 cell 保留中间结果，已有证据目录拒绝覆盖。

对 runner 输出的精确 `runRoot` 执行：

```powershell
python -X utf8 tools/issue122/analyze-windows-pixels.py "<runRoot>"
```

Python 分析使用 Pillow 与 NumPy，保存像素差异数量、最大通道差、局部连通区域与放大差分图。
这些统计是诊断量，不是放宽验收的容差门；不会把 mixed 改成通过。

## 判定与失败边界

- 每轮两个相机，硬件 raw/chunked/nonindexed 加 software raw/chunked，共十个 cell。
- `overview` 是 P8 原概览相机与当前相机；`low` 是明确标记的两个补充低角度。
- 必须证明 GLB 响应哈希、模式和相机传播、361010 triangles、51/55 draws、5 个 Uint16 chunk 或一个 nonindexed 展开批次。
- 每个 cell 两次 CapturePreview 的解码像素哈希必须相同；缺失哈希、尺寸或不完整矩阵不能冒充相等。
- GPU 必须报告已识别的实体适配器，software 必须报告 SwiftShader/WARP 等软件实现；同 lane 的 renderer 和 WebView2 版本应一致。
- 只有两个相机都满足 raw 异常且两条对照正常，才标记 `gpu_uint32_path_reproduced`；一个相机异常仍为 mixed。
- `status=completed` 表示矩阵采集完成。mixed 或后端不足会返回 exit 1，表示不能自动归因；它不等同于进程崩溃或游戏故障复现。
- 构建可能保留 WebView2 WPF 依赖引入的已知 `WindowsBase MSB3277` warning；不把该 warning 当行为通过。

本轮执行记录与证据边界见[Windows 实机复核](../../docs/堕落城索引路径-Windows实机复核-2026-09-28.md)。
