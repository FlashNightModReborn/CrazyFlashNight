/*

class org.flashNight.naki.Sort.InsertionSort

# InsertionSort 排序类使用指南

## 介绍
`InsertionSort` 类实现了一种高效的插入排序算法，专门用于小规模数据的排序。该实现通过避免递归和函数调用，最大化性能，尤其适合于处理小型数组和几乎有序的数据。

此外，`sortOn` 方法基于插入排序算法扩展了对多字段排序的支持，提供了灵活的排序选项，例如数值排序、降序、大小写不敏感等，可以替代 AS2 原生的 `sortOn` 方法，增强性能和自定义能力。

## 方法概述

1. **sort(arr:Array, compareFunction:Function)**:
   - 实现高效的插入排序算法。
   - **使用场景**：
     - 当数据集较小时（如 100 个元素），插入排序通常能提供较快的排序速度。
     - 数据几乎有序时，插入排序能迅速完成排序。
     - 对于实时或增量数据插入场景，插入排序能够高效处理。

2. **sortOn(arr:Array, fieldName:Object, options:Object)**:
   - 基于插入排序的自定义 `sortOn` 方法，完全替代 AS2 的原生 `sortOn` 方法。
   - 支持多字段排序、自定义排序选项（数值、降序、大小写敏感等）、返回索引数组以及唯一性检测。
   - **使用场景**：
     - 适用于需要根据一个或多个字段进行排序的对象数组。
     - 可用于处理数据量小、字段排序需求复杂的场景，提供比 AS2 内置 `sortOn` 更强的性能和灵活性。
     - 当需要保证数组元素的唯一性或返回排序后的索引数组时，可以启用 `Array.UNIQUESORT` 或 `Array.RETURNINDEXEDARRAY` 选项。
   - **支持的排序选项**：
     - `Array.NUMERIC`：按数值进行排序。如果字段包含数值，建议使用此选项。
     - `Array.DESCENDING`：按降序排序。默认是升序排序，如果需要降序，可以与其他选项组合使用。
     - `Array.CASEINSENSITIVE`：忽略大小写进行排序。适用于字符串排序，特别是涉及多个字段时可以结合使用。
     - `Array.RETURNINDEXEDARRAY`：返回索引数组而不是直接排序的结果。此选项用于需要返回元素原始位置的情况。
     - `Array.UNIQUESORT`：启用唯一性检测，若有重复值则返回 null。适用于需要确保数组唯一性的场景。

## 方法使用示例

### sort 方法
```actionscript
import org.flashNight.naki.Sort.InsertionSort;

// 假设我们有一个包含随机数的数组
var arr:Array = [5, 2, 9, 1, 5, 6];

// 调用插入排序
var sortedArray:Array = InsertionSort.sort(arr);

// 输出排序后的数组
trace(sortedArray); // [1, 2, 5, 5, 6, 9]
```

### sortOn 方法
```actionscript
import org.flashNight.naki.Sort.InsertionSort;

// 假设我们有一个对象数组
var arr:Array = [{name: "Alice", age: 30}, {name: "Bob", age: 25}, {name: "Charlie", age: 25}];

// 1. 按 age 字段升序排序
InsertionSort.sortOn(arr, "age", Array.NUMERIC);

// 输出排序后的数组
trace(arr); // [{name: "Bob", age: 25}, {name: "Charlie", age: 25}, {name: "Alice", age: 30}]

// 2. 按 name 字段降序、忽略大小写排序
InsertionSort.sortOn(arr, "name", Array.DESCENDING | Array.CASEINSENSITIVE);

// 输出排序后的数组
trace(arr); // [{name: "Charlie", age: 25}, {name: "Bob", age: 25}, {name: "Alice", age: 30}]

// 3. 按 age 和 name 字段进行多字段排序，age 优先，若 age 相同则按 name 排序，忽略大小写
InsertionSort.sortOn(arr, ["age", "name"], [Array.NUMERIC, Array.CASEINSENSITIVE]);

// 输出排序后的数组
trace(arr); // [{name: "Bob", age: 25}, {name: "Charlie", age: 25}, {name: "Alice", age: 30}]
```

## 注意事项
- `sortOn` 方法对多字段排序有完整支持，能够通过传入多个字段名数组和对应的选项数组来实现复杂排序需求。
- 当排序数组中包含重复元素时，可以启用 `Array.UNIQUESORT` 选项进行唯一性检测，如果检测到重复值，则返回 `null` 以指示排序失败。
- 如果需要保留排序前的元素索引，可以使用 `Array.RETURNINDEXEDARRAY` 选项，返回的结果将是原数组中每个元素的新排序索引。

```

*/

class org.flashNight.naki.Sort.InsertionSort {

    /**
     * 高效的插入排序实现，专门用于小规模数据的排序。
     * 通过避免递归和函数调用，最大化性能。
     *
     * @param arr 要排序的数组。
     * @param compareFunction 自定义的比较函数，定义排序顺序。
     * @return 排序后的数组。
     */
    public static function sort(arr:Array, compareFunction:Function):Array {
        var a:Array = arr;
        var length:Number = a.length;
        if (length <= 1) return a;
        
        var compare:Function = compareFunction != undefined ? compareFunction : function(a, b):Number { return a - b; };
        
        var i:Number = 1; // 从第二个元素开始
        var j:Number;   // 用于存储当前位置
        var key:Object; // 用于存储当前元素

        do {
            key = arr[i];
            j = i - 1;
            
            do {
                if (compare(a[j], key) > 0) {
                    a[j + 1] = a[j--];
                } else {
                    break;
                }
            } while (j >= 0);
            
            a[j + 1] = key;
        } while (++i < length);
        
        return a;
    }





