# Launcher .NET 10 迁移 — 最终状态报告

立项：2026-05-28 / 完工：2026-05-28 同日 / Worktree：`E:\wt\cf7n10` / Branch：`worktree-launcher-net10-migration`

## 5 个 atomic commit

| # | SHA | Title |
|---|-----|-------|
| 1 | `b5dd3335f` | launcher: remove unused GpuRenderer D3D11 spike (Phase 1 of net10 migration) |
| 2 | `263d0141d` | launcher: migrate csproj to SDK-style net10.0-windows + PackageReference (Phase 2) |
| 3 | `b487c2767` | launcher: replace SharpDX.DXGI with Vortice.DXGI for GPU detection (Phase 3) |
| 4 | `d100e5fa5` | launcher/build.ps1: use dotnet publish --self-contained instead of manual DLL copy (Phase 4) |
| 5 | `1bf537bb8` | pack.config: shrink root-files after launcher single-file publish (Phase 5) |

净改动：`git diff main..HEAD --stat` 显示 1352 行新增 / 2810 行删除（含 4 个 GpuRenderer 死代码 .cs 文件 + 12 个 dead binary + 2 个 packages.config 删除；csproj/build.ps1/run_tests.ps1 重写）。

## 终态产物（用户回来检查清单）

| 文件 | 状态 |
|------|------|
| `launcher/CRAZYFLASHER7MercenaryEmpire.csproj` | SDK-style，net10.0-windows，33 行（原 188） |
| `launcher/Directory.Packages.props` | 中心化 PackageVersion 锁定 |
| `global.json` | repo root SDK 10.0.300 pin，rollForward=latestFeature |
| `launcher/tests/Launcher.Tests.csproj` | SDK-style，net10，39 行（原 109） |
| `launcher/build.ps1` | dotnet publish FDD + native bootstrap + runtime/ 复制与 verify gate |
| `launcher/tests/run_tests.ps1` | `dotnet test`，39 行（原 86） |
| `launcher/src/Config/GpuPreferenceManager.cs` | SharpDX.DXGI → Vortice.DXGI |
| `launcher/src/{Program,Guardian/GuardianForm,Guardian/WebOverlayForm}.cs` | FDD/runtime 子目录路径修复：入口路径用 `Environment.ProcessPath`，根目录资产显式走 `projectRoot` |
| `tools/cf7-packer/pack.config.yaml` | root-files 瘦身，并新增 `launcher-runtime` / `runtime-installer` 层 |
| `CRAZYFLASHER7MercenaryEmpire.exe` | native bootstrap（约 260KB，含 app.ico），负责 runtime 检测、日志与启动 `runtime/Core.exe` |
| `runtime/` | FDD Core apphost + managed/native deps（约 36.7MB / 21 文件） |

## 自动化层 — 已通过

| 检查 | 结果 |
|------|------|
| `dotnet restore` + `dotnet build -c Release` 主项目 | ✅ 0 error |
| `dotnet restore` + `dotnet build -c Release` tests 项目 | ✅ 0 error |
| `dotnet test` Launcher.Tests on net10.0 | ✅ 550/550 PASS |
| `launcher/build.ps1` 端到端 | ✅ 零 exit（TS / native miniaudio / sol_parser Rust / dotnet publish / 6 步 verify gate 全过） |
| `launcher/tests/run_tests.ps1` | ✅ 550/550 PASS（新 dotnet test 路径） |
| `tools/cf7-packer/pack:dry-run` | ✅ 4883 文件，`root-files` 10 + `launcher-runtime` 20 + `runtime-installer` 1 + `launcher-web` 2742，无 collector error |
| `grep -r "SharpDX" launcher/src` | ✅ 空 |
| `grep -r "GpuRenderer\|D3DPanel\|CasShader" launcher/src` | ✅ 空 |
| MSBuild Release（Phase 1 之后过渡态） | ✅ 0 error（Phase 2 之后弃用，改 dotnet build） |

## 半自动化层 — 已尝试

| 检查 | 结果 | 备注 |
|------|------|------|
| dotnet publish 输出验证 | ✅ | FDD 输出约 36.7MB / 21 文件，托管与 native 依赖位于 `runtime/` |
| publish 后 projectRoot 内容 | ✅ | 根目录 bootstrap + `runtime/` Core 运行时 + hotkey_guard.exe + Flash Player + SWF/bat/configs |
| save_repair_dict.json 与源头一致校验（cf7-save-repair-dict-build verify） | ✅ | npm run verify 退 0 |
| launcher/web 运行时资产清单（76 项） | ✅ | 全部存在 |
| launcher/data 运行时资产清单（map_hud_data / save_repair_dict / save_schema） | ✅ | 3 项全存在 |
| native cursor canvas 契约校验 | ✅ | 6 states, 64x64, hotspot=16,16 |
| Vortice.DXGI restore | ✅ | 3.6.2 net10.0 兼容 |

