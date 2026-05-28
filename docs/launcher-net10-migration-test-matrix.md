# Launcher .NET 10 迁移 — 三层验收矩阵

立项：2026-05-28 / Worktree：`E:\wt\cf7n10`（branch `worktree-launcher-net10-migration`）

## 三层定义

- **自动层 (auto)**：纯命令行能验证，CI 友好（编译、单元测试、文件存在性 / 内容校验）
- **半自动层 (semi)**：需要启动进程或解析日志，agent 可执行但需人工读判定的细节
- **人力层 (manual)**：必须人坐在桌前看 UI / 听音 / 拍快门、对手感、感知卡顿

## Phase × 验收层 矩阵

| Phase | 自动层 | 半自动层 | 人力层 | Claude 评 | Kimi 评 |
|-------|--------|----------|--------|-----------|---------|
| 1. 删 GpuRenderer 死代码 | ✅ MSBuild Release 0 error；`grep GpuRenderer launcher/src` = 空 | ✅ `launcher/tests/run_tests.ps1` 550/550 PASS | 📋 plain Panel 丢 `TabStop=true` + `IsInputKey` override：reveal 后键盘焦点 smoke-test（Flash HWND 自管焦点，预期 benign） | ✅ LGTM | ✅ APPROVED |
| 2. SDK-style csproj + net10 + PackageReference | ✅ `dotnet restore` + `dotnet build -c Release` 全绿，0 error；launcher csproj 从 188 行缩到 33 行；tests csproj 从 109 行缩到 39 行；`global.json` + `Directory.Packages.props` 存在 | ✅ `dotnet test` 跑 Launcher.Tests on net10.0：550/550 PASS（与 net462 baseline 一致） | n/a（编译目标变更，不动业务逻辑） | ⚠️ warnings-only（详见 commit） | ⏭️ kimi unreachable this phase（超 3min 无输出，按 fail-fast §7） |
| 3. SharpDX.DXGI → Vortice.DXGI | ✅ `dotnet build -c Release` 全绿，0 error；`grep -r "SharpDX" launcher/src` = 空；只新增 `Vortice.DXGI` 1 个包；HasDiscreteGpu 1:1 翻译（38 行 vs 原 40 行，远低于 5 行差异预算） | ✅ `dotnet test` 550/550 PASS；agent 不动 launcher.exe 启动 | 真机切换 mode=auto / on / off 看 `HKCU\Software\Microsoft\DirectX\UserGpuPreferences` 写入/清理；笔记本电池 vs AC 切换 auto 行为 | ✅ self-review | ⏭️ kimi unreachable this phase（>3min 无输出，按 fail-fast §7） |
| 4. build.ps1 → dotnet publish | ✅ `launcher/build.ps1` 端到端零 exit（TS→native miniaudio→sol_parser→dotnet publish FDD→copy→verify gate）；发布形态为 native bootstrap + `runtime/` Core apphost 与依赖，FDD 输出约 36.7MB / 21 文件；Step 6c save_repair_dict 校验仍通过；路径修复不再依赖 `Assembly.Location` 推断项目根 | ✅ projectRoot 拷贝清单：`CRAZYFLASHER7MercenaryEmpire.exe` bootstrap + `runtime/CRAZYFLASHER7MercenaryEmpire.Core.exe` + managed/native deps + bundled runtime installer；`launcher/tests/run_tests.ps1`：550/550 PASS | 真机缺 runtime 场景需验证 bootstrap installer/UAC 与 `logs/bootstrap.log` | ✅ self-review | ⏭️ kimi unreachable this phase（连续 3 次启动 >3min 无输出，按 fail-fast §7） |
| 5. pack.config root-files 瘦身 | ✅ `npm --prefix tools/cf7-packer run pack:dry-run`：root-files 保持根目录用户入口与游戏资产，FDD 依赖进入 `launcher-runtime`，installer 进入 `runtime-installer` | ✅ pack:dry-run 整体出 4883 文件（root-files 10 + launcher-runtime 20 + runtime-installer 1 + launcher-web 2742 + root-dirs 24 + 其他 layer），无 collector error；FDD runtime 约 36.7MB，installer 约 58MB | 出包→解压→双击运行可启动 launcher，进游戏热路径玩到一关结束（**人力验**，agent 不动 .exe） | ✅ self-review | ⏭️ kimi unreachable this session（按 fail-fast §7 全程降级） |