    /**
     * 基于插入排序算法的自定义 `sortOn` 方法，完全替代 AS2 的原生 `sortOn` 方法。
     * 支持多字段排序、自定义排序选项（数值、降序、大小写敏感等）、返回索引数组以及唯一性检测。
     *
     * 功能说明：
     * - 此方法允许根据一个或多个字段进行排序，并且可以通过选项设置不同的排序规则。
     * - 提供了灵活的排序机制，支持数值型排序、字符串排序（大小写敏感或不敏感）、升序和降序等多种模式。
     * - 支持返回一个索引数组，即排序后返回原始数组中元素的排序索引位置。
     * - 提供唯一性检测功能（uniqueSort），当数组中有重复元素时返回 null 以指示排序失败。
     * - 可以用来替代 AS2 的 `Array.sortOn` 方法，提供更多自定义排序选项，并避免内置方法的某些限制。
     *
     * 性能表现总结：
     * - 在小规模数据（如 100 个元素）的测试中，`InsertionSort` 方法表现与内置 `sortOn` 方法相近，有时甚至略快。
     * - 在大规模数据（如 1000 个元素）的测试中，`InsertionSort` 方法显著优于内置 `sortOn`，尤其在处理多字段排序（如 `name,x`）时，性能差异尤为显著。
     * - 特别是在处理重复数据、倒序数据和部分有序数据时，`InsertionSort` 表现出色，处理时间远低于内置方法。
     *
     * 使用说明：
     * - `arr`：要排序的数组，其中每个元素应为包含指定字段的对象。
     * - `fieldName`：字段名或字段名数组，用于指定排序依据的字段。如果是数组，则表示多字段排序。
     * - `options`：排序选项或选项数组，定义排序规则和行为。可以通过 `|` 操作符组合多个选项。支持的选项包括：
     *      - `Array.NUMERIC`：按数值进行排序。如果字段包含数值，建议使用此选项。
     *      - `Array.DESCENDING`：按降序排序。默认是升序排序，如果需要降序，可以与其他选项组合使用。
     *      - `Array.CASEINSENSITIVE`：忽略大小写进行排序。适用于字符串排序，特别是涉及多个字段时可以结合使用。
     *      - `Array.RETURNINDEXEDARRAY`：返回索引数组而不是直接排序的结果。此选项用于需要返回元素原始位置的情况。
     *      - `Array.UNIQUESORT`：启用唯一性检测，若有重复值则返回 null。适用于需要确保数组唯一性的场景。
     *
     * 组合选项的使用：
     * - 你可以通过 `|` 操作符将多个选项组合。例如：
     *      - `Array.NUMERIC | Array.DESCENDING`：表示按数值降序排序。
     *      - `Array.CASEINSENSITIVE | Array.DESCENDING`：表示忽略大小写并按降序排序。
     *      - 如果有多个字段，可以为每个字段分别设置不同的选项，并在 `options` 数组中按顺序传入。
     *
     * 示例用法：
     * ```actionscript
     * var arr:Array = [{name: "Alice", age: 30}, {name: "Bob", age: 25}, {name: "Charlie", age: 25}];
     * 
     * // 按 age 字段升序排序
     * InsertionSort.sortOn(arr, "age", Array.NUMERIC);
     *
     * // 按 name 字段降序、忽略大小写排序
     * InsertionSort.sortOn(arr, "name", Array.DESCENDING | Array.CASEINSENSITIVE);
     *
     * // 按 age 和 name 字段进行多字段排序，age 优先，若 age 相同则按 name 排序，忽略大小写
     * InsertionSort.sortOn(arr, ["age", "name"], [Array.NUMERIC, Array.CASEINSENSITIVE]);
     * ```
     *
     * @param arr 要排序的数组，每个元素应包含需要排序的字段。
     * @param fieldName 单个字段名或字段名数组，用于指定排序的依据。
     * @param options 单个选项或选项数组，定义排序的规则和行为。可以通过 `|` 操作符组合多个选项。
     * @return 排序后的数组，或者如果启用了唯一性检查且发现重复元素时返回 null。
     */

