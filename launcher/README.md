# CF7:ME Guardian Launcher

C# WinForms 守护进程，替代旧 Node.js Local Server，负责启动并嵌入 Flash Player SA、提供 V8 脚本总线和 HTTP/XMLSocket 通信。

## 技术栈

| 项目 | 版本/说明 |
|------|-----------|
| 运行时 | .NET Framework 4.6.2, x64 |
| 语言 | C# 5 |
| UI | WinForms (WinExe) |
| 构建 | MSBuild 4.0 + NuGet (packages.config) + MSVC (native DLL) |
| 音频 | miniaudio (Unlicense, 单头文件 C 库 → native DLL, WASAPI) |
| JS 引擎 | ClearScript 7.4.5 (Chromium V8, 替代 Node.js vm2) |
| Web 覆盖层 | WebView2 1.0.3856.49 (Evergreen Runtime, 幽灵输入解耦架构) |
| JSON | Newtonsoft.Json 13.0.3 |
| GPU (实验) | SharpDX 4.2.0 (D3D11, 当前禁用) |

## 架构概览

```
┌─────────────────────────────────────────────────┐
│  GuardianForm (WinForms)                        │
│  ┌──────────────────────────────────────┐       │
│  │ _flashPanel  (Panel, Dock=Fill)      │       │
│  │   └─ Flash Player SA (SetParent 嵌入) │       │
│  ├──────────────────────────────────────┤       │
│  │ Toolbar (Dock=Top)  │ LogBar (Dock=Bot)│     │
│  └──────────────────────────────────────┘       │
│  TrayIcon                                       │
└───────┬──────────────────────────┬──────────────┘
        │                          │
   ┌────┴────┐               ┌─────┴──────┐
   │XMLSocket│               │  HTTP API  │
   │TCP :port│               │  :port     │
   │\0-delim │               │  REST/JSON │
   └────┬────┘               └─────┬──────┘
        │                          │
        ├─ 快车道 (前缀协议) ──────────────────┐
        │  'F' → FrameTask.HandleRaw(cam,hn)  │
        │  'R' → FrameTask.HandleReset()      │
        │  'S' → AudioTask.HandleSfxFastLane() │
        │  'P' → AS2 applyFromLauncher(C#→AS2)│
        │  (绕过 JSON 解析，零 GC 分配)        │
        ├──────────────────────────────────────┘
        │
   ┌────┴──────────────────────────┴──┐
   │    MessageRouter (JSON 路由)     │
   │  ┌────────────────────────────┐  │
   │  │  toast (sync, fire&forget) │  │
   │  │  audio (sync, fire&forget) │  │
   │  │  gomoku_eval (async)       │  │
   │  │  → rapfi engine            │  │
   │  └────────────────────────────┘  │
   └───────────────┬──────────────────┘
                   │
   ┌───────────────┴──────────────────┐
   │  AudioEngine (C# P/Invoke)       │
   │  ┌────────────────────────────┐  │
   │  │  miniaudio.dll (native C)  │  │
   │  │  WASAPI shared mode        │  │
   │  │  BGM: dual-instance xfade  │  │
   │  │  SFX: preload + 90ms dedup │  │
   │  └────────────────────────────┘  │
   └──────────────────────────────────┘

   hotkey_guard.exe  ← 独立进程，低级键盘钩子
   (接收 Guardian PID, 拦截 Ctrl+Q/W/R/F/P/O)

   ┌─────────────────────────────────────────┐
   │  幽灵输入解耦 (Ghost Input Decoupled)    │
   │                                         │
   │  InputShieldForm                        │
   │  (GDI+ α=1 命中区拦截 → CDP 注入)       │
   │         ↓ CDP Input.dispatchMouseEvent  │
   │  WebOverlayForm                         │
   │  (WS_EX_TRANSPARENT, WebView2 渲染)     │
   │         ↓ 穿透                          │
   │  Flash HWND (WS_CHILD)                  │
   └─────────────────────────────────────────┘
```

