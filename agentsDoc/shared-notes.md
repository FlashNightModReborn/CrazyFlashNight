# 跨 Agent 共享记忆

---

## 1. 用户偏好与工作习惯


---

## 2. 已知坑与临时 Workaround

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

