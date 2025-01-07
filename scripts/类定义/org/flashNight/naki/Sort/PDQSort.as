
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

        // 检查数组是否整体有序
        var isSorted:Boolean = true; // 标记是否整体有序
        for (var iChk:Number = 1; iChk < length; iChk++) {
            // 如果前一个元素大于后一个元素，说明数组不是整体有序
            if (cmpPre(arr[iChk - 1], arr[iChk]) > 0) {
                isSorted = false;
                break; // 退出循环，数组不整体有序
            }
        }
        if (isSorted) {
            return arr; // 数组已经整体有序，直接返回
        }

        // 检查数组是否整体逆序
        var isReverse:Boolean = true; // 标记是否整体逆序
        for (var iRev:Number = 1; iRev < length; iRev++) {
            // 如果前一个元素小于后一个元素，说明数组不是整体逆序
            if (cmpPre(arr[iRev - 1], arr[iRev]) < 0) {
                isReverse = false;
                break; // 退出循环，数组不整体逆序
            }
        }
        if (isReverse) {
            // 如果数组整体逆序，则直接反转数组
            var l:Number = 0; // 左指针，起始位置
            var r:Number = length - 1; // 右指针，结束位置
            while (l < r) {
                // 使用链式赋值交换 arr[l] 和 arr[r]
                arr[l] = arr[r] + (arr[r] = arr[l]) - arr[r];
                l++; // 左指针右移
                r--; // 右指针左移
            }
            return arr; // 反转完成，返回数组
        }

        //----------------------------------------------------------
        // 2) 确定比较函数（defaultCompare）
        //----------------------------------------------------------
        // 再次确认比较函数，用于后续排序操作
        var compare:Function = (compareFunction == null) ?
            function(a:Number, b:Number):Number { return a - b; } :
            compareFunction;

        //----------------------------------------------------------
        // 3) 内省排序：设置最大允许深度
        //----------------------------------------------------------
        // 使用位运算替换 Math.floor(2 * Math.log(length))，以减少函数调用开销
        var maxDepth:Number = (2 * Math.log(length)) | 0; // 最大递归深度限制

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
            right = Number(stack[--sp]);
            left  = Number(stack[--sp]);

            var size:Number = right - left + 1; // 当前区间的大小

            //------------------------------------------------------
            // (a) 小区间 -> 直接插入排序 (内联展开)
            //------------------------------------------------------
            if (size <= 10) { // 如果区间大小小于等于10，使用插入排序
                for (var iIns:Number = left + 1; iIns <= right; iIns++) { // 从第二个元素开始
                    var keyVal:Number = arr[iIns]; // 当前元素作为插入的关键值
                    var jIns:Number = iIns - 1; // 插入位置的前一个索引
                    // 合并自减操作到循环条件中，减少指令数
                    while (jIns >= left && compare(arr[jIns], keyVal) > 0) { // 比较并移动元素
                        arr[jIns + 1] = arr[jIns]; // 将较大的元素向右移动
                        jIns--; // 指针左移
                    }
                    arr[jIns + 1] = keyVal; // 将关键值插入到正确位置
                }
                continue; // 处理下一个区间
            }

            //------------------------------------------------------
            // (b) 检查区间有序度 (>= 90%有序) -> 直接插入排序
            //------------------------------------------------------
            var orderedCount:Number = 0; // 记录有序的相邻元素对数
            for (var iOrd:Number = left + 1; iOrd <= right; iOrd++) {
                // 如果前一个元素小于等于后一个元素，则认为这一对是有序的
                if (compare(arr[iOrd - 1], arr[iOrd]) <= 0) {
                    orderedCount++;
                }
            }
            if (orderedCount >= (0.9 * (size - 1))) { // 如果有序度达到90%以上
                // 再次进行插入排序，确保排序的稳定性
                for (var iIns2:Number = left + 1; iIns2 <= right; iIns2++) { // 从第二个元素开始
                    var keyVal2:Number = arr[iIns2]; // 当前元素作为插入的关键值
                    var jIns2:Number = iIns2 - 1; // 插入位置的前一个索引
                    // 合并自减操作到循环条件中，减少指令数
                    while (jIns2 >= left && compare(arr[jIns2], keyVal2) > 0) { // 比较并移动元素
                        arr[jIns2 + 1] = arr[jIns2]; // 将较大的元素向右移动
                        jIns2--; // 指针左移
                    }
                    arr[jIns2 + 1] = keyVal2; // 将关键值插入到正确位置
                }
                continue; // 处理下一个区间
            }

            //------------------------------------------------------
            // (c) 深度超限 -> 堆排序 (内联展开)
            //------------------------------------------------------
            if (maxDepth-- <= 0) { // 如果递归深度超限，切换到堆排序
                // === heapSort 开始 ===
                // 建立最大堆
                var startHeap:Number = left; // 堆的起始位置
                var endHeap:Number   = right; // 堆的结束位置
                // 使用位运算替换 Math.floor((endHeap - startHeap) / 2) + startHeap，减少函数调用开销
                for (var iHeap:Number = ((endHeap - startHeap) >> 1) + startHeap; iHeap >= startHeap; iHeap--) { // 从最后一个非叶子节点开始
                    // 内联 heapify 操作，调整堆以满足最大堆性质
                    var hi:Number = iHeap; // 当前节点索引
                    while (true) {
                        var largest:Number = hi; // 假设当前节点是最大的
                        // 计算左子节点索引，使用位运算替代乘法
                        var lch:Number = ( (hi - startHeap) << 1 ) + 1 + startHeap; // 2*(hi - startHeap) +1
                        // 计算右子节点索引，使用位运算替代乘法
                        var rch:Number = ( (hi - startHeap) << 1 ) + 2 + startHeap; // 2*(hi - startHeap) +2
                        // 比较左子节点与当前最大值
                        if (lch <= endHeap && compare(arr[lch], arr[largest]) > 0) {
                            largest = lch;
                        }
                        // 比较右子节点与当前最大值
                        if (rch <= endHeap && compare(arr[rch], arr[largest]) > 0) {
                            largest = rch;
                        }
                        if (largest != hi) { // 如果子节点中有比当前节点大的
                            // 链式赋值交换 arr[hi] <-> arr[largest]
                            arr[hi] = arr[largest] + (arr[largest] = arr[hi]) - arr[largest];
                            hi = largest; // 继续向下调整
                        } else {
                            break; // 当前节点已经是最大的，结束调整
                        }
                    }
                }
                // 提取堆顶元素，将其放到正确的位置
                for (var jHeap:Number = endHeap; jHeap > startHeap; jHeap--) {
                    // 链式赋值交换 arr[startHeap] <-> arr[jHeap]
                    arr[startHeap] = arr[jHeap] + (arr[jHeap] = arr[startHeap]) - arr[jHeap];

                    // siftDown 操作，重新调整堆以维持最大堆性质
                    var root:Number = startHeap; // 根节点索引
                    var boundary:Number = jHeap - 1; // 堆的边界
                    while (true) {
                        var largestH:Number = root; // 假设根节点是最大的
                        // 计算左子节点索引，使用位运算替代乘法
                        var leftC:Number  = ( (root - startHeap) << 1 ) + 1 + startHeap; // 2*(root - startHeap) +1
                        // 计算右子节点索引，使用位运算替代乘法
                        var rightC:Number = ( (root - startHeap) << 1 ) + 2 + startHeap; // 2*(root - startHeap) +2
                        // 比较左子节点与当前最大值
                        if (leftC <= boundary && compare(arr[leftC], arr[largestH]) > 0) {
                            largestH = leftC;
                        }
                        // 比较右子节点与当前最大值
                        if (rightC <= boundary && compare(arr[rightC], arr[largestH]) > 0) {
                            largestH = rightC;
                        }
                        if (largestH != root) { // 如果子节点中有比当前节点大的
                            // 链式赋值交换 arr[root] <-> arr[largestH]
                            arr[root] = arr[largestH] + (arr[largestH] = arr[root]) - arr[largestH];
                            root = largestH; // 继续向下调整
                        } else {
                            break; // 当前节点已经是最大的，结束调整
                        }
                    }
                }
                // === heapSort 结束 ===
                continue; // 处理下一个区间
            }

            //------------------------------------------------------
            // (d) 五点取样选 pivot (Median-of-Five) 内联展开
            //------------------------------------------------------
            var sizeMed:Number = size; // 当前区间的大小
            // 使用位运算替代 Math.floor((sizeMed - 1) / 4)，减少函数调用开销
            var step:Number = (sizeMed - 1) >> 2; // 计算步长，等同于 floor((sizeMed -1)/4)
            var idx1:Number = left;  
            var idx2:Number = left + step; 
            var idx3:Number = left + ( (sizeMed - 1) >> 1 ); // 中间点索引
            var idx4:Number = right - step; 
            var idx5:Number = right; 

            // 对选取的5个点进行微型插入排序，以找到中位数
            var indices:Array = [idx1, idx2, idx3, idx4, idx5]; // 存储选取的索引
            for (var si:Number = 1; si < 5; si++) { // 从第二个索引开始
                var kIndex:Number = indices[si]; // 当前索引
                var keyV:Number = arr[kIndex]; // 当前索引对应的值
                var sj:Number = si - 1; // 前一个索引
                while (sj >= 0 && compare(arr[indices[sj]], keyV) > 0) { // 比较并寻找插入位置
                    indices[sj + 1] = indices[sj]; // 将较大的索引向后移动
                    sj--; // 指针左移
                }
                indices[sj + 1] = kIndex; // 将当前索引插入到正确位置
            }
            // 选取中间位置的索引作为 pivot 索引
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
                var cPart:Number = compare(arr[idxLoop], pivotValue); // 比较当前元素与 pivot
                if (cPart < 0) { // 当前元素小于 pivot
                    // 链式赋值交换 arr[idxLoop] <-> arr[lessIndex]
                    arr[idxLoop] = arr[lessIndex] + (arr[lessIndex] = arr[idxLoop]) - arr[lessIndex];
                    lessIndex++; // 小于区域右扩
                    idxLoop++; // 扫描索引右移
                } else if (cPart > 0) { // 当前元素大于 pivot
                    // 链式赋值交换 arr[idxLoop] <-> arr[greatIndex]
                    arr[idxLoop] = arr[greatIndex] + (arr[greatIndex] = arr[idxLoop]) - arr[greatIndex];
                    greatIndex--; // 大于区域左收缩
                    // 不增加 idxLoop，因为交换过来的元素需要重新比较
                } else { // 当前元素等于 pivot
                    // 此处可以实现批量跳过重复元素的优化，但当前仅简单跳过
                    idxLoop++; // 扫描索引右移
                }
            }

            // 将 pivot 放回正确的位置 (lessIndex - 1)
            // 链式赋值交换 arr[left] <-> arr[lessIndex - 1]
            arr[left] = arr[lessIndex - 1] + (arr[lessIndex - 1] = arr[left]) - arr[lessIndex - 1];

            //------------------------------------------------------
            // (f) 子区间入栈 (优先处理更小的子区间)
            //------------------------------------------------------
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



/*

org.flashNight.naki.Sort.PDQSortTest.runTests();

*/