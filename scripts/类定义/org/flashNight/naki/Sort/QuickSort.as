/*

class org.flashNight.naki.Sort.QuickSort

# QuickSort 排序类使用指南

## 介绍
`QuickSort` 类实现了三种排序算法：标准快速排序、三路快速排序和自适应排序。自适应排序能够根据数据集的特点自动选择合适的排序算法，以保证最佳的排序性能。

## 方法概述

1. **sort(arr:Array, compareFunction:Function)**:
   - 标准快速排序的实现。适用于一般的随机数据集或规模较小的无序数据。
   - **使用场景**：
     - 当数据规模较小时（如 100 以下）或数据类型较为随机时，标准快速排序表现稳定。
     - 无大量重复数据的场景。

2. **threeWaySort(arr:Array, compareFunction:Function)**:
   - 三路快速排序，专为处理大量重复元素优化。它通过将数组分为三部分（小于基准值、等于基准值、大于基准值）来减少不必要的比较和交换操作。
   - **使用场景**：
     - 当数据集中包含大量重复元素时（如 `duplicates` 数据类型），三路快速排序表现最佳。
     - **避免在完全逆序的数据上使用**，在这种情况下表现较差。

3. **adaptiveSort(arr:Array, compareFunction:Function)**:
   - 自适应排序，根据数据规模和重复元素比例自动选择标准快速排序或三路快速排序。是默认推荐使用的方法。
   - **使用场景**：
     - 对任何规模或类型的数据集均适用。
     - 无需手动选择排序算法，系统自动选择最优方案。
     - 对包含大量重复元素的数据（如 `duplicates`）或无序、部分有序的数据都能自动进行优化。

## 方法使用示例

```actionscript
import org.flashNight.naki.Sort.QuickSort;

// 假设我们有一个包含随机数的数组
var arr:Array = [3, 1, 4, 1, 5, 9, 2, 6, 5, 3, 5];

// 调用标准快速排序
var sortedArray:Array = QuickSort.sort(arr);

// 调用三路快速排序
var sortedArrayThreeWay:Array = QuickSort.threeWaySort(arr);

// 调用自适应排序（推荐）
var sortedArrayAdaptive:Array = QuickSort.adaptiveSort(arr);
```

## 性能建议

1. **优先使用 adaptiveSort**：
   - 该方法能够自动适应数据集的特点，选择最优的排序算法。在大多数场景下，自适应排序能够提供一致的高性能，尤其是在处理不确定的数据集时表现最佳。
   
2. **在明确数据类型的情况下使用指定排序算法**：
   - 如果数据集中有大量重复元素（如大规模的 `duplicates` 类型数据），可以考虑使用 `threeWaySort` 进行排序。
   - 对于小规模且较为无序的数据集，`sort`（标准快速排序）通常能提供非常快速的排序速度。

3. **避免在完全逆序的数据上使用 threeWaySort**：
   - 三路快速排序在处理完全逆序的数组时，性能表现较差，建议在这种情况下使用 `adaptiveSort`。

## 性能表现总结

- 对于小规模数据（如长度为 10），三种排序算法的表现差异不大。
- 对于中等规模数据（如长度为 100），`adaptiveSort` 在所有数据类型下表现出稳定的高效性。
- 对于大规模数据（如长度为 1000），`adaptiveSort` 在处理不同数据类型时仍然表现最佳，而 `threeWaySort` 在处理大量重复元素的数据时效果尤为突出。

---

通过以上指南，您可以根据数据集的特性选择合适的排序方法，同时在不确定数据类型时优先选择 `adaptiveSort` 以获得最佳的排序性能和一致性。

*/
import org.flashNight.naki.Sort.*;

class org.flashNight.naki.Sort.QuickSort {

