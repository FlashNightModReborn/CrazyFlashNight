### 正则表达式引擎使用指南

#### 概述

**org.flashNight.gesh.regexp** 是一个纯 AS2 实现的正则表达式引擎，采用递归下降解析器生成 AST，再通过回溯 NFA 进行匹配。支持大部分常用正则语法，可在 Flash Player 8+ / AVM1 环境下运行。

**架构**：`Parser`（词法/语法分析）→ `ASTNode`（AST 节点 + 匹配引擎）→ `RegExp`（用户接口）

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

对于 `(a+)+b` 这类嵌套量词模式，当前引擎在 25 个 `a` 的输入上可在 <30ms 内快速失败。但更深层的嵌套仍可能导致指数级回溯，建议：
- 避免 `(a*)*`、`(a+)+` 等嵌套量词
- 优先使用具体的字符集 + 固定量词

#### 性能参考（AVM1 环境）

| 基准 | 典型耗时 |
|------|----------|
| 简单字面量匹配 | ~0.4ms/op |
| 字符类匹配 | ~0.3ms/op |
| 邮箱验证（复杂模式） | ~4.5ms/op |
| 多捕获组 exec | ~0.1ms/op |
| 全局匹配循环 | ~0.7ms/op |

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
| 交替 `\|` | ✅ | |
| 锚点 `^ $` | ✅ | 支持多行模式 |
| 正向前瞻 `(?=...)` | ✅ | |
| 负向前瞻 `(?!...)` | ✅ | |
| 正向后顾 `(?<=...)` | ✅ | 固定长度 |
| 负向后顾 `(?<!...)` | ✅ | 固定长度 |
| 单词边界 `\b` `\B` | ✅ | |
| 反向引用 `\1` `\2` | ✅ | 基础支持 |
| 十六进制转义 `\xHH` | ✅ | |
| Unicode 转义 `\uHHHH` | ✅ | |
| `i` 忽略大小写 | ✅ | |
| `g` 全局匹配 | ✅ | |
| `m` 多行模式 | ✅ | |
| `s` dotAll 模式 | ✅ | |
| Sequence 跨兄弟回溯 | ✅ | 贪婪/非贪婪量词 + Group 包装量词 |
| 命名捕获组 `(?<name>...)` | ❌ | 待实现 |
| 原子组 `(?>...)` | ❌ | 待实现 |
| 占有量词 `a++` | ❌ | 待实现 |
| ReDoS 记忆化 | ❌ | 待实现 |

---

### 运行测试

```actionscript
import org.flashNight.gesh.regexp.*;

RegExpTest.runTests();
```

或通过 Flash CS6 自动化编译（详见 `scripts/FlashCS6自动化编译.md`）：

```bash
bash scripts/compile_test.sh
```
