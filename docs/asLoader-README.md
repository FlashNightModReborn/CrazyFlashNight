# asLoader 启动架构 · 导览与待测

**文档角色**：asLoader 启动子系统的**入口导览**（反直觉架构的心智地图 + 验证状态 + 测试入口）。深层细节下沉到设计 / 施工 doc，本文只回答「这是什么、为什么这么怪、验了什么、还要测什么」。
**最后核对代码基线**：commit `e7205600d0`（2026-06-17）。
**深层 doc**：[架构设计](asLoader重构-架构设计-2026-06-15.md)（为什么这么设计 + P0-P6 路线）· [BootSequencer 构建标准](asLoader-BootSequencer-构建标准-2026-06-16.md)（启动契约 + §5 边界 runbook）。

## 0. TL;DR（先读这段）

asLoader = 游戏启动器：一个 Flash CS6 影片剪辑 symbol，**承载全部 `org.flashNight.*` 类字节码 + 跑启动序列**。2026-06 把它从 **82 帧时间轴塌缩成单帧**，异步逻辑搬进 `BootSequencer` 状态机类。

⚠ **反直觉点（看到别"修"，都是有意为之）**：
1. **整个 boot 是一帧**。这帧定义一堆 `_root.__boot.fN = function(){…}` staged 函数，最后 `BootSequencer.run(this)`。没有多帧时间轴。
2. **异步 boot 逻辑住在 class**（BootSequencer），靠挂在 `_root` 上的 `onEnterFrame` tick clip 驱动——因为 asLoader 自身 boot 完会自删，tick 必须挂 `_root` 才存活。
3. **大帧被切成 chunk 函数** `fN_1..fN_k`：AVM1 单函数体 ≤64KB（`DefineFunction2.codeSize` 是 UI16），单位函数 506KB / 装备 456KB 装不进一个 function。
4. **所有 import 是一个 82 包通配并集头**（不是每文件具体 import）。

## 1. 文件地图（boot 散落 4 处）

| 件 | 路径 | 作用 |
|---|---|---|
| symbol | `scripts/asLoader/LIBRARY/asLoader.xml` | 单帧，`#include _collapsed_frame.as`；备份 `asLoader.xml.pre-collapse.bak`（回退用） |
| 帧 CDATA | `scripts/asLoaderManifest/_collapsed_frame.as` | **生成物，勿手改**：82 包并集头 + staged fN 定义 + s0..s9 编排 + `BootSequencer.run(this)` |
| 生成器 | `tools/assemble-collapsed-frame.js` | 重生成 `_collapsed_frame.as`（改 boot 同步逻辑改这个再 regen） |
| 状态机 | `scripts/类定义/org/flashNight/boot/BootSequencer.as` | S0-S10 异步序列（握手 / loader 队列 / await / handoff） |
| 主 SWF 改 A | `CRAZYFLASHER7MercenaryEmpire/DOMDocument.xml`（f33） | `_root.__boot.mainReadyToContinue = true`（替代旧 `_root.asLoader.play()`） |

> **`scripts/asLoaderManifest/frameNN.as` 的角色（塌缩后）**：① **生成器输入**（被 `assemble-collapsed-frame.js` 读取并内联进 `_collapsed_frame.as`）= STAGED 帧 `2,3,9,10,18,32,36–42` + loader-fire 帧 `53–56,58,59,62–70,74`——改 boot 同步逻辑改这些再 regen；② **其余 frameNN.as（f4/5/6/7/11/25–27/48–52/57/75/91 等）= 历史参考**，对应异步/控制逻辑已搬进 `BootSequencer.as`，改它们**不影响** boot。一次性脚本 `tools/strip-stale-frame-imports.js` 已退役（勿作常驻门、勿扩白名单）。

## 2. Boot 流（S0-S10）

S0 init → S1 syncCode（引擎+通信，建 `_root._bootstrap`）→ **S2 握手**（socket → handshake → 存档恢复 gate → 驱动主 SWF playhead）→ S3/S4 任务数据/文本 await → S5 parse → **S6 syncSys**（建 loader 队列 → 逐 tick 抽干，含异步 preload 等待门）→ S7 syncLogic（玩家模板/装备/UI… 大帧 chunk）→ S8 fanout（fire-and-forget）→ S9 crafting → **S10 handoff**（`_root.play()` 必先于自删，顺序铁律）。

## 3. 为什么每个怪点都必须在（别"优化"掉）

