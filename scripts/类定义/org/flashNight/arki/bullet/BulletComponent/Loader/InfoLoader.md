# InfoLoader 使用指南

## 目录

1. [简介](#简介)
2. [架构与设计](#架构与设计)
    - [单例模式](#单例模式)
    - [组件加载器](#组件加载器)
    - [映射表机制](#映射表机制)
3. [功能与工作流程](#功能与工作流程)
    - [数据加载](#数据加载)
    - [数据解析](#数据解析)
    - [回调机制](#回调机制)
4. [快速开始](#快速开始)
    - [初始化 InfoLoader](#初始化-InfoLoader)
    - [注册回调函数](#注册回调函数)
    - [获取加载的数据](#获取加载的数据)
5. [扩展与维护](#扩展与维护)
    - [新增组件加载器](#新增组件加载器)
    - [注册新的加载器](#注册新的加载器)
6. [技术细节](#技术细节)
    - [接口定义](#接口定义)
    - [InfoLoader 类详解](#InfoLoader-类详解)
    - [ShellLoader 类详解](#ShellLoader-类详解)
7. [示例代码](#示例代码)
    - [完整代码结构](#完整代码结构)
    - [实际应用示例](#实际应用示例)
8. [最佳实践](#最佳实践)
9. [常见问题](#常见问题)
10. [总结](#总结)

---

## 简介

`InfoLoader` 是一个模块化、可扩展的子弹属性加载器，设计用于在 ActionScript 2 (AS2) 项目中高效管理和解析 `bullets_cases.xml` 文件中的子弹数据。通过实现 `IComponentLoader` 接口的不同加载器，`InfoLoader` 能够灵活地处理多种子弹属性，并将其组织成易于访问和维护的结构。

---

## 架构与设计

### 单例模式

`InfoLoader` 采用单例模式，确保在应用程序生命周期中仅存在一个实例。这种设计模式有助于集中管理子弹数据，避免重复加载和数据不一致的问题。

**实现方式：**

- **私有静态实例变量：**
    ```actionscript
    private static var instance:InfoLoader = null;
    ```
- **私有构造函数：**
    ```actionscript
    private function InfoLoader() { /* ... */ }
    ```
- **公共静态获取实例方法：**
    ```actionscript
    public static function getInstance():InfoLoader {
        if (instance == null) {
            instance = new InfoLoader();
        }
        return instance;
    }
    ```

### 组件加载器

通过 `IComponentLoader` 接口，`InfoLoader` 支持多种属性解析逻辑。每个加载器负责解析 `bullets_cases.xml` 中特定类型的属性，如弹壳 (`ShellLoader`)、移动 (`MovementLoader`) 等。

**接口定义：**

```actionscript
interface IComponentLoader {
    /**
     * 加载并解析子弹相关信息
     * @param data:Object 原始数据
     * @return Object 加载后的信息
     */
    function load(data:Object):Object;
}
```

### 映射表机制

`InfoLoader` 使用一个映射表 (`loadersMap`) 将属性类型与对应的加载器绑定。这种设计使得添加新属性类型变得简单，只需在映射表中注册新的加载器。

**示例：**

```actionscript
this.loadersMap["shellData"] = new ShellLoader();
this.loadersMap["ammoData"] = new AmmoLoader();
```

---

## 功能与工作流程

### 数据加载

`InfoLoader` 通过 `BulletsCasesLoader` 加载 `bullets_cases.xml` 文件中的子弹数据。加载过程是异步的，加载完成后会触发回调函数。

### 数据解析

加载完成后，`InfoLoader` 遍历每个子弹节点，依次调用映射表中注册的各个加载器进行解析。解析结果按照属性类型（如 `shellData`）和子弹名称进行组织。

### 回调机制

`InfoLoader` 提供 `onLoad` 方法，允许用户在数据加载完成后注册回调函数。所有注册的回调将在数据加载完成后依次执行，确保用户可以在数据准备好之后进行后续操作。

---

## 快速开始

### 初始化 InfoLoader

在项目初始化阶段，确保 `InfoLoader` 被实例化，以便开始加载和解析子弹数据。

```actionscript
InfoLoader.getInstance();
```

### 注册回调函数

使用 `onLoad` 方法注册回调函数，在数据加载完成后执行自定义逻辑。

```actionscript
InfoLoader.getInstance().onLoad(function(data:Object):Void {
    _root.弹壳系统.弹壳映射表 = data.shellData;
    trace("弹壳配置数据已加载完成！");
});
```

### 获取加载的数据

通过 `getData` 方法获取特定类型的数据，并可指定默认值以防数据未加载。

```actionscript
var shellData:Object = InfoLoader.getInstance().getData("shellData", {});
trace("弹壳数据: " + shellData);
```

---

## 扩展与维护

### 新增组件加载器

若需处理新的子弹属性类型，如弹药 (`Ammo`) 或效果 (`Effect`)，需实现 `IComponentLoader` 接口的新的加载器类。

**示例：AmmoLoader**

```actionscript
class AmmoLoader implements IComponentLoader {
    public function AmmoLoader() {
        // 构造函数，可初始化属性
    }

    /**
     * 实现接口方法，加载并解析弹药相关信息
     * @param data:Object 子弹数据节点
     * @return Object 解析后的弹药信息
     */
    public function load(data:Object):Object {
        var ammoInfo:Object = {};
        var ammoNode:Object = data.ammo;

        if (ammoNode != undefined) {
            ammoInfo.弹药类型 = (ammoNode.type != undefined) ? ammoNode.type : "默认弹药";
            ammoInfo.弹药数量 = (ammoNode.count != undefined) ? Number(ammoNode.count) : 0;
        }

        return ammoInfo;
    }
}
```

### 注册新的加载器

在 `InfoLoader` 的构造函数中，将新的加载器实例与对应的键名绑定到 `loadersMap` 中。

```actionscript
this.loadersMap["ammoData"] = new AmmoLoader();
```

这样，`InfoLoader` 在数据解析时会自动调用 `AmmoLoader` 来处理 `ammoData`。

---

## 技术细节

### 接口定义

#### IComponentLoader 接口

定义了加载器必须实现的 `load` 方法，用于解析特定类型的数据。

```actionscript
interface IComponentLoader {
    /**
     * 加载并解析子弹相关信息
     * @param data:Object 原始数据
     * @return Object 加载后的信息
     */
    function load(data:Object):Object;
}
```

### InfoLoader 类详解

#### 属性

- `private static var instance:InfoLoader = null;`
    - 单例实例。
- `private var infoData:Object = {};`
    - 存储解析后的所有数据。
- `private var isLoaded:Boolean = false;`
    - 标记数据是否已加载完成。
- `private var onLoadCallbacks:Array = [];`
    - 存储加载完成后的回调函数列表。
- `private var loadersMap:Object = {};`
    - 映射表，将数据类型键名与加载器实例绑定。

#### 构造函数

```actionscript
private function InfoLoader() {
    this.loadersMap["shellData"] = new ShellLoader();
    // 可以在此添加更多加载器
    // this.loadersMap["ammoData"] = new AmmoLoader();

    var server = ServerManager.getInstance();
    var self = this;

    BulletsCasesLoader.getInstance().loadBulletsCases(
        function(data:Object):Void {
            var resultData:Object = {}; // 存储解析后的总数据
            var bulletNodes:Array = data.bullet;

            for (var i:Number = 0; i < bulletNodes.length; i++) {
                var bulletNode:Object = bulletNodes[i];

                // 遍历映射表，按键名执行加载器
                for (var key:String in self.loadersMap) {
                    var loader:IComponentLoader = self.loadersMap[key];
                    var componentInfo:Object = loader.load(bulletNode);

                    // 如果加载器返回 null 或空对象，跳过挂载
                    if (componentInfo == null || typeof(componentInfo) != "object" || Object.prototype.toString.call(componentInfo) != "[object Object]") {
                        continue;
                    }

                    // 初始化存储键，确保为对象结构
                    if (resultData[key] == undefined) {
                        resultData[key] = {};
                    }

                    // 使用 name 作为键，存储解析结果
                    var bulletName:String = (bulletNode.shell != undefined && bulletNode.shell.name != undefined)
                        ? bulletNode.shell.name
                        : ("bullet_" + i);

                    resultData[key][bulletName] = componentInfo;
                }
            }

            self.infoData = resultData; // 保存总数据到 infoData
            self.isLoaded = true;

            // 触发所有回调
            for (var k:Number = 0; k < self.onLoadCallbacks.length; k++) {
                self.onLoadCallbacks[k](self.infoData);
            }

            server.sendServerMessage("BulletsCasesLoader：bullets_cases.xml 加载成功！");

            // 清空回调队列
            self.onLoadCallbacks = [];
        },
        function():Void {
            server.sendServerMessage("BulletsCasesLoader：bullets_cases.xml 加载失败！");
        }
    );
}
```

**逻辑说明：**

1. **加载器注册：**
    - 将 `ShellLoader` 实例注册到 `loadersMap` 中，键名为 `"shellData"`。
    - 可以根据需要注册更多加载器。

2. **数据加载：**
    - 使用 `BulletsCasesLoader` 异步加载 `bullets_cases.xml`。
    - 成功加载后，通过回调函数处理数据。

3. **数据解析：**
    - 遍历每个子弹节点 (`bulletNode`)。
    - 对于每种数据类型（如 `shellData`），调用对应的加载器解析数据。
    - 如果加载器返回有效数据，将其存储在 `resultData` 中，键名为子弹的 `name` 或默认值 `"bullet_x"`。

4. **数据存储与回调触发：**
    - 将解析后的数据存储在 `infoData` 中。
    - 标记 `isLoaded` 为 `true`。
    - 依次执行所有注册的回调函数，传递解析后的数据。
    - 发送服务器消息，指示加载成功。
    - 清空回调队列。

#### 方法

##### onLoad

**描述：** 注册加载完成后的回调函数。

**定义：**

```actionscript
public function onLoad(callback:Function):Void {
    if (this.isLoaded) {
        callback(this.infoData); // 如果已经加载完成，直接执行回调
    } else {
        this.onLoadCallbacks.push(callback); // 否则加入回调队列
    }
}
```

**使用说明：**

- 在需要使用加载数据的地方，调用 `onLoad` 方法注册回调。
- 回调函数将在数据加载完成后自动执行。

**示例：**

```actionscript
InfoLoader.getInstance().onLoad(function(data:Object):Void {
    _root.弹壳系统.弹壳映射表 = data.shellData;
    trace("弹壳配置数据已加载完成！");
});
```

##### getData

**描述：** 通用化获取加载的数据，支持设置默认值。

**定义：**

```actionscript
public function getData(key:String, defaultValue:Object):Object {
    return this.infoData[key] != undefined ? this.infoData[key] : defaultValue;
}
```

**参数：**

- `key`：数据类型的键名（如 `"shellData"`）。
- `defaultValue`：当指定键的数据不存在时返回的默认值。

**返回值：** 加载的数据对象或默认值。

**使用说明：**

- 适用于在数据加载完成后立即获取数据。
- 可以在回调函数中使用，确保数据已加载。

**示例：**

```actionscript
var shellData:Object = InfoLoader.getInstance().getData("shellData", {});
trace("弹壳数据: " + shellData);
```

##### getInstance

**描述：** 获取 `InfoLoader` 的单例实例。

**定义：**

```actionscript
public static function getInstance():InfoLoader {
    if (instance == null) {
        instance = new InfoLoader();
    }
    return instance;
}
```

**使用说明：**

- 在项目中任何需要访问 `InfoLoader` 的地方，通过 `getInstance` 方法获取实例。

**示例：**

```actionscript
var loader:InfoLoader = InfoLoader.getInstance();
```

### ShellLoader 类详解

`ShellLoader` 是 `IComponentLoader` 接口的一个实现，负责解析子弹的弹壳相关信息。

#### 类定义

```actionscript
class org.flashNight.arki.bullet.BulletComponent.Loader.ShellLoader implements IComponentLoader {
    public function ShellLoader() {
        // 构造函数，若需要初始化可以在此实现
    }

    /**
     * 实现接口方法，加载并解析弹壳相关信息
     * @param data:Object 子弹数据节点
     * @return Object 解析后的弹壳信息
     */
    public function load(data:Object):Object {
        var shellInfo:Object = {};
        var shellNode:Object = data.shell;

        shellInfo.弹壳 = (shellNode != undefined && shellNode.casing != undefined) ? shellNode.casing : "步枪弹壳";
        shellInfo.myX = (shellNode != undefined && shellNode.xOffset != undefined) ? Number(shellNode.xOffset) : 0;
        shellInfo.myY = (shellNode != undefined && shellNode.yOffset != undefined) ? Number(shellNode.yOffset) : 0;
        shellInfo.模拟方式 = (shellNode != undefined && shellNode.simulationMethod != undefined) ? shellNode.simulationMethod : "标准";

        return shellInfo;
    }
}
```

#### 方法

##### load

**描述：** 解析子弹的弹壳相关信息。

**定义：**

```actionscript
public function load(data:Object):Object {
    var shellInfo:Object = {};
    var shellNode:Object = data.shell;

    shellInfo.弹壳 = (shellNode != undefined && shellNode.casing != undefined) ? shellNode.casing : "步枪弹壳";
    shellInfo.myX = (shellNode != undefined && shellNode.xOffset != undefined) ? Number(shellNode.xOffset) : 0;
    shellInfo.myY = (shellNode != undefined && shellNode.yOffset != undefined) ? Number(shellNode.yOffset) : 0;
    shellInfo.模拟方式 = (shellNode != undefined && shellNode.simulationMethod != undefined) ? shellNode.simulationMethod : "标准";

    return shellInfo;
}
```

**逻辑说明：**

1. **检查 `shell` 节点是否存在：**
    - 如果存在，提取相关属性并赋予默认值。
    - 如果不存在，使用默认值初始化 `shellInfo`。

2. **返回解析后的弹壳信息对象。**

---

## 示例代码

### 完整代码结构

以下是 `InfoLoader` 和 `ShellLoader` 的完整实现代码：

#### IComponentLoader 接口

```actionscript
interface org.flashNight.arki.bullet.BulletComponent.Loader.IComponentLoader {
    /**
     * 加载并解析子弹相关信息
     * @param data:Object 原始数据
     * @return Object 加载后的信息
     */
    function load(data:Object):Object;
}
```

#### ShellLoader 类

```actionscript
import org.flashNight.arki.bullet.BulletComponent.Loader.IComponentLoader;

class org.flashNight.arki.bullet.BulletComponent.Loader.ShellLoader implements IComponentLoader {
    public function ShellLoader() {
        // 构造函数，若需要初始化可以在此实现
    }

    /**
     * 实现接口方法，加载并解析弹壳相关信息
     * @param data:Object 子弹数据节点
     * @return Object 解析后的弹壳信息
     */
    public function load(data:Object):Object {
        var shellInfo:Object = {};
        var shellNode:Object = data.shell;

        shellInfo.弹壳 = (shellNode != undefined && shellNode.casing != undefined) ? shellNode.casing : "步枪弹壳";
        shellInfo.myX = (shellNode != undefined && shellNode.xOffset != undefined) ? Number(shellNode.xOffset) : 0;
        shellInfo.myY = (shellNode != undefined && shellNode.yOffset != undefined) ? Number(shellNode.yOffset) : 0;
        shellInfo.模拟方式 = (shellNode != undefined && shellNode.simulationMethod != undefined) ? shellNode.simulationMethod : "标准";

        return shellInfo;
    }
}
```

#### InfoLoader 类

```actionscript
import org.flashNight.arki.bullet.BulletComponent.Loader.IComponentLoader;
import org.flashNight.arki.bullet.BulletComponent.Loader.ShellLoader;
import org.flashNight.gesh.xml.LoadXml.BulletsCasesLoader;
import org.flashNight.neur.Server.ServerManager;

class org.flashNight.arki.bullet.BulletComponent.Loader.InfoLoader {
    private static var instance:InfoLoader = null;
    private var infoData:Object = {};
    private var isLoaded:Boolean = false; // 标记是否已完成加载
    private var onLoadCallbacks:Array = []; // 加载完成后的回调函数列表
    private var loadersMap:Object = {}; // 组件加载器列表

    /**
     * 私有构造函数
     */
    private function InfoLoader() {
        this.loadersMap["shellData"] = new ShellLoader();
        // 可以在此添加更多加载器，例如：
        // this.loadersMap["ammoData"] = new AmmoLoader();

        var server = ServerManager.getInstance();
        var self = this;

        BulletsCasesLoader.getInstance().loadBulletsCases(
            function(data:Object):Void {
                var resultData:Object = {}; // 存储解析后的总数据
                var bulletNodes:Array = data.bullet;

                for (var i:Number = 0; i < bulletNodes.length; i++) {
                    var bulletNode:Object = bulletNodes[i];

                    // 遍历映射表，按键名执行加载器
                    for (var key:String in self.loadersMap) {
                        var loader:IComponentLoader = self.loadersMap[key];
                        var componentInfo:Object = loader.load(bulletNode);

                        // 如果加载器返回 null 或空对象，跳过挂载
                        if (componentInfo == null || typeof(componentInfo) != "object" || Object.prototype.toString.call(componentInfo) != "[object Object]") {
                            continue;
                        }

                        // 初始化存储键，确保为对象结构
                        if (resultData[key] == undefined) {
                            resultData[key] = {};
                        }

                        // 使用 name 作为键，存储解析结果
                        var bulletName:String = (bulletNode.shell != undefined && bulletNode.shell.name != undefined)
                            ? bulletNode.shell.name
                            : ("bullet_" + i);

                        resultData[key][bulletName] = componentInfo;
                    }
                }

                self.infoData = resultData; // 保存总数据到 infoData
                self.isLoaded = true;

                // 触发所有回调
                for (var k:Number = 0; k < self.onLoadCallbacks.length; k++) {
                    self.onLoadCallbacks[k](self.infoData);
                }

                server.sendServerMessage("BulletsCasesLoader：bullets_cases.xml 加载成功！");

                // 清空回调队列
                self.onLoadCallbacks = [];
            },
            function():Void {
                server.sendServerMessage("BulletsCasesLoader：bullets_cases.xml 加载失败！");
            }
        );
    }

    /**
     * 注册加载完成后的回调
     */
    public function onLoad(callback:Function):Void {
        if (this.isLoaded) {
            callback(this.infoData); // 如果已经加载完成，直接执行回调
        } else {
            this.onLoadCallbacks.push(callback); // 否则加入回调队列
        }
    }

    /**
     * 通用化获取加载的数据，支持默认值
     * @param key:String - 数据的键名
     * @param defaultValue:Object - 数据不存在时返回的默认值（可选）
     * @return Object - 加载的数据对象或默认值
     */
    public function getData(key:String, defaultValue:Object):Object {
        return this.infoData[key] != undefined ? this.infoData[key] : defaultValue;
    }

    /**
     * 获取单例实例
     */
    public static function getInstance():InfoLoader {
        if (instance == null) {
            instance = new InfoLoader();
        }
        return instance;
    }
}
```

### 实际应用示例

假设您在游戏中需要加载并使用弹壳数据，可以按照以下步骤操作：

1. **注册回调函数**

    在游戏初始化或需要加载数据的地方，注册回调函数以处理加载完成后的数据。

    ```actionscript
    InfoLoader.getInstance().onLoad(function(data:Object):Void {
        _root.弹壳系统.弹壳映射表 = data.shellData;
        trace("弹壳配置数据已加载完成！");
    });
    ```

2. **在回调函数中使用加载的数据**

    一旦数据加载完成，注册的回调函数将被执行，您可以在其中进行后续操作，如初始化弹壳系统。

    ```actionscript
    InfoLoader.getInstance().onLoad(function(data:Object):Void {
        _root.弹壳系统.弹壳映射表 = data.shellData;
        trace("弹壳配置数据已加载完成！");
        // 进一步初始化或使用弹壳数据
    });
    ```

3. **获取特定类型的数据**

    如果需要在加载完成后立即获取特定类型的数据，可以使用 `getData` 方法。

    ```actionscript
    var shellData:Object = InfoLoader.getInstance().getData("shellData", {});
    trace("弹壳数据: " + shellData);
    ```

---

## 最佳实践

1. **模块化加载器设计**
    - 每个属性类型应有独立的加载器，实现 `IComponentLoader` 接口。
    - 避免在加载器中处理不相关的逻辑，保持职责单一。

2. **合理命名与映射**
    - 确保 `loadersMap` 中的键名与加载器处理的数据类型一致，便于理解和维护。
    - 使用有意义的键名，如 `"shellData"`、`"ammoData"` 等。

3. **错误处理**
    - 在加载失败的回调中，除了发送服务器消息，还可以考虑重试机制或用户提示。
    - 确保回调函数能够正确处理数据加载失败的情况。

4. **扩展性考虑**
    - 设计时预留接口，方便未来添加新的加载器。
    - 避免在核心逻辑中硬编码特定的数据类型，使用映射表动态管理加载器。

5. **数据验证**
    - 在加载器中对解析后的数据进行验证，确保数据的完整性和正确性。
    - 可以在回调函数中进一步验证和处理数据。

6. **性能优化**
    - 对于大型 XML 文件，确保解析过程高效，避免阻塞主线程。
    - 考虑分步加载或延迟加载策略，提升应用性能。

---

## 常见问题

### 1. **如何处理加载失败的情况？**

**解答：**
当前实现中，加载失败时通过 `ServerManager` 发送失败消息。为了增强健壮性，您可以在失败回调中添加更多处理逻辑，如重试加载或提示用户。

**示例改进：**

```actionscript
function():Void {
    server.sendServerMessage("BulletsCasesLoader：bullets_cases.xml 加载失败！");
    // 添加重试机制或用户提示
    // 例如，重试加载三次
    var retryCount:Number = 0;
    var maxRetries:Number = 3;
    var retryLoad = function():Void {
        if (retryCount < maxRetries) {
            retryCount++;
            BulletsCasesLoader.getInstance().loadBulletsCases(successCallback, retryLoad);
        } else {
            trace("BulletsCasesLoader：bullets_cases.xml 多次加载失败！");
            // 可选择触发回调队列中的失败逻辑
        }
    };
    retryLoad();
}
```

### 2. **如何确保加载器的顺序执行？**

**解答：**
当前实现中，加载器是按映射表中键名的遍历顺序执行的。如果加载顺序有要求，可以调整 `loadersMap` 的定义顺序，或在加载器内部处理依赖关系。

### 3. **如何在运行时动态添加新的加载器？**

**解答：**
您可以在 `InfoLoader` 初始化后，通过访问 `loadersMap` 动态添加新的加载器。

**示例：**

```actionscript
var ammoLoader:IComponentLoader = new AmmoLoader();
InfoLoader.getInstance().loadersMap["ammoData"] = ammoLoader;
```

### 4. **如何在回调中处理部分加载的数据缺失？**

**解答：**
在回调函数中，您可以检查特定的数据类型是否存在，并进行相应的处理。

**示例：**

```actionscript
InfoLoader.getInstance().onLoad(function(data:Object):Void {
    if (data.shellData != undefined) {
        _root.弹壳系统.弹壳映射表 = data.shellData;
        trace("弹壳配置数据已加载完成！");
    } else {
        trace("弹壳数据缺失，无法初始化弹壳系统！");
    }
});
```

---

## 总结

`InfoLoader` 通过单例模式和模块化的组件加载器设计，实现了灵活、高效的子弹属性加载与管理。其映射表机制使得新增和维护不同类型的数据解析变得简单，同时通过异步回调机制确保数据加载完成后能够及时响应。遵循最佳实践和扩展指南，`InfoLoader` 能够适应项目中不断增长的需求，保持代码的可维护性和扩展性。