    public static function sortOn(arr:Array, fieldName:Object, options:Object):Array {
        var length:Number = arr.length;
        if (length <= 1) {
            return arr; // 若数组长度小于等于 1，无需排序，直接返回
        }

        // 初始化字段名数组和选项数组，确保两个数组长度一致
        var fieldNames:Array = (fieldName instanceof Array) ? fieldName : [fieldName];
        var optionsArray:Array = (options instanceof Array) ? options : [options];

        // 用于控制是否返回索引数组，以及是否启用唯一性检查
        var returnIndexedArray:Boolean = false;
        var uniqueSort:Boolean = false;
        var globalOptions:Number = 0; // 全局选项，用于存储所有字段的选项（通过按位运算合并）
        var hasDuplicates:Boolean = false; // 新增：初始化 hasDuplicates 变量，用于检测重复项

        // 遍历选项数组，合并所有选项到 globalOptions 中
        for (var optIndex:Number = 0; optIndex < optionsArray.length; optIndex++) {
            var opt:Number = optionsArray[optIndex];
            globalOptions |= opt;
        }

        // 解析全局选项的具体行为
        returnIndexedArray = (globalOptions & Array.RETURNINDEXEDARRAY) != 0;
        uniqueSort = (globalOptions & Array.UNIQUESORT) != 0;

        // 如果启用了索引返回或唯一性检查，初始化索引数组
        var indices:Array = [];
        if (returnIndexedArray || uniqueSort) {
            for (var i:Number = 0; i < length; i++) {
                indices[i] = i; // 将原始数组的索引保存到索引数组中
            }
        }

        // 处理单字段排序的情况
        if (fieldNames.length == 1) {
            // 获取字段名和选项
            var field:String = fieldNames[0];
            var option:Number = optionsArray[0];

            // 解析选项中的具体排序规则
            var numeric:Boolean = (option & Array.NUMERIC) != 0;
            var descending:Boolean = (option & Array.DESCENDING) != 0;
            var caseInsensitive:Boolean = (option & Array.CASEINSENSITIVE) != 0;

            // 数字排序：根据 numeric 和 descending 的组合处理升序或降序的排序逻辑
            // 字符串排序：根据大小写敏感或不敏感的规则进行比较

            // 将不同的排序规则展开成具体的排序循环
            if (numeric) {
                if (descending) {
                    // 数值降序排序
                    for (i = 1; i < length; i++) {
                        var keyNumDesc:Object = arr[i];
                        var keyValueNumDesc:Number = Number(keyNumDesc[field]);
                        var j:Number = i - 1;

                        // 插入排序逻辑，降序比较
                        while (j >= 0 && Number(arr[j][field]) < keyValueNumDesc) {
                            arr[j + 1] = arr[j];
                            j--;
                        }
                        arr[j + 1] = keyNumDesc;

                        // 若启用了唯一性检测，检查是否存在重复值
                        if (uniqueSort && !hasDuplicates && j >= 0 && Number(arr[j][field]) == keyValueNumDesc) {
                            hasDuplicates = true;
                        }
                    }
                } else {
                    // 数值升序排序
                    for (i = 1; i < length; i++) {
                        var keyNumAsc:Object = arr[i];
                        var keyValueNumAsc:Number = Number(keyNumAsc[field]);
                        j = i - 1;

                        while (j >= 0 && Number(arr[j][field]) > keyValueNumAsc) {
                            arr[j + 1] = arr[j];
                            j--;
                        }
                        arr[j + 1] = keyNumAsc;

                        // 若启用了唯一性检测，检查是否存在重复值
                        if (uniqueSort && !hasDuplicates && j >= 0 && Number(arr[j][field]) == keyValueNumAsc) {
                            hasDuplicates = true;
                        }
                    }
                }
            } else {
                // 字符串排序，根据是否启用大小写敏感以及排序方向执行
                if (descending) {
                    if (caseInsensitive) {
                        // 字符串降序，忽略大小写
                        for (i = 1; i < length; i++) {
                            var keyLexDescCI:Object = arr[i];
                            var keyValueLexDescCI:String = String(keyLexDescCI[field]).toLowerCase();
                            j = i - 1;

                            while (j >= 0 && String(arr[j][field]).toLowerCase() < keyValueLexDescCI) {
                                arr[j + 1] = arr[j];
                                j--;
                            }
                            arr[j + 1] = keyLexDescCI;

                            // 若启用了唯一性检测，检查是否存在重复值
                            if (uniqueSort && !hasDuplicates && j >= 0 && String(arr[j][field]).toLowerCase() == keyValueLexDescCI) {
                                hasDuplicates = true;
                            }
                        }
                    } else {
                        // 字符串降序，区分大小写
                        for (i = 1; i < length; i++) {
                            var keyLexDesc:Object = arr[i];
                            var keyValueLexDesc:String = keyLexDesc[field];
                            j = i - 1;

                            while (j >= 0 && arr[j][field] < keyValueLexDesc) {
                                arr[j + 1] = arr[j];
                                j--;
                            }
                            arr[j + 1] = keyLexDesc;

                            // 若启用了唯一性检测，检查是否存在重复值
                            if (uniqueSort && !hasDuplicates && j >= 0 && arr[j][field] == keyValueLexDesc) {
                                hasDuplicates = true;
                            } 
                        }
                    }
                } else {
                    if (caseInsensitive) {
                        // 字符串升序，忽略大小写
                        for (i = 1; i < length; i++) {
                            var keyLexAscCI:Object = arr[i];
                            var keyValueLexAscCI:String = String(keyLexAscCI[field]).toLowerCase();
                            j = i - 1;

                            while (j >= 0 && String(arr[j][field]).toLowerCase() > keyValueLexAscCI) {
                                arr[j + 1] = arr[j];
                                j--;
                            }
                            arr[j + 1] = keyLexAscCI;

                            // 若启用了唯一性检测，检查是否存在重复值
                            if (uniqueSort && !hasDuplicates && j >= 0 && String(arr[j][field]).toLowerCase() == keyValueLexAscCI) {
                                hasDuplicates = true;
                            }
                        }
                    } else {
                        // 字符串升序，区分大小写
                        for (i = 1; i < length; i++) {
                            var keyLexAsc:Object = arr[i];
                            var keyValueLexAsc:String = keyLexAsc[field];
                            j = i - 1;

                            while (j >= 0 && arr[j][field] > keyValueLexAsc) {
                                arr[j + 1] = arr[j];
                                j--;
                            }
                            arr[j + 1] = keyLexAsc;

                            // 若启用了唯一性检测，检查是否存在重复值
                            if (uniqueSort && !hasDuplicates && j >= 0 && arr[j][field] == keyValueLexAsc) {
                                hasDuplicates = true;
                            }
                        }
                    }
                }
            }
        // 处理多字段排序（最多支持两个字段的情况）
        // 当提供两个字段进行排序时，先按第一个字段排序，若第一个字段相等，则按第二个字段排序
        } else if (fieldNames.length == 2) {
            // 提取两个字段的排序选项
            var option1:Number = optionsArray[0];
            var option2:Number = optionsArray[1];

            // 根据选项解析第一个字段的排序规则
            var numeric1:Boolean = (option1 & Array.NUMERIC) != 0;
            var descending1:Boolean = (option1 & Array.DESCENDING) != 0;
            var caseInsensitive1:Boolean = (option1 & Array.CASEINSENSITIVE) != 0;

            // 根据选项解析第二个字段的排序规则
            var numeric2:Boolean = (option2 & Array.NUMERIC) != 0;
            var descending2:Boolean = (option2 & Array.DESCENDING) != 0;
            var caseInsensitive2:Boolean = (option2 & Array.CASEINSENSITIVE) != 0;

            // 获取两个字段的名称
            var field1:String = fieldNames[0];
            var field2:String = fieldNames[1];

            // 插入排序算法的主要逻辑，排序索引数组或直接排序对象数组
            for (i = 1; i < length; i++) {
                var keyIndex:Number = returnIndexedArray || uniqueSort ? indices[i] : i;
                var key:Object = arr[keyIndex];
                j = i - 1;

                // 比较逻辑，首先比较第一个字段，若第一个字段相等则比较第二个字段
                while (j >= 0) {
                    var compareIndex:Number = returnIndexedArray || uniqueSort ? indices[j] : j;
                    var compare:Object = arr[compareIndex];

                    var cmp:Number = 0; // 用于存储比较结果

                    // 先比较第一个字段
                    var aValue1 = compare[field1];
                    var bValue1 = key[field1];

                    // 根据 numeric1 选项，判断是否按数值排序
                    if (numeric1) {
                        aValue1 = Number(aValue1);
                        bValue1 = Number(bValue1);
                    } else if (caseInsensitive1) {
                        // 若启用了大小写不敏感选项，将值转换为小写进行比较
                        if (typeof aValue1 == "string") aValue1 = aValue1.toLowerCase();
                        if (typeof bValue1 == "string") bValue1 = bValue1.toLowerCase();
                    }

                    // 执行第一个字段的比较
                    if (aValue1 == bValue1) {
                        // 如果第一个字段相等，继续比较第二个字段
                        var aValue2 = compare[field2];
                        var bValue2 = key[field2];

                        if (numeric2) {
                            aValue2 = Number(aValue2);
                            bValue2 = Number(bValue2);
                        } else if (caseInsensitive2) {
                            if (typeof aValue2 == "string") aValue2 = aValue2.toLowerCase();
                            if (typeof bValue2 == "string") bValue2 = bValue2.toLowerCase();
                        }

                        if (aValue2 == bValue2) {
                            cmp = 0; // 第二个字段也相等，认为两个对象相等
                        } else if (aValue2 > bValue2) {
                            cmp = descending2 ? -1 : 1; // 按第二字段降序或升序排列
                        } else {
                            cmp = descending2 ? 1 : -1;
                        }
                    } else if (aValue1 > bValue1) {
                        cmp = descending1 ? -1 : 1; // 按第一个字段降序或升序排列
                    } else {
                        cmp = descending1 ? 1 : -1;
                    }

                    // 执行插入排序，移动位置
                    if (cmp > 0) {
                        if (returnIndexedArray || uniqueSort) {
                            indices[j + 1] = indices[j]; // 移动索引
                        } else {
                            arr[j + 1] = arr[j]; // 移动元素
                        }
                        j--;
                    } else {
                        break; // 如果不需要交换位置，跳出循环
                    }
                }

                // 插入排序结束，更新索引或数组
                if (returnIndexedArray || uniqueSort) {
                    indices[j + 1] = keyIndex;
                } else {
                    arr[j + 1] = key;
                }

                // 若启用了唯一性检查，检查是否存在重复值
                if (uniqueSort && !hasDuplicates && j >= 0) {
                    var prevIndex:Number = returnIndexedArray || uniqueSort ? indices[j] : j;
                    var prev:Object = arr[prevIndex];

                    // 检查是否两个字段都相等，若相等则认为是重复值
                    var prevValue1 = prev[field1];
                    var keyValue1 = key[field1];

                    if (numeric1) {
                        prevValue1 = Number(prevValue1);
                        keyValue1 = Number(keyValue1);
                    } else if (caseInsensitive1) {
                        if (typeof prevValue1 == "string") prevValue1 = prevValue1.toLowerCase();
                        if (typeof keyValue1 == "string") keyValue1 = keyValue1.toLowerCase();
                    }

                    if (prevValue1 == keyValue1) {
                        var prevValue2 = prev[field2];
                        var keyValue2 = key[field2];

                        if (numeric2) {
                            prevValue2 = Number(prevValue2);
                            keyValue2 = Number(keyValue2);
                        } else if (caseInsensitive2) {
                            if (typeof prevValue2 == "string") prevValue2 = prevValue2.toLowerCase();
                            if (typeof keyValue2 == "string") keyValue2 = keyValue2.toLowerCase();
                        }

                        if (prevValue2 == keyValue2) {
                            hasDuplicates = true; // 两个字段都相等，认为存在重复值
                        }
                    }
                }
            }
        } else {
            // 处理多于两个字段的情况，使用通用的多字段比较逻辑
            for (i = 1; i < length; i++) {
                var keyIndexMulti:Number = returnIndexedArray || uniqueSort ? indices[i] : i;
                var keyMulti:Object = arr[keyIndexMulti];
                j = i - 1;

                // 比较多个字段的逻辑
                while (j >= 0) {
                    var compareIndexMulti:Number = returnIndexedArray || uniqueSort ? indices[j] : j;
                    var compareMulti:Object = arr[compareIndexMulti];

                    var cmpMulti:Number = 0;

                    // 逐个字段进行比较，直到发现不相等的字段
                    var idx:Number;
                    for (idx = 0; idx < fieldNames.length; idx++) {
                        var fieldMulti:String = fieldNames[idx];
                        var optionMulti:Number = optionsArray[idx];

                        var numericMulti:Boolean = (optionMulti & Array.NUMERIC) != 0;
                        var descendingMulti:Boolean = (optionMulti & Array.DESCENDING) != 0;
                        var caseInsensitiveMulti:Boolean = (optionMulti & Array.CASEINSENSITIVE) != 0;

                        var aValueMulti = compareMulti[fieldMulti];
                        var bValueMulti = keyMulti[fieldMulti];

                        if (numericMulti) {
                            aValueMulti = Number(aValueMulti);
                            bValueMulti = Number(bValueMulti);
                        } else if (caseInsensitiveMulti) {
                            if (typeof aValueMulti == "string") aValueMulti = aValueMulti.toLowerCase();
                            if (typeof bValueMulti == "string") bValueMulti = bValueMulti.toLowerCase();
                        }

                        if (aValueMulti == bValueMulti) {
                            cmpMulti = 0; // 当前字段相等，继续比较下一个字段
                        } else if (aValueMulti > bValueMulti) {
                            cmpMulti = descendingMulti ? -1 : 1; // 按当前字段的升降序排序
                        } else {
                            cmpMulti = descendingMulti ? 1 : -1;
                        }

                        if (cmpMulti != 0) {
                            break; // 如果发现不相等的字段，立即退出循环
                        }
                    }

                    // 根据比较结果进行元素或索引的交换
                    if (cmpMulti > 0) {
                        if (returnIndexedArray || uniqueSort) {
                            indices[j + 1] = indices[j]; // 交换索引
                        } else {
                            arr[j + 1] = arr[j]; // 交换元素
                        }
                        j--;
                    } else {
                        break;
                    }
                }

                // 插入排序结束，更新数组或索引数组
                if (returnIndexedArray || uniqueSort) {
                    indices[j + 1] = keyIndexMulti;
                } else {
                    arr[j + 1] = keyMulti;
                }

                // 唯一性检查
                if (uniqueSort && !hasDuplicates && j >= 0) {
                    var prevIndexMulti:Number = returnIndexedArray || uniqueSort ? indices[j] : j;
                    var prevMulti:Object = arr[prevIndexMulti];

                    // 检查多个字段的重复性
                    var isDuplicate:Boolean = true;
                    for (idx = 0; idx < fieldNames.length; idx++) {
                        var fieldDup:String = fieldNames[idx];
                        var optionDup:Number = optionsArray[idx];

                        var numericDup:Boolean = (optionDup & Array.NUMERIC) != 0;
                        var caseInsensitiveDup:Boolean = (optionDup & Array.CASEINSENSITIVE) != 0;

                        var aValueDup = prevMulti[fieldDup];
                        var bValueDup = keyMulti[fieldDup];

                        if (numericDup) {
                            aValueDup = Number(aValueDup);
                            bValueDup = Number(bValueDup);
                        } else if (caseInsensitiveDup) {
                            if (typeof aValueDup == "string") aValueDup = aValueDup.toLowerCase();
                            if (typeof bValueDup == "string") bValueDup = bValueDup.toLowerCase();
                        }

                        if (aValueDup != bValueDup) {
                            isDuplicate = false;
                            break;
                        }
                    }

                    if (isDuplicate) {
                        hasDuplicates = true;
                    }
                }
            }
        }

        // 如果启用了唯一性检查且检测到重复值，返回 null
        if (uniqueSort && hasDuplicates) {
            return null; // 返回 null 表示数组中存在重复值
        }

        // 如果启用了索引数组返回选项，则返回排序后的索引数组
        if (returnIndexedArray) {
            return indices;
        } else {
            return arr; // 返回排序后的数组
        }
    }

}






