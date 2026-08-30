# AGENTS.md

## 项目概述

闪客快打7佣兵帝国（CF7:ME）单机 MOD。游戏核心仍在 **AS2 / Flash CS6**，但当前工程已经是多栈本地系统：**C# Guardian Launcher + WebView2 / Web + TypeScript / V8 + Rust `sol_parser` + PowerShell / CLI 自动化** 都是现役组成部分。

**本文件角色**：顶层任务路由器 + 硬约束入口。只负责“先看什么、别做错什么”，不重复承载子系统深度实现。  
**最后核对代码基线**：release source commit `5789d597fbb7af32753fe4a35887b1f2a3a34e10`（2026-08-30；tag `runtime-build-v2/20260830-tester-feedback-stability-v2`、tree `f0151025a88c416a5580ca658c9917ca3a922b4a`、request `90E4BFB9875C73EE6672E89F404763C68E2BF33184AD2ED68421D5C975ECEED6`、deployment `3e23bda255dae09e20e309a12c5b21d86b28f347`）。
本地 X509 `builder-local-a` / `physical-host-a`（keyId `28DBEAF3761CCF3177FE396596A2557D8A6C9393371CD41DC893FF75A02723B3`）与 GitHub OIDC/Sigstore builder `0DA07505D82F271D66FB0CFEB0E1ABB16BF7652CB94C6184EAF424243BDD8B95` / `github-hosted-windows`（cloud run `33288898204`）已对 identity `9B146D22C82925853757DCA8D63CDDBECD31CD19C43EC1771F6B26D8F5824CEE`、closure `C8B22C4532AD259E4C514BED30C87DC016E2FE17F9C001158F4CF18F900E1C94` 达成 v2 双 signer / 双故障域共识；正式 Core DLL SHA-256 为 `783ED17121AF986074894A4BEC0D09B28046FE7BD068F8F3522174462936A529`，39/39 production receipt SHA-256 为 `E35133850D7DBAD88B3AD9EF28ACC44E9DA8D097D29C3EC719C6A1294578FF79`；deployment commit `3e23bda255dae09e20e309a12c5b21d86b28f347` 与首次 post-promotion audit run `33289302965` 已推送/通过，审计明确输出 `state=promoted`、`deploymentChanged=true`。

**状态边界**：本列车修复测试员暴露的关卡奖励持久化与即时交付投影、Loot v2 自动入栏、药剂 v3 原槽 affinity、空背包装备调制关闭、动态插件槽容量，以及 NativeHud/Panel close 的前台所有权判定。production policy `39/39`、worktree/index 33-file bundle、signed consensus、原子 promotion、正式根 bootstrap `--verify-only` 与 post-promotion Audit 均通过。
准确状态为 `promoted / FIELD_REVALIDATION_PENDING`。部署后只执行根 bootstrap 完整性验证，没有在测试员的 QQ/直播环境重跑抢焦、战斗空调制关闭、通关后立即交付、领奖重启读回或槽 4 血瓶三来源回原槽，因此不称本增量 `e2e_verified`、`HUMAN_ACCEPTANCE_PASSED` 或业务 `standard_entry_verified`。斗兽 Gate F campaign 与 Audio H2 继续保持各自独立门，不能由本次通用 runtime promotion 代签。

---

## 硬约束（最高优先级）