## 目录结构

```
launcher/
├── CRAZYFLASHER7MercenaryEmpire.csproj   项目文件
├── packages.config                        NuGet 包清单
├── build.ps1                              构建脚本
├── app.ico                                应用图标
├── src/
│   ├── Program.cs                         入口：单例检查→配置→总线→嵌入→消息循环
│   ├── Config/
│   │   └── AppConfig.cs                   读取 config.toml (key=value 解析)
│   ├── Guardian/
│   │   ├── GuardianForm.cs                WinForms 主窗口 (工具栏/日志/托盘)
│   │   ├── WindowManager.cs               Win32 SetParent 嵌入 + 看门狗
│   │   ├── ProcessManager.cs              Flash SA 进程生命周期
│   │   ├── LogManager.cs                  线程安全日志 → TextBox + 文件 (logs/)
│   │   ├── OverlayBase.cs                 GDI+ Layered Window 覆盖层基类
│   │   ├── ToastOverlay.cs                GDI+ toast 消息 (WS_EX_TRANSPARENT)
│   │   ├── NotchOverlay.cs                GDI+ 刘海栏 (选择性穿透, 状态机)
│   │   ├── HitNumberOverlay.cs            GDI+ 伤害数字
│   │   ├── WebOverlayForm.cs              WebView2 视觉层 (WS_EX_TRANSPARENT)
│   │   ├── InputShieldForm.cs             幽灵输入层 (GDI+ α 命中 + CDP 注入)
│   │   ├── IToastSink.cs                  Toast 接口 (WebView2/GDI+ 双实现)
│   │   ├── INotchSink.cs                  Notch 接口
│   │   ├── FlashCoordinateMapper.cs       Flash 舞台坐标 ↔ 屏幕坐标
│   │   ├── FpsRingBuffer.cs               FPS 环形缓冲 + 统计方法 + 场景重置
│   │   ├── PerfDecisionEngine.cs          性能决策引擎 (统计阈值+迟滞, 替代AS2 Kalman/PID)
│   │   ├── HotkeyGuard.cs                 独立进程：WH_KEYBOARD_LL 钩子
│   │   └── KeyboardHook.cs                (未使用，保留备用)
│   ├── Bus/
│   │   ├── XmlSocketServer.cs             TCP 服务器（快车道 F/R 前缀 + JSON 双通道）
│   │   ├── HttpApiServer.cs               HTTP REST (/status, /console, /logBatch 等)
│   │   ├── MessageRouter.cs               JSON task 路由 → sync/async handler
│   │   ├── TaskRegistry.cs                Task 注册表 — single source of truth
│   │   ├── PortAllocator.cs               种子 "1192433993" 确定性端口分配
│   │   └── FlashPolicyHandler.cs          Flash 跨域策略
│   ├── Audio/
│   │   ├── AudioEngine.cs                 miniaudio P/Invoke (play/stop/seek/peak)
│   │   └── MusicCatalog.cs                BGM 目录：XML解析 + 文件系统扫描 + 热加载
│   ├── Services/
│   │   └── DirectoryWatcherService.cs     通用文件监听服务（去抖 + 增量回调）
│   ├── Tasks/
│   │   ├── AudioTask.cs                   BGM JSON handler (play/stop/vol/seek/loop) + SFX 快车道
│   │   ├── FrameTask.cs                   帧数据处理（快车道 HandleRaw + JSON 回退）
│   │   ├── GomokuTask.cs                  五子棋 AI (外部 rapfi 引擎, async)
│   │   └── ToastTask.cs                   UI toast 通知 (fire-and-forget)
│   └── Render/                            GPU 锐化 (实验性，当前禁用)
│       ├── GpuRenderer.cs                 D3D11 off-screen CAS 处理
│       ├── CasShaderBytecode.cs           HLSL CAS 着色器
│       ├── D3DPanel.cs                    双缓冲显示面板
│       └── RenderNativeMethods.cs         PrintWindow/BitBlt P/Invoke
├── native/
│   ├── miniaudio.h                        miniaudio 单头文件库 (Unlicense)
│   ├── miniaudio_bridge.c                 C 导出层 (BGM crossfade/seek/pause/looping, SFX preload, peak)
│   └── build.bat                          MSVC 自动探测 + 编译脚本
├── web/                                   WebView2 overlay 前端资源
│   ├── overlay.html                       DOM 结构 (Toast + Notch + Jukebox + 帮助弹窗)
│   ├── css/overlay.css                    样式 + 动效
│   ├── lib/
│   │   └── marked.min.js                  Markdown→HTML 渲染器 (MIT, ~40KB min)
│   └── modules/
│       ├── bridge.js                      C# ↔ JS 消息桥
│       ├── uidata.js                      帧同步 UI 状态分发 (KV 格式)
│       ├── toast.js                       Toast 消息 (Flash HTML 白名单过滤)
│       ├── sparkline.js                   FPS 折线图渲染 (DPR 感知, LOD)
│       ├── notch.js                       Notch UI (FPS/sparkline/clock/toolbar + hitRect 上报)
│       ├── currency.js                    经济面板 (金钱/K点 动画)
│       └── jukebox.js                     BGM 点歌器 (专辑浏览/选曲/波形/seek/暂停/设置/帮助)
├── bin/Release/                           编译输出
├── packages/                              NuGet 包缓存
└── tools/
    └── nuget.exe                          NuGet CLI
```

