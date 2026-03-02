# AGENTS.md

## 项目概述

《闪客快打7佣兵帝国》（Crazy Flasher 7: Mercenary Empire）单机版 MOD 开发工程。基于 ActionScript 2.0 + Adobe Flash CS6 技术栈，已获原作者 **andylaw** 授权。

**Agent 定位**：全栈游戏开发协作者——参与编码、游戏设计、数值平衡、叙事策划、测试、文档等全维度工作。

---

## 技术环境与事实约束

| 维度 | 说明 |
|------|------|
| 操作系统 | Windows（必需） |
| 核心技术 | ActionScript 2.0 + Adobe Flash Professional CS6 |
| 编译限制 | AS2 仅能通过 Flash CS6 GUI 编译，**Agent 当前无法执行编译验证**（未来可能通过 MCP/Computer Use 扩展） |
| 辅助技术 | Node.js 14+（本地服务器）、PowerShell（自动化） |
| 可运行验证 | Node.js 服务器、PowerShell 脚本 |
| 可直接修改并立即生效 | `data/`、`config/` 下的 XML 配置文件 |
| SWF 文件 | Agent 不得手动编辑；提交规则见「版本控制备忘」 |
| 终端编码 | Windows 默认 GBK（codepage 936），Agent 使用终端前需切换至 UTF-8，详见 `agentsDoc/shared-notes.md` |

---

## 项目架构地图

> 可编辑性标注：✎ 可直接修改 | ⚙ 需 Flash CS6 验证 | ⊘ 禁止修改

```
项目根目录/
├── scripts/                    ⚙ AS2 源代码
│   ├── 展现/、引擎/、通信/、逻辑/   帧脚本（按功能分区）
│   ├── 逻辑系统分区/              逻辑分区脚本
│   ├── 类定义/org/flashNight/     核心类库（七大包，见下文）
│   ├── 优化随笔/                  24 篇 AS2 性能研究
│   ├── tools/、macros/            脚本工具与宏定义
│   └── *.fla / *.swf             测试用 Flash 项目
├── data/                       ✎ 游戏数据（关卡/物品/单位/对话/环境）
├── config/                     ✎ 系统配置（PID/天气等）
├── tools/Local Server/         ✎ Node.js 本地服务器
├── automation/                 ✎ PowerShell 自动化脚本
├── flashswf/                   ⚙ Flash 资源（Agent 只读）
├── agentsDoc/                  ✎ Agent 深度文档
├── 0.说明文件与教程/            ✎ 设计文档与教程
├── docs/                       ✎ 技术审计文档
└── music/、sounds/、xml/、闪7重置版字体/  资源文件
```

---

## 核心代码库速查

`scripts/类定义/org/flashNight/` 七大包：

| 包 | 职责 | 关键模块 |
|----|------|----------|
| **arki** | 游戏引擎核心 | bullet（子弹工厂）、component（Buff/伤害/护盾）、render（射线VFX）、camera、audio、collision、spatial、item、unit、scene、task |
| **aven** | 协调与测试 | EventCoordinator（事件总线）、Promise（未完工）、Proxy、test（TestRunner/TestSuite/Assertions） |
| **gesh** | 通用工具库（22 模块） | array、string（EvalParser/KMP/压缩）、pratt（表达式求值）、json/xml/toml/fntl（解析器群）、number、object、func、iterator、regexp、path、depth、paint 等 |
| **hana** | 独立小游戏仓库 | 作为资源 SWF 加载，库符号注入主文件运行时 |
| **naki** | 数据结构与数学 | DataStructures（AVL/红黑树/BVH/图/堆/并查集/LRU/BigInt 等 35+ 类）、Sort（TimSort/PDQSort 等）、RandomNumberEngine（LCG/MT/PCG）、Cache、Interpolation、DP |
| **neur** | 事件/控制/计时/状态机 | Event（EventDispatcher/EventBus）、ScheduleTimer（CooldownWheel/TaskManager/CerberusScheduler）、Controller（PID/卡尔曼滤波）、StateMachine、Tween、Server、Navigation、MarkovChain |
| **sara** | 物理引擎 | primitives（粒子）、constraints（约束）、surfaces（表面碰撞）、composites（复合体/弹簧盒）、graphics |

各系统详细描述与选用决策见 [agentsDoc/game-systems.md](agentsDoc/game-systems.md)。

关键设计模式：事件=总线模式 | 子弹=工厂模式 | 音频=接口抽象 | 深度管理器（`gesh/depth/DepthManager`）=AVL 树，未投入使用（性能测试未通过）

---

## 场景化文档索引

> 按工作场景查找所需文档。每个场景列出：项目文件 + agentsDoc 深度文档。

### ▸ 编写/审查 AS2 代码
- **必读**：[as2-anti-hallucination.md](agentsDoc/as2-anti-hallucination.md) — 防止 JS/AS3 语法幻觉
- 性能参考：[as2-performance.md](agentsDoc/as2-performance.md) — 索引 24 篇优化随笔
- 编码规范：[coding-standards.md](agentsDoc/coding-standards.md)（含热路径 vs 非热路径双轨开发策略 §3）

### ▸ 数值平衡与物品设计
- [game-design.md](agentsDoc/game-design.md) — 平衡框架与参考公式来源
- `0.说明文件与教程/武器-技能数值-价格-合成表填写的参考公式*.xlsx`、`data/items/`、`data/units/`

### ▸ 战斗/子弹/Buff 系统
- [game-systems.md](agentsDoc/game-systems.md) — 各子系统入口索引
- 审查文档：`tools/BuffSystem_Review_Prompt_CN.md`、`tools/EventSystem_Review_Prompt_CN.md`、`tools/TimerSystem_Review_Prompt_CN.md`、`tools/BalancedTreeSystem_Review_Prompt_CN.md`

### ▸ 关卡与环境
- `data/stages/`、`data/environment/`、`config/WeatherSystemConfig.xml`、`0.说明文件与教程/无限过图背景配置教程.pdf`

### ▸ 叙事与对话
- [game-design.md](agentsDoc/game-design.md) — 世界观与叙事参考
- `data/dialogues/`、`0.说明文件与教程/支线规划表.xlsx`

### ▸ 数据文件结构 / 服务器开发 / 测试
- [data-schemas.md](agentsDoc/data-schemas.md) — XML 数据规范
- [architecture.md](agentsDoc/architecture.md) — 技术架构与 AS2↔服务器通信、`tools/Local Server/server.md`
- [testing-guide.md](agentsDoc/testing-guide.md) — 测试约定与方法

### ▸ 自动化与部署
- `automation/README.md`、`automation/config.toml`、`config/PIDController 参数配置与调优指南.md`

### ▸ 项目架构理解
- [architecture.md](agentsDoc/architecture.md)、`docs/stateFlags兼容期动态修改点审计.md`、`persistent_state_scan_report.md`

### ▸ 新增物品/单位
- `0.说明文件与教程/添加新物品和单位的详细基础教程宝宝可用.docx`、`0.说明文件与教程/1.改动说明（含作弊码）.txt`

### ▸ 会话收尾：自我优化
- **必读**：[self-optimization.md](agentsDoc/self-optimization.md) — 经验总结 → 评估归档 → 更新文档 → 更新 MEMORY.md

---

## 版本控制备忘

- **SWF 提交**：`scripts/asLoader.swf` 达到可用节点时可提交；其他资源 SWF 完成功能后再上传封档
- **不提交**：大型二进制资源、`node_modules`
- **分支策略**：重大修改建议创建功能分支
- **Git 文档**：`0.说明文件与教程/github项目操作文档.txt`
