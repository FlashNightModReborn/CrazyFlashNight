# Arena Worker P0–P1 施工与验证

**文档角色**：本次有限施工的接口、文件归属与验证记录，不替代现役 Campaign / 发布合同。
**源码起点**：`61b477298854afcdcea54970c07e7818f9d3b5e4`。
**私有候选验证基线**：工作树 HEAD 为 `ed64e139aeca9e2bda12691743a5cadc1c7ec4be`；已精确同步上游至 `155160229b280ead5c53bc7f79761ce845febc8a` 的 6 文件差异，再叠加本次未提交施工。
**发布交接**：`main/origin/main` 已在 `34e312a14cfd820331724fbf083c328d2b9e7e08` 干净交接；正式入口 Core / identity / closure 已读回匹配其发布回执，随后才开始本任务的私有编译。
**状态**：最低表现候选 5DB 的 P0 六局、P1 串行六局与并行六局、单侧 Flash 原子故障隔离以及普通入口回归均已取得本轮实际证据。并行完整墙钟吞吐为串行的 1.4343 倍，仍低于 1.6 倍扩展参考线；本次在 P0–P1 收口。Host 7023 通过、22 项既有专项跳过，Node 84 项及 Index 策略 47 项通过。源码迁入阶段交付 76 个文件，未含 SWF、正式 runtime 或 bootstrap。正式推广已完成，部署推送与远端审计结果见下述发布记录；原候选证据不自动升级为人类视觉、输入或标准入口验收。

用户授权主代理与两个常驻子代理无人值守完成 P0–P1。加载与面板长尾发布会话持有 main、CS6 和实机窗口；本任务先在隔离工作树施工，待该列车完成并交接最终 main 身份后集成、联调，再将已验证改动迁入 main 供人类监督测试。上述施工阶段最初不含 commit / push / runtime promotion；2026-10-11 用户后续明确授权“提交推送，走获取云端共识，构建部署推送的发布列车”，正式发布结果见本文末尾，原实机证据仍按私有候选范围保留。

## 施工归属

当前管理工作树为 `C:/Users/fs/.codex/worktrees/arena-worker-integration/CrazyFlashNight`，分支 `codex/arena-worker-integration`。最初 `arena-worker-p0-p1` 工作树原样保留；迁入时 27 个既有文件完成三方合并，24 个新增文件逐字节核验，并保留独立输入快照。第二根为 `C:/Users/fs/.codex/worktrees/arena-worker-w02/CrazyFlashNight`，分支 `codex/arena-worker-w02`；上游 6 文件和首轮 58 个施工文件已逐字节同步，实机发现的修复在最终构建前再次同步。不能把普通目录副本或伪造 `.git` 当作开发仓库。

| 负责人 | 独占修改范围 | 职责 |
|---|---|---|
| 主代理 | 本文、P0 度量脚本、人物技能缓存及其 focused suite、必要自动化/构建注册 | 协议、状态隔离、集成、真实验证与收口 |
| Node 子代理 | `tools/arena-calibration/`，除 `measure-worker-p0.js` / `test-worker-p0-metrics.js` | 不可变证据、精确 SOL、独立上下文、Worker client / 短 shard runner |
| Host 子代理 | Worker composition 与必要 Host/Bus/Task 注入、相关 C# 测试；`ArenaCalibrationService.as`、`ServerManager.as` | 合法入口、进程与端口所有权、身份 echo、私有输出与安全关闭 |

所有 Agent 都不得改动发布中的 main。共享文件先协调归属；AS2 编译、Host/Flash 图形运行和性能采样由主代理串行调度。Node 夹具与无窗口 C# 测试可以并行。首次可行性结论优先，首版保留尚未证明可裁剪的 WebView / native / audio 组件。

## 首版执行合同

同一个受验证 Core 增加显式 Arena Worker 入口；每 Worker 一个 Host、一个 Flash、一个 Socket / LaunchFlow 和一个 active batch。复用正常初始化与入局链，使用窄 Worker policy；不复制 LaunchFlow，不把单 Host 改成多 Flash。

入口：`Core.exe --project-root <Worker 合法独立资源根> --arena-worker <绝对 launch.json>`。

| 字段 | 含义 |
|---|---|
| `workerId` | 稳定 Worker 槽名，不是进程身份 |
| `sessionEpoch` | 每个新 Host / Flash 会话重新生成的身份 |
| `assignmentId` / `attemptId` | 本次领取与物理执行身份 |
| `batchId` / `manifestHash` | 冻结批次身份 |
| `caseId` / `caseHash` / `runId` / `repeatIndex` | 逐局身份，必须由 AS2 实际回报后核对 |
| `projectRoot` | 该 Worker 实际资源根，必须是合法独立 worktree / clone |
| `swfOrigin` | 该根下主 SWF 的 canonical 完整来源 |
| `saveRoot` | 固定 `projectRoot/saves` |
| `outputRoot` | 固定 `projectRoot/tmp/arena-calibration` |
| `stateRoot` | 本会话私有配置、descriptor、TEMP 与控制凭据目录 |

`runtimeIdentity.runtimeMode` 保留实际 `isolated_candidate`，另用 `executionMode=arena_worker` 标识执行模式；不得伪装 `formal_runtime`。Worker 的主 SWF、asLoader 与资源闭包需绑定实际路径及字节，git HEAD 自报不是装载证明。

`stateRoot/owner.json` 的 schema 为 `arena-worker.owner.v1`，只包含非秘密根目录、身份、实际端口、Host PID / 创建时间 / 路径与 runtime 身份。`processStartUtcTicks` 使用十进制字符串，避免 JavaScript 数字精度损失。控制凭据放独立私有文件，不写入 owner、结果或日志。

受鉴权 `POST /arena-worker` 只接受以下动作：

