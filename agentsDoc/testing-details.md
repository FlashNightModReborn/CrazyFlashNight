# 测试正文：按需验证细节

**文档角色**：验证规范层正文（由选择矩阵 `agentsDoc/testing-guide.md` 路由进入）。**最后核对代码基线**：commit `2e5e32321506fa1fb2693f3928205f8c45b4235e`（2026-09-17）。

本页是验证矩阵的规范层正文：按主题分节，读者只读命中章节即可，不要求回头全量读 AGENTS.md、`agentsDoc/testing-guide.md` 选择矩阵或迁移回包。任务到门的触发与选择规则在矩阵页；本页承接命中主题后的完整 runner、工作目录、参数、成功判据、失败恢复条件与证据边界。

**通用前缀**：PowerShell 命令前先跑 `chcp.com 65001 | Out-Null`（避免 GBK 乱码）；本文所有 PowerShell 命令默认已执行该前缀，不再每条重复。

**计数口径**：runner 阈值分两类——机器钉死（runner 脚本内的 `ExpectedTracePatterns`/断言常量钉住，本文给出当前钉值与脚本路径，以脚本为准）与文本阈值（找不到当前机器真源的历史文本计数，保留为有效义务并就近标注「（待核：阈值来源为历史文本，未找到当前机器真源）」）。带日期的旧计数、旧 runId、旧 SWF hash 与旧发布身份是纯历史收据，不复制进本页，统一转入 `docs/testing-guide-history-2026-09-17.md`；有取代关系的只保留现役口径。任何旧通过数都不得代签新工作树。

**证据分层通则**：源码/静态、逻辑 runner、Mock-browser、真实 Host/Flash、候选、正式 runtime 与人类专项分别记录；`compiled` 不等于行为通过，`candidate_built` 不等于 `candidate_executed`；通过的候选不代签 promotion；promotion 不代签业务 `standard_entry_verified`。未运行就写未运行。

<a id="docs"></a>
## 文档与治理验证

**触发**：文档内容/入口、路径归属、校验器、装备函数所有权或派生清单说明变化。

**必跑**：

- `node tools/validate-doc-governance.js`（级联 `tools/validate-equip-fn-coverage.js`：装备目录 ≡ frame37 ≡ README 索引）。
- `git diff --check`。
- 修改巡检器本身时追加 `node tools/test-doc-governance.js`（巡检器纯文本 fixture 单测，现役入口）。

**视改动追加**：

