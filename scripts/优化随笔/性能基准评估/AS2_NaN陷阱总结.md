# AS2 (AVM1) NaN 完全行为手册

> **测试环境**：Flash CS6 / AVM1，2026-03-13 实测
> **目的**：穷举 NaN 在 AS2 中的所有行为边界，标注与 IEEE 754 / ECMAScript 标准的偏差，为基建层防御性编程提供可靠依据

---

## 一、核心发现：AS2 NaN 的三大致命偏差

### 偏差 1：NaN 自等性——同一变量 `NaN == NaN` 返回 true

| 表达式 | AS2 实测 | IEEE 754 / ES 标准 | 偏差 |
|--------|----------|-------------------|------|
| `nan_div == nan_div`（同一变量） | **true** | false | **致命偏差** |
| `nan_div != nan_div`（同一变量） | **false** | true | **致命偏差** |
| `nan_div == nan_div2`（同源不同变量） | false | false | 一致 |
| `nan_div == nan_sqrt`（不同源） | false | false | 一致 |
| `(0/0) == (0/0)`（内联表达式） | false | false | 一致 |

**机制分析**：AVM1 对同一寄存器/变量槽的 NaN 做了引用级比较短路——同一个变量引用与自身比较直接返回 true，跳过了 IEEE 754 的 NaN 特殊处理。不同变量即使值都是 NaN，由于是不同的引用，走正常数值比较路径返回 false。

**致命后果**：**`x != x` 不能用作 NaN 检测**。在标准 JS/IEEE 754 中 `x != x` 当且仅当 x 为 NaN 时为 true，但 AS2 中这个惯用法完全失效——对同一变量始终返回 false。

---

### 偏差 2：`>` 和 `<` 返回 undefined（不是 false）

| 表达式 | AS2 实测 | IEEE 754 / ES 标准 | 偏差 |
|--------|----------|-------------------|------|
| `NaN > 42` | **undefined** | false | **偏差** |
| `NaN < 42` | **undefined** | false | **偏差** |
| `42 > NaN` | **undefined** | false | **偏差** |
| `42 < NaN` | **undefined** | false | **偏差** |
| `NaN > NaN`（同变量） | **undefined** | false | **偏差** |
| `NaN < NaN`（异源） | **undefined** | false | **偏差** |

**机制分析**：AVM1 的 `<` / `>` 操作码在操作数为 NaN 时返回 undefined 而非 false。在布尔上下文中 undefined 等价于 false，所以 `if (NaN > x)` 不进入——**表面行为与标准一致，但返回值类型不同**。

**连锁效应**：这个偏差是偏差 3 的根源。

---

### 偏差 3：`>=` / `<=` 与 NaN 始终返回 true

| 表达式 | AS2 实测 | IEEE 754 / ES 标准 | 偏差 |
|--------|----------|-------------------|------|
| `NaN >= 42` | **true** | false | **致命偏差** |
| `NaN <= 42` | **true** | false | **致命偏差** |
| `42 >= NaN` | **true** | false | **致命偏差** |
| `42 <= NaN` | **true** | false | **致命偏差** |
| `NaN >= NaN`（同变量） | **true** | false | **致命偏差** |
| `NaN >= NaN`（异源） | **true** | false | **致命偏差** |
| `NaN >= 0` | **true** | false | **致命偏差** |
| `NaN <= 0` | **true** | false | **致命偏差** |
| `NaN >= Infinity` | **true** | false | **致命偏差** |
| `NaN <= -Infinity` | **true** | false | **致命偏差** |

**实现验证**：
```
NaN >= 42    → true
!(NaN < 42)  → !(undefined) → true
两者完全一致
```

**确认**：AVM1 将 `>=` 实现为 `!(<)`，`<=` 实现为 `!(>)`。由于 `<` / `>` 对 NaN 返回 undefined，`!(undefined)` = true，导致 **NaN 与任何值的 `>=` / `<=` 比较都返回 true**。

---

## 二、直接后果：NaN 导致的死循环

```
while (i <= NaN)  → 死循环！ i<=NaN 永远为 true
while (i >= NaN)  → 死循环！ i>=NaN 永远为 true
for (i=NaN; i>=0; i--)  → 死循环！ NaN>=0 为 true，NaN-- 仍为 NaN

while (i < NaN)   → 不进入（安全）
while (i > NaN)   → 不进入（安全）
for (i=NaN; i>0; i--)  → 不进入（安全）
```

**规则**：严格不等式 `<` / `>` 在 NaN 时返回 undefined（falsy），循环不进入——安全。非严格不等式 `<=` / `>=` 返回 true，循环条件永远满足——**死循环**。

