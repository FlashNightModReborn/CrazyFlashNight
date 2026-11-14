# Flash CS6 自动化编译指南

**文档角色**：Flash CS6 编译 smoke canonical doc。  
**最后核对代码基线**：commit `c475797b8afaf37e9b5fe7d805ca932a668d4ed8`（2026-11-14；补充多机器宿主兼容分流、机器级编译互斥锁、32 位 4 GiB VA 水位自动轮换与崩溃排障）。

本文件只讲 **Flash CS6 编译与 smoke 验证链**：计划任务、JSFL、trace、编译器错误、截图与故障排查。  
游戏启动与运行自动化请看 [automation/README.md](../automation/README.md)。
`compile_test.ps1` 只保存本次新增 Flash trace 到 `scripts/flashlog.txt`，并将 `[TEST_FAIL]` / `[FAIL]` / `Tests Failed: N>0`、缺失/陈旧/非 `0/0` 的 Compiler Errors 视为失败。

## 1. 当前定位

- Agent 可从终端触发 Flash CS6 `testMovie()` 或 `publish()`，并读取对应的 trace / 编译器输出
- 这条链路当前仍属于 **smoke 级验证**
- 没有目标所需的新鲜证据组合（至少本轮 `compiler_errors.txt` `0/0`；publish 另需 SWF 刷新，测试另需行为证据）时，不要直接声称“已编译通过”

## 2. 前提条件与多机器环境分流

- 已以管理员身份运行过一次 `scripts/setup_compile_env.bat`（部署 `cf7_compile_loader.jsfl`、`flash_project_path.cfg`、`mm.cfg`，并登记不限时的 `FlashCS6Task` 生命周期任务与显式调用 `Flash.exe "<Loader>"` 的 `CompileTriggerTask` 触发任务）
- 已登记 `FlashCS6Task` 时，无需事先手动启动 Flash CS6，显式传 `-Target` 时也无需预先打开 `TestLoader`（`compile_test.ps1` 会按需自动冷启动干净宿主并从盘打开目标）；仅在省略 `-Target` 沿用旧行为时才要求目标已在前台打开
- 已安装 Node.js；TestLoader 的 `function codeSize < 60000` 是硬门，缺少 `node` 或 `tools/swf-function-sizes.js` 时会在触发 Flash 前失败。非 TestLoader 目标缺少 Node 时，预编译 BOM 门仍只告警降级
- 如果近期更新过编译自动化脚本、换过仓库路径或换过机器，先以管理员身份重新运行一次 `scripts/setup_compile_env.bat -SkipCleanup`

### 多开发机兼容形态（标准安装 vs 绿色便携版）

不同开发机的 CS6 安装来源不同，**不要把某台机器的兼容层注册表硬搬到所有机器**：

1. **标准完整安装版 CS6（推荐新机形态）**：MSI 安装器已完整写入系统 COM / 许可项，**无需设置任何 `AppCompatFlags\Layers` 兼容标志**。直接运行一次 `scripts/setup_compile_env.bat` 建立双计划任务即可免弹窗、免 `.jsfl` 默认关联串台（与 Adobe Animate 共存时同样安全）。
2. **绿色便携版 CS6（需提权桥接形态）**：缺少系统级注册表项时直接普通启动可能报错退出，此时在 `AppCompatFlags\Layers` 中**仅保留 `~ RUNASADMIN`**，配合双计划任务（`RunLevel=Highest`）即可从非提权终端与 Agent 会话无感调用。**严禁额外勾选或保留 `WIN7RTM` / `WINXPSP3` 兼容模式**——实测 `WIN7RTM` 会强制注入 `AcLayers.dll` 兼容堆垫片，导致 `asLoader` 单次发布慢约 `25%` 并额外吞噬约 `216 MiB` 的 32 位虚拟地址空间，大幅提高长程施工 OOM 崩溃率（量化对照与新机只读自检脚本见 [`docs/flash-cs6-va-exhaustion-and-host-profile-2026-11-14.md`](../docs/flash-cs6-va-exhaustion-and-host-profile-2026-11-14.md)）。

## 3. 使用方式

### 目标选择速查

先判断改动属于哪一层，再选 `-Target`；默认频率 / 优先级是 **asLoader → TestLoader → main**，不要把“改了 `.as`”直接等价为 `main`。

| 层级 | 职责 | 典型改动 | 推荐目标 |
|------|------|----------|----------|
| asLoader 逻辑注入层 | 运行时 AS2 class / boot include / `_root` 方法与 WebView bridge 注入 | 多数 `scripts/类定义/`、`scripts/逻辑/`、`scripts/逻辑系统分区/*_WebView.as`、`*PanelService.as` | `-Target publish`（别名已隐含 publish-only） |
| TestLoader 测试层 | 测试入口、mock、专项断言、trace 验证 | `scripts/TestLoader.as`、测试 class、测试 fixture | `-Target test` |
| 主文件运行壳 | 运行入口、主 FLA 时间轴、主文件库元件、主文件 linkage | `CRAZYFLASHER7MercenaryEmpire/LIBRARY/*`、主 XFL/FLA、主时间轴帧脚本、主文件 linkage 变更 | `-Target main` |
| 独立资源 XFL / 子 SWF | UI、关卡、素材库等由主文件加载或引用的独立 SWF | `flashswf/UI/*/LIBRARY/*.xml`、`flashswf/levels/*/LIBRARY/*.xml`、`flashswf/arts/*/LIBRARY/*.xml` | `-Target <xfl> -PublishOnly -VerifySwf <对应.swf>` |