## 人力验收待办（**agent 不动 launcher.exe**，等用户回来）

### 阻塞性 — 必验

| 项 | 为什么需要人力 |
|----|----------------|
| 双击 `CRAZYFLASHER7MercenaryEmpire.exe` 能从 BootstrapPanel 启动到 GuardianForm | bootstrap 先检测 .NET 10 Windows Desktop Runtime；缺失时拉起 bundled installer，已安装时转发到 `runtime/CRAZYFLASHER7MercenaryEmpire.Core.exe --project-root <root>`。**任何一次启动失败都是 P0。** |
| 进游戏（Flash 嵌入）+ 一局战斗到结束 | Flash Player SA 经 Win32 SetParent 嵌入到 `_flashPanel`（Phase 1 由 `D3DPanel` 退化为 plain `Panel`，丢 `TabStop=true` + `IsInputKey` override）；Flash HWND 自管焦点，理论 benign，但需 smoke test |
| WebView2 overlay 全部 panel 各开一次（about / display / archive / intelligence / map / stage-select / kshop / jukebox / 三个 minigame: lockbox / pinalign / gobang） | WebView2 1.0.3856.49 在 net10.0-windows 下应当行为一致，但 transitive WindowsBase 4.0 vs 5.0 MSB3277 warning 提示有版本统一隐患 |
| 存档读写：进存档界面，存盘 → 读盘 → 导入 → 导出，无报错 | SaveAutoRepairService 依赖 `launcher/data/save_repair_dict.json`；SolResolver 依赖 native `sol_parser.dll`（独立 Rust cdylib，不在 publish bundle 里） |
| 战斗热路径玩 ≥ 5 分钟，看 FrameTask / hit-number-bundle / 战斗音效（miniaudio）/ 各 panel 联动是否符合预期 | net10 GC / JIT 模式与 net462 不同，长时间运行的内存/CPU 行为可能漂移 |
| 工具栏热键 F（全屏切换）/ Q（退出）/ Ctrl+F（GUARDIAN_HK） | `SendKeyToFlash` Phase 1 删了 `_gpuMode` 分支后只走 `keybd_event` 全局注入路径；测试键盘 focus 行为 |

### 推荐 — 强烈建议验

| 项 | 为什么 |
|----|--------|
| 笔记本上切 `gpuPreference = "auto"`，AC 接通 + 独显在场，看注册表 `HKCU\Software\Microsoft\DirectX\UserGpuPreferences` 是否写入 launcher exe + msedgewebview2.exe 条目 | Vortice.DXGI EnumAdapters1 行为等价 SharpDX.DXGI Factory1.GetAdapter1，但真机 GPU 枚举差异未实测（agent 不启动 launcher） |
| 同上，切到电池 → 注册表条目应被 `Revert()` 清掉 | 同上 |
| `gpuPreference = "on"` 强制写入，"off" 强制不写入 | mode 切换路径完整性 |
| 长会话稳定性测试（≥ 30 min 游戏 + WebView2 panel 切换）：内存增长？CPU 漂移？句柄泄漏？ | net10/FDD 行为应稳定，但 net10 ↔ net462 的 GC heap 模型差异仍需观察 |
| 全屏 ↔ 窗口模式切换 ≥ 5 次 | `WindowManager.OnHostPanelResize`/`ResizeFlashToPanel` 简化（Phase 1 + 删 EnableGpuMode/DisableGpuMode），但 500ms watchdog re-embed 路径未改 |
| 退出路径：从游戏中按 Ctrl+Q → ForceExit → 8s ExitGuard 兜底 | Phase 1 删了 `StopGpuRenderer()` 在 Dispose/OnFormClosing 的调用，理论 benign（_gpuRenderer 永远 null）但需实测 |
| 多显示器 + DPI 缩放（100% / 125% / 150%）切换 | High-DPI manifest 仍走 WFO0003 警告但未改逻辑 |
| Flash Player SA 异常退出后 `OnFlashExited` 回调与 PID 追踪 | 不动业务逻辑，理论应无变化 |
| 系统锁屏 / 快速用户切换：focus watchdog 行为 | `_sessionLocked` 标志、`_vacuumStreak` 路径未变 |
| 启动期 WebView2 init 失败兜底（断网或 Evergreen Runtime 损坏） | `OnBootstrapInitFailed` 路径未变 |