- **人类注意力与工程效率宪法**：在授权、安全与真实性不退让的前提下，以减少人类同步负担、缩短真实交付关键路径为第一原则；已授权、范围内且可恢复的机器工作默认无人值守继续。只有新权限、不可逆外部动作、实质产品取舍或不可替代的人类感知才可打断；不得把 human-care 变成状态机、receipt、逐字 acceptance 或发布门。完整边界见 [human-care.md](agentsDoc/human-care.md)
- **编译限制**：AS2 的实际编译仍只能由 Flash CS6 GUI 完成；在已运行 `scripts/setup_compile_env.bat`、已打开 TestLoader 的前提下，可通过 `scripts/compile_test.ps1` / `scripts/compile_test.sh` 做**有限自动化 smoke 验证**并读取 trace / Output Panel 副本。**当前链路仍在迭代期**，不要把 `publish_done.marker` 单独当作成功依据；没有新鲜 trace、输出日志或 IDE 复核时，不要笼统声称“已编译通过”
- **Flash 目标归属**：不要把“改了 `.as`”或“改了 Flash 资产 XML”直接等价为编主文件。默认频率 / 优先级是 `asLoader`（业务逻辑注入，最高频）→ `TestLoader`（闭环调试 / 测试）→ `main`（只代表 `CRAZYFLASHER7MercenaryEmpire` 主 XFL）。独立 UI / 关卡 / 素材库 XFL（如 `flashswf/UI/*/*.xfl`）必须直接 `-Target <xfl> -PublishOnly -VerifySwf <对应.swf>`；选择 `-Target main` 必须能说明触及主文件层
- **`.as` 编码**：必须 **UTF-8 with BOM**；新增 / 重建用“复制现有 `.as` → 改名”保留 BOM（见 [as2-anti-hallucination.md](agentsDoc/as2-anti-hallucination.md) §0）
- **SWF**：禁止手动编辑；`scripts/asLoader.swf` 达到可用节点时可提交，其他 SWF 完成功能后封档上传
- **Launcher 二进制发布**：`launcher/build.ps1` 只是 prepare → pure producer → policy 的本地兼容编排器，不具备发布权。正式发布须冻结 immutable Git-tree request，由通过 `tools/check-runtime-build-env.ps1` 的注册本地 X509 worker 与另一真实 faultDomain（推荐 GitHub hosted OIDC/Sigstore）分别生成同一 build identity / payload closure；GitHub hosted source tag 必须由 API、workflow `GITHUB_SHA` 与 run `headSha` 三重绑定到 requested commit，并由无 bypass 的 tag update/deletion ruleset 冻结。至少两个不同 signer + faultDomain、production policy receipt 与 v2 strict verifier 全通过后，才准用 `tools/promote-runtime-bundle.ps1 -RequestId ...` 原子写 bootstrap、`runtime/`、manifest 与 signed consensus。正式部署现已进入 v2；v1 与一次性 migration marker 只保留为历史审计输入，任何 v2 → v1 降级都必须失败。禁止自由文本 ID 冒充 builder、复制私钥、伪造证明或把单机 candidate 复制到 runtime；完整流程见 [runtime-build-reproducibility.md](docs/runtime-build-reproducibility.md)
- **发布门分层**：通用 runtime promotion 只承载 supply-chain/部署完整性，不得读取 Audio H1/H2/E3、截图、听感或其他产品体验证据，也不得为体验 `pending` 创建 emergency 旁路状态机。功能专项证据只决定对应功能能否声称 `e2e_verified` / `standard_entry_verified`；真正影响 DLL 的 source/recipe/toolchain 仍必须进入 immutable request 与双构建闭包。
- **Launcher 验收术语**：统一使用 `compiled → candidate_built → candidate_executed → e2e_verified → promoted → standard_entry_verified`；`launcher/build.ps1` 最多到 `candidate_built`，候选执行 / E2E 必须绑定实际进程路径、build identity 与 payload closure。F8 正式 release tag `runtime-build-v2/20260731-agent-runtime-wings-f8-v1` / request `A9B33601805709DBB5EAE6DAF312C2B7B0B502096FDD3BDCEA9CBE26D8B1299C` 已由本地 X509 `physical-host-a` 与 GitHub OIDC/Sigstore `github-hosted-windows` 对 identity `0F4C92F237ABD7785C957F3CD135ABF2EFB1EB5D9AB5671B869F39D00970675C` / closure `54FBCCBA7C90ACF407B09E38FFB874C13DE3CDFB80CF62D0F8D4E239A42962F0` 达成共识并 promotion；随后无 candidate id 的正式入口以纯 Agent Runtime MCP 完成可见帮助面板、可信 shutdown 与无新增残留差量复验，严格达到 `standard_entry_verified`。该结论仍只覆盖单屏、Flash metadata-only、Launcher/NativeHud/WebOverlay WGC 与 `panel.open`，不外推为物理双屏、“13/13”、Flash pixels/input、Hair 或 Wings 完整产品验收。F8 早期隔离 candidate 的 `e2e_verified / NOT_DEPLOYED` 与 F7 C1 的 `candidate_built / NOT_DEPLOYED` 继续作为历史节点；完整证据契约见 [testing-guide.md](agentsDoc/testing-guide.md)
- **主线准入**：所有 write collaborator（含 `Crazyfs`、`Flash-Night`）保留现有客户端 fast-forward 直推，不要求 PR、CODEOWNER 或 required Actions check。普通 docs/data/Flash/XFL/Web-only 不触发 runtime workflow；native 源码 push 后 Audit 可成功报告 `source-ahead`，只有根 EXE、`runtime/**`、manifest/consensus 等部署闭包变化却缺少完整 v2 promotion 时才事后失败报警。远端只保留无 bypass 的 `main` 删除/non-fast-forward 禁令、授权发布者 source-tag creation 与无 bypass tag immutability 三条零 Actions ruleset；GitHub Free 公开仓库没有本方案可用的服务端 path push restriction，Actions 不能撤销已进入 `main` 的提交。正式 release 仍必须本地 X509 + GitHub Hosted OIDC/Sigstore 双 signer、双 faultDomain，无第二人在线前置；完整边界见 [contribution-workflow.md](docs/contribution-workflow.md)
- **XFL / FLA 治理**：FLA 施工后跑 [scripts/tools/xfl/](scripts/tools/xfl/) 三件套（audit / rename_a_class / fix_includes）+ 重扫 [tools/linkage_scanner/scan_linkage.py](tools/linkage_scanner/scan_linkage.py)；linkageId 撞车类冲突一律人工 CS6 修，工具不动；FLA 出现「轴歪 + 编辑闪退 + 无法另存 XFL」三件套查 [FLA-rigPropagationMatrix-溢出导致元件不可编辑.md](scripts/优化随笔/FLA-rigPropagationMatrix-溢出导致元件不可编辑.md)；整体能力分层与触发条件见 [docs/xfl-agent-工具栈-长期路线-2026-05-24.md](docs/xfl-agent-工具栈-长期路线-2026-05-24.md)，Layer 1+ 未到触发条件不要扩张；新增素材库 XFL 需通过 `flashswf/arts/things-new.fla` 作为挂载入口注入，完成功能后重新发布 `things-new.swf`
- **终端编码**（PowerShell）：运行命令前先执行 `chcp.com 65001 | Out-Null`，避免 GBK 乱码
- **Unicode 直写**：代码字符串字面量、注释中直接使用 UTF-8 中文字符；除非目标语境明确要求转义（如协议样例、规范文本或必须 escape 的格式），不要写 `\uXXXX` Unicode 转义
- **可直接修改**：`data/`、`config/` 下 XML（重启生效）
- **验证矩阵**：不要在本文件背命令清单；统一看 [testing-guide.md](agentsDoc/testing-guide.md)
- **协作约束**：commit 标题必须全中文（允许保留 `docs:` 等类型前缀），写清改了什么、测试员需要回归什么；`git worktree` 非必要不新建、用后必清理、残留必报告。细则见 [contribution-workflow.md](docs/contribution-workflow.md) 的"提交信息约定"与"worktree 使用纪律"两节
- **不提交**：`node_modules`，以及未受版本化生成器、manifest 逐文件引用、完整性验证与体积审计共同约束的大型二进制/临时证据。确属游戏运行时且进入上述可复验闭包的正式素材（例如 dressup、portrait 发布资产）是显式例外；`tmp/` 候选、联系表、模型缓存和可由闭包重建的中间产物仍不得借此入库
- **文档同步规则**：凡是路径迁移、协议变更、测试入口变更、构建门槛变更、新子栈引入 / 淘汰，同轮同步更新对应 canonical doc，并运行 `node tools/validate-doc-governance.js`
- **协作元约束**：任务粒度、subagent 边界、无人值守执行与验证成本统一看 [agent-harness.md](agentsDoc/agent-harness.md)；人类注意力、同步打断与流程防腐统一看 [human-care.md](agentsDoc/human-care.md)