    /**
     * 标准快速排序算法的实现。
     * 
     * 快速排序是一种基于“分而治之”的经典排序算法。它通过选择一个基准值（通常为数组的中间元素），
     * 然后将数组分为两部分：一部分比基准值小，另一部分比基准值大。接着递归地对这两部分进行排序。
     * 快速排序的平均时间复杂度为 O(n log n)，但在某些最坏情况下（如完全逆序数组）会退化为 O(n²)。
     * 本实现使用了非递归的方式，通过栈来模拟递归，以避免递归带来的栈溢出风险。同时，对于小数组使用插入排序，
     * 以提高小数组的排序效率。
     *
     * @param arr 要排序的数组。
     * @param compareFunction 自定义的比较函数，可用于定义排序的顺序。若未提供，则使用默认的数值比较。
     * @return 排序后的数组。
     */
    public static function sort(arr:Array, compareFunction:Function):Array {
        var length:Number = arr.length;
        if (length <= 1) {
            // 如果数组长度小于等于1，直接返回数组，无需排序
            return arr;
        }

        // 定义局部比较函数，以减少参数传递的开销
        var compare:Function;
        var defaultCompare:Boolean = false;
        if (compareFunction != undefined) {
            compare = compareFunction; // 使用自定义比较函数
        } else {
            defaultCompare = true; // 使用默认的数值比较
            compare = function(a, b):Number {
                return a - b; // 返回数值差，正数表示 a 大于 b，负数表示 a 小于 b
            };
        }

        // 使用栈模拟递归，避免递归调用带来的栈深度问题
        var stack:Array = new Array(2 * length); // 预分配栈空间，用于存储左右边界
        var sp:Number = 0; // 栈指针

        var left:Number = 0;
        var right:Number = length - 1;

        // 初始左右边界入栈
        stack[sp++] = left;
        stack[sp++] = right;

        while (sp > 0) {
            // 从栈中弹出当前的左右边界
            right = Number(stack[--sp]);
            left = Number(stack[--sp]);

            // 如果子数组长度小于等于 10，使用插入排序，因为插入排序在小数组上效率更高
            if (right - left <= 10) {
                var i:Number, j:Number, key;
                for (i = left + 1; i <= right; i++) {
                    key = arr[i];
                    j = i - 1;
                    if (defaultCompare) {
                        // 默认数值比较
                        while (j >= left && arr[j] > key) {
                            arr[j + 1] = arr[j];
                            j--;
                        }
                    } else {
                        // 使用自定义的比较函数
                        while (j >= left && compare(arr[j], key) > 0) {
                            arr[j + 1] = arr[j];
                            j--;
                        }
                    }
                    arr[j + 1] = key; // 将 key 插入到正确位置
                }
                continue; // 处理下一个子数组
            }

            // 选择基准值，使用子数组的中间元素
            var pivotIndex:Number = left + ((right - left) >> 1);
            var pivotValue = arr[pivotIndex];

            // 将基准值移至数组末尾，便于后续分区操作
            var temp = arr[pivotIndex];
            arr[pivotIndex] = arr[right];
            arr[right] = temp;

            var storeIndex:Number = left;
            var i:Number;

            // 分区操作：将比基准值小的元素移到左边，比基准值大的移到右边
            if (defaultCompare) {
                // 默认数值比较
                for (i = left; i < right; i++) {
                    if (arr[i] < pivotValue) {
                        temp = arr[i];
                        arr[i] = arr[storeIndex];
                        arr[storeIndex] = temp;
                        storeIndex++;
                    }
                }
            } else {
                // 使用自定义比较函数
                for (i = left; i < right; i++) {
                    if (compare(arr[i], pivotValue) < 0) {
                        temp = arr[i];
                        arr[i] = arr[storeIndex];
                        arr[storeIndex] = temp;
                        storeIndex++;
                    }
                }
            }

            // 将基准值放回正确位置
            temp = arr[storeIndex];
            arr[storeIndex] = arr[right];
            arr[right] = temp;

            // 优先处理较小的子数组，减少栈深度，避免栈溢出
            var leftSize:Number = storeIndex - 1 - left;
            var rightSize:Number = right - (storeIndex + 1);

            if (leftSize > rightSize) {
                if (left < storeIndex - 1) {
                    stack[sp++] = left;
                    stack[sp++] = storeIndex - 1;
                }
                if (storeIndex + 1 < right) {
                    stack[sp++] = storeIndex + 1;
                    stack[sp++] = right;
                }
            } else {
                if (storeIndex + 1 < right) {
                    stack[sp++] = storeIndex + 1;
                    stack[sp++] = right;
                }
                if (left < storeIndex - 1) {
                    stack[sp++] = left;
                    stack[sp++] = storeIndex - 1;
                }
            }
        }

        return arr; // 返回排序后的数组
    }

