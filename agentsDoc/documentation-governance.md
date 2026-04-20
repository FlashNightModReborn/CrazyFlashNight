# 文档治理规则

**文档角色**：文档治理 canonical doc。  
**最后核对代码基线**：commit `c2118e295`（2026-04-20）。

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

## 7. 巡检脚本

统一使用：

```powershell
chcp.com 65001 | Out-Null
node tools/validate-doc-governance.js
```

当前脚本负责轻量静态巡检：

- `AGENTS.md` 的关键链接存在
- 已知回流模式没有重新进入高频入口文档
- 关键文档包含基线标记或维护约束
- 关键版本号与 canonical 文档没有明显冲突

脚本是巡检器，不是 source of truth；规则本身仍以本文为准。
