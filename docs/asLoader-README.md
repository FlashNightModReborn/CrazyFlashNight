# asLoader 启动架构 · 导览与待测

**文档角色**：asLoader 启动子系统的**入口导览**（反直觉架构的心智地图 + 验证状态 + 测试入口）。深层细节下沉到设计 / 施工 doc，本文只回答「这是什么、为什么这么怪、验了什么、还要测什么」。
**最后核对代码基线**：commit `56c697896f9a854fcb4fd81a8c47e3108e7b290e` + 2026-11-15 本地未提交三模块工作树。§5 保留 commit `b4d1267d51e5bdf4957fe56d21f6ee2c0a5049de` 后 2026-07-25 工作树的历史验证；历史计数和运行回执不代表现役产物，当前数值以重新生成、SWF 扫描及对应执行记录为准。
**深层 doc**：[架构设计](asLoader重构-架构设计-2026-06-15.md)（为什么这么设计 + P0-P6 路线）· [BootSequencer 构建标准](asLoader-BootSequencer-构建标准-2026-06-16.md)（启动契约 + §5 边界 runbook）· [asLoader / TestLoader 维护性路线](asLoader-TestLoader维护性重构-架构路线-2026-07-24.md)（维护性施工路线；阶段状态以该文档为准，当前构建入口与门禁以本文为准）。

## 0. TL;DR（先读这段）

asLoader 是游戏启动代码子系统。主影片仍从 `scripts/asLoader.swf` 导入同名 symbol；生产类按 `tools/asloader-modules.json` 分属原入口、共享库和启动逻辑三个 SWF，每个类只能有一个 owner。有界定义帧仍安装同一组函数，末帧才启动状态机，业务阶段顺序不变。

### 编译模块与装载合同（2026-11-15 候选）

原入口只驻留 `SaveManager` 并装载代码（XFL 与输出 SWF 映射：`resident` = `scripts/asLoaderBootstrap/asLoaderBootstrap.xfl` → `scripts/asLoader.swf`；`shared` = `scripts/asLoaderShared/asLoaderShared.xfl` → `scripts/asLoaderShared.swf`；`boot` = `scripts/asLoader/asLoader.xfl` → `scripts/asLoaderLogic.swf`）。原入口通过主影片的 RSL 导入保持既有 `SharedObject.getLocal` 命名空间；不得把存档类直接移动到正常加载的另一个 SWF。共享库 `scripts/asLoaderShared.swf`、启动逻辑 `scripts/asLoaderLogic.swf` 由 `MovieClipLoader` 串行加载到 `_root.__asLoaderCode`（固定深度 `65531`）下的持久子影片，显式 `_lockroot=false`。这两个代码影片须存活到 AVM1 会话结束，handoff 只删除原公共入口和定义 host（定义 host 位于单帧时间轴负深度时先换至父影片的下一空闲非负深度，再执行 `removeMovieClip()`，避免 AVM1 负深度静默残留）。嵌套 RSL 曾出现共享服务读不到真实根对象，不能用类数量或编译成功代替根身份检查。

`scripts/asLoaderBootstrap.as` 负责装载；回调身份由根上的普通状态对象持有，拒绝过期/重复回调，错误或单模块60秒超时明确停止，保留失败原因，不自动重试。它在异步装载之前建立同一个 `__boot` 容器，定义帧只在不存在时建立，保证主影片 f33 提前到达的继续信号不会丢失。`BootSequencer.start()` 在任何单例初始化前用 live host URL 绑定资源目录。原入口驻留类不能依赖尚未加载的父类或 eager 跨类初始化。

常驻壳在创建 `__asLoaderCode` 之前安装根层级分配器，模块静态构造器使用 1024 至 32767 的动态区。S1 沿用同一计数器，回绕时跳过仍在使用的层。可用[运行时回归夹具](../tools/asloader-runtime-regression/)复现主时间轴装入、移除真实注释框的过程，并检查冷却轮、连续射击、刀光回收和延迟存盘回调。

