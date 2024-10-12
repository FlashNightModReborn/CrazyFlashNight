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













import org.flashNight.gesh.regexp.*;
// 创建正则表达式对象
var regex1:RegExp = new RegExp("a*b", "");
trace("测试1：正则表达式 /a*b/ 匹配 'aaab'");
trace(regex1.test("aaab")); // 输出 true

var regex2:RegExp = new RegExp("(abc)+", "");
trace("测试2：正则表达式 /(abc)+/ 匹配 'abcabc'");
trace(regex2.test("abcabc")); // 输出 true

var regex3:RegExp = new RegExp("[a-z]{3}", "");
trace("测试3：正则表达式 /[a-z]{3}/ 匹配 'abc'");
trace(regex3.test("abc")); // 输出 true

var regex4:RegExp = new RegExp("a|b", "");
trace("测试4：正则表达式 /a|b/ 匹配 'a'");
trace(regex4.test("a")); // 输出 true

trace("测试5：正则表达式 /a|b/ 匹配 'b'");
trace(regex4.test("b")); // 输出 true

var regex5:RegExp = new RegExp("a+", "");
trace("测试6：正则表达式 /a+/ 匹配 'aa'");
trace(regex5.test("aa")); // 输出 true

var regex6:RegExp = new RegExp("a+", "");
trace("测试7：正则表达式 /a+/ 匹配 ''");
trace(regex6.test("")); // 输出 false

// 测试 exec() 方法
var regex7:RegExp = new RegExp("(a)(b)(c)", "");
var result:Array = regex7.exec("abc");
if (result != null) {
    trace("测试8：正则表达式 /(a)(b)(c)/ 匹配 'abc'");
    trace("匹配结果：" + result[0]); // 输出 'abc'
    trace("捕获组1：" + result[1]); // 输出 'a'
    trace("捕获组2：" + result[2]); // 输出 'b'
    trace("捕获组3：" + result[3]); // 输出 'c'
} else {
    trace("测试8失败：未匹配");
}

// 测试字符集
var regex8:RegExp = new RegExp("[^a-z]", "");
trace("测试9：正则表达式 /[^a-z]/ 匹配 '1'");
trace(regex8.test("1")); // 输出 true

trace("测试10：正则表达式 /[^a-z]/ 匹配 'a'");
trace(regex8.test("a")); // 输出 false

// 测试11：嵌套分组和量词的组合
var regex11:RegExp = new RegExp("(ab(c|d))*", "");



// trace("测试11：正则表达式 /(ab(c|d))*/ 匹配 'abcdabcdabcc'");

trace(regex11.test("abcdabcdabcc")); // 预期输出 true

// 测试12：量词 {0}
var regex12:RegExp = new RegExp("a{0}", "");
trace("测试12：正则表达式 /a{0}/ 匹配 'abc'");
trace(regex12.test("abc")); // 预期输出 true

// 测试13：量词 {3,1}，n > m 的情况
var regex13:RegExp = new RegExp("a{3,1}", "");
trace("测试13：正则表达式 /a{3,1}/ 匹配 'aaa'");
trace(regex13.test("aaa")); // 预期输出 false 或处理错误

// 测试14：匹配空字符串
var regex14:RegExp = new RegExp("^$", "");
trace("测试14：正则表达式 /^$/ 匹配 ''");
trace(regex14.test("")); // 预期输出 true

// 测试15：量词允许零次匹配
var regex15:RegExp = new RegExp("a*", "");


// trace("测试15：正则表达式 /a*/ 匹配 ''");

trace(regex15.test("")); // 预期输出 true

// 测试16：任意字符匹配
var regex16:RegExp = new RegExp("a.c", "");
trace("测试16：正则表达式 /a.c/ 匹配 'abc'");
trace(regex16.test("abc")); // 预期输出 true

trace("测试17：正则表达式 /a.c/ 匹配 'a c'");
trace(regex16.test("a c")); // 预期输出 true

trace("测试18：正则表达式 /a.c/ 匹配 'abbc'");
trace(regex16.test("abbc")); // 预期输出 false

