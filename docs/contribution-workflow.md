# 协作者直推与 native/runtime 发布边界

**文档角色**：`main` 的协作者提交体验、native/runtime 事后审计与正式发布授权边界；二进制发布证据仍以 [runtime-build-reproducibility.md](runtime-build-reproducibility.md) 为准。

## 当前结论

仓库继续保留 AS2、XML、XFL、Web 与 Launcher 的同提交原子性，不拆软件仓库和资产仓库。GitHub Free 公开仓库采用“全员直推 + 事后审计 + 正式发布双生产者共识”：

- 所有已有 write 权限的协作者，包括 `Crazyfs`、`Flash-Night`，都继续使用现有客户端 `Pull → Commit → Push main`；服务端不要求 PR、CODEOWNER 或另一人在线。
- 普通文档、美术、策划、AS2、Web 与数据提交不触发 runtime integrity workflow，各自继续遵守原有专项验证。
- C# / Rust / C / C++、项目/锁文件与其他 native 源码直推属于正常开发态。push 后审计可以成功报告 `source-ahead`，表示源码领先于当前已部署 runtime；它不是发布失败，也不要求每次提交立即重建二进制。
- 根 EXE、`runtime/**`、manifest、signed consensus 等部署字节若发生变化，却没有完整 v2 promotion 证据，push 后 workflow 必须失败报警。报警是事后信号，不能撤销已经进入 `main` 的提交。
- 正式 release 才要求注册本地 X509 producer 与 GitHub Hosted OIDC/Sigstore producer 对同一 immutable source 达成双 signer、双 `faultDomain` 共识。构建共识不要求 Flash-Night 人工审批；任一获授权发布者可独立完成整条列车。

PR 仍可用于自愿讨论或代码审阅，但不是任何账号的主线前置条件。一键 PR 工具只保留为可选辅助，不再是准入入口或权限来源。

## 所有协作者：维持原操作

1. 拉取 `main`。
2. 编辑并 commit。
3. 点击 Push。

`main-global-ref-integrity-v1` 禁止删除与 non-fast-forward / force-push，因此正常直推必须基于当前远端形成可追溯的 fast-forward 历史。远端已经前进时，先按现有客户端的正常同步流程处理；不要 force-push 覆盖他人工作。

普通内容路径不会为了证明“没有 native 变化”而启动 Windows Actions。素材、策划数据、AS2、主 XFL/SWF、独立 Flash 资产、文档与 `launcher/web/**` 的正确性仍由各自格式、编译、harness 与人工验收负责；runtime workflow 不为这些内容提供语义背书。

## native 事后审计状态

`config/build/native-change-gate.v1.json` 与 `config/build/runtime-inputs.v2.json` 共同描述 native/runtime 边界：

- C# / Rust / C / C++ 源码、项目文件、Cargo/.NET/CMake 等锁与入口；
- `launcher/src/**`、`launcher/native/**`、根 bootstrap、`runtime/**`；
- `.github/workflows/**`、`.github/actions/**`、`config/build/**`；
- runtime request、worker、GitHub attestation、policy receipt、promotion、consensus、verifier 与对应回归工具。

`Runtime native audit / audit-native-runtime` 监听 `main` push、目标为 `main` 的可选 PR 和获授权发布者的手工 dispatch；所有事件只接受首次 run，旧 run 的 rerun 在 runner 分配前跳过。静态 paths 只覆盖上述 native/runtime 集合，普通内容不会启动 runner。PR 检查只是自愿的提前反馈，未被任何 ruleset 设为 required。自动 push/PR 使用低成本 diff 语义；手工 dispatch 则强制当前 HEAD 完成 integrity、source identity 与 strict consensus 全链，作为 release-readiness 检查，源码仍为 `source-ahead` 时按尚未可发布失败，不能把它理解成只重审最后一个 commit。

push 后状态分三类理解：

| 状态 | 含义 | 后续动作 |
|------|------|----------|
| 普通内容 | 不触发 runtime workflow | 按受影响子栈完成验证 |
| `source-ahead` | native/release 输入源码领先，但正式部署字节和既有 consensus 未被混改 | 审计成功；继续开发，准备正式 release 时再冻结最终 commit |
| 部署漂移 / 无效 consensus | 根 EXE、runtime、manifest、consensus 或发布控制闭包与合法 promotion 不一致 | workflow 失败报警；停止把该 HEAD 当成可发布部署，修复或完成正式 promotion |

未绑定的新 DLL、EXE、源码或 future build-control 路径仍应由审计显式报警，不能利用 descriptor 漏列假装进入合法发布闭包。历史冻结对象可在明确清理时删除；若要继续开发，先把源码、确定性 producer 与产物一起迁入发布身份。

`policyHash` 继续覆盖生成器、审计器、派生资产与发布政策，但它不意味着每次 policy/native 源码直推都要即时 promotion。正式 release request 会冻结当时完整 Git tree，并用 production policy receipt 重新绑定。

## 正式 release：无需第二人在线

正式发布者从已提交的最终 source commit 建立一次性、单路径段的 `runtime-build-v2/<release-id>` tag 和 immutable request，然后取得。cloud config、dispatch helper、envelope/attestation verifier 与主线准入审计都会拒绝任意其他 tag 命名空间或 `runtime-build-v2/a/b` 这类嵌套 tag，确保被证明的 `sourceRef` 必定落在 creation + immutability 两条远端规则覆盖内：

1. 注册本地 X509 worker 的签名票；
2. GitHub Hosted Windows 的 OIDC/Sigstore 签名票；
3. production policy receipt；
4. v2 strict verifier 通过结果。

