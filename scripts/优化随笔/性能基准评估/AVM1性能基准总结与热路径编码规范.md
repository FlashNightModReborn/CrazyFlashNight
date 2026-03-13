# AVM1 性能基准总结与热路径编码规范

基于 bench_gen_v8.js 生成的 165 项基准测试（BenchMain_v8.as）、BytecodeProbe 字节码反汇编验证、AS2_NaN 陷阱总结，综合提炼而成。

---

## 证据分层说明

本文档使用以下证据标签：

| 标签 | 含义 | 证据基础 | 使用方式 |
|------|------|---------|---------|
| `[T1a]` | **硬规则 · 零前提** | benchmark + BytecodeProbe 双重确认，无语义风险 | 新写代码直接遵循。存量改写范围见 §12 P0（部分为批量搜改，部分为结构重写） |
| `[T1b]` | **硬规则 · 有前提** | benchmark + BytecodeProbe 双重确认，但替换依赖值域/语义/上下文前提 | 逐调用点确认前提条件后替换，不可批量搜改 |
| `[T2]` | **工程策略** | benchmark 证明了成本方向，但替代方案的全链路成本未被基准覆盖 | 按热点模块试点，先 profile 再改写 |
| `[T3]` | **实验策略** | 数据不足、有已知反例、或 workload 不对称 | 仅供参考，不作为改写依据 |
| `[P]` | **平台经验** | 字节码反汇编 / 项目实战验证，但非当前 benchmark 体系产出 | 可信，但证据源独立于 benchmark |

§1~§9 为数据与分析（标注可信度但不做规范性断言），§10 为分层编码指引，§12 为路线图。

---

## 目录

