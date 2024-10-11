/*
### 正则表达式使用指南

#### 概述
正则表达式（Regular Expression，简称“正则”或“RegEx”）是一种用于匹配和操作文本的强大工具，广泛应用于文本搜索、替换、验证等场景。在本指南中，我们将一步步介绍如何使用 ActionScript 2 (AS2) 环境中的正则表达式类（`RegExp`），帮助用户快速掌握基础知识，并了解如何在不同场景中提升开发效率。

### 1. 创建正则表达式对象
在 AS2 中，你可以使用 `RegExp` 类来创建正则表达式对象。创建一个正则表达式的基本语法是：
```actionscript
var regex:RegExp = new RegExp(pattern, flags);
```
- `pattern` 是正则表达式的模式，定义了你想匹配的文本规则。
- `flags` 是可选参数，用于指定匹配规则（如是否忽略大小写）。

例如：
```actionscript
var regex:RegExp = new RegExp("a*b", "");
```
这个表达式匹配以零个或多个 `a` 字符开头并紧跟一个 `b` 字符的字符串。

### 2. 基本特性

#### 2.1 字符匹配
正则表达式最基本的功能是匹配具体的字符或字符组合。
- 直接匹配字符，如 `a` 匹配字母 `a`，`abc` 匹配整个字符串 `abc`。
```actionscript
var regex:RegExp = new RegExp("abc", "");
trace(regex.test("abc")); // 输出 true
```

#### 2.2 字符集
- 使用 `[]` 来表示字符集，匹配指定范围内的任意一个字符。例如：
  - `[abc]` 匹配 `a`、`b` 或 `c`。
  - `[a-z]` 匹配所有小写字母。
```actionscript
var regex:RegExp = new RegExp("[a-z]", "");
trace(regex.test("f")); // 输出 true
```

#### 2.3 否定字符集
- 使用 `[^]` 表示不匹配括号内的任意字符。例如，`[^a-z]` 表示不匹配小写字母：
```actionscript
var regex:RegExp = new RegExp("[^a-z]", "");
trace(regex.test("1")); // 输出 true
```

### 3. 量词（Quantifiers）
量词用于指定前面的元素出现的次数。

#### 3.1 常用量词
- `*`：匹配零个或多个前面的元素。例如，`a*` 表示零个或多个 `a` 字符。
- `+`：匹配一个或多个前面的元素。例如，`a+` 表示一个或多个 `a`。
- `?`：匹配零个或一个前面的元素。例如，`a?` 表示零个或一个 `a`。
- `{n}`：精确匹配 `n` 次。例如，`a{3}` 表示匹配三个连续的 `a`。
- `{n,m}`：匹配 `n` 到 `m` 次。例如，`a{2,5}` 表示匹配 2 到 5 个 `a`。

#### 3.2 使用示例
```actionscript
var regex:RegExp = new RegExp("a{3}", "");
trace(regex.test("aaa")); // 输出 true，正好有三个 a
```

### 4. 分组与捕获
通过使用 `()` 可以将模式分组，方便提取部分匹配结果。
```actionscript
var regex:RegExp = new RegExp("(abc)", "");
var result:Array = regex.exec("abc");
trace(result[1]); // 输出 'abc'，即捕获的第一个分组
```

### 5. 逻辑或 `|`
使用 `|` 表示逻辑或，用于匹配多个模式中的任意一个。例如，`a|b` 表示匹配 `a` 或 `b`。
```actionscript
var regex:RegExp = new RegExp("a|b", "");
trace(regex.test("a")); // 输出 true
trace(regex.test("b")); // 输出 true
```

### 6. 特殊字符
正则表达式中的某些字符具有特殊含义，使用 `\` 转义。例如：
- `.`：匹配除换行符外的任意字符。
- `\d`：匹配任意数字（0-9）。
- `\w`：匹配任意字母、数字或下划线。
- `\s`：匹配空白字符（如空格、制表符）。
- `\b`：匹配单词边界。
- `^`：匹配字符串的开始。
- `$`：匹配字符串的结尾。

#### 示例：
```actionscript
var regex:RegExp = new RegExp("\\d+", "");
trace(regex.test("123")); // 输出 true，匹配数字
```

### 7. 非贪婪量词
默认情况下，正则表达式的量词是“贪婪”的，它会尽可能多地匹配。你可以通过在量词后面加 `?` 来让匹配变成“非贪婪”的，即尽可能少地匹配。
```actionscript
var regex:RegExp = new RegExp("a+?", "");
trace(regex.exec("aaa")[0]); // 输出 'a'，只匹配一个 a
```

### 8. 测试和执行
- `test()`：用于测试字符串是否匹配正则表达式，返回布尔值。
- `exec()`：用于执行正则表达式，返回一个包含匹配结果的数组，或 `null` 表示没有匹配。

#### 示例：
```actionscript
var regex:RegExp = new RegExp("a+", "");
trace(regex.test("aaa")); // 输出 true
```

### 9. 匹配修饰符
匹配修饰符可以改变正则表达式的行为。常见的修饰符包括：
- `i`：忽略大小写。
- `m`：多行匹配，`^` 和 `$` 匹配每行的开头和结尾。

#### 示例：
```actionscript
var regex:RegExp = new RegExp("abc", "i");
trace(regex.test("AbC")); // 输出 true，忽略大小写
```

### 10. 常见的正则表达式模式应用

#### 10.1 匹配电子邮件地址
```actionscript
var regex:RegExp = new RegExp("[\\w.-]+@[\\w.-]+\\.\\w+", "");
trace(regex.test("example@test.com")); // 输出 true
```

#### 10.2 匹配电话号码
```actionscript
var regex:RegExp = new RegExp("\\d{3}-\\d{3}-\\d{4}", "");
trace(regex.test("123-456-7890")); // 输出 true
```

#### 10.3 匹配 URL
```actionscript
var regex:RegExp = new RegExp("https?://[\\w.-]+", "");
trace(regex.test("http://example.com")); // 输出 true
```

### 11. 常见错误与调试技巧
- **量词错误**：确保 `{n,m}` 中的 `n` 小于等于 `m`，否则会导致无效量词错误。
- **未匹配到结果**：检查正则表达式中的转义符号，确保正确使用 `\` 来转义特殊字符。

让我们对之前的指南进行扩展，增加实际应用场景，并详细说明如何在这些场景中编写正则表达式，以便更好地理解和运用这些功能。

---

### 正则表达式使用指南（实际场景与丰富实例）

#### 1. 创建正则表达式对象
在真实开发中，正则表达式通常用于处理用户输入、搜索文本内容或进行数据验证。比如，在一个表单中验证电子邮件地址时，我们可以创建一个正则表达式来匹配正确的格式。

```actionscript
var regex:RegExp = new RegExp("[\\w.-]+@[\\w.-]+\\.\\w+", "");
```
这个正则表达式匹配有效的电子邮件地址格式，例如 `"example@test.com"`。`[\\w.-]+` 匹配用户名部分，`@` 匹配电子邮件中的 `@` 符号，`[\\w.-]+` 匹配域名部分，最后的 `\\.\\w+` 匹配顶级域名（如 `.com` 或 `.net`）。

### 2. 字符匹配
#### 实际应用场景：文本查找和替换
假设你正在开发一个文本编辑器，其中需要查找文本中所有出现的单词 "hello" 并替换为 "hi"。

**编写正则表达式**：
```actionscript
var regex:RegExp = new RegExp("hello", "g");
```
- **解释**：`hello` 匹配字面上的 "hello"。`g` 修饰符表示全局搜索，匹配文档中的所有 "hello"。

**实际使用**：
```actionscript
var text:String = "hello world, hello everyone!";
var newText:String = text.replace(regex, "hi");
trace(newText); // 输出 "hi world, hi everyone!"
```
这种方法可以用于快速替换文档中的内容。

### 3. 字符集
#### 实际应用场景：用户名验证
在用户注册表单中，你可能需要验证用户名只能包含字母和数字。你可以使用字符集来限制用户输入。

**编写正则表达式**：
```actionscript
var regex:RegExp = new RegExp("^[a-zA-Z0-9]+$", "");
```
- **解释**：`[a-zA-Z0-9]` 表示匹配任意大小写字母和数字。`^` 表示匹配字符串的开始，`$` 表示匹配字符串的结束，因此整个用户名必须由这些字符组成。

**实际使用**：
```actionscript
var username:String = "user123";
trace(regex.test(username)); // 输出 true，表示用户名有效
```

### 4. 否定字符集
#### 实际应用场景：过滤非法字符
如果你想确保输入内容不包含特定字符（如特殊符号），可以使用否定字符集。例如，限制输入不包含非字母字符。

**编写正则表达式**：
```actionscript
var regex:RegExp = new RegExp("[^a-zA-Z]", "");
```
- **解释**：`[^a-zA-Z]` 表示匹配非字母字符。

**实际使用**：
```actionscript
var input:String = "Hello!@#";
trace(regex.test(input)); // 输出 true，表示输入中有非法字符
```

### 5. 量词
#### 实际应用场景：密码强度验证
在注册系统中，你可能需要验证用户密码是否至少包含 8 个字符，并且包含字母和数字。

**编写正则表达式**：
```actionscript
var regex:RegExp = new RegExp("^(?=.*[a-zA-Z])(?=.*\\d)[a-zA-Z\\d]{8,}$", "");
```
- **解释**：`(?=.*[a-zA-Z])` 确保至少有一个字母，`(?=.*\\d)` 确保至少有一个数字，`[a-zA-Z\\d]{8,}` 表示长度至少为 8。

**实际使用**：
```actionscript
var password:String = "Passw0rd";
trace(regex.test(password)); // 输出 true，表示密码符合要求
```

### 6. 分组与捕获
#### 实际应用场景：解析日期格式
你可能需要从用户输入的日期中提取年、月和日。例如，解析输入 `"2024-09-30"`。

**编写正则表达式**：
```actionscript
var regex:RegExp = new RegExp("(\\d{4})-(\\d{2})-(\\d{2})", "");
```
- **解释**：`(\\d{4})` 捕获年份，`(\\d{2})` 捕获月份和日期，`-` 用于匹配分隔符。

**实际使用**：
```actionscript
var date:String = "2024-09-30";
var result:Array = regex.exec(date);
trace("Year: " + result[1]);  // 输出 "Year: 2024"
trace("Month: " + result[2]); // 输出 "Month: 09"
trace("Day: " + result[3]);   // 输出 "Day: 30"
```
分组捕获可以方便地将复杂字符串拆分为多个部分。

### 7. 逻辑或
#### 实际应用场景：多种输入格式匹配
假设你需要匹配电话号码，可以支持用户输入带或不带区号的格式，例如 "123-4567" 或 "010-123-4567"。

**编写正则表达式**：
```actionscript
var regex:RegExp = new RegExp("(\\d{3}-)?\\d{3}-\\d{4}", "");
```
- **解释**：`(\\d{3}-)?` 表示区号部分是可选的，`\\d{3}-\\d{4}` 匹配电话号码的主体部分。

**实际使用**：
```actionscript
var phoneNumber1:String = "123-4567";
var phoneNumber2:String = "010-123-4567";
trace(regex.test(phoneNumber1)); // 输出 true
trace(regex.test(phoneNumber2)); // 输出 true
```

### 8. 特殊字符
#### 实际应用场景：文件路径匹配
假设你正在处理文件路径时，需要识别路径中的特定字符（如 `.` 和 `/`）。

**编写正则表达式**：
```actionscript
var regex:RegExp = new RegExp("\\.\\w+$", "");
```
- **解释**：`\\.` 匹配点字符，`\\w+` 匹配文件扩展名，`$` 表示文件名末尾。

**实际使用**：
```actionscript
var filePath:String = "document.txt";
trace(regex.test(filePath)); // 输出 true，表示匹配文件扩展名
```

### 9. 测试和执行
#### 实际应用场景：验证和提取数据
`test()` 方法用于验证字符串是否符合正则表达式，`exec()` 用于提取匹配的内容。在复杂项目中，这两者经常结合使用。

例如，在用户输入时，你可以先使用 `test()` 验证输入是否合法，再使用 `exec()` 提取具体的内容。

```actionscript
var regex:RegExp = new RegExp("(\\d{4})-(\\d{2})-(\\d{2})", "");
var input:String = "2024-09-30";
if (regex.test(input)) {
    var result:Array = regex.exec(input);
    trace("Year: " + result[1]); // 输出年
}
```

### 10. 非贪婪量词
#### 实际应用场景：HTML 标签提取
在网页解析中，非贪婪量词可以避免过多的匹配。例如，提取 `div` 标签中的内容时，贪婪匹配可能会匹配多个 `div` 标签之间的内容，而非贪婪匹配只匹配第一个。

**编写正则表达式**：
```actionscript
var regex:RegExp = new RegExp("<div>.*?</div>", "g");
```
- **解释**：`.*?` 为非贪婪匹配，确保尽量少地匹配字符。

**实际使用**：
```actionscript
var html:String = "<div>First</div><div>Second</div>";
trace(html.match(regex)); // 输出 ["<div>First</div>", "<div>Second</div>"]
```

### 11. 匹配修饰符
#### 实际应用场景：忽略大小写的文本搜索
在需要匹配大小写不敏感的文本时，`i` 修饰符可以让正则表达式忽略大小写。例如，搜索文本中的单词 "Hello" 或 "hello"：

**编写正则表达式**：
```actionscript
var regex:RegExp = new RegExp("hello", "i");
```

**实际使用**：
```actionscript
trace(regex.test("Hello")); // 输出 true
trace(regex.test("hello")); // 输出 true
```

---

### 总结

通过这些实例，用户不仅能理解正则表达式的基础语法，还能学会如何在

实际项目中灵活运用这些功能，例如处理用户输入、解析数据、验证文本等。在编写正则表达式时，用户可以逐步构建复杂的模式，结合字符匹配、量词、分组、特殊字符等工具，快速高效地解决文本处理问题。

正则表达式是提升开发效率的有力工具，掌握它可以极大地减少处理文本相关任务的代码复杂度。


*/
import org.flashNight.gesh.regexp.*;

