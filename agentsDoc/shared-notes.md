# 跨 Agent 共享记忆

> 所有参与本仓库的 Agent（Claude Code、Codex、Kimi Code、Antigravity 等）均可读写此文件。
> 用于记录**跨会话、跨 Agent 有价值**的运营级知识。

---

## 1. 用户偏好与工作习惯

<!-- 在此记录用户对协作流程、代码风格、沟通方式等方面的偏好 -->

---

## 2. 已知坑与临时 Workaround

<!-- 格式：▸ [日期] [简述] — [详情/绕过方式] -->

### ▸ [2026-03-02] Windows 终端中文乱码

**根因**：Windows 默认终端 codepage 为 936 (GBK)，而 Agent 常用的 bash/shell 环境以 UTF-8 解码输出流。两者不匹配时，所有 Windows 原生命令（`cmd.exe`、`powershell.exe`、`chcp.com` 等）输出的中文都会乱码。

**影响范围**：
- `powershell.exe` 输出中文 → 乱码
- `cmd.exe` / `dir` 输出中文路径 → 乱码
- `chcp.com` 自身输出 → 乱码
- Git Bash 内置命令（`ls`、`git log`）**不受影响**（它们直接输出 UTF-8）
- `git diff --name-only` 等命令中的中文文件名会被转义为八进制序列（如 `\347\261\273`），非乱码但不可读

**修复方案**：

1. **调用 Windows 原生命令前切换 codepage**：
   ```bash
   chcp.com 65001 > /dev/null 2>&1
   ```
   之后同一 session 内所有 `cmd.exe`、`powershell.exe` 输出均为 UTF-8。

2. **Git 中文路径显示**（每次 clone 后需执行一次）：
   ```bash
   git config --local core.quotePath false
   ```
   使 `git diff`、`git status` 等命令直接显示中文文件名而非八进制转义。

**注意**：
- `chcp.com 65001` 仅对当前 session 有效，无法通过仓库配置持久化
- `core.quotePath` 存在 `.git/config` 中，不入库，每个 clone 需单独设置
- 如果 Agent 平台支持启动钩子（如 Claude Code 的 hooks），可考虑在会话初始化时自动执行上述命令

---

## 3. 高频操作备忘

<!-- 不适合放入正式文档、但反复用到的操作片段或路径 -->

---

## 4. 维护规则

- **只记录已验证的信息**，不记录猜测
- **去重**：添加前检查是否已有相同内容
- 详细技术文档放 `agentsDoc/` 对应主题文件，此处只放轻量条目
- 纯粹的会话级临时状态（如"当前正在调试 X 函数"）**不要**提交到此文件，请使用各 Agent 平台自身的私有记忆机制
