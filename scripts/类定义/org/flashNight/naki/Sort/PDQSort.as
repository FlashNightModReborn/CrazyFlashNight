/*
## 自适应快速排序与 PDQSort 使用指南

### 介绍

`自适应快速排序` 和 `PDQSort` 是两种高效的排序算法，适用于不同的数据集和应用场景。`自适应快速排序` 结合了标准快速排序和三路快速排序，在处理随机数据集、重复数据集时表现优异。而 `PDQSort` 基于模式识别技术，能够在处理已排序、逆序和部分有序的数据集时发挥强大的性能优势。

### 什么时候使用自适应快速排序？

`自适应快速排序` 在绝大多数情况下表现稳定，并且适合处理各种类型的数据集，特别是在以下场景下表现最佳：

1. **随机数据集**：
   - 自适应快速排序在处理随机分布的数据时表现高效且一致，特别是在小规模到中等规模的数据集（100 到 1000 个元素）上。即便是大规模的随机数据集，`自适应快速排序` 也能保持良好的性能表现。
   
2. **包含重复元素的数据集**：
   - 自适应快速排序在包含大量重复元素的数据集上表现尤为优异。通过三路快速排序的优化，它可以有效地减少重复元素的比较和交换操作，从而避免性能下降。在处理具有高重复率的数据集时，自适应快排明显优于 PDQSort。

3. **小规模数据集**：
   - 对于小规模的数据集（小于 1000 个元素），`自适应快速排序` 通常表现优于 PDQSort 和内建排序，因为它结合了快速排序和三路排序的优势，减少了不必要的递归和复杂度。

4. **不确定数据分布**：
   - 当数据分布不确定，或你无法预知数据集的特点时，`自适应快速排序` 是一个较为安全的选择。它可以在不同类型的数据集上提供一致的高性能表现，无需手动选择合适的排序算法。

### 什么时候使用 PDQSort？

尽管 `自适应快速排序` 在大多数情况下表现优异，`PDQSort` 在某些特定场景下具有显著的性能优势，特别是在以下情况下推荐使用 PDQSort：

1. **已排序或接近有序的数据集**：
   - `PDQSort` 在识别并处理已排序或部分有序的数据集时表现出色。它能够通过模式识别技术减少排序操作，从而显著缩短排序时间。特别是当数据集规模较大（如 1000+ 个元素）时，`PDQSort` 比 `自适应快排` 更为高效。

2. **完全逆序数据集**：
   - 在处理完全逆序的数据集时，`PDQSort` 能够避免快速排序可能出现的性能瓶颈，并通过堆排序保证较为稳定的性能。对于逆序数据，尤其是大规模数据（如 1000+ 元素），PDQSort 表现明显优于自适应快排。

3. **大规模数据集**：
   - 对于非常大的数据集（3000+ 元素），`PDQSort` 的性能往往更加稳定，尤其在已排序、逆序或部分有序的情况下。它可以通过模式识别减少不必要的排序开销，保持较低的时间复杂度。

### 性能表现总结

#### 1. 随机数据集
- **自适应快速排序**: 在处理 100 到 1000 元素的随机数据时表现优异，通常优于内建排序。在更大规模（10000+ 元素）的数据集上，性能依然稳定，建议优先使用。
- **PDQSort**: 在处理随机数据时表现不如自适应快排，尤其在大规模随机数据集上，PDQSort 有时会出现较高的性能开销。

#### 2. 已排序或部分有序数据集
- **PDQSort**: 对于已排序或部分有序的数据集，PDQSort 通过模式识别和优化能够显著减少排序时间。特别是在处理大规模数据集时（如 1000+ 元素），PDQSort 明显优于自适应快排。
- **自适应快速排序**: 在已排序数据集上表现良好，但在识别已排序模式方面不如 PDQSort。

#### 3. 完全逆序数据集
- **PDQSort**: 在处理完全逆序数据时表现稳定，避免了传统快速排序的性能瓶颈。它能够通过堆排序保证逆序数据的高效处理。
- **自适应快速排序**: 在处理逆序数据时性能仍然不错，但在极端情况下可能会略逊于 PDQSort。

#### 4. 重复数据集
- **自适应快速排序**: 通过三路快速排序的优化，自适应快排能够高效处理高重复率的数据集，避免不必要的比较和交换操作。
- **PDQSort**: 在高重复率数据集上，PDQSort 的模式识别能力表现不佳，可能导致性能大幅下降。建议在这种场景下优先选择自适应快排。

### 使用建议

1. **优先使用自适应快速排序**：
   - 在大部分场景下，`自适应快速排序` 提供了最佳的性能和一致性。特别是在处理随机数据和包含重复元素的数据集时，它是首选算法。

2. **在已排序、部分有序或完全逆序的数据集上，使用 PDQSort**：
   - 如果数据集是已排序、部分有序或完全逆序，`PDQSort` 能够通过模式识别减少排序操作，显著提高性能，特别是在处理大规模数据时。

3. **对于高重复率的数据集，优先选择自适应快速排序**：
   - 在处理具有高重复率的场景下，`自适应快速排序` 的三路快排优化能够有效减少比较和交换操作，避免性能下降。在这些情况下，PDQSort 的表现可能不佳。

4. **不确定数据分布时，使用自适应快速排序**：
   - 当数据分布不确定时，优先选择 `自适应快速排序`，它能够适应各种数据类型，并自动调整排序策略，保证性能稳定。

---

通过上述指南，您可以根据数据集的特性选择合适的排序算法，确保在不同场景下获得最佳的排序性能。
*/


