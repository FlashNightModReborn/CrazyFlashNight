# AGENTS.md

## 项目概述

闪客快打7佣兵帝国（CF7:ME）单机 MOD。游戏核心仍在 **AS2 / Flash CS6**，但当前工程已经是多栈本地系统：**C# Guardian Launcher + WebView2 / Web + TypeScript / V8 + Rust `sol_parser` + PowerShell / CLI 自动化** 都是现役组成部分。

**本文件角色**：顶层任务路由器 + 硬约束入口。只负责“先看什么、别做错什么”，不重复承载子系统深度实现。  
**最后核对代码基线**：commit `9f8f0c225`（2026-04-20）。

---

## 硬约束（最高优先级）

- **编译限制**：AS2 的实际编译仍只能由 Flash CS6 GUI 完成；在已运行 `scripts/setup_compile_env.bat`、已打开 TestLoader 的前提下，可通过 `scripts/compile_test.ps1` / `scripts/compile_test.sh` 做**有限自动化 smoke 验证**并读取 trace / Output Panel 副本。**当前链路仍在迭代期**，不要把 `publish_done.marker` 单独当作成功依据；没有新鲜 trace、输出日志或 IDE 复核时，不要笼统声称“已编译通过”
- **`.as` 编码**：必须 **UTF-8 with BOM**；新增 / 重建用“复制现有 `.as` → 改名”保留 BOM（见 [as2-anti-hallucination.md](agentsDoc/as2-anti-hallucination.md) §0）
- **SWF**：禁止手动编辑；`scripts/asLoader.swf` 达到可用节点时可提交，其他 SWF 完成功能后封档上传
- **终端编码**（PowerShell）：运行命令前先执行 `chcp.com 65001 | Out-Null`，避免 GBK 乱码
- **可直接修改**：`data/`、`config/` 下 XML（重启生效）
- **验证矩阵**：不要在本文件背命令清单；统一看 [testing-guide.md](agentsDoc/testing-guide.md)
- **不提交**：大型二进制资源、`node_modules`
- **文档同步规则**：凡是路径迁移、协议变更、测试入口变更、构建门槛变更、新子栈引入 / 淘汰，同轮同步更新对应 canonical doc，并运行 `node tools/validate-doc-governance.js`
- **协作元约束**：任务粒度、subagent 边界、prompt 自包含规则统一看 [agent-harness.md](agentsDoc/agent-harness.md);长会话节奏 / 主动行为 / 软停窗口看 [human-care.md](agentsDoc/human-care.md)

---

## Context Packs（按任务最小加载，最后核对 commit `9f8f0c225`）

先判定**主责子栈**，再只读对应文档；跨栈任务先跟主责子栈走，再按依赖补读。

- **AS2 / Flash CS6**：先读 [as2-anti-hallucination.md](agentsDoc/as2-anti-hallucination.md) + [testing-guide.md](agentsDoc/testing-guide.md)；按需补 [FlashCS6自动化编译.md](scripts/FlashCS6自动化编译.md)、[coding-standards.md](agentsDoc/coding-standards.md)、[as2-performance.md](agentsDoc/as2-performance.md)、[game-systems.md](agentsDoc/game-systems.md)
- **XML / 数据与游戏设计**：先读 [data-schemas.md](agentsDoc/data-schemas.md)；按需补 [game-design.md](agentsDoc/game-design.md)、[testing-guide.md](agentsDoc/testing-guide.md)、`0.说明文件与教程/`
- **Launcher Host（C# / WinForms / WebView2 / Bus）**：先读 [launcher/README.md](launcher/README.md) + [architecture.md](agentsDoc/architecture.md)；按需补 [coding-standards.md](agentsDoc/coding-standards.md)、[testing-guide.md](agentsDoc/testing-guide.md)、[tech-stack-rationalization.md](docs/tech-stack-rationalization.md)、[cfn-cli.sh](tools/cfn-cli.sh)
- **Launcher Web / Minigames**：先读 [launcher/README.md](launcher/README.md) + [testing-guide.md](agentsDoc/testing-guide.md)；按需补 [architecture.md](agentsDoc/architecture.md)、`launcher/web/modules/minigames/*/README.md`、`launcher/web/modules/minigames/*/dev/harness.html`
- **Automation / Build / Verification**：先读 [automation/README.md](automation/README.md) + [testing-guide.md](agentsDoc/testing-guide.md)；按需补 [FlashCS6自动化编译.md](scripts/FlashCS6自动化编译.md)、[launcher/README.md](launcher/README.md)、[cfn-cli.sh](tools/cfn-cli.sh)
- **协作 / 任务粒度 / harness**：先读 [agent-harness.md](agentsDoc/agent-harness.md) + [human-care.md](agentsDoc/human-care.md)；按需补 [self-optimization.md](agentsDoc/self-optimization.md)
- **文档治理 / 会话归档**：先读 [documentation-governance.md](agentsDoc/documentation-governance.md) + [self-optimization.md](agentsDoc/self-optimization.md)；按需补 [tech-stack-rationalization.md](docs/tech-stack-rationalization.md)、[shared-notes.md](agentsDoc/shared-notes.md)、[README.md](README.md)

---

## 文档边界

- [AGENTS.md](AGENTS.md)：只写路由、硬约束、触发器
- [README.md](README.md)：人类维护者总览
- [agentsDoc/architecture.md](agentsDoc/architecture.md)：系统拓扑 canonical doc
- [agentsDoc/testing-guide.md](agentsDoc/testing-guide.md)：验证矩阵 canonical doc
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
