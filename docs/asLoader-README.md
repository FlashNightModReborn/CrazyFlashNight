# asLoader 启动架构 · 导览与待测

**文档角色**：asLoader 启动子系统的**入口导览**（反直觉架构的心智地图 + 验证状态 + 测试入口）。深层细节下沉到设计 / 施工 doc，本文只回答「这是什么、为什么这么怪、验了什么、还要测什么」。
**最后核对代码基线**：commit `b4d1267d51e5bdf4957fe56d21f6ee2c0a5049de` + 当前审阅修复工作树（2026-07-25）；下列“当前”结论均以该工作树为对象。
**深层 doc**：[架构设计](asLoader重构-架构设计-2026-06-15.md)（为什么这么设计 + P0-P6 路线）· [BootSequencer 构建标准](asLoader-BootSequencer-构建标准-2026-06-16.md)（启动契约 + §5 边界 runbook）· [asLoader / TestLoader 维护性路线](asLoader-TestLoader维护性重构-架构路线-2026-07-24.md)（维护性施工路线；阶段状态以该文档为准，当前构建入口与门禁以本文为准）。

## 0. TL;DR（先读这段）

asLoader = 游戏启动器：一个 Flash CS6 影片剪辑 symbol，**承载全部 `org.flashNight.*` 类字节码 + 跑启动序列**。2026-06 把它从 **82 帧时间轴塌缩成单帧**，异步逻辑搬进 `BootSequencer` 状态机类。

⚠ **反直觉点（看到别"修"，都是有意为之）**：
1. **整个 boot 是一帧**。唯一 `BOOT_SOURCES` 表机械派生 `_root.__boot.fN = function(){…}` 与 6 个纯装配 stage，最后 `BootSequencer.run(this)`。没有多帧时间轴。
2. **异步 boot 逻辑住在 class**（BootSequencer），靠挂在 `_root` 上的 `onEnterFrame` tick clip 驱动——因为 asLoader 自身 boot 完会自删，tick 必须挂 `_root` 才存活。
3. **大帧被切成 chunk 函数** `fN_1..fN_k`：AVM1 单函数体 ≤64KB（`DefineFunction2.codeSize` 是 UI16），单位函数 506KB / 装备 456KB 装不进一个 function。
4. **常规 import 是一个 82 包通配并集头**；另有由组装器 exact-match 守门的 9 个具体 import：`BootSequencer` + `Action.Skill` 包内 8 个现役类。该包因会话期新增类需要显式导入而整体从通配头改为具体类集合（AS2 不允许同包通配与具体 import 并存），用于规避 Flash CS6 常驻会话包索引陈旧。

## 1. 文件地图（boot 散落 4 处）

| 件 | 路径 | 作用 |
|---|---|---|
| symbol | `scripts/asLoader/LIBRARY/asLoader.xml` | 单帧，只 `#include _collapsed_frame.as`；历史结构与回退统一走 Git |
| 帧 CDATA | `scripts/asLoaderManifest/_collapsed_frame.as` | **生成物，勿手改**：82 包并集头 + 9 个具体 import 白名单 + 29 个 live source 定义 + 6 个纯装配 stage + `BootSequencer.run(this)` |
| 生成器 | `tools/assemble-collapsed-frame.js` | 持有唯一 live 输入表 `BOOT_SOURCES`，负责排序 / 展开 / 校验 / 生成，不持有启动业务条件 |
| 状态机 | `scripts/类定义/org/flashNight/boot/BootSequencer.as` | S0-S10 业务行为所有者；S0 / S5 / S9、异步与控制逻辑、S7 杂项加载顺序都在这里；帧顶 `_lockroot=false; stop()` 属生成物结构前导 |
| 主 SWF 改 A | `CRAZYFLASHER7MercenaryEmpire/DOMDocument.xml`（f33） | `_root.__boot.mainReadyToContinue = true`（替代旧 `_root.asLoader.play()`） |

