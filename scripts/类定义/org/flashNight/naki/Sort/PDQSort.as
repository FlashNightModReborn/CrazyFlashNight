
class org.flashNight.naki.Sort.PDQSort {
    
    /**
     * PDQSort 的极度内联展开版：
     * - 完全去除私有函数，将所有逻辑写在 sort() 内
     * - 所有交换操作尽量使用链式赋值，减少临时变量
     * - 合并自增自减操作，使用位运算替代乘法
     * - 替换 Math.floor 调用，减少函数调用开销
     * - 牺牲可读性与维护性，仅为追求极致性能
     * 
     * @param arr 要排序的数组
     * @param compareFunction 若为 null, 则使用数值比较 a - b
     * @return 排好序的原数组(就地修改)
     */
    public static function sort(arr:Array, compareFunction:Function):Array {
        var length:Number = arr.length;
        if (length <= 1) {
            return arr; // 数组长度为0或1，无需排序，直接返回
        }

        //----------------------------------------------------------
        // 1) 预排序检测（检查数组是否已整体有序或整体逆序）
        //----------------------------------------------------------
        // 确定比较函数：若用户未提供，则使用默认的数值比较函数
        var cmpPre:Function = (compareFunction == null) ?
            function(a:Number, b:Number):Number { return a - b; } :
            compareFunction;

        var isSorted:Boolean = true;    // 升序标记
        var isReversed:Boolean = true;  // 降序标记
        var lastCmp:Number = 0;         // 缓存最后一次比较结果

        // 单次遍历同时检测两种状态
        for (var i:Number = 1; i < length; i++) {
            lastCmp = cmpPre(arr[i-1], arr[i]);
            
            // 动态更新状态标记
            isSorted = isSorted && (lastCmp <= 0);  // 需要所有元素 <= 0
            isReversed = isReversed && (lastCmp >= 0); // 需要所有元素 >= 0
            
            // 提前终止条件：当两个标记都为false时
            if (!isSorted && !isReversed) break;
        }

        if (isSorted) return arr; // 整体有序直接返回

        if (isReversed) {
            // 整体逆序时反转数组
            var l:Number = 0;
            var r:Number = length - 1;
            while (l < r) {
                // 安全交换：使用临时变量替代链式赋值
                var tmp:Object = arr[l];
                arr[l] = arr[r];
                arr[r] = tmp;
                l++;
                r--;
            }
            return arr;
        }

        //----------------------------------------------------------
        // 2) 确定比较函数（defaultCompare）
        //----------------------------------------------------------
        // 再次确认比较函数，用于后续排序操作

        /*
        var compare:Function = (compareFunction == null) ?
            function(a:Number, b:Number):Number { return a - b; } :
            compareFunction;
        */

        //----------------------------------------------------------
        // 3) 内省排序：设置最大允许深度
        //----------------------------------------------------------
        // 使用位运算替换 Math.floor(2 * Math.log(length))，以减少函数调用开销
        var maxDepth:Number = (2 * (Math.log(length) / Math.LN2)) | 0;  // 最大递归深度限制

        //----------------------------------------------------------
        // 4) 准备栈模拟递归
        //----------------------------------------------------------
        var stack:Array = new Array(2 * length); // 初始化栈，用于存储待处理的区间
        var sp:Number = 0; // 栈指针，初始为0
        var left:Number = 0; // 当前处理区间的左边界
        var right:Number = length - 1; // 当前处理区间的右边界

        // 将初始区间 [left, right] 入栈
        stack[sp++] = left;
        stack[sp++] = right;

        //----------------------------------------------------------
        // 5) 主循环
        //----------------------------------------------------------
        while (sp > 0) { // 当栈非空时，继续处理
            // 从栈中弹出当前需要处理的区间 [left, right]
            right = stack[--sp];
            left  = stack[--sp];

            var size:Number = right - left + 1; // 当前区间的大小

            //------------------------------------------------------
            // (a) 小区间 -> 直接插入排序 (内联展开)
            //------------------------------------------------------
            if (size <= 32) {
                var iIns:Number = left + 1;
                do {
                    var keyVal:Number = arr[iIns];
                    var j:Number = iIns;
                    
                    // 合并比较和移动的单层循环
                    while (--j >= left && cmpPre(arr[j], keyVal) > 0) {
                        arr[j + 1] = arr[j];
                    }
                    arr[j + 1] = keyVal;
                } while (++iIns <= right);
                
                continue;
            }

            //------------------------------------------------------
            // (b) 检查区间有序度 (>= 90%有序) -> 直接插入排序
            //------------------------------------------------------
            var orderedCount:Number = 0; // 记录有序的相邻元素对数
            for (var iOrd:Number = left + 1; iOrd <= right; iOrd++) {
                // 如果前一个元素小于等于后一个元素，则认为这一对是有序的
                if (cmpPre(arr[iOrd - 1], arr[iOrd]) <= 0) {
                    orderedCount++;
                }
            }

            if (orderedCount >= (0.9 * (size - 1))) {
                var iOrd:Number = left + 1;
                do {
                    var key:Number = arr[iOrd];
                    var k:Number = iOrd;
                    
                    // 逆序检测优化：最多触发一次逆序移动
                    while (--k >= left && cmpPre(arr[k], key) > 0) {
                        arr[k + 1] = arr[k];
                    }
                    arr[k + 1] = key;
                } while (++iOrd <= right);
                
                continue;
            }

            //------------------------------------------------------
            // (c) 深度超限 -> 堆排序 (内联展开)
            //------------------------------------------------------
            if (maxDepth-- <= 0) { // 如果递归深度超限，切换到堆排序
            // === heapSort 开始 ===
            var startHeap:Number = left;
            var endHeap:Number = right;
            var endH:Number = endHeap;
            var sizeHeap:Number = endH - startHeap + 1;
            for (var iHeap:Number = startHeap + ((sizeHeap - 2) >> 1); iHeap >= startHeap; iHeap--) {
                var hi:Number = iHeap;
                while (true) {
                    var largest:Number = hi;
                    var lch:Number = (hi << 1) - startHeap + 1;
                    if (lch <= endH) {
                        if (cmpPre(arr[lch], arr[largest]) > 0) {
                            largest = lch;
                        }
                        var rch:Number = lch + 1;
                        if (rch <= endH && cmpPre(arr[rch], arr[largest]) > 0) {
                            largest = rch;
                        }
                    }
                    if (largest != hi) {
                        arr[hi] = arr[largest] + (arr[largest] = arr[hi]) - arr[largest];
                        hi = largest;
                    } else {
                        break;
                    }
                }
            }
            for (var jHeap:Number = endH; jHeap > startHeap; jHeap--) {
                arr[startHeap] = arr[jHeap] + (arr[jHeap] = arr[startHeap]) - arr[jHeap];
                var boundary:Number = jHeap - 1;
                var root:Number = startHeap;
                while (true) {
                    var largestH:Number = root;
                    var leftC:Number = (root << 1) - startHeap + 1;
                    if (leftC <= boundary) {
                        if (cmpPre(arr[leftC], arr[largestH]) > 0) {
                            largestH = leftC;
                        }
                        var rightC:Number = leftC + 1;
                        if (rightC <= boundary && cmpPre(arr[rightC], arr[largestH]) > 0) {
                            largestH = rightC;
                        }
                    }
                    if (largestH != root) {
                        arr[root] = arr[largestH] + (arr[largestH] = arr[root]) - arr[largestH];
                        root = largestH;
                    } else {
                        break;
                    }
                }
            }
                // === heapSort 结束 ===
                continue; // 处理下一个区间
            }

            //------------------------------------------------------
            // (d) 五点取样选 pivot (Median-of-Five) 优化版
            //------------------------------------------------------
            var sizeMed:Number = size; // 当前区间的大小

            // 优化1：展开 Math.max(1, (sizeMed-1)>>2)
            var stepRaw:Number = (sizeMed - 1) >> 2; // 直接位运算计算原始步长
            var step:Number = (stepRaw < 1) ? 1 : stepRaw; // 手动实现 max(1, stepRaw)

            // 优化2：直接计算五个取样点索引，避免中间数组操作
            var idx1:Number = left;
            var idx2:Number = left + step;
            var idx3:Number = left + ((sizeMed - 1) >> 1); // 中间点
            var idx4:Number = right - step;
            var idx5:Number = right;

            // 优化3：手动展开插入排序循环（针对5个元素）
            // --- 初始化索引数组 ---
            var indices:Array = [idx1, idx2, idx3, idx4, idx5];

            // --- 手动插入排序（5元素展开） ---
            // 第1轮插入：处理 indices[1] (原 si=1)
            var kIndex:Number = indices[1];
            var keyV:Number = arr[kIndex];
            var sj:Number = 0;
            while (sj >= 0 && cmpPre(arr[indices[sj]], keyV) > 0) {
                indices[sj + 1] = indices[sj];
                sj--;
            }
            indices[sj + 1] = kIndex;

            // 第2轮插入：处理 indices[2] (原 si=2)
            kIndex = indices[2];
            keyV = arr[kIndex];
            sj = 1;
            while (sj >= 0 && cmpPre(arr[indices[sj]], keyV) > 0) {
                indices[sj + 1] = indices[sj];
                sj--;
            }
            indices[sj + 1] = kIndex;

            // 第3轮插入：处理 indices[3] (原 si=3)
            kIndex = indices[3];
            keyV = arr[kIndex];
            sj = 2;
            while (sj >= 0 && cmpPre(arr[indices[sj]], keyV) > 0) {
                indices[sj + 1] = indices[sj];
                sj--;
            }
            indices[sj + 1] = kIndex;

            // 第4轮插入：处理 indices[4] (原 si=4)
            kIndex = indices[4];
            keyV = arr[kIndex];
            sj = 3;
            while (sj >= 0 && cmpPre(arr[indices[sj]], keyV) > 0) {
                indices[sj + 1] = indices[sj];
                sj--;
            }
            indices[sj + 1] = kIndex;

            // 选取中位数索引
            var pivotIndex:Number = indices[2];

            // 链式赋值交换 arr[left] <-> arr[pivotIndex]，将 pivot 移动到左边界
            arr[left] = arr[pivotIndex] + (arr[pivotIndex] = arr[left]) - arr[pivotIndex];

            //------------------------------------------------------
            // (e) 三路分区 + 重复元素优化 (可选批量跳过)
            //------------------------------------------------------
            var pivotValue:Number = arr[left]; // 选定的 pivot 值
            var lessIndex:Number  = left + 1; // 小于 pivot 的区域起始索引
            var greatIndex:Number = right; // 大于 pivot 的区域结束索引
            var idxLoop:Number = left + 1; // 当前扫描索引

            while (idxLoop <= greatIndex) { // 当扫描索引未超过大于区域的结束索引时
                var cPart:Number = cmpPre(arr[idxLoop], pivotValue); // 比较当前元素与 pivot
                if (cPart < 0) { // 当前元素小于 pivot
                    // 链式赋值交换 arr[idxLoop] <-> arr[lessIndex]
                    arr[idxLoop] = arr[lessIndex] + (arr[lessIndex] = arr[idxLoop]) - arr[lessIndex];cmpPre
                    lessIndex++; // 小于区域右扩
                    idxLoop++; // 扫描索引右移
                } else if (cPart > 0) { // 当前元素大于 pivot
                    // 链式赋值交换 arr[idxLoop] <-> arr[greatIndex]
                    arr[idxLoop] = arr[greatIndex] + (arr[greatIndex] = arr[idxLoop]) - arr[greatIndex];
                    greatIndex--; // 大于区域左收缩
                    // 不增加 idxLoop，因为交换过来的元素需要重新比较
                } else { // 当前元素等于 pivot
                    // 理论应该实现批量跳过重复元素的优化，但as2环境下暂时未找到性能更好的解决方法
                    idxLoop++; // 扫描索引右移
                }
            }

            // 将 pivot 放回正确的位置 (lessIndex - 1)
            // 链式赋值交换 arr[left] <-> arr[lessIndex - 1]
            arr[left] = arr[lessIndex - 1] + (arr[lessIndex - 1] = arr[left]) - arr[lessIndex - 1];

            //------------------------------------------------------
            // (f) 子区间入栈 (优先处理更小的子区间)
            //------------------------------------------------------
            // 坏分区检测逻辑
            var totalLen:Number = right - left + 1;
            var leftLen:Number  = (lessIndex - 1) - left;
            var rightLen:Number = right - greatIndex;

            if ((leftLen > 0 && leftLen < (totalLen >> 3)) || 
                (rightLen > 0 && rightLen < (totalLen >> 3))) 
            {
                maxDepth--;
            }


            var leftLen:Number  = (lessIndex - 1) - left; // 左子区间长度
            var rightLen:Number = right - greatIndex; // 右子区间长度
            if (leftLen < rightLen) { // 如果左子区间更小
                if (left < (lessIndex - 2)) { // 确保左子区间有多个元素
                    stack[sp++] = left; // 将左子区间左边界入栈
                    stack[sp++] = lessIndex - 2; // 将左子区间右边界入栈
                }
                if ((greatIndex + 1) < right) { // 确保右子区间有多个元素
                    stack[sp++] = greatIndex + 1; // 将右子区间左边界入栈
                    stack[sp++] = right; // 将右子区间右边界入栈
                }
            } else { // 如果右子区间更小或相等
                if ((greatIndex + 1) < right) { // 确保右子区间有多个元素
                    stack[sp++] = greatIndex + 1; // 将右子区间左边界入栈
                    stack[sp++] = right; // 将右子区间右边界入栈
                }
                if (left < (lessIndex - 2)) { // 确保左子区间有多个元素
                    stack[sp++] = left; // 将左子区间左边界入栈
                    stack[sp++] = lessIndex - 2; // 将左子区间右边界入栈
                }
            }
        }

        return arr; // 返回排序后的数组
    }

}



