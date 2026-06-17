# asLoader BootSequencer · 权威启动契约 · 构建标准 · 2026-06-16

**文档角色**：BootSequencer（C2 全量异步-B）施工的**权威跨时间轴启动契约**。
**来源**：8-agent workflow（3 readers → 综合 → 3 对抗校验 → spec），全部 file:line 二次核对。
**上游设计**：[asLoader重构-架构设计-2026-06-15.md](asLoader重构-架构设计-2026-06-15.md)。
**状态**：契约已闭合；BootSequencer 类为 DRAFT，待 CS6 编译 + 真机验证。

> ## ⚠ 2026-06-16 重大修正 + 进展（读 Runbook 前必看）
> 1. **AVM1 函数体 64KB 硬限推翻「单函数 staging」**：`DefineFunction2.codeSize` 是 UI16（≤65535B 字节码）。大帧（单位函数 506KB/装备 456KB/UI 189KB 源）wrap 进单个 `function(){}` 即溢出 → 编译 0 错却静默产坏函数（真机实证 f36/f37/f41 staged 函数从不执行）。帧脚本(DoAction)是 UI32 无此限。
> 2. **修复 = chunk 分块**：`tools/stage-wrap-frame.js --chunk-bytes <源字节预算> [--flatten]` 把帧 includes 切多个 `_root.__boot.fN_k` 函数各 <64KB 字节码（保序/不拆单文件/`--flatten` 展平聚合 include 如装备函数列表→62 武器）；`tools/swf-function-sizes.js` = codeSize 门（解析 SWF 每个 DefineFunction2，>阈值 exit1，**无需真机即拦溢出**）。源→字节码比实测 0.34-0.43。
> 3. **function form 而非 class form**（工程裁决）：class 静态方法不捕获时间轴 scope（裸 `打印加载内容`/自定义函数静默不解析），function-on-`_root` 闭包捕获时间轴已 f2 真机证；**且 class wrap≠静态 typing**（内部仍 untyped `_root.X=function`）。typed class 化作独立长期 track，不耦合 collapse。
> 4. **进度：全 12 sync 帧已 staged + 真机验证通过**（f2/3/9/10/18/32/38/39/40 单函数 + f36/f37/f41 chunk）；`_root.__boot` 收尾删除已加（frame91 + 本 doc §3 S10）。**剩 = 本 Runbook 的 async 帧（f4 握手/f5,6 await/f7 parse/f26 loader-seq/f48-74 fanout/f75 craft/f91 handoff）→ BootSequencer + P5 塌缩 + §4 三处主 FLA 改动 + §5 真机边界验**。下面 Runbook 的「单 staged 函数」表述统一按 chunk 化理解。
> 5. **2026-06-16 评审修复轮**（两点，已验证）：
>    - **工具 import 正则盲区**：`stage-wrap-frame.js`/`lint-frame-imports.js` 旧正则强制 `;`，漏剥**无分号 import**（AS2 分号非必需）。实证 `单位函数_fs_aka_玩家模板迁移.as`/`单位函数_lsy_敌人模板迁移.as` 的 `import …RandomNumberEngine.*`（无分号）泄进 f36 staged 函数体、lint 假报「子文件无残留」。修 = 正则改**行首锚定 + 分号可选 + 标识符分段式** `[seg](?:\.[seg])*(?:\.\*)?`（⚠ 仅去 `;` 会因贪婪 `[\w.$]*` 吞掉 `.*` 前的点、末尾全可选不回溯→漏下游离 `*`；分段式根治）。两文件已 BOM 安全剥（`tools/strip-stale-frame-imports.js`，包已在 f36 联合头覆盖故行为不变，待下次 publish 入 SWF）。lint `--fold-specific --strict`=0、check-bom 205、全 tools 已无同类盲区。
>    - **compile_test asLoader 假成功**：脚本只看 compiler_errors / `[TEST_FAIL]` 即 exit 0，从不校验 `asLoader.swf` 是否真刷新（marker 产出但 SWF 未重写=与 testing-guide 口径相反地假通过）。修 = 新增 opt-in `-VerifySwf <path>`，触发前记 mtime/size 基线、成功路径校验其变化，未刷新→`exit 1`（fail-closed）。**asLoader publish 一律 `-VerifySwf scripts/asLoader.swf`**（testing-guide §2 已写硬）。
> 6. **2026-06-16 P3 收官 + S6 队列机制更正（读 §3 前必看）**：
>    - **f42(视觉) 已 staged** → 全 13 sync `#include` 帧 staged 完成（f2/3/9/10/18/32/36/37/38/39/40/41/42）。剩余帧皆非 stage-wrap 类归 BootSequencer。
>    - **⚠ §3 原 S6 描述（"同步串行 最终化1→最终化2→最终化3"）不准**：实读源码，f18(最终化1)=`for-in` 跑全部 `_root.preloaders`（一次性）；**f26(最终化2)=`onEnterFrame` 每帧抽 1 个 `_root.loaders`（时间切片，async 多帧）**；f32(最终化3)=跑全部 `_root.loaderkillers` + 删三队列。队列生命周期：f9 建 `_root.loaders` → f10(佣兵/兵种/商城/商店_兼容) 各 push → f26 抽干 → f32 删。**BootSequencer.as 已据此改 S6=stepSyncSys（sysPhase 0 跑 s6_pre=f9+f10+f18，相位 1 每 tick 抽 1 个 loader，队空跑 s6_post=f32→S7）**，已更 §3。
>    - **f5/f6 parity**：原 f5 调 `打印加载内容("加载任务数据……")` + cb `_root.发布消息("任务数据加载完毕")`、f6 cb `_root.发布消息("任务文本加载完毕")`，draft 漏；已补进 BootSequencer S3/S4（host.打印加载内容 + _root.发布消息，C1 事件副作用必留）。
>    - **塌缩帧需定义的 s-函数**（映射 staged fN）：s0_init=f1·s1_syncCode=f2,f3·s5_parseTask=f7·**s6_pre=f9,f10,f18 / s6_post=f32**·s7_syncLogic=f36..f42+f48-59·s8_fanout=f62-74·s9_onCrafting=f75。**未做**：写塌缩帧 CDATA + 改 asLoader.xml 单帧 + 3 主 FLA 改（destructive，待评审后执行）。
> 7. **2026-06-17 P5 塌缩已应用 + happy-path 真机全绿（4 个运行时回归已修，凡塌缩必查）**：塌缩 boot 首测暴露 4 类**编译 0 错却运行时坏**的陷阱（publish 无 trace，全靠注入诊断定位）——
>    - **(a) chunk 帧调度必须调全部 chunk 名，不能调 base `fN`**：组装器 `s7_syncLogic` 调 `_root.__boot.f36()/f37()/f41()`，但这三帧是 chunk 帧只定义 `fN_1..fN_k` **无 base `fN`** → 调用 no-op → 三最大帧（单位函数 506K/装备 456K/UI 189K ≈ 游戏主体）从不执行。**症状=入 base_lobby 但角色瘫痪 + 刘海屏不展开（notifyGameEntered 在 f41 没跑）+「大量代码未运行」观感，且无报错**。修 = `assemble-collapsed-frame.js` 加 `extractDefNames`+`callsFor(N)`（chunk 帧=顺序调全 chunk 名），s1/s6/s7 全改 callsFor。
>    - **(b) 异步 preload→consume 靠帧间隔，塌缩压成紧 tick → 数据未落地就被读**：`佣兵系统_兼容.as` 是 preloader(异步 XML.load→GetFileByPath 异步 LoadVars)+loader(读 preload 数据建 `_root.mercs_list`) 双阶段；原版 f18(fire)→goto链→f26(consume) 有帧间隔，塌缩压到相邻 tick → loader 在 `onData` 回来前读空 → `mercs_list` 只 1 条 → 佣兵几乎不刷（trace 实证 `mercsList=1`）。**系统性**：全 `兼容` 文件 + 任何 GetFileByPath 型 preload 同理。修 = `GetFileByPath` 加全局在途计数 `_root.__pendingFileLoads`（load++/onData--），BootSequencer.stepSyncSys S6 插**相位 1 等待门**（最少 30 帧 + 等 `__pendingFileLoads==0`，150 帧兜底）再抽 loader。真机验 `mercsList=204` 满编。**通用律：凡「fire 异步→后续帧 consume」的 boot 序列，塌缩后都要加显式等待门**。
>    - **(c) eager 自单例（`static var instance = new Self()`）构造里做跨类调用 = 类注册序陷阱**：`VectorAfterimageRenderer.as:59` 在类注册期即构造，构造里 `_fadeCallback = Delegate.create1(this, onFadeUpdate)`；塌缩单帧使依赖类 `Delegate` 可能**尚未注册** → **AVM1 对「未定义类.方法()」静默返回 undefined 不抛错** → `_fadeCallback` 变 undefined（其余构造照跑/绘制正常）→ 渐隐回调形同虚设、刀光不消失（**无报错，极隐蔽，只在很久后表现为功能缺失**）。修 = 入队前（initializeCanvas，引擎早就绪）重绑委托。审计：eager 自单例 ∩ 构造调 `Delegate.create*` = 仅此一例（EventBus 的 Delegate.create 只在注释；余自单例皆平凡值构造）。**通用律：eager 自单例构造勿做跨类调用**。
>    - **(d) 潜伏大小写 typo 被塌缩联合头更严格解析暴露**：`单位函数_lsy_敌人模板迁移.as` 误写 `StaticDeinitializer.deinitializeUnit`（真方法 `deInitializeUnit` 大写 I）。多帧时该上下文未解析为 typed 类故 0 错；塌缩联合头使其解析为 typed 类 → 静态方法类型检查 → 编译报错（非塌缩 bug，是先前潜伏 typo 被更严格解析揪出）。**⚠C1 注记**：若旧运行时大小写敏感(SWF v7+)则修前这 2 处 enemy-deinit 是静默 no-op、修后真 deinit=行为变化，可游戏内验敌人死亡清理。
>    - **状态**：塌缩 boot happy-path 全绿（引擎/通信/玩家模板/装备/战斗/UI/关卡/佣兵满编/刀光褪色/存档 loadAll OK，launcher.log 无 boot 错），诊断插桩已清理净化重编（SWF 869820B）。**剩 = §5 七边界验 + trace 等价门**。