// 测试19：字符集和量词的组合
var regex19:RegExp = new RegExp("[abc]+", "");
trace("测试19：正则表达式 /[abc]+/ 匹配 'aaabbbcccabc'");
trace(regex19.test("aaabbbcccabc")); // 预期输出 true

// 测试20：否定字符集和量词的组合
var regex20:RegExp = new RegExp("[^abc]+", "");
trace("测试20：正则表达式 /[^abc]+/ 匹配 'defg'");
trace(regex20.test("defg")); // 预期输出 true

// 测试21：多个选择的组合
var regex21:RegExp = new RegExp("a|b|c", "");
trace("测试21：正则表达式 /a|b|c/ 匹配 'b'");
trace(regex21.test("b")); // 预期输出 true

trace("测试22：正则表达式 /a|b|c/ 匹配 'd'");
trace(regex21.test("d")); // 预期输出 false

// 测试23：量词嵌套的情况
var regex23:RegExp = new RegExp("(a+)+", "");
trace("测试23：正则表达式 /(a+)+/ 匹配 'aaa'");
trace(regex23.test("aaa")); // 预期输出 true

// 测试24：无法匹配的情况
var regex24:RegExp = new RegExp("a{4}", "");
trace("测试24：正则表达式 /a{4}/ 匹配 'aaa'");
trace(regex24.test("aaa")); // 预期输出 false

// 测试25：匹配长字符串
var longString:String = "";
for (var i:Number = 0; i < 1000; i++) {
    longString += "a";
}
var regex25:RegExp = new RegExp("a{1000}", "");
trace("测试25：正则表达式 /a{1000}/ 匹配 1000 个 'a'");
trace(regex25.test(longString)); // 预期输出 true

// 测试26：嵌套捕获组
var regex26:RegExp = new RegExp("((a)(b(c)))", "");
var result26:Array = regex26.exec("abc");
if (result26 != null) {
    trace("测试26：正则表达式 /((a)(b(c)))/ 匹配 'abc'");
    trace("匹配结果：" + result26[0]); // 输出 'abc'
    trace("捕获组1：" + result26[1]); // 输出 'abc'
    trace("捕获组2：" + result26[2]); // 输出 'a'
    trace("捕获组3：" + result26[3]); // 输出 'bc'
    trace("捕获组4：" + result26[4]); // 输出 'c'
} else {
    trace("测试26失败：未匹配");
}

// 测试27：预定义字符类 \d
var regex27:RegExp = new RegExp("\\d+", "");
trace("测试27：正则表达式 /\\d+/ 匹配 '12345'");
trace(regex27.test("12345")); // 预期输出 true

// 测试28：预定义字符类 \D
var regex28:RegExp = new RegExp("\\D+", "");
trace("测试28：正则表达式 /\\D+/ 匹配 'abcDEF'");
trace(regex28.test("abcDEF")); // 预期输出 true

// 测试29：预定义字符类 \w
var regex29:RegExp = new RegExp("\\w+", "");
trace("测试29：正则表达式 /\\w+/ 匹配 'hello_world123'");
trace(regex29.test("hello_world123")); // 预期输出 true

// 测试30：预定义字符类 \W
var regex30:RegExp = new RegExp("\\W+", "");
trace("测试30：正则表达式 /\\W+/ 匹配 '!@#'");
trace(regex30.test("!@#")); // 预期输出 true

// 测试31：预定义字符类 \s
var regex31:RegExp = new RegExp("\\s+", "");
trace("测试31：正则表达式 /\\s+/ 匹配 '   '");
trace(regex31.test("   ")); // 预期输出 true

// 测试32：预定义字符类 \S
var regex32:RegExp = new RegExp("\\S+", "");
trace("测试32：正则表达式 /\\S+/ 匹配 'non-space'");
trace(regex32.test("non-space")); // 预期输出 true

// 测试33：转义字符 \n
var regex33:RegExp = new RegExp("hello\\nworld", "");
trace("测试33：正则表达式 /hello\\nworld/ 匹配 'hello\nworld'");
trace(regex33.test("hello\nworld")); // 预期输出 true