- `start`：进入 launch 配置冻结的专用 slot，固定 `fresh=false`、`rememberSlot=false`、`reveal=true`，复用 AgentControlTask / GameLaunchFlow。
- `startBatch`：要求真实 ready 状态与完整 assignment / attempt / manifest 身份。
- `status`：返回本会话 agent 与 arena 状态。
- `abort` / `result`：只操作精确绑定的执行身份。
- `shutdown`：关闭准入后，只有该精确响应的 Write + Close 完成才能提交本会话退出；写失败、复制响应或其他响应均不能触发，服务端写完不冒充客户端收到。
- `faultStopFlash`：仅 launch 和 Task 同时启用 `allowFaultInjection=true` 的隔离试验目标可用；只接收完整十字段与冻结的 `faultId`，不接收 PID / 路径 / 命令。Host 在本轮 pending / generation / owned identity 的同一临界区中消费一次票并终止持有句柄的自有 Flash，锁外观察退出；真实断连链产生 `bridge_lost`。任何 claim 后异常均保留 unknown 且不得重放；`faultReceipt` 是同会话缓存，客户端随后保存不可变快照，不能保证 Host 崩溃后找回。

Worker 不开放普通 legacy `/task`、任意控制台或 save-push 旁路。Socket 使用 exact-process authority；必须实际 bind 成功后公布端口，strict discovery 失败不能盲扫邻居。正常 Guardian 的单实例、输入与权限默认保持既有行为。

Windows 上首版复用 `HttpListener` / HTTP.sys。Node 发送凭据前同时核对 Host PID、创建时间、路径与实际监听所有权；内核 PID 4 不是豁免，必须进一步从 `netsh http show servicestate view=requestq` 验证该端口全部 request queue 的注册进程及 localhost 根前缀。当前解析器支持本机已核验的英文输出；无监听、外来进程、缺队列或未知输出均拒绝发出凭据。这是当前 Windows 工具边界，不能只凭 descriptor 自报端口称为已验证。

每 Worker 使用独立 `TEMP/TMP`。SOL 仍位于 Windows 实际用户 Roaming 目录，通过完整主 SWF 来源与专用 slot 隔离；不假定覆盖 `APPDATA/USERPROFILE` 可以重定向 Flash 的系统目录。用户级 trust 使用单独的 Worker 会话租约文件，只包含自身根目录；不改普通 `cf7me.cfg` 或系统级 trust。文件回收须绑定本轮所有权及原始字节。

运行前使用真实 Git 的 `rev-parse` 与 worktree 注册核对资源根，不以 `.git` 存在性代替合法仓库证明。每个 runner 保全自身非目标槽，双开协调层另对声明的主存档根及整个 SharedObjects 树做前后快照；允许写集合只能是本轮两个完整 SWF 来源及精确目标槽。普通 Archive 不产生 repair/rebuild 备份；异常事务残留不默认忽略。

每次物理执行使用 create-new 的 `tmp/arena-calibration/batches/<batchId>/attempts/<attemptId>/results.jsonl`。重复传递同一身份/内容应幂等；同身份不同字节拒收或隔离。旧 journal 引用的全部证据必须仍能解引用到原始字节。P1 输出与历史 Gate F 生产 journal 分开；不在本轮建设 P2 的完整 reducer / 恢复调度。

短 shard 完成后回收 Flash 会话。transport failure 与身份不符必须精确隔离/回收；自然达到 `timeoutFrames` 的 combat timeout 保留为合法实验事实，不因胜负不满意重复抽样。

Worker 的资源闭包、非目标存档和运行身份核验在独立 Node 线程中执行，保留原先的逐文件排序 / 完整读取 / SHA 算法；控制事件循环继续收取另一 Worker 的回执。线程退出、前后全部核验与错误处理仍计入完整墙钟，任何不完整或变化的证据均不能合格；后续步骤失败时保留已取得的保护快照。普通 `run-unattended` 同步 API 未改。

可选 `launch.performance` 使用三字段 `{preset, mode, maxRenderHeight}`；Worker 默认 `performance/fixed/180`，只应用于其私有偏好。180 是现有性能调度在 360 上限下可达到的最低阶段；该精确三元组只在 Worker 入口开放，普通 Guardian 配置与默认值保持原合同。固定的是策略阶段和 Flash 光栅高度上限，实际光栅还受窗口及 Windows DPI 映射约束，可以低于 180。默认目标为 LOW、表现预算 2、320×180 窗口输出并关闭锐化；显式指定其余既有方案仍保留原渲染语义。玩法时钟继续为 30 帧，不用降速换吞吐。owner 中的 `performance` 是请求，Host `performanceObservation` 与逐局 AS2 `presentationAudit` 才记录实际状态；后台导致 inactive/stale 时保留原状态，不把请求值当作已经应用。

Worker 关闭 Native HUD 显示和动画、PlayerInfo 表面及查询定时器、伤害数字、Web CSS 动画 / 可视化 / 热重载；Web 表现上限为 15 帧，场景揭幕和启动回执仍走真实浏览器。现有 idle 路径继续隐藏 Web 控制器并冻结界面定时器。保留业务接收端、30 帧 AS2、原生世界捕获与投射物合同：直接撤掉原生呈现会使当前场景围栏无法成立，也可能让投射物退回 Flash，不能用假回执代替或把 CPU 转移当成已省电。以上是低负载执行策略，尚无整机功耗 / 频率证据可判定 TDP 墙。

## 已落地的源码与验证入口

`ArenaSkillCache` 仅用于 `_arenaCalibrationUnit === true` 的人物模板。定义键包括姓名、等级、装备组合与实际技术值；缓存保存独立定义，命中后重新分配逐单位技能对象并清空冷却。已由装备生命周期提前注册的技能仍保留其原有所有权，普通人物模板保持既有路径。入场一次采集 `cacheKey/cacheHit/skillCount/cooldownsClear/definitionSignature`；缺采样必须标为未观测，不能当作冷却已清空。该改动改变标定的战斗语义，样本必须进入新 cohort。

真实 focused 暴露了该初始化函数的接收者不一致：类调用传入单位的姓名/等级为 `CacheSubject/30`，裸字段却读取为 `undefined/undefined`，而 `this.personality` 仍正确。现仅在预注册早退之后将姓名、等级和装备读取绑定到 `this`，使生成输入与技能表写入属于同一单位；不改变技能点、LCG、取桶、强化算法或普通缓存键格式。修复前两轮均为 11/21，诊断与失败产物保留；修复后真实 Flash 为 21/21，且普通缓存与预注册分支断言通过。

