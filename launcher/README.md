# CF7:ME Guardian Launcher

C# WinForms 守护进程，替代旧 Node.js Local Server，负责启动并嵌入 Flash Player SA、提供 V8 脚本总线和 HTTP/XMLSocket 通信。

## 技术栈

| 项目 | 版本/说明 |
|------|-----------|
| 运行时 | .NET Framework 4.5, x64 |
| 语言 | C# 5 |
| UI | WinForms (WinExe) |
| 构建 | MSBuild 4.0 + NuGet (packages.config) |
| JS 引擎 | ClearScript 7.4.5 (Chromium V8, 替代 Node.js vm2) |
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
   │\0-JSON  │               │  REST/JSON │
   └────┬────┘               └─────┬──────┘
        │                          │
   ┌────┴──────────────────────────┴──┐
   │         MessageRouter            │
   │  ┌──────┬───────┬─────────────┐  │
   │  │ eval │ regex │ computation │  │
   │  │ (V8) │ (V8)  │   (C#)     │  │
   │  ├──────┴───────┴─────────────┤  │
   │  │      gomoku_eval (async)   │  │
   │  │      → rapfi engine        │  │
   │  └────────────────────────────┘  │
   └──────────────────────────────────┘

   hotkey_guard.exe  ← 独立进程，低级键盘钩子
   (接收 Guardian PID, 拦截 Ctrl+Q/W/R/F/P/O)
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
│   │   ├── LogManager.cs                  线程安全日志 → TextBox
│   │   ├── HotkeyGuard.cs                 独立进程：WH_KEYBOARD_LL 钩子
│   │   └── KeyboardHook.cs                (已弃用)
│   ├── Bus/
│   │   ├── XmlSocketServer.cs             TCP \0-JSON (Flash XMLSocket 协议)
│   │   ├── HttpApiServer.cs               HTTP REST (/console, /logBatch 等)
│   │   ├── MessageRouter.cs               task 字段路由 → sync/async handler
│   │   ├── PortAllocator.cs               种子 "1192433993" 确定性端口分配
│   │   └── FlashPolicyHandler.cs          Flash 跨域策略
│   ├── Tasks/
│   │   ├── EvalTask.cs                    V8 eval 沙箱 (1s 超时)
│   │   ├── RegexTask.cs                   V8 JS 正则匹配
│   │   ├── ComputationTask.cs             数组求和
│   │   └── GomokuTask.cs                  五子棋 AI (外部 rapfi 引擎)
│   └── Render/                            GPU 锐化 (实验性，当前禁用)
│       ├── GpuRenderer.cs                 D3D11 off-screen CAS 处理
│       ├── CasShaderBytecode.cs           HLSL CAS 着色器
│       ├── D3DPanel.cs                    双缓冲显示面板
│       └── RenderNativeMethods.cs         PrintWindow/BitBlt P/Invoke
├── bin/Release/                           编译输出
├── packages/                              NuGet 包缓存
└── tools/
    └── nuget.exe                          NuGet CLI
```

## 在 VS Code 中构建

### 前置条件

- Windows 系统，已安装 .NET Framework 4.5+ (系统自带)
- MSBuild: `C:\Windows\Microsoft.NET\Framework64\v4.0.30319\msbuild.exe` (系统自带)
- 终端使用 PowerShell 或 Git Bash

### 一键构建

```powershell
cd launcher
powershell -File build.ps1
```

构建流程：
1. `nuget restore` — 恢复 NuGet 包 (ClearScript, Newtonsoft.Json, SharpDX)
2. `msbuild /p:Configuration=Release` — 编译 C# 项目
3. 复制产物 (exe + 8 DLL) 到项目根目录
4. 复制 V8 原生 DLL 到项目根目录

### 产物

构建完成后，以下文件被部署到项目根目录：

| 文件 | 说明 |
|------|------|
| `CRAZYFLASHER7MercenaryEmpire.exe` | Guardian 主程序 (~84KB) |
| `ClearScript.Core.dll` | V8 引擎核心 |
| `ClearScript.V8.dll` | V8 managed 封装 |
| `ClearScript.V8.ICUData.dll` | V8 国际化数据 (~10MB) |
| `ClearScriptV8.win-x64.dll` | V8 原生引擎 (~22MB) |
| `Newtonsoft.Json.dll` | JSON 库 |
| `SharpDX.dll` | DirectX 核心 |
| `SharpDX.DXGI.dll` | DXGI 封装 |
| `SharpDX.Direct3D11.dll` | D3D11 封装 |
| `SharpDX.D3DCompiler.dll` | HLSL 编译器封装 |

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
三层防御：
1. `SetMenu(NULL)` 移除 Flash 菜单栏（消除加速器快捷键）
2. `RegisterHotKey` 注册 Ctrl+F(全屏)/Ctrl+Q(退出)
3. `hotkey_guard.exe` 独立进程 WH_KEYBOARD_LL 钩子拦截 Ctrl+Q/W/R/F/P/O

### GPU 锐化 (实验性, 当前禁用)
目标：Flash 以 LOW 画质渲染降低 CPU 负担，外部 GPU CAS 锐化补偿画质。

已验证可行：
- BitBlt 捕获 Flash 帧 (0/300 黑帧, avg 2ms, p95 4ms)
- D3D11 off-screen CAS 处理 + staging 回读

待解决：将 GPU 处理后的帧显示到用户可见的 WinForms 面板（WM_PAINT 覆盖 / airspace 问题）。