`main` 是主运行壳 publish-only 验证，只证明 `CRAZYFLASHER7MercenaryEmpire.xfl` 及其直接库资源已发布；它不是所有 `flashswf/` 资产的兜底目标。普通 asLoader 注入逻辑跑 `main` 不会证明 `scripts/asLoader.swf` 已更新；独立 UI / 关卡 / 素材库 XFL 跑 `main` 也不会证明对应子 SWF 已更新。若同轮跨层改动，按实际层级分别跑对应目标。

### PowerShell

```powershell
chcp.com 65001 | Out-Null
powershell -ExecutionPolicy Bypass -File scripts/compile_test.ps1
```

默认等待完成 marker 30 秒；慢 CPU / 低压设备可显式增大等待时间：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/compile_test.ps1 -TimeoutSeconds 120
```

### 选择编译目标（`-Target`，免手动切活动文档）

不传 `-Target` = 编译 **Flash 当前活动文档**（旧行为）。传 `-Target` 则由参数指定，脚本写 `scripts/compile_target.cfg`；`compile_action.jsfl` 读取后立即删除该文件，并据此 close+reopen 目标 FLA 从盘重读：

```powershell
# 测试构建（带 trace）：跑本机被 gitignore 的 TestLoader scratch 入口；仓库不保证固定 suite，专项施工须显式装入并记录 aggregate/template、suite 名与断言数
powershell -ExecutionPolicy Bypass -File scripts/compile_test.ps1 -Target test -TimeoutSeconds 180

# 发布构建：编 asLoader（别名自动走 doc.publish()，并启用 -VerifySwf scripts/asLoader.swf；无需再写 -PublishOnly）
# 注意：asLoader 现已超过 820 个类（~7.2 MB），冷宿主完整发布约需 600~800 秒，建议至少设 900 秒避免误超时留闸
powershell -ExecutionPolicy Bypass -File scripts/compile_test.ps1 -Target publish -TimeoutSeconds 900

# 主文件构建：只用于主 FLA / 资产 / linkage / 主时间轴相关改动
# publish-only（doc.publish() 不 testMovie），不会拉起整套游戏；产出仓库根 CRAZYFLASHER7MercenaryEmpire.swf
# 自动启用 -VerifySwf；成功判据 = Compiler Errors 0 个错误 + 主 SWF 已刷新
powershell -ExecutionPolicy Bypass -File scripts/compile_test.ps1 -Target main -TimeoutSeconds 300

# 任意 FLA/XFL（相对仓库根或绝对路径）
powershell -ExecutionPolicy Bypass -File scripts/compile_test.ps1 -Target scripts/asLoader/asLoader.xfl