静态与夹具入口：

```powershell
node tools/arena-calibration/run-checks.js
node tools/arena-calibration/test-worker-p0-metrics.js
powershell -File scripts/run-arena-skill-cache-tests.ps1 -SkipCompile
powershell -File scripts/run-arena-worker-protocol-tests.ps1 -SkipCompile
```

技能 focused runner 包含真实玩家模板 `#include`，协议 focused 覆盖真实 handler、延迟 stage callback 与派生单位 loader hook。真实 Flash 验证去掉 `-SkipCompile`；静态检查不代签行为断言。修改模板后执行 assembly → `--check` → BOM → equipment coverage；publish 与 focused 编译仍按共享窗口串行执行。

标定场景的首局准入保留 StageManager 实际初始化令牌，经过真实 `initStage → initializeStageWorld → initCalibrationHostStage` 链传递；在 loader / Start 执行前捕获世界普通对象身份，防止同路径 MovieClip 被替换后误认。`ArenaCalibrationService` 冻结当前十字段执行身份、请求对象与过场普通对象身份，完成世界和灯光初始化后发送专用 ready；仍等待原有 frame 30 原生围栏、Web revealed 与 frame 36 严格释放，专用回调再次核对当前世界/代际并消费请求后才生成单位与启动时钟。该分支不发布普通到达和过场释放事件；warm 运行只能复用同一已呈现世界及代际。

单 shard 工具为 `node tools/arena-calibration/run-worker-shard.js --help`。输入是合法资源根下的 `arena-worker.launch.v1`、精确 candidate、冻结 manifest 和明确实验标签；一轮新 Host 只执行一个短 shard，然后回收自身 Host / Flash。结果保留原始行、manifest 快照、生命周期、实际 runtime 身份、所观测资源闭包与存档差异，不使用历史 Gate F journal。

直接启动 Core 前复用 `tools/dotnet-runtime-detect.ps1` 的现有运行时探测，将选定的用户级 .NET 路径仅加入本轮子进程环境。缺失时留下失败前置回执，不启动 Host 或自动安装运行时。

有限组协调入口为 `node tools/arena-calibration/run-worker-experiment.js --help`。`arena-worker.experiment-plan.v1` 显式列出每个 Worker 的根、candidate、只读种子及各组 manifest；工具先封存全部预期回执，再为每个 job 创建新 session 和专用槽。每组完成全部回收及全局存档核对后才进入下一组；缺回执、保护变化或回收失败保留证据并停止后组。启动投递未知只可读回当前身份，不能重新发送 start。

本轮每个实测 job 显式设置 `batchTimeoutMs=900000`：六局各 1800 帧在既有 30 帧时钟下，仅自然 timeout 上界就有 360 秒，不能使用五分钟默认值。`sessionState=cold` 指新的 Host/Flash 会话；同一 shard 的后续 repeat 用于技能定义的 warm-cache 观察，不宣称操作系统文件缓存或机器温度已经冷却。

单侧故障入口为 `node tools/arena-calibration/run-worker-isolation-probe.js --plan <plan.json> --fault-worker <workerId>`。仅接受一个双 Worker 并发组；双方冻结身份、在途 run 和真实进程均验证后，对指定 Worker 本轮拥有的 Flash 执行一次精确终止。结果要求该 run 留下 `bridge_lost`、另一 Worker 在故障后完成对应 run，并且全部安全回收、全局非目标存档未变。进程不明、观测过期或没有真实重叠均不能代签；该预期失败实验永远不取得速度资格。

P0 度量入口：

```powershell
node tools/arena-calibration/measure-worker-p0.js --plan <frozen-plan.json> --output <new-report.json>
```

`arena-worker.p0-plan.v1` 逐组列出全部预期回执路径、`expectedConcurrency` 和双开全局存档保护回执，再声明 baseline/candidate 对照。协调器预声明 `groupReportPath`，其完整组区间必须覆盖所有回执及组前后全局保护核验；度量复核每份 receipt hash，并使用该整组墙钟。旧的仅回执输入明确标为 `receipt_envelope`，只含各 runner 的前置核验至回收及组内间隙。相同战斗输入的总工作量与 candidate / 资源身份必须一致；仅时间重叠而共用进程、端口或存档根不能算双开。零错误、带真实帧时钟的自然结束局计入强度样本；自然 timeout 单列，基础设施 timeout/错误保留为失败成本。缺回执或资格不完整时不提供合格倍率。

夹具回执标记 `isolated_fixture`，命令行度量拒绝其真实运行资格。资源记录的 `observed_runtime_resources` 是所列文件的字节绑定；在独立完整资源清单建立前保留 `completeResourceClosure=false`，不升级为全部装载资源证明。

本轮输入另列出 Flash 播放器、跨域配置、角色/关卡等运行媒体、音频、字体及 Host 界面资源，共 11691 个追加路径；与默认的主 SWF、asLoader、data、config 一并逐 job 做前后字节核对。追加清单约含 1.70 GB 媒体与界面文件，读盘和校验成本计入墙钟；这仍是明确列出的资源范围，不是所有系统字体、驱动或动态装载来源的完整证明。

度量另汇总窗口点采样、实际显示状态及 Host/Flash 的 CPU 与内存。CPU 只对同一 PID、创建时间和路径内单调增长的计数计算采样区间平均占用；缺值、计数倒退或换进程不填零。内存是采样峰值，资源范围明确不包括 WebView 子进程；窗口点采样也不证明整个区间始终可见或未激活。原始观测保留在每个 shard receipt。

## 完成标准与当前证据

