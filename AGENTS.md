# AGENTS.md

## 项目概述

闪客快打7佣兵帝国（CF7:ME）单机 MOD。游戏核心仍在 **AS2 / Flash CS6**，但当前工程已经是多栈本地系统：**C# Guardian Launcher + WebView2 / Web + TypeScript / V8 + Rust `sol_parser` + PowerShell / CLI 自动化** 都是现役组成部分。

**本文件角色**：顶层任务路由器 + 硬约束入口。只负责“先看什么、别做错什么”，不重复承载子系统深度实现。  
**最后核对代码基线**：CF7 Agent Runtime / Wings F8 current source commit `53caabc90941826ddacf626f536b0f473adbf049`、tree `5ac63ec05fbbc9b89aa14f7f0b5ab25698f9742d`（2026-07-31）。F7 C1 `dd84230a1d262c6478591cae2d11051b7a8aa7b1` 及其 `candidate_built / NOT_DEPLOYED` 结论保留为历史证据。

---

## 硬约束（最高优先级）

- **编译限制**：AS2 的实际编译仍只能由 Flash CS6 GUI 完成；在已运行 `scripts/setup_compile_env.bat`、已打开 TestLoader 的前提下，可通过 `scripts/compile_test.ps1` / `scripts/compile_test.sh` 做**有限自动化 smoke 验证**并读取 trace / Output Panel 副本。**当前链路仍在迭代期**，不要把 `publish_done.marker` 单独当作成功依据；没有新鲜 trace、输出日志或 IDE 复核时，不要笼统声称“已编译通过”
- **Flash 目标归属**：不要把“改了 `.as`”或“改了 Flash 资产 XML”直接等价为编主文件。默认频率 / 优先级是 `asLoader`（业务逻辑注入，最高频）→ `TestLoader`（闭环调试 / 测试）→ `main`（只代表 `CRAZYFLASHER7MercenaryEmpire` 主 XFL）。独立 UI / 关卡 / 素材库 XFL（如 `flashswf/UI/*/*.xfl`）必须直接 `-Target <xfl> -PublishOnly -VerifySwf <对应.swf>`；选择 `-Target main` 必须能说明触及主文件层
- **`.as` 编码**：必须 **UTF-8 with BOM**；新增 / 重建用“复制现有 `.as` → 改名”保留 BOM（见 [as2-anti-hallucination.md](agentsDoc/as2-anti-hallucination.md) §0）
- **SWF**：禁止手动编辑；`scripts/asLoader.swf` 达到可用节点时可提交，其他 SWF 完成功能后封档上传
- **Launcher 二进制发布**：`launcher/build.ps1` 只是 prepare → pure producer → policy 的本地兼容编排器，不具备发布权。正式发布须冻结 immutable Git-tree request，由通过 `tools/check-runtime-build-env.ps1` 的注册本地 X509 worker 与另一真实 faultDomain（推荐 GitHub hosted OIDC/Sigstore）分别生成同一 build identity / payload closure；GitHub hosted source tag 必须由 API、workflow `GITHUB_SHA` 与 run `headSha` 三重绑定到 requested commit，并由无 bypass 的 tag update/deletion ruleset 冻结。至少两个不同 signer + faultDomain、production policy receipt 与 v2 strict verifier 全通过后，才准用 `tools/promote-runtime-bundle.ps1 -RequestId ...` 原子写 bootstrap、`runtime/`、manifest 与 signed consensus。正式部署现已进入 v2；v1 与一次性 migration marker 只保留为历史审计输入，任何 v2 → v1 降级都必须失败。禁止自由文本 ID 冒充 builder、复制私钥、伪造证明或把单机 candidate 复制到 runtime；完整流程见 [runtime-build-reproducibility.md](docs/runtime-build-reproducibility.md)
- **Launcher 验收术语**：统一使用 `compiled → candidate_built → candidate_executed → e2e_verified → promoted → standard_entry_verified`；`launcher/build.ps1` 最多到 `candidate_built`，候选执行 / E2E 必须绑定实际进程路径、build identity 与 payload closure。F8 candidate `c-0f4c92f237ab-98ebd18146-20260731t022411220z-20da007a` 绑定 identity `0F4C92F237ABD7785C957F3CD135ABF2EFB1EB5D9AB5671B869F39D00970675C` / closure `54FBCCBA7C90ACF407B09E38FFB874C13DE3CDFB80CF62D0F8D4E239A42962F0` / Core `86DF1F5DC611037DB3A85FD9BA0D43490394F232D25A4F62B59AA4F2B4B6E4FD`，已由纯 Agent Runtime MCP 可见旅程达到 `e2e_verified / NOT_DEPLOYED`；本次仅单屏、无 Flash pixels、未跑“13/13”、未 promotion 或标准入口复验，正式 runtime 保持不变。F7 C1 `dd84230a1d262c6478591cae2d11051b7a8aa7b1` 的 exact `candidate_built / NOT_DEPLOYED` 继续作为历史节点。只有 `promoted` 后再从 `automation/start.ps1` / 根 bootstrap 标准入口验证到同一正式身份，才可称“已部署 / 正式验收”；完整证据契约见 [testing-guide.md](agentsDoc/testing-guide.md)
- **主线准入**：所有 write collaborator（含 `Crazyfs`、`Flash-Night`）保留现有客户端 fast-forward 直推，不要求 PR、CODEOWNER 或 required Actions check。普通 docs/data/Flash/XFL/Web-only 不触发 runtime workflow；native 源码 push 后 Audit 可成功报告 `source-ahead`，只有根 EXE、`runtime/**`、manifest/consensus 等部署闭包变化却缺少完整 v2 promotion 时才事后失败报警。远端只保留无 bypass 的 `main` 删除/non-fast-forward 禁令、授权发布者 source-tag creation 与无 bypass tag immutability 三条零 Actions ruleset；GitHub Free 公开仓库没有本方案可用的服务端 path push restriction，Actions 不能撤销已进入 `main` 的提交。正式 release 仍必须本地 X509 + GitHub Hosted OIDC/Sigstore 双 signer、双 faultDomain，无第二人在线前置；完整边界见 [contribution-workflow.md](docs/contribution-workflow.md)
- **XFL / FLA 治理**：FLA 施工后跑 [scripts/tools/xfl/](scripts/tools/xfl/) 三件套（audit / rename_a_class / fix_includes）+ 重扫 [tools/linkage_scanner/scan_linkage.py](tools/linkage_scanner/scan_linkage.py)；linkageId 撞车类冲突一律人工 CS6 修，工具不动；FLA 出现「轴歪 + 编辑闪退 + 无法另存 XFL」三件套查 [FLA-rigPropagationMatrix-溢出导致元件不可编辑.md](scripts/优化随笔/FLA-rigPropagationMatrix-溢出导致元件不可编辑.md)；整体能力分层与触发条件见 [docs/xfl-agent-工具栈-长期路线-2026-05-24.md](docs/xfl-agent-工具栈-长期路线-2026-05-24.md)，Layer 1+ 未到触发条件不要扩张；新增素材库 XFL 需通过 `flashswf/arts/things-new.fla` 作为挂载入口注入，完成功能后重新发布 `things-new.swf`
- **终端编码**（PowerShell）：运行命令前先执行 `chcp.com 65001 | Out-Null`，避免 GBK 乱码
- **Unicode 直写**：代码字符串字面量、注释中直接使用 UTF-8 中文字符；除非目标语境明确要求转义（如协议样例、规范文本或必须 escape 的格式），不要写 `\uXXXX` Unicode 转义
- **可直接修改**：`data/`、`config/` 下 XML（重启生效）
- **验证矩阵**：不要在本文件背命令清单；统一看 [testing-guide.md](agentsDoc/testing-guide.md)
- **不提交**：大型二进制资源、`node_modules`
- **文档同步规则**：凡是路径迁移、协议变更、测试入口变更、构建门槛变更、新子栈引入 / 淘汰，同轮同步更新对应 canonical doc，并运行 `node tools/validate-doc-governance.js`
- **协作元约束**：任务粒度、subagent 边界、prompt 自包含规则统一看 [agent-harness.md](agentsDoc/agent-harness.md);长会话节奏 / 主动行为 / 软停窗口看 [human-care.md](agentsDoc/human-care.md)

