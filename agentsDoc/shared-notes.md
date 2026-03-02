# 跨 Agent 共享记忆

> 所有参与本仓库的 Agent 均可读写。记录**跨会话、跨 Agent 有价值**的运营级知识。
> 维护规则：只记录已验证信息；添加前去重；详细技术文档放 `agentsDoc/` 对应主题文件；会话级临时状态放各平台私有记忆。

---

## 1. 用户偏好与工作习惯

<!-- 在此记录用户对协作流程、代码风格、沟通方式等方面的偏好 -->

---

## 2. 已知坑与临时 Workaround

### ▸ [2026-03-02] Windows 终端中文乱码

Windows 默认 codepage 936 (GBK)，Agent 的 bash 环境以 UTF-8 解码，导致 `cmd.exe`/`powershell.exe` 输出中文乱码。Git Bash 内置命令不受影响。

**修复**：
```bash
# 每个 session 执行一次，切换 codepage 为 UTF-8
chcp.com 65001 > /dev/null 2>&1
# 每个 clone 执行一次，使 git 直接显示中文文件名
git config --local core.quotePath false
```

均为 session/clone 级设置，不入库。可考虑通过 Agent 平台启动钩子自动执行。

---

## 3. 高频操作备忘

<!-- 不适合放入正式文档、但反复用到的操作片段或路径 -->