---

## 三、NaN 检测方法可靠性矩阵

| 方法 | NaN 检测 | Infinity 检测 | 性能 | 可靠性 |
|------|----------|---------------|------|--------|
| `isNaN(x)` | ✅ 可靠 | ❌ 不检测 | 函数调用 | **推荐（纯 NaN 检测）** |
| `(x - x) != 0` | ✅ 可靠 | ✅ 也检测 | 1减1比 | **推荐（NaN + Infinity）** |
| `x != x` | ❌ **不可靠** | ❌ 不检测 | 1比较 | **禁用** |
| `typeof(x) != "number"` | ❌ NaN 也是 number | — | 字符串比较 | 不适用 |

### `(x - x) != 0` 详细验证

| 输入 | `x - x` | `!= 0` | 检测结果 |
|------|---------|--------|----------|
| `0/0`（NaN） | NaN | **true** | ✅ 检出 |
| `Math.sqrt(-1)`（NaN） | NaN | **true** | ✅ 检出 |
| `undefined + 0`（NaN） | NaN | **true** | ✅ 检出 |
| `Number("abc")`（NaN） | NaN | **true** | ✅ 检出 |
| `Infinity - Infinity`（NaN） | NaN | **true** | ✅ 检出 |
| `42`（正常数值） | 0 | false | ✅ 正确放行 |
| `Infinity` | NaN | **true** | ✅ 检出（附带） |

### `x != x` 失败验证

| 输入 | 结果 | 检测结果 |
|------|------|----------|
| `nan_div != nan_div` | **false** | ❌ 漏检！ |
| `nan_sqrt != nan_sqrt` | **false** | ❌ 漏检！ |
| `nan_undef != nan_undef` | **false** | ❌ 漏检！ |
| `nan_infSub != nan_infSub` | **false** | ❌ 漏检！ |

**所有来源的 NaN 与自身比较都返回 false，即 `x != x` 对 NaN 不成立。**

---

## 四、NaN 的完整行为参考

### 4.1 NaN 来源

以下表达式在 AS2 中产生 NaN（typeof 均为 `"number"`）：

| 表达式 | 结果 | 备注 |
|--------|------|------|
| `0 / 0` | NaN | |
| `undefined + 0` | NaN | undefined 参与算术 |
| `Number(undefined)` | NaN | |
| `Math.sqrt(-1)` | NaN | 负数开方 |
| `Infinity - Infinity` | NaN | |
| `Infinity / Infinity` | NaN | |
| `Number("abc")` | NaN | 不可解析字符串 |
| `Number(null)` | **NaN** | ⚠ 标准 JS 返回 0 |
| `Number("")` | **NaN** | ⚠ 标准 JS 返回 0 |
| `Number(" ")` | **NaN** | ⚠ 标准 JS 返回 0 |
| `parseInt("")` | NaN | |
| `parseInt("NaN")` | NaN | |
| `parseFloat("NaN")` | NaN | |

**AS2 特有偏差**：`Number(null)` / `Number("")` / `Number(" ")` 在标准 JavaScript 中返回 0，在 AS2 中返回 NaN。这意味着看似安全的空值转换在 AS2 中会产生 NaN。

### 4.2 算术传播

NaN 参与任何算术运算都传播 NaN（与标准一致）：

```
NaN + 1   = NaN       NaN - 1   = NaN
NaN * 1   = NaN       NaN / 1   = NaN
NaN * 0   = NaN       -NaN      = NaN
NaN + NaN = NaN
```

例外：`Math.pow(NaN, 0) = 1`（标准规定任何数的 0 次方为 1）。

### 4.3 位运算截断

NaN 参与位运算时被截断为 0（与标准一致）：

```
NaN | 0   = 0         NaN & 0   = 0
NaN ^ 0   = 0         NaN >> 0  = 0
NaN << 0  = 0         NaN | 1   = 1
NaN | -1  = -1        Infinity | 0 = 0
```

**安全模式**：`(expr) | 0` 可将 NaN 截断为 0，常用于整数化时的兜底。

### 4.4 布尔转换

NaN 在布尔上下文中为 falsy（与标准一致）：

```
Boolean(NaN) = false    !NaN  = true    !!NaN = false
if (NaN) → 不进入       if (!NaN) → 进入
```

### 4.5 逻辑运算符

```
NaN || 42  = 42      （NaN falsy，返回右操作数）
NaN && 42  = NaN     （NaN falsy，短路返回 NaN）
42 || NaN  = 42      （42 truthy，短路返回 42）
42 && NaN  = NaN     （42 truthy，返回右操作数 NaN）
0 || NaN   = NaN     （0 falsy，返回 NaN）
```