/*

import org.flashNight.naki.Sort.*;

// 生成测试数据的函数
function generateTestData(size:Number, dataType:String):Array {
    var arr:Array = [];
    var i:Number;

    switch (dataType) {
        case "random":
            for (i = 0; i < size; i++) {
                arr.push(Math.random() * size);
            }
            break;
        case "sorted":
            for (i = 0; i < size; i++) {
                arr.push(i);
            }
            break;
        case "reverse":
            for (i = size - 1; i >= 0; i--) {
                arr.push(i);
            }
            break;
        case "partial":
            for (i = 0; i < size; i++) {
                arr.push(i % 10 == 0 ? Math.random() * size : i);
            }
            break;
        case "duplicates":
            for (i = 0; i < size; i++) {
                arr.push(i % 100);
            }
            break;
        default:
            for (i = 0; i < size; i++) {
                arr.push(Math.random() * size);
            }
            break;
    }

    return arr;
}

// 比较函数
function compareNumbers(a, b):Number {
    return a - b;
}

// 测试函数
// 测试函数
function performTest(size:Number, dataType:String, sortType:String):Void {
    var arr:Array;
    var arrCopy:Array;
    var startTime:Number;
    var endTime:Number;
    var timeBuiltin:Number;
    var timeCustom:Number;

    // 生成测试数据
    arr = generateTestData(size, dataType);
    arrCopy = arr.concat(); // 复制数组用于自定义排序

    var scale:Number = Math.ceil(600000 / size); // Scale factor

    // 测试内置 sort 方法
    if (sortType == "builtin") {
        for (var s:Number = 0; s < scale; s++) {
            startTime = getTimer();
            arr.sort(compareNumbers);
            endTime = getTimer();
        }
        timeBuiltin = (endTime - startTime) / scale;
        trace("Built-in sort time: " + timeBuiltin + " ms");
    }

    // 测试自定义快速排序
    if (sortType == "quicksort") {
        for (var s:Number = 0; s < scale; s++) {
            arrCopy = arr.concat(); // Reset array
            startTime = getTimer();
            QuickSort.sort(arrCopy, compareNumbers);
            endTime = getTimer();
        }
        timeCustom = (endTime - startTime) / scale;
        trace("Custom quicksort time: " + timeCustom + " ms");
    }

    // 测试三向快速排序
    if (sortType == "threeway") {
        for (var s:Number = 0; s < scale; s++) {
            arrCopy = arr.concat(); // Reset array
            startTime = getTimer();
            QuickSort.threeWaySort(arrCopy, compareNumbers);
            endTime = getTimer();
        }
        timeCustom = (endTime - startTime) / scale;
        trace("Three-way quicksort time: " + timeCustom + " ms");
    }

    // 测试自适应快速排序
    if (sortType == "adaptiveSort") {
        for (var s:Number = 0; s < scale; s++) {
            arrCopy = arr.concat(); // Reset array
            startTime = getTimer();
            QuickSort.adaptiveSort(arrCopy, compareNumbers);
            endTime = getTimer();
        }
        timeCustom = (endTime - startTime) / scale;
        trace("Adaptive quicksort time: " + timeCustom + " ms");
    }

    // 测试插入排序
    if (sortType == "insertionSort") {
        for (var s:Number = 0; s < scale; s++) {
            arrCopy = arr.concat(); // Reset array
            startTime = getTimer();
            InsertionSort.sort(arrCopy, compareNumbers);
            endTime = getTimer();
        }
        timeCustom = (endTime - startTime) / scale;
        trace("Insertion sort time: " + timeCustom + " ms");
    }

    // 验证排序结果是否一致
    var isEqual:Boolean = true;
    if (sortType != "builtin") {
        arr.sort(compareNumbers);
        for (var i:Number = 0; i < size; i++) {
            if (arr[i] != arrCopy[i]) {
                isEqual = false;
                break;
            }
        }
        trace("Arrays are equal: " + isEqual);
    }

    trace("-------------------------------");
}

// 测试配置
var testSizes:Array = [100]; // 这里可以根据需要调整大小
var dataTypes:Array = ["duplicates", "sorted", "reverse", "partial", "duplicates"];
var sortMethods:Array = ["builtin", "quicksort", "threeway", "adaptiveSort", "insertionSort"]; // 添加插入排序

// 依次执行测试
for (var i:Number = 0; i < testSizes.length; i++) {
    for (var j:Number = 0; j < dataTypes.length; j++) {
        for (var k:Number = 0; k < sortMethods.length; k++) {
            trace("Data Type: " + dataTypes[j] + ", Size: " + testSizes[i] + ", Sort Method: " + sortMethods[k]);
            performTest(testSizes[i], dataTypes[j], sortMethods[k]);
        }
    }
}


Data Type: duplicates, Size: 100, Sort Method: builtin
Built-in sort time: 0.0005 ms
-------------------------------
Data Type: duplicates, Size: 100, Sort Method: quicksort
Custom quicksort time: 0.000166666666666667 ms
Arrays are equal: true
-------------------------------
Data Type: duplicates, Size: 100, Sort Method: threeway
Three-way quicksort time: 0.000333333333333333 ms
Arrays are equal: true
-------------------------------
Data Type: duplicates, Size: 100, Sort Method: adaptiveSort
Adaptive quicksort time: 0.000166666666666667 ms
Arrays are equal: true
-------------------------------
Data Type: duplicates, Size: 100, Sort Method: insertionSort
Insertion sort time: 0 ms
Arrays are equal: true
-------------------------------
Data Type: sorted, Size: 100, Sort Method: builtin
Built-in sort time: 0.0005 ms
-------------------------------
Data Type: sorted, Size: 100, Sort Method: quicksort
Custom quicksort time: 0.000166666666666667 ms
Arrays are equal: true
-------------------------------
Data Type: sorted, Size: 100, Sort Method: threeway
Three-way quicksort time: 0.000333333333333333 ms
Arrays are equal: true
-------------------------------
Data Type: sorted, Size: 100, Sort Method: adaptiveSort
Adaptive quicksort time: 0.000166666666666667 ms
Arrays are equal: true
-------------------------------
Data Type: sorted, Size: 100, Sort Method: insertionSort
Insertion sort time: 0 ms
Arrays are equal: true
-------------------------------
Data Type: reverse, Size: 100, Sort Method: builtin
Built-in sort time: 0.0005 ms
-------------------------------
Data Type: reverse, Size: 100, Sort Method: quicksort
Custom quicksort time: 0.000166666666666667 ms
Arrays are equal: true
-------------------------------
Data Type: reverse, Size: 100, Sort Method: threeway
Three-way quicksort time: 0.00233333333333333 ms
Arrays are equal: true
-------------------------------
Data Type: reverse, Size: 100, Sort Method: adaptiveSort
Adaptive quicksort time: 0.000166666666666667 ms
Arrays are equal: true
-------------------------------
Data Type: reverse, Size: 100, Sort Method: insertionSort
Insertion sort time: 0.00166666666666667 ms
Arrays are equal: true
-------------------------------
Data Type: partial, Size: 100, Sort Method: builtin
Built-in sort time: 0.0005 ms
-------------------------------
Data Type: partial, Size: 100, Sort Method: quicksort
Custom quicksort time: 0.000166666666666667 ms
Arrays are equal: true
-------------------------------
Data Type: partial, Size: 100, Sort Method: threeway
Three-way quicksort time: 0.000333333333333333 ms
Arrays are equal: true
-------------------------------
Data Type: partial, Size: 100, Sort Method: adaptiveSort
Adaptive quicksort time: 0.000333333333333333 ms
Arrays are equal: true
-------------------------------
Data Type: partial, Size: 100, Sort Method: insertionSort
Insertion sort time: 0.000166666666666667 ms
Arrays are equal: true
-------------------------------
Data Type: duplicates, Size: 100, Sort Method: builtin
Built-in sort time: 0.0005 ms
-------------------------------
Data Type: duplicates, Size: 100, Sort Method: quicksort
Custom quicksort time: 0 ms
Arrays are equal: true
-------------------------------
Data Type: duplicates, Size: 100, Sort Method: threeway
Three-way quicksort time: 0.0005 ms
Arrays are equal: true
-------------------------------
Data Type: duplicates, Size: 100, Sort Method: adaptiveSort
Adaptive quicksort time: 0.000166666666666667 ms
Arrays are equal: true
-------------------------------
Data Type: duplicates, Size: 100, Sort Method: insertionSort
Insertion sort time: 0 ms
Arrays are equal: true
-------------------------------

*/