> 帧号：MAIN = `CRAZYFLASHER7MercenaryEmpire/DOMDocument.xml`（场景帧 0-based）；asLoader = `scripts/asLoader/LIBRARY/asLoader.xml`（DefineSprite 内 f 序号 0-based）；shim = `scripts/通信/通信_fs_bootstrap.as`；类 = `scripts/类定义/org/flashNight/neur/Server/{BootstrapHandshake,BootstrapWait,SaveManager}.as`。

---

## 0. 三项对抗校验定论（修正了初始误判）

- **CHECK2 confirmed**：**asLoader f4 是唯一真实握手驱动；MAIN f62-64 是不可达死代码/幂等备援**。shim 缺失时 f4 走 shim-missing 分支不外跳，MAIN 永冻在 f1，到不了 f62；shim 存在时 f4 已 `gotoAndStop("boot_check")`，f62 的 `startHandshake` 被幂等锁 `getState()!="Idle"return`（shim:14）短路。fail-closed 由「MAIN 冻结在 f1」实现，**不靠 f62**。
- **CHECK3 partly-wrong → 两点修正**：
  1. **单帧 `play()` 不"回 frame0 重跑"**——单帧 clip 在 `play()` 下 playhead 停在唯一帧、每 loop 回绕**重执行帧脚本一次**。**防重跑靠帧首 `stop()` + 幂等 guard 位**，不能依赖"play 不 loop"。
  2. **第二结构耦合点**：asLoader 实例 keyframe 寿命 = **MAIN frame1–33**（`DOMDocument.xml:1684` index=1 dur=33），**frame34 空关键帧移除实例**（`:1696`）。折叠后实例寿命与 `removeMovieClip()` 自删抢生命周期 → 必须处理（见 §3 改动 B）。
- **CHECK1 partly-wrong → f25→f27 land-frame 定性**：`gotoAndStop("load")`（asLoader.xml:319）落 index26 执行其 land-frame 脚本（`#include 最终化2`@325）一次，f27 `gotoAndPlay("kill")`@331 接力 → 净效果 = 最终化1→**最终化2**→最终化3 顺序跑完。**折叠时必须把最终化2 显式排进串行序列**（易漏）。

---

## 1. 权威 boot 时序（统一线性序列，严格执行先后）

| # | 谁 | file:line | 动作 | 推进/等待 |
|---|----|----|----|----|
| 1 | MAIN | DOMDocument.xml:904 (f0 `steam`) | 无脚本（isSWF 自推进在 :1033-1207 注释块=死代码） | 计时→f1 |
| 2 | MAIN | :1213 (f1 `外置大脑载入`,dur32) | `stop()` 冻结主轴；asLoader 实例占 frame1–33 | **阻塞**，等 asLoader 子剪辑驱动 |
| 3 | asLoader | asLoader.xml:70-71 (f0) | `_lockroot=false`；`_root.stop()`(冗余)；定义 `打印加载内容` | →f1 |
| 4 | asLoader | :81-82 (f1) | `GlobalInitializer.initialize()`（`if(initialized)return` 单例） | →f2 |
| 5 | asLoader | :88-109 (f2 `引擎`) | 同步 `#include` 18 引擎文件 | →f3 |
| 6 | asLoader | :115-126 (f3 `通信`) | 同步 `#include` 9 通信文件，**含 :122 bootstrap.as→建 `_root._bootstrap`** | →f4 |
| 7 | asLoader | :138 (f4 `init`) | `this.stop()`+注册 `onEnterFrame` 握手机；**不内部 play()** | **阻塞**，onEnterFrame 自驱 |
| 7a | asLoader | :159-177 | 阶段1：轮询 `server.isSocketConnected`；连上→`startHandshake()`@171 | 等 socket；**>10000ms→`socket_connect_timeout`@162** |
| 7b | shim | 通信_fs_bootstrap.as:14-59 | `startHandshake` 幂等@14；`BootstrapHandshake.start(…,60000)` | socket round-trip，**60s 窗** |
| 7c | shim | :34-48 (success cb) | 写 `savePath`/`attemptId`/Protocol2 存盘决策；`_bootstrapSavePathReady=true`@48 | handleResponse@55 触发 |
| 7d | asLoader | :181-196 | 阶段2：轮询 `handshakeStatus()`；Success→`读取本地存盘()`@196（`_bootstrapPreloadFired` 一次性） | 等 Success；Failed 停@184-188 |
| 7e | asLoader | :198 (gate) | `if 存档恢复等待中()==true return;`（自旋 yield） | **可阻塞**：`_repairPending`(C2-β) 或 JSON 预取在途 |
| 7f | asLoader | :200-207 | 清 onEnterFrame@200；`sendReady()`@204；**`_root.gotoAndStop("boot_check")`@207** | 把 MAIN f1→f5 |
| 8 | MAIN | :1219-1220 (f5 `boot_check`) | `注释结束()`；`gotoAndPlay("单机版开始")`@1220 | →f30 |
| 9 | MAIN | :1244-1261 (f30 `单机版开始`) | 清欢迎语；FSCommand showmenu；`useCodepage=false`；`Stage.showMenu=false` | 计时→f33 |
| 10 | MAIN | :1270-1271 (f33 `外置大脑继续加载`) | `stop()`@1270；**`_root.asLoader.play()`@1271**（解冻 asLoader f4→f5） | **MAIN 阻塞**；交还驱动权 |
| 11 | asLoader | :222-231 (f5) | `this.stop()`；`TaskDataLoader.loadTaskData`，cb `play()`@231 | **异步阻塞**：任务数据 JSON |
| 12 | asLoader | :245-254 (f6) | `this.stop()`；`TaskTextLoader.loadTaskText`，cb `play()`@254 | **异步阻塞**：任务文本 JSON |
| 13 | asLoader | :266-273 (f7) | `TaskUtil.ParseTaskData`@266；raw*=null；fire-and-forget `loadGuideData`@273 | →f9 |
| 14 | asLoader | :287-289 (f9) | `#include 逻辑系统分区_初始化.as` | →f10 |
| 15 | asLoader | :295-301 (f10 `systems`) | `#include` 佣兵/兵种/商城/商店系统_兼容 | →f11 |
| 16 | asLoader | :307/313/319/325/331/337 (f11→f32) | goto 链：preload(最终化1)→load(**最终化2** land-frame)→kill(最终化3) | 见 §0 CHECK1 |
| 17 | asLoader | :343-366 ＋并行层 (f36-42) | **7 层并行 `#include`**：单位函数/装备/功能/关卡/战斗/UI交互/视觉（同帧多层并行；折叠按层串行等价） | 同步推进 |
| 18 | asLoader | :372-440 (f48-f59) | 同步杂项：子弹/发型/色彩/宠物/技能/过场；legacy 佣兵 preload 已移除 | 推进 |
| 19 | asLoader | :451-778 (f62-f74) | **fire-and-forget 异步 loaders**：ItemData/敌人属性/称号+材料/**地图Catalog(whenAvailable@605)**/情报/关卡/环境/基建/装备配置/NPC技能（不阻塞） | 各 cb 独立回填 |
| 20 | asLoader | :782-810 (f75) | `this.stop()`@787；`CraftingListLoader`；cb 建 `ItemObtainIndex`@807，`play()`@810 | **异步阻塞**：合成表 JSON |
| 21 | asLoader | :821-823 (f91) | **`_root.play()`@821 → `this.stop()`@822 → `removeMovieClip()`@823**（顺序铁律） | 恢复 MAIN f33；自卸载 |
| 22 | MAIN | :1277-1436 (f52→f125) | 显示语言/脸型库/**f62-64 死代码自旋备援**/`sendReady`(f65 幂等)/`封面 sendRevealReady`(f81)/全部翻译/物品栏初始化/`notifyGameEntered` | UI 门闩 |
| 23 | MAIN | :1442-1482 (f129 `读盘`) | `stop()`；`是否存过盘()` 分流（坏档/无盘/正常） | **首个常规用户交互阻塞** |
| 24 | MAIN | :1510+ (f135 `基地地图`) | `play()` 进游戏主循环 | 运行 |

