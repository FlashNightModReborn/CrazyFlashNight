# AS2 / AVM1 BitmapData 尺寸上限与 API 黑箱实测

**文档角色**：AVM1 运行时实测档案（`flash.display.BitmapData` 的 canonical 参考）。
**最后核对代码基线**：commit `45156f419`（2026-05-20）。
**运行时**：游戏自带 projector，Flash Player `11.2.202.228`（`getVersion()` → `WIN 11,2,202,228`）。

> AS2 是冷门语言，官方语言参考停在 Flash 8 时代且不再更新，LLM 训练集中关于
> AVM1 运行时的数据稀薄且常常过时。**本文每一条都是实测结论，不是文档转述。**
> 复现方式见 §5——任何结论存疑都应重测，不要凭训练数据臆断。

---

## 1. 结论速览

- AS2 语言参考写 `BitmapData` 上限 = 2880×2880 —— 那是 Flash 8 (FP8) 时代的冻结
  文档，**不绑定本运行时**。
- 本运行时（FP11.2 projector）实测：**没有 2880 限制，没有 8191/边 限制，
  没有 16,777,215/总像素 限制。**
- 真实约束是**内存**（`width * height * 4` 字节）。
- 失败形态**不统一**：近 2 GiB 堆顶 → 不可恢复的播放器**挂死**；`≥ 2^31` 字节
  → clean `null`。**不能靠 `if(bd == null)` 兜 OOM。**

## 2. 尺寸上限实测

四轮独立交叉验证（单图扫描 / 多手段判活 / 拐点 / 方形宽高比 / dispose-realloc /
双图同时分配），全部 `0 个错误`、新鲜 trace。实测通过 = 构造非 `null`、
`width/height` 与请求一致、**远角像素 setPixel/getPixel 往返成功**（仅看
`bd.width` 不够，需写远角防静默裁剪）。

通过的样本：

| 类别 | 样本 | 说明 |
|------|------|------|
| 单维度 | 宽 50000、高 100000 | 薄条，内存极小 |
| 方形 | 4096² / 10000² / 15000² / 20000²(1.6GB) | 排除「窄条特殊优化」假说 |
| 越文档线 | 4096×4096 = 16,777,216 px | 恰过 FP10 文档的 16,777,215 上限 |
| 大图 | 10000×2000(20M px)、12000×4000 | — |
| 双图同时持有 | 20000×2000 × 2 | 模拟 `addBodyLayers` 的 layers[0]+[2] |

单图实测拐点（每像素 4 字节）：

- `268091×2000` = 2,144,728,000 B ≈ 2045 MiB → **OK**
- `268092×2000` = 2,144,736,000 B ≈ 2045 MiB → **播放器挂死**（trace 中断、无结束哨兵）

## 3. 失败形态：2^31 字节边界

表面矛盾：`268092×2000`(2045 MiB) 挂死，而**更大**的 `300000×2000`(2289 MiB)、
`30000×30000`(3433 MiB) 反而返回 clean `null`。

一致解释 —— `2^31` 字节（2,147,483,648 = 2 GiB）这条整数边界：

- `w*h*4 < 2^31`：Flash 真去 `malloc` → 堆给得起就 OK，给不起（实测堆顶
  ≈ 2,144,728,000 B）就**挂死**。
- `w*h*4 ≥ 2^31`：在 32 位有符号整数里溢出 / 被尺寸校验提前拦下 →
  **廉价 clean `null`**。

**含义**：那个 clean `null` 只是巨型请求整数溢出的副产品，**不是 Flash 优雅
处理 OOM**。真实的近顶 OOM 形态是挂死。因此构造 BitmapData 时，`null` 检查
**挡不住** OOM —— 唯一可靠手段是把尺寸压在离 2 GB 很远处。

## 4. BitmapData API 黑箱陷阱（实测）

写 BitmapData 相关测试 / 代码时极易踩，且 LLM 几乎必然臆断错：

### 4.1 `getPixel32` 返回有符号 int32
alpha=`0xFF` 的像素，`getPixel32` 读回是**负数**（`0xFF00FF00` → `-16711936`），
与正字面量比较恒不等 → 假阴性。
→ 用 `getPixel`（24 位 RGB，恒正），或对 `getPixel32` 结果 `& 0xFFFFFF` 后比较。

### 4.2 alpha=0 的 fillColor 致 setPixel/getPixel 全局失效
透明 BitmapData 若以 `fillColor` 的 alpha=0 初始化（如
`new BitmapData(w,h,true,0x00000000)`），后续所有 `setPixel` 写入后 `getPixel`
**恒返回 0**（预乘 alpha 所致）。alpha ≥ 1 即恢复正常。
→ 初始化 fillColor 的 alpha 取 ≥ 1，或用 `setPixel32` 显式写 alpha。

### 4.3 `getColorBoundsRect()` 在 AVM1 恒返回空矩形
无论 mask / color 如何设置，AVM1 的 `getColorBoundsRect` 恒返回 `(0,0,0,0)`
（与 AS3 行为不同）。不能作为 AVM1 的判活 / 内容检测手段。

## 5. 复现方法与测量边界

- **闭环**：把探针写进 `scripts/TestLoader.as`（gitignored scratch 帧脚本，
  被 TestLoader 帧 0 `#include`）→ `bash scripts/compile_test.sh` →
  读 `scripts/flashlog.txt` 的 trace。
- **判活**：构造后必须写**远角像素**并读回；只看 `bd.width/.height` 无法区分
  「真位图」与「声称大小实则裁剪/损坏」。并行用 `copyPixels` / `draw` / 多点采样
  交叉确认。
- **内存安全**：探维度上限用薄条（`h=8`，再大也才几百 KB）；逼近 GB 级时按
  从小到大排序——trace 逐行落盘，挂死前的结果仍在 flashlog 里。
- **负对照**：必须包含**注定失败**的用例（`0×0`、`-1×10`、`≥2^31` 字节），
  确认探针确实能识别失败，否则「全过」不可信。
- **无内存自省**：AVM1 没有 `System.totalMemory` 一类 API（详见
  [as2-anti-hallucination.md](../../agentsDoc/as2-anti-hallucination.md) §2「不存在的语法/API」），
  运行时读不到堆余量——所以 §3 的失败形态只能黑盒观测「挂死 / null」，
  探针也只能测「可用性」、测不了「占用」。
- ⚠ **测量边界**：以上数字在 `TestLoader`（近空 SWF，独占整个 ~2 GB 进程
  地址空间）测得。**运行中的真实游戏进程已被引擎 + 已加载资源占掉数百 MB**，
  留给 BitmapData 的实际预算远小于这些数字。要为内存做精细决策，须在真实游戏里另测。

## 6. 工程含义

- `SceneManager.addBodyLayers()` 旧代码把 `deadbody.layers` 两张 BitmapData 钳到
  `2880×1024` —— 该常量是 FP8 遗留、已无依据，且会让宽度超 2880 的地图背景 /
  尸体层在 2880 处**静默截断**。commit `45156f419` 起放宽到 `8192×4096`
  （定位为防御性护栏、非设计天花板）。决策记录见
  [地图背景层调查-2026-05.md](../../docs/地图背景层调查-2026-05.md)。
- 单张 BitmapData 不要设计在 GB 级；近 2 GB 是挂死区。
- 程序生成的超大世界图仍应走瓦片化烤图（把 `deadbody.layers` 改成 BitmapData
  瓦片网格），原因是工程稳定性，不是 2880 硬墙。
