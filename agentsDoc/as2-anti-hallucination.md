# AS2 反幻觉约束

## Quick Sheet（速查）

- **.as 编码**：必须 UTF-8 with BOM；禁止从零新建，必须复制现有文件再改名（帧脚本 `.as` 同样适用——丢 BOM 会被编译器**静默跳过**且不报错）
- **禁止 `package`**：AS2 无此关键字，类名需全路径 `class org.flashNight...ClassName {}`
- **帧脚本 import**：必须通配符 `import org.flashNight.xxx.*`，禁止具体类导入
- **类型**：无 `int`/`uint`（用 `Number`）、无 `Vector.<T>`（用 `Array`）、无 `const`（用 `var`/`static var`）
- **事件**：无 `addEventListener`，用回调赋值 `mc.onPress = handler`
- **显示对象**：无 `Sprite`/`Stage`，核心是 `MovieClip`
- **禁用 API**：无 `JSON.parse`（用 `LiteJSON`）、无 `setTimeout`（用帧计时器）、无 `Promise`、无模板字符串、无解构
- **保留字陷阱**：`eq/ne/lt/gt/le/ge/and/or/not/add` 是保留字，命名避开，键名用 `obj["lt"]`
- **字典对象**：仅限封闭内部字典可 `obj.__proto__ = null`；凡会泄露到模块边界的数据/配置对象保持普通 `Object`
- **proto-null 判空**：对断原型对象禁用 `== null` / `!= null` / `== undefined` / `!= undefined`
- **`try...catch`**：生产代码禁用（性能损耗大），测试中允许
- **`#include` 路径**：基准是 `.fla` 类路径（`scripts/`），引用宏统一用 `#include "../macros/XXX.as"`

---

## 0. 文件编码：UTF-8 with BOM（最高优先级）

`.as` 文件必须使用 **UTF-8 with BOM** 编码。BOM 头丢失的三种后果（按可见性排序）：

1. class 文件 BOM 丢失：编译报错或中文乱码（**明显**，IDE 会报）
2. **被 FLA 帧脚本 `#include` 的 `.as` 丢 BOM**：编译器**静默跳过**其全部内容，生成 SWF 的对应 DoAction 为 0 字节，**compiler_errors 仍报 `0 个错误`**，smoke 链路无法捕获。诊断步骤见 [`scripts/FlashCS6自动化编译.md`](../scripts/FlashCS6自动化编译.md) §8 "marker 已生成但 flashlog.txt 为空"
3. 中文字符串 BOM 缺失 + 多字节序列被工具截断：运行时显示 fffd

### Agent 操作 .as 文件的安全流程
1. **新建文件**：先复制一个已有的 `.as` 文件，重命名，再修改内容（保留 BOM 头）
2. **大范围编辑**：大规模修改同一个文件可能触发工具重新生成文件内容，同样会丢失 BOM 头。如发生此情况，按上述复制流程重新操作
3. **禁止从零新建** `.as` 文件（无法保证 BOM 头）；必须复制现有文件再改名
4. **TestLoader.as 等帧脚本 `.as` 同样在 BOM 约束内**——它们不是 class 文件但仍被编译器读取，丢 BOM 触发上述第 2 种静默失败
5. **批量替换大段内容时的字节级 fallback**：复制源文件后如需把整个 class body 改写成 runner / 小型帧脚本，直接 Edit 整文件有 BOM 丢失风险。改用字节级写入：取源文件前 3 字节（已确认是 BOM）+ 新内容的 UTF-8 字节，调 `[System.IO.File]::WriteAllBytes($path, $bom + $contentBytes)`。**`Out-File -Encoding utf8` / `Set-Content -Encoding utf8` 等高层 cmdlet 在 PS5.1 上不可靠**（BOM 写入歧义），只有 `WriteAllBytes` 字节级 API 才保证 BOM 字节序。验证：`[System.IO.File]::ReadAllBytes($path)[0..2]` 应为 `EF BB BF`。2026-05-29 用此法在 `scripts/TestLoader.as` 上端到端验证过 117/117 测试通过

