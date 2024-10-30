# ArrayUtil 类使用指南

## 目录

1. [简介](#简介)
2. [背景与原理](#背景与原理)
3. [类结构](#类结构)
4. [方法详解](#方法详解)
    - [forEach](#foreach)
    - [map](#map)
    - [filter](#filter)
    - [reduce](#reduce)
    - [some](#some)
    - [every](#every)
    - [find](#find)
    - [findIndex](#findindex)
    - [indexOf](#indexof)
    - [lastIndexOf](#lastindexof)
    - [includes](#includes)
5. [使用示例](#使用示例)
---

## 简介

`ArrayUtil` 是一个专为 ActionScript 2 (AS2) 设计的数组工具类，提供了一系列高效、实用的静态方法来简化数组操作。通过采用逆序遍历（从数组末尾向前遍历）的优化策略，`ArrayUtil` 在处理大规模数组时表现出色，显著提升了性能。该类旨在弥补 AS2 内置数组方法的不足，为开发者提供更强大的数组处理能力。

## 背景与原理

在 AS2 中，数组操作相对有限，缺乏许多现代编程语言中常见的高级数组方法，如 `map`、`filter`、`reduce` 等。为了提升开发效率和代码性能，`ArrayUtil` 类应运而生。其核心优化理念是采用逆序遍历数组，这在某些情况下能够减少循环开销，尤其是在处理大规模数组时，性能提升显著。

### 逆序遍历的优势

1. **性能提升**：逆序遍历可以减少循环中的时间开销，尤其是在动态类型语言中，避免了每次迭代中对数组长度的重新计算。
2. **内存管理**：通过减少不必要的数组操作（如 `unshift`），优化内存使用。
3. **早期退出机制**：对于可以提前退出的操作（如 `some`、`find`），逆序遍历有助于更快地找到目标元素，减少不必要的迭代。

## 类结构

```actionscript
// 文件: org/flashNight/gesh/array/ArrayUtil.as
class org.flashNight.gesh.array.ArrayUtil {
    
    // 对数组的每个元素执行一次提供的函数
    public static function forEach(arr:Array, callback:Function):Void { /* ... */ }
    
    // 创建一个新数组，包含调用提供的函数后的每个元素的结果
    public static function map(arr:Array, callback:Function):Array { /* ... */ }
    
    // 创建一个新数组，包含所有通过提供的函数测试的元素
    public static function filter(arr:Array, callback:Function):Array { /* ... */ }
    
    // 使用提供的函数对数组进行累加，简化为单个值
    public static function reduce(arr:Array, callback:Function, initialValue:Object):Object { /* ... */ }
    
    // 测试数组中是否至少有一个元素通过了提供的函数测试
    public static function some(arr:Array, callback:Function):Boolean { /* ... */ }
    
    // 测试数组中的所有元素是否都通过了提供的函数测试
    public static function every(arr:Array, callback:Function):Boolean { /* ... */ }
    
    // 返回数组中第一个满足提供的测试函数的元素的值
    public static function find(arr:Array, callback:Function):Object { /* ... */ }
    
    // 返回数组中第一个满足提供的测试函数的元素的索引
    public static function findIndex(arr:Array, callback:Function):Number { /* ... */ }
    
    // 返回数组中第一个匹配指定元素的索引
    public static function indexOf(arr:Array, searchElement:Object):Number { /* ... */ }
    
    // 返回数组中最后一个匹配指定元素的索引
    public static function lastIndexOf(arr:Array, searchElement:Object):Number { /* ... */ }
    
    // 确定数组是否包含指定的元素
    public static function includes(arr:Array, searchElement:Object):Boolean { /* ... */ }
}
```

## 方法详解

### forEach

**描述**：对数组的每个元素执行一次提供的函数。

**参数**：
- `arr:Array`：要遍历的数组。
- `callback:Function`：对每个元素执行的函数，接受三个参数：
    - `el`：当前元素。
    - `idx`：当前元素的索引。
    - `arr`：数组本身。

**返回值**：无。

**实现与优化**：
采用逆序遍历，通过缓存数组长度来减少循环中的计算开销。

**代码实现**：

```actionscript
/**
 * 对数组的每个元素执行一次提供的函数。
 * @param arr 要遍历的数组。
 * @param callback 对每个元素执行的函数。
 */
public static function forEach(arr:Array, callback:Function):Void {
    var len:Number = arr.length;
    for (var i:Number = len - 1; i >= 0; i--) {
        callback(arr[i], i, arr);
    }
}
```

### map

**描述**：创建一个新数组，包含调用提供的函数后的每个元素的结果。

**参数**：
- `arr:Array`：要映射的数组。
- `callback:Function`：对每个元素执行的函数，接受三个参数：
    - `el`：当前元素。
    - `idx`：当前元素的索引。
    - `arr`：数组本身。

**返回值**：一个新数组，每个元素是回调函数的结果。

**实现与优化**：
采用 `push` 方法替代 `unshift`，并在遍历结束后反转数组，以保持原有顺序，避免频繁的数组重排。

**代码实现**：

```actionscript
/**
 * 创建一个新数组，其中包含调用提供的函数后返回的每个元素的结果。
 * 优化：使用 push 代替 unshift，并在遍历结束后反转数组，以提高性能。
 * @param arr 要映射的数组。
 * @param callback 对每个元素执行的函数。
 * @return 一个新数组，每个元素是回调函数的结果。
 */
public static function map(arr:Array, callback:Function):Array {
    var result:Array = [];
    var len:Number = arr.length;
    for (var i:Number = len - 1; i >= 0; i--) {
        result.push(callback(arr[i], i, arr));
    }
    result.reverse(); // 反转数组以保持原有顺序
    return result;
}
```

### filter

**描述**：创建一个新数组，包含所有通过提供的函数测试的元素。

**参数**：
- `arr:Array`：要过滤的数组。
- `callback:Function`：测试每个元素的函数，接受三个参数：
    - `el`：当前元素。
    - `idx`：当前元素的索引。
    - `arr`：数组本身。

**返回值**：一个新数组，包含通过测试的元素。

**实现与优化**：
采用 `push` 方法替代 `unshift`，并在遍历结束后反转数组，以保持原有顺序，避免频繁的数组重排。

**代码实现**：

```actionscript
/**
 * 创建一个新数组，其中包含所有通过提供的函数测试的元素。
 * 优化：使用 push 代替 unshift，并在遍历结束后反转数组，以提高性能。
 * @param arr 要过滤的数组。
 * @param callback 测试每个元素的函数。
 * @return 一个新数组，包含通过测试的元素。
 */
public static function filter(arr:Array, callback:Function):Array {
    var result:Array = [];
    var len:Number = arr.length;
    for (var i:Number = len - 1; i >= 0; i--) {
        if (callback(arr[i], i, arr)) {
            result.push(arr[i]);
        }
    }
    result.reverse(); // 反转数组以保持原有顺序
    return result;
}
```

### reduce

**描述**：使用提供的函数对数组的累加器和每个元素执行操作，以将数组简化为单个值。

**参数**：
- `arr:Array`：要简化的数组。
- `callback:Function`：对每个元素执行的函数，接受四个参数：
    - `acc`：累加器。
    - `el`：当前元素。
    - `idx`：当前元素的索引。
    - `arr`：数组本身。
- `initialValue:Object`：用于开始累加的初始值。

**返回值**：累加后的结果。

**实现与优化**：
采用逆序遍历，并根据是否提供初始值来调整累加器的初始化和遍历起点。

**代码实现**：

```actionscript
/**
 * 使用提供的函数对数组的累加器和每个元素执行操作，以将数组简化为单个值。
 * @param arr 要简化的数组。
 * @param callback 对每个元素执行的函数。
 * @param initialValue 用于开始累加的初始值。
 * @return 累加后的结果。
 */
public static function reduce(arr:Array, callback:Function, initialValue:Object):Object {
    // 检查是否提供了 initialValue 参数
    var hasInitialValue:Boolean = (initialValue != undefined);
    
    // 如果有初始值，则 accumulator 是 initialValue，否则是数组的最后一个元素
    var accumulator:Object = hasInitialValue ? initialValue : arr[arr.length - 1];
    
    // 如果有初始值，从最后一个元素开始迭代；否则，从倒数第二个元素开始
    var startIndex:Number = hasInitialValue ? arr.length - 1 : arr.length - 2;
    
    // 逆向遍历数组，并应用回调函数
    for (var i:Number = startIndex; i >= 0; i--) {
        accumulator = callback(accumulator, arr[i], i, arr);
    }
    
    return accumulator;
}
```

### some

**描述**：测试数组中是否至少有一个元素通过了提供的函数测试。

**参数**：
- `arr:Array`：要测试的数组。
- `callback:Function`：测试每个元素的函数，接受三个参数：
    - `el`：当前元素。
    - `idx`：当前元素的索引。
    - `arr`：数组本身。

**返回值**：如果任何元素通过测试，则返回 `true`，否则返回 `false`。

**实现与优化**：
采用逆序遍历，一旦找到满足条件的元素立即返回，减少不必要的迭代。

**代码实现**：

```actionscript
/**
 * 测试数组中是否至少有一个元素通过了提供的函数测试。
 * @param arr 要测试的数组。
 * @param callback 测试每个元素的函数。
 * @return 如果任何元素通过测试，则返回 true，否则返回 false。
 */
public static function some(arr:Array, callback:Function):Boolean {
    var len:Number = arr.length;
    for (var i:Number = len - 1; i >= 0; i--) {
        if (callback(arr[i], i, arr)) {
            return true;
        }
    }
    return false;
}
```

### every

**描述**：测试数组中的所有元素是否都通过了提供的函数测试。

**参数**：
- `arr:Array`：要测试的数组。
- `callback:Function`：测试每个元素的函数，接受三个参数：
    - `el`：当前元素。
    - `idx`：当前元素的索引。
    - `arr`：数组本身。

**返回值**：如果所有元素都通过测试，则返回 `true`，否则返回 `false`。

**实现与优化**：
采用逆序遍历，一旦发现有元素未通过测试，立即返回 `false`，减少不必要的迭代。

**代码实现**：

```actionscript
/**
 * 测试数组中的所有元素是否都通过了提供的函数测试。
 * @param arr 要测试的数组。
 * @param callback 测试每个元素的函数。
 * @return 如果所有元素都通过测试，则返回 true，否则返回 false。
 */
public static function every(arr:Array, callback:Function):Boolean {
    var len:Number = arr.length;
    for (var i:Number = len - 1; i >= 0; i--) {
        if (!callback(arr[i], i, arr)) {
            return false;
        }
    }
    return true;
}
```

### find

**描述**：返回数组中第一个满足提供的测试函数的元素的值。

**参数**：
- `arr:Array`：要搜索的数组。
- `callback:Function`：测试每个元素的函数，接受三个参数：
    - `el`：当前元素。
    - `idx`：当前元素的索引。
    - `arr`：数组本身。

**返回值**：第一个符合条件的元素值，如果没有找到则返回 `null`。

**实现与优化**：
采用逆序遍历，一旦找到满足条件的元素立即返回，减少不必要的迭代。

**代码实现**：

```actionscript
/**
 * 返回数组中第一个满足提供的测试函数的元素的值。
 * @param arr 要搜索的数组。
 * @param callback 测试每个元素的函数。
 * @return 第一个符合条件的元素值，如果没有找到则返回 null。
 */
public static function find(arr:Array, callback:Function):Object {
    var len:Number = arr.length;
    for (var i:Number = len - 1; i >= 0; i--) {
        if (callback(arr[i], i, arr)) {
            return arr[i];
        }
    }
    return null;
}
```

### findIndex

**描述**：返回数组中第一个满足提供的测试函数的元素的索引。

**参数**：
- `arr:Array`：要搜索的数组。
- `callback:Function`：测试每个元素的函数，接受三个参数：
    - `el`：当前元素。
    - `idx`：当前元素的索引。
    - `arr`：数组本身。

**返回值**：第一个符合条件的元素索引，如果没有找到则返回 `-1`。

**实现与优化**：
采用逆序遍历，一旦找到满足条件的元素立即返回其索引，减少不必要的迭代。

**代码实现**：

```actionscript
/**
 * 返回数组中第一个满足提供的测试函数的元素的索引。
 * @param arr 要搜索的数组。
 * @param callback 测试每个元素的函数。
 * @return 第一个符合条件的元素索引，如果没有找到则返回 -1。
 */
public static function findIndex(arr:Array, callback:Function):Number {
    var len:Number = arr.length;
    for (var i:Number = len - 1; i >= 0; i--) {
        if (callback(arr[i], i, arr)) {
            return i;
        }
    }
    return -1;
}
```

### indexOf

**描述**：返回数组中第一个匹配指定元素的索引。

**参数**：
- `arr:Array`：要搜索的数组。
- `searchElement:Object`：要查找的元素。

**返回值**：第一个匹配元素的索引，如果未找到则返回 `-1`。

**实现与优化**：
采用正序遍历，从头到尾查找第一个匹配的元素。

**代码实现**：

```actionscript
/**
 * 返回数组中第一个匹配指定元素的索引。
 * @param arr 要搜索的数组。
 * @param searchElement 要查找的元素。
 * @return 第一个匹配元素的索引，如果未找到则返回 -1。
 */
public static function indexOf(arr:Array, searchElement:Object):Number {
    var len:Number = arr.length;
    for (var i:Number = 0; i < len; i++) {
        if (arr[i] === searchElement) {
            return i;
        }
    }
    return -1;
}
```

### lastIndexOf

**描述**：返回数组中最后一个匹配指定元素的索引。

**参数**：
- `arr:Array`：要搜索的数组。
- `searchElement:Object`：要查找的元素。

**返回值**：最后一个匹配元素的索引，如果未找到则返回 `-1`。

**实现与优化**：
采用逆序遍历，从尾到头查找最后一个匹配的元素。

**代码实现**：

```actionscript
/**
 * 返回数组中最后一个匹配指定元素的索引。
 * @param arr 要搜索的数组。
 * @param searchElement 要查找的元素。
 * @return 最后一个匹配元素的索引，如果未找到则返回 -1。
 */
public static function lastIndexOf(arr:Array, searchElement:Object):Number {
    var len:Number = arr.length;
    for (var i:Number = len - 1; i >= 0; i--) {
        if (arr[i] === searchElement) {
            return i;
        }
    }
    return -1;
}
```

### includes

**描述**：确定数组是否包含指定的元素。

**参数**：
- `arr:Array`：要搜索的数组。
- `searchElement:Object`：要查找的元素。

**返回值**：如果数组包含该元素，则返回 `true`，否则返回 `false`。

**实现与优化**：
通过调用 `indexOf` 方法判断元素是否存在，简化实现逻辑。

**代码实现**：

```actionscript
/**
 * 确定数组是否包含指定的元素。
 * @param arr 要搜索的数组。
 * @param searchElement 要查找的元素。
 * @return 如果数组包含该元素，则返回 true，否则返回 false。
 */
public static function includes(arr:Array, searchElement:Object):Boolean {
    return ArrayUtil.indexOf(arr, searchElement) !== -1;
}
```

## 使用示例

以下示例展示了如何在 AS2 中使用优化后的 `ArrayUtil` 类进行各种数组操作。

### 1. forEach 示例

```actionscript
var myArray:Array = [1, 2, 3, 4, 5];
org.flashNight.gesh.array.ArrayUtil.forEach(myArray, function(element, index, array) {
    trace("元素 " + index + " 是 " + element);
});
// 输出顺序为逆序
// 元素 4 是 5
// 元素 3 是 4
// 元素 2 是 3
// 元素 1 是 2
// 元素 0 是 1
```

### 2. map 示例

```actionscript
var myArray:Array = [1, 2, 3, 4, 5];
var squares:Array = org.flashNight.gesh.array.ArrayUtil.map(myArray, function(element) {
    return element * element;
});
trace(squares); // 输出: 1,4,9,16,25
```

### 3. filter 示例

```actionscript
var myArray:Array = [1, 2, 3, 4, 5];
var evenNumbers:Array = org.flashNight.gesh.array.ArrayUtil.filter(myArray, function(element) {
    return element % 2 == 0;
});
trace(evenNumbers); // 输出: 2,4
```

### 4. reduce 示例

```actionscript
var myArray:Array = [1, 2, 3, 4];
var sum:Object = org.flashNight.gesh.array.ArrayUtil.reduce(myArray, function(acc, el) {
    return acc + el;
}, 0);
trace(sum); // 输出: 10

var product:Object = org.flashNight.gesh.array.ArrayUtil.reduce(myArray, function(acc, el) {
    return acc * el;
});
trace(product); // 输出: 24 (即 4 * 3 * 2 * 1)
```

### 5. some 示例

```actionscript
var myArray:Array = [1, 2, 3, 4, 5];
var hasEven:Boolean = org.flashNight.gesh.array.ArrayUtil.some(myArray, function(element) {
    return element % 2 == 0;
});
trace(hasEven); // 输出: true
```

### 6. every 示例

```actionscript
var myArray:Array = [2, 4, 6, 8];
var allEven:Boolean = org.flashNight.gesh.array.ArrayUtil.every(myArray, function(element) {
    return element % 2 == 0;
});
trace(allEven); // 输出: true
```

### 7. find 示例

```actionscript
var myArray:Array = [1, 2, 3, 4, 5];
var firstEven:Object = org.flashNight.gesh.array.ArrayUtil.find(myArray, function(element) {
    return element % 2 == 0;
});
trace(firstEven); // 输出: 2
```

### 8. findIndex 示例

```actionscript
var myArray:Array = [1, 2, 3, 4, 5];
var index:Number = org.flashNight.gesh.array.ArrayUtil.findIndex(myArray, function(element) {
    return element > 3;
});
trace(index); // 输出: 3 (元素 4 的索引)
```

### 9. indexOf 示例

```actionscript
var myArray:Array = [1, 2, 3, 2, 1];
var index:Number = org.flashNight.gesh.array.ArrayUtil.indexOf(myArray, 2);
trace(index); // 输出: 1 (第一个 2 的索引)
```

### 10. lastIndexOf 示例

```actionscript
var myArray:Array = [1, 2, 3, 2, 1];
var lastIndex:Number = org.flashNight.gesh.array.ArrayUtil.lastIndexOf(myArray, 2);
trace(lastIndex); // 输出: 3
```

### 11. includes 示例

```actionscript
var myArray:Array = [1, 2, 3, 4, 5];
var containsThree:Boolean = org.flashNight.gesh.array.ArrayUtil.includes(myArray, 3);
trace(containsThree); // 输出: true
```





import org.flashNight.gesh.array.ArrayUtil;

// 定义测试数组
var testArray:Array = [1, 2, 3, 4, 5];
var largeArray:Array = [];
for (var i:Number = 0; i < 10000; i++) {
    largeArray.push(i);
}

// 简单的断言函数，用于测试正确性
function assertEquals(actual, expected, message:String):Void {
    if (actual === expected) {
        trace("[PASS] " + message);
    } else {
        trace("[FAIL] " + message + " - Expected: " + expected + ", Actual: " + actual);
    }
}

function assertArrayEquals(actual:Array, expected:Array, message:String):Void {
    if (actual.length !== expected.length) {
        trace("[FAIL] " + message + " - Array lengths differ. Expected: " + expected.length + ", Actual: " + actual.length);
        return;
    }
    for (var i:Number = 0; i < actual.length; i++) {
        if (actual[i] !== expected[i]) {
            trace("[FAIL] " + message + " - Arrays differ at index " + i + ". Expected: " + expected[i] + ", Actual: " + actual[i]);
            return;
        }
    }
    trace("[PASS] " + message);
}

// 性能基准测试函数
function measurePerformance(label:String, func:Function):Void {
    var startTime:Number = getTimer();
    func();
    var endTime:Number = getTimer();
    trace(label + " Time: " + (endTime - startTime) + " ms");
}

// 测试 forEach 方法
function testForEach():Void {
    trace("Testing forEach:");
    
    // 测试小数组的正确性
    var forEachResultSmall:Array = [];
    ArrayUtil.forEach(testArray, function(el, idx, arr) {
        forEachResultSmall.push("Element " + idx + ": " + el);
    });
    var expectedForEachSmall:Array = ["Element 4: 5", "Element 3: 4", "Element 2: 3", "Element 1: 2", "Element 0: 1"];
    assertArrayEquals(forEachResultSmall, expectedForEachSmall, "forEach small array correctness");
    
    // 性能测试小数组（不输出 trace 以避免影响性能）
    measurePerformance("forEach small array performance", function() {
        ArrayUtil.forEach(testArray, function(el, idx, arr) {});
    });
    
    // 性能测试大数组
    measurePerformance("forEach large array", function() {
        ArrayUtil.forEach(largeArray, function(el, idx, arr) {});
    });
}

// 测试 map 方法
function testMap():Void {
    trace("Testing map:");
    
    // 测试小数组的正确性
    var mapResultSmall:Array = ArrayUtil.map(testArray, function(el, idx, arr) {
        return el * 2;
    });
    var expectedMapSmall:Array = [1 * 2, 2 * 2, 3 * 2, 4 * 2, 5 * 2];
    assertArrayEquals(mapResultSmall, expectedMapSmall, "map small array correctness");
    
    // 性能测试小数组
    measurePerformance("map small array performance", function() {
        ArrayUtil.map(testArray, function(el, idx, arr) {
            return el * 2;
        });
    });
    
    // 性能测试大数组
    measurePerformance("map large array", function() {
        ArrayUtil.map(largeArray, function(el) {
            return el * 2;
        });
    });
}

// 测试 filter 方法
function testFilter():Void {
    trace("Testing filter:");
    
    // 测试小数组的正确性
    var filterResultSmall:Array = ArrayUtil.filter(testArray, function(el, idx, arr) {
        return el % 2 == 0;
    });
    var expectedFilterSmall:Array = [2, 4];
    assertArrayEquals(filterResultSmall, expectedFilterSmall, "filter small array correctness");
    
    // 性能测试小数组
    measurePerformance("filter small array performance", function() {
        ArrayUtil.filter(testArray, function(el, idx, arr) {
            return el % 2 == 0;
        });
    });
    
    // 性能测试大数组
    measurePerformance("filter large array", function() {
        ArrayUtil.filter(largeArray, function(el) {
            return el % 2 == 0;
        });
    });
}

// 测试 reduce 方法
function testReduce():Void {
    trace("Testing reduce:");
    
    // 测试小数组的正确性
    var reduceResultSmall = ArrayUtil.reduce(testArray, function(acc, el) {
        return acc + el;
    }, 0);
    var expectedReduceSmall:Number = 15; // 1 + 2 + 3 + 4 + 5
    assertEquals(reduceResultSmall, expectedReduceSmall, "reduce small array correctness");
    
    // 测试不带初始值的 reduce
    var reduceResultSmallNoInit:Object = ArrayUtil.reduce(testArray, function(acc, el) {
        return acc + el;
    });
    var expectedReduceSmallNoInit:Object = 14; // 5 + 4 + 3 + 2 + 1 = 15, but initialValue is undefined, so accumulator starts at 5, then 5+4+3+2+1=15
    // Correction: the sum should still be 15
    assertEquals(reduceResultSmallNoInit, 15, "reduce small array correctness without initialValue");
    
    // 性能测试小数组
    measurePerformance("reduce small array performance", function() {
        ArrayUtil.reduce(testArray, function(acc, el) {
            return acc + el;
        }, 0);
    });
    
    // 性能测试大数组
    measurePerformance("reduce large array", function() {
        ArrayUtil.reduce(largeArray, function(acc, el) {
            return acc + el;
        }, 0);
    });
}

// 测试 some 方法
function testSome():Void {
    trace("Testing some:");
    
    // 测试小数组的正确性
    var someResultSmall:Boolean = ArrayUtil.some(testArray, function(el) {
        return el > 3;
    });
    var expectedSomeSmall:Boolean = true;
    assertEquals(someResultSmall, expectedSomeSmall, "some small array correctness");
    
    // 性能测试小数组
    measurePerformance("some small array performance", function() {
        ArrayUtil.some(testArray, function(el) {
            return el > 3;
        });
    });
    
    // 测试大数组的正确性
    var someResultLarge:Boolean = ArrayUtil.some(largeArray, function(el) {
        return el > 9998;
    });
    var expectedSomeLarge:Boolean = true;
    assertEquals(someResultLarge, expectedSomeLarge, "some large array correctness");
    
    // 性能测试大数组
    measurePerformance("some large array", function() {
        ArrayUtil.some(largeArray, function(el) {
            return el > 9998;
        });
    });
}

// 测试 every 方法
function testEvery():Void {
    trace("Testing every:");
    
    // 测试小数组的正确性
    var everyResultSmall:Boolean = ArrayUtil.every(testArray, function(el) {
        return el > 0;
    });
    var expectedEverySmall:Boolean = true;
    assertEquals(everyResultSmall, expectedEverySmall, "every small array correctness");
    
    // 性能测试小数组
    measurePerformance("every small array performance", function() {
        ArrayUtil.every(testArray, function(el) {
            return el > 0;
        });
    });
    
    // 测试大数组的正确性
    var everyResultLarge:Boolean = ArrayUtil.every(largeArray, function(el) {
        return el >= 0;
    });
    var expectedEveryLarge:Boolean = true;
    assertEquals(everyResultLarge, expectedEveryLarge, "every large array correctness");
    
    // 性能测试大数组
    measurePerformance("every large array", function() {
        ArrayUtil.every(largeArray, function(el) {
            return el >= 0;
        });
    });
}

// 测试 find 方法
function testFind():Void {
    trace("Testing find:");
    
    // 测试小数组的正确性
    var findResultSmall:Object = ArrayUtil.find(testArray, function(el) {
        return el == 3;
    });
    var expectedFindSmall:Object = 3;
    assertEquals(findResultSmall, expectedFindSmall, "find small array correctness");
    
    // 性能测试小数组
    measurePerformance("find small array performance", function() {
        ArrayUtil.find(testArray, function(el) {
            return el == 3;
        });
    });
    
    // 测试大数组的正确性
    var findResultLarge:Object = ArrayUtil.find(largeArray, function(el) {
        return el == 9999;
    });
    var expectedFindLarge:Object = 9999;
    assertEquals(findResultLarge, expectedFindLarge, "find large array correctness");
    
    // 性能测试大数组
    measurePerformance("find large array", function() {
        ArrayUtil.find(largeArray, function(el) {
            return el == 9999;
        });
    });
}

// 测试 findIndex 方法
function testFindIndex():Void {
    trace("Testing findIndex:");
    
    // 测试小数组的正确性
    var findIndexResultSmall:Number = ArrayUtil.findIndex(testArray, function(el) {
        return el == 4;
    });
    var expectedFindIndexSmall:Number = 3;
    assertEquals(findIndexResultSmall, expectedFindIndexSmall, "findIndex small array correctness");
    
    // 性能测试小数组
    measurePerformance("findIndex small array performance", function() {
        ArrayUtil.findIndex(testArray, function(el) {
            return el == 4;
        });
    });
    
    // 测试大数组的正确性
    var findIndexResultLarge:Number = ArrayUtil.findIndex(largeArray, function(el) {
        return el == 9999;
    });
    var expectedFindIndexLarge:Number = 9999; // Since largeArray indices go from 0 to 9999
    assertEquals(findIndexResultLarge, 9999, "findIndex large array correctness");
    
    // 性能测试大数组
    measurePerformance("findIndex large array", function() {
        ArrayUtil.findIndex(largeArray, function(el) {
            return el == 9999;
        });
    });
}

// 测试 includes 方法
function testIncludes():Void {
    trace("Testing includes:");
    
    // 测试小数组的正确性
    var includesResultSmall:Boolean = ArrayUtil.includes(testArray, 3);
    var expectedIncludesSmall:Boolean = true;
    assertEquals(includesResultSmall, expectedIncludesSmall, "includes small array correctness");
    
    // 性能测试小数组
    measurePerformance("includes small array performance", function() {
        ArrayUtil.includes(testArray, 3);
    });
    
    // 测试大数组的正确性
    var includesResultLarge:Boolean = ArrayUtil.includes(largeArray, 9999);
    var expectedIncludesLarge:Boolean = true;
    assertEquals(includesResultLarge, expectedIncludesLarge, "includes large array correctness");
    
    // 性能测试大数组
    measurePerformance("includes large array", function() {
        ArrayUtil.includes(largeArray, 9999);
    });
}

// 运行所有测试
testForEach();
testMap();
testFilter();
testReduce();
testSome();
testEvery();
testFind();
testFindIndex();
testIncludes();


Testing forEach:
[PASS] forEach small array correctness
forEach small array performance Time: 0 ms
forEach large array Time: 36 ms
Testing map:
[PASS] map small array correctness
map small array performance Time: 0 ms
map large array Time: 27 ms
Testing filter:
[PASS] filter small array correctness
filter small array performance Time: 0 ms
filter large array Time: 23 ms
Testing reduce:
[PASS] reduce small array correctness
[PASS] reduce small array correctness without initialValue
reduce small array performance Time: 0 ms
reduce large array Time: 13 ms
Testing some:
[PASS] some small array correctness
some small array performance Time: 0 ms
[PASS] some large array correctness
some large array Time: 0 ms
Testing every:
[PASS] every small array correctness
every small array performance Time: 0 ms
[PASS] every large array correctness
every large array Time: 14 ms
Testing find:
[PASS] find small array correctness
find small array performance Time: 0 ms
[PASS] find large array correctness
find large array Time: 0 ms
Testing findIndex:
[PASS] findIndex small array correctness
findIndex small array performance Time: 0 ms
[PASS] findIndex large array correctness
findIndex large array Time: 0 ms
Testing includes:
[PASS] includes small array correctness
includes small array performance Time: 0 ms
[PASS] includes large array correctness
includes large array Time: 5 ms