class org.flashNight.gesh.regexp.RegExp 
{
    private var pattern:String;
    private var flags:String;
    private var ast:ASTNode;
    private var ignoreCase:Boolean;
    private var global:Boolean;
    private var multiline:Boolean;
    public var lastIndex:Number = 0; // 新增属性
    private var totalGroups:Number; // 新增属性，记录总捕获组数

    public function RegExp(pattern:String, flags:String) {
        this.pattern = pattern;
        this.flags = flags;
        this.ignoreCase = flags.indexOf('i') >= 0;
        this.global = flags.indexOf('g') >= 0;
        this.multiline = flags.indexOf('m') >= 0;
        this.lastIndex = 0;
        this.parse();
    }

    private function parse():Void {
        try {
            var parser:Parser = new Parser(this.pattern);
            this.ast = parser.parse();
            this.totalGroups = parser.getTotalGroups(); // 获取总捕获组数
        } catch (e:Error) {
            trace("正则表达式解析错误：" + e.message);
            this.ast = null;
            this.totalGroups = 0;
        }
    }

    public function test(input:String):Boolean {
        if (this.ast == null) return false;
        var inputLength:Number = input.length;
        var startPos:Number = 0;
        if (this.pattern.charAt(0) == '^') {
            var captures:Array = initializeCaptures();
            var result:Object = this.ast.match(input, 0, captures, this.ignoreCase);
            return result.matched && result.position <= inputLength;
        } else {
            for (var pos:Number = 0; pos <= inputLength; pos++) {
                var captures:Array = initializeCaptures();
                var result:Object = this.ast.match(input, pos, captures, this.ignoreCase);
                if (result.matched) {
                    return true;
                }
            }
            return false;
        }
    }

