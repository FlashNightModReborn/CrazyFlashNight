# 玩家持久属性组合回归

本入口对应 2026-10-22 属性一致性专项。审计基线为 `edbc57572bca`，施工基线为
`4cacdc76c1c21e953344d3bb515ebad19fa0656e`。原审计 ZIP 未提供；本目录探针重新读取
当前生产源码并记录 SHA-256，不冒称复跑了原包。

```powershell
node tools/player-stat-refresh/run-source-probes.js --source . --mode baseline
node tools/player-stat-refresh/run-source-probes.js --source . --mode fixed
powershell -File scripts/run-player-stat-refresh-tests.ps1 -TimeoutSeconds 600
node tools/player-stat-refresh/test-check-writes.js
node tools/player-stat-refresh/check-writes.js --output <审读JSON路径>
node tools/player-stat-refresh/check-writes.js --baseline --output <分类基线JSON路径>
```

`baseline` 只用于原缺陷代码树上的反例核实，输出 `known-current-failure`，不能当作修复通过；当前已修复树不应期待旧缺陷继续成立。
`fixed` 要求目标语义成立，不能以缺陷仍可复现为通过依据。实际 AS2 focused suite
单独通过真实 CS6 runner 执行；Node 不是 AVM1，不证明 MovieClip 引用、加载时序、
事件、动画任务或真实保存。

加 `--output <路径>` 可保存完整报告而只在终端打印摘要。当前 fixed 探针提取并执行新 API，旧基线分支保留给对应旧代码树。
探针只擦除函数签名和变量声明中的 AS2 类型，保留三元表达式、字符串和注释。
每个结果记录所执行的源文件、函数范围和源码哈希。测试替身包括技能 cache、
无副作用的 UI/武器通知、固定装备 fixture、内存协调端口和托管算术端口；Node 没有实际 BuffManager/AVM1，均不能代签生产生命周期。

工单中的协调模型、生产属性投影及 Flash/Host 旅程分别报告，不合并通过率。

检查器是有限增量词法审读，默认比较 HEAD；`--base <commit>` 可切到另一确定基线。owner 表只说明审读归属，不豁免硬规则。
`--baseline` 不以当前历史命中阻断施工，供建立分类清单；普通模式仅对新增行中的明确禁用模式失败。
命令、字段和失败恢复的唯一合同见 [玩家属性合同](../../docs/player-stat-refresh-contract.md)。
