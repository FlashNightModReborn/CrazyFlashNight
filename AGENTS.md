# AGENTS.md

## 项目概述

闪客快打7佣兵帝国（CF7:ME）单机 MOD，AS2 + Flash CS6 技术栈，已获原作者 andylaw 授权。

---

## 技术环境与事实约束

| 维度 | 说明 |
|------|------|
| 核心技术 | ActionScript 2.0 + Adobe Flash Professional CS6（Windows） |
| 编译限制 | AS2 仅能通过 Flash CS6 GUI 编译，**Agent 当前无法执行编译验证** |
| 辅助技术 | Node.js（本地服务器）、PowerShell（自动化）— Agent 可直接运行验证 |
| 可直接修改并立即生效 | `data/`、`config/` 下的 XML 配置文件 |
| SWF 文件 | Agent 不得手动编辑；提交规则见「版本控制备忘」 |
| 终端编码 | Windows 默认 GBK，Agent 使用终端前执行 `chcp.com 65001 > /dev/null 2>&1` 切换 UTF-8 |

---

## 项目架构地图

> 可编辑性标注：✎ 可直接修改 | ⚙ 需 Flash CS6 验证 | ⊘ 禁止修改

```
项目根目录/
├── scripts/                    ⚙ AS2 源代码
│   ├── 展现/、引擎/、通信/、逻辑/   帧脚本
│   ├── 逻辑系统分区/              逻辑分区脚本
│   ├── 类定义/org/flashNight/     核心类库（七大包，见下文）
│   ├── 优化随笔/                  24 篇性能研究
│   ├── tools/、macros/            工具与宏
│   └── *.fla / *.swf             测试用 Flash 项目
├── data/                       ✎ 游戏数据
├── config/                     ✎ 系统配置
├── tools/Local Server/         ✎ Node.js 本地服务器
├── automation/                 ✎ PowerShell 自动化
├── flashswf/                   ⚙ Flash 资源（只读）
├── agentsDoc/                  ✎ Agent 深度文档
├── 0.说明文件与教程/            ✎ 设计文档与教程
├── docs/                       ✎ 技术审计文档
└── music/、sounds/、xml/        资源文件
```

---

## 核心代码库速查

`scripts/类定义/org/flashNight/` 七大包：

| 包 | 职责 |
|----|------|
| **arki** | 游戏引擎核心（战斗/渲染/场景/物品/单位） |
| **aven** | 协调与测试（EventCoordinator、Proxy、测试框架） |
| **gesh** | 通用工具库（21 模块：array/string/number/object/pratt/path/xml 等） |
| **hana** | 小游戏资源（库符号注入主文件运行时） |
| **naki** | 数据结构与数学（45+ 类、排序、随机数、缓存、插值） |
| **neur** | 事件/控制/计时/状态机（EventBus、计时器三级体系、Tween、导航） |
| **sara** | 物理引擎（粒子、约束、碰撞、复合体） |

各系统详细描述、模块枚举与选用决策见 [game-systems.md](agentsDoc/game-systems.md)。

---

## 场景化文档索引

> 按工作场景查找入口文档，具体文件路径见各 agentsDoc 文件内部。

| 场景 | 入口文档 |
|------|----------|
| AS2 编码/审查 | **[as2-anti-hallucination.md](agentsDoc/as2-anti-hallucination.md)**（必读）、[as2-performance.md](agentsDoc/as2-performance.md)、[coding-standards.md](agentsDoc/coding-standards.md) |
| 数值/物品/关卡设计 | [game-design.md](agentsDoc/game-design.md) |
| 战斗/子弹/Buff/事件/计时器 | [game-systems.md](agentsDoc/game-systems.md) |
| XML 数据/服务器/测试 | [data-schemas.md](agentsDoc/data-schemas.md)、[architecture.md](agentsDoc/architecture.md)、[testing-guide.md](agentsDoc/testing-guide.md) |
| 自动化 | `automation/README.md` |
| 新增物品/单位 | `0.说明文件与教程/添加新物品和单位的详细基础教程宝宝可用.docx` |
| 项目架构 | [architecture.md](agentsDoc/architecture.md) |
| **会话收尾** | **[self-optimization.md](agentsDoc/self-optimization.md)**（必读） |

---

## 版本控制备忘

- **SWF 提交**：`scripts/asLoader.swf` 达到可用节点时可提交；其他资源 SWF 完成功能后再上传封档
- **不提交**：大型二进制资源、`node_modules`
