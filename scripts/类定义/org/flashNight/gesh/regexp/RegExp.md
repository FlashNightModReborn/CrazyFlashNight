### 正则表达式引擎使用指南

#### 概述

**org.flashNight.gesh.regexp** 是一个纯 AS2 实现的正则表达式引擎，采用递归下降解析器生成 AST，再通过回溯 NFA 进行匹配。支持大部分常用正则语法，可在 Flash Player 8+ / AVM1 环境下运行。

**架构**：`Parser`（词法/语法分析）→ `ASTNode`（AST 节点 + 匹配引擎）→ `RegExp`（用户接口）

**架构边界**：
- 优势：分组、断言、捕获结果、替换模板等 ECMAScript 风格语义都可以在现有 AST 框架内继续扩展
- 约束：当前仍是回溯型引擎，最坏情况下仍可能出现灾难回溯；后顾断言只支持固定长度模式

---

### 目录

1. [创建正则表达式对象](#1-创建正则表达式对象)
2. [标志（Flags）](#2-标志flags)
3. [字符匹配](#3-字符匹配)
4. [量词（Quantifiers）](#4-量词quantifiers)
5. [分组与捕获](#5-分组与捕获)
6. [逻辑或操作符 `|`](#6-逻辑或操作符-)
7. [锚点（Anchors）](#7-锚点anchors)
8. [环视（Lookaround）](#8-环视lookaround)
9. [单词边界](#9-单词边界)
10. [反向引用](#10-反向引用)
11. [特殊字符与转义](#11-特殊字符与转义)
12. [String.prototype 注入方法](#12-stringprototype-注入方法)
13. [常用正则表达式实例](#13-常用正则表达式实例)
14. [回溯机制与性能](#14-回溯机制与性能)
15. [调试与常见错误](#15-调试与常见错误)
16. [特性支持总表](#16-特性支持总表)

---

### 1. 创建正则表达式对象

```actionscript
import org.flashNight.gesh.regexp.*;

var regex:RegExp = new RegExp(pattern:String, flags:String);
```

- **pattern**：正则表达式模式字符串（注意 AS2 字符串中 `\` 需要双写为 `\\`）
- **flags**：修饰符组合字符串

**示例**：
```actionscript
var regex:RegExp = new RegExp("\\d+", "gi");
```

实例公开属性：

```actionscript
var re:RegExp = new RegExp("abc", "im");
trace(re.source);    // "abc"
trace(re.flags);     // "im"
trace(re.lastIndex); // 0
```

---

### 2. 标志（Flags）

| 标志 | 名称 | 说明 |
|------|------|------|
| `i` | ignoreCase | 忽略大小写匹配 |
| `g` | global | 全局匹配，`exec()` 从 `lastIndex` 继续 |
| `m` | multiline | 多行模式，`^` `$` 匹配行首/行尾（`\n` 分隔） |
| `s` | dotAll | `.` 匹配包括换行符 `\n` 在内的所有字符 |

**示例**：
```actionscript
// 多行模式
var re:RegExp = new RegExp("^abc", "m");
re.test("xyz\nabc");  // true — ^ 匹配第二行行首

// dotAll 模式
var re2:RegExp = new RegExp("a.b", "s");
re2.test("a\nb");  // true — . 匹配 \n
```

---

### 3. 字符匹配

#### 3.1 字面量字符

直接匹配字符本身。特殊字符需转义：`. ^ $ * + ? { } [ ] ( ) | \`

#### 3.2 任意字符 `.`

匹配除 `\n` 外的任意字符（开启 `s` 标志后匹配所有字符）。

#### 3.3 字符集 `[...]`

```actionscript
var re:RegExp = new RegExp("[a-z]+", "");    // 小写字母
var re2:RegExp = new RegExp("[A-Za-z0-9]", ""); // 字母数字
```

- 支持范围：`[a-z]`、`[0-9]`、`[\x30-\x39]`
- 支持预定义类混用：`[\d\D]`、`[a\W]`
- 否定字符集：`[^abc]` 匹配不在集合内的字符

#### 3.4 预定义字符类

| 语法 | 说明 | 反义 |
|------|------|------|
| `\d` | 数字 `[0-9]` | `\D` |
| `\w` | 单词字符 `[A-Za-z0-9_]` | `\W` |
| `\s` | 空白符（空格、`\t`、`\n`、`\r`、`\f`、`\v`） | `\S` |

在字符集内同样可用：`[\D]+` 匹配非数字字符串。

#### 3.5 十六进制与 Unicode 转义

```actionscript
var re:RegExp = new RegExp("\\x41\\x42\\x43", "");  // 匹配 "ABC"
var re2:RegExp = new RegExp("[\\x30-\\x39]+", "");   // 匹配数字（字符集内也支持）
var re3:RegExp = new RegExp("\\u4e2d\\u6587", "");   // 匹配 "中文"
```

---

### 4. 量词（Quantifiers）

#### 4.1 贪婪量词

| 语法 | 说明 |
|------|------|
| `*` | 0 次或多次 |
| `+` | 1 次或多次 |
| `?` | 0 次或 1 次 |
| `{n}` | 恰好 n 次 |
| `{n,}` | 至少 n 次 |
| `{n,m}` | n 到 m 次（n ≤ m） |

#### 4.2 非贪婪量词

在量词后加 `?` 变为非贪婪，尽可能少匹配：

```actionscript
var re:RegExp = new RegExp("<.*?>", "");
var m:Array = re.exec("<div>content</div>");
trace(m[0]);  // "<div>" — 非贪婪，匹配最短
```

#### 4.3 回溯说明

量词在 Sequence 中支持跨兄弟回溯。当贪婪量词消耗过多导致后续节点失败时，引擎自动减少匹配次数重试。对 `Group(Quantifier)` 结构（如 `([\w.-]+)`）同样有效。

---

### 5. 分组与捕获

#### 5.1 捕获组 `(...)`

```actionscript
var re:RegExp = new RegExp("(\\d{4})-(\\d{2})-(\\d{2})", "");
var m:Array = re.exec("2026-03-11");
trace(m[0]);  // "2026-03-11" — 完整匹配
trace(m[1]);  // "2026" — 捕获组 1
trace(m[2]);  // "03"   — 捕获组 2
trace(m[3]);  // "11"   — 捕获组 3
trace(m.index); // 0    — 匹配起始位置
```

#### 5.2 非捕获组 `(?:...)`

只分组不捕获，不占用编号：

```actionscript
var re:RegExp = new RegExp("(?:abc)+", "");
re.test("abcabc");  // true
```

#### 5.3 嵌套分组

```actionscript
var re:RegExp = new RegExp("(ab(c|d))+", "");
re.test("abcabd");  // true
```

#### 5.4 命名捕获组 `(?<name>...)`

```actionscript
var re:RegExp = new RegExp("(?<year>\\d{4})-(?<month>\\d{2})-(?<day>\\d{2})", "");
var m:Array = re.exec("2026-03-11");

trace(m[1]);           // "2026"
trace(m.groups.year);  // "2026"
trace(m.groups.month); // "03"
trace(m.groups.day);   // "11"
```

- 命名组同时保留编号捕获和 `groups` 对象访问
- `groups` 是普通 `Object`
- 当前不主动拒绝重复组名；如果重复命名，`groups` 中后出现的同名键会覆盖前者，建议避免重复命名

---

### 6. 逻辑或操作符 `|`

```actionscript
var re:RegExp = new RegExp("cat|dog|bird", "");
re.test("dog");  // true
re.test("fish"); // false
```

支持在分组内使用：`(true|false)`

---

### 7. 锚点（Anchors）

| 语法 | 说明 |
|------|------|
| `^` | 字符串/行首（`m` 标志下匹配 `\n` 后的位置） |
| `$` | 字符串/行尾（`m` 标志下匹配 `\n` 前的位置） |

```actionscript
var re:RegExp = new RegExp("^hello$", "");
re.test("hello");       // true
re.test("say hello");   // false

// 多行模式
var re2:RegExp = new RegExp("^abc$", "m");
re2.test("xyz\nabc\n123");  // true
```

---

### 8. 环视（Lookaround）

#### 8.1 正向前瞻 `(?=...)`

匹配位置后面是指定模式，不消耗字符：

```actionscript
var re:RegExp = new RegExp("foo(?=bar)", "");
re.test("foobar");  // true
re.test("foobaz");  // false
```

#### 8.2 负向前瞻 `(?!...)`

匹配位置后面**不是**指定模式：

```actionscript
var re:RegExp = new RegExp("foo(?!bar)", "");
re.test("foobaz");  // true
re.test("foobar");  // false
```

#### 8.3 正向后顾 `(?<=...)`

匹配位置前面是指定模式（**要求固定长度**）：

```actionscript
var re:RegExp = new RegExp("(?<=foo)bar", "");
re.test("foobar");  // true
re.test("bazbar");  // false
```

#### 8.4 负向后顾 `(?<!...)`

匹配位置前面**不是**指定模式（**要求固定长度**）：

```actionscript
var re:RegExp = new RegExp("(?<!foo)bar", "");
re.test("bazbar");  // true
re.test("foobar");  // false
```

> **限制**：后顾断言要求模式为固定长度（不能包含 `*`、`+`、`{n,m}` 等可变量词）。

---

### 9. 单词边界

| 语法 | 说明 |
|------|------|
| `\b` | 单词边界（`\w` 与 `\W` 之间，或字符串起止处） |
| `\B` | 非单词边界 |

```actionscript
var re:RegExp = new RegExp("\\bword\\b", "");
re.test("a word here");  // true
re.test("awordhere");    // false
re.test("word");         // true

var re2:RegExp = new RegExp("\\bcat\\b", "");
re2.test("concatenate"); // false — cat 两侧不是边界
```

---

### 10. 反向引用

通过 `\1`、`\2` 引用之前捕获组匹配的内容：

```actionscript
var re:RegExp = new RegExp("(a)\\1", "");
re.test("aa");  // true
re.test("ab");  // false
```

> 当前只支持数字反向引用，不支持命名反向引用 `\k<name>`。

---

### 11. 特殊字符与转义

| 转义序列 | 匹配内容 |
|----------|----------|
| `\\` | 反斜杠 `\` |
| `\.` | 点 `.` |
| `\n` | 换行符 |
| `\r` | 回车符 |
| `\t` | 制表符 |
| `\f` | 换页符 |
| `\xHH` | 十六进制字符（如 `\x41` = `A`） |
| `\uHHHH` | Unicode 字符（如 `\u4e2d` = `中`） |

**注意**：AS2 字符串中 `\` 本身需要转义为 `\\`，因此模式中的 `\d` 要写成 `"\\d"`。

---

### 12. String.prototype 注入方法

通过 `RegExp.injectMethods()` 可向 `String.prototype` 注入 4 个便捷方法：

```actionscript
RegExp.injectMethods();

var str:Object = "Price: $12.50 and $8.99";
var re:RegExp = new RegExp("\\d+\\.\\d+", "g");

// regexp_match — 返回所有匹配结果数组
var matches:Array = str.regexp_match(re);
// ["12.50", "8.99"]

// regexp_replace — 替换匹配内容
var replaced:String = str.regexp_replace(re, "X");
// "Price: $X and $X"

// regexp_search — 返回第一个匹配的位置
var pos:Number = str.regexp_search(re);
// 8

// regexp_split — 按匹配分割字符串
var parts:Array = str.regexp_split(re);
// ["Price: $", " and $", ""]

RegExp.removeMethods();  // 使用完毕后移除
```

补充语义：

- `regexp_match()` 在 `g` 模式下会安全推进 `lastIndex`，不会因为零宽匹配卡死
- `regexp_split()` 会内部克隆出带 `g` 标志的正则，因此即使传入的原始表达式没有 `g`，也会完成全部分割
- `regexp_replace()` 当前支持以下替换模板：
  - `$$`：字面量 `$`
  - `$&`：整个匹配
  - ``$` ``：匹配前缀
  - `$'`：匹配后缀
  - `$1`、`$2` ...：编号捕获组
  - `$<name>`：命名捕获组

示例：

```actionscript
RegExp.injectMethods();

var iso:Object = "2026-03-11";
var reDate:RegExp = new RegExp("(?<year>\\d{4})-(?<month>\\d{2})-(?<day>\\d{2})", "");

trace(iso.regexp_replace(reDate, "$2/$3/$1"));             // "03/11/2026"
trace(iso.regexp_replace(reDate, "$<day>/$<month>/$<year>")); // "11/03/2026"
trace(iso.regexp_replace(new RegExp("2026", ""), "$$YEAR"));   // "$YEAR-03-11"

RegExp.removeMethods();
```

---

### 13. 常用正则表达式实例

#### 数字验证（含科学记数法）
```actionscript
var re:RegExp = new RegExp("^-?\\d+(\\.\\d+)?([eE][+-]?\\d+)?$", "");
re.test("123");      // true
re.test("-123.45");  // true
re.test("1e10");     // true
re.test("12a");      // false
```

#### ISO 日期时间
```actionscript
var re:RegExp = new RegExp("^\\d{4}-\\d{2}-\\d{2}[Tt ]\\d{2}:\\d{2}:\\d{2}", "");
re.test("2024-10-09T08:30:00Z");  // true
```

#### 电子邮件
```actionscript
var re:RegExp = new RegExp("^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$", "");
re.test("test@example.com");  // true
```

#### URL
```actionscript
var re:RegExp = new RegExp("^(https?:\\/\\/)?([\\w.-]+)\\.([a-z\\.]{2,6})([\\/\\w .-]*)*\\/?$", "i");
re.test("https://www.example.com/path");  // true
```

#### 布尔值（忽略大小写）
```actionscript
var re:RegExp = new RegExp("^(true|false)$", "i");
re.test("TRUE");  // true
```

---

### 14. 回溯机制与性能

#### 回溯架构

引擎采用 NFA 回溯匹配。`matchSequenceFrom()` 方法实现 Sequence 节点的跨兄弟回溯：

1. 遇到 Quantifier（或 Group 包装的 Quantifier），枚举匹配次数
2. 贪婪模式从 max→min 递减尝试，非贪婪从 min→max 递增
3. 每个次数下递归验证后续兄弟节点是否匹配成功
4. 失败则回退到上一个 Quantifier 尝试下一个次数

#### ReDoS 防护

字符类节点会预构建 ASCII / Unicode 命中缓存，能够明显改善 `[a-zA-Z0-9]+` 这类高频字符集判断。

对于 `(a+)+b` 这类嵌套量词模式，当前引擎在 25 个 `a` 的输入上实测约 **99ms** 单次失败，仍低于测试阈值，但更深层嵌套依然可能导致指数级回溯，建议：
- 避免 `(a*)*`、`(a+)+` 等嵌套量词
- 优先使用具体的字符集 + 固定量词

#### 性能参考（当前仓库 TestLoader 基准实测）

| 基准 | 实测耗时 |
|------|----------|
| 简单字面量匹配 | `1.3408ms/op` |
| 字符类匹配 | `0.242ms/op` |
| 邮箱验证（复杂模式） | `5.9215ms/op` |
| ReDoS `(a+)+b`，25 个 `a` | `99ms` 单次 |
| 多捕获组 exec | `0.3387ms/op` |
| 全局匹配循环 | `2.638ms/op` |

与本轮字符类缓存优化前的记录相比：

- 字符类匹配：`0.5718ms/op` → `0.242ms/op`
- 邮箱验证：`10.009ms/op` → `5.9215ms/op`

仍需注意：

- 简单字面量、密集 `exec()`、全局 `exec()` 循环并未同步变快
- 主要热点仍在 `captures.slice()`、回溯分支复制和全局匹配状态维护

---

### 15. 调试与常见错误

#### 15.1 量词范围错误
`{n,m}` 中 n 必须 ≤ m，否则解析阶段抛出异常。

#### 15.2 转义遗漏
AS2 字符串中 `\` 要写两次：`"\\d"` 而非 `"\d"`。常见遗漏：`\\.`、`\\\\`、`\\/`。

#### 15.3 后顾断言长度限制
`(?<=...)` 和 `(?<!...)` 内的模式必须为固定长度，不能使用 `*`、`+`、`{n,m}` 可变量词。

#### 15.4 `exec()` 与 `lastIndex`
使用 `g` 标志时，`exec()` 从 `lastIndex` 开始匹配。循环调用前应重置：`re.lastIndex = 0;`

#### 15.5 零宽全局匹配
当前实现已对 `a*` 这类零宽全局匹配做推进保护，`exec()` / `regexp_match()` 不会因为空匹配陷入死循环。

#### 15.6 当前未实现的常见语义
- 命名反向引用 `\k<name>`
- `regexp_replace()` 的函数回调替换
- 类似 JavaScript `split` 的“把捕获组也插入结果数组”
- 原子组 `(?>...)`、占有量词 `a++`
- Unicode 属性类、内联 flag 组等更高级语法

---

### 16. 特性支持总表

| 特性 | 状态 | 说明 |
|------|------|------|
| 字面量匹配 | ✅ | |
| `.` 任意字符 | ✅ | 默认不匹配 `\n`，`s` 标志开启后匹配所有 |
| 字符集 `[...]` / `[^...]` | ✅ | 含范围、预定义类、hex/unicode 转义 |
| 预定义字符类 `\d\w\s\D\W\S` | ✅ | |
| 量词 `* + ? {n} {n,} {n,m}` | ✅ | 贪婪 + 非贪婪 |
| 分组 `()` / `(?:)` | ✅ | 捕获 + 非捕获 |
| 命名捕获组 `(?<name>...)` | ✅ | `exec()` 结果带 `groups` 对象 |
| 交替 `|` | ✅ | |
| 锚点 `^ $` | ✅ | 支持多行模式 |
| 正向前瞻 `(?=...)` | ✅ | |
| 负向前瞻 `(?!...)` | ✅ | |
| 正向后顾 `(?<=...)` | ✅ | 固定长度 |
| 负向后顾 `(?<!...)` | ✅ | 固定长度 |
| 单词边界 `\b` `\B` | ✅ | |
| 反向引用 `\1` `\2` | ✅ | 基础支持 |
| `source` / `flags` / `lastIndex` | ✅ | 公开实例属性 |
| `regexp_replace()` 替换模板 | ✅ | 支持字面量 `$`、整个匹配、前后缀、编号组、命名组 |
| `regexp_split()` 全量分割 | ✅ | 原始表达式即使无 `g` 也会内部克隆为全局模式 |
| 十六进制转义 `\xHH` | ✅ | |
| Unicode 转义 `\uHHHH` | ✅ | |
| `i` 忽略大小写 | ✅ | |
| `g` 全局匹配 | ✅ | |
| `m` 多行模式 | ✅ | |
| `s` dotAll 模式 | ✅ | |
| Sequence 跨兄弟回溯 | ✅ | 贪婪/非贪婪量词 + Group 包装量词 |
| 命名反向引用 `\k<name>` | ❌ | 未实现 |
| `regexp_replace()` 回调函数 | ❌ | 未实现 |
| `split` 捕获组回填 | ❌ | 未实现 |
| 原子组 `(?>...)` | ❌ | 待实现 |
| 占有量词 `a++` | ❌ | 待实现 |
| ReDoS 记忆化 | ❌ | 待实现 |

---

### 运行测试

```actionscript
import org.flashNight.gesh.regexp.*;

RegExpTest.runTests();    // 快速回归
RegExpTest.runAllTests(); // 含性能基准，Flash 自动化场景下可能超过 30 秒
```

或通过 Flash CS6 自动化编译（详见 `scripts/FlashCS6自动化编译.md`）：

```bash
bash scripts/compile_test.sh
```
