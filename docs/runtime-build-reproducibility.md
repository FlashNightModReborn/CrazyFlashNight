# Launcher 运行时构建基线与二进制原子提交

**文档角色**：Launcher Windows 运行时发布环境、产物身份与跨机器协作的 canonical deep doc。  
**最后核对代码基线**：commit `12fb70d702`（2026-07-17）+ 当前运行时构建治理过渡工作树。

## 目标与边界

短期内允许多台机器开发，但正式写入受版本控制运行时二进制的机器必须复现同一套工具链。本机建立基线 `cf7-win-x64-2026-07-17`；机器名、用户名和安装根目录不固定，编译器版本与 executable 字节、SDK、构建参数和源码输入身份固定。

这不是长期 CI 发布服务。它是两台主要开发机共享写入权期间的过渡闸门：不符合基线的机器仍可改 Web、AS2、数据和普通源码，也可运行不发布 runtime 的验证，但不得生成或提交 Launcher runtime 二进制。

## 单一入口与环境锁

- 正式入口只有 `launcher/build.ps1`；不要分别运行三个 native build 后手工复制产物。
- `config/build/runtime-toolchain.lock.json` 锁定 .NET SDK/host、Roslyn `csc`、MSBuild、MSVC `cl/link`、Windows SDK `rc`、Rust `rustc/cargo` 的版本与 SHA-256；NuGet 解析结果与包内容哈希由 `launcher/packages.lock.json` 固定。
- `global.json` 使用 `10.0.300` + `rollForward: disable`；`launcher/native/sol_parser/rust-toolchain.toml` 使用 `1.96.0-x86_64-pc-windows-msvc`。
- 构建前 `tools/check-runtime-build-env.ps1` 必须为 OK。它允许 VS、dotnet、rustup 安装根不同，但不接受同名不同字节的工具。
- `vcvars64` 必须显式选择锁定的 MSVC toolset 与 Windows SDK，并在初始化后核对 `where cl/link/rc` 的首个真实路径；外部 `CL`、`LINK`、`RUSTFLAGS`、`RUSTC_WRAPPER` 等注入变量会被清空。
- Rust 发布每次先 clean；路径 remap 与 `/Brepro` 通过唯一的 `CARGO_ENCODED_RUSTFLAGS` 同时传入，避免环境 `RUSTFLAGS` 覆盖链接确定性参数。managed Release 不携带 PDB，并使用 locked NuGet restore。

当前基线版本为：.NET SDK `10.0.300`；MSVC toolset `14.44.35207`（`cl 19.44.35227.0` / `link 14.44.35227.0`）；Windows SDK `10.0.22621.0`；Rust `1.96.0` commit `ac68faa20c58cbccd01ee7208bf3b6e93a7d7f96`。精确哈希只以 lock JSON 为准，文档不复制第二份。

## 原子产物与身份

以下集合必须来自同一次完整构建并在同一提交中出现：

- 根目录 `CRAZYFLASHER7MercenaryEmpire.exe`
- `runtime/CRAZYFLASHER7MercenaryEmpire.Core.*` 与全部受 manifest 管理的依赖 DLL/JSON
- `runtime/miniaudio.dll`
- `runtime/sol_parser.dll`
- `runtime/cf7-runtime-manifest.tsv`

manifest 除文件大小与 SHA-256 外，还记录：

- `sourceTreeHash`：所有 runtime 构建输入的有序 Git-filtered blob 身份；不绑定物理 checkout 路径。
- `toolchainLockHash`：环境锁文件身份。
- `toolchainBaseline`：人可读基线名。

受 manifest 管理的 `runtime/**` 与 toolchain lock 在 `.gitattributes` 中按原始字节入库，避免 Git 在 JSON 上做 CRLF/LF 转换后让“构建时校验的文件”与“另一台机器 checkout 的文件”发生变化；manifest 自身固定 LF。引入本规则的基线迁移提交必须执行一次 `git add --renormalize runtime`，把 `Core.deps.json`、`Core.runtimeconfig.json` 等既有文本按新属性重新写入 index；以后日常提交不得反复运行该迁移命令。

`tools/verify-runtime-bundle.ps1` 校验工作树集合；`-Staged` 完全从 Git index 枚举源码输入与部署文件。manifest 文件行必须精确等于“根 bootstrap + `runtime/**` 中除 manifest 自身外的全部文件”，重复、大小写冲突、`../` 越界、遗漏和额外文件都会失败。bootstrap 的 `--verify-only` 执行同一闭包语义且只接受独立参数全等，不检查/安装 .NET、不弹窗、不启动 Core；`automation/start.ps1`、`scripts/gobang_trainer_cycle.ps1`、`tools/cfn-cli.sh` 在直启 Core 前都必须先通过它。部署态 Core 在托管入口最早阶段还会反向调用 bootstrap probe，因此手工直启或未来遗漏 probe 的脚本也不能绕过；native 哈希期间拒绝写入/删除共享，并在 UAC 前、启动 Core 前和 Core 入口形成三段复核。

GitHub workflow 会执行 staged 模式，但仓库维护者还必须把 `Runtime bundle integrity / verify-staged-bundle` 配成受保护分支 required status check；未配置时它只能报告失败，不能阻止管理员或直接 push 绕过。

## Agent 与维护者工作流

1. 普通开发先改源码，不因检测到 runtime 输入变化就自动重建二进制。
2. 确实需要发布 Host/native 变化时，先运行 `tools/check-runtime-build-env.ps1`；非 OK 立即停止，不尝试“尽量构建”。
3. 运行一次 `launcher/build.ps1`，保留它生成的完整原子集合。
4. 运行 `launcher/tests/run_tests.ps1` 及受改动子栈的专项验证。
5. 提交前运行 `tools/verify-runtime-bundle.ps1`；审阅 staged 内容时再运行 `tools/verify-runtime-bundle.ps1 -Staged`。
6. 同源复验时连续运行两次完整 build；Rust 两轮都必须显示 clean 后全量编译，第二次的 23 个原子产物 SHA-256 必须全部不变。

禁止用单文件 checkout/冲突取舍来“消除二进制 diff”；如果集合被拆散，重新完整构建。未通过环境锁时，Agent 应报告缺失或不一致项，并继续完成不涉及 runtime 发布的工作，不得更新 lock 来迁就当前机器。

## 基线升级

升级 SDK/编译器是显式维护事件，不是某台机器自动更新后的顺手提交：先在基准机更新 lock 与 pin，完整构建两次确认稳定，再更新本文与 Launcher 文档，提交完整原子集合；随后第二台发布机安装并通过新 lock。旧基线在同一提交中退役，禁止两个工具链同时拥有发布权。
