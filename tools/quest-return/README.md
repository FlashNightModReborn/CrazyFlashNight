# 任务交付与返回候选工具


最后核对代码基线：release source commit `85b168e35222f1e2a750ce89481f3aa416a73467`；已完成有效项目人验与正式部署，保留下文各阶段历史记录。已整合上游彩蛋地图名字修复并刷新场景来源证据。产品与协议合同以[关卡结果 ADR §0E](../../docs/关卡结果与基地结算-CSharp-Web-ADR-2026-08-27.md#0e-2026-09-11-明确任务选择单次返回与到达确认隔离候选)为准。

| 层级 | 入口与所证明范围 |
|---|---|
| Flash 返回权威 | `scripts/run-stage-return-tests.ps1`：119 项，结算后普通门进出、清场前拒绝旧 token 并保留场景、延迟清场不越过世界/淡出身份，以及真实 MovieClip 同路径替换/迟到事件/恢复身份、加载失败回原处、原点、剧情、单次返回、旧 Web 关闭重验、错场景/旧 token、换档 ABA、原生下拉栏默认排序/无任务/重复确认/动态任务事实/精确端点重验；含日常交付共享排序、重连、队列重排、状态失效与旧场景/换档回调。 |
| Flash 回归 | `scripts/run-map-domain-tests.ps1`：60 项，含同地点导航不淡出；`scripts/run-task-panel-tests.ps1`：15 项；`scripts/run-map-loot-tests.ps1`：807 项（StageRunSession 528、Loot 267、Planner 12），含旧 true 标志退休、剩余奖励回读与失败重试。只有 fresh trace/Compiler/输出满足 runner 才计通过。 |
| Web | `node tools/quest-return/test-ui.js`：选择 tuple、禁用原因、无默认选择、取消零返回及截图；`node tools/run-tasks-harness.js --qa` 回归既有任务与成就面板。模拟 Host 不证明真实桥接或 Flash 转场。 |
| Host | `dotnet test launcher/tests/Launcher.Tests.csproj`；全量音频测试须按已有约定给子进程设置 `CF7_NODE_EXE` 为本机 Node 绝对路径。StageOutcome v4 / confirmation v3、TaskDelivery v1、MapDomain stage_return/task_delivery、NativeHud 真实 HWND 手势与既有奖励逻辑一起回归。 |
| 数据与 XFL | `node tools/quest-return/verify-coverage.js`：原 NPC 脚本、SWF 哈希及生产地图条件投影；XFL audit/rename/fix_includes 的只读预览及 linkage 重扫，历史问题按原基线比较，不声称旧美术全量 clean。 |
| 发布产物 | asLoader 用 `compile_test.ps1 -Target asloader`；累计施工含主淡出元件，首次配套须 `-Target main -PublishOnly -VerifySwf CRAZYFLASHER7MercenaryEmpire.swf`。Compiler 0/0 与新鲜 SWF 仅证明编译。 |
| 专用存档 | `node tools/quest-return/prepare-acceptance-saves.js --seed <只读玩家JSON>` 创建三个固定 cf7_agent_return_* 克隆；退出该目录所有候选进程后 `--reset` 复位并备份原克隆 JSON/SOL。种子与清单在 `tmp/quest-return-acceptance`，禁止覆盖真实玩家档。 |
| 隔离启动 | 沿用 `automation/dev.ps1 -ForceBuild -BuildOnly` 构建与 `-ReuseOnly` 启动已验 identity；不新增生产发布捷径。 |
| 人类体验 | 大学档：先保留队首基地任务，从大学选关通关大学城周边，选 Bat 直接回大学，领奖后仍在大学并对话交付。彩蛋档：从基地大厅幸存老兵进入 AVP，同关达成两项后主动选文天回彩蛋；彩蛋是交付点，不是 AVP 出发点。恢复档：基地车库 → 堕落城区域 → 革命军哨所固定四件护甲；留一个背包空格，部分领取、背包满、关闭保存、重启/换档/返回该档、续领，不重复发放、不旧导航；不要求测试员破坏文件模拟保存失败。 |

2026-09-11 维护者已确认其余有效验收项完成，并授权日志复核后的提交、双故障域构建共识、部署和推送；原 E3/E4 撤销用例不计通过。自动门、候选执行、真实业务验收和 production promotion 分别记账，最终发布身份与状态以 [runtime 发布记录](../../docs/runtime-build-reproducibility.md) 为准。

## 彩蛋回执与头像补齐（2026-09-11）

E1 多目标选择、主动到文天和彩蛋 E2 交付已由维护者确认可行。原 E3 的“彩蛋出发 AVP”前提不存在，用例作废；不要求重复 AVP，也不据此判普通返回故障。默认区域仍是实际出发的基地；原 E4 也因彩蛋地图隔离设定撤销，下步为奖励恢复 R1—R5，U4 等未报告项目保留原状态。

补齐前静态扫描正式 `data/task/list.xml` 的 13 个目录文件、244 项任务：53 个交付 NPC 名称中 8 个没有同名小头像（按 Windows 文件名大小写规则）；地图登记的 74 个 NPC 名称中共 15 个缺图。此统计不是当前可达人物数，也不代替驻点条件检查。交付优先缺口为 A兵团士兵、heeho君、室友、文天、爱国青年、神秘男人、被改造的方舟无人机、长生军战士。其中 6 个已有对话立绘 PNG 可派生，heeho君与神秘男人尚需核对别名或真实场景来源。后续按实际人物来源统一构图并补齐共享 profiles 目录，兼顾普通交付、结算、任务页和合成跳转；随后维护者授权一并补齐，15 张已由共享生成器落盘；当前注册人物与任务交付目标的缺图/空图均为 0，原 66 张保留。详见 [NPC 小头像工具](../npc-profiles/README.md)。

`outskirts/聚落` 与两个公开热点现已撤回；这曾是本轮未提交修复新增内容。地点登记不等于公开地图入口。普通 navigate 的私有地点请求必须拒绝；已有完成任务只在已解锁、NPC 在场且精确选择仍有效时允许返回/交付。`verify-coverage.js` 现覆盖公开页缺席与私有交付路线，Host 定向回归含私有地点的导航拒绝、任务完成/驻点/进入条件/生命周期与 tuple 负例。