    public function exec(input:String):Array {
        if (this.ast == null) return null;
        var inputLength:Number = input.length;
        var lastIndex:Number = this.global ? this.lastIndex : 0;
        for (var pos:Number = lastIndex; pos <= inputLength; pos++) {
            // Initialize captures array with nulls
            var captures:Array = initializeCaptures();
            var result:Object = this.ast.match(input, pos, captures, this.ignoreCase);
            if (result.matched) {
                captures[0] = input.substring(pos, result.position); // Entire match
                captures.index = pos;
                captures.input = input;
                if (this.global) {
                    this.lastIndex = result.position;
                }
                return captures;
            }
        }
        if (this.global) {
            this.lastIndex = 0;
        }
        return null;
    }

    // 新增方法：初始化 captures 数组
    private function initializeCaptures():Array {
        var captures:Array = new Array(this.totalGroups + 1);
        for (var i:Number = 0; i <= this.totalGroups; i++) {
            captures[i] = null;
        }
        return captures;
    }
}


// import org.flashNight.gesh.regexp.*;
// // 创建正则表达式对象
// var regex1:RegExp = new RegExp("a*b", "");
// trace("测试1：正则表达式 /a*b/ 匹配 'aaab'");
// trace(regex1.test("aaab")); // 输出 true

// var regex2:RegExp = new RegExp("(abc)+", "");
// trace("测试2：正则表达式 /(abc)+/ 匹配 'abcabc'");
// trace(regex2.test("abcabc")); // 输出 true

