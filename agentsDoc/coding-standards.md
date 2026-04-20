# 编码规范与多栈边界

**文档角色**：编码规范 canonical doc。  
**最后核对代码基线**：commit `c2118e295`（2026-04-20）。

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

## 3. C# Launcher 规范

> Guardian Launcher（`launcher/`）使用 **C# 5 / .NET Framework 4.6.2 / MSBuild 4.0**。

- 任务注册统一经 `TaskRegistry.RegisterAll()`，不要在 `Program.cs` 散装扩散
- 高/低频消息分层明确：快车道前缀 ≠ JSON 路由
- 本地服务默认只绑定 `localhost`
- 代码风格受 C# 5 约束：
  - 无 string interpolation
  - 无 null propagation
  - 无 expression-bodied members
- 构建入口以 `launcher/build.ps1` 为准；子系统深文档以 `launcher/README.md` 为准

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
- 不要在自动化文档里混写过时的独立 server 运行路径

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
