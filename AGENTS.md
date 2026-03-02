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
| 禁止修改 | 已编译的 SWF 文件 |

---

## 项目架构地图

> 可编辑性标注：✎ 可直接修改 | ⚙ 需 Flash CS6 验证 | ⊘ 禁止修改

```
项目根目录/
├── scripts/                    ⚙ ActionScript 2.0 源代码
│   ├── 展现/                      视觉系统和 UI 交互
│   ├── 引擎/                      引擎核心（调试、随机、eval 等）
│   ├── 通信/                      网络和存档系统
│   ├── 逻辑/                      游戏逻辑（关卡系统、战斗系统）
│   ├── 逻辑系统分区/              逻辑系统的分区脚本
│   ├── 类定义/org/flashNight/     核心类库（见下文）
│   ├── 优化随笔/                  24篇 AS2 性能深度研究
│   ├── tools/                     脚本工具
│   ├── macros/                    宏定义
│   └── *.fla / *.swf             测试用 Flash 项目
├── data/                       ✎ 游戏数据（关卡/物品/单位/对话/环境）
├── config/                     ✎ 系统配置（PID控制器/天气系统等）
├── tools/Local Server/         ✎ Node.js 本地服务器
├── automation/                 ✎ PowerShell 自动化脚本
├── flashswf/                   ⊘ Flash 资源文件（需 Flash CS6 编辑）
├── agentsDoc/                  ✎ Agent 深度文档体系
├── 0.说明文件与教程/            ✎ 游戏设计文档和教程
├── docs/                       ✎ 技术审计文档
├── music/                        音乐资源
├── sounds/                       音效资源
├── xml/                          附加 XML 资源
└── 闪7重置版字体/                 字体资源
```

---

## 核心代码库速查

`scripts/类定义/org/flashNight/` 七大包：

| 包 | 职责 | 关键组件 |
|----|------|----------|
| **arki** | 游戏引擎核心 | 子弹工厂、摄像机、组件系统、物品管理、音频引擎 |
| **aven** | 事件协调工具 | 事件总线、事件包装器 |
| **gesh** | 通用工具库 | 数组工具、字符串解析（EvalParser）、算法 |
| **hana** | 独立小游戏仓库 | 可独立运行，主文件可调用加载 |
| **naki** | 数据结构与数学 | 高级矩阵、随机数引擎（LCG/MersenneTwister） |
| **neur** | 事件/控制/计时/状态机 | FrameTimer、EventDispatcher、状态机 |
| **sara** | 物理引擎 | 粒子系统、物理约束、表面碰撞检测 |

关键设计模式：事件=总线模式 | 子弹=工厂模式 | 音频=接口抽象 | 深度管理=AVL树（未投入使用，性能测试未通过）

---

## 场景化文档索引

> 按工作场景查找所需文档。每个场景列出：项目文件 + agentsDoc 深度文档。

### ▸ 编写/审查 AS2 代码
- **必读**：[agentsDoc/as2-anti-hallucination.md](agentsDoc/as2-anti-hallucination.md) — 防止 JS/AS3 语法幻觉
- 性能参考：[agentsDoc/as2-performance.md](agentsDoc/as2-performance.md) — 索引 24 篇优化随笔
- 编码规范：[agentsDoc/coding-standards.md](agentsDoc/coding-standards.md)

### ▸ 数值平衡与物品设计
- [agentsDoc/game-design.md](agentsDoc/game-design.md) — 平衡框架与参考公式来源
- `0.说明文件与教程/武器-技能数值-价格-合成表填写的参考公式*.xlsx`
- `data/items/`、`data/units/`

### ▸ 战斗/子弹/Buff 系统
- [agentsDoc/game-systems.md](agentsDoc/game-systems.md) — 各子系统入口索引
- 已有审查文档：`tools/BuffSystem_Review_Prompt_CN.md`、`tools/EventSystem_Review_Prompt_CN.md`、`tools/TimerSystem_Review_Prompt_CN.md`、`tools/BalancedTreeSystem_Review_Prompt_CN.md`

### ▸ 关卡与环境
- `data/stages/`、`data/environment/`
- `config/WeatherSystemConfig.xml`
- `0.说明文件与教程/无限过图背景配置教程.pdf`

### ▸ 叙事与对话
- [agentsDoc/game-design.md](agentsDoc/game-design.md) — 世界观与叙事参考
- `data/dialogues/`
- `0.说明文件与教程/支线规划表.xlsx`

### ▸ 数据文件结构
- [agentsDoc/data-schemas.md](agentsDoc/data-schemas.md) — XML 数据规范

### ▸ 服务器开发
- `tools/Local Server/server.md` — 详细 API 文档与模块说明
- [agentsDoc/architecture.md](agentsDoc/architecture.md) — AS2↔服务器通信架构

### ▸ 测试
- [agentsDoc/testing-guide.md](agentsDoc/testing-guide.md) — 测试约定与方法

### ▸ 自动化与部署
- `automation/README.md`
- `automation/config.toml`
- `config/PIDController 参数配置与调优指南.md`

### ▸ 项目架构理解
- [agentsDoc/architecture.md](agentsDoc/architecture.md) — 技术架构总览
- `docs/stateFlags兼容期动态修改点审计.md`
- `persistent_state_scan_report.md`

### ▸ 新增物品/单位
- `0.说明文件与教程/添加新物品和单位的详细基础教程宝宝可用.docx`
- `0.说明文件与教程/1.改动说明（含作弊码）.txt`

### ▸ 会话收尾：自我优化
- **必读**：[agentsDoc/self-optimization.md](agentsDoc/self-optimization.md) — 知识归档流程
- 执行经验总结 → 评估归档价值 → 更新对应文档 → 更新 MEMORY.md

---

## 版本控制备忘

- **不提交**：SWF 文件、大型二进制资源
- **已在仓库中**：`node_modules`（添加新包时评估是否提交）
- **分支策略**：重大修改建议创建功能分支
- **Git 文档**：`0.说明文件与教程/github项目操作文档.txt`