---

## 2. stop/play 配对（完整性已闭合）

- **配对①（f4→f5，跨时间轴两跳链）**：asLoader f4 `this.stop()`@138 ←解冻← MAIN f33 `_root.asLoader.play()`@1271。中间链：f4 onEnterFrame 成功不解冻自己，而是 `gotoAndStop("boot_check")`@207 把 MAIN f1→f5→(单机版开始)→f33。
- **配对②（MAIN f33→f52+，asLoader 卸载回驱）**：MAIN f33 `stop()`@1270 ←解冻← asLoader f91 `_root.play()`@821。**顺序铁律：先 `_root.play()` 再 `removeMovieClip()`**。
- **配对③（asLoader 内部异步 JSON 硬门）**：f5 stop@222←cb@231；f6 stop@245←cb@254；f75 stop@787←cb@810。
- **fail-closed**：shim 缺失 = MAIN 永冻 f1（非靠 f62）；socket 10s（asLoader.xml:160）；handshake 60s（shim:59，覆盖 `BootstrapHandshake.DEFAULT_TIMEOUT_MS=5000`）；f4 内联注释「整体10s」**过时勿信**。

---

## 3. BootSequencer 状态机规格（施工核心）

**形态**：asLoader 折叠为单关键帧 MovieClip；帧首 `stop()`；`_root` 挂 tick（仿 `DataQueryService.whenAvailable` 存活模式，确保自删后回调可达）。原 f0-f91 折叠为顺序 stage + gate。**防重跑靠帧首 stop + 幂等 guard，不靠"play 不 loop"**（§0）。

```
_root.__boot.tick()  (onEnterFrame 驱动)

S0_INIT      [同步 f0-f1]   guard s0done: _lockroot=false; GlobalInitializer.initialize(); →S1
S1_SYNC_CODE [同步 f2-f3]   guard s1done: #include 引擎×18+通信×9(建 _root._bootstrap); →S2
S2_HANDSHAKE [异步, 移植 f4] ★跨SWF★
   if(_bootstrap==undefined){置 _bootstrapFailed; HALT 加载画面}  // fail-closed
   阶段1 等 isSocketConnected; >10000ms→socket_connect_timeout HALT; 连上→startHandshake()(幂等)
   阶段2 hs=handshakeStatus(); Failed→HALT; !=Success→return(自旋)
         Success: if(!_bootstrapPreloadFired) 读取本地存盘();
                  GATE: if(存档恢复等待中()) return;   // C2-β 修复决策自旋
                  if(!_bootstrapReadySent) sendReady(); →S3
   超时: socket 10s / handshake 60s (删 MAIN 63/64 自旋回环)
S3_TASKDATA  [异步 await]   loadTaskData→taskDataReady; await→S4
S4_TASKTEXT  [异步 await]   loadTaskText→taskTextReady; await→S5
S5_PARSE     [同步 f7]      ParseTaskData; raw*=null; fire loadGuideData(不await); →S6
S6_SYNC_SYS  [f9-f32,含逐tick队列] s6_pre=f9(建_root.loaders)+f10(兼容×4 push入队)+f18(最终化1:for-in跑全部_root.preloaders)
             → 每tick抽1个 _root.loaders[current]()(复刻f26最终化2 onEnterFrame切片,async多帧) → 队空 s6_post=f32(最终化3:跑全部_root.loaderkillers+删preloaders/loaders/loaderkillers三队列) →S7  ★三队列语义不同★
S7_SYNC_LOGIC[同步串行 f36-f59] 单位函数→装备→功能→关卡→战斗→UI交互→视觉 + 杂项loaders; →S8
S8_FANOUT    [fire-forget f62-74] 发起全部异步 loaders(不await); →S9
S9_CRAFTING  [异步 await f75] loadCraftingList→建 ItemObtainIndex→craftReady; await→S10
S10_HANDOFF  [f91 ★跨SWF★] _root.play()(必先); onEnterFrame=null; removeMovieClip()(或代码挂载)
```

---

## 4. 必须的主 FLA 改动清单（精确 file:line）

- **改动 A（必须）— MAIN f33 resume 信号**：`DOMDocument.xml:1271` `_root.asLoader.play()` → 状态机可观测信号（如 `_root.__boot.mainReadyToContinue=true`，S2 后据此放行 S3 起加载链）。折叠后 asLoader 单帧帧首已 stop 等握手，f33 不应再 `play()` 推帧。同帧 :1270 `stop()` 保留。
- **改动 B（原标「必须」→ 2026-06-17 经分析降级为「未做且可省，但属潜伏脆弱」，外部审阅 M1）— asLoader 实例 keyframe 寿命**：`DOMDocument.xml:1684`(index=1 dur=33) + `:1696`(index=34 移除)。**现状：未改**（实例仍 frames 1–33、f34 空关键帧移除）。**为何 happy-path 仍对**：S2 `gotoAndStop("boot_check")` 后 MAIN 走 f5→f30→**f33 `stop()` 冻结**，f33 ∈ [1,33] 跨度内 → 实例全程存活；S10 handoff 的 `_root.play()`+`removeMovieClip()` 先于 MAIN 推进到 f34 执行 → 实例由自删收尾、f34 空关键帧从不真正抢删。真机 happy-path 已印证。**潜伏脆弱（必须知晓）**：此正确性**唯一依赖 f33 的 `stop()`**——若后续任何改动移除该 stop、或失败路径让 MAIN 越过 f33，实例会在 f34 被空关键帧抢删 → `BootSequencer.host.*`（`打印加载内容`/`rawTaskData`…）全失效。**若要根除依赖**：二选一 ①延展 :1684 duration 覆盖整个加载窗 + 删/后移 :1696；②删时间轴实例改 MAIN f1 `_root.attachMovie("asLoader",…)` 代码挂载，由 S10 统一生命周期。当前选择「不改 + 靠 f33 stop」是有意取舍，非遗漏。
- **改动 C（建议）— 删 f62-64 死代码自旋**：`:1311-1316/1325-1335/1347-1356`。当前不可达；折叠后握手全在 S2。删 f63/f64 的 `gotoAndPlay(63/64)` 自旋回环；f62 可留纯诊断不驱动控制流。
- **未破坏（无需改）**：MAIN f5/f30/f52/f61/f65/f81/f129 label 与脚本不依赖 asLoader 内部帧结构；f65 `sendReady`、f81 `sendRevealReady` 保留（幂等）。

