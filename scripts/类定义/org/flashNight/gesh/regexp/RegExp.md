### 正则表达式引擎使用指南

#### 概述
正则表达式（Regular Expressions，简称“正则”）是一种强大的文本匹配工具，可以通过特定的模式来搜索、验证、或操作字符串。在本指南中，我们将深入介绍如何使用 **org.flashNight.gesh.regexp** 提供的正则表达式类 (`RegExp`) 进行各种文本处理操作，详细讲解每个功能模块的用法、特性支持情况、实现细节，并配合实例说明如何在实际项目中高效地使用正则表达式。

本指南将特别适用于不熟悉正则表达式的用户，通过详细分步的介绍，帮助理解其基础及进阶特性。

---

### 目录

1. **创建正则表达式对象**
2. **字符匹配**
   - 字符集与否定字符集
   - 字符类
3. **量词（Quantifiers）**
   - 常见量词
   - 非贪婪量词
4. **分组与捕获**
   - 捕获组与非捕获组
5. **逻辑或操作符 (`|`)**
6. **特殊字符与转义**
7. **反向引用的基础支持**
8. **常用正则表达式的实例**
9. **调试与常见错误**

---

### 1. 创建正则表达式对象

在 **ActionScript 2 (AS2)** 中，使用 `RegExp` 类来创建正则表达式对象的语法如下：

```actionscript
var regex:RegExp = new RegExp(pattern:String, flags:String);
```

- **pattern**：定义了正则表达式的匹配模式，例如 `\d+` 表示匹配一个或多个数字。
- **flags**：用于控制匹配行为的修饰符。常见的修饰符有：
  - `i`：忽略大小写。
  - `g`：全局匹配。
  - `m`：多行匹配，`^` 和 `$` 匹配每行的开头和结尾。

**示例**：
```actionscript
var regex:RegExp = new RegExp("a*b", "i");
trace(regex.test("Aaab"));  // 输出 true，忽略大小写匹配
```

---

### 2. 字符匹配

#### 2.1 字符集与否定字符集
- **字符集**使用方括号 `[ ]` 来匹配集合内的任意字符，例如：
  - `[a-z]` 匹配任意小写字母。
  - `[0-9]` 匹配数字。

```actionscript
var regex:RegExp = new RegExp("[a-z]+", "");
trace(regex.test("hello"));  // 输出 true
```

- **否定字符集**使用 `[^]` 来表示不匹配括号内的字符，例如：
```actionscript
var regex:RegExp = new RegExp("[^a-z]", "");
trace(regex.test("1"));  // 输出 true，数字 1 不属于小写字母
```

#### 2.2 字符类
- **\d**：匹配任意数字（`0-9`）。
- **\w**：匹配字母、数字或下划线。
- **\s**：匹配空白字符。

```actionscript
var regex:RegExp = new RegExp("\\d+", "");
trace(regex.test("12345"));  // 输出 true
```

---

### 3. 量词（Quantifiers）

量词用于定义前一个元素的重复次数：

- **`*`**：匹配零次或多次。
- **`+`**：匹配一次或多次。
- **`?`**：匹配零次或一次。
- **`{n}`**：匹配恰好 n 次。
- **`{n,}`**：至少匹配 n 次。
- **`{n,m}`**：匹配 n 到 m 次。

**示例**：
```actionscript
var regex:RegExp = new RegExp("a{3}", "");
trace(regex.test("aaa"));  // 输出 true，正好三个 'a'
```

#### 3.1 非贪婪量词
正则表达式默认使用“贪婪匹配”，即尽可能多地匹配。通过在量词后加 `?` 可实现非贪婪匹配，尽可能少地匹配字符。

**示例**：
```actionscript
var regex:RegExp = new RegExp("a+?", "");
trace(regex.exec("aaa")[0]);  // 输出 'a'，只匹配一个 'a'
```

---

### 4. 分组与捕获

- **捕获组**：使用括号 `()` 进行分组，可提取匹配到的子字符串。
- **非捕获组**：`(?: )` 用于只匹配而不捕获。

**示例**：
```actionscript
var regex:RegExp = new RegExp("(abc)(def)", "");
var result:Array = regex.exec("abcdef");
trace(result[1]);  // 输出 'abc'，第一个捕获组
trace(result[2]);  // 输出 'def'，第二个捕获组
```

#### 捕获组编号
捕获组可以通过 `exec()` 方法返回的数组来提取，第一项为完整匹配，后续项为各个捕获组的内容。

---

### 5. 逻辑或操作符 `|`

使用 `|` 表示逻辑或，可匹配多个模式中的任意一个：

```actionscript
var regex:RegExp = new RegExp("a|b", "");
trace(regex.test("a"));  // 输出 true
trace(regex.test("b"));  // 输出 true
trace(regex.test("c"));  // 输出 false
```

---

### 6. 特殊字符与转义

正则表达式中有些字符具有特殊含义，如 `.`、`^`、`$`、`*`、`+` 等。如果要匹配这些字符本身，需要使用反斜杠 `\` 进行转义。

- **`.`**：匹配除换行符外的任意字符。
- **`\d`**：匹配任意数字。
- **`\w`**：匹配字母、数字或下划线。

```actionscript
var regex:RegExp = new RegExp("\\.", "");
trace(regex.test("."));  // 输出 true，匹配点字符
```

---

### 7. 反向引用的基础支持

目前正则引擎对**反向引用**提供了基础支持，捕获组的内容可以在同一个正则表达式中再次被引用。

- 通过 `\1`、`\2` 等形式来引用之前的捕获组。

```actionscript
var regex:RegExp = new RegExp("(a)\\1", "");
trace(regex.test("aa"));  // 输出 true
```

**注意**：反向引用目前只做了基础支持，不能用于复杂生产环境。

---

### 8. 常用正则表达式的实例

#### 8.1 匹配电子邮件地址

```actionscript
var regex:RegExp = new RegExp("[\\w.-]+@[\\w.-]+\\.\\w+", "");
trace(regex.test("example@test.com"));  // 输出 true
```

#### 8.2 匹配电话号码
```actionscript
var regex:RegExp = new RegExp("\\d{3}-\\d{3}-\\d{4}", "");
trace(regex.test("123-456-7890"));  // 输出 true
```

#### 8.3 匹配 URL
```actionscript
var regex:RegExp = new RegExp("https?://[\\w.-]+", "");
trace(regex.test("http://example.com"));  // 输出 true
```

---

### 9. 调试与常见错误

#### 9.1 量词错误
当使用量词时，确保 `{n,m}` 中 `n <= m`，否则会导致无效量词错误。

#### 9.2 转义符号
确保在需要时正确使用 `\` 转义特殊字符，如 `.`、`$`、`^`。

**示例**：
```actionscript
var regex:RegExp = new RegExp("\\.", "");
trace(regex.test("."));  // 输出 true
```

#### 9.3 反向引用问题
反向引用目前只支持基础功能，复杂的模式可能无法正确匹配。

---

### 总结

本正则表达式引擎在 ActionScript 2 环境中提供了基础的正则功能，支持匹配、捕获、量词、字符集、逻辑或等基本操作，同时对反向引用有初步的支持。尽管如此，高级正则功能（如环视等）暂时未实现，且反向引用的使用在复杂场景中仍需谨慎。

通过合理地使用这些基础功能，可以显著提升文本处理的效率。在开发过程中，遇到正则匹配错误时，可以通过调试工具和常见错误排查表来辅助定位问题，逐步优化正则表达式的匹配效果。




### 10. 测试class的运行代码

import org.flashNight.gesh.regexp.RegExpTest;

RegExpTest.runTests();