---

## Context Packs（按任务最小加载，最后核对 commit `88479aee4c`）

先判定**主责子栈**，再只读对应文档；跨栈任务先跟主责子栈走，再按依赖补读。

- **AS2 / Flash CS6**：先读 [as2-anti-hallucination.md](agentsDoc/as2-anti-hallucination.md) + [testing-guide.md](agentsDoc/testing-guide.md)；按需补 [FlashCS6自动化编译.md](scripts/FlashCS6自动化编译.md)（有编译 / smoke 验证 SWF 需求时即补读）、[coding-standards.md](agentsDoc/coding-standards.md)、[as2-performance.md](agentsDoc/as2-performance.md)、[game-systems.md](agentsDoc/game-systems.md)、[asLoader-README.md](docs/asLoader-README.md)（asLoader 启动序列 / 单帧塌缩 + BootSequencer 任务）；怪物 / 人形装备换皮参考包见 [monster-reskin-pipeline](tools/monster-reskin-pipeline/README.md)，装备生命周期脚本（新增 / 改装备）见 [装备函数 README](scripts/逻辑/装备函数/README.md)
- **AS2 UI → Web Panel 迁移**：先读 [as2-web-panel-migration.md](agentsDoc/as2-web-panel-migration.md) + [launcher/README.md](launcher/README.md) + [testing-guide.md](agentsDoc/testing-guide.md)；按需补 AS2 / Launcher Host / Launcher Web 对应文档
- **XML / 数据与游戏设计**：先读 [data-schemas.md](agentsDoc/data-schemas.md)；按需补 [game-design.md](agentsDoc/game-design.md)、[testing-guide.md](agentsDoc/testing-guide.md)、`0.说明文件与教程/`；**武器 / 技能数值平衡**以 [balance 落盘与复现契约](tools/cf7-balance-tool/docs/agent-balance-record-design.md) 为入口，具体取值查 [武器平衡规则表](tools/cf7-balance-tool/docs/weapon-balance-rulebook.md)；公式最高权威仍是注明的 XLSX，仓库工具只作派生计算与辅助验证
- **Launcher Host（C# / WinForms / WebView2 / Bus）**：先读 [launcher/README.md](launcher/README.md) + [architecture.md](agentsDoc/architecture.md)；玩家信息 NativeHud 的 SVG 真源/渲染基座施工另读 [PlayerInfo B0 专项 ADR](docs/玩家信息界面-NativeHud-SVG真源与程序化动效-B0-ADR与分片施工计划-2026-07-28.md)；CF7 Agent Runtime / Wings Network 有施工、协议评审或范围变更时必读 [一期范围冻结 ADR](docs/CF7-Agent-Runtime与Wings-Network一期-范围冻结-ADR-2026-07-30.md)；按需补 [coding-standards.md](agentsDoc/coding-standards.md)、[testing-guide.md](agentsDoc/testing-guide.md)、[tech-stack-rationalization.md](docs/tech-stack-rationalization.md)、[cfn-cli.sh](tools/cfn-cli.sh)
- **Launcher Web / Minigames**：先读 [launcher/README.md](launcher/README.md) + [testing-guide.md](agentsDoc/testing-guide.md)；按需补 [architecture.md](agentsDoc/architecture.md)、[launcher/perf/README.md](launcher/perf/README.md)（Web overlay 性能优化：消融测试 harness，含施工记录 [docs/web-overlay-perf-A-tier-施工-2026-04-25.md](docs/web-overlay-perf-A-tier-施工-2026-04-25.md)）、`launcher/web/modules/minigames/*/README.md`、`launcher/web/modules/minigames/*/dev/harness.html`
- **Automation / Build / Verification**：先读 [automation/README.md](automation/README.md) + [testing-guide.md](agentsDoc/testing-guide.md)；发布 Launcher runtime 时必读 [runtime-build-reproducibility.md](docs/runtime-build-reproducibility.md)；按需补 [FlashCS6自动化编译.md](scripts/FlashCS6自动化编译.md)（有编译 / smoke 验证 SWF 需求时即补读）、[launcher/README.md](launcher/README.md)、[cfn-cli.sh](tools/cfn-cli.sh)
- **协作 / 任务粒度 / harness**：先读 [agent-harness.md](agentsDoc/agent-harness.md) + [human-care.md](agentsDoc/human-care.md)；按需补 [self-optimization.md](agentsDoc/self-optimization.md)
- **文档治理 / 会话归档**：先读 [documentation-governance.md](agentsDoc/documentation-governance.md) + [self-optimization.md](agentsDoc/self-optimization.md)；按需补 [tech-stack-rationalization.md](docs/tech-stack-rationalization.md)、[shared-notes.md](agentsDoc/shared-notes.md)、[README.md](README.md)