---

## 5. C1 验证（trace/socket 事件等价 — Flash SA 无 trace，走 `sendServerMessage` `[BootstrapAS]`，asLoader.xml:134-135）

采集有序事件：`frame4 entered`(:139)=S2进入 → `socket ready firing handshake`(:170)=阶段1 → `hs=Success`+`firing preload`(:182/195)=阶段2 → `存档恢复等待中` gate 进出(:198)=C2-β边界 → `sending ready ack`(:203)+`jumping boot_check`(:206)=S2收尾 → 三异步cb(`任务数据/文本/合成表加载成功`,:792)=S3/S4/S9 → f91 `_root.play()` 前后=S10。BootSequencer 发同 schema → comparator diff（顺序+事件类型+关键状态，容时间戳差）。**字节门不适用**（结构变了）。

**真机必验**：(a) C2-β 注入 `_repairPending` 坏档→S2 gate 自旋→修复卡→`applyRepairResolved`(SaveManager.as:908/924) 放行；(b) 阻断 socket→10s `socket_connect_timeout`(:162)；(c) shim 缺失 fail-closed（MAIN 冻结非靠 f62）；(d) 存档三分支 `重新游戏确认`/`存档损坏`/`跳转地图("房间")`(:1448/1452/1480)；(e) **最终化2 在场**（S6 没漏 land-frame）；(f) 生命周期不抢（改动 B **未做**，靠 f33 `stop()` 使实例在 1–33 跨度存活、handoff 先于 f34 自删 → 仍应只卸载一次，见 §4 改动 B）；(g) 单帧 loop 回绕一轮，#include/loader 不重复执行（guard 生效）。

### 5.1 trace-diff 门 + 各边界期望信号（2026-06-17 BootSequencer 化 + 失败路径日志落地）

**comparator 已就位**：`node tools/trace-diff.js diff <golden> <new>`（事件序列 LCS diff，分歧 exit 1）；`extract <log>` 抽规范事件。**已批处理感知**：launcher LogBatch 用 `|` 把同帧多条 `[BootstrapAS]` 拼进一行，extract 现按位置多匹配（不再 break，否则 `hs=Success|firing preload` 只留前者→假分歧）。**BootSequencer 词表已对齐 trace-diff RULES**：`handshake stage entered`→S2_ENTER（rule 已加别名）、`socket ready, firing handshake`→SOCKET_READY、`handshake hs=Success`/`handshake FAILED`→HANDSHAKE_RESULT、`firing preload`→PRELOAD_FIRE、`sending ready ack`→READY_ACK、`bootstrap complete`/`jumping boot_check`→BOOT_CHECK_JUMP、`任务数据/文本加载完毕`→TASKDATA_OK/TASKTEXT_OK。

**happy-path 期望规范序列**（extract 应见，容时间戳/批处理）：`S2_ENTER → SOCKET_READY → HANDSHAKE_RESULT → PRELOAD_FIRE →（坏档时 +RECOVERY_GATE_ENTER/EXIT）→ READY_ACK → BOOT_CHECK_JUMP → TASKDATA_OK → TASKTEXT_OK → … → CRAFTING_OK → HANDOFF_PLAY`。**✅ 2026-06-17 已实测全 10 段**（真机 boot，SWF 870267：HANDSHAKE_RESULT + 新 CRAFTING_OK/HANDOFF_PLAY 全在，`trace-diff diff` [OK]）。

> **⚠ 2026-06-17 trace 门覆盖修正（外部审阅 Medium）**：当前固化的 `tools/baselines/boot-golden.log` **仅覆盖 S2–S4**（末事件 = `TASKTEXT_OK`）。根因：`TASKDATA_OK/TASKTEXT_OK` 之所以可见，是因为 f5/f6 走 `_root.发布消息`→toast→socket→launcher.log；而**原 frame75（S9）/ frame91（S10）只有 `trace()`，Flash SA 剔 trace → 从不进 launcher.log**，故 golden 无 `CRAFTING_OK`/`HANDOFF_PLAY`，**S5–S10 整段对 trace-diff 不可见 → S9/S10 回归能通过门**。
> **已修（源级，待重编 + 重抓 golden 生效）**：`BootSequencer.stepCrafting` 成功 cb 加 `bslog("合成表数据加载完毕")`→`CRAFTING_OK`；`handoff()` 首行加 `bslog("event=handoff")`→`HANDOFF_PLAY`（走 `[BootstrapAS]` 诊断通道，**不发 `发布消息` 故无新 UI toast**，行为零变化）。
> **语义须知**：旧多帧 boot 对 S9/S10 **物理上发不出**可见事件，故 `CRAFTING_OK`/`HANDOFF_PLAY` **不是「旧↔新等价」项，而是「塌缩 boot 的前向回归快照」**——必须用**塌缩 boot 重抓一份新 golden**（含这两事件）作基线，旧 golden 只继续守 S2–S4 等价。**✅ 2026-06-17 已闭合**：真机 boot（recompile 后 SWF 870267）→ `tools/baselines/boot-golden.log` 重抓为单次完整 boot（S2→S10 共 10 事件），`trace-diff diff` [OK]。两新事件真机确发。

**七边界触发 + 期望 `[BootstrapAS]` 信号**（失败路径双通道日志=`BootSequencer.stepHandshake`/`halt`，2026-06-17 恢复）：

| 边界 | 触发方式 | 期望 launcher.log 信号 | 通过判据 |
|---|---|---|---|
| (a) C2-β 坏档 | 注入 `_repairPending` 坏档（关游戏写无 SOL 的坏档 json，见 [[save-system-sol-json-shadow]]） | PRELOAD_FIRE 后存档恢复 gate 自旋、`applyRepairResolved` 放行 | gate 进出各一次、不死锁、放行进游戏 |
| (b) socket 超时 | 不启 launcher 直开 SWF / 防火墙挡端口 | `socket timeout after ~10000ms` + `HALT: socket_connect_timeout` + 玩家见「启动器连接超时」 | 主 SWF 冻结不前进(fail-closed)、日志有因 |
| (c) shim 缺失 | 改 shim 注入路径使 `_root._bootstrap` 不建 | `shim missing, stopped` + `HALT: shim_missing` + 玩家见「启动器通信 shim 缺失」 | MAIN 冻结在 f1(非靠 f62)、日志有因 |
| (d) 存档三分支 | 新档/坏档/正常档各跑一次 | `重新游戏确认`/`存档损坏`/`跳转地图("房间")` 对应分支 | 各分支走对、无串档 |
| (e) 最终化2 在场 | 正常 boot 观察 S6 | 佣兵满编（S6 逐 tick 抽干 loaders + 异步等待门） | `mercsList=204`、商城/兵种全载=land-frame 未漏 |
| (f) 生命周期 | 正常 boot 观察卸载 | asLoader 仅 handoff 卸载一次 | 无残留 asLoader 实例、无重复 boot |
| (g) 单帧 loop | 正常 boot（单帧 play 回绕） | `run()` 幂等 guard 生效，#include/loader 不重复 | 无双重初始化/双 tick |

握手失败(b/c)现 `halt()` 在 fail-closed 后**释放 `_instance` + 回收 tickClip** → 同会话可重试（关 launcher 重开 / 补 shim 后重挂 asLoader 不卡在「无 tick 驱动」死状态）。

### 5.2 七边界构造细则（2026-06-17 落地，回答「条件如何构造」）

