### FNTL (FlashNight Text Language) - Technical Documentation

## Introduction

FNTL (FlashNight Text Language) is a human-readable configuration format based on TOML (Tom's Obvious, Minimal Language), designed specifically for the FlashNight project. Its purpose is to enable both developers and users (including non-technical users) to modify game configuration files easily. FNTL provides a syntax that is simple to read and write, with support for UTF-8 encoding, including Chinese characters, making it ideal for international use.

This document serves as a technical foundation for implementing, extending, and using FNTL. It outlines the core syntax, features, and best practices for managing configuration files within the FlashNight environment.

---

## Table of Contents

1. **Design Principles**
2. **Core Features**
3. **Syntax Overview**
4. **Key-Value Types**
5. **Tables and Nested Tables**
6. **Array Support**
7. **Table Arrays**
8. **Inline Tables**
9. **UTF-8 and Chinese Character Support**
10. **Escape Sequences**
11. **Date-Time Handling**
12. **Error Handling and Validation**
13. **Custom Extensions**
14. **Examples**
15. **Best Practices**
16. **FNTL in Action**
17. **Additional Examples**
18. **Frequently Asked Questions (FAQ)**
19. **Tools and Resources**
20. **Changelog**
21. **User Case Studies**
22. **Extended Topics**
23. **Appendix**

---

## 1. Design Principles

FNTL follows these core principles:

- **Human readability**: Files should be easy to read and modify by both developers and end-users. This is essential for user-editable game configurations.
- **UTF-8 support**: Fully supports international characters, especially Chinese, making it suitable for a global user base.
- **Compatibility**: FNTL syntax is backward compatible with TOML. Users familiar with TOML can easily adapt to FNTL.
- **Minimalism**: The syntax avoids unnecessary complexity, focusing on providing a clear structure that balances flexibility and simplicity.
- **Extendibility**: FNTL includes extensions such as support for more complex data types, configuration rules, and Chinese characters in keys, which TOML lacks.

---

## 2. Core Features

### Key Features of FNTL:

- **UTF-8 encoded**: Allows for keys and values in any language, including Chinese characters.
- **Readable and user-friendly**: Non-developers can easily edit and understand FNTL configurations.
- **Array and table support**: Allows for complex configurations to be structured clearly.
- **Inline table support**: For compact representation of simple objects.
- **Special types**: Including booleans, numbers, arrays, and dates.
- **Multiline strings**: Supports multiline strings for extended text values.
- **Commenting**: Like TOML, FNTL supports comments using `#`, making it easy to document configurations.

---

## 3. Syntax Overview

FNTL syntax closely mirrors TOML but includes extensions for supporting non-Latin keys and more flexible data structures.

### Basic structure:

- **Key-value pairs**: `key = value`
  - Keys can include Unicode characters, including Chinese.
  - Values can be of different types, such as strings, booleans, integers, floats, arrays, tables, and dates.

Example:
```fntl
# Game settings
游戏名称 = "FlashNight"
版本号 = 1.0
启用音效 = true
```

### Comments:
Comments begin with `#` and are ignored by the parser.

```fntl
# This is a comment explaining the setting below
volume = 80
```

---

## 4. Key-Value Types

### Strings:
Strings can be either basic strings or multiline strings.

#### Basic String:
```fntl
name = "John Doe"
```

#### Multiline String:
Multiline strings are enclosed in triple quotes.

```fntl
description = """This is a multiline
string that spans multiple lines."""
```

### Numbers:
Numbers in FNTL can be integers or floating-point values.

```fntl
max_players = 100
average_score = 89.75
```

### Booleans:
Booleans are represented as `true` or `false`.

```fntl
debug_mode = false
```

### Arrays:
Arrays hold multiple values of the same type, separated by commas and enclosed in square brackets.

```fntl
player_names = ["Alice", "Bob", "Charlie"]
```

### Dates:
FNTL supports ISO 8601 date-time format.

```fntl
last_played = 2023-09-25T08:30:00Z
```

---

## 5. Tables and Nested Tables

Tables are used to group related key-value pairs, represented with square brackets.

### Basic Table:
```fntl
[server]
ip = "192.168.1.1"
port = 8080
```

### Nested Tables:
Nested tables are represented by separating table names with dots.

```fntl
[database.connection]
server = "localhost"
port = 5432
```

---

## 6. Array Support

Arrays can store a list of values, enclosed in square brackets.

```fntl
inventory_items = ["sword", "shield", "potion"]
```

Arrays can also contain other arrays or objects.

---

## 7. Table Arrays

Table arrays allow multiple instances of a table to be defined, using double square brackets `[[...]]`.

```fntl
[[monsters]]
name = "Goblin"
level = 5

[[monsters]]
name = "Dragon"
level = 50
```

---

## 8. Inline Tables

Inline tables provide a compact way to represent small tables.

```fntl
player = { name = "Alice", score = 2500 }
```

---

## 9. UTF-8 and Chinese Character Support

FNTL fully supports UTF-8, allowing the use of any language, including Chinese characters, for both keys and values. This extension from TOML is critical for providing a seamless experience for users in different languages.

Example:
```fntl
[游戏设置]
难度 = "高"
```

### Implementation Details:

- **Keys**: Supports any UTF-8 characters, including Chinese, Japanese, Korean, etc.
- **Values**: String values also support any UTF-8 characters, ensuring seamless storage of multilingual content.
- **Comments**: Comments can also contain UTF-8 characters, facilitating documentation in the user's native language.

---

## 10. Escape Sequences

FNTL supports various escape sequences within strings, such as:

- `\n` for newline
- `\t` for tab
- `\"` for double-quote
- Unicode escape sequences via `\u` followed by four hexadecimal digits

Example:
```fntl
dialog = "He said, \"Hello!\""
greeting = "你好\n世界"  # Contains newline
```

---

## 11. Date-Time Handling

FNTL adheres to the ISO 8601 format for dates and times. It supports both local and UTC time, with the `Z` suffix indicating UTC.

```fntl
created_at = 2023-09-25T14:30:00Z
```

### Parsing Rules:

- **Date**: `YYYY-MM-DD`
- **Time**: `HH:MM:SS`, optional fractional seconds
- **Timezone**: `Z` for UTC or `+/-HH:MM` for local time

---

## 12. Error Handling and Validation

FNTL ensures that configuration files are validated before they are loaded into the application. It checks for:

- **Syntax errors**: Ensures the file adheres to FNTL syntax rules.
- **Data type validity**: Checks if the data types in key-value pairs are correct.
- **Missing required keys**: Ensures all necessary keys are present in the configuration.

### Error Reporting:

Error messages are user-friendly, aimed at non-technical users, especially when editing configuration files for games. They include line and column numbers to help users quickly locate and fix issues.

---

## 13. Custom Extensions

FNTL extends TOML in several ways:

- **UTF-8 keys and values**: Support for Chinese and other languages in both keys and values.
- **Flexible date formats**: Enhanced support for time zones and ISO 8601 dates.
- **Extended array handling**: More robust support for nested arrays.
- **Recursion Depth Limitation**: Sets a recursion depth limit (default 256) for parsing nested data structures to prevent performance issues or stack overflows.

These extensions make FNTL more flexible and adaptable, capable of meeting the needs of international users and complex configurations.

---

## 14. Examples

Here are a few examples to demonstrate the various features of FNTL:

### Game Settings Example:
```fntl
# Game settings
游戏名称 = "FlashNight"
版本号 = 1.0
启用音效 = true

[玩家]
名字 = "李雷"
最高分 = 4500

[[道具]]
名字 = "剑"
价格 = 100

[[道具]]
名字 = "盾"
价格 = 150
```

### Advanced Configuration Example:
```fntl
# Server configuration
[服务器]
IP地址 = "192.168.1.1"
端口 = 8080

[数据库.连接]
类型 = "PostgreSQL"
端口 = 5432
启用连接池 = true

[[敌人]]
名字 = "哥布林"
等级 = 5

[[敌人]]
名字 = "龙"
等级 = 50

玩家 = { 名字 = "张三", 分数 = 3000, 等级 = 15 }
```

### Complex Nested Structure Example:
```fntl
# Comprehensive game configuration
[游戏设置]
游戏名称 = "FlashNight"
版本号 = 2.1
启用音效 = true
语言 = "中文"

[服务器]
IP地址 = "10.0.0.1"
端口 = 9090

[数据库.连接]
类型 = "MySQL"
IP地址 = "10.0.0.2"
端口 = 3306
用户名 = "admin"
密码 = "password123"

[[关卡]]
名称 = "森林探险"
难度 = "中等"
奖励 = [100, 200, 300]

[[关卡]]
名称 = "沙漠之旅"
难度 = "困难"
奖励 = [500, 600, 700]

玩家 = { 名字 = "王五", 分数 = 7500, 等级 = 20 }
```

### Error Example:
```fntl
# Incorrect configuration
游戏名称 = "FlashNight
版本号 = 1.0
启用音效 = true
```
*Explanation*: The `游戏名称` string is not closed with a double quote.

---

## 15. Best Practices

- **Use clear key names**: Always use meaningful, descriptive key names, especially when writing configurations meant for non-technical users.
- **Comment your configurations**: Adding comments helps users understand the purpose of each configuration setting.
- **Keep tables organized**: Nested tables should be used to group related configurations logically.
- **Use UTF-8 encoding**: Ensure all FNTL files are saved with UTF-8 encoding to avoid issues with special characters.
- **Avoid deep nesting**: Adhere to the recursion depth limit to maintain readability and performance.
- **Validate configurations**: Regularly validate your FNTL files to catch and fix errors early.
- **Backup configurations**: Keep backups of working configuration files before making significant changes.

---

## 16. FNTL in Action

FNTL is integrated into the FlashNight project’s configuration system. Users can easily edit settings via external configuration files, without the need to modify the game code directly. The format is designed to be intuitive and forgiving, making it accessible to both technical and non-technical users alike.

### Workflow:

1. **Create Configuration File**: Users can create or modify `.fntl` files using any text editor.
2. **Edit Configuration Items**: Change key-value pairs, add tables or arrays as needed.
3. **Save File**: Ensure the file is saved with UTF-8 encoding.
4. **Load Configuration**: The game loads the `.fntl` file during startup or runtime and applies the configuration settings.

### Example Application:

A user wants to change the game's difficulty settings. They can edit the `config.fntl` file as follows:

```fntl
[游戏设置]
难度 = "中等"
最大玩家数 = 150
```

After saving the file, the game will adjust the difficulty level and maximum number of players based on the new configuration.

---

## 17. Additional Examples

### 17.1 Complex Nested Tables

```fntl
# Comprehensive server configuration
[服务器]
名称 = "主服务器"
IP地址 = "192.168.100.1"
端口 = 8080

[服务器.数据库]
类型 = "MongoDB"
IP地址 = "192.168.100.2"
端口 = 27017
用户名 = "dbadmin"
密码 = "securepassword"

[服务器.数据库.选项]
连接池大小 = 20
超时时间 = 30
```

### 17.2 Error Configuration Example

```fntl
# Incorrect data type
玩家分数 = "高"  # 应为数字类型

# Missing equals sign
游戏名称 "FlashNight"

# Invalid date format
创建时间 = 2023/09/25 14:30:00
```

*Explanation*:
- `玩家分数` 应该是数字类型，但被赋值为字符串 `"高"`。
- `游戏名称` 缺少等号 `=`
- `创建时间` 日期格式不符合 ISO 8601 标准。

### 17.3 User-Specific Configuration

```fntl
# User-specific settings
[用户]
用户名 = "用户123"
语言 = "中文"
主题 = "暗色模式"

[[用户.权限]]
角色 = "管理员"
级别 = 10

[[用户.权限]]
角色 = "玩家"
级别 = 1
```

---

## 18. Frequently Asked Questions (FAQ)

### 18.1 Can I use non-Chinese characters in keys?

**Yes.** FNTL supports any UTF-8 characters in both keys and values, allowing the use of various languages, including Chinese, Japanese, Korean, and more.

### 18.2 What encoding should I use for FNTL files?

**UTF-8** encoding is required for FNTL files to ensure proper handling of all supported characters.

### 18.3 How do I handle special characters in strings?

Use escape sequences such as `\n` for newlines, `\t` for tabs, `\"` for double quotes, and `\uXXXX` for Unicode characters.

### 18.4 What happens if my configuration file has a syntax error?

FNTL parsers will provide an error message indicating the line and column where the error occurred, helping you quickly locate and fix the issue.

### 18.5 Can FNTL handle nested arrays?

**Yes.** FNTL supports nested arrays, allowing for complex data structures.

### 18.6 Is there a limit to how deeply I can nest tables?

FNTL sets a default recursion depth limit of 256 to prevent performance issues or stack overflows. Avoid excessive nesting to maintain readability and performance.

### 18.7 How do I validate my FNTL file?

Use FNTL-compatible validation tools or parsers integrated into your development environment to check for syntax and data type errors.

### 18.8 Can I convert TOML files to FNTL?

**Yes.** Since FNTL is backward compatible with TOML, you can rename `.toml` files to `.fntl` and extend them with UTF-8 characters as needed. However, ensure that your parser handles the extended features properly.

---

## 19. Tools and Resources

### 19.1 Recommended Text Editors

- **Visual Studio Code**: Offers extensive support for UTF-8 encoding and syntax highlighting through extensions.
- **Sublime Text**: Lightweight editor with excellent UTF-8 support and customizable syntax highlighting.
- **Notepad++**: Free editor that supports multiple languages and encodings, including UTF-8.

### 19.2 Validation Tools

- **FNTL Validator**: A command-line tool to validate FNTL files against syntax rules.
- **Online Validators**: Websites offering online FNTL validation and syntax checking.

### 19.3 Parsing Libraries

- **FNTL Parser**: Custom parsing library developed for FNTL.
- **TOML Libraries**: Existing TOML parsers can be extended to support FNTL's additional features.

---

## 20. Changelog

### Version 1.0

- Initial release of FNTL (FlashNight Text Language).
- Based on TOML with extensions for UTF-8 and Chinese character support.
- Added support for key-value pairs, tables, nested tables, arrays, table arrays, inline tables, multiline strings, and comments.
- Implemented error handling and validation mechanisms.
- Provided comprehensive examples and best practices.

---

## 21. User Case Studies

### 21.1 Successful Configuration by Non-Technical Users

**Scenario**: A user wanted to customize the in-game settings to better suit their preferences without any technical knowledge.

**Action**:
1. Opened the `config.fntl` file using Notepad++.
2. Edited the `难度` (difficulty) key to `"中等"`.
3. Changed the `最大玩家数` (max players) to `150`.
4. Saved the file with UTF-8 encoding.

**Outcome**: Upon restarting the game, the difficulty level adjusted to medium, and the maximum number of players increased, providing a better gaming experience tailored to the user's preferences.

### 21.2 Developer Enhancements with FNTL

**Scenario**: Developers needed a flexible way to manage multiple configurations for different game environments (development, staging, production).

**Action**:
1. Created separate `.fntl` files for each environment.
2. Utilized nested tables to organize environment-specific settings.
3. Implemented table arrays to manage lists of game objects, such as enemies and items.

**Outcome**: Streamlined the configuration management process, allowing developers to switch between environments effortlessly and maintain organized, scalable configuration files.

### 21.3 Localization Support

**Scenario**: The game was being localized into multiple languages, requiring configurations to support various character sets.

**Action**:
1. Leveraged FNTL's UTF-8 support to create configuration files in different languages.
2. Used Chinese characters for Chinese localization files, and other scripts for additional languages.
3. Maintained consistent configuration structures across different language files.

**Outcome**: Enabled seamless localization of game settings, ensuring that players from different regions could easily understand and modify their game configurations in their native languages.

---

## 22. Extended Topics

### 22.1 Security Considerations

When allowing users to edit configuration files, it's essential to consider the security implications:

- **Input Validation**: Ensure that all user inputs are validated to prevent injection attacks or malformed configurations that could crash the game.
- **Access Control**: Restrict access to sensitive configuration settings to prevent unauthorized modifications.
- **Backup Configurations**: Encourage users to keep backups of their configuration files before making changes to recover from accidental errors.
- **Sanitize Inputs**: Strip or escape any potentially harmful characters or scripts embedded within the configuration files.

### 22.2 Internationalization and Localization

FNTL's support for UTF-8 and non-Latin characters makes it ideal for internationalization (i18n) and localization (l10n):

- **Language-Specific Keys**: Use keys that are meaningful in the target language to enhance user understanding.
- **Consistent Formatting**: Maintain a consistent structure across different language configuration files to simplify maintenance.
- **Date and Time Formats**: Support various date and time formats as per regional standards by leveraging FNTL's flexible date-time handling.

### 22.3 Performance Optimization

For large and complex FNTL files, consider the following optimizations:

- **Lazy Loading**: Load only necessary sections of the configuration when required to reduce memory usage.
- **Caching**: Implement caching mechanisms to avoid repeated parsing of unchanged configuration files.
- **Efficient Parsing**: Optimize the lexer and parser to handle large files with minimal performance overhead.

### 22.4 Extending Data Types

Based on project requirements, FNTL can be extended to support additional data types:

- **Enums**: Define enumerated types for restricted value sets.
- **Custom Objects**: Allow user-defined objects with specific validation rules.
- **Binary Data**: Support binary data encoding for complex data structures.

### 22.5 Integration with Development Tools

Enhance the developer experience by integrating FNTL with development tools:

- **Syntax Highlighting**: Develop syntax highlighting for popular text editors to improve readability.
- **Auto-Completion**: Implement auto-completion features for commonly used keys and structures.
- **Linting Tools**: Create linting tools to automatically detect and suggest fixes for configuration issues.

---

## 23. Appendix

### Appendix A: FNTL vs. TOML Comparison

| Feature               | TOML                      | FNTL                                 |
|-----------------------|---------------------------|--------------------------------------|
| **Character Set Support** | ASCII only                | Full UTF-8 support, including Chinese |
| **File Extension**       | `.toml`                   | `.fntl`                               |
| **Comment Support**      | Supports `#` comments     | Supports `#` comments                 |
| **Table Representation** | Single and nested tables  | Single and nested tables with Chinese names |
| **Inline Tables**        | Supported                 | Supported                             |
| **Array Support**        | Supported                 | Supported with enhanced nested array handling |
| **Date-Time Format**     | ISO 8601                  | ISO 8601 with enhanced timezone support |
| **Escape Sequences**     | Basic escape sequences    | Extended escape sequences, including Unicode escapes |
| **Recursion Depth Limit**| No explicit limit         | Default limit set to 256 to prevent deep nesting issues |

### Appendix B: Glossary

- **UTF-8**: A variable-width character encoding used for electronic communication, capable of encoding all possible characters (code points) in Unicode.
- **ISO 8601**: An international standard covering the exchange of date and time-related data.
- **Inline Table**: A table that is defined within a single line, useful for small collections of key-value pairs.
- **Table Array**: A collection of tables with the same name, allowing multiple instances of similar data structures.

### Appendix C: References

- **TOML Official Documentation**: [https://toml.io/en/](https://toml.io/en/)
- **Unicode Standard**: [https://www.unicode.org/standard/standard.html](https://www.unicode.org/standard/standard.html)
- **ISO 8601 Standard**: [https://www.iso.org/iso-8601-date-and-time-format.html](https://www.iso.org/iso-8601-date-and-time-format.html)

---

# FNTL（FlashNight Text Language）技术文档

## 引言

FNTL（FlashNight Text Language）是一种基于TOML（Tom's Obvious, Minimal Language）的可读性高的配置格式，专为FlashNight项目设计。其目的是让开发者和用户（包括非技术用户）能够轻松修改游戏配置文件。FNTL提供了简单易读易写的语法，支持UTF-8编码，包括中文字符，非常适合国际化使用。

本文档作为实施、扩展和使用FNTL的技术基础，概述了核心语法、功能以及在FlashNight环境中管理配置文件的最佳实践。

---

## 目录

1. **设计原则**
2. **核心功能**
3. **语法概述**
4. **键值类型**
5. **表格与嵌套表格**
6. **数组支持**
7. **表格数组**
8. **内联表格**
9. **UTF-8与中文字符支持**
10. **转义序列**
11. **日期时间处理**
12. **错误处理与验证**
13. **自定义扩展**
14. **示例**
15. **最佳实践**
16. **FNTL在项目中的应用**
17. **附加示例**
18. **常见问题（FAQ）**
19. **工具与资源**
20. **版本更新记录**
21. **用户案例研究**
22. **扩展主题**
23. **附录**

---

## 1. 设计原则

FNTL遵循以下核心原则：

- **人类可读性**：文件应易于阅读和修改，适合开发者和最终用户，特别是非技术用户编辑游戏配置。
- **UTF-8支持**：全面支持国际字符集，尤其是中文，适用于全球用户群体。
- **兼容性**：FNTL语法与TOML保持向后兼容。熟悉TOML的用户可以轻松适应FNTL。
- **简约主义**：语法避免不必要的复杂性，专注于提供清晰的结构，平衡灵活性与简洁性。
- **可扩展性**：FNTL包括对更复杂数据类型、配置规则和中文键名的支持，这些是TOML所缺乏的。

---

## 2. 核心功能

### FNTL的主要功能：

- **UTF-8编码**：支持任何语言的键和值，包括中文字符。
- **可读性与用户友好**：非开发者可以轻松编辑和理解FNTL配置。
- **数组与表格支持**：允许将复杂配置清晰地结构化。
- **内联表格支持**：用于简单对象的紧凑表示。
- **特殊类型支持**：包括布尔值、数字、数组、日期等。
- **多行字符串**：支持多行字符串以存储扩展文本值。
- **注释**：类似于TOML，FNTL支持使用`#`进行注释，便于文档化配置。

---

## 3. 语法概述

FNTL语法与TOML非常相似，但扩展了对非拉丁字符（如中文）的支持，以适应更广泛的字符集需求。

### 基本结构：

- **键值对**：`键 = 值`
  - 键可以包含Unicode字符，包括中文。
  - 值可以是不同的数据类型，如字符串、布尔值、整数、浮点数、数组、表格和日期。

示例：
```fntl
# 游戏设置
游戏名称 = "FlashNight"
版本号 = 1.0
启用音效 = true
```

### 注释：

注释以`#`开头，解析器会忽略注释内容。

```fntl
# 这是一个注释，解释下面的设置
音量 = 80
```

---

## 4. 键值类型

### 字符串：

字符串可以是基本字符串或多行字符串。

#### 基本字符串：
```fntl
名字 = "张三"
```

#### 多行字符串：
多行字符串使用三个引号包围。

```fntl
描述 = """这是一个多行描述的例子，
它跨越了多行。"""
```

### 数字：

FNTL中的数字可以是整数或浮点数。

```fntl
最大玩家数 = 100
平均分数 = 89.75
```

### 布尔值：

布尔值用`true`或`false`表示。

```fntl
调试模式 = false
```

### 数组：

数组包含相同类型的多个值，用逗号分隔并用方括号包围。

```fntl
玩家名字 = ["李雷", "韩梅梅", "小明"]
```

### 日期：

FNTL支持ISO 8601日期时间格式。

```fntl
最后登录时间 = 2024-10-09T08:30:00Z
```

---

## 5. 表格与嵌套表格

表格用于将相关的键值对分组，使用方括号表示。

### 基本表格：
```fntl
[服务器]
IP = "192.168.1.1"
端口 = 8080
```

### 嵌套表格：
嵌套表格通过点号分隔表名。

```fntl
[数据库.连接]
类型 = "PostgreSQL"
端口 = 5432
```

---

## 6. 数组支持

数组可以存储多个相同类型的值，用方括号包围，值之间用逗号分隔。

```fntl
库存物品 = ["剑", "盾", "药水"]
```

数组还可以包含其他数组或对象。

---

## 7. 表格数组

表格数组允许定义多个同名的表格实例，使用双方括号`[[...]]`表示。

```fntl
[[敌人]]
名字 = "哥布林"
等级 = 5

[[敌人]]
名字 = "龙"
等级 = 50
```

---

## 8. 内联表格

内联表格提供了一种紧凑的方式来表示小型表格。

```fntl
玩家 = { 名字 = "李四", 分数 = 2500 }
```

---

## 9. UTF-8与中文字符支持

FNTL完全支持UTF-8，允许在键和值中使用任何语言的字符，包括中文。这一扩展是FNTL相对于TOML的关键优势，确保本地化用户体验。

示例：
```fntl
[游戏设置]
难度 = "高"
```

### 具体实现：

- **键名**：支持任何UTF-8字符，包括中文、日文、韩文等。
- **值**：字符串值也支持任何UTF-8字符，确保多语言内容的无缝存储。
- **注释**：注释中也可以包含UTF-8字符，便于用母语进行文档化。

---

## 10. 转义序列

FNTL支持在字符串中的多种转义序列，例如：

- `\n` 表示换行
- `\t` 表示制表符
- `\"` 和 `\'` 表示引号
- Unicode转义序列通过`\u`后跟四个十六进制数字表示

示例：
```fntl
问候 = "你好\n世界"  # 包含换行符的字符串
引用 = "他说，\"你好！\""  # 包含引号的字符串
```

---

## 11. 日期时间处理

FNTL遵循ISO 8601格式进行日期和时间的表示，支持本地时间和UTC时间，`Z`后缀表示UTC时间。

```fntl
创建时间 = 2023-09-25T14:30:00Z
```

### 解析规则：

- **日期**：`YYYY-MM-DD`
- **时间**：`HH:MM:SS`，可选的毫秒部分
- **时区**：`Z`表示UTC时间，或`+/-HH:MM`表示本地时间

---

## 12. 错误处理与验证

FNTL确保在加载配置文件前进行验证，检查以下内容：

- **语法错误**：确保文件符合FNTL语法规范。
- **数据类型有效性**：检查键值对中的数据类型是否正确。
- **必需键缺失**：确保配置文件中包含所有必需的键。

### 错误报告：

错误信息应友好，便于非技术用户理解并修复配置文件中的问题。错误信息包括行号和列号，帮助用户快速定位问题。

---

## 13. 自定义扩展

FNTL在TOML的基础上进行了多项扩展：

- **UTF-8键和值**：支持中文及其他语言的键名和值，增强了多语言支持。
- **灵活的日期格式**：增强了对时区和ISO 8601日期的支持，适应不同地区的时间表示需求。
- **扩展的数组处理**：更健壮地支持嵌套数组，满足复杂配置的需求。
- **递归深度限制**：为解析嵌套数据结构设置递归深度限制（默认256），防止过深的嵌套导致性能问题或栈溢出。

这些扩展使FNTL更具灵活性和适应性，能够满足国际化用户和复杂配置需求。

---

## 14. 示例

以下是一些示例，展示了FNTL的各种特性：

### 游戏设置示例：
```fntl
# 游戏设置
游戏名称 = "FlashNight"
版本号 = 1.0
启用音效 = true

[玩家]
名字 = "李雷"
最高分 = 4500

[[道具]]
名字 = "剑"
价格 = 100

[[道具]]
名字 = "盾"
价格 = 150
```

---

## 15. 最佳实践

- **使用清晰的键名**：始终使用有意义且描述性的键名，特别是在为非技术用户编写的配置中。
- **添加注释**：通过注释帮助用户理解每个配置项的用途。
- **组织表格**：使用嵌套表格合理地分组相关配置，保持结构清晰。
- **确保UTF-8编码**：确保所有FNTL文件均以UTF-8编码保存，以避免特殊字符问题。
- **避免过深的嵌套**：遵循递归深度限制，保持配置文件的可读性和性能。
- **验证配置**：定期使用验证工具检查配置文件的正确性。
- **备份配置文件**：在进行重大更改前备份现有配置文件，以便在需要时恢复。

---

## 16. FNTL在项目中的应用

FNTL集成于FlashNight项目的配置系统中，用户可以通过外部配置文件轻松编辑设置，无需直接修改游戏代码。其设计直观且包容性强，适合技术和非技术用户使用。

### 使用流程：

1. **创建配置文件**：用户可以使用文本编辑器创建或修改`.fntl`文件。
2. **编辑配置项**：根据需要更改键值对、添加表格或数组。
3. **保存文件**：确保文件以UTF-8编码保存。
4. **加载配置**：游戏在启动或运行时加载`.fntl`文件，并应用配置设置。

### 示例应用：

用户希望修改游戏的难度设置，只需编辑`config.fntl`文件中的相应键值：

```fntl
[游戏设置]
难度 = "中等"
最大玩家数 = 150
```

保存后，游戏将根据新的配置重新调整难度和玩家数量。

---

## 17. 附加示例

### 17.1 复杂嵌套表格

```fntl
# 综合服务器配置
[服务器]
名称 = "主服务器"
IP地址 = "192.168.100.1"
端口 = 8080

[服务器.数据库]
类型 = "MongoDB"
IP地址 = "192.168.100.2"
端口 = 27017
用户名 = "dbadmin"
密码 = "securepassword"

[服务器.数据库.选项]
连接池大小 = 20
超时时间 = 30
```

### 17.2 错误配置示例

```fntl
# 错误配置示例
玩家分数 = "高"  # 应为数字类型

# 缺少等号
游戏名称 "FlashNight"

# 无效的日期格式
创建时间 = 2023/09/25 14:30:00
```
*解释*：
- `玩家分数` 应该是数字类型，但被赋值为字符串 `"高"`。
- `游戏名称` 缺少等号 `=`
- `创建时间` 日期格式不符合 ISO 8601 标准。

### 17.3 用户特定配置

```fntl
# 用户特定设置
[用户]
用户名 = "用户123"
语言 = "中文"
主题 = "暗色模式"

[[用户.权限]]
角色 = "管理员"
级别 = 10

[[用户.权限]]
角色 = "玩家"
级别 = 1
```

---

## 18. 常见问题（FAQ）

### 18.1 我可以在键名中使用非中文字符吗？

**可以。** FNTL支持在键名和值中使用任何UTF-8字符，包括中文、日文、韩文等。

### 18.2 我应该使用什么编码保存FNTL文件？

**UTF-8**编码是必需的，以确保FNTL文件能够正确处理所有支持的字符。

### 18.3 如何在字符串中处理特殊字符？

使用转义序列，如 `\n` 表示换行，`\t` 表示制表符，`\"` 表示双引号，`\uXXXX` 表示Unicode字符。

### 18.4 如果我的配置文件有语法错误，会发生什么？

FNTL解析器会提供包含错误行号和列号的错误信息，帮助您快速定位并修复问题。

### 18.5 FNTL能处理嵌套数组吗？

**可以。** FNTL支持嵌套数组，允许创建复杂的数据结构。

### 18.6 表格的嵌套深度有限制吗？

FNTL设置了默认的递归深度限制为256，以防止过深的嵌套导致性能问题。建议避免过度嵌套，以保持配置文件的可读性和性能。

### 18.7 如何验证我的FNTL文件？

使用FNTL兼容的验证工具或集成在开发环境中的解析器来检查语法和数据类型错误。

### 18.8 我可以将TOML文件转换为FNTL吗？

**可以。** 由于FNTL与TOML语法向后兼容，您可以将`.toml`文件重命名为`.fntl`并根据需要扩展它们以支持UTF-8字符。不过，请确保您的解析器能够正确处理FNTL的扩展特性。

---

## 19. 工具与资源

### 19.1 推荐的文本编辑器

- **Visual Studio Code**：通过扩展提供广泛的UTF-8编码和语法高亮支持。
- **Sublime Text**：轻量级编辑器，支持优秀的UTF-8编码和可定制的语法高亮。
- **Notepad++**：免费编辑器，支持多种语言和编码，包括UTF-8。

### 19.2 验证工具

- **FNTL Validator**：一个命令行工具，用于根据语法规则验证FNTL文件。
- **在线验证器**：提供在线FNTL验证和语法检查的网站。

### 19.3 解析库

- **FNTL Parser**：专为FNTL开发的自定义解析库。
- **TOML库**：现有的TOML解析库可以扩展以支持FNTL的附加功能。

---

## 20. 版本更新记录

### 版本 1.0

- 发布FNTL（FlashNight Text Language）初始版本。
- 基于TOML，增加了UTF-8和中文字符支持的扩展。
- 添加了键值对、表格、嵌套表格、数组、表格数组、内联表格、多行字符串和注释的支持。
- 实现了错误处理和验证机制。
- 提供了全面的示例和最佳实践。

---

## 21. 用户案例研究

### 21.1 非技术用户成功配置

**场景**：一名用户希望根据个人偏好自定义游戏设置，但没有任何技术知识。

**操作**：
1. 使用Notepad++打开`config.fntl`文件。
2. 将`难度`键的值改为 `"中等"`。
3. 将`最大玩家数`改为 `150`。
4. 保存文件，确保使用UTF-8编码。

**结果**：重启游戏后，难度等级调整为中等，最大玩家数增加，用户获得了更符合自己需求的游戏体验。

### 21.2 开发者使用FNTL进行增强

**场景**：开发者需要一种灵活的方式来管理不同游戏环境（开发、测试、生产）的配置。

**操作**：
1. 为每个环境创建单独的`.fntl`文件。
2. 利用嵌套表格组织环境特定的设置。
3. 使用表格数组管理敌人和物品列表。

**结果**：配置管理流程更加简化，开发者能够轻松切换环境，并维护有组织、可扩展的配置文件。

### 21.3 本地化支持

**场景**：游戏需要本地化到多个语言，配置需要支持各种字符集。

**操作**：
1. 利用FNTL的UTF-8支持创建不同语言的配置文件。
2. 为中文本地化文件使用中文字符，其他语言使用相应的脚本。
3. 在不同语言文件中保持一致的配置结构。

**结果**：实现了游戏设置的无缝本地化，确保来自不同地区的玩家能够轻松理解和修改配置文件，提升了用户体验。

---

## 22. 扩展主题

### 22.1 安全性考虑

允许用户编辑配置文件时，需要考虑以下安全性问题：

- **输入验证**：确保所有用户输入经过验证，防止注入攻击或导致游戏崩溃的错误配置。
- **访问控制**：限制对敏感配置设置的访问，防止未经授权的修改。
- **备份配置**：鼓励用户在进行重大更改前备份配置文件，以便在需要时恢复。
- **清理输入**：去除或转义配置文件中的潜在有害字符或脚本。

### 22.2 国际化与本地化

FNTL的UTF-8和非拉丁字符支持使其非常适合国际化（i18n）和本地化（l10n）：

- **语言特定键名**：使用目标语言中有意义的键名，增强用户理解。
- **一致的格式**：在不同语言的配置文件中保持一致的结构，简化维护。
- **日期和时间格式**：利用FNTL灵活的日期时间处理，支持各地区的时间表示标准。

### 22.3 性能优化

对于大型和复杂的FNTL文件，可以考虑以下优化：

- **懒加载**：仅在需要时加载配置文件的必要部分，减少内存使用。
- **缓存**：实现缓存机制，避免重复解析未更改的配置文件。
- **高效解析**：优化词法分析器和解析器，提高解析大型文件的性能。

### 22.4 扩展数据类型

根据项目需求，FNTL可以扩展支持更多的数据类型：

- **枚举类型**：定义受限值集的枚举类型。
- **自定义对象**：允许用户定义具有特定验证规则的对象。
- **二进制数据**：支持二进制数据编码，用于复杂的数据结构。

### 22.5 与开发工具集成

通过与开发工具集成，提升开发者体验：

- **语法高亮**：为流行的文本编辑器开发语法高亮功能，提升可读性。
- **自动完成**：实现常用键和结构的自动完成功能，提高编辑效率。
- **代码检查工具**：创建代码检查工具，自动检测和建议配置问题的修复。

---

## 23. 附录

### 附录A: FNTL与TOML的对比

| 特性               | TOML                      | FNTL                                 |
|--------------------|---------------------------|--------------------------------------|
| **字符集支持**     | 仅支持ASCII                | 完全支持UTF-8，包括中文字符           |
| **文件扩展名**     | `.toml`                   | `.fntl`                               |
| **注释支持**       | 支持 `#` 注释              | 支持 `#` 注释                         |
| **表格表示**       | 单层与嵌套表格            | 单层与嵌套表格，同时支持中文表名       |
| **内联表格**       | 支持                      | 支持                                  |
| **数组支持**       | 支持                      | 支持，增强了嵌套数组处理               |
| **日期时间格式**   | ISO 8601                  | ISO 8601，增强了时区支持               |
| **转义序列**       | 支持基本转义              | 支持更多转义序列，包括Unicode转义       |
| **递归深度限制**   | 无明确限制                | 默认256，防止过深嵌套导致性能问题        |

### 附录B: 术语表

- **UTF-8**：一种可变长度字符编码，用于电子通信，能够编码Unicode中的所有字符（码点）。
- **ISO 8601**：涵盖日期和时间相关数据交换的国际标准。
- **内联表格**：在单行中定义的表格，用于存储小型的键值对集合。
- **表格数组**：具有相同名称的多个表格的集合，允许多个实例的数据结构。

### 附录C: 参考资料

- **TOML官方文档**：[https://toml.io/en/](https://toml.io/en/)
- **Unicode标准**：[https://www.unicode.org/standard/standard.html](https://www.unicode.org/standard/standard.html)
- **ISO 8601标准**：[https://www.iso.org/iso-8601-date-and-time-format.html](https://www.iso.org/iso-8601-date-and-time-format.html)

---




var test:org.flashNight.gesh.fntl.FNTLLexerTest = new org.flashNight.gesh.fntl.FNTLLexerTest();

// 调用测试方法，运行所有测试用例
test.runAllTests();