// var regex3:RegExp = new RegExp("[a-z]{3}", "");
// trace("测试3：正则表达式 /[a-z]{3}/ 匹配 'abc'");
// trace(regex3.test("abc")); // 输出 true

// var regex4:RegExp = new RegExp("a|b", "");
// trace("测试4：正则表达式 /a|b/ 匹配 'a'");
// trace(regex4.test("a")); // 输出 true

// trace("测试5：正则表达式 /a|b/ 匹配 'b'");
// trace(regex4.test("b")); // 输出 true

// var regex5:RegExp = new RegExp("a+", "");
// trace("测试6：正则表达式 /a+/ 匹配 'aa'");
// trace(regex5.test("aa")); // 输出 true

// var regex6:RegExp = new RegExp("a+", "");
// trace("测试7：正则表达式 /a+/ 匹配 ''");
// trace(regex6.test("")); // 输出 false

// // 测试 exec() 方法
// var regex7:RegExp = new RegExp("(a)(b)(c)", "");
// var result:Array = regex7.exec("abc");
// if (result != null) {
//     trace("测试8：正则表达式 /(a)(b)(c)/ 匹配 'abc'");
//     trace("匹配结果：" + result[0]); // 输出 'abc'
//     trace("捕获组1：" + result[1]); // 输出 'a'
//     trace("捕获组2：" + result[2]); // 输出 'b'
//     trace("捕获组3：" + result[3]); // 输出 'c'
// } else {
//     trace("测试8失败：未匹配");
// }