- 交叉 grep / 链接检查 / 基线复核。
- 改 TaskManager 零间隔分发须在 TestLoader 跑 `TaskManagerTester.runOrderingContractTests()`，每 case 用新 tester，覆盖首次入表、`0→0`、分发外 `0→正→0`、时间轮回调新建零任务本次执行、零任务回调新建 ID 下次执行及快照已有 ID 重入限制。
- 主线准入与 ruleset 状态机验证门见 [正式 runtime 发布](#runtime) 的「主线准入与发布授权门」。
- 套装系统（剑圣一期起）的 validator/preflight/单测/游戏内验收门属领域 suite，见 [套装与武器专项](#suite-equipment-set)。

<a id="data"></a>
## XML、数值与游戏内容

**触发**：`data/`、`config/`、配方、属性、任务/地图/敌人/掉落定义及其源工作簿变化。

### 武器 balance v1 / profile 标定

必跑（工作目录 `tools/cf7-balance-tool`）：

- `npm run typecheck`
- `npm test`
- `npm run roundtrip-check`
- `npm run balance-sync -- --check`
- `npm run balance-check`

根目录另跑 `node tools/validate-doc-governance.js` 与 `git diff --check`。

固定门（拒绝项与 digest 合同）：

- 旧平铺/v2/runtime SHA 草案拒绝；`workbookVersion → SHA` 注册映射严格一致。
- 台账/runtime 8 输入、状态、digest 对账；每个现有 `data/data_*` 有独立 profile；未知 tier/缺 profile 不回退。
- input digest 绑定身份/profile/机械语义/workbookVersion/14 项业务数字；source digest 覆盖完整 effective data/skill/lifecycle。
- 普通物品 clone 不携 balance；Web 只见四字段最小摘要。
- 公式最终仍以当前 SHA 的 XLSX 工作簿为准；仓库工具只作派生计算与辅助验证，不用手改派生 XML 代替。

视改动追加：

- 改 AS2 选择/摘要/缓存时用 `scripts/compile_test.ps1 -Target test` 取得 `InventoryPanelServiceTest`、`NpcShopPanelServiceTest`、`KShopCheckoutServiceTest` 的 fresh trace（各 suite 计数机器钉死值见 [Flash 编译核心](#flash-core) 与对应 runner 脚本），再用 `-Target publish -VerifySwf scripts/asLoader.swf` 刷新注入层。
- 改玩家显示时追加 `node tools/test-workbench-primitives.js`、`node tools/test-kshop-presenters.js`、KShop/NPC harness 与物品格视觉矩阵（文本现役 20 项，待核：阈值来源为历史文本，未找到当前机器真源）。

### XML / 数据 / 游戏数值通用门

- 受影响路径运行时 smoke。
- 近战/压制近战长枪的 `bullet`、`split` 或 `data*` 变体改动固定运行 `node tools/validate-melee-longgun-chain.js`。
- 竞技场标准佣兵掉落固定运行 `node tools/validate-arena-drop-rules.js`、`powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run-arena-drop-rule-tests.ps1 -TimeoutSeconds 240`（机器钉死 20/20）
  与 `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run-boot-sequencer-tests.ps1 -TimeoutSeconds 240`（机器钉死 BootSequencer 91/91 + BootstrapHandshake 12/12），分别冻结 XML/物品目录/旧可达集合、规则顺序与概率语义、启动 fail-closed 和 `ItemObtainIndex → TooltipComposer` 来源投影。

- `compile_test`、游戏内人工验证按改动面追加；近战长枪静态门不代签 Flash 或实战命中，重启后人工回归多段主伤、同一目标一次多段命中只附加一份淬毒及暴君收割机副武器隔离。
- 触及掉落 AS2 或启动加载时发布 `scripts/compile_test.ps1 -Target publish -TimeoutSeconds 300 -VerifySwf scripts/asLoader.swf`；Web/AS2 tooltip 消费链变化再追加 tooltip corpus 门（见 [Web、工作台与小游戏](#web)）。

派生输出的再生与 `--check` 规则见 [派生物与生成输入](#derived)；掉落/关卡行为对真实 HUD 的验证见 [关卡、输入与战斗](#stage-input)。

<a id="flash-core"></a>
## Flash 编译核心：目标选择与成功判据

**先选层级，再选 `-Target`；默认频率 / 优先级是 asLoader → TestLoader → main，不要把普通 `.as` 改动默认升级为主文件编译。**

速查（归属 → 目标）：

- `asLoader` 逻辑注入层（多数 `scripts/类定义/`、`scripts/逻辑/`、WebView bridge、`_root.gameCommands.*`）→ `-Target publish`。
- `TestLoader` 测试层 → `-Target test`。
- 主文件运行壳（`CRAZYFLASHER7MercenaryEmpire` 主 XFL、主库元件、主 linkage、主时间轴）→ `-Target main`。
- 独立资源 XFL / 子 SWF（如 `flashswf/UI/*`、`flashswf/levels/*`、`flashswf/arts/*`）不归 `main` 兜底：先定位同目录 `.xfl` 与 `PublishSettings.xml` 输出 SWF，再跑 `-Target <xfl> -PublishOnly -VerifySwf <对应.swf>`。

**入口**：`powershell -ExecutionPolicy Bypass -File scripts/compile_test.ps1` 或 `bash scripts/compile_test.sh`（等价 bash 入口，参数语义相同）。

显式 `-Target` 免手动切活动文档；省略 `-Target` 则取当前活动文档。`publish_done.marker` 只结束等待；exit 0 还要求本轮新鲜、严格 `0/0` 的 `compiler_errors.txt`，并通过目标对应的 SWF / 行为门。编译操作链路与计划任务细节以 [scripts/FlashCS6自动化编译.md](../scripts/FlashCS6自动化编译.md) 为准，不用活动文档猜目标。

成功判据按目标不同：

- **TestLoader（测试构建）**：成功 = `[OK] 编译完成` + 本次运行的新鲜行为输出 + `compiler_errors.txt` `0 个错误`。行为输出可取本轮新鲜 `scripts/flashlog.txt` trace，或在 trace 为空时取脚本本轮导出的新鲜 `scripts/compile_output.txt` / Output Panel 副本；两者都必须明确证据类型、suite 名和断言数，并且无 `[TEST_FAIL]` / `[FAIL]` / `Tests Failed: N>0`。
  不得把 Output Panel 副本称为 trace，也不得仅凭 `publish_done.marker` 判成功。`scripts/TestLoader.as` 被 `.gitignore`，是本机 scratch runner，仓库不保证其当前固定调用任何 suite；每项施工必须用 tracked aggregate/template 或在记录中给出实际 runner、suite 名与断言数。template 安装后属于非 class 帧脚本，必须保留 UTF-8 BOM，且只能使用包通配 import 或全限定类名，禁止具体类 import。
  **仅逻辑层**：真 socket、跨 SWF 生命周期、真实存档落点仍须真机复核，分层见 [构建标准 §5.3](../docs/asLoader-BootSequencer-构建标准-2026-06-16.md)。
- **asLoader / publish 模式（发布二进制，剔 trace 等功能以免性能损耗）**：**本就不出 trace**——脚本会打 `[INFO] 无 trace 输出 (publish 模式不执行 trace)`，`flashlog.txt` 不刷新属正常，**不要据此判失败**。成功 = `[OK] 编译完成` + `scripts/compiler_errors.txt` 显示 `0 个错误` + `scripts/asLoader.swf` 已刷新（mtime/size 变化）。
  **SWF 刷新机器门**：`-Target publish` 会自动启用 `-VerifySwf scripts/asLoader.swf`，正确示例是 `powershell -File scripts/compile_test.ps1 -Target publish -TimeoutSeconds 150`；显式重复传同一路径也允许。`-Target main` 同样自动校验根主 SWF；任意 XFL/FLA 路径目标仍必须显式传对应的 `-VerifySwf <目标.swf>`。
  脚本触发前记录 SWF 的 mtime/size 基线，成功路径校验其确被重写：未变 / 不存在 → `[ERROR] 目标 SWF 未刷新` + `exit 1`（fail-closed）。
- **main / 主文件 publish-only**：只验证主文件运行壳、资产挂载、linkage 与主时间轴相关变更；不替代 asLoader 逻辑注入验证。成功 = `compiler_errors.txt` `0 个错误` + 根目录主 SWF 刷新；`main` 不产 trace 属正常。
- **独立资源 XFL / 子 SWF publish-only**：只验证该 XFL 对应 SWF；例如改 `flashswf/UI/玩家信息界面/LIBRARY/*.xml` 时应编 `flashswf/UI/玩家信息界面/玩家信息界面.xfl` 并校验 `flashswf/UI/玩家信息界面.swf` 刷新。成功 = `compiler_errors.txt` `0 个错误` + `-VerifySwf` 指向的子 SWF 已刷新；`main` 刷新不能替代这个判据。显式 `-Target` 会先丢弃同目标的 CS6 内存文档并从磁盘重开；
  中文/空格路径须归一化 `pathURI` 与 cfg URI，避免复用标题带 `*` 的旧 XFL。部分 XFL 重开会弹缺失字体确认框，异常长等待先截图/检查 CS6 前台并人工确认。关键帧脚本除 `-VerifySwf` 外还须用 FFDec 导出 script 检索新增标志串。XFL/FLA 施工后另跑 `python scripts/tools/xfl/audit.py <xfl>` 与 `python tools/linkage_scanner/scan_linkage.py --xml-only`。

**TestLoader 环境前置**：Node.js 与 `tools/swf-function-sizes.js` 是 `function codeSize < 60000` 硬门；显式 TestLoader 目标缺失任一项时会在触发 Flash 前失败。非 TestLoader 目标缺少 Node 时，预编译 BOM 门仍只告警降级。

**fresh TestLoader SWF 函数尺寸门**：每个 fresh 产物还须跑 `node tools/swf-function-sizes.js scripts/TestLoader.swf --max 60000 --top 15`，并将 `codeSize` 与 canonical 源端单函数闭包度量、fresh 行为证据合用；源字节提示线只作调查，不是 hard gate。

**主 SWF / asLoader class 边界审计**：改 `scripts/类定义/org/flashNight/neur/Server/*` 或部署前追加 `node tools/audit-as2-class-embedding.js --policy child-only`；临时双 SWF 重打兜底用 `--policy dual-build --marker _repairPending --marker applyRepairResolved`。
若主 SWF 仍嵌入 `__Packages.org.flashNight.neur.Server.SaveManager` / `ServerManager`，asLoader 新 class 不会覆盖。**全局单一归属门（asLoader 重构 P1）**：`--policy single-ownership` 断言「主 SWF 嵌入 `org.flashNight.*` 类 = 0 且无 class 同时嵌入两 SWF」——比 child-only 更强，守「主时间轴误直引用游戏 class 致其嵌进主 SWF → 首注册胜出 shadow 掉 asLoader 重编版本」。
改主 FLA 帧脚本 / 新增主时间轴 class 引用、或部署前跑。（文本曾记录基线 main=0 / loader=599 或 625 / intersection=0，待核：阈值来源为历史文本，未找到当前机器真源；门本身按断言语义执行。）

**对外表述边界**：可以说「已完成 Flash CS6 自动化 smoke 验证」/「已触发编译并拿到新鲜 trace」（TestLoader）/「asLoader 发布编译 0 错误、SWF 已重生成」（publish 模式）。缺少新鲜 trace、编译器错误面板或 IDE 复核时不得说「已编译通过」；但 asLoader publish 本就无 trace，以 `0 个错误` + SWF 刷新为准。若 AS2 逻辑改动选择 `main`，必须说明触及主 FLA / 资产 / linkage / 主时间轴，否则应使用 asLoader / TestLoader。

<a id="flash-recovery"></a>
## focused runner 事务与恢复合同

**tracked 入口与编译 mutex**：活跃 focused TestLoader 必须使用 tracked 入口。入口只持同一把仓库编译 mutex；原 runner 的同卷持久备份先写入 `scripts/.testloader-scratch-recovery/<token>.as` 并验 SHA-256，再在改写 scratch 前落 `scripts/testloader_scratch_inflight.marker`，把单锁与持久事务闸覆盖到「安装 template → 子编译复用 exact-match lease → 消费 fresh evidence → SHA-256 恢复 scratch」的完整事务。
子 `compile_test.ps1` 只接受与 marker 中 repo/owner/lease/runner/backup 完全一致的 lease；普通编译见 marker 一律 fail-closed。lease 仍不是鉴权；持久 marker + recovery sidecar 才覆盖「父进程在子编译成功后、恢复前被硬杀且 named mutex 已消失」的窗口，且 marker 只能在 installed/original SHA-256 均验证后删除。

**JSFL 重开协议门**：目标已打开时，`compile_action.jsfl` 先不保存关闭并以 `compile_reopen.marker` 请求二阶段重开；`compile_test.ps1` 只接受与本轮完全相同的 target/mode 且最多一次，随后重新触发计划任务，由下一次 JSFL 从磁盘打开。禁止在同一 JSFL 栈内 close+open，也禁止枚举文档时调用 `FLfile` 平台路径转换；CS6 可能因未保存/非 ASCII XFL 绕过 `try/catch` 中止宿主。改此协议必跑 `node tools/test-flash-compile-jsfl.js`；
真实 smoke 还必须覆盖「目标已关闭直接打开」和「目标已打开二阶段重开」两轮，并各自取得新鲜 Compiler `0/0` + SWF 刷新。

**公共项**：

- `publish_done.marker` **仅说明 JSFL 触发结束**，不能单独视为成功；`compile_test.ps1` 要求 `compiler_errors.txt` 存在、身份/mtime 属于本轮且内容严格为 `0/0`，缺失、空文件、旧副本或非零诊断都失败。
- `compile_action.jsfl` 在每个目标前清空独立 Compiler Errors 面板并删除旧导出，并在任何 target/doc early return 前同时消费一次性 target/mode cfg；PowerShell terminal 路径也同时清两者，timeout/nonterminal 才保留给迟到 JSFL。
- 32K 自动重试使用保守格式：唯一最终汇总可解析、errors>0、warnings=0，汇总前恰有同数量的非空诊断行且每行自身含 `32K`；混合错误、多行上下文、汇总后文本或不可解析格式一律不重试。首轮完整诊断保存在本轮 `compile_output.txt`，最终 `compiler_errors.txt` 属于第二轮；第二轮仍失败则照常失败。testMovie 若重试可能产生两组 trace，但 focused 健康门只接受唯一闭合 runId block 并要求 `32K retry=0`。
- 所有正常编译共享仓库 mutex；所有 scratch writer 在写入前持久记录 `testloader_scratch_inflight.marker` 与同卷 recovery sidecar，只有 byte-exact 恢复后才 exact-match 删除。

**异常与崩溃恢复**：`compile_test.ps1` 在触发计划任务前先写 in-flight `compile_state_uncertain.marker`，故 child host 被硬杀时：已触发则闸仍在，写闸前被杀则尚未触发 Flash；无需由每个父 runner 再把普通编译失败一律升级为人工清闸。父 runner 自身崩溃由 scratch marker 阻断普通编译；
编译 `[TIMEOUT]`，或 focused / Gobang / 协议在 child exit 0 后仍未观察到唯一 runId 终态时，则由 `compile_state_uncertain.marker` 阻断可能迟到的 JSFL/player。marker 带本轮唯一 token，terminal 只清除内容仍 exact-match 的本轮 in-flight body，不能擦掉其他故障的新 marker。必须先确认 Flash、计划任务和旧 test player 均已静止并核对迟到 marker/SWF/diagnostics。
若 `testloader_scratch_inflight.marker` 存在，先读取其中 `runner_path/backup_path/original_sha256/had_runner`，验证 backup SHA-256 并按哈希恢复或确认原本不存在，再删除 marker 与 recovery sidecar；不得只删闸或把残留 scratch 当原件。完成这些人工复核后才可显式删除 `compile_state_uncertain.marker` 并调大 timeout 重试。

**import 规则**：以 [AS2 防幻觉规范](as2-anti-hallucination.md) 为准：`import pkg.*` 已覆盖该包时禁止再叠加具体类 import，同包 class 不要求重复 import；跨包且没有 wildcard 覆盖时才用具体 import。asLoader 的 `Action.Skill` 是已登记的常驻 CS6 L42 特例：该包 wildcard 被整体排除，只允许组装器白名单中的具体 imports；不得扩成全项目通则。非 class TestLoader template 继续只用包通配或 FQN，禁止具体类 import。

**FLA 时间轴结构变更**：改 symbol/FLA 时间轴结构（如 `asLoader.xml` 帧数/层数增删、塌缩）后必须关闭并重开该 FLA，关闭时选「不保存」以免内存旧版 clobber 磁盘；否则 publish 仍可能产旧时间轴。externalization 后只改外置 `.as`（CDATA）时 publish 会从盘重读、无需 reopen；时间轴结构变更则必须 reopen。CWS 内直接 grep 类名/trace 串无效，应读 `logs/launcher.log` 的 boot trace。

<a id="domain-suites"></a>
## 领域 suite

各领域自己的 runner、工作目录、参数、现役阈值与固定覆盖点。阈值口径适用本文开头的「计数口径」：标注「机器钉死」的以 runner 脚本内 `ExpectedTracePatterns`/断言常量为准；其余文本计数保留义务并标待核。跨域共享的持久写合同见 [持久写与恢复](#save)，协议/生命周期合同见 [跨层协议与权威](#cross-layer)，编译与恢复见 [Flash 编译核心](#flash-core) / [focused runner 事务与恢复合同](#flash-recovery)。

<a id="suite-inventory"></a>
### 库存、背包与批量转移

**库存真批量转移门（现役规则）**：显式背包—战备箱/仓库批量必须发送一次 `autoTransferBatch`，不可回退为 N 次旧 `autoTransfer`；`Ctrl+单击` 仍固定单件旧路径。Host 请求须严格限制 1–50 个同源唯一 slot lease、合法容器对、exact 两窗口与 `mergeThenEmpty`，success 必须按 full/partial exact schema 重建，首项 `target_full` 为确定零写，`commit_failed` 与畸形 success 进入 reconcile。
AS2 必须证明目标只扫描一次、来源/目标各一次 revision 与 index rebuild、partial 只提交有序前缀、目标提交故障可精确恢复对象引用/数量/索引/revision，且 dirty/events/snapshot 只在完整提交后发布。确定性门是请求 `50→1`、窗口 snapshot `100→2`、每容器 revision/rebuild `50→1`；同进程 1/10/50 对照的墙钟只作观测。该旅程的写后重启读回未见覆盖记录，见 [持久写与恢复](#save)。
战备箱/仓库 UI 还须覆盖正文批量命令栏、普通点击批量暂存、重复点击取消、显式执行后复用 `autoTransfer` 严格单飞、`Ctrl+单击` 单件立即转移，以及最低画布 `0/1/5/50` 件的零溢出/零重叠；独立战备箱紧凑态固定 `6×7` 容纳 40 槽。

**tracked AS2 入口与机器钉死阈值**（`scripts/run-item-panel-tests.ps1`，`-Suite Shared|Crafting|Npc` 分域，缺省 `All` 全套；`-TimeoutSeconds 240`）：

- `EquipmentInventoryTest` 28/28（机器钉死）。
- `InventoryPanelServiceTest` 194/194（机器钉死；取代文本中 131/138/142/144/147/170 等旧计数，旧值见归档）。
- `CraftingPanelServiceTest` 158/158 + `SynthesisIndexTest` 18/18（机器钉死）。
- `NpcShopPanelServiceTest` 66/66（机器钉死）。

物品格协议施工须看到 `InventoryPanelServiceTest` 的现役机器钉值、合成/材料来源与用途施工须看到 `CraftingPanelServiceTest` + `SynthesisIndexTest` 的新鲜 Output Panel/trace 证据，不能只凭 publish marker。`-SkipCompile` 只证明静态合同。

**装备调制最终态门**：`powershell -ExecutionPolicy Bypass -File scripts/run-equipment-tuning-tests.ps1 -TimeoutSeconds 240` 现役计数为 Equipment Tuning **88/88** + Inventory **170/170**（机器钉死），覆盖已穿戴进阶/安装/替换/卸下/卸下全部配件后的有效等级门、exact 等级边界、preview→commit 等级竞态零写、背包高等级进阶继续允许、`replace_mod` 拆件后容量拒绝与 after 容量投影。
绿灯只证明 focused TestLoader + Inventory 行为与新鲜 Compiler/SWF 门，不代签真实游戏业务旅程、asLoader publish、runtime promotion 或 `standard_entry_verified`。

**装备调制 Web 体验门**：`node tools/run-equipment-tuning-harness.js` 必须在 `1024×576 / 1366×768 / 1920×1080` 各通过（文本阈值 147/147，待核：阈值来源为历史文本，未找到当前机器真源），覆盖 loadout 四入口同排、不可用进阶隐藏、缺料空态、不可用候选只写 Web status。`node tools/test-character-build-session.js` 必须覆盖 finalize 在状态切换前取消 pending candidates；
`node tools/run-character-build-workbench-harness.js` 必须通过生产控制器三视口、hidden-body、整备菜单（文本阈值 1110/1110 + 12/12 + 18/18，待核），覆盖 send-refused Web notice、迟到候选隔离与正常 finalize。该门只证明 source Web/会话/harness，不代签 Launcher candidate、真实 Flash socket、游戏内手工旅程、promotion 或 `standard_entry_verified`。

**已穿戴强化度交换、稀疏配件库存与候选调制切槽门**：配件测试数据必须同时包含持有数大于 0 与等于 0 的兼容候选，fresh open 断言 `modFilterPath=ownership/owned` 且只显示前者，玩家显式返回「持有」根后再断言全目录与数量 0 标识。
loadout convert 必须覆盖 exact loadout source + exact 背包 target、双 receipt 交换、第二侧失败全回滚、stale target 零写、Character authority 已观察后 `needs_reconcile`、Host 对 changed/no-op 快照数分支校验，以及 Web 确定成功/未知结果的 loadout + 背包对账和旧 target lease 清理。从背包候选进入调制后，选择另一件已穿戴且可调制装备必须在原 tuning session 内原子 rebind；
旧候选 owner 只在新 source 被 view 接受后撤销，busy 或 handler 拒绝时保持原对象与锁。

**运行态装备投影门**：11 槽 dirty 必须比较 `RuntimeEquipmentProjection` 保存的 applied canonical exact refs 与 `level/tier/mods` live 语义；HP/MP、Buff 内容、姿态、攻击模式、重量/速度/防御等刷新后验、手雷数量、`lastUpdate`、弹药/战技/形态均不得仅因打开构筑制造 live dirty。复合武器只允许 owner/version 绑定的 `reserveEmptySlotAlias → commitSlotAlias` 借用 canonical 空槽；
当前吉他喷火为长枪→刀、死者之手为刀→长枪，冲突、占用、过期或未提交 intent fail-closed，teardown 必须统一回收。真实换装/`level/tier/mods`/exact ref 变化仍进入一次 Dressup；外部已完成的完整 applied stamp 可避免重复刷新，但任何刷新异常或后验失败锁存 retry-required，不能采信半完成结果。

<a id="suite-crafting"></a>
### 合成、材料与采购

**合成持有量/标记/采购联动 current gate**（必跑）：

- `node tools/validate-crafting-recipes.js`
- `node tools/validate-panel-contracts.js`
- `node tools/test-panel-contracts.js`
- `node tools/test-crafting-runtime.js`
- `node tools/run-crafting-harness.js`
- `node tools/run-npcshop-harness.js`
- `node tools/run-kshop-harness.js`
- `launcher/tests/run_tests.ps1`
- `scripts/run-item-panel-tests.ps1 -Suite Crafting`

触及 AS2 生产逻辑后另以 `scripts/compile_test.ps1 -Target publish -VerifySwf scripts/asLoader.swf` 刷新注入层并跑 function-size 门。panel contract 的机器钉死口径为 7 domains / 42 commands（`tools/test-panel-contracts.js` 断言）；文本中 4/23、5/31 与变异 62/66/68/70 等计数为历史，见归档。

**固定业务规则**：配方采购直达必须另固定证明 Gold/K 路由零新增 `materials/materialDetail` 请求、装备前置物可路由、目标 NPC recipe-origin 精确定位；嵌套合成必须证明多个 producer 分别显示 28px 扳手入口、同分类零 snapshot 精确聚焦、跨分类 exact snapshot 验证后切换，且两条路径都不自动标记或合成。
配方采购 UI 还必须覆盖计划量 1→2→1、固定 10 列、48px 等高材料卡、数量 `持有/需要`、无装备「缺少装备」、仅强化不足显示 `+当前/+要求`、战备箱来源显示「合成前需要从战备箱取出」、装备栏来源显示「合成前需要卸下装备」，并由项目浮层明确说明这里只是合成前指引、不会自动移动装备；双 NPC + KShop 三个 28px 单层头像入口不得挤压正文、产生可见横向滚动或使用原生 `title`，且必须保持 exact `shopId`。来源投影必须验证 `totalOwned = usableOwned + equippedOwned + battleBoxOwned`，两处来源强化上限不得超过总上限。
可用 `?scenario=pg-crafting-procurement&visual=procurement` 只读打开稳定观感页，但截图不代签交互。mock-browser、focused Flash 和 isolated candidate 必须分层报告，均不代签 promotion 或标准入口。决策与 P1–P4 验收边界见 [合成工作台 P1–P4 ADR](../docs/合成工作台-持有量标记采购联动-P1-P4-ADR-2026-08-17.md)；P4 观感与真实操作固定按该 ADR §6 的约 5 分钟人工旅程验收，不再扩建一次性 runner。

**合成商品图离线人工验收**：改候选生成器、构图或路线策略先跑 `node tools/build-crafting-product-review.js --sample` + `node tools/test-crafting-product-review.js`；
test 会按当前配方、物品 XML、icon/dressup manifest、renderer/inspector/render harness/builder 重算 `sourceDigest` 并拒绝 stale `review-data.json`，进入人工批次前必须跑 `node tools/build-crafting-product-review.js` 全量重建。产物只写 `tmp/crafting-product-review/`，用 `node tools/open-crafting-product-review.js` 打开；
人类导出的 `crafting-product-review-decisions.json` 是素材/构图回归输入，不是生产 manifest。审查范围按现役目录的全部唯一产物（文本记录 2026-09-07 为 284 条配方、282 个唯一产物，待核）；双刀必须以两个真实 holder 呈现主/副刀，疾影必须呈现刀身/刀鞘；缺任一部件、渲染不是两个 holder 或误把普通 `dressup2` 当双刀都必须使契约失败。防具聚焦以实际装备 fields 定框：上装不补手、下装不补脚、手套不补前臂、鞋不补腿，仅头盔允许脸型承托；
512px 离屏合成后单次缩到 256px，`sqrt(alphaPixels)` 等效线性增益必须 `>1`，达到 `1.08×` 才推荐。`reviewRole=nonqualifying` 以及动画静态预览的 `static-first-frame + contractPass=false` 候选必须禁用最终单选，不得由人类误签为通过。决定文件与本地状态均绑定 digest：同 digest 只保留仍存在且可签收的 `candidateId`；跨 digest 仅迁移「需要调构图/缺少合适素材」问题标志与备注，绝不迁移候选通过决定。该工具只作离线作者/回归门；
生产检视器直接消费 dressup/icon manifest 并执行定案三路 fail-safe，任何素材、构图或 route 变化仍须先 sample/full 人工审，再跑 inspector 全量门与生产多视口 harness。

**材料入口固定覆盖**（共享 UI 合同）：`MATERIALS → openMaterialUI → crafting view=materials`、`materials/materialDetail`、`44:56` 双栏、默认紧凑 7 列/完整 2 列、密度对应的键盘列数、来源/用途投影、发送/挂载失败 fail-closed 且无旧页 fallback。「旧 material-only 页面不存在」只指旧条件入口链、提示与 fallback 不得存在，不要求删除 XFL 内已脱离入口链的普通材料帧。材料历史 closure（基建分档等）只约束其冻结列车，见归档。

<a id="suite-dialogue"></a>
### 现场对白与原生交互

**现场对白门**：运行 `node tools/test-server-callback-timeouts.js`，再顺序运行 `scripts/run-native-dialogue-tests.ps1`、`scripts/run-map-domain-tests.ps1`（机器钉死 MapDomainBridgeTest 60/60）、`scripts/run-map-loot-tests.ps1`（机器钉死 Loot 189 + Planner 12 + StageRunSession 594，见 [持久写与恢复](#save)），最后 `scripts/compile_test.ps1 -Target publish`。
覆盖握手/地图/面板毫秒期限、查询发送范围、同时超时托管、旧行数保护、新 rid 回退及 4096 行窗口的内容/暂停/事件移交。人力执行 [三组游戏旅程](../docs/对白v2审阅修复-人力验收单-2026-09-16.md)。Host/绘制改动继续跑 Launcher `NativeDialogue|NativeHudInputRoutingTests`、`tools/run-native-dialogue-webview2-smoke.ps1` 与 [SVG 工具](../tools/xfl-ui-svg/README.md) 只读 `--verify`，覆盖属性解析、富文本、时钟、作者窗口/按钮与缓存失效；
smoke 复用 exact SDK resolver。hidden WebView2/位图是 fixture，机器通过不代签实际游戏体验；历史发布与人验边界见 [专项交接](../docs/对话框迁移与高清立绘治理-调研与施工准备-2026-09-12.md#114-已有验证与准确边界)。

**原生交互（菜单/注释/鼠标兼容）**：focused AS2 runner、Launcher 定向测试和实际候选人验边界见 [专项 ADR](../docs/NPC菜单与原生注释迁移-ADR-2026-09-12.md#验证与人验边界)；源码测试与图片不能代签实际输入。runner 为 `scripts/run-native-interaction-tests.ps1`；
C# 定向 `NativeInteraction` / `Tooltip` 系列（含 `TooltipInspectionFeedbackTests`、`NativeTooltipPointerFeedbackTests`、`NativeTooltipPlacementContractTests`、`NativeHudTooltipFlickerTests`、`NativeTooltipPlainFeedbackTests`）；`node tools/test-tooltip-document-consumers.js`；
双端绘制见 [tooltip-parity](../launcher/perf/tooltip-parity/README.md)：保持相同物理窗口，覆盖 100% / 125% / 150% 显示缩放及长文案滚动反例；分帧语料见 `scripts/run-tooltip-corpus-audit.ps1 -IncludeContext`。角色构筑须验证真实新增 document 回包；血剑须验证结构化战技名与冷却。离屏/模拟 DPI 证据不代替实际窗口悬停与遮挡人验。

<a id="suite-stage"></a>
### 选关、启动前门与关卡会话

**Stage Select Panel 必跑**：

- `powershell -ExecutionPolicy Bypass -File launcher/build.ps1`
- `node tools/export-stage-select-manifest.js --summary`
- `node tools/audit-stage-select-layout.js --json`
- `node tools/audit-diplomacy-stage-select-links.js --json`
- `node tools/run-stage-select-harness.js --browser edge`

接 AS2 snapshot / enter 时追加 `launcher/tests/run_tests.ps1` 与 `scripts/compile_test.ps1`；坐标/视觉偏移时追加 `powershell -ExecutionPolicy Bypass -File tools/run-stage-select-visual-audit.ps1`（FFDec 导出 `DefineSprite 330` 裁出 1024×576 原帧，与无头 Edge 截到的 Web 舞台生成 `tmp/stage-select-visual-audit/sheets/*-compare.png` 与 `visual-audit-index.json` 对照）。需要抽查 hover 卡片时用 `node tools/capture-stage-select-web-frames.js --browser edge --fixture mixed --frame 基地门口 --hover-stage 新手练习场` 生成无头 Edge 单帧截图。

**manifest 与审计基线**：`export-stage-select-manifest.js --summary` 复核 XFL/XML → manifest 数量；`audit-stage-select-layout.js --json` 复核 labels / source entry instances / rendered / direct `entryKind=map/task` / decoration / nav buttons / `stageNames` 等计数基线（单一真值 `launcher/web/modules/stage-select/dev/stage-select-golden.js`；
文本记录 2026-08-16 为 166 / 14 / 2 / 28 / 164，待核：阈值来源为历史文本，以 golden 文件当前值为准）、背景与装饰资源存在、`previewMissing=0`、`previewSources` 四级链（external→internal→derived→default；
自 P4-b 起 `node tools/derive-stage-select-previews.js [--write]` 从关卡首个 Background SWF 经 FFDec 主视觉帧派生 derived 级，异常帧一律拒收保留 default）、`mapDirectLayoutMissing=[]`、`unmappedStageLikeInstances=[]`。
`audit-diplomacy-stage-select-links.js --json` 用 FFDec 全量扫描 `Type=外交地图` 的 `RootFadeTransitionFrame` SWF，并显式列出 StageInfo-only 外交地图（文本记录当前 `外交-黑铁阁`，源选关 XFL 无按钮、不按 Web 缺漏处理），确认旧 `关卡地图` 门被 AS2 公共 Web 选关陷阱覆盖、`地图-*` frameLabel 会反查回选关页签，且 return-frame bridge / return-frame isolation / 同场景 return filter 仍存在。

**harness 固定覆盖**：open/close、16 页切换、fixture、runtime 隐藏测试标题/fixture/dev 控件、runtime 地图空间占比、runtime frame menu 展开跳转同步、runtime `localFrame` 单次 `jump_frame` 同步、runtime return nav 使用入口 `returnFrameLabel` 发送 `return_frame` 并关闭、hover preview、真实 snapshot mock、live 关卡简介渲染、Flash HTML 标签清洗、锁定关卡不发 enter、已解锁关卡 enter 成功关闭、
外交地图绿色直达/委托任务直达入口 `entryKind` 且无二次难度按钮、外交地图入口（golden `mapStageButtonInstances`）的 `shape/外交地图点` 与文字内部矩阵运行时坐标、魔神法阵底图装饰层、challenge 只发地狱、背景矩阵、普通难度按钮锚点与 1024×576 / 1366×768 / 1920×1080 视口。
会话守卫覆盖：请求携带 `panelInstanceId`/`sessionGeneration`/`catalogVersion` 信封、异实例回包拒绝且合法重试仍可自愈、stateRevision 非单调快照不得覆盖更新状态、关闭重开后旧会话迟到回包丢弃、Host 同名 reopen 走 `onRebind` 换绑不重建 DOM、arena 重定向 closePanel:false 保持面板开启 + returnTo 重开会话轮换 + 链前回包丢弃。
C# 侧对应 `launcher/tests/Tasks/StageSelectTaskTests.cs`（exact instance 绑定/异实例与缺失拒绝/守卫键不进 Flash/回包代封回显与 revision 单调/换绑失效/精确关闭幂等/断线解绑）与 `launcher/tests/Guardian/StageSelectPanelChainTests.cs`（map→stage-select→arena returnTo 栈重开新实例与 initData 还原、栈不跨独立面板泄漏、关闭观察器清在途请求）。
控制器按四层拆分：`stage-select-panel.js` 为薄 facade（Panels.register + `_debug*`），实现位于 `launcher/web/modules/stage-select/`（core → view-model（纯数据层，无 DOM/document/window，P5 三维 renderer 插座）→ renderer → inspector → bridge 五模块，lazy 闭包同序）。
检查器行为：节点焦点环由自有键盘模态类 `.is-kb-focus` 驱动（WebView2 宿主嵌入焦点链会让鼠标点击命中 `:focus-visible`），选中/卡开节点不画蓝环，检查器内控件焦点环不变；当前双栏的 Enter/Space 在难度键上只选择，出战由独立按钮明确提交（取代历史 pinned 检查器直接提交语义）。

**锁定原因合同**：AS2 `StageSelectPanelService.buildLockReason` 生成 `stageDetails[].lockReason`（恒在、仅锁定时非空），C# 回包整体透传零改动；harness 断言 snapshot 下发的具体 `lockReason` 文案，旧快照缺 `lockReason` 字段时回退通用文案。检查器内 ←/→ 在同排难度按钮间循环移焦、焦点即选中高亮、↑/↓ 无操作、检查器开态下节点方向键截停并回引检查器、悬停他节点 hover 卡不受影响、Esc 归还焦点、Enter 提交当前焦点难度 payload 不变；挑战模式单键循环原地且 Enter 提交地狱；
锁定检查器无难度按钮、方向键不抢关闭钮焦点。合成鼠标全路径选中后无蓝环无残留卡、`.is-selected` 镜像卡锚点且乱序残留 `is-card-open` 也被 CSS 硬隐藏、回悬选中节点不再开卡；Esc 取消选中回基线、hover 卡恢复打开、键盘模态环让位给开卡。

**测试员反馈合同（2026-08-24 起现役）**：Stage Select browser QA 必须证明任务节点 hover 后红点/黄圈仍可见、局部卡片难度按钮一步可点且不强开 pinned inspector；AS2 静态审计必须证明仅 Web 来源且真实通关时，经来源场景 `SceneReady` 重开 Web，死亡/失败/撤退清来源但不重开，发送失败保留旧 Flash fallback。自动门为 Edge harness + layout/diplomacy audits + Flash smoke；
真实「进新手练习场→通关→fresh Web snapshot」仍需游戏内人工验收，browser/static/compile 不代签。

**废城固定镜头（三维试点）**：`python tools/import-stage-select-diorama.py --check` 核对资产闭包；`node tools/run-stage-select-harness.js --browser edge` 保留既有行为回归，运行入口改为仅监听 loopback 的临时同源 HTTP 服务以支持 ESM/GLB；`node tools/test-stage-select-diorama.js` 验证真实模型、固定画布、16 入口/名称命中、普通与外交 mouse→mock Host、锁定/投影键盘、静止出帧、30 次开关缓存、迟到加载与失败/上下文丢失重试。
截图和报告位于 `tmp/stage-select-diorama/`，不作为真实 WebView2/AS2 进关证据。聚焦双栏追加验证：`node tools/test-stage-select-focus.js` + `node tools/test-stage-select-navigation.js` + `node tools/test-stage-select-intel.js` 验证真实 GLB 建筑特写/高亮、取景预设、二维详情等价、未记录情报隐藏和难度选择零写；`python tools/derive-stage-select-intel.py --check` 检查静态情报派生。
当前施工范围见 [选关界面-webview迁移路线图](../docs/选关界面-webview迁移路线图.md#2026-09-09-废城固定镜头首版当前发布范围)。

**Stage Select 通关返回纠偏门（取代 2026-08-24 自动回流合同）**：`.is-task` 节点 hover/focus 时 marker 与 task-pulse 必须持续显示，hover 卡直接暴露难度按钮且不打开 pinned inspector；普通关卡成功结算必须按 `_root.关卡地图帧值` 返回并停留在 Flash，奖励有无都不得因本场由 Web 发起而自动重开 panel，玩家下一次显式进入选关时才读取 fresh snapshot。死亡、失败、撤退保持既有返回语义。
`audit-diplomacy-stage-select-links.js` 固定证明目的地驱动返回存在，并拦截 `_root.Web选关战斗回流`、`Web选关回流待打开`、`as2_stage_complete_return` 任一生产残留。自动门为 Edge harness + layout/diplomacy audits + Launcher tests + Flash publish smoke；真实「有奖励/无奖励通关后停留 Flash、再次显式进门才开 Web」仍需游戏内人工验收，browser/static/compile 不代签。

**Stage Select 进入/关闭传输合同**：进入回包须跨淡出保持 exact `callId`，关闭须先同步投递再销毁，transport false/throw 时保留面板、busy/pending 与重试权。

**主时间轴 82–125 启动前门迁移门**：Host 必跑 `launcher/tests/run_tests.ps1`，角色创建/槽位定向至少覆盖 `GameLaunchFlowCharacterCreateTests|ArchiveCommandHandlerRenameTests|SaveSlotCatalogTests|RebuildBackupStoreTests`；
timer 用例必须证明 title 与 scene 分相、草稿编辑无 deadline、durable-before-Ready、普通读档 entry 后 fail-closed、exact SceneReady/reset/error 后迟到 callback 无效。
Web 必跑 `node tools/run-bootstrap-character-create-harness.js --browser edge`、`node tools/run-bootstrap-harness.js --browser edge`、`node tools/run-hairdresser-harness.js --browser edge` 与 `node tools/test-agent-entry-contract.js`；
建角矩阵至少覆盖 1920×1080、1600×900、1366×768、1024×576、`uiFontScale=1.35/1.75/1.9`、DOM 全屏往返与 reduced-motion，并守住固定居中 `1024×576` 逻辑画布、全屏不重排/纸娃娃不拉伸、三步零页面滚屏、准备期完整遮罩/inert/零焦点、既有 PM19 V2 背景建角全程暂停调度且保留棋盘、不另叠加加载图形、snapshot + renderer 严格元数据 + canvas 至少 501 个非透明像素 + 双 rAF 才开放、显式失败/12 秒期限只降级展示且不触发 Flash/scene timeout、
cancel/reopen 迟到回调不揭页、显示名跟随/覆盖/恢复、标题右侧三步指示、角色名主标题、左侧唯一身高、隐藏但贯穿 exact wire 的脸型、三个装备槽 + 当前槽共享候选池、紧凑/完整密度持久化且零业务 RPC、完整卡片放大且名称/选中态不冲突、装备真实 icon alias/富注释/零 hover RPC、发型单槽 + 两种密度全量 77 项/完整模式候选池内部滚动/重复项与绝对 source index 保留/可辨识短名且 raw 名仅留 ARIA/注释、难度统一有界 `PanelTooltip` 与 Esc 先关注释、确认页难度/摘要双列且默认显示名不重复。
AS2 必跑 `scripts/run-character-creation-tests.ps1`（机器钉死 40/40）、`scripts/run-character-build-tests.ps1`，触及建角服务时 fresh publish `-Target publish`；触及主 XFL 时另 fresh publish `-Target main`，并跑 XFL audit / rename dry-run / fix-includes dry-run、linkage scanner 与 FFDec frame script 复核。
自动协议、布局、TestLoader 与 publish artifact 都不代签真实 WebView2→Flash 场景、显示观感、IME 手感、滑块/图标触感、长注释遮挡、普通读档、新建 durable 后重启读回、重建备份/旧 SOL 保护或重复显示名辨识。人类验收前状态只能到 exact isolated `candidate_built/candidate_executed`；验收通过前不得请求云端共识、promotion、部署或二进制推送。

**大学/车库选关返回**：地图/结算 runner 的 StageRunSessionTest 覆盖大学共享车库选关页、snapshot/子页保留根场景、同场景关闭与显式车库跳转（现役机器钉死总项见 [持久写与恢复](#save) 的 map-loot 段）。Web 使用既有 `node tools/run-stage-select-harness.js --viewport 1024x576`，专项可加 `--case runtime-college-return`。测试与编译最终结果只读 [问题登记](../docs/已知问题登记-2026-09-09.md)，未完成的正式入口旅程不由 fixture 代签。

<a id="suite-intelligence"></a>
### 情报面板

必跑：`powershell -ExecutionPolicy Bypass -File launcher/build.ps1` + `powershell -ExecutionPolicy Bypass -File launcher/tests/run_tests.ps1` + `node tools/validate-intelligence-h5.js --strict` + `node tools/run-intelligence-harness.js --browser edge`。
改 AS2 `intelligenceState/intelligenceTooltip` 或正式入口运行态联动时追加 Flash compile smoke；手测 Native HUD 与旧 Web notch 的主工具栏「情报」，以及 Native HUD「其他 → 测试 → 情报测试」。
情报溢出先跑 `node tools/test-information-overflow.js`（文本记录扫描 59 个情报配置，待核：阈值来源为历史文本，未找到当前机器真源），再由 `scripts/run-item-panel-tests.ps1 -TimeoutSeconds 240` 取得 Inventory/NPC/Crafting 的 fresh Output Panel/trace 与 Compiler Errors 0/0；静态脚本不能替代后者。Intelligence exact admission 合同见 [跨层协议与权威](#cross-layer) 的 B4–B6 段。

<a id="suite-settings"></a>
### 设置面板

**设置 Web Panel 门**：固定运行 `node tools/run-settings-panel-harness.js`、`node tools/run-settings-panel-visual-harness.js`、`node tools/run-kshop-harness.js`、两项 panel-contract 门、`launcher/tests/run_tests.ps1`、`scripts/run-settings-tests.ps1`（机器钉死 GameSettingsPanelServiceTest 47/47；
文本中 42/42 为历史）与 `scripts/run-player-manual-input-tests.ps1`；设置样式还必须跑 `node tools/audit-workbench-ui.js` 与 `node tools/check-workbench-css-bundle.js`。Settings AS2 focused 必须为当前钉值 + `Compiler 0/0 + 32K retry=0`，再精确 publish/verify `scripts/asLoader.swf`。
真机按 [设置面板人工验收单](../docs/设置-Web-Panel-人工体验验收-2026-08-21.md) 覆盖双入口、启动前 Launcher 壳视觉、真实 Flash 原分辨率静态预览与全屏缩放模拟、键位迁移/冲突/Esc/订阅跟随、试听与 cancel/close/断线恢复、性能、偏好重开/重启、首页及作弊帮助、尝试复活/返回基地和保存重启读回。自动门不代签物理 WebView2、真实 socket/存档或听感。

**双药剂组门（现役规则）**：当前 authority 固定为 `2 组 × 4 lane = 8` 个物理槽，`6` 只在上升沿切换，`7/8/9/0` 继续使用四条 `drug:0..3` 冷却，上下同列共享；`drug:switch` 独立冷却，切换不得重置 lane，成功切换同帧抑制用药并锁存四键到松开。存档保持 `3.0`，以 `ext.drugLoadout.version=2` 区分布局；无标记旧档只保留 `0..3` 并清除 ghost，v2 保留 `0..7`，future fail-closed，活动组不落盘。
Settings 必须是 36 行、`keySchemaVersion=2`，保留历史占用 `6` 的动作并为切换键选择无冲突 fallback；Character Build 顶层仍 v1，但严格携 `drugLayout.v=2` 与 8 行 `slot/bank/lane/active`，Web 两排四列且没有第九假槽。AS2 手动输入 runner 现役机器钉死：LongGun 486/486 + ManualCooldown 57/57 + DrugInput 58/58 + KeyManagerMigration 14/14（`scripts/run-player-manual-input-tests.ps1`；
文本中 474/474+50/50+28/28 与 486+57+55+14 为历史）。机器门不代签 `6 | 7 | 8 | 9 | 0` 观感、切换手感、旧档/重启读回或键位冲突迁移。下方文本若再出现 `4 槽`、`11+4`、17 路冷却及更旧计数只作历史。

Settings 写锁存/迟到 snapshot 的持久写合同见 [持久写与恢复](#save)。

新增或修改公开 Web 可写设置字段时，字段权威与白名单边界归 [运行时配置节](../launcher/README.md#运行时配置) 的用户偏好注册表：公开 Web 写入必须经 `config_set` 白名单，Host-only 字段不得因前端同名而获得写权限；注册表与面板注册的精确集合由文档巡检机器门核对，新增字段须同步登记。

<a id="suite-character-build"></a>
### 角色构筑与装备调制（Web/Host/AS2）

**focused 入口**：`powershell -ExecutionPolicy Bypass -File scripts/run-character-build-tests.ps1 -TimeoutSeconds 360`（视 runner 当前参数）。
tracked template 顺序执行 `SaveManagerTest`、`EquipmentInventoryTest`、`InventoryPanelServiceTest`、`CharacterBuildTransactionSpikeTest`、`CharacterBuildServiceTest` 与 `PlayerInfoProviderTest`（当前另含 `RuntimeEquipmentProjectionTest`，以 runner 脚本为准），守 SaveManager 的 dirty/成功标志/异常复位与 `sv:1→sv:2|sv:3`、
EquipmentInventory 的 11 槽白名单/原始 mutation revision/无事件事务、背包 lease/candidate projection、跨容器事务反例、角色构筑 session generation/state/live 签名/药剂 revision/finalize 反例，以及旧 `populatePlayerInfo` 的 40+ 字段面和现役 snapshot 的 **9 组 47 行 exact rows**、稳定顺序、极端/缺 hero fail-closed、legacy renderer parity 和称号受限 spans/恶意畸形标签降级。
六套汇总只要求动态的非零通过项与 `0 failed`（SaveManager 另要求 `passed/total` 相等）；该 runner 的 ExpectedTracePatterns 只钉非零通过，不钉具体数，文本中的合计计数均为各轮历史证据。`-SkipCompile` 仅验证 tracked suite/template/附加 AS2 源、UTF-8 BOM、精确 start/complete marker 与 scratch 恢复事务，不是 Flash 行为或编译通过证据。

**Web 领域必跑**：

- `node tools/test-character-build-session.js`
- `node tools/test-character-build-facet-counts.js`
- `node tools/test-character-build-projection.js`
- `node tools/test-character-build-candidate-tuning.js`
- `node tools/test-character-build-tuning-capability.js`
- `node tools/test-character-build-slot-transition.js`
- `node tools/test-character-build-candidate-tooltip.js`（候选及已装备/药剂 rich tooltip 与右栏布局）
- `node tools/test-dressup-stable-fit.js`
- `python tools/test-dressup-manifest-integrity.py`
- `python tools/test-merc-dressup-coverage.py`
- `node tools/test-equipment-tuning-runtime.js`
- `node tools/test-equipment-tuning-model.js`
- `node tools/test-inventory-runtime.js`
- `node tools/test-inventory-workbench-modules.js`
- `node tools/test-safe-exit-web.js`
- Equipment Tuning opener/preview/commit Gate 合同：`node tools/equipment-tuning/run-checks.js`（含 `PG-TUNE-PREVIEW` 与 `PG-TUNE-E2E` 纯离线正负例）。
- 共享生命周期/相机：`node tools/test-workbench-lifecycle.js`、`node tools/test-workbench-focus.js`、`node tools/test-workbench-focus-integration.js`、`node tools/test-workbench-components.js`、`node tools/test-workbench-inspection-viewport.js`。
- 视觉/组合：`node tools/check-workbench-css-bundle.js`、`node tools/audit-workbench-ui.js --strict-warnings`、`node tools/run-equipment-tuning-harness.js`、`node tools/run-character-build-harness.js`、`node tools/run-character-build-workbench-harness.js`、`node tools/run-character-build-dressup-harness.js`、
  `node tools/run-item-grid-visual-matrix.js`、`node tools/run-workbench-visual-atlas.js --strict-warnings`。

Host：`launcher/tests/run_tests.ps1`，并定向覆盖 strict `navigate_skills`、atomic consume、deferred-open、nonce/baseline、late trainer cleanup；
AS2：`scripts/run-character-build-tests.ps1` 与受影响的 tuning/manual-input/item-panel runner，Character→Skills 改动另跑 `scripts/run-skill-migration-tests.ps1 -TimeoutSeconds 240`，发布注入层时精确刷新 `scripts/asLoader.swf`。

**固定覆盖（行为与 UI 合同）**：`EQUIP_UI` 固定进入 Character Build；
`CF7_WEB_INVENTORY_WORKBENCH` 不再授权或触发回滚，任意环境值都不能改变 Web-only fail-closed、11+8 槽与四类 mutation、写后 revision/signature、可选 `candidateFacets` 的 legacy omission/strict malformed rejection、`scope=all` 与 revision fence、相关 `use` 候选口径、权威 `0`/unknown `—`、写后刷新及零额外业务请求、已穿戴/候选嵌入式调制、七类 tuning operation、exact visual-retire、
ordinary close/shutdown persistence fence 与 Guardian crash 遗留旧 Flash 不接管。
UI 必须覆盖：角色装备/调制/个人信息使用 DLS、普通物品筛选保持 inventory 中性；`55:45`、右栏最小 `360px`，左内层弹性纸娃娃 + 约 `204px` 贴右槽区，1024 下 Canvas 至少 `300px`、药剂两排四列（2 rowgroup / 2 row / 8 gridcell）、零横溢出；固定 11+8 槽使用真实图标、角标与完整 ARIA，颈部零 projection/缺图显式 fallback；左 PaneChrome 内联浏览摘要与放大入口，无重复计数、空预览标签和 routine 底栏；
右 PaneChrome 最多三项「装备 / 调制 / 卸下」（药剂为「装入」），无通用详情/pin、独立 action rail 或 1024 溢出。一个 density toggle/controller/preference 在 storage、构筑候选和 embedded tuning 间迁移，无已存偏好时初始紧凑，显式保存的 `full|compact` 优先；往返保持顺序、选择、预览、焦点且零业务流量。战备箱/仓库普通点击批量暂存并显式执行，`Ctrl+单击` 单件立即 `autoTransfer`，两者都走既有 lease/单飞/对账。

**相机与 Dressup 门**：相机必须从当前权威 snapshot（有候选时为覆盖后的当前合成 state）逐次重测 `空手/长枪/手枪/手枪2/双枪/兵器/手雷` 七种 pose 的结构骨架 envelope：`身体/脸型/发型/面具/屁股/左大腿/右大腿/小腿/脚` 参与取景，手臂、手与武器只绘制、不参与 scale；禁止按 `panelInstanceId + gender` 跨状态缓存。
Dressup 门必须固定 `auto_opposite_gender=0`，`opposite_gender_only` 保持 uncovered 并由当前性别 holder basic fallback，男女 `手雷站立` 各有且仅有一个 `手雷_装扮` holder；人工 alias 必须有显式 reason。放大前后 exact Canvas/renderer identity 不变，wheel/`+/-`/drag/arrows/full-view reset 只 transform Canvas，关闭复位、嵌入态不吞输入。
stats 固定 9 组 47 行、3×3、抗性 4×2/2×4、八 SVG `aria-hidden`、power `log10` / resistance linear；「调制说明」无 pin 且随 operation/focus 更新，modal/说明/tuning 逐层 Esc。

**容量与槽区合同**：容量只消费当前 `snapshot.equipment.modSlotCapacity + snapshot.equipment.mods`，仅接受 `0..64` 整数且 installed≤capacity，不设三槽业务上限，`0`=无插件槽、missing 不猜、malformed/超限=容量未知。真实剑圣腿甲固定 `1 个进阶 + 3 个插件`，可用容量态为 `1/3 + 2` 个空插件槽；4+ synthetic fixture 只证明调制 surface 不硬编码三槽。
顶部持久快捷总览与 operation 详细槽区按同一 capacity 全量显示，进阶/已装/空槽均可 Tab/点击进入对应操作但不提前 preview/commit；summary/operation focus key 必须按 surface 唯一，空槽不承诺精确物理槽号，批量卸下是 slot group 外、同 rail 最右且与卡片同高的方形按钮；owner-only 状态变化不得重建 snapshot 引用未变的 pane DOM；
inventory/loadout 物品格的 `modSlots[]` 是针对当前真实三插件 schema 的紧凑 presentation projection，并与独立进阶 marker 合成 `1+3` 可视槽，source-port glyph/ARIA 同步一致。

**候选与提交合同**：Character-origin Materials/Intelligence exact instance 才获 Host one-shot，展示 hint 不授权。Character 候选再次 click/Space 清预览且零写，明确非 repeat Enter、双击候选或拖候选到高亮兼容槽位才可提交（兼容范围仅当前已选槽位；背包范围按物品 `equipmentEligibility.slots` 白名单逐槽判定装备槽，药剂行按 `stack/药剂/quantity>0` 协议判别放开至全部药剂槽，逐槽冷却由 Host 写入时裁决）；
Tuning single quick 不越过 preview/token/lease/revision/write/reconcile，batch/cascade/remove-all 恰好一次人工确认；inventory 交换 preview target 仅接受 exact `{sourceKind:"inventory",containerId:"背包",slot,expectedLease}` 四键，intent 即时反馈只投影 `aria-busy` 与阶段，不乐观改写数量/snapshot/lease/token/槽位，不排队或重放 mutation。
commit 成功先采用 Host 验证的 `response.snapshot`，但 inventory external-write lock 保持到 fresh refresh；source ref 精确一致时省略第二次 tuning snapshot，否则 fresh read/retry/reconcile。

**候选路径 fixed 合同**：候选路径固定 exact active workbench instance、`sessionGeneration`、背包 `slot/expectedLease`、validated candidates allowlist 与严格 `context.kind="character_build_candidate"`；畸形/近似 context 不得回落 generic InventoryTask，blocked 行可检视但 forged/stale source 拒绝。
已装备/药剂路径固定为 loadout-domain read：exact `sessionGeneration + expectedLoadoutRevision + expectedDrugRevision`，`slotKey` / 零基 `drugSlot` 精确二选一；Host/AS2 拒绝多余键、错目标、空槽、旧 revision 与畸形 rich payload。AS2 必须复用 `InventoryPanelService.buildTooltipProjection()` / `TooltipComposer`，composer 返回后重检双 revision 与对象引用。
Web pointer/focus 共用 basic→rich；snapshot/新 candidates/写入/supersede/离开 `idle`/rebind/close 均使对应 owner/cache 失效、隐藏浮层并拒绝迟到复活，tooltip 零选择/装备/调制/对账 authority。布局另固定验证右栏只有「PaneChrome 标题 / 紧凑单行候选上下文 / 占满余高的候选网格」三行；范围控件、焦点摘要与候选操作组同一紧凑单行、按钮 non-shrink/nowrap，兼容/背包 scope 的 scroll viewport 等高，候选首行不得被说明区推到底部。
blocked 候选解释收敛为底部状态栏（aria-live）单一出口，瓦片仅露「不可装备」短标记，完整原因保留 aria-describedby 与悬浮说明，候选摘要行不再镜像原生 title tooltip。audit 口径：`--strict-warnings` 双树 `0 error / 0 warning` 为现役要求；文本曾记录的非严格 `0 error / 4 WB112 warnings` 已被取代（见归档）。

**候选直接调制（C3）**：固定覆盖 selected candidate 优先、无 candidate 才回落 loadout；exact inventory source，blocked/非装备/零强化/near-shape/同槽歧义 fail closed；写后只通过已挂载 Storage cache coordinator 收束且不得激活 Storage，再刷新 exact target/new lease/source/tooltip/current selection。
entry/session/panel/target/request generation fence 必须阻止迟到复活，unknown/stale 不 replay。返回先匹配同 physical slot + 新 lease，缺失时 next→previous，歧义/空集合聚焦当前槽候选标题；先恢复非零 scroll，再对越界目标做 PanelScale-aware nearest 修正，可见目标不得扰动滚动。1024 下「装备 / 调制候选 / 卸下」保持单行、完整 ARIA 与至少 44px 命中宽。C3 只复用现役 Host/AS2 inventory-source 闭环；
未改 `.as`、SWF 或 Flash target 时不要求 CS6/publish，也不能把自动门外推为 candidate、游戏 E2E 或部署。

**Skills 往返**：Character Build → Skills 必须 strict `reason:"navigate_skills"`、active/exact binding、arm-before-close、visual-retire、acknowledged detach 与 coordinator-settled 后原子消费；Host 生成一次性 `openRequestId`，AS2 只回显 `nativehud/manage`，nonce/source/view/baseline 全匹配才开。
最终 initData 不含 `trainerSession/canReturnTrainer`，不创建或恢复教师 session，只管理自身技能；pending/active manage 都不能被教师请求抢占，迟到教师须拒绝并 cleanup。stale/foreign/duplicate、close/retire/navigation/recovery 失败不得越过 Character fence，Host 禁止直调 `OpenPanel("skills")`。
反向 Skills → Character Build 固定覆盖 Character 来源 exact manage 才显示显式返回、与 trainer return 互斥、strict `navigate_character_build`、ordinary `×`/Esc/backdrop 不返回、visual-idle 与 Skill coordinator-settled 两门乱序恰好消费一次、write/reconcile/cleanup 非 idle 禁止返回、workbench exact tuple 与完整 baseline；
前向 admission/Host rejection 只允许一次 rollback 或一次 toast，旧 timeout 在 lifecycle epoch 或更新 intent 后必须静默失效。`PreparationNavigationV1` 默认 `true` 时 Native HUD 显示「游戏 / 整备 / 辅助 / 系统」四行，整备六项目标与 Character 菜单同源；显式 `false` 或非法配置必须成套恢复旧导航 presentation/header/focus，同时继续证明所有生产 UI 入口 Web-only fail-closed，绝不恢复已退役 AS2 全屏 UI。
Web 材料直达 `crafting view=materials` 且无旧页 fallback、SafeExit `sv:1/2/3`/one-shot 继续覆盖（见 [持久写与恢复](#save)）。browser case 以同一源码树完整输出为准。

**冻结树 UX 加固固定覆盖**：Character-origin Materials/Intelligence exact instance 才获 Host one-shot，展示 hint 不授权，Web exact 五键返回、Native HUD/普通 close 负例、child retire→fresh workbench nonce/new session 与 lifecycle cancellation；
`PendingInstanceBind` 不是可转让预约，forward child 尚未 exact 绑定时到来的 ordinary crafting/intelligence same-name open 必须在 admission/initData enrichment 前原子撤销它，丢失、取消或迟到的 forward 不能授权后来普通实例。Intelligence 只在 authoritative `state / bundle / snapshot / glossary_snapshot` 在途时阻断返回，tooltip 与后台 glossary catalog 不阻断，settle 后恢复。
B2 AS2 echo 顶层必须 exact 五键 `{task,panel,source,initData,openRequestId}`、`initData` exact `{profile:"battlebox",view:"tuning"}`；携 exact source 或 `tuning.open.*` requestId 的近似请求不得回落 ordinary open。层级筛选固定上层 title + breadcrumb、下层当前层级选项；
宽态下层选项不提前换行，真实窄态自然换行且零横向滚动，breadcrumb 只在自身不足时折叠中段并保留祖先返回与完整 accessible path，不回退 native select。

**LoadoutPicker scope/anchor 纠偏门**：触及共享 drop-policy、Character Build candidates 或佣兵换装时，必须同时证明「scope 只筛候选、anchor 只服务 compatible/CTA、候选权威白名单独立裁决 drop target、写后保留原 scope+anchor」。Character 装备候选在 compatible/backpack 都必须携并由 Host 验证 `equipmentEligibility`，合法药剂两种 scope 都可映射四药剂槽且目标冷却仍由 Host/AS2 写前复验；
Merc slot/backpack 都必须携 `eligibleSlots`。生产 browser 必跑 `node tools/run-character-build-workbench-harness.js` 与 `node tools/run-team-harness.js`，至少覆盖背包写后仍无 anchor、兼容槽 A→B 跨槽、取消零写、实际 exact 落点、写后 authority revision 刷新一次且连续写不 stale；
另跑 Character standalone、session/projection、`CharacterBuildTaskTests`、Launcher 全量、Merc/Character focused Flash 与 asLoader publish。

**纸娃娃稳定与调制源提示门**：装备写入、候选预览与错误反馈必须共用纸娃娃舞台内的 absolute feedback stack；任何提示出现/消失都不得成为 composite 第三行，也不得改变 doll stage 或 canvas 高度并触发重新 fit。角色构筑与独立装备调制的主装备图标必须经共享 `EquipmentTuningView` 复用既有权威富提示，两个入口只提供各自的 authority adapter：已装备来源绑定 session generation、slot、loadout revision 与 item identity，背包来源绑定 exact `背包` slot/lease；
rerender、authority revision/lease、epoch、busy/read/reconcile 或 scope dispose 必须释放旧 binding，刷新后只能以新 lease 重绑，禁止位置 key、入口分叉实现或旧 tooltip 复活。本增量不新增 AS2/C# 消息、保存格式或调制业务权威；自动门不代签真人观感、candidate、promotion 或 `standard_entry_verified`。

**Character effective instance qualification**：`scripts/run-character-build-tests.ps1 -TimeoutSeconds 240`；发布注入层时再精确 `scripts/compile_test.ps1 -Target publish`。runner 必须把普通 M4A1、三阶沙漠军装、墨冰/狱火 M4A1、普通牙狼与电脑芯片巨兽的真实 `BaseItem.getData()` 结果同时绑定生产物品/插件 XML 和 `data/equipment/equipment_config.xml` TierMapping；
candidate、facet 与 mutation 三处共用实例有效事实，禁止基础 catalog 或实例影子等级 fallback。通过须有唯一 fresh runId 首尾、六套零失败、Compiler `0/0`、32K retry `0`、fresh trace/output/errors、SWF 刷新与 function-size 健康门；静态门、旧 trace 或单独 `publish_done.marker` 均不能代签。

<a id="suite-skills"></a>
### 技能面板

必跑：

- `powershell -ExecutionPolicy Bypass -File scripts/run-skill-migration-tests.ps1 -TimeoutSeconds 240`（精确计数以 runner 为准，当前 `SkillLoadoutServiceTest 58/58`、`SkillPanelServiceTest 48/48`、Compiler Errors `0/0`；该入口不再包含 LongGun / ManualCooldown / DrugInput，三者改由玩家手动输入 runner 独立守门；Loadout 覆盖旧 HUD 图标壳重建、快捷槽空目标移动/占用目标交换/no-op/坏源拒绝；
  Panel 另覆盖 `skillPanelOpen` exact `openRequestId` 回显、缺失或畸形 `openRequestId` 均零发送；新 Host 缺 nonce 拒绝、`moveSlot` 路由、成功教师读续租与连续 120 秒空闲过期）。
- `node tools/test-skills-ui-modules.js`（文本现役 `65/65`，待核：阈值来源为历史文本，未找到当前机器真源）。
- `node tools/run-skills-harness.js`（文本现役 3 视口 `150/150`，待核）。
- `node tools/test-item-filter.js`（文本现役 `37/37`，待核）。
- `node tools/run-item-grid-visual-matrix.js`（文本现役 `20/20`，待核）。
- `node tools/run-kshop-harness.js`（文本现役 `153/153` 或更晚计数，待核；以 runner 当前输出为准）。
- `launcher/build.ps1`（candidate-only；凡改 `SkillTask` / Host 命令映射，必须启动脚本返回的精确 candidate，记录实际 Core 路径、build identity、payload closure 后再做领域 E2E；源码/xUnit/build exit 0 均不等于正式 Host 已部署）。
- `launcher/tests/run_tests.ps1`。
- `npm --prefix tools/cf7-save-repair test` 与 `npm --prefix tools/cf7-save-repair run typecheck`。

发布 `asLoader.swf`；实际触及 main / 物品技能 UI / 玩家信息 UI / things 时逐目标 `-PublishOnly -VerifySwf`，三件套 + linkage scanner，dirty XFL 不得强制丢弃内存改动。

skills harness 固定覆盖：`min(MaxLevel,currentLevel+floor(skillPoints/UpgradeSP))` 可负担上限、零费升级保留元数据上限、SP 不足一级时明确阻塞且零无效 preview、切换到不可升级技能会取消上一技能 debounce 并隔离迟到回包、AS2 HTML 白名单注释、无常驻详情栏、固定居中 `12×64px` Hotbar、`48px` 快捷槽图标与 `3px` 间距、技能库完整/紧凑不改变 Hotbar、正常等级与悬停/聚焦卸载动作避让、管理顶栏常显且独立分组的「快捷栏｜安全/快速」、切换零业务流量、帮助只说明规则且学习确认不可绕过、
完整卡与物品 owned grid 共节奏的 `48px`/`40px` 紧凑瓦片、trainer→manage→trainer exact rebind、形态/配置或学习/流派三组首击筛选、manage 两行紧凑承载、跨组组合/一键清除、武术/科技/超能力流派可见、默认收起搜索与 `/`/Esc、manage/trainer 指标分层、玩家文案、异常诊断复制且不泄漏 trainer session、L/R marker 视觉隐藏但 ARIA 保留、manage/trainer 情境帮助、模态最小画布边界与焦点恢复、技能→快捷槽装备拖拽、快捷槽→快捷槽单写移动/交换与 `Alt+←/→` 连续调整、
技能→技能格 reorder 交换、已装备目标拒绝、`Alt+↑/↓` 兜底且无常驻上移/下移、选择按稳定节点原位更新并保留技能库滚动与实体焦点、键盘重排后焦点实体保持可见、选择/调级自动预览、可点击中间刻度/拖动/精确输入的整数 range、方向键/Home/End 原生语义、拖动期零请求且松开只预览最终等级、等待时保留并标记上一份权威消耗、确认前过期 token 静默刷新、右侧说明/消耗/余额/门槛/主动作决策栏、无常态「计算消耗」按钮、教师能力过期留在可解释终态且不自动关闭。

Character 来源 exact manage 的自动门还必须覆盖：只显示「← 返回构筑」且与 `canReturnTrainer` 互斥；显式返回走 strict `navigate_character_build`，普通 `×`/Esc/native backdrop 只关闭回游戏；帮助/确认模态与展开搜索先消费 Esc；write/reconcile/cleanup 非 idle 时入口禁用；双 settled gate、workbench nonce/baseline、bounded rollback 与 lifecycle latest-intent-wins 均有对抗测试。
真机覆盖 manage/trainer、教师来源 manage 返回 trainer 与关闭清理、初学只准 1 级、12 槽/被动/reorder、快捷槽空目标移动/占用目标交换/连续键盘调整、坏档 fail-closed、active+candidate+return cleanup、断线/timeout/reconcile、重启回读、strict `openRequestId`，并确认 root `legacySkill*` / `openSkillPanel` 不存在、只保留 `quickSkillUnequip` 窄 HUD；
入口须 GUI 验证 Web 成功或可见 fail-closed，不再设置 legacy bridge / S6 观察退役门。

**workbench 返回屏障（双向收口合同）**：workbench `openRequestId` 只准入 exact `{panel=workbench,source=nativehud_equipment,profile=battlebox,view=build}`，baseline 同时覆盖 active panel/instance、queued command、reserved owner/instance 与 idle/processing fence，迟到 A 不消费 B。
navigation/热重载、socket disconnect、shutdown 必须作为先推进 generation/epoch 的 lifecycle cancellation barrier，latest intent 胜出，barrier 前后的迟到 callback 都不能创建 wait、重新排队或打开；competition/send-false/timeout 也撤销相应 one-shot/wait。新 Host + 旧 `asLoader.swf` 的 workbench 缺 nonce 必须 fail-closed，这条路径没有滚动兼容；
Host/SWF 必须由同一 immutable candidate 绑定同一 build identity/payload closure 完成实际执行与 E2E。前向失败至多一次 `skill_open_rollback` 且不循环，反向失败不复活 Skills；返回/回滚后稳定「技能配置」焦点。

<a id="suite-kshop-npc"></a>
### K 店与 NPC 物品商店

必跑：

- `node tools/validate-panel-contracts.js` + `node tools/test-panel-contracts.js`（机器钉死 strict panel contract v2、7 domains / 42 commands；production policy 必须通过 `panel-cross-layer-contracts`。
  覆盖 command capability / AS2 业务裁决 owner、nullable Flash handler binding、全局 action / response-handler 唯一、HandleWebRequest 内实际 command resolver 与 exact fail-closed domain guard、Host case 覆写/歧义 return、未登记 Host command、AS2 action→cmd/receiver/source 精确绑定、bracket/dot 静态 action/response-task assignment 与 handler alias、
  合法空白/Unicode 标识符/字符串伪证据、跨文件重复注册、空数值扩展面与双上限 interaction policy）。

- `node tools/validate-item-sets.js`（文本冻结 66 套 / 327 件，待核；中心表 ID/名称/排序唯一、成员引用闭包、零成员/单成员拒绝）。
- `node tools/validate-npc-shops.js`（文本冻结 35 NPC / 835 商品，待核）。
- `node tools/test-item-filter.js`（含 `branchTree` 保留套装 order）。
- `node tools/run-npcshop-harness.js`（文本现役 133/133 + `PG-MATERIAL-NAVIGATION` 23/23 + reduced SecondaryPage 2/2，待核）。
- `node tools/run-kshop-harness.js`（文本现役 153/153 或 155/155，待核，以 runner 当前输出为准）。
- `node tools/run-item-grid-visual-matrix.js`。
- `launcher/tests/run_tests.ps1`（C# 直接消费同一 `panel-contracts.v2.json` 的 NPC/Crafting/KShop 边界向量）。
- `powershell -ExecutionPolicy Bypass -File scripts/run-item-panel-tests.ps1 -TimeoutSeconds 240`（机器钉死阈值见 [库存、背包与批量转移](#suite-inventory)）。

NPC/KShop 共享固定覆盖：严格整数输入、完整 authority range、线性/对数边界、真实数量键盘步进、`A=purchaseLimit` / `E=maxPurchasable` 标记、草稿首个 Esc、本地拒绝零 preview、稳定行/滚动/焦点、无偏好初始紧凑与保存偏好优先；「大数可用→减一→+5 超出当前可提交上限→权威阻塞→可用恢复」的双上限状态机和 re-preview 在途控件可见锁/回包重开；
close→reopen 旧 epoch 回包隔离、读 timeout/畸形回包恢复 checkpoint、全部库存/数量权威分歧 fresh snapshot、commit 在途返回/数量/重复提交锁、畸形 commit reconcile/零重放，以及生产 `readPhysicalInventorySurface` 的首批 `背包 0/50 + 战备箱 0/100`、按 `A` 补页、exact 十键 response、完整 raw-window/merged receipt 在首次打开与成功提交后刷新均被实际消费。
KShop 另固定单击加购、拖拽可选、真实 SecondaryPage、共享数量控件、稳定结算行/焦点/滚动与紧凑偏好、结算 × 恒在页头最右端（§5.5 位置契约几何断言）；共享 Tooltip 另覆盖 dense 浮层零命中、1 秒检视、轨迹抢占与 owner wheel，以及商品显式激活后的 pinned 右栏、hover 不覆盖和关闭生命周期。二级页 × 恒在页头最右端（结算/帮助/整理三页几何断言）。KShop、材料与战备箱还须覆盖共享 `HelpAction` 的唯一入口、领域文案、modal inert/Esc 与 opener focus restore。

**数量上限合同**：Host 对 NPC 购买数量只做 `1..999999` 技术护栏；`purchaseLimit` 是普通数字/range/步进的合法 preview 输入硬上限，`maxPurchasable` 是当前可直接提交上限和「可用」目标/轨道标记。超过后必须返回一致的 `canCommit=false/blockingError`，保持数量/返回/可用可操作且绝不允许提交；re-preview 在途必须让数量控件可见禁用，禁止把点击静默吞掉；成功 preview 仍须通过 schema/身份/数量/scope/总额/容量/commit-state 一致性校验。
NPC 的 UI 仍只投影背包 50 格与战备箱前 40 格；取证 receipt 必须保留 `50+A` 全物理可访问面，A 仅允许 `0,40,…,240`，同阶段 owner/sessionNonce/metadata/epoch/version/facets 一致且合并后有序无缺口。场景 NPC 主入口变更才发布主 XFL；纯 AS2 服务改动发布 `-Target publish -VerifySwf scripts/asLoader.swf`。
真机覆盖 Pig 等单 use 多 subtype 目录、配置人工 section 的类别/套装/专柜切换、目录与背包 drilldown 返回、数字输入/range/可用混合买卖结算、帮助页/结算页无漏层、交易与断线对账；agent 克隆槽进档须等待本轮新鲜 `[BootstrapAS] event=handoff` 后再调用 `agentEnterResolvedSave()`。

**NPC snapshot 数量污染与诊断专项**：机械/协议门运行 `node tools/test-panel-runtime.js`、`node tools/test-npcshop-runtime.js`、`node tools/validate-panel-contracts.js` 与 `node tools/test-panel-contracts.js`；browser 必须完整运行 `node tools/run-npcshop-harness.js`，不能只用 material-navigation 子集代签。
Host 定向门使用用户态 SDK 执行 `dotnet test launcher/tests/Launcher.Tests.csproj -c Release --no-restore --filter "FullyQualifiedName~NpcShopTaskTests|FullyQualifiedName~AuthorityLogFormatterTests"`，至少证明合法非空材料/情报 snapshot 可采用、非法小数被拒绝且所有日志不泄漏名称/原值。
AS2 必须运行 `powershell -ExecutionPolicy Bypass -File scripts/run-item-panel-tests.ps1 -Suite Npc -TimeoutSeconds 240` 并取得 fresh `NpcShopPanelServiceTest` 现役钉值 + `Compiler 0/0 + 32K retry=0`；`-SkipCompile` 仍只属静态门。
发布逻辑注入层时另跑 `scripts/compile_test.ps1 -Target publish -VerifySwf scripts/asLoader.swf`，确认 fresh compiler output、SWF 刷新与 function-size 门。上述自动证据只覆盖污染夹具、协议相关性和隔离策略；测试机物理隔离且原存档已丢失时，不得宣称原事故唯一归因或真实存档 E2E（另见 [诊断与现场观测](#diagnostics)）。

<a id="suite-map"></a>
### 地图面板与地图内容工作台

**审计与 harness**：`node tools/audit-map-taskmarkers.js` + `node tools/audit-map-avatar-visibility.js`（同一 C# 只读内容检查）+ `node tools/audit-map-webp-assets.js` + `node tools/audit-map-layout.js` + `node tools/audit-map-scale-experience.js`；
C# 地图／作者／HUD 测试、`scripts/run-map-domain-tests.ps1`（机器钉死 60/60，含主动撤退、关注容量回收、自动接链与采样分批）、`scripts/run-settings-tests.ps1`；地图 Web `run-qa.js --browser=edge` 含 `map-return/map-return-stale-read`，Host `MapTaskResponseTests` 守当前实例与未知返回；
独立候选与人类入口见 [地图主动撤退](../docs/关卡结果与基地结算-CSharp-Web-ADR-2026-08-27.md#0c-2026-09-08-地图主动撤退入口)、`scripts/run-map-loot-tests.ps1`、`scripts/run-boot-sequencer-tests.ps1`，再单独发布 asLoader。独立彩蛋场景不创建公开热点，完成任务的受控交付例外由 `MapDomainSessionTests` 与 `tools/quest-return/verify-coverage.js` 覆盖。

**合并前 gate（缺一不得合并）**：改 `map-panel.js` / `map-canvas-stage-renderer.js` / `map-panel-data.js` / `panels.js` / `地图系统_WebView.as` 的 PR 必须在合并前跑通：1. `node tools/audit-map-taskmarkers.js`；2. `node tools/audit-map-scale-experience.js` 输出 `errors=0` 且明示 capability debt；
3. `node tools/run-map-harness-headless.js --browser edge` 全绿（`map-ui1`~`map-ui34`，其中 `map-ui21` 覆盖全 18 filter profile，`map-ui34` 覆盖 camera 稳定性）；4. `node tools/audit-map-layout.js` 无几何漂移。

**生产地图 headless harness 与 Tasks／Stage Select 回归**；作者 UI 用独立副本执行 `test-ui-v2.js / test-ui-mutations.js / test-ui-npc.js`，禁止写入当前地图作测试。实际 WebView2 smoke 禁用 GPU，只检查加载／隔离，不自动游玩。旧导出器不再写 JS／图片，素材从工作台候选导入／裁切／发布 linkage 提取。C# 基于已验证像素尺寸生成当前 capability；取景配置改动后运行 `node tools/tune-map-filter-fit.js --write`。
NativeHud 资源／缓存变化追加 `BitmapLruCacheTests` 与 Launcher 全量。当前 source、候选与三条独立人类旅程见 [地图工作台](../tools/map-workbench/README.md)，机器通过不代签真实 NPC 互动或正式入口。

**地图内容工作台帮助与上游兼容**：在 `new-test-fixture.ps1` 的独立副本上运行 `test-help.js`，验证十主题搜索／上下文帮助、共享二级页 Tab／Esc／返回／面板关闭、草稿与画布保留、A／B 独立编辑、三视口、加载失败／迟到响应，以及空草稿接纳新基线、非空草稿与未完成写入保留、重开先核对原保存、目录失败不覆盖草稿；详见 [工作台入口](../tools/map-workbench/README.md)。`node tools/map-workbench/test-upstream-compat.js` 运行真实 NPC 初始化源码前缀的九项逻辑路径，不代签 AVM1；
AS2 合并仍需地图桥／启动／相关上游专项的新鲜 CS6 trace 与 asLoader publish、函数尺寸门。保存后关闭另跑 `test-ui-mutations.js` 的面板／文档重建、原操作查询和迟到响应隔离；地图回包身份由 CS6 地图桥（机器钉死 60/60）与 C# `MapTaskResponseTests` 联合守护。`test-view-modes.js` 守创作／玩家视图：初期隐藏内容可编辑、同一 C# 快照与导航门不变、整页隐藏原因、单击与拖动区分、切页迟到重绘隔离、A/B／相机／草稿保留、未知头像占位和三视口分层滚动可达；仅独立副本、无 apply。

**校准与复核入口**：manifest 校准入口 `launcher/web/modules/map/dev/preview.html`；可视化构建入口 `launcher/web/modules/map/dev/builder.html`；地图布局全量复核入口 `node tools/audit-map-layout.js [--page school] [--json]`；filter-fit preset 离线重算入口 `node tools/tune-map-filter-fit.js --write`。
`preview` 负责看运行时同构的 Canvas assembled stage（`sceneVisuals` + backdrop/theme + filter/anomaly overlay）、布局、过滤、`buttonRect`、动态头像槽位、locked groups 条件、flash hint、XFL source rect、draft 校准与 override 导出；`builder` 在此基础上开启热点 / 过滤按钮拖拽缩放、bundle 粘贴导入和草稿持久化；两者都不替代 browser harness 的交互 gate。
需要给人眼或外部视觉模型看图时，用 `python tools/render-map-audit-sheet.py --page base --page faction --page defense --page school` 生成热点/头像审计图，再按需调用 `powershell -ExecutionPolicy Bypass -File tools/kimi-map-review.ps1 ...` 做视觉复核。
缩放体验矩阵入口 `node tools/audit-map-scale-experience.js` 固定覆盖 18 filter × 3 viewport × 3 DPR × 2 effects，并将无法满足 profile 的低清素材单列为 capability debt；文本记录当时只允许 `defense:all`、`defense:first_line`、`faction:fallen` 三项无冻结真源债务，出现其他债务即失败（待核：债务清单以审计当前输出为准）。

**地图资源箱 / 全正网格 Web-only loot**：`tools/test-audit-stage-chests.ps1` + `tools/test-map-loot-wiring.ps1` + `scripts/run-map-loot-tests.ps1 -TimeoutSeconds 300` + Launcher/Web loot、共享 workbench 与普通 Lockbox QA；
发布 AS2 另跑 `scripts/compile_test.ps1 -Target publish -TimeoutSeconds 300 -VerifySwf scripts/asLoader.swf`，改地图元件 XFL 时直接发布 `flashswf/arts/new/素材库-地图元件/素材库-地图元件.xfl` 并验证对应 SWF。静态全量检查：六箱领域内所有正整数 `row/col` 是 Web intent，支持 `1×1`、`col<=8`、`capacity<=64`；非箱正网格不被 loot 劫持，超界/畸形箱体 fail-closed；
只有精确 `0×0` direct 与无 reservation 的 break 地面掉落，负数/单边零/混合尺寸必须 fail-closed；数量仅在 min/max 同时缺省时默认 `1/1`，单边缺省或显式坏值必须拒绝；production marker=0、S0 生产引用=0、Flash renderer/claim-only fallback 不可达。`test-map-loot-wiring` 解析真实 XFL Include closure，守六个 canonical linkage/统一开启回调，并要求五类可破碎箱在「破碎」标签帧调用统一破碎脚本。
运行时 failure 保留同一 inventory/anchor：`SUSPENDED`，空→`CONSUMED`，anchor 失效→`EXPIRED`，未收束 journal/effects 保持 `COMMIT_PENDING`；保留 journal、幂等、pause、proof、unknown-only-query、same-instance organizer 与 teardown barrier（recovery ledger 合同见 [持久写与恢复](#save)）。人工只做正常标题帧/NativeHud、装备箱领空、生存箱满包 organizer、保险箱单击 suspend/reopen，以及装备/生存破碎；
direct 有现成夹具时顺带目视，存盘/重启回读与数值对账尽量自动化并合并 standard-entry，不造 9 站。

<a id="suite-arena"></a>
### 竞技场面板

必跑：

- `node tools/test-arena-portrait-coverage.js`
- `node tools/test-arena-meta-portraits.js`
- `node tools/audit-arena-portrait-coverage.js --check`
- `node tools/derive-arena-meta-teams.js --check`
- `node tools/derive-arena-factions.js --check`
- `node tools/derive-arena-unit-catalog.js --check`
- `node tools/derive-arena-unit-param-presets.js --check`
- `node tools/derive-arena-custom-presets.js --check`
- `node tools/run-arena-harness.js --browser edge --case custom-match-p1`（覆盖入口卡瘦身、三层编辑页、全量单位浏览、u235 远古诛神 112px 首帧 ready、势力折叠分组、滚动追加、分类展开/收起与点击添加均保留单位目录滚动位置、搜索命首批次外单位、敌对/非敌对过滤、非敌对标签、占位图标、待标定预设池、关卡参数预设搜索、参数深层编辑页、JSON/XML 参数互转、参数赛程码、战场参数子页预设/滑条、阵型图例、单侧随机、本地保存/读取、红蓝交换、手动 roster 编辑）。
- `node tools/run-arena-harness.js --browser edge --case custom-match-p2`（覆盖确认页、`custom_start`、战场参数默认值进入 `calibrationCase`、关闭 Web panel、`custom_result` 回开、独立结算页与确认返回基地，含 `panel_esc`/backdrop 共用的无参 close 入口）。
- `node tools/run-arena-harness.js --browser edge --case custom-match-pve`（覆盖 `玩家 vs 怪物` 走标准 `enter`、`custom_pve`、当前玩家、怪物 roster、Web 不携经济字段且 Host 固定重建 0 押金/奖金、不走 `custom_start`）。
- `node tools/run-arena-harness.js --browser edge --case custom-secondary-page`（参数深层编辑页由共享 SecondaryPage 承载——inert/aria-hidden 分层、焦点移入 initialFocus、Tab 环页内 trap、DOM keydown 与宿主 panel_esc 双通道 Esc 逐层、opener 焦点归还、确认条共享 CommitBar 的 ready/busy 投影、结算页焦点栈层激活）。
- `node tools/run-arena-harness.js --browser edge --case calibrated-roster-authority`（标定组合保序展示、参数透传、零 AS2 随机 preview，commit 只发送 session-scoped `calibratedRosterId` 且不夹带 roster）。
- `node tools/run-arena-harness.js --browser edge --viewports=1024x576,1366x768,1920x1080`（三视口门禁：runner 默认视口已对齐逻辑画布 1024×576，日常 `--case` 调用不再写死 `--viewport`；`--viewports` 同进程逐视口独立 launch 跑全量用例并分列汇总，任一视口失败整体非零退出；与 `--viewport` 同给时 `--viewports` 优先）。
- `node --check` 语法门（精确文件清单，模块目录增删文件时同步本清单）：`node --check launcher/web/modules/arena-panel.js launcher/web/modules/arena/arena-core.js launcher/web/modules/arena/arena-shell.js launcher/web/modules/arena/arena-challenge-browser.js launcher/web/modules/arena/arena-preview-authority.js launcher/web/modules/arena/arena-custom-editor.js launcher/web/modules/arena/arena-result.js launcher/web/modules/arena-custom-parameters.js launcher/web/modules/arena-custom-undo.js launcher/web/modules/arena-custom-polling.js launcher/web/modules/arena-custom-param-editor.js launcher/web/modules/arena-custom-result-view.js launcher/web/modules/arena-custom-match-code.js launcher/web/modules/arena-custom-presets.js launcher/web/modules/arena-unit-catalog.js launcher/web/modules/arena-unit-param-presets.js launcher/web/modules/arena/dev/qa-suite.js tools/derive-arena-meta-teams.js tools/derive-arena-factions.js tools/derive-arena-unit-catalog.js tools/derive-arena-unit-param-presets.js tools/derive-arena-custom-presets.js`

视改动追加：触及标准竞技场卡片行为时追加 `--case panel-open`、`--case grid-batch-preview`、`--case calibrated-roster-authority`、`--case keyboard-commit`、`--case reroll-all`、`--case hidden-mixed-enter`、`--case standard-mixed-card`、`--case no-merc-meta-dressup`、`--case no-merc-synthetic-dressup`；
改 C# `ArenaTask` / `ArenaAuthorityCatalog` / `ArenaCalibrationTask` 时先跑 authority focused tests，再跑 `launcher/tests/run_tests.ps1`；改 AS2 `arenaSnapshot/arenaEnter` 或经济公式时运行 `scripts/run-arena-authority-tests.ps1 -TimeoutSeconds 240`（机器钉死 13/13）取得 fresh trace/output/compiler/32K 证据，发布时再精确 publish asLoader。
真实验收先跑 `node tools/workbench-live-e2e/arena-live-e2e.self-test.js`，再运行 `node tools/workbench-live-e2e/arena-live-e2e.js --candidate-root <candidate> --allow-read-only-live-seed`：必须从真实 WebView2 以 `isTrusted=true` 的 candidate-page 输入选择/确认，Web payload 无经济字段，Host 注入与 AS2 接受值一致，关闭重开后旧 session cardId 在到达 Flash 前被拒绝；
标准页 DOM 允许同时呈现 10 张 `mode=standard` 卡与 2 张隐藏挑战卡，实跑器只以 10 张标准卡的顺序/身份对齐标准权威子集，不能把合法隐藏卡误判为超额；该输入不冒充物理鼠标，报告固定 `physicalInputAttestation=false`。Arena P5 权威真机门的完整合同见 [持久写与恢复](#save) 的受控进档段。

<a id="suite-warlord"></a>
### 军阀（战棋）

当前状态、候选与人类范围只维护于 [基础闭环施工交接](../docs/军阀-基础闭环施工交接-2026-09-05.md)；本页与归档中的 r8–r14 数量和候选指令保留为历史。

**现役门（Slice 6.1 r11 起）**：改变参战控制权时，Host `ControlWireMatrix_ActualParticipantsOwnControl` 可通过 `CF7_WARLORD_WIRE_FIXTURE_DIR` 导出实际 transport 命令；同轮 `scripts/run-warlord-action-encounter-tests.ps1 -HostWireFixtureDirectory <导出目录>` 必须让 Flash LiteJSON 直接解析该输出并通过 AS2 validator，不以两端独立手写样本替代跨栈验证。
runner 现役机器钉死：`ActionEncounterRunnerTest Tests Passed: 97` + `Cases Passed: 4/4`（`-HostWireFixtureDirectory` 模式另钉 `Host Wire Passed: 16/16`）；文本中 63/63（3 cases）为历史。玩家 loader 后过早把 `_root.控制目标` 改成镜头会令延迟初始化永久按 AI 分流且跳过纸娃娃装备；
r11 合同为初始化全程保持 exact 玩家名，用全自动与 actor hold 冻结，待 `操控编号 == 0`、`hasDressup === true`、公开 `RuntimeEquipmentProjection` 状态 aligned 后才放权，不改正常游戏路径、不造伪 `SceneReady`。真人门验证主角/普通兵装备外观、键盘控制、无 `[AI] fs`、结算/返回，以及本阵营 `END_ACTION` 直接占点、下一阵营行动前按快照批量包围占领；通过前不得称 `e2e_verified` 或 `HUMAN_ACCEPTANCE_PASSED`。
当前主板故障机器禁用 Computer Use、自动真实游玩及 GPU 压测，纯逻辑测试与编译串行，真人短时自然游玩不承担日志／receipt 管线。

<a id="suite-tasks"></a>
### 任务、成就与调度板

**Task Panel 必跑**：

- `python tools/bake-npc-profiles.py --check` 核对小头像来源、重建字节与 NPC 缺图，见 [共享头像工具](../tools/npc-profiles/README.md)。
- `node tools/run-tasks-harness.js --qa`。
- 2026-09-11 返回专项含 119 项 Flash 回归（结算后走门、清场前拒绝、真实世界身份与延迟重试），见 [quest-return 测试矩阵](../tools/quest-return/README.md)。
- `node tools/audit-web-item-icon-closure.js`（task-ui1~50 + ach-ui1~13，Edge headless：筛选/列表/排序/详情缓存/富物品 tooltip/空态 + 写操作交付·放弃·确认弹窗·背包满·ESC modal 栈·远程交付门控（含绕过按钮直发 finishTask→requires_npc 服务端门控自断言）·删除在途锁·前往交付·finishNavigable 不缓存固化（注册表迟到→重选复查）+ 事件日志（任务树渲染·对话按钮可见性·回放富立绘组件（不关面板）
  ·对话 AS2 htmlText(FONT/B) 经 convertAS2Html 渲染·tab 往返·图表视图（六边形+前置连线渲染/点节点选中+明细/25% 缩放/章节折叠/左键拖拽平移+点击拖拽判定/任务线配色按链区分/对话回放进度门控/重开重置工具栏）·对话回放真白名单清洗恶意标签·图表防剧透（未接取节点不进图+详情遮罩）·服务端对话门控（绕过直发 finish→locked）·共享判定条件进度行渲染（conditions {label,cur,target}+done 态）·条件进度不缓存固化（运行态字段重选后台复查→进度行就地刷新）·satisfied 权威纠偏（条件达成翻转完成态→徽章/交付按钮/列表角标同步）
  ·副本对话完整立绘/缩略模式切换·副本委托简报按行顺序渲染·调度板独立聚合/详情/出击/复盘·减少动态效果下背景水印/呼吸光晕/物品托盘伪元素停转·纯缓存契约仅限无 conditions/无导航复查任务）自断言；
  图标审计覆盖任务/成就奖励与情报物品最终 `icon` → `launcher/web/icons/manifest.json` 闭包）。

**视改动追加**：改 AS2 `taskSnapshot/taskDetail/tasksTooltip/taskFinish/taskDelete/taskNavigateFinish/taskTreeState/taskReplayDialogue/achievementState/achievementClaim` 或 C# `TaskTask`/`WebOverlayForm` 路由时追加 `launcher/tests/run_tests.ps1`（xUnit `TaskTaskTests`，
含字符串/缺失 backend callId 丢弃回归 `HandleFlashResponse_StringBackendCallId_DroppedAndLogged` + `PanelBridgeTests`；
Web→Flash 透传信封收口到共用 `PanelBridge.BuildFlashCommand`，含 `action`/`task` 保留键守卫——全部桥共用、保留键集单一处，新桥调它即继承，杜绝逐桥漏抄）+ `scripts/compile_test.ps1` + `powershell -ExecutionPolicy Bypass -File scripts/run-task-panel-tests.ps1`（TaskPanelService wire 契约机器钉死 15/15：taskDetail/taskNavigateFinish 跨异步、乱序、
失败与同步拒绝回包的 callId 必须保持数字型并断言原始 wire 为 `"callId":71` 而非 `"callId":"71"`，锚定 2026-09-07 e131182909 回归）。

**派生门**：改任务数据展示字段（title/description/chain/itemReqs·rewards.icon）须重跑 `node tools/derive-task-catalog.js`（build Step 1e；含闭包校验器，缺 `$KEY` exit 1；奖励/需求图标从 `data/items` XML 派生）刷新 `task-catalog.json`；
任务 `conditions` 字段同走 Step 1e 校验（类型枚举/label 必填/sinceAccept 单调限定/economyCount 白名单单源/布尔型 taskFinished·itemOwned 的 target 必须=1/itemOwned count≥1/chainProgress 有序号链存在+target≤链最大 seq/条件死锁=单调 AND-OR 不动点，对齐运行时语义：taskAvailable 只查 get_requirements、链序号不约束完成顺序；
chainProgress 按「任一 seq≥target 候选可完成」析取处理，基线可完成集 vs 带条件集之差=条件死锁，统一覆盖自链·seq 缺口·跨链/taskFinished 互锁·get_req 介导环·级联，且不误报同链独立乱序任务）；build Step 1e 固定运行 `node tools/test-derive-task-conditions.js`（23 用例正反矩阵，合成夹具走 `--task-dir` 不碰真实数据；正式数据 conditions=0 时常规派生不执行这些分支，矩阵负责持续守门）。
新增 objective 类型三处联动：`ObjectiveEvaluator.as` 分发 + `tools/lib/objective-types.js` 枚举 +（成就启用时）achievement derive params case。改成就数据（`data/achievement/*.json`）或 `AchievementMetrics.as` 白名单须重跑 `node tools/derive-achievement-catalog.js --check` + 真跑（build Step 1f；
含 objective 枚举/跨域闭包/economyCount 白名单单源/hidden 脱敏校验/rewards.icon 从 `data/items` XML 派生）刷新 `achievement-catalog.json`。

**业务规则**：成就 tab=tasks 面板第三 tab（`achievement-tab.js`，claim 走 `achievementClaim` 全称命令防 ShopTask 截胡，背包满回 `inventory_full` 保持可重试）；
写操作传 taskId（非 index，splice 后偏移）、交付走服务端 `taskCompleteCheck` 硬门控、远程交付仅 `finish_remote` 任务开放（否则回 `requires_npc`）、前往交付复用地图 `MapPanelService.navigateToHotspot`（不可达回 `not_navigable`）、事件日志静态目录走 build 派生 web 直读·进度叠加走 `treeState`·对话回放 `replayDialogue` 按需回传单任务对话文本行 + 立绘字段，web 内联组件渲染（不关面板）；
视觉/动效复核 `node tools/run-tasks-harness.js --shot=<png> --query="view=list&filter=副本&detail=6"`（日志 tab 用 `--query="tab=log"`）；正式 runtime 富 tooltip/筛选/动效/交付发奖扣物/放弃移除/前往跳转/事件日志树·对话回放需游戏内端到端手测；
**远程交付（`finish_remote`）成功后面板必须关闭**——AS2 `FinishTask` 会 `SetDialogue` 完成对话+弹奖励提示界面+可能自动接取下一任务再弹接取对话，这些原版 UI 在游戏层、被独占 web 覆盖层挡住，故成功路径关面板露出（手测确认奖励/对话可见且无残留）。

**Task Dispatch Board**：`node tools/run-tasks-harness.js --qa`（task-ui46~49）+ `node tools/run-tasks-harness.js --shot=<png> --query="board=1" --viewport=1280x720` + `launcher/tests/run_tests.ps1` + `scripts/compile_test.ps1`。覆盖调度板独立标题/聚合列表、独立 `mission_briefing` 防剧透、进入关卡成功关闭 panel、已结案任务转复盘且奖励语义不重复；
改 `dispatchBoardSnapshot/detail/briefing/enter`、`dispatch_board` / `dispatch_replayable` 或基建入口时必须复跑。Web mock 不替代游戏内手测：正式验收仍需确认建成基建后能打开、未接取任务不能绕过进入、首次完成能回写任务需求、复盘不会重复接取或发任务奖励。

<a id="suite-team"></a>
### 战队、战宠与佣兵装备

必跑：`powershell -ExecutionPolicy Bypass -File tools/audit-pet-roster-types.ps1` + `node tools/run-team-harness.js` + `launcher/build.ps1` + `launcher/tests/run_tests.ps1`。
T800 托管长枪追加 `powershell -ExecutionPolicy Bypass -File scripts/run-managed-longgun-tests.ps1 -TimeoutSeconds 240`（机器钉死 ManagedLongGun 126/126）+ `scripts/compile_test.ps1 -Target publish` + 独立发布 `flashswf/arts/things1/things1.xfl`；仅当实际改动 legacy 删除兼容脚本时再发布 `flashswf/UI/战宠相关界面/战宠相关界面.xfl`；
佣兵装备托管追加 `powershell -ExecutionPolicy Bypass -File scripts/run-merc-loadout-tests.ps1 -TimeoutSeconds 360`（机器钉死 113/113，固定含 scope=backpack / eligibleSlots 跨槽白名单用例）。

**run-team-harness 覆盖**（文本阈值 218/218 或 222/222×3，待核：阈值来源为历史文本，未找到当前机器真源）：佣兵卡片纸娃娃快照与培养页 canvas 非空；改佣兵纸娃娃时补看头像只绘制 `脸型/发型/面具`、培养页造型预览与性格左右分栏、manifest `appearance.faceById/hairById` 原始编号归一化；游戏内手测 Native/Web fallback 的唯一战队入口、四标签、领养/雇佣/出战/关闭重开；改 `MercPanelService` face/hair 或 merc snapshot 字段时追加 Flash smoke。
统一战队 Web 面板是现役标准入口，旧 `战宠相关界面.swf` 只属兼容面。Team 三视口还须覆盖托管长枪右栏、「兼容 / 背包」筛选、锁定原因、12 秒超时解锁回拉、交付/取回、候选独立滚动与完整/紧凑密度；名册卡片不得因武器行改变排版，当前武器只在右侧详情显示，详情/培养当前武器/候选格都必须使用项目 `PanelTooltip` 完整属性注释且零原生 `title`。Host 回归必须证明两个写命令及 `weapon_tooltip` 同时进入总允许表与 `PetTask`，候选注释保留 exact lease-bound source。
真实 `pets.xml` 回归必须锁定关键宠物既有定义又能经类型化领养目录默认分类投影。另跑 Launcher 全量、XFL 三件套与 linkage scan；自动门不代签真实存档重启、AI 命中效率、特殊枪时间轴或数值平衡，须按专题施工记录完成人工游戏内验收。

**T800 focused TestLoader 固定验证**：`ManagedLongGunServiceTest`（机器钉死 126/126）policy/冻结/lease 事务/候选与当前武器 canonical 富注释/损坏及错误品类记录 fail-closed/普通与战宠分流/缺失换装生命周期桥/预设武器权威图标投影/非主角弹匣哨兵/M134 成功发射到可见帧前进与副武器隔离，并联跑 `DressupReferenceManagerTest`（文本 70 条，待核）活动 `man` 接管及同分支冲突隔离；要求 fresh trace/output/errors、Compiler 0/0、32K retry=0。
佣兵装备托管：`MercLoadoutServiceTest` focused 套件固定 10 槽 policy/冻结克隆/lease 与 loadoutRevision 事务/交付-替换-取回故障矩阵/损坏托管 fail-closed/解雇守卫/出战生成注入；Team 三视口覆盖装备调配三态、手雷槽只读、候选筛选与锁定原因、交付/替换/取回、超时解锁回拉、`custody_not_empty` 解雇报错；Host 回归证明 5 个 `loadout_*` 命令同时进入总允许表与 `MercTask` 映射。
佣兵装备托管二期（LoadoutPicker 抽离与换装对齐）：Team 三视口固定覆盖 picker 槽位网格+常驻候选栏、合成 PointerEvent 拖拽交付/替换与跨槽白名单高亮/拒绝、双击提交、五态、scope 乐观切换回滚、写后 picker 状态与 scrollTop 保持、快照刷新不关 picker；character-build 两套 harness 在抽离后零断言改动回归；`test-workbench-ui-ratchet.js` 焦点环例外为 (file,selector) 白名单表并覆盖 merc 槽位。
设计文档：[佣兵装备托管-设计-2026-08-23](../docs/佣兵装备托管-设计-2026-08-23.md)、[LoadoutPicker 抽离与佣兵换装二期-设计-2026-08-24](../docs/LoadoutPicker抽离与佣兵换装二期-设计-2026-08-24.md)。

Team/Pet/Merc 的 exact 身份与迟到回包合同见 [持久写与恢复](#save) 的「Host/Web 权威与生命周期门」。

<a id="suite-hairdresser"></a>
### 理发与整形

必跑：`node tools/validate-panel-contracts.js` + `node tools/test-panel-contracts.js` + `node tools/test-panel-runtime.js`；`node tools/run-hairdresser-harness.js`（低负载源码检查可用 `node tools/run-hairdresser-harness.js --static-only` / `node tools/run-plastic-surgery-harness.js --static-only`；
该模式不证明浏览器布局或实机体验）、`node tools/run-plastic-surgery-harness.js` + `node tools/test-dressup-stable-fit.js` + `node tools/test-inventory-workbench-lazy-closure.js`、`node tools/run-bootstrap-character-create-harness.js`；
`scripts/run-hairdresser-tests.ps1`（机器钉死 39/39）、`scripts/run-plastic-surgery-tests.ps1`（机器钉死 44/44）、`scripts/run-character-creation-tests.ps1`、`scripts/run-character-build-tests.ps1`；`launcher/tests/run_tests.ps1`。理发保留 77 行免费目录与 CAS；整形覆盖原地刷新、保留 HP/MP/Buff/装备、一次性扣费、保存失败重试、未知 token 查询与关闭重开。
严格保存、独立 XFL/asLoader publish 和候选/人类验收分别取证，见 [整形共享说明](../docs/医务室整形-Web面板与外观共享-2026-09-08.md)。

<a id="suite-bootstrap"></a>
### 启动页与建角（Bootstrap）

- 启动页 `node tools/run-bootstrap-harness.js --browser edge`（PM19 V2：延迟入口重放、40 线等和、可见时钟、静止 resize、暂停零配置写、视频/建角覆盖冻结、透明加载持续扫光及遮罩更新、右栏实际像素、持久错误与绘制故障回退、640×360 大字错误提示/重试可见、启动/重试单次发送和单向退休）。
- 建角 `node tools/run-bootstrap-character-create-harness.js --browser edge`（V2 使用 `paused-covered`）。
- 当前背景与人验边界见 [启动引导-PM19质数幻方背景-设计与施工-2026-08-05](../docs/启动引导-PM19质数幻方背景-设计与施工-2026-08-05.md)。
- Bootstrap harness 另须验证首页作者/版本 Markdown 页签、近全屏完整边框、单版本按钮/键盘切换、2.718 视频提纲、GitHub 整包链接、当前动态版本与原音频设置。

启动前门迁移门（Host/Web/AS2 完整矩阵）见 [选关、启动前门与关卡会话](#suite-stage)。

<a id="suite-minigame"></a>
### 小游戏（Lockbox / Pinalign / Gobang / 黑市）

**Node QA**：单局 `node launcher/tools/run-minigame-qa.js --game lockbox|pinalign|gobang`；全套 `node launcher/tools/run-minigame-qa.js --game all`（`--game` 亦接受 `blackmarket`）。静态校验 `node launcher/tools/validate-minigame-final-state.js`，拦截旧平铺 Lockbox 入口、旧版分游戏 session 命令名、旧共享结构 class 名。
各模块 `dev/harness.html?qa=1` browser harness。

**黑市**：另跑 `node tools/derive-black-market-shadow-catalog.js --check`、`node tools/test-blackmarket-equipment-preview.js` 与 `node tools/test-workbench-inspection-viewport.js`。黑市普通产品门必须证明：core 拒绝 exact catalog 输入；浏览器 lazy closure 不含 exact oracle、dressup、EquipmentInspector 或 `equipment-preview.js`；
Web 静态根没有 exact catalog/oracle 文件，历史 catalog/exact-core URL 不可读；旧 bootstrap marker/`allowExactIdentityLab` 即使预置也不能创建 exact API；产品只生成 `anonymous / 匿名影子货舱` 合成货物，公开 `category/subclass/counterPrice` 在真实目录命中 0 项；调用方 seed 不能重放；snapshot/DOM/ARIA/遥测/新请求不含真实 URI/ID/icon key/目录 JSON；六件 surface 只消费身份无关 `data:` 表面。
K 支付提取与回售继续分别记录 `deltaTp/deltaK/deltaV` 并满足 `deltaV=deltaTp+50×deltaK`。全目录闭包、确定性配对、492/492 防具、完整武器与代理锐化只由 Web 根外 `tools/fixtures/blackmarket/` 和独立 Node QA 验证，不是产品 panel/browser 能力。面板保持固定 `1024×576`、仅由 `PanelScale` 缩放，检视只复制匿名覆泥母版。浏览器不可用时不得用 Node 结果代签像素观感；
黑市仍是 `productionWrites=false` 匿名影子交互，不代签真实目录玩法、经济、AS2 存档、正式 runtime 或 WebView2 业务 E2E。

**Gobang trainer 专项门**：改五子棋 AI、题库或 trainer 时，先用 `powershell -ExecutionPolicy Bypass -File scripts/gobang_trainer_cycle.ps1 -Problems <id|prefix*> -StopBusAfter -Json` 定向，再去掉 `-Problems` 跑完整 68 题。
健康结论要求唯一 runId 闭合块、`Total=68 / Run=65 / Skipped=3`、Local `65/65`、分类分子/分母一致、Compiler Errors `0/0`、retry `0` 和 scratch/bus 完整回收；Rapfi 差异单列观察，不替代本地门。文本记录 2026-07-25 当前树完整 fresh 基线为 Local `60/65`、Rapfi `58/65`，因此按预期 exit 1，五个失败详见 `Gobang/TRAINING_METHODOLOGY.md`（待核：该基线为历史文本）；不得把 runner/编译器健康误写成 AI 全绿。

**Jukebox Panel**：自动 harness `launcher/web/modules/jukebox/dev/harness.html`（手动）或 `node tools/run-jukebox-harness.js --browser edge`（无头），固定覆盖首次 catalog 对账专辑 chip、点曲 pending→active、停止后实际 Canvas STANDBY 绘制、主题持久化与 LED 状态；旧 `web/modules/jukebox.js` 已退役，发布门禁和复杂度审计不得回引。
改 `web/modules/jukebox/jukebox-panel.js` / `WebOverlayForm.HandleJukeboxMessage` / `MusicCatalog` 时补跑 [launcher/README.md](../launcher/README.md)「Jukebox panel 手测」；只改 Native HUD [AudioHudState](../launcher/src/Guardian/Hud/AudioHudState.cs) / Notch 背景包络则走 [Native HUD gate](#specialized)，不要求重复跑未触及的 Web panel harness。

<a id="suite-fonts"></a>
### 字体目录

先跑 `node --test tools/fontctl/tests/fontctl.test.js`、`fontctl validate / scan / resolve / audit-usage / generate --check`，再跑 `node tools/run-font-catalog-harness.js`、分别以 `--scale 1`、`1.25`、`1.5`、`1.75` 运行 `node tools/run-intelligence-harness.js --viewport 1024x576`，并运行 `launcher/tests/run_tests.ps1`；
改 Native 消费、Host handler、FontPack 或启动顺序时追加 `launcher/build.ps1`。打包改动还须跑 `tools/cf7-packer` 的 `npm test -- packages/core/tests/runtime-fonts-config.test.ts` 与 `npm run validate-config`；Crafting、Equipment、KShop、NPC closure 变化分别跑其 `tools/workbench-live-e2e/*/bootstrap.js --check` 父门。
`sync --check` 是已选择下载集的 cache 完整性诊断：干净仓库的 gitignored cache 为空时应报告 missing，不要求全绿；其安全下载、staging 与恢复语义由隔离 fixture 覆盖。
矩阵覆盖 XML/XSD/generated compatibility manifest/permanent 完整性、来源优先、requested+redirect allowlist、安全 staging、Web CSS/Canvas/preset/compatibility、三视口四 DPI、离线/损坏 fallback、C# 投影 hash、style/restart boundary、production closure 与 temporary 打包排除。

**分层语义**：Node 的 glyph/metadata 门不得代签 custom 的运行时可用性；`fontctl resolve` 只建模 face-major 静态顺序，首选前的 TTF/OTF/WOFF custom 固定为 `runtime-probe-required`，未探测 OS family 的 system fallback 也为 provisional，且 `hostExactSelection=false`。
custom 实际正负例、Native `AddMemoryFont`、Web/Native 共用已验证 byte snapshot、hash ETag、未命中后下载可见与 FontPack 每次重新读盘验真由 C# 定向测试证明；Edge harness 仅为 `browser-fixture-non-authoritative`。打包门必须让三项 generated 投影与兼容 manifest 实际经过 filter + execute pack 并出现在输出闭包，不能只检查仓库存在。
FontPack 追加 `RuntimeFontCatalogTests`，分别模拟 GitHub Release→`release-assets.githubusercontent.com` 和 raw→`raw.githubusercontent.com`，并拒绝非默认端口及后续 foreign/sibling hop。

<a id="suite-reward"></a>
### 奖励、礼包与统一暂存

**礼包/物品使用门（2026-08-31 工作树起）**：另跑 `validate-reward-packs.js`、`node tools/test-character-build-item-use.js`、session/projection/workbench/audit Web 四门、`launcher/web/modules/loot/dev/test-loot-state.js`、Loot browser/lazy-cancel harness 与 Host ItemUse/CharacterBuild/Loot focused。
AS2 覆盖三模式礼包、stale/满容量零写、回执查询、64-occurrence 持久回读、旧手雷恢复、未打开 Reward authority 在新批次追加后重建而已打开 identity 保持稳定、药剂 lane 优先级、四条帧权威 cooldown snapshot、claim 原子性，以及圣诞树 10/20/40/60/120 分钟帧窗口、主线进度门、跨场景已投送隐藏、跨 Flash 启动 token 不碰 AVM1 int32 饱和和 `#supplytime` 仅域偏移。Web 另固定：服用提交后只凭 fresh snapshot/new lease 恢复同物理槽同物品选择与原焦点，物品耗尽/换位/换物不恢复；
候选旧回包按 `stale_state` 安全刷新、已被后续操作取代时静默收束；四条有序 lane 严格 shape、活动期短轮询/全 ready 停止、两组同列格内阴影同步，从 0 条 ready 首次转为至少 1 条时只对含 `no_available_lane` 的当前背包总览重读一次并复原同物品选择，且 cooldown 不产生 blocked 红框或新增排版行。Host 只在无 selector 背包总览要求并复验 `useAction/useBlockedReason`，装备槽、药剂槽和带 selector 的 backpack scope 必须保持原候选行形状。
静态/XFL 门不代签 Flash CS6 fresh Compiler/trace、游戏旅程、promotion 或 `standard_entry_verified`。

**统一奖励暂存回归**：共享收纳工作树定向 Web/DOM/Host/AS2 入口与证据层级见 [本轮回归矩阵](../docs/暂存物资并入共享收纳工作台-调研与施工方案-2026-09-12.md#103-定向回归与证据)。旧奖励回归：`scripts/run-reward-stash-tests.ps1`（机器钉死 114/114），加 `-RunScale` 测隔离 SOL 的 0/64/256/1024/4096 条与实际字节/P95/P99/pack/flush/保存分段耗时；旧 root N+1/terminal ACK 和关卡继续跑 `scripts/run-map-loot-tests.ps1`。
Web/Host 入口、已替换的旧产品合同、20 样本的观测边界与候选验收状态见 [暂存 ADR](../docs/统一奖励暂存与非阻塞领取-ADR-2026-09-11.md)。

**Reward H-A 隔离测试档门**：人工跨重启验收只允许使用 `cf7_agent_reward_root_acceptance_v1` 等专用 `cf7_agent_*` 槽，玩家现役 `crazyflasher7_saves*` 只能作只读 seed。
运行 `node tools/prepare-loot-target-full-save.js --seed-slot crazyflasher7_saves --slot cf7_agent_reward_root_acceptance_v1 --fixture reward-root-partial-v1` 后，再以相同 `--slot/--fixture` 加 `--verify-only`；
生成器必须证明 seed 逐字节不变、target 旧 JSON/tombstone/SOL 已先备份、背包 0–49 全满、49 槽恰有一个固定配方「感恩节礼包」、`ext.rewardInbox` 为 canonical empty v1。进入 target 后开包会腾出一格并建立 11 项确定性 Reward；H-A 仍必须真人确认一次容量受限 partial 的中文结果与实际资产一致、正常退出和同 candidate/slot 重启后不重不丢、腾位后 remaining 可继续领取且无永久 loading。
修复门要求 capacity root 的 blocked/remaining exact-set 相等且只含容量错误，并允许 Reward 重投影轮换 retained lease；Web 必须保留 exact 容量原因和 organizer CTA。生成器单测入口为 `node tools/test-prepare-loot-target-full-save.js`；fixture/自动门不代签真人感知，也不得在 H-A/H-S 裁决前触发提交或部署。

Reward 未知写查询、O1 观测与存档闭包合同见 [持久写与恢复](#save)。

<a id="suite-equipment-set"></a>
### 套装、钛合金与血剑/激光武器专项

**套装一期**：按 [设计文档 §6](../docs/套装系统-设计与剑圣一期验收-2026-07-14.md) 执行 validator、组件 preflight/显式失败回滚、抗性 85/破击 `power*0.075` 精确值、SetEffectController 单测、TestLoader 新鲜 trace、asLoader publish 与游戏内验收，剑圣五件套是首个完成门。

**钛合金原型离线模型**：运行 `python -X utf8 -B tools/cf7-balance-tool/models/ti61/test_model.py`、同目录 `model.py` 与 `model.py --check`；[建模记录](../docs/钛合金61式套装-原型建模-2026-09-08.md) 区分设计投影与实机验收。

**钛合金反馈增量（2026-09-10）**：`scripts/run-titanium-set-tests.ps1 -TimeoutSeconds 900`（机器钉死 233/233），覆盖真实复活入口、血剑强化盾量、真伤与高危闪避、起跳保护、砸地一次配给与八秒计时、取消/死亡/卸装清理、171 易伤/击溃及副仓，并覆盖破盾血剑投射、战技联弹与固定增伤。`scripts/run-blood-sword-tests.ps1`（机器钉死 95/95）追加加载真实 things0 血浪容器，检查七波发射、区域定位、视觉无额外扣血与取消；
第五版收尾微调新增 44 帧一次释放、9 帧独立余迹、完整父变换、真实特效池、null 返回与世界卸载；不以旧 70/84/85 项记录代替，也不代签人类观感。`node tools/ti61-feedback/check_blood_wave.js` 的 10 项直接执行生产资源/路由函数体，只是 Node 合同验证。改共享输入/装填另跑手动输入 runner，改 171 开火接线另跑武器动画 runner。业务逻辑发布 asLoader；战技与图标独立发布 things0，核对新鲜 Compiler、Output、SWF 实际解压与新增导出/帧脚本，零编译错误不替代产物可读性。
参数、证据与玩家实战清单见 [施工记录](../docs/钛合金61反馈调整-施工与验收-2026-09-10.md)；旧 S1/S2 基线见 [套装 ADR §17](../docs/钛合金61式装甲套装-玩法设计-ADR-2026-07-27.md#17-首轮运行反馈满血初始盾与红束火控)，focused 测试不代签正式入口体验。

**血剑迁移**：另跑 `scripts/run-blood-sword-tests.ps1`（真实血剑/血浪与余波原 84 项，追加百分比自损及残血支付 11 项，共 95 项，机器钉死）；第五版视觉历史验收见 [迁移记录](../docs/血色光剑天秤-R04材质与装备脚本迁移-2026-09-08.md)，自损试点见 [反馈调整记录](../docs/钛合金61反馈调整-施工与验收-2026-09-10.md)。

**枪械激光**：另跑 `scripts/run-weapon-laser-tests.ps1`（机器钉死 WeaponLaserSightTest 97/97；文本「三槽位 89 项」为历史），见 [激光记录](../docs/P90印花集与钛合金61式共用激光装配-2026-09-07.md)。

<a id="suite-boot"></a>
### Boot / Bootstrap 与材料 catalog loader

**Boot/Bootstrap tracked focused 入口**：`powershell -ExecutionPolicy Bypass -File scripts/run-boot-sequencer-tests.ps1 -TimeoutSeconds 240`；当前 exact contract 为 BootSequencer **91/91** + BootstrapHandshake **12/12**（机器钉死），`-SkipCompile` 只验 template/suite/BOM/scratch 事务。旧的 36/47/58/86 计数是历史基线，见归档。

**`material_catalog.xml` 真文件 loader 的 tracked 异步入口**：`powershell -ExecutionPolicy Bypass -File scripts/run-material-catalog-loader-tests.ps1 -TimeoutSeconds 240`；其 `-SkipCompile` 只证明 XML/source/BOM/scratch 静态门，不能代替实际双 loader `reload()` 回调。
文本记录 2026-08-15 合并树已由生产 loader 实际 `reload()` 取得 catalog 224、legacy 58、DirectPurpose 2、`authoredDirectPurposeId` refs 27（待核：阈值来源为历史文本，未找到当前机器真源）；基建仍由 67 occurrence / 21 unique generator exact gate 约束（待核）。

<a id="suite-loot"></a>
### Loot / 关卡结算 runner

**`scripts/run-map-loot-tests.ps1 -TimeoutSeconds 300`** 现役机器钉死：`LootContainerServiceTest` 189 + `LootMaterializationPlannerTest` 12 + `StageRunSessionTest` 594（脚本内 `$expectedServicePassCount/$expectedPlannerPassCount/$expectedStagePassCount`）。
文本中的旧计数（267+12+419=698、165+9+372=546、205+9+382=596、676/684/824 等合计口径）均为各轮历史证据，见归档。该 runner 的 tracked TestLoader 直接 include 生产 `关卡系统_lsy_场景转换.as`，真实执行 `_root.返回基地/_root.关卡结束`，不得以测试 stub 代签转场异常与 exactly-once 合同。
StageRunSession 覆盖大学/车库选关返回、真实胜利记录、撤退后迟到波次/判胜不能修改真实任务条件与正常胜利恰好一次回归、准备/保存/转场失败、v1/v2 失败投影握手、同结算重试与重复请求拒绝（配套 Host StageOutcome/RightContext、地图 AS2/Web 回归，见 [返回失败恢复](../docs/关卡结果与基地结算-CSharp-Web-ADR-2026-08-27.md#0d-2026-09-08-返回失败后的原生重试入口)）。

**战场即时补给**：`scripts/run-battle-supply-tests.ps1 -TimeoutSeconds 240`（机器钉死 PickupEffectService 59/59 + AmmoSupplyService 50/50 + DrugProhibition 23/23）：四态领取/效果白名单/中性上下文/距离收拢、三范围补弹/GM6 负 shot 跳过/tube 按实例区分/machineGunShot 镜像/换弹在途拒领、DisableDrug 两入口拦截；设计契约与验收边界见 [补给文档](../docs/战场即时补给品-技术调研与首批施工准备-2026-09-12.md) §13–§14。

**命令统一前缀**为 `powershell -ExecutionPolicy Bypass -File scripts/<runner>`。成功输出会报告 `32K retry`：健康基线必须 `retry=0`，自动恢复只能作诊断；`-SkipCompile` 只验 template/BOM/恢复机制。

<a id="cross-layer"></a>
## 跨层协议与权威

**触发**：新命令、schema/身份/版本、打开/关闭、数据所有权、写锁、token、回包或原入口退休。权威核心与领域合同先读 [as2-web-panel-migration.md](as2-web-panel-migration.md)；本节承载跨层 runner 与固定负例。

### Panel pending lifecycle 门

必跑：

- `node tools/test-panel-runtime.js`（文本现役 40/40，runner 为自计数，待核：阈值来源为历史文本，未找到当前机器真源）。
- `node tools/validate-panel-contracts.js` + `node tools/test-panel-contracts.js`（机器钉死口径见 [K 店与 NPC 物品商店](#suite-kshop-npc)）。
- `node tools/run-npcshop-harness.js`、`node tools/run-crafting-harness.js`、`node tools/run-hairdresser-harness.js`（各文本计数待核）。
- `launcher/tests/run_tests.ps1`；提交为 clean immutable tree 后再跑 `launcher/build.ps1`，dirty Worktree 只产 candidate、production policy 必须拒绝。

固定覆盖（改 `PanelPendingCallTracker`、`PanelRequestOwnerLifecycle`、NpcShop/Crafting/Hairdresser pending lifecycle、exact owner close/rebind 或 shutdown wiring 时）：ready=false、active/recent duplicate、response/timeout 竞态单终态、重复/迟到 response、read/write 的 send-false 与 timeout 精确 `error/requiresReconcile/writeState`、
`ClearPending()` / `Dispose()` 后不复活，以及 early/bus-only/normal 三条 shutdown 都 dispose 三个 Task。
Host owner lifecycle 必须在接受关闭后先 seal exact tuple，same tuple 的异步重观察不得重新 admission；只有权威 different tuple 才创建 fresh owner。Hairdresser 另固定 production close observer 清 pending、写在途保留 `needs_reconcile`、重开 fresh snapshot 收敛且迟到 commit 不复活。
通用 `Panels` 另固定覆盖初始/懒注册缺失、create/append/onOpen/onRebind 失败、lazy 同步 throw/非 thenable/异步拒绝、same-active 新 rebind 退休旧 pending，以及 onClose/onForceClose/Bridge.send 异常；任一 mount/rebind 失败只关闭 incoming exact Host owner 一次并清净 DOM/active/pending。
helper 只能保存 correlation 与 opaque context，不得读取 domain/cmd/payload/read-write/token/reconcile/capability；领域 Task 不得残留第二套 pending/Timer/backend callId mux。纯 Host 重构不要求发布 SWF；若声称某域 Flash 回归也在本轮 fresh 通过，须明确取得 fresh trace 还是 Output Panel 副本，二者不得混称。

### AS2 UI → Web Panel 迁移门

按 [as2-web-panel-migration.md](as2-web-panel-migration.md) 补闭环表 + `launcher/build.ps1` + `launcher/tests/run_tests.ps1` + `node tools/audit-workbench-ui.js --strict-warnings` + `node tools/run-workbench-visual-atlas.js --strict-warnings`。
改 `PanelTooltip`、profile、消费者或相关 CSS 时另跑 `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run-tooltip-corpus-audit.ps1 -TimeoutSeconds 999`、`node tools/parse-tooltip-corpus.js`、`node launcher/perf/tooltip-audit/runner.js` 与 `node launcher/perf/tooltip-interaction/runner.js`。

改 Overlay 游戏 UI 行为、KShop/工作台 `Panels` required-assets 门、
`ShopTask` / `InventoryTask` / `game-ui-behavior.*` / `panel-runtime.js` / `workbench-lifecycle.js` / `workbench-focus.js` / `workbench-primitives.js` / `workbench-components.js` / `workbench.js` / `item-filter.js` / `kshop-runtime.js` / `kshop-views.js` / `kshop-cart-controller.js` / `kshop-*-presenter.js` /
`inventory-runtime.js` / `inventory-ui.js` / `inventory-workbench-*.js` / `inventory-workbench.js` / `npcshop-secondary-pages.js` / `skills-*.js`（lazy registry 必须按依赖顺序审计，
不只检查文件存在）/ `equipment-tuning-*.js` / `kshop.js` / 对应 CSS 时，追加 `node tools/test-item-filter.js`、`node tools/run-item-grid-visual-matrix.js`（截图加 `--shot=tmp/item-grid-visual-matrix.png`）与 `node tools/run-kshop-harness.js`（另自动复跑真实 `PanelTooltip` PointerEvent 探针：共享语义 ItemCard/ItemGrid、完整/紧凑、类别/套装/专柜入口、武器三级下钻、标题面包屑祖先返回、
筛选轨道不抖动、装备调制帮助、合成子路由返回，以及 checkout 成功后延迟 inventory refresh 期间新加购不丢失/已交付条目不复活）；
改 `data/items/equipment_mods` 展示元数据时追加 `node tools/validate-equipment-mod-ui.js`（文本口径 105 mod / 四档 / 六 scope / 101 插件材料，另含四个特殊材料的一对一闭包，待核）。

公共矩阵固定断言：目录并列分支、背包行内单层下钻、标题面包屑单行与溢出中段折叠、native select 隐藏、无嵌套横向滚动和二级页覆盖；KShop 还须断言切换分类时筛选轨道与物品格顶边不移动、分类按钮无过渡动画，真实 tooltip 门固定断言基础 Web 样式、富布局、图标与 basic→rich 连续重排，并覆盖 `0.667/1.25` transform scale 的 10px gap/视口闭包、detached owner 不复活及 scope dispose 后 detached binding=0；
`dense-inspect` 必须浮层零 hit-test、仅正文溢出时 1 秒稳定停留进入检视、顶部状态条不覆盖正文且 owner 进入动效与稳定外轮廓可辨、6px 无箭头滚动指示器按 pending/inspect 换色、快速/慢速横纵斜轨迹、新 owner 抢占、owner wheel 边界不泄漏、键盘立即检视与离开退出；`pinned-inspector` 必须显式激活、hover 不覆盖、以 7px 无箭头且可 hover 的滑块独立滚动，并由 close/Esc/outside click 退出；`simple-tooltip` 只允许有界短提示。
仍直接调用 `showAtMouse/showAnchored` 的消费者必须显式 profile 并追加领域 harness，面板关闭、rebind 或整树替换必须 dispose/release scope；
改 lifecycle/focus/SecondaryPage 时追加 `node tools/test-workbench-lifecycle.js`、`node tools/test-workbench-focus.js`、`node tools/test-workbench-focus-integration.js`、`node tools/test-workbench-components.js`，fresh trace 固定覆盖 `KShopCheckoutServiceTest` 中的专柜名、套装元数据、武器子型独立投影、legacy 结账复用权威限额/直接交付及情报领取按真实目标路由；
业务视觉复现沿用 `--visual=... --shot=<path>`。inventory AS2 固定回归 `InventoryPanelServiceTest`（机器钉值见 [库存、背包与批量转移](#suite-inventory)），覆盖重复纯读 lease 稳定、真实写入版本失效、原位装备指纹、套装分支对完整权威容器跨页筛选、全部成功写入口推进 `mutationRevision`、失败写不推进与 facet 缓存 O(1) 失效；Host 固定回归结构化类别/套装筛选白名单、`filterKey/filterSpec` 一致性与回包镜像；旧 AS2 无 facets 时保留兼容回退。
改宿舍 XFL 入口还须发布对应 XFL/SWF；真机须覆盖仓库/战备箱、紧凑密度、类别/套装树筛选、写入后 facet 刷新、断线重开对账及重启回读。

### Item identity triple 聚合门

`powershell -ExecutionPolicy Bypass -File tools/run-identity-triple-gate.ps1`：先跑 contracts、真实 mod/icon closure 与 canonical presentation mutation ratchet，再严格按 **shared Inventory+Character+Loot → KShop → Crafting → NPC Shop → Equipment Tuning strong reference** 排列；
每段的 tracked AS2、领域 Host filter、Web 专项与完整 feature harness 必须相邻执行，不得嵌套 A2 `run-inventory-fault-gate.ps1`、使用 `--identity-only` 或以单一 Host filter/共享 fixture 代替完整视图与生命周期。`scripts/run-item-panel-tests.ps1 -Suite Shared|Crafting|Npc` 提供分域 tracked TestLoader，缺省 `All` 保持全套入口；
Gate 缺省只做 `-SkipCompile` 静态/BOM/恢复事务验证，追加 `-CompileAs2` 才逐段取得 fresh trace/output/errors、Compiler `0/0`、32K retry `0` 并对每个 fresh `scripts/TestLoader.swf` 跑 function-size 门。
Crafting 商品图审阅必须在同段依次执行 `node tools/test-crafting-product-review-cleanup.js`、隔离 `--sample --output-root tmp/identity-triple-gate/crafting-product-review-<unique>` 构建与 `--review-data` 消费；Gate 的 `finally` 只准由同一 builder 的 `--cleanup-output-root` 模式清理该唯一临时子目录，默认 `tmp/crafting-product-review/` 人工审阅数据不得读写、覆盖或删除。

**触发与固定口径**：触及 `data/items/equipment_mods`、Inventory/Character/Loot/KShop/Crafting/NPC/Equipment 的 AS2 projection、Host sanitizer/preview/postcondition、Web runtime/presenter/renderer 或 identity fixture 时必跑。
固定数据口径为 105 mods / 19 presentation aliases / 13 icon-key divergence / 3 all-distinct / 13 legacy internal-icon misses（待核：阈值来源为历史文本，未找到当前机器真源）；shared 只冻结 `name/itemName` 规则身份、`displayName` 玩家文案、`icon` 资产键及安全叶节点，旧缺字段兼容仅允许在 AS2 authority projection，Host/Web 不猜 alias；字段字节相等合法，但角色仍分离。
每个写域继续独立证明 exact owner/request/selector、sanitize、任意新 preview 尝试的旧 token 策略、single-use commit 与 accepted postcondition。聚合门通过仍不等于整树 Launcher、candidate、游戏 E2E、promotion 或部署。

**A3 关闭条件（现役口径）**：按 2026-08-05 本地单机、单操作者比例裁决，A3 关闭要求 current-tree shared + Equipment + KShop + Crafting + NPC 完整 canonical Gate、专用 clone 恢复，以及当前 isolated candidate 的一条 Equipment `snapshot→三名分离候选 preview→commit→fresh snapshot→安全保存→不重新播种重启读回` 生产旅程；候选替换与旧 token 拒绝继续由自动门证明，不再要求 KShop/Crafting/NPC 重复 live mutation。
优先使用 Launcher Agent Runtime computer-use；能力不可达时可回退 Codex computer-use，本机 WebView2 子窗口无法被 Windows 自动化直接命中时允许使用候选页面输入通道，并如实记录 `isTrusted`/pixels 边界；该边界属于 A5 交互验收，不阻断 A3 authority/data 与存档读回。
NPC 新 live receipt 必须在 bootstrap 命令中显式携带整数 `--expected-buy-rate-permille 0..1000`，并由 v5 bundle/receipt 同时绑定 initial 与 fresh-restart 权威快照；页面成功但倍率场景未命中不得算定价覆盖。历史自动基线现为 Superseded / Reopened（见归档）；
A3 四消费面离线证据只允许从 `node tools/workbench-live-e2e/equipment/bootstrap.js --check`、`node tools/workbench-live-e2e/kshop/bootstrap.js --check`、`node tools/workbench-live-e2e/crafting/bootstrap.js --check`、`node tools/workbench-live-e2e/npc/bootstrap.js --check` 进入，直接 runner/verifier 必须 `NOT_ADMITTED`，
并追加 `node tools/workbench-live-e2e/lib/self-test.js`。
任一领域在最终 Gate 后发生生产字节变化，只重跑 shared 与该直接受影响领域；五门、Equipment live receipt 与一次独立终审 GO 前保持 `NOT_DEPLOYED`，不得批准 A4。

### B4–B6 fixed post-close、Materials exact handoff 与 Intelligence exact admission

必跑：`launcher/tests/run_tests.ps1`；定向覆盖 `LauncherCommandRouterTests|TaskRegistryStatusTests|WebOverlayFormPanelCloseTests|PanelHostSkillInstanceTests`；B5 AS2 跑 `powershell -ExecutionPolicy Bypass -File scripts/run-item-panel-tests.ps1 -TimeoutSeconds 240`；
Web 继续跑 `node tools/test-inventory-workbench-modules.js`、`node tools/run-character-build-harness.js`、`node tools/run-character-build-workbench-harness.js`、`node tools/test-panel-runtime.js`、`node tools/validate-panel-contracts.js`。

合同：close parser 只认 `navigate_skills | navigate_materials | navigate_intelligence`，现役三目标均启用；intent 只持 target/exact instance/phase/generation/lifecycle epoch/timer。Materials direct HUD 与 Character settled 都必须先安装独立 wait，再发 Host opaque `openRequestId`；
只准入 exact `{task:"panel_request",panel:"crafting",source:"nativehud_materials",initData:{view:"materials"},openRequestId}` 与 Host admission，并固定 runtime initData。合法无 nonce ordinary Web materials envelope 仅在没有 armed intent/material wait 时准入；存在 wait 时 missing nonce 拒绝并保留正确 wait；显式畸形 token 在 AS2 零发送；
nonce-bearing wrong/near-match 是当前 target failure，清 wait 并按阶段一次提示/至多一次 rollback，迟到正确 echo 零打开。Intelligence 只在 exact coordinator settled 后于同一 lifecycle fence 内取得 Host idle admission，并以 Host 内建封闭 `{mode:"prod",source:"runtime",debug:false}` 同步打开；
Web 不提供 panel/initData，零 AS2 nonce、零 target timer、零 Skill/Material wait 与 `FixedPanelOpenWait`。固定覆盖 sync false/throw、competition、navigation/热重载/socket/shutdown、admission、lifecycle advancement、late/duplicate、pre-close Build 保留、post-close 至多一次 rollback，以及 rollback 失败留在游戏并给出装备入口提示；
Host admission 一旦接受，后续 pause socket false/throw 不反转成功边。

### 共享 `PanelTooltip.bindAsync` 焦点合同

合同中的「focus A→hover B→leave B 恢复 A」专指真实键盘导航取得 focus 的 A；固定反例门为「真实鼠标点击 A→空白隐藏」和「真实鼠标点击 A→hover B→空白不得恢复 A」，并须确认鼠标点击已键盘聚焦的 A 会撤销 keyboard owner；测试不得用裸 `.focus()` 冒充 pointer/keyboard 来源。

持久写侧的锁存/对账合同见 [持久写与恢复](#save)；面板 UX 与共享工作台视觉门见 [Web、工作台与小游戏](#web)。

<a id="web"></a>
## Web、工作台与小游戏

**默认顺序**：纯逻辑 / 确定性问题先跑 Node QA；协议 / DOM / 布局 / 交互问题进 browser harness；目录 / 协议 / 旧入口回流问题再补静态校验。启动页涉及脚本顺序、`BootstrapApp.onMessage`、PM19 相位、tooltip 或键盘时，固定补跑 bootstrap harness；它不替代真实 Launcher/WebView2 启动链。

**Browser harness（直接打开）**：`launcher/web/modules/minigames/{lockbox,pinalign,gobang}/dev/harness.html` / `launcher/web/modules/map/dev/harness.html` / `launcher/web/modules/stage-select/dev/harness.html` / `launcher/web/modules/intelligence/dev/harness.html` / `launcher/web/modules/jukebox/dev/harness.html` /
`launcher/web/modules/crafting/dev/harness.html`。

**URL 参数**：`?qa=1` 自动断言 / `?case=` 单条 / `?scenario=` 脚本场景 / `?dump=1` 结构化输出。

**双栏工作台共享门**：另按 [workbench-ui-system.md](workbench-ui-system.md) 运行 `node tools/audit-workbench-ui.js --strict-warnings`、66 场景（48 shared synthetic + 18 Arena 生产闭包两阶段）`node tools/run-workbench-visual-atlas.js --strict-warnings`、`node tools/test-panel-lazy-loader-browser.js`（真实 Edge 中间依赖一次 503 后重试）、
20 项 `node tools/run-item-grid-visual-matrix.js` 与受影响 feature harness（66/20 等文本计数待核：阈值来源为历史文本，未找到当前机器真源）。
Tuning/整备/面包屑加固还固定运行 `node tools/test-equipment-tuning-confirmation.js`、`node tools/test-equipment-tuning-interaction.js`、`node tools/test-equipment-tuning-source-marker.js`、`node tools/test-inventory-workbench-preparation-menu.js`、`node tools/test-workbench-profile.js`、`node tools/test-workbench-ui-ratchet.js`；
断言必须覆盖 owner-scoped disabled/ARIA 恢复、强化控件保持焦点/候选交换才迁移 CommitBar、具名 `role="group"` 且 generic section 无 `aria-disabled`、Click/Enter/Space toggle、ArrowDown open、Tab 关闭但不 `preventDefault`/假移焦，以及面包屑 root/current/ancestor 完整 accessible path 与省略中段 title。

**reduced-motion G4 收尾门**：G4 的收尾不接受「media query 文本存在」作为通过；
同一树至少运行 `node tools/test-workbench-ui-ratchet.js`、`node tools/run-kshop-harness.js`、`node tools/run-equipment-tuning-harness.js`、`node tools/run-character-build-workbench-harness.js`、default/release-tree strict UI audit、CSS bundle、visual atlas 与 item-grid matrix。
KShop 必须证明 shell busy pulse、壳外 Tooltip exact workbench owner、`tasks` 反例、Inspector transition 与 SecondaryPage 静态终态；Tuning 必须证明 ambient normal 实际运行、reduced 下 animation 归零且 `.55` 静态补偿和尺寸保留；Character 必须读取 renderer create option。
工作台 `skins.css` / `character-build.css` 不得重现 `.001s/.001ms`，Loot / Inspector 不得重建 root 已覆盖的 local reduced block，Tuning 本地只保留静态补偿；SecondaryPage `visibility 0s linear` 是合法延迟离场，非工作台 `task_panel.css` 的 `0.001s` 有意范围外，只能称「工作台已清零」。

**Character Workbench 导航事务与 busy header**：Storage ↔ Build 导航事务必须覆盖递增 generation 与 destroyed fence：destroy 先使 pending 失效并清 ports，随后到达的 prepare callback 对 activate、mount、history 与 focus 均为零副作用；controller 在 pending 期间上报不同合法 view 时必须 supersede 旧事务并推进 generation，不得在提交新 view 后遗留旧 pending 门；
30 秒 orphan watchdog 只允许 discard/abort/恢复操作，迟到 callback 零副作用，绝不把 timeout 当成功。新增两条叶门分别覆盖分叉上报与 orphan prepare。这证明关闭了确定性 navigation race/活锁路径，但「重启后恢复」本身不能证明内存泄漏、WebView renderer crash 或透明 tooltip/overlay 遮挡，归因仍须 live hit-test、`ProcessFailed`、heap/console 证据（见 [诊断与现场观测](#diagnostics)）。
带 reason 的 Build busy header action 必须保持 `aria-disabled` 与真实解释路径：可见 stats/close 仍有非零 hitbox，四个 action 保留基线 accessible name、把生产 capture 先读取的 cue 切为 `error`，真实 Edge 内 DOM `.click()` 只显示对应动作 reason（Close 明示完成后才能关闭工作台）且零 stats/navigation/close 穿透，恢复后原名/原 cue 精确还原；legacy rollout-off 的 storage/skills 复用同一守卫。
无 reason 的禁用态仍使用原生 `disabled`。

**map harness 固定覆盖**：Canvas renderer debug state 与非空像素、顶部分页与关闭按钮的 hit-test 可达性、右侧层级按钮遮挡、学校页 `室友头像` 动态切换、`1366x768` 紧凑视口滚动可达性、locked group 的锁定提示与锁定原因可达性、`base` assembled 热点框与 Canvas scene visual 联合包围框对齐（`map-ui11`）、静态头像运行时 rect 与 source metadata 对齐（`map-ui10`）、taskNpc 环锚点跟随并套住动态头像、任务环层低于 hotspot 标签层（`map-ui12`）、
连点热点去重 + busy 物理 disabled（`map-ui13`）、hotspot / 分页 / filter / close 的 `data-audio-cue` 语义路由**且单次触发**（`map-ui14`，依赖 overlay 载入 `modules/audio.js` + `modules/overlay-audio-bindings.js`；
harness 用 `BootstrapAudio` 计数器存根替身；13 事件语义词典 / 面板 profile / 防双响规则的权威定义见 [Web UI 音效契约](../docs/Web-UI音效-语义语言与接入契约-2026-08-15.md)）、右侧 rail 脱离 stage frame + body 不溢出（`map-ui15`）、locked filter 点击不切状态且弹锁定原因 toast（`map-ui16`）、faction filter 切换驱动 `data-active-filter` 属性与 canvas filter summary（`map-ui17`）、
defense restricted filter 触发 canvas anomaly state（`map-ui18`）、rail 手风琴仅展开 active 非 meta filter 子场景列表 + 点子项复用 `requestNavigate`（`map-ui19` / `map-ui20`）、filter-fit preset 按 page/filter preset 命中并维持 coverage floor（`map-ui21`）、学校页静态头像与场景归属保持一致并输出 review 候选（`map-ui22`）、热点左下角标签通过 content-fit 内独立标签层保持高于透明命中层并贴合热点（`map-ui23`）
、地图热点二级「选关」动作打开匹配 stage-select frame 且不替代主 `navigate`（`map-ui24`）、host 驱动关闭后 canvas RAF 循环停止不泄漏（`map-ui25`）、任务红点 hotspot/filter/page 三级聚合 + 同 hotspot 多 NPC 折叠为 1（`map-ui26`）、locked group 剧透防护下任务红点不点亮（`map-ui27`）、task hotspot stage-select 副动作快捷入口（`map-ui28`）、同一 hotspot 多 NPC 仅计 1 + 跨 filter 折叠（`map-ui29`）、
page tab badge 计数 >= 10 时夹到 "9+"（`map-ui30`）、pixel-level hittest 引擎 alpha 边缘 / 重叠覆盖（z 顺序后画覆盖前画）/ filter 过滤 / 浮点/NaN 坐标边界（`map-ui31a`~`map-ui31d`）、sceneVisual DOM 层非 hierarchy 模式 canvas drawScenes 短路（`map-ui32a`）/ hierarchy 模式 canvas 画非 focus muted + DOM 显 focus 无双绘（`map-ui32b`）
/ current+hover 不同位 DOM 两张同显 + dimmer 压暗（`map-ui32c`）、动态舞台缩放联合 viewport / 素材清晰度 / Canvas 像素预算限幅并验证选择性 2× 资产能力（`map-ui33`）。

小游戏（Lockbox/Pinalign/Gobang/黑市/Jukebox）的 runner 与合同见 [小游戏](#suite-minigame)；各业务面板的 runner 见 [领域 suite](#domain-suites)。

<a id="host"></a>
## Host、总线与自动化

**普通开发**：先跑 `launcher/tests/run_tests.ps1`；需未提交 Worktree 的人类可见检查时，推荐运行 `automation/dev.ps1`（或根 `本地开发启动.cmd`）：它按当前 Worktree build identity 精确复用/生成 candidate，始终 `NOT_DEPLOYED`，并硬核验 `runtimeMode=isolated_candidate`、`processPath`、`coreSha256`、`buildIdentity`、`payloadClosure`。
`automation/start.ps1` 无 `-CandidateRoot` 只属于已 promotion 正式入口；`start.ps1 -CandidateRoot` 仅作指定产物的低层诊断兼容入口。native 源码直推后 Audit 应成功报告 `source-ahead`，不要求每次立即 promotion（发布协议见 [正式 runtime 发布](#runtime)）。

**Launcher xUnit runner policy（机器核对一致）**：`launcher/tests/xunit.runner.json` 是全量 `launcher/tests/run_tests.ps1` 的 canonical execution policy，冻结且只允许 v2.8 schema、`diagnosticMessages=true` 与 `parallelizeTestCollections=false` 三项治理键（已核对当前文件内容与此一致）。runner 严格预检 source；csproj 复制配置；程序集自检 output copy 的三项 exact 类型/值；
testhost 在 `console;verbosity=normal` 诊断流中还必须恰好一次出现 `parallel test collections = off` marker，单个 fact 或重跑绿不能代签实际串行。不得用 CLI 重开集合并行或逐项放宽生产 deadline。

**总线健康 / AS2 回环**：`bash tools/cfn-cli.sh status`；`bash tools/cfn-cli.sh console "help"`。

**集成 (testMovie)**：`bash tools/cfn-cli.sh start-bus`（headless：直跑 `runtime/Core.exe`，绕 bootstrap 的 MessageBox）。

**`--bus-only` 适用范围**：Flash CS6 testMovie ↔ Launcher 通信链验证；AI / 模拟实验需外部 Flash 自连总线；排查启动链路 vs 总线本身。根目录 `.exe` 是 net10 native bootstrap（runtime 缺失会弹框阻塞自动化），headless 调用方（`cfn-cli.sh` / `automation/start.ps1` / `scripts/gobang_trainer_cycle.ps1`）都已切到 `runtime/Core.exe` + 复刻 bootstrap 的 `DOTNET_ROOT` 探测。
验 **Flash↔launcher 建连 / XMLSocket / FlashPlayerTrust** 类问题**只用真 launcher**，别用 `compile_test`/`testMovie` 或裸 socket 桩：testMovie 作者环境 socket 沙箱与独立播放器不同（自动信任 + 默认探 843 master policy），裸桩常假阳性（`connect()=true` 但服务端零连接、`onConnect` 不回）；定病因优先读真机 `logs/launcher.log` 是否出现 `WaitingConnect -> WaitingHandshake`（=socket 已连上）。
复盘见 [优化随笔/Flash本地SWF信任与Launcher建连](../scripts/优化随笔/Flash本地SWF信任与Launcher建连——trust编码与IPv6loopback踩坑.md)。

**WebView2 GPU 与浏览器输入策略**：`powershell -ExecutionPolicy Bypass -File tools/set-launcher-gpu-preference.ps1 -List` + `powershell -ExecutionPolicy Bypass -File tools/sample-launcher-gpu.ps1 -DurationSeconds 6` + `node tools/audit-web-overlay-complexity.js` + `launcher/tests/run_tests.ps1`（共享浏览器策略矩阵、
AppConfig/env 与双宿主接线包含在全量）。
`audit-workbench-ui` 只覆盖 Web/CSS 与发布接线，不能代替 Host 证据。GPU `-Apply` / `-Revert` 后完整重启并复核 engine；机器不稳定时先跑静态复杂度审计。输入策略用 exact candidate 分别走 Bootstrap 与 Overlay：生产态验证 Ctrl±、Ctrl+滚轮、F5、F12、默认右键均不改变页面或打开浏览器 chrome，自动填充/密码保存关闭，普通 wheel、inspection wheel、CDP 输入、PanelScale、命中坐标仍正常；真实 pinch 只能由触控/触控板输入证明，CDP 合成 pinch 不记 E2E。
以 `CF7_WEBVIEW2_DEV_MODE=1` 重启后只恢复未被 Host 保留的 accelerator、DevTools 与右键，zoom/pinch 与自动填充/密码保存仍禁；`KeyboardHook` / `HotkeyGuard` 保留 `Ctrl+W/R/P/O/F/Q`，所以开发态用 `F5` 作 reload 正例，`Ctrl+R` 在两种模式都继续走 Host 合同。至少覆盖 100%/150% DPI。文本记录：当前 exact candidate 只在本机 150% DPI 完成双宿主 production/development 实机 smoke；
100% DPI 与真实 pinch 仍待物理设备，不能称完整 D 批 E2E（该限制仍有效）。

**协议延迟专项门**：改 `ServerManager`、`FrameBroadcaster`、JSON callback / push、总线发现或协议 benchmark 时，跑 `powershell -ExecutionPolicy Bypass -File scripts/protocol_latency_cycle.ps1 -StopBusAfter -Json`；需要抖动分布再跑 `protocol_latency_sweep.ps1 -Runs <N> -Json`。
cycle 必须从 AS2 源精确派生并收到 14 个 summary 与各自 raw samples，拒绝缺失/重复/额外/non-finite/汇总不一致，另要求唯一 runId、Compiler Errors `0/0`、retry `0` 和精确 PID bus teardown。单次 sweep 只验证契约，不替代多 run 延迟分布基线。

**DPI 相关 smoke**：改 DPI manifest / overlay 坐标 / Web viewport metrics 时，除 build + xUnit 外人工覆盖单屏 100/125/150/175%、Windows 未勾选与「应用程序」覆盖、双屏混合 DPI 启动/跨屏/全屏切换；「系统/系统(增强)」只要求 `[DPI]` 日志和提示，不把点击正确性列为通过标准。

<a id="save"></a>
## 持久写与恢复

**触发**：SaveManager/R1、SafeExit、库存/共享收纳/暂存领取、交易、奖励或可能触达真实用户槽位的 E2E。未知写只走该域允许的 exact query/reconcile，不自动重试写；实写必须有明确测试范围，使用规定隔离/克隆槽，保护既有差异及原始字节，不反向覆盖玩家已有存档。

### Host/Web 权威与生命周期门

Settings 必跑 `node tools/run-settings-panel-harness.js` 与 `SettingsTaskTests`，固定覆盖非 preview 写的 timeout、DeliveryUnknown、malformed success 均进入 reconcile，且 `ambiguous → close/rebind → 写仍拒绝 → 锁存后有效 snapshot 放行`；锁存前发出的迟到 snapshot 不得解锁，cancel 半恢复保留基线与可见重试，不得自动重放或显示确定未执行。
Team/Pet/Merc 必跑 `node tools/run-team-harness.js`、`node tools/test-panel-runtime.js`、`PetTaskTests`、`MercTaskTests` 与 `WebOverlayFormPanelCloseTests`；两域请求须携 active Team instance，回包须同时匹配 instance、pending callId 与 cmd，foreign/inactive/stale/错命令均拒绝，replacement 清旧 pending，迟到回包不可写新文档。
Pet/Merc 的 exact mutation 在 `client_timeout / timeout / delivery_unknown` 后必须锁存同一因果 epoch、跨 close/rebind 拒绝继续写并自动读取 fresh snapshot；未知写之前的 snapshot、旧 instance 回包或失败 snapshot 均不得解锁，`not_sent / panel_instance_expired` 与普通业务失败则不得误锁或自动重放。Team/blackmarket/warlord close 等 Host exact acknowledgment；
确认丢失 3 秒后只恢复重试，不本地关闭，迟到 A 不关闭 B；旧 `panel:pets|mercs/cmd:close` 必须 fail-closed。blackmarket 另跑 browser harness、`run-minigame-qa --game blackmarket` 与 panel-close tests，exact close 不改变 `shadowOnly`；
warlord 另跑包内 Node/Edge harness、`run-minigame-qa --game warlord` 与 panel-close tests，固定 `productionWrites=false`，普通浏览器不得代签真实 WebView2 或 AS2 战斗权威。六个 tracker Task 还须由 `ProgramPanelTaskShutdownTests` 锁定三条生产 shutdown disposal。

### 玩家物资异常安全门

`scripts/run-player-asset-transaction-tests.ps1` 现役门槛为 **124/124**（机器钉死：`ExpectedTracePatterns` 钉 `PlayerAssetTransactionTest Tests Passed: 124`；
文本中 117/117 为 2026-08-23 旧值、113/113 为更早值，见归档），静态门另冻结 production begin 与 direct-authority caller 精确集合（文本记录为 26/22，待核：以 runner 静态门当前断言为准），并必须得到 fresh trace/output/errors、Compiler **0/0**、32K retry **0**；`-SkipCompile` 只证明静态合同。
runner 静态禁止 XFL 直连事务类，校验 asLoader 提供十个 `_root` 玩家物资门面（含异常结算、强制 dirty 与通用资产 snapshot/restore），冻结 production begin 精确集合，其中区分 direct-authority caller 与 XFL facade begin。AVM1 对 undefined owner 的成员赋值可能静默，已枚举 authority 首写必须经 `PlayerAssetTransaction.markDirtyRequired(saveOwner)` 显式验证、写入并读回 dirty；
focused TestLoader 必须真实 `#include` 任务系统脚本，不能把 AdditionalAs 的 BOM 检查冒充 Quest 动态执行。`ItemUtil.acquire/submit` 必须以 raw before/after 判定请求是否完整兑现，receipt 才按请求 ownership budget 截断；同步监听器造成少发、错槽、over-acquire/over-remove 时返回 false，由现役复合领域 exact snapshot 恢复，不能用 capped receipt 反证成功。
Quest 固定 submit 交付物→可恢复奖励→经 `require` 聚合校验的 XP/SP→任务完成→commit→guarded 升级投影顺序；任何 false/throw 恢复资产、任务、进度与 dirty，下一任务独立成功。`TaskPanelService` 在 `FinishTask=true` 后只把任务列表当可降级投影；构建异常仍回 `success:true + refreshDeferred:true`，下一 snapshot 独立恢复，禁止把已提交奖励变成永久 busy/未知重放。
成就领取保留首写前 claimed one-shot，首次已提交回包异常被隔离，下一 callId 仍以既有 `already_claimed + overlay` 收敛且不重复发奖。生产 direct caller 另由 `DrugInputServiceTest`、`ManagedLongGunServiceTest`、NPC、KShop、Crafting、EquipmentTuning、Inventory 各 focused suite 覆盖（现役钉值见 [领域 suite](#domain-suites)）；
Crafting 的 procurementPlans 与资产/dirty 同快照，submit=false 的 partial/over-remove 也必须 restore 后 settle(false)。另须运行 `node tools/test-panel-contracts.js`（机器钉值 7 domains / 42 commands）。奖励物品界面的单项按钮只能委托父时间轴共享 `领取单项`，单项/一键都采用 assets+XP+奖励列表 snapshot、dirty-before-one-shot、false/throw exact restore；
平板基建采用 assets+等级 snapshot，先复原领域等级再返还玩家资产。两个独立 XFL 分别 direct publish/VerifySwf，asLoader 另跑 publish；commit 后的埋点、音效、提示、UI/场景重建、响应与 Achievement overlay/stringify/socket 均须隔离。

### 地图 loot 的 break / reservation 与 recovery ledger 合同

地图 loot 行中「无 reservation 的 break」精确指正在破碎的 exact target 没有 reservation/authority；同 target 必须拦截重复奖励，另一 target 的合法 authored break 继续 direct drop，unsupported shape 始终 fail-closed。
自动故障矩阵还必须覆盖 routed open ACK 的 `queued / definite_rejection / definite_no_send / delivery_uncertain` 四分、raw Coordinator ACK 精确键集与 MessageRouter `callId` 注入、delivery-uncertain 对当前 socket source 的强制 detach/exact-attempt proof，以及 SUSPENDED/COMMIT_PENDING 下同箱与另一箱 break 对照。
recovery ledger 的确定性回归固定验证：8 条稳定 proof 仍允许一次 admission 且 strict accepted 会剪枝解锁；明确 rejection/no-send 不消耗 reserve，拒绝后迟到 socket 也不能伪造当前 attempt；第 9 条 proof 写入后新 open fail-closed，Host admission fence 对应的旧 exact query 成功时 retain-only、删除其余未接纳候选并恢复可重开。
另以 AS2 源码静态契约固定 local socket capture、三处 current-source guard、identity-guarded retirement 与统一 `onSocketClose` handoff，确保 retired source 的迟到 `onData/onClose` 不具备推进路径。它们都是确定性自动门，不增加真人战斗场景；静态契约不能冒充已直接注入旧 socket 回调的动态测试。

### SaveManager API 分层（R1）门

**调用点扫描门**：改 SaveManager 存盘入口（`_root.强制存盘` / `_root.自动存盘` / `_root.本地存盘` / 直调 `flushNow()` / XFL 帧脚本对应调用）时必跑 `node tools/save-api-migration/check-callsites.js`；R1 步骤 10–14 起另有 `node tools/save-api-migration/test-callsites.js`（文本记录 17/17，待核：阈值来源为历史文本，未找到当前机器真源）。
manifest 为 `tools/save-api-migration/callsites.v1.json`（当前机器真值：38 物理点 / 32 逻辑点 = strict 18 + debounce 14；scripts 旧入口 forceSave/directFlushNow/autoSave/localSave 已全部归零，XFL 旧入口亦归零；文本中「36 物理点 / 17 strict + 15 debounce」「37 物理点 / 32 逻辑点」与「步骤 10/11/12/13 另轮施工」为历史口径，见归档）。发布前后对照追加 `--verify-swf-hashes`；
口径、paired 副本与 liveState 取信规则见 [tools/save-api-migration/README.md](../tools/save-api-migration/README.md)；Slice 2+ 迁移改旧入口文本必须同轮更新 manifest，否则本门以未命中/数量不足拒绝。所选 XFL 经 CS6 fresh publish 后以 `python -X utf8 tools/save-api-migration/check-published-scripts.py <swf> <export-dir>` 对 FFDec 输出核对可达 API/reason。

**四层语义合同（Slice 1–4 起，未迁调用点部分仍有效）**：改 `SaveManager.as` / `通信_lsy_原版存档系统.as` / `SaveManagerTest.as` 后必跑 `scripts/run-character-build-tests.ps1` 与 `node tools/save-api-migration/check-callsites.js`。
canonical dirty：`SaveManager.markDirty()` 为唯一置位入口并双镜像 `_root.存档系统.dirtyMark`，`hasPendingChanges()` 已补 `_settingsMigrationPending` 与 `KeyManager.hasPendingKeySettingsMigration()`，三处悬空 `存档系统.markDirty()` 由 `installSaveApiShims()` 接通为真 API。
四层 API：`_root.存档系统.markDirty / requestSave / flushDurableNow / flushBeforeTransition`；`requestSave` 返回 Void、全局单 300ms trailing timer、reason 只接受与 `callsites.v1.json` 同源的注册 ID（transition 仅 `safe_exit / stage.return_base / character_creation.start_tutorial` 三个 allowlist，越表 fail-closed）；
`flushNow / flushDurableNow / flushBeforeTransition` 分别进入同一私有内核 `_strictFlushCore`，静态门禁止 public 级联（防 ingress 双计数）；`true` 仍仅代表本地 `SharedObject.flush()===true`，无 dirty 早退、无 strict 合并；成功 strict fence 才吸收 pending request，timer 遇 `_saveInFlight` 重挂不丢弃，wheel 边界守卫吞异常（sv:3 + 诊断保留 dirty，不 rethrow）。
语义桶 `_saveApiStats`：6 ingress / 6 request disposition / 5 full origin / 3 家族×5 strict outcome / 5 flush lane×4（lane 合计恒等于物理 flushAttempt）/ 固定 reason 桶 + reasonUnregistered + 测试有界 trace，物理八分桶名称与含义不变。

**步骤 6→9 调用点迁移合同**：D1/D2（商城系统_WebView）迁 `requestSave("shop.panel_close")` 与 canonical `markDirty()` + `requestSave("shop.cart_edit")`；B3/B4/B5（GameSettingsPanelService executeApply/executeSave、CharacterBuildService invokeBoolean 桥 fallback）迁 `flushDurableNow`；A1/A6/B2（safeExit、返回基地、建角）迁 `flushBeforeTransition`；
A4/A5/A3 三 wrapper（ItemUse `flushSave`、Loot `flushSaveVerified(reason)`、PAT `performStrongSave`）内部改调 `flushDurableNow`，wrapper 形状/失败语义不变。扫描器扩展四层 API family（apiMarkDirty/apiRequestSave/apiFlushDurableNow/apiFlushBeforeTransition，shim 与类内直调双形态匹配 + 定义宿主排除），`danglingMarkDirty` 区段更名 `canonicalMarkDirty`。
受影响测试 double 同函数镜像（Loot/KShop/Npc/StageRunSession 四套）。

### 测试反馈修复专项合同（2026-08-30 起现役）

奖励/任务跑 `scripts/run-map-loot-tests.ps1`（机器钉值见 [Loot / 关卡结算 runner](#suite-loot)）；存档/药剂与 PAT 用各自 focused runner（机器钉值见上）。
合同固定 durable settlement/receipt restore（资产 manifest/count 精确递减，suspend/resume 只允许 revision 单调跳号）、Loot v2 `targetContainerId="自动"` + loot/背包/药剂栏三快照、`drugLoadout.v3` 最近耗尽原槽、dynamic `modSlotCapacity` 与外部前台零抢焦；同名多 generation 歧义必须 `stale_stage_rejected`。
2026-09-19 维护者通过 #72 收口了直播+QQ 抢焦、战斗空调制关闭、通关后立刻前往交付、领取后重启继续；槽位血瓶三来源回原槽由 #71 同日收口。上述结果仅证明 08-30 测试反馈增量的限定现场旅程，不能代签原始焦点事故的根因、输入/WebView 专项或完整产品 `standard_entry_verified`；后者仍按各自契约维护。

### 装备调制 live Gate（PG-TUNE-PREVIEW / PG-TUNE-E2E）

触及 Equipment Tuning Host/Web/AS2 的 opener、preview/commit/reconcile、诊断、运行身份或持久化合同，或声称相关玩家反馈已关闭时，除自动门外必须先以不带 `--shutdown` 的 exact `node tools/equipment-tuning/run-unattended.js --seed-slot <显式源槽> [--candidate-root <exact candidate>]` 取得 `snapshot_gate_reached` 报告；
seed-time SHA 不得被启动写回覆盖，只有同 attempt 严格 `start < handoff < title-frame < Archive <= snapshot` 且 `startup_normalization.v1` 窄语义、角色/等级、BigInt 文件身份与稳定窗全部闭合，才可建立 post-snapshot baseline；旧 report 一律作废。
`PG-TUNE-PREVIEW` 用 `node tools/equipment-tuning/verify-journey.js --open-report <report>`，只在 fresh interaction watermark 之后真实 safe-mode 点击且完整 runtime identity 前后复验后输出 `preview_verified`，不得外推 commit；
`PG-TUNE-E2E` 用 `node tools/equipment-tuning/verify-commit-journey.js --open-report <report>`，只接受 opener 产出的 `cf7_agent_equipment_tuning` clone，要求 computer-use 分离候选/提交两动作、完整 runtime identity 前后复验、全程句柄绑定 clone guard、同 tuple Web/Host transaction + new-lease refresh、
最终 Archive char count/exact clone receipt 与 clone item/`lastSaved` 实变、旧 PID 退出、重启前零 Core 且新身份/ready/readback 三阶段仅允许同一新 PID、同 runtime 无 reseed fresh 重启及同槽 `stateRef` 读回，最终 receipt 必须为 `e2e_verified`；
进程退出后只允许从 canonical/non-reparse 的同一 `launcher.log` 水位补采 archive 行以避免 HTTP 先停造成漏证；该 Gate 不绑定 SAFEEXIT arm/done/`EXIT_CONFIRM`，固定 `safeExitUiJourneyVerified=false`，不得冒写为 SAFEEXIT UI 旅程已验收。verifier 不发送业务/存盘命令、在读取前拒绝 canonical opener report 目录外路径、不读写玩家档。正常成功只签 `reconcileDisposition=not_required`；
未知写入的真实 reconcile 故障旅程仍由 A2 单独注入验收，缺失时不得写成已覆盖。无人值守 opener、纯离线 `--check`、半程/failed receipt 或 isolated candidate 均不能替代上述 live Gate、promotion、标准入口或 GUI 验收；本地 JSON 无 Host 签名/MAC，不能宣称抵御恶意同用户进程。

### 无人值守迁移测试与受控进档

若改动后的行为无法被现有 harness 或 QA 覆盖，同轮补测试入口，不把「靠人工记得点开」当作默认收尾。无人值守迁移测试允许用窄化 `agent_control` 动作绕过旧 AS2 按钮探索，但必须固定专用 `cf7_agent_*` 克隆槽、匹配当前 attempt/save runtime ack，并继续走正式 AS2 opener→`panel_request`→Host 白名单→Web/领域协议；禁止直接 `PanelHost.OpenPanel`、`Panels.open` 或用 `/console` 调业务 preview/commit。
受控进档顺序固定为：记录本次 `start` 日志水位 → 在该水位后同时取得 fresh handoff 与真实 `[LaunchFlow] bootstrap_reveal_ready: Flash reveal cleared`（watchdog 事件不计，缺失报 `title_frame_not_observed`）→ 仅调用一次 `agentEnterResolvedSave()` → helper fail-closed 调 `_root.notifyGameEntered()`，同包发送 attempt-bound `s:1|ga:<_bootstrapAttemptId>`，
再以 `gotoAndStop` 进入「读盘」帧 → Host 排除 legacy 无 `ga` 包、将 receipt exact 绑定当前 attempt，且只有该 receipt 才设 `gameEnteredObserved=true` → runtime ready。
每次 `start` 与后续 `s:0` 都重新加锁；裸 `s:1`、helper 已调用、watchdog 或 `revealPerformed` 均非成功证据。直达证据只替代导航成本，不能替代真实入口专项：每个旧/新入口限时 60–90 秒或两次截图，失败即留证停止；写 E2E 仍须 commit 后存盘、完全重启回读。

**KShop 旧存档只读真机门**：先跑 `node tools/workbench-live-e2e/kshop-legacy-readback.self-test.js`（文本现役 7/7，待核），再使用 `node tools/workbench-live-e2e/kshop-legacy-readback.js --candidate-root <candidate> --seed-slot <只读真实槽> --slot <专用 cf7_agent_* 槽> --expected-catalog-count 227 --allow-read-only-live-seed`。
入口必须逐字节 clone seed，在真实 WebView2 中由物理 GUI 输入完成同进程 `打开→关闭→重开→关闭`，再以同一 candidate/clone 新 PID 重启完成第三次读回；close 只接受命中可见 header 的 `isTrusted` 左键，或 exact close request 后紧邻、哈希连续且面板已隐藏的 Host `panel_esc`，后者须标记 `browserIsTrusted:false / physicalInputAttestation:false`，不得冒充 DOM 物理点击。
三次都要固定 catalog、K 点和历史待领取投影一致，并同时证明原始 save JSON SHA-256/字节不变、clone 的 `shop` 与 K 点不变。该门禁止 `saveCart/checkout*/claim`，不替代带真实购买、SAFEEXIT 和 Inventory poststate 的写旅程。

**Arena P5 权威真机门**：先跑 `node tools/workbench-live-e2e/arena-live-e2e.self-test.js`，再对同一最终 candidate 运行 `node tools/workbench-live-e2e/arena-live-e2e.js --candidate-root <candidate> --allow-read-only-live-seed`。
固定 `agent_control openArena` 只可携当前专用槽和 attempt，Host 只发无参 `openArenaForAgent`，AS2 固定生成 `stage_select_arena_redirect` / `difficulty=冒险` 的生产 `panel_request`。正向关闭、选卡、确认都用绑定 candidate PID/页面的 CDP Input 命中可见目标，并由被动观察器证明 DOM `isTrusted=true`；这属于 candidate-page browser input，不是物理设备证明。
唯一直接 `Bridge.send` 只准发送重开后旧 session cardId 的无写 `preview` 负例，必须 `stale_authority` 且 Flash dispatch 增量为 0，禁止借此调用成功 preview/enter。报告还必须绑定 source digest、Web 无经济字段、Host 重建命令、AS2 接受值、截图、seed 逐字节不变与受信 shutdown。

### A5 材料商店旅程与存档闭包

**A5 存档闭包（文本现役 277/277，取代旧 251/251、266/266 与 274/274 数量，含 archive/restart 字节等值；待核：阈值来源为历史文本，未找到当前机器真源）**：baseline/archive/restart 各自保留原始字节与 SHA，target 逐字节绑定 restart；跨重启只忽略根 `lastSaved` 并排序四个登记为集合的来源缓存数组，其他漂移仍拒绝。
ignored-output v3 只增加 preparation 绑定的 seed/target/recovery 三槽、exact marker、三份 exact log 与两棵 exact WebView2 userdata 根；generated 0B 仍封存 SHA，near prefix、额外 log、foreign save 与 offline recovery receipt 继续拒绝，v2 历史收据仍按原 schema 验证。
static gate 在 release ignored-output inventory 验证后，仅按 sealed browser-module inventory 将 canonical Playwright 文件同步投影到 materialized Worktree，并只临时替换 inventory-bound crafting dev harness fixture；candidate 产品 modules/assets 不替换。
成功、browser failure 或 callback exception 都须在返回前恢复 fixture、移除 Playwright 投影，pre-existing destination、copy drift 与 cleanup residue 一律 fail closed。

**A5 Agent Runtime key-only 旅程（现役口径，覆盖 v3/20 步与 v7）**：控制计划为 `workbench-live-e2e.material-shop.control-plan.v4`，共 1024 步；首个 `panel.open materials` 后，材料段只通过项目 Agent Runtime 的 `input.press_key` 执行 Tab / 方向键 / Enter / Escape，覆盖默认档案、排序菜单、分类树、网格和详情动作。
固定从「全部材料」焦点进入「军用帆布」，并把 `{category:"属性武器",recipeIndex:0,productName:"二阶复合防御组件"}` 的「查看配方」终态交给独立 PNG reviewer；随后 Escape、结构化重开 materials，再继续既有且唯一的「食用油」 `quantity=1` 购买和跨重启读回。current raw evidence 为 `workbench-live-e2e.material-shop.journey-evidence.v9`；
verifier 必须将 16 个 key intent 全局唯一且按执行顺序逐个绑定 trusted action receipt 与同 session ledger 的 method/arguments/result，并把 exact key-sequence digest 与 recipe capture digest 写入 evidence。`purchase-authorization.v2` 必须同时绑定 exact runId、applicabilitySha256 与 `{厨师,24,食用油}`；generic/冻结 t1903 v1 只能按各自 legacy 路径回放。
close dispatch 不能单独代签关闭：recipe Escape 与 ordinary close 都必须在同一 first session 紧邻后继 `panel.open materials`，并绑定该 open 后首个 visible WebOverlay WGC observation、content.read 与 successor PNG；Host stable-idle admission 是旧 tracked visual 已关闭的机器栅栏。截图不能代签键盘、DOM focus、close provenance、重开或 recipe tuple 的动作 provenance；
缺 receipt、跨 step/session 复用、顺序/ledger/capture/read 漂移或 capture-only 伪造一律失败。离线专项门追加 `node tools/workbench-live-e2e/material-shop/test-agent-runtime-keyboard-recipe-evidence.js` 与 `node tools/workbench-live-e2e/material-shop/test-agent-runtime-authorization-binding.js`，仍不等于真实 GUI/candidate/E2E。

**A5 visible-only review（现役 v4，覆盖 v3 口径）**：新 Agent review request 固定为 `workbench-live-e2e.material-shop.review-request.v4`；v3 只保留为显式 legacy 非 Agent replay，不得重解释。
先跑 `node tools/workbench-live-e2e/material-shop/test-visible-review-contract.js`：v4 的 14 个 claim 只能陈述单帧 PNG 可判断的可见终态，所有 claim step 必须是 `requiresCapture=true`，且 step 并集逐一精确覆盖 16 张 Agent capture，不得遗漏、重复或混入 foreign step。PNG reviewer 不代签 native/runtime、指针/键盘/输入、重启、关窗转场、持久化或 shutdown provenance；
这些仍由 raw、trusted-runner 与 release closure 分层验证。`reachable_enemy_and_shop_portraits_visible` 不可删除；任一可见敌人或商店头像缺失/破图必须判 `fail`。`review-receipt.v1` 继续要求全部 claim 为 `pass`，所以存在破图的运行不得 accepted，也不得进入 `e2e_verified`。
current Agent raw replay 从 v9 起只记录 portrait capture 存在与 `pending_independent_visible_png_review`，不得写 enemy/shop resolved；v6 仅按 exact t1903 runId + plan/evidence SHA 保留历史字节读取，旧 resolved 字段只按 capture-presence 解释且不能新签。专项门为 `node tools/workbench-live-e2e/material-shop/test-agent-runtime-portrait-evidence.js`；
t1903 v4 release 另绑定旧 current-program closure，程序漂移后不声称可 full replay，仍无 acceptance/review receipt。reviewer 只可签「军用帆布默认档案详情可见」「exact 配方终态可见」「重开后的材料档案可见」等单帧终态，不得在 claim id 或陈述中夹带 focus、keyboard、Escape/close、reopen 或 restart 已发生的推断；`materials_recipe_jump` 是 exact recipe PNG 的唯一 raw capture ref；
`recipe_escape_close` 仍先抓同一可见终态再发 Escape，关闭结果由 raw successor fence 而非该 PNG 单独证明。

**材料→NPCShop A5 候选旅程门**：离线先跑 `node tools/workbench-live-e2e/material-shop/self-test.js`（文本现役计数见上，待核；含 Agent Runtime v3 正负例、seed-audit 特殊清理恢复与 pre-control failure discard 临时 Worktree 事务）与 `node tools/workbench-live-e2e/material-shop/verify-run.js --check`。
新运行只走 [material-shop/README.md](../tools/workbench-live-e2e/material-shop/README.md) 的 `prepare.js --agent-runtime-jsonl --authorize-quantity-one-purchase` → materialize/BuildOnly → 项目 trusted JSONL/WGC + guarded input → raw verify → 独立可见 PNG review/accept → exact worktree release；
structured opener 固定 `panel.open materials`，首段 EOF trusted shutdown 后封存 archive，再以 fresh trusted runner 重启读回，末段 close 后 EOF final shutdown。review 绑定两段 completion/transcript/ledger hash 与 Agent capture receipts；
release 必须同时验证 `trusted_runner_persistence_shutdown`、`restart_candidate/readback/close`、`trusted_runner_final_shutdown`、两段 clean completion 及 archive/restart 字节等值，不以 admission、SAFEEXIT、exit-confirm、supported-shutdown、CDP 或 passive Playwright/Host log 代签。
v2 Computer Use 路径仅用于已有证据 `legacy replay` 与登记恢复，不再作为新 live admission。BuildOnly 仍固定 `resources/automation/dev.ps1 -ForceBuild -BuildOnly -CandidateLeaf a5`；clone/lock/recovery、canonical fixture authority binding、operation lease、commit 后 recovery blocker 与 exact worktree removal 边界不变。current-data applicability 必须机器重抓；
文本记录当时为 224 材料、35 店、104 occurrence/101 unique、4 seed×104=416 且 locked/max 均 `not_applicable_current_data`（待核：以机器重抓为准），只允许 unlocked quantity-one purchase 作为必跑 live 路由。self-test 与 `verify-run --check` 都是离线门，不产生 `candidate_built`、`CANDIDATE_CAPTURED`、`e2e_verified` 或部署声明；只有独立 acceptance 才能产 `e2e_verified / NOT_DEPLOYED`。

### Reward 未知写与 O1 观测

Reward 未知写只按 `rootOperationId` exact query，不允许 projection 猜测；O1 仅以精确环境值 `1` 启用，无 retry/watchdog/修复。Reward/O1 的 runner 入口见 [奖励、礼包与统一暂存](#suite-reward)。

<a id="stage-input"></a>
## 关卡、输入与战斗

### 战斗地图绕行、复活与焦点门

战斗/胜负结算中地图必须保持可读，但 `navigate/open_stage_select` 显示 lifecycle lock 并零发送；选关、任务/竞技场/外交/legacy/new-character 等入口统一先取得 `StageRunSession` exact reservation。`_root.返回基地` 的可选投影异常不阻断淡出，淡出失败回滚转场 globals 且可重试，成功才清 manager/battle；`_root.关卡结束` 的视觉异常不阻断真实 `FinishStage` 恰一次。
NativeHud down 绑定 exact action/revision，suspend/hide/capture loss/外放均取消；Panel close 只有 close 起点与恢复前两次 live foreground 都属于 CF7 才恢复 Flash。有效 `stage_settlement` 零奖励报告可 suspend/reopen，`map_chest` 仍拒绝。
自动门固定为 fresh map-loot、character-build、player-manual-input、asLoader publish/function-size、Launcher 全量、Map/Loot/Stage Select/Tasks/Panel contracts、Workbench audit 与文档治理。真人焦点/复活观感验收结论与部署边界见归档；部署后只有 supply-chain、根 bootstrap `--verify-only` 与 post-promotion Audit 证据时，不称本功能业务 `standard_entry_verified`。

### 打击数字（C# 原生化）跨栈门

AS2 只发送逐段结算事实，C# `HitNumberRuntime` / `HitNumberOverlay` 是唯一 reducer、布局与绘制路径；V8/Flash renderer、旧 `_root.是否打击数字特效` 与 `_root.同屏打击数字特效上限` 不得恢复为 fallback。
改解析、聚合、颜色、布局、overlay、Host 偏好或设置 Web 时，至少运行 Hit Number focused（文本门槛 97/97，待核：阈值来源为历史文本，未找到当前机器真源）、Settings Host/Web（20/20、18/18，待核）、Launcher 全量与视觉 harness [`tools/hit-number-visual-harness/run.ps1`](../tools/hit-number-visual-harness/README.md)；
追加 `scripts/run-hit-number-tests.ps1`（机器钉死 9/9）、`scripts/run-settings-tests.ps1`（机器钉死 47/47）、asLoader publish 和真实 candidate。五状态固定为 `off / balanced / total / classic / detail`，有限上限按 Burst 原子裁剪，`0` 才显式无限，屏外余量剔除始终保留；精确历史独立进入 32,768 段环形账本，只在暂停态 Web 设置按需分页。
打击数字视觉门必须复用生产 tight-region renderer，覆盖 26 图、review sheet、两段视频、五状态、balanced 不绘制目标箭头且 detail/total 保留短距归属标记、目标锚定与同目标三 Burst 上限、有限 detail 每目标最新六行、六目标/近邻交错归属、120 段无限制、五位数带属性逐发边界、四模式 canonical 同输入 11 色板/语义全集、balanced/total 最新色→贡献主体色、非 MISS 零伤来源色、属性/粉碎分槽、精确状态数值、最新目标 Z-top、23/24/25 原子边界、屏外剔除、经典/总伤与平衡同字号基准，
以及 1200 段/秒和固定 32,768 段环形账本溢出后的资源稳定；
中心样本提交 surface 外沿必须零非透明像素，精确历史只从暂停态 Web 设置按需分页物化，不占用 `Alt` 或其他战斗键。真机继续覆盖高 hit 下的目标归属与打击感、设置内对账日志、四色板/全语义、total 与 balanced 瞬态闪色/回落、状态比例/计数追赶、零伤、逐发长值、`Alt` 喷气背包不受影响、边缘/屏外、reset/断连、五状态、24/0 与设置后立即重排；合成门不代签真机、candidate、promotion 或标准入口。

### AS2 战斗与输入 runner

按 [Flash 编译核心](#flash-core) 三层先选 `-Target publish|test|main`。

- 托管长枪/装扮引用：`scripts/run-managed-longgun-tests.ps1`（机器钉死 ManagedLongGun 126/126；并须同时取得 DressupReferenceManager 70/70（待核）、EventBus `All tests completed`、fresh trace/output/errors、Compiler 0/0、32K retry 0）。新增 attach 相位合同固定真实 loader 返回栈只校验 placement/exact registration/initObject 槽身份，资源计划在 Dressup/Extra/Buff 后消费；
  generic 非人形允许 MP 字段双缺省，T800 `hasDressup` 固定合法 `0/0`；spawn 满 HP、preserve 绝对资源、upgrade 满 HP 保 MP，并继续覆盖同步 null/throw/身份错误时保留旧单位。真人先后发现的全宠首次出战 `deploy_failed` 与「休息后单位消失但 flag 回滚」均已明确推翻旧同步 mock 的业务通过解释；退场现对已确认由 `gameworld.attachMovie` 动态创建的单位只发一次 bare `removeMovieClip`，以原生请求受理作为提交边界；禁止用同栈 `_parent` 或父级软别名回滚已经发出的删除。
  现役 `delete/world_adopt` 分别只撤目标 slot、只部署新 slot，禁止同栈全场 remove 后按旧 canonical 名全量 attach。
- HP/击溃/护盾/冲击衰减：`scripts/run-combat-hp-impact-tests.ps1`（机器钉死 ToughnessVulnerabilityPipelineTest `passed=159 failed=0`；文本 153/153、140/140 为历史）。settlement 门固定普通/联弹全段 MISS 只保留数字，不发布 hit/kill/death/enemyKilled，也不触发仇恨、翻面、血效、血条或击中特效；
  `DamageResult.NULL` 的旧几何命中合同保持：小跳/闪现等无敌期 `DamageResult.NULL` 继续允许几何命中 FX，但 `ImpactStateHandler` 必须零冲击/位移/状态副作用，不得重置 `lastHitTime` 或韧性恢复基线。正常 actual 热路必须内联分类，不得新增 `DamageResult` 静态分类调用、`ActionTry` 或临时对象分配；极低频 resolved MISS 仍可能触发护盾 `absorbDamage(0)`/回充延迟重置，作为性能优先的显式注释兼容误差，不列入拒收门。
- 玩家手动输入/冷却：`powershell -ExecutionPolicy Bypass -File scripts/run-player-manual-input-tests.ps1 -TimeoutSeconds 240`，机器钉死 `LongGunSubWeaponCoreTest` 486/486 + `ManualCooldownServiceTest` 57/57 + `DrugInputServiceTest` 58/58 + `KeyManagerMigrationTest` 14/14，覆盖 12+4+1 通道、毫秒取整/拒绝重入、暂停/跨场景调度、缺 renderer/rebind、按住等冷却、
  战技共享/副武器绕过、死亡/空格/零数量/最后一瓶/同帧多药键/旧第 5 格隔离，以及存档系统缺失时首写前失败、ItemRemoved listener fault 后的精确 loss、索引/EventBus/事务恢复与下一独立扣药，再发布 `asLoader.swf`；
  若改 `flashswf/UI/玩家信息界面/LIBRARY`，还须独立发布该 XFL、FFDec 检索关键脚本并真机核对键位/动画/扣药。

- 改 `StageEvent.Sound` 归一化或播放时追加 `powershell -ExecutionPolicy Bypass -File tools/test-stage-event-sound.ps1`（文本记录 11/11，待核）。
- 装备进阶 preview 必须以玩家实际口径输出 `fireRate` 与 `floor(500/impact)`，不得显示 raw `interval` 或倒置冲击力；定向门为 `node tools/test-equipment-tuning-model.js`、三视口 `node tools/run-equipment-tuning-harness.js` 与 `scripts/run-equipment-tuning-tests.ps1`（机器钉值见 [库存、背包与批量转移](#suite-inventory)）。
- 改共享输入/装填另跑手动输入 runner；改 171 开火接线另跑武器动画 runner（见 [套装与武器专项](#suite-equipment-set)）。

### 手雷/药剂堆叠与无目标背包总览门

fresh open 必须发送无 selector + `candidateScope=backpack`；Host/Web exact 边界拒绝双 selector、无目标 `compatible`、多余键、非 exact `target:{kind:"backpack"}` 及误分类行，AS2 独立拒绝双 selector、无目标 `compatible` 与非法 scope，并只生成 exact backpack target。browser 必须覆盖总览中装备/药剂的权威拖拽落点、其他物品只读阻断、点槽只进兼容筛选，且零新增「选物品后点槽即穿戴」快速模式。
AS2 另必须覆盖手雷/药剂同名装入 merge、异名 swap、卸下 merge-first、满包同名堆、rollback 与 `ItemUtil.acquire` 满包补入已装 exact ref。

### 屏外尸体与场景碰撞专项门

**屏外尸体保留专项门**：改 `DeathEffectRenderer` 离屏策略、`保留屏外尸体` 实例参数或黑铁会总堂第二图火凤验收配置时，先跑 `powershell -ExecutionPolicy Bypass -File tools/test-offscreen-corpse-retention.ps1`；再跑 `powershell -ExecutionPolicy Bypass -File scripts/run-offscreen-corpse-retention-tests.ps1 -SkipCompile` 验证 tracked suite/runner/BOM/恢复机制。
需要 Flash 行为证据时去掉 `-SkipCompile`，只接受专用 runId 包围的 `DeathEffectRendererTest` 15/15、7/7 cases、0 failed（机器钉死 15）与本轮 Compiler Errors 0/0；必须覆盖未标记屏外单位仍跳过、标记单位普通/旋转入口实际写入 `BitmapData`、同步 draw 后恢复隐藏状态、全局尸体开关优先。静态门或 `-SkipCompile` 不能声称 Flash 编译通过。

**SceneCollisionManager 专项门**：改场景碰撞来源、重绘或卸载顺序时，先跑 `powershell -ExecutionPolicy Bypass -File tools/test-scene-collision-manager.ps1`；再跑 `powershell -ExecutionPolicy Bypass -File scripts/run-scene-collision-manager-tests.ps1 -SkipCompile` 验证 tracked suite/runner/BOM/恢复机制。
需要行为证据时去掉 `-SkipCompile`，只接受专用 runId 包围的 `SceneCollisionManagerTest` 21/21、4/4 cases、0 failed（机器钉死 21）与本轮 Compiler Errors 0/0；静态门或 `-SkipCompile` 不能声称 Flash 编译通过。

### 限时关卡 TimePool 回归门

TimePool 改动必须同时覆盖 XML 全量配置、AS2 连续/重入/重叠/暂停/同帧优先/清理、Launcher `T` 投影、Launcher 全量、Flash CS6 fresh publish/Compiler、runtime v2 与 production policy。
先跑 `powershell -File tools/validate-stage-time-pools.ps1`（文本基线 configured=3 / pools=3 / refs=9，待核）、`powershell -File scripts/run-stage-time-pool-tests.ps1`（机器钉死 46/46）、Launcher `XmlSocketStageTimerTests` 与 fresh `scripts/compile_test.ps1 -Target publish`；静态、Mock、Compiler 证据不代签真实关卡 HUD 与手感。

### 关卡结果/结算与复活按钮

关卡结果/结算改动另跑 `scripts/run-map-loot-tests.ps1`、`scripts/run-settings-tests.ps1`、StageOutcome/RightContext Host focused、Launcher 全量，以及 Loot browser/state/lazy/doll/panel-contract、Stage Select、Tasks、Settings Web 回归。复活双按钮的操作内容宽度固定为 `64/48` 逻辑像素（`4` 间距与 `4` 右内缩另计）；
库存移到左侧状态区，按「持有 + 16px 复活币图标 + 剩余库存｜复活｜回基地」分段绘制，图标解析失败降级为「复活币 + 剩余库存」。动作与库存必须 `NoWrap + LineLimit`，`2.1万` 使用常规字号；更长合法库存依次缩至 14px/12px 图标与紧凑字体，只有最终仍溢出时才去掉缩写小数位，绘制与命中共享同一动作矩形。精确 publish `scripts/asLoader.swf` 后仍须 fresh Compiler/Output/FFDec。

<a id="derived"></a>
## 派生物与生成输入

**通则**：生成源/生成器/sidecar、脚本 bundle、头像图标、材料索引、任务目录或运行依赖变化时，从真源再生并执行对应 `--check`，验证 source→generator→output→manifest 的一致性；不得手补派生文件掩盖 stale。检查 BOM/EOL/raw-byte、大小写和排序 oracle、Git tracked/disk 的精确集合与禁止多余项。计数/hash 以当前机器产物为准，不复用历史通过数；尚无机器真源的活跃阈值先保留并标待核，不能直接删掉。游戏产物变化执行真实消费者检查；
进入正式部署闭包才追加 runtime（见 [正式 runtime 发布](#runtime)），不将所有派生提交视为独立发布请求。

各领域派生门索引（细节归各领域章节，不重复复制）：

- 武器 balance roundtrip/sync：`npm run roundtrip-check`、`npm run balance-sync -- --check`、`npm run balance-check`（工作目录 `tools/cf7-balance-tool`），见 [XML、数值与游戏内容](#data)。
- Arena 派生链同步门（P5 current）：`derive-arena-meta-teams.js --check` 对 `data/arena/meta_teams.json` 与 `launcher/web/modules/arena-meta-rosters.js` 做 exact 字节比较，`derive-arena-factions.js --check` 同样校验 `data/arena/arena_factions.json` → `launcher/web/modules/arena-factions.js`；
  release prepare 按依赖顺序重建它们及 custom presets/unit catalog/parameter presets，release policy 与 runtime-inputs v2 将真源、生成器和输出纳入闭包。触及 `data/stages/**` 或 faction JSON 后先重跑对应生成器、审核 tracked 差量，再跑全部 `--check` 与 Arena harness；任何 stale/missing 输出必须非零失败，生成物禁止手改。
- 任务/成就目录派生（build Step 1e/1f）：`node tools/derive-task-catalog.js`、`node tools/test-derive-task-conditions.js`、`node tools/derive-achievement-catalog.js --check`，见 [任务、成就与调度板](#suite-tasks)。
- 选关 preview 派生：`node tools/derive-stage-select-previews.js [--write]`；静态情报派生 `python tools/derive-stage-select-intel.py --check`，见 [选关、启动前门与关卡会话](#suite-stage)。
- 地图 filter-fit preset 离线重算：`node tools/tune-map-filter-fit.js --write`，见 [地图面板与地图内容工作台](#suite-map)。
- 图标/纸娃娃/头像烘焙与 manifest 完整性：见 [美术与资产](#art)、[头像专项](#portrait)。
- 小游戏静态终态：`node launcher/tools/validate-minigame-final-state.js`，见 [小游戏](#suite-minigame)。
- 黑市影子目录：`node tools/derive-black-market-shadow-catalog.js --check`，见 [小游戏](#suite-minigame)。
- 情报 H5：`node tools/validate-intelligence-h5.js --strict`（Intelligence Panel 行，见 [领域 suite](#domain-suites) 触发清单）。

**A5 materialized 路径预算门**：`prepare` / `materialize` 必须在创建 run 目录、Git worktree 或候选前，以真实 canonical destination 遍历完整 sealed scope 的绝对物理路径。Launcher 未声明 `longPathAware`，所以 `<=259` 可用、`>=260` 必须拒绝，并报告最长 relative/absolute、投影长度与安全 runId 最大长度。文本记录：当前根下 13 字符 runId 的最长 shop portrait 为 259，14 字符为 260（待核：以专用离线门当前输出为准）；
专用离线门为 `node tools/workbench-live-e2e/material-shop/test-materialized-path-budget.js`。

<a id="art"></a>
## 美术与资产

**触发**：原生矢量/模型转绘、XFL/library、图标/纸娃娃、装备检视图。唯一可编辑源、坐标、比例、命名、action frame、library/linkage 与消费者一致性以 [art-asset-assembly.md](art-asset-assembly.md) 为准；本节只承载各资产的验证 runner 与固定门。
XFL/FLA 施工后跑 `python scripts/tools/xfl/audit.py <xfl>`、`python tools/linkage_scanner/scan_linkage.py --xml-only` 等三件套与 publish 判据见 [Flash 编译核心](#flash-core)。

### Icon Bake

必跑（每条独立执行）：

- `node --check launcher/web/modules/asset-timeline.js launcher/web/modules/icons.js tools/test-asset-timeline.js tools/test-icons-layered-periods.js`
- `python -m py_compile tools/bake-icons-offline.py tools/promote-icon-animation-candidates.py`
- `node tools/test-asset-timeline.js`
- `python tools/test-asset-timeline-export.py`
- `python tools/test-nested-animation-stop-semantics.py`
- `python tools/test-icon-animation-candidate-filter.py`
- `python tools/test-icon-animated-budget.py`
- `node tools/test-icons-layered-periods.js`
- `python tools/bake-icons-offline.py --scope all --resolve-only --report tmp/icon-bake-resolve-report.json`
- `python tools/bake-icons-offline.py --scope all --animation-structure-audit-only --ffdec-timeout-seconds 120 --report tmp/icon-animation-structure-audit.json`
- `python tools/bake-icons-offline.py --scope all --limit 5 --output-dir tmp/icon-bake-sample-icons --tmp-dir tmp/icon-bake-sample-ffdec --report tmp/icon-bake-sample-report.json --keep-tmp`
- `python tools/bake-icons-offline.py --scope all --limit 5 --export-animated-frames --output-dir tmp/icon-bake-anim-sample-icons --tmp-dir tmp/icon-bake-anim-sample-ffdec --report tmp/icon-bake-anim-sample-report.json`
- `python tools/bake-icons-offline.py --scope all --dry-run --report tmp/icon-bake-offline-dry-run-report.json`
- `python tools/audit-icon-layout-regressions.py --report tmp/icon-layout-regressions-before-restore.json`

**语义 f2 门**：纯 `stop();` 父级仍冻结为 `static-first-frame`；但 `item/item-tier` 若实际 `f2` 非透明且与 `f1` 可见像素不同，必须保留可由 `gotoAndStop(2)` 显式寻址的语义 `f2`，同时保持 `playback=static-first-frame / animated=false / frameCount=1`。该例外不得扩到 skill；重复帧、透明 f2 与仅透明像素 RGB 不同仍不得制造语义帧。
定向写入后必须核对 manifest f2、`_2.webp` 尺寸/Alpha、f1/f2 可见像素差异与重复 dry-run 幂等，不能仅凭 XFL 已补帧或 SWF 时间戳声称 Web 图标闭包完成。

**固定边界**：离线 FFDec 产物不承诺与 Flash Player 真机烘焙像素级一致；默认保护既有 `launcher/web/icons` PNG/WebP，大差异只记录 `layoutProtected` 并保留旧图；
正式写入前先审 `unresolvedSummary` / `unresolved[*].conflictSources` / `export_errors` / `missing_frame` / `layoutProtected` / `f1Profile` / `animationAudit`（源帧数、唯一帧、重复帧、连续 hold 可压缩量、`nestedAnimatedDescendantCount` / `nestedStoppedDescendantCount` / `sampleNestedDescendants`）；
结构摸底先审 `animationStructureCandidates` / `animationStructureParentStopNested` / `animationStructurePlainStop` / `animationStructureUnsupported` / `spriteGraphErrors[].error=swf_xml_timeout`，PNG/SVG/XML2SWF 超时则按对应 export error 的 `exitCode=124` 审；纯 `stop();` 父级应冻结为 `static-first-frame`，只有首帧内未停止的子 MovieClip 继续按局部动画处理；
`test-nested-animation-stop-semantics.py` 固定验证父级首帧 `stop();` 不会递归冻结未停止子 MovieClip。`--export-animated-frames` 会把父 symbol 自身真动图写成 `frames[]/timelineFrames[]`，也会把父首帧、stripped base 全透明、唯一自播放子 MovieClip 的图标写成 `playback=nested-animation` 全画布帧；
父第 1 帧直接挂一个或多个可动子层且层深度不交错时，写 `nestedAnimation.layers[]` 分层帧序列，检查 `nestedIconCanvas` / `nestedIconLayered` / `nestedIconCanvasUnsupported` / `nestedIconLayeredUnsupported` / `frame1Diff`，layered entry 可包含已烘焙进 PNG 的 `filters` 与自动校准 `offset` 元数据，
layer frame 应包含裁剪元数据 `cropX/cropY/cropWidth/cropHeight/canvasWidth/canvasHeight` 并在报告里记录 `nested_icon_layer_crop_*` 像素统计；
类似 `冰魄矿石` / `月之碎片` 应通过 layered 导出，明显偏离的候选仍应保守降级；复杂嵌套仍只审计不做 LCM 预合成。生产推广用 `--animation-candidates-only --animation-candidate-report tmp/icon-animation-structure-audit.json` 复用审计候选，配 `--animated-candidate-max-source-frames` 先挡掉超长周期，再用 `--name` 分批写入；
批量推进用 `tools/promote-icon-animation-candidates.py` 输出逐候选 `animated|visual-static|budget-static|unsupported-static|timeout` 汇总，候选失败不应污染已成功条目。Web 播放时间线统一由 `AssetTimeline` 处理 `timelineFrames[]` 优先级、`durationFrames/holdFrames`、重复帧去重判断与按 fps 选帧，layered 图标的动效判断必须把 crop 元数据纳入 identity；

导出端统一由 `asset_timeline_export.py` 处理 digest 去重、`duplicateOfFrame` 与连续 hold 压缩，PNG 写入使用无损 optimize。`--max-animated-icon-bytes` 用于单图标体积门槛，超预算记录 `animatedIconBudgetSkipped` 并回退静态首帧；视觉上只有同一 `uri + crop` 的多帧候选记录 `animatedVisualStaticDowngraded` 并回退静态首帧。
`Icons.resolve()` 是首帧 URL 入口，生产列表/格子图标应使用 `Icons.html()`，并用浏览器 harness 证明显式 `playback` 图标会自动切换 `timelineFrames[]|frames[] + durationFrames`、layered 图标会按层独立切帧且不生成组合帧、wrapper 尺寸与 error fallback 兼容 kshop/merc/arena/tasks、legacy `f1/f2` 不误播放；
`test-icons-layered-periods.js` 固定验证 5 帧与 7 帧图标子层按各自周期独立选帧、frame budget 是 12 而不是 35，同时验证单层 120 帧 layered 图标不依赖多层假设、裁剪 style 会随帧应用、同一 URI 但 crop 改变仍会播放；`Icons.applyIconToImage()` 对普通 PNG 序列动图会自动播放，对 layered entry 只做静态 fallback。只有确认接受 alpha 包围盒/质心偏移后才加 `--force-overwrite-existing`；
全量 `--scope all` 强制覆盖还必须显式加 `--allow-layout-regression-risk`，若出现偏移回归用 `tools/audit-icon-layout-regressions.py --restore` 从 Git 基线恢复 tracked PNG/WebP；若要保持既有 Flash 字节基线，继续用 Launcher 运行态 `BAKE` / `BAKE10` / `BAKE_SKILL`。

### Icon Normalize Guard

`python tools/test-icon-normalization.py`。静态离线路径用 alpha 内容边界模拟 AS2 `MovieClip.getBounds(mc)`；FFDec 外层 canvas 只允许在嵌套/分层动画父画布路径显式 `preserve_canvas=True`，避免全量烘焙把大画布武器图标缩小或裁掉。同门负责固定 source-aware 布局护栏：只有旧产物可见 RGBA（透明像素隐藏 RGB 归零）仍匹配 provenance、渲染配方不变且源 SWF digest + 新渲染 digest 同时改变才自动刷新；mtime 只审计、不授权；显式/授权刷新必须连微差真实落盘。

### 装备检视器全量离线人工验收

先跑 `node tools/build-equipment-inspector-review.js` 全量重建，再跑 `node tools/test-equipment-inspector-review.js` 与 `node tools/open-equipment-inspector-review.js --check`；人类用 `node tools/open-equipment-inspector-review.js` 打开。产物只写 `tmp/equipment-inspector-review/`，导出的 `equipment-inspector-review-decisions.json` 仅作 QA 证据。
固定 1197 条原始定义且不按 name 去重，稳定 ID=`sourceFile::name::同文件同名 occurrence`；文本冻结口径：2844 候选、1749 required=543 武器商品图+552 男防具+552 女防具+102 图标回退（3 弩+99 颈部），另锁 9 双刀、9 疾影、16 个实际 fallback 缺图（待核：阈值来源为历史文本，未找到当前机器真源）。33 个动态 required 分支必须逐个打开真实 production `EquipmentInspector` 并显式确认 `motionReviewed`，静态首帧、伪 DOM change、伪导入和未确认打开均不得签过。
`sourceDigest` 绑定 XML/代码/实际素材字节，`reviewDigest` 绑定候选图、关键构图指标、门与递归 motion 证据；opener 逐字节校验 2946 个 artifact 引用（待核），partial/stale/越界/缺失/哈希不符以及 page error/failed request 一律失败。

### Dressup Doll（纸娃娃）

必跑：

- `python tools/bake-dressup-offline.py --no-write`
- `python tools/bake-dressup-offline.py --export-assets --limit 5 --output-dir tmp/dressup-sample-out --tmp-dir tmp/dressup-sample-tmp`
- `python tools/normalize-dressup-timelines.py --dry-run`
- `node --check launcher/web/modules/asset-timeline.js launcher/web/modules/dressup-doll-renderer.js launcher/web/modules/dressup/dressup-panel.js launcher/web/modules/merc-panel.js tools/run-dressup-harness.js tools/run-merc-dressup-probe.js tools/test-asset-timeline.js tools/test-dressup-renderer-periods.js tools/t
  est-merc-panel-appearance-fallback.js`
- `node tools/test-asset-timeline.js`
- `python tools/test-asset-timeline-export.py`
- `python tools/test-nested-animation-stop-semantics.py`
- `python tools/test-dressup-manifest-integrity.py`
- `python tools/test-merc-dressup-coverage.py`
- `node tools/test-dressup-renderer-periods.js`
- `node tools/test-merc-panel-appearance-fallback.js`
- `node tools/run-dressup-harness.js --browser edge --sample animated`
- `node tools/run-dressup-harness.js --browser edge --sample nested`
- `node tools/run-dressup-harness.js --browser edge --sample nested-a`
- `node tools/run-dressup-harness.js --browser edge --skin-key "男变装-A兵团精致战术背心身体" --gender 男 --field 身体`
- `node tools/run-merc-dressup-probe.js --browser edge`

改 `DressupInitializer.updateDressupKeys`、`data/items` 装扮字段、`asset_source_map.xml`、或 `flashswf/UI/对话框界面` / `flashswf/arts/things0/LIBRARY/主角-男.xml` 主角模板/holder XFL 时，
重跑 `python tools/bake-dressup-offline.py --export-assets --export-missing-assets --prune-orphan-assets` 写 `launcher/web/assets/dressup/manifest.json + report.json + skins/*.png`；
若只需要规范化既有 PNG/manifest 的连续 hold，可先跑 `python tools/normalize-dressup-timelines.py` 补 `timelineFrames[] + durationFrames`，不重新调用 FFDec。

**固定合同**：离线映射必须保持 `auto_opposite_gender=0`：`opposite_gender_only` 保持 uncovered，由当前性别 holder 的 `basic` fallback 承担；人工 alias 仍允许，但每条必须显式登记 reason。battle rig 固定七种状态，并证明男女 `手雷站立` 各有且仅有一个真实 `手雷_装扮` holder。
检查 `metadataErrors=0` / `timelineScriptErrors=0` / `spriteGraphErrors=0` / `nestedLayerUnsupportedDescendants=0` 且所有 `skinKeys[*].frames[]` / `holders[*].basic.frames[]` / `nestedAnimation.layers[*].frames[]` 都有 `originX/originY`，否则 Canvas 注册点不可信。
`test-dressup-manifest-integrity.py` 固定检查真实 manifest 资源闭包、可导出 skinKey 均有 `export/frames`、`skins/*.png` 无孤儿文件、A 兵团背心父级冻结 + 子层播放、battle rig 状态/holder 字段闭包、`攻击模式` 条件可见性 `runtimeVariants.neutral`、matrix/origin 与压缩时间轴；
`test-merc-dressup-coverage.py` 固定检查全量 `data/merc/mercenaries.json` 装备、脸型、发型到 dressup manifest 的运行时闭包，并只允许已确认源素材缺失且 Flash 会回退 holder `基本款` 的少量身体件；`test-merc-panel-appearance-fallback.js` 固定验证佣兵头像 `face/hair` 归一化、`helmet=true` 压发，以及一次性头像截图必须等待 `pendingImages=0` 后才缓存。
报告语义：`staticStopSkinKeys` / `staticCollapsedSkinKeys` 表示父 sprite 首帧纯 `stop();` 已按 Flash 行为折叠父时间线；`nestedAnimationSkinKeys` 表示父级第一帧内仍有自播放子 MovieClip，Web 侧不能当普通静图或 LCM 全量合成；`conditionalVariantSkinKeys` / `conditionalVariantRemovedPlaceObjects` 表示导出器按 clipAction 的 `攻击模式` 可见性脚本生成 neutral 变体；
`exportedNestedLayerKeys/Frames` 表示已生成 stripped base + 子层独立帧；`nestedLayerCompositedDescendants` 表示由父层帧序列覆盖的后续帧挂载子 MovieClip；`duplicateFrameRefs` 用于确认重复播放帧已复用同一 PNG；纸娃娃压缩 key 必须包含 `uri/width/height/originX/originY`；
`timelineCompressedFrameRefs` / `timelineCompressionSamples` 用于确认连续重复帧已折叠为 `timelineFrames[] + durationFrames`；`animatedSkinKeys` 是父时间线自身需要播放的真实多帧。`--skin-key` 用于精确回归类似 A 兵团背心身体这种「父层 1 帧 + 子层飘带动效」的 skinKey，runner 会检查 keyMap/gender 命中、Canvas 非空、`ANIM` 状态和多帧 hash 变化；
`run-merc-dressup-probe.js` 用真实 `data/merc/mercenaries.json` 样本检查 `equips[].name -> manifest.items[name].fieldsByGender[gender]`、脸型/发型映射、helmet 压发、battle reference 截图、缺失部件和截图，Phase 0 覆盖差时不得推进正式 Team/Merc UI；真实导出后追加 Flash 基准截图对比，重点查 origin/matrix/fallback 基本款/头发表情帧；身体 holder 缺 linkage 应显示 `basic`，武器 holder 缺装扮应隐藏；

生产 Panel 入口走 `DRESSUP_TEST` / `web/modules/dressup/dev/panel-harness.html`。

**只读基线（文本冻结值，禁止测试重生成）**：dressup manifest/report 基线文本记录为 items 1292、skinKeys 2853、covered/export 2712、missing 141（`opposite_gender_only=135`、`exact_xml_without_as_linkage=3`、`no_matching_source=3`）、manual alias 9、auto opposite-gender alias 0、battle states 7、battle audit error 0；
佣兵闭包 resolved parts 3253、同性别 basic fallback parts 12、failures 0（待核：阈值来源为历史文本，manifest 由生成器维护，以当前产物为准；不运行测试重生成 manifest/report）。
dressup skins 体积审计由 `test-dressup-manifest-integrity.py` 内 `assert_skin_png_size_budget` 承担：单 PNG ≤512KiB（allowlist 仅 `skins/a8dfe0f8_1.png` 的 u235 全躯干真实导出，字节漂移即失败）、总量预算按文本记录为 157,341,573B（2026-08-10 实测 104,894,382B×1.5，待核：预算常量以脚本当前值为准）；
u235 的远古诛神头/胸/腿/鞋由 4 个 unit-scoped virtual item 精确绑定 10 个 source-map skinKey 与真实 PNG，手套由 `黄金骑士牙狼手套` 精确绑定 2 个远古手部 skinKey，禁止降级成普通诛神素材。

### 怪物 / 人形装备换皮参考包

必跑：

- `python -m py_compile tools/monster-reskin-pipeline/export_ffdec_assets.py tools/monster-reskin-pipeline/build_reference_package.py tools/monster-reskin-pipeline/split_component_concepts.py tools/monster-reskin-pipeline/audit_dressup_reskin.py tools/monster-reskin-pipeline/trace_xfl_dependencies.py tools/monster-re
  skin-pipeline/smoke_test.py`
- `python tools/monster-reskin-pipeline/smoke_test.py`
- `python tools/monster-reskin-pipeline/export_ffdec_assets.py --config <config> --check-only`
- 人形整套追加 `node --check tools/run-dressup-harness.js` + `node tools/run-dressup-harness.js --browser edge --init-file <preset> --canvas-shot <png>`。
- 逐件正式验收用 `python tools/monster-reskin-pipeline/audit_dressup_reskin.py --component-manifest <manifest> --dressup-preset <preset> --output <tmp-dir>`，必须取得 `gate.semanticComponentReviewPassed=true` 与 `gate.battleRigReassemblyPassed=true`。

流程与边界：真素材跑 `export_ffdec_assets.py` → `build_reference_package.py` → `split_component_concepts.py`，人工复核各 action 固定画布、keypose、注册点十字与部件 concept sheet；人形先确认 `missing=0`，整套图只冻结造型，不从遮挡后的整图机械切件；定稿件以原透明 skin PNG 保留局部坐标，再回 Web 拼装复核。Flash 人工矢量回填前追加细节预算轮：银色≤3 档、黑/红≤2 档、每主板≤1 个大高光，删除拉丝/噪点、细铆钉、多级倒角、同心微环和照片级反射；
历史高漂移件只作为单独的形态素材池，记录可借用宏观分区并投影回当前源视角，禁止直接拼接不同视角 PNG 或冒充主清单。回装前强制逐件人工语义门：手部四指 + 拇指，鞋身完整且仅含短踝接口，并核对人体结构、部件归属与共享件非镜像约束；manifest 记录通过的 `semanticGate`，自动连通性和装配不替代此检查。默认回装门强制 `rig=battle`、固定六态、12 个唯一 skinKey / 15 次部件放置、baseline/fit/masked 非空且零缺件、逐态 override 全命中及总览图落盘；`--state ... --diagnostic-only` 只作局部排查，不构成验收。`fit` 暴露比例缺口；
`masked` 仅是恢复旧 alpha 的裁切/占用诊断，alpha 差异为 0 不能证明机械接口连续，也不能作为候选资产。接口断裂时须先对六态 masked 整机做同身份 img2img 连贯性再生成，再按身体/骨盆→共享上臂/小腿→独立肢体→手/鞋→头的依赖链重生分件，最后重新跑本门。改回 Flash 后按目标 XFL 跑 Layer 0、linkage scanner 与独立 publish，并重烘 dressup manifest；完整边界见 [monster-reskin-pipeline README](../tools/monster-reskin-pipeline/README.md)。

### 启动、Flash smoke 与离线专项工具（美术相关）

- 犀牛静态地图摆件：`python -X utf8 tools/rhino-map-assets/build.py --check`、三张 XFL 治理与显式 CS6 publish；车号、坐标与原生/实机边界见 [rhino-map-assets](../tools/rhino-map-assets/README.md)。
- 武器分件动画：`python -X utf8 -B tools/weapon-animation/test_xfl_recoil.py`、`scripts/run-weapon-animation-tests.ps1`（机器钉死 AS2 37 项逻辑 + 15 项真实 XML/物品/素材与生产生命周期装卸集成）；原生逐帧矩阵、独立 SWF 导出与体验边界见 [动画工具](../tools/weapon-animation/README.md)。
- 素材工作台：`python -X utf8 -B tools/asset-workbench/test_core.py`、原生 `AssetWorkbenchTaskTests`，真实 GUI / 三件 3XD 实测见 [工作台验证](../tools/asset-workbench/README.md#验证与本地体验)。
- 装备尺度换算 / XFL 度量衡：参见 [asset-metrology 定向验证](../tools/asset-metrology/README.md#验证)。

<a id="portrait"></a>
## 头像专项

### Dialogue Portraits（对白立绘）

必跑：

- `python -m py_compile tools/bake-dialogue-portraits.py tools/test-dialogue-portrait-authority.py`
- `python tools/test-dialogue-portrait-authority.py`
- `python tools/bake-dialogue-portraits.py --external-only --limit 1 --output-dir tmp/dialogue-portrait-smoke-out --tmp-dir tmp/dialogue-portrait-smoke-tmp --ffdec-timeout-seconds 120`
- `node --check launcher/web/modules/dialogue/dialogue-view.js`
- 同名双源人工裁决追加 `node --check tools/dialogue-portrait-source-review/build-review.js` + `node --check tools/dialogue-portrait-source-review/test-review.js` + `node tools/dialogue-portrait-source-review/test-review.js` + `node tools/dialogue-portrait-source-review/build-review.js` +
  `node tools/dialogue-portrait-source-review/build-review.js --check`。

正式刷新生产立绘时跑 `python tools/bake-dialogue-portraits.py --output-dir launcher/web/assets/dialogue-portraits --tmp-dir tmp/dialogue-portrait-bake --ffdec-timeout-seconds 240`，检查 `report.json` 的 `missingExternalSwf` 必须为空，manifest v2 的 PNG `bounds` 覆盖率应接近 100%，且磁盘 PNG 必须与 manifest URI 精确同集；
`missingFrames` 可非空但必须逐项确认运行时可接受 fallback（精确表情 → `普通` → 默认表情 → 第一张图），否则补 XFL/SWF 源或导出策略。内嵌肖像 character ID 必须从当前 SWF `ExportAssetsTag` 动态解析；烘焙前现有输出默认是透明画布语义基线，仅当 alpha 包围盒与可见 RGBA 完全一致时复用旧 PNG，真实像素变化必须生成新资产。完整双源烘焙要求 `authority-policy.json` 与当前同名集合精确闭合，且 `sourceCollisions` 逐项证明 manifest 最终采用人审来源，新增未裁决项必须失败；
落选来源 PNG 必须从最终资产闭包清除，只允许完整烘焙将其预览保留在忽略提交的 `tmp/dialogue-portrait-source-review/candidates/`。人工裁决生成 `tmp/dialogue-portrait-source-review/review.html` 后逐项比较外部 SWF 与内嵌时间轴，可导出绑定当前 `sourceDigest` / manifest digest 的阶段性或完整 JSON；页面与 JSON 均为 `productionWrites=false` 的只读证据，不代表 manifest 已修复、素材已重烘焙或运行时已验证。
改 `taskReplayDialogue` 立绘字段或 `web/modules/dialogue/dialogue-view.js` 时同时跑 Task Panel harness；主角纸娃娃快照路径还需保留 Dressup Doll gate（见 [美术与资产](#art)）。

### Arena / 材料头像密度门

**Arena 全模式头像与密度门**：触及 `EnemyPortraits`、`MercPortraits`、challenge browser、佣兵/主角只读外观投影或卡片密度时，固定运行相关 `node --check`、lazy closure、merc appearance fallback、`node tools/test-portrait-resolver-runtime.js`（10 例：manifest 拉取失败冷却重试 / alias 与 variant 优先级 / legacy 2MiB・8x 边界 / locked sealed 不递归）、
`node tools/test-merc-portrait-renderer-runtime.js`（8 例：并发槽异常恢复 / 共享 renderer / 末订阅者取消 / 同 turn 重挂载 / 别名归一缓存 / LRU 与字节预算 / 过期 token / 与 tools/lib/arena-portrait-routing.js 的发型别名表跨 runtime 逐键相等）、`test-arena-portrait-coverage.js`、`test-arena-meta-portraits.js`、`audit-arena-portrait-coverage.js --check`、
`test-dressup-manifest-integrity.py` 以及 Arena/Team 三视口 harness。
Arena 每档须 34/34（待核：阈值来源为历史文本，未找到当前机器真源）：完整 2 列、紧凑 3 列且保留人数/等级/经济；身份闭包文本口径锁定 217/217 ready、0 fallback、222 个 accepted enemy variant、444 个绑定与 442 个唯一文件（待核，以 `audit-arena-portrait-coverage.js --check` 当前输出为准）。标准 mixed 的公开 merc actor 必须与同 mercId 的生成 tuple 等值；
无佣兵 meta-team/synthetic 主角模板必须按 `ArenaUnitCatalog.portrait.actor` 显式走 `portraitKind=dressup`，缺 gender 对齐 AS2 legacy 规则归女；隐藏卡不得挂载/预取头像或在 DOM 泄露身份。该门不代签真实 WebView2→Flash、游戏内视觉或部署。

**材料档案来源头像门**：触及材料 enemy/shop 头像、`ShopPortraits`、Crafting lazy closure 或 shop portrait manifest 时，固定运行 `node tools/test-portrait-resolver-runtime.js`（10/10）、`node tools/test-shop-portrait-resolver-runtime.js`（12/12：exact schema/Identity(80)、无 trim/case/alias、退避上限、固定 no-alt 占位、解码失败、
request-token/disconnected stale fence）、`node tools/test-inventory-workbench-lazy-closure.js`（文本 25/25，待核）、`python tools/test-material-enemy-portrait-coverage.py` 与 `python tools/test-shop-portrait-assets.py`。
前者每轮从 `data/items + data/enemy_properties` 动态派生材料敌人集合（文本记录当时为 78/78 ready / 210 个材料掉落 occurrence / 156 个 exact SVG+PNG 绑定；该门不硬编码总数，以动态派生为准），不得把 manifest 反向变成运行时发现来源；后者固定 active shop exact-set（文本 34/34，待核）并校验内容寻址 PNG、hash、256×256、非空 alpha bounds 与 provenance。
修改 baker/Flash source/subjects/manifest 时再追加完整 `python tools/bake-shop-portraits.py --check`；日常 release policy 只接快速资产闭包门。上述静态/Node 门不代签真实 WebView2→Flash、游戏内发现制、视觉效果或部署。

### 头像 P1 / P2 / P3 工具链

- 头像 P1：`node tools/portrait-worker/test-codex-cli-luna-worker.js`；显式 CLI probe / 真实固定 fixture 分别用 `node tools/portrait-worker/run-capability-pilot.js --codex-exe <absolute-codex.exe> --probe-only` 与去掉 `--probe-only` 的同入口，必须取得不同 PID 的 Luna Max A/B、exact closure、语义一致、零孤儿与不可覆盖 report。
- 头像 P2/P3：按 [Portrait Pilot](../tools/portrait-pilot/README.md) 依次执行 fresh `prepare_pilot.py prepare` 或从已验证 P2/P3 receipt 执行带 fresh `--batch-id` 的选择性 `prepare_pilot.py refine`、显式 CLI 的 `run-visual-pilot.js --max-concurrency <1..12> --service-tier standard|fast`、`prepare_pilot.py render`、
  `build-review.js` build/check、`test-review.js` 与 `open-review.js --check`；
  代表集 prepare 固定 12 eligible + 3 blocker，后续精修只包含 receipt 中的 adjustment 行且每模型分片 1–4 行；只接受首帧命名 `man` 来源或显式 warning、A/B 独立 PID/白名单/有界反馈重试闭包、两角色确定性派生、SVG 仅作几何映射、FFDec API 精确选帧、高倍真实裁切不放大候选、预乘 alpha RGBA 门、当前 source/review digest、保存重复点击抑制/显著反馈和 stale/partial fail-closed。
  身份级 `reviewKeyOverrides` 只允许维护归一化 `requiredFeatureRegion/requiredMustIncludeRegion`，必须由模型结果校验与 renderer 再校验共同守住并由 profile hash 进入 source closure；不能补画、替代人审或处理来源冲突。
- 若 adjustment 已明确到 A/B frame + crop，固定改走 `build-framing-guidance.js` build/check → `test-framing-guidance.js` → `open-framing-guidance.js --check`；人类在完整候选上框像素正方形并查看绑定 `sourceHighResolution` 的实时 80px，导出后由 `verify-framing-guidance.js` 写回执，再用 `render-framing-guidance.py render/check` 无模型重渲染。
  若精确帧仅因像素量超过 Pillow 默认阈值而失败，改用 `render-framing-guidance-large-frame-v1.py render/check`；只有逐行 alpha 证据命中精确 allowlist 时才可使用 `render-framing-guidance-large-frame-fidelity-v1.py render/check`。
  当例外已由父 shard 的全路诊断冻结时，改用 `render-framing-guidance-large-frame-fidelity-v2.py render/check --diagnostic-report <report>` 同时绑定诊断 digest、角色、身份、候选、帧和源图 hash；所有包装器都必须有界解码。该支路必须拒绝 stale parent receipt、错误候选 hash、非正方形、可见面积不足、低于 1024 真实来源像素、未逐项确认和重复并发保存，并复验预乘 RGBA MAE、透明越界、4096 上限与 512/80/48/32/WEBP 闭包；
  `human_framing_guidance_verified / human_guided_automated_checked` 只覆盖所选 frame/crop，仍不是 production promotion。

- duplicate/conflict 固定走 `prepare_source_choices.py prepare/check` → `test-source-choice.js` → `open-source-choice.js --check`，每个命名来源优先渲染内部 `man` 并使用稳定 `sourceCandidateKey`；无 symbolName orphan 只能转人工维护。导出后由 `verify-source-choice-decisions.js` build/check 冻结回执，必须拒绝 stale digest、不可渲染来源被当作 selected、漏项与重复并发保存；
  选中后仍是 `portraitRef + default`，不能无运行时选择器就冒充产品变体。已由人类确认的换皮复用固定用 `freeze-portrait-alias-decision.js` build/check 绑定来源决定与目标 guidance/render，并列出不应合并的异常；它只生成非生产 alias receipt，消费者 `portraitRef` 落盘仍需单独施工。
  代表集汇总用 `build-representative-closure.js` build/check，`12/12 eligible resolved` 只授权继续异常队列，不等于全量 campaign、promotion 或 consumer ready；`pass` 接受 Luna A，B 只作审计。
  `capability_verified / candidate_proposed / automated_checked / review_open_preflight_verified` 均不等于 `human_reviewed`、art accepted、promotion、consumer 或 production ready。

### 头像 P4 campaign / 两阶段方向与扩容

先以 `prepare_campaign.py inventory/check-inventory` 冻结 enemy + pet consumer union、source-choice receipt 与代表集 closure，再以 `prepare-shard/check-shard` 生成有界身份批；代表集与 `--exclude-manifest` 中既有项/异常必须排除。campaign 只接受首帧唯一命名 `man`，缺失/不唯一/漂移写 `resolutionAnomalies`，禁止 root fallback。
profile 准备与复验必须运行 campaign 可实现性门并执行 `python tools/portrait-pilot/test-feature-profile-feasibility.py`：每个 mode 的 `minimumRenderedFeatureLongAxisOccupancy` 与 short-axis floor 都不得大于 `1−2×mustIncludeSafeMargin`，否则必须在模型调用前拒绝。模型固定每批最多四行 × A/B；文本记录当前按阶段冻结 Luna Max / Fast / 600 秒：selection-only 可受控并发 6，精确 localization 保持并发 3；
任一 Fast6 批出现 429、transport、timeout、orphan/survivor 或首答闭包退化必须回落 3。每 shard 必须记录实际 attempts、p95、429/transport、timeout/orphan/survivor 和人审通过率，出现连接重连或门控修复时不得继续提高并发。人审页面不设行数上限，优先单页减少切换；`下一批候选身份数 × 估计失败率` 与预算 6 只作遥测，人工扩容覆盖必须显式写入 calibration，不能伪装成统计自然达标。
campaign 尾部不足目标量时必须记录 desired/effective/missing availability closure，不得 root fallback。后续提示与工程必须绑定全部既有人审回执及更晚决定对旧决定的 supersession；文本记录 atlas v6 / compact retrieval v4 要求 168 条当前标签、105 条几何、3 条 superseded negative、`latestResolvedStateIncluded` 与完整父 artifact 闭包（待核：阈值来源为历史文本，以 campaign 工具当前校验为准）。
分片用于减负，不得把同一角色的头、身体、武器切成失去空间语境的碎片；仍未定位时改走「候选帧筛选 → 所选原生高分辨率帧定位」。构图以可识别度为最高目标：头通常是主焦点，头弱时允许标志性武器/身体结构成为复合焦点；主焦点须在甜区并有安全范围，弱组件可受控裁边。运行顺序继续是显式 CLI → 标准 renderer → `build-review.js` build/check → `test-review.js` → `open-review.js --check`；
minimum source crop 1024、retained master ≤4096、intermediate frame ≤16384、预乘 RGBA MAE 与 512/80/48/32/WebP 全部闭合后才可打开真人页面。反馈标定 `build-feedback-calibration-v4.js` 的 build/check 必须同时保留估计遥测与 `humanScaleOverride`；identity shard 扩容由维护者显式决定（文本记录曾由 12 翻倍到 24），不得自动提高模型并发。标准运行只因 feature occupancy 拒绝时，只有全部 attempt-1 transport/schema、锁帧、candidate/方向闭包和每行违例全部可证，才可用 `derive-localization-first-answer-report-v1.js` 形成受限人审报告；只要混入 `RESULT_VALUE_INVALID` 或 transport 不闭合就必须拒绝恢复。
标准 MAE 失败先用 v2 diagnostic 覆盖全部 A/B 路；非二值 alpha、且只在 8–8.25 的单一 identity/candidate/frame 可用 `derive-near-threshold-rasterization-evidence-v1.py` 证明 alpha/core/centroid/双向 edge/bbox 对应，再由 `render-feature-orientation-human-review-fidelity-v1.py` fresh render/check。全局 MAE 仍为 8，所有恢复都只授权真人评价。

`review_open_preflight_verified` 不是 `human_reviewed`，没有完整决定回执不得启动下一个 shard 或 promotion。

**两阶段、方向与扩容（2026-08-08 起）**：固定走「候选选帧 → 确定性 A/B selection lock → 所选原生高分辨率网格定位」；lock 必须逐行绑定候选 hash，第一阶段几何和当前留出集真人目标坐标不得进入第二阶段，精确帧超过 Pillow 默认阈值时仍须同时满足轴向 `≤16384` 与独立面积硬上限 `maximumSourceFramePixels=min(maximumSourceFrameDimension², 240,000,000)`；
现行 fidelity 适配器必须在基础 renderer 的 `.convert()` / `.load()` 前按图像头拒绝超限帧，并在结束后恢复共享 opener 与 Pillow 阈值。第二阶段用 `run-localization-pilot-v2.js --localization-views ...` 输出 `keep|flip_x + reason + confidence`；canonical 主体方向为朝右，box 坐标保持原候选空间，renderer 只在 crop 后、输出金字塔前应用翻转。
A/B 对方向达成一致也不是正确性证明（历史反例见归档）：人类「反转后可用」是要求再翻一次恢复原方向，必须记为 `model_flip_false_positive`，不能反推源图需要翻转。`wrong_pose` 只有备注语义确实要求换姿态时才走 `build-frame-reselection.js ... --review-key <key>`；若人类明确说当前帧可用、问题是透明通道或其他后处理，必须走单独的版本化处理/review，不能机械重选帧。
`prepare_exact_action_frame_directive_v1.py` 必须验证 XFL/SWF 动作起帧、库元件映射、内部总帧数和精确帧，`prepare_frame_reselection_localization_directive_v2.py` 只允许 `verified_human_exact_action_frame_directive` 覆盖方向。
迷你黑洞类黑底合成固定走 `prepare_black_matte_review_v1.py build/check` → `test-black-matte-review.js` → `open-black-matte-review.js --check`/可见页 → `verify-black-matte-review.js` build/check；公式与 4096px 输入输出必须闭合。以上状态仍全部 `productionWrites=false`；后处理取得真人回执前不得 promotion 或启动下一 shard。

### Team / Arena 头像 promotion 与消费者门

先运行 `python tools/portrait-pilot/build-enemy-portrait-evidence-pack-v1.py check` 与 `python tools/portrait-pilot/test-evidence-pack-v1.py`；
再依次运行 `python tools/portrait-pilot/promote-arena-portrait-supplement-v1.py check`、`python tools/portrait-pilot/promote-enemy-portraits-v1.py check` 和 `python tools/portrait-pilot/promote-team-portraits-v1.py check`，随后设置 `CF7_PORTRAIT_EVIDENCE_ONLY=1` 重跑前两门，
强制在没有 `tmp/portrait-pilot` provenance 的 clean-checkout 语义下只使用随仓 immutable evidence。
通用包闭包口径、evidence pack 记录数与 subjects exact-set 的文本冻结值见归档（226 identity / 227 variant / 564 条记录 / 454 subjects 等，待核：以各 verifier 当前输出为准）。`python tools/portrait-pilot/test-evidence-only-full-build-v1.py` 只证明进程内 base→supplement promotion assembly 在阶段状态/cache 清空后全消费且不触达 live tmp；
它显式 stub 四个 historical verifier 子进程，因为父进程 audit hook 不会继承；四门 verifier 由真实 normal supplement promotion 与各自 standalone check 独立覆盖，不得把这项回归外推为子进程 clean-checkout 证明。SVG 生成仍必须剥离 FFDec 自闭合空 filter 并绑定 `compatibilityTransforms`，否则 Chromium 会出现「onload 成功但全空」。
方向门固定追加人类回执 check、`preserve-orientation-source-assets-v1.py check`、orientation-audit 证据闭包 propagation `check --current`，以及带 `--supersession-receipt` 的显式历史复验；历史 r210/r220 基线不得在 controller/manifest 合法演进后继续冒充 current（详见归档）。
运行 `node tools/audit-arena-portrait-coverage.js --check` 的文本口径为 450 条目录 / 217 个消费身份 / 217 ready / 0 locked fallback（待核）：3 个 `主角-*` 模板全部走纸娃娃，214 个怪物身份全部 ready；同时核对 222 个 accepted variant 的 444 个 SVG/PNG 绑定 / 442 个唯一文件。随后执行 Team 与 Arena 三视口 harness；
Arena 还必须覆盖全模式头像分流、完整态 2 列且每卡最多 4 个实际单位小头像、紧凑态 3 列且只显示同组首项、密度切换零新 preview、隐藏卡零身份预取、纸娃娃窗口与 Team 共享 `card/112px/cover` 裁切、长目录只挂载可见邻域、共享 renderer 默认并发不超过 4、项目 `PanelTooltip` 且无原生 `title`，以及零横向溢出。ignored backup 只作本机运维恢复，不得写成 clean-checkout 权威证据。这些门证明资产/Mock-browser 闭包，不等于真实 Launcher WebView2→Flash、游戏内视觉 E2E 或 runtime 发布。

<a id="diagnostics"></a>
## 诊断与现场观测

**通则**：区分探针、分发延迟、关联丢失、生命周期和真实业务 owner，读取现役诊断 ADR 的启用方式、限额与证据窗口。本机不复现不等于现场无故障；观测不授权 watchdog/重试/自动修复，诊断开关默认值和精确启用值不得扩大。只有现场取证/新鲜行为需要才启动相应环境；日志脱敏、用户存档与未知写保护仍适用（见 [持久写与恢复](#save)）。

**焦点观察**：Host FocusTrace/RollingFocusLog/FocusExitCollector/AppConfig/NativeHud/RightContext/StageOutcome/LayeredWindowCommit 与现役 focus gate 定向测试；AS2 `run-map-loot-tests.ps1` 的 StageRunSessionTest 覆盖撤退后迟到波次/判胜不能修改真实任务条件与正常胜利恰好一次回归（现役钉值见 [Loot / 关卡结算 runner](#suite-loot)）；
持续录制、退出自动 ZIP、真实隐藏采集器及人工边界见 [焦点管理 §9.12](../docs/焦点管理-诊断与卡顿排查-2026-05-24.md#912-2026-09-07配置化持续录制与固定容量保留)。焦点诊断默认关闭；测试员设置根 `config.toml` 的 `diagFocusTrace = true` 后重启即可持续录制并在正常退出时自动打包。

跨层端到端输入交接必须同时遵守 [焦点管理 §9.10a](../docs/焦点管理-诊断与卡顿排查-2026-05-24.md#field-input-chain-v1) 与长期卡 [#103](https://github.com/FlashNightModReborn/CrazyFlashNight/issues/103)：缺失 hook/dequeue、Native HUD、intent、AS2 accept/local result、durable/transition 或 scene-ready 任一层时，只记该层未知/不完整，不以正常样本、焦点恢复或 promotion 代签现场根因。

**输入事故交接（发布源 `fbbc47a8c0`）**：输入/诊断 focused、显式 `CF7_TEST_PORTRAIT_WEBVIEW=1`、runtime source/queue 门与新鲜 asLoader 证据见 [焦点诊断 §9.18](../docs/焦点管理-诊断与卡顿排查-2026-05-24.md#918-2026-09-13输入边沿防御与分层观察) 和 [头像工具说明](../tools/portrait-pilot/README.md#2026-09-13卷积-svg-运行时禁用政策)。

**建连/总线诊断**：Flash↔Launcher 建连类问题只用真 launcher 定病（读 `logs/launcher.log` 的 `WaitingConnect -> WaitingHandshake`），不用 compile_test/testMovie 或裸 socket 桩，详见 [Host、总线与自动化](#host)。

**GPU/机器不稳定**：先跑静态复杂度审计（`node tools/audit-web-overlay-complexity.js`），GPU 偏好切换后完整重启复核 engine，见 [Host、总线与自动化](#host)。

**NPC snapshot 污染类事故**：自动证据只覆盖污染夹具、协议相关性和隔离策略；测试机物理隔离且原存档已丢失时，不得宣称原事故唯一归因或真实存档 E2E（runner 见 [K 店与 NPC 物品商店](#suite-kshop-npc)）。

<a id="specialized"></a>
## 专项资格、长时运行与真人评价

**通则**：命中专项时先读该专项当前 ADR/runner 所定义的 source/corpus/plan/hash 与接收标准，再跑其适用门。历史长时记录、成功比例、固定模板/模型并发是当时证据或专项配置，不是全项目默认。真人评价、长时 soak、候选执行和正式供应链分别陈述。

### CF7 Agent Runtime / Wings（F8 现役断言）

必跑：`launcher/tests/run_tests.ps1` + `node --test tools/cf7-agent/tests` + legacy HTTP/entry guardrail tests（`node tools/test-legacy-http-auth.js` + `powershell -ExecutionPolicy Bypass -File tools/test-legacy-http-auth.ps1` + `node tools/test-legacy-http-client.js` + `node tools/test-legacy-http-client-migrations.js` +
`powershell -ExecutionPolicy Bypass -File tools/test-runtime-entry-guardrails.ps1`）
。

**F8 current 必须断言**：Flash descriptor 为 metadata-only，exact `observationModes=[]` / `inputModes=[]`，pixel capture 返回 `unsupported_for_surface`；production 不发布 `window.activate` 且 activator map 为空；WGC 只覆盖 Launcher、WebOverlay、NativeHud。
structured `panel.open` 必须绑定 exact 一个当前 `RuntimeOwned` Launcher target、one-shot lease 与 broker dispatch receipt；trusted shutdown 的 canonical transient 有界重试不得 regrant/改 scope，`session.shutdown` action zero-retry。
正式旅程必须从不传 `-CandidateRoot` 的标准入口只经 Agent Runtime MCP 完成，不使用 Codex Computer Use、browser/Chrome、legacy privileged HTTP 或任何 `input.*`，pixel 只作内存 hash 后清零且不落 PNG。当前通过口径为单屏 Help-panel 窄纵切 `standard_entry_verified`；不外推物理双屏、Flash pixels/input、Hair/Wings 完整产品、业务写或维护者目视签收（历史计数与身份收据见归档）。

**固定覆盖（F7 起）**：`CurrentUserOnly` 外独立 OS peer token 的 Windows session/elevation/process incarnation，exact path+PID+start-time+HWND/owner，`activePanel{name,instanceId,targetId}`，导航开始即推进 document generation，`window.state` 零激活与 production `window.activate` pre/post exact binding，
production `business_modal` selector 恒空且内部 `BusinessModal` human-only；
`trace.export` 仅 enrolled developer + `DeveloperInteractive` + capability/consentPurpose + `data.export/allowExport`，8 MiB Runtime-owned JSONL 覆盖共同 pending marker/owner staging、owned-file cleanup、final move 后 audit failure、删除受阻保留 marker、dead-owner janitor、并发/既有同名不误删，以及 legacy `.tmp` 独占清理与 markerless `.jsonl` 保留；
单文件 move 不作跨 audit/filesystem 事务证明，wire 只返 artifact ID/name；Hair 按理发店行；Wings 自由文本零执行、structured intent/receipt/reconcile 同管线。`LeaseDescriptor.purpose` 必填、`renewAfter` 可选且 shutdown 必须省略；
shutdown 只允许 `DeveloperInteractive` / `UnattendedTest`，selector/lease scope 必须解析为恰好一个当前 `RuntimeOwned` Launcher target（这是 scope cardinality，不是 session 全局 singleton），唯一 `session.shutdown`、TTL≤30 秒、one action、no renew；只有语法有效、已认证、完全授权并到达 issuance policy 的 PlayerAssist acquire 返回 `consent_required`，畸形、越权或直接 action 可更早失败。
成功 consume 的 owner 持有 execution reservation 到 JSON/可选 binary 全部 response frames 完成 `WriteAsync` 或显式 abort；失败 consume 从未拥有且不能释放他人 reservation。live map 仅保留 active 或 reservation-draining lease；terminal tombstone 为 FIFO **256**，committed-shutdown exact-session latch 独立保留 **64** 且不驱逐，第 65 个不同 session 全局 fail closed；
tombstone eviction 与 wrong/stale renew/release 均不得重开 writer，renew/release 只处理 exact active owner。同 identity/canonical payload replay 必须返回 ledger retained 的同一 `ContractReceipt`（含 aborted delivery 的 durable `ReconciliationRequired` Unknown），零 re-dispatch、零第二组通用 action audit、零二次 receipt synthesis。

external/human input 抢占尚未取得 delivery-write ownership 的 active/execution-pending/delivery-pending/queued action；首字节前 ownership claim 成功后普通 revoke/input 不得回滚，终态只归 completion state machine。单一绝对 action deadline 从完整 request frame 收到时开始，覆盖 parse/admission/scheduler/performer/writer lock/全部 frame `WriteAsync`，不得重置。
SafeExit 只先 arm；首字节前先 claim exact audit identity，再 claim lease write ownership + human-input sequence fence；第二道失败保持零成功字节、补偿唯一 `action_response_unknown` 并同步确认 abort。`action_response_written/unknown` 为 reserved event，generic append 必须拒绝。
全部 required frames 完成 `WriteAsync` 是 server disposition 而非 peer ack：正常追加唯一 `action_response_written`；后置 Flush 不回滚；post-write commit/audit callback false/throw 只允许 continuity lost、pending removal 与必要的 `truncated` segment，不合成 Unknown，也不保证 SafeExit continuation，故不算 clean E2E。
完整写前 abort callback false/throw 则保留 reservation 并标记 continuity lost，后继 writer 不得进入。unattended 只信 strict-verified exact `Core.exe --agent-unattended-runner`；Host 每次 committed full-surface refresh 后在 lock 外以 single-flight 重试 credential publish，teardown 先停止 admission/periodic refresh 再越过 in-flight barrier；
credential acquisition 是 caller 不可覆盖的单调 **30 秒**，与 request/session 最长 **10 分钟**独立。退出 observation 固定 no fallback 且只接受 `SourceLayer.Launcher`；shutdown lease/receipt 逐字段严格匹配，完整 receipt 后必须在 10 秒内观察同一 exact child exit code 0。
只有 adapter 0 + strict receipt + exact child 0 + no forced recovery 才在 stderr 恰好输出一条 ≤16 KiB、绑定 runtime/process/Core/build/closure/Guardian/full receipt 且不含 secret 的 completion evidence，stdout 始终只承载协议；timeout、非零退出、forced recovery 或缺 evidence 均失败。MCP 固定 `initialize` → response → `notifications/initialized` → tools；
JSONL call 30 秒，MCP active call 从 handler 到 buffered response copy/flush 共用绝对 30 秒预算，idle 输出各有 30 秒 budget，完整 shutdown transcript 同样 bounded；timeout 取消、异步关闭 pipe、零伪 response 并只回收 exact owned child。standard HTTP/XML 与 legacy 互斥；

没有真实交互前台的 exact candidate execution/E2E、双屏、真实 crash/power-loss/delete-denial 恢复演练、v2 promotion 与 standard-entry 复核，不称部署或正式验收。

### 导弹运动 / 追踪参数离线调优

`python tools/missile-tuning-sim/run_sim.py compare --configs ...`；视改动追加 `scan --objective loiter|pressure|hit` / `audit`、`compile_test`、游戏内人工验证。

### 竞技场斗兽标定（campaign 门）

必跑：`npm --prefix tools/arena-calibration ci --ignore-scripts --no-audit --no-fund` + `node tools/arena-calibration/run-checks.js`（Ajv 2020 编译全部 schema，合法/非法实例双向验收，并含 `intake-workbook.js --check`、Campaign 13-action fixture、`run-unattended.js --check` 的参数/authority/阵型 rerun、生产原始 JSONL、manifest/case 绑定、build-gate、report、
关停 PID 与 reveal 后进档时序自检）+ `node tools/test-agent-entry-contract.js` + `launcher/tests/run_tests.ps1`；
新 Host candidate 必须先独立 build，再传 `--candidate-root <精确绝对 candidateRoot>`，嵌入 `launcher-build` / `launcher` gate 必须 fail-fast；改 AS2 runner / 存档装载 / agent 进档入口时追加 `scripts/compile_test.ps1 -Target publish` / `-Target test`。

**工作簿与 roster 绑定**：工作簿摄取必须绑定 `workbookSha256 + sheetName + cell + cellValueHash`，hash-bound override 只改派生产物，原 `.xlsx` 保持只读；roster `parameters/sourceId/hpPermille`、case `authorityContext`、显式 timeout、阵型与间距必须进入 manifest/case hash 并由 rerun 原样保留。
真机必须验证从冷启动/已启动 launcher 通过 `agent_control` 进入专用标定存档，并在启动、恢复、重启各阶段硬核验 `runtimeMode/processPath/coreSha256/buildIdentity/payloadClosure` 与预选 formal/candidate 身份一致；受控进档顺序按 [持久写与恢复](#save) 的「受控进档」段执行。随后从普通场景自动跳关进入 StageManager 专用竞技场标定分支：不刷主角/同伴，覆盖跑完、timeout、abort、JSONL 写入、run-unattended 有限次数自动重启补跑与 `run-report.*` 失败清单；
同时覆盖安全阀负例：runner 默认拒绝 `crazyflasher7_saves*` 正式槽和 `--fresh`，坏档通过直接 `agent_control start` 也必须停在 `save_decision_unsafe` / `runtime_save_not_loaded`，正向 ready 必须包含同一 `attemptId/savePath` 的 `saveRuntime.loaded=true`。每个真实 shard 还必须在跑前/收尾对专用目标槽以外的全部 live shadow JSON 与对应 SOL 做 hash 快照，任一差异即失败。
普通 `gameworld` smoke 只证明通信链路，不作为数值样本；AS2 runner 禁止直接替换带主角的普通 `gameworld`；StageInfo/跳转入口不可用时应返回 `stage_failed`。

**生产 JSONL 与完成门**：改战场参数 / 阵型 / 多阶段接管 / 污染清扫时，生产 JSONL 原始行（不得先 normalization 丢字段）必须包含 `spawnDistance`（Host synthetic timeout 可缺省）、`blueFormation`、`redFormation`、`formationSpacing`、`blueSpawnPositions` / `redSpawnPositions` / `formationAudit`、`authorityContext`、`phaseSpawnCount` / `spawnedUnits`、
`blueUnitResults` / `redUnitResults` 并直接通过 schema；
污染场必须返回 schema-valid `contamination` 而不是有效胜负样本。最终 `complete_candidate` 必须机械拒绝总样本 `<30`、缺任一 side assignment、任一方向 error 非零、未完成 side-swap review、timeout provisional；两方向 `timeouts/samples/timeoutRate` 必须自洽，合并 timeout 必须同时不高于 snapshot stop condition 与 `5%`，`explained_long_timeout` 只补来源解释、不能绕过低 timeout 门。
生产化先运行 `build-production-recommendation.js` 生成 exact bundle，检查 proposed catalog/dry-run/rollback/implementation closure；Host 只接受当前 authority session 的 `calibratedRosterId` 并重建规范 roster，Web 不得夹带 roster，生产目录不写 faction `benchLevel`；
正式写入必须由人类批准精确 `bundleHash` 后运行 `apply-production-recommendation.js`，任何 base、Git revision、消费者闭包或验证漂移都 fail closed/回滚，不得把 bundle 生成等同于已启用、已构建 candidate 或已发布。

**Campaign Gate B–E 增量门（2026-08-27 起）**：`node tools/arena-calibration/run-checks.js` 必须同时通过 `test-campaign-gate-b.js` 与 `test-campaign-gates-cde.js`。Gate B 固定拒绝 producer 缺失/active/unknown/stale、过期/撤销 grant 与 writer contention，并覆盖双 flush 四个 crash 点、ack 丢失 exactly-once、未提交断尾排除、closed segment 篡改拒绝及 pause/resume；
真实验收另要求至少两个 short shard，中间跨进程恢复，execution artifact 绑定 exact formal/candidate runtime、raw JSONL、cohort compatibility 和未变的受保护存档 snapshot。Gate C 只有三份真实 profile proposal/receipt 全过硬门后才可生成 blind packet，且仍须真人盲评和 versioned gold suite；Gate D 的 timeout/error 只能进 anomaly，不能进强度拟合；
Gate E fixture 只证明 packet/response schema，实际通过必须有获批 exact player build、2–4 encounter、至少一个 holdout、自动客观遥测与真人标签。request/scorecard/packet ready 均不得代写为 Gate C/E 通过。

**Gate E 真人门**：先以 `run-human-pve-session.js --packet <pve-packet.json> --plan <private/pve-runtime-plan.json>` 启动 exact runtime；只用 `--signal next|finish|abort --run-dir <本轮目录>` 驱动 owned-file 控制信号。
两场后运行 `finalize-human-pve.js` 绑定原始 report、截图、维护者原话、等效佣兵数量/等级与隔离克隆，再用 `evaluationctl.js validate-pve --packet ... --response ...` 验证 exact packet。通过必须同时满足源存档 hash 未变、非目标存档集合未变、active 专用槽/进程/锁/恢复记录均为 0；没有 duration/胜负/承伤/输出/残血等自动证据时只能记 `equivalence_only`，不能补猜为完整 PVE telemetry。

**Gate F 星期级增量门**：统一入口 `node tools/arena-calibration/run-checks.js` 必须通过 `test-campaign-gate-f.js`、`test-gate-f-anomaly-policy.js`、`test-arena-summon-lineage-source.js`、`run-exception-review.js --check`、`gate-fctl.js --check` 与 `build-gate-f-week-plan.js --check`，覆盖 plan/manifest/decision/admission hash 篡改、
candidate baseline 完整性、经验 timeout override 和 soak admission 的真正 Schema 实例、workbook/cell/candidate/raw-evidence 绑定、报告 `resultPath` 与唯一 `resultSnapshotPath`/manifest snapshot、磁盘和 active producer、window 到期/撤销、partial row durable commit、重复排除、显式 attention measurement、20-epoch 分母与 exception 去重。
timeout override 只作用于派生计划，必须保留原双向 timeout、证明提升窗口双向自然结束并标记 formal replay required；不得修改 normalized intake 或覆盖旧结果。正式运行只接受 clean Git source + exact formal runtime 冻结 plan；先执行三份 10-run fresh soak，逐份验证原始 JSONL/manifest、runtime identity、受保护存档、timeout/error/时长/磁盘和 0 人工动作，再开放剩余 10–25 run shard。
基础设施 soak 只能从 `arena-calibration.soak-admission.v1` 选择同一 formal runtime、exact candidate timeout、original/side-swap 均自然结束、零 error/timeout/recovery、正常关闭且存档不变的稳定代表；每份必须覆盖普通参数、单位 payload、阵型、长 timeout 与高等级。候选自身真实 timeout 留在该候选全量普通分片中，不能污染平台稳定性门，也不能因退出 soak 而删除。
全量阶段若完整、exact-runtime、save-clean 的 shard 只因 `timeout_rate` 超阈值，则必须提交原始行、写 `candidate_timeout_anomaly / keep_provisional` deferred item 并继续；timeout 仍排除于强度拟合且参与最终候选低-timeout 门。
标准/长 shard 在 exact runtime、存档、磁盘、墙钟和完整 cardinality 均闭合后，若恢复耗尽且失败行只属于 `contamination/error/invalid_case/spawn_failed`，则必须提交 raw/partial 事实并写 `quarantined` receipt，只隔离由 `caseId` 确定的候选、跳过该候选后续 shard，其他候选继续；污染/错误行仍绝不进入强度拟合。
基础设施 soak、`stage_failed/bridge_lost`、duration drift、runtime/save/disk、runner/report/cardinality 异常仍失败。每个 controller 默认最多异步唤醒一个 `run-exception-review.js`；模型只可对 hash-bound request 返回四类建议，`mayAcceptSample=false`、`mayResumeCandidate=false`，不得写完成 receipt 或阻塞后续 shard；Codex CLI 缺失、超时、失败和非法输出一律保持 quarantine。

运行监控必须把 controller/runner 的祖先和全部后代视为同一受控进程树，内部检查子进程不能误触竞争者；树外独立 runner/Flash、内容开发或 revoke 仍必须经 owned signal 在 300 秒硬上限内让位；既有 partial 事实可以 exactly-once 提交，但不完整 shard 不得写 `completed`。任何 ArenaCalibrationService、污染判定或 SWF 战斗资产变化必须切换 battle-semantics cohort，旧样本只保留为历史，不能用 compatibility receipt 混入新 cohort。
Fixture、candidate 诊断、冻结前草案、`arm`、三份以下或少于 20 个真实 eligible epoch 都不能代签 Gate F low-touch/星期级通过。

### Audio Platform v2（专项资格）

**通用发布解耦的现役口径在 [正式 runtime 发布](#runtime)**：通用 promotion 不要求 Audio H1/H2/E3/截图/听感；本节只保留专项资格义务。

**R4 H2 合规路径（当前未闭合；owner-emergency release 已 promoted，属历史状态）**：P4 `755c88eef2f0fb92f247d3a381dc91638cdf8e77` 与 H4 `0792adf201802f1369a91b2fd3e4561a25c279b9` 的 A1–A6 合同继续有效。`sleep_resume` 每个 episode 用 hash-bound working-state ticks 判定：`<=15s` 命中质量目标，`>15s && <=30s` 以 `targetMiss=true` 结构化保留但不阻断，`>30s` fail-closed；
最终 PCM 只比较末个 closing `Ready` 后两份同 session、同 `audioReadyGeneration`、同 physical runtime tuple 的显式 snapshot，必须在同一路 BGM 或 SFX bus 上同时证明第二份 frame 前进且 `peakAbsPcm16>=64`，严禁跨 generation 作 frame 差。正常路径仍要求 E2/H2、v2 request、双 builder 与 evidence-only E3 `h2-request-link.json` 闭合。
owner-emergency 发布未满足或伪造 H2，不能反向补签 A6/E2/E3，也不把 Audio 专项推进为 `standard_entry_verified`。

**Audio Platform v2 gate（current source，H2 blocked）**：改 `launcher/native` 音频 ABI/backend/decoder、`launcher/src/Audio`、`AudioTask`/XMLSocket、AS2 `AudioBridge`/`SoundEffectManager`、Jukebox availability、音频资产发现/后缀、`config/audio-v2` 或 `tools/audio-v2` 时，先跑合同与生成物检查：

- `node tools/audio-v2/validate-contract.js --proposal-commit 307ee8d2df3dfbf21ceb4f8b53bc91541eb3cc9c --h1-receipt docs/evidence/audio-v2/h1-implementation-acceptance-r7.json`
- `node tools/audio-v2/contract.test.js`
- `node tools/audio-v2/generate-decoder-lock.js --check`
- `node tools/audio-v2/generate-native-build-inputs.js --check`
- `node tools/audio-v2/generate-shipped-audio-assets.js --check`
- `node tools/audio-v2/check-shipped-audio-assets.js`
- `node tools/audio-v2/shipped-audio-assets.test.js`
- `node tools/audio-v2/update-qualification-dependencies.js --check`

native/Host/AS2/Web 按触及面追加 `launcher/native/tests/run_audio_bridge_v2_contract.ps1`、`run_audio_bridge_support_contract.ps1`、`run_audio_backend_policy_contract.ps1`、`run_audio_bridge_v2_runtime_contract.ps1`、`launcher/tests/run_tests.ps1`、
`scripts/run-audio-v2-tests.ps1 -SkipCompile` 与 `node tools/run-jukebox-harness.js --browser edge`；
PowerShell 脚本统一带 `powershell -ExecutionPolicy Bypass -File`。runtime payload closure、manifest file rows 与 actual payload paths 必须统一使用显式 UTF-16 code-unit Ordinal；固定 .NET oracle 与显式 `zh-CN` 负例必须同时通过。
qualification source 门至少运行 `qualification-runner.test.js`、`qualification-observer.test.js`、`materialize-qualification-fixtures.test.js`、`qualification-operator.test.js`、`assemble-a6-evidence.test.js`、`update-qualification-dependencies.test.js` 六个 Node 门，以及 `qualification-observer-client.tests.ps1`、
`qualification-stimulus-client.tests.ps1`、`capture-endpoint.tests.ps1`、`list-playback-endpoints.tests.ps1`、`write-qualification-toolchain.tests.ps1` 五个 PowerShell 门（均在 `tools/audio-v2/`）；
A6 prepare 前另运行 `write-qualification-toolchain.ps1 -OutputPath <absolute-json>`，再把该 canonical JSON 交给 assembler 的 `--toolchain-json`；Host 另跑 `AudioQualificationDiagnosticsV1Tests`、`AudioQualificationStimulusV1Tests` focused 与 Launcher 全量。
`-SkipCompile` 只验 tracked suite/template/BOM/事务，触及 AS2 后仍须取得 fresh TestLoader/CS6 trace、Compiler `0/0`、32K retry `0` 与精确 asLoader publish，动态 hash/计数只填 ADR 恢复卡。native 正例必须证明 production 仅 WASAPI/DirectSound/WinMM、Null 不可达、runtime probe 有界且 offline qualification 解码到 EOF；单测 sink、Null、内部 PCM/meter 不能代签端点可听。

**A6 取证流程**：A6 先由最终 source commit 的两个 clean producer 重建出相同 identity/closure/逐文件闭包，再用 `automation/start.ps1 -CandidateRoot <abs> -AudioV2QualificationRunId <32-lower-hex>` 启动 exact `NOT_DEPLOYED` candidate；该 flag 在 formal/standard/unattended/legacy 入口不可达。`operator prepare` 必须只接受全新 runId，独占创建 run root 与空 `captures/`；
既有 run root（captures 缺失、为空或非空）一律 fail-closed 且不得触碰。`run-automated --capture-output-root` 必须精确绑定本 run 的 canonical `captures/`，真实 ancestry 无 symlink/junction/reparse、lane 初始为空，并在每次 production capture 前重验而不自行创建或清理。
materializer 逐项重读并校验六个 production full-filename SFX 的 bytes/hash，按连续 MPEG Layer III frame 严格解析到 exact EOF 并锁 version/sample rate/frame/sample/duration；只接纳 `sourceDurationMs >= 3000`，按 duration、sourceBytes 降序与 linkageId 升序冻结 `qualifiedLongSfx`，`sfx_playback`、dense 同 ID×6 与 mix 都必须使用该 hash/duration binding。
operator 用 separate observer/stimulus pipe 按 strict order 自动跑前 10 case，Opus 后在 case 外 mute BGM、dense overlap 后 restore 并等待 qualified floor duration +250ms（文本记录当前 `3813+250=4063ms`，待核：以 qualification 工具当前输出为准），末尾再 restore；
stimulus 只经生产 `AS2 → XMLSocket → AudioTask → AudioCoordinator/native`，`sent=true` 只证明 socket delivery。capture 在 `IAudioClient.Start` 后写 `ReadySignalPath`，operator 等 token 才发 stimulus；runtime `f32` 与 endpoint WAV `pcm_s16le` 分别绑定。mix 初始 SFX meter 必须 quiet；
随后锁同一 playing request/decoder 与合法非空 loop bounds，允许 cursor wrap 或整圈后相等，并分别要求 BGM/SFX meter 非静音且推进。crossfade raw snapshot 全部须非静音、frameCount 不回退；
允许短 cached read，但首尾 source 替换、总 frame 前进、至少 3 个 distinct frame sample，且含 leading/trailing duplicate 的连续 no-progress wall-clock 窗口均 `<=500ms`，不得声称每次读取都推进，也不证明 dual-slot gain envelope。
人类在端点 A 完成前 10 case/三份 capture/gain restore，marker 外切 A→B 并等待 ready，再在 default-device case 内切 B→A、等待恢复并取 `device_recovery` capture，最后在 A 完成物理路由、sleep/resume、no-stale-SFX；后 4 端点动作与 10 听感不可代签。assembler 只生成/复核 9 组 config/input 与 `HUMAN_REQUIRED` drafts，固定 `promotionAuthorized=false`，绝不生成 E1/H2/pass；
最终仍需 9 reports、44 checks、4 captures、10 listening verdicts。

**Audio A6 C# observer focused gate**：改 `AudioQualificationDiagnosticsV1`、`Program`/`start.ps1` 接线、coordinator qualification snapshot 或 `AudioTask` observer 时，先跑 `dotnet test launcher/tests/Launcher.Tests.csproj -c Debug --filter FullyQualifiedName~AudioQualificationDiagnosticsV1Tests`，
再跑全量 `launcher/tests/run_tests.ps1`。
focused 必须覆盖 formal/standard/unattended/legacy flag fail-closed、无 flag 无 pipe、exact candidate/process/canonical/size/run 绑定、真实 JS observer snapshot request round-trip、active case mismatch、14-case/9-journal reconnect、hash/source、并发/dispose，以及 crossfade 100ms single-flight 自动三点、raw UTC 顺序、
短 cached read 与 `<=500ms` no-progress derivation、end/dispose late-drop、production 150 点/15 秒双上限；
另须把包含 `0.00001/0.000089/0.1/<0.5e-6→0` 的 C# raw journal response 直接交给真实 Node `validateResponse/validateJournal`，并逐字重算 canonical bytes 与 hashes。crossfade 自动门只证明 exact 非零 `fadeSeconds` 请求、相关 `started` result、source 替换及上述分辨率下 bounded no-progress 的非零 BGM meter；它不证明双 slot 同时活跃、各 slot 增益包络、endpoint 可听或 H2。

**Audio MF async / decoder 补充门**：改 `audio_mf_decoder.*`、Media Foundation 生命周期或 cancel/timeout 时，必须追加 `powershell -ExecutionPolicy Bypass -File launcher/native/tests/run_audio_mf_decoder_async_contract.ps1`，并保留 timeout、cancel、Flush、late callback、quarantine 与引用归零的确定性负例；
`run_audio_bridge_v2_runtime_contract.ps1` 在真实 production device ready 时还会 materialize tracked 六样本并调用同一 offline helper，要求 AAC/Opus/Vorbis/静音 WAV 全部完整 EOF/非零帧，Opus/Vorbis/静音 WAV 各精确 24000 帧，坏 Ogg 保持 category 4，页内截断 Vorbis 为 category 5 / qualification failed / EOF 未到达。两者都不替代真实 endpoint。

**Audio WASAPI reroute/recovery 补充门**：native contract 必须实际编译/链接/运行并锁定 config forward、bridge `MA_TRUE` 与 callback 零 graph mutation；
managed focused 用 pinned .NET 10.0.300 执行 `dotnet test launcher/tests/Launcher.Tests.csproj -c Release --no-restore --filter FullyQualifiedName~CF7Launcher.Tests.Audio.AudioCoordinatorTests --logger console;verbosity=normal`。这些 source/focused 门都不代签 exact candidate、真实端点或 H2。

**S11 observer 证据语义（现役合同）**：recovery marker 是 endpoint transition boundary，首个 `Recovering` 可已暴露新 endpoint digest；每 episode 保持同一 session、`audioReadyGeneration` 相对当前 `Ready` baseline 精确 `+1`，episode 内 `deviceGeneration` 不回退；
retry 可迁移 endpoint，closing `Ready` physical tuple 对齐末个 `Recovering`、`deviceGeneration` 相对该 baseline 前进，并成为下一 baseline。每段 hash-bound `workingStateElapsed100ns` 仍须 `<=150000000`，排除 sleep/hibernate；
final post 可与末个 closing `Ready` 同事件，必须完整对齐末 `Ready`、qualified endpoint digest 回原始 pre，并由 BGM/SFX 至少一路 PCM meter 同时非静音且 frame 推进闭合。其他 case、UTC window、有限 SFX 与 stale-generation 语义不变。S10 的 frozen source/identity 与十个不可复用 runId/capture 只作历史（见归档）。

**R7 content-sniff 补充门**：当前 P7/H7/S7 只新增 qualification runner 的有界 canonical codec 映射。RIFF/WAVE 必须在 declared/available bounds 内按 word padding 遍历并要求唯一有效 `fmt `，仅 tag `1` / 16-bit 映射 `pcm_s16le`；
ISO-BMFF 必须按 big-endian box bounds 沿 exact `moov/trak/mdia/minf/stbl → stsd entryCount → mp4a` nested chain 结构解析，top-level `stsd/mp4a`、裸 marker/`indexOf` 一律拒绝。malformed、截断、越界、重复或 unsupported 均 fail-closed；定向门为 runner 35/35、全 795 tracked mismatch=0（待核：阈值来源为历史文本，未找到当前机器真源），以及 dependency manifest 568 项（待核）。
P7 frozen validator 的 exact-chain 已知宽松不得作为 H2/E1 oracle，最终 release Source 必须另行闭合。

**Launcher 前门 BGM focused gate**：改 `FrontdoorBgmLease`、其 `AudioCoordinator` exact-CAS surface、`GameLaunchFlow` 音频交接或 `Program` 音频装配时，至少运行 `dotnet test launcher/tests/Launcher.Tests.csproj -c Release --filter "FullyQualifiedName~FrontdoorBgm|FullyQualifiedName~ProgramAudioLifecycleTests"`。
focused 必须覆盖同 epoch 重复 acquire 不重播、foreign source 不抢权且清空后才可获取、revoke 只命中自身 requestId、AS2 supersede 后迟到 revoke 不 stop、revoke 同时清 latest/pending recovery 且设备恢复不复活、无 OP Bootstrap admission/角色提交保持、OP/legacy admission 让出、actual reveal 最终让出，以及 `SceneReady` 后但 reveal 前 reset/error 可恢复、reveal 后永不回抢；另须静态确认固定曲目存在。
自动门只证明 Host 状态机和 native 请求关联，不能证明真实 endpoint 可听、`0.4 × master` 主观响度、OP/reveal 交接无爆音/重叠或长加载遮蔽效果；这些必须在 exact candidate 的实际前门→OP/读档/新建角色旅程中由人类听验，未执行时不得称 Audio H2、`e2e_verified` 或 `standard_entry_verified`。

### Native HUD gate

改 [NativeHudTheme](../launcher/src/Guardian/Hud/NativeHudTheme.cs)、[NativeHudFonts](../launcher/src/Guardian/Hud/NativeHudFonts.cs)、[NotchWidget](../launcher/src/Guardian/Hud/NotchWidget.cs)、[AudioHudState](../launcher/src/Guardian/Hud/AudioHudState.cs)、
[RightContextWidget](../launcher/src/Guardian/Hud/RightContextWidget.cs)、[RightHudLayout](../launcher/src/Guardian/Hud/RightHudLayout.cs)、[MapDisplayState](../launcher/src/Guardian/Hud/MapDisplayState.cs)、[SafeExitPanelWidget](../launcher/src/Guardian/Hud/SafeExitPanelWidget.cs)、
[LootFeedWidget](../launcher/src/Guardian/Hud/Loot/LootFeedWidget.cs) / [LootFeedModel](../launcher/src/Guardian/Hud/Loot/LootFeedModel.cs) / [SingleFlightBatchQueue](../launcher/src/Guardian/Hud/Loot/SingleFlightBatchQueue.cs) / [LootIconCatalog](../launcher/src/Guardian/Hud/Loot/LootIconCatalog.cs) /
[DollPortraitBakeService](../launcher/src/Guardian/Hud/Loot/DollPortraitBakeService.cs)、
[LootFeedTask](../launcher/src/Tasks/LootFeedTask.cs) / [DollBakeTask](../launcher/src/Tasks/DollBakeTask.cs)、[NativeHudOverlay](../launcher/src/Guardian/NativeHudOverlay.cs) 或 `Program.cs` 注册顺序时，必跑 `launcher/build.ps1` + `launcher/tests/run_tests.ps1`。

缓存/烘焙定向门必须覆盖最小预算下图标 A→B→A 淘汰重载、动画整组预算、exact requestId 的 missing/foreign/duplicate/late 拒绝、匹配失败只释放本请求、PNG 完整解码与 exact 256×256，以及宿主 `devicePixelRatio=1.5` 时快照仍显式 `pixelRatio:1` / 256×256 / `animate:false`；单纯 PNG magic、key-only 清理或 mock 成功不得计通过。人工覆盖 1024×576 / 1600×900 / 1920×1080 / 4:3 letterbox：刘海与右侧动作行共享 32px 顶行；
刘海外框比右栏槽位再低一级；常驻面板采用黑底、1 device-pixel 直角发丝框、与外框分离的内侧明暗压边和技能槽式角标，hover/pressed 不得把整圈外框加粗/提纯白，常见 1.0～1.875 倍 viewport scale 不得膨胀为 2px 粗框，100/125/150/175% 下线宽、角标与文字基线清晰，不回退为圆角/切角外壳或大圆角半透明卡片；已安装 FontPack 时刘海中文/右侧入口/SafeExit/Toast/地图标签命中思源宋体，缺失时仍可用回退字体，FPS/数字/系统图标/Combo 字体不变；刘海折叠展开端点、透明 CompositeBounds 点击透传。
`PreparationNavigationV1` 默认 `true` 时必须完整显示「游戏 / 整备 / 辅助 / 系统」四行：游戏仅战队/平板/商城，整备固定装备/战备箱/装备调制/技能/材料/情报六项且与 Character Build 菜单同源；显式 `false` 或非法配置必须成套恢复旧「游戏 / 辅助 / 系统」三行、七项游戏行、Build header 与 `skills` focus。该 off fixture 只验证旧导航 presentation，任何生产入口仍须 Web-only fail-closed，不得恢复退役 AS2 全屏 UI。
材料入口不能叠在活动 Web panel 上，辅助行含点歌机/地图开关/修改器/帮助；
「系统 → 其他」的「控制/测试/工具」分类切换与随刘海收起、刘海内容硬裁切且与右栏至少留 12px、FPS 前景+BGM 低透明度包络、右侧 `252px = 3×50px 双字入口 + 3×34px 图标入口`、任务/SafeExit 单一状态槽优先级、SafeExit Saving/Done/Failed、Failed 取消/重试、Done one-shot 确认、raw/replay 拒绝、Done 5 秒无操作自动收起且悬停确认按钮暂停、地图无通知时不显示冗余 header、卡片只做 `compact ↔ expanded`、刘海只做显示/关闭、完整 Web 地图一击直达与中文 toast、combo/toast、
loot feed 与 panel 开关后 idle。
性能 gate：单次刘海展开/收起的 HWND placement 与 bitmap resize 各≤2，idle WebView2 保持 `SW_HIDE`，并对比 `nativeHud.boundsSource/repaintSource/commit` 计数与 p95。

**Loot feed 专项 gate**（完整事务/协议边界见 [玩家物资事务与双向播报 ADR](../docs/玩家物资事务与双向播报-ADR-2026-08-22.md)）：先跑 `scripts/run-player-asset-transaction-tests.ps1`（机器钉值见 [持久写与恢复](#save)）；该入口必须静态拒绝 `flashswf/**/*.xml` 直接调用 `PlayerAssetTransaction/ItemUtil`，并校验 asLoader 仍提供十个 `_root` 玩家物资门面。
协议定向测试必须覆盖 v1 必填/错型/source/正整数 safe-max、operationId+itemKey exact replay/冲突 replay、legacy 降级与 `eliteLevel` 缺失/非法/`0/1/2`，模型测试必须覆盖 gain/loss 合并隔离、饱和五槽下 reload immediate 抢占、`−1` layout、12 条任务奖励 `5/5/2` 无损轮播、pending 零老化、完整物资身份合并隔离、Boss 即时抢占、精英/拾取最小曝光后抢占、victim slot 原位复用、普通击杀身份压缩仍守恒、逻辑计数精确而视觉计数最多 8Hz，以及只在 gain `1→2`、
loss `9→10` 等方向感知计数位数桶变化时发布几何。
触及 `PlayerAssetTransaction` / `_root.发布物资事务回执` / `_root.发布物资变更消息` / `_root.发布战利品消息` / `_root.发布击杀播报` / `UnitUtil.getEliteLevel` 时追加精确 `scripts/compile_test.ps1 -Target publish`，只以 fresh Compiler `0/0` 与刷新后的 `asLoader.swf` 声称 publish-only 通过。
人工视觉覆盖还要确认 12px 名称/按需右计数列在战斗底图可读，96–220px/8px 内容宽度不为 `count=1` 预留空列且「摇滚公园基础资料集」不出现省略号，5 行不遮挡战斗中心，4px/180ms SmoothStep 入场与 280ms SmoothStep 退场无横向甩动，计数 180ms/1–2px 交叉淡化及数字区色洗/底沿在割草时可感知、在拾取时克制，并且无整卡缩放/弹跳/粒子，动画图标 450ms 后冻结。
性能采样要求 socket burst 任意时刻至多一个 UI drain 在途、同批一次决策、静态 hold 零 repaint、视觉重绘受 32ms 采样与 33ms overlay 合成硬边界限制在约 30/s、count commit 不高于 8Hz；同一计数位数桶内 count-only 不发布 bounds，跨桶只发布一次。loot feed 行为面：五个共享槽位 + 可恢复等待队列；
同 `direction/kind/itemKey/tier/派生调度策略/eliteLevel` 与一致展示合并，`operationId/reason/mergeScope/raw source` 不进入卡片身份、跨 source 只合并完全相同策略且隔离 `unknown`，等待期不计时；loss 用红色负号且数量一也显示 `−1`；`reload` 即时精确聚合；任务/通关奖励、开箱与 Boss 保真，精英/拾取可抢占杂兵，普通击杀仅身份溢出压缩；左下锚底且不与 toast 重叠；精英琥珀分段轨、Boss 金色双轨，任务/开箱不伪装为 Boss；失败提示仍走左侧文字区。

### PlayerInfo（SVG renderer / B0 系列）

**xUnit / PlayerInfo SVG renderer**：xUnit `powershell -File launcher/tests/run_tests.ps1`（先跑 exact-SDK 合同，再跑全量）；隔离 corpus 按 [专项工具入口](../tools/player-info-hud/README.md) 的 exact 10.0.300 locked restore → Release build → run。历史 B0-02 evidence 固定为 10/10 + 16、不得覆盖；
B0-04 canonical 报告只接受 12/12、78/78 fail-closed（58 项值级 grammar）、8/8 canonical 与 `rendererQualified=false`。
生产 renderer 资格另以 `tools/validate-player-info-svg-production-contract.ps1` 对真实 candidate 取得 `status=passed / mode=candidate / policyEligible=true`，并精确验证 11-file renderer-family/deps/唯一 target、负例、production policy、全量 xUnit 与 runtime/packer；`--core` 仅诊断。

**B0-05 raster/cache/topology**：必跑 `tools/player-info-hud/run-b0-05-runtime-qualification.ps1`；只接受 exact SDK/locked restore、fresh runId、canonical LF/无 BOM、32 Gate、最终 executable source/test DLL/Core/11-file target/15-file test-output closure 与 runner 重算。
v2 合同固定 8-field key（含 `sourceToBitmapIdentity`）、8 logical layer / 10 owned PArgb payload；任何 dotnet host 启动前拒绝已登记的 JIT/GC 环境覆盖，报告与脚本共同核验 Normal priority、继承 affinity 与 server-GC。parse/raster 只计 aggregate StrictSvg/Skia payload-slot operation，不冒充 PArgb copy completion 或逐 logical-layer 归因；
代表性 PArgb copy 诊断每 logical layer 一次且不含 `mp.fill` 两个 fragment。先以与 acceptance 相同的 `Task.Run`/fresh `Bake` 路径执行 16 轮四 viewport round-robin excluded warmup（64 个完整记录样本、无自适应停），再取每 viewport 20 个 acceptance 样本，nearest-rank p95 门为 100 ms。结果最多到 `passed / synthetic_fixed_bounds / split_required`。

**B0-06 focused**：必须覆盖完整 PlayerInfo namespace + `PanelHostHudCompanionTests`；formal runner 在任何 `dotnet` host 启动前复用 B0-05 exact 12 项 JIT/GC override 拒绝表，并由报告/runner 双向重建 JSON 真布尔类型（禁止字符串强制转换）、Normal priority、精确非零继承 affinity 与 server-GC=false；该合同进入 qualification status/failures，总数仍为 48 且未新增 Gate ID。
warmup 从 v1 的单组收敛收紧为连续两组，原 GDI/USER/process handle 数值门与趋势门不变；runner 固定 3000 visible、3000 idle、同一 STA/owner 上最多 5 个 100-cycle excluded lifecycle group；每组继续独立满足严格 handle envelope，只有首个连续两组均收敛的 pair 后才立即执行新的独立 100-cycle acceptance，五组内无合格 pair 只能 `diagnostic_after_warmup_cap` 并失败。
split commit p95 是 prepared-memory-DC `UpdateLayeredWindow` transaction；可复用 top-down PArgb DIB/DC 的 setup+cleanup 跨帧摊销，并由 lifecycle resource Gate 约束。commit `bf8dd2c…8479` 的 47/47、1737+3/1740、旧 run/hash 与 `visual-evidence.json` 全是 historical v1，不批准当前 v2。

**PlayerInfo gate**：改 canonical asset、manifest/planner、raster key/cache/pipeline、PArgb bridge 或其 executable closure，除上一段入口外还必须重跑 B0-05 formal runner；dirty diagnostic 不计 formal。人工视觉须单独确认 MP label/maximum/percent 左锚边、current 右锚边、低透明装饰底字关系，HP 两遍 Glow 与横线的可识别性，以及圆形 HP 球体未被遮罩/裁切。
改 `launcher/src/Guardian/Hud/PlayerInfo/`、PlayerInfo 的 Program/PanelHost 生命周期或 B0-06 取证工具时，另跑 PlayerInfo focused suite、B0-06 formal runner 与 C#/Web/direct-edge A/B；
fixture surface 必须保持 opt-in、独立 union、恒 click-through、无 `pi_*`，由 surface 单一持有/推进 animation model，widget 只读消费，Resume 只有在有效 plan + raster request 建立后才完成，且代码不得隐藏/修改旧 Flash HUD。PlayerInfo 人工项另含旧 Flash 与 fixture 同屏/分层、透明 crop、真实游戏 composite、关键比例与 41-tick HP 平滑、实际鼠标透传；headless Edge 或 computer-use 均不能代签。
自动 HWND/ULW 与图像闭包不代替 accepted Flash oracle、真实游戏 composite、DWM、z-order/occlusion、鼠标透传或人类审美验收。MP 四字段须 unique `bestDx=0`，且 label/maximum/percent 的 leading edge、current 的 trailing edge 各为 `dx=0`；cyan centroid 只诊断。

**Crafting materials v2 Host focused**：使用 exact SDK 10.0.300 执行 `dotnet test launcher/tests/Launcher.Tests.csproj --filter "FullyQualifiedName~CraftingTask"`，固定覆盖 command-specific v1/v2 gate、初始 v2→完整 v1 唯一降级、session/snapshot lock、versionless failure/correlation、v2 exact schema、六种 source union、UTF-16 `lp1` key、
boundary±1、finite/range/order/count/occurrence 与 O6 unavailable pair；
只证明 Host，不代签 AS2/Web/E2E/candidate/部署。

<a id="runtime"></a>
## 正式 runtime 发布与验收状态

**触发**：已获授权的正式发布、实际部署闭包变更，或发布工具/协议本身的维护。操作权威是 [runtime-build-reproducibility.md](../docs/runtime-build-reproducibility.md) 与机器真源；
当前正式 runtime 的身份、promotion 与专项验收只读 [runtime release consensus](../config/build/runtime-release-consensus.json)、[runtime manifest](../runtime/cf7-runtime-manifest.tsv) 和该文档，本节不复制 current identity/计数。

**验收状态阶梯（统一术语）**：`compiled → candidate_built → candidate_executed → e2e_verified → promoted → standard_entry_verified`。`dev.ps1` 默认成功启动最多到 `candidate_executed`，候选执行/E2E 必须绑定实际路径与身份；只有同一身份 promotion 后再由无参 `automation/start.ps1` / 根 bootstrap 标准入口验证，才可称「已部署 / 正式验收」。

**日常候选与发布入口**：

- 日常 Worktree 隔离功能检查：`automation/dev.ps1`（双击根 `本地开发启动.cmd`），可追加 `-Status|-ReuseOnly|-ForceBuild|-BuildOnly`；长路径隔离 Worktree 仅允许 exact `-ForceBuild -BuildOnly -CandidateLeaf <lowercase-alnum-hyphen-leaf>`，叶节点必须是 `tmp/runtime-candidates/v2` 的短 direct child、满足 bootstrap `<260` 预算且目标预先不存在，绝不 `ForceReplace`；
  它按当前 build identity 精确复用/生成 `NOT_DEPLOYED` candidate。
- 无参 `automation/start.ps1` = 正式已部署入口；`start.ps1 -CandidateRoot <absolute candidateRoot>` = 低层诊断兼容入口。
- 完整本地候选兼容编排：`launcher/build.ps1 -BuilderId local-dev`；纯 producer：`launcher/build-runtime-candidate.ps1`。
- 只验证正式双 builder quorum、明确不部署时，调用既有 `tools/promote-runtime-bundle.ps1` 的 `-VerifyOnly -ReportPath <absolute-new-json>`：仍完整重验 request/worktree/receipt/candidate/proofs/consensus 与 live deployment cleanliness，脚本声明的唯一仓内输出是 CreateNew 一份 `cf7-runtime-promotion-preflight.v2`，不得写 runtime/consensus，也不得把报告复用为 promotion 输入；
  正式 promotion 必须去掉两个参数全量重跑。

**`launcher/build.ps1` 的角色**：现在只是 prepare → pure producer → read-only policy 的兼容编排器，不签名、不入 quorum；producer 只在隔离 candidate 内生成根 EXE、Core/依赖、`miniaudio.dll`、`sol_parser.dll` 与 manifest v2，policy/Web/data 审计独立签发 receipt。
日常 Worktree 可见检查统一由 `automation/dev.ps1` 计算当前 build identity，精确复用或用 `-SkipPrepare -SkipPolicy` 生成 `NOT_DEPLOYED` candidate，再交给低层 `automation/start.ps1 -CandidateRoot`。
它只接受仓内 canonical 非 reparse v2 candidate，并要求安装哨兵、schema/manifest、Core SHA-256、build identity、payload closure 全匹配后才以自身 bootstrap `--verify-runtime-only` 启动；同身份闭包分叉、walk-up、候选树外目录、坏 marker 或身份漂移一律 fail-closed。断网重建需已安装锁定工具链并缓存 NuGet/Cargo 依赖；精确复用已有 candidate 不需要云端。
v2 将 artifact source、producer recipe、toolchain lock、policy 分为四个互斥域，build identity 只含前三域，payload closure 排除 manifest；相同 build identity 出现分叉 closure 必须停发。正式 request 以 Git tree+policy 冻结，worker 用隔离 clone、lease/heartbeat/mutex 与 CAS；
本地 proof 必须来自 tracked registry 中不可导出 X509 key，GitHub proof 必须经 repo/workflow/source-ref 固定的 OIDC/Sigstore 验真，quorum 同时要求不同 signer 与 faultDomain。

**正式发布链**：prepare 最终 tracked 资产 → `new-runtime-build-request.ps1 -SourceKind Treeish` 冻结 full commit → 注册本地 X509 worker + GitHub hosted OIDC/Sigstore 对同一 build identity/payload closure 取双 signer/双 faultDomain quorum → production policy receipt → `promote-runtime-bundle.ps1` → 无参 `automation/start.ps1` /
根 bootstrap 标准入口身份核对与领域 smoke。

**协议回归门（构建/发布协议改动固定跑）**：

- `tools/test-runtime-dev-entry.ps1`
- `tools/test-runtime-entry-guardrails.ps1`
- `tools/test-runtime-build-v2.ps1`
- `tools/test-runtime-release-policy.ps1`
- `tools/test-runtime-build-queue.ps1`
- `tools/test-runtime-github-attestation.ps1`
- `tools/test-invoke-runtime-github-build.ps1`
- `tools/test-main-branch-admission.ps1`
- `tools/test-runtime-release-state.ps1`
- `tools/test-runtime-build-consensus.ps1`
- `tools/test-runtime-release-consensus-v2.ps1`

改 VerifyOnly/report path 或 replay-window 稳定性时，后者必须覆盖 CreateNew、绝对 long path、protected/reparse/8.3 alias、输入与 live-deployment pre/post drift、无 runtime/release mutation、canonical bytes 与不泄露本机信息。另按改动追加 bootstrap `--verify-only`、`tools/cfn-cli`、`--bus-only`。

**Audit 与 source-ahead**：`audit-native-runtime` 只由 native/runtime 静态 paths 触发；普通 docs/data/Flash/XFL/Web-only 不启动。Audit 先做 path/binding，再在部署闭包未变时零 payload 哈希退出 `source-ahead`；根 EXE/runtime/manifest/consensus/builder registry 变化才执行 v2 strict，缺合法 promotion 必须事后红灯。workflow 不是 required context，不能预先阻止直推；v2 永久拒绝降级。

**候选 E2E 的 `resources` 路径前置**：完整 Flash 游戏候选 E2E 的项目根必须保留 `...\resources` 路径形态；这是现有 `PathManager` 建立 data/task 等资源基址的运行前置，而不是 candidate 身份的一部分。项目根为任意普通目录时，Core 可以启动且身份核验通过，但任务数据加载仍可能因资源基址为空而失败，不能记 `candidate_executed` 的功能 smoke。普通开发直接从 main 的 `resources` 根运行 `本地开发启动.cmd`，native candidate 自带隔离；
只有任务另需隔离时才使用 `<隔离目录>\resources` 工作树，不把 clean Worktree 或 Steam 所有权当作普通开发前置。该前置只用于完整游戏启动，纯构建、Host/Web/AS2 自动门不要求伪造目录名。

**Audio 通用发布解耦门（现役，覆盖旧「H2 前严禁 promotion/deployment」历史语句）**：改 `promote-runtime-bundle.ps1`、runtime input descriptor、native change gate 或 runtime Audit workflow 时，运行 PowerShell parse check、`powershell -ExecutionPolicy Bypass -File tools/test-runtime-build-v2.ps1`、
`tools/test-runtime-release-state.ps1` 与 workflow/path parity 回归。
静态门必须同时证明：promotion 不含 Audio H1/H2/E3 或 emergency 参数；verification window 精确绑定 `request.releaseTreeOid`；`config/audio-v2/**`、`docs/contracts/audio-v2/**`、`tools/audio-v2/**` 不进入通用 `policyHash` 或 runtime Audit path filter；
真正影响 DLL 的 `launcher/native/**`、`launcher/src/**`、Audio build-input manifest、decoder lock 与 producer 仍处于 artifact/producer/native gate。Audio H2 只决定专项 `e2e_verified` / `standard_entry_verified`，未完成时标记 `pending`；历史 emergency validator 测试只在维护历史工具时定向运行，不再是发布列车门。

**主线准入与发布授权门**：文档治理巡检跑 `node tools/validate-doc-governance.js`；另按改动跑 `tools/test-submit-contribution.ps1`（仅可选 PR 辅助回归）、`tools/test-main-branch-admission.ps1`、`tools/audit-main-branch-admission.ps1 -ExpectedState ConfigOnly|Prepared|Layered|Active`、`tools/test-invoke-runtime-github-build.ps1`。
现役准入事实（以 [contribution-workflow.md](../docs/contribution-workflow.md) 为准）：所有 write collaborator（含 `Crazyfs` / `Flash-Night`）可 fast-forward 直推且不需要 PR/check/CODEOWNER；远端仅有 `main-global-ref-integrity-v1`、`runtime-source-tag-creation-v1`、`runtime-source-tag-immutability-v1` 三条零 Actions ruleset。
迁移按 3 disabled + minimal classic → 3 active + minimal classic → 3 active 且 classic removed 逐态 fail-closed；native audit 全事件只接受首次 run，获授权手工 dispatch 必须强制 release-readiness 全链；cloud 只接受两个固定 actor ID 的首次 `workflow_dispatch`，负例覆盖其他 actor、repository_dispatch 与 rerun，artifact 覆盖 unsigned=1 天、diagnostics/signed=7 天。

**部署后表述**：standard-entry 只覆盖实际验证的功能/环境；记清尚未重跑的业务与感官验收。部署后只执行根 bootstrap `--verify-only` 与 post-promotion Audit 时，不得声称业务 `standard_entry_verified`。历史发布身份与收据不进本页，见 `docs/testing-guide-history-2026-09-17.md`。

## 迁移来源

本文件为 2026-09-17 一次性迁移自冻结 `agentsDoc/testing-guide.md`（114 物理行，source SHA-256 `5eb88fb231eb2c8858cf96f7bff310e3fcee247eb85dcf30006d8e8b3002ccc0`，HEAD `2e5e32321506fa1fb2693f3928205f8c45b4235e`）：活跃规则、runner、恢复合同与特殊门重组为本页；可证明的纯历史收据转入 [testing-guide 历史归档](../docs/testing-guide-history-2026-09-17.md)；
逐行处置台账见回包 `tmp/docs-decision-return-20260917/evidence/TESTING_MIGRATION_LEDGER.json`。本页是规范层常驻文档，不常驻历史发布列表；后续按领域命中自然维护，不建立每次施工回写本页的惯例。