    /**
     * 自适应排序方法，根据数据的特点选择最优的排序算法。
     * 
     * 该方法首先根据数组的大小判断是否使用内建排序。对于长度较小的数组，直接调用内建的 Array.sort 方法。
     * 然后根据数组中重复元素的比例选择排序算法：当数组包含大量重复元素时，三路快速排序（Three-way Quicksort）表现更好，
     * 因为它在处理重复数据时可以有效减少不必要的比较。当重复元素较少时，使用标准快速排序。
     *
     * @param arr 要排序的数组。
     * @param compareFunction 自定义的比较函数，定义排序顺序。
     * @return 排序后的数组。
     */
    public static function adaptiveSort(arr:Array, compareFunction:Function):Array {
        var length:Number = arr.length;
        if (length <= 1) {
            // 数组为空或仅包含一个元素时，无需排序
            return arr;
        }

        // 定义小数组的长度阈值
        var smallArrayThreshold:Number = 50; // 小于等于50个元素的数组，直接使用插入排序
        var duplicateRatioThreshold:Number = 0.9; // 重复元素比例超过90%，使用内建排序

        // 定义局部比较函数
        var compare:Function;
        var defaultCompare:Boolean = false;
        if (compareFunction != undefined) {
            compare = compareFunction; // 使用自定义比较函数
        } else {
            defaultCompare = true; // 默认数值比较
            compare = function(a, b):Number {
                return a - b;
            };
        }

        // 第一步：判断数组长度
        if (length <= smallArrayThreshold) {
            // 数组较小，使用内建排序以提高效率
            InsertionSort.sort(arr,compare);
            return arr;
        }

        // 第二步：估算数组中的重复元素比例
        var uniqueElements:Object = {}; // 用于存储数组中的唯一元素
        var uniqueCount:Number = 0; // 记录唯一元素的数量
        var sampleSize:Number = Math.min(length, 1000); // 采样最多1000个元素进行估算

        for (var i:Number = 0; i < sampleSize; i++) {
            var elem = arr[i];
            if (uniqueElements[elem] == undefined) {
                uniqueElements[elem] = true;
                uniqueCount++;
            }
        }

        var uniquenessRatio:Number = uniqueCount / sampleSize; // 计算唯一元素比例
        var duplicateRatio:Number = 1 - uniquenessRatio; // 计算重复元素比例

        // 第三步：根据重复比例选择排序算法
        if (duplicateRatio >= duplicateRatioThreshold) {
            // 重复元素比例高，使用内建排序，处理效率更高
            arr.sort(compare);
            return arr;
        } else if (duplicateRatio >= 0.5) {
            // 重复元素较多，使用三路快速排序，专门优化大量重复数据的场景
            return threeWaySort(arr, compare);
        } else {
            // 重复元素较少，使用标准快速排序
            return sort(arr, compare);
        }
    }

