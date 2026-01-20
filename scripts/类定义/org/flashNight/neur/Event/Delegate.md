# org.flashNight.neur.Event.Delegate 类使用指南

## 1. 介绍

`org.flashNight.neur.Event.Delegate` 类是一种高效的动态参数传递和回调管理工具，针对需要频繁传递动态参数的场景进行了优化，特别适用于事件驱动和高频回调机制。与 ActionScript 2 中 `mx` 包提供的 Delegate 实现相比，`org.flashNight.neur.Event.Delegate` 提供了更丰富的功能和性能增强，特别是在**参数预处理**和**缓存机制**方面，显著提升了动态参数传递的效率，能够更好地适应复杂业务场景。

## 2. 功能对比（与 `mx.Delegate` 实现）

- **缓存机制**：本实现提供了更复杂的缓存机制，允许基于作用域、方法以及动态参数的组合缓存委托函数。相比 `mx.Delegate` 的简单函数绑定，本实现大幅减少了重复创建委托函数的开销。
- **动态参数支持**：`org.flashNight.neur.Event.Delegate` 支持对超过 5 个参数的动态处理，并针对不同的参数数量进行了优化选择，避免了每次都使用 `apply`，在参数少于 5 个的情况下直接进行快速调用，而 `mx.Delegate` 对动态参数支持较弱。
- **作用域绑定增强**：相比 `mx.Delegate`，该实现可以处理更加复杂的作用域绑定情况，不仅支持常规的对象方法绑定，还支持自定义作用域回调的高级操作。
- **性能优化**：`org.flashNight.neur.Event.Delegate` 针对回调频繁的业务场景进行了细致优化，减少了不必要的函数创建和 `apply` 调用，尤其适合需要高效处理动态参数传递和频繁回调的应用场景。

## 3. 功能概述

- **委托创建与缓存**：为每个函数和作用域分配唯一标识符，将生成的委托函数缓存，避免重复创建相同的函数，减少内存占用。
- **动态参数预处理**：委托函数支持动态传参，并通过预处理与缓存机制优化 `apply` 调用，特别适合频繁调用的场景。
- **作用域绑定**：允许为任意函数指定作用域，使函数在调用时能正确引用 `this`，确保上下文不丢失。
- **复杂参数处理**：支持超过5个参数的函数调用，并且为简单参数情况提供优化的调用方式。
- **性能优化**：针对参数数量的不同，选择最优的函数调用方式，减少运行时判断和开销。

## 4. 使用方法

### 4.1 `create(scope:Object, method:Function):Function`

创建一个委托函数，将指定的方法绑定到给定的作用域。通过缓存机制优化委托函数的创建和复用，提升性能。

- `scope`：作为 `this` 绑定的对象。如果为 `null`，函数将在全局作用域执行。
- `method`：需要在该作用域内执行的函数，必须为有效的函数引用，不能为 `null` 或 `undefined`。

**示例**：
```as
var delegate = org.flashNight.neur.Event.Delegate.create(testInstance, testInstance.sayHello);
trace(delegate("Hello")); // 输出: Hello, my name is Alice
```

### 4.2 `createWithParams(scope:Object, method:Function, params:Array):Function`

创建一个带有预定义参数的委托函数，将函数和预定义的参数绑定到指定的作用域。该方法通过将参数封装在闭包中，避免了每次调用时使用 `apply`，从而优化了动态传参场景下的性能。

- `scope`：作为 `this` 绑定的对象。
- `method`：需要在该作用域内执行的函数。
- `params`：预定义的参数数组。

**注意**：`createWithParams` 适合处理相对简单的参数传递情况。如果传递的 `params` 包含复杂对象或嵌套结构，由于 `toString` 方法生成的 UID 可能无法保证唯一性，建议回退到 `create` 方法进行基础处理，以避免缓存策略失败。

**示例**：
```as
var preBoundDelegate = org.flashNight.neur.Event.Delegate.createWithParams(null, preBoundTest, ["foo", "bar"]);
trace(preBoundDelegate()); // 输出: Pre-bound args: foo and bar
```

### 4.3 `clearCache():Void`

清理缓存中的所有委托函数。建议在大型应用程序或长时间运行的程序中定期调用此方法，以防止内存泄漏。

