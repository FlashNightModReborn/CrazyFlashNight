## **目录**

1. [简介](#简介)
2. [类概述](#类概述)
   - [1. XMLParser 类](#1-xmlparser-类)
   - [2. StringUtils 类](#2-stringutils-类)
   - [3. XMLLoader 类](#3-xmlloader-类)
3. [详细解析](#详细解析)
   - [1. XMLParser 类详解](#1-xmlparser-类详解)
   - [2. StringUtils 类详解](#2-stringutils-类详解)
   - [3. XMLLoader 类详解](#3-xmlloader-类详解)
4. [使用指南](#使用指南)
   - [1. 准备 XML 文件](#1-准备-xml-文件)
   - [2. 编写 AS2 代码](#2-编写-as2-代码)
   - [3. 实例化并使用](#3-实例化并使用)
5. [注意事项](#注意事项)
6. [常见问题解答](#常见问题解答)
7. [总结](#总结)

---

## **简介**

本文档详细介绍了三个用于处理 XML 文件的 ActionScript 2 (AS2) 类：

- **XMLParser**：负责将 XML 节点解析为 AS2 对象。
- **StringUtils**：提供字符串处理的实用工具，特别是处理 HTML 实体编码和解码。
- **XMLLoader**：负责加载 XML 文件，并使用 XMLParser 将其解析为 AS2 对象。

这些类协同工作，使得在 AS2 环境下处理 XML 文件更加高效和方便。本文将深入剖析每个类的逻辑和特性，并提供详细的使用指南。

---

## **类概述**

### **1. XMLParser 类**

- **功能**：解析 XML 节点，将其转换为 AS2 对象，支持类型转换、空节点处理、CDATA、属性解析等。
- **主要方法**：
  - `parseXMLNode(node:XMLNode):Object`
  - `convertDataType(value:String):Object`
  - `getInnerText(node:XMLNode):String`
  - `isValidXML(node:XMLNode):Boolean`

### **2. StringUtils 类**

- **功能**：提供字符串处理的实用方法，主要用于 HTML 实体的编码和解码。
- **主要方法**：
  - `escapeHTML(str:String):String`
  - `unescapeHTML(str:String):String`
  - `encodeHTML(str:String):String`（别名）
  - `decodeHTML(str:String):String`（别名）

### **3. XMLLoader 类**

- **功能**：加载 XML 文件，并使用 XMLParser 解析为 AS2 对象，提供加载成功和失败的回调处理。
- **主要方法**：
  - 构造函数 `XMLLoader(xmlFilePath:String, onLoadHandler:Function, onErrorHandler:Function)`
  - `getParsedData():Object`

---

## **详细解析**

### **1. XMLParser 类详解**

#### **1.1. 功能概述**

XMLParser 类的主要功能是将给定的 XML 节点解析为 AS2 对象。它支持以下特性：

- **文本节点处理**：将文本节点的内容转换为适当的数据类型。
- **属性解析**：将节点的属性解析并存储为对象的属性。
- **子节点处理**：递归解析子节点，支持多层嵌套。
- **类型转换**：将字符串自动转换为数字或布尔值。
- **特殊节点处理**：对特定节点（如 `Description`、`MaterialDetail`）进行特殊处理，支持 HTML 实体解码。
- **空节点处理**：对空节点或无值节点进行合理的处理。

#### **1.2. 方法详解**

##### **1.2.1. parseXMLNode(node:XMLNode):Object**

- **功能**：递归解析给定的 XML 节点，返回对应的 AS2 对象。
- **逻辑流程**：
  1. **节点类型检查**：根据 `nodeType` 判断节点类型。
     - **文本节点（3）**：直接返回转换后的值。
     - **CDATA 节点（4）**：返回节点值。
     - **元素节点（1）**：继续处理。
  2. **节点有效性检查**：使用 `isValidXML` 方法验证节点是否合法。
  3. **属性处理**：遍历节点的属性，使用 `convertDataType` 进行类型转换。
  4. **子节点处理**：
     - **跳过注释节点（8）**。
     - **特殊节点处理**：对于 `Description` 和 `MaterialDetail`，使用 `getInnerText` 获取内容并解码 HTML 实体。
     - **递归解析**：对有子节点的节点，递归调用 `parseXMLNode`。
     - **同名节点处理**：如果存在同名节点，转换为数组存储。
     - **空节点处理**：对子节点无值的情况，赋值为空字符串。

##### **1.2.2. convertDataType(value:String):Object**

- **功能**：将字符串转换为适当的数据类型（数字、布尔值或原始字符串）。
- **逻辑**：
  - 如果字符串可以转换为数字（使用 `isNaN` 判断），则返回数字类型。
  - 如果字符串为 `"true"` 或 `"false"`（不区分大小写），则返回布尔值。
  - 否则，返回原始字符串。

##### **1.2.3. getInnerText(node:XMLNode):String**

- **功能**：获取节点的内部文本内容，主要用于处理包含 HTML 标签的节点。
- **逻辑**：
  - 遍历子节点，累加文本节点和 CDATA 节点的 `nodeValue`。
  - 使用 `StringUtils.decodeHTML` 对结果进行 HTML 实体解码。

##### **1.2.4. isValidXML(node:XMLNode):Boolean**

- **功能**：检查节点是否为有效的 XML 节点，主要用于过滤无效或非法的节点。
- **逻辑**：
  - 检查节点名称是否存在且非空。
  - 递归检查所有子节点的有效性，忽略文本、CDATA 和注释节点。

#### **1.3. 特殊处理**

- **同名节点**：如果多个子节点具有相同的名称，则在结果对象中将其存储为数组，便于遍历和处理。
- **特殊节点**：`Description` 和 `MaterialDetail` 节点被特殊处理，以确保其内容被正确解析并解码 HTML 实体。

### **2. StringUtils 类详解**

#### **2.1. 功能概述**

StringUtils 类提供了字符串处理的实用方法，特别是用于 HTML 实体的编码和解码。

#### **2.2. 方法详解**

##### **2.2.1. escapeHTML(str:String):String**

- **功能**：将字符串中的特殊字符转义为对应的 HTML 实体。
- **逻辑**：
  - 按顺序替换 `&`、`<`、`>`、`"`、`'` 等字符，防止冲突。
  - 使用预定义的 `htmlEntitiesReverse` 映射替换其他特殊字符。

##### **2.2.2. unescapeHTML(str:String):String**

- **功能**：将字符串中的 HTML 实体反转义为对应的字符。
- **逻辑**：
  - 使用预定义的 `htmlEntities` 映射，逐个替换 HTML 实体为对应的字符。

##### **2.2.3. encodeHTML(str:String):String**

- **功能**：`escapeHTML` 方法的别名，方便使用。

##### **2.2.4. decodeHTML(str:String):String**

- **功能**：`unescapeHTML` 方法的别名，方便使用。

#### **2.3. 内部实现**

- **单例模式**：使用私有静态变量 `instance` 和 `getInstance` 方法，确保 `StringUtils` 类只有一个实例，节省资源。
- **预定义映射**：
  - `htmlEntities`：HTML 实体到字符的映射，用于反转义。
  - `htmlEntitiesReverse`：字符到 HTML 实体的映射，用于转义。

### **3. XMLLoader 类详解**

#### **3.1. 功能概述**

XMLLoader 类负责加载 XML 文件，并使用 XMLParser 将其解析为 AS2 对象。它还提供了加载成功和失败的回调机制，方便开发者处理不同的加载结果。

#### **3.2. 方法详解**

##### **3.2.1. 构造函数**

```as2
public function XMLLoader(xmlFilePath:String, onLoadHandler:Function, onErrorHandler:Function)
```

- **参数**：
  - `xmlFilePath`：要加载的 XML 文件的路径。
  - `onLoadHandler`：加载成功后的回调函数，接收解析后的对象作为参数。
  - `onErrorHandler`：加载失败后的回调函数。

- **逻辑**：
  - 创建一个新的 `XML` 对象，并设置 `ignoreWhite` 为 `true`，以忽略空白节点。
  - 定义 `xml.onLoad` 回调，根据加载结果调用 `handleXMLLoad` 或 `handleXMLError`。
  - 开始加载 XML 文件。

##### **3.2.2. handleXMLLoad():Void**

- **功能**：处理 XML 加载成功的逻辑。
- **逻辑**：
  - 使用 `XMLParser.parseXMLNode` 解析 XML 的第一个子节点（根节点）。
  - 将解析结果存储在 `parsedData` 中。
  - 调用 `onLoadHandler`，并传递解析后的数据。

##### **3.2.3. handleXMLError():Void**

- **功能**：处理 XML 加载失败的逻辑。
- **逻辑**：
  - 输出错误信息 `XMLLoader: Failed to load XML file.`。
  - 如果提供了 `onErrorHandler`，则调用。

##### **3.2.4. getParsedData():Object**

- **功能**：获取解析后的数据对象。
- **逻辑**：
  - 返回 `parsedData`。

---

## **使用指南**

### **1. 准备 XML 文件**

确保您的 XML 文件格式正确，无语法错误。以下是一个示例：

```xml
<Config>
    <App name="DemoApp" version="1.0.0" />
    <Settings>
        <Language>en-US</Language>
        <DebugMode>false</DebugMode>
        <MaxUsers>100</MaxUsers>
    </Settings>
    <Features>
        <Feature>Login</Feature>
        <Feature>Registration</Feature>
        <Feature>Profile</Feature>
    </Features>
</Config>
```

### **2. 编写 AS2 代码**

#### **2.1. 引入必要的类**

```as2
import org.flashNight.gesh.xml.XMLLoader;
import org.flashNight.gesh.xml.XMLParser;
import org.flashNight.gesh.string.StringUtils;
```

#### **2.2. 定义回调函数**

```as2
function onLoadHandler(parsedData:Object):Void {
    trace("XML 加载并解析成功！");
    trace("解析结果：" + objectToString(parsedData));
    
    // 示例：访问解析后的数据
    var appName:String = parsedData.Config.App.name;
    var appVersion:String = parsedData.Config.App.version;
    var language:String = parsedData.Config.Settings.Language;
    var debugMode:Boolean = parsedData.Config.Settings.DebugMode;
    var maxUsers:Number = parsedData.Config.Settings.MaxUsers;
    var features:Array = parsedData.Config.Features.Feature;

    trace("应用名称：" + appName);
    trace("版本：" + appVersion);
    trace("语言：" + language);
    trace("调试模式：" + debugMode);
    trace("最大用户数：" + maxUsers);
    trace("功能列表：" + features.join(", "));
}

function onErrorHandler():Void {
    trace("XML 加载失败，请检查文件路径和格式。");
}
```

#### **2.3. 工具函数**

用于将对象转换为字符串，方便调试输出。

```as2
function objectToString(obj:Object):String {
    if (obj == null) return "null";
    if (typeof(obj) != "object") return "\"" + obj + "\"";
    var str:String = "{";
    var first:Boolean = true;
    for (var key:String in obj) {
        if (!first) str += ", ";
        str += key + ": " + objectToString(obj[key]);
        first = false;
    }
    str += "}";
    return str;
}
```

### **3. 实例化并使用**

```as2
// 指定 XML 文件路径
var xmlFilePath:String = "path/to/your/Config.xml";

// 创建 XMLLoader 实例
var xmlLoader:XMLLoader = new XMLLoader(xmlFilePath, onLoadHandler, onErrorHandler);
```

---

## **注意事项**

1. **文件路径**：确保 XML 文件的路径正确。相对路径是相对于 SWF 文件的位置。

2. **编码格式**：XML 文件应使用 UTF-8 编码，防止中文或特殊字符出现乱码。

3. **特殊字符**：如果 XML 内容包含特殊字符（如 `<`, `>`, `&`），应使用 CDATA 或进行实体转义。

4. **同名节点**：如果存在同名的子节点，解析结果将是一个数组。

---

## **常见问题解答**

### **1. 为什么解析后的布尔值是字符串？**

确保在 `XMLParser` 的 `convertDataType` 方法中正确处理了布尔值的转换。如果发现布尔值仍然是字符串，可能需要检查 XML 文件中是否存在大小写问题，如使用了 `"False"` 而非 `"false"`。

### **2. 如何处理节点缺失的情况？**

解析器会返回 `null` 或 `undefined`，在访问节点属性前，最好进行存在性检查：

```as2
if (parsedData.Config.Settings != undefined) {
    // 安全地访问属性
}
```

### **3. 如何处理空节点？**

空节点（如 `<EmptyNode />`）会被解析为 `""`（空字符串）。在代码中，可以进行判断：

```as2
if (parsedData.Config.EmptyNode == "") {
    trace("EmptyNode 是一个空节点。");
}
```

### **4. XML 加载失败怎么办？**

- 检查文件路径是否正确。
- 确认文件名和扩展名是否正确。
- 确保服务器或本地环境允许加载本地文件。

---

## **总结**

通过以上的详细介绍，您应该对 `XMLParser`、`StringUtils` 和 `XMLLoader` 三个类的功能、逻辑和使用方法有了深入的了解。它们共同构成了一个强大的 XML 处理工具，使得在 AS2 环境下解析和操作 XML 数据变得高效而便捷。


```as2
org.flashNight.gesh.xml.TestXmlLoader.runTests();
```

```output
开始测试 XMLLoader 和 XMLParser...
Loading URL: 类定义/org/flashNight/gesh/xml/TestXml/特殊字符和cdata.xml
Loading URL: 类定义/org/flashNight/gesh/xml/TestXml/环境设置.xml
Loading URL: 类定义/org/flashNight/gesh/xml/TestXml/空节点且不完整.xml
Loading URL: 类定义/org/flashNight/gesh/xml/TestXml/色彩引擎.xml
Loading URL: 类定义/org/flashNight/gesh/xml/TestXml/超大.xml
所有测试完成。
测试通过：特殊字符和 CDATA 文件加载成功。
Parsed Data: {StageInfo: {Description: "这是一个包含特殊字符的描述，测试 <br> 换行。", Type: "特殊字符测试"}}
Parsed Description: 这是一个包含特殊字符的描述，测试 <br> 换行。
测试通过：环境设置文件加载成功。
Parsed Data: {Environment: {Height: "600", Width: "800", Alignment: "true", BackgroundURL: "simple_BG.swf"}}
Parsed BackgroundURL: simple_BG.swf
测试通过：空节点和不完整文件加载成功。
Parsed Data: {Environment: {1: "", 0: {Alignment: "false", BackgroundURL: ""}}}
Parsed Environment Count: 2
Parsed Environment 1: {Alignment: "false", BackgroundURL: ""}
Parsed Environment 2: ""
测试通过：色彩引擎文件加载成功。
Parsed Data: {PresetSet: {Preset: {1: {greenMultiplier: "0.8", redMultiplier: "1", Contrast: "0", Brightness: "0", level: "2"}, 0: {blueOffset: "10", redMultiplier: "0.5", Contrast: "20", Brightness: "-10", level: "1"}}, name: "测试预设"}}
Parsed Brightness: -10
测试通过：超大文件加载成功。耗时: 267ms
Parsed Preset Count: 1000
```