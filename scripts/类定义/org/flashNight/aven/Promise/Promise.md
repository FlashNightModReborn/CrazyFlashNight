# ActionScript 2 Promise 类

`org.flashNight.aven.Promise.Promise` 是一个在 ActionScript 2 (AS2) 中实现的 `Promise` 类，用于管理异步操作，灵感来源于现代 JavaScript 的 `Promise`。该类支持链式调用、错误处理和嵌套 `Promise` 解析，使得在 AS2 环境下也能以更优雅的方式处理异步任务。

## 为什么需要 Promise

### 回调地狱问题

在 AS2 中，传统的异步操作通常通过回调函数来实现。当需要处理多个异步任务，且这些任务之间存在依赖关系时，代码会逐渐变得复杂，形成“回调地狱”（Callback Hell）或“金字塔代码”。

**示例：**

```actionscript
function task1(callback:Function):Void {
    // 异步操作...
    callback(result1);
}

function task2(result1:Object, callback:Function):Void {
    // 使用 result1 进行操作...
    callback(result2);
}

function task3(result2:Object, callback:Function):Void {
    // 使用 result2 进行操作...
    callback(result3);
}

// 调用方式
task1(function(result1:Object):Void {
    task2(result1, function(result2:Object):Void {
        task3(result2, function(result3:Object):Void {
            // 继续嵌套...
        });
    });
});
```

随着嵌套层级的增加，代码变得难以维护和阅读。回调地狱的问题主要体现在：

- **代码可读性差**：深层的嵌套使得代码结构混乱，难以追踪逻辑流程。
- **错误处理复杂**：每个回调都需要单独处理错误，增加了代码的复杂性。
- **难以调试**：嵌套的回调函数使得调试过程变得困难。

### Promise 的解决方案

`Promise` 提供了一种更清晰的方式来管理异步操作，避免了深层嵌套。通过链式调用，可以将异步任务按顺序排列，代码更加直观。

**使用 Promise 后的改写：**

```actionscript
var promise = new Promise(function(resolve:Function, reject:Function):Void {
    // 异步操作...
    resolve(result1);
});

promise.then(function(result1:Object):Promise {
    // 使用 result1 进行操作...
    return new Promise(function(resolve:Function, reject:Function):Void {
        // 异步操作...
        resolve(result2);
    });
}).then(function(result2:Object):Promise {
    // 使用 result2 进行操作...
    return new Promise(function(resolve:Function, reject:Function):Void {
        // 异步操作...
        resolve(result3);
    });
}).then(function(result3:Object):Void {
    // 处理最终结果
});
```

通过 `then()` 方法的链式调用，异步任务按顺序执行，代码结构更加扁平化，解决了回调地狱的问题。优势包括：

- **代码可读性提高**：链式结构使得逻辑流程清晰明了。
- **统一的错误处理**：可以在链的末尾添加错误处理，简化了错误管理。
- **易于维护和扩展**：添加或修改异步步骤更加方便。

## 功能概述

`Promise` 类提供了以下主要功能：

1. **异步操作的封装**：将异步任务封装成 `Promise` 实例，使用 `resolve` 表示成功，`reject` 表示失败。
2. **链式调用**：通过 `.then()` 方法，支持多个回调函数按顺序执行，处理异步任务的串行化。
3. **错误处理**：使用 `.onCatch()` 方法来处理异步操作中的错误，避免了在每个回调中处理错误的麻烦。
4. **嵌套 `Promise` 支持**：在 `.then()` 中返回另一个 `Promise`，可以处理更复杂的异步逻辑。
5. **静态方法**：
   - `Promise.resolve(value)`：返回一个立即成功的 `Promise`。
   - `Promise.reject(reason)`：返回一个立即失败的 `Promise`。
   - `Promise.all(promises)`：并行执行多个 `Promise`，等待所有 `Promise` 完成。
   - `Promise.race(promises)`：并行执行多个 `Promise`，返回最先完成的 `Promise` 的结果。
   - `Promise.allSettled(promises)`：并行执行多个 `Promise`，等待所有 `Promise` 完成，无论成功或失败。