# 独立资源 XFL / 子 SWF：先看同目录 PublishSettings.xml 的输出名，再给 -VerifySwf
powershell -ExecutionPolicy Bypass -File scripts/compile_test.ps1 -Target 'flashswf/UI/玩家信息界面/玩家信息界面.xfl' -PublishOnly -VerifySwf 'flashswf/UI/玩家信息界面.swf'
```

`test`|`testloader` → `scripts/TestLoader`（`doc.testMovie()`）；`publish`|`asloader` → `scripts/asLoader`（隐式 **publish-only** + 自动 `-VerifySwf scripts/asLoader.swf`）；`main`|`mainfile`|`empire` → `CRAZYFLASHER7MercenaryEmpire/CRAZYFLASHER7MercenaryEmpire.xfl`（隐式 **publish-only** + 自动 `-VerifySwf CRAZYFLASHER7MercenaryEmpire.swf`）。因此 `publish/asloader/main` 别名都可省略 `-PublishOnly`；只有任意显式 FLA/XFL 路径需要禁止 testMovie 时才额外传该开关。`-Target` 决定编哪个，无需手动切到前台；publish-only 在诊断落盘后自动以“不保存”关闭本轮目标，TestLoader/testMovie 则保持打开供调试。**注意：实测表明关闭 XFL 文档几乎不释放 CS6 内置 AS2 编译器全局单例池已保留的 32 位虚拟地址空间（VA）**；真正回收 VA 依赖下文的编译前脏宿主自动轮换或显式 `-QuitFlashAfterPublish` 退出进程。

`run-focused-testloader.ps1` 对异步 XML/SWF 加载和后续帧检查，在子编译成功后最多额外等待 `AsyncBehaviorTimeoutSeconds` 秒，从原始 Flash 日志补读本轮 domain/runId 的后续记录。`AsyncBehaviorTimeoutSeconds` 默认 30 秒，和 `TimeoutSeconds` 均接受 1 至 3600 秒；专用 runner 可明确覆盖异步等待值，例如盾冲入口为 600 秒，异步行为窗口独立于编译 `TimeoutSeconds` 计时。延长等待不改变用例、帧数 watchdog 或结果判据。取第一个本轮 Start 或 Complete 起的完整后缀，随后仍严格要求单 Start、单 Complete、顺序正确、期望断言唯一、无失败哨兵和零 32K 重试；不接受其他 runId 或从多个重复块中挑一段通过。无 GUI 回归入口为 `powershell -File tools/test-focused-testloader-trace.ps1`（10 个正确/错误 run、顺序、重复和失败哨兵夹具）。超时未闭合仍保留原有不确定状态恢复门。

批量发布大 XFL 时可额外传 `-QuitFlashAfterPublish`。该开关只接受 publish-only：JSFL 必须先完成 `doc.publish()`、保存 Compiler Errors、关闭目标并写 terminal marker，之后才 `fl.quit(false)`；调用方看到成功返回后再用既有 `FlashCS6Task` 启动干净实例。测试模式、畸形/残留 cfg 或 terminal 前退出都 fail-closed，不能用进程退出替代 SWF 刷新与 Compiler `0/0`。

此外，由于 32 位 `Flash.exe` 用户态 VA 硬上限为 `4,095.9 MiB`，而 `asLoader` 单次发布峰值已达约 `3.75~3.97 GiB` 且关文档不释放编译器内存池，`compile_test.ps1` 内置了**机器级互斥锁与编译前 VA 水位自动轮换保护**：
- **双层互斥锁**：除仓库级 `Local\CF7_FlashCompile_<RepoHash>` 外，同时获取机器级 `Local\CF7_FlashCompile_MachineGlobal`，防止同一台机器的多个 worktree 并发抢占唯一的 `Flash.exe` 实例、全局 Commands 目录与 `.aso` 缓存。
- **编译前脏宿主自动轮换**：非独占宿主租约（无 `testhost_ownership.marker`）下，若检测到当前 `Flash.exe` 的 `VirtualSize` 超过安全阈值（`asLoader` 目标 `> 700 MiB`，其余目标 `> 2400 MiB`），脚本会在写编译 cfg 前自动调用 `quit_owned_test_host` 安全关闭可丢弃测试文档并退出旧宿主，再经 `FlashCS6Task` 冷启动干净实例；若 CS6 内打开了未保存或非测试的外部美术/业务文档，`quit_owned_test_host` 拒绝退进程并立即 fail-closed 报错，绝不丢弃人工修改。每次编译结束或异常退出时，终端均会输出本轮 `[CS6 VA 水位]` 起点、峰值占比与驻留值。

显式目标若已经在 CS6 打开，`compile_action.jsfl` 会先以“不保存”关闭，写入一次性 `compile_reopen.marker`；`compile_test.ps1` 校验 exact 目标与模式后最多重触发一次，再从磁盘打开并编译，确保外部编辑的 XFL XML 是 source of truth。关闭与重开必须分属两次 JSFL 调用：Flash CS6 在同一调用栈内关闭并立即重开 XFL 时可能直接中止宿主脚本。publish-only 在完成发布、保存 Compiler Errors 后还会关闭刚发布的目标；该尾部关闭发生在 terminal marker 之前，关闭失败不能伪装成成功。比较 cfg URI 与 `doc.pathURI` 时只做纯字符串 URI 解码、斜杠和大小写归一化；不要对所有已打开文档调用 `FLfile` 平台路径转换，未保存或含非 ASCII 路径的其他 XFL 可能让 CS6 绕过 JavaScript `try/catch` 整体中止。中文路径在两处可能分别表现为直写 Unicode 与 percent-encoded URI；不归一会漏关带 `*` 的旧文档，使 `doc.publish()` 复用旧 symbol 缓存。部分独立 XFL 在重开时会弹缺失字体确认框，计划任务会一直等不到 terminal marker；编译时间异常拉长时先截图/检查 CS6 前台并人工确认，不要重复触发多个编译任务。`-VerifySwf` 只能证明文件被重写，关键 XML 帧脚本还应以 FFDec 导出 script 检查新增标志串是否进入 SWF。

> ⚠️ **编译单元归属铁律（踩过坑）**：`scripts/类定义/` 下的 **类**（如 `*PanelService`）与 `scripts/逻辑系统分区/*_WebView.as`、`scripts/展现/UI交互/*.as` 这些 **boot `#include` 脚本** 都编进 **asLoader**——asLoader 编译 class + 把方法注入 `_root`（`_root.gameCommands.*` 等）全局提供给主文件和其他 SWF 使用。**改这些必须 `-Target publish`（asLoader），`-Target main` 不会生效！** `-Target main` 只编主文件 FLA 自身的元件 / 时间轴帧脚本（如 `Symbol 1770`、主文件库元件增删）。判断方法：被改的东西在 `asLoaderManifest`(`grep 文件名 scripts/asLoaderManifest/`) 里 → 用 `publish`；路径属于 `CRAZYFLASHER7MercenaryEmpire/` → 用 `main`；路径属于 `flashswf/UI/*`、`flashswf/levels/*`、`flashswf/arts/*` 这类独立 XFL → 找同目录 `.xfl` 和 `PublishSettings.xml` 输出 SWF，用显式 `-Target <xfl> -PublishOnly -VerifySwf <swf>`；两边都动了 → 分别编。验证可 `ffdec -export script` 后 grep 改动标志串确认进了哪个 SWF。

独立资源 XFL 的输出位置通常不在该 XFL 子目录的 `bin/` 下；`bin/` 多为 XFL cache。以 `flashswf/UI/玩家信息界面` 为例，源入口是 `flashswf/UI/玩家信息界面/玩家信息界面.xfl`，发布产物由 `PublishSettings.xml` 指向 `flashswf/UI/玩家信息界面.swf`。改 `LIBRARY/*.xml` 后，主文件 `-Target main` 刷新不代表这个 SWF 已刷新。

**先确认是否需要发布，再定位编译单元**：上述归属规则适用于实际需要交付的运行时改动。已迁 Web 的历史 UI、未进入时间轴/export 闭包的库副本，可以保留源码修正而不刷新旧 SWF；shared import 的本地脚本副本也不会编进 importer。不得把一次静态全库扫描直接展开为全量 CS6 弹窗队列。生产入口与 RSL 实例的核对方式、R1 从 11 项试编收窄到 5 项交付的实例见 [迁移护栏](../agentsDoc/as2-web-panel-migration.md)与 [R1 收尾记录](../docs/R1存盘API迁移收尾-2026-09-05.md)。Flash 在 fresh Compiler/SWF 检查完成后按 `-QuitFlashAfterPublish` 退出属正常终态，不需要重新打开补编。

**test 与 publish-only 的差别**：`test/testloader` 走 `doc.testMovie()`；`publish/asloader` 与 `main/mainfile/empire` 别名都隐式走 `doc.publish()`，任意显式路径则只有加 `-PublishOnly` 才切到该模式。此前 `publish/asloader` 别名只自动设置 `VerifySwf`、却误走 testMovie，现已修复为在解析别名时同时写入 publish mode。publish 只编译产出 SWF + 填充 Compiler Errors，不启动测试播放器；主文件 testMovie 会启动整套游戏并可能因 launcher socket / 反盗版层留下僵尸窗口。模式由 `compile_test.ps1` 写 `scripts/compile_mode.cfg`（`publish`/缺省 `test`），`compile_action.jsfl` 读取后选 `publish()` vs `testMovie()`，一次性指令读到即删。publish-only 不产新鲜行为 trace，`flashlog.txt 未刷新` 属正常；判据是本轮 `compiler_errors.txt` 与 `-VerifySwf` 刷新门。预编译 BOM 门已扩展覆盖主文件 classpath 高频迁移类子树 `arki\task`/`arki\merc`/`arki\stageSelect`。

### Bash

测试模式在新 `testMovie()` 前调用 [`fl.closeAllPlayerDocuments()`](https://help.adobe.com/archive/en_US/flash/cs4/flash_cs4_extending.pdf)，关闭旧测试播放器，避免其继续向共享 trace 写入重复记录；编辑文档保持原有重开规则。普通 publish-only 不执行此清理；显式 `-QuitFlashAfterPublish` 在退出前结束测试播放器。该选项会丢弃其他打开文档的内存修改，只在本轮拥有这些文档且磁盘原件已保全时使用。终端 marker 与该调用不证明 CS6 进程已退出，后续需要空闲前台时必须另核实际窗口/进程。无 GUI 顺序验证为 `node tools/test-flash-compile-jsfl.js`，真实行为仍须唯一闭合 runId，不以去重日志代替通过。

```bash
bash scripts/compile_test.sh
```

`compile_test.sh` 会把参数原样透传给 PowerShell 脚本：

```bash
bash scripts/compile_test.sh -TimeoutSeconds 120
```

`TimeoutSeconds` 允许 `1..3600`，只调整等待 marker 的轮询上限，不改变编译内容或成功判据。

`compile_test.ps1` 在 `Start-ScheduledTask` 前先写本轮 exact-owned in-flight `scripts/compile_state_uncertain.marker`；`[TIMEOUT]`、触发后的 host 崩溃或其它非 terminal 退出都会保留它，后续编译在仓库 mutex 内 fail-closed。terminal 路径只删除内容仍与本轮 in-flight body 完全相同的文件，避免旧 lease child 擦掉另一故障刚写入的新闸。非 terminal 路径保留 `compile_target.cfg` / `compile_mode.cfg` 给迟到 JSFL 按原目标消费，不能提前删 target 后让它回退并误编当前活动文档。focused / map / Gobang / protocol scratch writer 另在改写 `TestLoader.as` 前创建 `scripts/.testloader-scratch-recovery/<token>.as`、验证原件 SHA-256，并写 `scripts/testloader_scratch_inflight.marker`；普通编译见该 marker 一律拒绝，只有 installed/original SHA-256 均验证后才删除 marker 与 sidecar。先确认 Flash / `CompileTriggerTask` / 旧 test player 已静止并核对迟到的 marker、SWF 与 diagnostics；若 scratch marker 仍在，按其中 `backup_path/original_sha256/had_runner` 恢复 `scripts/TestLoader.as`，不能只删闸或把遗留 scratch 当原件。完成这些人工复核后再删除 compile uncertain marker；下轮在触发前会清理未被迟到 JSFL 消费的旧 cfg。lease 不是鉴权，marker 是人工复核与恢复材料，不会自动猜测覆盖。

首次冷启动由既有 `FlashCS6Task` 承接编辑器生命周期，再由 `CompileTriggerTask` 向它递交 JSFL。后者安装时有30秒执行上限，直接用它启动编辑器会提前终止较大的编译，即使外层等待设为180秒也无效。入口只接受同一个 CS6 程序、无参数、Highest、不限时的已登记启动任务；任务不符或15秒内没有进程则在编译触发前失败，不修改计划任务权限或时限。外层超时与不确定状态恢复规则照旧。

二阶段重开请求是事务内握手，不是 terminal 成功证据。marker 正文固定为两行 exact `targetURI` + `test|publish`；PowerShell 只接受与本轮目标/模式一致的一次请求，漂移、畸形或第二次请求立即失败并清理本轮 cfg。首次 JSFL 返回后才允许重新触发计划任务，防止同一宿主调用栈内 close/open；成功、已知失败等 terminal 路径都会清理该 marker，timeout/nonterminal 则继续由 uncertain marker 阻断后续编译。可选 `compile_quit_after_publish.cfg` 只接受 exact `quit` 且读取即删，PowerShell finally 也会清理未消费指令，避免迟到退出污染下一轮。协议静态回归入口为 `node tools/test-flash-compile-jsfl.js`。

仓库内唯一受支持的人工编译入口是 `compile_test.ps1` / `compile_test.sh`；`cf7_compile_loader.jsfl` 与 `compile_action.jsfl` 只是该事务内部组件，不应单独打开或执行。旧诊断入口 `test_publish.jsfl`、`test_trace.jsfl` 以及绕过事务的 `train_cycle.sh` 已删除；Gobang 长耗时回归改走持同一仓库 mutex 的 `gobang_trainer_cycle.ps1`。

<a id="read-only-player-recovery"></a>
### 只读测试的自动停止与独占宿主

可响应的旧 Test Movie 使用 `powershell -File scripts/compile_test.ps1 -StopTestPlayers`。控制仍持仓库 mutex、验证任务和 scratch admission；独立 nonce 回执确认关闭，再由下一次宿主调用确认 `closed=false`。该操作不编译、清面板、退出编辑器或自行清未知闸，控制回执存入 `tmp/flash-testplayer-control/`。迟到/错误 nonce、重复出现的播放器、未消费 cfg、宿主漂移或超时均拒绝恢复。Windows `Responding` 仅是采样提示，不能代替新鲜 JSFL 回执；CS6 冷初始化时可能短时为 false。

`run-focused-testloader.ps1 -AutoStopReadOnlyPlayer` 的封闭白名单由 runner 源码裁决，限本轮已审阅的内存/只读 debt/probe；四个 debt runner 默认选用它。保留原失败及本轮原始 trace、Compiler、SWF，核对停止和迟到产物、SHA-256 恢复 scratch 后，才 exact-match 清本轮行为未知 marker。无 Complete、断言失败或异常仍返回失败；自动停止不是通过证据。持久写、真实槽位、交易/奖励及 DeliveryUnknown 不使用此例外。

可能卡死的只读测试可显式加 `-OwnedReadOnlyHost`。前置是无既有 Flash；用既有 `FlashCS6Task` 创建新宿主，绑定 PID/创建时刻/任务 executable，并由新鲜 JSFL 回执证明文档仅为可丢弃的 TestLoader。文档 open/new/切换监视器发现其他或未保存文档即写 taint，拒绝自动结束宿主。该宿主运行期间不要用于其他编辑工作。正常/失败收尾均只停止这次任务拥有的宿主；必须确认实际进程消失、trigger 与 lifecycle 任务空闲、迟到产物稳定、原件恢复及 marker exact-match，才能清本轮闸。不会盲重放，也不结束原先用户编辑器。

确需给独占测试腾出宿主时，`-QuitOwnedTestHost` 仅接受空编辑器、可丢弃 TestLoader，以及 `compile_action.jsfl` 明列的六类CF6生成测试宿主（含地面拾取RSL宿主）；须属于本轮且已保全磁盘源及scratch原件。使用精确路径，不按前缀或通配放行其他、未保存或美术文档。inspect/output独占租约仍仅接受TestLoader。第一轮仅关闭目标，下一轮空编辑器才退出，另核实际进程退出；不能把退出请求回执当作退出。普通发布不带这些选项。

协议回归：`node tools/test-flash-compile-jsfl.js`、`powershell -File tools/test-testplayer-control.ps1`、`powershell -File tools/test-focused-testloader-trace.ps1`。独占路径的真实新宿主/文档事件/进程退出仍由 focused 运行证明；只读例外不改变上文一般未知写与人工恢复合同。

`run-student-repair-asset-tests.ps1` 默认使用独占宿主，验证全部70例时间轴及必要的位图断言。完整图像导出按需传 `-ExportBitmaps`，其成本与日常行为门分开；用例范围、无损行输出和入口见 [专项 README](test-runners/student-repair/README.md)。完整图像模式使用持同一mutex的 `clear_owned_test_output` 控制定期清空本轮已绑定、无taint的 Output Panel；仅清屏幕缓冲，原始 Flash Player 日志、Compiler 和既有输出文件保持。CLI `-ClearOwnedTestOutput` 还要求本轮 active scratch lease；独立nonce回执必须包含 `owned=true/output_cleared=true`，不关闭播放器、不改变宿主ownership nonce。迟到回执不放行，下次编译仍防御未消费控制cfg。focused 的 `TimeoutSeconds` 约束编译，`AsyncBehaviorTimeoutSeconds` 独立约束异步行为，不以编译预算截短行为等待。

## 4. 当前链路

```
compile_test.ps1 / compile_test.sh
  → 取得仓库级 CF7_FlashCompile_<RepoHash> mutex（scratch 父 runner 以 exact-match lease 复用）+ 机器级 CF7_FlashCompile_MachineGlobal mutex
  → 显式 TestLoader 目标先检查 node + swf-function-sizes.js；缺失则不触发 Flash
  → 检查现有 Flash.exe VirtualSize 水位（asLoader > 700 MiB / 其余 > 2400 MiB 且无独占租约时，经 quit_owned_test_host 自动轮换干净宿主；有外部/未保存文档则 fail-closed）
  → 若 Flash.exe 未运行，先由不限时 FlashCS6Task 冷启动编辑器并等待 UI 响应
  → Start-ScheduledTask 'CompileTriggerTask'
    → 已配置的 Flash.exe "<CF7 Loader 路径>"（Highest，不依赖 .jsfl 默认关联）
    → cf7_compile_loader.jsfl
      → compile_action.jsfl
        → 目标已打开时关闭并写 compile_reopen.marker 后返回
  → 若收到重开请求：校验 exact target/mode，最多重触发一次 CompileTriggerTask
    → compile_action.jsfl（目标原本未打开，或二阶段重触发）从磁盘打开目标
        → 清空独立 Compiler Errors 面板并删除旧导出
        → 按 compile_mode.cfg 选择 doc.testMovie() 或 doc.publish()
        → publish-only 保存诊断后关闭本轮目标；testMovie 保持打开
        → fl.compilerErrors.save()（只保存本轮诊断）
        → 仅当唯一汇总可解析、warnings=0、且汇总前逐行含「32K」的诊断数恰等于 errors 时重试一次
          → 首轮诊断先 trace 到 Output Panel；混合/多行上下文/汇总后文本/不可解析格式均不重试
          → publish_done.marker / flashlog / compiler_errors
  → marker 后输出本轮 [CS6 VA 水位]，要求 compiler_errors 本轮刷新且严格 0/0
  → TestLoader 另要求 SWF 刷新与 codeSize < 60000；生产 SWF 另核类归属门与继承顺序门
```

## 5. 关键产物与判据

| 文件 | 用途 | 判读方式 |
|------|------|----------|
| `scripts/flashlog.txt` | Flash trace 副本 | 优先看是否为本次运行新鲜生成 |
| `scripts/compile_output.txt` | Output Panel 副本 | 辅助看 JSFL / 输出面板文本；若触发纯 32K 重试，首轮完整诊断保存在这里 |
| `scripts/compiler_errors.txt` | 最终 Compiler Errors 面板副本 | JSFL 会在每个目标编译前清独立面板并删除旧导出；PowerShell 要求文件存在、身份/mtime 属于本轮且内容严格 `0/0`；若发生纯 32K 重试，本文件属于第二轮 |
| `scripts/compile_reopen.marker` | JSFL → PowerShell 二阶段重开请求 | 仅为一次性内部握手；exact target/mode 且每轮最多一次，不能视为完成或成功 |
| `scripts/publish_done.marker` | JSFL 触发完成标记 | 不能单独代表编译并运行成功 |

2026-07-21 17:12:59 +08 的最终资源箱回归使用 `-Target publish`（未额外传 `-PublishOnly`）实际走 `doc.publish()`：生成 `scripts/asLoader.swf` **1,041,903 bytes**，SHA-256 `AD799970A8A2AFD0F9A402C704934F08985A3144FA608A7564E17BC4899C815E`，Git blob `3dd59f73f9fc71128da99c2eb03796290df1e010`；本轮 Compiler Errors 为 **0/0**。该 publish-only 证据只证明目标 SWF 刷新与编译器零错误，AS2 行为结论由随后独立 fresh TestLoader 的 **166/166** trace 支撑。

### 正确表述

- `已完成 Flash CS6 自动化 smoke 验证`
- `已触发 Flash CS6 编译并拿到新鲜 trace`

接近 AS2 单分支 32K 上限的旧类在切换 XFL 后可能出现首次 ASO 编译失败、同目标再次编译通过。JSFL 只接受保守的一行一诊断格式：唯一最终汇总可解析、errors>0、warnings=0，且汇总前恰有同数量的非空诊断行、每行自身含 `32K`。只要混有语法/链接错误、多行上下文、汇总后文本或无法解析，就不重试。重试前的完整诊断会 trace 到 `compile_output.txt`，第二轮诊断才写入最终 `compiler_errors.txt`；第二轮仍失败则照常失败。focused runner 只接受唯一闭合 runId block，且健康基线必须 `32K retry=0`；自动恢复只能作为诊断证据，不能冒充健康通过。

首轮 32K 诊断在进入重试前即保存到 `compile_output.txt`，无需等第二轮完成。第二轮 `publish/testMovie` 可能清空 Output 面板；最终副本会在缺失时补回标明首轮来源的诊断段，避免把实际重试漏计为零次。长耗时或原生崩溃时先读该文件定位首轮错误，不把 CPU 活跃视为构建进展，也不因已有 suite Complete 就忽略编译器诊断或重复 runId。

### 不正确表述

- 只看到 `publish_done.marker` 就说 `已编译通过`
- 缺少该目标要求的新鲜证据组合还说 `编译成功`（例如 publish-only 缺本轮 Compiler Errors `0/0` 或目标 SWF 刷新；testMovie 缺其要求的 trace / Output 证据）

asLoader发布还会核对实际类继承注册顺序（`tools/check-as2-inheritance-order.js`）：父类DoInitAction必须先于派生类。缺失或倒序不会因Compiler 0/0而放行；此门针对完整加载器的类初始化，不由较小TestLoader通过代替。

## 6. 当前边界

- AS2 帧脚本中的类型错误、未声明变量不会稳定体现在编译期错误里
- 只有语法错误和 class 文件中的静态类型错误更容易被自动捕获
- 长耗时套件可能超过默认 30 秒轮询上限；先确认 Flash / TestLoader / 计划任务状态，再按需用 `-TimeoutSeconds` 调大
- **被 FLA 帧脚本 `#include` 的 `.as` 文件失去 BOM 时，CS6 编译器静默跳过其内容**，生成 SWF 的对应帧 DoAction 为 0 字节，但 `compiler_errors.txt` 仍报 `0 个错误`、`publish_done.marker` 正常落盘、`compile_test.sh` 报 `[OK] 编译完成` —— smoke 链路无法捕获此类静默失败
- 遇到“marker 成功但没有 trace”，优先怀疑：
  - 旧环境残留
  - TestLoader 未正确打开
  - Flash IDE 编译器错误
  - `TestLoader.as` 或其它被 `#include` 的帧脚本 `.as` 丢失 BOM（见 §8 同名条目）

## 7. 截图与界面检查

需要查看 Flash CS6 当前状态时，可使用：

```powershell
chcp.com 65001 | Out-Null
powershell -ExecutionPolicy Bypass -File scripts/capture_screenshot.ps1
```

适用场景：

- UI 排版检查
- Output / Compiler Errors 面板复核
- 运行时画面与窗口状态确认

## 8. 故障排查

### 等待上限内无 marker

- Flash CS6 未运行
- TestLoader 未打开
- `CompileTriggerTask` 不存在或失效
- Loader / `flash_project_path.cfg` 未部署
- 慢 CPU / 低压设备尚未完成；排除前述环境问题后，用 `-TimeoutSeconds` 调大重试

### `CompileTriggerTask` 返回 Access Denied

- Windows 沙箱可能允许读写仓库，却拒绝读取 Task Scheduler；这不等于计划任务不存在，也不代表 CS6 编译链损坏
- `compile_test.ps1` 会把该情况明确报告为“无权读取”，应先批准同一条编译命令在沙箱外运行
- 只有沙箱外运行仍明确报告任务缺失时，才以管理员身份重跑 `scripts/setup_compile_env.bat`

### marker 已生成但 `flashlog.txt` 为空

- 先看 Flash IDE 的 **输出 / 编译器错误** 面板
- 再看 `scripts/compiler_errors.txt`
- 再核对 `scripts/compile_output.txt` 和真实 `flashlog.txt` 时间戳
- 若 `compiler_errors.txt` 报 `0 个错误`、SWF 体积异常小（kB 级而非数十 kB）、debug player 直跑也无 trace —— 大概率是被 `#include` 的帧脚本 `.as` **丢了 BOM**，编译器静默跳过 include 内容，生成空帧脚本。验证手段：

  ```bash
  "/c/Program Files (x86)/FFDec/ffdec.bat" -export script ./tmp_swf_dump scripts/TestLoader.swf
  ls -la tmp_swf_dump/scripts/frame_1/DoAction.as   # 0 字节 = 帧脚本未被编译进去
  head -c 3 scripts/TestLoader.as | od -An -tx1     # 应为 ef bb bf；若不是则补 BOM
  ```

  修复后用 IDE 的"另存为 UTF-8 with BOM"重写一次，或用 `printf '\xef\xbb\xbf'` 前置后再编译

### 重启后仍停在导出 SWF，或完整类编译发生原生异常

专项 `testMovie` 结束不等于测试播放器已退出。涉及 `SaveManager/ServerManager` 的夹具可能在断言终态后继续发现端口、连接正在试玩的 Host；这类夹具须与真实试玩隔离。已确认本轮终态并还原 scratch 后，先用 `compile_test.ps1 -StopTestPlayers` 取得两阶段回执；大包发布需要干净宿主时，再用 `-QuitOwnedTestHost` 核对只剩本轮 TestLoader/空编辑器并确认实际退出。新宿主应先取得一次无播放器的 JSFL 回执，再发布；进程存在本身不证明编辑器已就绪。共享宿主有其他或未保存文档时继续保持关闭闸，不能结束整个进程。

先保留本轮输入、Output、Compiler、未完成SWF及未知marker，区分仍在消耗CPU的编译与长期无进展的导出。检查本机 `%LOCALAPPDATA%\Adobe\Flash CS6\<语言>\Configuration\Classes\aso` 是否存在与故障时间对应的0字节类缓存；重启不会重建这些磁盘缓存。空缓存是排查线索，不能仅凭它认定故障原因。

确认本轮独占测试宿主已退出、计划任务空闲、scratch原件按SHA-256恢复且迟到产物稳定后，按既有未知状态恢复规则收束失败；再记录空缓存的完整路径、时间、大小与摘要，将该文件移入本轮证据目录保全。只隔离已核对的异常缓存，不清空全局缓存或修改源码绕过。重新运行同一源输入，要求缓存重新生成、新鲜Compiler `0/0`和完整suite行为；失败原件继续保留。仅有导出进度变化不能称验证通过。

若编译期间 `Flash.exe` 直接异常退出或卡死在 `"FlashPro Fatal Exception"` 弹窗，结合终端输出的观测峰值 VA 按以下三类分流处置（详细反汇编与 21 份转储证据见 [`docs/flash-cs6-va-exhaustion-and-host-profile-2026-11-14.md`](../docs/flash-cs6-va-exhaustion-and-host-profile-2026-11-14.md)）：

1. **低水位崩溃（观测峰值 VA `< 2.0 GiB`）**：通常不是内存耗尽，而是 AS2 编译器前端在特定包通配 `import pkg.*` 或跨类符号消解时触发确定性空指针（如 `+0x1062FB0`）。此时重启宿主或电脑无效，应检查本轮新增/改动的 `.as` 与 `import` 写法。
2. **高水位崩溃（观测峰值 VA `> 3.1 GiB`）或 32K 重试期退出**：32 位 `Flash.exe` 连续虚拟地址段耗尽（倍增内存池调用 `std::nothrow` 返回 `0` 后解引用）。核对本机 `AppCompatFlags\Layers` 未开启 `WIN7RTM`、确保在干净冷宿主上单跑 `asLoader`（`-TimeoutSeconds 900`），并检查 `compile_output.txt` 是否因单类字节码贴近 `32 KB`（`DoInitAction` 的 `SI16` 分支上限）触发了同进程二次编译重试；贴墙类应拆小以消除重试。
3. **模态异常框卡死或长开机后期连续段挤压**：若 `Flash.exe` 卡在 `"FlashPro Fatal Exception"`（如 `0xC0000374`）使非提权终端无法 `Stop-Process`，且该实例由 `FlashCS6Task` 拉起，可执行 `Stop-ScheduledTask -TaskName 'FlashCS6Task'` 跨 UIPI 收束残留进程，再按上文核对静止态并清理本轮闸门；若干净冷宿主仍在 `~3.15 GiB` 处反复分配连续大块失败，重启 Windows 以刷新 WoW64 高地址系统 DLL 映射基址。

### 仍然弹 UAC

- **`CompileTriggerTask` / `FlashCS6Task` 必须 `RunLevel=Highest`**（`setup_compile_env.ps1::Register-CompileTask` 的默认值），并且编译任务直接执行已配置的 `Flash.exe`，参数为带引号的 CF7 Loader 绝对路径。旧版 `cmd /c start` 仍会经过 `.jsfl` 文件关联；与 Animate 共存时可能弹出打开方式选择器，并在选择程序后再次请求 UAC，不能仅凭 Highest 判定整条链路免弹窗。
- 绿色便携版 Flash CS6 在部分机器上需要在 HKCU/HKLM `SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers` 下保留 `Flash.exe = ~ RUNASADMIN` 才能启动（去掉直接运行失败），但**不要附加 `WIN7RTM`**；标准完整安装版则无需该兼容项。
- 以管理员身份重新运行 `scripts/setup_compile_env.bat -SkipCleanup`，一次性更新两个已有任务并保留编译诊断；这次安装需要人类确认 UAC。日常触发使用计划任务，避免直接从未提升终端启动 Flash.exe。
- 核对任务 Execute / Arguments / RunLevel 后实际触发 JSFL，再用新鲜 Compiler Errors 和 SWF 刷新验证。兼容读取旧任务不代表已修复；无需修改系统默认应用或关闭 UAC。

### 打开文档时弹出缺失字体

字体弹窗属于文档依赖，显式调用 CS6 不会自动消除它。先定位 XFL 的 `DOMTextAttrs.face` 和实际文本：真实素材应补齐原字体或核对替代效果；共享库的编辑器占位标签可使用本机已有字体。本轮 `things-new.fla` 中 `敌人-诺艾尔` 的两个中文导入标签从缺失的 Broadway 改用 MicrosoftYaHei，保留原 `linkageImportForRS` / `linkageURL`，不改实际敌人 SWF。新 Codex 武器库采用原生矢量形状，不引入字体。未知弹窗仍须观察后处理，不能用超时重试或统一回车掩盖。

2026-09-11 主文件整合中，两个导入占位标签（同盟通路/卸货站）的 6 处 `FranklinGothic-Demi` 改为本机已有 `MicrosoftYaHei`；金币/K 点两个导入占位的未声明 `Bebas Neue*` 改为已安装同字体的 PostScript 名 `BebasNeue-Regular`。四个元件保留原 Import linkage、URL、文本、矩阵及版式属性，不改其实际来源 SWF。主文件经标准发布入口 13 秒完成，Compiler 0/0；这证明本轮打开和发布正常，不将上次超时唯一归因为字体。设备字体 `_sans` 与其他已安装字体不属于缺失字体，不能仅凭扫描不到字体文件便替换。

### 游戏仍运行时读取测试日志

游戏与CS6测试播放器可能同时持有 `flashlog.txt` 的写句柄。编译入口以 `FileShare.ReadWrite` 读取打开时的固定长度字节快照，focused runner的异步收尾也允许共享读取；不要求测试员为取日志退出游戏。仍保留原始前缀比较、本轮nonce、唯一有序Start/Complete、Compiler 0/0与零32K重试门，不能把其他运行实例的输出当本轮证据。

2026-09-08 血剑回归曾在 `target closed; request second-phase reopen` 后超时；触发任务已回到Ready，目标cfg仍未消费，旧TestLoader.swf未刷新，CS6已无打开文档。确认这些事实、TestLoader.as逐字节恢复及本轮token后，先归档再清除本轮marker/cfg；从关闭目标状态重新运行得到56/56与Compiler 0/0。超时样本保留，不计为通过；本次未改动二阶段重开协议，也未进一步认定未消费请求的内部原因。

## 9. 相关文档

- 启动与运行自动化：[`automation/README.md`](../automation/README.md)
- 测试矩阵：[`agentsDoc/testing-guide.md`](../agentsDoc/testing-guide.md)
- 按需验证细节：[`agentsDoc/testing-details.md`](../agentsDoc/testing-details.md#flash-core)
- 32 位 VA 耗尽取证与单机宿主对照档案：[`docs/flash-cs6-va-exhaustion-and-host-profile-2026-11-14.md`](../docs/flash-cs6-va-exhaustion-and-host-profile-2026-11-14.md)
- 顶层硬约束：[`AGENTS.md`](../AGENTS.md)