两张票必须拥有不同 signer identity 和真实不同 `faultDomain`，且 build identity / payload closure 全等。GitHub Hosted 是自动第二生产者，不是第二名 human reviewer；它证明构建来源与字节共识，不判断源码业务意图。只要发布者拥有已登记本地证书、source-tag 创建权和 cloud dispatch 权，就不需要等待另一账号批准。

cloud workflow 只接受 `Crazyfs`（GitHub actor ID `91271520`）或 `Flash-Night`（`138298913`）发起的 `workflow_dispatch`，并只接受 `run_attempt == 1`；失败后应重新 dispatch，不使用 Actions 的 rerun 按钮。该授权用于限制发布能力与 hosted runner 消耗，不影响任何协作者直推源码。

cloud artifact 保留期是有意缩短的临时传递窗口：

- unsigned candidate + envelope：1 天，仅供 build → attest job 交接；
- 失败 bootstrap diagnostics：7 天；
- signed candidate + envelope + Sigstore bundle：7 天，供 helper 下载、验真和 promotion。

超过 7 天仍未 promotion 时重新 dispatch；不要把 Actions artifact 当永久发布档案。promotion 后的 tracked manifest/consensus 与其内嵌证明才是仓库长期审计记录。

## GitHub 远端只保留三条零 Actions ruleset

`config/build/main-branch-admission.v2.json` 是全员直推、advisory CODEOWNERS、source-tag 创建者和以下三条规则的版本化 source of truth。远端不设置身份 gate、Require PR、CODEOWNER review 或 required Actions check，只保留三条不依赖 Actions 结果的引用完整性规则：

| Ruleset | bypass | 规则 |
|---------|--------|------|
| `main-global-ref-integrity-v1` | 无 | 禁止删除 `main`；禁止 non-fast-forward / force-push，正常 fast-forward 直推不受阻 |
| `runtime-source-tag-creation-v1` | 仅获授权发布账号，`User + always` | 只有 `Crazyfs`、`Flash-Night` 可创建 `refs/tags/runtime-build-v2/*` |
| `runtime-source-tag-immutability-v1` | 无 | 已创建的 runtime source tag 禁止任何 update 与 deletion |

tag creation 与 immutability 必须分开：创建新 tag 的 bypass 不能同时获得移动或删除旧 tag 的能力。`.github/CODEOWNERS` 可以保留为审阅提示，但没有服务端 required-review 效力，不构成准入或发布证明。

首次部署固定按四态迁移，避免切换时丢失引用保护：

1. `ConfigOnly`：只校验本地 schema、actor ID 与三条规则契约。
2. `Prepared`：三条 ruleset 已创建但为 `disabled`；minimal classic 仍启用，且只以 `enforce_admins=true`、`allow_force_pushes=false`、`allow_deletions=false` 禁止所有人（含管理员）force/delete，不含 required check、PR review、push restriction、signature、linear-history 或其他准入门槛。
3. `Layered`：三条 ruleset 激活，minimal classic 暂时保留；先验证 main/tag 有效规则与直推语义。
4. `Active`：最后删除 classic，远端只剩三条 active ruleset。回滚时必须先恢复 minimal classic，再禁用 ruleset。

远端规则只读复核入口：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/audit-main-branch-admission.ps1
```

## 明确的残余风险

GitHub Free 公开仓库没有本方案可用的服务端 path push restriction。只要账号有 write 权限，服务器就会接受其 fast-forward native push，包括源码、workflow，甚至部署文件；push 后 Actions 最多报警，不能回滚或阻止该提交进入 `main`。

`paths` 也只是降低 Windows runner 消耗的 best-effort 调度器，不是完整安全边界。GitHub.com 当前只用生成 diff 的前 3,000 个文件匹配过滤器；超大素材提交若把 native/runtime 文件排在该窗口之外，审计可能不启动。反过来，单次 push 超过 1,000 个 commit 或 diff 生成超时会无视过滤器而启动 workflow。因此“普通内容零 runner”是常规提交目标，不是超大 push 的绝对保证；官方限制见 [Workflow syntax for GitHub Actions](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#git-diff-comparisons)。

因此必须接受并管理以下边界：

- `source-ahead` 只表示开发源码领先，不表示已发布，也不表示代码安全或经过第二人审阅；
- 部署漂移红灯出现后，`main` 已经包含问题提交；维护者必须及时处置，不能把红灯当作无害构建噪声；
- path-filter 可能因上述 GitHub diff 窗口漏掉超大提交中的 native/runtime 文件，所以事后 Audit 只提供快速反馈；正式安全边界始终是受保护 immutable tag、双生产者共识、production receipt 与 promotion；
- GitHub Hosted attestation 证明“哪份源码由哪个 workflow 构建出哪些字节”，不证明源码意图安全；取消 human reviewer 后，业务正确性与恶意改动风险由提交者、测试和事后审计共同承担；
- source tag 权限与不可变规则能保护正式 release 输入，但不能阻止普通账号先把 native 源码推到 `main`；发布者必须在冻结 release 前审阅目标 tree 与告警状态；
- 管理员仍可修改 repository settings/ruleset，这是 GitHub 设置层的独立风险；三条 ruleset 不能约束管理员主动拆除规则；
- 若未来必须做到“误碰 native 也绝不进入 main”，需要升级到具备服务端 path restriction 的托管方案，或把 native/runtime 信任链迁到独立仓库。本方案不虚构该能力。

## 何时再考虑拆分资产仓库

只有当素材体积成为主要克隆瓶颈、跨栈原子改动显著减少，并具备“不可变资产包 + 主仓 manifest 锁定 + 自动发布”后，才评估独立资产源仓库。当前为普通合作者引入 submodule 或双主线，会把同步指针和跨仓漂移处理转嫁给最不熟悉 Git 的人。
