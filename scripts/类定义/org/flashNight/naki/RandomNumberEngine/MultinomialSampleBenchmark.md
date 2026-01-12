# MultinomialSample 阈值性能测试

## 测试目的

确定 `multinomialSample3` 和 `multinomialSample4` 中小 n 循环路径与大 n 高斯近似路径的最佳切换阈值。

## 理论分析

### 成本模型

**小 n 路径（直接循环 + 二分判定）**：
- 每次迭代：1 次 `nextFloat()` + 2 次比较
- 预估成本：~2 单位/次
- 总成本：~2n

**大 n 路径（独立高斯采样 + 归一化）**：
- 方差计算：3 次乘法
- 条件 sqrt：0-3 次（取决于方差是否 > 0.25）
- Irwin-Hall 采样：0-3 组（每组 3 次 nextFloat）
- 归一化修正：加法/位运算
- 预估成本：10-50 单位（取决于概率分布）

### 理论平衡点

- 最坏情况（3×sqrt+3×IH3）：n* ≈ 26
- 典型情况（2×sqrt+2×IH3）：n* ≈ 18
- 最好情况（无波动）：n* ≈ 5

## 测试脚本 1：基准性能对比

```actionscript
import org.flashNight.naki.RandomNumberEngine.*;

// 获取随机数引擎实例
var RNG:LinearCongruentialEngine = LinearCongruentialEngine.getInstance();

// 测试参数
var ITERATIONS:Number = 10000;  // 每个 n 值的测试次数
var outCounts:Array = [0, 0, 0, 0];

// 典型概率分布（基于游戏实际数据）
// dodgeProb ≈ 0.15, bounceProb ≈ 0.6, instantProb ≈ 0.05
var pMiss:Number = 0.85 * 0.15;           // ≈ 0.1275
var pBounce:Number = 0.85 * 0.85 * 0.6;   // ≈ 0.4335
var pInstant:Number = 0.15;               // 0.15

trace("====== multinomialSample4 性能测试 ======");
trace("概率分布: pMiss=" + pMiss + ", pBounce=" + pBounce + ", pInstant=" + pInstant);
trace("每个 n 值测试 " + ITERATIONS + " 次");
trace("");

// 测试不同的 n 值
var testNValues:Array = [3, 5, 8, 10, 12, 15, 18, 20, 24, 30, 40, 50, 64, 80, 100];

for (var idx:Number = 0; idx < testNValues.length; idx++) {
    var n:Number = testNValues[idx];

    var startTime:Number = getTimer();
    for (var i:Number = 0; i < ITERATIONS; i++) {
        RNG.multinomialSample4(n, pMiss, pBounce, pInstant, outCounts);
    }
    var endTime:Number = getTimer();
    var elapsed:Number = endTime - startTime;
    var avgTime:Number = elapsed / ITERATIONS;

    trace("n=" + n + " | 总耗时: " + elapsed + "ms | 平均: " + avgTime.toFixed(4) + "ms/次");
}
```

## 测试脚本 2：强制路径对比

此脚本通过修改阈值来强制使用不同路径，直接对比两种实现的性能。