| 范围 | 完成条件 | 当前状态 |
|---|---|---|
| 单例可靠性 | 时钟变化的重复 import 不破坏旧引用；SOL 精确来源；busy 与回包严格身份；attempt 不覆写 | c2b5 冻结源码：Node 84 项通过；Host 7023 通过、22 项显式专项跳过、0 失败 |
| P0 | 当前候选真实入局；后台时钟、实际性能方案、cold/warm 与技能状态可复核 | v6 六局完成，真实揭幕；实际 256×144 LOW / 效果 2，输出 320×180；约 30 FPS，四组技能冷暖与冷却初值通过 |
| P1 双开 | 两个独立 Host/Flash 同时完成不同短 shard；进程、端口、资源/存档、结果归属闭合 | v6 串行与并行各六局完成；并行两侧真实生命周期和战斗区间重叠，独立身份与端口均核对 |
| 错误隔离 | 单边断桥/失败不伤邻居，不写正式或邻居存档；未知结果不重放 | v6 仅终止 w01 指定 Flash；精确第三局 bridge_lost，w02 三局完成；单次故障回执与两侧回收、存档边界通过 |
| 正常入口 | Worker 模式不改变普通 Guardian 的默认权限、单例与关闭；兼容调用可完成真实单批 | 无 Worker / Legacy 标志的单例与关闭通过；显式 Legacy 一局完成，MEDIUM 默认仍生效，严格终态只读续查后一次正常关闭 |
| 初步收益 | 相同冻结 workload 比较有效样本/完整墙钟，包含失败与启停成本 | v6 串行 241142 ms、并行 168129 ms，89.57 → 128.47 有效样本/小时，1.4343 倍；短期对照，不证明热稳态或 TDP 改善 |

已完成的本轮真实 AS2 focused：技能 21/21（runId `aa472882323643edafc1a2d6205e3bb7`），Worker 协议 22/22（runId `4b1792f7a71b45bdb810730642f17515`）。两者均为本轮 Compiler 0/0、唯一闭合行为区间、32K retry=0，并通过 SWF 函数体门与 scratch 原样恢复；它们仍不代签真实候选与双实例。

补齐专用呈现准入后的真实 CS6 验证位于 `tmp/arena-worker-as2-validation/20261011-presentation-r1`：场景过渡 83/83（runId `c0062b1ca6e7440b91cd6dbf7d3b1a20`）、Worker 协议 52/52（`cf8bc07141874f6184ff2fd24c9802a5`）、Map/Loot 1035/1035（`4eba0d94ef13489eaea38ece8df9937d`，其中 StageRunSession 834，Box 13 case / 53 assertions 另通过）。三套均为新鲜 Compiler 0/0、32K retry=0、scratch 原样恢复；协议覆盖真实准入后的两演员/时钟、warm、世界/代际更换、取消和逐字段拒绝，新增四项 Stage 断言覆盖真实令牌链与 Start 同路径替换。它们证明 AS2 行为，真实 Web/native 完整呈现仍须新一轮 P0 联调。

既有 Map/Loot suite 为 1031/1031（其中 StageRunSession 830；BoxInteractionArbiter 的 13 case / 53 assertions 另通过），runId `ac9e7a44123c49308e1d68d56b2f9c8c`。协议延迟专项在隔离根无槽位时保留一轮 `no_slot` 失败，随后仅创建专用测试种子的只读副本，取得 14 组完整指标、零失败，runId `a2009e4904fd4b2bbf620de4c15dc021`；该项使用隔离根继承的普通 bus-only runtime，只证明当前 AS2 的既有传输回归。

首轮私有 `scripts/asLoader.swf` 由 CS6 publish-only 生成：1508891 bytes，SHA-256 `593BDA1F0E0031B8E57EF9517691BA1FDB65D72B1CF15F8D0BAC7D96C0F7685D`，Compiler 0/0；最大函数体 51972 bytes，小于 60000 门。single-ownership 为 main 0 / loader 714 / intersection 0。自有测试播放器已回收，原 IDE 编辑文档保留；全局编译绑定和 loader 原始字节均已恢复，正式 main 的 55 项文件/目录记录与 GPU 偏好摘要前后无变化。

专用呈现准入后的私有 asLoader 已重新由真实 CS6 publish-only 生成：1509925 bytes，SHA-256 `0C9773A3250BDFC9CA1667AB8699239E491602C01ED163793FFD3C25C93730DD`，本轮 Compiler 0/0、最大函数体仍为 51972 bytes，single-ownership 仍为 main 0 / loader 714 / intersection 0。publish 不产生新 trace；其成功依据为本轮 Compiler、正确目标 SWF 刷新和字节审计。2026-10-11 04:28:45 UTC 全局编译绑定按本轮租约恢复，loader 原字节恢复、触发器 Ready、无遗留编译门；正式入口/共享文件的 55 项记录与 GPU 摘要再次确认未变。

首轮私有候选的 build identity 为 `3AC449B5691D7E5F5E0DC952DFEC00E25463A543D47203BF9211935FB1A5F57C`，payload closure 为 `A463E7C1401CE5A912E80D1ED2C390250D446B600FAEB31ADE93DF441CDF2D17`。W2 是这份候选的逐字节副本，共 45 文件、371007024 bytes，不是独立 builder。两根所列资源各 12440 文件、1738560011 bytes，聚合 SHA-256 均为 `40813a463fad35bcea6a1d7b42c88c8864938a7b28a5fb145a02814c5f25d2a0`。

构建包装器的 Worktree 策略入口因未提交施工拒绝，保留失败日志后改走现有 `IdentityMode=Index` 验证入口，未创建提交。第一次 Index 校验又将 Git 的八条 LF/CRLF 提示误计入源码差异：独立保留的标准输出为零字节、退出码为零；仅在新验证子进程设 `core.safecrlf=false` 抑制该提示，未改 `autocrlf`、源码、候选或持久 Git 配置，也未跳过任何检查。新回执绑定 tree `3f93764ec47b488416ab4aea6262629d5cb8e6be`，47/47 通过；policy hash 为 `0D099E09D3077541D986CB2E6CCCD8A59F54E6698AB796149CD3C9BFCA00D595`，回执位于隔离根 `tmp/arena-worker-candidate-validation/20261011-index-r3/policy.json`。后续修复须按实际变更域重新验证：二进制输入变化重建候选；仅 AS2/策略变化时须读回构建身份各域未变、绑定新 SWF 资源并取得新策略回执，不能沿用旧回执覆盖新源码。