// // 测试字符集
// var regex8:RegExp = new RegExp("[^a-z]", "");
// trace("测试9：正则表达式 /[^a-z]/ 匹配 '1'");
// trace(regex8.test("1")); // 输出 true

// trace("测试10：正则表达式 /[^a-z]/ 匹配 'a'");
// trace(regex8.test("a")); // 输出 false

// // 测试11：嵌套分组和量词的组合
// var regex11:RegExp = new RegExp("(ab(c|d))*", "");



// // trace("测试11：正则表达式 /(ab(c|d))*/ 匹配 'abcdabcdabcc'");

// trace(regex11.test("abcdabcdabcc")); // 预期输出 true

// // 测试12：量词 {0}
// var regex12:RegExp = new RegExp("a{0}", "");
// trace("测试12：正则表达式 /a{0}/ 匹配 'abc'");
// trace(regex12.test("abc")); // 预期输出 true

// // 测试13：量词 {3,1}，n > m 的情况
// var regex13:RegExp = new RegExp("a{3,1}", "");
// trace("测试13：正则表达式 /a{3,1}/ 匹配 'aaa'");
// trace(regex13.test("aaa")); // 预期输出 false 或处理错误

// // 测试14：匹配空字符串
// var regex14:RegExp = new RegExp("^$", "");
// trace("测试14：正则表达式 /^$/ 匹配 ''");
// trace(regex14.test("")); // 预期输出 true

// // 测试15：量词允许零次匹配
// var regex15:RegExp = new RegExp("a*", "");


// // trace("测试15：正则表达式 /a*/ 匹配 ''");

// trace(regex15.test("")); // 预期输出 true

// // 测试16：任意字符匹配
// var regex16:RegExp = new RegExp("a.c", "");
// trace("测试16：正则表达式 /a.c/ 匹配 'abc'");
// trace(regex16.test("abc")); // 预期输出 true

