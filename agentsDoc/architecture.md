# 项目技术架构总览

**文档角色**：系统拓扑 canonical doc。  
**最后核对代码基线**：commit `9f8f0c225`（2026-04-20）。

本项目当前应被理解为：**Flash 核心游戏 + Guardian Launcher Host + WebView2 UI + native / build tooling** 的本地多栈系统。

## 1. 总体分层

```
┌──────────────────────────────────────────────────────┐
│ Flash / AS2 Runtime                                 │
│ 主 SWF、子资源、帧脚本、org.flashNight.* 类库         │
└───────────────┬──────────────────────────────────────┘
                │ XMLSocket / HTTP / 本地文件 / 启动参数
┌───────────────▼──────────────────────────────────────┐
│ Guardian Launcher Host (C# / WinForms / .NET 4.6.2) │
│ 启动链路、TaskRegistry、音频、overlay 宿主、存档决议   │
└───────────────┬──────────────────────────────────────┘
                │ WebView2 postMessage / bridge
┌───────────────▼──────────────────────────────────────┐
│ Launcher Web UI                                     │
│ bootstrap、overlay、Panels、minigames、dev harness   │
└───────────────┬──────────────────────────────────────┘
                │ build / native boundary
┌───────────────▼──────────────────────────────────────┐
│ Tooling & Native                                    │
│ TypeScript/V8、Rust sol_parser、PowerShell、CLI      │
└──────────────────────────────────────────────────────┘
```

## 2. 五条核心链路

### A. Flash / AS2 运行时链

- 游戏核心逻辑、帧脚本、资源链接和 `_root` 级业务入口仍在 `scripts/` 与 Flash 资产中
- 子资源与主 SWF 共享运行时上下文，不以现代沙箱或模块系统隔离
- `_root`、MovieClip、帧驱动 FSM、XML 数据加载仍是核心工程现实
- 这条链的验证与构建依赖 Flash / JSFL / IDE 协同，不属于可直接命令行编译的普通脚本项目

### B. Flash CS6 编译与自动化 smoke 链

- 真实编译器仍是 Flash CS6 GUI
- 自动化 smoke 通过 `scripts/compile_test.ps1/.sh` → JSFL → `testMovie()` → `flashlog.txt` / `compile_output.txt` / `compiler_errors.txt`
- 这条链只提供 **smoke 级验证**，不能取代 IDE 人工复核，也不能把 `publish_done.marker` 当作最终成功依据
- 详细编译自动化细节由 `scripts/FlashCS6自动化编译.md` 负责

### C. Guardian Launcher Host 链

- `launcher/` 是当前运行时宿主，不再只是“附带工具”
- 关键职责：
  - 启动前 WebView2 预检与 BootstrapPanel
  - Flash Player SA 启动、预热、嵌入与 reveal
  - XMLSocket / HTTP 本地总线与 `TaskRegistry`
  - 音频系统、Notch / Toast / Web overlay 宿主
  - 启动前存档决议与 Protocol 2
- 当前存档 authority 边界：
  - valid legacy SOL 在 Resolver 命中 `Snapshot(source=sol)` 时，会被同步 seed 到当前运行根的 `saves/{slot}.json`
  - Bootstrap `list/load/load_raw` 只对标准 10 槽做 legacy 预热；自定义 legacy 槽不自动继承
  - `resources/` 与 `CrazyFlashNight/` 是两套物理隔离运行根；authority、legacy SOL 搜索和删除都不跨根
- `launcher/README.md` 是该子系统的 source of truth

### D. Launcher Web / Minigames / Overlay 链

- WebView2 前端已承担启动引导、运行态 overlay、Panel 系统和小游戏 UI
- 小游戏当前采用统一壳层与宿主协议：
  - 共享结构类：`minigame-*`
  - 共享宿主上报：`minigame_session`
  - 浏览器 harness + Node QA + 静态验证三层回归
- 这条链与 AS2 游戏核心并存，但职责不同：它是运行态 UI 层，不是替代游戏主逻辑的重写

### E. Native & Build 链