## 在 VS Code 中构建

### 前置条件

- Windows 系统，已安装 .NET Framework 4.5+ (系统自带)
- MSBuild: `C:\Windows\Microsoft.NET\Framework64\v4.0.30319\msbuild.exe` (系统自带)
- MSVC C 编译器 (cl.exe): Visual Studio 2022 Build Tools 或任意 VS 版本
  - 安装: `winget install Microsoft.VisualStudio.2022.BuildTools --override "--add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 --add Microsoft.VisualStudio.Component.Windows11SDK.22621"`
  - build.bat 会自动探测 vcvars64.bat 位置
- 终端使用 PowerShell 或 Git Bash

### 一键构建

```powershell
cd launcher
powershell -File build.ps1
```

构建流程：
1. `nuget restore` — 恢复 NuGet 包 (ClearScript, Newtonsoft.Json, SharpDX)
2. TypeScript 编译 — `npx tsc` (V8 HitNumber 脚本)
3. **native/build.bat** — 编译 miniaudio_bridge.c → miniaudio.dll (自动探测 MSVC)
4. `msbuild /p:Configuration=Release` — 编译 C# 项目
5. 复制产物 (exe + 9 DLL + miniaudio.dll) 到项目根目录
6. 复制 V8 原生 DLL 到项目根目录

### 产物

构建完成后，以下文件被部署到项目根目录：

| 文件 | 说明 |
|------|------|
| `CRAZYFLASHER7MercenaryEmpire.exe` | Guardian 主程序 (~118KB) |
| `miniaudio.dll` | 原生音频引擎 (WASAPI, ~770KB) |
| `ClearScript.Core.dll` | V8 引擎核心 |
| `ClearScript.V8.dll` | V8 managed 封装 |
| `ClearScript.V8.ICUData.dll` | V8 国际化数据 (~10MB) |
| `ClearScriptV8.win-x64.dll` | V8 原生引擎 (~22MB) |
| `Newtonsoft.Json.dll` | JSON 库 |
| `SharpDX.dll` | DirectX 核心 |
| `SharpDX.DXGI.dll` | DXGI 封装 |
| `SharpDX.Direct3D11.dll` | D3D11 封装 |
| `SharpDX.D3DCompiler.dll` | HLSL 编译器封装 |
| `Microsoft.Web.WebView2.Core.dll` | WebView2 托管核心 |
| `Microsoft.Web.WebView2.WinForms.dll` | WebView2 WinForms 控件 |
| `WebView2Loader.dll` | WebView2 原生加载器 |

