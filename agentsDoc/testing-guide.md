# 测试指南：按改动选择验证

**文档角色**：验证选择矩阵。**最后核对代码基线**：commit `2e5e32321506fa1fb2693f3928205f8c45b4235e`（2026-09-17）。

<a id="select"></a>
## 选择与证据边界

本页只决定“本次必须验证什么、何时扩展”；不存发布流水账、不用旧通过数代签新工作树。
先取实际 diff 和受影响入口，再选择以下行；一次任务可以命中多行，**去重执行，不把下方所有专题串成必跑清单**。
文档链接调整只做文档验证；并不因此运行游戏、写存档、重建正式 runtime 或申请新人工验收。

命中的业务必须覆盖成功、拒绝、边界、失败恢复及相关重入/迟到回包；既有专题更严格的义务继续有效。
轻量选择矩阵不削减专题门：遇到协议、持久写、编译恢复、资格证据或产物闭包，进入对应 `testing-details.md` 正文，
定位该任务的完整 runner、前置条件和限制后停止扩读。命令只能在实际授权范围执行；工具可产生文件或启动进程，不能只看名称认作只读。

证据分别记录源码/静态、逻辑 runner、Mock-browser、真实 Host/Flash、候选、正式 runtime 与人类专项。
`compiled` 不等于行为通过，`candidate_built` 不等于 `candidate_executed`；通过的候选不代签 promotion；
promotion 不代签该业务的 `standard_entry_verified`。说明实际运行的路径、目标与证据种类；未运行就写未运行。
同一工具重复出现在多行只执行一次；新授权只在真的超出范围时申请。

<a id="docs"></a>
## 文档、导航与工程纪律

