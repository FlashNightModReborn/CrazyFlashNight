# org.flashNight.neur.Event.Delegate 类使用指南

## 版本历史

### v3.1 (2026-03) - 缓存隔离 + create0 淘汰
- **[FIX]** 缓存键加入 arity 前缀（`"1:"`/`"2:"`/`"*:"`），防止不同 arity 的 wrapper 互相覆盖
  - v3.0 中同一 (scope, method) 对若先由特化版本缓存，后续 `create` 会返回错误 arity wrapper
  - 现在各 arity 版本使用独立缓存槽，同一 `__delegateCache` 对象中可安全共存
- **[DEL]** 删除 `create0`：零参场景 AVM1 已优化空 `arguments` 构建，`create0` 实测 0.95x 性能倒退
- **[FIX]** `BulletFactory.shouldDestroy` 绑定修正为 `create1`（调用方传入 `bullet` 参数）
- **[FIX]** `ObjectPool.as` 的 `Delegate.create(this, releaseObject, newObj)` 修正为 `createWithParams`（第 3 参数被静默忽略的 BUG）
- **[MIGRATE]** 热路径调用站点迁移：1参→`create1`，2参→`create2`，0参/可变→`create`

### v3.0 (2026-03) - 特化版本优化
- **[PERF]** 新增 `create1`/`create2` 特化方法，消除 wrapper 中 `arguments` 对象开销（~1538ns/次）
- **[PERF]** 删除冗余 `init()` 调用，静态初始化器已足够
- **[API]** `create()` 保持完全向后兼容，作为可变参数 fallback

### v2.1 (2026-01) - 三方交叉审查修复
- **[FIX]** `createWithParams` 的 `paramsUID` 添加长度前缀，修复缓存键碰撞风险
  - 之前 `["a|b"]` 和 `["a", "b"]` 都会生成 `"a|b"`，导致缓存碰撞
  - 现在分别生成 `"1:a|b"` 和 `"2:a|b"`，确保唯一性
- **[NOTE]** 简单类型参数使用 `String()` 转换是性能-稳定性的权宜之计（见性能说明）
- **[CLEAN]** 移除未使用的 import 语句

### v2.0 (2026-01) - 内存泄漏修复
- **[FIX]** 将缓存从静态全局迁移到 `scope` 对象自身 (`__delegateCache`)
- **[FIX]** 当 `scope` 被 GC 时，其缓存自然释放，彻底解决内存泄漏
- **[COMPAT]** `scope==null` 的情况仍使用全局缓存（无泄漏风险）
- **[PERF]** 保持 O(1) 缓存查找性能

### 性能说明
- `create1`/`create2`：零 `arguments` 开销，适用于调用时参数数量已知（1-2个）的场景（1.69x/1.83x 加速）
- `create`：通用版本，零参数时无额外开销（AVM1 优化空 arguments），可变参数场景的 fallback
- 缓存键的生成是性能-稳定性的权衡
- v2.1 通过添加长度前缀大幅降低了碰撞概率，但仍非完全零碰撞

---

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

### 4.0 选择指南（v3.1+）

| 你知道调用时的参数数量吗？ | 推荐方法 | 典型场景 |
|---------------------------|----------|----------|
| 固定 0 参 | `create` | 命令分发、定时回调、状态回调（AVM1 优化零参 arguments） |
| 固定 1 参 | `create1` | 子弹更新、网络回调、shouldDestroy |
| 固定 2 参 | `create2` | 双参数事件、坐标回调 |
| 不确定 / 可变 | `create` | EventBus 订阅、通用事件监听 |
| 需要预绑定参数 | `createWithParams` | 参数在创建时已知且固定 |

### 4.1 `create1(scope:Object, method:Function):Function` (v3.0+)

创建一个单参数委托函数。wrapper 通过显式形参接收参数，不创建 `arguments` 对象。

**示例**：
```as
// BulletFactory: 子弹更新回调接收单个参数
bulletInstance.updateMovement = Delegate.create1(movement, movement.updateMovement);
// 调用时: bulletInstance.updateMovement(deltaTime)
```