> **贯穿性陷阱（先读）——诊断通道本身依赖 socket**：所有 `[BootstrapAS]` 日志都走 `_root.server.sendServerMessage`→socket→launcher.log。**socket 没连上时这条通道本身是哑的**。故凡涉及 socket 未连/未握手的边界（b、部分 c），**主判据必须是「玩家可见文案 + 主 SWF 冻结」**，launcher.log 信号是 best-effort（只有 socket 后来连上/通道有缓冲才到）。别把「日志没出现」误判为「代码没跑」。

- **(a) C2-β 坏档恢复 gate**（`_repairPending` 自旋 → `applyRepairResolved` 放行）
  - **前置**：launcher 正常运行（需其 BootstrapPanel 修复卡 + 推 `task=repair_resolved` 的链路在）。
  - **构造**：关游戏 → 在 `saves/` 写一个**结构损坏**的槽位 json（截断/字段缺失）、**且无同名 `.sol`**（无 SOL → 强制走 JSON 恢复，见 [[save-system-sol-json-shadow]]）→ 启动。`读取本地存盘()`(preload) 检出损坏 → `SaveManager` 置 `_repairPending=true`(SaveManager.as:519)。
  - **观察**：`PRELOAD_FIRE` 后，S2 hsPhase2 卡在 `if(存档恢复等待中())return` 自旋；屏上停在修复卡；走完修复 → launcher 推 `repair_resolved` → `applyRepairResolved`(SaveManager.as:924) 清 flag → 下一 tick `READY_ACK`→`BOOT_CHECK_JUMP`。
  - **判据**：gate 进出各一次、不死锁；修复后进游戏；`mydata` 喂的是 cleaned snapshot（非坏档）。

- **(b) socket 连接超时**（10s → `HALT: socket_connect_timeout`）
  - **构造（择一）**：①直接双击 `CRAZYFLASHER7MercenaryEmpire.swf`/SA 播放器开主 SWF，**不经 launcher**（无 socket server）；②launcher 在跑但**防火墙挡其 XMLSocket 端口** / 改端口令连不上。①更彻底但无 launcher 即无 launcher.log。
  - **观察**：约 10s 后玩家见**「启动器连接超时」**、主 SWF 冻结在 f1 不前进。`socket timeout after ~10000ms` + `HALT: socket_connect_timeout` 仅当通道可达才进 log（见上陷阱）。
  - **判据**：fail-closed（不进游戏、不黑屏崩）；屏面文案正确。**首要看屏不看 log**。

- **(c) shim 缺失**（`_root._bootstrap==undefined` → `HALT: shim_missing`）—— **✅ 2026-06-17 真机过**
  - **构造**：让 asLoader 不建 shim。当前 SWF 必含 shim，故需特制：①临时注释 `_collapsed_frame.as` 的 f3 里 `通信_fs_bootstrap.as` include（或源帧 frame3.as）→ 重编一个**一次性 SWF**（**注意 `git checkout asLoader.swf` 会回退到 HEAD 的 pre-S9/S10 旧 SWF → 还 good SWF 必须重编，不能 checkout**）；②或换入归档的**前-bootstrap asLoader.swf**（旧 build）。
  - **观察**：`_root.server` 仍建（本地服务器在 bootstrap 之前 include）故 socket 能连、日志可达 → AS2 侧 `shim missing, stopped` + `HALT: shim_missing` + 玩家见**「启动器通信 shim 缺失」**；MAIN 冻结在 f1（**非靠 f62 死代码**，§0 CHECK2）。**⚠ 实测屏幕停在 launcher 的 `Error: handshake_timeout`**：launcher 侧 `WAIT_HANDSHAKE_MS=8000`（GameLaunchFlow）8s 收不到 `bootstrap_handshake` → `WaitingHandshake -> Error (handshake_timeout)` → 杀 Flash（zombie close），抢在 AS2「shim 缺失」文案之前接管 UI。**双层 fail-closed，互不依赖**。
  - **判据**：AS2 日志 `HALT: shim_missing`（停在 S2 无后续）+ launcher `handshake_timeout` + 进不去游戏；**测毕重编 good SWF 还原（非 checkout）**。

- **(d) 存档三分支**（MAIN f129 读盘分流）
  - **构造**：分别准备 ①**无任何存档**（删槽位 json+sol）→ `重新游戏确认`；②**坏档**（同 (a) 但走到 f129，或恢复后仍异常）→ `存档损坏`；③**正常档**（完整 sol+json）→ `跳转地图("房间")`。各跑一次。
  - **判据**：三分支各走对、无串档、无把正常档判坏。

- **(e) 最终化2 在场 + S6 异步等待门**（佣兵满编）
  - **构造**：正常 boot 即可（无需注入）。重点验**塌缩压紧 tick 后异步 preload 仍落地**。
  - **观察**：S6 sysPhase1 等待门（最少 30 帧 + `__pendingFileLoads==0`，150 帧兜底）后才逐 tick 抽 loader。
  - **判据**：佣兵满编 `mercsList=204`、商城/兵种/商店全载（land-frame 即原 f26 最终化2 未漏）。**回归信号 = `mercsList=1`**（等待门失效）。

- **(f) 生命周期不抢**（asLoader 仅卸载一次；改动 B 未做，靠 f33 stop）
  - **构造**：正常 boot。
  - **观察/判据**：boot 完成后 `_root.asLoader == undefined`（实例已由 handoff 自删）；无残留空 clip；boot 代码只跑一次。**⚠重点回归探针**：因改动 B 未做（§4），实例存活全靠 MAIN f33 的 `stop()`——若改了 f33 或失败路径让 MAIN 越过 f33，实例会在 f34 被空关键帧抢删致 host 失效。验时确认 MAIN 确实冻结在 f33 直到 handoff。

- **(g) 单帧 loop 不重复**（帧首 stop + 幂等 guard）
  - **构造**：正常 boot。单帧 `this.stop()` 本就不 loop；本项验**即便回绕也不双初始化**。
  - **观察/判据**：`BootSequencer.run()` 因 `_instance != undefined` 早退、`if(_root.__boot==undefined)` guard 生效 → 无双 tick / 无 #include 二次执行 / 无 loader 重复 fire。主动测可临时去掉帧首 stop 观察 guard 兜底（**测毕还原**）。

**统一采集 + 判定**：正常路径跑完后 `node tools/trace-diff.js extract logs/launcher.log` 看事件序列；happy-path 应见 §5.1 规范序列（含新 `CRAFTING_OK`/`HANDOFF_PLAY`）。失败边界看 `HALT: <reason>` + 玩家文案。**先重抓一份塌缩 boot 的 golden 再 `diff`**（旧 golden 仅 S2–S4，§5.1）。

### 5.3 验证分层与载体（2026-06-17 落地，回答「用 TestLoader / bus-only 是否更方便」）

把七边界拆三层载体，**绝大多数故障逻辑可自动化，残留人类项收敛到 3 类**：

- **L1 — TestLoader 单元测试**（`scripts/类定义/org/flashNight/boot/BootSequencerTest.as` → 挂进 `scripts/TestLoader.as` → `compile_test.ps1` 抓 trace）：在 debug player 里 **mock `host`/`_root._bootstrap`/`_root.server`/`_root.__boot` staged 函数/`存档恢复等待中` 等**，直接 `new BootSequencer(host)` + 手动驱 `step()` 断言状态机。**deterministic、每次改 BootSequencer.as 即回归**。覆盖：(b) socket 超时、(c) shim 缺失、握手失败、(a) 修复 gate 自旋→放行、(g) `run()` 幂等、S6 等待门/抽干顺序、**新 `CRAFTING_OK`/`HANDOFF_PLAY` 发一条**（= 把 Finding 1 变回归守卫）。
- **L2 — `launcher --bus-only` + `cfn-cli`**（headless 起 socket bus + 托管游戏，不建 BootstrapPanel）：抓 **happy-path golden**（`cfn-cli start-bus` → 游戏 boot → `cfn-cli ... log` 导 launcher.log → `trace-diff.js diff`）。socket-present 集成验。
- **L3 — 真机正常模式**：不可 mock 的 Flash/集成行为。