### 单独编译 HotkeyGuard

```powershell
cd launcher/src/Guardian
csc /target:winexe /out:../../../hotkey_guard.exe HotkeyGuard.cs
```

### VS Code 任务配置 (可选)

在项目根目录创建 `.vscode/tasks.json`：

```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "Build Guardian",
      "type": "shell",
      "command": "powershell -File launcher/build.ps1",
      "group": { "kind": "build", "isDefault": true },
      "problemMatcher": "$msCompile"
    }
  ]
}
```

配置后按 `Ctrl+Shift+B` 即可构建。

## 运行时配置

项目根目录 `config.toml`：

```toml
flashPlayerPath = "Adobe Flash Player 20.exe"
swfPath = "CRAZYFLASHER7MercenaryEmpire.swf"

# GPU CAS 锐化（实验性，显示管线待完善）
gpuSharpening = false
sharpness = 0.5
```

## 关键设计决策

### Flash 嵌入 (SetParent)
Guardian 通过 Win32 `SetParent` 将 Flash Player SA 窗口嵌入 WinForms Panel，移除标题栏/边框/菜单栏。500ms 看门狗定时器检测全屏等操作导致的脱离并自动重新嵌入。

### 双通道通信
- **XMLSocket** (TCP, \0 分隔 JSON): Flash 原生支持，用于实时消息
- **HTTP API** (REST): 外部工具访问，支持 /console 命令队列 (5s 超时)

### 端口分配
从种子 `"1192433993"` 提取 4/5 位数子串作为候选端口，与 AS2 `ServerManager.as` 保持一致。运行时逐个测试可用性。

### 快捷键拦截
两层防御：
1. `SetMenu(NULL)` 移除 Flash 菜单栏（消除加速器快捷键，Ctrl+F/Q/W/O/P 从源头消失）
2. `hotkey_guard.exe` 独立进程 `WH_KEYBOARD_LL` 前台感知钩子：仅当 Guardian/Flash 在前台时拦截 Ctrl+F(全屏)/Ctrl+Q(退出)，不影响其他应用

### 原生音频引擎 (miniaudio)
音频播放从 Flash Sound API 完全迁移到 C# launcher 的 native DLL，Flash 侧仅发送播放指令。

**架构**：
- `miniaudio_bridge.c` → `miniaudio.dll`: 单文件 C 库，WASAPI shared mode，支持 play/stop/seek/peak
- `AudioEngine.cs`: P/Invoke 封装 (bgm_play/stop/seek/get_peak/get_cursor/get_length/is_playing)
- `AudioTask.cs`: BGM JSON handler (bgm_play/stop/vol/seek) + SFX 快车道批量解析
- `MusicCatalog.cs`: BGM 曲库管理，合并 bgm_list.xml + 文件系统自动发现 + FileSystemWatcher 热加载
- `DirectoryWatcherService.cs`: 通用文件监听服务（500ms 去抖，可复用于 mod/皮肤等场景）

**BGM 专辑系统**：`MusicCatalog` 启动时解析 `sounds/bgm_list.xml`（手工注册曲目）并扫描 `sounds/*/` 子目录发现未注册的音频文件（MP3/WAV/OGG/FLAC），按文件夹名归类为专辑。合并后的完整目录在 Flash 业务就绪后推送（`OnClientReady` 事件），热加载增量通过 `catalogUpdate` 推送。玩家只需在 `sounds/` 下新建文件夹投放音频，游戏运行中即可识别。详细说明见 `sounds/README.md`。

