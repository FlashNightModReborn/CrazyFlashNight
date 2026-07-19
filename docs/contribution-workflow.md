# 协作者直推与 native 账号隔离

**文档角色**：`main` 的账号准入、普通合作者提交体验与 native/runtime 变更分域；二进制发布证据仍以 [runtime-build-reproducibility.md](runtime-build-reproducibility.md) 为准。

## 当前结论

仓库继续保留 AS2、XML、XFL、Web 与 Launcher 的同提交原子性，不拆软件仓库和资产仓库。GitHub Free 公开仓库当前采用“账号隔离 + native 黑名单分类”组合：

- 普通文档、美术、策划、AS2 与 Web 合作者保留原来的 `Pull → Commit → Push`，可以从现有 Git 客户端直接推 `main`，不要求学习分支或 PR。
- `Crazyfs`、`Flash-Night` 作为 native 受限账号，不获得身份门 bypass；无论本次改什么路径，都必须先进入 PR，并通过 `verify-staged-bundle`。
- 新增 collaborator 默认受限。只有确认其不承担 C# / Rust / C / C++ / DLL / EXE / runtime 信任链开发后，才把账号显式加入版本化 bypass 清单并同步远端 ruleset。
- 开发机身份可以切换，但准入跟 GitHub 账号而不是机器绑定；承担 native 开发时应使用受限账号。