```actionscript
import org.flashNight.naki.RandomNumberEngine.*;

var RNG:LinearCongruentialEngine = LinearCongruentialEngine.getInstance();

var ITERATIONS:Number = 10000;
var outCounts:Array = [0, 0, 0, 0];

// 典型概率分布
var pMiss:Number = 0.1275;
var pBounce:Number = 0.4335;
var pInstant:Number = 0.15;

trace("====== 强制路径对比测试 ======");
trace("");

// 内联测试函数：小 n 循环路径
function testLoopPath(n:Number, pMiss:Number, pBounce:Number, pInstant:Number, outCounts:Array):Void {
    var t1:Number = pInstant;
    var tLow:Number = t1 + pMiss;
    var tMid:Number = tLow + pBounce;

    var instantCount:Number = 0;
    var missCount:Number = 0;
    var bounceCount:Number = 0;
    var penCount:Number = 0;

    var i:Number = 0;
    do {
        var r:Number = RNG.nextFloat();
        if (r < tLow) {
            if (r < t1) instantCount++; else missCount++;
        } else {
            if (r < tMid) bounceCount++; else penCount++;
        }
    } while (++i < n);

    outCounts[0] = missCount;
    outCounts[1] = bounceCount;
    outCounts[2] = penCount;
    outCounts[3] = instantCount;
}

// 内联测试函数：大 n 高斯路径
function testGaussianPath(n:Number, pMiss:Number, pBounce:Number, pInstant:Number, outCounts:Array):Void {
    var pPen:Number = 1 - pInstant - pMiss - pBounce;
    if (pPen < 0) pPen = 0;

    var varInst:Number = n * pInstant * (1 - pInstant);
    var varMiss:Number = n * pMiss * (1 - pMiss);
    var varBounce:Number = n * pBounce * (1 - pBounce);

    var instantCount:Number;
    var missCount:Number;
    var bounceCount:Number;
    var penCount:Number;

    if (varInst > 0.25) {
        instantCount = (n * pInstant + Math.sqrt(varInst) * ((RNG.nextFloat() + RNG.nextFloat() + RNG.nextFloat()) * 2 - 3) + 0.5) >> 0;
    } else {
        instantCount = (n * pInstant + 0.5) >> 0;
    }

    if (varMiss > 0.25) {
        missCount = (n * pMiss + Math.sqrt(varMiss) * ((RNG.nextFloat() + RNG.nextFloat() + RNG.nextFloat()) * 2 - 3) + 0.5) >> 0;
    } else {
        missCount = (n * pMiss + 0.5) >> 0;
    }

    if (varBounce > 0.25) {
        bounceCount = (n * pBounce + Math.sqrt(varBounce) * ((RNG.nextFloat() + RNG.nextFloat() + RNG.nextFloat()) * 2 - 3) + 0.5) >> 0;
    } else {
        bounceCount = (n * pBounce + 0.5) >> 0;
    }

    if (instantCount < 0) instantCount = 0;
    if (missCount < 0) missCount = 0;
    if (bounceCount < 0) bounceCount = 0;

    var sum:Number = instantCount + missCount + bounceCount;
    if (sum > n) {
        var scale:Number = n / sum;
        instantCount = (instantCount * scale) >> 0;
        missCount = (missCount * scale) >> 0;
        bounceCount = (bounceCount * scale) >> 0;
        penCount = n - instantCount - missCount - bounceCount;
    } else {
        penCount = n - sum;
    }
    if (penCount < 0) penCount = 0;

    outCounts[0] = missCount;
    outCounts[1] = bounceCount;
    outCounts[2] = penCount;
    outCounts[3] = instantCount;
}

// 测试关键 n 值范围
var testNValues:Array = [10, 12, 15, 18, 20, 22, 24, 26, 28, 30, 35, 40];

for (var idx:Number = 0; idx < testNValues.length; idx++) {
    var n:Number = testNValues[idx];

    // 测试循环路径
    var startLoop:Number = getTimer();
    for (var i:Number = 0; i < ITERATIONS; i++) {
        testLoopPath(n, pMiss, pBounce, pInstant, outCounts);
    }
    var loopTime:Number = getTimer() - startLoop;

    // 测试高斯路径
    var startGauss:Number = getTimer();
    for (var j:Number = 0; j < ITERATIONS; j++) {
        testGaussianPath(n, pMiss, pBounce, pInstant, outCounts);
    }
    var gaussTime:Number = getTimer() - startGauss;

    var diff:Number = loopTime - gaussTime;
    var winner:String = (diff > 0) ? "Gaussian" : "Loop";

    trace("n=" + n + " | Loop: " + loopTime + "ms | Gaussian: " + gaussTime + "ms | 差值: " + diff + "ms | 优胜: " + winner);
}
```

## 测试脚本 3：不同概率分布对比

测试不同概率分布下的最佳阈值（因为高斯路径性能受 var > 0.25 条件影响）。

