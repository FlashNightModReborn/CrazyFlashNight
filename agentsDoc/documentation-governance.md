# 文档治理规则

**文档角色**：文档治理 canonical doc。  
**最后核对代码基线**：commit `04718fa57afb64836e95893f0c4ff821d25ca043`（2026-08-16）。

## 1. 文档分层

| 层级 | 文件 | 角色 |
|------|------|------|
| 顶层路由 | `AGENTS.md` | 任务路由、硬约束、Context Packs、文档地图 |
| 人类总览 | `README.md` | onboarding、项目总览、快速开始 |
| 主题深文档 | `agentsDoc/*` | 架构、测试、规范、治理等 canonical doc |
| 子系统 source of truth | `launcher/README.md` 等 | 稳定架构、入口、职责地图、机器注册表与专题文档索引 |
| 评估 / 路线图 / ADR | `docs/*` | 技术栈评估、审计、决策沉淀 |

## 2. 角色边界

- `AGENTS.md` 不重复堆叠 Launcher / Flash / minigame 的深度实现
- `README.md` 不充当 Agent 规则手册
- `agentsDoc/*` 不负责顶层路由
- 子系统 README 不负责项目级总览
- 同一事实只能有一个 canonical doc；其他文档只做链接和摘要
- `human-care.md` 只写约束 Agent / 流程的宪法与负面权利；不得扩展成状态、schema、receipt、acceptance 或发布门
- 事故时间线与量化反例放入 `docs/*` 独立复盘，不把案例堆回高频 canonical doc
- 新增流程必须说明它消除的决策不确定性、为何不能自动化，以及相对人工打断和关键路径的净收益；不能证明就不新增
- 流程时长、revision 数和 token 代理指标只用于触发删减，不得成为需要人类确认的合规对象

## 3. 高变动文档基线规则

以下文档或章节必须显式标注“最后核对代码基线：commit ...”：

- `AGENTS.md` 的项目概述与 Context Packs
- `launcher/README.md` 的源码职责地图、构建/候选/发布、测试入口、Panel / minigame 章节
- `agentsDoc/architecture.md`
- `agentsDoc/testing-guide.md`
- `agentsDoc/as2-web-panel-migration.md`
- `agentsDoc/workbench-ui-system.md`
- `agentsDoc/agent-harness.md`
- `agentsDoc/human-care.md`
- `agentsDoc/documentation-governance.md`
- `agentsDoc/self-optimization.md`
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
- Launcher 的 `AppConfig` key/环境覆盖、用户偏好 JSON key、Core/Bootstrap CLI、Bootstrap cmd、测试一级分区、Panel id 或 lazy 最终模块变化 → 同步 `launcher/README.md` 对应机器注册表
- 正式 runtime consensus/manifest 或发布列车变化 → 更新机器清单与 `docs/runtime-build-reproducibility.md`；`launcher/README.md` 只保留真源链接，不复制 request/identity/closure、文件数或产物大小
- 稳定玩家包或玩家可见功能列车收口 → 同批更新 `docs/version-archaeology/versions/<version>.md`、`series-index.md`、玩家页 `launcher/web/content/version-history.md` 与可录制的视频提纲；稳定包另补 `release-boundaries.md` 的 Release URL/tag/时间/资产。多次 WIP 允许在收口提交批量登记，不要求逐提交填表；完整证据与措辞契约见 [版本考古维护规范](../docs/version-archaeology/README.md)
- 装备生命周期脚本增删（`scripts/逻辑/装备函数/*.as`）→ 同步 `asLoaderManifest/frame37.as` 接线 + 该目录 `README.md` 索引；依次运行 `node tools/assemble-collapsed-frame.js`、`node tools/assemble-collapsed-frame.js --check`、`node tools/check-bom.js` 与 `node tools/validate-equip-fn-coverage.js`，再由 CS6 重编。`BOOT_SOURCES` 是 live 顶层输入的唯一清单，不得另建平行 frame / stage manifest
- 武器 / 技能数值平衡参数变更（武器 XML `<balance>`、完整审计台账、业务判据或 `tools/cf7-balance-tool` 公式系数）→ 同步 `tools/cf7-balance-tool/docs/agent-balance-record-design.md`；判据变化同时同步 `tools/cf7-balance-tool/docs/weapon-balance-rulebook.md`，并执行设计契约的当前验证矩阵。武器 `balance-sync --check` 与 `balance-check` 是 strict v1 必跑门，但不能单独替代工作簿核对、规则证据审计或 AS2/Web 展示测试；入口路由见 `AGENTS.md` Context Packs「XML / 数据与游戏设计」

