# Agent 协作与 harness 实践

**文档角色**：Agent 协作 / 任务粒度 / 无人值守执行 canonical doc。
**最后核对代码基线**：commit `539fa306181da40d092c03508afdbddef18eff8d`（2026-08-15）。

只写项目特定约束。协作目标不是制造更多可见步骤，而是在 [human-care.md](human-care.md) 的边界内，把真实产品结果更快、可恢复地交付。

## 1. 任务粒度软上限

| 维度 | 软上限 | 超过的处理 |
|------|--------|------------|
| 改动文件数 | 6-8 | 内部拆分可验证 patch / 阶段；commit 仅在任务已授权时执行 |
| 单次新增 / 重写行数 | ~400 | 分阶段，每阶段保持可运行或可回滚 |
| 涉及子栈数 | 2 | 跨 3 个起先声明拓扑、主责栈与接口边界 |
| 单文件改动行数 | ~200 | 倾向拆函数或隔离机械生成内容 |
| 快速验证耗时 | <2 min | 同时提供快速 smoke 与完整套件 |

超限首先改变 Agent 的内部施工方式；只有 scope、风险或不可逆性实质变化时才请求用户重新决策。

## 2. 人机职责边界

| 责任方 | 默认负责 |
|--------|----------|
| 人类 | 产品目标、风险偏好、外部 mutation 权限、不可逆取舍、真实听感 / 目视 / 物理判断 |
| Agent | 搜索、哈希、worktree、实现、测试、重试、等待 / resume、构建、证据整理、状态传递，以及已具体授权的发布执行 |

默认交互形态是：**一次 scope 授权 → 无人值守施工 → 一次合并后的产品验收或不可逆决定 → 完成**。commit、tree、request、runner 和 receipt 之间的机械绑定必须由工具传递，不得要求用户复制粘贴充当总线。

一般修改 / 构建授权不自动包含 commit、push、tag、workflow dispatch、promotion、deploy 或外部消息；每类外部 mutation 必须已被当前任务具体纳入。用户离开和动作可回滚都不扩大权限。

## 3. 最短可证伪执行顺序

1. 先检查最便宜、最可能否定方案的静态事实。
2. 做最小实现和定向测试，不先建设完整证明体系。
3. 在正式 request 前验证 materializer / build-input closure，确保声明输入覆盖真实构建输入。
4. 尽早启动真实 build / runtime smoke；能在 3 分钟暴露的问题，不应在 3 小时文档后才发现。
5. 安全、完整性与原子回滚硬门留在 promotion 前；只有当前授权和该子系统既有 release contract 都允许时，体验与物理验收才可后置 canary。
6. 只在完成声明所必需时扩到全量验证，并准确使用 `compiled → candidate_built → candidate_executed → e2e_verified → promoted → standard_entry_verified`。

每个新增 gate 必须回答：消除什么不确定性、失败会改变什么行动、为什么机器不能自动完成、为什么必须现在完成。没有行动差异的验证不得进入关键路径。

## 4. 流程预算与止损

- 同一 gate / contract 进入第三轮修正时，必须停止机械创建下一 revision 并独立审查根因。可选、低价值 gate 可在对应风险权威同意后合并或移出关键路径；保护权限、数据、安全、identity / closure 与真实性声明的门不得因次数删除或放宽。
- 连续失败若来自操作包装、编码、路径或重定向，保留原证据并用有界修复继续；不要把可恢复的 Agent 错误升级为人类批准点。
- 同类状态只发送 blocker、实质变化和最终结果；等待中的心跳留给持久日志或 monitor，不刷主上下文。
- 测试、文档与证据的规模若明显超过产品改动，主 Agent 必须主动缩减并说明保留下来的硬门。
- 用户离开后只冻结可选 scope；任务已具体授权的施工、构建、等待、验证及外部 mutation 继续，直至完成或遇到真正权限 blocker。

## 5. Subagent 边界

主线判断不能外包。Subagent 适合并行搜索、独立审计、日志压缩和互不重叠的实现；不适合重复主线状态机或各自向用户索要同一信息。

- 任务必须有边界、输入、完成条件和“禁止触碰”范围。
- 子任务只上报新 blocker、可消费产物或最终结论；主 Agent 负责去重、排序和一次性交互。
- 并发 Agent 不得在同一文件或同一外部 ref 上无协调写入。

## 6. 可重入验证与持久执行

所有 Agent 启动的验证脚本应幂等、可中断、结果显式；长构建应有 run id、checkpoint、原子结果与 resume，而不是依赖人类持续看守。

- retry 必须区分“恢复同一 run”和“创建新 run”；不可变 request 不因网络等待重建。
- 验证失败保留首因；修复包装错误后继续同一有效证据链，不伪装成首次成功。
- 真正不可恢复时只暂停受阻分支，其他独立工作继续。

## 7. Harness-first 与 Flash smoke 特例

- UI / overlay / minigame 行为变更优先补现有 `dev/harness.html`、`qa-suite.js` 或静态校验；不要只留“人工点一下”。
- Node QA 负责确定性状态流，browser harness 负责协议 / DOM / 交互，静态校验负责结构与旧入口回流。
- `scripts/compile_test.ps1` 退出 0 不等于 Flash 编译成功；必须核本次 `flashlog.txt`、`compiler_errors.txt`，`publish_done.marker` 只代表 JSFL 触发结束。详见 [testing-guide.md §2](testing-guide.md)。

## 8. 项目特定反模式

- **终态错觉**：退出 0、绿 workflow 或零用例被扩张成产品完成；对策是核具体消费者和声明边界。
- **沉默回退**：放宽断言、跳过用例或改阈值让失败消失；任何弱化都不得由 Agent 单方决定，保护门必须由对应风险权威明确接受并同步降级完成声明。
- **流程追逐**：验证器小修触发新合同、新回执和新人工签字；第三轮按 §4 止损。
- **人类消息总线**：让用户转发机器可读取的 ID、hash、状态或精确文本；应由 orchestrator 持久传递。
- **过早物理验收**：在 source closure 和真实 build 尚未成立时占用人类；默认移到最小候选完成后，只有既有授权与 release contract 允许时才可移到部署后 canary。

## 9. 收尾与关联

结论只写已验证状态、未验证边界和真正需要的人类动作；不说“应该可以了”。会话归档见 [self-optimization.md](self-optimization.md)，验证矩阵见 [testing-guide.md](testing-guide.md)，文档治理见 [documentation-governance.md](documentation-governance.md)。
