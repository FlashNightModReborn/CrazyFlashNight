# asLoader 启动架构 · 导览与待测

**文档角色**：asLoader 启动子系统的**入口导览**（反直觉架构的心智地图 + 验证状态 + 测试入口）。深层细节下沉到设计 / 施工 doc，本文只回答「这是什么、为什么这么怪、验了什么、还要测什么」。
**最后核对代码基线**：commit `b852c0eba1`（2026-06-17）。
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
| 静态门 codeSize <64K | ✅ 最大函数体 29K |
| 静态门 single-ownership | ✅ main=0 / loader=572 / 交集=0 |
| 编译 0 错 / BOM / whitespace / doc-gov | ✅ |
| **trace 等价门末段** | ⏳ 需一次普通 boot 捕 `HANDSHAKE_RESULT` 跑 `trace-diff.js diff` |
| **§5 七边界** | ⏳ 需手动注入故障（坏档/socket 超时/shim 缺失/存档三分支/最终化2/生命周期/单帧 loop） |

## 6. 怎么测 / 怎么改

- **改 boot 同步逻辑**：改源 `.as` → `node tools/assemble-collapsed-frame.js` regen → CS6 **重开** asLoader FLA（时间轴结构改必须 reopen，**关闭选「不保存」** 否则内存旧版 clobber 盘）→ `powershell -File scripts/compile_test.ps1 -VerifySwf scripts/asLoader.swf -TimeoutSeconds 180`。
- **改 BootSequencer**：直接改类 → 重编（同上；publish 模式无 trace，看 `0 错误` + SWF 刷新）。
- **trace 门**：`node tools/trace-diff.js diff <golden> <new>`（事件序列 LCS 等价，容时间戳/批处理）。
- **边界**：构建标准 doc **§5.1** 七边界表（触发 → 期望 `[BootstrapAS]` 信号 → 判据）。
- **回退**：`git checkout` + 用 `asLoader.xml.pre-collapse.bak` 还原 symbol。

---
**新接手测试者**：读完 §0 + §5 即可开测；要改 boot 结构再读 §1-§4 + 两个深层 doc。**改 `.as` 必带 UTF-8 BOM**（见 [as2-anti-hallucination.md](../agentsDoc/as2-anti-hallucination.md)）。
