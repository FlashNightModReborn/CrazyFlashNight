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
        ├─ 快车道 (前缀协议) ──────────────────────┐
        │  'F' → FrameTask.HandleRaw(cam,hn,fps)  │
        │  'R' → FrameTask.HandleReset()           │
        │  'S' → AudioTask.HandleSfxFastLane()     │
        │  'N' → INotchSink.AddNotice(通知)        │
        │  'W' → INotchSink.SetStatusItem(波次)    │
        │  'U' → WebView2 UiData 透传              │
        │  'D' → FrameTask.LoadInputModule(DFA)    │
        │  'P' → AS2 applyFromLauncher(C#→AS2)     │
        │  (绕过 JSON 解析，零 GC 分配)             │
        ├──────────────────────────────────────────┘
        │
   ┌────┴──────────────────────────┴──┐
   │    MessageRouter (JSON 路由)     │
   │  ┌────────────────────────────┐  │
   │  │  toast (sync, fire&forget) │  │
   │  │  audio (sync, fire&forget) │  │
   │  │  gomoku_eval (async)       │  │
   │  │  → rapfi engine            │  │
   │  │  data_query (async)        │  │
   │  │  → NPC/佣兵数据查询        │  │
   │  │  shop_response (async)     │  │
   │  │  → ShopTask 面板桥接       │  │
   │  │  archive (async)           │  │
   │  │  → 存档shadow备份/读取     │  │
   │  │  cmd (sync) C#↔AS2 命令    │  │
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
│   │   └── KeyboardHook.cs                进程内低级键盘钩子 (ESC 面板路由 + 全屏切换)
│   ├── Bus/
│   │   ├── XmlSocketServer.cs             TCP 服务器（快车道前缀 + JSON 双通道 + TrySend/OnClientDisconnected）
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
│   │   ├── FrameTask.cs                   帧数据处理（快车道 HandleRaw + JSON 回退 + 搓招输入）
│   │   ├── GomokuTask.cs                  五子棋 AI (外部 rapfi 引擎, async)
│   │   ├── DataQueryTask.cs               NPC/佣兵数据查询 (async, XML 缓存)
│   │   ├── ToastTask.cs                   UI toast 通知 (fire-and-forget)
│   │   ├── ShopTask.cs                    K点商城桥接 (Web callId↔Flash callId 双层映射, 10s 超时)
│   │   └── ArchiveTask.cs                 存档shadow备份/读取 (async, 一致性校验)
│   ├── V8/
│   │   └── V8Runtime.cs                   ClearScript V8 运行时（伤害数字渲染 + 搓招 DFA）
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
│   ├── overlay.html                       DOM 结构 (Toast + Notch + 工具条 + Panel 容器 + Tooltip)
│   ├── css/
│   │   ├── overlay.css                    Notch/Toast/Jukebox 等样式 + 动效
│   │   └── panels.css                     面板系统样式 (Cyberpunk 2077 风格, 商城+帮助)
│   ├── lib/
│   │   └── marked.min.js                  Markdown→HTML 渲染器 (MIT, ~40KB min)
│   ├── icons/                             物品图标资源 (2199 PNG, ~53MB)
│   │   ├── manifest.json                  图标名→文件名映射
│   │   └── *.png                          图标图片
│   ├── help/                              游戏帮助 Markdown 源文件
│   │   ├── controls.md                    基本操作
│   │   ├── worldview.md                   世界观
│   │   └── easter-eggs.md                 彩蛋内容
│   └── modules/
│       ├── bridge.js                      C# ↔ JS 消息桥
│       ├── uidata.js                      帧同步 UI 状态分发 (KV 格式 + 旧格式兼容)
│       ├── toast.js                       Toast 消息 (Flash HTML 白名单过滤)
│       ├── sparkline.js                   FPS 折线图渲染 (DPR 感知, LOD)
│       ├── notch.js                       Notch UI (FPS/sparkline/clock/toolbar/任务通知/存盘/安全退出)
│       ├── currency.js                    经济面板 (金钱/K点 动画)
│       ├── combo.js                       搓招连击显示 (飞出动效)
│       ├── jukebox.js                     BGM 点歌器 (专辑浏览/选曲/波形/seek/暂停/设置/帮助)
│       ├── panels.js                      通用面板生命周期管理器 (register/open/close/ESC)
│       ├── tooltip.js                     通用面板 Tooltip (hover/anchored 两种模式, AS2 HTML 转换)
│       ├── icons.js                       图标 manifest 加载与解析
│       ├── kshop.js                       K点商城面板 (商品/购物车/领取/Flash 桥接)
│       └── help-panel.js                  游戏帮助面板 (Markdown tab 切换, Panel 系统)
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
- **HTTP API** (REST): 外部工具访问，支持 /console 命令队列 (5s 超时)、/save-push 存档推送、/task 通用 httpCallable 路由

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

### 存档 Shadow 备份 (ArchiveTask)
Flash `SaveManager` 存盘后，将 mydata JSON 副本推送到 Launcher 落盘（`saves/` 目录）。SOL 仍是权威源，Launcher 做 shadow 备份并进行语义级一致性校验。

**协议**：
- `shadow`: Flash→C#，携带 slot + data，落盘为 `saves/{slot}.json`
- `load`: Flash→C#，按 slot 读取 shadow 副本返回
- `list`: 列出所有 shadow 存档

**HTTP `/save-push`**：C#→Flash 方向，从 `saves/` 读取指定 slot 的 JSON 并通过 XMLSocket 推送到 AS2（`save_push` task），用于启动时恢复。

### 进程生命周期加固
- **shutdown try-catch 保护**：每个 Dispose 步骤独立 try-catch，防止单点异常跳过后续清理
- **Flash 僵尸进程检测**：Socket 断连后 10s 内进程仍未退出则 ForceExit（Flash Player 20 SA 偶发退出卡死）
- **OnKillFlash 钩子**：退出前先 DetachFlash + AudioEngine.Shutdown + KillFlash，在 ExitThread 之前执行
- **ProcessManager 线程安全**：`_flashProcess` 访问加锁，`KillFlash()` 可多次安全调用
- **AppDomain.UnhandledException**：非 UI 线程未处理异常写日志

### GPU 锐化 (实验性, 当前禁用)
目标：Flash 以 LOW 画质渲染降低 CPU 负担，外部 GPU CAS 锐化补偿画质。

已验证可行：
- BitBlt 捕获 Flash 帧 (0/300 黑帧, avg 2ms, p95 4ms)
- D3D11 off-screen CAS 处理 + staging 回读

待解决：将 GPU 处理后的帧显示到用户可见的 WinForms 面板（WM_PAINT 覆盖 / airspace 问题）。

### Flash UI → Web 迁移

以下 Flash 主文件实例已迁移到 Launcher WebView2 overlay，释放 Flash 内存并提高 GC 效率：

| Flash 实例 | Web 实现 | 协议 |
|-----------|---------|------|
| 弹出公告界面 (新任务横幅) | notch.js 通知条 `#quest-notice-bar` | `Utask\|{name}` (旧格式透传) |
| 弹出公告界面 (公告) | notch.js 通知条 | `Uannounce\|{text}` (旧格式透传) |
| 任务完成提示 | notch.js 通知条完成态 (❗ 图标呼吸 + 可点击) | `td:0/1` (KV 帧同步) |
| 功能按钮界面 (装备/任务) | `#quest-row` 工具条按钮行 | `cmd` gameCommand |
| 存盘动画 | ✕ 按钮状态变化 (·· → ✓) | `sv:1/2` (KV 帧同步) |
| 安全退出界面 | `#safe-exit-panel` 面板 | `sv:1/2` + `EXIT_CONFIRM` click |
| 帮助界面 (帮助界面.swf) | Panel 系统 `help-panel.js` (Markdown tab) | Bridge → C# panel_cmd open help |
| K点商城 (商城界面 MC) | Panel 系统 `kshop.js` (商品/购物车/领取) | ShopTask 双层 callId 桥接 (Web↔Flash) |

**右上角工具条布局**：
```
┌──────────────────────┐
│ ⚙  🔧  ⏸  ?  ✕      │  ← #top-right-tools
├──────────────────────┤
│ ☰ 装备  │  ☰ 任务   │  ← #quest-row (游戏中常驻)
├──────────────────────┤
│ [❗] 任务已达成·交付  │  ← #quest-notice-bar (动态)
├──────────────────────┤
│ ♪ 点歌  未播放        │  ← #jukebox-panel
└──────────────────────┘
```

**通知条状态机**：隐藏 → (新任务/公告到达) → 播放通知 → (队列空+td:1) → 完成态常驻 → (td:0) → 隐藏。完成态图标持续呼吸脉冲 (`icon-breathe`)，可点击跳转地图交付。

### 面板系统 (Panel System)

全屏遮罩面板框架，用于承载需要独占交互的复杂 UI（商城、帮助等），取代 Flash MovieClip 弹窗。

**架构**：
```
按钮点击 (SHOP/HELP)
    ↓
C# HandleButtonClick → 设置 _activePanel → PostToWeb panel_cmd open
    ↓
JS Panels.open(id) → 创建/显示面板 DOM → 遮罩 + ESC 支持
    ↓ (ESC)
C# KeyboardHook._panelEscEnabled → PostToWeb panel_esc → Panels.triggerRequestClose
    ↓ (关闭)
JS Bridge.send({cmd:'close', panel:id}) → C# HandlePanelMessage → 按面板 ID 路由
```

**面板类型**：
- **kshop** (K点商城): 需要 Flash 交互 (shopPanelOpen/Close 暂停控制, ShopTask 异步桥接)
- **help** (游戏帮助): 纯 Web 侧，无 Flash 交互，不暂停游戏

**通用模块**：
- `panels.js`: 面板注册/生命周期管理 (register/open/close/force_close)
- `tooltip.js`: hover 跟随 + anchored 锚定两种模式，AS2 HTML 转换
- `icons.js`: 物品图标 manifest 加载 + 名称→URL 解析

**状态机 (_activePanel)**：`null` → `"kshop"/"help"` → `null`。断连时仅对 `kshop` 设 `_pauseNeedsRestore`，help 面板不触发 Flash 暂停恢复。

**热重载恢复**：`_uiDataSnapshot` 按 KV key 维护最新值快照，WebView2 热重载后 `FlushUiDataBuffer` 先回放完整快照，确保 game-ready 等关键状态不丢失。
