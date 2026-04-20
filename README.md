# 闪客快打7佣兵帝国 单机版 MOD

**《闪客快打7佣兵帝国》（Crazy Flasher 7: Mercenary Empire）单机版 MOD 开发工程**  
**最后核对代码基线**：commit `c2118e295`（2026-04-20）。

CF7:ME 是一个 **Flash 起源、当前已演化为多栈运行时** 的单机 MOD 工程。  
游戏核心仍运行在 **ActionScript 2.0 + Flash CS6** 上，但外围运行、启动、UI、验证和存档链路已经扩展为：

- **C# Guardian Launcher**：WinForms 宿主、启动链路、本地通信总线、音频、存档决议
- **WebView2 前端**：Bootstrap 引导页、运行态 overlay、Panel 系统、小游戏 UI
- **TypeScript / ClearScript V8**：Launcher 内嵌脚本构建与运行
- **Rust `sol_parser`**：AMF0 / SOL 解析原生组件
- **PowerShell / CLI 自动化**：启动脚本、Flash smoke、bus-only、巡检工具

## 当前技术栈

| 子栈 | 当前角色 | 说明 |
|------|----------|------|
| AS2 / Flash CS6 | 核心游戏逻辑与资产编译 | 无替代编译链，仍是项目物理约束 |
| C# / .NET Framework 4.6.2 | Guardian Launcher Host | 启动、总线、音频、overlay、存档决议 |
| WebView2 / Web | 运行态 UI | Bootstrap、overlay、Panel、minigames |
| TypeScript / ClearScript V8 | Launcher 内嵌脚本 | 构建产物由 `launcher/scripts/` 管理 |
| Rust | `sol_parser.dll` | 专用 native 解析边界件 |
| PowerShell / CLI | 自动化与诊断 | 启动、编译 smoke、CLI、巡检 |

## 项目目录

```
CrazyFlashNight/
├── scripts/        AS2 源代码、帧脚本、Flash 测试工程、JSFL 自动化
├── data/           游戏数据（XML / JSON）
├── config/         系统配置
├── launcher/       Guardian Launcher（C# Host + WebView2 + TypeScript/V8 + native glue）
├── automation/     启动与运行自动化
├── tools/          CLI、巡检、历史工具与辅助脚本
├── agentsDoc/      深度文档与文档治理
├── docs/           评估、审计、路线图类文档
├── flashswf/       Flash 资源（只读）
├── AGENTS.md       Agent 路由入口
└── README.md       本文件：人类维护者总览
```

## 快速开始

### 运行游戏

```powershell
cd "<项目根目录>"
.\automation\start.ps1
```

### 修改 AS2 / Flash 后验证

```powershell
chcp.com 65001 | Out-Null
powershell -ExecutionPolicy Bypass -File scripts/compile_test.ps1
```

### 修改 Launcher 后验证

```powershell
chcp.com 65001 | Out-Null
powershell -File launcher/build.ps1
powershell -File launcher/tests/run_tests.ps1
```

### 修改 Web / Minigame 后验证

```powershell
chcp.com 65001 | Out-Null
node launcher/tools/run-minigame-qa.js --game all
node launcher/tools/validate-minigame-final-state.js
```

### 修改文档治理后验证

```powershell
chcp.com 65001 | Out-Null
node tools/validate-doc-governance.js
```

## 文档地图

| 需求 | 入口文档 |
|------|----------|
| Agent 路由、硬约束、任务入口 | [AGENTS.md](AGENTS.md) |
| 系统拓扑与子栈关系 | [agentsDoc/architecture.md](agentsDoc/architecture.md) |
| 验证矩阵与测试入口 | [agentsDoc/testing-guide.md](agentsDoc/testing-guide.md) |
| 编码规范与多栈边界 | [agentsDoc/coding-standards.md](agentsDoc/coding-standards.md) |
| 文档治理规则 | [agentsDoc/documentation-governance.md](agentsDoc/documentation-governance.md) |
| Launcher 深文档 | [launcher/README.md](launcher/README.md) |
| 技术栈保留 / 收敛决策 | [docs/tech-stack-rationalization.md](docs/tech-stack-rationalization.md) |

## 维护说明

- 本 README 只负责 **人类维护者的总览与 onboarding**，不重复承载 Launcher / Flash / minigame 的深度实现细节
- 路径迁移、协议变更、测试入口变更、版本门槛变更时，必须同步更新对应 canonical doc
- 技术栈演进判断统一看 [docs/tech-stack-rationalization.md](docs/tech-stack-rationalization.md)