```actionscript
import org.flashNight.naki.RandomNumberEngine.*;

var RNG:LinearCongruentialEngine = LinearCongruentialEngine.getInstance();

var ITERATIONS:Number = 5000;
var outCounts:Array = [0, 0, 0, 0];

trace("====== 不同概率分布测试 ======");
trace("");

// 定义多种概率分布场景
var scenarios:Array = [
    {name: "典型分布", pMiss: 0.1275, pBounce: 0.4335, pInstant: 0.15},
    {name: "高闪避", pMiss: 0.35, pBounce: 0.30, pInstant: 0.10},
    {name: "低闪避", pMiss: 0.05, pBounce: 0.50, pInstant: 0.05},
    {name: "高懒闪避", pMiss: 0.10, pBounce: 0.35, pInstant: 0.35},
    {name: "集中分布", pMiss: 0.02, pBounce: 0.90, pInstant: 0.02}
];

var testNValues:Array = [15, 18, 20, 24, 30];

for (var s:Number = 0; s < scenarios.length; s++) {
    var scenario:Object = scenarios[s];
    trace("--- " + scenario.name + " ---");
    trace("pMiss=" + scenario.pMiss + ", pBounce=" + scenario.pBounce + ", pInstant=" + scenario.pInstant);

    for (var idx:Number = 0; idx < testNValues.length; idx++) {
        var n:Number = testNValues[idx];

        var startTime:Number = getTimer();
        for (var i:Number = 0; i < ITERATIONS; i++) {
            RNG.multinomialSample4(n, scenario.pMiss, scenario.pBounce, scenario.pInstant, outCounts);
        }
        var elapsed:Number = getTimer() - startTime;

        trace("  n=" + n + " | " + elapsed + "ms");
    }
    trace("");
}
```

## 测试脚本 4：精确阈值搜索

二分搜索找到精确的平衡点。

```actionscript

import org.flashNight.naki.RandomNumberEngine.*;

var RNG:LinearCongruentialEngine = LinearCongruentialEngine.getInstance();

var ITERATIONS:Number = 8000;
var outCounts:Array = [0, 0, 0, 0];

// 典型概率分布
var pMiss:Number = 0.1275;
var pBounce:Number = 0.4335;
var pInstant:Number = 0.15;

trace("====== 精确阈值搜索 ======");
trace("概率分布: pMiss=" + pMiss + ", pBounce=" + pBounce + ", pInstant=" + pInstant);
trace("");

// 内联循环路径
function loopPath(n:Number):Void {
    var t1:Number = pInstant;
    var tLow:Number = t1 + pMiss;
    var tMid:Number = tLow + pBounce;

    var instantCount:Number = 0, missCount:Number = 0, bounceCount:Number = 0, penCount:Number = 0;
    var i:Number = 0;
    do {
        var r:Number = RNG.nextFloat();
        if (r < tLow) {
            if (r < t1) instantCount++; else missCount++;
        } else {
            if (r < tMid) bounceCount++; else penCount++;
        }
    } while (++i < n);
    outCounts[0] = missCount; outCounts[1] = bounceCount; outCounts[2] = penCount; outCounts[3] = instantCount;
}

// 内联高斯路径
function gaussPath(n:Number):Void {
    var pPen:Number = 1 - pInstant - pMiss - pBounce;
    if (pPen < 0) pPen = 0;

    var varInst:Number = n * pInstant * (1 - pInstant);
    var varMiss:Number = n * pMiss * (1 - pMiss);
    var varBounce:Number = n * pBounce * (1 - pBounce);

    var instantCount:Number, missCount:Number, bounceCount:Number, penCount:Number;

    instantCount = (varInst > 0.25) ? ((n * pInstant + Math.sqrt(varInst) * ((RNG.nextFloat() + RNG.nextFloat() + RNG.nextFloat()) * 2 - 3) + 0.5) >> 0) : ((n * pInstant + 0.5) >> 0);
    missCount = (varMiss > 0.25) ? ((n * pMiss + Math.sqrt(varMiss) * ((RNG.nextFloat() + RNG.nextFloat() + RNG.nextFloat()) * 2 - 3) + 0.5) >> 0) : ((n * pMiss + 0.5) >> 0);
    bounceCount = (varBounce > 0.25) ? ((n * pBounce + Math.sqrt(varBounce) * ((RNG.nextFloat() + RNG.nextFloat() + RNG.nextFloat()) * 2 - 3) + 0.5) >> 0) : ((n * pBounce + 0.5) >> 0);

    if (instantCount < 0) instantCount = 0;
    if (missCount < 0) missCount = 0;
    if (bounceCount < 0) bounceCount = 0;

    var sum:Number = instantCount + missCount + bounceCount;
    if (sum > n) {
        var scale:Number = n / sum;
        instantCount = (instantCount * scale) >> 0;
        missCount = (missCount * scale) >> 0;
        bounceCount = (bounceCount * scale) >> 0;
        penCount = n - instantCount - missCount - bounceCount;
    } else {
        penCount = n - sum;
    }
    if (penCount < 0) penCount = 0;

    outCounts[0] = missCount; outCounts[1] = bounceCount; outCounts[2] = penCount; outCounts[3] = instantCount;
}

// 细粒度测试
for (var n:Number = 1; n <= 40; n += 2) {
    var startLoop:Number = getTimer();
    for (var i:Number = 0; i < ITERATIONS; i++) {
        loopPath(n);
    }
    var loopTime:Number = getTimer() - startLoop;

    var startGauss:Number = getTimer();
    for (var j:Number = 0; j < ITERATIONS; j++) {
        gaussPath(n);
    }
    var gaussTime:Number = getTimer() - startGauss;

    var ratio:Number = loopTime / gaussTime;
    var marker:String = (ratio > 1.1) ? " <-- Gaussian优" : ((ratio < 0.9) ? " <-- Loop优" : "");

    trace("n=" + n + " | Loop:" + loopTime + "ms | Gauss:" + gaussTime + "ms | 比值:" + ratio + marker);
}

trace("");
trace("比值 > 1.0 表示高斯路径更快，建议阈值设为比值首次 > 1.0 的 n 值");
```