---

## 1. AS2 vs AS3 关键差异

### 类声明与包系统
- AS2 无 `package` 关键字，类的包路径由文件系统目录结构决定
- AS2 类声明：`class org.flashNight.arki.bullet.Factory.BulletFactory { }`
- AS3 幻觉：~~`package org.flashNight.arki.bullet.Factory { class BulletFactory {} }`~~
- AS2 导入：`import org.flashNight.arki.bullet.Factory.BulletFactory;`
- AS2 支持通配符导入：`import org.flashNight.arki.bullet.Factory.*;`
- **非 class 的 .as 文件（帧脚本等）必须使用通配符导入**：这些文件通过 `#include` 拼接为巨型上下文，明确导入具体 class 可能与其他一起 `#include` 的 .as 文件产生导入冲突，只能使用 `.*` 通配符形式

### 类型系统
- AS2 类型注解使用冒号后置：`var x:Number = 0;`
- AS2 无 `int`/`uint` 类型，只有 `Number`
- AS2 无 `Vector.<T>` 泛型，只有 `Array`
- AS2 函数返回类型：`function foo():String { }` 或 `function foo():Void { }`
- **AS2 类型系统只做编译期检查，不做运行时约束**。运行时可以给任何变量赋任何类型的值
  - 工程契约：除非有明确理由，**必须按强类型编写**，将错误提前到编译期
  - 测试场景：使用 mock 对象时可能因类型不匹配导致编译不过，此时可用无类型（省略类型注解）绕过编译

### 事件系统
- AS2 **不存在** `addEventListener` / `removeEventListener`
- AS2 事件处理使用回调赋值：`mc.onPress = function() { }`
- AS2 事件处理使用 `on()` / `onClipEvent()` 块（帧脚本中）
- 本项目自定义事件系统位于：`org.flashNight.neur/`（参阅 game-systems.md）

### 显示对象
- AS2 无 `Sprite`、`DisplayObject`、`Stage`（这些是 AS3 概念）
- AS2 核心显示对象是 `MovieClip`
- 创建子 MC：`parentMC.createEmptyMovieClip("name", depth)`
- 附加库元件：`parentMC.attachMovie("linkageId", "name", depth)`
- 深度管理由 `DepthManager.as`（Twip Trick 模运算）统一管理，已全面投入使用。核心公式 `depth = bandLow + int((Y-yMin)*S)*N + entityID`，零碰撞保证。帧脚本的 `swapDepths` 被劫持到 `DepthManager.updateDepth`，调用方无需手动管理深度
- **`gotoAndStop`/`gotoAndPlay` 会立即卸载当前帧的 MovieClip**，调用链处于被卸载 MC 的 `onEnterFrame` 中时，帧跳转后的代码**不会执行**（执行上下文被销毁）
  - 本项目解决方案：`__stateTransitionJob` 作业机制，帧跳转后统一调度（参见 `scripts/引擎/引擎_fs_路由基础.as`）
  - **编码规则**：帧跳转后不要写依赖当前 MC 存活的逻辑

---

## 2. AS2 vs JavaScript 易混淆点

### 空值访问与判空
- AS2 `undefined.prop` 返回 `undefined` 不崩溃。链式 `a.b.c.d` 直接访问，**禁止逐级判空**
- **禁止**：`if (a != undefined && a.b != undefined && a.b.c != undefined)`

### 作用域与 this
- AS2 `var` 有函数作用域（类似 JS），无 `let`/`const`
- AS2 方法中 `this` 指向调用者，但回调中 `this` 容易丢失
- 绑定 `this` 的方式：`org.flashNight.neur.Event.Delegate` 可用，但实践中闭包更常用（`var self = this;`）