### 可延后 — 不阻塞合并

- WFO0003 `app.manifest` DPI 设置建议迁到 `Application.SetHighDpiMode` API（保持 manifest 方案当前可用）
- ~~AppConfig.cs 中 `Sharpness` / `GpuSharpeningEnabled` / config.toml `gpuSharpening` 是 pre-existing dead 配置 knob（GpuRenderer 死代码删除后无消费者），cleanup 留给后续 PR~~ — 已随 post-migration 收尾批次清理（连带删 `ParseFloat` helper + README sample）
- WindowsBase 4.0 vs 5.0 transitive 冲突 warning（WebView2 1.0.3856.49 transitive 引 net5.0 WPF dll references WindowsBase 5.0；info-only，build 输出选 4.0）
- Newtonsoft.Json 13.0.3 → System.Text.Json 切换（独立立项，本次 goal 明令禁止同步）
- NRT（Nullable=enable）按文件灰度（独立立项，本次禁止同步）
- launcher 渲染合成方向（C# 自有合成器 + WGC + RTMP 等）（独立立项，本次禁止动）

## Reviewer 聚合

| Phase | Claude self-review | Kimi |
|-------|--------------------|------|
| 1 | ✅ LGTM | ✅ APPROVED（唯一成功响应的一次） |
| 2 | ⚠️ WARNINGS_ONLY（intentional transitional） | ⏭️ unreachable >3min |
| 3 | ✅ approved | ⏭️ unreachable >3min |
| 4 | ⚠️ WARNINGS_ONLY（intentional transitional） | ⏭️ unreachable >3min |
| 5 | ✅ APPROVED | ⏭️ unreachable >3min |

**Kimi unreachable this session**：Phase 1 后 4 次启动 kimi 均 >3min 无输出（fail-fast §7）。可能是 Moonshot 服务端拥塞或 prompt 长度问题。本机 `kimi --version` v1.x 已 login，额度充足。后续 phase 全靠 Claude self-review via `code-review` skill 思路推进。

## 绝对禁止 — 已遵守

- ✅ 未推 remote / 未 merge 主仓 / 未改 git config
- ✅ 未启动 launcher.exe（人力验给用户）
- ✅ 未切 Newtonsoft → System.Text.Json
- ✅ 未开 Nullable=enable
- ✅ 未动渲染合成方向（仅删 GpuRenderer D3D11 spike）
- ✅ 未装清单外工具（除 .NET SDK + Vortice.Windows NuGet）

## 等用户回来

1. 把 worktree branch `worktree-launcher-net10-migration` 合并到 main，或者按 PR 审一遍（5 commit atomic，可单独 cherry-pick）
2. 按上面的「人力验收待办」清单走一遍
3. 验完无问题就推 main → 出 cf7-packer pack → 出 SFX
4. 任何回归 → 5 commit atomic，可 revert 任一 phase 而不影响其它

**Worktree 路径**：`E:\wt\cf7n10`（短路径绕开 git core.longpaths 限制，flashswf/arts/new/Au的素材 那一坨长路径文件名才能 checkout 成功）。可保留也可 `git worktree remove` 清掉。

## 异常处理记录

