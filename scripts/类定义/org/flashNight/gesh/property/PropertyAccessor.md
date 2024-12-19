# PropertyAccessor 使用手册

---

## 目录

1. [模块概述](#模块概述)
2. [功能特性](#功能特性)
   - [惰性加载（Lazy Loading）](#惰性加载lazy-loading)
   - [计算属性（Computed Properties）](#计算属性computed-properties)
   - [验证机制（Validation Mechanism）](#验证机制validation-mechanism)
   - [回调支持（Callback Support）](#回调支持callback-support)
   - [缓存失效（Cache Invalidation）](#缓存失效cache-invalidation)
3. [技术实现细节](#技术实现细节)
   - [类结构与成员变量](#类结构与成员变量)
   - [构造函数详解](#构造函数详解)
   - [方法详解](#方法详解)
4. [使用指南](#使用指南)
   - [基础用法](#基础用法)
     - [定义简单属性](#定义简单属性)
     - [定义只读属性](#定义只读属性)
   - [高级用法](#高级用法)
     - [使用计算属性](#使用计算属性)
     - [应用验证函数](#应用验证函数)
     - [设置回调函数](#设置回调函数)
5. [示例代码](#示例代码)
   - [示例 1：基本属性管理](#示例-1-基本属性管理)
   - [示例 2：只读属性](#示例-2-只读属性)
   - [示例 3：计算属性与缓存](#示例-3-计算属性与缓存)
   - [示例 4：带验证与回调的属性](#示例-4-带验证与回调的属性)
6. [性能优化](#性能优化)
   - [惰性加载的性能优势](#惰性加载的性能优势)
   - [缓存机制的性能提升](#缓存机制的性能提升)
   - [动态方法替换的效率](#动态方法替换的效率)
   - [性能测试结果](#性能测试结果)
7. [最佳实践](#最佳实践)
   - [选择合适的功能特性](#选择合适的功能特性)
   - [合理使用缓存与invalidate](#合理使用缓存与invalidate)
   - [设计高效的验证与回调函数](#设计高效的验证与回调函数)
8. [常见问题](#常见问题)
9. [结语](#结语)

---

## 模块概述

`PropertyAccessor` 是一个用于管理对象属性的强大工具类。它通过实现 `IProperty` 接口，提供了一系列功能，包括惰性加载、计算属性、验证机制、回调支持以及缓存管理。该模块旨在提升属性管理的灵活性和性能，适用于需要动态属性控制的复杂应用场景。

### 主要特点

- **惰性加载**：通过动态方法替换，延迟属性值的计算，提升性能。
- **计算属性**：支持基于函数的动态属性计算，并缓存结果以避免重复计算。
- **验证机制**：在设置属性值时进行合法性验证，确保数据一致性。
- **回调支持**：属性值变化时触发自定义回调，便于实现依赖关系。
- **缓存失效**：灵活控制计算属性的缓存状态，确保数据的实时性。

---

## 功能特性

### 惰性加载（Lazy Loading）

**概述**：惰性加载是一种优化技术，通过延迟属性值的计算，直到实际需要时才进行计算，从而节省资源和提升性能。

**实现方式**：
- 在首次调用 `get` 方法时，根据是否存在 `computeFunc` 动态替换 `get` 方法的实现。
- 替换后的 `get` 方法直接返回缓存的值，避免后续的重复判断和计算。

### 计算属性（Computed Properties）

**概述**：计算属性是基于其他数据动态生成的属性值。通过提供一个计算函数 (`computeFunc`)，`PropertyAccessor` 可以根据需要计算属性值，并缓存结果以提高效率。

**应用场景**：
- 属性值依赖于其他变量或属性，例如计算面积、价格等。

### 验证机制（Validation Mechanism）

**概述**：在设置属性值时，通过验证函数 (`validationFunc`) 确保新值的合法性。如果新值不符合条件，则拒绝设置，保持原有值。

**应用场景**：
- 限制数值范围、确保字符串格式等。

### 回调支持（Callback Support）

**概述**：在属性值成功设置后，通过回调函数 (`onSetCallback`) 执行额外的逻辑，如更新依赖属性、触发事件等。

**应用场景**：
- 属性值变化后需要通知其他模块或触发某些操作。

### 缓存失效（Cache Invalidation）

**概述**：通过 `invalidate` 方法，可以手动使计算属性的缓存失效，确保下次访问时重新计算属性值。

**应用场景**：
- 当依赖的数据发生变化，需要更新计算属性的值时。

---

## 技术实现细节

### 类结构与成员变量

```actionscript
class org.flashNight.gesh.property.PropertyAccessor implements IProperty {
    private var _value; // 属性值，适用于非计算属性。
    private var _cache; // 缓存值，适用于计算属性。
    private var _cacheValid:Boolean; // 缓存是否有效。
    private var _computeFunc:Function; // 计算函数，用于动态生成属性值。
    private var _onSetCallback:Function; // 回调函数，属性值改变时触发。
    private var _validationFunc:Function; // 验证函数，用于验证新值是否合法。
    private var _propName:String; // 属性名称。
    private var _obj:Object; // 目标对象，即宿主对象。

    private var _originalGet:Function; // 用于在invalidate后恢复get方法。
    private var _originalInvalidate:Function; // 用于不同模式下的invalidate替换。
    
    // ... 构造函数与方法定义 ...
}
```

### 构造函数详解

```actionscript
public function PropertyAccessor(
    obj:Object,
    propName:String,
    defaultValue,
    computeFunc:Function,
    onSetCallback:Function,
    validationFunc:Function
)
```

**参数说明**：

- `obj:Object`：目标对象，属性将被添加到该对象上。
- `propName:String`：属性名称。
- `defaultValue`：属性的默认值，适用于非计算属性。
- `computeFunc:Function`：计算函数，用于生成计算属性的值。可选。
- `onSetCallback:Function`：回调函数，属性值设置后调用。可选。
- `validationFunc:Function`：验证函数，设置属性值前调用以验证新值。可选。

**构造逻辑**：

1. **初始化成员变量**：
   - 根据是否存在 `computeFunc`，初始化 `_cacheValid` 和 `_cache`。
2. **惰性替换 `get` 方法**：
   - 如果 `computeFunc` 存在，定义一个需要计算并缓存值的 `get` 方法，并在首次调用后替换为直接返回缓存值的优化版本。
   - 否则，`get` 方法直接返回 `_value`。
3. **惰性替换 `invalidate` 方法**：
   - 如果是计算属性，`invalidate` 方法会使缓存失效，并重新定义 `get` 方法以重新计算值。
   - 否则，`invalidate` 方法为空操作。
4. **惰性替换 `set` 方法**：
   - 如果是计算属性（即只读），`set` 方法为空操作。
   - 否则，根据是否存在 `validationFunc` 和 `onSetCallback`，定义相应的 `set` 方法逻辑。
5. **添加属性访问器到目标对象**：
   - 使用 `addProperty` 方法将 `get` 和 `set` 方法绑定到目标对象的属性上。

### 方法详解

#### `get()`

**描述**：获取属性值。对于计算属性，首次调用时会计算并缓存结果，后续调用直接返回缓存值。

**返回值**：属性的当前值。

#### `set(newVal):Void`

**描述**：设置属性值。根据是否存在 `validationFunc` 和 `onSetCallback`，执行相应的逻辑。

**参数**：
- `newVal`：新的属性值。

#### `invalidate():Void`

**描述**：使缓存失效。仅适用于计算属性，调用后下次访问属性时会重新计算其值。

#### `getPropName():String`

**描述**：获取属性名称，便于调试和日志记录。

**返回值**：属性名称。

---

## 使用指南

### 基础用法

#### 定义简单属性

```actionscript
var obj:Object = {};
var accessor:PropertyAccessor = new PropertyAccessor(obj, "simpleProp", 10, null, null, null);

trace(obj.simpleProp); // 输出：10
obj.simpleProp = 20;
trace(obj.simpleProp); // 输出：20
```

**说明**：
- 创建一个简单的可读写属性 `simpleProp`，默认值为 `10`。
- 无需计算函数、验证函数或回调函数。

#### 定义只读属性

```actionscript
var obj:Object = {};
var accessor:PropertyAccessor = new PropertyAccessor(
    obj,
    "readOnlyProp",
    0, // 默认值
    function():Number { return 42; }, // 计算函数，返回固定值
    null,
    null
);

trace(obj.readOnlyProp); // 输出：42
obj.readOnlyProp = 50; // 无效操作，属性值不变
trace(obj.readOnlyProp); // 输出：42
```

**说明**：
- 创建一个只读属性 `readOnlyProp`，通过 `computeFunc` 返回固定值 `42`。
- 尝试设置新值 `50` 无效，属性值仍为 `42`。

### 高级用法

#### 使用计算属性

```actionscript
var obj:Object = {};
var baseValue:Number = 5;
var accessor:PropertyAccessor = new PropertyAccessor(
    obj,
    "computedProp",
    0,
    function():Number { return baseValue * 2; }, // 计算函数
    null,
    null
);

trace(obj.computedProp); // 输出：10
baseValue = 15;
accessor.invalidate(); // 缓存失效，重新计算
trace(obj.computedProp); // 输出：30
```

**说明**：
- `computedProp` 根据 `baseValue` 计算其值。
- 通过调用 `invalidate` 方法，缓存失效后重新计算属性值。

#### 应用验证函数

```actionscript
var obj:Object = {};
var accessor:PropertyAccessor = new PropertyAccessor(
    obj,
    "validatedProp",
    50,
    null,
    null,
    function(value:Number):Boolean { return value >= 10 && value <= 100; } // 验证函数
);

trace(obj.validatedProp); // 输出：50
obj.validatedProp = 20; // 合法设置
trace(obj.validatedProp); // 输出：20
obj.validatedProp = 200; // 无效设置
trace(obj.validatedProp); // 输出：20
```

**说明**：
- `validatedProp` 只有在新值在 `[10, 100]` 范围内时才能成功设置。
- 设置 `200` 超出范围，属性值保持 `20` 不变。

#### 设置回调函数

```actionscript
var obj:Object = {};
var callbackTriggered:Boolean = false;

var accessor:PropertyAccessor = new PropertyAccessor(
    obj,
    "callbackProp",
    0,
    null,
    function():Void { callbackTriggered = true; }, // 回调函数
    null
);

obj.callbackProp = 123; // 触发回调
trace(callbackTriggered); // 输出：true
trace(obj.callbackProp); // 输出：123
```

**说明**：
- `callbackProp` 在属性值成功设置后，会触发回调函数，将 `callbackTriggered` 设置为 `true`。
- 确保回调函数在属性值更改时被正确调用。

---

## 示例代码

### 示例 1：基本属性管理

```actionscript
var obj:Object = {};
var accessor:PropertyAccessor = new PropertyAccessor(obj, "age", 25, null, null, null);

trace(obj.age); // 输出：25
obj.age = 30;
trace(obj.age); // 输出：30
```

### 示例 2：只读属性

```actionscript
var obj:Object = {};
var accessor:PropertyAccessor = new PropertyAccessor(
    obj,
    "constantValue",
    0,
    function():Number { return 100; }, // 只读，返回固定值
    null,
    null
);

trace(obj.constantValue); // 输出：100
obj.constantValue = 200; // 无效设置
trace(obj.constantValue); // 输出：100
```

### 示例 3：计算属性与缓存

```actionscript
var obj:Object = {};
var multiplier:Number = 3;
var accessor:PropertyAccessor = new PropertyAccessor(
    obj,
    "calculatedValue",
    0,
    function():Number { return multiplier * 10; }, // 计算函数
    null,
    null
);

trace(obj.calculatedValue); // 输出：30
multiplier = 5;
accessor.invalidate(); // 使缓存失效，重新计算
trace(obj.calculatedValue); // 输出：50
```

### 示例 4：带验证与回调的属性

```actionscript
var obj:Object = {};
var updateFlag:Boolean = false;

var accessor:PropertyAccessor = new PropertyAccessor(
    obj,
    "score",
    70,
    null,
    function():Void { updateFlag = true; }, // 回调函数
    function(value:Number):Boolean { return value >= 0 && value <= 100; } // 验证函数
);

trace(obj.score); // 输出：70
obj.score = 85; // 合法设置，触发回调
trace(obj.score); // 输出：85
trace(updateFlag); // 输出：true

obj.score = 150; // 无效设置
trace(obj.score); // 输出：85
```

---

## 性能优化

`PropertyAccessor` 通过多种技术手段提升属性管理的性能，主要包括惰性加载、缓存机制和动态方法替换。

### 惰性加载的性能优势

- **延迟计算**：属性值仅在实际需要时才计算，避免不必要的计算开销。
- **动态替换**：首次调用后替换 `get` 方法，减少后续调用中的判断逻辑，提高执行效率。

### 缓存机制的性能提升

- **避免重复计算**：计算属性值后缓存结果，避免在多次访问时重复执行计算函数。
- **快速访问**：缓存有效时，直接返回缓存值，极大提升访问速度。

### 动态方法替换的效率

- **减少分支判断**：在构造函数中根据属性类型替换方法，运行时调用时无需进行条件判断，提升方法执行速度。
- **优化代码路径**：根据不同场景，定义最优的 `get`、`set` 和 `invalidate` 方法实现，确保高效运行。

### 性能测试结果

以下为在不同场景下进行的性能测试结果，测试环境为基于 Flash 的 ActionScript 2 环境。

```actionscript
// 性能测试代码片段
var obj:Object = {};
var iterations:Number = 100000;
var accessor:PropertyAccessor = new PropertyAccessor(
    obj,
    "performanceProp",
    0,
    null,
    null,
    null
);

var startTime:Number = getTimer();

// 混合读写性能测试
for (var i:Number = 0; i < iterations; i++) {
    obj.performanceProp = i;
    var val:Number = obj.performanceProp;
}

var endTime:Number = getTimer();
trace("混合读写性能测试耗时：" + (endTime - startTime) + " ms");

// 纯读性能测试
accessor.invalidate(); // 确保缓存失效
var readStartTime:Number = getTimer();

for (var j:Number = 0; j < iterations; j++) {
    var readVal:Number = obj.performanceProp;
}

var readEndTime:Number = getTimer();
trace("纯读性能测试耗时：" + (readEndTime - readStartTime) + " ms");

// 纯写性能测试
var writeAccessor:PropertyAccessor = new PropertyAccessor(
    obj,
    "writePerformanceProp",
    0,
    null,
    null,
    null
);

var writeStartTime:Number = getTimer();

for (var k:Number = 0; k < iterations; k++) {
    obj.writePerformanceProp = k;
}

var writeEndTime:Number = getTimer();
trace("纯写性能测试耗时：" + (writeEndTime - writeStartTime) + " ms");
```

**测试结果示例**：

```
混合读写性能测试耗时：645 ms
纯读性能测试耗时：386 ms
纯写性能测试耗时：259 ms
```

**分析**：
- 混合读写操作较为耗时，因为涉及多次读写操作。
- 纯读操作由于缓存机制的优化，执行速度较快。
- 纯写操作由于直接赋值操作，执行速度最快。

---

## 最佳实践

### 选择合适的功能特性

在使用 `PropertyAccessor` 时，根据具体需求选择合适的功能特性：

- **简单属性**：无需计算、验证或回调，直接使用默认值即可。
- **只读属性**：提供 `computeFunc`，不需要 `set` 方法。
- **计算属性**：提供 `computeFunc`，并在需要时调用 `invalidate` 以更新缓存。
- **带验证和回调的属性**：结合使用 `validationFunc` 和 `onSetCallback`，确保属性值的合法性并处理依赖逻辑。

### 合理使用缓存与invalidate

- **缓存使用**：对于计算属性，依赖于不频繁变化的数据，可以通过缓存机制提升性能。
- **缓存失效**：当依赖数据发生变化时，调用 `invalidate` 方法确保属性值的实时性。
- **避免过度缓存**：在数据频繁变化的场景下，频繁调用 `invalidate` 可能导致性能下降，需权衡使用。

### 设计高效的验证与回调函数

- **验证函数**：
  - 简洁高效，避免复杂的逻辑以减少性能开销。
  - 返回布尔值，明确表示新值是否合法。
  
- **回调函数**：
  - 仅在必要时使用，避免在回调中执行耗时操作。
  - 确保回调逻辑不会导致属性的递归更新。

---

## 常见问题

### Q1：如何创建一个既可读又可写的属性？

**答**：在创建 `PropertyAccessor` 时，不提供 `computeFunc`，并根据需要选择是否提供 `validationFunc` 和 `onSetCallback`。例如：

```actionscript
var obj:Object = {};
var accessor:PropertyAccessor = new PropertyAccessor(
    obj,
    "name",
    "John Doe",
    null, // 无计算函数
    null, // 无回调函数
    null  // 无验证函数
);

trace(obj.name); // 输出：John Doe
obj.name = "Jane Smith";
trace(obj.name); // 输出：Jane Smith
```

### Q2：如何使属性只读？

**答**：提供 `computeFunc`，并不提供 `set` 方法（即传入 `null`）。例如：

```actionscript
var obj:Object = {};
var accessor:PropertyAccessor = new PropertyAccessor(
    obj,
    "readOnlyProp",
    0,
    function():Number { return 100; }, // 只读属性
    null,
    null
);

trace(obj.readOnlyProp); // 输出：100
obj.readOnlyProp = 200; // 无效设置
trace(obj.readOnlyProp); // 输出：100
```

### Q3：如何在属性值改变时更新其他依赖属性？

**答**：使用 `onSetCallback` 回调函数，在属性值设置后执行更新逻辑。例如：

```actionscript
var obj:Object = {};
var area:Number = 0;

var accessor:PropertyAccessor = new PropertyAccessor(
    obj,
    "width",
    10,
    null,
    function():Void { // 回调函数
        obj.area = obj.width * obj.height;
    },
    null
);

var accessorHeight:PropertyAccessor = new PropertyAccessor(
    obj,
    "height",
    5,
    null,
    function():Void { // 回调函数
        obj.area = obj.width * obj.height;
    },
    null
);

var accessorArea:PropertyAccessor = new PropertyAccessor(
    obj,
    "area",
    50,
    null,
    null,
    null
);

trace(obj.area); // 输出：50
obj.width = 20;
trace(obj.area); // 输出：100
obj.height = 10;
trace(obj.area); // 输出：200
```

### Q4：`invalidate` 方法的作用是什么？

**答**：`invalidate` 方法用于使计算属性的缓存失效，下次访问属性时会重新计算其值。适用于当依赖的数据发生变化时，确保属性值的实时性。

---

## 结语

`PropertyAccessor` 提供了一种高效、灵活的方式来管理对象属性。通过结合惰性加载、计算属性、验证机制和回调支持，开发者可以轻松实现复杂的属性管理逻辑，同时保持代码的简洁和高性能。无论是在简单的数据存储还是复杂的依赖关系处理中，`PropertyAccessor` 都能提供强大的支持，极大提升开发效率和应用性能。

---

## 附录

### 测试代码

```actionscript
import org.flashNight.gesh.property.*;
var test:PropertyAccessorTest = new PropertyAccessorTest();
test.runTests();

```