    /**
     * 三路快速排序算法。
     * 
     * 三路快速排序是一种针对包含大量重复元素的数组的优化算法。它将数组分为三部分：
     * 小于基准值的部分、等于基准值的部分和大于基准值的部分。通过减少不必要的比较和交换操作，
     * 三路快速排序在处理重复元素时性能显著优于标准快速排序。
     *
     * @param arr 要排序的数组。
     * @param compareFunction 自定义的比较函数，定义排序顺序。
     * @return 排序后的数组。
     */
    public static function threeWaySort(arr:Array, compareFunction:Function):Array {
        var length:Number = arr.length;
        if (length <= 1) {
            // 数组为空或仅包含一个元素时，无需排序
            return arr;
        }

        // 定义局部比较函数
        var compare:Function;
        var defaultCompare:Boolean = false;
        if (compareFunction != undefined) {
            compare = compareFunction; // 使用自定义比较函数
        } else {
            defaultCompare = true; // 默认数值比较
            compare = function(a, b):Number {
                return a - b;
            };
        }

        // 使用栈来模拟递归，避免递归调用的栈深度问题
        var stack:Array = new Array(2 * length);
        var sp:Number = 0;

        var leftIndex:Number = 0;
        var rightIndex:Number = length - 1;

        // 初始左右边界入栈
        stack[sp++] = leftIndex;
        stack[sp++] = rightIndex;

        while (sp > 0) {
            // 出栈左右边界
            rightIndex = Number(stack[--sp]);
            leftIndex = Number(stack[--sp]);

            if (rightIndex <= leftIndex) {
                // 如果子数组为空或只有一个元素，跳过排序
                continue;
            }

            // 小数组使用插入排序，提升性能
            if (rightIndex - leftIndex <= 10) {
                var i:Number, j:Number, key;
                for (i = leftIndex + 1; i <= rightIndex; i++) {
                    key = arr[i];
                    j = i - 1;
                    if (defaultCompare) {
                        while (j >= leftIndex && arr[j] > key) {
                            arr[j + 1] = arr[j];
                            j--;
                        }
                    } else {
                        while (j >= leftIndex && compare(arr[j], key) > 0) {
                            arr[j + 1] = arr[j];
                            j--;
                        }
                    }
                    arr[j + 1] = key;
                }
                continue;
            }

            // 三路分区
            var lessThanIndex:Number = leftIndex; // 小于基准值的部分
            var greaterThanIndex:Number = rightIndex; // 大于基准值的部分
            var currentIndex:Number = leftIndex + 1; // 当前遍历元素的下标

            var pivotValue = arr[leftIndex]; // 基准值为数组的左端点元素

            while (currentIndex <= greaterThanIndex) {
                var cmp:Number;
                if (defaultCompare) {
                    cmp = arr[currentIndex] - pivotValue; // 计算当前元素与基准值的差异
                } else {
                    cmp = compare(arr[currentIndex], pivotValue);
                }

                if (cmp < 0) {
                    // 当前元素小于基准值，交换至左边区域
                    if (lessThanIndex != currentIndex) {
                        var temp = arr[lessThanIndex];
                        arr[lessThanIndex] = arr[currentIndex];
                        arr[currentIndex] = temp;
                    }
                    lessThanIndex++;
                    currentIndex++;
                } else if (cmp > 0) {
                    // 当前元素大于基准值，交换至右边区域
                    var temp = arr[currentIndex];
                    arr[currentIndex] = arr[greaterThanIndex];
                    arr[greaterThanIndex] = temp;
                    greaterThanIndex--;
                } else {
                    // 当前元素等于基准值，继续遍历
                    currentIndex++;
                }
            }

            // 优先处理较小的子数组，减少栈深度
            var leftSubarraySize:Number = lessThanIndex - leftIndex;
            var rightSubarraySize:Number = rightIndex - greaterThanIndex;

            if (leftSubarraySize < rightSubarraySize) {
                if (leftIndex < lessThanIndex - 1) {
                    stack[sp++] = leftIndex;
                    stack[sp++] = lessThanIndex - 1;
                }
                if (greaterThanIndex + 1 < rightIndex) {
                    stack[sp++] = greaterThanIndex + 1;
                    stack[sp++] = rightIndex;
                }
            } else {
                if (greaterThanIndex + 1 < rightIndex) {
                    stack[sp++] = greaterThanIndex + 1;
                    stack[sp++] = rightIndex;
                }
                if (leftIndex < lessThanIndex - 1) {
                    stack[sp++] = leftIndex;
                    stack[sp++] = lessThanIndex - 1;
                }
            }
        }

        return arr; // 返回排序后的数组
    }

