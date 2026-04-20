# 自优化工作流

**文档角色**：会话归档 / 自优化 canonical doc。  
**最后核对代码基线**：commit `d4f31beee`（2026-04-20）。

## 1. 触发时机

- 用户明确结束会话前
- 完成较大开发任务后
- 发现重要技术洞察、架构理解或踩坑经验时
- 修改了 `AGENTS.md`、`README.md`、`agentsDoc/*`、`launcher/README.md`、`automation/README.md`、`scripts/FlashCS6自动化编译.md`
- 用户主动要求归档或巡检文档健康度时
- **长会话软停窗口触发**(详见 [human-care.md §4-§5](human-care.md))

## 2. 归档判断

### 归档

满足任一即可：

- 跨会话有价值
- 纠正性知识
- 可复用模式
- 用户要求记录
- 文档治理或技术栈认知发生了稳定变化

### 不归档

- 一次性调试过程
- 已在代码注释中记录
- 未验证的猜测

## 3. 归档目标

| 发现类型 | 归档到 |
|----------|--------|
| AS2 语法 / API 幻觉 | `as2-anti-hallucination.md` |
| AS2 性能发现 | `as2-performance.md` |
| 系统拓扑与链路理解 | `architecture.md` |
| 编码规范 | `coding-standards.md` |
| 测试方法与验证矩阵 | `testing-guide.md` |
| 游戏系统 | `game-systems.md` |
| 游戏设计决策 | `game-design.md` |
| 数据结构与 XML 约束 | `data-schemas.md` |
| 文档职责 / 维护触发器 / 基线规则 | `documentation-governance.md` |
| 技术栈保留 / 收敛 / 停止扩散决策 | `docs/tech-stack-rationalization.md` |
| 跨 Agent 运营知识 | `shared-notes.md` |

## 4. 文档治理收尾检查

如果本次会话修改了文档，收尾时额外检查：

1. 是否改到了正确的 canonical doc，而不是只改了入口摘要
2. 是否更新了高变动文档 / 章节的 commit 基线
3. 是否清理了已知过时叙述，而不是把新叙述和旧叙述并存
4. 是否补上了新的维护触发器、测试入口或路径变更
5. 是否运行了：

```powershell
chcp.com 65001 | Out-Null
node tools/validate-doc-governance.js
```

## 5. 知识持久化：双轨机制

### 轨道 A：仓库共享

`agentsDoc/shared-notes.md`

适合：

- 用户偏好
- 已知坑与 workaround
- 高频操作备忘

不适合：

- 详细技术文档
- 已在 canonical doc 中稳定记录的规则
- 会话临时状态

### 轨道 B：平台私有记忆

- Claude Code：`~/.claude/projects/[项目]/memory/MEMORY.md`
- 其他平台：各自私有记忆机制

决策规则：

- 对其他 Agent 也有用 → 轨道 A
- 仅当前会话 / 当前 Agent 有用 → 轨道 B

## 6. 维护准则

- **渐进式**：每次会话填充一点，不追求一次完善
- **准确性优先**：只记录已验证信息
- **去重**：添加前检查是否已有相同内容
- **角色一致**：入口文档不堆深度实现，深文档不反过来充当路由页

## 7. 文档健康度巡检

定期或用户要求时检查：

- 是否有过时或不准确的信息
- 是否有新系统、新子栈、新验证入口需要补充索引
- `AGENTS.md` 的 Context Packs 是否覆盖当前工作场景
- 技术栈描述是否仍符合 `docs/tech-stack-rationalization.md`
- 入口文档是否突破 [documentation-governance.md §7](documentation-governance.md) 的体量预算

## 8. 长会话健康收尾

进入长会话软停窗口时(参见 [human-care.md §5](human-care.md)),收尾动作按顺序:

1. **不再开新方向**：把当前正在做的最小任务收完
2. **强制归档当前进度**：本文 §4 收尾检查 + 把还没固化的洞察写到对应 canonical doc 或 memory
3. **commit 现场可提交的部分**：避免下一段会话面对一堆未提交脏状态;无法 commit 的部分写一句「下一段从 X 开始」
4. **运行巡检**：

```powershell
chcp.com 65001 | Out-Null
node tools/validate-doc-governance.js
```

5. **轻量收尾话术**:陈述当前状态与未完成项,不评估「人类是否疲劳」、不数据化人类。

「最后再做一件」几乎从不是最后一件。出现这类语言时优先复述当前状态,而不是直接接活。
