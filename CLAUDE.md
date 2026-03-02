# CLAUDE.md

## 项目知识库

本项目的完整知识体系位于 [AGENTS.md](AGENTS.md)，首次接触项目时请阅读。

深度文档位于 [agentsDoc/](agentsDoc/) 目录，按需查阅：
- 编写 AS2 代码前**必读**：[agentsDoc/as2-anti-hallucination.md](agentsDoc/as2-anti-hallucination.md)
- 会话结束前执行：[agentsDoc/self-optimization.md](agentsDoc/self-optimization.md)

## 行为规则

- 交流语言：中文
- 编写 AS2 代码时，严格遵循 AS2 语法，不要混入 AS3 或 JavaScript 语法
- **.as 文件编码必须是 UTF-8 with BOM**。新建 .as 文件时先复制已有文件再重命名修改，不要从零创建（会丢失 BOM 头）
- 修改 XML 数据文件时，保持现有格式和中文注释风格
- 不要尝试编译 AS2 代码或启动 Flash CS6（当前无此能力）
- 可以直接运行和测试 Node.js 服务器与 PowerShell 脚本
- **终端编码**：调用 `cmd.exe`/`powershell.exe` 等 Windows 原生命令前，先执行 `chcp.com 65001 > /dev/null 2>&1` 切换至 UTF-8，否则中文输出会乱码