**危险模式**：`x && y` 中如果 x 为 truthy 而 y 为 NaN，整个表达式返回 NaN。

### 4.6 字符串转换

```
String(NaN)    = "NaN"
NaN.toString() = "NaN"
NaN + ""       = "NaN"
"" + NaN       = "NaN"
```

### 4.7 Math 函数

| 表达式 | 结果 | 符合标准 |
|--------|------|----------|
| `Math.abs(NaN)` | NaN | ✅ |
| `Math.floor(NaN)` | NaN | ✅ |
| `Math.ceil(NaN)` | NaN | ✅ |
| `Math.round(NaN)` | NaN | ✅ |
| `Math.sqrt(NaN)` | NaN | ✅ |
| `Math.max(NaN, 5)` | NaN | ✅ |
| `Math.max(5, NaN)` | NaN | ✅ |
| `Math.min(NaN, 5)` | NaN | ✅ |
| `Math.min(5, NaN)` | NaN | ✅ |
| `Math.pow(NaN, 0)` | 1 | ✅（标准规定） |
| `Math.pow(NaN, 1)` | NaN | ✅ |

### 4.8 数组与对象

```
arr[NaN]      → undefined       // NaN 不是有效索引
typeof arr[NaN] → "undefined"
```

NaN 作为对象属性键时被字符串化为 `"NaN"`：
```
obj[nan_div] = 100    // 等价于 obj["NaN"] = 100
obj[nan_sqrt]         // 等价于 obj["NaN"] → 100
obj["NaN"]            // → 100
```

**所有不同来源的 NaN 作为键时共享同一个 `"NaN"` 属性。**

### 4.9 排序

`Array.sort(Array.NUMERIC)` 将 NaN 值排到末尾：
```
排序前: [3, NaN, 1, NaN, 2]
排序后: [1, 2, 3, NaN, NaN]
```

### 4.10 isNaN() 的边界

| 输入 | isNaN() | 备注 |
|------|---------|------|
| `NaN`（任意来源） | true | ✅ |
| `42` | false | ✅ |
| `"abc"` | **true** | ⚠ 先转 Number 再判断 |
| `"123"` | false | 字符串可解析为数字 |
| `undefined` | true | |
| `null` | **true** | ⚠ 标准 JS 中 isNaN(null) = false |

**AS2 偏差**：`isNaN(null)` 返回 true（因为 `Number(null)` 在 AS2 中返回 NaN），标准 JS 中 `isNaN(null)` 返回 false（因为 `Number(null)` 返回 0）。

### 4.11 undefined 与 NaN 的交互

```
typeof undefined    = "undefined"
undefined == null   = true        （宽松相等）
undefined == NaN    = false       （NaN 不等于任何非 NaN）
undefined + 0       = NaN         （算术中 undefined → NaN）
undefined * 1       = NaN
undefined | 0       = 0           （位运算截断）
Number(undefined)   = NaN
isNaN(undefined)    = true
```

### 4.12 Infinity 对照

Infinity 行为与标准一致（无偏差），作为对照：

```
Infinity == Infinity  = true      （正常自等性）
Infinity != Infinity  = false
1/0                   = Infinity
-1/0                  = -Infinity
Infinity | 0          = 0         （位运算截断为 0）
(Infinity - Infinity) != 0 = true （结果为 NaN）
isNaN(Infinity - Infinity) = true
```

---

## 五、防御性编程规则（更新版）

### 规则 1：NaN 检测必须用 `isNaN()` 或 `(x - x) != 0`

```actionscript
// ❌ 错误——AS2 中同变量 NaN 自等
if (x != x) { /* 检测 NaN */ }           // 永远不执行！

// ✅ 正确——函数调用
if (isNaN(x)) { /* 检测 NaN */ }

// ✅ 正确——零代价算术检测（同时检测 Infinity）
if ((x - x) != 0) { /* 检测 NaN 或 Infinity */ }
```

### 规则 2：循环条件禁用 `<=` / `>=`，改用 `<` / `>`

```actionscript
// ❌ 致命——NaN 导致死循环
while (c <= c1) { c++; }          // c1 为 NaN 时永远 true

// ✅ 安全——NaN 时不进入
while (c < c1 + 1) { c++; }       // 但 c1+1 仍为 NaN，不进入

// ✅ 最安全——入口守卫
if ((c1 - c1) != 0) return;       // 先排除 NaN
while (c <= c1) { c++; }          // 确认 c1 有效后安全使用
```

### 规则 3：除法前检查分母

