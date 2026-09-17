# 文档治理规则

**文档角色**：文档治理 canonical doc。  
**最后核对代码基线**：commit `c1e51dd1e8dba6bf72452cfef3af8b6f09b36acf`（2026-09-12；本轮核对长期 UI 迁移计划的归属与维护规则）。

## 1. 文档分层

| 层级 | 文件 | 角色 |
|------|------|------|
| 顶层路由 | `AGENTS.md` | 硬约束、按任务读取路由、文档地图 |
| 人类总览 | `README.md` | onboarding、项目总览、快速开始 |
| 主题深文档 | `agentsDoc/*` | 架构、规范、治理等 canonical doc；验证类按 matrix/details 分工：`testing-guide.md` 是验证选择矩阵，`testing-details.md` 是按需验证正文（规范层） |
| 子系统 source of truth | `launcher/README.md` 等 | 稳定架构、入口、职责地图、机器注册表与专题文档索引 |
| 评估 / 路线图 / ADR | `docs/*` | 技术栈评估、审计、决策沉淀 |

## 2. 角色边界

- `AGENTS.md` 不重复堆叠 Launcher / Flash / minigame 的深度实现
- `README.md` 不充当 Agent 规则手册
- `agentsDoc/*` 不负责顶层路由；验证类文档的 matrix/details 分工：矩阵只决定「验什么、何时扩展」，完整 runner、前置与恢复条件进 `testing-details.md`
- 子系统 README 不负责项目级总览
- 同一事实只能有一个 canonical doc；其他文档只做链接和摘要
- `.workbuddy-ai/` 等工具私有会话目录与 `tmp/` 只存本机记忆、临时日志和可重建中间物；持久决策归 `docs/`（原始裁决可归 `docs/裁决存档/`）、复用检查器归 `tools/`、正式素材归所属运行时资产目录。忽略私有目录前，先把唯一一份必要知识迁出并更新引用，不把本机工作量估计变成发布门。
- `human-care.md` 只写约束 Agent / 流程的宪法与负面权利；不得扩展成状态、schema、receipt、acceptance 或发布门
- 事故时间线与量化反例放入 `docs/*` 独立复盘，不把案例堆回高频 canonical doc
- 新增流程必须说明它消除的决策不确定性、为何不能自动化，以及相对人工打断和关键路径的净收益；不能证明就不新增
- 流程时长、revision 数和 token 代理指标只用于触发删减，不得成为需要人类确认的合规对象

## 3. 高变动文档基线规则

以下文档或章节必须显式标注“最后核对代码基线：commit ...”：

- `AGENTS.md`（文档角色行）
- `launcher/README.md` 的源码职责地图、构建/候选/发布、测试入口、Panel / minigame 章节
- `agentsDoc/architecture.md`
- `agentsDoc/testing-guide.md`
- `agentsDoc/testing-details.md`
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
- UI 迁移包的范围、现役消费者、估算前提或交付证据发生实质变化 → 在自然收口节点更新 §6 的同一本迁移台账；不要求逐次工具调用、WIP 提交或等待期间填表
- Launcher 的 `AppConfig` key/环境覆盖、用户偏好 JSON key、Core/Bootstrap CLI、Bootstrap cmd、测试一级分区、Panel id 或 lazy 最终模块变化 → 同步 `launcher/README.md` 对应机器注册表
- 正式 runtime consensus/manifest 或发布列车变化 → 更新机器清单与 `docs/runtime-build-reproducibility.md`；`launcher/README.md` 只保留真源链接，不复制 request/identity/closure、文件数或产物大小
- 稳定玩家包或玩家可见功能列车收口 → 同批更新 `docs/version-archaeology/versions/<version>.md`、`series-index.md`、玩家页 `launcher/web/content/version-history.md` 与可录制的视频提纲；稳定包另补 `release-boundaries.md` 的 Release URL/tag/时间/资产。多次 WIP 允许在收口提交批量登记，不要求逐提交填表；完整证据与措辞契约见 [版本考古维护规范](../docs/version-archaeology/README.md)
- 装备生命周期脚本增删（`scripts/逻辑/装备函数/*.as`）→ 同步 `asLoaderManifest/frame37.as` 接线 + 该目录 `README.md` 索引；依次运行 `node tools/assemble-collapsed-frame.js`、`node tools/assemble-collapsed-frame.js --check`、`node tools/check-bom.js` 与 `node tools/validate-equip-fn-coverage.js`，再由 CS6 重编。`BOOT_SOURCES` 是 live 顶层输入的唯一清单，不得另建平行 frame / stage manifest
- 武器 / 技能数值平衡参数变更（武器 XML `<balance>`、完整审计台账、业务判据或 `tools/cf7-balance-tool` 公式系数）→ 同步 `tools/cf7-balance-tool/docs/agent-balance-record-design.md`；判据变化同时同步 `tools/cf7-balance-tool/docs/weapon-balance-rulebook.md`，并执行设计契约的当前验证矩阵。武器 `balance-sync --check` 与 `balance-check` 是 strict v1 必跑门，但不能单独替代工作簿核对、规则证据审计或 AS2/Web 展示测试；入口路由见 `AGENTS.md` 按任务读取「数据、数值与派生物」

