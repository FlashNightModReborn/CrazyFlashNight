# 跨 Agent 共享记忆

---

## 1. 用户偏好与工作习惯


---

## 2. 已知坑与临时 Workaround

### ▸ [2026-08-08] 怪物头像 Luna 集群的已验证边界与后续知识管线入口

头像工程已经验证“独立 Luna CLI worker + 明确 schema + 独立 shard + 单一 controller + 确定性 renderer + Edge 人审”能够闭合生产规模任务；当前消费者无关包为 226 identity / 227 variant，其中 222 个 variant 有真人接受证据，原 98 identity Team 子集完整保留。Arena 的 217 个消费身份现为 217/217 ready：214 个怪物身份命中通用 manifest，`主角-男 / 主角-尾上世莉架 / 主角-文天` 3 个模板按单位外观投影进入 `MercPortraits` 纸娃娃路线，locked fallback 为 0。当前 r221 方向传播审计 digest `DDC843A4…0576` 覆盖 222/222，0 action/SVG/PNG mismatch、0 legacy：基础 178 项双路高置信度模型保持 + 39 项真人裁决，尾批另绑定 4 pass + 家用机器人 1 项显式 `flip_x`；锡蒙利范围光环发生器按人类批准签名复用锡蒙利头像，不复制主体。并发必须按阶段拆分：当前实证是 selection Luna Max/Fast6、localization Luna Max/Fast3、单进程 600 秒；Fast6 localization 和并发 8 均未获验证。该结论不等于 Luna 可自主艺术签署，也不等于真实 WebView2→Flash、消费者范围外 2 个 production pending 或全游戏 E2E 已完成。新任务首先按 [怪物头像生产管线运行手册](../docs/怪物头像生产管线-可复用运行手册-2026-08-09.md) 执行；批次证据、失败模式和恢复经过见 [头像路线备忘 §12](../docs/怪物头像统一资产与Luna-CLI-Worker路线评估备忘-2026-08-05.md#12-本轮工程复盘技术有效性与复用契约)。未来简介、标签和主题建设当前仅为设计储备，见 [怪物知识库与美术导演管线](../docs/怪物知识库与美术导演管线-设计储备与维度讨论-2026-08-08.md)；未冻结维度、正史权限和剧透阶段前不得启动全量模型任务。

### ▸ [2026-08-05] Sol / Terra V2 不能原生 spawn Luna V1

当前 Codex active-backend compatibility filter 会拒绝 Sol / Terra V2 父线程显式生成 Luna child；`agents.default_subagent_model`、custom-agent 包装和本地模型缓存修改都不能可靠绕过。需要 Luna 做批量、明确、无状态的图片任务时，优先使用独立顶层 `codex exec -m gpt-5.6-luna --ephemeral` worker，并由确定性 controller 管 PID、stdin / JSONL、schema、timeout、digest 和单一合并；每次运行前仍须 capability probe，不能把 2026-08-05 的目录状态当永久承诺。怪物头像专项的完整数据边界、Edge 人审和 compact 恢复入口见 [路线评估备忘](../docs/怪物头像统一资产与Luna-CLI-Worker路线评估备忘-2026-08-05.md)。

### ▸ [2026-03-02] Git 中文文件名显示

```bash
# 每个 clone 执行一次，使 git 直接显示中文文件名（而非八进制转义）
git config --local core.quotePath false
```

> 终端编码（chcp 65001）的规则已在 AGENTS.md「硬约束（最高优先级）」中定义，此处不重复。

---

### ▸ [2026-03-03] HTML 富文本中的特殊字符转义

tooltip 系统使用 HTML 富文本渲染（`<FONT>` 标签等）。在拼接用户可见文本时，`<` `>` `&` 必须写为 `&lt;` `&gt;` `&amp;`，否则会被 Flash HTML 解析器当作标签吞掉，导致文本丢失或显示异常。

**易错场景**：数学符号（< > ≤ ≥）、条件运算符显示、任何含尖括号的描述文本。

---

## 3. 高频操作备忘

