# 文档治理规则

**文档角色**：文档治理 canonical doc。  
**最后核对代码基线**：commit `d4f31beee`（2026-04-20）。

## 1. 文档分层

| 层级 | 文件 | 角色 |
|------|------|------|
| 顶层路由 | `AGENTS.md` | 任务路由、硬约束、Context Packs、文档地图 |
| 人类总览 | `README.md` | onboarding、项目总览、快速开始 |
| 主题深文档 | `agentsDoc/*` | 架构、测试、规范、治理等 canonical doc |
| 子系统 source of truth | `launcher/README.md` 等 | 子系统内部结构、协议、验证、路径 |
| 评估 / 路线图 / ADR | `docs/*` | 技术栈评估、审计、决策沉淀 |

## 2. 角色边界

- `AGENTS.md` 不重复堆叠 Launcher / Flash / minigame 的深度实现
- `README.md` 不充当 Agent 规则手册
- `agentsDoc/*` 不负责顶层路由
- 子系统 README 不负责项目级总览
- 同一事实只能有一个 canonical doc；其他文档只做链接和摘要

## 3. 高变动文档基线规则

以下文档或章节必须显式标注“最后核对代码基线：commit ...”：

- `AGENTS.md` 的项目概述与 Context Packs
- `launcher/README.md` 的目录树、测试入口、Panel / minigame 章节
- `agentsDoc/architecture.md`
- `agentsDoc/testing-guide.md`
- `docs/tech-stack-rationalization.md`

如果改动只是文档本身而非代码，也仍以**最后核对的代码基线**为准，不写“文档修改日期”替代代码基线。

## 4. 维护触发器

出现以下变化时，必须同步维护文档：

- 目录迁移或入口文件变化
- 协议 / schema / wire shape 变化
- 测试与验证入口变化
- 构建链路、依赖门槛、环境前置条件变化
- 新子栈引入，或旧子栈停止扩张 / 退役
- source of truth 从一个文档转移到另一个文档

## 5. 回流保护

已知会污染入口认知的旧叙述，统一视为 **migration guard**，不再散落写在高频入口文档里。  
日常文档只写当前真相；针对已知回流模式的拦截，优先交给巡检脚本和本节规则。

当前 guard 重点覆盖：

- 已被淘汰的顶层项目概述
- 已失真的旧运行态 / 旧 server 叙述
- 与当前代码不符的旧版本、旧路径、旧测试入口

## 6. 更新策略

### 先改 canonical doc

涉及事实变化时，先改真正的 canonical doc，再改入口页与摘要页。

### 入口页只做摘要

- `AGENTS.md`：告诉读者去哪里
- `README.md`：告诉维护者项目现在是什么
- 不在入口文档中复制整段深文档内容

### 文档替换优于并存

当旧叙述已经失真时，优先替换；不要在高频入口文档里持续保留“旧说法禁止回流”的解释性段落。

## 7. 文档体量预算

入口文档承担的是「让读者快速决策去哪里」,行数失控会直接吞 agent 上下文与人类注意力。  
本仓的预算如下,巡检脚本会硬校验:

| 文档 | 角色 | 行数预算 | 超限处理 |
|------|------|----------|----------|
| `AGENTS.md` | 顶层路由 | ≤ 80 | 路由项太多 → 拆 Context Pack 类别;深内容 → 下沉到 canonical doc |
| `CLAUDE.md` | Claude 入口卡 | ≤ 20 | 几乎只剩链接;新规则进 AGENTS.md 或 canonical doc |
| `README.md` | 人类总览 | ≤ 120 | 教程 / 历史 / 营销话术全部下沉 |
| `agentsDoc/testing-guide.md` | 验证矩阵 | ≤ 110 | 命令表格化;细节下沉到子系统 README |
| `agentsDoc/agent-harness.md` | 协作 / harness | ≤ 90 | 只写项目特定;模型通识(prompt 写法、subagent 概念)不进 |
| `agentsDoc/human-care.md` | 人类节奏 | ≤ 90 | 节奏 / 信号 / 主动行为表格化;不重复 self-optimization |
| `agentsDoc/documentation-governance.md` | 文档治理 | ≤ 130 | 案例下沉到 shared-notes |
| `agentsDoc/self-optimization.md` | 自优化 | ≤ 130 | — |

**预算原则**:Opus 4.7+ 等新一代模型已具备大量协作通识,canonical doc 应只承载**项目特定**约束。模型已知道的(prompt 自包含、subagent 边界、不要 outsource thinking 等),不在本仓重复。

**深文档**（架构、子系统 README、`as2-*`、`game-*`、`docs/*`）不设硬上限,但应显式标注「文档角色」与基线 commit。

预算超限不是禁止 commit,但应在同一改动里完成「下沉 / 拆分」动作,而不是默默放任增长。

## 8. 巡检脚本

统一使用：

```powershell
chcp.com 65001 | Out-Null
node tools/validate-doc-governance.js
```

当前脚本负责轻量静态巡检：

- 必读文件存在
- `AGENTS.md` 的关键链接存在
- 已知回流模式没有重新进入高频入口文档
- 关键文档包含基线标记或维护约束
- 高变动文档的基线 commit 真实存在于 `git log` 中
- 入口文档行数没有突破本文 §7 的预算

脚本是巡检器，不是 source of truth；规则本身仍以本文为准。
