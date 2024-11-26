# AS2 自定义 Proxy 类使用指南

## 目录

1. [概述](#概述)
2. [实现原理](#实现原理)
3. [特性与功能](#特性与功能)
4. [与 JavaScript Proxy 的区别](#与-javascript-proxy-的区别)
5. [使用方法](#使用方法)
    - [引入 Proxy 类](#引入-proxy-类)
    - [属性监视器](#属性监视器)
        - [添加属性 Setter 监视器](#添加属性-setter-监视器)
        - [添加属性 Setter 监视器（基于 `watch` 方法）](#添加属性-setter-监视器基于-watch-方法)
        - [添加属性 Getter 监视器](#添加属性-getter-监视器)
        - [移除属性 Setter 监视器](#移除属性-setter-监视器)
        - [移除属性 Setter 监视器（基于 `watch` 方法）](#移除属性-setter-监视器基于-watch-方法)
        - [移除属性 Getter 监视器](#移除属性-getter-监视器)
    - [函数调用监视器](#函数调用监视器)
        - [添加函数调用监视器](#添加函数调用监视器)
        - [移除函数调用监视器](#移除函数调用监视器)
6. [适用场景](#适用场景)
7. [局限性](#局限性)
8. [示例代码](#示例代码)
    - [属性监视示例](#属性监视示例)
    - [属性监视示例（基于 `watch` 方法）](#属性监视示例基于-watch-方法)
    - [函数调用监视示例](#函数调用监视示例)
9. [注意事项](#注意事项)
10. [结语](#结语)

---

## 概述

在 ActionScript 2 (AS2) 中，原生并未提供类似 JavaScript 中 `Proxy` 对象的功能。然而，在某些开发场景中，我们需要对对象的属性访问、修改以及方法调用进行监视或拦截。为此，我们自定义实现了一个 `Proxy` 类，通过利用 AS2 的特性，实现了对对象属性和方法的监视。

## 实现原理

该自定义 `Proxy` 类的核心原理包括：

1. **属性拦截**：使用 AS2 的 `addProperty` 方法，为对象的属性设置自定义的 Getter 和 Setter。当属性被访问或修改时，触发对应的回调函数。

2. **函数拦截**：通过替换对象的方法为代理函数，在代理函数中调用回调函数，然后再执行原始方法。

3. **唯一标识 (UID)**：为每个被监视的对象和函数分配一个唯一的 UID，便于在内部管理回调函数。

4. **回调管理**：使用哈希表存储对象和属性的回调函数列表，实现对回调的添加和移除操作。

## 特性与功能

### 新增特性

- **基于 `watch` 的 Setter 监视器**：
  - 通过 `addPropertySetterWatcherWithWatch` 方法，可以利用 AS2 的原生 `watch` 方法，实现更高效的 Setter 监视功能。
  
- **基于 `watch` 的 Setter 监视器移除**：
  - 使用 `removePropertyWatcherWithWatch` 方法，可以移除通过 `addPropertySetterWatcherWithWatch` 添加的 Setter 监视器，确保监视器能够被正确管理和清理。

### 更新后的特性列表

- **属性监视**：可以监视对象属性的读取（Getter）和写入（Setter）操作。
- **基于 `watch` 的 Setter 监视**：通过原生 `watch` 方法，提高 Setter 监视的性能和效率。
- **函数调用监视**：可以监视对象方法的调用，拦截方法调用前的操作。
- **多回调支持**：支持为同一属性或方法注册多个回调函数，按顺序执行。
- **动态添加与移除**：支持在运行时动态添加和移除监视器。
- **回调参数传递**：
  - **Setter 回调**：接收新值和旧值两个参数。
  - **Getter 回调**：接收当前属性值作为参数。
  - **函数调用回调**：接收与原始函数相同的参数。

## 与 JavaScript Proxy 的区别

- **功能范围**：JavaScript 的 `Proxy` 对象可以拦截几乎所有的对象操作（如属性删除、枚举、函数调用等），而 AS2 的自定义 `Proxy` 类只能拦截属性的 Getter 和 Setter，以及函数调用。

- **实现方式**：JavaScript `Proxy` 是语言层面的特性，提供了原生支持。而 AS2 的 `Proxy` 类是基于语言特性的自定义实现，利用了 `addProperty` 和方法替换的技巧。

- **灵活性**：JavaScript `Proxy` 更加灵活和强大，AS2 的实现有一定的局限性，无法完全模拟 JavaScript `Proxy` 的所有功能。

## 使用方法

### 引入 Proxy 类

首先，需要在您的项目中引入 `Proxy` 类：

```actionscript
import org.flashNight.aven.Proxy.Proxy;
```

### 属性监视器

#### 添加属性 Setter 监视器

```actionscript
Proxy.addPropertySetterWatcher(obj:Object, propName:String, callback:Function):Void
```

- **参数说明**：
  - `obj`：需要监视的对象。
  - `propName`：需要监视的属性名。
  - `callback`：当属性被修改时调用的回调函数，接受两个参数：`newValue`（新值）和 `oldValue`（旧值）。

- **示例**：

```actionscript
var user:Object = {};
Proxy.addPropertySetterWatcher(user, "age", function(newValue, oldValue) {
    trace("Age changed from " + oldValue + " to " + newValue);
});
user.age = 25; // 输出: Age changed from undefined to 25
```

#### 添加属性 Setter 监视器（基于 `watch` 方法）

```actionscript
Proxy.addPropertySetterWatcherWithWatch(obj:Object, propName:String, callback:Function):Void
```

- **参数说明**：
  - `obj`：需要监视的对象。
  - `propName`：需要监视的属性名。
  - `callback`：当属性被修改时调用的回调函数，接受两个参数：`newValue`（新值）和 `oldValue`（旧值）。

- **示例**：

```actionscript
var user:Object = {};
Proxy.addPropertySetterWatcherWithWatch(user, "age", function(newValue, oldValue) {
    trace("WithWatch - Age changed from " + oldValue + " to " + newValue);
});
user.age = 30; // 输出: WithWatch - Age changed from undefined to 30
```

#### 添加属性 Getter 监视器

```actionscript
Proxy.addPropertyGetterWatcher(obj:Object, propName:String, callback:Function):Void
```

- **参数说明**：
  - `obj`：需要监视的对象。
  - `propName`：需要监视的属性名。
  - `callback`：当属性被访问时调用的回调函数，接受一个参数：`value`（当前值）。

- **示例**：

```actionscript
var user:Object = { name: "Alice" };
Proxy.addPropertyGetterWatcher(user, "name", function(value) {
    trace("Name accessed: " + value);
});
var userName = user.name; // 输出: Name accessed: Alice
```

#### 移除属性 Setter 监视器

```actionscript
Proxy.removePropertySetterWatcher(obj:Object, propName:String, callback:Function):Void
```

- **参数说明**：
  - 与 `addPropertySetterWatcher` 相同。

- **示例**：

```actionscript
Proxy.removePropertySetterWatcher(user, "age", setterCallback);
```

#### 移除属性 Setter 监视器（基于 `watch` 方法）

```actionscript
Proxy.removePropertyWatcherWithWatch(obj:Object, propName:String):Void
```

- **参数说明**：
  - `obj`：需要移除监视的对象。
  - `propName`：需要移除监视的属性名。

- **示例**：

```actionscript
Proxy.removePropertyWatcherWithWatch(user, "age");
```

#### 移除属性 Getter 监视器

```actionscript
Proxy.removePropertyGetterWatcher(obj:Object, propName:String, callback:Function):Void
```

- **参数说明**：
  - 与 `addPropertyGetterWatcher` 相同。

- **示例**：

```actionscript
Proxy.removePropertyGetterWatcher(user, "name", getterCallback);
```

### 函数调用监视器

#### 添加函数调用监视器

```actionscript
Proxy.addFunctionCallWatcher(obj:Object, funcName:String, callback:Function):Void
```

- **参数说明**：
  - `obj`：方法所属的对象。
  - `funcName`：需要监视的方法名。
  - `callback`：当方法被调用时执行的回调函数，接受与原方法相同的参数。

- **示例**：

```actionscript
user.sayHello = function(greeting) {
    trace(greeting + ", " + this.name);
};

Proxy.addFunctionCallWatcher(user, "sayHello", function(greeting) {
    trace("sayHello method called with argument: " + greeting);
});

user.sayHello("Hi"); 
// 输出:
// sayHello method called with argument: Hi
// Hi, Alice
```

#### 移除函数调用监视器

```actionscript
Proxy.removeFunctionCallWatcher(obj:Object, funcName:String, callback:Function):Void
```

- **参数说明**：
  - 与 `addFunctionCallWatcher` 相同。

- **示例**：

```actionscript
Proxy.removeFunctionCallWatcher(user, "sayHello", functionCallback);
```

## 适用场景

- **调试与日志**：监视属性和方法的访问，以记录或调试对象的行为。

- **数据绑定**：当属性值改变时，自动更新关联的视图或组件。

- **验证与校验**：在属性设置前，对新值进行验证，确保数据合法性。

- **权限控制**：在方法调用前，检查用户权限，决定是否允许执行。

## 局限性

- **性能影响**：过多的属性和方法监视可能影响性能，建议仅在必要时使用。

- **不支持属性删除**：无法监视属性的删除操作。

- **方法替换风险**：函数监视通过替换原方法实现，可能导致原方法的上下文或引用发生变化。

- **不支持内置对象**：无法对内置对象（如 Array、String）的原型方法进行监视。

## 示例代码

### 属性监视示例

```actionscript
import org.flashNight.aven.Proxy.Proxy;

var product:Object = { price: 100 };

// 添加 Setter 监视器
Proxy.addPropertySetterWatcher(product, "price", function(newValue, oldValue) {
    trace("Price changed from " + oldValue + " to " + newValue);
});

// 添加 Getter 监视器
Proxy.addPropertyGetterWatcher(product, "price", function(value) {
    trace("Price accessed: " + value);
});

// 使用基于 watch 的 Setter 监视器
Proxy.addPropertySetterWatcherWithWatch(product, "price", function(newValue, oldValue) {
    trace("WithWatch - Price changed from " + oldValue + " to " + newValue);
});

product.price = 120; 
// 输出: 
// Price changed from 100 to 120
// WithWatch - Price changed from 100 to 120

var currentPrice = product.price; 
// 输出: Price accessed: 120
```

### 属性监视示例（基于 `watch` 方法）

```actionscript
import org.flashNight.aven.Proxy.Proxy;

var user:Object = {};
Proxy.addPropertySetterWatcherWithWatch(user, "age", function(newValue, oldValue) {
    trace("WithWatch - Age changed from " + oldValue + " to " + newValue);
});
user.age = 30; // 输出: WithWatch - Age changed from undefined to 30
```

### 函数调用监视示例

```actionscript
import org.flashNight.aven.Proxy.Proxy;

var calculator:Object = {};

calculator.add = function(a, b) {
    return a + b;
};

// 添加函数调用监视器
Proxy.addFunctionCallWatcher(calculator, "add", function(a, b) {
    trace("add method called with arguments: " + a + ", " + b);
});

var result = calculator.add(5, 7);
// 输出: 
// add method called with arguments: 5, 7
// Result: 12

// 移除函数调用监视器
Proxy.removeFunctionCallWatcher(calculator, "add", functionCallback);
```

## 注意事项

- **回调函数引用**：在添加和移除回调时，需保证是同一函数引用，否则无法正确移除。

- **避免递归调用**：在 Setter 回调中再次修改同一属性，可能导致无限递归，需谨慎处理。

- **内存管理**：及时移除不再需要的监视器，防止内存泄漏。

- **方法上下文**：函数监视器替换了原方法，可能影响方法内部的 `this` 指向，确保在方法内部正确引用上下文。

- **性能影响**：尤其是在大量属性和回调的情况下，监视器的添加和触发可能会影响性能，建议仅在必要时使用，并进行性能评估。

## 结语

自定义的 `Proxy` 类为 AS2 提供了类似于 JavaScript `Proxy` 的部分功能，尽管功能有限，但在特定场景下仍然非常有用。通过合理使用，可以提高代码的可维护性和扩展性。在使用过程中，需注意其局限性和潜在的风险，确保应用的稳定性和性能。





import org.flashNight.aven.Proxy.*;

// 在主时间轴或主类中添加以下代码
var proxyTest:ProxyTest = new ProxyTest();




=== ProxyTest 开始 ===
--- 测试: 添加属性 setter 监视器 ---
[DEBUG] setterCallback 被调用
[PASS] Setter 回调接收到正确的新值
[PASS] Setter 回调接收到正确的旧值
[PASS] Setter 回调被正确触发
--- 测试: 添加基于 watch 的属性 setter 监视器 ---
[DEBUG] setterCallbackWithWatch 被调用
[PASS] SetterWithWatch 回调接收到正确的新值
[PASS] SetterWithWatch 回调接收到正确的旧值
[PASS] SetterWithWatch 回调被正确触发
--- 测试: 添加属性 getter 监视器 ---
[DEBUG] getterCallback 被调用
[PASS] Getter 回调接收到正确的值
[PASS] Getter 回调被正确触发
[PASS] Getter 返回正确的值
--- 测试: 移除属性 setter 监视器 ---
[PASS] Setter 回调已成功移除，未被触发
--- 测试: 移除基于 watch 的属性 setter 监视器 ---
[PASS] SetterWithWatch 回调已成功移除，未被触发
--- 测试: 移除属性 getter 监视器 ---
[PASS] Getter 回调已成功移除，未被触发
--- 测试: 多个回调函数的注册和触发 ---
[DEBUG] setterCallback2 被调用
[PASS] Setter 回调2接收到正确的新值
[PASS] Setter 回调2接收到正确的旧值
[DEBUG] setterCallback1 被调用
[PASS] Setter 回调1接收到正确的新值
[PASS] Setter 回调1接收到正确的旧值
[PASS] Setter 回调1被正确触发
[PASS] Setter 回调2被正确触发
--- 测试: 函数调用监视器 ---
[DEBUG] functionCallback 被调用
[PASS] 函数回调接收到正确的第一个参数
[PASS] 函数回调接收到正确的第二个参数
[PASS] 函数调用回调被正确触发
[PASS] 函数返回值正确
[PASS] 移除函数调用回调后，回调未被触发
[PASS] 函数返回值正确
--- 测试: 性能评估 ---
--- 测试1: 单一属性 Setter 回调性能评估 ---
添加 1000 个 setter 回调耗时: 7 毫秒
设置属性触发 1000 个 setter 回调耗时: 5 毫秒
Setter 回调总调用次数: 1001
--- 测试2: 多属性、多回调 Setter 和 Getter 性能评估 ---
添加 100 个属性，每个属性 100 个回调耗时: 146 毫秒
访问 100 个属性触发所有回调耗时: 89 毫秒
Setter 回调调用总次数: 10100
Getter 回调调用总次数: 10100
--- 测试3: 函数调用代理性能评估 ---
调用函数 1000 次触发所有回调耗时: 441 毫秒
函数回调调用总次数: 101000
--- 测试4: 移除大量 Setter 回调性能评估 ---
添加 50 个属性的 100 个回调耗时: 35 毫秒
移除 50 个属性的 100 个回调耗时: 193 毫秒
--- 测试5: 嵌套代理性能评估 ---
添加 10 层嵌套代理耗时: 1 毫秒
设置属性触发嵌套回调耗时: 0 毫秒
回调调用总次数: 10
--- 扩展性能测试: Watch vs Proxy vs WatchWithWatch vs AddProperty ---
--- 测试样例1: 单属性单回调性能 ---
Watch 添加单回调耗时: 115 ms
Proxy 添加单回调耗时: 37699 ms
WatchWithWatch 添加单回调耗时: 47072 ms
AddProperty 添加单回调耗时: 140503 ms
Watch 设置属性耗时: 0 ms
Proxy 设置属性耗时: 0 ms
WatchWithWatch 设置属性耗时: 0 ms
AddProperty 设置属性耗时: 0 ms
Watch 回调调用次数: 4
Proxy 回调调用次数: 4
WatchWithWatch 回调调用次数: 4
AddProperty 回调调用次数: 4
--- 测试样例2: 多属性多回调性能 ---
Proxy 添加多回调耗时: 1123 ms
Proxy 触发多回调耗时: 69 ms
Proxy 回调调用次数: 9000
--- 测试样例3: 高频触发场景 ---
Proxy 高频触发回调耗时: 36 ms
Proxy 回调调用次数: 3000
=== ProxyTest 结束 ===
通过的测试: 13
失败的测试: 0