账号期望状态的唯一版本化记录是 `config/build/main-branch-admission.v1.json`。远端只读复核入口：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/audit-main-branch-admission.ps1
```

## 普通合作者：维持原操作

普通 bypass 账号继续使用 GitHub Desktop 或现有客户端：

1. 拉取 `main`。
2. 编辑并 commit。
3. 点击 Push。

无需运行额外脚本，也不会因为尚不存在的 GitHub check 被服务器预先拒绝。`verify-staged-bundle` 仍会在 `main` push 后运行，用于事后确认这次提交没有让 Launcher runtime 状态漂移；普通内容不触发重新建立二进制共识。检查不会只相信上一次 push 的 event base，而是沿 `main` 第一父链回到最近一次由固定 workflow、GitHub Actions App 和 `push/main` 成功检查共同确认的绿色提交，再累计比较到当前 head。因此“误推 native → 再推文档”不会把漂移洗绿；连续 push 导致前一次 run 被取消也不影响该性质。

纯素材、策划数据、AS2、主 XFL/SWF、独立 Flash 资产、文档与 `launcher/web/**` 仍各自遵守原有编译、格式与专项测试约束。native fastpath 只证明“没有触及 native/runtime 受限域”，不证明素材语义、数值或 Flash 发布结果正确。

## 受限账号：PR 入口

`Crazyfs`、`Flash-Night` 直接推 `main` 会被 GitHub 身份门拒绝。可以自行使用正常 PR，也可以在本地 `main` 已 commit、工作树干净且不落后远端时双击根目录 `一键提交到主线.cmd`。工具会创建唯一 `contrib/*` 分支和 ready PR；文档/内容车道可登记 auto-merge，软件车道等待手工合并。它不会 force push、reset、rebase 或强删分支。合并方式固定为 merge commit；v2 GitHub producer proof 把 source commit 绑定为最终 `main` 的祖先，squash/rebase 会改写该祖先关系，因而不能用于受限账号的 native promotion。

命令行入口：

```powershell
gh auth login
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/submit-contribution.ps1 -Wait
```

`config/build/contribution-lanes.v1.json` 只决定这个一键 PR 工具的显示、等待与 auto-merge 行为，不再是直推权限源，也不参与 CI 的 native/non-native 判定。

## native 黑名单如何判定

`config/build/native-change-gate.v1.json` 是准入分类的 canonical 配置。分类器从外部成功检查确认的 trusted base 读取该文件，并联合 `runtime-inputs.v2.json` 的 artifact source、producer recipe、toolchain lock 与完整 payload；命中任一项就走完整 strict 链：

- C# / Rust / C / C++ 源码、项目文件、全局 native 编译扩展名与 Cargo/.NET/CMake 等锁和入口文件名；
- `launcher/src/**`、`launcher/native/**`、根 bootstrap、`runtime/**`；
- `.github/workflows/**`、`.github/actions/**`、`config/build/**`；
- runtime request、worker、GitHub attestation、policy receipt、promotion、consensus、verifier 与对应回归工具。

命中 native gate 的新增或修改还必须被当前 index 的 runtime descriptor 输入闭包、payload，或明确的 canonical release 输出/迁移控制路径绑定；任意新出现或被改写的未绑定 DLL、EXE、源码、项目文件和 future build-control 路径都在调用 verifier 前失败，不能靠“strict 只验证已知输入”洗绿。删除未绑定的历史 native 文件允许进入 strict，以便安全清理；未改动的历史文件不会因为一次普通内容 push 被重新纳入发布身份。

Launcher 单测、两个 `sol_parser` 的 tests/examples 与根 solution 已作为 policy 输入显式绑定，可正常随 native release train 演进。历史 vendor/tool 二进制、`launcher/bin/**` 以及尚未纳入纯 producer 的 `HotkeyGuard.cs` / `hotkey_guard.exe` 则保持冻结：可以在明确清理时删除，不能直接替换或修改；若要继续开发 HotkeyGuard，必须先把源码、确定性 producer 与根 EXE 一起迁入 payload 闭包，不能只把源码列成 policy 来假装获得双构建共识。

未命中黑名单且 trusted base 到当前 head 的累计 Git diff 仅含规范 regular-file 新增、修改或删除时，输出 `state=protected-nonnative-fastpath`，直接继承该绿色祖先的 signed consensus，不读取或散列 payload blob。event base 仍单独用于 deployment/migration 状态比较，绝不被 trusted base 替代。GitHub API 不可用、找不到无歧义绿色锚、空/全零 event base 时，required check 明确保持失败，待 API/锚恢复后重跑；它不会把 immediate event base 或单次本地 strict 结果变成可继承绿灯。symlink、gitlink、可执行 mode、危险/非规范路径、大小写碰撞、缺失/畸形 gate 与非祖先 base 同样失败关闭。

正式 release 的 `policyHash` 仍保持广义证据闭包：内容生成器、审计器、派生目录与发布资产继续由下一次 production policy receipt 绑定。它们不再因为日常内容提交而被误判成 native，但也没有从 release 证据中删除。

## GitHub 主线与 runtime source tag ruleset

远端必须拆成四个职责单一的 ruleset，不能合并：

| Ruleset | bypass | 规则 |
|---------|--------|------|
| `main-native-identity-gate-v1` | 仅版本化清单中的普通账号，`User + always` | Require PR；只允许 merge commit；strict `verify-staged-bundle`（GitHub Actions App `15368`）；普通审批数为 0；命中 trust-root/native CODEOWNERS 时必须由另一 native owner 审批 |
| `main-global-ref-integrity-v1` | 无 | 禁止删除 `main`；禁止 non-fast-forward / force-push |
| `runtime-source-tag-creation-v1` | 仅 `Crazyfs`、`Flash-Night`，`User + always` | 只有受限 native 账号可创建 `refs/tags/runtime-build-v2/*` |
| `runtime-source-tag-immutability-v1` | 无 | 已创建的 runtime source tag 禁止任何 update 与 deletion |

原因是 `always` 会绕过同一 ruleset 内全部规则；如果把删除/force-push 规则放进身份门，普通账号也会绕过它们。tag creation 与 tag immutability 也必须分开，否则允许 release maintainer 创建新 tag 的 bypass 会同时允许其移动或删除旧 tag。

`.github/CODEOWNERS` 的空 catch-all 使纯文档/内容 PR 没有 owner，因此受限账号的普通内容提交仍可在 required check 绿色后零人工审批合并；但 `.github/**`、`config/build/**`、`tools/**`、`runtime/**`、Launcher native 源码/工程/构建入口以及全局 native 扩展名均由 `@Crazyfs @Flash-Night` 所有。受限作者修改这些 trust-root/native 文件时不能批准自己的 PR，必须由另一 native owner 审批。这一门槛阻止作者把 required workflow、分类器或证明链改成无条件成功后自行合入；普通 bypass 账号的直推体验不受 CODEOWNER 规则影响。

规则迁移固定分三态执行，避免切换窗口把所有人锁死或同时撤掉保护：

首次引导 PR 还有一个历史 CODEOWNERS 交叉点：旧 `main` 只列 `@Crazyfs @lyyloo @XDD3102`，所以新加入的 `@Flash-Night` 不能审批这一次 PR。首选由旧 owner 正常审批；若明确不可用，才允许在该 PR required check 已绿色、classic 配置已完整快照后执行一次受控 bootstrap：只临时关闭 `require_code_owner_reviews`，继续保留 enforce-admins、Require PR、strict `verify-staged-bundle`、禁止 force-push/deletion，合并后立即把 classic CODEOWNER 要求恢复为 true；任何一步失败都先恢复 classic，再停止迁移。这个例外只解决旧 owner 集到新 owner 集的交接，不能留作日常绕过。

1. `Prepared`：四个 ruleset 已按版本化配置创建但仍为 `disabled`，classic branch protection 保持原样；运行 `tools/audit-main-branch-admission.ps1 -ExpectedState Prepared`。
2. `Layered`：先激活四个 ruleset，classic protection 仍保留；运行 `-ExpectedState Layered`，确认主线四类有效规则、source-tag 创建/不可变规则与 workflow 活性都存在。
3. `Active`：最后删除 classic protection，再运行 `-ExpectedState Active`；此时 classic endpoint 必须为 404，四个 ruleset 必须 active。

本地只审 schema 用 `-ExpectedState ConfigOnly`。审计还会让 CODEOWNERS 扩展名/入口名与 native gate 同源，校验规范化 LF 摘要、远端 `main` blob 与 GitHub CODEOWNERS errors；同时绑定 required workflow 的 database ID、仓库内路径与 `state=active`，并在 Layered/Active 状态确认当前 `main` HEAD 已由该 workflow 的成功 `push/main` check 精确覆盖，防止 ruleset 指向已禁用、已删除或只在旧提交上成功的同名检查。若迁移后需要回滚，必须先恢复 classic protection，再禁用 ruleset；不要先拆掉现行保护。

## 明确的残余风险

GitHub Free 公开仓库的这个方案按账号隔离，不是按路径做服务端 push restriction。获得 `always` bypass 的普通账号若误改 native 文件，服务器仍会接受 push；push 后 CI 可以报警，但不能撤销已经进入 `main` 的提交。

历史回放中，排除 `Crazyfs`、`Flash-Night` 后的 1,825 个真实 file-changing non-merge 提交仅 3 个命中 native 黑名单（0.164%）：一个 C# 修改、两个 EXE。概率低但不是零，因此：

- bypass 只授予已确认不承担 native 开发的账号；新 collaborator 默认 restricted；
- 任意 DLL/EXE 都保持受限，不给素材树开二进制例外；
- push 后 `verify-staged-bundle` 红灯必须由 native 维护者处置，不能当作素材构建噪声忽略；
- 若未来需要“普通账号即使误碰 native 也无法推入”，应升级到支持 path push ruleset 的仓库方案，或把 native/runtime 信任链拆到独立仓库；本方案不虚构该能力。

多数 collaborator 当前仍有较高仓库权限，管理员能够修改 repository settings/ruleset，这是独立的设置层风险。本轮不静默降权；后续可在确认职责后把无需管理设置的账号收敛到 `write` / `maintain`。

绿色锚由仓库自己的 workflow 复核，足以防真实协作者的误操作和连续 push 漂移，但不是对恶意 bypass actor 的仓库外证明：拥有直推权的人仍可能主动篡改 workflow 后推入 `main`。服务端 path rule 或 native 独立仓库才是抵御该类主动攻击的边界。

## 一键工具安全边界

一键工具只接受：工作树完全干净、当前不处于 merge/rebase/cherry-pick/revert/bisect/sequencer 中间态、提交相对远端 `main` 只 ahead 不 behind。远端已前进时会停止，不自行改写历史。合并后也只有在贡献 commit 已成为远端 `main` 祖先时，才 `--ff-only` 回到 `main` 并用普通 `branch -d` 清理。

## 何时再考虑拆分资产仓库

只有当素材体积成为主要克隆瓶颈、跨栈原子改动显著减少，并具备“不可变资产包 + 主仓 manifest 锁定 + 自动发布”后，才评估独立资产源仓库。当前为普通合作者引入 submodule 或双主线，会把同步指针和跨仓漂移处理转嫁给最不熟悉 Git 的人。
