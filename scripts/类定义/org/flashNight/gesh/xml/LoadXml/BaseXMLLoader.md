# BaseXMLLoader 使用指南

## 目录
1. [简介](#简介)
2. [依赖组件](#依赖组件)
   - [PathManager](#PathManager)
   - [XMLLoader](#XMLLoader)
3. [类结构](#类结构)
4. [功能特性](#功能特性)
5. [方法详解](#方法详解)
6. [使用指南](#使用指南)
   - [加载 XML 文件](#加载-xml-文件)
   - [重新加载 XML 文件](#重新加载-xml-文件)
   - [获取加载的数据](#获取加载的数据)
   - [检查加载状态](#检查加载状态)
7. [继承与扩展](#继承与扩展)
   - [创建自定义加载器](#创建自定义加载器)
8. [示例代码](#示例代码)
   - [BulletsCasesLoader 示例](#BulletsCasesLoader-示例)
9. [最佳实践](#最佳实践)
10. [常见问题](#常见问题)
11. [附录](#附录)

---

## 简介

`BaseXMLLoader` 是一个通用的 ActionScript 2 (AS2) 类，旨在简化和标准化 XML 文件的加载与解析过程。通过继承该基类，开发者可以快速创建特定的 XML 加载器类，充分利用其内置的路径管理、数据缓存、加载状态控制和回调机制，提高代码复用性和维护性。

---

## 依赖组件

`BaseXMLLoader` 依赖于以下两个核心类：

### PathManager

**路径管理器**，负责根据当前运行环境自动设置和解析资源文件的基础路径。它的主要职责包括：

- **初始化路径**：检测当前运行环境并设置资源根路径。
- **路径解析**：将相对路径解析为完整的 URL 路径。
- **路径适配**：将本地文件路径转换为 URL 格式路径，支持中文路径解码。

**关键方法**：

- `initialize()`: 初始化路径管理器，设置基础路径。
- `isEnvironmentValid()`: 检查当前是否处于有效的资源环境中。
- `resolvePath(relativePath:String):String`: 解析相对路径为完整路径。
- `adaptPathToURL(filePath:String):String`: 将本地路径适配为 URL 格式路径。
- `getScriptsClassDefinitionPath():String`: 获取 `scripts/类定义/` 目录的完整路径。

### XMLLoader

**XML 加载器**，负责加载指定路径的 XML 文件并将其解析为 ActionScript 对象。它的主要职责包括：

- **加载 XML 文件**：异步加载 XML 文件。
- **解析 XML 数据**：将加载的 XML 数据转换为可操作的对象。
- **错误处理**：处理加载失败的情况，并提供回调函数通知调用者。

**关键方法与属性**：

- 构造函数：`XMLLoader(xmlFilePath:String, onLoadHandler:Function, onErrorHandler:Function)`
- `handleXMLLoad()`: 处理加载成功后的逻辑。
- `handleXMLError()`: 处理加载失败后的逻辑。
- `getParsedData():Object`: 获取解析后的数据对象。

---

## 类结构

```actionscript
class org.flashNight.gesh.xml.LoadXml.BaseXMLLoader {
    private var data:Object = null;
    private var _isLoading:Boolean = false;
    private var filePath:String;

    public function BaseXMLLoader(relativePath:String) { /* ... */ }
    public function load(onLoadHandler:Function, onErrorHandler:Function):Void { /* ... */ }
    public function reload(onLoadHandler:Function, onErrorHandler:Function):Void { /* ... */ }
    public function getData():Object { /* ... */ }
    public function isLoaded():Boolean { /* ... */ }
    public function isLoadingStatus():Boolean { /* ... */ }
    public function objectToString(obj:Object):String { /* ... */ }
}
```

---

## 功能特性

- **路径管理**：自动解析和管理资源文件的基础路径，支持中文路径解码。
- **数据加载**：使用 `XMLLoader` 加载和解析 XML 文件，转换为可操作的对象。
- **数据缓存**：加载的数据会被缓存，避免重复加载，提高性能。
- **加载状态控制**：提供方法检查数据是否已加载或正在加载，防止重复加载。
- **回调机制**：支持加载成功和失败的回调函数，方便外部处理。
- **重载功能**：允许重新加载数据文件，忽略已有缓存。
- **调试辅助**：提供 `objectToString` 方法，将对象转换为字符串，便于调试输出。

---

## 方法详解

### 构造函数

```actionscript
public function BaseXMLLoader(relativePath:String)
```

- **参数**：
  - `relativePath`：相对于资源目录的文件路径（如 `"data/items/bullets_cases.xml"`）。
  
- **功能**：
  - 初始化路径管理器。
  - 解析并设置文件的完整路径。
  - 检查资源环境是否有效。

### load

```actionscript
public function load(onLoadHandler:Function, onErrorHandler:Function):Void
```

- **参数**：
  - `onLoadHandler`：加载成功后的回调函数，接收解析后的数据对象作为参数。
  - `onErrorHandler`：加载失败后的回调函数。

- **功能**：
  - 检查是否正在加载或已加载，避免重复加载。
  - 使用 `XMLLoader` 加载指定的 XML 文件。
  - 在加载成功或失败时调用相应的回调函数。

### reload

```actionscript
public function reload(onLoadHandler:Function, onErrorHandler:Function):Void
```

- **参数**：
  - `onLoadHandler`：加载成功后的回调函数。
  - `onErrorHandler`：加载失败后的回调函数。

- **功能**：
  - 清除已有的缓存数据。
  - 重新加载数据文件。

### getData

```actionscript
public function getData():Object
```

- **返回值**：
  - 解析后的数据对象，如果尚未加载，则返回 `null`。

- **功能**：
  - 获取已加载和解析的数据。

### isLoaded

```actionscript
public function isLoaded():Boolean
```

- **返回值**：
  - 如果数据已加载，返回 `true`；否则返回 `false`。

- **功能**：
  - 检查数据是否已经加载完成。

### isLoadingStatus

```actionscript
public function isLoadingStatus():Boolean
```

- **返回值**：
  - 如果正在加载，返回 `true`；否则返回 `false`。

- **功能**：
  - 检查是否当前正在进行加载操作。

### objectToString

```actionscript
public function objectToString(obj:Object):String
```

- **参数**：
  - `obj`：要转换为字符串的对象。

- **返回值**：
  - 对象的字符串表示。

- **功能**：
  - 将复杂的嵌套对象转换为字符串，便于调试输出。

---

## 使用指南

### 加载 XML 文件

要加载一个 XML 文件，只需创建 `BaseXMLLoader` 的实例，指定相对路径，并调用 `load` 方法。

```actionscript
import org.flashNight.gesh.xml.LoadXml.BaseXMLLoader;

// 创建 BaseXMLLoader 实例
var loader:BaseXMLLoader = new BaseXMLLoader("data/items/bullets_cases.xml");

// 加载 XML 文件
loader.load(
    function(data:Object):Void {
        trace("加载成功！");
        trace(loader);
    },
    function():Void {
        trace("加载失败！");
    }
);
```

### 重新加载 XML 文件

如果需要重新加载已经加载过的 XML 文件，可以调用 `reload` 方法。

```actionscript
// 重新加载 XML 文件
loader.reload(
    function(data:Object):Void {
        trace("重新加载成功！");
    },
    function():Void {
        trace("重新加载失败！");
    }
);
```

### 获取加载的数据

加载完成后，可以通过 `getData` 方法获取解析后的数据对象。

```actionscript
if (loader.isLoaded()) {
    var data:Object = loader.getData();
    trace("已加载的数据：" + loader);
}
```

### 检查加载状态

可以使用 `isLoaded` 和 `isLoadingStatus` 方法检查数据是否已加载或正在加载。

```actionscript
if (loader.isLoadingStatus()) {
    trace("数据正在加载中...");
}

if (loader.isLoaded()) {
    trace("数据已加载完成。");
}
```

---

## 继承与扩展

`BaseXMLLoader` 旨在作为一个通用的基类，通过继承它，可以创建特定的 XML 加载器类，自动拥有加载、缓存、状态控制等功能。

### 创建自定义加载器

假设需要加载 `weapons.xml` 文件，可以创建一个继承自 `BaseXMLLoader` 的类 `WeaponsLoader`。

```actionscript
import org.flashNight.gesh.xml.LoadXml.BaseXMLLoader;
import org.flashNight.gesh.object.ObjectUtil;

class org.flashNight.gesh.xml.LoadXml.WeaponsLoader extends BaseXMLLoader {
    private static var instance:WeaponsLoader = null;

    /**
     * 获取单例实例。
     * @return WeaponsLoader 实例。
     */
    public static function getInstance():WeaponsLoader {
        if (instance == null) {
            instance = new WeaponsLoader();
        }
        return instance;
    }

    /**
     * 构造函数，指定 weapons.xml 的相对路径。
     */
    private function WeaponsLoader() {
        super("data/items/weapons.xml");
    }

    /**
     * 加载 weapons.xml 文件。
     * @param onLoadHandler 加载成功后的回调函数。
     * @param onErrorHandler 加载失败后的回调函数。
     */
    public function loadWeapons(onLoadHandler:Function, onErrorHandler:Function):Void {
        this.load(function(data:Object):Void {
            trace("WeaponsLoader: 文件加载成功！");
            trace("Parsed Data: " + ObjectUtil.toString(data)); // 调试输出解析结果
            if (onLoadHandler != null) onLoadHandler(data);
        }, function():Void {
            trace("WeaponsLoader: 文件加载失败！");
            if (onErrorHandler != null) onErrorHandler();
        });
    }

    /**
     * 获取已加载的 weapons 数据。
     * @return Object 解析后的数据对象，如果尚未加载，则返回 null。
     */
    public function getWeaponsData():Object {
        return this.getData();
    }
}
```

### 使用自定义加载器

```actionscript
import org.flashNight.gesh.xml.LoadXml.WeaponsLoader;

// 获取 WeaponsLoader 实例
var weaponsLoader:WeaponsLoader = WeaponsLoader.getInstance();

// 加载 weapons.xml 文件
weaponsLoader.loadWeapons(
    function(data:Object):Void {
        trace("主程序：weapons.xml 加载成功！");
        trace("主程序解析结果: " + weaponsLoader);
        // 在此处处理 weapons 数据
    },
    function():Void {
        trace("主程序：weapons.xml 加载失败！");
    }
);

// 检查是否已加载
if (weaponsLoader.isLoaded()) {
    var weaponsData:Object = weaponsLoader.getWeaponsData();
    // 使用 weaponsData 进行业务逻辑处理
}
```

---

## 示例代码

### BulletsCasesLoader 示例

`BulletsCasesLoader` 是一个继承自 `BaseXMLLoader` 的具体加载器，用于加载 `bullets_cases.xml` 文件。

```actionscript
import org.flashNight.gesh.xml.LoadXml.BaseXMLLoader;
import org.flashNight.gesh.object.ObjectUtil;

class org.flashNight.gesh.xml.LoadXml.BulletsCasesLoader extends BaseXMLLoader {
    private static var instance:BulletsCasesLoader = null;

    /**
     * 获取单例实例。
     * @return BulletsCasesLoader 实例。
     */
    public static function getInstance():BulletsCasesLoader {
        if (instance == null) {
            instance = new BulletsCasesLoader();
        }
        return instance;
    }

    /**
     * 构造函数，指定 bullets_cases.xml 的相对路径。
     */
    private function BulletsCasesLoader() {
        super("data/items/bullets_cases.xml");
    }

    /**
     * 加载 bullets_cases.xml 文件。
     * @param onLoadHandler 加载成功后的回调函数。
     * @param onErrorHandler 加载失败后的回调函数。
     */
    public function loadBulletsCases(onLoadHandler:Function, onErrorHandler:Function):Void {
        this.load(function(data:Object):Void {
            trace("BulletsCasesLoader: 文件加载成功！");
            trace("Parsed Data: " + ObjectUtil.toString(data)); // 调试输出解析结果
            if (onLoadHandler != null) onLoadHandler(data);
        }, function():Void {
            trace("BulletsCasesLoader: 文件加载失败！");
            if (onErrorHandler != null) onErrorHandler();
        });
    }

    /**
     * 获取已加载的 bullets_cases 数据。
     * @return Object 解析后的数据对象，如果尚未加载，则返回 null。
     */
    public function getBulletsCasesData():Object {
        return this.getData();
    }
}
```

### 使用示例

```actionscript
import org.flashNight.gesh.xml.LoadXml.BulletsCasesLoader;

// 获取 BulletsCasesLoader 实例
var bulletsLoader:BulletsCasesLoader = BulletsCasesLoader.getInstance();

// 加载 bullets_cases.xml 文件
bulletsLoader.loadBulletsCases(
    function(data:Object):Void {
        trace("主程序：bullets_cases.xml 加载成功！");
        trace("主程序解析结果: " + bulletsLoader);
        // 在此处处理 bullets 数据
    },
    function():Void {
        trace("主程序：bullets_cases.xml 加载失败！");
    }
);

// 检查是否已加载
if (bulletsLoader.isLoaded()) {
    var bulletsData:Object = bulletsLoader.getBulletsCasesData();
    trace("已加载的 bullets 数据：" + bulletsLoader.objectToString(bulletsData));
    // 使用 bulletsData 进行业务逻辑处理
}
```

---

## 最佳实践

1. **单例模式**：为每个具体的加载器类实现单例模式，确保全局只有一个实例，便于数据共享和管理。
2. **路径管理**：始终通过 `PathManager` 解析和管理文件路径，确保路径的一致性和正确性，尤其是在包含中文字符的路径中。
3. **缓存机制**：利用基类的缓存机制，避免重复加载同一文件，提高性能。
4. **回调处理**：充分利用加载成功和失败的回调函数，进行相应的数据处理或错误处理。
5. **数据验证**：在回调函数中，添加对加载数据的验证逻辑，确保数据结构和内容符合预期。
6. **错误处理**：在错误回调中，提供详细的错误信息和可能的修复建议，便于快速定位问题。
7. **调试辅助**：使用 `objectToString` 方法输出加载的数据对象，便于调试和验证数据内容。

---

## 常见问题

### Q1: 为什么 `BaseXMLLoader` 会提示“未检测到资源目录”？

**原因**：`PathManager` 未能在当前运行环境中检测到 `resources/` 目录，导致无法设置基础路径。

**解决方法**：
- 确认运行环境的文件路径是否包含 `resources/` 目录。
- 检查 `_url` 是否正确反映了实际的文件路径。
- 确保 `PathManager` 的 `initialize` 方法在程序启动时被正确调用。

### Q2: 如何处理加载失败的情况？

**解决方法**：
- 在加载失败的回调函数中，添加详细的错误处理逻辑，例如重试加载、显示错误消息给用户等。
- 检查文件路径是否正确，文件是否存在，文件权限是否允许读取。
- 确保 XML 文件的格式正确，避免解析错误。

### Q3: `objectToString` 方法输出的 `[object Object]` 如何解决？

**原因**：`objectToString` 方法未被调用或调用位置错误。

**解决方法**：
- 确保在输出对象时，调用了 `objectToString` 方法。例如：
  ```actionscript
  trace("Parsed Data: " + loader);
  ```
- 检查 `objectToString` 方法是否正确定义并可访问。

---

## 附录

### PathManager 类

```actionscript
class org.flashNight.gesh.path.PathManager {
    private static var basePath:String = null; // 资源根路径
    private static var isValidEnvironment:Boolean = false; // 是否在 resource 环境中运行

    public static function initialize():Void {
        var url:String = decodeURL(_url); // 获取当前文件的 URL 并解码中文路径
        trace("当前 URL: " + url);

        var resourceIndex:Number = url.indexOf("resources/");
        if (resourceIndex != -1) {
            basePath = url.substring(0, resourceIndex + "resources/".length); // 截断到 resources/ 为止
            isValidEnvironment = true;
            trace("检测到资源目录，基础路径设置为: " + basePath);
        } else {
            basePath = null;
            isValidEnvironment = false;
            trace("未检测到资源目录，路径管理器未启用。");
        }
    }

    public static function getBasePath():String {
        if (basePath == null) {
            initialize();
        }
        return basePath;
    }

    public static function isEnvironmentValid():Boolean {
        if (basePath == null) {
            initialize();
        }
        return isValidEnvironment;
    }

    public static function resolvePath(relativePath:String):String {
        if (!isEnvironmentValid()) {
            trace("当前不在资源环境中，无法解析路径: " + relativePath);
            return null;
        }
        return basePath + relativePath;
    }

    public static function adaptPathToURL(filePath:String):String {
        if (filePath == null) {
            return null;
        }
        return "file:///" + filePath.split("\\").join("/");
    }

    private static function decodeURL(encodedURL:String):String {
        return unescape(encodedURL);
    }

    public static function getScriptsClassDefinitionPath():String {
        if (!isEnvironmentValid()) {
            trace("当前不在资源环境中，无法获取 scripts/类定义/ 路径。");
            return null;
        }
        return basePath + "scripts/类定义/";
    }
}
```

### XMLLoader 类

```actionscript
import org.flashNight.gesh.string.StringUtils;
import org.flashNight.gesh.xml.XMLParser;

class org.flashNight.gesh.xml.XMLLoader {
    private var xml:XML;
    private var onLoadHandler:Function;
    private var onErrorHandler:Function;
    private var parsedData:Object;

    /**
     * 构造函数，初始化 XMLLoader
     * @param xmlFilePath 要加载的 XML 文件地址。
     * @param onLoadHandler 加载完成后的处理函数，接收解析后的对象作为参数。
     * @param onErrorHandler 可选，加载失败后的处理函数。
     */
    public function XMLLoader(xmlFilePath:String, onLoadHandler:Function, onErrorHandler:Function) {
        this.xml = new XML();
        this.xml.ignoreWhite = true;
        this.onLoadHandler = onLoadHandler;
        this.onErrorHandler = onErrorHandler;

        var self:XMLLoader = this;
        this.xml.onLoad = function(loadSuccess:Boolean):Void {
            if (loadSuccess) {
                self.handleXMLLoad();
            } else {
                self.handleXMLError();
            }
        };
        this.xml.load(xmlFilePath);
    }

    /**
     * 处理 XML 加载完成后的逻辑。
     */
    private function handleXMLLoad():Void {
        this.parsedData = XMLParser.parseXMLNode(this.xml.firstChild);
        if (this.onLoadHandler != null) {
            this.onLoadHandler(this.parsedData);
        }
    }

    /**
     * 处理 XML 加载错误后的逻辑。
     */
    private function handleXMLError():Void {
        trace("XMLLoader: Failed to load XML file.");
        if (this.onErrorHandler != null) {
            this.onErrorHandler();
        }
    }

    /**
     * 获取解析后的数据。
     * @return Object 解析后的数据对象。
     */
    public function getParsedData():Object {
        return this.parsedData;
    }
}
```

---

# 结语

通过 `BaseXMLLoader` 基类，您可以轻松创建各种 XML 加载器类，统一管理加载流程，简化代码结构，提高项目的可维护性和扩展性。结合 `PathManager` 和 `XMLLoader`，`BaseXMLLoader` 提供了一个强大的框架，满足大多数 XML 加载需求。