- **单帧**：用户拍板的 C2-B（symbol 真只剩 1 帧脚本）。
- **chunk**：64KB 函数体硬限；`tools/swf-function-sizes.js` 是 codeSize 门（无需真机即拦溢出）。
- **tick 挂 `_root`**：asLoader handoff 自删后回调仍要可达。
- **S6 异步等待门**：塌缩把多帧压成紧 tick，破坏了原版 preload→consume 依赖的隐式帧间隔时序（曾致佣兵库只载 1 条）。
- **function form（非 typed class）**：`_root.X = function` 闭包能捕获时间轴 scope（裸 `打印加载内容` 可解析）；typed class 静态方法不捕获 → 故 boot 代码用 function form，typed class 化作独立长期 track。

## 4. 塌缩踩过的坑（认症状用，详见构建标准 §0）

1. **chunk 帧调度必须调全部 chunk 名**，不能调 base `fN`（chunk 帧无 base）→ 否则大帧静默不跑（入 lobby 但角色瘫痪 / 无刘海屏）。
2. **eager 自单例 `static var instance = new Self()` 构造里跨类调用** → 依赖类未注册时 **AVM1 对「未定义类.方法()」静默返回 undefined（不抛错）** → 死回调（刀光不褪 bug）。**通用律：自单例构造勿跨类调用**。
3. **异步 preload→consume 靠帧间隔**，塌缩压紧 tick 须加显式等待门（见 S6）。
4. **大小写 typo 被并集头更严格类型解析暴露**（多帧时该上下文未 typed-resolve 不报，塌缩后报编译错）。

## 5. 验证状态（2026-06-17）

| 项 | 状态 |
|---|---|
| Happy-path 真机 boot | ✅ 通过（引擎/通信/玩家/装备/战斗/UI/关卡/佣兵满编 204/刀光褪色/存档 loadAll OK） |
| 静态门 codeSize <64K | ✅ 门过（`--max 60000` exit 0），**但最大 chunk = 58064 B**（次大 53240 B，均在 `DoAction[sprite=1 frame=0]` 即 boot 帧），距 UI16 硬限 65535 仅 ~7.5KB、距门 ~1.9KB，3 函数标 ⚠接近。⚠ 余量薄：最大者极可能是**不可再切的单文件 chunk**（如玩家模板迁移），该源文件再长 ~7KB 即静默溢出。**勿信旧「29K」表述** |
| 静态门 single-ownership | ✅ main=0 / loader=572 / 交集=0 |
| 编译 0 错 / BOM / whitespace / doc-gov | ✅ |
| **trace 等价门（happy-path）** | ✅ 2026-06-17 重抓塌缩 boot golden（`tools/baselines/boot-golden.log`，单次完整 boot S2→S10），`trace-diff diff` [OK]，10 事件全含 `CRAFTING_OK`/`HANDOFF_PLAY`（真机实测 SWF 870267 发出，非仅单测）。旧 golden 仅 S2–S4 已替换 |
| **§5 七边界** | ✅ 基本完成（2026-06-17 真机）：(c) shim 缺失双层 fail-closed、(a) 坏档 C2-β 修复 gate、(d) 正常/新档(decision=empty)/坏档(随 a)、握手失败 fail-closed(测试churn顺带实证)、(e)(f) 随 happy-path boot 覆盖。(b) socket 超时=纯看屏(独立开 SWF 已见卡死协议帧)+L1 逻辑已覆盖。详见构建标准 §5.3 |

## 6. 怎么测 / 怎么改

- **改 boot 同步逻辑**：改源 `.as` → `node tools/assemble-collapsed-frame.js` regen → CS6 **重开** asLoader FLA（时间轴结构改必须 reopen，**关闭选「不保存」** 否则内存旧版 clobber 盘）→ `powershell -File scripts/compile_test.ps1 -VerifySwf scripts/asLoader.swf -TimeoutSeconds 180`。
- **改 BootSequencer**：直接改类 → 重编（同上；publish 模式无 trace，看 `0 错误` + SWF 刷新）。
- **trace 门**：`node tools/trace-diff.js diff <golden> <new>`（事件序列 LCS 等价，容时间戳/批处理）。
- **边界**：构建标准 doc **§5.1** 七边界表（触发 → 期望 `[BootstrapAS]` 信号 → 判据）。
- **回退**：`git checkout` + 用 `asLoader.xml.pre-collapse.bak` 还原 symbol。

---
**新接手测试者**：读完 §0 + §5 即可开测；要改 boot 结构再读 §1-§4 + 两个深层 doc。**改 `.as` 必带 UTF-8 BOM**（见 [as2-anti-hallucination.md](../agentsDoc/as2-anti-hallucination.md)）。