## 安装和使用

将 `Promise` 类文件放入项目的 `org/flashNight/aven/Promise/` 目录中，并在需要使用的文件中导入该类：

```actionscript
import org.flashNight.aven.Promise.Promise;
```

## 基础用法示例

### 1. 创建一个 Promise

使用 `Promise` 来封装异步操作，例如网络请求或定时任务。`Promise` 的构造函数接受一个 `executor` 函数，包含 `resolve` 和 `reject` 两个参数，用于标记异步操作的成功或失败。

```actionscript
var asyncTask:Promise = new Promise(function(resolve:Function, reject:Function):Void {
    // 模拟异步操作
    var timerID:Number = setInterval(function():Void {
        clearInterval(timerID);
        resolve("操作成功"); // 成功后调用 resolve
    }, 1000);
});

asyncTask.then(function(value:Object):Void {
    trace("结果: " + value); // 输出 "结果: 操作成功"
}).onCatch(function(reason:Object):Void {
    trace("失败原因: " + reason);
});
```

### 2. 链式调用

通过 `then()` 方法，可以将多个异步操作按顺序串联起来，避免嵌套回调。

```actionscript
var promiseChain:Promise = new Promise(function(resolve:Function, reject:Function):Void {
    resolve(1);
});

promiseChain.then(function(value:Object):Object {
    trace("第一个 then: " + value); // 输出 1
    return value + 1; // 返回的值传递到下一个 then
}).then(function(value:Object):Object {
    trace("第二个 then: " + value); // 输出 2
    return value + 1;
}).then(function(value:Object):Void {
    trace("第三个 then: " + value); // 输出 3
});
```

### 3. 错误处理

使用 `onCatch()` 方法可以统一处理链式调用中发生的错误，避免在每个 `then()` 中编写错误处理逻辑。

```actionscript
var errorPromise:Promise = new Promise(function(resolve:Function, reject:Function):Void {
    // 模拟异步操作抛出异常
    throw new Error("发生异常");
});

errorPromise.then(function(value:Object):Void {
    trace("成功结果: " + value);
}).onCatch(function(reason:Object):Void {
    trace("异常被捕获: " + reason.message); // 输出 "异常被捕获: 发生异常"
});
```

### 4. 嵌套 Promise

在 `then()` 中返回另一个 `Promise`，可以处理更复杂的异步流程，外层 `Promise` 会等待内层 `Promise` 完成后再继续执行。

```actionscript
var nestedPromise:Promise = new Promise(function(resolve:Function, reject:Function):Void {
    resolve("初始结果");
});

nestedPromise.then(function(value:Object):Promise {
    trace("初始 then: " + value); // 输出 "初始 then: 初始结果"
    return new Promise(function(innerResolve:Function, innerReject:Function):Void {
        // 模拟异步操作
        var timerID:Number = setInterval(function():Void {
            clearInterval(timerID);
            innerResolve("嵌套 Promise 完成");
        }, 1000);
    });
}).then(function(value:Object):Void {
    trace("嵌套 then: " + value); // 输出 "嵌套 then: 嵌套 Promise 完成"
});
```

## Promise 静态方法

### Promise.resolve(value)

创建一个立即成功的 `Promise`，常用于将现有的值转换为 `Promise` 对象。

```actionscript
var resolvedPromise:Promise = Promise.resolve("立即成功");
resolvedPromise.then(function(value:Object):Void {
    trace("Promise.resolve 结果: " + value); // 输出 "Promise.resolve 结果: 立即成功"
});
```

### Promise.reject(reason)

创建一个立即失败的 `Promise`，常用于将错误信息包装成 `Promise` 对象。

```actionscript
var rejectedPromise:Promise = Promise.reject("立即失败");
rejectedPromise.onCatch(function(reason:Object):Void {
    trace("Promise.reject 错误: " + reason); // 输出 "Promise.reject 错误: 立即失败"
});
```