    /**
     * 增强版快速排序，支持：
     * 1. 小数组切换为插入排序
     * 2. 随机化 pivot / 三数取中 pivot
     * 3. 双轴快速排序
     * 
     * @param arr               要排序的数组
     * @param compareFunction   自定义比较函数，不提供则使用默认数值比较
     * @param useDualPivot      是否启用双轴快速排序，true则在大规模子数组上使用双轴分区
     * @param pivotStrategy     pivot选择策略，可选值 "random" 或 "median3"
     * @return                  排好序的数组（原地排序）
     */
    public static function enhancedQuickSort(
        arr:Array,
        compareFunction:Function,
        useDualPivot:Boolean,
        pivotStrategy:String
    ):Array {
        var length:Number = arr.length;
        pivotStrategy = pivotStrategy || "random";
        if (length <= 1) {
            return arr;
        }

        // ----------------------
        // 1. 定义插入排序阈值
        //    子数组长度<=此阈值则切换到插入排序
        // ----------------------
        var INSERTION_THRESHOLD:Number = 10;

        // ----------------------
        // 2. 定义比较函数
        // ----------------------
        var compare:Function;
        var defaultCompare:Boolean = false;
        if (compareFunction != undefined) {
            compare = compareFunction;
        } else {
            defaultCompare = true; // 默认数值比较
            compare = function(a, b):Number {
                return a - b; // a>b则返回正数，a<b则返回负数
            };
        }

        // ----------------------
        // 3. 准备迭代所需的栈
        //    和原先 sort 函数类似
        // ----------------------
        var stack:Array = new Array(2 * length);
        var sp:Number = 0; // stack pointer

        // 初始边界
        var left:Number = 0;
        var right:Number = length - 1;

        // 入栈
        stack[sp++] = left;
        stack[sp++] = right;

        // ----------------------
        // 4. 迭代处理
        // ----------------------
        while (sp > 0) {
            right = Number(stack[--sp]);
            left = Number(stack[--sp]);

            // 子区间长度
            var size:Number = right - left + 1;

            // ----------- 4.1 小数组用插入排序 -----------
            if (size <= INSERTION_THRESHOLD) {
                insertionSort(arr, left, right, compare, defaultCompare);
                continue;
            }

            // ----------- 4.2 大数组 -> 根据需求选择 单轴/双轴 -----------
            if (useDualPivot) {
                // ---------- (A) 双轴快速排序 ----------
                // 在此示例中，选取最左元素和最右元素为 pivot1 和 pivot2
                // 如果 pivot1 > pivot2，则交换
                var pivot1 = arr[left];
                var pivot2 = arr[right];
                if (defaultCompare) {
                    if (pivot1 > pivot2) {
                        swap(arr, left, right);
                        pivot1 = arr[left];
                        pivot2 = arr[right];
                    }
                } else {
                    if (compare(pivot1, pivot2) > 0) {
                        swap(arr, left, right);
                        pivot1 = arr[left];
                        pivot2 = arr[right];
                    }
                }

                // 双轴分区过程
                var i:Number = left + 1;
                var leftIndex:Number = left + 1;     // 小于 pivot1 的区域边界
                var rightIndex:Number = right - 1;    // 大于 pivot2 的区域边界

                while (i <= rightIndex) {
                    var cmp1:Number;
                    var cmp2:Number;
                    if (defaultCompare) {
                        cmp1 = arr[i] - pivot1;
                        cmp2 = arr[i] - pivot2;
                    } else {
                        cmp1 = compare(arr[i], pivot1);
                        cmp2 = compare(arr[i], pivot2);
                    }

                    if (cmp1 < 0) {
                        swap(arr, i, leftIndex);
                        leftIndex++;
                        i++;
                    } else if (cmp2 > 0) {
                        swap(arr, i, rightIndex);
                        rightIndex--;
                    } else {
                        i++;
                    }
                }

                // 把 pivot1、pivot2 放回正确位置
                leftIndex--;
                rightIndex++;

                swap(arr, left, leftIndex);
                swap(arr, right, rightIndex);

                // 现在 arr[left..leftIndex-1] < pivot1
                //      arr[leftIndex] == pivot1
                //      arr[leftIndex+1..rightIndex-1] 在 pivot1 和 pivot2 之间
                //      arr[rightIndex] == pivot2
                //      arr[rightIndex+1..right] > pivot2

                // ----------- 入栈子区间（小的先入栈）-----------
                // 子区间1: left..(leftIndex-1)
                // 子区间2: (leftIndex+1)..(rightIndex-1)
                // 子区间3: (rightIndex+1)..right
                pushSubArray(stack, left, leftIndex-1, sp);
                sp += 2;
                pushSubArray(stack, leftIndex+1, rightIndex-1, sp);
                sp += 2;
                pushSubArray(stack, rightIndex+1, right, sp);
                sp += 2;

            } else {
                // ---------- (B) 单轴快速排序 ----------
                // 先根据 pivotStrategy 选pivotIndex
                var pivotIndex:Number = selectPivotIndex(arr, left, right, pivotStrategy, compare, defaultCompare);
                var pivotValue = arr[pivotIndex];
                
                // 将 pivot 放到 right 位置，统一做分区
                swap(arr, pivotIndex, right);

                // 分区
                var storeIndex:Number = left;

                if (defaultCompare) {
                    for (var idx:Number = left; idx < right; idx++) {
                        if (arr[idx] < pivotValue) {
                            swap(arr, idx, storeIndex);
                            storeIndex++;
                        }
                    }
                } else {
                    for (idx = left; idx < right; idx++) {
                        if (compare(arr[idx], pivotValue) < 0) {
                            swap(arr, idx, storeIndex);
                            storeIndex++;
                        }
                    }
                }

                // 把 pivot 放回正确位置
                swap(arr, storeIndex, right);

                // ----------- 入栈子区间（小的先入栈）-----------
                // 子区间1: left..(storeIndex-1)
                // 子区间2: (storeIndex+1)..right
                var leftSize:Number = storeIndex - 1 - left;
                var rightSize:Number = right - (storeIndex + 1);

                if (leftSize < rightSize) {
                    // 先压左区间
                    if (left < storeIndex - 1) {
                        stack[sp++] = left;
                        stack[sp++] = storeIndex - 1;
                    }
                    // 后压右区间
                    if (storeIndex + 1 < right) {
                        stack[sp++] = storeIndex + 1;
                        stack[sp++] = right;
                    }
                } else {
                    // 先压右区间
                    if (storeIndex + 1 < right) {
                        stack[sp++] = storeIndex + 1;
                        stack[sp++] = right;
                    }
                    // 后压左区间
                    if (left < storeIndex - 1) {
                        stack[sp++] = left;
                        stack[sp++] = storeIndex - 1;
                    }
                }
            }
        }

        return arr;
    }

