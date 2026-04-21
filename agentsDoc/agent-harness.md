# Agent 协作与 harness 实践

**文档角色**：Agent 协作 / 任务粒度 canonical doc。  
**最后核对代码基线**：commit `9f8f0c225`（2026-04-20）。

只写**项目特定**约束。Prompt 写法、subagent 概念、self-contained 这类通识不在本文重复。

## 1. 任务粒度软上限

| 维度 | 软上限 | 超过的处理 |
|------|--------|------------|
| 改动文件数 | 6-8 | 拆 commit / 拆 PR |
| 单次新增 / 重写行数 | ~400 | 分阶段,每阶段独立可验证 |
| 涉及子栈数 | 2 | 跨 3 个起,先做拓扑图与边界声明 |
| 单文件改动行数 | ~200 | 倾向拆函数或拆 commit |
| 验证耗时 | <2 min | 提供「快速 smoke」与「完整套件」两档 |

超出阈值不是禁止,但应在动手前显式说明「为什么这次只能整体做」。

### 拆分信号(任一触发就停下来重拆)

- 写到一半要回头改前半段接口
- 计划里突然出现「顺便」「同时」「再把 X 也」
- 一次 commit 同时包含「修 bug + 改架构 + 加测试」
- 同时改 AS2 + Launcher + 文档

## 2. Subagent 边界

主线判断不能外包。Subagent 适合:多轮搜索定位、调研型问题、大量原始日志(不该进主上下文)、独立可并行的工作。**不适合**:路径已知的单文件改、需要主线设计判断的核心实现。

## 3. 可重入验证(项目硬约束)

所有 agent 启动的验证脚本必须 idempotent、可中断、结果显式。

### Flash smoke 的特殊性

`scripts/compile_test.ps1` 退出 0 **不等于**编译成功。判据看新鲜的:

- `scripts/flashlog.txt`(本次运行生成)
- `scripts/compiler_errors.txt`(无新错误)
- `publish_done.marker` 仅说明 JSFL 触发结束

详见 [testing-guide.md §2](testing-guide.md)。

### Harness-first 约定

- UI / overlay / minigame 行为变更，优先补现有 `dev/harness.html`、`qa-suite.js` 或静态校验；不要只留“人工点一下”的说明
- Node QA 负责确定性 / core 状态流；browser harness 负责协议 / DOM / 布局 / 交互；静态校验负责结构与旧入口回流拦截
- 新增 harness 用例应可重跑、可断言、结果结构化；优先提供 query 参数、脚本场景或固定入口，而不是临时控制台片段

## 4. 项目特定失败模式

### 4.1 终态错觉

「脚本退出 0 = 任务完成」。Flash smoke 退出 0 但 trace 是上一次的;minigame QA 跑了但用例数为 0。**对策**:看具体输出,不看退出码。

### 4.2 沉默的回退

发现验证不通过,默默改条件让它通过(放宽断言、跳过用例、改阈值)。**对策**:失败先报告,改判据要主线显式同意。

### 4.3 上下文饱和后硬撑

主上下文已塞满 diff / 日志,仍尝试继续大改动。**对策**:进入「归档 + 重启会话」模式,把进度写到 plan 或 memory。详见 [self-optimization.md](self-optimization.md)。

## 5. 收尾话术

- 全跑通:`已跑 <验证 A> / <验证 B>,结果 <具体特征>`
- 部分跑通:`已跑 <A>;<B> 因为 <原因> 没跑,需要人工 <动作>`
- 拿不到信号:`改动已落地但缺少 <信号>,无法判断是否成功`

不要说:`应该可以了` / `已经 work` / 在没有 trace 时说`编译通过`。

## 6. 关联文档

- 验证命令清单 → [testing-guide.md](testing-guide.md)
- 长会话节奏 / 主动行为 → [human-care.md](human-care.md)
- 会话归档 → [self-optimization.md](self-optimization.md)
- 文档治理 → [documentation-governance.md](documentation-governance.md)
