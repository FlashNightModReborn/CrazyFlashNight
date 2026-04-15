# Phase 1 owner / 退出状态图

P3b Phase 1 接管后各资源/生命周期的 owner 矩阵。reviewer 勾选确认用。

## 切 ApplicationContext 后 owner 矩阵

| 资源 | Phase 0 owner | Phase 1 owner | 迁移确认点 |
|---|---|---|---|
| 消息循环 | `Application.Run(form)` | `Application.Run(ctx)` | [Program.cs](../src/Program.cs) 正常模式末尾 |
| BootstrapForm 生命周期 | n/a | ctx.MainForm；Ready 时 `HideForReady()` 不 Close | [GuardianContext.cs](../src/Guardian/GuardianContext.cs) |
| GuardianForm 生命周期 | 消息循环直接持有 | ctx 持有；Bootstrap 期不 Show，Ready 才 Show | GameLaunchFlow.TransitionToReady |
| TrayIcon | 构造期 `Visible=true` | 初始 `Visible=false`；`ShowTrayIcon()` 在 readyWiring 触发 | [GuardianForm.cs](../src/Guardian/GuardianForm.cs) SetupTrayIcon |
| WebOverlayForm / InputShieldForm | Program.cs 局部 | 同；`SetReady()` 由 readyWiring 触发 | Program.cs readyWiring delegate |
| `processManager.Start()` | Program.cs 直调 | `GameLaunchFlow.TransitionToSpawning` | [GameLaunchFlow.cs](../src/Guardian/GameLaunchFlow.cs) |
| `windowManager.EmbedFlashWindow` | Program.cs ThreadPool | `GameLaunchFlow.TransitionToEmbedding` (ThreadPool) | GameLaunchFlow.TransitionToEmbedding |
| `form.Show + Activate + SetReady` | Program.cs ThreadPool 包块 | `GameLaunchFlow.TransitionToReady` | GameLaunchFlow.TransitionToReady |
| ExitGuard 8s 强杀 | `GuardianForm.DoExit` 启动 | 同（ctx 路径必经 guard.ForceExit → DoExit） | GuardianContext.cs FormClosed handler |
| ProcessManager.KillFlash | `form.OnKillFlash` 注入 | 同；GameLaunchFlow Reset 也可主动调 | Program.cs OnKillFlash delegate |
| WindowManager.DetachFlash | 同上 | 同上 | 同上 |
| AudioEngine.Shutdown | 同上 | 同上 | 同上 |
| socketServer / httpServer | Program.cs main 末尾 Dispose | 同；ctx 退出后执行 | Program.cs 末尾 |
| `bootstrap_handshake` / `bootstrap_ready` router 注册 | 无（spike lambda） | GameLaunchFlow 构造器 | GameLaunchFlow ctor |

## 退出路径

所有触发源最终进 `guard.ForceExit → DoExit → (ExitGuard 8s) → OnShutdownEarly → OnKillFlash → Application.ExitThread`。

```
触发源
├── Ctrl+Q / Alt+F4 / 关闭按钮 (GuardianForm)    → ForceExit
├── 托盘"退出"菜单项                              → ForceExit
├── Notch Overlay 工具栏退出按钮                  → ForceExit
├── HttpServer shutdown 请求                     → ForceExit
├── Flash 进程自然退出 (ProcessManager.OnFlashExited) → form.ForceExit (activative 状态由 GameLaunchFlow 拦截进 Error)
├── Socket zombie 10s 兜底 Timer                → ForceExit
├── BootstrapForm Alt+F4 / 关闭                 → close-policy 检查 → 允许退出时 → guard.ForceExit (ctx FormClosed handler)
└── Steam ownership / 文件缺失                  → return 1 (早退, 不经 ctx)

ForceExit → DoExit
├── ExitGuard 后台线程 8s Environment.Exit(1) 保险
├── OnShutdownEarly (frameTask.Stop + fast-path 断)
├── OnKillFlash (DetachFlash + AudioShutdown + KillFlash)
├── CleanupTrayIcon
└── Application.ExitThread
```

## close-policy 表

BootstrapForm 当前状态决定 Alt+F4 / X 按钮是否放行。

| 状态 | Alt+F4 / X | 实现 |
|---|---|---|
| Idle | 允许退出 | FormClosing 不拦截；ctx 正常退出 |
| Spawning / WaitingConnect / WaitingHandshake / Embedding / WaitingGameReady | 拦截 + MessageBox "启动中,请等待完成或点重置" | BootstrapForm.OnFormClosingGuard `e.Cancel=true` |
| Resetting | 拦截 + "重置中,请稍候" | 同上 |
| Ready | n/a (已 Hide) | — |
| Error | 允许退出 | 同 Idle |

## WebView2 硬依赖

Phase 1 强制要求 WebView2 Runtime 可用。启动时预检 `CoreWebView2Environment.GetAvailableBrowserVersionString()`；失败弹 MessageBox + `return 1`。`--force-webview-fail` 启动开关用于测试场景 40。

## reviewer 勾选

- [x] owner 矩阵每行已核对对应代码位置
- [x] 退出路径所有分支经 ExitGuard 保险（BootstrapForm.FormClosed 走 guard.ForceExit）
- [x] close-policy 表六状态在 BootstrapForm.OnFormClosingGuard 实装
- [x] WebView2 预检在 Run() 入口前置；`--force-webview-fail` 生效
- [x] TrayIcon 初始 Visible=false，readyWiring 中 `form.ShowTrayIcon()` 触发
- [ ] ExitGuard 覆盖测试 (`OnShutdownEarly` 注入 10s sleep 验证 8s Environment.Exit(1) 仍生效) — **待 11b-β 收尾**