## 5. 回流保护

已知会污染入口认知的旧叙述，统一视为 **migration guard**，不再散落写在高频入口文档里。  
日常文档只写当前真相；针对已知回流模式的拦截，优先交给巡检脚本和本节规则。

当前 guard 重点覆盖：

- 已被淘汰的顶层项目概述
- 已失真的旧运行态 / 旧 server 叙述
- 与当前代码不符的旧版本、旧路径、旧测试入口
- 把发布收据、动态通过数、runId 或事故时间线重新堆入 `launcher/README.md`

## 6. 更新策略

### 先改真源，再同步入口

涉及事实变化时，先改真正的 canonical doc，再改入口页与摘要页。

- `AGENTS.md`：告诉读者去哪里
- `README.md`：告诉维护者项目现在是什么
- 不在入口文档中复制整段深文档内容

### 文档替换优于并存

当旧叙述已经失真时，优先替换；不要在高频入口文档里持续保留“旧说法禁止回流”的解释性段落。

### 可变事实链接到机器真源

runtime 身份/闭包/文件大小、源码注册表和测试分区等可机械提取的事实，由机器文件或代码拥有；文档只保留受校验的摘要/registry，不另建平行手写真源。

### 长期 UI 迁移计划

[剩余迁移台账](../docs/AS2-UI迁移剩余清单与难度评估-2026-09-12.md)是剩余范围、交付包、估算与下一步的唯一汇总入口；文件日期是建账日期，后续原位维护。协议、实现与专项验收仍归对应 canonical doc / ADR。具体字段见台账 §2.1、§8；记账只减少重复调查和排期，不新增审批、状态机、定时汇报或发布门。

- 保留旧条目与交付包 ID；拆分、合并、完成或退役都登记去向，不复用编号或重复计价。调查结论、实施进度、候选/人验/promotion/正式入口业务复验分开记录，不折算成全量完成率。
- 在选包、范围确认、有效候选或阶段收口时合并更新“当前状态、下一步、专项依据、共享写入范围”；有可靠记录才填实际工程投入，并与排队/人验等待分开。缺项由 Agent 补查，不以填表阻断已授权施工。
- 证据 JSON 是绑定输入摘要的历史调查快照，不是实时注册表；新事实追加必要证据并更新正文来源，不为记账重跑全游戏扫描、重编或覆盖旧快照。原始 Agent 报告与会话日志留在临时目录。
- 接续任务先核工作区和在途专项；共享文件由当前施工方维护。其他任务先做互不重叠的整理，提交和推送只纳入已授权范围，不把并发改动一并收走。

<a id="reading-budgets"></a>
## 7. 文档体量预算

入口文档承担的是「让读者快速决策去哪里」，体量失控会直接吞 agent 上下文与人类注意力。预算数值的唯一真源是下面这个机器可解析标记块，巡检器从这里读取，JS 内不再手填第二份常量：