只编辑 canonical 类源码、原 boot 输入及上述入口；`tools/build-asloader-modules.py` 从单一类归属表生成 XFL root、roots/exclude 文件和忽略目录 `tmp/asloader-modules` 中的完整编译路径镜像。非本模块的已登记类用 `intrinsic class` API 声明，仅保留签名，不产生替身实现；本模块和其他源码仍用原始字节。接口和实现切换时写入新时间戳，不能用 `copy2` 倒签日期而让 CS6 复用旧 ASO。类所有权表不持有 `BOOT_SOURCES` 或业务阶段表。

标准 `powershell -File scripts/compile_test.ps1 -Target publish -TimeoutSeconds 900` 自动生成并依次真实发布三个模块，使用跨阶段仓库锁、逐阶段机器锁及专用 `m1` 父锁身份，保留原 focused `v1` scratch 恢复规则。任一新鲜 Compiler、SWF刷新、零32K重试、函数尺寸、精确类归属、父类注册顺序或编译后输入检查失败都会停止；逐阶段诊断和 manifest 收据位于 `tmp/asloader-builds/`。类漏登记或跨模块重复必须修正源/归属，不能扩大排除列表掩盖。`--check` 可单独用于两个生成器。打包必须同时包含三个 SWF 和运行配给 JSON。`compiled` 收据不代表游戏已运行或已正式发布。

⚠ **反直觉点（看到别"修"，都是有意为之）**：
1. **定义装载分帧，业务由状态机执行**。唯一 `BOOT_SOURCES` 表机械派生 `_root.__boot.fN = function(){…}`；完整函数按源体积分到定义帧，最后一帧安装6个纯装配stage、停止播放，并调用一次 `BootSequencer.run(this)`。前置帧只安装定义。
2. **异步 boot 逻辑住在 class**（BootSequencer），靠挂在 `_root` 上的 `onEnterFrame` tick clip 驱动——因为 asLoader 自身 boot 完会自删，tick 必须挂 `_root` 才存活。
3. **大帧被切成 chunk 函数** `fN_1..fN_k`：AVM1 单函数体 ≤64KB（`DefineFunction2.codeSize` 是 UI16），单位函数 506KB / 装备 456KB 装不进一个 function。
4. **常规 import 是一个 82 包通配并集头**；另有由组装器 exact-match 守门的 9 个具体 import：`BootSequencer` + `Action.Skill` 包内 8 个现役类。该包因会话期新增类需要显式导入而整体从通配头改为具体类集合（AS2 不允许同包通配与具体 import 并存），用于规避 Flash CS6 常驻会话包索引陈旧。

## 1. 文件地图（boot 散落 4 处）

| 件 | 路径 | 作用 |
|---|---|---|
| symbol | `scripts/asLoader/LIBRARY/asLoader.xml` | 生成器维护唯一boot图层的定义帧及include顺序；历史结构与回退统一走Git |
| 定义母版及分段 | `scripts/asLoaderManifest/_collapsed_frame.as`、`_definition_frameNN.as` | **生成物，勿手改**。母版保持完整定义与接线；XFL实际消费同源分段。每段保留同一82包+9具体类导入头，所有定义齐备后才启动状态机 |
| 生成器 | `tools/assemble-collapsed-frame.js`、`tools/asloader-definition-frames.js` | `BOOT_SOURCES`仍是唯一live输入表；辅助模块只分配完整定义和生成符号引用，不持有启动业务条件 |
| 状态机 | `scripts/类定义/org/flashNight/boot/BootSequencer.as` | S0-S10 业务行为所有者；S0 / S5 / S9、异步与控制逻辑、S7 杂项加载顺序都在这里；帧顶 `_lockroot=false`、前置帧play/末帧stop属于生成物结构前导 |
| 主 SWF 改 A | `CRAZYFLASHER7MercenaryEmpire/DOMDocument.xml`（f33） | `_root.__boot.mainReadyToContinue = true`（替代旧 `_root.asLoader.play()`） |

