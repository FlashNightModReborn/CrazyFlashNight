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
- **改动 B（必须）— asLoader 实例 keyframe 寿命**：`DOMDocument.xml:1684`(index=1 dur=33) + `:1696`(index=34 移除)。二选一：①延展 :1684 duration 覆盖整个加载窗（至少到 f81 封面前）+ 删/后移 :1696；②**推荐**：删时间轴实例，改 MAIN f1 脚本 `_root.attachMovie("asLoader",…)` 代码挂载，由 S10 `removeMovieClip()` 统一生命周期（消除 keyframe 与自删双重所有权）。
- **改动 C（建议）— 删 f62-64 死代码自旋**：`:1311-1316/1325-1335/1347-1356`。当前不可达；折叠后握手全在 S2。删 f63/f64 的 `gotoAndPlay(63/64)` 自旋回环；f62 可留纯诊断不驱动控制流。
- **未破坏（无需改）**：MAIN f5/f30/f52/f61/f65/f81/f129 label 与脚本不依赖 asLoader 内部帧结构；f65 `sendReady`、f81 `sendRevealReady` 保留（幂等）。

---

## 5. C1 验证（trace/socket 事件等价 — Flash SA 无 trace，走 `sendServerMessage` `[BootstrapAS]`，asLoader.xml:134-135）

采集有序事件：`frame4 entered`(:139)=S2进入 → `socket ready firing handshake`(:170)=阶段1 → `hs=Success`+`firing preload`(:182/195)=阶段2 → `存档恢复等待中` gate 进出(:198)=C2-β边界 → `sending ready ack`(:203)+`jumping boot_check`(:206)=S2收尾 → 三异步cb(`任务数据/文本/合成表加载成功`,:792)=S3/S4/S9 → f91 `_root.play()` 前后=S10。BootSequencer 发同 schema → comparator diff（顺序+事件类型+关键状态，容时间戳差）。**字节门不适用**（结构变了）。

**真机必验**：(a) C2-β 注入 `_repairPending` 坏档→S2 gate 自旋→修复卡→`applyRepairResolved`(SaveManager.as:908/924) 放行；(b) 阻断 socket→10s `socket_connect_timeout`(:162)；(c) shim 缺失 fail-closed（MAIN 冻结非靠 f62）；(d) 存档三分支 `重新游戏确认`/`存档损坏`/`跳转地图("房间")`(:1448/1452/1480)；(e) **最终化2 在场**（S6 没漏 land-frame）；(f) 生命周期不抢（改动 B 后只卸载一次）；(g) 单帧 loop 回绕一轮，#include/loader 不重复执行（guard 生效）。

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
