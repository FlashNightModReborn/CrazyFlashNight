# AGENTS.md

## 项目概述

闪客快打7佣兵帝国（CF7:ME）单机 MOD，AS2 + Flash CS6 技术栈，已获原作者 andylaw 授权。

---

## 硬约束（最高优先级）

- **编译限制**：AS2 仅能通过 Flash CS6 GUI 编译；Agent 无法执行编译验证（不要声称“已编译通过”）
- **.as 编码**：必须 **UTF-8 with BOM**；新增/重建用“复制现有 `.as` → 改名”保留 BOM（见 [as2-anti-hallucination.md](agentsDoc/as2-anti-hallucination.md) §0）
- **SWF**：禁止手动编辑；提交规则见「版本控制备忘」
- **终端编码**（PowerShell）：运行命令前先执行 `chcp.com 65001 | Out-Null` 避免 GBK 乱码
- **可直接修改**：`data/`、`config/` 下 XML（重启生效）
- **可直接运行验证**：`tools/Local Server/`（Node.js）、`automation/`（PowerShell）

---

## Context Packs（按任务最小加载）

| 场景 | 必读 | 按需 |
|------|------|------|
| AS2 编码/审查 | [as2-anti-hallucination.md](agentsDoc/as2-anti-hallucination.md) | [coding-standards.md](agentsDoc/coding-standards.md)、[as2-performance.md](agentsDoc/as2-performance.md)、[game-systems.md](agentsDoc/game-systems.md) |
| 改 XML 数据/配置 | [data-schemas.md](agentsDoc/data-schemas.md) | [game-design.md](agentsDoc/game-design.md)、[testing-guide.md](agentsDoc/testing-guide.md) |
| 本地服务器/通信 | [architecture.md](agentsDoc/architecture.md) | `tools/Local Server/server.md`、[testing-guide.md](agentsDoc/testing-guide.md) |
| 自动化脚本 | `automation/README.md` | `start_game*.ps1`、`xml_fla.ps1` |
| 新增物品/单位 | `0.说明文件与教程/添加新物品和单位的详细基础教程宝宝可用.docx` | [data-schemas.md](agentsDoc/data-schemas.md)、[game-design.md](agentsDoc/game-design.md) |
| 会话收尾 | [self-optimization.md](agentsDoc/self-optimization.md) | [shared-notes.md](agentsDoc/shared-notes.md) |

---

## 项目架构地图

> 可编辑性标注：✎ 可直接修改 | ⚙ 需 Flash CS6 验证 | ⊘ 禁止修改

```
项目根目录/
├── scripts/                    ⚙ AS2 源代码
│   ├── 展现/、引擎/、通信/、逻辑/   帧脚本
│   ├── 逻辑系统分区/              逻辑分区脚本
│   ├── 类定义/org/flashNight/     核心类库（见 agentsDoc/game-systems.md）
│   ├── 优化随笔/                  24 篇性能研究
│   ├── tools/、macros/            工具与宏
│   └── *.fla / *.swf             测试用 Flash 项目
├── data/                       ✎ 游戏数据
├── config/                     ✎ 系统配置
├── tools/Local Server/         ✎ Node.js 本地服务器
├── automation/                 ✎ PowerShell 自动化
├── flashswf/                   ⊘ Flash 资源（只读）
├── agentsDoc/                  ✎ Agent 深度文档
├── 0.说明文件与教程/            ✎ 设计文档与教程
└── docs/                       ✎ 技术审计文档
```

---

## 版本控制备忘

- **SWF 提交**：`scripts/asLoader.swf` 达到可用节点时可提交；其他 SWF 完成功能后封档上传
- **不提交**：大型二进制资源、`node_modules`
