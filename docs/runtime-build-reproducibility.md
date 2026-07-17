# Launcher 运行时构建基线与二进制原子提交

**文档角色**：Launcher Windows 运行时发布环境、产物身份与跨机器协作的 canonical deep doc。  
**最后核对代码基线**：上游 `9e900762a6`（2026-07-17）+ 当前多机工具链引导与运行时原子重建工作树。

## 目标与边界

多台机器同时拥有 runtime 构建能力，但单机不再拥有正式部署集合的写入权。每台机器必须复现同一套工具链并只生成隔离 candidate；至少两个不同 builder 对同一 source/toolchain/recipe 得到逐文件相同的闭包 SHA 后，promotion 门才写入受版本控制二进制。本机建立基线 `cf7-win-x64-2026-07-17`；机器名、用户名和安装根目录不固定，编译器版本与 executable 字节、SDK、构建参数和源码输入身份固定。

这是长期多机协作的发布闸门，不等价于完整 CI 发布服务：不符合基线的机器仍可改 Web、AS2、数据和普通源码，也可运行不发布 runtime 的验证，但不得生成或提交 Launcher runtime 二进制。构建资格跟随锁定工具字节，最终发布资格跟随两个独立 attestation 的一致性与 staged bundle/consensus 验证，不跟随机器名或“某台主力机”的口头身份。

## 单一入口与环境锁

- 构建入口只有 `launcher/build.ps1 -BuilderId <稳定小写 ID>`；它清空并重建 `tmp/runtime-candidates/<source-toolchain>/<builder>/`，绝不直接覆盖项目根 runtime。部署入口只有 `tools/promote-runtime-bundle.ps1 -CandidateRoot <候选> -PeerAttestationPath <另一机 JSON>`；不要分别运行三个 native build 或手工复制 candidate。
- 新机器或环境漂移先运行 `powershell -ExecutionPolicy Bypass -File tools/bootstrap-runtime-build-env.ps1`。它按 lock 安装/补齐精确 .NET 与 Rust，并只在 VS Build Tools 阶段请求一次 UAC；`-VerifyOnly` 只审计、不下载、不安装。正式构建仍会独立重跑字节门禁，bootstrap 成功不能代替 build gate。
- `config/build/runtime-toolchain.lock.json` 锁定 .NET SDK/host、Roslyn `csc`、MSBuild、MSVC `cl/link`、Windows SDK `rc`、Rust `rustc/cargo` 的版本与 SHA-256；同时锁定 dotnet-install、rustup-init 和 VS 17.14.32 Build Tools 固定 bootstrapper 的 URL、版本与 SHA-256。NuGet 解析结果与包内容哈希由 `launcher/packages.lock.json` 固定。
- `global.json` 使用 `10.0.300` + `rollForward: disable`；`launcher/native/sol_parser/rust-toolchain.toml` 使用 `1.96.0-x86_64-pc-windows-msvc`。
- 构建前 `tools/check-runtime-build-env.ps1` 必须为 OK。它允许 VS、dotnet、rustup 安装根不同，也允许多个 VS 实例并存；检测器遍历所有候选并只选择 `cl/link` 版本和哈希同时匹配的实例，不接受“目录名相同但文件被 servicing 更新”的工具。
- `vcvars64` 必须显式选择锁定的 MSVC toolset 与 Windows SDK，并在初始化后核对 `where cl/link/rc` 的首个真实路径；外部 `CL/_CL_/LINK/_LINK_/INCLUDE/LIB/LIBPATH`、`RUSTFLAGS`、`RUSTC_WRAPPER` 等注入变量会被清空，`TMP/TEMP` 固定到 `%LOCALAPPDATA%\CF7\runtime-build-temp`，locale/timezone 设为稳定值。
- Rust 发布每次先 clean；路径 remap 与 `/Brepro` 通过唯一的 `CARGO_ENCODED_RUSTFLAGS` 同时传入，避免环境 `RUSTFLAGS` 覆盖链接确定性参数。managed Release 不携带 PDB，并使用 locked NuGet restore。
- `miniaudio.dll` 不直接消费工作树 C/H 原始字节：Git blob 身份会规范化文本换行，但 MSVC 的确定性种子仍会观察 checkout 的 CRLF/LF 与物理源码路径。`launcher/build.ps1` 先把 `miniaudio_bridge.c/miniaudio.h` 逐字节规范化为 LF 临时副本，`launcher/native/build.bat` 再以 `/utf-8 /experimental:deterministic /pathmap:<临时目录>=C:\cf7-runtime-src` 编译并由 linker `/Brepro` 收口。不得绕过总构建脚本单独运行 native build，也不得把某台机器的 `core.autocrlf` 当成发布基线。

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

candidate 根另写 `runtime-build-attestation.json`，记录 `builderId/sourceTreeHash/toolchainLockHash/buildRecipeHash/artifactClosureHash` 与完整文件摘要。`builderId` 是区分独立重建者的稳定操作 ID，不是发布所有权；promotion 至少消费两个不同 ID 且四个身份字段全等。promotion 成功后生成 `config/build/runtime-release-consensus.json`，供 Git/CI 证明当前部署闭包确实经过双 builder 共识；该记录不进入 sourceTreeHash，避免身份循环。