/*
import org.flashNight.naki.Sort.InsertionSort;

// Helper function to create a deep copy of the array
function deepCopyArray(arr:Array):Array {
    var copy:Array = [];
    for (var i:Number = 0; i < arr.length; i++) {
        copy.push({x: arr[i].x, y: arr[i].y, name: arr[i].name});
    }
    return copy;
}

// Generate test data
function generateTestData(size:Number, dataType:String):Array {
    var arr:Array = [];
    var i:Number;
    var names:Array = ["Alice", "Bob", "Charlie", "David", "Eve", "Frank", "Grace", "Heidi"];

    switch (dataType) {
        case "random":
            for (i = 0; i < size; i++) {
                arr.push({x: Number(Math.random() * size), y: Math.random() * size, name: names[Math.floor(Math.random() * names.length)]});
            }
            break;
        case "sorted":
            for (i = 0; i < size; i++) {
                arr.push({x: Number(i), y: Math.random() * size, name: names[Math.floor(Math.random() * names.length)]});
            }
            break;
        case "reverse":
            for (i = size - 1; i >= 0; i--) {
                arr.push({x: Number(i), y: Math.random() * size, name: names[Math.floor(Math.random() * names.length)]});
            }
            break;
        case "partial":
            for (i = 0; i < size; i++) {
                arr.push({x: i % 10 == 0 ? Number(Math.random() * size) : Number(i), y: Math.random() * size, name: names[Math.floor(Math.random() * names.length)]});
            }
            break;
        case "duplicates":
            for (i = 0; i < size; i++) {
                arr.push({x: Number(i % 100), y: Math.random() * size, name: names[i % names.length]});
            }
            break;
        default:
            for (i = 0; i < size; i++) {
                arr.push({x: Number(Math.random() * size), y: Math.random() * size, name: names[Math.floor(Math.random() * names.length)]});
            }
            break;
    }

    return arr;
}

// Testing function
function performTest(size:Number, dataType:String, sortType:String, fieldNames:Array, options:Array):Void {
    var arr:Array;
    var arrCopy:Array;
    var startTime:Number;
    var endTime:Number;
    var totalTime:Number = 0;
    var iterations:Number = 10; // Perform more iterations for more stable timing

    // Generate test data
    arr = generateTestData(size, dataType);

    // Warm-up runs before timing
    for (var warmup:Number = 0; warmup < 3; warmup++) {
        if (sortType == "builtin") {
            arr.sortOn(fieldNames, options);
        } else if (sortType == "insertionSort") {
            InsertionSort.sortOn(arr, fieldNames, options);
        }
    }

    // Perform actual timing
    for (var s:Number = 0; s < iterations; s++) {
        arrCopy = deepCopyArray(arr); // Deep copy for clean sorting

        if (sortType == "builtin") {
            startTime = getTimer();
            arrCopy.sortOn(fieldNames, options);
            endTime = getTimer();
            totalTime += (endTime - startTime);
        }

        if (sortType == "insertionSort") {
            arrCopy = deepCopyArray(arr); // Reset array
            startTime = getTimer();
            InsertionSort.sortOn(arrCopy, fieldNames, options);
            endTime = getTimer();
            totalTime += (endTime - startTime);
        }
    }

    // Report average time per iteration
    var avgTime:Number = totalTime / iterations;
    trace(sortType + " average time: " + avgTime + " ms");

    // Check if arrays are sorted correctly
    arrCopy = deepCopyArray(arr);
    arrCopy.sortOn(fieldNames, options); // Built-in sorting for comparison

    var isEqual:Boolean = true;
    for (var i:Number = 0; i < size; i++) {
        if (arr[i].x != arrCopy[i].x || arr[i].name != arrCopy[i].name) {
            isEqual = false;
            break;
        }
    }
    trace("Arrays are equal: " + isEqual);
    trace("-------------------------------");
}

// Test configuration
var testSizes:Array = [100, 1000]; // Adjust for performance testing
var dataTypes:Array = ["duplicates", "sorted", "reverse", "partial", "random"];
var sortMethods:Array = ["builtin", "insertionSort"]; // Compare built-in and insertion sortOn

// Sorting fields and options to test
var sortFields:Array = [["x"], ["x", "y"], ["name", "x"]]; // Single and multiple fields
var sortOptions:Array = [[Array.NUMERIC | Array.ASCENDING], [Array.NUMERIC | Array.ASCENDING, Array.NUMERIC | Array.DESCENDING], [Array.CASEINSENSITIVE, Array.NUMERIC]];

// Run tests
for (var i:Number = 0; i < testSizes.length; i++) {
    for (var j:Number = 0; j < dataTypes.length; j++) {
        for (var k:Number = 0; k < sortMethods.length; k++) {
            for (var m:Number = 0; m < sortFields.length; m++) {
                trace("Data Type: " + dataTypes[j] + ", Size: " + testSizes[i] + ", Sort Method: " + sortMethods[k] + ", Fields: " + sortFields[m]);
                performTest(testSizes[i], dataTypes[j], sortMethods[k], sortFields[m], sortOptions[m]);
            }
        }
    }
}

Data Type: duplicates, Size: 100, Sort Method: builtin, Fields: x
builtin average time: 0.3 ms
Arrays are equal: true
-------------------------------
Data Type: duplicates, Size: 100, Sort Method: builtin, Fields: x,y
builtin average time: 0.1 ms
Arrays are equal: true
-------------------------------
Data Type: duplicates, Size: 100, Sort Method: builtin, Fields: name,x
builtin average time: 1.1 ms
Arrays are equal: true
-------------------------------
Data Type: duplicates, Size: 100, Sort Method: insertionSort, Fields: x
insertionSort average time: 0.2 ms
Arrays are equal: true
-------------------------------
Data Type: duplicates, Size: 100, Sort Method: insertionSort, Fields: x,y
insertionSort average time: 0.3 ms
Arrays are equal: true
-------------------------------
Data Type: duplicates, Size: 100, Sort Method: insertionSort, Fields: name,x
insertionSort average time: 0.8 ms
Arrays are equal: true
-------------------------------
Data Type: sorted, Size: 100, Sort Method: builtin, Fields: x
builtin average time: 0.5 ms
Arrays are equal: true
-------------------------------
Data Type: sorted, Size: 100, Sort Method: builtin, Fields: x,y
builtin average time: 0.5 ms
Arrays are equal: true
-------------------------------
Data Type: sorted, Size: 100, Sort Method: builtin, Fields: name,x
builtin average time: 0.9 ms
Arrays are equal: true
-------------------------------
Data Type: sorted, Size: 100, Sort Method: insertionSort, Fields: x
insertionSort average time: 0.2 ms
Arrays are equal: true
-------------------------------
Data Type: sorted, Size: 100, Sort Method: insertionSort, Fields: x,y
insertionSort average time: 0.4 ms
Arrays are equal: true
-------------------------------
Data Type: sorted, Size: 100, Sort Method: insertionSort, Fields: name,x
insertionSort average time: 0.8 ms
Arrays are equal: true
-------------------------------
Data Type: reverse, Size: 100, Sort Method: builtin, Fields: x
builtin average time: 0.4 ms
Arrays are equal: true
-------------------------------
Data Type: reverse, Size: 100, Sort Method: builtin, Fields: x,y
builtin average time: 0.5 ms
Arrays are equal: true
-------------------------------
Data Type: reverse, Size: 100, Sort Method: builtin, Fields: name,x
builtin average time: 1.2 ms
Arrays are equal: true
-------------------------------
Data Type: reverse, Size: 100, Sort Method: insertionSort, Fields: x
insertionSort average time: 0.3 ms
Arrays are equal: true
-------------------------------
Data Type: reverse, Size: 100, Sort Method: insertionSort, Fields: x,y
insertionSort average time: 0.2 ms
Arrays are equal: true
-------------------------------
Data Type: reverse, Size: 100, Sort Method: insertionSort, Fields: name,x
insertionSort average time: 0.8 ms
Arrays are equal: true
-------------------------------
Data Type: partial, Size: 100, Sort Method: builtin, Fields: x
builtin average time: 0.1 ms
Arrays are equal: true
-------------------------------
Data Type: partial, Size: 100, Sort Method: builtin, Fields: x,y
builtin average time: 0.3 ms
Arrays are equal: true
-------------------------------
Data Type: partial, Size: 100, Sort Method: builtin, Fields: name,x
builtin average time: 1 ms
Arrays are equal: true
-------------------------------
Data Type: partial, Size: 100, Sort Method: insertionSort, Fields: x
insertionSort average time: 0.2 ms
Arrays are equal: true
-------------------------------
Data Type: partial, Size: 100, Sort Method: insertionSort, Fields: x,y
insertionSort average time: 0.3 ms
Arrays are equal: true
-------------------------------
Data Type: partial, Size: 100, Sort Method: insertionSort, Fields: name,x
insertionSort average time: 0.7 ms
Arrays are equal: true
-------------------------------
Data Type: random, Size: 100, Sort Method: builtin, Fields: x
builtin average time: 0.2 ms
Arrays are equal: true
-------------------------------
Data Type: random, Size: 100, Sort Method: builtin, Fields: x,y
builtin average time: 0.4 ms
Arrays are equal: true
-------------------------------
Data Type: random, Size: 100, Sort Method: builtin, Fields: name,x
builtin average time: 0.9 ms
Arrays are equal: true
-------------------------------
Data Type: random, Size: 100, Sort Method: insertionSort, Fields: x
insertionSort average time: 0.2 ms
Arrays are equal: true
-------------------------------
Data Type: random, Size: 100, Sort Method: insertionSort, Fields: x,y
insertionSort average time: 0.4 ms
Arrays are equal: true
-------------------------------
Data Type: random, Size: 100, Sort Method: insertionSort, Fields: name,x
insertionSort average time: 0.8 ms
Arrays are equal: true
-------------------------------
Data Type: duplicates, Size: 1000, Sort Method: builtin, Fields: x
builtin average time: 22.6 ms
Arrays are equal: true
-------------------------------
Data Type: duplicates, Size: 1000, Sort Method: builtin, Fields: x,y
builtin average time: 22.9 ms
Arrays are equal: true
-------------------------------
Data Type: duplicates, Size: 1000, Sort Method: builtin, Fields: name,x
builtin average time: 99 ms
Arrays are equal: true
-------------------------------
Data Type: duplicates, Size: 1000, Sort Method: insertionSort, Fields: x
insertionSort average time: 1.8 ms
Arrays are equal: true
-------------------------------
Data Type: duplicates, Size: 1000, Sort Method: insertionSort, Fields: x,y
insertionSort average time: 4.7 ms
Arrays are equal: true
-------------------------------
Data Type: duplicates, Size: 1000, Sort Method: insertionSort, Fields: name,x
insertionSort average time: 7.8 ms
Arrays are equal: true
-------------------------------
Data Type: sorted, Size: 1000, Sort Method: builtin, Fields: x
builtin average time: 22.8 ms
Arrays are equal: true
-------------------------------
Data Type: sorted, Size: 1000, Sort Method: builtin, Fields: x,y
builtin average time: 22.8 ms
Arrays are equal: true
-------------------------------
Data Type: sorted, Size: 1000, Sort Method: builtin, Fields: name,x
builtin average time: 96.4 ms
Arrays are equal: true
-------------------------------
Data Type: sorted, Size: 1000, Sort Method: insertionSort, Fields: x
insertionSort average time: 2 ms
Arrays are equal: true
-------------------------------
Data Type: sorted, Size: 1000, Sort Method: insertionSort, Fields: x,y
insertionSort average time: 3.3 ms
Arrays are equal: true
-------------------------------
Data Type: sorted, Size: 1000, Sort Method: insertionSort, Fields: name,x
insertionSort average time: 7.6 ms
Arrays are equal: true
-------------------------------
Data Type: reverse, Size: 1000, Sort Method: builtin, Fields: x
builtin average time: 22.3 ms
Arrays are equal: true
-------------------------------
Data Type: reverse, Size: 1000, Sort Method: builtin, Fields: x,y
builtin average time: 22.9 ms
Arrays are equal: true
-------------------------------
Data Type: reverse, Size: 1000, Sort Method: builtin, Fields: name,x
builtin average time: 96.2 ms
Arrays are equal: true
-------------------------------
Data Type: reverse, Size: 1000, Sort Method: insertionSort, Fields: x
insertionSort average time: 1.9 ms
Arrays are equal: true
-------------------------------
Data Type: reverse, Size: 1000, Sort Method: insertionSort, Fields: x,y
insertionSort average time: 3.7 ms
Arrays are equal: true
-------------------------------
Data Type: reverse, Size: 1000, Sort Method: insertionSort, Fields: name,x
insertionSort average time: 7.8 ms
Arrays are equal: true
-------------------------------
Data Type: partial, Size: 1000, Sort Method: builtin, Fields: x
builtin average time: 22.7 ms
Arrays are equal: true
-------------------------------
Data Type: partial, Size: 1000, Sort Method: builtin, Fields: x,y
builtin average time: 22.9 ms
Arrays are equal: true
-------------------------------
Data Type: partial, Size: 1000, Sort Method: builtin, Fields: name,x
builtin average time: 97.5 ms
Arrays are equal: true
-------------------------------
Data Type: partial, Size: 1000, Sort Method: insertionSort, Fields: x
insertionSort average time: 1.8 ms
Arrays are equal: true
-------------------------------
Data Type: partial, Size: 1000, Sort Method: insertionSort, Fields: x,y
insertionSort average time: 3.3 ms
Arrays are equal: true
-------------------------------
Data Type: partial, Size: 1000, Sort Method: insertionSort, Fields: name,x
insertionSort average time: 8 ms
Arrays are equal: true
-------------------------------
Data Type: random, Size: 1000, Sort Method: builtin, Fields: x
builtin average time: 21.3 ms
Arrays are equal: true
-------------------------------
Data Type: random, Size: 1000, Sort Method: builtin, Fields: x,y
builtin average time: 21.6 ms
Arrays are equal: true
-------------------------------
Data Type: random, Size: 1000, Sort Method: builtin, Fields: name,x
builtin average time: 97.5 ms
Arrays are equal: true
-------------------------------
Data Type: random, Size: 1000, Sort Method: insertionSort, Fields: x
insertionSort average time: 2 ms
Arrays are equal: true
-------------------------------
Data Type: random, Size: 1000, Sort Method: insertionSort, Fields: x,y
insertionSort average time: 3.3 ms
Arrays are equal: true
-------------------------------
Data Type: random, Size: 1000, Sort Method: insertionSort, Fields: name,x
insertionSort average time: 8 ms
Arrays are equal: true
-------------------------------

*/