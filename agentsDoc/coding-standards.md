# 编码规范与多栈边界

**文档角色**：编码规范 canonical doc。  
**最后核对代码基线**：commit `b852c0eba1`（2026-06-17）。

## 1. 总原则

- **跟随所在子栈的现实约束**：不要把 AS3 / 现代 JS / 新版 C# / 任意 Rust 惯例直接投射到旧栈
- **跟随所在文件的既有风格**：除非当前任务明确做风格收敛，否则不要为了“统一”大面积改写历史代码
- **边界清晰优先**：多栈项目里，边界正确比局部抽象“更优雅”更重要
- **文档与实现同步**：路径、协议、测试入口、依赖门槛变化时，同轮更新 canonical doc

## 2. AS2 / Flash 规范

- 注释全部中文
- class 文件命名用英文；`_root` 业务挂载函数可用中文
- 热路径遵循高性能约束，非热路径优先可读性
- `.as` 文件必须 **UTF-8 with BOM**
- AS2 语法与幻觉防护以 [as2-anti-hallucination.md](as2-anti-hallucination.md) 为准
- 性能相关具体决策以 [as2-performance.md](as2-performance.md) 为准
- asLoader / 启动序列架构（单帧塌缩 + BootSequencer + chunk + 82 包并集头）以 [../docs/asLoader-README.md](../docs/asLoader-README.md) 为准

## 3. C# Launcher 规范

> Guardian Launcher（`launcher/`）使用 **C# (`LangVersion=latest`) / `net10.0-windows` / SDK-style csproj / FDD `dotnet publish --self-contained false` + native bootstrap**（2026-05-28 由 .NET Framework 4.6.2 + MSBuild + packages.config 迁来）。

- 任务注册统一经 `TaskRegistry.RegisterAll()`，不要在 `Program.cs` 散装扩散
- 高/低频消息分层明确：快车道前缀 ≠ JSON 路由
- 本地服务默认只绑定 `localhost`
- 代码风格：`LangVersion=latest` 允许 modern C# 特性（string interpolation / null propagation / pattern matching / expression-bodied members 等），但**不要为了用而用**——新代码风格统一以模块内现有代码为准；遗留 C# 5 风格的文件保留原状直到有功能性改动需要重写
- FDD/runtime 子目录布局硬约束：**禁止依赖 `Assembly.Location` 推断项目根目录**；需要当前进程 exe 用 `Environment.ProcessPath`，需要 Core runtime 目录用 `AppContext.BaseDirectory`，需要根目录资产时显式传入 `projectRoot`
- Nullable 默认 `disable`；按文件灰度启用 NRT 是独立立项，不要为单个文件随意打开
- 依赖版本统一在 [`launcher/Directory.Packages.props`](../launcher/Directory.Packages.props) 中心化锁定；csproj 只写 `PackageReference Include="..."` 不带 Version
- SDK pin 由 repo root [`global.json`](../global.json) 控制（`10.0.300` + `rollForward: latestFeature`），所有 dotnet 调用前 Push-Location 到 projectRoot 保证 host 能找到
- 构建入口以 `launcher/build.ps1` 为准；测试入口以 `launcher/tests/run_tests.ps1`（`dotnet test`）为准；子系统深文档以 `launcher/README.md` 为准

## 4. Web 前端 / Minigame 规范

- 共享 panel 生命周期遵循 `Panels.register(...)`
- 小游戏共享结构使用 `minigame-*` 类名，不重新引入旧共享结构命名
- 小游戏宿主上报统一走 `minigame_session`，不要恢复 `lockbox_session` / `pinalign_session`
- shared shell、host bridge、QA 基础层优先复用，避免每个小游戏自建一套协议和 harness
- Web / minigame 的深层契约以 `launcher/README.md` 和各自模块 README 为准

## 5. TypeScript / V8 / Rust 边界规范

- 这两类子栈属于**受控边界件**，不要把它们扩成新的“默认主栈”
- TypeScript 只服务于 `launcher/scripts/` 的构建与 V8 运行时代码
- Rust 只服务于明确的 native 边界件，如 `sol_parser`
- 当这两类子栈的职责发生变化时，必须同步更新：
  - `launcher/README.md`
  - `docs/tech-stack-rationalization.md`
  - 必要时更新 `AGENTS.md` 的 Context Packs

## 6. PowerShell 与自动化规范

- 含中文的 `.ps1` 优先保持 **UTF-8 with BOM**
- 手动 PowerShell 命令前先执行 `chcp.com 65001 | Out-Null`
- 运行自动化时区分：
  - 启动 / 运行自动化：`automation/README.md`
  - Flash 编译 smoke：`scripts/FlashCS6自动化编译.md`
- 自动化文档按“启动 / 运行”与“Flash smoke”分层，不再混写失真的独立 server 运行路径

## 7. 文档规范

- `AGENTS.md`：只写路由、硬约束、任务入口、文档地图
- `README.md`：只写人类 onboarding 与项目总览
- `agentsDoc/*`：写主题级 canonical doc
- `launcher/README.md`：写 Launcher 子系统 source of truth
- 高变动文档 / 章节使用“最后核对代码基线：commit ...”标记
- 文档治理规则以 [documentation-governance.md](documentation-governance.md) 为准

## 8. 调试与验证

- AS2 调试细节看 [as2-anti-hallucination.md](as2-anti-hallucination.md) §3
- 验证矩阵与话术边界看 [testing-guide.md](testing-guide.md)