### 4.2 `create2(scope:Object, method:Function):Function` (v3.0+)

创建一个双参数委托函数。

**示例**：
```as
// 双参数回调
var onHit = Delegate.create2(this, this.handleHit);
onHit(target, damage); // 无 arguments 开销
```

### 4.3 `create(scope:Object, method:Function):Function`

创建一个通用委托函数，将指定的方法绑定到给定的作用域。支持 0-5+ 任意数量参数。

**注意**：v3.1 起，当调用时参数数量为 1-2 个时，优先使用 `create1`/`create2` 以消除 `arguments` 开销。零参数和可变参数场景直接使用 `create()`（零参时 AVM1 已优化，无额外开销）。

- `scope`：作为 `this` 绑定的对象。如果为 `null`，函数将在全局作用域执行。
- `method`：需要在该作用域内执行的函数，必须为有效的函数引用，不能为 `null` 或 `undefined`。

**示例**：
```as
var delegate = org.flashNight.neur.Event.Delegate.create(testInstance, testInstance.sayHello);
trace(delegate("Hello")); // 输出: Hello, my name is Alice
```

### 4.5 `createWithParams(scope:Object, method:Function, params:Array):Function`

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

### 4.6 `clearCache():Void`

清理缓存中的所有委托函数。建议在大型应用程序或长时间运行的程序中定期调用此方法，以防止内存泄漏。

**示例**：
```as
org.flashNight.neur.Event.Delegate.clearCache();
```

## 5. 性能优化重点

### 5.1 arguments 开销消除（v3.0 核心优化）

AVM1 基准测试数据表明，`arguments` 对象的创建成本约为 **~1538ns/次**，是 AVM1 中最昂贵的操作之一。

**问题**：v2.x 的 `create()` 返回的 wrapper 函数内部必须访问 `arguments` 对象来分发参数，即使调用时参数数量固定（如零参数），也要付出 ~1538ns 的代价。

**解决方案**：v3.0 的 `create1`/`create2` 特化版本的 wrapper 使用显式形参，完全不访问 `arguments`：

```as
// create1 的 wrapper（单参数，通过形参 a 接收，无 arguments）
var f = function(a) { return method.call(scope, a); };

// create2 的 wrapper（双参数，通过形参 a,b 接收，无 arguments）
var f = function(a, b) { return method.call(scope, a, b); };

// 对比 create() 的 wrapper（有参数时必须创建 arguments 对象）
var f = function() {
    var len = arguments.length;  // 有参数时 ~1538ns 开销
    if (len == 0) return method.call(scope);  // 零参时 AVM1 已优化，无额外开销
    else if (len == 1) return method.call(scope, arguments[0]);
    // ...
};
```

**关键发现（v3.1）**：零参数调用时 AVM1 会优化空 `arguments` 的构建，`create0` 实测反而有 0.95x 性能倒退（额外的 `method.call(scope)` 闭包层反而比 `create()` 内联分发更慢），因此已删除。仅 1 参（1.69x）和 2 参（1.83x）有实际收益。

### 5.2 动态参数传递的预处理与优化

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

### 5.3 预绑定参数的优势

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

### 5.4 缓存机制的高效利用

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
2. **性能敏感场景**（v3.1 更新）：当调用时参数数量为 1-2 个时，优先使用 `create1`/`create2` 以消除 `arguments` 对象开销（1.69x/1.83x 加速）。零参数和可变参数场景使用 `create`（零参时 AVM1 已优化，无额外开销）。参数在创建时就已固定的场景使用 `createWithParams`。
3. **作用域管理**：确保传递正确的 `scope` 参数，以保证回调函数内部 `this` 指向预期对象。`scope` 为 `null` 时，函数将在全局作用域执行。
4. **内存管理**：
   - v2.0 起，缓存存储在 `scope` 对象的 `__delegateCache` 属性中，当 `scope` 被 GC 回收时缓存自动释放
   - `scope == null` 的情况使用全局缓存，可通过 `clearCache()` 手动清理
   - 单个 `scope` 的缓存可通过 `clearScopeCache(scope)` 清理

