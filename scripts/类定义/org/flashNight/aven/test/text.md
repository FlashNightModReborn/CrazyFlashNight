# 测试框架计划与设计文档

## 目录

1. [引言](#引言)
2. [目标与规划](#目标与规划)
3. [架构设计](#架构设计)
   - [核心组件](#核心组件)
   - [辅助组件](#辅助组件)
   - [扩展与插件](#扩展与插件)
4. [组织结构](#组织结构)
   - [文件结构](#文件结构)
   - [类关系图](#类关系图)
5. [实现思路](#实现思路)
   - [AS2 技术限制与应对](#as2-技术限制与应对)
   - [模块化设计原则](#模块化设计原则)
6. [使用指南](#使用指南)
   - [编写测试用例](#编写测试用例)
   - [创建测试套件](#创建测试套件)
   - [配置测试运行器](#配置测试运行器)
   - [运行测试](#运行测试)
7. [下一步计划](#下一步计划)
   - [实现辅助模块](#实现辅助模块)
   - [增强框架功能](#增强框架功能)
8. [结论](#结论)

## 引言

本文件旨在详细描述 `org.flashNight.aven.test` 测试框架的计划、架构、组织、实现思路和使用细节。该测试框架是为 ActionScript 2 (AS2) 环境设计的，旨在为 AS2 项目提供一个模块化、可扩展、易于使用的自动化测试框架。

## 目标与规划

- **目标**：
  - 提供一个轻量级但功能强大的测试框架，支持单元测试、集成测试等。
  - 采用模块化设计，降低耦合度，提升可扩展性和可维护性。
  - 支持测试用例的组织、执行、报告生成和结果分析。
  - 考虑 AS2 的技术限制，提供适合该环境的解决方案。

- **规划**：
  - 实现核心组件，包括测试用例、测试套件、测试运行器、断言库和报告器。
  - 支持配置化测试执行，允许灵活地控制测试行为。
  - 提供辅助模块，增强框架的功能，如测试数据管理、日志系统等。
  - 提供详细的使用指南和示例，方便开发者上手。

## 架构设计

### 核心组件

1. **TestCase** (`TestCase.as`)

   - 表示单个测试用例，包含描述、输入、预期输出、测试函数和标签。
   - 提供方法获取测试用例的信息。

2. **TestSuite** (`TestSuite.as`)

   - 表示一组相关的测试用例。
   - 负责管理 `TestCase` 的集合。

3. **TestRunner** (`TestRunner.as`)

   - 负责执行 `TestSuite` 中的所有 `TestCase`。
   - 控制测试执行流程，包括测试的开始、结束、结果收集等。

4. **TestConfig** (`TestConfig.as`)

   - 定义测试运行的配置选项，如调试模式、重复次数、屏蔽输出、标签过滤等。
   - 影响 `TestRunner` 的行为。

5. **TestReporter** (`TestReporter.as`)

   - 报告器接口，定义测试结果的记录和报告生成方式。
   - 可以实现不同的报告器（如控制台报告器、XML 报告器）。

6. **Assertions** (`Assertions.as`)

   - 断言库，提供各种断言方法，如 `assertEquals`、`assertTrue` 等。
   - 用于验证测试结果是否符合预期。

### 辅助组件

1. **TestUtils** (`TestUtils.as`)

   - 提供辅助方法，如深度比较、对象字符串化等。
   - 支持断言和测试执行过程。

### 扩展与插件

1. **插件接口** (`ITestPlugin.as`)

   - 定义插件接口，允许开发者扩展测试框架的功能。
   - 插件可以在测试执行的不同阶段插入自定义逻辑。

## 组织结构

### 文件结构

```
org/
└── flashNight/
    └── aven/
        └── test/
            ├── TestCase.as
            ├── TestSuite.as
            ├── TestRunner.as
            ├── TestConfig.as
            ├── TestReporter.as
            ├── Assertions.as
            ├── TestUtils.as
            ├── ConsoleTestReporter.as
            ├── ITestPlugin.as
            └── examples/
                └── ExampleTest.as
```

### 类关系图

```
+-------------------+
|     TestCase      |
+-------------------+
          |
          v
+-------------------+          +-------------------+
|    TestSuite      | <------> |    TestRunner     |
+-------------------+          +-------------------+
          |                               |
          v                               v
+-------------------+          +-------------------+
|   TestReporter    | <------> |    TestConfig     |
+-------------------+          +-------------------+
          |
          v
+-------------------+
|    Assertions     |
+-------------------+
          |
          v
+-------------------+
|     TestUtils     |
+-------------------+
```

## 实现思路

### AS2 技术限制与应对

- **包与命名空间**：AS2 不支持包，但可以通过目录结构和类命名来模拟包结构。
- **类型系统**：AS2 的类型检查较为宽松，需要手动确保类型一致性。
- **接口与继承**：AS2 支持接口和继承，可以用于实现多态和模块化设计。
- **错误处理**：使用 `try-catch` 块进行异常处理，捕获测试过程中的错误。

### 模块化设计原则

- **低耦合**：各个模块之间的依赖尽量减少，通过接口和抽象类实现模块间的通信。
- **高内聚**：每个模块职责单一，便于理解和维护。
- **可扩展性**：提供插件机制和接口，允许开发者根据需要扩展框架功能。
- **易用性**：提供简单明了的 API 和使用方式，降低上手难度。

## 使用指南

### 编写测试用例

```actionscript
var testCase:TestCase = new TestCase(
    "测试用例描述",
    inputObject,
    expectedOutput,
    function(input:Object):Object {
        // 测试逻辑实现
        var result:Object = performTest(input);
        return result;
    },
    ["标签1", "标签2"]
);
```

- **描述**：简短描述测试用例的目的。
- **输入**：测试函数的输入数据。
- **预期输出**：期望的测试结果，用于断言。
- **测试函数**：执行测试逻辑的函数，接受输入并返回实际结果。
- **标签**：用于对测试用例进行分类和过滤。

### 创建测试套件

```actionscript
var testSuite:TestSuite = new TestSuite("测试套件名称");
testSuite.addTestCase(testCase1);
testSuite.addTestCase(testCase2);
// 添加更多的测试用例
```

- **名称**：为测试套件指定一个有意义的名称。
- **添加测试用例**：将 `TestCase` 添加到 `TestSuite` 中。

### 配置测试运行器

```actionscript
var config:TestConfig = new TestConfig(
    false,      // debug 模式
    1,          // 重复次数
    false,      // 是否屏蔽输出
    ["标签1"],  // 启用的标签
    []          // 禁用的标签
);

var reporter:ConsoleTestReporter = new ConsoleTestReporter(config);
var runner:TestRunner = new TestRunner(config, reporter);
```

- **配置选项**：
  - `debug`：是否启用调试模式。
  - `repeat`：每个测试用例的重复执行次数。
  - `mute`：是否屏蔽输出。
  - `enabledTags`：只运行包含这些标签的测试用例。
  - `disabledTags`：跳过包含这些标签的测试用例。

### 运行测试

```actionscript
runner.addSuite(testSuite);
runner.run();
```

- **添加测试套件**：将 `TestSuite` 添加到 `TestRunner` 中。
- **执行测试**：调用 `run()` 方法开始测试执行。

## 下一步计划

### 实现辅助模块

1. **日志系统**

   - 实现一个日志记录模块，支持不同级别的日志输出（信息、警告、错误）。
   - 允许将日志输出到文件，便于调试和问题追踪。

2. **测试数据管理**

   - 支持从外部文件（如 JSON、XML）加载测试数据。
   - 将测试数据与测试逻辑分离，提升可维护性和可扩展性。

3. **更多的报告器**

   - 实现 `XMLTestReporter`，生成机器可读的 XML 格式测试报告，便于与 CI/CD 系统集成。
   - 实现 `HTMLTestReporter`，生成友好的 HTML 测试报告，便于人类阅读。

### 增强框架功能

1. **插件系统完善**

   - 定义插件生命周期，在测试执行的不同阶段（如开始前、结束后）调用插件方法。
   - 提供一些默认插件，如性能测试插件、覆盖率统计插件等。

2. **更多的断言方法**

   - 在 `Assertions` 类中添加更多断言方法，如 `assertNull`、`assertNotNull`、`assertGreaterThan` 等。

3. **支持并行测试**

   - 由于 AS2 的限制，真正的并行可能无法实现，但可以模拟并行执行，优化测试执行时间。

4. **错误分类与报告**

   - 在报告中区分失败的测试用例是由于断言失败还是发生了异常，提供更详细的错误信息。

## 结论

通过上述设计和实现，我们将构建一个适用于 AS2 环境的功能强大、灵活、可扩展的测试框架。该框架将有助于提高项目的代码质量，促进自动化测试的实践。

---

## 实现辅助模块

根据计划，接下来我们将实现以下辅助模块：

1. **日志系统** (`Logger.as`)
2. **测试数据管理** (`TestDataLoader.as`)
3. **更多的报告器** (`XMLTestReporter.as`)

### 1. 日志系统 (`Logger.as`)

```actionscript
// 文件路径：org/flashNight/aven/test/Logger.as
class org.flashNight.aven.test.Logger {
    private static var LEVEL_INFO:Number = 1;
    private static var LEVEL_WARN:Number = 2;
    private static var LEVEL_ERROR:Number = 3;

    private static var currentLevel:Number = LEVEL_INFO;
    private static var isMuted:Boolean = false;

    public static function setLevel(level:Number):Void {
        currentLevel = level;
    }

    public static function mute():Void {
        isMuted = true;
    }

    public static function unmute():Void {
        isMuted = false;
    }

    public static function info(message:String):Void {
        if (!isMuted && currentLevel <= LEVEL_INFO) {
            trace("[INFO] " + message);
        }
    }

    public static function warn(message:String):Void {
        if (!isMuted && currentLevel <= LEVEL_WARN) {
            trace("[WARN] " + message);
        }
    }

    public static function error(message:String):Void {
        if (!isMuted && currentLevel <= LEVEL_ERROR) {
            trace("[ERROR] " + message);
        }
    }
}
```

**功能说明**：

- **日志级别控制**：可以设置当前日志级别，低于当前级别的日志将被输出。
- **静音模式**：可以通过 `mute()` 和 `unmute()` 控制日志输出，全局静音。
- **日志方法**：提供 `info()`、`warn()`、`error()` 方法输出不同级别的日志。

**使用示例**：

```actionscript
Logger.setLevel(Logger.LEVEL_WARN);
Logger.info("This is an info message.");   // 不会输出
Logger.warn("This is a warning message."); // 会输出
Logger.error("This is an error message."); // 会输出
```

### 2. 测试数据管理 (`TestDataLoader.as`)

```actionscript
// 文件路径：org/flashNight/aven/test/TestDataLoader.as
class org.flashNight.aven.test.TestDataLoader {
    public static function loadJSON(jsonString:String):Object {
        // AS2 没有内置的 JSON 解析器，需要使用第三方库或自定义实现
        // 这里假设有一个全局的 JSON 解析器
        return _global.JSON.parse(jsonString);
    }
}
```

**功能说明**：

- **加载 JSON 数据**：由于 AS2 的限制，我们无法直接从文件中读取数据，所以这里提供从 JSON 字符串解析为对象的方法。
- **依赖**：需要有一个全局的 JSON 解析器，如 `json2.as`。

**使用示例**：

```actionscript
var jsonString:String = '{ "name": "Alice", "age": 30 }';
var data:Object = TestDataLoader.loadJSON(jsonString);
trace("Name: " + data.name + ", Age: " + data.age);
```

### 3. 更多的报告器 (`XMLTestReporter.as`)

```actionscript
// 文件路径：org/flashNight/aven/test/XMLTestReporter.as
class org.flashNight.aven.test.XMLTestReporter implements org.flashNight.aven.test.TestReporter {
    private var passed:Number;
    private var failed:Number;
    private var skipped:Number;
    private var testResults:Array;
    private var config:org.flashNight.aven.test.TestConfig;

    public function XMLTestReporter(config:org.flashNight.aven.test.TestConfig) {
        this.passed = 0;
        this.failed = 0;
        this.skipped = 0;
        this.testResults = [];
        this.config = config;
    }

    public function startSuite(name:String):Void {
        // 无需操作
    }

    public function endSuite(name:String):Void {
        // 无需操作
    }

    public function startTest(description:String):Void {
        // 无需操作
    }

    public function passTest(description:String, time:Number):Void {
        this.passed++;
        this.testResults.push({ status: "pass", description: description, time: time });
    }

    public function failTest(description:String, time:Number, error:Error):Void {
        this.failed++;
        this.testResults.push({ status: "fail", description: description, time: time, error: error.message });
    }

    public function skipTest(description:String):Void {
        this.skipped++;
        this.testResults.push({ status: "skip", description: description });
    }

    public function generateReport():Void {
        var xml:String = "<testsuite>";
        for (var i:Number = 0; i < this.testResults.length; i++) {
            var result:Object = this.testResults[i];
            xml += "<testcase name=\"" + escapeXML(result.description) + "\" time=\"" + result.time + "\">";
            if (result.status == "fail") {
                xml += "<failure>" + escapeXML(result.error) + "</failure>";
            } else if (result.status == "skip") {
                xml += "<skipped/>";
            }
            xml += "</testcase>";
        }
        xml += "</testsuite>";
        // 将 xml 保存到文件或输出
        saveReport(xml);
    }

    private function escapeXML(str:String):String {
        return str.split("&").join("&amp;").split("<").join("&lt;").split(">").join("&gt;").split("\"").join("&quot;");
    }

    private function saveReport(xmlContent:String):Void {
        // 由于 AS2 无法直接写入文件，这里提供一个模拟方法
        // 实际实现需要根据具体环境（如使用外部库或引擎提供的文件写入接口）
        // 以下是示例代码
        trace("XML Report Generated:\n" + xmlContent);
    }
}
```

**功能说明**：

- **生成 XML 格式的测试报告**：按照 JUnit 测试报告格式生成 XML，便于集成到 CI/CD 系统中。
- **记录测试结果**：在测试执行过程中，记录每个测试用例的结果和执行时间。
- **输出报告**：在测试结束后，生成 XML 报告，可以扩展为保存到文件或发送到服务器。

**使用示例**：

```actionscript
var config:TestConfig = new TestConfig(false, 1, false, null, null);
var reporter:XMLTestReporter = new XMLTestReporter(config);
var runner:TestRunner = new TestRunner(config, reporter);

// 添加测试套件和用例

runner.run();
```

---

### 增强框架功能

#### 1. 插件系统完善 (`ITestPlugin.as`)

```actionscript
// 文件路径：org/flashNight/aven/test/ITestPlugin.as
interface org.flashNight.aven.test.ITestPlugin {
    function beforeSuite(suiteName:String):Void;
    function afterSuite(suiteName:String):Void;
    function beforeTest(testDescription:String):Void;
    function afterTest(testDescription:String, passed:Boolean, error:Error):Void;
}
```

**功能说明**：

- **插件接口定义**：提供在测试执行不同阶段的钩子方法。
- **可扩展性**：开发者可以实现该接口，创建自定义插件，扩展测试框架的功能。

#### 2. 在 `TestRunner` 中集成插件系统

```actionscript
// 在 TestRunner 类中添加插件支持
class org.flashNight.aven.test.TestRunner {
    // 其他成员变量
    private var plugins:Array;

    public function TestRunner(config:TestConfig, reporter:TestReporter) {
        // 其他初始化
        this.plugins = [];
    }

    public function addPlugin(plugin:ITestPlugin):Void {
        this.plugins.push(plugin);
    }

    public function run():Void {
        for (var i:Number = 0; i < this.suites.length; i++) {
            var suite:TestSuite = this.suites[i];
            for (var p:Number = 0; p < this.plugins.length; p++) {
                this.plugins[p].beforeSuite(suite.getName());
            }
            // 执行测试套件中的测试用例
            for (var j:Number = 0; j < suite.getTestCases().length; j++) {
                var testCase:TestCase = suite.getTestCases()[j];
                // 插件 beforeTest
                for (var p:Number = 0; p < this.plugins.length; p++) {
                    this.plugins[p].beforeTest(testCase.getDescription());
                }
                // 执行测试用例
                var passed:Boolean = false;
                var error:Error = null;
                try {
                    // 测试执行逻辑
                    passed = true;
                } catch (e:Error) {
                    error = e;
                }
                // 插件 afterTest
                for (var p:Number = 0; p < this.plugins.length; p++) {
                    this.plugins[p].afterTest(testCase.getDescription(), passed, error);
                }
            }
            for (var p:Number = 0; p < this.plugins.length; p++) {
                this.plugins[p].afterSuite(suite.getName());
            }
        }
    }
}
```

**功能说明**：

- **插件生命周期方法**：在测试执行过程中，调用插件的相应方法，实现扩展功能。
- **插件管理**：`TestRunner` 提供 `addPlugin()` 方法，允许添加多个插件。

#### 3. 示例插件 (`PerformancePlugin.as`)

```actionscript
// 文件路径：org/flashNight/aven/test/PerformancePlugin.as
class org.flashNight.aven.test.PerformancePlugin implements org.flashNight.aven.test.ITestPlugin {
    private var testStartTime:Number;

    public function beforeSuite(suiteName:String):Void {
        // 可以在这里记录套件开始时间
    }

    public function afterSuite(suiteName:String):Void {
        // 可以在这里记录套件结束时间
    }

    public function beforeTest(testDescription:String):Void {
        // 记录测试用例开始时间
        this.testStartTime = getTimer();
    }

    public function afterTest(testDescription:String, passed:Boolean, error:Error):Void {
        var duration:Number = getTimer() - this.testStartTime;
        trace("Test '" + testDescription + "' executed in " + duration + "ms");
    }
}
```

**功能说明**：

- **性能监控**：在每个测试用例执行前后，记录执行时间，输出性能信息。
- **易于扩展**：可以根据需要添加更多功能，如记录到文件、统计平均执行时间等。

**使用示例**：

```actionscript
var runner:TestRunner = new TestRunner(config, reporter);
var performancePlugin:PerformancePlugin = new PerformancePlugin();
runner.addPlugin(performancePlugin);

// 添加测试套件和用例

runner.run();
```

---

## 总结

通过上述辅助模块的实现，我们增强了测试框架的功能，提供了日志系统、测试数据管理、更丰富的报告方式和插件机制。这些模块提高了框架的实用性和可扩展性，使其更适合实际项目的需求。

- **日志系统**：帮助开发者在调试和分析时记录重要信息。
- **测试数据管理**：将测试数据与测试逻辑分离，方便维护和扩展。
- **更多的报告器**：提供多种报告格式，适应不同的集成需求。
- **插件系统**：允许开发者根据需要扩展框架功能，实现自定义的测试行为。

通过不断完善和扩展，该测试框架将成为 AS2 项目中不可或缺的工具，助力开发者编写高质量的代码，提升开发效率。

---