// trace("测试17：正则表达式 /a.c/ 匹配 'a c'");
// trace(regex16.test("a c")); // 预期输出 true

// trace("测试18：正则表达式 /a.c/ 匹配 'abbc'");
// trace(regex16.test("abbc")); // 预期输出 false

// // 测试19：字符集和量词的组合
// var regex19:RegExp = new RegExp("[abc]+", "");
// trace("测试19：正则表达式 /[abc]+/ 匹配 'aaabbbcccabc'");
// trace(regex19.test("aaabbbcccabc")); // 预期输出 true

// // 测试20：否定字符集和量词的组合
// var regex20:RegExp = new RegExp("[^abc]+", "");
// trace("测试20：正则表达式 /[^abc]+/ 匹配 'defg'");
// trace(regex20.test("defg")); // 预期输出 true

// // 测试21：多个选择的组合
// var regex21:RegExp = new RegExp("a|b|c", "");
// trace("测试21：正则表达式 /a|b|c/ 匹配 'b'");
// trace(regex21.test("b")); // 预期输出 true

// trace("测试22：正则表达式 /a|b|c/ 匹配 'd'");
// trace(regex21.test("d")); // 预期输出 false

// // 测试23：量词嵌套的情况
// var regex23:RegExp = new RegExp("(a+)+", "");
// trace("测试23：正则表达式 /(a+)+/ 匹配 'aaa'");
// trace(regex23.test("aaa")); // 预期输出 true

// // 测试24：无法匹配的情况
// var regex24:RegExp = new RegExp("a{4}", "");
// trace("测试24：正则表达式 /a{4}/ 匹配 'aaa'");
// trace(regex24.test("aaa")); // 预期输出 false

// // 测试25：匹配长字符串
// var longString:String = "";
// for (var i:Number = 0; i < 1000; i++) {
//     longString += "a";
// }
// var regex25:RegExp = new RegExp("a{1000}", "");
// trace("测试25：正则表达式 /a{1000}/ 匹配 1000 个 'a'");
// trace(regex25.test(longString)); // 预期输出 true

// // 测试26：嵌套捕获组
// var regex26:RegExp = new RegExp("((a)(b(c)))", "");
// var result26:Array = regex26.exec("abc");
// if (result26 != null) {
//     trace("测试26：正则表达式 /((a)(b(c)))/ 匹配 'abc'");
//     trace("匹配结果：" + result26[0]); // 输出 'abc'
//     trace("捕获组1：" + result26[1]); // 输出 'abc'
//     trace("捕获组2：" + result26[2]); // 输出 'a'
//     trace("捕获组3：" + result26[3]); // 输出 'bc'
//     trace("捕获组4：" + result26[4]); // 输出 'c'
// } else {
//     trace("测试26失败：未匹配");
// }

// // 测试27：预定义字符类 \d
// var regex27:RegExp = new RegExp("\\d+", "");
// trace("测试27：正则表达式 /\\d+/ 匹配 '12345'");
// trace(regex27.test("12345")); // 预期输出 true

// // 测试28：预定义字符类 \D
// var regex28:RegExp = new RegExp("\\D+", "");
// trace("测试28：正则表达式 /\\D+/ 匹配 'abcDEF'");
// trace(regex28.test("abcDEF")); // 预期输出 true

// // 测试29：预定义字符类 \w
// var regex29:RegExp = new RegExp("\\w+", "");
// trace("测试29：正则表达式 /\\w+/ 匹配 'hello_world123'");
// trace(regex29.test("hello_world123")); // 预期输出 true

// // 测试30：预定义字符类 \W
// var regex30:RegExp = new RegExp("\\W+", "");
// trace("测试30：正则表达式 /\\W+/ 匹配 '!@#'");
// trace(regex30.test("!@#")); // 预期输出 true

// // 测试31：预定义字符类 \s
// var regex31:RegExp = new RegExp("\\s+", "");
// trace("测试31：正则表达式 /\\s+/ 匹配 '   '");
// trace(regex31.test("   ")); // 预期输出 true