## 测试脚本 5：multinomialSample3 专项测试

```actionscript
import org.flashNight.naki.RandomNumberEngine.*;

var RNG:LinearCongruentialEngine = LinearCongruentialEngine.getInstance();

var ITERATIONS:Number = 10000;
var outCounts:Array = [0, 0, 0];

// 无懒闪避时的概率分布
var pMiss:Number = 0.15;  // dodgeProb
var pBounce:Number = 0.85 * 0.6;  // (1-dodgeProb) * bounceProb = 0.51

trace("====== multinomialSample3 性能测试 ======");
trace("概率分布: pMiss=" + pMiss + ", pBounce=" + pBounce);
trace("");

// 内联循环路径
function loop3(n:Number):Void {
    var tMiss:Number = pMiss;
    var tBounce:Number = pMiss + pBounce;
    var missCount:Number = 0, bounceCount:Number = 0, penCount:Number = 0;
    var i:Number = 0;
    do {
        var r:Number = RNG.nextFloat();
        if (r < tMiss) missCount++;
        else if (r < tBounce) bounceCount++;
        else penCount++;
    } while (++i < n);
    outCounts[0] = missCount; outCounts[1] = bounceCount; outCounts[2] = penCount;
}

// 内联高斯路径
function gauss3(n:Number):Void {
    var varMiss:Number = n * pMiss * (1 - pMiss);
    var varBounce:Number = n * pBounce * (1 - pBounce);

    var missCount:Number, bounceCount:Number, penCount:Number;

    missCount = (varMiss > 0.25) ? ((n * pMiss + Math.sqrt(varMiss) * ((RNG.nextFloat() + RNG.nextFloat() + RNG.nextFloat()) * 2 - 3) + 0.5) >> 0) : ((n * pMiss + 0.5) >> 0);
    bounceCount = (varBounce > 0.25) ? ((n * pBounce + Math.sqrt(varBounce) * ((RNG.nextFloat() + RNG.nextFloat() + RNG.nextFloat()) * 2 - 3) + 0.5) >> 0) : ((n * pBounce + 0.5) >> 0);

    if (missCount < 0) missCount = 0;
    if (bounceCount < 0) bounceCount = 0;

    var sum:Number = missCount + bounceCount;
    if (sum > n) {
        var scale:Number = n / sum;
        missCount = (missCount * scale) >> 0;
        bounceCount = (bounceCount * scale) >> 0;
        penCount = n - missCount - bounceCount;
    } else {
        penCount = n - sum;
    }
    if (penCount < 0) penCount = 0;

    outCounts[0] = missCount; outCounts[1] = bounceCount; outCounts[2] = penCount;
}

for (var n:Number = 10; n <= 40; n += 2) {
    var startLoop:Number = getTimer();
    for (var i:Number = 0; i < ITERATIONS; i++) {
        loop3(n);
    }
    var loopTime:Number = getTimer() - startLoop;

    var startGauss:Number = getTimer();
    for (var j:Number = 0; j < ITERATIONS; j++) {
        gauss3(n);
    }
    var gaussTime:Number = getTimer() - startGauss;

    var ratio:Number = loopTime / gaussTime;
    var marker:String = (ratio > 1.1) ? " <-- Gaussian优" : ((ratio < 0.9) ? " <-- Loop优" : "");

    trace("n=" + n + " | Loop:" + loopTime + "ms | Gauss:" + gaussTime + "ms | 比值:" + ratio.toFixed(3) + marker);
}
```