<!-- doc-read-budgets:start -->
{"byteBudgets":{"AGENTS.md":12288,"agentsDoc/testing-guide.md":20480},"lineBudgets":{"CLAUDE.md":20,"README.md":120,"launcher/README.md":430,"agentsDoc/agent-harness.md":90,"agentsDoc/human-care.md":90,"agentsDoc/documentation-governance.md":150,"agentsDoc/self-optimization.md":135},"readability":{"maxLineChars":320,"maxParagraphBytes":2048,"appliesTo":["AGENTS.md","agentsDoc/testing-guide.md"]}}
<!-- doc-read-budgets:end -->

- **字节预算（硬门）**：`AGENTS.md` ≤ 12288 UTF-8 字节、`agentsDoc/testing-guide.md` ≤ 20480 UTF-8 字节。两者取消行数硬门；行数门不得被用作压行激励，新增锚点/章节不受行数门逼迫。
- **行数预算（提示级 warn，不阻断）**：`CLAUDE.md` ≤ 20、`README.md` ≤ 120、`launcher/README.md` ≤ 430、`agentsDoc/agent-harness.md` ≤ 90、`agentsDoc/human-care.md` ≤ 90、本文 ≤ 150、`agentsDoc/self-optimization.md` ≤ 135。超限只提示并解释：新增锚点/章节不受行数门逼迫，应删重复/缩小范围而非压行。
- **可读性规则（硬门）**：散文/表格单行建议 ≤ 320 字符、连续段落建议 ≤ 2 KiB，超限时报告精确位置。默认约束新改入口文件（标记块 `appliesTo` 所列），深层既有债务只报告不阻断。`launcher/README.md` 另有单行 ≤ 320 字符专项硬门。三档中只有字节预算、可读性规则与该 320 字符专项是硬门（error）；其余 7 份文档的行数预算一律提示级（warn）。

**预算原则**：canonical doc 只承载**项目特定**约束；模型已具备的协作通识（prompt 写法、subagent 边界等）不在本仓重复。
**深文档**（架构、`as2-*`、`game-*`、`docs/*`）一般不设硬上限，但应显式标注「文档角色」与基线 commit。

预算超限不是禁止 commit，但应在同一改动里完成「下沉 / 拆分」动作，而不是默默放任增长。

## 8. 巡检脚本

统一使用：

```powershell
chcp.com 65001 | Out-Null
node tools/validate-doc-governance.js
node tools/test-doc-governance.js   # 巡检器纯文本 fixture 单测；改巡检器时必跑
```

当前脚本负责轻量静态巡检：

- 必读文件存在
- `AGENTS.md` 的关键链接存在
- 已知回流模式没有重新进入高频入口文档
- 关键文档包含基线标记或维护约束
- 高变动文档的基线 commit 真实存在于 `git log` 中
- 入口文档体量符合本文 §7 标记块：字节预算与单行/段落可读性为硬门，其余文档行数预算为提示级 warn
- 治理范围内本地 Markdown 链接与 fragment 锚点可解析：含同文件锚点、中文标题 slug、重复标题 `-1`/`-2` 后缀、显式 `<a id>`、引用式链接与 URL 解码；代码围栏内假链接豁免，相对路径不得逃出仓库根；治理闭包名单内文件一律阻断，名单外的新增/改动行（git diff 识别，未跟踪文件全部行算新增）同样阻断，未改动行的既有债务逐条 warn（不静默豁免）
- 四个入口文件（`AGENTS.md`、`CLAUDE.md`、`README.md`、`agentsDoc/testing-guide.md`）的必读边（先读/必读类强指令子句，同行弱词子句不吞）无循环；详见/参考类背景互链不计入
- Launcher 分节基线齐全，本地 Markdown 链接与源码职责路径可解析
- runtime consensus 与 manifest 身份一致，README 不复制可变发布收据和产物数字
- Launcher 配置、用户偏好、CLI、Bootstrap cmd、测试分区、Panel id/最终模块与代码 exact-set 一致
- Bootstrap 早退观察窗与 native 常量一致，旧“启动 Core 后立即退出”叙述不回流
- 世界观稳定节名引用存在对应定义，旧行号锚点不回流

脚本是巡检器，不是 source of truth；规则本身仍以本文为准。