// // 测试32：预定义字符类 \S
// var regex32:RegExp = new RegExp("\\S+", "");
// trace("测试32：正则表达式 /\\S+/ 匹配 'non-space'");
// trace(regex32.test("non-space")); // 预期输出 true

// // 测试33：转义字符 \n
// var regex33:RegExp = new RegExp("hello\\nworld", "");
// trace("测试33：正则表达式 /hello\\nworld/ 匹配 'hello\nworld'");
// trace(regex33.test("hello\nworld")); // 预期输出 true

// // 测试34：忽略大小写匹配
// var regex34:RegExp = new RegExp("abc", "i");
// trace("测试34：正则表达式 /abc/i 匹配 'AbC'");
// trace(regex34.test("AbC")); // 预期输出 true

// // 测试35：非贪婪量词
// var regex35:RegExp = new RegExp("a+?", "");
// trace("测试35：正则表达式 /a+?/ 匹配 'aaa'");
// var result35:Array = regex35.exec("aaa");
// if (result35 != null) {
//     trace("匹配结果：" + result35[0]); // 预期输出 'a'
// } else {
//     trace("测试35失败：未匹配");
// }

// // 测试36：非捕获分组
// var regex36:RegExp = new RegExp("a(?:bc)+", "");
// trace("测试36：正则表达式 /a(?:bc)+/ 匹配 'abcbc'");
// var result36:Array = regex36.exec("abcbc");
// if (result36 != null) {
//     trace("匹配结果：" + result36[0]); // 输出 'abcbc'
//     trace("捕获组数：" + (result36.length - 1)); // 预期为0，因为没有捕获组
// } else {
//     trace("测试36失败：未匹配");
// }

// // 测试37：嵌套捕获组
// var regex37:RegExp = new RegExp("(a(b(c)))", "");
// var result37:Array = regex37.exec("abc");
// if (result37 != null) {
//     trace("测试37：正则表达式 /(a(b(c)))/ 匹配 'abc'");
//     trace("匹配结果：" + result37[0]); // 预期输出 'abc'
//     trace("捕获组1：" + result37[1]); // 预期输出 'abc'
//     trace("捕获组2：" + result37[2]); // 预期输出 'bc'
//     trace("捕获组3：" + result37[3]); // 预期输出 'c'
// } else {
//     trace("测试37失败：未匹配");
// }

// // Test38: Backreference with single group
// var regex38:RegExp = new RegExp("(a)\\1", "");
// trace("测试38：正则表达式 /(a)\\1/ 匹配 'aa'");
// trace(regex38.test("aa")); // 预期输出 true

// // Test39: Backreference with multiple groups (should not match)
// var regex39:RegExp = new RegExp("(a)(b)\\1\\2", "");
// trace("测试39：正则表达式 /(a)(b)\\1\\2/ 匹配 'abba'");
// trace(regex39.test("abba")); // 预期输出 false

// // Test40: Backreference with multiple groups (should match)
// var regex40:RegExp = new RegExp("(a)(b)\\2\\1", "");
// trace("测试40：正则表达式 /(a)(b)\\2\\1/ 匹配 'abba'");
// trace(regex40.test("abba")); // 预期输出 true

// // Test41: Backreference with nested groups
// var regex41:RegExp = new RegExp("((a)b)\\1", "");
// trace("测试41：正则表达式 /((a)b)\\1/ 匹配 'abab'");
// trace(regex41.test("abab")); // 预期输出 true

// // Test42: Positive Lookahead (Assuming future support)
// var regex42:RegExp = new RegExp("a(?=b)", "");
// trace("测试42：正则表达式 /a(?=b)/ 匹配 'ab'");
// trace(regex42.test("ab")); // 预期输出 true

// trace("测试42：正则表达式 /a(?=b)/ 匹配 'ac'");
// trace(regex42.test("ac")); // 预期输出 false

// // Test43: Negative Lookahead (Assuming future support)
// var regex43:RegExp = new RegExp("a(?!b)", "");
// trace("测试43：正则表达式 /a(?!b)/ 匹配 'ac'");
// trace(regex43.test("ac")); // 预期输出 true

// trace("测试43：正则表达式 /a(?!b)/ 匹配 'ab'");
// trace(regex43.test("ab")); // 预期输出 false

