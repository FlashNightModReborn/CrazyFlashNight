# 闪客快打7佣兵帝国 · 单机版 MOD

**Crazy Flasher 7: Mercenary Empire**

在经典 Flash 动作游戏的基础上，继续扩展佣兵战斗、角色养成与探索内容，也记录一款老游戏如何逐步更新界面、画面与运行架构。

[下载稳定整包](https://github.com/FlashNightModReborn/CrazyFlashNight/releases) · [值得玩什么](#play) · [项目知识库](#knowledge) · [运行与开发](#quick-start) · [参与贡献](#contribute)

> **先选版本**：当前主线为 **2.718 开发版（DEV / UNSTABLE）**，尚无对应稳定玩家整包；最新公开稳定整包为 **2.71**。下文介绍的开发内容不代表 2.71 整包已经包含，体验以所用构建与角色进度为准。版本来源见 [稳定发包边界](docs/version-archaeology/release-boundaries.md)。

**最后核对代码基线**：commit `edc0002eff1e5c5b06612c6e3b9c31562c4012b3`（核对日期：2026-10-02）。

<a id="play"></a>
## 值得玩什么

开发版更新不只有功能列表，以下几条路线能帮助你找到实际内容：

- **从大学任务走进工坊**：完成“交差”后，到基地军火库找 Shop Girl 接“返校报到”，沿大学二期前往地下工坊。教学链会带你收集材料、合成“能量干扰盾”并交付任务，串起剧情、配方与角色构筑。入口与前置见 [大学二期路线](launcher/web/content/version-history.md#q-u01q-u10大学二期)
- **带着倒计时撤离核电站**：完成“挫其锋芒”、主线进度达到 77 后，从“选关 → 地下 2 层 → 核电站”进入；撤离段的 600 秒在子图之间共享，换图不会重置。路线与其他关卡的完成边界见 [关卡体验指南](launcher/web/content/version-history.md#新关卡与环境在哪里7-个目录项加一条可直接找到的雪天体验)
- **让装备参与照明**：手电、镭射、蓝晶套装与部分发光兵器有不同的照明表现，光源可随角色和装备状态变化；具体生效条件看物品注释。更新范围与性能待验说明见 [开发版记录](launcher/web/content/version-history.md#2718-当前开发)，场景灯的配置方式另见 [场景光源](docs/场景光源-配置与开发验收-2026-10-01.md)

启动、多存档、建角，以及地图、任务、情报、战队、商店、仓库和合成等界面也在逐步重做。Native HUD、WebView2 面板与保留的 Flash 界面共同构成当前体验；完整入口与“开发中／当前不要找”的内容见 [玩家更新说明](launcher/web/content/version-history.md)。

<a id="knowledge"></a>
## 能从这个项目学到什么

仓库中的研究和制作经验也是项目的一部分。这里把实测结论、架构取舍、素材装配与问题复盘整理成可追溯的项目知识，供人类维护者与 Agent 共用。

| 想研究的问题 | 可以带走的具体经验 | 从哪里读 |
|---|---|---|
| 老 Flash 游戏怎样找到真正的性能热点？ | AVM1 基准与字节码对照、属性访问和调用成本、热路径优化的适用前提；区分实测规则、工程策略与实验结论 | [AS2 性能指引](agentsDoc/as2-performance.md) |
| 如何在保留老游戏的同时逐步更新技术？ | AS2、C#、WebView2 与原生组件如何分工，业务与存档权威如何划分，哪些技术保留、收敛或停止扩张 | [系统架构](agentsDoc/architecture.md)、[技术栈取舍](docs/tech-stack-rationalization.md) |
| 一张画稿怎样真正进入游戏？ | 尺度换算、注册点与握持点、分件和动画接口、唯一 XFL 编辑源，以及导出后消费者的核对方法 | [美术资产装配](agentsDoc/art-asset-assembly.md) |

### 人与 Agent 如何共用

- **人按问题进入**：从上表或专题目录寻找相关解释、工具和案例，不必先通读整套工程规则
- **Agent 按任务进入**：[AGENTS.md](AGENTS.md)提供约束与任务路由，具体事实仍落到同一份专题权威正文；验证选择见 [测试矩阵](agentsDoc/testing-guide.md#select)
- **按文档角色使用结论**：历史调查与验收记录按注明的版本和范围使用；当前决策以维护中的权威文档为准，可变运行身份回到机器清单核对
- **知识靠维护延续**：通过检索、验证和持续维护，让已确认的经验跨任务复用；事实变化时修订权威正文，入口只保留摘要和链接，详见 [文档治理](agentsDoc/documentation-governance.md)

<a id="quick-start"></a>
## 运行与开发

普通玩家可从 [Releases](https://github.com/FlashNightModReborn/CrazyFlashNight/releases)选择稳定整包，并按对应版本说明使用。仓库的日常运行与源码开发有两条入口：

### 运行已部署版本

```powershell
cd "<项目根目录>"
.\automation\start.ps1
```

无候选参数时，只运行项目根中已部署的正式 runtime；源码领先时也不会自动切换到新构建。

### 运行开发候选

双击根目录 `本地开发启动.cmd`，或在 PowerShell 中运行：

```powershell
cd "<项目根目录>"
chcp.com 65001 | Out-Null
powershell -File automation/dev.ps1
```

开发入口选择或生成与当前源码身份匹配的隔离 candidate，不改写正式 `runtime/`。AS2/XFL 改动仍须先用真实 Flash CS6 刷新配套 SWF；候选不等于正式发布。

**环境前置**：当前 Launcher 面向 Windows x64，使用 .NET 10、WebView2 与独立 Flash Player。完整游戏运行需保留 `…\resources` 路径语义；源码副本不能直接当作已配置的完整安装。首次配置、锁定工具链、离线复用与排错见 [自动化说明](automation/README.md#2-首次配置)和 [开发入口说明](launcher/README.md#离线开发入口与身份绑定候选)。

<a id="contribute"></a>
## 如何参与

可以从一个明确的问题或一小块内容开始，不必先掌握所有技术栈：

| 你希望贡献什么 | 建议入口 |
|---|---|
| 美术、动画、装备或场景素材 | [素材装配](agentsDoc/art-asset-assembly.md)：确认源文件、尺度与接口，再按所属资产验证 |
| 任务、关卡、文案与玩法策划 | [游戏设计](agentsDoc/game-design.md)、[数据归属](agentsDoc/data-schemas.md#data-entry)：先找到实际配置和消费者 |
| 数值、配方与平衡 | [数据与数值验证](agentsDoc/testing-guide.md#data)：沿用源工作簿与工具链，不用派生文件替代公式权威 |
| 程序、界面、工具或问题定位 | [架构](agentsDoc/architecture.md)、[Launcher](launcher/README.md)、[验证矩阵](agentsDoc/testing-guide.md#select)：按改动层选择验证 |
| 文档整理或与 Agent 协作 | [AGENTS.md](AGENTS.md)、[协作实践](agentsDoc/agent-harness.md)、[人类注意力约束](agentsDoc/human-care.md)：复用已有知识和工具，记录有依据的结论 |

有 write 权限的协作者使用现有 Git 客户端 **Pull → Commit → Push main**；PR 可用于自愿讨论或审阅。提交前保留并核对他人改动，中文提交说明附回归提示；权限、账号与发布边界以 [贡献流程](docs/contribution-workflow.md)为准。

验证按 [测试矩阵](agentsDoc/testing-guide.md#select)选取，不把所有子系统的测试都变成前置。纯文档改动运行 `node tools/validate-doc-governance.js` 与 `git diff --check`；Flash 编译遵循 [CS6 操作说明](scripts/FlashCS6自动化编译.md)，marker 不能代替本轮编译结果。

## 工程速览

| 层 | 主要职责与目录 |
|---|---|
| AS2 / Flash CS6 | 核心游戏逻辑与资产编译：`scripts/`；`flashswf/` 资源按所属源与装配规则维护，默认只读 |
| C# / .NET 10 | Guardian Launcher、Native HUD、通信、音频与存档决议：`launcher/src/` |
| WebView2 / TypeScript / V8 | 面板与工作台：`launcher/web/`；内嵌脚本：`launcher/scripts/` |
| C/C++ / Rust | 原生启动、画面、音频与 AMF0 / SOL 解析：`launcher/native/` |
| 数据、工具与知识 | `data/`、`config/`；`automation/`、`tools/`；`agentsDoc/`、`docs/` |

## 维护与发布边界

本 README 提供项目展示与知识导航，深度实现、历史收据和专项验收留在对应权威文档。路径、协议、测试入口或版本门槛变化时，先同步权威正文，再更新入口摘要。

当前正式 runtime 身份以 [consensus](config/build/runtime-release-consensus.json) 与 [manifest](runtime/cf7-runtime-manifest.tsv) 为准。候选构建、实际运行、正式部署与业务验收分别取证；普通文档或内容改动不自动授权发布，完整流程见 [runtime 发布协议](docs/runtime-build-reproducibility.md#release-protocol)。

## 署名与许可证

原作由 **Andy Law / AndyLaw.Games** 创作；原作分工、重置计划参与者与特别感谢见 [作者与致谢](launcher/web/content/about-authors.md)。仓库许可证见 [LICENSE](LICENSE)，第三方组件说明见 [THIRD-PARTY-NOTICES](launcher/THIRD-PARTY-NOTICES.txt)；具体素材与组件的权利说明以其来源声明为准。