> **`scripts/asLoaderManifest/frameNN.as` 的角色（塌缩后）**：当前根目录只保留 `BOOT_SOURCES` 列出的 29 个 live 输入：staged 帧 `2,3,9,10,18,32,36–42` 与 loader-fire 帧 `53–56,58,59,62–70,74`。`frameNN` 只是兼容 / 排障坐标，语义名、执行顺序、phase 与 shape 以同一张 `BOOT_SOURCES` 表为准；根目录出现未入表的 `frameNN.as` 或表项缺文件都会失败。旧 `frame0/1/4/5/6/7/26/75/91.as` 和 pre-collapse 备份不再作为现行参考或回退面，需要追溯时查 Git。一次性脚本 `tools/strip-stale-frame-imports.js` 已退役（勿作常驻门、勿扩白名单）。

### 1.1 生成器现行契约

2026-09-06 地图域切流后的新鲜发布检测到 `f36_9` 为 60,843 B；已沿顶层方案边界拆成 `单位函数_aka_战宠进阶.as` 与 `单位函数_aka_战宠进阶_扩展.as`，由 `frame36` 的 `f36_9 → f36_11 → f36_10` 连续装配，仍是先完整战宠进阶、再护盾。两段规范化拼接与拆分前原文完全一致，未改方案、数值或调用顺序；唯一顶层局部变量没有跨片引用。需要完整方案的直接 include 测试必须按相同顺序包含两段。拆分不放宽 `codeSize < 60000` 门。