| 边界 | 载体 | 自动化 | 备注 |
|---|---|---|---|
| (b) socket 超时（逻辑） | L1 | ✅ | `inst.hsStart = getTimer()-11000` 后 step → HALT |
| (c) shim 缺失 | L1 | ✅ | `_root._bootstrap=undefined` |
| 握手失败 | L1 | ✅ | mock `handshakeStatus()="Failed"` |
| (a) 修复 gate 逻辑 | L1 | ✅ | mock `存档恢复等待中` true→false |
| (g) 单帧 loop 幂等 | L1 | ✅ | `run()` 二次断言早退 |
| S9/S10 事件发出 | L1 | ✅ | mock `sendServerMessage` 记录断言 |
| happy-path golden + trace 等价 | L2 | ✅ | **2026-06-17 已完成**：recompile 后真机 boot → golden 重抓（S2→S10 10 事件）→ `trace-diff` [OK] |
| (c) **真** shim 缺失 fail-closed | L3 | ✅ | 2026-06-17 过：AS2 `HALT: shim_missing`（停 S2 非靠 f62）+ launcher `handshake_timeout` 双层 |
| (b) **真** socket 连接/超时 | L3 | ◑ | 视觉态等价已见（独立开 SWF 卡死协议帧）；纯看屏(socket 断→日志哑)、L1 已覆盖逻辑。**连接/XMLSocket/trust 类只用真 launcher，桩常假阳性**（testing-guide） |
| (a) 修复**端到端**（修复卡 UI） | L3 | ✅ | 2026-06-17 过：L0 坏档→RepairPending→S2 gate 自旋→applyRepairResolved→boot（见 §5.3 进度） |
| (d) 存档三分支 | L3 | ✅ | 2026-06-17 过：正常/新档(decision=empty)/坏档(随 a)；真 SaveManager + 真 SOL/JSON |
| (e) 佣兵满编 / staged #include 真跑 | L3 | ✗ | 需真编译 SWF（64KB chunk + 真 preloader 时序） |
| (f) 跨 SWF 生命周期 + f33-stop 依赖 | L3 | ✗ | Flash 时间轴实例寿命，mock 不出 |

**⚠ L1 的边界（别误判覆盖）**：单测跑的是 **mock 后的逻辑**；塌缩引入的 4 个回归全是「**编译 0 错却运行时坏**」（chunk 调 base 名 / eager 单例跨类调用 / 大小写 typo / 异步压紧 tick），**恰好盲于 L1**。L1 是快速内环（守状态机逻辑回归），**不替代 L2/L3**。

#### L2 golden 重抓步骤（须先人类 CS6 重编）

`logs/launcher.log` 由 launcher 自写（LogManager.InitFileLog），**无 cfn-cli 子命令拉取**（`cfn-cli log <msg>` 是**发**调试消息，非读）——直接读该文件即可。

```bash
# 0)（人类）CS6 重编 asLoader.swf —— BootSequencer 新事件 + 任何源改入 SWF（结构改需 reopen，见 testing-guide）
# 1) 真 boot 一次（择一）：
bash automation/start.ps1                  # 正常模式（最贴真机；连接/握手类首选）
#   或 headless：bash tools/cfn-cli.sh start-bus && bash tools/cfn-cli.sh wait-socket
#   （bus-only 起 socket bus + FlashHostPanel；游戏是否自动托管 vs 需外部 Flash 连入按当前链路确认）
# 2) boot 完成后 launcher 已落 logs/launcher.log：
node tools/trace-diff.js extract logs/launcher.log         # 末段应见 …→CRAFTING_OK→HANDOFF_PLAY
# 3) 序列正确后固化为新 golden（建议只截取本次 boot 段）：
cp logs/launcher.log tools/baselines/boot-golden.log
node tools/trace-diff.js diff tools/baselines/boot-golden.log logs/launcher.log   # [OK] 自洽
# bus-only 收尾：bash tools/cfn-cli.sh stop-bus
```

> ⚠ **连接/握手类只用真 launcher**（testing-guide §「`--bus-only` 适用」铁律）：testMovie 的 socket 沙箱与独立播放器不同、裸桩常假阳性。故 (b) 真 socket 超时归 L3，不在 L2 用 testMovie 代测。

#### 进度（2026-06-17）

1. ✅ **CS6 重编 asLoader.swf** —— agent 经 compile_test 触发，0 错误，SWF 870233→870267（+34=两 bslog），codeSize 门过。
2. ✅ **CS6 跑 TestLoader/BootSequencerTest** —— agent 临时 retarget harness 触发，**36/36 PASS，0 `[TEST_FAIL]`，0 编译错误**（harness 已 git 还原）。
3. ✅ **L2 golden 重抓 + `trace-diff diff`** —— recompile 后真机 boot 落 `logs/launcher.log`，抽末次完整 boot（S2→S10 10 事件，含真机实发的 `CRAFTING_OK`/`HANDOFF_PLAY`）→ 覆盖 `tools/baselines/boot-golden.log` → `trace-diff diff` [OK]。

**L3 故障/存档边界进度**：
- ✅ **(c) shim 缺失（2026-06-17 真机过）**：agent 编无-shim SWF（868014 B，注释 f3 bootstrap include）→ 真机 boot。**双层 fail-closed 实证**：AS2 侧 `handshake stage entered, _bootstrap=false` → `shim missing, stopped` → `HALT: shim_missing`（无后续 firing handshake/boot_check/handoff = 停在 S2，非靠 f62）；launcher 侧 8s 后 `wait timeout: handshake_timeout` → `WaitingHandshake -> Error` → 杀 Flash。**屏幕显示的是 launcher 的 `Error: handshake_timeout`（launcher 抢先接管 + 杀进程，AS2 的「shim 缺失」文案一闪而过）**。测后 agent 重编 good SWF（870268）还原。
- ✅ **(a) 修复端到端 / C2-β 手动 gate（2026-06-17 真机过）**：fixture = `saves/repair_a.json` 角色名 `$[0][0]` 注入 `�`（L0=永远 Manual）+ 删 `repair_a.sol`（SOL 每次保存会重生，无-SOL 测必删）。日志全程：`[AutoRepair] repair_a fffd=1 applied=0 kept_for_manual=1`（L0 留手动）→ `SolResolver repairable byLayer=L0:1 source=json_shadow` → `repair_required posted` → `Embedding -> RepairPending` → **AS2 S2 gate 自旋**（`[SaveManager.preload] repairable: pending user decision` 后**无 sending ready ack**）→ 用户在修复卡决策（丢弃 `path=["0","0"] ClearValue`）→ `RepairPending -> WaitingGameReady` → `[SaveManager.applyRepairResolved] applied cleanedSnapshot, pending cleared` → **`sending ready ack` → `boot_check` → `event=handoff` → reveal**。gate 自旋→放行→boot 完成，不死锁/不串档/角色名落地为决策值。**asLoader 的 `存档恢复等待中` gate 真机确证**（与 L1 `test_repairGate_spinsThenReleases` 互证）。
  - **观察记**：reveal 是引导器面板盖住 Flash 直到 handoff 后 `panel swap` 一次性露出（`requireFlashReveal` 设计，AS2 加载画面全程被盖）→ 非本次重构行为；reveal 路径（MAIN f81 `sendRevealReady`@DOMDocument.xml:1373 + launcher-web）不在本次 diff（范围内 MAIN 仅改 f33 改动A）。