## 8. 运行时保证清单

| 保证项 | 说明 |
|--------|------|
| 缓存命中 O(1) | 相同 (scope, method, params) 组合返回同一委托 |
| 缓存自动释放 | scope 被 GC 时其缓存自动释放（v2.0+） |
| 参数隔离 | 不同 params 组合产生不同委托 |
| UID 非枚举 | `__dictUID` 不会出现在 `for..in` 循环中 |
| 缓存隔离 | `create1`/`create2`/`create` 各自独立缓存槽，arity 前缀防止覆盖（v3.1+） |
| 零 arguments 开销 | `create1`/`create2` 的 wrapper 不创建 `arguments` 对象（v3.0+） |
| 零参无损 | `create()` 零参数调用时 AVM1 优化空 `arguments`，无额外开销（v3.1 验证） |

| 不保证项 | 说明 |
|----------|------|
| 完全零碰撞 | `createWithParams` 的缓存键存在极低概率碰撞（当字符串参数包含 `\|` 时） |
| 复杂对象参数 | 复杂嵌套对象作为 params 可能导致缓存策略失效 |
| 特化版本参数校验 | `create1`/`create2` 不检查 `method == null`，由调用方保证 |

---

## 9. 测试验证

运行 `DelegateTest` 类验证所有功能：

```actionscript
var delegateTest:org.flashNight.neur.Event.DelegateTest = new org.flashNight.neur.Event.DelegateTest();
delegateTest.runAllTests();
```

测试覆盖：作用域绑定、参数预绑定、缓存机制、边界值、v2.0 回归测试等 46 项测试用例。


```output

========================================
Delegate 测试套件 v3.0
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

--- [v3.1] 特化版本测试 ---
运行模块：[v3.0] create1 单参数特化测试
  [PASS] [v3.0] create1 scope绑定单参调用
  [PASS] [v3.0] create1 全局作用域单参调用
  [PASS] [v3.0] create1 缓存命中返回同一委托
  [PASS] [v3.0] create1 传null参数
  [PASS] [v3.0] create1 传undefined参数
运行模块：[v3.0] create2 双参数特化测试
  [PASS] [v3.0] create2 scope绑定双参调用
  [PASS] [v3.0] create2 全局作用域双参调用
  [PASS] [v3.0] create2 缓存命中返回同一委托
运行模块：[v3.1] 特化版本缓存隔离测试
  [PASS] [v3.1] create1与create2缓存隔离
  [PASS] [v3.1] create1与create缓存隔离
  [PASS] [v3.1] create2与create缓存隔离
  [PASS] [v3.1] create1自身缓存命中
  [PASS] [v3.1] create2自身缓存命中
  [PASS] [v3.1] create自身缓存命中
  [PASS] [v3.1] create1调用正确
  [PASS] [v3.1] create2调用正确
  [PASS] [v3.1] create通用版调用正确
  [PASS] [v3.1] clearScopeCache后create1重建委托

--- 性能测试 ---
运行模块：性能测试
  [PERF] create() 缓存命中: 56ms / 10000 ops (178571 ops/sec)
  [PERF] create() 缓存未命中: 222ms / 10000 ops (45045 ops/sec)
  [PERF] 委托调用: 202ms / 100000 ops (495050 ops/sec)
  [PERF] createWithParams 缓存命中: 61ms / 10000 ops (163934 ops/sec)
  [PERF] create1() 单参调用: 140ms / 100000 ops (714286 ops/sec)
  [PERF] create()  单参调用: 235ms / 100000 ops (425532 ops/sec)
  [PERF] create1 加速比: 1.68x
  [PERF] create2() 双参调用: 143ms / 100000 ops (699301 ops/sec)
  [PERF] create()  双参调用: 256ms / 100000 ops (390625 ops/sec)
  [PERF] create2 加速比: 1.79x

========================================
测试结果汇总
========================================
总测试用例数: 64
通过: 64 (100%)
失败: 0 (0%)

✓ 所有测试用例均通过！
========================================




```