受 manifest 管理的 `runtime/**` 与 toolchain lock 在 `.gitattributes` 中按原始字节入库，避免 Git 在 JSON 上做 CRLF/LF 转换后让“构建时校验的文件”与“另一台机器 checkout 的文件”发生变化；manifest 自身固定 LF。引入本规则的基线迁移提交必须执行一次 `git add --renormalize runtime`，把 `Core.deps.json`、`Core.runtimeconfig.json` 等既有文本按新属性重新写入 index；以后日常提交不得反复运行该迁移命令。

`tools/verify-runtime-bundle.ps1` 校验工作树集合，`-DeploymentRoot` 可在不触碰正式 runtime 的情况下验证 candidate，`-Staged` 完全从 Git index 枚举源码输入与部署文件。manifest 文件行必须精确等于“根 bootstrap + `runtime/**` 中除 manifest 自身外的全部文件”，重复、大小写冲突、`../` 越界、遗漏和额外文件都会失败。`tools/verify-runtime-consensus.ps1` 进一步校验 release-consensus 的两个不同 builder、四重构建身份和实际闭包；首次双机 promotion 生成该记录后禁止删除。bootstrap 的 `--verify-only` 执行同一闭包语义且只接受独立参数全等，不检查/安装 .NET、不弹窗、不启动 Core；`automation/start.ps1`、`scripts/gobang_trainer_cycle.ps1`、`tools/cfn-cli.sh` 在直启 Core 前都必须先通过它。部署态 Core 在托管入口最早阶段还会反向调用 bootstrap probe，因此手工直启或未来遗漏 probe 的脚本也不能绕过；native 哈希期间拒绝写入/删除共享，并在 UAC 前、启动 Core 前和 Core 入口形成三段复核。

GitHub workflow 会执行 staged 模式，但仓库维护者还必须把 `Runtime bundle integrity / verify-staged-bundle` 配成受保护分支 required status check；未配置时它只能报告失败，不能阻止管理员或直接 push 绕过。

## Agent 与维护者工作流

1. 普通开发先改源码，不因检测到 runtime 输入变化就自动重建二进制。
2. 新机器先运行 `tools/bootstrap-runtime-build-env.ps1`；已配置机器可用 `-VerifyOnly` 快速复核。下载缓存放在 `%LOCALAPPDATA%\CF7\toolchain-cache\<baseline>`，不进入仓库。
3. 确实需要发布 Host/native 变化时，先运行 `tools/check-runtime-build-env.ps1`；非 OK 立即停止，不尝试“尽量构建”。VS 唯一需要管理员权限，Agent 可启动固定 bootstrapper，但 UAC 仍由人类或受管机器策略授权。
4. Builder A 运行 `launcher/build.ps1 -BuilderId builder-a`；同机再跑一次，Rust 两轮都必须 clean 后全量编译且 closure SHA 不变。
5. Builder B 在相同提交/工作树输入运行 `launcher/build.ps1 -BuilderId builder-b`，把小型 `runtime-build-attestation.json` 交给 A；两个 artifactClosureHash 不同立即停止，不允许任选其一。
6. 在 candidate 所在机器运行 `tools/promote-runtime-bundle.ps1 -CandidateRoot <A 候选> -PeerAttestationPath <B attestation>`；它要求当前正式部署无脏改动，以可回滚目录交换写入 bundle 和 release-consensus，再复跑 managed/native/consensus 门。
7. 运行 `launcher/tests/run_tests.ps1` 及受改动子栈的专项验证；提交前运行 `tools/verify-runtime-bundle.ps1` 与 `tools/verify-runtime-consensus.ps1`，审阅 staged 内容时两者都加 `-Staged`。

禁止用单文件 checkout/冲突取舍来“消除二进制 diff”，禁止伪造第二 builder ID 或手改 attestation/consensus；如果集合被拆散，重新双机构建并 promotion。promotion 会在 `tmp/runtime-promotions/` 保留可恢复的上一份部署。未通过环境锁或跨机闭包不一致时，Agent 应报告缺失/差异并继续完成不涉及 runtime 发布的工作，不得更新 lock 来迁就当前机器。

## 基线升级

升级 SDK/编译器是显式维护事件，不是某台机器自动更新后的顺手提交：先在基准环境更新最终工具哈希与固定安装器 URL/哈希，完整构建两次确认稳定，再更新本文与 Launcher 文档，提交完整原子集合；随后其他发布机运行 bootstrap 并通过新 lock。旧基线在同一提交中退役，禁止两个工具链同时拥有发布权。若微软固定 bootstrapper 或 dotnet/rustup 安装器下载字节变化，脚本必须 fail-fast；先人工核对官方来源，再显式升级 lock，不能关闭哈希校验。