- ✅ **(d) 存档三分支（2026-06-17 真机过）**：正常档（test，`loadAll source=sol OK weqr lv100`）+ 新档（空槽 `crazyflasher7_saves8`：`save resolved wire=empty kind=Empty` → `decision=empty` → 即 `sending ready ack` → `boot_check` → `event=handoff` → reveal，无 gate 无报错）+ 坏档分支已随 (a) 覆盖。
- ✅ **握手失败 fail-closed（2026-06-17 顺带实证）**：测试快速关/重开导致 13:01:33 / 13:04:30 两次 `handshake FAILED: callback timeout` → `HALT: handshake_failed`，AS2 正确停在 S2，下次干净启动恢复（halt() 释放 _instance 生效）。与 L1 `test_handshakeFailed_halts` 互证。
- ⏳ 剩 **(b) 真 socket 超时**：纯看屏（socket 断→`[BootstrapAS]` 通道也哑，无 AS2 日志）；独立开 SWF 已见「卡死协议帧」≈ 等价 fail-closed；逻辑 L1 `test_socketTimeout_halts` 已覆盖。低价值，可速过/跳。
- 📝 **观察（单次、自恢复、不阻塞）**：12:31 一次 boot 在 handoff/S9 附近 `UIFreezeProbe ui_stale ~2562ms` 后 `ui_stale_exit`（~1s 自恢复）；仅一次，疑与晚期 boot 密集工作（S9 建 ItemObtainIndex / panel-swap）或「S7 单 tick 跑完全部 include」权衡相关；频繁复现再深究。
- (e) 佣兵满编 / (f) 生命周期 happy-path 面已随成功 boot（跑到 HANDOFF_PLAY + 卸载一次）覆盖；故障注入态建议真机眼验。

---

## 6. 残留不确定（需真机确认）

1. **f25→f27 land-frame 精确 AVM1 时序**：已从"游戏可启动"反推确凿，建议真机插桩确认最终化2/3 执行先后（折叠后此不确定性消失）。
2. **UI交互/视觉系统层 #include 行号**（asLoader.xml:936/976）：未逐字 re-grep，施工前确认这两层文件清单完整。
3. **fire-and-forget loaders（S8）重复发起幂等**：单帧 loop 回绕若误触，确认各 loader getInstance 单例 / DataQueryService query 去重（:454/476/605/615/648/667/685/704/742/770）。
4. **改动 B 方案选择**（延展 keyframe vs attachMovie）：attachMovie 需确认 linkage export 已开（`libraryItemName="import/scripts/asLoader"`,:1686）+ 真机验 `_root.asLoader` 引用/`_lockroot`/`_root` 透传等价。
5. **`__bootstrapWaitTick` clip**（BootstrapWait.as:52-53 挂 `_root`）：删改动 C 后确认无悬挂 onEnterFrame。
6. **whenAvailable 存活**（asLoader.xml:605）：S8/S2 回调在 S10 自删后若在途，须确认 whenAvailable 把回调挂 `_root` 非实例（tick 选 `_root` 宿主的根因）。

---

## 7. 施工 Runbook（执行清单 · 带门）

> **进度（2026-06-16，Flash 干净只开 asLoader，已授权编译）**：
> - ✅ 编译环回 + 字节门确定性已证（无改动重编 byte-identical；ASO 增量 35s vs 110s）。
> - ✅ **P3 externalize 已完成**：38 帧 CDATA 外置到 `scripts/asLoaderManifest/`（`tools/externalize-asloader-frames.js`），3 次编译全 byte-identical，symbol XML 冻结（635→38 行）。**C2 原痛已解 + 零行为变更**。跳过琐碎帧（f11/25/27 goto、f48 print、f49-52 注释）。
> - ✅ trace 门实证：`logs/launcher.log` 真 boot trace → golden 存 `tools/baselines/boot-golden.log`。
> - ⏳ 下面 P3-staged-wrap / P4 / P5 = **非 byte-identical，需真机 boot 验**（trace 门 happy-path 可验，7 边界场景需人观察）。每步后跑对应门，红则回退该步。

**约定**：编译走 `powershell -File scripts/compile_test.ps1 -TimeoutSeconds 150`（asLoader publish 慢机 ~77-113s；已含预编译 BOM 门）。字节门 = `node tools/swf-tag-diff.js diff tools/baselines/<相位>.golden.json scripts/asLoader.swf`。**每相位起点先 `node tools/swf-tag-diff.js dump scripts/asLoader.swf --out tools/baselines/<相位>.golden.json` 固化基线**。

### P3 前置静态门已落地 + 结论（2026-06-16，纯 node，零源改，已把折叠从「设计」推进到「可施工规格」）

折叠（把每帧 #include 包成 `_root.__boot.sN=function(){...}` 由状态机调度）有两处静态风险，原 Runbook 只有 TODO 没有工具。现各建一门，**两门均给出确定性绿灯结论**：

- **门 ① 联合 import 头碰撞**：`node tools/lint-frame-imports.js --fold-specific [--strict]`。把 47 个具体 import 的「包」并入通配并集（= 子文件剥具体 import、靠单帧联合头解析的终态），重算跨包叶名碰撞。**结论：折叠新增 6 包（`gesh.pratt`/`gesh.text`/`gesh.xml.LoadXml`/`neur.InputCommand`/`neur.PerformanceOptimizer`/`arki.unit.Action.Melee`）→ 并集 76→82，新引入碰撞 = 0**。⇒ 折叠时子文件**仅需删掉自带具体 import，零 FQN 改写**。`--strict --fold-specific` exit 0。
  - **⚠ 单一具体 import 白名单例外（外部审阅 Low，2026-06-17 显式化）**：塌缩产物 `_collapsed_frame.as` **故意保留恰好一条具体 import**——`import org.flashNight.boot.BootSequencer;`（L42 陷阱：CS6 会话缓存对会话内新建类，通配头/FQN 都可能解析失败，须显式具体 import）。它由 `assemble-collapsed-frame.js` **生成后注入**，不在任何被 lint 扫描的时间轴帧源内，故 `lint --fold-specific` 的 strict 分支**按设计只判「折叠新碰撞」、不判「具体 import」**（具体 import 是折叠终态会被联合头吸收的合法形态），看不到也不应 flag 这条。**结论：这是唯一允许的具体 import，治理上等价于白名单单例**；新增任何**其它**具体 import 到产物都属违规（评审 `_collapsed_frame.as` 头部时人工把关）。「strict」之名不覆盖此例外是已知且有意。
  - **权威联合头（82 包，已验证 0 碰撞）= 折叠后单帧 CDATA 顶部固定块**：