1. [AVM1 成本阶梯](#1-avm1-成本阶梯)
2. [访问与成员查找](#2-访问与成员查找)
3. [函数调用与 DF1/DF2](#3-函数调用与-df1df2)
4. [字符串与类型转换](#4-字符串与类型转换)
5. [数学运算与 Math 桥接](#5-数学运算与-math-桥接)
6. [控制流](#6-控制流)
7. [容器操作与 GC](#7-容器操作与-gc)
8. [host/native 边界](#8-hostnative-边界)
9. [AS2 特有陷阱](#9-as2-特有陷阱)
10. [分层编码指引](#10-分层编码指引)
11. [不应通用化的经验策略](#11-不应通用化的经验策略)
12. [项目优化路线图](#12-项目优化路线图)
13. [附录：完整基准数据](#13-附录完整基准数据)

---

## 1. AVM1 成本阶梯

基准环境：Flash Player WIN 11,2,202,228，STD_TOTAL=2,000,000 ops，REPEATS=9，WARMUP=3。

| 成本带 | per-op 量级 | 典型操作 | 工程含义 |
|--------|------------|---------|---------|
| 免费带 | 0~30ns | 局部变量读写、算术(+−×÷)、位运算(&\|^<<>>)、typeof、`!!n`、常量折叠 | 循环体内的纯标量运算几乎免费 |
| 低税带 | 30~100ns | 数组索引(~35ns)、`_root` 读取(~46ns)、三元表达式、字符串拼接(~54ns)、`Number(s)`(76ns) | 可在热路径使用，但注意累积 |
| 中税带 | 100~300ns | 对象成员读写(~150ns)、native 属性(~170ns)、`Math.xxx`(~255ns)、`parseInt`(230ns)、`instanceof`(136ns) | 热循环中需局部缓存 |
| 高税带 | 300~700ns | `call_empty`(485ns)、`s.length`(580ns)、字符串方法(580~760ns)、`with`(409ns)、`Key.isDown`(417ns) | 热路径需削减调用次数 |
| 极重带 | 700~1600ns | 方法调用(1340ns)、闭包(1235ns)、`arguments`(1538ns)、`new`(835~915ns)、DF1调用(1079ns)、`split`(1499ns)、`arr.concat`(1673ns) | 热路径禁止或改用替代方案 |

---

## 2. 访问与成员查找

### 2.1 局部变量 vs 全局/成员

```
local_read:       ~0ns    (register 直读，字节码: Push register)
global_read:     ~98ns    (GetVariable 作用域链查找)
root_read:       ~46ns    (register1 + GetMember)
obj_dot_hit:    ~144ns    (GetVariable + GetMember)
obj_miss:       ~158ns    (查找失败，遍历原型链)
native_get_x:   ~171ns    (C++ getter 桥接)
```

**字节码验证**：探针确认局部变量在 DF2 函数中走 `Push register`（直接寄存器读），全局变量走 `GetVariable`（作用域链查找），成员走 `GetVariable + GetMember`。

**可信度**：高。**层次**：2（字节码确认）。

### 2.2 dot 与 bracket 无差异

```
obj_dot_hit:    ~144ns
obj_bracket_str: ~144ns
```

字节码完全一致，均为 `GetMember`。真正的税来自查找层级和 miss，不是语法形式。

### 2.3 链式访问线性增长

```
chain_depth2:   ~179ns  (2层)
chain_depth3:   ~230ns  (3层)
```

每多一层约 +80ns。纸娃娃/深层 MovieClip 层级是典型打击目标。

### 2.4 原型链读取

```
proto1_read:    ~152ns
proto2_read:    ~151ns  (composite/2)
proto3_read:    ~102ns  (composite/3)
```

深度增加后边际成本不显著，可能有 hash 缓存。但这不意味着可以忽略——每次仍比局部变量贵 150ns。

### 2.5 数组索引

```
arr_read_var_5:     ~35ns
arr_read_local_100: ~35ns
arr_read_local_1000: ~36ns
```

**与数组大小无关**（5/100/1000 元素一致），但引用必须是局部变量。全局数组引用会额外叠加 ~98ns 作用域查找税。

### 工程规则

```actionscript
// 错误：热循环中反复做深链访问
while (i--) {
    _root.gameWorld.enemies[i].hp -= this.weapon.damage;
}

// 正确：入口缓存，循环内只用局部变量
var enemies:Array = _root.gameWorld.enemies;
var dmg:Number = this.weapon.damage;
while (i--) {
    enemies[i].hp -= dmg;  // enemies[i] 仍是一次成员读(~35ns)，dmg 免费
}
```

---

## 3. 函数调用与 DF1/DF2

### 3.1 调用成本阶梯

```
call_empty (DF2):     ~485ns    (最便宜的函数调用)
call_empty (DF1):    ~1079ns    (2.2x 更慢)
call_method (o.m()):  ~1340ns   (需 GetVariable + GetMember 解析 receiver)
closure_read:        ~1235ns    (作用域链查找捕获变量)
arguments.length:    ~1538ns    (最贵)
```

### 3.2 DF1 vs DF2 选择规则

AS2 编译器根据函数体是否**引用**参数/局部变量来选择 DefineFunction 版本：

```actionscript
// DF1 — 作用域链，~1079ns/call，~1604ns/new
function empty():Void {}

// DF2 — 寄存器，~485ns/call，~847ns/new
function empty(d:Number):Void { var _:Number = d; }
```

**仅声明参数但不使用，不会触发 DF2。** 必须在函数体中引用参数。

**字节码验证**：探针确认 DF1 用 `DefineFunction`（0 寄存器），DF2 用 `DefineFunction2`（寄存器分配）。

**适用范围**：仅限轻量 helper / 空构造函数 / 纯转发函数。函数体有实质逻辑时，DF1/DF2 差异被函数体成本稀释。

### 3.3 参数数量的影响

```
call_empty:     ~485ns   (0 arg)
call_onearg:    ~474ns   (1 arg)
call_twoargs:   ~502ns   (2 args)
call_threeargs: ~540ns   (3 args)
call_fiveargs:  ~628ns   (5 args)
```

每增加一个参数约 +30ns。热路径函数参数尽量少。

### 3.4 proto 方法 vs instance 方法

```
proto_method:    ~594ns
instance_method: ~596ns
```

无显著差异。不要为此做风格迁移。

### 3.5 .call / .apply 增量

```
fn_call_dotcall:  +82ns  (基于直接调用的增量)
fn_apply_cached:  +90ns
```

.call/.apply 本身增量不大，真正的成本是它们包装的调用层级。

---

## 4. 字符串与类型转换

### 4.1 length(s) vs s.length — 41x 差距

```
str_length (s.length):   ~580ns   (GetMember "length")
str_length_as1 (length(s)): ~14ns (StringLength opcode)
```

**字节码验证**：`s.length` 编译为 `Push s, "length", GetMember`；`length(s)` 编译为 `Push s, StringLength`。专用 opcode 跳过了整个成员查找管线。

**注意**：`length()` 是 AS1 函数，仅对字符串有效。数组长度仍用 `arr.length`。

### 4.2 字符串方法——全部极贵

```
charAt:       ~688ns
charCodeAt:   ~658ns
indexOf(hit): ~709ns
indexOf(miss):~721ns
substr:       ~704ns
split:       ~1499ns  (且每次创建新数组)
toLowerCase:  ~688ns
fromCharCode: ~761ns
```

全部走 `CallMethod` 路径。解析器热核应改为单次前向扫描。

### 4.3 类型转换

```
Number(s):     ~76ns    (ToNumber opcode)
parseInt(s):  ~231ns    (CallFunction)
parseFloat:   ~248ns    (CallFunction)
String(n):     ~14ns    (快速路径)
""+n:          ~58ns    (字符串拼接)
typeof(x):     ~11ns    (TypeOf opcode)
```

**已知纯数字字符串用 `Number(s)`，已知数值转串用 `String(n)`**。

### 4.4 布尔转换 — 7x 差距

```
Boolean(n):  ~193ns    (CallFunction "Boolean")
!!n:          ~28ns    (Not, Not — 两条内联 opcode)
```

**字节码验证**：`Boolean(n)` 编译为 `Push n, 1, "Boolean", CallFunction`；`!!n` 编译为 `Push n, Not, Not`。

### 4.5 比较运算符

```
同类型 ==:   ~19ns    (Equals2)
同类型 ===:  ~21ns    (StrictEquals)
跨类型 ==:  ~104ns   ("42"==42，触发 ToNumber 转换)
跨类型 ===:  ~19ns   (直接 false，无转换)
```

跨类型 `==` 比 `===` 贵 5.6x。但同类型差异极小(~2ns)，不需要为此做全项目无脑替换。**热路径和可能混类型的场景必须用 `===`。**

### 4.6 +s 不做类型转换（AS2 编译器 bug）

```actionscript
var s:String = "42";
var b:Number = +s;     // b 实际是 String "42"！
trace(typeof(b));       // "string"
```

**字节码验证**：`+s` 编译为 `Push s`（无 ToNumber），编译器直接跳过了转换。`Number(s)` 编译为 `Push s, ToNumber`。

**绝对禁止 `+s` 转数字。统一用 `Number(s)`。**

### 4.7 typed vs untyped 局部变量

```
typed_vs_untyped_read: delta=0ns
```

字节码完全一致。类型标注在运行时完全擦除。继续使用（帮助编译期检查），但不要期望运行时性能收益。

---

## 5. 数学运算与 Math 桥接

### 5.1 Math.xxx 统一 ~250-265ns

```
Math.floor:  ~254ns     Math.ceil:  ~251ns
Math.round:  ~254ns     Math.abs:   ~249ns
Math.min:    ~264ns     Math.max:   ~264ns
Math.sqrt:   ~253ns     Math.sin:   ~265ns
Math.atan2:  ~293ns     Math.random: ~257ns
```

**字节码验证**：`Math.floor(a)` 编译为 `Push a, 1, "Math", GetVariable, "floor", CallMethod`——三步操作。

### 5.2 缓存 Math 引用 — 省约 44%

```
cached_math_floor: ~142ns  (vs 直调 254ns)
cached_math_sin:   ~147ns  (vs 直调 265ns)
```

缓存后仍需 `CallMethod(undefined)`，省掉的是 `GetVariable("Math") + GetMember("floor")` 查找税。

```actionscript
// 在函数入口或模块级别
var mfloor:Function = Math.floor;
var msin:Function = Math.sin;

// 热循环内
b = mfloor(a);    // ~142ns 而非 ~254ns
b = msin(angle);  // ~147ns 而非 ~265ns
```

### 5.3 内联替换 — 比 Math.xxx 快 4-9x

| 操作 | Math.xxx | 内联替代 | 加速比 | 语义差异 |
|------|---------|---------|-------|---------|
| 取整 | `Math.floor(x)` 254ns | `(x\|0)` 29ns | **8.7x** | ToInt32 截断(toward zero)：(a) 负数 `-3.7\|0=-3` 非 `-4`，(b) NaN\|0→0，Infinity\|0→0，(c) \|x\|≥2^31 截断为错误值 |
| 绝对值 | `Math.abs(x)` 249ns | `x<0?-x:x` 58ns | **4.3x** | NaN 时：Math.abs→NaN；三元→NaN（AS2 中 `NaN<0` 返回 undefined→falsy，走 else 分支返回 NaN）。**行为一致** |
| 最小值 | `Math.min(a,b)` 264ns | `a<b?a:b` 31ns | **8.5x** | 仅限二元。NaN 时：Math.min→NaN；三元→b（`NaN<b` 为 undefined→falsy，返回 b）。**行为不同** |
| 最大值 | `Math.max(a,b)` 264ns | `a>b?a:b` 42ns | **6.3x** | 仅限二元。NaN 时：Math.max→NaN；三元→b（`NaN>b` 为 undefined→falsy，返回 b）。**行为不同** |
| clamp | `Math.min(Math.max(a,lo),hi)` 274ns | `a<lo?lo:(a>hi?hi:a)` 40ns | **6.8x** | — |

**`~~x` 取整(69ns) 比 `x|0`(29ns) 贵 2.4x** `[T1a]`，字节码确认 `~~x` = 2×(BitXor 0xFFFFFFFF) = 4 ops。两者语义相同（均为 ToInt32），纯粹是指令数差异。

**`x|0` 替代 `Math.floor` 的完整前提** `[T1b]`：`x|0` 执行的是 ECMAScript ToInt32 转换，非数学 floor：
- NaN|0 → 0，Infinity|0 → 0（静默吞掉异常值）
- |x| ≥ 2^31 时截断为错误值（ToInt32 取模）
- 负数截断 toward zero：`-3.7|0 = -3` 而非 `-4`

仅在已知输入为有限数值、Int32 范围内、且 x≥0 或截断语义可接受时使用。否则用 `var mf:Function = Math.floor; mf(x);`（142ns）。

### 5.4 NaN/Infinity 传播代价

```
nan_add:       ~297ns  (NaN+1)
infinity_mul:  ~218ns  (Infinity*2)
```

远高于普通算术(~20ns)。一旦 NaN 进入热循环，所有后续运算都在高成本区。

**AS2 NaN 的额外危险**（实测确认，详见 [AS2_NaN陷阱总结.md](AS2_NaN陷阱总结.md)）：
- `NaN > x` / `NaN < x` 返回 **undefined**（非标准的 false），导致 `>=`/`<=` 对 NaN 返回 true
- `while(i <= NaN)` / `while(i >= NaN)` → **死循环**
- 性能+安全复合风险：NaN 感染后不仅每步运算贵 15x，还可能触发死循环
- **零代价检测**：`(x - x) != 0`（~39ns）比 `isNaN()`（184ns）快 4.7x

---

## 6. 控制流

### 6.1 if-else vs switch

```
5 cases:   if-else 158ns  vs  switch 180ns
10 cases:  if-else 330ns  vs  switch 356ns
```

**字节码验证**：switch 用 `StrictEquals + If` 跳链，if-else 用 `Equals2 + Not + If`。AVM1 的 switch **不是跳表**。

if-else 略快(~13%)，但差异不大。适合作为热状态机专题策略，不适合作为全项目风格要求。

### 6.2 逻辑短路

```
false && x (短路):  ~36ns
true && x (求值):   ~64ns
true || x (短路):   ~25ns
```

把最可能为 false 的条件放在 `&&` 左侧，最可能为 true 的放在 `||` 左侧。

### 6.3 循环形式

```
do-while:    ~305ns/iter
while(i--):  ~336ns/iter
for(i++):    ~335ns/iter
empty while: ~112ns/iter
```

do-while 最快(~9%)，但差异远不如减访问层级/减调用边界重要。

### 6.4 热路径禁区

```
with 块:     ~409ns
try(无异常):  ~75ns
try(有异常): ~473ns
eval:        ~216ns
for-in 5p:  ~2200ns/iter
for-in 20p: ~7800ns/iter
```

---

## 7. 容器操作与 GC

### 7.1 数组方法成本

```
arr.push:       ~273ns
arr.pop:        ~185ns
arr.shift:      ~405ns
arr.unshift:    ~973ns
arr.splice(mid): ~4231ns
arr.concat:     ~1673ns
arr.slice:      ~766ns
arr.sort(5):    ~540ns
arr.reverse:    ~752ns
arr.join:       ~495ns
arr.length=0:    ~69ns   (清空)
```

**splice 是最贵的单一容器操作(4231ns)**。替代方案（标记删除+压缩、swap-with-last+pop）需按实际删除/遍历频率 profile 选择。

### 7.2 分配成本

```
new Object():    ~900ns
new Array():     ~550ns
{x:1} 字面量:    ~350ns
[1,2,3] 字面量:  ~725ns
[1..10]:        ~1750ns
```

`new` 本身是极重操作。但"使用对象池"不是自动更优的替代——项目现有 ObjectPool.as 的 `getObject()` 链路包含 `resetFunc.apply(obj, arguments)`（apply+arguments，极重带）、`Delegate.create`（闭包）、`Array.prototype.slice.call`（三重极重操作）。**是否使用池需要全链路 profile，而非机械替换所有 `new`。**

清空数组用 `arr.length=0`(69ns) 而非 `arr=[]`(550ns+GC)——这一点是 `[T1]` 硬规则。

---

## 8. host/native 边界

```
_mc._x get:      ~171ns
_mc._x set:      ~146ns
_mc._visible:    ~165ns
Key.isDown:      ~417ns
fromCharCode:    ~762ns
cached parseInt: ~177ns
getTimer():       ~8ns   (原生 opcode，不是函数调用)
```

native API 成本差异大，不是统一常数。`getTimer()` 极便宜，可自由用于计时。

### isNaN — AS2 特殊行为与零代价替代

```
isNaN(n):       ~184ns  (CallFunction)
n != n:          ~17ns  (但在 AS2 中始终返回 false！禁用！)
(n - n) != 0:   ~39ns  (1 减法 + 1 比较，可靠，同时检测 Infinity)
```

**AS2 中 `NaN == NaN`（同一变量）返回 true（违反 IEEE 754）**。AVM1 对同一寄存器的 NaN 做了引用级比较短路。`n != n` 始终返回 false，**禁止用作 NaN 检测**。

**NaN 与 `>` / `<` 返回 undefined（非 false）**：`NaN > 42` → undefined，`NaN < 42` → undefined。在布尔上下文中 undefined 等价 falsy，表面行为与标准一致，但这导致 `>=`（实现为 `!(<)`）和 `<=`（实现为 `!(!)`）对 NaN **始终返回 true**：`NaN >= 42` → `!(undefined)` → true。**这会导致 `while (i <= NaN)` 死循环。**

**热路径推荐 `(n - n) != 0`**：比 `isNaN()` 快约 4.7x，且同时检测 Infinity。详见 [AS2_NaN陷阱总结.md](AS2_NaN陷阱总结.md) §三。

---

## 9. AS2 特有陷阱

详见 [AS2_NaN陷阱总结.md](AS2_NaN陷阱总结.md)（完全行为手册，含 17 组实测数据）。核心要点：

1. **`+s` 不转换类型**：编译器 bug，`+s` 对 String 返回原 String
2. **NaN 级联感染**：一旦 `_bh` 被 NaN 污染，所有后续累加永久 NaN
3. **Array.pop()/shift() 返回 Object**：显式类型声明会编译错误
4. **NaN == NaN = true（同变量）**：AS2 违反 IEEE 754，`n != n` 不能检测 NaN。用 `(n-n)!=0` 或 `isNaN(n)`
5. **`>` / `<` 对 NaN 返回 undefined**：非标准返回值，导致 `>=`/`<=` 对 NaN 始终为 true（死循环根因）
6. **`Number(null)` / `Number("")` / `Number(" ")` 返回 NaN**：标准 JS 中返回 0，AS2 特有陷阱
7. **`isNaN(null)` 返回 true**：标准 JS 中返回 false（因 AS2 的 `Number(null)=NaN`）
8. **循环中 `<=` / `>=` 与 NaN 值会死循环**：`while(i <= NaN)` 永远为 true。只用 `<` / `>` 严格不等式可安全避免

---

## 10. 分层编码指引

### Tier 1a · 硬规则 · 零前提（新代码直接遵循）

> 每条均有 benchmark + BytecodeProbe 双重确认，无语义风险。其中部分为写法等价变换（可批量搜改，见 P0），部分为编码准则（新写时遵循，存量按热点逐步改造）。

**访问**

- **H01** `[T1a]` 热循环中，外部变量首次使用前必须 `var local = xxx` 局部化
- **H02** `[T1a]` 链式访问 `a.b.c` 若在循环内使用 >=2 次，必须缓存中间对象
- **H03** `[T1a]` MovieClip 属性(`_x/_y/_visible` 等)批量读写前，缓存 MC 引用到局部变量

**字符串与类型转换**

- **H04** `[T1a]` 字符串长度一律用 `length(s)`(14ns)，禁止 `s.length`(580ns) — 41x 差距。注意：仅对字符串有效，数组长度仍用 `arr.length`
- **H05** `[T1a]` 数字转换一律用 `Number(s)`，**绝对禁止** `+s`（AS2 编译器 bug：不生成 ToNumber）
- **H06** `[T1a]` 布尔转换一律用 `!!x`(28ns)，禁止 `Boolean(x)`(193ns) — 7x 差距
- **H07** `[T1a]` NaN 检测禁止 `n != n`（AS2 中同变量 NaN==NaN 为 true）。冷路径用 `isNaN(n)`(184ns)；热路径用 `(n - n) != 0`(~39ns，同时检测 Infinity)
- **H07b** `[T1a]` 循环条件涉及可能为 NaN 的变量时，禁用 `<=` / `>=`（NaN 时始终为 true → 死循环）。用 `<` / `>` 严格不等式，或在循环前用 `(x-x)!=0` 守卫

**调用**

- **H09** `[T1a]` 热路径禁止使用 `arguments` 对象(1538ns)。用显式参数

**数学**

- **H11** `[T1a]` 不能内联的 Math(sin/cos/sqrt/atan2) 缓存引用：`var msin:Function = Math.sin;`（省~44%）
- **H12** `[T1a]` 禁止 `~~x` 取整(69ns, 4ops)，用 `x|0`(29ns, 1op)

**控制流**

- **H16** `[T1a]` 热路径禁止 `for-in`(2200~7800ns/iter)
- **H17** `[T1a]` 热路径禁止 `with`(409ns)
- **H18** `[T1a]` 热路径禁止 `try-catch` 包裹。异常处理放在外层

**容器**

- **H20** `[T1a]` 热路径禁止 `splice`(4231ns)/`concat`(1673ns)/`unshift`(973ns)
- **H21** `[T1a]` 清空数组用 `arr.length = 0`(69ns)，不用 `arr = []`(550ns+GC)

### Tier 1b · 硬规则 · 有前提（逐调用点审查后替换）

> benchmark + BytecodeProbe 双重确认性能差距真实存在，但替换有值域/语义前提，不可全局搜改。

**跨类型比较**

- **H08** `[T1b]` 热路径用 `===` 替代 `==`（跨类型 `==` 贵 5.6x）。同类型差异仅 ~2ns，冷路径无需替换
  - ⚠️ **前提**：该比较点不依赖 `==` 的隐式 coercion（如 `"42" == 42` 依赖自动转换则不能直接替换）。安全场景：(a) 类型已在比较前归一化，或 (b) 确认双方始终同类型但想防御混入

**逻辑短路**

- **H19** `[T1b]` 逻辑短路：最可能 false 的条件放 `&&` 左侧
  - ⚠️ **前提**：条件求值无副作用，且不存在 guard 顺序依赖（如 `obj != null && obj.x > 0` 中左侧是右侧的安全前提，不能调换）

**DF2 审计**

- **H10** `[T1b]` 轻量 helper / 空 ctor / 纯转发函数确认触发 DF2（函数体中引用参数）。前提：仅限函数体极轻，实质逻辑时差异被稀释

**数学内联替换**

- **H13** `[T1b]` 热路径取整用 `(x|0)` 替代 `Math.floor()` — 8.7x
  - ⚠️ **前提（全部必须满足）**：
    - (a) x 是有限数值（`NaN|0 → 0`，`Infinity|0 → 0`，静默吞掉异常值）
    - (b) x 在 Int32 范围内（|x| < 2^31，超范围截断为错误值）
    - (c) x≥0，或截断语义可接受（`x|0` 是 toward-zero 截断，`-3.7|0 = -3` 而非 `-4`）
  - 不满足任一前提时，用缓存的 `Math.floor` 引用（142ns）
- **H14** `[T1b]` 热路径 abs 用 `x<0?-x:x` 替代 `Math.abs()` — 4.3x。⚠️ 前提：输入为有限数值
- **H15** `[T1b]` 热路径 min/max/clamp 用三元表达式 — 6.3~8.5x。⚠️ 前提：仅限二元、已知有限数值。NaN 输入时行为与 Math.min/max 不同

### Tier 2 · 工程策略（需先 profile 再试点）

> benchmark 证明了成本方向，但替代方案的全链路成本未被基准覆盖。

**调用形态**

- **S01** 热路径中 `o.m()` 方法调用极贵(1340ns)。优化方向：减少调用次数或改 API 形态，**不是**简单缓存方法引用
  - `var f = o.m; f()` 会丢 `this`——AS2 函数引用不携带 receiver。安全做法：(a) 仅限不依赖 `this` 的纯函数，或 (b) 先将方法重构为不依赖 receiver 的形态
- **S02** `new` 本身 847~915ns（极重），但"使用对象池"不是自动更优
  - 项目现有 ObjectPool.as 链路包含 apply+arguments+Delegate.create+Array.prototype.slice.call，全部落在文档定义的极重带。需全链路 profile 才能判断是否比直接 new 更优
  - 轻量场景考虑手写 inline 池（无 apply/arguments/Delegate）

**分配与 GC**

- **S03** 热路径避免临时对象/数组字面量，复用预分配静态对象。管理成本（重入保护、生命周期）需按场景评估
- **S04** `apply` 参数数组应预分配复用
- **S05** `split()` 极贵(1499ns)且创建新数组，一次 split 后缓存结果

**host/native 与生命周期**

- **S06** 输入采样集中到每帧一次 snapshot(Key.isDown=417ns/次)。具体实现成本取决于采样量
- **S07** 逻辑层批量读写 `_mc` 时(170ns/次)，统一走 view flush。单次读写场景 flush 层反而增加间接成本
- **S08** 热路径避免 `delete` 驱动生命周期，优先 active flag / null 置空。注意：benchmark 的 `delete_prop`(166ns) 测的是简单属性删除，不代表实体容器删除成本
- **S09** 实体列表避免 `splice` 删除(4231ns)。具体方案（标记删除+压缩、swap-with-last+pop、双缓冲）需按删除/遍历频率 profile
- **S10** 属性 miss(158ns)有额外成本，频繁读取的属性应预初始化

---

## 11. 不应通用化的经验策略

| 项 | 为什么不能通用化 |
|----|----------------|
| "AOS 一定比 SOA 快" | benchmark 中 AOS 用局部 `e` 缓存了对象引用，SOA 用全局数组多了作用域查找税，workload 不对称 |
| "新增属性比已有属性写入快" | `member_set_newprop` 是 struct+resetEach 特殊 case，不是普通热路径等价物 |
| "所有函数都要强制 DF2" | 仅适用于 tiny wrapper/ctor，函数体有实质逻辑时差异被稀释 |
| "`===` 总比 `==` 快" | 同类型差异仅 ~2ns；只在跨类型时有意义 |
| "do-while 比 for 快" | 差异 ~9%，远不如减访问层级/减调用边界 |
| "缓存 Math.xxx 就够了" | 缓存只减查找税(~110ns)，不减 native 调用税；能内联的应优先内联 |
| "脏标记一定比直接写 host 快" | 当前 micro workload 落在 1ms timer quantum 边界，数据不可区分 |
| "switch vs if-else 要统一换" | 差异仅 ~13%，适合热状态机专题策略，不适合全项目风格 |
| "typed vs untyped 会影响性能" | 运行时完全擦除，不影响性能，但类型标注的编译期检查价值仍存在 |
| "字符串累加没问题" | `gc_string_concat_accum` 仍为 NOISY_CV>0.99，待真实 workload 验证 |
| "对象池一定比 new 快" | 项目现有 ObjectPool.as 的 getObject/release 链路包含 apply+arguments+Delegate+slice，全部落在极重带。池是否比 new 更优需全链路 profile |

---

## 12. 项目优化路线图

### P0 — T1a 写法等价变换（可批量搜改）

1. **`s.length` → `length(s)`**（仅字符串上下文）— 41x 差距，零语义风险
2. **`Boolean(x)` → `!!x`** — 7x 差距，零语义风险
3. **`+s` → `Number(s)`** — 编译器 bug，零语义风险
4. **`~~x` → `x|0`** — 2.4x 差距，同为截断语义
5. **不能内联的 `Math.sin/cos/atan2/sqrt` → 缓存引用** — 44% 提升，零语义风险
6. **将本文的编码指引(第10节)写入项目文档** ✓ 已完成（agentsDoc/as2-performance.md）

### P0.5 — T1b 逐调用点审查后替换（有语义前提）

1. **热路径 `Math.floor` → `x|0`** — 逐调用点确认：(a) 有限数值 (b) Int32 范围 (c) x≥0 或截断可接受。NaN/Infinity 会被静默压成 0
2. **热路径 `Math.abs` → `x<0?-x:x`** — 需确认输入为有限数值
3. **热路径 `Math.min/max` → 三元表达式** — 需确认二元、有限数值、NaN 行为差异可接受
4. **热路径 `==` → `===`** — 需确认不依赖隐式 coercion，或类型已归一化

### P1 — 先 profile 再试点（Tier 2 工程策略）

1. **战斗 tick `getTimer()` 插桩 profiling** — 定位 top-3 耗时阶段
2. 热路径成员访问局部别名化（按 profile 结果优先处理热点函数）
3. DF2 审计（限轻量 helper/ctor，按调用频次排序）
4. 方法调用形态优化（减少调用次数或改 API，不是缓存方法引用）
5. 输入采样集中化（需设计 snapshot 方案，评估采样量）

### P2 — 架构改造（Tier 2，需设计评审）

1. Delegate/回调链收敛 → 固定签名分发器
2. 解析器重构 → 单次前向扫描器
3. 容器策略优化 → ring buffer / head-index（按 workload 选方案）
4. 热路径 `delete` 消除 → active flag / null 置空
5. 属性 miss 预初始化
6. ObjectPool.as 链路审计 → 评估是否需要无 apply/arguments 的轻量池

### P1.5 — NaN 防御体系（已有实测数据，可立即推进）

> 2026-03-13 已完成 AS2 NaN 完全行为测试，确认三大致命偏差（自等性/undefined返回值/>=<=始终true）。

1. **基建层零代价 NaN 守卫**：Ray.as、RayCollider.as、BladeMotionTrailsRenderer.as 的零向量/NaN 守卫修复（0性能代价）
2. **HP 除法短路保护**：SortedUnitCache(8处)、TargetCacheManager(1处) 的 `maxhp > 0 &&` 前置（0性能代价，短路反而省除法）
3. **热路径循环 `<=`/`>=` 审计**：排查所有 `while(x <= y)` / `while(x >= y)` 模式，评估 NaN 死循环风险

### P3 — 长期 / 待验证（Tier 2~3）

1. UI/MC flush 层 + dirty buffer（仅批量读写场景受益）
2. 状态机 → stateId + flat context
3. 配置解析预编译/二进制缓存

---

## 13. 附录：完整基准数据

测试条件：`STD_TOTAL=2,000,000  GC_TOTAL=20,000  STRUCT_TOTAL=400,000  REPEATS=9  WARMUP=3`

### 算术 / 比较 / 位运算

| 测试名 | delta(ms) | per-op(ns) | rel | CV |
|--------|----------|-----------|-----|-----|
| noop_baseline | 0.00 | 0.0 | 0.00x | BASELINE |
| add_int | 38.00 | 19.0 | 1.00x | 0.05 |
| add_float | 65.00 | 32.5 | 1.71x | 0.03 |
| sub_int | 42.00 | 21.0 | 1.11x | 0.05 |
| mul_int | 41.00 | 20.5 | 1.08x | 0.05 |
| div_int | 44.00 | 22.0 | 1.16x | 0.02 |
| mod_int | 52.00 | 26.0 | 1.37x | 0.04 |
| eq_num | 37.00 | 18.5 | 0.97x | 0.05 |
| strict_eq | 41.00 | 20.5 | 1.08x | 0.02 |
| eq_str_num | 208.00 | 104.0 | 5.47x | 0.01 |
| strict_eq_str_num | 37.00 | 18.5 | 0.97x | 0.02 |
| nan_add | 593.00 | 296.5 | 15.61x | 0.00 |
| infinity_mul | 436.00 | 218.0 | 11.47x | 0.01 |

### 调用 / 闭包

| 测试名 | delta(ms) | per-op(ns) | rel | CV |
|--------|----------|-----------|-----|-----|
| call_empty | 970.00 | 485.0 | 25.53x | 0.00 |
| call_onearg | 947.00 | 473.5 | 24.92x | 0.01 |
| call_fiveargs | 1255.50 | 627.8 | 33.04x | 0.00 |
| call_method | 2679.00 | 1339.5 | 70.50x | 0.00 |
| call_empty_df1 | 2158.00 | 1079.0 | 56.79x | 0.00 |
| call_empty_df2 | 1033.00 | 516.5 | 27.18x | 0.01 |
| new_empty_df1 | 3207.00 | 1603.5 | 84.39x | 0.01 |
| new_empty_df2 | 1694.00 | 847.0 | 44.58x | 0.00 |
| closure_read | 2470.00 | 1235.0 | 65.00x | 0.01 |
| closure_deep2 | 2519.00 | 1259.5 | 66.29x | 0.00 |
| arguments_length | 3076.00 | 1538.0 | 80.95x | 0.01 |
| arguments_read | 2612.50 | 1306.3 | 68.75x | 0.00 |

### 字符串

| 测试名 | delta(ms) | per-op(ns) | rel | CV |
|--------|----------|-----------|-----|-----|
| str_length | 1160.00 | 580.0 | 30.53x | 0.01 |
| str_length_as1 | 28.00 | 14.0 | 0.74x | 0.06 |
| str_charat | 1375.00 | 687.5 | 36.18x | 0.01 |
| str_indexof_short_hit | 1418.00 | 709.0 | 37.32x | 0.01 |
| str_split | 2997.00 | 1498.5 | 78.87x | 0.01 |

### 数学

| 测试名 | delta(ms) | per-op(ns) | rel | CV |
|--------|----------|-----------|-----|-----|
| math_floor | 507.00 | 253.5 | 13.34x | 0.01 |
| math_abs | 497.00 | 248.5 | 13.08x | 0.00 |
| math_sin | 529.00 | 264.5 | 13.92x | 0.01 |
| floor_bitor0 | 58.50 | 29.3 | 1.54x | 0.01 |
| cached_math_floor | 283.50 | 141.8 | 7.46x | 0.01 |
| clamp_mathminmax | 1095.00 | 273.8 | 14.41x | 0.01 |
| clamp_ternary | 161.50 | 40.4 | 2.13x | 0.01 |

### 转换

| 测试名 | delta(ms) | per-op(ns) | rel | CV |
|--------|----------|-----------|-----|-----|
| to_bool_num | 386.00 | 193.0 | 10.16x | 0.01 |
| to_bool_doublenot | 55.00 | 27.5 | 1.45x | 0.03 |
| to_number_str | 152.00 | 76.0 | 4.00x | 0.02 |
| number_cast_obj | 2409.00 | 1204.5 | 63.39x | 0.01 |

---

## 参考文件

- [bench_gen_v8.js](bench_gen_v8.js) — 基准测试生成器
- [BenchMain_v8.as](BenchMain_v8.as) — 生成的 AS2 测试主文件
- [manifest_v8.json](manifest_v8.json) — 测试项清单
- [BytecodeProbe.md](BytecodeProbe.md) — JPEXS P-code 反汇编记录
- [BytecodeProbe_Guide.md](BytecodeProbe_Guide.md) — 反汇编操作指南
- [AS2_NaN陷阱总结.md](AS2_NaN陷阱总结.md) — NaN 感染与防御