// 测试34：忽略大小写匹配
var regex34:RegExp = new RegExp("abc", "i");
trace("测试34：正则表达式 /abc/i 匹配 'AbC'");
trace(regex34.test("AbC")); // 预期输出 true

// 测试35：非贪婪量词
var regex35:RegExp = new RegExp("a+?", "");
trace("测试35：正则表达式 /a+?/ 匹配 'aaa'");
var result35:Array = regex35.exec("aaa");
if (result35 != null) {
    trace("匹配结果：" + result35[0]); // 预期输出 'a'
} else {
    trace("测试35失败：未匹配");
}

// 测试36：非捕获分组
var regex36:RegExp = new RegExp("a(?:bc)+", "");
trace("测试36：正则表达式 /a(?:bc)+/ 匹配 'abcbc'");
var result36:Array = regex36.exec("abcbc");
if (result36 != null) {
    trace("匹配结果：" + result36[0]); // 输出 'abcbc'
    trace("捕获组数：" + (result36.length - 1)); // 预期为0，因为没有捕获组
} else {
    trace("测试36失败：未匹配");
}

// 测试37：嵌套捕获组
var regex37:RegExp = new RegExp("(a(b(c)))", "");
var result37:Array = regex37.exec("abc");
if (result37 != null) {
    trace("测试37：正则表达式 /(a(b(c)))/ 匹配 'abc'");
    trace("匹配结果：" + result37[0]); // 预期输出 'abc'
    trace("捕获组1：" + result37[1]); // 预期输出 'abc'
    trace("捕获组2：" + result37[2]); // 预期输出 'bc'
    trace("捕获组3：" + result37[3]); // 预期输出 'c'
} else {
    trace("测试37失败：未匹配");
}

// Test38: Backreference with single group
var regex38:RegExp = new RegExp("(a)\\1", "");
trace("测试38：正则表达式 /(a)\\1/ 匹配 'aa'");
trace(regex38.test("aa")); // 预期输出 true

// Test39: Backreference with multiple groups (should not match)
var regex39:RegExp = new RegExp("(a)(b)\\1\\2", "");
trace("测试39：正则表达式 /(a)(b)\\1\\2/ 匹配 'abba'");
trace(regex39.test("abba")); // 预期输出 false

// Test40: Backreference with multiple groups (should match)
var regex40:RegExp = new RegExp("(a)(b)\\2\\1", "");
trace("测试40：正则表达式 /(a)(b)\\2\\1/ 匹配 'abba'");
trace(regex40.test("abba")); // 预期输出 true

// Test41: Backreference with nested groups
var regex41:RegExp = new RegExp("((a)b)\\1", "");
trace("测试41：正则表达式 /((a)b)\\1/ 匹配 'abab'");
trace(regex41.test("abab")); // 预期输出 true

// Test42: Positive Lookahead (Assuming future support)
var regex42:RegExp = new RegExp("a(?=b)", "");
trace("测试42：正则表达式 /a(?=b)/ 匹配 'ab'");
trace(regex42.test("ab")); // 预期输出 true

trace("测试42：正则表达式 /a(?=b)/ 匹配 'ac'");
trace(regex42.test("ac")); // 预期输出 false

// Test43: Negative Lookahead (Assuming future support)
var regex43:RegExp = new RegExp("a(?!b)", "");
trace("测试43：正则表达式 /a(?!b)/ 匹配 'ac'");
trace(regex43.test("ac")); // 预期输出 true

trace("测试43：正则表达式 /a(?!b)/ 匹配 'ab'");
trace(regex43.test("ab")); // 预期输出 false

// Test44: Positive Lookbehind (Assuming future support)
var regex44:RegExp = new RegExp("(?<=a)b", "");
trace("测试44：正则表达式 /(?<=a)b/ 匹配 'ab'");
trace(regex44.test("ab")); // 预期输出 true

trace("测试44：正则表达式 /(?<=a)b/ 匹配 'cb'");
trace(regex44.test("cb")); // 预期输出 false

// Test45: Negative Lookbehind (Assuming future support)
var regex45:RegExp = new RegExp("(?<!a)b", "");
trace("测试45：正则表达式 /(?<!a)b/ 匹配 'cb'");
trace(regex45.test("cb")); // 预期输出 true