**示例**：
```as
org.flashNight.neur.Event.Delegate.clearCache();
```

## 5. 性能优化重点

### 5.1 动态参数传递的预处理与优化

**`Delegate` 类的核心优势在于其动态参数的预处理能力**，通过 `createWithParams` 方法，预先将动态参数绑定至委托函数，避免了每次调用时重新解析参数和调用 `apply`。相比于传统的基于 `apply` 的动态参数传递，这种方法大大减少了性能开销。

- **预处理机制**：在创建委托函数时即完成参数绑定，使用直接调用 (`call`) 取代 `apply`，确保性能最优。
- **缓存机制**：通过缓存相同作用域和函数的委托，避免每次创建委托函数时重复解析参数。

**示例**：
```as
function dynamicArgumentTest() {
    return Array.prototype.join.call(arguments, ", ");
}

var dynamicDelegate = org.flashNight.neur.Event.Delegate.create(null, dynamicArgumentTest);
trace(dynamicDelegate(1, "a", true, null)); // 输出: 1, a, true, null
```

### 5.2 预绑定参数的优势

使用 `createWithParams` 方法时，参数会在创建时被绑定到委托函数中，避免了每次任务执行时进行参数解析的过程。特别是在高频任务调用中，提前绑定参数的方式能有效降低函数调用的成本。

**示例**：
```as
function preBoundTest(arg1, arg2) {
    return "Pre-bound args: " + arg1 + " and " + arg2;
}

var preBoundDelegate = org.flashNight.neur.Event.Delegate.createWithParams(null, preBoundTest, ["foo", "bar"]);
trace(preBoundDelegate()); // 输出: Pre-bound args: foo and bar
```

相比动态传参在每次执行时都需要 `apply` 进行处理，预绑定参数的方式更加高效，避免了不必要的参数解析和性能损耗。

### 5.3 缓存机制的高效利用

`Delegate` 类通过缓存相同作用域和函数组合生成的委托函数，避免了每次调用时重复创建新函数。在频繁调用相同任务的场景下，缓存机制可以大幅减少内存占用和函数创建的开销。

**示例**：
```as
var delegateA1 = org.flashNight.neur.Event.Delegate.create(null, globalTestFunction);
var delegateA2 = org.flashNight.neur.Event.Delegate.create(null, globalTestFunction);
trace(delegateA1 === delegateA2); // 输出: true
```

## 6. 与 `mx.Delegate` 的对比优势

### 6.1 增强的回调支持

- **`mx.Delegate` 简单绑定与调用**：`mx.Delegate` 主要用于简单的作用域绑定和回调机制，但其支持的参数处理能力有限。
- **增强的动态参数支持**：`org.flashNight.neur.Event.Delegate` 在 `mx.Delegate` 的基础上增加了对动态参数、复杂回调场景的支持，特别是在处理大量参数传递时，性能提升显著。

### 6.2 更复杂的作用域处理

- **`mx.Delegate` 只能绑定单一作用域**：`mx.Delegate` 仅支持简单的作用域绑定，无法应对复杂的作用域传递场景。
- **多层次作用域支持**：`org.flashNight.neur.Event.Delegate` 可以处理复杂的多层次作用域绑定，更适合大型项目中的复杂业务需求。

### 6.3 缓存与性能优化

- **`mx.Delegate` 无缓存支持**：`mx.Delegate` 在每次绑定时都会重新创建函数对象，未提供任何缓存机制，导致在高频调用时性能下降。
- **缓存机制优化**：`org.flashNight.neur.Event.Delegate` 提供了完整的缓存机制，显著减少函数重复创建，提升性能，尤其适合需要频繁回调的场景。

## 7. 注意事项