## 5. 回流保护

已知会污染入口认知的旧叙述，统一视为 **migration guard**，不再散落写在高频入口文档里。  
日常文档只写当前真相；针对已知回流模式的拦截，优先交给巡检脚本和本节规则。

当前 guard 重点覆盖：

- 已被淘汰的顶层项目概述
- 已失真的旧运行态 / 旧 server 叙述
- 与当前代码不符的旧版本、旧路径、旧测试入口
- 把发布收据、动态通过数、runId 或事故时间线重新堆入 `launcher/README.md`

## 6. 更新策略

### 先改 canonical doc

涉及事实变化时，先改真正的 canonical doc，再改入口页与摘要页。

### 入口页只做摘要

- `AGENTS.md`：告诉读者去哪里
- `README.md`：告诉维护者项目现在是什么
- 不在入口文档中复制整段深文档内容

### 文档替换优于并存

当旧叙述已经失真时，优先替换；不要在高频入口文档里持续保留“旧说法禁止回流”的解释性段落。

### 可变事实链接到机器真源

runtime 身份/闭包/文件大小、源码注册表和测试分区等可机械提取的事实，由机器文件或代码拥有；文档只保留受校验的摘要/registry，不另建平行手写真源。

## 7. 文档体量预算

入口文档承担的是「让读者快速决策去哪里」,行数失控会直接吞 agent 上下文与人类注意力。  
本仓的预算如下,巡检脚本会硬校验:

| 文档 | 角色 | 行数预算 | 超限处理 |
|------|------|----------|----------|
| `AGENTS.md` | 顶层路由 | ≤ 80 | 路由项太多 → 拆 Context Pack 类别;深内容 → 下沉到 canonical doc |
| `CLAUDE.md` | Claude 入口卡 | ≤ 20 | 几乎只剩链接;新规则进 AGENTS.md 或 canonical doc |
| `README.md` | 人类总览 | ≤ 120 | 教程 / 历史 / 营销话术全部下沉 |
| `launcher/README.md` | Launcher 高频深文档 | ≤ 430，单行 ≤ 320 字符 | 发布收据 / 动态计数下沉；长协议拆专题文档 |
| `agentsDoc/testing-guide.md` | 验证矩阵 | ≤ 114 | 命令表格化;细节下沉到子系统 README |
| `agentsDoc/agent-harness.md` | 协作 / harness | ≤ 90 | 只写项目特定;模型通识(prompt 写法、subagent 概念)不进 |
| `agentsDoc/human-care.md` | 注意力 / 效率宪法 | ≤ 90 | 只写负面约束与无人值守默认；案例下沉复盘 |
| `agentsDoc/documentation-governance.md` | 文档治理 | ≤ 150 | 案例下沉到 shared-notes |
| `agentsDoc/self-optimization.md` | 自优化 | ≤ 135 | — |

**预算原则**:Opus 4.7+ 等新一代模型已具备大量协作通识,canonical doc 应只承载**项目特定**约束。模型已知道的(prompt 自包含、subagent 边界、不要 outsource thinking 等),不在本仓重复。

**深文档**（架构、`as2-*`、`game-*`、`docs/*`）一般不设硬上限，但应显式标注「文档角色」与基线 commit；高频 `launcher/README.md` 采用上表专项预算。

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
- Launcher 分节基线齐全，本地 Markdown 链接与源码职责路径可解析
- runtime consensus 与 manifest 身份一致，README 不复制可变发布收据和产物数字
- Launcher 配置、用户偏好、CLI、Bootstrap cmd、测试分区、Panel id/最终模块与代码 exact-set 一致
- Bootstrap 早退观察窗与 native 常量一致，旧“启动 Core 后立即退出”叙述不回流
- 世界观稳定节名引用存在对应定义，旧行号锚点不回流

脚本是巡检器，不是 source of truth；规则本身仍以本文为准。