首轮 P0 为 `aw-live-p0-profiles-20261011-v2`。两组均真实入局并绑定专用槽；默认方案整组 273578 ms，固定 540p 方案整组 262400 ms，分别在首局等待 AS2 回包 150015 / 150003 ms 后得到 Host 合成的 `bridge_lost`。每组只有一条失败行，零有效强度样本，倍率为 null。固定方案确有 `ready / 960×540 / LOW` 实际采样，但它不使失败战斗获得吞吐资格。两组均无控制投递或强制回收错误，Host/Flash 自然退出，runtime、所列资源、种子、私有及全局非目标存档前后未变；正式入口与共享偏好/trust/GPU 的边界核对也通过。

现场日志将失败定位到过场：AS2 持续发送约 30 FPS 的 render sample 和同一 `cover` 请求；Host 的 `SceneTransitionController` 与 `CompositionHelpSurface` 都要求本进程拥有前台焦点才投递 Web 过场，后台 Worker 因此等不到真实 `covered` 回执。该 30 FPS 只证明等待期间的呈现采样，不是已完成战斗的时钟。修复限于显式 Worker 后台呈现策略，仍保留实际 Web 绘制回执、身份、连接、可见及未最小化条件，禁止自动激活或跨应用提窗；普通入口、书架与奖励过场继续原有资格门。首轮完整失败、日志快照和保护回执保留在隔离根 `tmp/arena-worker-live-validation/20261011-p0-r1` 及对应 experiment 目录。

