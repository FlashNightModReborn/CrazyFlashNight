# AS2 反幻觉约束

> 本文档约束 LLM 在编写 ActionScript 2.0 代码时避免 JavaScript / AS3 语法幻觉。
> 编写或审查任何 AS2 代码前**必读**此文档。

---

## 0. 文件编码：UTF-8 with BOM（最高优先级）

Flash CS6（AS2 最高支持版本）要求 `.as` 文件使用 **UTF-8 with BOM** 编码，**不支持普通 UTF-8**。BOM 头丢失会导致编译失败或中文乱码。

### Agent 操作 .as 文件的安全流程
1. **新建文件**：先复制一个已有的 `.as` 文件，重命名，再修改内容（保留 BOM 头）
2. **大范围编辑**：大规模修改同一个文件可能触发工具重新生成文件内容，同样会丢失 BOM 头。如发生此情况，按上述复制流程重新操作
3. **绝对不要**使用 Write 工具从零创建 `.as` 文件（无法保证 BOM 头）

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
- 深度管理是手动的（本项目有基于 AVL 树的 DepthManager.as，但尚未投入使用，性能测试未通过）
- **`gotoAndStop`/`gotoAndPlay` 会立即卸载当前帧的 MovieClip**。如果调用链处于即将被卸载的 MC 的 `onEnterFrame` 中，`gotoAndStop` 之后的代码**不会执行**——调用者的执行上下文被销毁了。这在现代语言中没有对应概念，极易踩坑
  - 本项目的解决方案：状态切换作业机制（`__stateTransitionJob`），将 `gotoAndStop` 后需要执行的逻辑封装为作业对象，由状态改变函数在帧跳转后统一调度。参见 `scripts/引擎/引擎_fs_路由基础.as`
  - **编码规则**：在 MovieClip 的 `onEnterFrame` 等回调中触发帧跳转时，不要在 `gotoAndStop` 之后写任何依赖当前 MC 存活的逻辑

---

## 2. AS2 vs JavaScript 易混淆点

### 空值访问与判空
- **AS2 非常宽容，不需要判空**。访问 `undefined.prop` 返回 `undefined` 而不会崩溃
- 对于 `a.b.c.d` 链式访问，**直接一步到位**，不要逐级判空检查
- 虚拟机已为宽容性付出了性能代价，额外的判空检查只会雪上加霜
- **禁止**写出 `if (a != undefined && a.b != undefined && a.b.c != undefined)` 这种防御式代码

### 作用域与 this
- AS2 `var` 有函数作用域（类似 JS），无 `let`/`const`
- AS2 方法中 `this` 指向调用者，但回调中 `this` 容易丢失
- 绑定 `this` 的方式：`org.flashNight.neur.Event.Delegate` 可用，但实践中闭包更常用（`var self = this;`）

### 原型链
- AS2 类底层基于原型链继承
- `__proto__` 可访问和修改（本项目有原型链注入的性能研究）
- AS2 的 `extends` 编译后等价于原型链设置
- **用对象做字典时必须先断开原型链**（`obj.__proto__ = null`），否则 `for...in` 会遍历到原型属性，属性查找也会沿原型链上溯产生意外命中
- **`for...in` 遍历顺序是稳定的**（Ruffle 项目验证的结论）：
  1. 原型链属性优先枚举
  2. 自身属性按**最后插入的最先枚举**（reverse insertion order）
  3. DisplayObject 子对象按 depth 从高到低
  4. 删除属性后顺序仍然稳定

### 对象字面量与键名
- AS2 对象字面量的键名**不加引号**：`{name: "sword", damage: 10}`
- 现代 JS 中常见的 `{"name": "sword"}` 写法在 AS2 中虽然不报错，但**不是惯用风格**，应避免
- 当键名包含特殊字符、空格或与保留字冲突时，字面量语法无法直接声明，需改用括号记法动态赋值：
  ```actionscript
  var obj = {};
  obj["lt"] = 5;        // 保留字作键名
  obj["my-key"] = 10;   // 含连字符的键名
  ```
- 读取同理：`obj["lt"]` 可行，`obj.lt` 会被编译器解析为运算符而报错（详见「Flash 4 遗留保留字」一节）

### 不存在的语法/API
<!-- TODO: 从实际编码经验中持续补充 -->
- `===` / `!==` **存在**（勿误标为不存在）
- `>=` / `<=` 实现为朴素的 `!(<)` / `!(>)`，**不是独立比较**。当涉及 NaN 时行为尤其危险：`NaN < x` 为 false，因此 `NaN >= x` 为 true。处理可能为 NaN 的值时必须先显式检查 `isNaN()`
- 无原生 `Array.forEach`/`map`/`filter`/`reduce`（需手写循环）。本项目 `org.flashNight.gesh.array.ArrayUtil` 提供了类似方法，**仅限测试套件中使用**，工程代码中不推荐（性能损耗不低）
- 无原生 `JSON.parse`/`JSON.stringify`。本项目自实现了三套 JSON 解析器（均在 `scripts/类定义/` 下）：
  - `JSON.as` — 通用版，功能完整
  - `FastJSON.as` — 更快，带缓存（详见 `FastJSON.md`）
  - `LiteJSON.as` — 当前使用，砍掉了工程确定不必要的功能以换取精简（详见 `LiteJSON.md`）
  - `IJSON.as` — JSON 解析器接口
