# 普通合作者一键贡献与路径分域

**文档角色**：普通文档、美术、策划与开发改动进入 `main` 的协作入口；runtime 二进制发布仍以 [runtime-build-reproducibility.md](runtime-build-reproducibility.md) 为准。

## 目标

仓库继续保留 AS2、XML、XFL、Web 与 Launcher 的同提交原子性，当前不拆成软件仓库和资产仓库。协作边界由路径车道、验证门和一键入口表达，不要求普通合作者学习 Git 分支、PR、rebase 或 merge queue。

普通合作者只需：

1. 像过去一样拉取，并在 Git 客户端中完成本地 commit。
2. 双击仓库根目录的 `一键提交到主线.cmd`。
3. 文档/内容车道请保持窗口打开：窗口会显示 PR 地址与检查进度，合并后自动安全回到 `main` 再提示完成；普通软件车道只建立待维护者审阅的 PR，显示地址后即可关闭。

工具会把“本地 `main` 比远端多出 commit”的状态转换为唯一 `contrib/*` 分支，推送、建立 ready PR，并登记安全的 merge-commit auto-merge。双击入口默认等待自动车道合并，再以 `--ff-only` 回到 `main`；若窗口被提前关闭或网络中断，再次双击会续接已有分支/PR并完成清理。整个流程不会 force push、reset、rebase 或强删分支。

## 四条贡献车道

| 车道 | 典型路径 | Runtime 新共识 | 首版合入行为 |
|------|----------|----------------|--------------|
| 文档 | `docs/**` | 不需要 | required check 通过后自动合并 |
| 游戏内容 | `flashswf/arts/**`、`flashswf/UI/**` 等明确素材根，以及 `data/**`、`xml/**`、`music/**`、`sounds/**` | 通常不需要 | required check 通过后自动合并；结论只证明未触碰 runtime，不声称素材语义正确 |
| 普通软件 | 非发布域的 AS2、Web、测试、工具等 | 通常不需要 | 自动建 PR；走对应软件测试与维护者合并 |
| Runtime 发布敏感 | 根 bootstrap、`runtime/**`、consensus、builder registry，以及 `runtime-inputs.v2.json` 定义的 source/recipe/toolchain/policy | 必须 | 完整 request、双 signer/双 faultDomain、receipt 与 promotion |

车道的唯一配置源是 `config/build/contribution-lanes.v1.json`。一键工具要求本地配置 blob 与受信远端 `main` 完全相同，CI 则只读取明确 base commit 中的版本；贡献分支不能在同一提交里自行扩大快速通道。分类只决定协作体验，不替代子栈验证。FLA/XFL/SWF 仍受 Flash 专用门禁约束；策划源数据若会派生 Launcher catalog，仍可能被 runtime policy 门升级为完整检查。未知路径一律进入维护者车道。

Runtime 快速通道采用“受保护集合 + 内容正向识别”，而不是只看扩展名。受保护集合包括当前 23 个 **Launcher runtime payload** 文件（根 bootstrap EXE、Core EXE/DLL/JSON、托管依赖与 native DLL）、manifest、consensus、builder registry、migration marker，以及 `runtime-inputs.v2.json` 从受信任 base 展开的 artifact source、producer recipe、toolchain 和 policy。只有这些对象全部零 diff，且全部变更都命中内容正向根时，提交才能继承 base 已有共识。CI 同时拒绝新增或触碰的 symlink、gitlink、可执行 mode、危险/非规范路径与大小写碰撞，并输出 changed-entry、保护集合及受信 base sentinel 的哈希供审计。

这在运行时完整性维度接近黑名单：碰到受保护集合就升级完整门；但不会采用“未列入黑名单的一律安全”的纯黑名单，因为新增构建入口、策略文件或派生数据很容易随着仓库演进漏列。内容车道仍需命中明确的素材/数据根，混合改动 fail closed 到维护者流程。

这里的 23 项不是整个游戏包的全部可执行物。根 `hotkey_guard.exe`、vendor `Adobe Flash Player 20.exe`、主 `CRAZYFLASHER7MercenaryEmpire.swf`、`scripts/asLoader.swf` 和各素材 SWF 分属 helper/vendor/Flash 发布治理：前四类及其源码进入 CODEOWNERS 维护者门，素材根内 SWF 保留内容快速通道并继续遵守 Flash 发布护栏。不能把“Launcher runtime 未漂移”扩写成“所有游戏二进制均已复现验证”。

## 为什么仍然使用 PR

GitHub required status 必须先附着到一个已经存在于远端的 commit；从本地直接推一个全新 SHA 到受保护 `main` 时，检查尚未产生，服务器会先拒绝该 push。PR 是 GitHub 原生的预合并检查载体，但这一细节由一键工具封装。

`main` 当前要求：

- 必须通过 PR，但普通路径要求 0 个人工审批；
- strict `verify-staged-bundle`，状态来源固定为 GitHub Actions App；
- CODEOWNERS 采用 fail-closed 默认 owner：新增、未知及普通软件路径都要求维护者审阅；只有与 canonical 车道一致的文档/内容正向根显式留空 owner，普通内容路径仍为 0 审批，`config/build/**` 与两份 Launcher 派生目录输入再从内容根中收回；
- 管理员同样受约束，禁止 force-push 与删除；
- 仓库启用 auto-merge 和合并后删除远端贡献分支。

因此“必须经过 required check”不等于“每个合作者都要建立 runtime 共识”。文档或普通资产没有改变受保护集合时，只是在合并前证明既有 runtime 状态仍可继承。

## 一键工具的安全边界

工具只接受以下起点：工作树完全干净、当前不是 merge/rebase/cherry-pick/revert/bisect/sequencer 中间态、提交相对远端 `main` 只 ahead 不 behind。远端已经前进时，工具会停下并给出中文提示，不自行改写历史。Git 可从 PATH、标准 Git for Windows 安装或 GitHub Desktop 自带版本解析；仍找不到时会给出中文安装提示。

合并完成后的清理也要求贡献 commit 已成为远端 `main` 的祖先；满足后才会切回 `main`、`--ff-only` 更新并用普通 `branch -d` 删除本地临时分支。任何祖先关系异常都会保留现场交给维护者。

`gh` 首次使用需要登录：

```powershell
gh auth login
```

命令行等价入口：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/submit-contribution.ps1 -Wait
```

## 何时再考虑拆分资产仓库

只有当原始素材体积已成为主要克隆瓶颈、跨栈原子改动显著减少，并且已经具备“不可变资产包 + 主仓 manifest 锁定 + 自动发布”后，才评估独立资产源仓库。当前直接采用 submodule 或双主线会把同步指针、跨仓提交和漂移处理转嫁给最不熟悉 Git 的合作者，培训成本反而更高。