首显拦截只调整有效的插入位置；不能把 `WM_WINDOWPOSCHANGING` 回调内追加 `NOACTIVATE/NOOWNERZORDER` 当作保证，Windows 会忽略这些修改，见 [Microsoft 消息合同](https://learn.microsoft.com/en-us/windows/win32/winmsg/wm-windowposchanging)。同样，已非置顶窗口使用 `HWND_NOTOPMOST` 不保证移动，见 [SetWindowPos 合同](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setwindowpos)。焦点、owner 与其他窗口的实际顺序均须由真实 HWND 测试核验，不能只依据 API 返回成功。

后台呈现修复的最终定向运行是 155/155、退出码 0、串行测试策略标记恰好一次。真实窗口覆盖首显、重显、同组修复及其他窗口/置顶窗口上缘，并检查前台句柄、owner 位置消息与最终窗口样式；另补实际预热顺序的隐藏句柄创建、后续 Owner/Bounds 绑定及再显示，句柄保持且各阶段 owner 位置消息为零。此前两轮分别发现基类提前读取尚未初始化的策略字段，以及 `HWND_NOTOPMOST` 不移动既有普通窗口的边界，失败日志和 154 项通过的 r3 均保留。最终日志为隔离根 `tmp/arena-worker-transition-focused-r4.log`，SHA-256 `46DFD86A83D76C04672D1C8CE0E5B5EFCC3BDB669238C5B5C4CF4B258ADE84D8`；它仍不代替新候选中的真实 Web 回执与完整战斗。

该修复后的完整 Host 回归为 7001 项：6979 通过、22 项既有显式 opt-in 跳过、0 失败，串行策略标记恰好一次，测试与探针进程全部退出。日志位于 W2 `tmp/arena-worker-launcher-validation/20261011T032701Z-c2399f36/launcher-full.log`，SHA-256 `F0137A65ECE47E3871F151D37D937EDDFC3ABDB2BD125B70BB42C9297FC845AB`；逐项跳过原因保留在同目录的 `verified-summary.json`。

新私有候选为 `c-f8fe0ef436d3-b7b2706ac9-20261011t032729105z-65ea6769`，Core SHA-256 `9B6B0209D36D36485DE6733297D56B072D7FFD5ED45B74198AF521A81C7756F5`，build identity `F8FE0EF436D3113828EC52A1DC78F208FF76181EE13099D8DD50E5698BDC2023`，payload closure `812DA904577C0C880839EE6369A30FFE4006EA26149EB71EDC179EB01869CDB9`。源码 tree `d77eefba07e9ad01977ce1f571bf909e32497228` 的完整 Index 策略为 47/47，通过回执位于 `tmp/arena-worker-candidate-validation/20261011-background-r1/policy.json`，SHA-256 `F7C9CF9F0B92AC10B2AEDBFCD34D18A656DF15DBE5A6FBFE579AC9461934E29A`。W2 副本的 45 文件、371009584 bytes 逐字节匹配，仍不属于独立 builder；主入口与正式运行库没有变更。

第二轮 P0 为 `aw-live-p0-profiles-20261011-v3`：两组均 6/6 自然结束、零错误，默认组完整墙钟 148517 ms，固定 540p 组 145879 ms。所有十字段身份、原始行与快照、存档/资源保护及自然回收均通过；四条角色序列在两组中都呈现 `cacheHit=[false,true,true]`、9 个技能、冷却全清空，定义签名组内及跨方案一致。AS2 记录真实 30 帧配置和未暂停状态，默认组实测 27.916–30.233 FPS；显示质量分别为 MEDIUM / LOW。程序度量的结构资格为 true，盖幕样本的倍率为 1.01808348；该数值不用于宣称完整 P0 通过或最终方案收益。

第二轮现场日志在真实 `scene_transition_project` / `covered` 后始终停留于 `loading / revision=3`，直至关闭，两个方案都没有 `reveal`。根因是无玩家标定场景有意不发布普通 `SceneReady`，而 `SceneTransitionService` 的揭幕条件只从该事件建立；首局又在标定 host 初始化后直接开战。因此须增加绑定当前执行、世界普通对象身份及过场代际的专用呈现通知，并在真实揭幕完成后才准入首局，保持普通到达、奖励和存档边界。完整日志快照位于 `tmp/arena-worker-live-validation/20261011-p0-v3/runtime-logs-final`，独立复算与限制位于 experiment 的 `independent-node-review.json`。本轮 12 局及全部成本保留；结束后正式入口/共享文件的 55 项记录与 GPU 偏好摘要仍未变化，Host / Flash / 测试进程无残留。

## 第三轮实测与后续修正

第三轮私有资源使用 asLoader SHA-256 `0C9773A3250BDFC9CA1667AB8699239E491602C01ED163793FFD3C25C93730DD`，两根各 12440 文件、1738561045 bytes，资源摘要 `sha256:2d7f691944cad0ee17361116361f3c6dc12b55ef5818c0ac24007b9c108f71eb`。冻结 tree `a4c32ce854746c27a43f2d5bc900f975c4619a41` 对原 F8 候选完成新的 Index 47/47 策略回执，未改写候选 metadata，也未发布。`aw-live-p0-profiles-20261011-v4` 两组各 6/6 完成并自然退出，完整墙钟为 145090 / 167154 ms；原始结果十字段、冷暖技能状态、实际画质、后台窗口观测和存档保护均有独立复算。两组均取得同身份的 covered → 原生目标场景 → reveal → revealed 日志链，再由真实编译测试和匹配的 asLoader 字节证明 AS2 的首局准入规则。它证明 Host / native / Web 围栏与程序顺序，不替代人眼像素、持续焦点或物理输入验收。不同随机战斗时长使这一次方案比值不构成分辨率的因果收益。

`aw-live-p1-balanced-20261011-v4` 串行 6 局与双 Worker 6 局全部结束，无失败 / 超时，四会话身份、端口、独立根与回收校验通过。完整墙钟 `245101 → 226504 ms`，`88.1269 → 95.3626 samples/hour`，比值 `1.0821045103`。真实串行 AS2 FPS 为 `28.863–30.397`；并行两根为 `23.011–29.146` / `24.223–28.988`，其中 w01 自动档曾由 1280×720 降到 1088×612 后恢复。基于 Host 请求/完成包络和 AS2 elapsed 的保守区间推导给出 13558 ms 并发战斗内区间；它是有时钟假设的下界推导，不是逐帧直接观测。固定前后校验成本占比显著，本轮仍不支持进入 P2 扩展。证据位于 `tmp/arena-worker-live-validation/20261011-p1-v4` 和对应 experiment 的独立复算文件。

`aw-live-fault-balanced-20261011-v4` 在精确自有 Flash 上实际执行了一次终止，目标出现真实 `bridge_lost`、邻居三局完成，存档与运行资源保护未变，但资格结果是 **failed**。两根退出控制分别留下连接重置和未知超时，不能用最终进程消失补作 ACK；预选的目标 / 邻居 run 又在数次进程查询期间推进，目标旧 run 已在终止前完成，不能事后将它改绑到下一局。完整原始输出和失败回执位于 `tmp/arena-worker-live-validation/20261011-fault-v4` 与其 experiment，禁止覆写或重放该次故障。

源码定位到两条独立问题：Host 原来在返回 shutdown 响应前排队退出，仅有 100 ms 延迟；Node 在一个 Worker 关闭后同步读取并哈希约 1.7 GB 资源，曾连续阻塞同一事件循环约 34 s。现已改为只在该精确响应 Write + Close 完成后提交退出，并把 Worker 前后校验搬到独立线程且保留原算法和摘要。故障注入采用前述显式 opt-in 与 Host 原子检查；Node 的四进程筛查放在最后状态刷新之前，首次不可变 claim 才绑定刷新后的 tuple，其后绝不改绑。

合并 Host 定向复验 119/119 通过，包含默认 180p / 隐藏窗口、禁用 HUD 不复活、退出写回次序、十字段与进程/代际逐项拒绝、响应/终止临界区先后、unknown 耗票和普通入口拒绝。首轮 115/119 的失败原日志保留在 `tmp/arena-worker-candidate-validation/fault-shutdown-minimum-20261011`；复验位于同名前缀的 `-r2`，TRX 摘要 `34A4F536556EFC97861EC00D23FFAEE58B805103353C445514484F3607DCFC01`。独立复核随后确认日期 token 差异还暴露了实际 wire 风险：首次故障响应的 ISO 字符串与后续查询重序列化可能修剪小数尾零，使同一收据校验值不同。因此不能只归为测试类型问题；Host 统一四个 UTC 时间的 JSON 输出并新增尾零回归，保持 Node 收据校验不放宽。未建句柄时程序改尺寸的断言则属于测试假设，修为真实隐藏句柄创建后的初始尺寸验证。最终修正版合并定向为 122/122，新增三个日期尾零样例通过真实 Controller 与 HTTP writer 生成首答，再与 status / result 的收据 UTF-8 字节严格比较；原日期类型比较也恢复为不作归一化的断言。结果位于 `tmp/arena-worker-candidate-validation/fault-shutdown-minimum-20261011-r3`，TRX 摘要 `EBC240502DAA803CDA5C673E646B3507DA2B704D045BFA3149F1D09D4E35BE6D`。Node 完整 `run-checks.js` 的 84 项检查均通过，日志位于 `tmp/arena-worker-candidate-validation/20261011-minimal-r1/node-full.log`，摘要 `CF1A3E2426D7A042EC910CFA80D4AC998C91ECFC4C1B8FE33FFDDF37563DC049`。Node 定向包含真实线程中资源读取暂停时另一实际 HTTP 连接仍收完整响应、真实超时/重置继续失败、部分证据留存、69 项故障拒绝检查与 33/33 度量断言。新的完整回归、候选与真实新 cohort 结果在完成后单独记录，旧 F8 实跑不代签它们。

## 最低表现候选与捕获诊断

冻结 tree `c2b5ded905b2201f9b60b64e1653ceb6b6219243` 的完整 Host 回归为 7045 项：7023 通过、22 项既有专项跳过、0 失败，串行入口标记恰好一次，测试与探针进程全部退出。日志位于 W2 `tmp/arena-worker-launcher-validation/20261011T060054Z-515ec513/launcher-full.log`，SHA-256 `3C5688D51A6F9E147804F9A64E06682D0B0DB586CBC219336102DC67CBB4AE20`。

完整 producer 生成独立候选 `c-5dbdd55b4e41-b7b2706ac9-20261011t060123130z-2dbd23dc`：identity `5DBDD55B4E41A99954F2E96B3437DE3FFC06DEFC6773677BE26CC93BBE41E45B`，closure `DED864E04FCF8339DC6B73AF78FB4EB63D9C613D85C155F4F1256CC73834E92E`，Core SHA-256 `D184F369AB1A106EC161ACA093FE44C5908EA5DBAE6AE3FC5D9ADA2CAD3F1068`。Index 策略 47/47 通过，回执 `tmp/arena-worker-candidate-validation/20261011-minimal-r1/policy.json` 的摘要为 `906F2C666177D642FCBF992C1B73687C19D9EFA9CD29D0DA0D10A44959AFA95C`。W2 为同候选逐文件核验的副本，不是独立 builder；没有正式推广。

`aw-live-p0-minimum180-20261011-v5` 保留一个 `bridge_lost` 失败行，首局等待 150008.7 ms，零有效样本，整组墙钟 246598 ms。实际窗口为 320×180；在本机 125% DPI 下，预算从初始 180 调整为 144。世界捕获曾接受首帧，但后续没有满足新围栏的可接受帧，原 10 秒捕获门失败，AS2 等待真实揭幕而没有开始战斗时钟。等待中的约 30 FPS / LOW render sample 不代替已开始的战斗；Host 性能完成观测也没有合格值。

单次私有诊断 `aw-diagnostic-output640-20261011-v1` 保留同一候选、180 上限、LOW、表现预算 2、关闭 HUD / Web 动效和三局近战输入。只在真实 `start` 前将精确新 Worker 窗口由 320×180 调整为 640×360：一次 `SetWindowPos`，位置、隐藏 owner 和前台观测不变，前后真实 status 的 Host 身份及 Guardian HWND 一致，随后才发送一次真实 start。因 Worker 隐藏任务栏，实测 `MainWindowHandle=0`，窗口绑定使用既有 status 的 `guardianHwnd` 再经 Win32 核对；未修改产品协议。

诊断中源裁剪为 400×225、Flash 源预算为 180、输出为 640×360，但仍只接受首帧并在捕获门失败；首局随后等待 150014.4 ms 留下 `bridge_lost`。该对照说明单纯放大窗口未解决现象，不能独立归因于尺寸、DPI、遮挡或静态画面。其外层始终为 `qualificationExcluded=true / p0Qualified=false`。`received` 统计的是通过时间、尺寸、裁剪过滤并完成提交的帧，不等同 `FrameArrived` 次数；`presented` 持续增长也不能给新源帧代签。

两次失败均取得真实客户端 shutdown 回执并自然回收，完整线程后置校验与资源 / 存档保护通过，正式入口和共享状态的 55 项记录及 GPU 偏好摘要未变。v5 记录位于 `tmp/arena-worker-live-validation/20261011-p0-v5`，尺寸诊断位于 `tmp/arena-worker-live-validation/20261011-diagnostic-output640-v1`；日志包含轮转副本，原始行和独立复算留在各自 experiment。它们证明退出修正在这两次单 Worker 失败场景中工作，不代替新的双 Worker 故障隔离。

捕获恢复草案没有进入产品代码。失败后只读采样在 06:51 UTC 观察到会话显示状态为 0；两次失败本身没有同期连续显示记录，不能反推其根因。随后保持同一 5DB 候选与原新帧、裁剪、场景围栏及超时判据，在实际亮屏条件下完成下述 v6 验证，没有新增原生重采样或放宽准入。

Node / Host fixture、AS2 Compiler 0/0、真实候选、双实例运行与人类感官验收分别记录。没有当前候选的 P0 后台时钟与 P1 实例隔离实测，不宣布“安全双开”。48–72 小时四开长测、完整恢复调度、AI A/B、Stage Trial 和正式发布均不属于本轮完成条件。

验证入口与继承门按 [testing guide](../agentsDoc/testing-guide.md) 和 [Arena campaign 验证](../agentsDoc/testing-details.md#竞技场斗兽标定campaign-门) 执行；AS2 编译必须遵守 [CS6 操作与恢复](../scripts/FlashCS6自动化编译.md)。新工具落地后登记其准确命令与验证证据，不提前把拟议接口写成已可运行。

## v6 完成结果与源码交接

以下记录均以 W1 私有根为基准；W2 是同一候选的第二独立资源根。源码与真实 CS6 产物保持上述 c2b5 / 5DB 绑定，最后只修订三份说明文档；未把文档修订后的工作树冒充原 Index 策略的冻结 tree。

- P0：`tmp/arena-worker-experiments/aw-live-p0-minimum180-20261011-v6`。六局 finished、零错误，战斗计时合计 34177 ms、实际帧率 29.994–30.296；全组完整墙钟 143523 ms。近战与远程双方各自为 cold / warm / warm，均为 9 个技能、冷却清空且定义签名一致。Host / Flash 采样平均分别约 0.140 / 0.488 个逻辑核，配对工作集采样峰约 1.119 GB；未计 WebView 子进程，不是整机功耗证据。
- P1：`tmp/arena-worker-experiments/aw-live-p1-minimum180-20261011-v6`。串行在 w01 先后启动两次独立会话，近战与远程各三局；并行在 w01 / w02 同时运行相同冻结任务。两组各六局均正常结束，实际帧率 29.798–30.218；完整墙钟分别为 241142 / 168129 ms，吞吐比 1.4342677。`independent-finish-review.json` 与 `independent-log-identity-map.json` 分别复核原始结果及 Host / Flash PID、生命周期与呈现日志关联。
- 故障隔离：`tmp/arena-worker-experiments/aw-live-fault-minimum180-20261011-v6`。唯一故障 `fault-b6cd3bac-088e-4add-be37-1d4027a1212f` 在 Host 原子核对后终止 w01 的 Flash 28568，精确绑定近战第三局；该局记录 bridge_lost，前两局已完成。w02 当时的远程第二局及后续第三局正常完成，最终三局 finished。两侧 Host 与所属进程回收，保护边界通过。故障组只提供隔离证据，不进入速度资格。

180 是渲染高度请求上限。本机 125% DPI 下真实源为 256×144，LOW、效果预算 2，输出 320×180；这些值由实际 performance observation 与 native presented 日志交叉确认。真实 covered → world handoff → reveal → revealed → hide 链和 battle 起止审计均已核对。战斗结束后静态场景的 advancing=false，以及启动前尚未显示的窗口样本，按其时间段保留，不声称全生命周期每时每刻都有新帧。

本轮显示资格由单次连续系统通知覆盖 owned GUI 启动至全部回收。用户明确授权最多 30 分钟的临时亮屏保持；实际 07:17:23–07:41:29 UTC 使用一次线程请求并在同一线程清除一次，未修改电源计划、未注入输入或解锁。最终 `tmp/arena-worker-display-lease/runs/20261011-bright-v6-r1/end.json` 证实清理，全部 P0/P1/fault journal 前缀与最终日志复核相同。该环境操作不成为 Worker 的默认自动唤醒行为，也不证明人类视觉质量。

普通默认入口证据为 `tmp/arena-worker-normal-regression/20261011-default-v6-r3`：第二个普通 Core 因全局单例退出 0，原宿主 / Flash / 热键守护进程在一次 CloseMainWindow 后退出 0。此前脚本先因多个 Node 路径拼接失败，再误将同 Core 的 hotkey-guard 子模式当作外部实例；两次失败原样保留。修正只作用于忽略目录中的回归包装，守护子进程须满足精确 held parent、创建时间、路径、命令模式和候选 PE MVID；没有放行任意同名进程。

显式 Legacy 入口证据为 `tmp/arena-worker-normal-regression/20261011-legacy-v6`：唯一批次 `ag-normal-legacy-20261011-c768d544`、唯一专用槽，正常 MEDIUM 配置下完成 203 帧 / 6768 ms。收尾包装的只读 status 曾因错误的 HTTP Host 地址返回 400；原失败保留。改用与既有客户端相同的 localhost 地址后，仅对同一 Host 做两次只读状态查询，重新核对完整十字段、原件 / 快照、已完成终态与专用槽，再一次 CloseMainWindow；没有重跑批次、额外 abort、HTTP shutdown 或自动恢复。`readonly-continuation-verification.json` 与 `continuation-completed.json` 记录实际续查和全部退出 0。

Worker 最终保护快照与普通入口回归后的 55 项共享 / 正式入口记录、GPU 偏好摘要完全相同；无残留 Host、Flash 或测试进程。汇总为 `tmp/arena-worker-live-validation/20261011-final-v6/display-and-normal-boundaries.json`。源码迁入使用最终 76 文件字节清单、main `34e312a` / `1551602` 前像核对与逐文件备份，仅复制源文件；正式 SWF、runtime、bootstrap、Index 和 Git 提交不在迁入操作内，记录归 `tmp/arena-worker-main-migration/20261011-final-v6`。

供人类监督的一份全新、尚未执行输入为 `tmp/arena-worker-p0-inputs/20261011-human-supervision-v1/live-human-supervision-minimum180.json`，SHA-256 `4871A00DCD901407535AA3D3418E56DEA1405649CC5E0DEE0E38A70FA6D4A3BD`。它绑定上述私有候选与 W1 资源，不能直接改指向 main 的合并发布资源；既有 v6 显示包装的白名单不包含此新输入。人类监督时在亮屏环境使用 W1 下的 `node tools/arena-calibration/run-worker-experiment.js --plan tmp/arena-worker-p0-inputs/20261011-human-supervision-v1/live-human-supervision-minimum180.json`，该命令会建立一次新的实验，已消费的实验身份不重放。人类视觉、实体输入、长时热稳态与标准入口验收仍独立保留。

## 正式发布列车（2026-10-11）

用户已明确授权本次提交、推送、云端共识与正式构建部署。发布前无冲突合入远端 `07ef4d1429d704973453dd501e08ad750c362374` 的前治安官源码、资产与原发布设置；原 76 个交付文件字节保持不变，随后仅更新发布说明及受控 source tag。合并后的 AS2 必须由 main 的真实 CS6 重新验证与发布，不能用旧私有 SWF 覆盖上游。此前 v6 的运行资源范围与实测倍率仍按原 cohort 保留，不给新增前治安官业务或合并后的标准入口代签。

本列车冻结源码 `2b1fb74477a57b27a712a483b6eaee73fbc3a15f`，受保护 source tag `runtime-build-v2/20261011-arena-worker-p0p1-v1`，immutable request `058416A0F489E502BF53860820FA58D7E3248C5A3BCD3AEAC09A22B8D55ABB19`。本机 X509 `builder-local-c / physical-host-c` 与 [GitHub hosted OIDC 独立构建 38126520046](https://github.com/FlashNightModReborn/CrazyFlashNight/actions/runs/38126520046) 的 build identity / 43 文件 payload closure 全等；完整 production policy **47/47**，receipt 精确绑定本次 signed CAS。正式 Core 与上述私有实测候选逐字节相同，AS2 则已包含新合入的上游资源范围。

合并后的 main 真实 CS6 Worker protocol **52/52**、技能缓存 **21/21**，三轮 Compiler 均为 **0/0**；重新发布的 asLoader 为 **6,007,550** 字节、SHA-256 `601CD42C51FF8CC1156E0CA7D4A688DC15E7CA65384F9F537E04136C05FA3B4D`。Node 检查、文档巡检与 22 项冻结派生资源检查通过。首次 prepare 发现前治安官缺失于生成的存档修复字典，原失败日志保留，生成器补齐后随源码提交；未放宽门禁。

唯一 writer 于 **2026-10-11 09:06:34 UTC** 完成正式推广，双 signer / 双 faultDomain、43 文件安装闭包和根 bootstrap `--verify-only` exit **0**。previous bundle 保留于 `tmp/runtime-promotions/20261011T090603919Z-6d91ba38dbb740baa3310bca6f65dd6e/previous`；完整身份与回执见 [发布证据](evidence/arena-worker-runtime-release-2026-10-11.json)。部署提交与远端 Audit 等待本次推送后的独立结果。原 v6 运行、显示、故障及负面证据保持原范围；本次未执行合并资源后的标准入口业务旅程，不宣称人类视觉、实体输入、弱机或长时热稳态验收。