- 无原生 `Promise`/`async`/`await`。本项目有自实现的 `org.flashNight.aven.Promise.Promise`，但**尚未完工**，暂勿使用
- `try...catch...finally` 语法存在且可用，但**工程契约禁止在生产代码中使用**（性能损耗大，参阅 `scripts/优化随笔/异常兜底措施的性能评估与优化.md`）。测试套件中允许使用
- 无模板字符串（`` ` ``），只能用 `+` 拼接。**不要用 `Array.join()` 替代**，实测远慢于裸 `+` 拼接（参阅 `scripts/优化随笔/字符串性能评估.md`）
- 无 `Number.toFixed()`/`Number.toPrecision()`/`Number.toExponential()`。AS2 的 Number 没有这些格式化方法，需手写：`Math.round(x * 100) / 100` 或自定义格式化函数
- 无解构赋值 `[a, b] = [1, 2]`
- 无原生展开运算符 `...args`。本项目 `org.flashNight.gesh.arguments` 包有相关实现，但底层基建基本手写展开以保证性能

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

**规避方式**：
- 命名时避开上述 12 个词，如用 `greaterThan` / `lessThan` 代替 `gt` / `lt`
- 括号记法 `obj["lt"]` 可绕过编译器（字符串字面量不被解析为运算符），但**点记法 `obj.lt` 会报错**

---

## 3. AS2 在本项目中的惯用法

### _root 与全局访问
- `_root` 指向主时间轴，是 AS2 项目的全局入口
- 本项目中 `_root` 级挂载函数与 class 类并存：需要提供给子资源 SWF 使用的功能**必须通过 `_root` 挂载**，这是子 SWF 全局访问主 SWF 功能的唯一途径
- **挂载建议**：新增挂载函数应通过二级属性分组（如 `_root.服务器.发布服务器消息`），避免直接在 `_root` 上堆积大量一级属性导致索引膨胀
- `_global` 用于真正的全局变量

### 文件包含与宏
- `#include "path/to/file.as"` — 预处理器指令，编译时文本替换
- 与 `import` 不同，`#include` 是源码级别的内联
- **宏文件位置**：`scripts/macros/`
- **⚠ #include 路径基准**：路径是相对于 `.fla` 项目设置的类路径（本项目为 `scripts/`），**不是相对于当前 .as 文件**。因此无论 class 文件在包结构中的深度如何，引用宏都只需要一层 `../`，例如 `#include "../macros/SOME_MACRO.as"`。这是高频错误点，切勿按文件系统相对路径计算层级

### 调试
- **`trace()`**：编译时可自动剔除，**可在热路径中使用**，是热路径调试的首选
- **`_root.发布消息(...)`**：轻量级游戏内消息输出
- **`_root.服务器.发布服务器消息(...)`**：重量级，通过服务器记录日志
  - 后两者均支持**无限参数自动拼接**，不需要手动用 `+` 拼接字符串
  - 后两者在热路径中完成测试任务后**必须注释掉**（不会被编译剔除，有运行时开销）

---

## 4. 常见幻觉速查表

| 幻觉写法 | 正确 AS2 写法 | 来源 |
|-----------|--------------|------|
| `addEventListener("click", handler)` | `mc.onPress = handler` | AS3 |
| `new Sprite()` | `mc.createEmptyMovieClip(name, depth)` | AS3 |
| `package { }` | 无，路径由目录结构决定 | AS3 |
| `const X:int = 1` | `var X:Number = 1`（或 `static var`） | AS3/JS |
| `array.push(...items)` | `array.push(item)` 逐个添加 | JS |
| `for (var i of arr)` | `for (var i = 0; i < arr.length; i++)` | JS |
| `for (var k in obj)` | 可用，遍历顺序**稳定**（见下文） | — |
| `obj?.prop` | 直接 `obj.prop`（AS2 对 undefined 访问不崩溃，无需判空） | JS |
| `JSON.parse(str)` | 自定义解析或 XML 解析 | JS |
| `setTimeout`/`setInterval` | 可用但一般不用，优先用帧计时器或 `EnhancedCooldownWheel` | 惯例 |
| `var gt:Number` / `obj.lt` | 避开 `eq ne lt gt le ge and or not add` 等 Flash 4 保留字 | AS1 遗留 |
| `n.toFixed(2)` | `Math.round(n * 100) / 100` 或自定义函数 | JS |
| `{"key": value}` 对象字面量 | `{key: value}` 键名不加引号；保留字/特殊键用 `obj["key"]` | JS 习惯 |
| `(cond ? 1 : 0)` 显式布尔转数值 | 直接使用比较结果参与算术运算，AVM1 硬连线 Boolean→Number 快速路径 | 现代语言习惯 |
| 拆分 `arr[--j+2]=tmp` 为 `arr[j+1]=tmp; j--;` | 保持副作用合并写法，触发 AVM1 StoreRegister 寄存器快速路径 | "代码整洁"直觉 |
| 批量拷贝用 `arr[d++]` | 4 路展开用偏移寻址 `arr[d+k]...d+=4`（3 vs 4 字节码/次） | 现代语言习惯 |

---

## 5. 持续更新机制

此文档应在每次会话的自优化环节中检查更新：
- 发现新的幻觉模式时，添加到速查表
- 在实际编码中验证的 AS2 行为差异，补充到对应章节
- 参阅 `agentsDoc/self-optimization.md` 了解更新流程