> **`scripts/asLoaderManifest/frameNN.as` 的角色（塌缩后）**：当前根目录只保留 `BOOT_SOURCES` 列出的 29 个 live 输入：staged 帧 `2,3,9,10,18,32,36–42` 与 loader-fire 帧 `53–56,58,59,62–70,74`。`frameNN` 只是兼容 / 排障坐标，语义名、执行顺序、phase 与 shape 以同一张 `BOOT_SOURCES` 表为准；根目录出现未入表的 `frameNN.as` 或表项缺文件都会失败。旧 `frame0/1/4/5/6/7/26/75/91.as` 和 pre-collapse 备份不再作为现行参考或回退面，需要追溯时查 Git。一次性脚本 `tools/strip-stale-frame-imports.js` 已退役（勿作常驻门、勿扩白名单）。

### 1.1 生成器现行契约

- `BOOT_SOURCES` 是唯一 live 输入表：当前 29 项（13 staged + 16 loader-fire），数组顺序就是 phase 内的确定执行顺序；不得再建平行 frame 清单、stage 接线表或独立 manifest。
- `node tools/assemble-collapsed-frame.js` 写生成物；`node tools/assemble-collapsed-frame.js --check` **不写文件**，按字节确认生成物可由当前表与规则精确重建。两种模式都会严格检查所有输入的 UTF-8 BOM、`frameNN.as` 根目录 exact-match、phase / shape、受控 envelope、具体 import 白名单、定义 / 调用唯一性，并要求 `BootSequencer.run(this)` 是唯一且最后的启动动作。
- 生成器会报告 canonical 源闭包度量：剥除每个源文件 BOM、把 CRLF/CR 规范为 LF，并计入 staged/loader-fire 自身源体，避免 checkout 行尾改变调查值。`70,000 B` 只用于突出复核候选，不是 hard gate，也没有 exact no-growth 例外；源字节与 AVM1 `codeSize` 不存在可证明的单调边界，不能让注释或格式增长变成构建 ratchet。当前高于提示线的是 `f3=149298 B`、`f36_2=121117 B`、`f37_7=76380 B`，仍须结合新鲜 SWF `codeSize` 扫描与行为证据判断是否拆分。

## 2. Boot 流（S0-S10）

帧顶结构前导先执行 `this._lockroot=false; this.stop();`，且必须早于任何 `_root` 读写；随后才进入业务状态机：S0 init → S1 syncCode（引擎+通信，建 `_root._bootstrap`）→ **S2 握手**（socket → handshake → 存档恢复 gate → 驱动主 SWF playhead）→ S3/S4 任务数据/文本 await → S5 parse → **S6 syncSys**（建 loader 队列 → 逐 tick 抽干，含异步 preload 等待门）→ S7 syncLogic（玩家模板/装备/UI… 大帧 chunk）→ S7 misc loaders → S8 fanout（fire-and-forget）→ S9 crafting → **S10 handoff**（`_root.play()` 必先于自删，顺序铁律）。

其中生成器只提供帧顶结构前导和 `s1_syncCode / s6_pre / s6_post / s7_syncLogic / s7_miscLoaders / s8_fanout` 六个无条件装配函数。`BootSequencer` 直接拥有 S0 的 `GlobalInitializer` 业务初始化、S5 任务解析与 guide fire-and-forget、S9 crafting 落地，以及 S7 的 `syncLogic → “加载杂项数据……” → misc loaders` 顺序；不要把这些业务重新塞回生成器。

## 3. 为什么每个怪点都必须在（别"优化"掉）