### 帧脚本闭包陷阱（asLoader 架构）
- 帧脚本通过 `#include` 注入 asLoader 的 as链接影片剪辑，加载完成后该 MovieClip 被 `removeMovieClip()` 移除
- **移除后帧脚本的 activation object 被回收**，闭包捕获的所有局部变量变为 `undefined`
- **禁止**：在帧脚本中创建需要持久存在的闭包（`addProperty` / `setTimeout` / `EventBus` 回调）并捕获局部变量
- **正确做法**：将需要持久闭包的逻辑放在 class 方法中（class 方法的 activation object 独立于 MovieClip 生命周期），帧脚本只做同步初始化调用
- 示例：`ws.setupLegacyBridge()` 在 class 方法内用 `var self = this` 创建 `addProperty` 闭包，而非在帧脚本中用局部变量 `ws` 创建
- **2026-06 塌缩后**：asLoader 已从 82 帧塌成**单帧**（架构导览见 [docs/asLoader-README.md](../docs/asLoader-README.md)）。单帧仍在 handoff 后被移除，故上述陷阱不变；`BootSequencer`（class + 挂 `_root` 的 `onEnterFrame` tick clip）即「持久闭包 / 异步逻辑住 class」的范本——握手 / loader 队列 / await 全在类里，单帧只做同步 `#include` 调用。

### AVM1 静默失败陷阱（塌缩暴露：编译 0 错但运行时坏）
- **「未定义类.方法()」静默返回 `undefined` 不抛错**：eager 自单例 `public static var instance:X = new X();` 在**类注册期**就构造；若构造里调用**另一尚未注册的类**（如 `Delegate.create1(...)`），AVM1 静默返回 undefined → 该字段变 undefined、其余构造照跑（极隐蔽，无报错，只在很久后表现为功能缺失）。**通用律：eager 自单例构造勿做跨类调用**；改在首次真正使用时（晚于 boot）惰性绑定。实例 = 刀光渐隐 bug（`VectorAfterimageRenderer._fadeCallback`），详 [BootSequencer 构建标准 §0](../docs/asLoader-BootSequencer-构建标准-2026-06-16.md)。
- **AVM1 单函数体 ≤64KB**：`DefineFunction2.codeSize` 是 UI16。把大段帧脚本 wrap 进单个 `function(){}` 超限会**编译 0 错却静默产坏函数**（从不执行）；帧脚本 DoAction 是 UI32 无此限。检测门 = `tools/swf-function-sizes.js`（无需真机即拦溢出）。

### 原型链
- AS2 类底层基于原型链继承
- `__proto__` 可访问和修改（本项目有原型链注入的性能研究）
- AS2 的 `extends` 编译后等价于原型链设置
- **仅当对象被当作内部字典/哈希表使用时，才断开原型链**（`obj.__proto__ = null`），否则 `for...in` 会遍历到原型属性，属性查找也会沿原型链上溯产生意外命中
- **凡会泄露到模块边界的数据结果禁止默认断链**：包括 JSON 解析结果、配置对象、加载器返回值、跨模块传递对象；必须保持普通 `Object`，兼容 `:Object` 形参、`!= null`、`hasOwnProperty`、`constructor` 等工程约定
- **需要 proto-null 字典时在消费端显式创建**，不要让解析器为所有对象统一断链；`LiteJSON.parse()` 返回普通对象
- **`proto-null` 对象的 loose equality 会退化**：实测 `obj == null` 与 `obj == undefined` 都可能返回 `true`，但 `===` 仍正常，自有属性与 `for...in` 仍可用；详见 [AS2 中 proto-null 对象的相等性退化与工程边界](../scripts/优化随笔/AS2%20中%20proto-null%20对象的相等性退化与工程边界.md)
- **`for...in` 遍历顺序是稳定的**（Ruffle 项目验证）：原型链属性优先 → 自身属性按 reverse insertion order → DisplayObject 子对象按 depth 降序。删除属性后顺序仍稳定