2026-10-18 的 CI 检出通信段 `f3` 为 60,668 B，超过既有 60,000 B 门槛，尚未达到 UI16 的 65,535 B 上限。`frame3.as` 现沿 Agent 注册边界拆成 `f3_1 → f3_2`：先执行通信、计时器、存档桥接与任务定义，再注册 Agent 接口。两段仍由同一 `s1_syncCode` 同步调用，相对拆分前的同一主线源码，两段的函数体拼接完全一致；九个 include 没有顶层局部变量或具名函数声明，不引入跨段捕获。`BOOT_SOURCES`、启动状态机和业务脚本未因拆分改写。 本轮新产物的两段分别为 45,559 / 15,472 B，全部函数最大 53,041 B；新鲜 Compiler `0/0`、103 项启动／握手断言、9 次实际候选启动的事件顺序及 18 场集成均通过，详见 [C6 补充证据](../tools/cf6-elder-assets/README.md#c6-loader-archive)。C5 的完整强度统计保留原执行身份；本次未发布新的正式 Host runtime。

- `BOOT_SOURCES` 是唯一 live 输入表：当前 29 项（13 staged + 16 loader-fire），数组顺序就是 phase 内的确定执行顺序；不得再建平行 frame 清单、stage 接线表或独立 manifest。
- `node tools/assemble-collapsed-frame.js` 写生成物；`node tools/assemble-collapsed-frame.js --check` **不写文件**，按字节确认母版、全部定义帧及符号include可由当前表与规则精确重建。两种模式都会严格检查所有输入的 UTF-8 BOM、`frameNN.as` 根目录 exact-match、phase / shape、受控 envelope、具体 import 白名单、定义 / 调用唯一性，并要求 `BootSequencer.run(this)` 是唯一且最后的启动动作。
- 生成器会报告 canonical 源闭包度量：剥除每个源文件 BOM、把 CRLF/CR 规范为 LF，并计入 staged/loader-fire 自身源体，避免 checkout 行尾改变调查值。`70,000 B` 只用于突出复核候选，不是 hard gate，也没有 exact no-growth 例外；源字节与 AVM1 `codeSize` 不存在可证明的单调边界，不能让注释或格式增长变成构建 ratchet。高于提示线的项目以本轮生成器输出为准，仍须结合新鲜 SWF `codeSize` 扫描与行为证据判断是否拆分。

2026-11-05候选采用定义分段以处理本批完整单帧发布反复退出。`240000`字节是完整函数的分组预算：超出时开启下一定义帧，不拒绝源码增长，也不代替AVM1函数体门。当前定义数量和分帧数由生成器输出核对；原六个阶段及其调用次序不变。每段在同一asLoader实例上安装函数，打印/错误门面保留时间轴作用域，末帧才启动状态机。生成器同时核对函数集合、顺序、拼接原文和唯一启动调用。诊断工程已取得Compiler 0/0、零32K重试、全部803个运行类及2213个帧函数；正式候选仍须重新发布、启动/握手回归及绑定新SWF身份的实际启动。

## 2. Boot 流（S0-S10）

定义帧先执行 `this._lockroot=false`，早于任何 `_root` 读写。前置帧保持播放，仅安装定义；末帧停止、安装接线后进入业务状态机：S0 init → S1 syncCode（引擎+通信，建 `_root._bootstrap`）→ **S2 握手**（socket → handshake → 存档恢复 gate → 驱动主 SWF playhead）→ S3/S4 任务数据/文本 await → S5 parse → **S6 syncSys**（建 loader 队列 → 逐 tick 抽干，含异步 preload 等待门）→ S7 配给目录 await → S7 syncLogic（玩家模板/装备/UI… 大帧 chunk）→ S7 misc loaders → S8 fanout（fire-and-forget）→ S9 crafting → **S10 handoff**（`_root.play()` 必先于自删，顺序铁律）。

其中生成器只提供帧顶结构前导和 `s1_syncCode / s6_pre / s6_post / s7_syncLogic / s7_miscLoaders / s8_fanout` 六个无条件装配函数。`BootSequencer` 直接拥有 S0 的 `GlobalInitializer` 业务初始化、S5 任务解析与 guide fire-and-forget、S9 crafting 落地，以及 S7 的 `syncLogic → “加载杂项数据……” → misc loaders` 顺序；不要把这些业务重新塞回生成器。

## 3. 为什么每个怪点都必须在（别"优化"掉）

- **定义装载与业务时序分离**：C2-B历史实现曾将symbol收为单帧。本候选为解决完整CS6编译持续退出，将定义分到多个编译单元；所有异步、等待与业务阶段仍由原状态机拥有。
- **chunk**：64KB 函数体硬限；`tools/swf-function-sizes.js` 拦尚未越墙的近墙 `codeSize`，canonical 源闭包度量只作回绕风险调查信号。字段是 UI16，已越过 65,535 B 的坏函数会回绕成小值，因此还必须看新鲜行为证据；源字节提示线本身不判成败。
- **tick 挂 `_root`**：asLoader handoff 自删后回调仍要可达。
- **S6 异步等待门**：塌缩把多帧压成紧 tick，破坏了原版 preload→consume 依赖的隐式帧间隔时序（曾致佣兵库只载 1 条）。
- **function form（非 typed class）**：`_root.X = function` 闭包能捕获时间轴 scope（裸 `打印加载内容` 可解析）；typed class 静态方法不捕获 → 故 boot 代码用 function form，typed class 化作独立长期 track。

### S7 配给目录屏障

`tools/build-choice-rewards.py` 从既有目录权威生成 `data/rewards/choice-rewards.runtime.json`；`ChoiceRewardDefinition` 只缓存解析后的运行目录，不再内嵌 pool 对象字面量。`BootSequencer.stepSyncLogic()` 在原 S7 逻辑之前一次读取该文件，使用既有 `BaseJSONLoader(..., "JSON")`。未就绪时留在 S7；缺文件、坏 JSON 或错误根形状沿 `halt("choice_rewards_failed")` 终止，不安装书架等消费者。ready 后原 `syncLogic → 文案 → misc loaders → 原生桥安装 → S8` 顺序同 tick 执行一次，异步回调本身不推进阶段。

书架安装在 S7 就会启动 BookDefinition 读取，CF6 配置校验同时消费配给目录，因此不得把此屏障推迟到 S9。现有 `get()` 消费者只读目录；抽取和交易路径继续保留已有复制边界。改目录后执行生成器与 `--check`、`tools/test-choice-rewards.py`，改屏障时另跑 `scripts/run-boot-sequencer-tests.ps1`。CF6 focused 入口先加载同一运行目录，再启动原 suite。

## 4. 塌缩踩过的坑（认症状用，详见构建标准 §0）

1. **chunk 帧调度必须调全部 chunk 名**，不能调 base `fN`（chunk 帧无 base）→ 否则大帧静默不跑（入 lobby 但角色瘫痪 / 无刘海屏）。
2. **eager 自单例 `static var instance = new Self()` 构造里跨类调用** → 依赖类未注册时 **AVM1 对「未定义类.方法()」静默返回 undefined（不抛错）** → 死回调（刀光不褪 bug）。**通用律：自单例构造勿跨类调用**。
3. **异步 preload→consume 靠帧间隔**，塌缩压紧 tick 须加显式等待门（见 S6）。
4. **大小写 typo 被并集头更严格类型解析暴露**（多帧时该上下文未 typed-resolve 不报，塌缩后报编译错）。

## 5. 历史验证状态（boot 行为基线 2026-06-17；当时工作树复核 2026-07-25）

| 项 | 状态 |
|---|---|
| 历史 Happy-path 真机 boot | ✅ 2026-06-17 基线通过（引擎/通信/玩家/装备/战斗/UI/关卡/佣兵满编 204/刀光褪色/存档 loadAll OK）；这是历史行为基线，不替代当前施工树的 fresh boot |
| **S1 当前产物事实** | ✅ `frame2/39/41` 近墙函数已拆分；2026-07-25 fresh publish 后对 `scripts/asLoader.swf` 执行 `swf-function-sizes --max 60000`，9493 个函数中最大三个为 **45,868 / 44,163 / 38,422 B** |
| **S3 生成器事实** | ✅ `--check` 字节级通过：82 包 + 9 具体类、29 live source（13 staged + 16 loader-fire）、6 个 stage；生成物由 `.gitattributes` 固定 LF；canonical 源闭包度量最大为 `f3=149298 B`，高于 70,000 B 的三项只列作调查候选，不作构建 hard gate |
| BOM | ✅ `node tools/check-bom.js`：当前 172 个 `.as` 全部带 UTF-8 BOM |
| 静态门 single-ownership | ✅ 当前复核：main=0 / loader=599 / 交集=0 |
| **当前 S1/S3 编译与真机 boot** | ✅ 最终生成物 fresh publish 约 35 s，Compiler Errors 面板副本 `0 个错误, 0 个警告`，`scripts/asLoader.swf` 刷新为 1,034,400 B（SHA-256 `5FAEB960ECB8F9375E9037CBB52854281E23DBE3DAE036451B0BAD0B4B00FACA`）；正式标准入口以专用克隆槽启动，attempt `f18ce86d75564adf8ac3457de4d9b063` 获得 fresh handoff、真实 `bootstrap_reveal_ready`、同 attempt `s:1` / runtime ack 与只读装备 snapshot，且本轮没有 reveal watchdog；报告为 `tmp/equipment-tuning/unattended/20260725T045156Z-cf7_agent_equipment_tuning/run-report.json` |
| **trace 等价门（happy-path）** | ✅ golden 仍为 2026-06-17 的单次完整 boot S2→S10；2026-07-25 对当前 fresh 真机日志执行 `trace-diff diff`，golden 10 事件 / new 10 事件 / LCS 10，顺序 `S2_ENTER → SOCKET_READY → HANDSHAKE_RESULT → PRELOAD_FIRE → READY_ACK → BOOT_CHECK_JUMP → TASKDATA_OK → TASKTEXT_OK → CRAFTING_OK → HANDOFF_PLAY` 完全一致 |
| **§5 七边界** | ✅ 基本完成（2026-06-17 真机）：(c) shim 缺失双层 fail-closed、(a) 坏档 C2-β 修复 gate、(d) 正常/新档(decision=empty)/坏档(随 a)、握手失败 fail-closed(测试churn顺带实证)、(e)(f) 随 happy-path boot 覆盖。(b) socket 超时=纯看屏(独立开 SWF 已见卡死协议帧)+L1 逻辑已覆盖。详见构建标准 §5.3 |

## 6. 怎么测 / 怎么改

- **改 boot 同步逻辑**：从 `BOOT_SOURCES` 的语义名定位 live source（新增顶层 source 时只改这张表，不建平行清单）→ 改源 `.as` → `node tools/assemble-collapsed-frame.js` → `node tools/assemble-collapsed-frame.js --check` → `node tools/check-bom.js` → `powershell -File scripts/compile_test.ps1 -Target publish -TimeoutSeconds 900`。只改外置 `.as` 时显式 `-Target` 会从盘读取，无需额外手工重开；生成器改动 `asLoader.xml` 帧数/层数/symbol 等时间轴结构时，须先让 CS6 **不保存关闭并重开**，避免内存旧版 clobber 磁盘。没有本轮新鲜 `compiler_errors.txt` `0/0`、目标 SWF 刷新，以及所需的 trace / Output Panel 副本或 IDE 复核时，不声称“编译通过”。
- **改 / 增装备生命周期函数**：编译真源是 `scripts/asLoaderManifest/frame37.as`（f37_N chunk），**不是**旧 `装备函数列表.as`（已删）。用途索引 / API 快查 / 新增 8 步见 `scripts/逻辑/装备函数/README.md`；改完依次跑生成、`--check`、BOM 与 `node tools/validate-equip-fn-coverage.js`，再由 CS6 对 asLoader 执行显式 `-Target publish`；只有同时改时间轴/XML 结构才手工重开。
- **改 BootSequencer / bootstrap handshake**：直接改类或 shim → 先跑 TestLoader（BootSequencerTest + BootstrapHandshakeTest）→ 重编 publish（publish 模式无 trace，看 `0 错误` + SWF 刷新）。
- **类继承注册顺序**：`node tools/check-as2-inheritance-order.js`用实际SWF根DoInitAction顺序和现役类的extends关系，拒绝父类晚于子类。`compile_test.ps1`在asLoader发布后自动执行；Compiler 0/0与类数量齐全不能替代此门。基础`ItemCollection`在运行期查找物品工厂，避免经具体物品/装备服务回连派生容器；它的公开构造、查询与序列化接口保持原合同。
- **asLoader 发布后的大小门**：对本轮产物执行 `node tools/swf-function-sizes.js scripts/asLoader.swf --max 60000 --top 15`，与 CI 同门槛；普通 publish 的 `0/0` 和 SWF 刷新不包含这项通过结论。若拆分启动 chunk，还需保序与作用域核查、BootSequencer/握手 suite 和绑定新加载器身份的实际启动行为。
- **trace 门**：`node tools/trace-diff.js diff <golden> <new>`（事件序列 LCS 等价，容时间戳/批处理）。
- **边界**：构建标准 doc **§5.1** 七边界表（触发 → 期望 `[BootstrapAS]` 信号 → 判据）。
- **回退 / 追溯**：只以 Git 记录为准，并把 symbol、`BootSequencer`、生成器、live manifest 与生成物作为同一装配闭包回退；不要复活 pre-collapse 备份或 9 个旧 history frame，也不要只还原其中一个文件。

---
**新接手测试者**：读完 §0 + §5 即可开测；要改 boot 结构再读 §1-§4 + 两个深层 doc。**改 `.as` 必带 UTF-8 BOM**（见 [as2-anti-hallucination.md](../agentsDoc/as2-anti-hallucination.md)）。

资源 SWF 不得重复定义工程类；发布后增量检查与最终生产闭包门见 [类归属验证](../agentsDoc/testing-details.md#flash-core)。