**BGM 优先级**：Flash 侧 `SoundEffectManager` 实现 3 级优先级状态机（stage > jukebox > scene），支持 override 模式（jukebox > stage > scene）。被高优先级抢占的 BGM 意图记录在 `_suppressedScene/_suppressedStage` 中，恢复时精确还原（含 album 模式和 loop 语义）。

**BGM**：双 `ma_sound` 实例 ping-pong crossfade。切换时旧曲淡出与新曲淡入重叠进行，基于 `ma_engine_get_time_in_milliseconds` 全局时钟调度。`stopBGM` 使用 `ma_sound_stop_with_fade_in_milliseconds`，操作两个槽位确保无残留。注意 miniaudio 的 base volume 与 fader 是相乘关系，crossfade 路径中 `ma_sound_set_volume` 必须设为 1.0（由 fader 独立控制 0→1 淡入）。Seek 使用 `ma_sound_seek_to_second()`（基于声源自身采样率换算，不依赖 engine sample rate）。

**BGM 可视化 + 点歌器**：`PeakDetector` 自定义节点（`ma_node_vtable` passthrough）插入 bgmGroup → engine endpoint 之间，实时采样 L/R peak。C# 60ms 轮询 `ma_bridge_bgm_get_peak/cursor/length/is_playing` → WebView2 `PostWebMessageAsJson` → `jukebox.js` 渲染滚动波形 + 进度条（可拖拽 seek）。点歌器面板含专辑浏览、选曲播放、设置菜单（覆盖关卡BGM / 真随机）和帮助按钮。曲目标题由 AS2 `pushUiState("bgm:title")` 经 UiData 通道推送，设置状态由 `jbo:/jbr:` 通道同步。

**SFX**：启动时扫描 `sounds/export/{武器,特效,人物}/` 目录，文件名即 linkageId，覆盖顺序武器→特效→人物（后覆盖前）。Flash 侧帧内累积，帧末由 FrameBroadcaster 合批发送 `S{id1}|{id2}|{id3}` 快车道消息。native 层 90ms 去重。

**路径编码**：所有字符串参数使用 `wchar_t*` (UTF-16)，文件操作用 `ma_sound_init_from_file_w()`，支持中文路径。

**音效资产**：由 `tools/export_sfx.py` 调用 FFDec CLI 从 SWF 批量导出并重命名为 linkageId，运行时无需 manifest 文件。

### 性能调度迁移 (PerfDecisionEngine)
原 AS2 端的完整反馈控制回路（Kalman 滤波→PID→迟滞量化→执行器，~1400 行）已迁移到 C# launcher 端。

**迁移依据**：PID 被数学证明退化为阈值生成器（Proposition 1, 97.4% 积分饱和率），迟滞量化器是实际控制权威。

**架构**：
- **C# PerfDecisionEngine** (~250 行): 滑动窗口统计(mean5/trend10) + 直接阈值 + 2/3 非对称迟滞确认 + 方差自适应
- **AS2 PerformanceScheduler** (~250 行，薄壳): 采样 + FPS 广播 + 接收 P 指令执行 + 本地后备
- **P 前缀快车道** (C#→AS2): `P{tier}|{softU_x100}\0`，零 JSON 解析
- **失焦抑制**: WindowManager.IsFlashForeground() 门控，先于 panic 判定
- **前馈 hold**: 关卡脚本 setPerformanceLevel() 可挂起远程模式 N 秒
- **断线后备**: AS2 极简阈值降级 (FPS<15→tier=1)；15 秒无样本自动触发 warmup

### GPU 锐化 (实验性, 当前禁用)
目标：Flash 以 LOW 画质渲染降低 CPU 负担，外部 GPU CAS 锐化补偿画质。

已验证可行：
- BitBlt 捕获 Flash 帧 (0/300 黑帧, avg 2ms, p95 4ms)
- D3D11 off-screen CAS 处理 + staging 回读

待解决：将 GPU 处理后的帧显示到用户可见的 WinForms 面板（WM_PAINT 覆盖 / airspace 问题）。