### 对象字面量与键名
- 键名**不加引号**：`{name: "sword", damage: 10}`（`{"name": ...}` 虽不报错但非惯用风格）
- 保留字/特殊字符键名用括号记法：`obj["lt"] = 5`（点记法 `obj.lt` 会被解析为运算符而报错，详见「Flash 4 遗留保留字」）

### 不存在的语法/API
- `===` / `!==` **存在**（勿误标为不存在）
- `>=`/`<=` 实现为 `!(<)`/`!(>)`，NaN 时行为危险：`NaN >= x` 为 true（因为 `NaN < x` 返回 **undefined** 而非 false，`!(undefined)` = true）。**优先用 `>`/`<` 严格不等式**可自然过滤 NaN（返回 undefined→falsy），比 `>=`/`<=` 更安全。**`while(i <= NaN)` 会死循环！**
- `NaN == NaN`（同一变量）返回 **true**（违反 IEEE 754）。`x != x` 不能用作 NaN 检测。用 `isNaN(x)` 或 `(x - x) != 0`（后者同时检测 Infinity，且性能更优~39ns vs ~184ns）
- `Number(null)` / `Number("")` / `Number(" ")` 返回 **NaN**（标准 JS 返回 0），`isNaN(null)` 返回 true
- `null == undefined` 为 true（与 JS 一致），`if (x != null)` 可同时排除 null 和 undefined
- 无原生 `Array.forEach`/`map`/`filter`/`reduce`（需手写循环）。`gesh.array.ArrayUtil` 提供类似方法，**仅限测试套件使用**
- 无原生 `JSON.parse`/`JSON.stringify`。本项目三套实现（`scripts/类定义/` 下）：`JSON.as`（通用）、`FastJSON.as`（带缓存）、**`LiteJSON.as`**（当前使用，最精简）、`IJSON.as`（接口）
- 无原生 `Promise`/`async`/`await`。`aven.Promise.Promise` 尚未完工，暂勿使用
- `try...catch...finally` 存在但**生产代码禁用**（性能损耗大）。测试中允许
- 无模板字符串，只能用 `+` 拼接（**不要用 `Array.join()`**，远慢于 `+`）
- 无 `Number.toFixed()` 等，需手写：`Math.round(x * 100) / 100`
- 无解构赋值、无原生展开运算符 `...args`
- 无 `System.totalMemory`/`System.freeMemory`：内存自省是 AS3 `flash.system.System` 独有；AVM1 的 `System` 只有 `capabilities`/`security`/`setClipboard` 等，**运行时读不到内存占用**（实测：写 `System.totalMemory` 直接编译报错）

### Flash 4 遗留保留字（命名陷阱）

AS1/Flash 4 时代的运算符关键词在 AS2 中仍是**保留字**，用作变量名、函数名、属性名会导致编译报错。这些词看起来像普通英文缩写，极易踩坑：

**10 个运算符关键词**（全部小写）：

| 保留字 | Flash 4 原义 | AS2 替代 |
|--------|-------------|---------|
| `eq` | 字符串相等 | `==` |
| `ne` | 字符串不等 | `!=` |
| `lt` | 字符串小于 | `<` |
| `gt` | 字符串大于 | `>` |
| `le` | 字符串小于等于 | `<=` |
| `ge` | 字符串大于等于 | `>=` |
| `and` | 逻辑与 | `&&` |
| `or` | 逻辑或 | `\|\|` |
| `not` | 逻辑非 | `!` |
| `add` | 字符串拼接 | `+` |

**2 个废弃语句关键词**：`tellTarget`、`ifFrameLoaded`

**规避方式**：命名时避开上述 12 个词（如用 `greaterThan` 代替 `gt`）；括号记法 `obj["lt"]` 可绕过编译器

---

## 3. AS2 在本项目中的惯用法