```actionscript
// ❌ 危险——分母为 0 或 undefined 时产生 NaN/Infinity
var ratio:Number = hp / maxhp;

// ✅ 安全——短路保护
if (maxhp > 0 && (hp / maxhp) < 0.5) { ... }
```

### 规则 4：`Number()` 转换的 AS2 特殊陷阱

```actionscript
// ⚠ AS2 与标准 JS 行为不同！
Number(null)  → NaN   // 标准 JS: 0
Number("")    → NaN   // 标准 JS: 0
Number(" ")   → NaN   // 标准 JS: 0

// ✅ 安全转换
var n:Number = (x == null || x == undefined) ? 0 : Number(x);
```

### 规则 5：不用一元加 `+s` 转数字

```actionscript
// ❌ AS2 的一元加对 String 不做转换
var b:Number = +s;          // b 实际仍为 String

// ✅ 显式转换
var b:Number = Number(s);
```

### 规则 6：利用 `| 0` 位截断作为最后防线

```actionscript
// NaN | 0 = 0，可防止 NaN 传播但会产生错误结果
hitTarget.hp = (hp - damage) | 0;   // damage 为 NaN 时 hp 归零（秒杀）
var col:Number = (x * invW) | 0;    // x 为 NaN 时 col=0（错误但不崩溃）
```

### 规则 7：`>=` / `<=` 不能作为 NaN 守卫

```actionscript
// ❌ 以为在守卫，实际守卫被穿透
if (tMin > tMax || tMax < 0 || tMin > maxDist) {
    return FALSE;   // NaN 时所有条件为 undefined(falsy)，守卫失效！
}

// ✅ 加入显式 NaN 检测
if ((tMin - tMin) != 0 || tMin > tMax || tMax < 0 || tMin > maxDist) {
    return FALSE;   // NaN 在第一个条件就被拦截
}
```

---

## 六、AS2 NaN 行为偏差速查表

| 行为 | AS2 (AVM1) | IEEE 754 / ES 标准 | 危险等级 |
|------|------------|-------------------|----------|
| `NaN == NaN`（同变量） | **true** | false | 🔴 致命 |
| `NaN != NaN`（同变量） | **false** | true | 🔴 致命 |
| `NaN > x` 返回值 | **undefined** | false | 🟡 中等 |
| `NaN < x` 返回值 | **undefined** | false | 🟡 中等 |
| `NaN >= x` | **true** | false | 🔴 致命 |
| `NaN <= x` | **true** | false | 🔴 致命 |
| `Number(null)` | **NaN** | 0 | 🟠 高 |
| `Number("")` | **NaN** | 0 | 🟠 高 |
| `Number(" ")` | **NaN** | 0 | 🟠 高 |
| `isNaN(null)` | **true** | false | 🟡 中等 |
| `NaN + ""` | `"NaN"` | `"NaN"` | ✅ 一致 |
| `Boolean(NaN)` | false | false | ✅ 一致 |
| `NaN \| 0` | 0 | 0 | ✅ 一致 |
| `typeof NaN` | `"number"` | `"number"` | ✅ 一致 |
| `isNaN(NaN)` | true | true | ✅ 一致 |
| `Math.max(NaN, x)` | NaN | NaN | ✅ 一致 |
| NaN 作对象键 | `"NaN"` 字符串化 | `"NaN"` 字符串化 | ✅ 一致 |
| 排序中的 NaN | 排到末尾 | 未定义 | — |

---

## 七、历史案例

### 案例 1：基准测试 NaN 感染（2026-03）

基准测试开发中 `_bh`（blackhole accumulator）被 NaN 感染，逐层剥离发现 5 个独立根因：

1. **死代码**：NaN 诊断 trace 放在 return 之后，永远不执行
2. **一元加陷阱**：`+s` 对 String 不转换，导致类型污染为字符串拼接
3. **Array.pop() 返回 Object**：赋值给 `:Number` 类型编译错误
4. **数组耗尽**：循环展开超过数组长度，pop() 返回 undefined → NaN
5. **未赋值变量**：base/test 共享 finalize，base 中变量未赋值 → undefined.length → NaN

感染链：一旦 `_bh += NaN`，后续所有 `_bh += x` 永远为 NaN（级联感染）。

### 案例 2：射线子弹链式弹跳死循环（2026-03-12，commit 326073da8）

电感切割刃武器新增射线子弹功能，NaN 坐标从业务层推入基建层（BulletQueueProcessor 的 chain 弹跳逻辑），导致距离计算产生 NaN，进而触发 `<=` 比较的死循环。

修复：业务层增加 NaN 守卫，阻止 NaN 坐标进入子弹系统。基建层尚待加固。