- **2026-05-28 15:29**：winget install Microsoft.DotNet.SDK.10 卡住（10min 0 CPU），非 admin shell 触发 UAC silent fail。切到 dotnet-install.ps1 user-scope 路径，装到 `%LOCALAPPDATA%\Microsoft\dotnet\sdk\10.0.300\`，绕开 admin elevation 需求
- **2026-05-28 15:47**：`EnterWorktree` 默认 `.claude/worktrees/<name>` 路径触发 git checkout filename-too-long 错误（flashswf/arts/new/Au的素材/.../*.xml 文件名超长，主仓加 worktree prefix 后超出 git core.longpaths 默认 buffer）。手工 `git -c core.longpaths=true worktree add E:/wt/cf7n10 -b worktree-launcher-net10-migration` 创短路径 worktree 解决
- **2026-05-28 16:34**：build.ps1 第一次跑 PowerShell 5.1 parse 失败（unexpected token ')'）。根因：Write tool 写文件无 BOM，PS 5.1 默认按 ANSI/GBK 解码 UTF-8 多字节字符（中文注释）造成解析偏移。用 PowerShell 重写 build.ps1 + run_tests.ps1 加 UTF-8 BOM 解决
- **2026-05-28 multiple**：Agent 工具 spawn 子 agent 默认在 `.claude/worktrees/agent-*/` 创隔离 worktree，同样触发 long-path 失败。dual reviewer 的 Claude 子 agent 路径不可用，全靠 Claude main session + `code-review` skill 思路完成 self-review

## Post-migration 部署形态调整（2026-05-28 后续）

Phase 1-5 + 第一轮 hardening 完成后，**端到端 smoke test 在主仓位置才能跑通**——worktree 路径触发 SWF 字节码层反盗版（见 [[feedback-worktree-vs-antipiracy]] 记忆），不是 launcher 代码问题。回主仓 fast-forward merge 后，进行第二轮审阅，识别出两个 P1/P2 + 三个 P2/P3 问题：

| Round | 问题 | 解决 commit |
|-------|------|-------------|
| Round 1 (`b096d76da`) | canonical doc 仍 .NET 4.6.2、`global.json` 在 launcher/ 子目录失效、miniaudio.dll 缺失只 WARN、146MB exe 入 git、doc 数字漂移 | launcher/net10: post-migration hardening + canonical doc sync |
| Round 2 (`c6af79d42`) | 146MB single-file 太大不利 git；其他 dev 缺 runtime 没法用 | 切到 **FDD + native C++ bootstrap + bundled installer**：用户面入口 = `CRAZYFLASHER7MercenaryEmpire.exe`（134KB native bootstrap）→ 检测 .NET 10 桌面运行时 → 缺失则 ShellExecute "runas" `tools/dotnet-runtime/windowsdesktop-runtime-10.0.8-win-x64.exe` /install /passive /norestart（UAC 一次）→ 启动 `CRAZYFLASHER7MercenaryEmpire.Core.exe`（FDD apphost，~255KB）+ 17 个 DLL（~36MB） |
| Round 3 (本次) | Round 2 把 Core.exe 跟 bootstrap 都放 projectRoot，用户可能误点 `Core.exe` 触发 .NET apphost 默认的英文 "You must install .NET" 对话框（不友好），且 runtime 缺失场景 bootstrap 无文件日志，没法事后诊断 | (a) **Core + 全部 transitive DLL 移到 `projectRoot/runtime/` 子目录**，根目录只剩 bootstrap + 游戏资产 + configs，用户无从误点；(b) Bootstrap 加文件日志 `logs/bootstrap.log`，记录 runtime 检测 / installer 调用 / Core 启动每一步；(c) Bootstrap launch Core 时显式传 `--project-root <abs>` arg，Program.cs 加 `--project-root` 解析 + `crossdomain.xml` 哨兵 walk-up fallback；(d) miniaudio / sol_parser side-car 不再放 projectRoot 根，只放 `runtime/` 与 Core 同目录（让 P/Invoke LoadLibrary 默认搜索命中）；(e) pack.config 新增 `launcher-runtime` 层处理 `runtime/` 子目录；(f) `cfn-cli.sh` / `set-launcher-gpu-preference.ps1` / `GpuPreferenceManager.cs` 都跟着指向 `runtime/Core.exe` |

**Round 2 关键决策**：
- AssemblyName 从 `CRAZYFLASHER7MercenaryEmpire` 改为 `CRAZYFLASHER7MercenaryEmpire.Core`，FDD apphost 拿 `.Core` 后缀；用户面 `CRAZYFLASHER7MercenaryEmpire.exe` 让给 bootstrap，保住 19 处历史脚本/文档对此文件名的引用
- `cfn-cli.sh` 的 `start-bus` / `kill` 改向 `Core.exe`（bootstrap 启动 Core 后立即退出，长跑进程是 Core）
- `set-launcher-gpu-preference.ps1` 候选列表改 `Core.exe`（bootstrap 不占 GPU）
- `GpuPreferenceManager.cs` hardcoded fallback 改 `Core.exe`
- bundled installer 入 git ~58MB；ongoing 季度 patch 更新成本可控
- 整体 git 跟踪：~37MB FDD + ~260KB bootstrap + 58MB installer = ~95MB（vs Round 1 self-contained 146MB）

**Bootstrap 源代码**：[`launcher/native/bootstrap/bootstrap.cpp`](../launcher/native/bootstrap/bootstrap.cpp)（pure Win32, 零 STL, ~250 行），build via `cl.exe`（与 miniaudio 共用 vcvars64 工具链，零新增依赖）。