trace("测试45：正则表达式 /(?<!a)b/ 匹配 'ab'");
trace(regex45.test("ab")); // 预期输出 false

// Test46: Named Capturing Group (Assuming future support)
var regex46:RegExp = new RegExp("(?<first>a)(?<second>b)", "");
trace("测试46：正则表达式 /(?<first>a)(?<second>b)/ 匹配 'ab'");
var result46:Array = regex46.exec("ab");
if (result46 != null) {
    trace("匹配结果：" + result46[0]); // 输出 'ab'
    trace("捕获组1(first)：" + result46[1]); // 输出 'a'
    trace("捕获组2(second)：" + result46[2]); // 输出 'b'
} else {
    trace("测试46失败：未匹配");
}

// Test47: Start and End Anchors with Multiline Flag
var regex47:RegExp = new RegExp("^a", "m");
trace("测试47：正则表达式 /^a/m 匹配 'a\\nb'");
trace(regex47.test("a\nb")); // 预期输出 true

var regex48:RegExp = new RegExp("b$", "m");
trace("测试48：正则表达式 /b$/m 匹配 'a\\nb'");
trace(regex48.test("a\nb")); // 预期输出 true

// Test49: Unclosed Group
try {
    var regex49:RegExp = new RegExp("(a", "");
    trace("测试49：正则表达式 /(a/ 匹配 'a'");
    trace(regex49.test("a")); // 应该抛出错误
} catch (e:Error) {
    trace("测试49：捕获到错误 - " + e.message);
}

// Test50: Empty Pattern
var regex50:RegExp = new RegExp("", "");
trace("测试50：空模式 /''/ 匹配 'abc'");
trace(regex50.test("abc")); // 预期输出 true

// Test51: Pattern with Only Quantifiers
try {
    var regex51:RegExp = new RegExp("*", "");
    trace("测试51：正则表达式 /*/ 匹配 'a'");
    trace(regex51.test("a")); // 应该抛出错误
} catch (e:Error) {
    trace("测试51：捕获到错误 - " + e.message);
}

// Test52: Matching a Very Long String
var longString10000:String = "";
for (var j:Number = 0; j < 10000; j++) {
    longString10000 += "a";
}
var regex52:RegExp = new RegExp("a{10000}", "");
trace("测试52：正则表达式 /a{10000}/ 匹配 10000 个 'a'");
trace(regex52.test(longString10000)); // 预期输出 true

// Test53: Catastrophic Backtracking
try {
    var regex53:RegExp = new RegExp("(a+)+b", "");
    trace("测试53：正则表达式 /(a+)+b/ 匹配 'aaaaa'");
    trace(regex53.test("aaaaa")); // 应该返回 false without excessive backtracking
} catch (e:Error) {
    trace("测试53：捕获到错误 - " + e.message);
}

// Test54: Unicode Characters
var regex54:RegExp = new RegExp("\\u0041", "");
trace("测试54：正则表达式 /\\u0041/ 匹配 'A'");
trace(regex54.test("A")); // 预期输出 true

// Test55: Escaped Special Characters
var regex55:RegExp = new RegExp("\\.", "");
trace("测试55：正则表达式 /\\./ 匹配 '.'");
trace(regex55.test(".")); // 预期输出 true

trace("测试55：正则表达式 /\\./ 匹配 'a'");
trace(regex55.test("a")); // 预期输出 false




////////////////////////////////////////


import org.flashNight.gesh.regexp.RegExp;

// 测试简单正则表达式
var regex1:RegExp = new RegExp("a*b", "");
trace("测试1：正则表达式 /a*b/ 匹配 'aaab' -> " + regex1.test("aaab")); // 预期 true

var regex2:RegExp = new RegExp("(abc)+", "");
trace("测试2：正则表达式 /(abc)+/ 匹配 'abcabc' -> " + regex2.test("abcabc")); // 预期 true

var regex3:RegExp = new RegExp("[a-z]{3}", "");
trace("测试3：正则表达式 /[a-z]{3}/ 匹配 'abc' -> " + regex3.test("abc")); // 预期 true