## 预期结果分析

根据测试结果，我们应该能够确定：

1. **精确平衡点**：循环路径与高斯路径耗时相等的 n 值
2. **推荐阈值**：考虑到精度和稳定性，通常选择略低于平衡点的值
3. **概率分布影响**：不同概率分布下平衡点是否有显著差异

## 当前设置

- `multinomialSample3` 阈值：12
- `multinomialSample4` 阈值：12

## 测试后更新记录

| 日期 | 测试环境 | 平衡点 | 最终阈值 | 备注 |
|------|---------|--------|---------|------|
| - | - | - | 24 | 理论估算值 |
| 2026-01-12 | Flash IDE | n=11 | 12 | 脚本4实测，n=11时比值1.01 |

## 脚本4测试日志（2026-01-12）

```
====== 精确阈值搜索 ======
概率分布: pMiss=0.1275, pBounce=0.4335, pInstant=0.15

n=1 | Loop:40ms | Gauss:45ms | 比值:0.888888888888889 <-- Loop优
n=3 | Loop:68ms | Gauss:168ms | 比值:0.404761904761905 <-- Loop优
n=5 | Loop:103ms | Gauss:185ms | 比值:0.556756756756757 <-- Loop优
n=7 | Loop:130ms | Gauss:175ms | 比值:0.742857142857143 <-- Loop优
n=9 | Loop:161ms | Gauss:169ms | 比值:0.952662721893491
n=11 | Loop:186ms | Gauss:184ms | 比值:1.01086956521739          <-- 平衡点
n=13 | Loop:215ms | Gauss:182ms | 比值:1.18131868131868 <-- Gaussian优
n=15 | Loop:234ms | Gauss:180ms | 比值:1.3 <-- Gaussian优
n=17 | Loop:267ms | Gauss:187ms | 比值:1.42780748663102 <-- Gaussian优
n=19 | Loop:303ms | Gauss:171ms | 比值:1.7719298245614 <-- Gaussian优
n=21 | Loop:317ms | Gauss:174ms | 比值:1.82183908045977 <-- Gaussian优
n=23 | Loop:365ms | Gauss:173ms | 比值:2.10982658959538 <-- Gaussian优
n=25 | Loop:399ms | Gauss:183ms | 比值:2.18032786885246 <-- Gaussian优
n=27 | Loop:415ms | Gauss:170ms | 比值:2.44117647058824 <-- Gaussian优
n=29 | Loop:433ms | Gauss:187ms | 比值:2.31550802139037 <-- Gaussian优
n=31 | Loop:478ms | Gauss:183ms | 比值:2.6120218579235 <-- Gaussian优
n=33 | Loop:507ms | Gauss:170ms | 比值:2.98235294117647 <-- Gaussian优
n=35 | Loop:567ms | Gauss:169ms | 比值:3.35502958579882 <-- Gaussian优
n=37 | Loop:558ms | Gauss:187ms | 比值:2.98395721925134 <-- Gaussian优
n=39 | Loop:605ms | Gauss:172ms | 比值:3.51744186046512 <-- Gaussian优

比值 > 1.0 表示高斯路径更快，建议阈值设为比值首次 > 1.0 的 n 值
```

### 结论

- **精确平衡点**：n = 11（比值 1.01）
- **推荐阈值**：12（保守取整，确保 n ≤ 12 走精确循环路径）
- **性能提升**：n = 15 时旧阈值(24)走循环需 234ms，新阈值走高斯仅 180ms，提升 30%
- **精度保证**：游戏中 80%+ 的联弹（n ∈ [3,12]）仍走精确循环路径