    /* ====================== 辅助函数们 ====================== */

    /**
     * 对小区间使用的插入排序
     */
    private static function insertionSort(arr:Array, left:Number, right:Number, compare:Function, defaultCompare:Boolean):Void {
        for (var i:Number = left + 1; i <= right; i++) {
            var key = arr[i];
            var j:Number = i - 1;
            if (defaultCompare) {
                while (j >= left && arr[j] > key) {
                    arr[j + 1] = arr[j];
                    j--;
                }
            } else {
                while (j >= left && compare(arr[j], key) > 0) {
                    arr[j + 1] = arr[j];
                    j--;
                }
            }
            arr[j + 1] = key;
        }
    }

    /**
     * 根据 pivotStrategy 返回 pivotIndex
     *   - "random"  : 从 [left, right] 区间随机挑选
     *   - "median3" : 三数取中（left, mid, right）
     */
    private static function selectPivotIndex(
        arr:Array,
        left:Number,
        right:Number,
        pivotStrategy:String,
        compare:Function,
        defaultCompare:Boolean
    ):Number {
        if (pivotStrategy == "median3") {
            return medianOfThree(arr, left, right, compare, defaultCompare);
        } else {
            // 默认使用随机 pivot
            var pivotIndex:Number = Math.floor(Math.random() * (right - left + 1)) + left;
            return pivotIndex;
        }
    }

    /**
     * 三数取中法，返回三者中值对应的下标
     */
    private static function medianOfThree(
        arr:Array,
        left:Number,
        right:Number,
        compare:Function,
        defaultCompare:Boolean
    ):Number {
        var mid:Number = left + ((right - left) >> 1);

        var a = arr[left];
        var b = arr[mid];
        var c = arr[right];

        // 为了比较方便，先做一个函数把值转为可比较大小
        function cmpVal(x, y):Number {
            return defaultCompare ? (x - y) : compare(x, y);
        }

        // 比较 a, b, c，大体思路：
        // 1. 先比较 a,b 交换成有序
        // 2. 再比较 a,c 交换
        // 3. 再比较 b,c 交换
        // 最后 a 就是最小，c 就是最大，b 就是中值
        if (cmpVal(a, b) > 0) {
            swap(arr, left, mid); // 交换 a,b
            a = arr[left];
            b = arr[mid];
        }
        if (cmpVal(a, c) > 0) {
            swap(arr, left, right); // 交换 a,c
            a = arr[left];
            c = arr[right];
        }
        if (cmpVal(b, c) > 0) {
            swap(arr, mid, right); // 交换 b,c
            b = arr[mid];
            c = arr[right];
        }
        // 此时，b就是三数中值
        return mid;
    }

    /**
     * 入栈辅助函数：把子区间 [l, r] 压到 stack 的下一个可用位置
     */
    private static function pushSubArray(stack:Array, l:Number, r:Number, sp:Number):Void {
        stack[sp] = l;
        stack[sp + 1] = r;
    }