### _root 与全局访问
- `_root` 指向主时间轴，是 AS2 项目的全局入口
- 本项目中 `_root` 级挂载函数与 class 类并存：需要提供给子资源 SWF 使用的功能**必须通过 `_root` 挂载**，这是子 SWF 全局访问主 SWF 功能的唯一途径
- **挂载建议**：新增挂载函数应通过二级属性分组（如 `_root.服务器.发布服务器消息`），避免直接在 `_root` 上堆积大量一级属性导致索引膨胀
- `_global` 用于真正的全局变量

### 文件包含与宏
- `#include "path/to/file.as"` — 预处理器指令，编译时源码级内联（非 `import`）
- **宏文件位置**：`scripts/macros/`
- **⚠ #include 路径基准**是 `.fla` 类路径（`scripts/`），**非当前文件路径**。引用宏统一用 `#include "../macros/XXX.as"`（一层 `../`），勿按文件系统层级计算

### 调试
- **`trace()`**：发布设置勾选「省略 trace 语句」后零开销（编译产物完全剔除），可在热路径中自由使用
- **`_root.发布消息(...)`**（轻量）/ **`_root.服务器.发布服务器消息(...)`**（服务器日志）：有运行时开销，热路径测试完毕后**必须注释掉**

---

## 4. 常见幻觉速查表

| 幻觉写法 | 正确 AS2 写法 |
|-----------|--------------|
| `addEventListener("click", handler)` | `mc.onPress = handler` |
| `new Sprite()` | `mc.createEmptyMovieClip(name, depth)` |
| `package { }` | 无，路径由目录结构决定 |
| `const X:int = 1` | `var X:Number = 1`（或 `static var`） |
| `array.push(...items)` | `array.push(item)` 逐个添加 |
| `for (var i of arr)` | `for (var i = 0; i < arr.length; i++)` |
| `obj?.prop` | 直接 `obj.prop`（AS2 不崩溃） |
| `JSON.parse(str)` | 自定义解析或 XML 解析 |
| `setTimeout`/`setInterval` | 优先用帧计时器或 `EnhancedCooldownWheel` |
| `var gt:Number` / `obj.lt` | 避开 Flash 4 保留字（§2 详述） |
| `n.toFixed(2)` | `Math.round(n * 100) / 100` |
| `{"key": value}` | `{key: value}`；保留字键用 `obj["key"]` |

> 注：AVM1 性能相关的编码惯例（布尔转数值快速路径、StoreRegister 副作用压行、偏移寻址展开等）见 [as2-performance.md](as2-performance.md) 优化决策快查表。

---

## 5. 实测档案与持续更新

AS2/AVM1 是冷门运行时，官方语言参考停在 Flash 8 且不再更新，模型训练数据稀薄、
常常过时。**凡 LLM 易凭训练数据臆断、而真相只能靠实测确定的运行时黑箱细节，
沉淀为独立实测档案**——这类档案对本项目的工程价值高于一般文档，因为它是该话题
唯一可靠的信源。本文只留指针：

- [AS2 / AVM1 BitmapData 尺寸上限与 API 黑箱实测](../scripts/优化随笔/AS2-BitmapData-尺寸上限实测.md)
  —— `BitmapData` 无 2880 / 8191 / 16,777,215 硬墙（官方文档过时），约束是内存；
  失败形态分「挂死」与「clean null」，`null` 检查挡不住 OOM；
  `getPixel32` 有符号、alpha=0 fillColor 致 setPixel 失效、`getColorBoundsRect`
  AVM1 恒空等 API 陷阱。
- [AS2 中 proto-null 对象的相等性退化与工程边界](../scripts/优化随笔/AS2%20中%20proto-null%20对象的相等性退化与工程边界.md)
  —— 见上文 §2「原型链」。

发现新幻觉模式或验证 AS2 行为差异时：颗粒小的结论直接补进本文对应章节；
成体系的实测专题另开档案、并在本节登记指针。流程见 [self-optimization.md](self-optimization.md)。