var regex4:RegExp = new RegExp("a|b", "");
trace("测试4：正则表达式 /a|b/ 匹配 'a' -> " + regex4.test("a")); // 预期 true
trace("测试4：正则表达式 /a|b/ 匹配 'b' -> " + regex4.test("b")); // 预期 true

var regex5:RegExp = new RegExp("a+", "");
trace("测试5：正则表达式 /a+/ 匹配 'aa' -> " + regex5.test("aa")); // 预期 true

var regex6:RegExp = new RegExp("a+", "");
trace("测试6：正则表达式 /a+/ 匹配 '' -> " + regex6.test("")); // 预期 false

var regex7:RegExp = new RegExp("(a)(b)(c)", "");
var result:Array = regex7.exec("abc");
if (result != null) {
    trace("测试7：正则表达式 /(a)(b)(c)/ 匹配 'abc'");
    trace("匹配结果：" + result[0]); // 输出 'abc'
    trace("捕获组1：" + result[1]); // 输出 'a'
    trace("捕获组2：" + result[2]); // 输出 'b'
    trace("捕获组3：" + result[3]); // 输出 'c'
} else {
    trace("测试7失败：未匹配");
}

// 测试 numberRegExp
var numberRegExp:RegExp = new RegExp("^-?\\d+(\\.\\d+)?([eE][+-]?\\d+)?$", "");
trace("测试8：正则表达式 numberRegExp 匹配 '123' -> " + numberRegExp.test("123")); // 预期 true
trace("测试8：正则表达式 numberRegExp 匹配 '-123.45' -> " + numberRegExp.test("-123.45")); // 预期 true
trace("测试8：正则表达式 numberRegExp 匹配 '1e10' -> " + numberRegExp.test("1e10")); // 预期 true
trace("测试8：正则表达式 numberRegExp 匹配 '12a' -> " + numberRegExp.test("12a")); // 预期 false

// 测试 dateTimeRegExp
var dateTimeRegExp:RegExp = new RegExp("^\\d{4}-\\d{2}-\\d{2}[Tt ][0-2]\\d:[0-5]\\d:[0-5]\\d(\\.\\d+)?([Zz]|([+-][0-2]\\d:[0-5]\\d))?$", "");
trace("测试9：正则表达式 dateTimeRegExp 匹配 '2024-10-09T08:30:00Z' -> " + dateTimeRegExp.test("2024-10-09T08:30:00Z")); // 预期 true
trace("测试9：正则表达式 dateTimeRegExp 匹配 '2024-10-09 08:30:00+02:00' -> " + dateTimeRegExp.test("2024-10-09 08:30:00+02:00")); // 预期 true
trace("测试9：正则表达式 dateTimeRegExp 匹配 '2024-13-40T25:61:61Z' -> " + dateTimeRegExp.test("2024-13-40T25:61:61Z")); // 预期 false

// 测试 booleanRegExp
var booleanRegExp:RegExp = new RegExp("^(true|false)$", "i");
trace("测试10：正则表达式 booleanRegExp 匹配 'true' -> " + booleanRegExp.test("true")); // 预期 true
trace("测试10：正则表达式 booleanRegExp 匹配 'FALSE' -> " + booleanRegExp.test("FALSE")); // 预期 true
trace("测试10：正则表达式 booleanRegExp 匹配 'yes' -> " + booleanRegExp.test("yes")); // 预期 false

// 测试 specialFloatRegExp
var specialFloatRegExp:RegExp = new RegExp("^(nan|inf|-inf)$", "i");
trace("测试11：正则表达式 specialFloatRegExp 匹配 'NaN' -> " + specialFloatRegExp.test("NaN")); // 预期 true
trace("测试11：正则表达式 specialFloatRegExp 匹配 'inf' -> " + specialFloatRegExp.test("inf")); // 预期 true
trace("测试11：正则表达式 specialFloatRegExp 匹配 '-INF' -> " + specialFloatRegExp.test("-INF")); // 预期 true
trace("测试11：正则表达式 specialFloatRegExp 匹配 '1.23' -> " + specialFloatRegExp.test("1.23")); // 预期 false