---

## Context Packs（按任务最小加载，最后核对 commit `86de257152c23536ae4590c6e8b42585aeaca290`）

先判定**主责子栈**，再只读对应文档；跨栈任务先跟主责子栈走，再按依赖补读。

- **AS2 / Flash CS6**：先读 [as2-anti-hallucination.md](agentsDoc/as2-anti-hallucination.md) + [testing-guide.md](agentsDoc/testing-guide.md)；按需补 [FlashCS6自动化编译.md](scripts/FlashCS6自动化编译.md)（有编译 / smoke 验证 SWF 需求时即补读）、[coding-standards.md](agentsDoc/coding-standards.md)、[as2-performance.md](agentsDoc/as2-performance.md)、[game-systems.md](agentsDoc/game-systems.md)、[asLoader-README.md](docs/asLoader-README.md)（asLoader 启动序列 / 单帧塌缩 + BootSequencer 任务）；怪物 / 人形装备换皮参考包见 [monster-reskin-pipeline](tools/monster-reskin-pipeline/README.md)，装备生命周期脚本（新增 / 改装备）见 [装备函数 README](scripts/逻辑/装备函数/README.md)
- **AS2 UI → Web Panel 迁移**：先读 [as2-web-panel-migration.md](agentsDoc/as2-web-panel-migration.md) + [launcher/README.md](launcher/README.md) + [testing-guide.md](agentsDoc/testing-guide.md)；按需补 AS2 / Launcher Host / Launcher Web 对应文档
- **XML / 数据与游戏设计**：先读 [data-schemas.md](agentsDoc/data-schemas.md)；按需补 [game-design.md](agentsDoc/game-design.md)、[testing-guide.md](agentsDoc/testing-guide.md)、`0.说明文件与教程/`；**武器 / 技能数值平衡**以 [balance 落盘与复现契约](tools/cf7-balance-tool/docs/agent-balance-record-design.md) 为入口，具体取值查 [武器平衡规则表](tools/cf7-balance-tool/docs/weapon-balance-rulebook.md)；公式最高权威仍是注明的 XLSX，仓库工具只作派生计算与辅助验证
- **Launcher Host（C# / WinForms / WebView2 / Bus）**：先读 [launcher/README.md](launcher/README.md) + [architecture.md](agentsDoc/architecture.md)；原生音频引擎、格式能力、桥接或真实端点验证施工/评审另读 [Audio Platform v2 ADR](docs/原生音频平台-v2-格式能力桥接契约与可观测性-ADR-2026-08-09.md)；玩家信息 NativeHud 的 SVG 真源/渲染基座施工另读 [PlayerInfo B0 专项 ADR](docs/玩家信息界面-NativeHud-SVG真源与程序化动效-B0-ADR与分片施工计划-2026-07-28.md)；CF7 Agent Runtime / Wings Network 有施工、协议评审或范围变更时必读 [一期范围冻结 ADR](docs/CF7-Agent-Runtime与Wings-Network一期-范围冻结-ADR-2026-07-30.md)；按需补 [coding-standards.md](agentsDoc/coding-standards.md)、[testing-guide.md](agentsDoc/testing-guide.md)、[tech-stack-rationalization.md](docs/tech-stack-rationalization.md)、[cfn-cli.sh](tools/cfn-cli.sh)
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
- [agentsDoc/human-care.md](agentsDoc/human-care.md)：人类注意力与工程效率宪法 canonical doc
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
