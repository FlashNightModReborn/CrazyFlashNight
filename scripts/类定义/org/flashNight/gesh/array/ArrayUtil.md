以下是 `ArrayUtil` 类的详细文档，涵盖了每个方法的用途、参数说明、返回值、使用示例以及从工程性能优化角度的一些优化技巧。该文档旨在帮助开发者全面理解和高效使用 `ArrayUtil` 类中的各项方法。

---

# ArrayUtil 类文档

`ArrayUtil` 类提供了一系列静态方法，用于操作和处理数组。这些方法模拟了现代 JavaScript 数组 API 的功能，适用于 ActionScript 2 (AS2) 环境。通过使用 `ArrayUtil`，开发者可以简化常见的数组操作，提高代码的可读性和维护性。

## 目录

1. [基础/已有方法](#基础已有方法)
    - [isArray](#isarray)
    - [forEach](#foreach)
    - [map](#map)
    - [filter](#filter)
    - [reduce](#reduce)
    - [some](#some)
    - [every](#every)
    - [find](#find)
    - [findIndex](#findindex)
    - [findLast](#findlast)
    - [findLastIndex](#findlastindex)
    - [indexOf](#indexof)
    - [lastIndexOf](#lastindexof)
    - [includes](#includes)
    - [fill](#fill)
    - [repeat](#repeat)
    - [flat](#flat)
    - [flatMap](#flatmap)
    - [from](#from)
    - [of](#of)
    - [union](#union)
    - [difference](#difference)
    - [unique](#unique)
    - [create](#create)
2. [新增扩展方法](#新增扩展方法)
    - [groupBy](#groupby)
    - [countBy](#countby)
    - [partition](#partition)
    - [chunk](#chunk)
    - [zip](#zip)
    - [unzip](#unzip)
    - [intersection](#intersection)
    - [xor](#xor)
    - [shuffle](#shuffle)
    - [compact](#compact)
    - [range](#range)
    - [sample](#sample)
    - [merge](#merge)

---

## 基础/已有方法

### `isArray`

**描述**: 检查给定的对象是否为数组。

**定义**:
```actionscript
public static function isArray(obj:Object):Boolean
```

**参数**:
- `obj:Object`: 要检查的对象。

**返回值**:
- `Boolean`: 如果对象是数组，返回 `true`；否则返回 `false`。

**示例**:
```actionscript
ArrayUtil.isArray([1, 2, 3]); // 返回 true
ArrayUtil.isArray({a:1});      // 返回 false
```

**性能优化技巧**:
- 使用 `instanceof` 操作符进行类型检查是高效的，适用于大多数场景。避免在大量循环或高频调用中进行复杂的类型判断。

---

### `forEach`

**描述**: 对数组的每个元素执行一次提供的回调函数。

**定义**:
```actionscript
public static function forEach(arr:Array, callback:Function):Void
```

**参数**:
- `arr:Array`: 要遍历的数组。
- `callback:Function`: 对每个元素执行的函数，接受三个参数：当前元素、索引和数组本身。

**返回值**:
- `Void`: 无返回值。

**示例**:
```actionscript
var arr:Array = [1, 2, 3];
ArrayUtil.forEach(arr, function(element:Object, index:Number, array:Array):Void {
    trace("Element at index " + index + ": " + element);
});
// 输出:
// Element at index 0: 1
// Element at index 1: 2
// Element at index 2: 3
```

**性能优化技巧**:
- 避免在回调函数中执行高开销操作，如复杂的计算或频繁的对象创建。
- 在循环内部尽量减少对数组长度的多次访问，可以在方法开始时缓存数组长度。

---

### `map`

**描述**: 创建一个新数组，其中包含调用提供的函数后返回的每个元素的结果。

**定义**:
```actionscript
public static function map(arr:Array, callback:Function):Array
```

**参数**:
- `arr:Array`: 要映射的数组。
- `callback:Function`: 对每个元素执行的函数，接受三个参数：当前元素、索引和数组本身。

**返回值**:
- `Array`: 一个新数组，每个元素是回调函数的结果。

**示例**:
```actionscript
var arr:Array = [1, 2, 3];
var mapped:Array = ArrayUtil.map(arr, function(element:Object, index:Number, array:Array):Object {
    return element * 2;
});
trace(mapped); // 输出: 2,4,6
```

**性能优化技巧**:
- 如果回调函数的计算可以提前批量处理，考虑在 `map` 调用前进行优化。
- 避免在回调中进行不必要的类型转换或复杂逻辑。

---

### `filter`

**描述**: 创建一个新数组，其中包含所有通过提供的回调函数测试的元素。

**定义**:
```actionscript
public static function filter(arr:Array, callback:Function):Array
```

**参数**:
- `arr:Array`: 要过滤的数组。
- `callback:Function`: 测试每个元素的函数，接受三个参数：当前元素、索引和数组本身。

**返回值**:
- `Array`: 一个新数组，包含通过测试的元素。

**示例**:
```actionscript
var arr:Array = [1, 2, 3, 4, 5, 6];
var filtered:Array = ArrayUtil.filter(arr, function(element:Object, index:Number, array:Array):Boolean {
    return element % 2 === 0;
});
trace(filtered); // 输出: 2,4,6
```

**性能优化技巧**:
- 在回调中使用简单的条件判断，避免复杂计算。
- 如果需要多次过滤同一数组，考虑缓存中间结果以减少重复计算。

---

### `reduce`

**描述**: 使用提供的回调函数对数组的累加器和每个元素执行操作，以将数组简化为单个值。

**定义**:
```actionscript
public static function reduce(arr:Array, callback:Function, initialValue:Object):Object
```

**参数**:
- `arr:Array`: 要简化的数组。
- `callback:Function`: 对每个元素执行的函数，接受四个参数：累加器、当前元素、索引和数组本身。
- `initialValue:Object`（可选）: 用于开始累加的初始值。

**返回值**:
- `Object`: 累加后的结果。

**示例**:
```actionscript
var arr:Array = [1, 2, 3, 4, 5];
var sum:Object = ArrayUtil.reduce(arr, function(acc:Object, curr:Object, index:Number, array:Array):Object {
    return acc + curr;
}, 0);
trace(sum); // 输出: 15
```

**异常**:
- 如果数组为空且未提供初始值，则抛出错误。

**性能优化技巧**:
- 尽量使回调函数内部逻辑简单高效，因为 `reduce` 会对每个元素执行一次回调。
- 如果 `reduce` 用于累计某些统计信息，考虑是否可以通过其他方法（如提前统计）来优化性能。

---

### `some`

**描述**: 测试数组中是否至少有一个元素通过了提供的回调函数测试。

**定义**:
```actionscript
public static function some(arr:Array, callback:Function):Boolean
```

**参数**:
- `arr:Array`: 要测试的数组。
- `callback:Function`: 测试每个元素的函数，接受三个参数：当前元素、索引和数组本身。

**返回值**:
- `Boolean`: 如果任何元素通过测试，则返回 `true`；否则返回 `false`。

**示例**:
```actionscript
var arr:Array = [1, 3, 5, 7, 8];
var hasEven:Boolean = ArrayUtil.some(arr, function(element:Object):Boolean {
    return element % 2 === 0;
});
trace(hasEven); // 输出: true
```

**性能优化技巧**:
- 一旦回调函数返回 `true`，`some` 方法会立即停止遍历，避免不必要的迭代。
- 确保回调函数在满足条件时尽早返回，以充分利用 `some` 的短路特性。

---

### `every`

**描述**: 测试数组中的所有元素是否都通过了提供的回调函数测试。

**定义**:
```actionscript
public static function every(arr:Array, callback:Function):Boolean
```

**参数**:
- `arr:Array`: 要测试的数组。
- `callback:Function`: 测试每个元素的函数，接受三个参数：当前元素、索引和数组本身。

**返回值**:
- `Boolean`: 如果所有元素都通过测试，则返回 `true`；否则返回 `false`。

**示例**:
```actionscript
var arr:Array = [2, 4, 6, 8];
var allEven:Boolean = ArrayUtil.every(arr, function(element:Object):Boolean {
    return element % 2 === 0;
});
trace(allEven); // 输出: true
```

**性能优化技巧**:
- 一旦回调函数返回 `false`，`every` 方法会立即停止遍历，避免不必要的迭代。
- 确保回调函数在发现不满足条件的元素时尽早返回 `false`。

---

### `find`

**描述**: 返回数组中第一个满足提供的回调函数的元素的值。

**定义**:
```actionscript
public static function find(arr:Array, callback:Function):Object
```

**参数**:
- `arr:Array`: 要搜索的数组。
- `callback:Function`: 测试每个元素的函数，接受三个参数：当前元素、索引和数组本身。

**返回值**:
- `Object`: 第一个符合条件的元素值，如果没有找到则返回 `null`。

**示例**:
```actionscript
var arr:Array = [1, 3, 5, 7, 8];
var found:Object = ArrayUtil.find(arr, function(element:Object):Boolean {
    return element > 5;
});
trace(found); // 输出: 7
```

**性能优化技巧**:
- 一旦找到符合条件的元素，`find` 方法会立即停止遍历，避免不必要的迭代。
- 回调函数应尽量高效，以快速定位目标元素。

---

### `findIndex`

**描述**: 返回数组中第一个满足提供的回调函数的元素的索引。

**定义**:
```actionscript
public static function findIndex(arr:Array, callback:Function):Number
```

**参数**:
- `arr:Array`: 要搜索的数组。
- `callback:Function`: 测试每个元素的函数，接受三个参数：当前元素、索引和数组本身。

**返回值**:
- `Number`: 第一个符合条件的元素索引，如果没有找到则返回 `-1`。

**示例**:
```actionscript
var arr:Array = [1, 3, 5, 7, 8];
var index:Number = ArrayUtil.findIndex(arr, function(element:Object):Boolean {
    return element > 5;
});
trace(index); // 输出: 3
```

**性能优化技巧**:
- 与 `find` 类似，`findIndex` 一旦找到符合条件的元素，会立即停止遍历。
- 确保回调函数在满足条件时尽早返回 `true`。

---

### `findLast`

**描述**: 返回数组中最后一个满足提供的回调函数的元素的值。

**定义**:
```actionscript
public static function findLast(arr:Array, callback:Function):Object
```

**参数**:
- `arr:Array`: 要搜索的数组。
- `callback:Function`: 测试每个元素的函数，接受三个参数：当前元素、索引和数组本身。

**返回值**:
- `Object`: 最后一个符合条件的元素值，如果没有找到则返回 `null`。

**示例**:
```actionscript
var arr:Array = [1, 3, 5, 7, 8, 9];
var found:Object = ArrayUtil.findLast(arr, function(element:Object):Boolean {
    return element % 2 === 0;
});
trace(found); // 输出: 8
```

**性能优化技巧**:
- 从数组尾部开始遍历，尽早找到目标元素，尤其在目标元素靠近末尾时，可以显著减少迭代次数。
- 回调函数应尽量高效，以快速定位目标元素。

---

### `findLastIndex`

**描述**: 返回数组中最后一个满足提供的回调函数的元素的索引。

**定义**:
```actionscript
public static function findLastIndex(arr:Array, callback:Function):Number
```

**参数**:
- `arr:Array`: 要搜索的数组。
- `callback:Function`: 测试每个元素的函数，接受三个参数：当前元素、索引和数组本身。

**返回值**:
- `Number`: 最后一个符合条件的元素索引，如果没有找到则返回 `-1`。

**示例**:
```actionscript
var arr:Array = [1, 3, 5, 7, 8, 9];
var index:Number = ArrayUtil.findLastIndex(arr, function(element:Object):Boolean {
    return element % 2 === 0;
});
trace(index); // 输出: 4
```

**性能优化技巧**:
- 与 `findLast` 类似，从数组尾部开始遍历，尽早找到目标元素，减少迭代次数。
- 回调函数应尽量高效，以快速定位目标元素。

---

### `indexOf`

**描述**: 返回数组中第一个匹配指定元素的索引。

**定义**:
```actionscript
public static function indexOf(arr:Array, searchElement:Object):Number
```

**参数**:
- `arr:Array`: 要搜索的数组。
- `searchElement:Object`: 要查找的元素。

**返回值**:
- `Number`: 第一个匹配元素的索引，如果未找到则返回 `-1`。

**示例**:
```actionscript
var arr:Array = [1, 2, 3, 2, 1];
var index:Number = ArrayUtil.indexOf(arr, 2);
trace(index); // 输出: 1
```

**性能优化技巧**:
- 对于大数组，尽量在需要时才使用 `indexOf`，因为它是线性搜索，时间复杂度为 O(n)。
- 如果需要频繁查找元素的位置，考虑使用其他数据结构（如哈希表）来优化查找效率。

---

### `lastIndexOf`

**描述**: 返回数组中最后一个匹配指定元素的索引。

**定义**:
```actionscript
public static function lastIndexOf(arr:Array, searchElement:Object):Number
```

**参数**:
- `arr:Array`: 要搜索的数组。
- `searchElement:Object`: 要查找的元素。

**返回值**:
- `Number`: 最后一个匹配元素的索引，如果未找到则返回 `-1`。

**示例**:
```actionscript
var arr:Array = [1, 2, 3, 2, 1];
var index:Number = ArrayUtil.lastIndexOf(arr, 2);
trace(index); // 输出: 3
```

**性能优化技巧**:
- 与 `indexOf` 类似，`lastIndexOf` 也是线性搜索，但从数组尾部开始。对于寻找最后一个元素的位置，尤其是目标元素靠近数组末尾时，效率较高。
- 对于大数组，确保只有在必要时才使用，以避免不必要的性能开销。

---

### `includes`

**描述**: 确定数组是否包含指定的元素。

**定义**:
```actionscript
public static function includes(arr:Array, searchElement:Object):Boolean
```

**参数**:
- `arr:Array`: 要搜索的数组。
- `searchElement:Object`: 要查找的元素。

**返回值**:
- `Boolean`: 如果数组包含该元素，则返回 `true`；否则返回 `false`。

**示例**:
```actionscript
var arr:Array = [1, 2, 3, NaN];
ArrayUtil.includes(arr, 2);       // 返回 true
ArrayUtil.includes(arr, 4);       // 返回 false
ArrayUtil.includes(arr, NaN);     // 返回 true
ArrayUtil.includes(arr, undefined);// 返回 false
```

**性能优化技巧**:
- `includes` 内部依赖于 `indexOf`，其时间复杂度为 O(n)。对于大数组，避免频繁调用 `includes`，尤其是在嵌套循环中。
- 若需要多次检查元素存在性，考虑使用缓存或辅助数据结构（如对象哈希表）来优化查找效率。

---

### `fill`

**描述**: 使用指定值填充数组中的所有元素或指定范围的元素。

**定义**:
```actionscript
public static function fill(arr:Array, value:Object, start:Number, end:Number):Array
```

**参数**:
- `arr:Array`: 要填充的数组。
- `value:Object`: 用于填充的值。
- `start:Number`（可选）: 开始填充的索引（默认为 `0`）。
- `end:Number`（可选）: 结束填充的索引（不包括，默认为数组长度）。

**返回值**:
- `Array`: 填充后的数组。

**示例**:
```actionscript
var arr:Array = [1, 2, 3, 4, 5];
var filled:Array = ArrayUtil.fill(arr, 0, 1, 3);
trace(filled); // 输出: 1,0,0,4,5

var filledFull:Array = ArrayUtil.fill([1,2,3], 9);
trace(filledFull); // 输出: 9,9,9
```

**性能优化技巧**:
- 填充操作通常涉及对数组的多次直接赋值，确保填充的范围不超过数组长度，以避免不必要的迭代。
- 对于大数组或多次填充操作，考虑批量处理或优化算法以减少赋值次数。

---

### `repeat`

**描述**: 将数组重复指定次数后拼接。

**定义**:
```actionscript
public static function repeat(arr:Array, count:Number):Array
```

**参数**:
- `arr:Array`: 要重复的数组。
- `count:Number`: 重复的次数。

**返回值**:
- `Array`: 重复后的新数组。

**示例**:
```actionscript
var arr:Array = [1, 2];
var repeated:Array = ArrayUtil.repeat(arr, 3);
trace(repeated); // 输出: 1,2,1,2,1,2

var emptyRepeated:Array = ArrayUtil.repeat([], 5);
trace(emptyRepeated); // 输出: 
```

**性能优化技巧**:
- 对于高重复次数，使用预分配的数组或其他优化技术以减少内存分配和数组拼接的开销。
- 避免重复拼接大数组多次，考虑通过倍增策略或其他算法来高效地构建重复数组。

---

### `flat`

**描述**: 将嵌套数组“展平”为一个单层数组。

**定义**:
```actionscript
public static function flat(arr:Array, depth:Number):Array
```

**参数**:
- `arr:Array`: 要展平的数组。
- `depth:Number`（可选）: 展平的深度（默认为 `1`）。

**返回值**:
- `Array`: 展平后的新数组。

**示例**:
```actionscript
var nested:Array = [1, [2, [3, 4]], 5];
var flattened1:Array = ArrayUtil.flat(nested, 1);
trace(flattened1); // 输出: 1,2,[3,4],5

var flattened2:Array = ArrayUtil.flat(nested, 2);
trace(flattened2); // 输出: 1,2,3,4,5

var flattenedInfinite:Array = ArrayUtil.flat(nested);
trace(flattenedInfinite); // 输出: 1,2,[3,4],5
```

**性能优化技巧**:
- 递归调用在深度较大时可能导致栈溢出或性能问题。对于深度未知或可能很大的数组，考虑使用迭代方法替代递归。
- 在 `flatten` 内部尽量减少函数调用和条件判断，提高展平速度。

---

### `flatMap`

**描述**: 将 `map` 与 `flat` 结合，在映射每个元素后展平。

**定义**:
```actionscript
public static function flatMap(arr:Array, callback:Function):Array
```

**参数**:
- `arr:Array`: 要处理的数组。
- `callback:Function`: 对每个元素执行的函数，应该返回一个数组或单个元素。

**返回值**:
- `Array`: 映射并展平后的新数组。

**示例**:
```actionscript
var arr:Array = [1, 2, 3];
var flatMapped:Array = ArrayUtil.flatMap(arr, function(element:Object):Array {
    return [element, element * 2];
});
trace(flatMapped); // 输出: 1,2,2,4,3,6

var flatMappedNonArray:Array = ArrayUtil.flatMap(arr, function(element:Object):Object {
    return element * 2;
});
trace(flatMappedNonArray); // 输出: 2,4,6
```

**性能优化技巧**:
- 尽量使 `callback` 函数高效，因为每个元素都会被调用一次。
- 如果映射后总是返回数组，考虑优化数组拼接操作，减少内存分配。

---

### `from`

**描述**: 将类数组对象或可迭代对象转换为数组。

**定义**:
```actionscript
public static function from(iterable:Object):Array
```

**参数**:
- `iterable:Object`: 要转换的类数组对象或可迭代对象。

**返回值**:
- `Array`: 转换后的数组。

**示例**:
```actionscript
var str:String = "hello";
var fromArr:Array = ArrayUtil.from(str);
trace(fromArr); // 输出: h,e,l,l,o

var obj:Object = {a:1, b:2, c:3};
var fromObj:Array = ArrayUtil.from(obj);
trace(fromObj); // 输出: 1,2,3

var arr:Array = [4,5,6];
var fromArrCopy:Array = ArrayUtil.from(arr);
trace(fromArrCopy); // 输出: 4,5,6
```

**性能优化技巧**:
- 对于字符串转换，避免多次调用 `charAt`，可考虑使用内置方法（若可用）或优化字符提取逻辑。
- 对象转换时，确保仅提取必要的属性，避免不必要的迭代。

---

### `of`

**描述**: 创建包含任意元素的新数组。

**定义**:
```actionscript
public static function of():Array
```

**参数**:
- 任意数量的参数: 要包含在新数组中的元素。

**返回值**:
- `Array`: 包含传入参数的数组。

**示例**:
```actionscript
var ofArr:Array = ArrayUtil.of(1, "a", true);
trace(ofArr); // 输出: 1,a,true

var emptyOf:Array = ArrayUtil.of();
trace(emptyOf); // 输出: 
```

**性能优化技巧**:
- 对于大量参数，考虑使用预分配的数组或其他方法来避免多次数组扩展。
- 在循环内部尽量减少数组操作，确保高效地添加元素。

---

### `union`

**描述**: 将多个数组合并并去重。

**定义**:
```actionscript
public static function union():Array
```

**参数**:
- `...arrs:Array`: 要合并的多个数组。

**返回值**:
- `Array`: 合并并去重后的新数组。

**示例**:
```actionscript
var unionArr:Array = ArrayUtil.union([1, 2], [2, 3], [3, 4]);
trace(unionArr); // 输出: 1,2,3,4

var unionArr2:Array = ArrayUtil.union([], [1], [1,2]);
trace(unionArr2); // 输出: 1,2
```

**性能优化技巧**:
- 对于多个大数组的合并，尽量在单次遍历中进行去重，以提高效率。
- 使用哈希表（对象）来记录已存在的元素，减少 `indexOf` 调用次数，从而优化性能。

---

### `difference`

**描述**: 返回存在于第一个数组但不存在于第二个数组的元素。

**定义**:
```actionscript
public static function difference(arr1:Array, arrs:Array):Array
```

**参数**:
- `arr1:Array`: 第一个数组。
- `arrs:Array`: 第二个数组。

**返回值**:
- `Array`: 差集后的新数组。

**示例**:
```actionscript
var diffArr:Array = ArrayUtil.difference([1,2,3,4], [2,4]);
trace(diffArr); // 输出: 1,3

var diffArr2:Array = ArrayUtil.difference([1,2,3], []);
trace(diffArr2); // 输出: 1,2,3
```

**性能优化技巧**:
- 将第二个数组转换为哈希表，以实现 O(1) 的查找时间，从而优化差集计算。
- 对于多个差集操作，考虑缓存中间结果以避免重复计算。

---

### `unique`

**描述**: 返回数组中唯一的元素，去除重复项。

**定义**:
```actionscript
public static function unique(arr:Array):Array
```

**参数**:
- `arr:Array`: 要去重的数组。

**返回值**:
- `Array`: 去重后的新数组。

**示例**:
```actionscript
var arr:Array = [1,2,2,3,4,4,5];
var uniqueArr:Array = ArrayUtil.unique(arr);
trace(uniqueArr); // 输出: 1,2,3,4,5

var arr2:Array = [];
var uniqueArr2:Array = ArrayUtil.unique(arr2);
trace(uniqueArr2); // 输出: 
```

**性能优化技巧**:
- 使用哈希表记录已见元素，避免多次 `indexOf` 调用，从而优化去重过程。
- 对于需要保持原数组顺序的场景，此方法已经适用。如果不需要顺序，考虑其他去重方法以提高效率。

---

### `create`

**描述**: 创建一个指定长度并用指定值填充的数组。

**定义**:
```actionscript
public static function create(length:Number, value:Object):Array
```

**参数**:
- `length:Number`: 数组的长度。
- `value:Object`: 用于填充的值（默认为 `undefined`）。

**返回值**:
- `Array`: 创建并填充后的新数组。

**示例**:
```actionscript
var createdArr:Array = ArrayUtil.create(5, "x");
trace(createdArr); // 输出: x,x,x,x,x

var createdArr2:Array = ArrayUtil.create(0, "y");
trace(createdArr2); // 输出: 
```

**性能优化技巧**:
- 对于大数组的创建，确保填充值是简单类型，避免在循环中进行复杂的对象创建。
- 如果填充值为引用类型对象，确保理解共享引用的后果，以避免意外的副作用。

---

## 新增扩展方法

### `groupBy`

**描述**: 根据回调函数的返回值对数组元素进行分组。类似于 Lodash 的 `groupBy`。

**定义**:
```actionscript
public static function groupBy(arr:Array, callback:Function):Object
```

**参数**:
- `arr:Array`: 要处理的数组。
- `callback:Function`: 对每个元素执行的分组函数，返回分组 `key`。

**返回值**:
- `Object`: 一个对象，以分组 `key` 为键，分组元素数组为值。

**示例**:
```actionscript
var arr:Array = [6.1, 4.2, 6.3];
var grouped:Object = ArrayUtil.groupBy(arr, function(num:Number):String {
    return Math.floor(num);
});
trace(grouped); // 输出: { "4": [4.2], "6": [6.1, 6.3] }
```

**性能优化技巧**:
- 确保回调函数返回的 `key` 值具有良好的分布，以避免某些组过大，影响后续操作的效率。
- 对于数值 `key`，尽量返回字符串形式，以确保对象属性的一致性和可访问性。

---

### `countBy`

**描述**: 根据回调函数的返回值统计次数。类似于 Lodash 的 `countBy`。

**定义**:
```actionscript
public static function countBy(arr:Array, callback:Function):Object
```

**参数**:
- `arr:Array`: 要处理的数组。
- `callback:Function`: 对每个元素执行的分组函数，返回分组 `key`。

**返回值**:
- `Object`: 一个对象，以分组 `key` 为键，出现次数为值。

**示例**:
```actionscript
var arr:Array = [6.1, 4.2, 6.3];
var counts:Object = ArrayUtil.countBy(arr, function(num:Number):String {
    return Math.floor(num);
});
trace(counts); // 输出: { "4": 1, "6": 2 }
```

**性能优化技巧**:
- 与 `groupBy` 类似，确保回调函数高效，避免在循环中进行复杂计算。
- 使用字符串 `key` 值有助于哈希表的快速访问和存储。

---

### `partition`

**描述**: 将数组按照回调函数切分为两个部分：符合条件的放在第一个数组，不符合条件的放在第二个数组。类似于 Lodash 的 `partition`。

**定义**:
```actionscript
public static function partition(arr:Array, callback:Function):Array
```

**参数**:
- `arr:Array`: 要拆分的数组。
- `callback:Function`: 判断条件函数，返回 `true` 或 `false`。

**返回值**:
- `Array`: `[ 符合条件的数组, 不符合条件的数组 ]`。

**示例**:
```actionscript
var arr:Array = [1,2,3,4,5,6];
var partitioned:Array = ArrayUtil.partition(arr, function(num:Number):Boolean {
    return num % 2 === 0;
});
trace(partitioned); // 输出: [ [2,4,6], [1,3,5] ]
```

**性能优化技巧**:
- 确保回调函数在判断条件时高效，避免不必要的计算。
- 对于大数组，考虑是否需要同时遍历和分类，以减少循环次数。

---

### `chunk`

**描述**: 将数组分块，每个分块的大小为指定的 `size`。类似于 Lodash 的 `chunk`。

**定义**:
```actionscript
public static function chunk(arr:Array, size:Number):Array
```

**参数**:
- `arr:Array`: 要分块的数组。
- `size:Number`: 每个分块的大小。

**返回值**:
- `Array`: 分块后的二维数组。

**示例**:
```actionscript
var arr:Array = [1,2,3,4,5,6,7];
var chunked:Array = ArrayUtil.chunk(arr, 3);
trace(chunked); // 输出: [ [1,2,3], [4,5,6], [7] ]
```

**性能优化技巧**:
- 在分块过程中，尽量减少数组的 `slice` 调用次数，尤其在高频调用时。
- 对于固定大小的块，预计算分块次数以优化循环条件。

---

### `zip`

**描述**: 将多个数组对应索引的元素组合在一起。类似于 Lodash 的 `zip`。

**定义**:
```actionscript
public static function zip():Array
```

**参数**:
- `...arrs:Array`: 多个数组。

**返回值**:
- `Array`: 组合后的二维数组。

**示例**:
```actionscript
var zipped:Array = ArrayUtil.zip([1,2], ["a","b"], [true, false]);
trace(zipped); // 输出: [ [1,"a",true], [2,"b",false] ]

var zipped2:Array = ArrayUtil.zip([1,2,3], ["a","b"], [true]);
trace(zipped2); // 输出: [ [1,"a",true], [2,"b",undefined], [3,undefined,undefined] ]
```

**性能优化技巧**:
- 确保传入的数组数量不超过预期，以避免不必要的循环次数。
- 对于大数组，优化内层循环，减少数组访问次数。

---

### `unzip`

**描述**: 将由 `zip` 创建的分组数组拆分成多个数组。类似于 Lodash 的 `unzip`。

**定义**:
```actionscript
public static function unzip(arr:Array):Array
```

**参数**:
- `arr:Array`: 要拆分的分组数组。

**返回值**:
- `Array`: 拆分后的多个数组。

**示例**:
```actionscript
var grouped:Array = [ [1,"a",true], [2,"b",false] ];
var unzipped:Array = ArrayUtil.unzip(grouped);
trace(unzipped); // 输出: [ [1,2], ["a","b"], [true, false] ]

var grouped2:Array = [];
var unzipped2:Array = ArrayUtil.unzip(grouped2);
trace(unzipped2); // 输出: 
```

**性能优化技巧**:
- 预先确定拆分后的数组长度，以优化内层循环的性能。
- 避免在拆分过程中进行复杂的条件判断，保持逻辑简单高效。

---

### `intersection`

**描述**: 返回多个数组的交集元素。

**定义**:
```actionscript
public static function intersection():Array
```

**参数**:
- `...arrs:Array`: 多个数组。

**返回值**:
- `Array`: 交集元素数组。

**示例**:
```actionscript
var inter:Array = ArrayUtil.intersection([1,2,3], [2,3,4], [3,4,5]);
trace(inter); // 输出: 3

var inter2:Array = ArrayUtil.intersection([1,2], [3,4]);
trace(inter2); // 输出: 
```

**性能优化技巧**:
- 从最小的数组开始计算交集，可以减少中间结果的大小，提高后续迭代的效率。
- 使用哈希表存储中间结果，以加快元素存在性的检查。

---

### `xor`

**描述**: 返回多个数组的对称差集 (xor)。即仅在其中一个数组中出现，而不在多个数组中重复出现的元素。

**定义**:
```actionscript
public static function xor():Array
```

**参数**:
- `...arrs:Array`: 多个数组。

**返回值**:
- `Array`: 对称差集数组。

**示例**:
```actionscript
var xorRes:Array = ArrayUtil.xor([1,2], [2,3], [3,4]);
trace(xorRes); // 输出: [1,4]

var xorRes2:Array = ArrayUtil.xor([1,1,2], [2,3,3]);
trace(xorRes2); // 输出: [1,3]
```

**性能优化技巧**:
- 对每个数组进行去重处理，可以避免重复元素影响计数。
- 使用哈希表记录元素出现的次数，快速确定哪些元素属于对称差集。
- 排序结果数组有助于提高后续操作的效率，如比较或进一步处理。

---

### `shuffle`

**描述**: 将数组随机打乱 (Fisher-Yates Shuffle)。

**定义**:
```actionscript
public static function shuffle(arr:Array):Array
```

**参数**:
- `arr:Array`: 要打乱的数组。

**返回值**:
- `Array`: 打乱后的数组（原数组也会被修改，若不希望修改原数组可先复制一份）。

**示例**:
```actionscript
var arr:Array = [1,2,3,4,5];
var shuffled:Array = ArrayUtil.shuffle(arr.concat()); // 复制数组后打乱
trace(shuffled); // 输出: 数组元素的随机顺序
```

**性能优化技巧**:
- Fisher-Yates Shuffle 是一种高效的打乱算法，时间复杂度为 O(n)。
- 为了避免修改原数组，建议在调用 `shuffle` 前先使用 `concat` 或其他方法复制数组。

---

### `compact`

**描述**: 过滤掉数组中 `falsy` 的值 (`undefined`, `null`, `0`, `""`, `false`, `NaN`)。类似于 Lodash 的 `compact`。

**定义**:
```actionscript
public static function compact(arr:Array):Array
```

**参数**:
- `arr:Array`: 要过滤的数组。

**返回值**:
- `Array`: 过滤后的新数组。

**示例**:
```actionscript
var arr:Array = [0, 1, false, 2, "", 3, null, 4, undefined, NaN];
var compacted:Array = ArrayUtil.compact(arr);
trace(compacted); // 输出: 1,2,3,4

var arr2:Array = [false, 0, "", null, undefined, NaN];
var compacted2:Array = ArrayUtil.compact(arr2);
trace(compacted2); // 输出: 
```

**性能优化技巧**:
- 在回调函数中进行简单的 `if (arr[i])` 判断，可以高效过滤 `falsy` 值。

---

### `range`

**描述**: 返回一个包含从 `start` 到 `end` 的连续整数数组。相当于 Python 的 `range` 或 Lodash 的 `range`。

**定义**:
```actionscript
public static function range(start:Number, end:Number, step:Number):Array
```

**参数**:
- `start:Number`: 起始值（包含）。
- `end:Number`: 结束值（不包含）。
- `step:Number`（可选）: 步进值（默认为 `1`）。

**返回值**:
- `Array`: 生成的数组。

**示例**:
```actionscript
var rangeArr:Array = ArrayUtil.range(0, 5);
trace(rangeArr); // 输出: 0,1,2,3,4

var rangeArr2:Array = ArrayUtil.range(5, 0, -1);
trace(rangeArr2); // 输出: 5,4,3,2,1

var rangeArr3:Array = ArrayUtil.range(0, 10, 2);
trace(rangeArr3); // 输出: 0,2,4,6,8

var rangeArr4:Array = ArrayUtil.range(0, 5, 0);
trace(rangeArr4); // 输出: 
```

**性能优化技巧**:
- 确保 `step` 不为 `0`，以避免无限循环。
- 对于固定步进的场景，可以预计算数组长度，进行一次性数组分配，减少内存分配次数。

---

### `sample`

**描述**: 随机从数组中返回一个或多个元素。

**定义**:
```actionscript
public static function sample(arr:Array, n:Number):Object
```

**参数**:
- `arr:Array`: 要采样的数组。
- `n:Number`（可选）: 采样个数，默认为 `1`。

**返回值**:
- `Object`: 采样得到的元素（当 `n=1` 时，直接返回元素；`n>1` 时，返回数组）。

**示例**:
```actionscript
var arr:Array = [1,2,3,4,5];
var singleSample:Object = ArrayUtil.sample(arr);
trace(singleSample); // 输出: 随机一个元素，例如: 3

var multiSample:Array = ArrayUtil.sample(arr, 3);
trace(multiSample); // 输出: 随机三个元素，例如: 2,4,5
```

**性能优化技巧**:
- 对于多次采样操作，特别是 `n` 接近数组长度时，考虑使用预打乱数组的方法，提高采样效率。
- 避免在高频调用中频繁复制和打乱数组，以减少内存和计算开销。

---

### `merge`

**描述**: 合并多个数组或对象中的值到目标数组中（浅合并）。用于简化多数组或多对象合并场景。

**定义**:
```actionscript
public static function merge(target:Array):Array
```

**参数**:
- `target:Array`: 目标数组。
- `sources:Object`: 要合并的多个数组或对象。

**返回值**:
- `Array`: 合并后的目标数组。

**示例**:
```actionscript
var target:Array = [1, 2];
var merged:Array = ArrayUtil.merge(target, [3,4], {a:5, b:6});
trace(merged); // 输出: 1,2,3,4,5,6

var target2:Array = [];
var merged2:Array = ArrayUtil.merge(target2, [1], {a:2});
trace(merged2); // 输出: 1,2

var target3:Array = [0];
var merged3:Array = ArrayUtil.merge(target3, [], {a:1});
trace(merged3); // 输出: 0,1
```

**性能优化技巧**:
- 尽量减少目标数组的多次 `concat` 调用，特别是在合并多个大数组时。可以考虑预分配数组长度或使用一次性拼接策略。
- 对于对象合并，确保仅合并必要的属性，避免不必要的迭代和赋值操作。

---

## 总结与优化建议

- **避免重复计算**: 在需要频繁操作同一数组时，考虑缓存中间结果，避免重复遍历或计算。
- **使用哈希表**: 对于需要快速查找元素的操作（如 `union`、`intersection`、`difference`），使用哈希表（对象）存储元素，可以显著提高查找效率。
- **减少内存分配**: 尽量在一次性操作中完成多个任务，避免频繁的数组复制和扩展，特别是在处理大数组时。
- **优化回调函数**: 回调函数应尽量高效，避免在每次调用中执行复杂逻辑或昂贵的计算，以减少整体执行时间。
- **预计算循环条件**: 在循环开始前，尽量将不变的条件或属性缓存起来，避免在每次迭代中重复计算或访问。
- **短路逻辑**: 对于支持短路的操作（如 `some`、`every`、`find`、`findIndex` 等），确保回调函数在满足条件时及时返回，以利用短路特性，提高性能。

通过合理使用 `ArrayUtil` 类中的方法，并结合上述优化建议，可以显著提升数组操作的效率和代码质量，确保在 AS2 环境中实现高效、可靠的数据处理。

---

# 工程性能优化技巧

在使用 `ArrayUtil` 类时，以下是一些从工程性能优化角度的建议和技巧：

1. **避免不必要的数组复制**:
    - 方法如 `shuffle` 和 `map` 会生成新的数组，尽量在需要时才调用，避免在高频操作中频繁复制大数组。
    - 使用 `concat` 时，了解它会生成新的数组，避免在不需要保留原数组的情况下使用，以节省内存。

2. **优化回调函数**:
    - 尽量使回调函数简洁高效，避免在每次调用中进行复杂的逻辑或计算。
    - 使用本地变量缓存外部变量，减少闭包带来的性能开销。

3. **减少循环嵌套**:
    - 尽量避免在数组方法中嵌套循环，尤其是在处理大数组时，以减少时间复杂度。
    - 对于需要多次遍历的操作，考虑是否可以通过一次遍历完成。

4. **利用哈希表加速查找**:
    - 对于需要频繁查找元素存在性的操作（如 `union`、`intersection`、`difference`），使用对象作为哈希表存储元素，可以将查找时间从 O(n) 降低到 O(1)。
    - 例如，在 `unique` 方法中，可以通过对象记录已存在的元素，避免多次 `indexOf` 调用。

5. **预分配数组长度**:
    - 对于已知长度的数组，考虑预先分配数组长度，避免在循环中动态扩展数组带来的性能损耗。
    - 尽管 AS2 对数组的支持有限，但可以通过一次性 `concat` 或其他方法优化数组构建过程。

6. **使用原地修改**:
    - 某些操作可以在原数组上进行修改，避免生成新的数组，节省内存。例如，`fill` 方法会修改原数组元素。
    - 在确定不会影响其他引用的情况下，优先选择原地操作。

7. **避免高开销的对象比较**:
    - 在 `assertEqual` 等测试方法中，避免对大对象或深层嵌套对象进行深度比较，以减少性能开销。
    - 仅在必要时进行详细的对象比较，平衡测试的准确性和性能。

8. **利用内置方法**:
    - 尽量利用 AS2 内置的数组方法（如 `slice`、`concat`）来完成常见操作，因为这些方法通常经过优化，性能较高。

9. **分批处理**:
    - 对于需要处理非常大的数组，考虑将其分批处理，避免一次性处理导致的内存压力或性能下降。
    - 分批处理还可以与用户界面更新相结合，避免阻塞界面响应。

10. **缓存重复结果**:
    - 如果某些操作会在多次调用中重复执行，考虑缓存其结果，避免重复计算。
    - 例如，对于重复调用 `groupBy` 或 `countBy` 的场景，可以缓存分组结果以提高效率。

通过合理应用上述优化技巧，可以显著提升 `ArrayUtil` 类在工程中的性能表现，确保在 AS2 环境下高效、可靠地处理数组数据。

---

# 测试代码与日志

```actionscript
import org.flashNight.gesh.array.ArrayUtilTest;

ArrayUtilTest.runTests();
```

```output

===== ArrayUtil Test Start =====
--- Testing isArray ---
[PASS] isArray with Array
[PASS] isArray with Object
[PASS] isArray with String
[PASS] isArray with null
[PASS] isArray with undefined
--- Testing forEach ---
[PASS] forEach multiplies elements by 2
--- Testing map ---
[PASS] map multiplies elements by 3
--- Testing filter ---
[PASS] filter even numbers
--- Testing reduce ---
[PASS] reduce sum with initial value 0
[PASS] reduce sum without initial value
[PASS] reduce empty array without initial value threw error
--- Testing some ---
[PASS] some checks for even numbers
[PASS] some checks for even numbers in all odd array
--- Testing every ---
[PASS] every checks all elements are even
[PASS] every checks all elements are even with one odd
[PASS] every on empty array returns true
--- Testing find ---
[PASS] find first element > 5
[PASS] find element > 10 in array
--- Testing findIndex ---
[PASS] findIndex first element > 5
[PASS] findIndex element > 10 in array
--- Testing findLast ---
[PASS] findLast even element
[PASS] findLast even element in all odd array
--- Testing findLastIndex ---
[PASS] findLastIndex even element
[PASS] findLastIndex even element in all odd array
--- Testing indexOf ---
[PASS] indexOf first occurrence of 2
[PASS] indexOf element not in array
--- Testing lastIndexOf ---
[PASS] lastIndexOf last occurrence of 2
[PASS] lastIndexOf element not in array
--- Testing includes ---
[PASS] includes element 2
[PASS] includes element 4
[PASS] includes NaN
[PASS] includes undefined
--- Testing fill ---
[PASS] fill array with 0 from index 1 to 3
[PASS] fill entire array with 9
--- Testing repeat ---
[PASS] repeat [1,2] three times
[PASS] repeat empty array five times
--- Testing flat ---
[PASS] flat nested array with depth 1
[PASS] flat nested array with depth 2
[PASS] flat nested array with default depth 1
--- Testing flatMap ---
[PASS] flatMap doubles elements
[PASS] flatMap with non-array return
--- Testing from ---
[PASS] from string to array
[PASS] from object to array
[PASS] from array to array (copy)
--- Testing of ---
[PASS] of creates array with elements 1, 'a', true
[PASS] of with no arguments creates empty array
--- Testing union ---
[PASS] union of [1,2], [2,3], [3,4]
[PASS] union with empty array
--- Testing difference ---
[PASS] difference [1,2,3,4] - [2,4]
[PASS] difference [1,2,3] - []
--- Testing unique ---
[PASS] unique [1,2,2,3,4,4,5]
[PASS] unique on empty array
--- Testing create ---
[PASS] create array of length 5 filled with 'x'
[PASS] create array of length 0
--- Testing groupBy ---
[PASS] groupBy floored numbers
--- Testing countBy ---
[FAIL] countBy floored numbers | Expected: { 6: 2, 4: 1, }, Actual: { 4: 1, 6: 2, }
--- Testing partition ---
[PASS] partition even and odd numbers
--- Testing chunk ---
[PASS] chunk array into size 3
[PASS] chunk array with size 0
--- Testing zip ---
[PASS] zip [1,2], ['a','b'], [true,false]
[PASS] zip arrays of different lengths
--- Testing unzip ---
[PASS] unzip [[1,'a',true],[2,'b',false]]
[PASS] unzip empty array
--- Testing intersection ---
[PASS] intersection of [1,2,3], [2,3,4], [3,4,5]
[PASS] intersection of [1,2], [3,4]
--- Testing xor ---
[PASS] xor of [1,2], [2,3], [3,4]
[PASS] xor of [1,1,2], [2,3,3]
--- Testing shuffle ---
[INFO] shuffle produces different order: true
--- Testing compact ---
[PASS] compact removes falsy values
[PASS] compact removes all falsy values
--- Testing range ---
[PASS] range from 0 to 5 with default step
[PASS] range from 5 to 0 with step -1
[PASS] range from 0 to 10 with step 2
[PASS] range with step 0 returns empty array
--- Testing sample ---
[INFO] single sample: 2
[PASS] sample single element is in array
[PASS] sample three elements are in array
--- Testing merge ---
[PASS] merge [1,2] with [3,4] and {a:5, b:6}
[PASS] merge empty target with [1] and {a:2}
[PASS] merge [0] with empty array and {a:1}
===== ArrayUtil Test End =====


```

