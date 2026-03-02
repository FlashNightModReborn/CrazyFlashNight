# AGENTS.md

## 项目概述

闪客快打7佣兵帝国（CF7:ME）单机 MOD，AS2 + Flash CS6 技术栈，已获原作者 andylaw 授权。Agent 定位：全栈游戏开发协作者（编码/设计/数值/叙事/测试/文档）。

---

## 技术环境与事实约束

| 维度 | 说明 |
|------|------|
| 核心技术 | ActionScript 2.0 + Adobe Flash Professional CS6（Windows） |
| 编译限制 | AS2 仅能通过 Flash CS6 GUI 编译，**Agent 当前无法执行编译验证** |
| 辅助技术 | Node.js 14+（本地服务器）、PowerShell（自动化）— Agent 可直接运行验证 |
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

| 包 | 职责 | 关键模块 |
|----|------|----------|
| **arki** | 游戏引擎核心 | bullet（子弹工厂）、component（Buff/伤害/护盾）、render（射线VFX）、camera、audio、collision、spatial、item、unit、scene、task |
| **aven** | 协调与测试 | EventCoordinator（事件总线）、Promise（未完工）、Proxy、test（TestRunner/TestSuite/Assertions） |
| **gesh** | 通用工具库（21 模块） | 高频：array、string、number、object、pratt、path、xml；详见 game-systems.md §10 |
| **hana** | 独立小游戏仓库 | 作为资源 SWF 加载，库符号注入主文件运行时 |
| **naki** | 数据结构与数学 | DataStructures（AVL/红黑树/BVH/图/堆/并查集/LRU/BigInt 等 35+ 类）、Sort（TimSort/PDQSort 等）、RandomNumberEngine（LCG/MT/PCG）、Cache、Interpolation、DP |
| **neur** | 事件/控制/计时/状态机 | Event（EventDispatcher/EventBus）、ScheduleTimer（CooldownWheel/TaskManager/CerberusScheduler）、Controller（PID/卡尔曼滤波）、StateMachine、Tween、Server、Navigation、MarkovChain |
| **sara** | 物理引擎 | primitives（粒子）、constraints（约束）、surfaces（表面碰撞）、composites（复合体/弹簧盒）、graphics |

各系统详细描述与选用决策见 [agentsDoc/game-systems.md](agentsDoc/game-systems.md)。

关键设计模式：事件=总线 | 子弹=工厂 | 音频=接口抽象 | 深度管理器=AVL 树（未投入使用，性能未通过）

---

## 场景化文档索引

> 按工作场景查找入口文档，具体文件路径见各 agentsDoc 文件内部。

| 场景 | 入口文档 | 备注 |
|------|----------|------|
| AS2 编码/审查 | **[as2-anti-hallucination.md](agentsDoc/as2-anti-hallucination.md)**（必读）、[as2-performance.md](agentsDoc/as2-performance.md)、[coding-standards.md](agentsDoc/coding-standards.md) | coding-standards §3 含双轨策略 |
| 数值/物品设计 | [game-design.md](agentsDoc/game-design.md) | 公式表、数据文件路径见文档内 |
| 战斗/子弹/Buff/事件 | [game-systems.md](agentsDoc/game-systems.md) | 含计时器选用决策、Review Prompt 索引 |
| 关卡/环境/叙事 | [game-design.md](agentsDoc/game-design.md) | `data/stages/`、`data/dialogues/` |
| XML 数据/服务器/测试 | [data-schemas.md](agentsDoc/data-schemas.md)、[architecture.md](agentsDoc/architecture.md)、[testing-guide.md](agentsDoc/testing-guide.md) | 服务器详情：`tools/Local Server/server.md` |
| 自动化 | `automation/README.md` | |
| 新增物品/单位 | `0.说明文件与教程/添加新物品和单位的详细基础教程宝宝可用.docx` | |
| 项目架构 | [architecture.md](agentsDoc/architecture.md) | |
| **会话收尾** | **[self-optimization.md](agentsDoc/self-optimization.md)**（必读） | 经验归档 → 更新文档 → 更新 MEMORY.md |

---

## 版本控制备忘

- **SWF 提交**：`scripts/asLoader.swf` 达到可用节点时可提交；其他资源 SWF 完成功能后再上传封档
- **不提交**：大型二进制资源、`node_modules`
- **分支策略**：重大修改建议创建功能分支
- **Git 文档**：`0.说明文件与教程/github项目操作文档.txt`
