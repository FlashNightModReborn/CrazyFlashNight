### FastJSON - 高性能 JSON 解析与序列化类

---

#### 目录
1. [简介](#简介)
2. [功能与设计](#功能与设计)
3. [安装与集成](#安装与集成)
4. [快速入门](#快速入门)
5. [详细使用指南](#详细使用指南)
    - [1. 初始化](#1-初始化)
    - [2. 序列化对象](#2-序列化对象)
    - [3. 反序列化 JSON 字符串](#3-反序列化-json-字符串)
    - [4. 错误处理](#4-错误处理)
6. [性能分析与优化](#性能分析与优化)
    - [性能测试结果](#性能测试结果)
    - [优化建议](#优化建议)
7. [使用建议与最佳实践](#使用建议与最佳实践)
8. [典型应用场景](#典型应用场景)
9. [常见问题与解决方案](#常见问题与解决方案)

---

### 简介

`FastJSON` 是一个为 ActionScript 2 (AS2) 环境设计的高性能 JSON 解析与序列化类。它特别针对 TCP 环境（如 `XMLSocket` 通信）中的高效数据传输需求进行了优化。通过采用非递归栈结构、缓存机制和高效的字符串处理技术，`FastJSON` 实现了比传统 JSON 类更快的处理速度和更低的资源消耗，适用于需要频繁处理 JSON 数据的实时通信应用。

### 功能与设计

- **高性能解析与序列化**：通过非递归的栈结构和并行数组，显著提升 JSON 数据的处理速度，避免递归带来的性能开销和栈溢出风险。
- **缓存机制**：内置解析缓存 (`parseCache`) 和序列化缓存 (`stringifyCache`)，减少重复处理相同数据的开销，提升整体性能。
- **全面的数据类型支持**：支持整数、浮点数、字符串、布尔值、`null`，并正确处理特殊字符（如换行、引号）和 Unicode 字符。
- **深度控制**：通过 `maxDepth` 属性限制解析深度，防止深度嵌套导致的栈溢出。
- **高效字符串处理**：将输入字符串分割为字符数组 (`charArray`)，优化字符访问速度，减少 `charAt` 的调用次数。
- **FIFO 缓存清理策略**：使用先进先出（FIFO）策略管理缓存，确保缓存大小在设定范围内，避免内存占用过高。

---

### 安装与集成

1. **下载 FastJSON 类文件**
    - 将 `FastJSON.as` 文件下载到项目的合适目录中

2. **导入 FastJSON 类**
    - 在需要使用 FastJSON 的 ActionScript 文件中导入该类：
    ```actionscript
    import org.flashNight.naki.FastJSON;
    ```

3. **确保依赖项可用**
    - 确保项目中包含 `Dictionary` 类和任何其他依赖模块

---

### 快速入门

以下是使用 `FastJSON` 进行 JSON 数据序列化与反序列化的基本步骤：

#### 1. 初始化

创建 `FastJSON` 实例：
```actionscript
var fastJSON:FastJSON = new FastJSON();
```

#### 2. 序列化对象

将 AS2 对象转换为 JSON 字符串：
```actionscript
var myObject:Object = { name: "Alice", age: 30, isActive: true };
var jsonString:String = fastJSON.stringify(myObject);
trace(jsonString); // 输出: {"name":"Alice","age":30,"isActive":true}
```

#### 3. 反序列化 JSON 字符串

将 JSON 字符串解析为 AS2 对象：
```actionscript
var jsonString:String = '{"name":"Alice","age":30,"isActive":true}';
var myObject:Object = fastJSON.parse(jsonString);
trace(myObject.name); // 输出: Alice
```

#### 4. 错误处理

在解析或序列化过程中，如果遇到无效的 JSON 数据，`FastJSON` 会抛出带有详细错误信息的异常。建议使用 `try-catch` 块进行错误处理：
```actionscript
try {
    var invalidJSON:String = '{"name":"Alice", "age":30, "active":yes}';
    var myObject:Object = fastJSON.parse(invalidJSON);
} catch (e:Object) {
    trace("解析错误: " + e.message + " 在位置: " + e.at);
}
```

---

### 详细使用指南

#### 1. 初始化

```actionscript
import org.flashNight.naki.FastJSON;

var fastJSON:FastJSON = new FastJSON();
```

**可选配置**：
- **最大解析深度**：默认 `maxDepth` 为 256，可根据需要调整以处理更深的嵌套结构。
    ```actionscript
    fastJSON.maxDepth = 512;
    ```

- **缓存最大容量**：默认 `cacheMaxSize` 为 1024，可根据应用需求调整。
    ```actionscript
    fastJSON.cacheMaxSize = 2048;
    ```

#### 2. 序列化对象

将 AS2 对象转换为 JSON 字符串。

**示例**：
```actionscript
var user:Object = {
    userId: 12345,
    userName: "Player1",
    level: 10,
    stats: {
        hp: 100,
        mp: 50,
        attack: 15,
        defense: 8
    },
    inventory: [
        { id: 101, name: "Health Potion", quantity: 3 },
        { id: 102, name: "Mana Potion", quantity: 2 },
        { id: 103, name: "Sword", quantity: 1 }
    ],
    quests: [
        {
            id: 201,
            title: "Defeat Goblins",
            progress: { current: 5, total: 10 }
        }
    ]
};

var jsonString:String = fastJSON.stringify(user);
trace(jsonString);
// 输出: {"quests":[{"id":201,"title":"Defeat Goblins","progress":{"current":5,"total":10}}],"inventory":[{"id":101,"name":"Health Potion","quantity":3},{"id":102,"name":"Mana Potion","quantity":2},{"id":103,"name":"Sword","quantity":1}],"stats":{"defense":8,"attack":15,"mp":50,"hp":100},"level":10,"userName":"Player1","userId":12345}
```

**注意事项**：
- 确保对象属性名为字符串类型，且不包含非法字符。
- `FastJSON` 自动处理特殊字符和 Unicode，不需手动转义。

#### 3. 反序列化 JSON 字符串

将 JSON 字符串解析为 AS2 对象。

**示例**：
```actionscript
var jsonString:String = '{"quests":[{"id":201,"title":"Defeat Goblins","progress":{"current":5,"total":10}}],"inventory":[{"id":101,"name":"Health Potion","quantity":3},{"id":102,"name":"Mana Potion","quantity":2},{"id":103,"name":"Sword","quantity":1}],"stats":{"defense":8,"attack":15,"mp":50,"hp":100},"level":10,"userName":"Player1","userId":12345}';
var user:Object = fastJSON.parse(jsonString);

trace(user.userName); // 输出: Player1
trace(user.stats.hp); // 输出: 100
```

**注意事项**：
- 输入字符串必须是有效的 JSON 格式，否则会抛出错误。
- `FastJSON` 会自动忽略以双下划线 (`__`) 开头的对象属性。

#### 4. 错误处理

处理 JSON 解析或序列化过程中可能出现的错误。

**示例**：
```actionscript
try {
    var invalidJSON:String = '{"name":"Alice", "age":30, "active":yes}';
    var myObject:Object = fastJSON.parse(invalidJSON);
} catch (e:Object) {
    trace("解析错误: " + e.message + " 在位置: " + e.at);
    // 输出: 解析错误: Unexpected token: yes 在位置: 28
}
```

**错误信息包含**：
- `message`: 错误描述。
- `at`: 出错位置（字符索引）。
- `text`: 原始 JSON 字符串。

---

### 性能分析与优化

#### 性能测试结果

根据测试日志，`FastJSON` 在序列化和反序列化方面表现出色，远超原始 JSON 类：

##### **基本性能（缓存有效）**
- **FastJSON**
  - 序列化：
    - 总时间: 1 ms
    - 平均每次时间: 0.01 ms
    - 最大时间: 1 ms
    - 最小时间: 0 ms
  - 反序列化：
    - 总时间: 1 ms
    - 平均每次时间: 0.01 ms
    - 最大时间: 1 ms
    - 最小时间: 0 ms

- **原始 JSON 类**
  - 序列化：
    - 总时间: 74 ms
    - 平均每次时间: 0.74 ms
  - 反序列化：
    - 总时间: 261 ms
    - 平均每次时间: 2.61 ms

##### **扩展性能（缓存无效）**
- **FastJSON**
  - 序列化：
    - 总时间: 148 ms
    - 平均每次时间: 1.48 ms
  - 反序列化：
    - 总时间: 207 ms
    - 平均每次时间: 2.07 ms

- **原始 JSON 类**
  - 序列化：
    - 总时间: 118 ms
    - 平均每次时间: 1.18 ms
  - 反序列化：
    - 总时间: 430 ms
    - 平均每次时间: 4.3 ms

**总结**：
- 在缓存命中情况下，`FastJSON` 的性能优势极为显著，序列化和反序列化速度分别提升了约74倍和261倍。
- 在缓存未命中时，`FastJSON` 依然保持较高的性能，与原始 JSON 类相比，反序列化速度提升了约2倍，序列化速度稍逊于原始 JSON 类。

#### 优化建议

1. **充分利用缓存机制**：
    - 在处理频繁重复的 JSON 数据时，`FastJSON` 的缓存机制能够显著提升性能。确保尽可能复用相同的数据结构，以充分利用缓存命中带来的性能优势。
  
2. **合理设置缓存容量**：
    - 根据应用需求调整 `cacheMaxSize`，平衡内存使用与缓存命中率。对于数据变化频繁的应用，可以适当减少缓存容量以避免频繁清理；对于数据重复度高的应用，增加缓存容量以提高命中率。

3. **控制解析深度**：
    - 默认 `maxDepth` 为 256，适用于大多数应用场景。对于嵌套结构极其复杂的 JSON 数据，可适当增加 `maxDepth`，但需谨慎以防内存耗尽。

4. **优化数据结构**：
    - 尽量简化 JSON 数据结构，避免过度嵌套和复杂的对象关系，以提升解析和序列化效率。

5. **定期清理缓存**：
    - 对于长时间运行的应用，定期监控和清理缓存，以防止缓存数据过多占用内存。

---

### 使用建议与最佳实践

1. **优先使用缓存**：
    - 在需要频繁序列化和反序列化相同 JSON 数据的场景中，确保数据能够被有效缓存。例如，用户配置、常用状态信息等。

2. **缓存失效管理**：
    - 对于数据频繁变化且唯一性高的应用，合理管理缓存的清理策略，避免缓存因频繁失效而导致性能下降。

3. **错误处理机制**：
    - 始终在解析和序列化过程中使用 `try-catch` 块，捕获并处理可能的错误，确保应用的稳定性。

4. **性能监控**：
    - 在高性能需求的应用中，定期进行性能监控，评估 `FastJSON` 的表现，必要时调整配置参数（如 `cacheMaxSize` 和 `maxDepth`）。

5. **内存管理**：
    - 注意监控应用的内存使用情况，尤其是在处理大规模 JSON 数据时，避免内存泄漏和过高的内存占用。

6. **代码优化**：
    - 优化 JSON 数据的生成和处理逻辑，减少不必要的序列化和反序列化操作，提升整体应用效率。

---

### 典型应用场景

`FastJSON` 特别适用于以下应用场景：

1. **实时通信应用（TCP/Socket）**：
    - 通过 `XMLSocket` 实现的实时数据传输，如多人在线游戏、即时聊天应用、实时数据监控系统等，`FastJSON` 能够提供低延迟、高吞吐量的数据处理能力。

2. **高频数据同步**：
    - 在需要频繁同步数据的客户端与服务器之间，如实时更新用户状态、配置同步等，`FastJSON` 的高效序列化与反序列化能够显著减少网络传输时间和处理延迟。

3. **复杂数据结构处理**：
    - 处理嵌套深度较大的 JSON 数据，如多层嵌套的配置文件、复杂的用户数据结构等，`FastJSON` 的非递归解析设计能够有效避免栈溢出，并保持高性能。

4. **移动与嵌入式设备**：
    - 由于资源有限，移动设备和嵌入式系统常常需要高效的 JSON 处理工具，`FastJSON` 的低内存占用和高速度非常适合这些环境。

5. **大数据量处理**：
    - 在需要处理大规模 JSON 数据的应用中，如日志分析、数据聚合等，`FastJSON` 能够快速处理大量数据，提升整体应用性能。

---

### 常见问题与解决方案

**Q1: FastJSON 抛出“Unexpected token”错误，如何解决？**

**A1:** 该错误通常由于输入的 JSON 字符串格式不正确。请检查 JSON 字符串的语法，确保所有的键和值都正确匹配，并且字符串使用双引号包裹。例如：
```actionscript
// 错误示例
var invalidJSON:String = '{"name":"Alice", "age":30, "active":yes}';

// 正确示例
var validJSON:String = '{"name":"Alice", "age":30, "active":true}';
```

**Q2: 如何调整 FastJSON 的缓存大小？**

**A2:** 通过设置 `cacheMaxSize` 属性来调整缓存的最大容量。例如，将缓存大小设置为 2048：
```actionscript
fastJSON.cacheMaxSize = 2048;
```

**Q3: FastJSON 无法处理某些特殊字符，怎么办？**

**A3:** `FastJSON` 已内置对特殊字符和 Unicode 的处理。如果遇到问题，请确保输入字符串使用正确的转义字符，并且遵循 JSON 规范。例如，字符串中的双引号应使用 `\"` 进行转义。

**Q4: FastJSON 解析深度超过限制，如何处理？**

**A4:** 如果需要处理更深层次的嵌套 JSON 数据，可以增加 `maxDepth` 的值，但需注意内存消耗和潜在的性能影响：
```actionscript
fastJSON.maxDepth = 512; // 根据需要调整
```

**Q5: 如何清空 FastJSON 的缓存？**

**A5:** 目前 `FastJSON` 未提供直接清空缓存的方法，可以通过重新创建实例或扩展类来实现缓存清理。例如：
```actionscript
fastJSON.parseCache = {};
fastJSON.stringifyCache = {};
fastJSON.parseCacheKeys = [];
fastJSON.stringifyCacheKeys = [];
fastJSON.parseCacheCount = 0;
fastJSON.stringifyCacheCount = 0;
```


### 附录

#### 技术细节

**1. 缓存机制**：
- `parseCache` 和 `stringifyCache` 使用对象存储解析和序列化结果。
- `parseCacheKeys` 和 `stringifyCacheKeys` 存储缓存键的插入顺序，用于 FIFO 清理策略。
- 当缓存容量超过 `cacheMaxSize` 时，最旧的缓存项会被移除，以腾出空间。

**2. 唯一键生成**：
- 使用 `Dictionary.getStaticUID` 为对象分配唯一的 UID，避免重复对象的重复解析和序列化。
- 基本类型（字符串、数字、布尔值）直接转换为字符串作为缓存键。

**3. 非递归栈结构**：
- `stringify` 方法通过并行数组 `stackTypes` 和 `stackData` 模拟栈结构，避免递归调用，提高性能。
- `value` 方法在解析过程中采用迭代方式处理 JSON 结构，避免深度嵌套带来的栈溢出风险。

**4. 字符串处理优化**：
- 将输入字符串拆分为字符数组 `charArray`，通过索引访问字符，提高解析速度。
- 序列化过程中，直接拼接字符串片段，减少字符串拼接的开销。

---


// --- 测试 JSON 和 FastJSON 类的正确性和性能 ---

// 定义测试数据
var tcpData:Object = new Object();
tcpData.userId = 12345;
tcpData.userName = "Player1";
tcpData.level = 10;
tcpData.stats = new Object();
tcpData.stats.hp = 100;
tcpData.stats.mp = 50;
tcpData.stats.attack = 15;
tcpData.stats.defense = 8;

// 添加 inventory 数组
tcpData.inventory = new Array();
var item1:Object = new Object();
item1.id = 101;
item1.name = "Health Potion";
item1.quantity = 3;
tcpData.inventory.push(item1);

var item2:Object = new Object();
item2.id = 102;
item2.name = "Mana Potion";
item2.quantity = 2;
tcpData.inventory.push(item2);

var item3:Object = new Object();
item3.id = 103;
item3.name = "Sword";
item3.quantity = 1;
tcpData.inventory.push(item3);

// 添加 quests 数组
tcpData.quests = new Array();
var quest1:Object = new Object();
quest1.id = 201;
quest1.title = "Defeat Goblins";
quest1.progress = new Object();
quest1.progress.current = 5;
quest1.progress.total = 10;
tcpData.quests.push(quest1);

// 定义复杂对象用于测试
var complexObject:Object = new Object();
complexObject.userId = 12345;
complexObject.userName = "Player1";
complexObject.level = 10;
complexObject.stats = new Object();
complexObject.stats.hp = 100;
complexObject.stats.mp = 50;
complexObject.stats.attack = 15;
complexObject.stats.defense = 8;
complexObject.inventory = [
    {id: 101, name: "Health Potion", quantity: 3},
    {id: 102, name: "Mana Potion", quantity: 2},
    {id: 103, name: "Sword", quantity: 1}
];
complexObject.quests = [
    {
        id: 201,
        title: "Defeat Goblins",
        progress: {
            current: 5,
            total: 10
        }
    }
];

// 定义测试用例
var testCases:Array = [
    // 原始测试用例
    {input: 12345, description: "Integer"},
    {input: 123.45, description: "Float"},
    {input: "hello world", description: "String"},
    {input: true, description: "Boolean true"},
    {input: false, description: "Boolean false"},
    {input: null, description: "Null"},
    {input: "Line1\nLine2\tTabbed", description: "Newline and tabbed"},
    {input: "Hello \"World\"", description: "Escaped quotes"},
    {input: "Hello 你好", description: "Unicode characters"},
    {input: {name:"Alice", age:30, isActive:true}, description: "Simple object"},
    {input: [1, 2, 3, 4, 5], description: "Simple array"},
    {input: {user:{id:123, info:{name:"Alice", active:true}}}, description: "Nested object"},
    {input: [[1, 2], [3, 4], [5, 6]], description: "Nested array"},
    {input: complexObject, description: "Complex object"},
    {input: {}, description: "Empty object"},
    {input: [], description: "Empty array"},
    {input: [1, null, 3, null, 5], description: "Sparse array"},
    {input: {id:123, name:null, active:true}, description: "Object with null"},
    // 无效 JSON 测试用例
    {input: "{\"name\":\"Alice\", \"age\":30", description: "Unfinished object"},
    {input: "[1, 2, 3", description: "Unfinished array"},
    {input: "{\"name\":\"Alice\", \"age\":30, \"active\":yes}", description: "Invalid JSON"}
];

// Helper function: 序列化输出对象为字符串用于显示
function serializeOutput(obj:Object):String {
    if (obj == null) return "null";
    if (typeof obj == "string") return "\"" + obj + "\"";
    if (typeof obj == "number" || typeof obj == "boolean") return String(obj);
    if (obj instanceof Array) {
        var arrStr:String = "[";
        for (var i:Number = 0; i < obj.length; i++) {
            if (i > 0) arrStr += ", ";
            arrStr += serializeOutput(obj[i]);
        }
        arrStr += "]";
        return arrStr;
    }
    if (typeof obj == "object") {
        var objStr:String = "{";
        var isFirst:Boolean = true;
        for (var key:String in obj) {
            if (!isFirst) objStr += ", ";
            isFirst = false;
            objStr += "\"" + key + "\":" + serializeOutput(obj[key]);
        }
        objStr += "}";
        return objStr;
    }
    return "";
}

// 创建 JSON 和 FastJSON 实例
var originalJSON = new JSON(false); // 假设原始 JSON 类支持构造函数参数控制模式
var fastJSON = new FastJSON(); // 假设 FastJSON 类无构造参数

// 执行功能测试
trace("=== 功能测试 ===");
for (var i:Number = 0; i < testCases.length; i++) {
    var testCase:Object = testCases[i];
    var input:Object = testCase.input;
    var description:String = testCase.description;
    var outputJSON:Object;
    var outputFastJSON:Object;
    var serializedJSON:String;
    var serializedFastJSON:String;
    
    trace("\n--- Test Case: " + description + " ---");
    
    try {
        // 使用原始 JSON 类序列化
        serializedJSON = originalJSON.stringify(input);
        // 使用原始 JSON 类反序列化
        outputJSON = originalJSON.parse(serializedJSON);
        
        // 显示原始 JSON 类结果
        trace("Original JSON | Serialized: " + serializedJSON);
        trace("Original JSON | Parsed Output: " + serializeOutput(outputJSON));
    } catch (e:Error) {
        trace("Original JSON | Error: " + e.message);
    }
    
    try {
        // 使用 FastJSON 类序列化
        serializedFastJSON = fastJSON.stringify(input);
        // 使用 FastJSON 类反序列化
        outputFastJSON = fastJSON.parse(serializedFastJSON);
        
        // 显示 FastJSON 类结果
        trace("FastJSON     | Serialized: " + serializedFastJSON);
        trace("FastJSON     | Parsed Output: " + serializeOutput(outputFastJSON));
    } catch (e:Error) {
        trace("FastJSON     | Error: " + e.message);
    }
}

// --- 性能测试：分别测量序列化和反序列化的时间 ---

// 设置迭代次数
var numIterations:Number = 100;
var jsonSerializeTimes:Array = [];
var jsonDeserializeTimes:Array = [];
var fastJsonSerializeTimes:Array = [];
var fastJsonDeserializeTimes:Array = [];

// 预先序列化一次数据以供反序列化测试使用
var serializedDataJson:String;
var serializedDataFastJSON:String;

try {
    serializedDataJson = originalJSON.stringify(tcpData);
} catch (e:Error) {
    trace("Error serializing with Original JSON: " + e.message);
}

try {
    serializedDataFastJSON = fastJSON.stringify(tcpData);
} catch (e:Error) {
    trace("Error serializing with FastJSON: " + e.message);
}

// 测试原始 JSON 类性能：序列化
trace("\n=== 性能测试：原始 JSON 类序列化 ===");
for (var j:Number = 0; j < numIterations; j++) {
    var startTime:Number = getTimer();

    // 使用原始 JSON 类序列化
    var tempSerializedJson:String = originalJSON.stringify(tcpData);

    var endTime:Number = getTimer();
    jsonSerializeTimes.push(endTime - startTime);
}

// 测试原始 JSON 类性能：反序列化
trace("\n=== 性能测试：原始 JSON 类反序列化 ===");
for (j = 0; j < numIterations; j++) {
    var startTimeDeser:Number = getTimer();

    // 使用原始 JSON 类反序列化
    var tempDeserializedJson:Object = originalJSON.parse(serializedDataJson);

    var endTimeDeser:Number = getTimer();
    jsonDeserializeTimes.push(endTimeDeser - startTimeDeser);
}

// 测试 FastJSON 类性能：序列化
trace("\n=== 性能测试：FastJSON 类序列化 ===");
for (j = 0; j < numIterations; j++) {
    var startTimeFastSer:Number = getTimer();

    // 使用 FastJSON 类序列化
    var tempSerializedFastJSON:String = fastJSON.stringify(tcpData);

    var endTimeFastSer:Number = getTimer();
    fastJsonSerializeTimes.push(endTimeFastSer - startTimeFastSer);
}

// 测试 FastJSON 类性能：反序列化
trace("\n=== 性能测试：FastJSON 类反序列化 ===");
for (j = 0; j < numIterations; j++) {
    var startTimeFastDeser:Number = getTimer();

    // 使用 FastJSON 类反序列化
    var tempDeserializedFastJSON:Object = fastJSON.parse(serializedDataFastJSON);

    var endTimeFastDeser:Number = getTimer();
    fastJsonDeserializeTimes.push(endTimeFastDeser - startTimeFastDeser);
}

// 定义统计函数
function calculateStatistics(times:Array):Object {
    var stats:Object = new Object();

    if (times.length == 0) {
        stats.totalTime = 0;
        stats.maxTime = 0;
        stats.minTime = 0;
        stats.avgTime = 0;
        stats.variance = 0;
        stats.stdDeviation = 0;
        return stats;
    }

    stats.totalTime = 0;
    stats.maxTime = times[0];
    stats.minTime = times[0];

    // Calculate total time, max, and min time
    for (var k:Number = 0; k < times.length; k++) {
        var cycleTime:Number = times[k];
        stats.totalTime += cycleTime;
        if (cycleTime > stats.maxTime) stats.maxTime = cycleTime;
        if (cycleTime < stats.minTime) stats.minTime = cycleTime;
    }

    // Calculate average time
    stats.avgTime = stats.totalTime / times.length;

    // Calculate variance and standard deviation
    var varianceSum:Number = 0;
    for (k = 0; k < times.length; k++) {
        varianceSum += Math.pow(times[k] - stats.avgTime, 2);
    }
    stats.variance = varianceSum / times.length;
    stats.stdDeviation = Math.sqrt(stats.variance);

    return stats;
}

// 计算并显示原始 JSON 类性能统计
var jsonSerStats:Object = calculateStatistics(jsonSerializeTimes);
var jsonDeserStats:Object = calculateStatistics(jsonDeserializeTimes);
trace("\n--- 原始 JSON 类性能统计 ---");
trace("序列化 - " + numIterations + " 次总时间: " + jsonSerStats.totalTime + " ms");
trace("序列化 - 平均每次时间: " + jsonSerStats.avgTime + " ms");
trace("序列化 - 最大时间: " + jsonSerStats.maxTime + " ms");
trace("序列化 - 最小时间: " + jsonSerStats.minTime + " ms");
trace("序列化 - 方差: " + jsonSerStats.variance + " ms^2");
trace("序列化 - 标准差: " + jsonSerStats.stdDeviation + " ms");

trace("反序列化 - " + numIterations + " 次总时间: " + jsonDeserStats.totalTime + " ms");
trace("反序列化 - 平均每次时间: " + jsonDeserStats.avgTime + " ms");
trace("反序列化 - 最大时间: " + jsonDeserStats.maxTime + " ms");
trace("反序列化 - 最小时间: " + jsonDeserStats.minTime + " ms");
trace("反序列化 - 方差: " + jsonDeserStats.variance + " ms^2");
trace("反序列化 - 标准差: " + jsonDeserStats.stdDeviation + " ms");

// 计算并显示 FastJSON 类性能统计
var fastJsonSerStats:Object = calculateStatistics(fastJsonSerializeTimes);
var fastJsonDeserStats:Object = calculateStatistics(fastJsonDeserializeTimes);
trace("\n--- FastJSON 类性能统计 ---");
trace("序列化 - " + numIterations + " 次总时间: " + fastJsonSerStats.totalTime + " ms");
trace("序列化 - 平均每次时间: " + fastJsonSerStats.avgTime + " ms");
trace("序列化 - 最大时间: " + fastJsonSerStats.maxTime + " ms");
trace("序列化 - 最小时间: " + fastJsonSerStats.minTime + " ms");
trace("序列化 - 方差: " + fastJsonSerStats.variance + " ms^2");
trace("序列化 - 标准差: " + fastJsonSerStats.stdDeviation + " ms");

trace("反序列化 - " + numIterations + " 次总时间: " + fastJsonDeserStats.totalTime + " ms");
trace("反序列化 - 平均每次时间: " + fastJsonDeserStats.avgTime + " ms");
trace("反序列化 - 最大时间: " + fastJsonDeserStats.maxTime + " ms");
trace("反序列化 - 最小时间: " + fastJsonDeserStats.minTime + " ms");
trace("反序列化 - 方差: " + fastJsonDeserStats.variance + " ms^2");
trace("反序列化 - 标准差: " + fastJsonDeserStats.stdDeviation + " ms");

// 显示示例序列化数据
trace("\nSerialized data example (Original JSON): " + serializedDataJson);
trace("Deserialized data example, userName (Original JSON): " + (jsonDeserStats.minTime >= 0 ? originalJSON.parse(serializedDataJson).userName : "null"));
trace("Serialized data example (FastJSON): " + serializedDataFastJSON);
trace("Deserialized data example, userName (FastJSON): " + (fastJsonDeserStats.minTime >= 0 ? fastJSON.parse(serializedDataFastJSON).userName : "null"));

// --- 扩展测试：缓存无效情况下的性能测试 ---

trace("\n=== 扩展测试：缓存无效情况下的性能测试 ===");

// 定义一个函数，用于生成全新的测试对象
function generateUniqueObject():Object {
    var obj:Object = new Object();
    obj.userId = Math.floor(Math.random() * 100000);
    obj.userName = "Player" + Math.floor(Math.random() * 1000);
    obj.level = Math.floor(Math.random() * 100);
    obj.stats = new Object();
    obj.stats.hp = Math.floor(Math.random() * 500);
    obj.stats.mp = Math.floor(Math.random() * 500);
    obj.stats.attack = Math.floor(Math.random() * 100);
    obj.stats.defense = Math.floor(Math.random() * 100);
    
    // 添加 inventory 数组
    obj.inventory = new Array();
    var numItems:Number = Math.floor(Math.random() * 10) + 1; // 1 到 10 个物品
    for (var m:Number = 0; m < numItems; m++) {
        var item:Object = new Object();
        item.id = 100 + m;
        item.name = "Item" + m;
        item.quantity = Math.floor(Math.random() * 20) + 1;
        obj.inventory.push(item);
    }
    
    // 添加 quests 数组
    obj.quests = new Array();
    var numQuests:Number = Math.floor(Math.random() * 5) + 1; // 1 到 5 个任务
    for (m = 0; m < numQuests; m++) {
        var quest:Object = new Object();
        quest.id = 200 + m;
        quest.title = "Quest " + m;
        quest.progress = new Object();
        quest.progress.current = Math.floor(Math.random() * 100);
        quest.progress.total = 100;
        obj.quests.push(quest);
    }
    
    return obj;
}

// 定义扩展测试用例数组（每次都是新对象）
var uniqueTestCases:Array = [];
for (i = 0; i < 50; i++) { // 创建 50 个唯一测试用例
    uniqueTestCases.push({input: generateUniqueObject(), description: "Unique object " + (i+1)});
}

// 执行扩展功能测试
trace("\n=== 扩展功能测试：缓存无效情况下 ===");
for (i = 0; i < uniqueTestCases.length; i++) {
    var uniqueTestCase:Object = uniqueTestCases[i];
    var uniqueInput:Object = uniqueTestCase.input;
    var uniqueDescription:String = uniqueTestCase.description;
    var uniqueOutputJSON:Object;
    var uniqueOutputFastJSON:Object;
    var uniqueSerializedJSON:String;
    var uniqueSerializedFastJSON:String;
    
    trace("\n--- Test Case: " + uniqueDescription + " ---");
    
    try {
        // 使用原始 JSON 类序列化
        uniqueSerializedJSON = originalJSON.stringify(uniqueInput);
        // 使用原始 JSON 类反序列化
        uniqueOutputJSON = originalJSON.parse(uniqueSerializedJSON);
        
        // 显示原始 JSON 类结果
        //trace("Original JSON | Serialized: " + uniqueSerializedJSON);
        //trace("Original JSON | Parsed Output: " + serializeOutput(uniqueOutputJSON));
    } catch (e:Error) {
        trace("Original JSON | Error: " + e.message);
    }
    
    try {
        // 使用 FastJSON 类序列化
        uniqueSerializedFastJSON = fastJSON.stringify(uniqueInput);
        // 使用 FastJSON 类反序列化
        uniqueOutputFastJSON = fastJSON.parse(uniqueSerializedFastJSON);
        
        // 显示 FastJSON 类结果
        //trace("FastJSON     | Serialized: " + uniqueSerializedFastJSON);
        //trace("FastJSON     | Parsed Output: " + serializeOutput(uniqueOutputFastJSON));
    } catch (e:Error) {
        trace("FastJSON     | Error: " + e.message);
    }
}

// --- 性能测试：缓存无效情况下的序列化和反序列化时间 ---

// 设置扩展测试迭代次数
var uniqueNumIterations:Number = 100;
var jsonSerializeTimesUnique:Array = [];
var jsonDeserializeTimesUnique:Array = [];
var fastJsonSerializeTimesUnique:Array = [];
var fastJsonDeserializeTimesUnique:Array = [];

// 生成独立的序列化和反序列化数据
var serializedDataJsonUnique:Array = [];
var serializedDataFastJSONUnique:Array = [];

for (i = 0; i < uniqueNumIterations; i++) {
    var uniqueObj:Object = generateUniqueObject();
    try {
        var serializedJsonUnique:String = originalJSON.stringify(uniqueObj);
        serializedDataJsonUnique.push(serializedJsonUnique);
    } catch (e:Error) {
        serializedDataJsonUnique.push("Error");
    }
    
    try {
        var serializedFastJSONUnique:String = fastJSON.stringify(uniqueObj);
        serializedDataFastJSONUnique.push(serializedFastJSONUnique);
    } catch (e:Error) {
        serializedDataFastJSONUnique.push("Error");
    }
}

// 测试原始 JSON 类性能：序列化（缓存无效）
trace("\n=== 扩展性能测试：原始 JSON 类序列化（缓存无效） ===");
for (j = 0; j < uniqueNumIterations; j++) {
    var startTimeUniqueSer:Number = getTimer();

    // 使用原始 JSON 类序列化
    var tempSerializedJsonUnique:String = originalJSON.stringify(generateUniqueObject());

    var endTimeUniqueSer:Number = getTimer();
    jsonSerializeTimesUnique.push(endTimeUniqueSer - startTimeUniqueSer);
}

// 测试原始 JSON 类性能：反序列化（缓存无效）
trace("\n=== 扩展性能测试：原始 JSON 类反序列化（缓存无效） ===");
for (j = 0; j < uniqueNumIterations; j++) {
    var uniqueSerializedJsonUnique:String = originalJSON.stringify(generateUniqueObject());
    var startTimeUniqueDeser:Number = getTimer();

    // 使用原始 JSON 类反序列化
    var tempDeserializedJsonUnique:Object = originalJSON.parse(uniqueSerializedJsonUnique);

    var endTimeUniqueDeser:Number = getTimer();
    jsonDeserializeTimesUnique.push(endTimeUniqueDeser - startTimeUniqueDeser);
}

// 测试 FastJSON 类性能：序列化（缓存无效）
trace("\n=== 扩展性能测试：FastJSON 类序列化（缓存无效） ===");
for (j = 0; j < uniqueNumIterations; j++) {
    var startTimeFastSerUnique:Number = getTimer();

    // 使用 FastJSON 类序列化
    var tempSerializedFastJSONUnique:String = fastJSON.stringify(generateUniqueObject());

    var endTimeFastSerUnique:Number = getTimer();
    fastJsonSerializeTimesUnique.push(endTimeFastSerUnique - startTimeFastSerUnique);
}

// 测试 FastJSON 类性能：反序列化（缓存无效）
trace("\n=== 扩展性能测试：FastJSON 类反序列化（缓存无效） ===");
for (j = 0; j < uniqueNumIterations; j++) {
    var uniqueSerializedFastJSONUnique:String = fastJSON.stringify(generateUniqueObject());
    var startTimeFastDeserUnique:Number = getTimer();

    // 使用 FastJSON 类反序列化
    var tempDeserializedFastJSONUnique:Object = fastJSON.parse(uniqueSerializedFastJSONUnique);

    var endTimeFastDeserUnique:Number = getTimer();
    fastJsonDeserializeTimesUnique.push(endTimeFastDeserUnique - startTimeFastDeserUnique);
}

// 计算并显示扩展测试性能统计
var jsonSerStatsUnique:Object = calculateStatistics(jsonSerializeTimesUnique);
var jsonDeserStatsUnique:Object = calculateStatistics(jsonDeserializeTimesUnique);
trace("\n--- 扩展测试：原始 JSON 类性能统计（缓存无效） ---");
trace("序列化 - " + uniqueNumIterations + " 次总时间: " + jsonSerStatsUnique.totalTime + " ms");
trace("序列化 - 平均每次时间: " + jsonSerStatsUnique.avgTime + " ms");
trace("序列化 - 最大时间: " + jsonSerStatsUnique.maxTime + " ms");
trace("序列化 - 最小时间: " + jsonSerStatsUnique.minTime + " ms");
trace("序列化 - 方差: " + jsonSerStatsUnique.variance + " ms^2");
trace("序列化 - 标准差: " + jsonSerStatsUnique.stdDeviation + " ms");

trace("反序列化 - " + uniqueNumIterations + " 次总时间: " + jsonDeserStatsUnique.totalTime + " ms");
trace("反序列化 - 平均每次时间: " + jsonDeserStatsUnique.avgTime + " ms");
trace("反序列化 - 最大时间: " + jsonDeserStatsUnique.maxTime + " ms");
trace("反序列化 - 最小时间: " + jsonDeserStatsUnique.minTime + " ms");
trace("反序列化 - 方差: " + jsonDeserStatsUnique.variance + " ms^2");
trace("反序列化 - 标准差: " + jsonDeserStatsUnique.stdDeviation + " ms");

var fastJsonSerStatsUnique:Object = calculateStatistics(fastJsonSerializeTimesUnique);
var fastJsonDeserStatsUnique:Object = calculateStatistics(fastJsonDeserializeTimesUnique);
trace("\n--- 扩展测试：FastJSON 类性能统计（缓存无效） ---");
trace("序列化 - " + uniqueNumIterations + " 次总时间: " + fastJsonSerStatsUnique.totalTime + " ms");
trace("序列化 - 平均每次时间: " + fastJsonSerStatsUnique.avgTime + " ms");
trace("序列化 - 最大时间: " + fastJsonSerStatsUnique.maxTime + " ms");
trace("序列化 - 最小时间: " + fastJsonSerStatsUnique.minTime + " ms");
trace("序列化 - 方差: " + fastJsonSerStatsUnique.variance + " ms^2");
trace("序列化 - 标准差: " + fastJsonSerStatsUnique.stdDeviation + " ms");

trace("反序列化 - " + uniqueNumIterations + " 次总时间: " + fastJsonDeserStatsUnique.totalTime + " ms");
trace("反序列化 - 平均每次时间: " + fastJsonDeserStatsUnique.avgTime + " ms");
trace("反序列化 - 最大时间: " + fastJsonDeserStatsUnique.maxTime + " ms");
trace("反序列化 - 最小时间: " + fastJsonDeserStatsUnique.minTime + " ms");
trace("反序列化 - 方差: " + fastJsonDeserStatsUnique.variance + " ms^2");
trace("反序列化 - 标准差: " + fastJsonDeserStatsUnique.stdDeviation + " ms");

// 显示示例序列化数据
trace("\nSerialized data example (Original JSON): " + serializedDataJson);
trace("Deserialized data example, userName (Original JSON): " + (jsonDeserStats.minTime >= 0 ? originalJSON.parse(serializedDataJson).userName : "null"));
trace("Serialized data example (FastJSON): " + serializedDataFastJSON);
trace("Deserialized data example, userName (FastJSON): " + (fastJsonDeserStats.minTime >= 0 ? fastJSON.parse(serializedDataFastJSON).userName : "null"));
















=== 功能测试 ===

--- Test Case: Integer ---
Original JSON | Serialized: 12345
Original JSON | Parsed Output: 12345
FastJSON     | Serialized: 12345
FastJSON     | Parsed Output: 12345

--- Test Case: Float ---
Original JSON | Serialized: 123.45
Original JSON | Parsed Output: 123.45
FastJSON     | Serialized: 123.45
FastJSON     | Parsed Output: 123.45

--- Test Case: String ---
Original JSON | Serialized: "hello world"
Original JSON | Parsed Output: "hello world"
FastJSON     | Serialized: "hello world"
FastJSON     | Parsed Output: "hello world"

--- Test Case: Boolean true ---
Original JSON | Serialized: true
Original JSON | Parsed Output: true
FastJSON     | Serialized: true
FastJSON     | Parsed Output: true

--- Test Case: Boolean false ---
Original JSON | Serialized: false
Original JSON | Parsed Output: false
FastJSON     | Serialized: false
FastJSON     | Parsed Output: false

--- Test Case: Null ---
Original JSON | Serialized: null
Original JSON | Parsed Output: null
FastJSON     | Serialized: null
FastJSON     | Parsed Output: null

--- Test Case: Newline and tabbed ---
Original JSON | Serialized: "Line1\nLine2\tTabbed"
Original JSON | Parsed Output: "Line1
Line2	Tabbed"
FastJSON     | Serialized: "Line1\nLine2\tTabbed"
FastJSON     | Parsed Output: "Line1
Line2	Tabbed"

--- Test Case: Escaped quotes ---
Original JSON | Serialized: "Hello \"World\""
Original JSON | Parsed Output: "Hello "World""
FastJSON     | Serialized: "Hello \"World\""
FastJSON     | Parsed Output: "Hello "World""

--- Test Case: Unicode characters ---
Original JSON | Serialized: "Hello 你好"
Original JSON | Parsed Output: "Hello 你好"
FastJSON     | Serialized: "Hello 你好"
FastJSON     | Parsed Output: "Hello 你好"

--- Test Case: Simple object ---
Original JSON | Serialized: {"name":"Alice","age":30,"isActive":true}
Original JSON | Parsed Output: {"isActive":true, "age":30, "name":"Alice"}
FastJSON     | Serialized: {"name":"Alice","age":30,"isActive":true}
FastJSON     | Parsed Output: {"isActive":true, "age":30, "name":"Alice"}

--- Test Case: Simple array ---
Original JSON | Serialized: [1,2,3,4,5]
Original JSON | Parsed Output: [1, 2, 3, 4, 5]
FastJSON     | Serialized: [1,2,3,4,5]
FastJSON     | Parsed Output: [1, 2, 3, 4, 5]

--- Test Case: Nested object ---
Original JSON | Serialized: {"user":{"id":123,"info":{"name":"Alice","active":true}}}
Original JSON | Parsed Output: {"user":{"info":{"active":true, "name":"Alice"}, "id":123}}
FastJSON     | Serialized: {"user":{"id":123,"info":{"name":"Alice","active":true}}}
FastJSON     | Parsed Output: {"user":{"info":{"active":true, "name":"Alice"}, "id":123}}

--- Test Case: Nested array ---
Original JSON | Serialized: [[1,2],[3,4],[5,6]]
Original JSON | Parsed Output: [[1, 2], [3, 4], [5, 6]]
FastJSON     | Serialized: [[1,2],[3,4],[5,6]]
FastJSON     | Parsed Output: [[1, 2], [3, 4], [5, 6]]

--- Test Case: Complex object ---
Original JSON | Serialized: {"quests":[{"id":201,"title":"Defeat Goblins","progress":{"current":5,"total":10}}],"inventory":[{"id":101,"name":"Health Potion","quantity":3},{"id":102,"name":"Mana Potion","quantity":2},{"id":103,"name":"Sword","quantity":1}],"stats":{"defense":8,"attack":15,"mp":50,"hp":100},"level":10,"userName":"Player1","userId":12345}
Original JSON | Parsed Output: {"userId":12345, "userName":"Player1", "level":10, "stats":{"hp":100, "mp":50, "attack":15, "defense":8}, "inventory":[{"quantity":3, "name":"Health Potion", "id":101}, {"quantity":2, "name":"Mana Potion", "id":102}, {"quantity":1, "name":"Sword", "id":103}], "quests":[{"progress":{"total":10, "current":5}, "title":"Defeat Goblins", "id":201}]}
FastJSON     | Serialized: {"quests":[{"id":201,"title":"Defeat Goblins","progress":{"current":5,"total":10}}],"inventory":[{"id":101,"name":"Health Potion","quantity":3},{"id":102,"name":"Mana Potion","quantity":2},{"id":103,"name":"Sword","quantity":1}],"stats":{"defense":8,"attack":15,"mp":50,"hp":100},"level":10,"userName":"Player1","userId":12345}
FastJSON     | Parsed Output: {"userId":12345, "userName":"Player1", "level":10, "stats":{"hp":100, "mp":50, "attack":15, "defense":8}, "inventory":[{"quantity":3, "name":"Health Potion", "id":101}, {"quantity":2, "name":"Mana Potion", "id":102}, {"quantity":1, "name":"Sword", "id":103}], "quests":[{"progress":{"total":10, "current":5}, "title":"Defeat Goblins", "id":201}]}

--- Test Case: Empty object ---
Original JSON | Serialized: {}
Original JSON | Parsed Output: {}
FastJSON     | Serialized: {}
FastJSON     | Parsed Output: {}

--- Test Case: Empty array ---
Original JSON | Serialized: []
Original JSON | Parsed Output: []
FastJSON     | Serialized: []
FastJSON     | Parsed Output: []

--- Test Case: Sparse array ---
Original JSON | Serialized: [1,null,3,null,5]
Original JSON | Parsed Output: [1, null, 3, null, 5]
FastJSON     | Serialized: [1,null,3,null,5]
FastJSON     | Parsed Output: [1, null, 3, null, 5]

--- Test Case: Object with null ---
Original JSON | Serialized: {"id":123,"name":null,"active":true}
Original JSON | Parsed Output: {"active":true, "name":null, "id":123}
FastJSON     | Serialized: {"id":123,"name":null,"active":true}
FastJSON     | Parsed Output: {"active":true, "name":null, "id":123}

--- Test Case: Unfinished object ---
Original JSON | Serialized: "{\"name\":\"Alice\", \"age\":30"
Original JSON | Parsed Output: "{"name":"Alice", "age":30"
FastJSON     | Serialized: "{\"name\":\"Alice\", \"age\":30"
FastJSON     | Parsed Output: "{"name":"Alice", "age":30"

--- Test Case: Unfinished array ---
Original JSON | Serialized: "[1, 2, 3"
Original JSON | Parsed Output: "[1, 2, 3"
FastJSON     | Serialized: "[1, 2, 3"
FastJSON     | Parsed Output: "[1, 2, 3"

--- Test Case: Invalid JSON ---
Original JSON | Serialized: "{\"name\":\"Alice\", \"age\":30, \"active\":yes}"
Original JSON | Parsed Output: "{"name":"Alice", "age":30, "active":yes}"
FastJSON     | Serialized: "{\"name\":\"Alice\", \"age\":30, \"active\":yes}"
FastJSON     | Parsed Output: "{"name":"Alice", "age":30, "active":yes}"

=== 性能测试：原始 JSON 类序列化 ===

=== 性能测试：原始 JSON 类反序列化 ===

=== 性能测试：FastJSON 类序列化 ===

=== 性能测试：FastJSON 类反序列化 ===

--- 原始 JSON 类性能统计 ---
序列化 - 100 次总时间: 70 ms
序列化 - 平均每次时间: 0.7 ms
序列化 - 最大时间: 2 ms
序列化 - 最小时间: 0 ms
序列化 - 方差: 0.23 ms^2
序列化 - 标准差: 0.479583152331272 ms
反序列化 - 100 次总时间: 264 ms
反序列化 - 平均每次时间: 2.64 ms
反序列化 - 最大时间: 4 ms
反序列化 - 最小时间: 2 ms
反序列化 - 方差: 0.2904 ms^2
反序列化 - 标准差: 0.538887743412299 ms

--- FastJSON 类性能统计 ---
序列化 - 100 次总时间: 1 ms
序列化 - 平均每次时间: 0.01 ms
序列化 - 最大时间: 1 ms
序列化 - 最小时间: 0 ms
序列化 - 方差: 0.0099 ms^2
序列化 - 标准差: 0.099498743710662 ms
反序列化 - 100 次总时间: 2 ms
反序列化 - 平均每次时间: 0.02 ms
反序列化 - 最大时间: 1 ms
反序列化 - 最小时间: 0 ms
反序列化 - 方差: 0.0196 ms^2
反序列化 - 标准差: 0.14 ms

Serialized data example (Original JSON): {"quests":[{"progress":{"total":10,"current":5},"title":"Defeat Goblins","id":201}],"inventory":[{"quantity":3,"name":"Health Potion","id":101},{"quantity":2,"name":"Mana Potion","id":102},{"quantity":1,"name":"Sword","id":103}],"stats":{"defense":8,"attack":15,"mp":50,"hp":100},"level":10,"userName":"Player1","userId":12345}
Deserialized data example, userName (Original JSON): Player1
Serialized data example (FastJSON): {"quests":[{"progress":{"total":10,"current":5},"title":"Defeat Goblins","id":201}],"inventory":[{"quantity":3,"name":"Health Potion","id":101},{"quantity":2,"name":"Mana Potion","id":102},{"quantity":1,"name":"Sword","id":103}],"stats":{"defense":8,"attack":15,"mp":50,"hp":100},"level":10,"userName":"Player1","userId":12345}
Deserialized data example, userName (FastJSON): Player1

=== 扩展测试：缓存无效情况下的性能测试 ===

=== 扩展功能测试：缓存无效情况下 ===

--- Test Case: Unique object 1 ---

--- Test Case: Unique object 2 ---

--- Test Case: Unique object 3 ---

--- Test Case: Unique object 4 ---

--- Test Case: Unique object 5 ---

--- Test Case: Unique object 6 ---

--- Test Case: Unique object 7 ---

--- Test Case: Unique object 8 ---

--- Test Case: Unique object 9 ---

--- Test Case: Unique object 10 ---

--- Test Case: Unique object 11 ---

--- Test Case: Unique object 12 ---

--- Test Case: Unique object 13 ---

--- Test Case: Unique object 14 ---

--- Test Case: Unique object 15 ---

--- Test Case: Unique object 16 ---

--- Test Case: Unique object 17 ---

--- Test Case: Unique object 18 ---

--- Test Case: Unique object 19 ---

--- Test Case: Unique object 20 ---

--- Test Case: Unique object 21 ---

--- Test Case: Unique object 22 ---

--- Test Case: Unique object 23 ---

--- Test Case: Unique object 24 ---

--- Test Case: Unique object 25 ---

--- Test Case: Unique object 26 ---

--- Test Case: Unique object 27 ---

--- Test Case: Unique object 28 ---

--- Test Case: Unique object 29 ---

--- Test Case: Unique object 30 ---

--- Test Case: Unique object 31 ---

--- Test Case: Unique object 32 ---

--- Test Case: Unique object 33 ---

--- Test Case: Unique object 34 ---

--- Test Case: Unique object 35 ---

--- Test Case: Unique object 36 ---

--- Test Case: Unique object 37 ---

--- Test Case: Unique object 38 ---

--- Test Case: Unique object 39 ---

--- Test Case: Unique object 40 ---

--- Test Case: Unique object 41 ---

--- Test Case: Unique object 42 ---

--- Test Case: Unique object 43 ---

--- Test Case: Unique object 44 ---

--- Test Case: Unique object 45 ---

--- Test Case: Unique object 46 ---

--- Test Case: Unique object 47 ---

--- Test Case: Unique object 48 ---

--- Test Case: Unique object 49 ---

--- Test Case: Unique object 50 ---

=== 扩展性能测试：原始 JSON 类序列化（缓存无效） ===

=== 扩展性能测试：原始 JSON 类反序列化（缓存无效） ===

=== 扩展性能测试：FastJSON 类序列化（缓存无效） ===

=== 扩展性能测试：FastJSON 类反序列化（缓存无效） ===

--- 扩展测试：原始 JSON 类性能统计（缓存无效） ---
序列化 - 100 次总时间: 130 ms
序列化 - 平均每次时间: 1.3 ms
序列化 - 最大时间: 4 ms
序列化 - 最小时间: 0 ms
序列化 - 方差: 0.41 ms^2
序列化 - 标准差: 0.640312423743285 ms
反序列化 - 100 次总时间: 455 ms
反序列化 - 平均每次时间: 4.55 ms
反序列化 - 最大时间: 10 ms
反序列化 - 最小时间: 2 ms
反序列化 - 方差: 1.6075 ms^2
反序列化 - 标准差: 1.2678722333106 ms

--- 扩展测试：FastJSON 类性能统计（缓存无效） ---
序列化 - 100 次总时间: 148 ms
序列化 - 平均每次时间: 1.48 ms
序列化 - 最大时间: 5 ms
序列化 - 最小时间: 0 ms
序列化 - 方差: 0.4496 ms^2
序列化 - 标准差: 0.670522184569609 ms
反序列化 - 100 次总时间: 145 ms
反序列化 - 平均每次时间: 1.45 ms
反序列化 - 最大时间: 6 ms
反序列化 - 最小时间: 0 ms
反序列化 - 方差: 0.547500000000001 ms^2
反序列化 - 标准差: 0.739932429347438 ms

Serialized data example (Original JSON): {"quests":[{"progress":{"total":10,"current":5},"title":"Defeat Goblins","id":201}],"inventory":[{"quantity":3,"name":"Health Potion","id":101},{"quantity":2,"name":"Mana Potion","id":102},{"quantity":1,"name":"Sword","id":103}],"stats":{"defense":8,"attack":15,"mp":50,"hp":100},"level":10,"userName":"Player1","userId":12345}
Deserialized data example, userName (Original JSON): Player1
Serialized data example (FastJSON): {"quests":[{"progress":{"total":10,"current":5},"title":"Defeat Goblins","id":201}],"inventory":[{"quantity":3,"name":"Health Potion","id":101},{"quantity":2,"name":"Mana Potion","id":102},{"quantity":1,"name":"Sword","id":103}],"stats":{"defense":8,"attack":15,"mp":50,"hp":100},"level":10,"userName":"Player1","userId":12345}
Deserialized data example, userName (FastJSON): Player1