    /**
     * 交换 arr[i], arr[j]
     */
    private static function swap(arr:Array, i:Number, j:Number):Void {
        var temp = arr[i];
        arr[i] = arr[j];
        arr[j] = temp;
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
                if (i % 10 == 0) {
                    arr.push(Math.random() * size);
                } else {
                    arr.push(i);
                }
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

    // 测试内置 sort 方法
    if (sortType == "builtin") {
        startTime = getTimer();
        arr.sort(compareNumbers);
        endTime = getTimer();
        timeBuiltin = endTime - startTime;
        trace("Built-in sort time: " + timeBuiltin + " ms");
    }
    
    // 测试自定义快速排序
    if (sortType == "quicksort") {
        startTime = getTimer();
        QuickSort.sort(arrCopy, compareNumbers);
        endTime = getTimer();
        timeCustom = endTime - startTime;
        trace("Custom quicksort time: " + timeCustom + " ms");
    }

    // 测试三向快速排序
    if (sortType == "threeway") {
        startTime = getTimer();
        QuickSort.threeWaySort(arrCopy, compareNumbers);
        endTime = getTimer();
        timeCustom = endTime - startTime;
        trace("Three-way quicksort time: " + timeCustom + " ms");
    }
	
	   // 测试三向快速排序
    if (sortType == "adaptiveSort") {
        startTime = getTimer();
        QuickSort.adaptiveSort(arrCopy, compareNumbers);
        endTime = getTimer();
        timeCustom = endTime - startTime;
        trace("adaptiveSort quicksort time: " + timeCustom + " ms");
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
var testSizes:Array = [100,1000,5000];
var dataTypes:Array = ["duplicates", "sorted", "reverse", "partial", "duplicates"];
var sortMethods:Array = ["builtin", "quicksort", "threeway", "adaptiveSort"];

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
Built-in sort time: 3 ms
-------------------------------
Data Type: duplicates, Size: 100, Sort Method: quicksort
Custom quicksort time: 1 ms
Arrays are equal: true
-------------------------------
Data Type: duplicates, Size: 100, Sort Method: threeway
Three-way quicksort time: 3 ms
Arrays are equal: true
-------------------------------
Data Type: duplicates, Size: 100, Sort Method: adaptiveSort
adaptiveSort quicksort time: 1 ms
Arrays are equal: true
-------------------------------
Data Type: sorted, Size: 100, Sort Method: builtin
Built-in sort time: 3 ms
-------------------------------
Data Type: sorted, Size: 100, Sort Method: quicksort
Custom quicksort time: 1 ms
Arrays are equal: true
-------------------------------
Data Type: sorted, Size: 100, Sort Method: threeway
Three-way quicksort time: 3 ms
Arrays are equal: true
-------------------------------
Data Type: sorted, Size: 100, Sort Method: adaptiveSort
adaptiveSort quicksort time: 1 ms
Arrays are equal: true
-------------------------------
Data Type: reverse, Size: 100, Sort Method: builtin
Built-in sort time: 4 ms
-------------------------------
Data Type: reverse, Size: 100, Sort Method: quicksort
Custom quicksort time: 1 ms
Arrays are equal: true
-------------------------------
Data Type: reverse, Size: 100, Sort Method: threeway
Three-way quicksort time: 13 ms
Arrays are equal: true
-------------------------------
Data Type: reverse, Size: 100, Sort Method: adaptiveSort
adaptiveSort quicksort time: 2 ms
Arrays are equal: true
-------------------------------
Data Type: partial, Size: 100, Sort Method: builtin
Built-in sort time: 1 ms
-------------------------------
Data Type: partial, Size: 100, Sort Method: quicksort
Custom quicksort time: 1 ms
Arrays are equal: true
-------------------------------
Data Type: partial, Size: 100, Sort Method: threeway
Three-way quicksort time: 3 ms
Arrays are equal: true
-------------------------------
Data Type: partial, Size: 100, Sort Method: adaptiveSort
adaptiveSort quicksort time: 1 ms
Arrays are equal: true
-------------------------------
Data Type: duplicates, Size: 100, Sort Method: builtin
Built-in sort time: 3 ms
-------------------------------
Data Type: duplicates, Size: 100, Sort Method: quicksort
Custom quicksort time: 1 ms
Arrays are equal: true
-------------------------------
Data Type: duplicates, Size: 100, Sort Method: threeway
Three-way quicksort time: 2 ms
Arrays are equal: true
-------------------------------
Data Type: duplicates, Size: 100, Sort Method: adaptiveSort
adaptiveSort quicksort time: 0 ms
Arrays are equal: true
-------------------------------
Data Type: duplicates, Size: 1000, Sort Method: builtin
Built-in sort time: 14 ms
-------------------------------
Data Type: duplicates, Size: 1000, Sort Method: quicksort
Custom quicksort time: 105 ms
Arrays are equal: true
-------------------------------
Data Type: duplicates, Size: 1000, Sort Method: threeway
Three-way quicksort time: 24 ms
Arrays are equal: true
-------------------------------
Data Type: duplicates, Size: 1000, Sort Method: adaptiveSort
adaptiveSort quicksort time: 14 ms
Arrays are equal: true
-------------------------------
Data Type: sorted, Size: 1000, Sort Method: builtin
Built-in sort time: 285 ms
-------------------------------
Data Type: sorted, Size: 1000, Sort Method: quicksort
Custom quicksort time: 14 ms
Arrays are equal: true
-------------------------------
Data Type: sorted, Size: 1000, Sort Method: threeway
Three-way quicksort time: 91 ms
Arrays are equal: true
-------------------------------
Data Type: sorted, Size: 1000, Sort Method: adaptiveSort
adaptiveSort quicksort time: 15 ms
Arrays are equal: true
-------------------------------
Data Type: reverse, Size: 1000, Sort Method: builtin
Built-in sort time: 301 ms
-------------------------------
Data Type: reverse, Size: 1000, Sort Method: quicksort
Custom quicksort time: 17 ms
Arrays are equal: true
-------------------------------
Data Type: reverse, Size: 1000, Sort Method: threeway
Three-way quicksort time: 1342 ms
Arrays are equal: true
-------------------------------
Data Type: reverse, Size: 1000, Sort Method: adaptiveSort
adaptiveSort quicksort time: 19 ms
Arrays are equal: true
-------------------------------
Data Type: partial, Size: 1000, Sort Method: builtin
Built-in sort time: 20 ms
-------------------------------
Data Type: partial, Size: 1000, Sort Method: quicksort
Custom quicksort time: 19 ms
Arrays are equal: true
-------------------------------
Data Type: partial, Size: 1000, Sort Method: threeway
Three-way quicksort time: 43 ms
Arrays are equal: true
-------------------------------
Data Type: partial, Size: 1000, Sort Method: adaptiveSort
adaptiveSort quicksort time: 20 ms
Arrays are equal: true
-------------------------------
Data Type: duplicates, Size: 1000, Sort Method: builtin
Built-in sort time: 14 ms
-------------------------------
Data Type: duplicates, Size: 1000, Sort Method: quicksort
Custom quicksort time: 110 ms
Arrays are equal: true
-------------------------------
Data Type: duplicates, Size: 1000, Sort Method: threeway
Three-way quicksort time: 24 ms
Arrays are equal: true
-------------------------------
Data Type: duplicates, Size: 1000, Sort Method: adaptiveSort
adaptiveSort quicksort time: 13 ms
Arrays are equal: true
-------------------------------
Data Type: duplicates, Size: 5000, Sort Method: builtin
Built-in sort time: 126 ms
-------------------------------
Data Type: duplicates, Size: 5000, Sort Method: quicksort
Custom quicksort time: 740 ms
Arrays are equal: true
-------------------------------
Data Type: duplicates, Size: 5000, Sort Method: threeway
Three-way quicksort time: 244 ms
Arrays are equal: true
-------------------------------
Data Type: duplicates, Size: 5000, Sort Method: adaptiveSort
adaptiveSort quicksort time: 124 ms
Arrays are equal: true
-------------------------------
Data Type: sorted, Size: 5000, Sort Method: builtin
Built-in sort time: 7284 ms
-------------------------------
Data Type: sorted, Size: 5000, Sort Method: quicksort
Custom quicksort time: 86 ms
Arrays are equal: true
-------------------------------
Data Type: sorted, Size: 5000, Sort Method: threeway
Three-way quicksort time: 933 ms
Arrays are equal: true
-------------------------------
Data Type: sorted, Size: 5000, Sort Method: adaptiveSort
adaptiveSort quicksort time: 88 ms
Arrays are equal: true
-------------------------------
Data Type: reverse, Size: 5000, Sort Method: builtin
Built-in sort time: 7451 ms
-------------------------------
Data Type: reverse, Size: 5000, Sort Method: quicksort
Custom quicksort time: 115 ms
Arrays are equal: true
-------------------------------
Data Type: reverse, Size: 5000, Sort Method: threeway
Three-way quicksort time: 33830 ms
Arrays are equal: true
-------------------------------
Data Type: reverse, Size: 5000, Sort Method: adaptiveSort
adaptiveSort quicksort time: 112 ms
Arrays are equal: true
-------------------------------
Data Type: partial, Size: 5000, Sort Method: builtin
Built-in sort time: 124 ms
-------------------------------
Data Type: partial, Size: 5000, Sort Method: quicksort
Custom quicksort time: 133 ms
Arrays are equal: true
-------------------------------
Data Type: partial, Size: 5000, Sort Method: threeway
Three-way quicksort time: 333 ms
Arrays are equal: true
-------------------------------
Data Type: partial, Size: 5000, Sort Method: adaptiveSort
adaptiveSort quicksort time: 135 ms
Arrays are equal: true
-------------------------------
Data Type: duplicates, Size: 5000, Sort Method: builtin
Built-in sort time: 123 ms
-------------------------------
Data Type: duplicates, Size: 5000, Sort Method: quicksort
Custom quicksort time: 693 ms
Arrays are equal: true
-------------------------------
Data Type: duplicates, Size: 5000, Sort Method: threeway
Three-way quicksort time: 245 ms
Arrays are equal: true
-------------------------------
Data Type: duplicates, Size: 5000, Sort Method: adaptiveSort
adaptiveSort quicksort time: 124 ms
Arrays are equal: true
-------------------------------


*/