# ActionScript 2 标志位组合算法性能微基准实验报告

**报告日期：2025-08-08** · **平台：AS2 / AVM1** 

---

## 1. 摘要（Executive Summary）

对 **7 种**常见“多布尔→位标志”组合写法进行了最高 **N=1e8** 次迭代的微基准。
**结论要点：**

* **最优梯队**：`(cond ? FLAG : 0)` 与 `if (cond)` 的直接计算（用 `+` 或 `|` 汇总）**性能几乎相同**（差距 <\~2%）。
* **LUT 查表**：无稳定优势；索引构造 + 数组寻址的成本抵消了省下的算术。
* **NegMask（`-Number(cond) & FLAG`）**：显著最慢（\~+25%），热路径中的显式类型转换开销过大。
  **建议**：保留项目当前的 `?: |` 写法即可；若真要抠 <1% 的边际，可考虑 `?: +`（前提：FLAG 互斥且为 2 的幂）。

---

## 2. 背景与目标

`BulletTypesetter.calculateFlags` 在游戏运行中是高频热路径：将一组布尔属性（如 `isMelee`、`isPierce` 等）组合为单个 **Number 型位标志**，供后续快速分流。
在已将 `FLAG_*` **下沉为局部常量**（消除属性查找瓶颈）后，评估是否存在**更快**的组合方式，并沉淀可复用的优化准则。

**目标：**

1. 定量比较 7 种实现的耗时差异；
2. 识别 AVM1 下稳定且可维护的“最优实践”；
3. 给出工程可落地的优化建议。

---

## 3. 实验设计

### 3.1 环境

* **语言 / VM**：ActionScript 2.0 / AVM1（解释执行，无现代 JIT）。
* **计时**：`getTimer()`（毫秒级）。
* **防 DCE**：使用 `acc` 聚合结果，避免被优化掉。

### 3.2 实现（自变量）

1. `calc_or`：三元 + 位或 `|`（**项目原始**）
2. `calc_if_or`：`if (c) flags |= FLAG;`
3. `calc_if_add`：`if (c) flags += FLAG;`
4. `calc_ternary_add`：三元 + 加法 `+`
5. `calc_negmask_or`：`(-Number(c) & FLAG) | ...`
6. `calc_negmask_add`：`(-Number(c) & FLAG) + ...`
7. `calc_lut`：LUT\[0..255] 查表（顶层一次性构建）

> **前提**：所有 `FLAG_*` 均为**互斥的 2 的幂**（如 1、2、4、…、128），确保 `+` 与 `|` 结果等价。

### 3.3 控制变量

* **迭代次数**：统一 **N = 100,000,000**（同时在 **N=1,000,000** 处验证趋势一致）。
* **输入序列**：用 `(j & mask) == 0` 生成周期性布尔，**各实现相同输入**。
* **预热**：先跑 **200,000** 次抹平冷启动影响。
* **LUT 构建**：在**顶层**一次性构建，避免污染热路径。

### 3.4 流程

预热 → 依序 `run(name, fn)` → 记录耗时（ms）→ 输出日志。
为减少顺序偏差，建议调换顺序多轮测试并取中位数（见 §7）。

---

## 4. 结果与分析

### 4.1 原始数据（N = 1e8）