class org.flashNight.naki.Sort.PDQSort {

    /**
     * PDQSort 的极度内联展开版：
     * - 完全去除私有函数，将所有逻辑写在 sort() 内
     * - 所有交换操作尽量使用链式赋值，减少临时变量
     * - 牺牲可读性与维护性，仅为追求极致性能
     */
    public static function sort(arr:Array, compareFunction:Function):Array {
        var length:Number = arr.length;
        if (length <= 1) {
            return arr; // 无需排序
        }

        //----------------------------------------------------------
        // 1) 预排序检测（是否已整体有序 / 逆序）
        //----------------------------------------------------------
        var cmpPre:Function;
        if (compareFunction == null) {
            cmpPre = function(a:Number,b:Number):Number{return a - b;};
        } else {
            cmpPre = compareFunction;
        }

        // 检查是否整体有序
        var isSorted:Boolean = true;
        for (var iChk:Number = 1; iChk < length; iChk++) {
            if (cmpPre(arr[iChk - 1], arr[iChk]) > 0) {
                isSorted = false;
                break;
            }
        }
        if (isSorted) {
            return arr; // 已经整体有序
        }

        // 检查是否整体逆序
        var isReverse:Boolean = true;
        for (var iRev:Number = 1; iRev < length; iRev++) {
            if (cmpPre(arr[iRev - 1], arr[iRev]) < 0) {
                isReverse = false;
                break;
            }
        }
        if (isReverse) {
            // 直接反转数组
            var l:Number = 0;
            var r:Number = length - 1;
            while (l < r) {
                // 链式赋值交换 arr[l] <-> arr[r]
                arr[l] = arr[r] + (arr[r] = arr[l]) - arr[r];
                l++;
                r--;
            }
            return arr;
        }

        //----------------------------------------------------------
        // 2) 确定比较函数（defaultCompare）
        //----------------------------------------------------------
        var compare:Function;
        var defaultCompare:Boolean = (compareFunction == null);
        if (defaultCompare) {
            compare = function(a:Number, b:Number):Number {
                return a - b;
            };
        } else {
            compare = compareFunction;
        }

        //----------------------------------------------------------
        // 3) 内省排序：设置最大允许深度
        //----------------------------------------------------------
        var maxDepth:Number = Math.floor(2 * Math.log(length));

        //----------------------------------------------------------
        // 4) 准备栈模拟递归
        //----------------------------------------------------------
        var stack:Array = new Array(2 * length);
        var sp:Number = 0;
        var left:Number = 0;
        var right:Number = length - 1;

        // 初始区间入栈
        stack[sp++] = left;
        stack[sp++] = right;

        //----------------------------------------------------------
        // 5) 主循环
        //----------------------------------------------------------
        while (sp > 0) {
            right = Number(stack[--sp]);
            left  = Number(stack[--sp]);

            var size:Number = right - left + 1;
            //------------------------------------------------------
            // (a) 小区间 -> 直接插入排序 (内联展开)
            //------------------------------------------------------
            if (size <= 10) {
                for (var iIns:Number = left + 1; iIns <= right; iIns++) {
                    var keyVal = arr[iIns];
                    var jIns:Number = iIns - 1;
                    while (jIns >= left && compare(arr[jIns], keyVal) > 0) {
                        arr[jIns + 1] = arr[jIns];
                        jIns--;
                    }
                    arr[jIns + 1] = keyVal;
                }
                continue;
            }

            //------------------------------------------------------
            // (b) 检查区间有序度 (>= 90%有序) -> 直接插入排序
            //------------------------------------------------------
            var orderedCount:Number = 0;
            for (var iOrd:Number = left + 1; iOrd <= right; iOrd++) {
                if (compare(arr[iOrd - 1], arr[iOrd]) <= 0) {
                    orderedCount++;
                }
            }
            if (orderedCount >= 0.9 * (size - 1)) {
                // 再次插入排序
                for (var iIns2:Number = left + 1; iIns2 <= right; iIns2++) {
                    var keyVal2 = arr[iIns2];
                    var jIns2:Number = iIns2 - 1;
                    while (jIns2 >= left && compare(arr[jIns2], keyVal2) > 0) {
                        arr[jIns2 + 1] = arr[jIns2];
                        jIns2--;
                    }
                    arr[jIns2 + 1] = keyVal2;
                }
                continue;
            }

            //------------------------------------------------------
            // (c) 深度超限 -> 堆排序 (内联展开)
            //------------------------------------------------------
            if (maxDepth-- <= 0) {
                // === heapSort begin ===
                // 建堆
                var startHeap:Number = left;
                var endHeap:Number   = right;
                for (var iHeap:Number = Math.floor((endHeap - startHeap) / 2) + startHeap; iHeap >= startHeap; iHeap--) {
                    // inline heapify
                    var hi:Number = iHeap;
                    while (true) {
                        var largest:Number = hi;
                        var lch:Number = 2 * (hi - startHeap) + 1 + startHeap;
                        var rch:Number = 2 * (hi - startHeap) + 2 + startHeap;
                        if (lch <= endHeap && compare(arr[lch], arr[largest]) > 0) {
                            largest = lch;
                        }
                        if (rch <= endHeap && compare(arr[rch], arr[largest]) > 0) {
                            largest = rch;
                        }
                        if (largest != hi) {
                            // 链式赋值交换 arr[hi] <-> arr[largest]
                            arr[hi] = arr[largest] + (arr[largest] = arr[hi]) - arr[largest];
                            hi = largest;
                        } else {
                            break;
                        }
                    }
                }
                // 提取堆顶
                for (var jHeap:Number = endHeap; jHeap > startHeap; jHeap--) {
                    // 链式赋值交换 arr[startHeap] <-> arr[jHeap]
                    arr[startHeap] = arr[jHeap] + (arr[jHeap] = arr[startHeap]) - arr[jHeap];

                    // siftDown
                    var root:Number = startHeap;
                    var boundary:Number = jHeap - 1;
                    while (true) {
                        var largestH:Number = root;
                        var leftC:Number  = 2 * (root - startHeap) + 1 + startHeap;
                        var rightC:Number = 2 * (root - startHeap) + 2 + startHeap;
                        if (leftC <= boundary && compare(arr[leftC], arr[largestH]) > 0) {
                            largestH = leftC;
                        }
                        if (rightC <= boundary && compare(arr[rightC], arr[largestH]) > 0) {
                            largestH = rightC;
                        }
                        if (largestH != root) {
                            arr[root] = arr[largestH] + (arr[largestH] = arr[root]) - arr[largestH];
                            root = largestH;
                        } else {
                            break;
                        }
                    }
                }
                // === heapSort end ===
                continue;
            }

            //------------------------------------------------------
            // (d) 五点取样选 pivot (Median-of-Five) 内联展开
            //------------------------------------------------------
            var sizeMed:Number = size; 
            var step:Number = Math.floor((sizeMed - 1) / 4);
            var idx1:Number = left;  
            var idx2:Number = left + step; 
            var idx3:Number = left + ((sizeMed - 1) >> 1); 
            var idx4:Number = right - step; 
            var idx5:Number = right; 

            // smallInsertion5 => 对 [idx1, idx2, idx3, idx4, idx5] 做微型插入排序
            // 准备一个 indices 数组
            var indices:Array = [idx1, idx2, idx3, idx4, idx5];
            for (var si:Number = 1; si < 5; si++) {
                var kIndex:Number = indices[si];
                var keyV = arr[kIndex];
                var sj:Number = si - 1;
                while (sj >= 0 && compare(arr[indices[sj]], keyV) > 0) {
                    indices[sj + 1] = indices[sj];
                    sj--;
                }
                indices[sj + 1] = kIndex;
            }
            // 中间位置 indices[2] 就是5个点的中值
            var pivotIndex:Number = indices[2];
            // 链式赋值交换 arr[left] <-> arr[pivotIndex]
            arr[left] = arr[pivotIndex] + (arr[pivotIndex] = arr[left]) - arr[pivotIndex];

            //------------------------------------------------------
            // (e) 三路分区 + 重复元素优化(可选批量跳过)
            //------------------------------------------------------
            var pivotValue = arr[left];
            var lessIndex:Number  = left + 1;
            var greatIndex:Number = right;
            var idxLoop:Number = left + 1;

            while (idxLoop <= greatIndex) {
                var cPart:Number = compare(arr[idxLoop], pivotValue);
                if (cPart < 0) {
                    // 链式赋值交换 arr[idxLoop] <-> arr[lessIndex]
                    arr[idxLoop] = arr[lessIndex] + (arr[lessIndex] = arr[idxLoop]) - arr[lessIndex];
                    lessIndex++;
                    idxLoop++;
                } else if (cPart > 0) {
                    // 链式赋值交换 arr[idxLoop] <-> arr[greatIndex]
                    arr[idxLoop] = arr[greatIndex] + (arr[greatIndex] = arr[idxLoop]) - arr[greatIndex];
                    greatIndex--;
                } else {
                    // c == 0
                    // 若需批量跳过可加逻辑, 这里仅 idxLoop++
                    idxLoop++;
                }
            }

            // 将 pivot 放回正确位置 (lessIndex - 1)
            // 链式赋值交换 arr[left] <-> arr[lessIndex - 1]
            arr[left] = arr[lessIndex - 1] + (arr[lessIndex - 1] = arr[left]) - arr[lessIndex - 1];

            //------------------------------------------------------
            // (f) 子区间入栈(小的先处理)
            //------------------------------------------------------
            var leftLen:Number  = (lessIndex - 1) - left;
            var rightLen:Number = right - greatIndex;
            if (leftLen < rightLen) {
                if (left < (lessIndex - 2)) {
                    stack[sp++] = left;
                    stack[sp++] = lessIndex - 2;
                }
                if ((greatIndex + 1) < right) {
                    stack[sp++] = greatIndex + 1;
                    stack[sp++] = right;
                }
            } else {
                if ((greatIndex + 1) < right) {
                    stack[sp++] = greatIndex + 1;
                    stack[sp++] = right;
                }
                if (left < (lessIndex - 2)) {
                    stack[sp++] = left;
                    stack[sp++] = lessIndex - 2;
                }
            }
        }

        return arr;
    }

}

/*

org.flashNight.naki.Sort.PDQSortTest.runTests();

*/