// // Test44: Positive Lookbehind (Assuming future support)
// var regex44:RegExp = new RegExp("(?<=a)b", "");
// trace("测试44：正则表达式 /(?<=a)b/ 匹配 'ab'");
// trace(regex44.test("ab")); // 预期输出 true

// trace("测试44：正则表达式 /(?<=a)b/ 匹配 'cb'");
// trace(regex44.test("cb")); // 预期输出 false

// // Test45: Negative Lookbehind (Assuming future support)
// var regex45:RegExp = new RegExp("(?<!a)b", "");
// trace("测试45：正则表达式 /(?<!a)b/ 匹配 'cb'");
// trace(regex45.test("cb")); // 预期输出 true

// trace("测试45：正则表达式 /(?<!a)b/ 匹配 'ab'");
// trace(regex45.test("ab")); // 预期输出 false

// // Test46: Named Capturing Group (Assuming future support)
// var regex46:RegExp = new RegExp("(?<first>a)(?<second>b)", "");
// trace("测试46：正则表达式 /(?<first>a)(?<second>b)/ 匹配 'ab'");
// var result46:Array = regex46.exec("ab");
// if (result46 != null) {
//     trace("匹配结果：" + result46[0]); // 输出 'ab'
//     trace("捕获组1(first)：" + result46[1]); // 输出 'a'
//     trace("捕获组2(second)：" + result46[2]); // 输出 'b'
// } else {
//     trace("测试46失败：未匹配");
// }

// // Test47: Start and End Anchors with Multiline Flag
// var regex47:RegExp = new RegExp("^a", "m");
// trace("测试47：正则表达式 /^a/m 匹配 'a\\nb'");
// trace(regex47.test("a\nb")); // 预期输出 true

// var regex48:RegExp = new RegExp("b$", "m");
// trace("测试48：正则表达式 /b$/m 匹配 'a\\nb'");
// trace(regex48.test("a\nb")); // 预期输出 true

// // Test49: Unclosed Group
// try {
//     var regex49:RegExp = new RegExp("(a", "");
//     trace("测试49：正则表达式 /(a/ 匹配 'a'");
//     trace(regex49.test("a")); // 应该抛出错误
// } catch (e:Error) {
//     trace("测试49：捕获到错误 - " + e.message);
// }

// // Test50: Empty Pattern
// var regex50:RegExp = new RegExp("", "");
// trace("测试50：空模式 /''/ 匹配 'abc'");
// trace(regex50.test("abc")); // 预期输出 true

// // Test51: Pattern with Only Quantifiers
// try {
//     var regex51:RegExp = new RegExp("*", "");
//     trace("测试51：正则表达式 /*/ 匹配 'a'");
//     trace(regex51.test("a")); // 应该抛出错误
// } catch (e:Error) {
//     trace("测试51：捕获到错误 - " + e.message);
// }

// // Test52: Matching a Very Long String
// var longString10000:String = "";
// for (var j:Number = 0; j < 10000; j++) {
//     longString10000 += "a";
// }
// var regex52:RegExp = new RegExp("a{10000}", "");
// trace("测试52：正则表达式 /a{10000}/ 匹配 10000 个 'a'");
// trace(regex52.test(longString10000)); // 预期输出 true

// // Test53: Catastrophic Backtracking
// try {
//     var regex53:RegExp = new RegExp("(a+)+b", "");
//     trace("测试53：正则表达式 /(a+)+b/ 匹配 'aaaaa'");
//     trace(regex53.test("aaaaa")); // 应该返回 false without excessive backtracking
// } catch (e:Error) {
//     trace("测试53：捕获到错误 - " + e.message);
// }

// // Test54: Unicode Characters
// var regex54:RegExp = new RegExp("\\u0041", "");
// trace("测试54：正则表达式 /\\u0041/ 匹配 'A'");
// trace(regex54.test("A")); // 预期输出 true

// // Test55: Escaped Special Characters
// var regex55:RegExp = new RegExp("\\.", "");
// trace("测试55：正则表达式 /\\./ 匹配 '.'");
// trace(regex55.test(".")); // 预期输出 true

// trace("测试55：正则表达式 /\\./ 匹配 'a'");
// trace(regex55.test("a")); // 预期输出 false

/*

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


*/