**触发：** 文档内容/入口、路径归属、校验器或派生清单说明发生变化。
**必需：** 对照受影响规范和机器真源，执行 `node tools/validate-doc-governance.js` 与 `git diff --check`。
新/改链接验证目标文件、精确锚点、条件和停止位置；根入口及矩阵测 UTF-8 字节与真实阅读范围，不以压行达标。
修改巡检器再执行 `node tools/test-doc-governance.js`（巡检器 fixture 单测）。
**条件扩展：** 装备函数所有权、运行闭包、面板注册或数据来源实际改变时，追加对应已有生成/一致性检查。
贡献流程/分支准入工具本身改变才跑其回归；文案修正不运行远端 ruleset 变更、发布或游戏。
**正文：** [文档验证与继承门](testing-details.md#docs)。

<a id="data"></a>
## XML、数值与游戏内容

**触发：** data/config、配方、属性、任务/地图/敌人/掉落定义及其源工作簿变化。
**必需：** 先按 [数据规范](data-schemas.md#data-entry) 检查 XMLParser 的隐式类型/数组语义及真实 loader；
执行所涉数据 validator，并在授权环境重启验证真实消费者。仅数据变化不要求编译 SWF；若源码或装载合同也变，再追加 AS2/Host。
**数值条件：** 原工作簿/公式仍为相应源；保留 `typecheck`、测试、`roundtrip-check`、`balance-sync -- --check`、
`balance-check` 等原数值链要求，工作目录和参数见正文，不用手改派生 XML 代替。
**专项条件：** melee-longgun、佣兵掉落、TimePool、关卡结算、军阀等执行各自 validator/runner 和对应真实 HUD/流程验证；
通用 XML 解析成功不能代签这些合同。
**正文：** [数据与数值](testing-details.md#data)；[关卡与输入](testing-details.md#stage-input)。

<a id="as2"></a>
## AS2 逻辑与 Flash 编译

**触发：** 类、帧脚本、asLoader/TestLoader、主或独立 XFL 及对应 SWF 变更。
**必需：** [AS2 反幻觉](as2-anti-hallucination.md)；选择真实归属目标和命中业务的 tracked focused runner，
检查 `.as` BOM、调用/装载兼容、成功及失败边界。非 class 帧 runner 禁止具体类 import；使用包通配或全限定名。
编译操作以 [CS6 工具说明](../scripts/FlashCS6自动化编译.md) 为准；不用活动文档猜目标。

目标为逻辑注入时 `-Target publish`，测试为 `-Target test`，仅主 XFL 为 `-Target main`；
独立资源使用 `-Target <xfl> -PublishOnly -VerifySwf <swf>`。
`publish_done.marker` 仅结束等待；要求本轮新鲜 Compiler `0/0` 和目标 SWF 刷新。
TestLoader 另需本轮 suite 的新鲜 trace 或新鲜导出 Output Panel，无失败断言；两种证据不可混称。
publish 本就无 trace，不因日志未刷新判失败。逻辑通过不等于真 socket、跨 SWF 生命周期或真实落盘通过。

**runner/恢复条件：** focused runner 修改 scratch 前先完成持久、SHA-256 可验的备份和 inflight marker；
整事务持同一编译 mutex，子调用只能复用 exact-match lease；lease 不是授权。
异常 marker/未静默进程必须按恢复协议处理，不能删 marker 试运气。
fresh TestLoader SWF 还运行 `node tools/swf-function-sizes.js scripts/TestLoader.swf --max 60000 --top 15`；源码大小只是提示。
**归属条件：** 装备函数/帧汇编/BOOT_SOURCES 改动追加 assemble→check→BOM→coverage；
main/asLoader 类所有权改动执行 strict single-ownership，不以 child-only 检查替代。
**正文：** [Flash 核心](testing-details.md#flash-core)、[focused runner 与恢复](testing-details.md#flash-recovery)、
[业务 suite](testing-details.md#domain-suites)。本页没有授权启动编译或覆盖未保存的 CS6 文档。

<a id="cross-layer"></a>
## 跨层协议、面板迁移与权威

**触发：** 新命令、schema/身份/版本、打开/关闭、数据所有权、写锁、token、回包或原入口退休。
**必需：** 先读 [权威核心](as2-web-panel-migration.md#authority-core) 及命中的领域合同；
闭合 Web cmd → C# action → AS2 handler → response → consumer，覆盖 exact 身份、拒绝、迟到、重入、未知结果与恢复。
Host 命令注册/审计白名单/dispatch 映射一起核对；改源码须跑对应 AS2 focused、Host focused 与既有 Launcher 全量要求，
以及该面板生产脚本闭包的 Node/browser/静态门。纯 Mock 不代签生产 opener/session/Host/Flash 链。

**持久写条件：** 追加 [存档与资产](#save)。未知写按业务 exact operation 身份查询对账，不盲重放、不从投影猜成功。
**退休条件：** 查生产 opener、Host dispatch、主/子 SWF 实例和 import 的可达性；有 linkage 不等于仍可达。
保留 AS2 parity oracle；不能为验旧截图强迫用户走已退休入口。
**范围条件：** 新/删迁移范围在自然收口更新迁移清单；不在每次工具调用写进度。
**正文：** [跨层验证](testing-details.md#cross-layer)、[业务 suite](testing-details.md#domain-suites)。

<a id="web"></a>
## Web、共享工作台与小游戏

**触发：** 页面脚本/CSS、共享 primitive、焦点、动效、布局、lazy closure 或小游戏。
**必需：** 定位 [生产注册与入口](../launcher/README.md#panel-registry)，执行该功能既有 Node QA、
真实浏览器 harness 与静态/契约检查；覆盖生产脚本闭包、真实 feature DOM、最低逻辑画布、中文长文案、
滚动极值、命中区和 keyboard/focus。CSS 变更（feature 或 shared contract）读取 [工作台合同](workbench-ui-system.md#ui-core) 中命中的布局/焦点/CSS 治理节。
**共享变更：** 追加受影响 consumer 矩阵、layout/ratchet、真实 reduced-motion 和 atlas；
合成 atlas 不能代替具体业务，media-query 文本存在不等于动效通过。
**加载变更：** 追加 lazy dependency/失败驱逐/重试/取消；注册表与依赖次序一致，不用 Mock 快照代替真实脚本加载。
**交互/关闭变更：** 跨层协议与真实 opener/session/Host 场景另验；没有 harness 时按既有约束补充，不绕生产入口。
**正文：** [Web 及工作台](testing-details.md#web)、[业务 suite](testing-details.md#domain-suites)。

<a id="host"></a>
## Host、通信、启动与自动化

**触发：** C#、V8/native glue、Launcher 配置/CLI、bootstrap、bus 或自动化工具。
**必需：** [源码职责](../launcher/README.md#source-map) 与相应 README；执行命中 focused tests 和
`powershell -File launcher/tests/run_tests.ps1` 的既有适用要求，保持 runner policy 单点维护。
涉及配置、CLI、bootstrap、panel/minigame 注册时，精确集合巡检必须随源码保持一致。
**候选条件：** 需要运行/视觉验证且已授权时才建隔离候选；记录实际执行的候选与身份。
`--bus-only` 只证明对应 headless bus 范围；测试 Movie/裸 Flash 不代签真实 Launcher 的 socket/trust。
**native/发布条件：** source-ahead 可以暂不发布；只有部署闭包与授权命中才追加 [runtime](#runtime)。
**正文：** [Host 与自动化](testing-details.md#host)。

<a id="save"></a>
## 存档、资产交易、奖励、退出与恢复

**触发：** SaveManager/R1、SafeExit、库存/共享收纳/暂存领取、交易、奖励或可能触达真实用户槽位的 E2E。
**必需：** 对应业务原子性、真实 owner、root/operation/session 身份及恢复合同；覆盖超时、畸形成功、重复/迟到、
生命周期切换、部分完成、重启恢复、防丢防重和非法成功拒绝。未知写只走该域允许的 exact query/reconcile，不自动重试写。
原 `filterSpec`、空选择拒绝、逻辑 entry revision 与物理 lease、双快照解锁等要求仍属于具体领域，不改成宽泛口号。

**实写条件：** 必须有明确测试范围，使用规定隔离/克隆槽；保护既有差异及原始字节，不反向覆盖玩家已有存档。
A5/R1 的源码、写出、重启读回闭包和白名单忽略项照原合同验证；不能把通用 save ack 当真实落盘。
SafeExit 的 arm 后本轮 sv:1→sv:2、场景唯一完成与退出顺序按对应合同覆盖。
**场景条件：** reward/地图/选关/任务的一次返回交付、重入与迟到结果追加关卡专项；
槽位 agent_control 只能使用其授权测试槽和生产 opener→session→Host 链，禁止直注入伪造通过。
**正文：** [持久写与恢复](testing-details.md#save)、[关卡与输入](testing-details.md#stage-input)。

<a id="derived"></a>
## 派生输出、闭包与可复现性

**触发：** 生成源/生成器/sidecar、脚本 bundle、头像图标、材料索引、任务目录或运行依赖变化。
**必需：** 从真源再生并执行对应 `--check`，验证 source→generator→output→manifest 的一致性；
不得手补派生文件掩盖 stale。检查 BOM/EOL/raw-byte、大小写和排序 oracle、Git tracked/disk 的精确集合与禁止多余项。
计数/hash 以当前机器产物为准，不复用历史通过数；尚无机器真源的活跃阈值先保留，不能直接删掉。
**范围条件：** 游戏产物变化执行真实消费者检查；进入正式部署闭包才追加 runtime，不将所有派生提交视为独立发布请求。
**正文：** [派生物与生成输入](testing-details.md#derived)。

<a id="art"></a>
## 美术、XFL、图标与头像

**触发：** 原生矢量/模型转绘、XFL/library、图标/纸娃娃、头像裁剪与推广。
**必需：** [装配规范](art-asset-assembly.md) 的唯一可编辑源、坐标、比例、命名、action frame、library/linkage 与消费者一致性；
执行所涉 audit/rename/fix-includes/确定性构建工具，检查透明/滤镜/方向、打包输出与实际 consumer。
**编译条件：** 实际改动 XFL/SWF 时追加 [AS2/Flash](#as2)，独立 SWF 不用 main 代编；需关闭未保存目标前遵守用户资产保护。
**专项条件：** IconBake/normalization、语义查询/纸娃娃/武器动画按各自 suite；头像 campaign/production promotion
另外读取明确真人回执、方向 supersession、不可变证据包、evidence-only 与消费者闭包，未人审不得自动推广。
**正文：** [美术与资产](testing-details.md#art)、[头像专项](testing-details.md#portrait)。

<a id="runtime"></a>
## 正式 runtime 构建、发布与标准入口

**触发：** 已获授权的正式发布、实际部署闭包变更，或发布工具/协议本身的维护。
**必需：** [发布协议](../docs/runtime-build-reproducibility.md#release-protocol) 与
[状态边界](../docs/runtime-build-reproducibility.md#evidence-states)，按真实 source/tag/request/identity/closure 执行其门；
同 immutable source 的双 signer/双 faultDomain、strict v2 policy、唯一 writer 和 bootstrap/runtime manifest/consensus 一致性不变。
不得候选拷贝正式路径、绕 ruleset 或伪造第二 builder；单独本地构建、人工候选、signed artifact 互不代替。
**Audio 分离：** 通用 promotion 不要求 Audio H1/H2/E3/截图/听感，不可因此使用 emergency-release；
真正影响 DLL 的音频源码/配方/toolchain 输入仍受闭包约束。维护历史 emergency 工具才读其旧验证合同。
**部署后：** standard-entry 只覆盖实际验证的功能/环境；记清尚未重跑的业务与感官验收。
**正文：** [发布选择及旧要求的替代关系](testing-details.md#runtime)；操作权威仍是 runtime 文档和机器真源。

<a id="diagnostics"></a>
## 现场故障、焦点与诊断观测

**触发：** 输入/焦点/卡顿/进程残留/消息丢失和现场观测。
**必需：** 区分探针、分发延迟、关联丢失、生命周期和真实业务 owner，读取现役诊断 ADR 的启用方式、限额与证据窗口。
本机不复现不等于现场无故障；观测不授权 watchdog/重试/自动修复，诊断开关默认值和精确启用值不得扩大。
**实机条件：** 只有现场取证/新鲜行为需要才启动相应环境；日志脱敏、用户存档与未知写保护仍适用。
**正文：** [诊断入口与证据边界](testing-details.md#diagnostics)。

<a id="specialized"></a>
## 专项资格、长时运行与真人评价

**触发：** Audio H1/H2/E3、NativeHUD、PlayerInfo B0、F8、斗兽标定、头像生产等命中专项。
**必需：** 先读该专项当前 ADR/runner 所定义的 source/corpus/plan/hash 与接收标准，再跑其适用门。
历史长时记录、成功比例、固定模板/模型并发是当时证据或专项配置，不是全项目默认。
未找到明确替代证据的活跃规则继续保留并标待核，不能因为“旧/长/贵”而静默删除。
**边界：** 真人评价、长时 soak、候选执行和正式供应链分别陈述；不追加新的全项目人工签字流程。
**正文：** [资格与 campaign](testing-details.md#specialized)、[头像](testing-details.md#portrait)。

## 下沉正文与原来源

以上 `testing-details.md#…` 正文与本矩阵同批建成（2026-09-17）。原义务来自冻结 `agentsDoc/testing-guide.md`
（336,166 字节 / 114 物理行），逐句拆分至 details 对应章节；纯历史收据转入
[testing-guide 历史归档](../docs/testing-guide-history-2026-09-17.md)（含来源行号与取代关系）。

- `#docs`：原 L54、55、114 的文档/所有权/准入部分。
- `#data`、`#stage-input`：原 L6、8、9、22、29、34、37、57、72、98–101、114 对应条款。
- `#flash-core`、`#flash-recovery`：原 L62、65–71、74；业务专门的 suite 数和阈值归 `#domain-suites`，未核对前保持有效。
- `#cross-layer`、`#domain-suites`：原 L3–15、19–33、38–53、57–61、94–108 中命中协议/领域的当前规则。
- `#web`：原 L19–33、38–53、60、73、92–107 中布局、运行闭包和消费者部分。
- `#host`、`#runtime`、`#specialized`：原 L18、21、35–40、55、75–89、114；L87 明确替代早期通用 Audio 发布前置。
- `#save`：原 L4、5、8、23、26、57、61、85、102、104、106–108、114 中持久写部分。
- `#derived`、`#art`、`#portrait`、`#diagnostics`：原 L10–12、27、34、39、43–49、54、69、88、94、103、108、111–114 的对应部分。

以上来源重叠表示一行混合多类信息，不允许整行按日期或数字自动归档。
旧片段到当前 owner 的逐条索引见 [历史归档](../docs/testing-guide-history-2026-09-17.md)。