- `launcher/scripts/` 中的 TypeScript 编译为 V8 运行时代码
- `launcher/native/sol_parser/` 通过 Rust 生成 `sol_parser.dll`
- PowerShell 承担 Windows 环境下的启动、编译 smoke、CLI 和诊断自动化
- 这里的 Node / Rust 都属于**受控边界件**，不是独立应用栈；它们存在的理由是为现有运行时服务

## 3. 通信与边界

### Flash ↔ Launcher

- 主通道：XMLSocket（快车道前缀 + JSON 路由）
- 辅助通道：HTTP（端口发现、状态查询、日志与辅助接口）
- 注册中心：`launcher/src/Bus/TaskRegistry.cs`
- 集成测试入口：`--bus-only`
- 鼠标手型迁移边界：AS2 `_root.鼠标` 是脚本兼容代理，`cursor_control` 只传低频状态；真实 cursor 坐标由 Launcher 低级鼠标 hook / 坐标泵采样，视觉只由 C# `CursorOverlayForm` 原生 layered window 接管并按 monitor DPI 缩放；Web DOM 只通过 `cursorFeedback` 回传 hover/press 状态变化，不承担 cursor 视觉 fallback；AS2 仅在物品拖拽期间同步保留的图标容器。

### Save Authority Boundary

- Launcher authority 固定落在 `<projectRoot>/saves/`；哪个根启动 launcher，就只认哪个根的 authority
- legacy SOL 定位只在当前运行根对应的 SharedObject 子树内进行，探测顺序为 `.swf` → `.exe` → 当前根 root-scoped fallback
- `reset` / `rebuild` / legacy SOL 删除都只影响当前运行根，不承担跨根合并或恢复职责

### Launcher Host ↔ WebView2

- Bootstrap 阶段：`chrome.webview.postMessage({cmd, ...})`
- 运行态：Bridge / Panel / UiData / Notch / overlay 消息桥
- Minigame：统一 `minigame_session` envelope
- 性能诊断边界：运行态 Web overlay 可分别启用 `webOverlayDisableCssAnimations`、`webOverlayDisableVisualizers` 做 A/B；`webOverlayLowEffects` 是聚合保护开关，并额外降低 map panel 的全屏 scanline / radar / pulse、CSS filter/drop-shadow 与覆膜合成成本。`webView2DisableGpu` 同时作用于 BootstrapPanel 与运行态 WebOverlayForm，用于定位 WebView2 GPU 合成责任面，不作为默认运行方案。`nativeCursorOverlay=false` 只关闭 C# cursor layered window，恢复系统鼠标，用于隔离 cursor 迁移与 WebView2 overlay 满载。双显卡调度通过 `tools/set-launcher-gpu-preference.ps1` 管理 Windows 每应用高性能 GPU 偏好；运行态采样用 `tools/sample-launcher-gpu.ps1` 按 launcher / flash / bootstrap / web_overlay 分组读取 GPU engine；静态复杂度审计用 `tools/audit-web-overlay-complexity.js` 统计 overlay CSS / JS 中的合成与布局风险点。GPU 偏好只能影响系统调度意愿，不能保证无 MUX 笔记本的最终桌面合成绕过核显。
- WebView2 user-data 边界：BootstrapPanel 与运行态 WebOverlayForm 使用不同 user-data 目录，避免诊断参数改变 WebView2 browser process group 后互相破坏初始化。BootstrapPanel 在 reveal 后隐藏时请求 WebView2 suspend，避免启动页在游戏态继续占 GPU。

### 文档边界

- 本文只讲系统拓扑与链路分层
- 协议明细、构建细节、测试矩阵、治理规则分别由：
  - `launcher/README.md`
  - `agentsDoc/testing-guide.md`
  - `agentsDoc/documentation-governance.md`
  - `docs/tech-stack-rationalization.md`

## 4. 当前架构结论

- 当前工程是一个必须接受 Flash 物理约束、同时由多条宿主与工具链围绕的本地多栈系统
- 入口文档应只陈述这一现实；技术栈演进判断统一下沉到 `docs/tech-stack-rationalization.md`

后续治理重点应放在：

- 文档 truth source 明确化
- 子栈边界收敛
- 验证矩阵标准化
- 入口页与深文档职责分离