```as2
// === asLoader 单帧折叠 · 联合 import 头（82 包，0 跨包碰撞，lint --fold-specific 验证）===
import flash.display.*; import flash.filters.*; import flash.geom.*;
import org.flashNight.arki.achievement.*; import org.flashNight.arki.audio.*;
import org.flashNight.arki.bullet.BulletComponent.Attributes.*; import org.flashNight.arki.bullet.BulletComponent.Chain.*;
import org.flashNight.arki.bullet.BulletComponent.Collider.*; import org.flashNight.arki.bullet.BulletComponent.Init.*;
import org.flashNight.arki.bullet.BulletComponent.Lifecycle.*; import org.flashNight.arki.bullet.BulletComponent.Movement.*;
import org.flashNight.arki.bullet.BulletComponent.Movement.Util.*; import org.flashNight.arki.bullet.BulletComponent.Queue.*;
import org.flashNight.arki.bullet.BulletComponent.Shell.*; import org.flashNight.arki.bullet.BulletComponent.Type.*;
import org.flashNight.arki.bullet.BulletComponent.Utils.*; import org.flashNight.arki.bullet.Factory.*;
import org.flashNight.arki.camera.*; import org.flashNight.arki.collision.*;
import org.flashNight.arki.component.Buff.*; import org.flashNight.arki.component.Buff.Component.*;
import org.flashNight.arki.component.Collider.*; import org.flashNight.arki.component.Damage.*;
import org.flashNight.arki.component.Effect.*; import org.flashNight.arki.component.Shield.*;
import org.flashNight.arki.component.StatHandler.*; import org.flashNight.arki.corpse.*;
import org.flashNight.arki.cursor.*; import org.flashNight.arki.item.*; import org.flashNight.arki.item.ItemUtil.*;
import org.flashNight.arki.item.drug.*; import org.flashNight.arki.item.itemCollection.*; import org.flashNight.arki.item.itemIcon.*;
import org.flashNight.arki.key.*; import org.flashNight.arki.map.*; import org.flashNight.arki.merc.*;
import org.flashNight.arki.render.*; import org.flashNight.arki.scene.*;
import org.flashNight.arki.spatial.animation.*; import org.flashNight.arki.spatial.move.*; import org.flashNight.arki.spatial.transform.*;
import org.flashNight.arki.stageSelect.*; import org.flashNight.arki.task.*; import org.flashNight.arki.unit.*;
import org.flashNight.arki.unit.Action.Melee.*; import org.flashNight.arki.unit.Action.PickUp.*;
import org.flashNight.arki.unit.Action.Regeneration.*; import org.flashNight.arki.unit.Action.Shoot.*; import org.flashNight.arki.unit.Action.Skill.*;
import org.flashNight.arki.unit.UnitComponent.Deinitializer.*; import org.flashNight.arki.unit.UnitComponent.Dressup.*;
import org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.*; import org.flashNight.arki.unit.UnitComponent.Initializer.*;
import org.flashNight.arki.unit.UnitComponent.Routing.*; import org.flashNight.arki.unit.UnitComponent.Targetcache.*;
import org.flashNight.arki.weather.*; import org.flashNight.aven.Coordinator.*; import org.flashNight.aven.Proxy.*;
import org.flashNight.gesh.arguments.*; import org.flashNight.gesh.array.*; import org.flashNight.gesh.depth.*;
import org.flashNight.gesh.json.LoadJson.*; import org.flashNight.gesh.object.*; import org.flashNight.gesh.path.*;
import org.flashNight.gesh.pratt.*; import org.flashNight.gesh.string.*; import org.flashNight.gesh.text.*;
import org.flashNight.gesh.tooltip.*; import org.flashNight.gesh.xml.LoadXml.*;
import org.flashNight.naki.DataStructures.*; import org.flashNight.naki.PseudoRandom.*;
import org.flashNight.naki.RandomNumberEngine.*; import org.flashNight.naki.Sort.*;
import org.flashNight.neur.Controller.*; import org.flashNight.neur.Event.*; import org.flashNight.neur.InputCommand.*;
import org.flashNight.neur.PerformanceOptimizer.*; import org.flashNight.neur.ScheduleTimer.*; import org.flashNight.neur.Server.*;
import org.flashNight.neur.StateMachine.*; import org.flashNight.sara.*; import org.flashNight.sara.util.*;
```

- **门 ② 作用域安全（staged 函数把帧体从时间轴作用域搬进函数作用域）**：`node tools/audit-frame-scope-safety.js [--strict]`。枚举每帧顶层时间轴声明（列 0 `var`/`function`/裸赋值，剥字符串+注释、shadowing 抑制），扫全帧裸引用，报告**跨帧**依赖。**结论：45 个顶层声明里，仅 2 个被跨帧裸读 → 必须放在折叠后单帧的「帧顶（时间轴作用域）」而非任何 staged 函数体内**：
  1. **`打印加载内容`**（f0 `function 打印加载内容(str)`，被 f2/3/4/5/9/32/36/48/62/69 裸调）= 真实加载进度打印函数。
  2. **`onError`**（f41 `function onError():Void {/*TODO*/}`，被 f3 `_root.载入关卡数据` 错误回调裸调）= **空 TODO 死桩**，AVM1 下卸载后调用为静默 no-op，折叠须保留同等（benign）行为。
  - 其余 43 个顶层声明（含 `技能桶`/`装备桶0-3`/`技能点数查找表` 等 16 个表）**仅本文件/本帧引用** → 放进各自 staged 函数体即可，靠同体 + `_root.*` 闭包捕获存活。⇒ **staged 函数设计对全 boot 安全，唯一约束 = 这 2 个符号置于帧顶**。
  - 信息性：`asloader` 在 f5/f6/f75 各 `var asloader=this`（异步回调捕获 asLoader 实例的惯语）→ 折叠后由 `BootSequencer.host`（`self.host`）替代，draft 已如此。

> **折叠 viability 已确定性闭合**（静态层）：联合头零碰撞 + 作用域仅 2 符号需帧顶。剩余不可静态证的只有 AVM1 运行时「函数字面量捕获时间轴 scope chain」行为（staged 函数内裸引用帧顶 `打印加载内容`/类名能否解析），属 §5「真机必验」范畴，非设计阻塞。

### P3 — 同步段去 import + 包 staged 函数（源改，可分批）

P3 改变执行结构（包进函数+延迟调用）→ **字节门不适用**，靠 compile 0 错 + lint + scope 门 + 后续 trace 等价。建议**先在现有多帧结构上验证 staged 函数可用**，再 P5 折叠。

1. ✅ **联合 import 头已定**（见上「P3 前置门 ①」：82 包、0 碰撞、可粘贴块）。门 = `node tools/lint-frame-imports.js --strict --fold-specific`（exit 0）。
2. 逐 group（14 个同步帧：引擎/通信/单位函数/装备/功能/关卡/战斗/UI/视觉/系统分区/最终化1/2/3）：把帧体 `#include` 列表包成 `_root.__boot.sN_xxx = function(){ ... }`（子文件**剥自带具体 import**，靠联合头解析，**零 FQN 改写已证**；BOM 用 `WriteAllBytes`/copy-from-existing）。**最终化2 单列入 S6 串行**。
   - ⚠ **`打印加载内容` 与 `onError` 必须留在折叠帧「帧顶」（时间轴作用域），不得包进任何 staged 函数**（门 ② 结论）；其余 43 个顶层声明放进各自 staged 函数体。
3. scope 门：`node tools/audit-frame-scope-safety.js --strict`（多帧源上现报 2 = 上述 2 符号，折叠为单帧后天然归零）。lint 门：`node tools/lint-frame-imports.js --strict --fold-specific`（折叠新碰撞 → 0）。
4. compile 门：`compile_test.ps1` 0 错 + SWF 刷新。

### P4 — 接 BootSequencer + 主 FLA 改动（最高危）

5. 评审 `org.flashNight.boot.BootSequencer.as`（DRAFT）：消除 6 条未验证假设；接 staged 函数名与 P3 对齐；显式 import 自检（L42）。
6. 主 FLA 改动 A（必须）：`DOMDocument.xml:1271` `_root.asLoader.play()` → `_root.__boot.mainReadyToContinue=true`。
7. 主 FLA 改动 B（必须）：asLoader 实例 keyframe 寿命（:1684/:1696）—— 选延展 keyframe 或 attachMovie 代码挂载（推荐后者）。
8. 主 FLA 改动 C（建议）：删 f62-64 死代码自旋（:1311-1356）。
9. **boot trace 插桩**：给「当前（未折叠）boot」按 §5 事件清单插桩发 `[BOOTTRACE] event=<ID>`（走 `_root.server.sendServerMessage`），跑一次真机 boot → 存 golden 事件日志。
10. compile 门（主 SWF 也需重编 —— 仅 11 个 mx 类，快）+ `node tools/audit-as2-class-embedding.js --policy single-ownership`（主 SWF 仍 0 org.flashNight）。

### P5 — 时间轴塌缩单帧 + 收尾

11. asLoader symbol 塌缩为单关键帧：联合头 + staged `#include` + `BootSequencer.run(this)`；删旧多帧多层（留旧 symbol 副本备回退）。
12. compile 门 0 错 + SWF 刷新。
13. **trace 等价门**：折叠后真机 boot 发 `[BOOTTRACE]` → `node tools/trace-diff.js diff <golden.log> <new.log>` 必 `[OK]`。
14. **真机必验**（§5 a-g）：C2-β 坏档修复 / socket 超时 / shim 缺失 fail-closed / 存档三分支 / 最终化2 在场 / 生命周期不抢 / 单帧 loop 不重复加载。
15. 文档治理：更新本 doc + 设计 doc + testing-guide；`node tools/validate-doc-governance.js`。

### 回退点

- P3/P4/P5 各自留 git 提交边界 + asLoader symbol 副本。任一相位 trace/真机红 → 回退该相位 symbol/源，不影响已落地的 P0-P2 工具与 P1 守门。