---

## 文档边界

- [AGENTS.md](AGENTS.md)：只写路由、硬约束、触发器
- [README.md](README.md)：人类维护者总览
- [agentsDoc/architecture.md](agentsDoc/architecture.md)：系统拓扑 canonical doc
- [agentsDoc/testing-guide.md](agentsDoc/testing-guide.md)：验证矩阵 canonical doc
- [agentsDoc/as2-web-panel-migration.md](agentsDoc/as2-web-panel-migration.md)：AS2 UI → Web Panel 迁移护栏 canonical doc
- [agentsDoc/agent-harness.md](agentsDoc/agent-harness.md)：Agent 协作与任务粒度 canonical doc
- [agentsDoc/human-care.md](agentsDoc/human-care.md)：人类节奏与会话健康 canonical doc
- [launcher/README.md](launcher/README.md)：Launcher 子系统 source of truth
- [docs/tech-stack-rationalization.md](docs/tech-stack-rationalization.md)：技术栈保留 / 收敛决策

---

## 维护触发器

以下变化发生时，不允许只改代码不改文档：

- 目录迁移或入口文件移动
- C# / Web / AS2 / CLI 协议变更
- 测试或验证入口变更
- 构建链路、依赖版本门槛、运行前置条件变更
- 新子栈引入，或旧子栈停止扩张 / 废弃

触发后按 [documentation-governance.md](agentsDoc/documentation-governance.md) 更新 canonical doc，并运行 `node tools/validate-doc-governance.js`。