| 实现                  | 逻辑                      |              耗时 (ms) | 相对性能（最快=100%） |         |       |
| ------------------- | ----------------------- | -------------------: | ------------: | ------- | ----- |
| **Ternary + (add)** | `(c?FLAG:0) + ...`      |          **281,584** |    **100.0%** |         |       |
| OR (ternary \`      | \`)                     |         \`(c?FLAG:0) |         ...\` | 282,351 | 99.7% |
| LUT\[256] index     | 预构 LUT 后索引              |              282,746 |         99.6% |         |       |
| IF \`               | =\`                     |        \`if(c) flags |      = FLAG\` | 286,155 | 98.4% |
| IF `+=`             | `if(c) flags += FLAG`   |              286,770 |         98.2% |         |       |
| NegMask `& +`       | `(-Number(c)&FLAG)+...` |              353,940 |         79.6% |         |       |
| NegMask \`&         | \`                      | \`(-Number(c)\&FLAG) |         ...\` | 354,242 | 79.5% |

> 在 **N=1e6** 的小规模测试中，排序一致，差值更小，说明结论**稳定**。

### 4.2 关键解读

* **最优梯队打平**：`?: +`、`?: |`、`if` 系列差距 <\~2%。`?: +` 在本机略胜 \~0.27%，属于噪声级。
* **LUT 不占优**：索引构造（8 组 0/1 与移位/或）本身与直接计算同量级，再加上数组寻址，抵消潜在收益。
* **NegMask 不香**：所谓“无分支”要靠 `Number(bool)` 显式转换，成本在 AVM1 很高；8 次/轮 × 1e8 轮，累计开销极大。
* **`+` vs `|`**：在幂值互斥前提下数学等价。`|` 走 32 位整形窄化路径，`+` 多为浮点直路；两者在本场景差距极小。

---

## 5. 结论与建议

### 5.1 结论

* 项目现行 **`(cond ? FLAG : 0) | ...`** 已处于**可观测上限**，**无需改**。
* 若要抠极致且能接受等价假设（FLAG 互斥幂值），可选 **`(cond ? FLAG : 0) + ...`**；收益约 **0.3%**。

### 5.2 更值当的工程优化

1. **减少计算次数（胜于改变写法）**

   * 将 flags 与\*\*“规范化后的类型键/基础素材名”**绑定做**前置缓存\*\*，热路径仅做 O(1) 取用。
   * **热路径禁**字符串规范化（如 `toLowerCase`）；只在数据注入阶段做。

2. **常量就地 + 幂值约束**

   * 继续用 `#include`/局部承接 `FLAG_*`，避免属性查找。
   * 确保 `FLAG_*` 为 **2 的幂**，不要触碰 `2^31` 临界（防止符号窄化问题）。

3. **可维护优先**

   * 默认保留 `?: |`；若团队偏可读，可用

     ```as
     var flags:Number=0; if(c) flags |= FLAG; // 约 +3% 开销
     ```
   * LUT、NegMask 不再考虑。

---

## 6. 适用边界与有效性威胁

* **平台差异**：不同 Player/Projector 版本、浏览器容器可能引入细微偏差。
* **机器状态**：温度/电源策略/后台负载影响抖动；建议“高性能”电源模式并清理后台。
* **顺序效应**：固定顺序可能有偏置；建议**打乱顺序多轮**，取中位数/平均。
* **数据分布**：实验使用周期性布尔；即便线上布尔偏斜，第一梯队打平的事实**大概率不变**，可加一轮“实战重放”验证。

---

## 7. 复现实验步骤（推荐）

1. 设定 **N=1e6 → 5e6 → 1e8** 分级跑，观察排序是否一致。
2. 打乱各实现的执行顺序，跑 **3–5 轮**，统计**中位数/平均**与方差。
3. 在目标发行形态（**投影器 / 浏览器容器**）各跑一轮，确认一致性。
4. 线上启动阶段可跑一个 **N=2e6** 的快基准做“回归嗅探”。

---

## 8. 代码与集成

### 8.1 推荐实现（性能/可读性平衡）

```actionscript
// 假设 FLAG_* 已在函数局部承接为 Number 且为 2 的幂
return ((isMelee        ? FLAG_MELEE        : 0)
      | (isChain        ? FLAG_CHAIN        : 0)
      | (isPierce       ? FLAG_PIERCE       : 0)
      | (isTransparency ? FLAG_TRANSPARENCY : 0)
      | (isGrenade      ? FLAG_GRENADE      : 0)
      | (isExplosive    ? FLAG_EXPLOSIVE    : 0)
      | (isNormal       ? FLAG_NORMAL       : 0)
      | (isVertical     ? FLAG_VERTICAL     : 0));
```

### 8.2 宏展开可切换（便于 A/B 回归）

```actionscript
// FlagCompose_or.asinc
( (isMelee ? FLAG_MELEE : 0)
| (isChain ? FLAG_CHAIN : 0)
| (isPierce ? FLAG_PIERCE : 0)
| (isTransparency ? FLAG_TRANSPARENCY : 0)
| (isGrenade ? FLAG_GRENADE : 0)
| (isExplosive ? FLAG_EXPLOSIVE : 0)
| (isNormal ? FLAG_NORMAL : 0)
| (isVertical ? FLAG_VERTICAL : 0) )

// FlagCompose_add.asinc
( (isMelee ? FLAG_MELEE : 0)
+ (isChain ? FLAG_CHAIN : 0)
+ (isPierce ? FLAG_PIERCE : 0)
+ (isTransparency ? FLAG_TRANSPARENCY : 0)
+ (isGrenade ? FLAG_GRENADE : 0)
+ (isExplosive ? FLAG_EXPLOSIVE : 0)
+ (isNormal ? FLAG_NORMAL : 0)
+ (isVertical ? FLAG_VERTICAL : 0) )
```

在 `calculateFlags` 内仅保留一个 `#include` 生效，另一行注释即可。

---

## 9. 性能准则备忘（Cheat Sheet）

* **先杀属性查找**（把常量下沉为局部），收益最大。
* **热路径禁类型转换**（`Number()`/`String()` 等）。
* **缓存 > 写法**：减少**计算次数**通常比改变**计算方式**更值当。
* **FLAG 设计**：幂值、互斥，避免符号窄化边界。
* **基准可重复**：固定输入、放大 N、打乱顺序、多轮取中位数。

---

### 附：基准脚本说明

```actionscript

// ===============================================
// Flags 组合微基准（AS2 / AVM1）
// - 单帧运行，最后一次性输出结果
// - 复制到一段脚本即可跑
// ===============================================

// 可调规模：建议先 1e6~5e6 观察趋势，再放大
var N:Number = 100000000;

// ———————————— 日志包装 ————————————
function log(msg:String):Void {
  if (_root.服务器 && _root.服务器.发布服务器消息) {
    _root.服务器.发布服务器消息(msg);
  } else {
    trace(msg);
  }
}

var i:Number, acc:Number = 0;

// ———————————— 基本旗标（2 的幂） ————————————
var FLAG_MELEE:Number=1, FLAG_CHAIN:Number=2, FLAG_PIERCE:Number=4, FLAG_TRANSPARENCY:Number=8;
var FLAG_GRENADE:Number=16, FLAG_EXPLOSIVE:Number=32, FLAG_NORMAL:Number=64, FLAG_VERTICAL:Number=128;

// ———————————— 多种实现 ————————————
function calc_or(isMelee, isChain, isPierce, isTransparency, isGrenade, isExplosive, isNormal, isVertical):Number {
  return ((isMelee?FLAG_MELEE:0)|(isChain?FLAG_CHAIN:0)|(isPierce?FLAG_PIERCE:0)|(isTransparency?FLAG_TRANSPARENCY:0)|
          (isGrenade?FLAG_GRENADE:0)|(isExplosive?FLAG_EXPLOSIVE:0)|(isNormal?FLAG_NORMAL:0)|(isVertical?FLAG_VERTICAL:0));
}

function calc_if_or(isMelee, isChain, isPierce, isTransparency, isGrenade, isExplosive, isNormal, isVertical):Number {
  var flags:Number = 0;
  if (isMelee)        flags |= FLAG_MELEE;
  if (isChain)        flags |= FLAG_CHAIN;
  if (isPierce)       flags |= FLAG_PIERCE;
  if (isTransparency) flags |= FLAG_TRANSPARENCY;
  if (isGrenade)      flags |= FLAG_GRENADE;
  if (isExplosive)    flags |= FLAG_EXPLOSIVE;
  if (isNormal)       flags |= FLAG_NORMAL;
  if (isVertical)     flags |= FLAG_VERTICAL;
  return flags;
}

function calc_if_add(isMelee, isChain, isPierce, isTransparency, isGrenade, isExplosive, isNormal, isVertical):Number {
  var flags:Number = 0;
  if (isMelee)        flags += FLAG_MELEE;
  if (isChain)        flags += FLAG_CHAIN;
  if (isPierce)       flags += FLAG_PIERCE;
  if (isTransparency) flags += FLAG_TRANSPARENCY;
  if (isGrenade)      flags += FLAG_GRENADE;
  if (isExplosive)    flags += FLAG_EXPLOSIVE;
  if (isNormal)       flags += FLAG_NORMAL;
  if (isVertical)     flags += FLAG_VERTICAL;
  return flags;
}

function calc_ternary_add(isMelee, isChain, isPierce, isTransparency, isGrenade, isExplosive, isNormal, isVertical):Number {
  return ((isMelee ? FLAG_MELEE : 0)
        + (isChain ? FLAG_CHAIN : 0)
        + (isPierce ? FLAG_PIERCE : 0)
        + (isTransparency ? FLAG_TRANSPARENCY : 0)
        + (isGrenade ? FLAG_GRENADE : 0)
        + (isExplosive ? FLAG_EXPLOSIVE : 0)
        + (isNormal ? FLAG_NORMAL : 0)
        + (isVertical ? FLAG_VERTICAL : 0));
}

function calc_negmask_or(isMelee, isChain, isPierce, isTransparency, isGrenade, isExplosive, isNormal, isVertical):Number {
  // -Number(true) => -1，-1 & FLAG => FLAG；false => 0
  return (((-Number(isMelee))       & FLAG_MELEE)
        |((-Number(isChain))        & FLAG_CHAIN)
        |((-Number(isPierce))       & FLAG_PIERCE)
        |((-Number(isTransparency)) & FLAG_TRANSPARENCY)
        |((-Number(isGrenade))      & FLAG_GRENADE)
        |((-Number(isExplosive))    & FLAG_EXPLOSIVE)
        |((-Number(isNormal))       & FLAG_NORMAL)
        |((-Number(isVertical))     & FLAG_VERTICAL));
}

function calc_negmask_add(isMelee, isChain, isPierce, isTransparency, isGrenade, isExplosive, isNormal, isVertical):Number {
  return (((-Number(isMelee))       & FLAG_MELEE)
        +((-Number(isChain))        & FLAG_CHAIN)
        +((-Number(isPierce))       & FLAG_PIERCE)
        +((-Number(isTransparency)) & FLAG_TRANSPARENCY)
        +((-Number(isGrenade))      & FLAG_GRENADE)
        +((-Number(isExplosive))    & FLAG_EXPLOSIVE)
        +((-Number(isNormal))       & FLAG_NORMAL)
        +((-Number(isVertical))     & FLAG_VERTICAL));
}

// —— 查表法：LUT[0..255] 直接给最终 flags ——
// 顶层一次性构建（避免热路径）
var LUT:Array = new Array(256);
function buildLUT():Void {
  var k:Number = 0;
  while (k < 256) {
    var f:Number = 0;
    if ((k & 1)   != 0) f += FLAG_MELEE;
    if ((k & 2)   != 0) f += FLAG_CHAIN;
    if ((k & 4)   != 0) f += FLAG_PIERCE;
    if ((k & 8)   != 0) f += FLAG_TRANSPARENCY;
    if ((k & 16)  != 0) f += FLAG_GRENADE;
    if ((k & 32)  != 0) f += FLAG_EXPLOSIVE;
    if ((k & 64)  != 0) f += FLAG_NORMAL;
    if ((k & 128) != 0) f += FLAG_VERTICAL;
    LUT[k] = f;
    k++;
  }
}
buildLUT();

function calc_lut(isMelee, isChain, isPierce, isTransparency, isGrenade, isExplosive, isNormal, isVertical):Number {
  // 把 8 个布尔压成 8 位索引（显式 0/1，避免隐式转换歧义）
  var idx:Number =
      ((isMelee?1:0)        << 0) |
      ((isChain?1:0)        << 1) |
      ((isPierce?1:0)       << 2) |
      ((isTransparency?1:0) << 3) |
      ((isGrenade?1:0)      << 4) |
      ((isExplosive?1:0)    << 5) |
      ((isNormal?1:0)       << 6) |
      ((isVertical?1:0)     << 7);
  return LUT[idx];
}

// ———————————— warm-up（抹平冷启动） ————————————
for (i=0;i<200000;i++) acc = calc_or(true,false,true,false,true,false,true,false);

// ———————————— 测试工具：统一生成相同布尔序列 ————————————
function run(name:String, fn:Function):Number {
  var t0:Number = getTimer();
  var j:Number;
  for (j=0;j<N;j++) {
    // 固定序列：8 位滚动
    var b0:Boolean = ((j&1)==0);
    var b1:Boolean = ((j&2)==0);
    var b2:Boolean = ((j&4)==0);
    var b3:Boolean = ((j&8)==0);
    var b4:Boolean = ((j&16)==0);
    var b5:Boolean = ((j&32)==0);
    var b6:Boolean = ((j&64)==0);
    var b7:Boolean = ((j&128)==0);
    acc += fn(b0,b1,b2,b3,b4,b5,b6,b7);
  }
  var dt:Number = getTimer() - t0;
  log("[基准] " + name + " = " + dt + " ms");
  return dt;
}

// ———————————— 开始测试 ————————————
var t_or:Number        = run("OR(ternary |)",       calc_or);
var t_if_or:Number     = run("IF |= (bitwise)",     calc_if_or);
var t_if_add:Number    = run("IF += (add)",         calc_if_add);
var t_t_add:Number     = run("Ternary + (add)",     calc_ternary_add);
var t_nm_or:Number     = run("NegMask & |",         calc_negmask_or);
var t_nm_add:Number    = run("NegMask & +",         calc_negmask_add);
var t_lut:Number       = run("LUT[256] index",      calc_lut);

log("[基准] 累计acc=" + acc);


```

```log

[基准] OR(ternary |) = 282351 ms
[基准] IF |= (bitwise) = 286155 ms
[基准] IF += (add) = 286770 ms
[基准] Ternary + (add) = 281584 ms
[基准] NegMask & | = 354242 ms
[基准] NegMask & + = 353940 ms
[基准] LUT[256] index = 282746 ms
[基准] 累计acc=89250000085

```