- **单帧**：用户拍板的 C2-B（symbol 真只剩 1 帧脚本）。
- **chunk**：64KB 函数体硬限；`tools/swf-function-sizes.js` 拦尚未越墙的近墙 `codeSize`，canonical 源闭包度量只作回绕风险调查信号。字段是 UI16，已越过 65,535 B 的坏函数会回绕成小值，因此还必须看新鲜行为证据；源字节提示线本身不判成败。
- **tick 挂 `_root`**：asLoader handoff 自删后回调仍要可达。
- **S6 异步等待门**：塌缩把多帧压成紧 tick，破坏了原版 preload→consume 依赖的隐式帧间隔时序（曾致佣兵库只载 1 条）。
- **function form（非 typed class）**：`_root.X = function` 闭包能捕获时间轴 scope（裸 `打印加载内容` 可解析）；typed class 静态方法不捕获 → 故 boot 代码用 function form，typed class 化作独立长期 track。

## 4. 塌缩踩过的坑（认症状用，详见构建标准 §0）

1. **chunk 帧调度必须调全部 chunk 名**，不能调 base `fN`（chunk 帧无 base）→ 否则大帧静默不跑（入 lobby 但角色瘫痪 / 无刘海屏）。
2. **eager 自单例 `static var instance = new Self()` 构造里跨类调用** → 依赖类未注册时 **AVM1 对「未定义类.方法()」静默返回 undefined（不抛错）** → 死回调（刀光不褪 bug）。**通用律：自单例构造勿跨类调用**。
3. **异步 preload→consume 靠帧间隔**，塌缩压紧 tick 须加显式等待门（见 S6）。
4. **大小写 typo 被并集头更严格类型解析暴露**（多帧时该上下文未 typed-resolve 不报，塌缩后报编译错）。

## 5. 验证状态（历史 boot 行为基线 2026-06-17；当前施工树 fresh 复核 2026-07-25）

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

- **改 boot 同步逻辑**：从 `BOOT_SOURCES` 的语义名定位 live source（新增顶层 source 时只改这张表，不建平行清单）→ 改源 `.as` → `node tools/assemble-collapsed-frame.js` → `node tools/assemble-collapsed-frame.js --check` → `node tools/check-bom.js` → `powershell -File scripts/compile_test.ps1 -Target publish -TimeoutSeconds 180`。只改外置 `.as` 时显式 `-Target` 会从盘读取，无需额外手工重开；只有改 `asLoader.xml` 帧数/层数/symbol 等时间轴结构时，才先让 CS6 **不保存关闭并重开**，避免内存旧版 clobber 磁盘。没有本轮新鲜 `compiler_errors.txt` `0/0`、目标 SWF 刷新，以及所需的 trace / Output Panel 副本或 IDE 复核时，不声称“编译通过”。
- **改 / 增装备生命周期函数**：编译真源是 `scripts/asLoaderManifest/frame37.as`（f37_N chunk），**不是**旧 `装备函数列表.as`（已删）。用途索引 / API 快查 / 新增 8 步见 `scripts/逻辑/装备函数/README.md`；改完依次跑生成、`--check`、BOM 与 `node tools/validate-equip-fn-coverage.js`，再由 CS6 对 asLoader 执行显式 `-Target publish`；只有同时改时间轴/XML 结构才手工重开。
- **改 BootSequencer / bootstrap handshake**：直接改类或 shim → 先跑 TestLoader（BootSequencerTest + BootstrapHandshakeTest）→ 重编 publish（publish 模式无 trace，看 `0 错误` + SWF 刷新）。
- **trace 门**：`node tools/trace-diff.js diff <golden> <new>`（事件序列 LCS 等价，容时间戳/批处理）。
- **边界**：构建标准 doc **§5.1** 七边界表（触发 → 期望 `[BootstrapAS]` 信号 → 判据）。
- **回退 / 追溯**：只以 Git 记录为准，并把 symbol、`BootSequencer`、生成器、live manifest 与生成物作为同一装配闭包回退；不要复活 pre-collapse 备份或 9 个旧 history frame，也不要只还原其中一个文件。

---
**新接手测试者**：读完 §0 + §5 即可开测；要改 boot 结构再读 §1-§4 + 两个深层 doc。**改 `.as` 必带 UTF-8 BOM**（见 [as2-anti-hallucination.md](../agentsDoc/as2-anti-hallucination.md)）。
