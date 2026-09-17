# 闪客快打7佣兵帝国 单机版 MOD

**《闪客快打7佣兵帝国》（Crazy Flasher 7: Mercenary Empire）单机版 MOD 开发工程**  
**最后核对代码基线**：commit `2e5e32321506fa1fb2693f3928205f8c45b4235e`（2026-09-17）。
**当前正式 runtime 身份与验收状态**：以机器真源 `config/build/runtime-release-consensus.json` 与 `runtime/cf7-runtime-manifest.tsv` 为准；发布协议与证据状态术语见 [runtime 构建复现文档](docs/runtime-build-reproducibility.md#release-protocol)。历史发布与专项验收证据（斗兽 Gate F 等）按对象留存在该文档的 [历史发布记录](docs/runtime-build-reproducibility.md#历史发布记录) 与对应 ADR，本 README 不复制收据。

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
| C# / .NET 10 | Guardian Launcher Host | 启动、总线、音频、overlay、存档决议 |
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

### 普通合作者提交文档 / 美术 / 策划改动

所有 write 协作者（含 `Crazyfs`、`Flash-Night`）在现有 Git 客户端 `Pull → Commit → Push` 直推主线，服务端不要求 PR、CODEOWNER 或另一人在线；PR 仅作自愿讨论或代码审阅。正式 runtime 发布才走双 signer / 双故障域共识，普通改动不参与。账号、tag 创建授权与 native 准入边界以 [协作者直推与 native 账号隔离](docs/contribution-workflow.md) 为唯一权威。

### 运行游戏

```powershell
cd "<项目根目录>"
.\automation\start.ps1
```

### 修改 AS2 / Flash 后验证

```powershell
chcp.com 65001 | Out-Null
# 编译目标按改动归属显式选择，不依赖 Flash 当前活动文档：
#   逻辑注入（多数 .as 改动）→ -Target publish；测试构建 → -Target test
#   主 XFL → -Target main；独立 XFL/SWF → -Target <xfl路径> -PublishOnly -VerifySwf <对应.swf>
powershell -ExecutionPolicy Bypass -File scripts/compile_test.ps1 -Target publish
```

目标归属、成功判据（marker 不等于编译成功）与恢复协议见 [验证矩阵 AS2 行](agentsDoc/testing-guide.md#as2) 和 [CS6 操作说明](scripts/FlashCS6自动化编译.md)。

### 修改 Launcher 后验证

```powershell
chcp.com 65001 | Out-Null
powershell -File launcher/tests/run_tests.ps1
# 需要隔离的完整候选时再运行；不会改写正式 runtime
powershell -File launcher/build.ps1 -BuilderId local-dev
```

Launcher 状态统一为 `compiled → candidate_built → candidate_executed → e2e_verified → promoted → standard_entry_verified`。`build.ps1` 只生成 candidate；只有 promotion 后再从 `automation/start.ps1` / 根 bootstrap 验证同一正式身份，才可称“已部署 / 正式验收”。候选启动与身份记录见 [Launcher 深文档](launcher/README.md)，正式发布见 [runtime 发布协议](docs/runtime-build-reproducibility.md#release-protocol)。

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
| 验证选择矩阵（先选门） | [agentsDoc/testing-guide.md](agentsDoc/testing-guide.md) |
| 验证正文（命中主题的完整 runner 与恢复） | [agentsDoc/testing-details.md](agentsDoc/testing-details.md) |
| 编码规范与多栈边界 | [agentsDoc/coding-standards.md](agentsDoc/coding-standards.md) |
| Agent 协作粒度与 harness 实践 | [agentsDoc/agent-harness.md](agentsDoc/agent-harness.md) |
| 人类注意力与工程效率宪法 | [agentsDoc/human-care.md](agentsDoc/human-care.md) |
| 文档治理规则 | [agentsDoc/documentation-governance.md](agentsDoc/documentation-governance.md) |
| 协作者直推与 native 账号隔离 | [docs/contribution-workflow.md](docs/contribution-workflow.md) |
| Launcher 深文档 | [launcher/README.md](launcher/README.md) |
| 技术栈保留 / 收敛决策 | [docs/tech-stack-rationalization.md](docs/tech-stack-rationalization.md) |

## 维护说明

- 本 README 只负责 **人类维护者的总览与 onboarding**，不重复承载 Launcher / Flash / minigame 的深度实现细节
- 路径迁移、协议变更、测试入口变更、版本门槛变更时，必须同步更新对应 canonical doc
- 技术栈演进判断统一看 [docs/tech-stack-rationalization.md](docs/tech-stack-rationalization.md)