### Promise.all(promises)

并行执行多个 `Promise`，等待所有 `Promise` 完成后，返回一个新的 `Promise`，其值是所有 `Promise` 结果的数组。如果有任意一个 `Promise` 失败，则返回第一个失败的原因。

```actionscript
var promise1:Promise = new Promise(function(resolve:Function, reject:Function):Void {
    // 模拟异步操作
    var timerID:Number = setInterval(function():Void {
        clearInterval(timerID);
        resolve("结果 1");
    }, 1000);
});

var promise2:Promise = Promise.resolve("结果 2");

Promise.all([promise1, promise2]).then(function(values:Array):Void {
    trace("Promise.all 结果: " + values.join(", ")); // 输出 "Promise.all 结果: 结果 1, 结果 2"
}).onCatch(function(reason:Object):Void {
    trace("Promise.all 失败原因: " + reason);
});
```

### Promise.race(promises)

并行执行多个 `Promise`，返回第一个完成（成功或失败）的 `Promise` 的结果。

```actionscript
var slowPromise:Promise = new Promise(function(resolve:Function, reject:Function):Void {
    var timerID:Number = setInterval(function():Void {
        clearInterval(timerID);
        resolve("慢速完成");
    }, 2000);
});

var fastPromise:Promise = new Promise(function(resolve:Function, reject:Function):Void {
    var timerID:Number = setInterval(function():Void {
        clearInterval(timerID);
        resolve("快速完成");
    }, 1000);
});

Promise.race([slowPromise, fastPromise]).then(function(value:Object):Void {
    trace("Promise.race 结果: " + value); // 输出 "Promise.race 结果: 快速完成"
}).onCatch(function(reason:Object):Void {
    trace("Promise.race 错误: " + reason);
});
```

### Promise.allSettled(promises)

并行执行多个 `Promise`，等待所有 `Promise` 完成后，返回一个新的 `Promise`，其值是每个 `Promise` 的状态和结果。

```actionscript
var p1:Promise = Promise.resolve("成功结果");
var p2:Promise = Promise.reject("失败原因");

Promise.allSettled([p1, p2]).then(function(results:Array):Void {
    for (var i:Number = 0; i < results.length; i++) {
        var result:Object = results[i];
        trace("Promise " + i + " 状态: " + result.status);
        if (result.status == "fulfilled") {
            trace("值: " + result.value);
        } else {
            trace("原因: " + result.reason);
        }
    }
    // 输出：
    // Promise 0 状态: fulfilled
    // 值: 成功结果
    // Promise 1 状态: rejected
    // 原因: 失败原因
});
```

## 回调地狱的解决

### 什么是回调地狱

回调地狱指的是在处理多个嵌套的异步操作时，代码结构呈现出多层嵌套的形态，像一个金字塔。这种代码难以阅读和维护，错误处理也变得复杂。

**示例：**

```actionscript
function loadData(callback:Function):Void {
    // 模拟异步数据加载
    setTimeout(function():Void {
        callback(null, data);
    }, 1000);
}

loadData(function(error:Object, data:Object):Void {
    if (error) {
        // 处理错误
    } else {
        processData(data, function(error:Object, result:Object):Void {
            if (error) {
                // 处理错误
            } else {
                saveData(result, function(error:Object):Void {
                    if (error) {
                        // 处理错误
                    } else {
                        // 完成
                    }
                });
            }
        });
    }
});
```

### Promise 如何解决回调地狱

使用 `Promise`，可以将上述嵌套的回调展开为链式调用，使代码更加清晰。

```actionscript
function loadDataPromise():Promise {
    return new Promise(function(resolve:Function, reject:Function):Void {
        // 模拟异步数据加载
        setTimeout(function():Void {
            resolve(data);
        }, 1000);
    });
}

function processDataPromise(data:Object):Promise {
    return new Promise(function(resolve:Function, reject:Function):Void {
        // 处理数据
        resolve(result);
    });
}

function saveDataPromise(result:Object):Promise {
    return new Promise(function(resolve:Function, reject:Function):Void {
        // 保存数据
        resolve();
    });
}

loadDataPromise()
    .then(function(data:Object):Promise {
        return processDataPromise(data);
    })
    .then(function(result:Object):Promise {
        return saveDataPromise(result);
    })
    .then(function():Void {
        trace("所有操作完成");
    })
    .onCatch(function(error:Object):Void {
        trace("发生错误: " + error);
    });
```