1. **参数预处理与缓存**：当相同的作用域和方法组合多次被调用时，`Delegate` 类会自动复用缓存的委托函数，避免重复创建新函数。确保参数是稳定的，以充分利用缓存机制。
2. **性能敏感场景**：对于需要频繁传递动态参数的高性能场景，优先考虑使用 `create




// 使用 DelegateTest 类进行测试
var delegateTest:org.flashNight.neur.Event.DelegateTest = new org.flashNight.neur.Event.DelegateTest();
delegateTest.runAllTests();


========================================
Delegate 测试套件 v2.0
========================================

--- 功能测试 ---
运行模块：作用域绑定测试
  [PASS] 测试用例 1：全局作用域绑定无参数函数
  [PASS] 测试用例 2：指定作用域绑定带参数函数
  [PASS] 测试用例 3：改变作用域后执行相同方法
运行模块：带参数的委托函数绑定测试
  [PASS] 测试用例 17：createWithParams 绑定函数并预传参数
  [PASS] 测试用例 18：带作用域的 createWithParams 绑定函数并预传参数
  [PASS] 测试用例 19：createWithParams 绑定带作用域函数并预传超过5个参数
运行模块：缓存机制测试
  [PASS] 测试用例 20.1：相同函数相同作用域返回相同委托
  [PASS] 测试用例 20.2：相同方法相同作用域返回相同委托
  [PASS] 测试用例 20.3：相同参数 createWithParams 返回相同委托
  [PASS] 测试用例 20.4：不同函数对象应返回不同的委托
运行模块：错误处理测试
  [PASS] 测试用例 5：null method 抛出预期错误
运行模块：动态参数传递测试
  [PASS] 测试用例 4：超过5个参数的调用
  [PASS] 测试用例 6：动态参数传递
  [PASS] 测试用例 7：大量参数传递
运行模块：复杂场景测试
  [PASS] 测试用例 8：绑定到指定作用域的函数动态传参
  [PASS] 测试用例 9：空参数调用
  [PASS] 测试用例 10：传递 null 和 undefined 参数
  [PASS] 测试用例 11：嵌套函数作用域绑定
  [PASS] 测试用例 12：传递对象参数
  [PASS] 测试用例 13：多层作用域绑定传递带有函数参数的对象
  [PASS] 测试用例 14：传递嵌套数组作为参数
  [PASS] 测试用例 15：传递包含方法的对象
  [PASS] 测试用例 16：绑定作用域后传递多个复杂类型参数
运行模块：清理缓存测试
  [PASS] 测试用例 21.1：全局委托缓存命中
  已清理全局缓存 (clearCache)
  [PASS] 测试用例 21.2：clearCache后全局委托重新创建
  [PASS] 测试用例 21.3：clearCache后缓存机制恢复
  [PASS] 测试用例 21.4：scope委托缓存命中
  [PASS] 测试用例 21.5：clearCache不影响scope缓存
  已清理 scope 缓存 (clearScopeCache)
  [PASS] 测试用例 21.6：clearScopeCache后scope委托重新创建
运行模块：不同类型的作用域对象测试
  [PASS] 测试用例 22.1：数组作为作用域对象
  [PASS] 测试用例 22.2：函数作为作用域对象
运行模块：边界值参数测试
  [PASS] 测试用例 23.1：传递空字符串
  [PASS] 测试用例 23.2：传递数字0
  [PASS] 测试用例 23.3：传递布尔值 true
  [PASS] 测试用例 23.4：传递布尔值 false

--- [v2.0] 回归测试 ---
运行模块：[v2.0] scope 缓存隔离测试
  [PASS] [v2.0] scope1 delegate works
  [PASS] [v2.0] scope2 delegate works
  [PASS] [v2.0] scope1 should have __delegateCache
  [PASS] [v2.0] scope2 should have __delegateCache
  [PASS] [v2.0] each scope has its own cache
  [PASS] [v2.0] same scope+method returns cached delegate
  [PASS] [v2.0] __delegateCache should not be enumerable
运行模块：[v2.0] clearScopeCache 测试
  [PASS] [v2.0] cache exists after create
  [PASS] [v2.0] cache cleared after clearScopeCache
  [PASS] [v2.0] new delegate created after cache clear
  [PASS] [v2.0] new delegate works correctly

--- 性能测试 ---
运行模块：性能测试
  [PERF] create() 缓存命中: 97ms / 10000 ops (103093 ops/sec)
  [PERF] create() 缓存未命中: 251ms / 10000 ops (39841 ops/sec)
  [PERF] 委托调用: 260ms / 100000 ops (384615 ops/sec)
  [PERF] createWithParams 缓存命中: 110ms / 10000 ops (90909 ops/sec)

========================================
测试结果汇总
========================================
总测试用例数: 46
通过: 46 (100%)
失败: 0 (0%)

✓ 所有测试用例均通过！
========================================