## 端到端跨 Phase 校验（agent 跑完所有 phase 后 + 用户回来前）

| 检查 | 层 | 期望 |
|------|-----|------|
| `dotnet build -c Release` 0 error | 自动 | 净（warning 见下方「已知 warning 清单」，全是 pre-existing 或 intentional） |
| `dotnet test` 全 PASS | 自动 | 550 / 550，与 net462 baseline 一致 |
| `launcher/build.ps1` 完整跑（含 native / TS / sol_parser / dotnet publish / verify gate）零 exit | 自动 | 终态 = projectRoot 出 native bootstrap `CRAZYFLASHER7MercenaryEmpire.exe` + `runtime/CRAZYFLASHER7MercenaryEmpire.Core.exe` + Core FDD 依赖（约 36.7MB / 21 文件） |
| `git diff main..worktree-launcher-net10-migration --stat` | 自动 | 5 个 atomic commit + 1 docs commit，主要 churn = csproj / build.ps1 / pack.config / GpuRenderer 系列 / GpuPreferenceManager |
| `tools/cf7-packer pack:dry-run` layer 统计 | 自动 | root-files 10、launcher-runtime 20、runtime-installer 1、launcher-web 2742；整体 4883 文件，无 collector error |
| **人力层全列表**（写在 `docs/launcher-net10-migration-status.md` 末尾） | 人力 | — |

### 已知 warning 清单（dotnet build / dotnet publish 时会 emit，不影响 0 error）

| Code | 来源 | 性质 |
|------|------|------|
| `CS0162` | `CursorOverlayForm.cs` / `DesktopCursorOverlay.cs` 中 condition 永远 false 的不可达分支 | **pre-existing**（net462 时代就有），跟本次迁移无关 |
| `CS0169` / `CS0067` | `FrameTask._inputPayloadLogged` / `MapHudWidget.AnimationStateChanged` / `SafeExitPanelWidget.AnimationStateChanged` 未使用字段/事件 | **pre-existing**，跟本次迁移无关 |
| `SYSLIB0014` | `FontPackTask.cs` 用 `WebRequest`/`ServicePointManager`（已 obsolete） | **pre-existing**，需独立 PR 切到 `HttpClient` |
| `WFO0003` | `app.manifest` 写 DPI 设置，WinForms 6+ 推荐改用 `Application.SetHighDpiMode` API | net10 升级**新增**，info-only，留给后续 cleanup |
| `MSB3277` | `WindowsBase 4.0` vs `5.0` transitive 冲突（WebView2 net5.0 WPF dll 引 5.0） | net10 升级**新增**，info-only，dotnet 自动选 4.0 |
| `xUnit2013` 等 analyzer | 测试代码用 `Assert.Equal()` 检查集合 size（推荐 `Assert.Single`） | net10 升级**新增**，xunit 2.4.2 → 2.9.2 analyzer 包扩大覆盖，留给后续 cleanup |
| `IL3000` | 已**全部修复**（Phase 4 commit `d100e5fa5`）：5 处 `Assembly.Location` → `Environment.ProcessPath` / `AppContext.BaseDirectory` | — |
| `CA1416` | platform-compat：项目 TFM=`net10.0-windows` 已显式 Windows-only | `<NoWarn>CA1416</NoWarn>` 显式压住 |

## 人力验收待办（agent 不动 .exe，等用户回来）

> 全屏 / 窗口 / 工具栏 / 启动画面 / WebView2 overlay / Flash 嵌入 / 音频 / 输入 / 存档读写 / 五子棋 / 锁盒 / 对位 / 战斗热路径 / 长会话稳定性 — 逐项核对一遍。具体清单在 phase 5 完成后由 agent 在 `docs/launcher-net10-migration-status.md` 末尾追加，附「为什么这一项需要人验」。

## Reviewer 评级填写规则

每个 phase 后 agent 在「Claude 评」/「Kimi 评」列填：
- ✅ LGTM
- ⚠️ warning (commit message 留痕)
- 🔴 critical (修复后再 commit)
- ⏭️ 跳过（如 kimi 超时按 fail-fast §7）
- 📋 已知项（双方都 warning 但已记录到 commit）