通过这种方式，异步操作被线性化，错误处理也统一在 `onCatch()` 中进行。这样不仅提高了代码的可读性，还使得异步流程更容易维护和扩展。

## 注意事项

- **异步模拟**：在 AS2 中，没有原生的异步机制，通常使用 `setInterval` 或 `setTimeout` 来模拟异步操作。
- **错误处理**：建议在链式调用的末尾添加 `onCatch()`，统一处理可能发生的错误。
- **性能考虑**：由于 AS2 的运行环境限制，过多的链式调用可能会影响性能，建议合理设计异步流程。
- **回调与 Promise 的兼容**：在过渡阶段，可能需要将传统回调函数封装为 `Promise`，以便与新的异步流程兼容。

## 常见问题解答 (FAQ)

### 1. 我可以在 `then()` 中返回一个值，而不是 `Promise` 吗？

可以的。如果在 `then()` 中返回一个非 `Promise` 的值，该值会被自动封装成一个立即成功的 `Promise`，传递给下一个 `then()`。

### 2. 如何在 `Promise.all()` 中处理失败的 `Promise`？

`Promise.all()` 会在任意一个 `Promise` 失败时立即拒绝。要处理所有 `Promise` 的结果（无论成功或失败），可以使用 `Promise.allSettled()`。

### 3. `Promise.race()` 会等待所有 `Promise` 完成吗？

不会。`Promise.race()` 只会返回第一个完成的 `Promise` 的结果，其他未完成的 `Promise` 将继续执行，但不会影响 `Promise.race()` 的结果。

### 4. 为什么我的 `Promise` 没有按预期执行？

可能的原因有：

- `Promise` 内部的异步操作未正确调用 `resolve` 或 `reject`。
- `then()` 或 `onCatch()` 中的回调函数未正确返回值。
- AS2 环境中的异步模拟方式需要正确使用 `setInterval` 或 `setTimeout`。

### 5. 如何将现有的回调函数转换为 `Promise`？

可以手动封装回调函数，将其转换为返回 `Promise` 的函数。例如：

```actionscript
function oldAsyncFunction(callback:Function):Void {
    // 异步操作
    callback(error, result);
}

function newAsyncFunction():Promise {
    return new Promise(function(resolve:Function, reject:Function):Void {
        oldAsyncFunction(function(error:Object, result:Object):Void {
            if (error) {
                reject(error);
            } else {
                resolve(result);
            }
        });
    });
}
```

## 结语

通过 `Promise` 类，开发者可以在 AS2 中更有效地管理异步操作，改善代码结构，提高可读性。`Promise` 不仅解决了回调地狱的问题，还为异步编程提供了统一的接口和模式。

如果您之前未接触过 `Promise`，建议从简单的示例开始，逐步理解其工作原理和优势。











import org.flashNight.aven.Promise.*;


TestPromise.main();




First then: 1
Second then: 2
Third then: 3
Exception caught: An exception occurred
First then (multiple then test): Resolved once
Second then (multiple then test): Resolved once
Nested promise test: [Promise state: fulfilled, value: Nested promise resolved]
Null value test: null
Undefined value test: undefined
Mixed promise first then: 5
Multiple resolve/reject test: First resolve
Error in multiple resolve/reject test: TypeError: Chaining cycle detected for promise
Promise with promise as value: [Promise state: fulfilled, value: Inner promise resolved]
Promise.resolve test: Immediate value
Promise.reject test: Immediate error
Promise.all empty array test: 
Promise.all empty array failure (should not be called)
Promise.allSettled empty array test: 


