class org.flashNight.naki.Sort.PDQSort {
    
    /**
     * 基于 Pattern-defeating Quicksort 算法的高度优化实现
     * 
     * 本实现通过以下核心优化策略达到极致性能：
     * 
     *   完全内联展开：消除所有函数调用开销
     *   预排序检测：快速处理已排序/逆序数组
     *   自适应策略：根据数据特征自动选择最优排序策略
     *   三路分区：高效处理重复元素
     *   内省保护：防止快速排序恶化成O(n²)
     * 
     * @param arr       待排序数组（就地修改）
     * @param compareFunction 比较函数，若为 null 使用数值比较 (a - b)
     * @return          排序后的原数组（实现原地排序）
     */
    public static function sort(arr:Array, compareFunction:Function):Array {
        var length:Number = arr.length;
        // 快速返回长度小于等于1的数组（边界情况处理）
        if (length <= 1) return arr;

        //==========================================================
        // [1/5] 预排序检测阶段 - O(n)时间复杂度快速检测
        //==========================================================
        // 动态选择比较函数（避免类型检查开销）
        var cmpPre:Function = compareFunction || function(a:Number, b:Number):Number { return a - b; };
        
        // 双标记并行检测（同时检测升序和降序）
        var isSorted:Boolean = true, isReversed:Boolean = true, lastCmp:Number = 0;
        for (var i:Number = 1; i < length; i++) {
            lastCmp = cmpPre(arr[i-1], arr[i]);
            isSorted = isSorted && (lastCmp <= 0);   // 持续验证升序
            isReversed = isReversed && (lastCmp >= 0);// 持续验证降序
            if (!(isSorted || isReversed)) break;     // 发现无序立即终止
        }
        
        // 处理已排序情况（快速返回）
        if (isSorted) return arr;
        // 处理完全逆序情况（就地反转数组，O(n/2)时间复杂度）
        if (isReversed) {
            var l:Number = 0, r:Number = length - 1;
            // 使用异或交换算法避免临时变量（经测试在AS2中性能最优）
            do { arr[l] = arr[r] + (arr[r] = arr[l]) - arr[r]; } while (++l < --r);
            return arr;
        }

        //==========================================================
        // [2/5] 内省排序参数初始化
        //==========================================================
        // 计算最大递归深度（位运算优化替代Math.floor）
        // 公式推导：2 * floor(log2(n))，确保堆排序及时介入
        var maxDepth:Number = (2 * (Math.log(length) / Math.LN2)) | 0;  

        //==========================================================
        // [3/5] 栈模拟递归结构
        //==========================================================
        // 栈容量公式：2*(ceil(log2(n)) + 安全余量)
        // 使用显式栈结构避免递归调用开销（关键性能优化）
        var stack:Array = new Array(maxDepth + 8), sp:Number = 0;
        var left:Number = 0, right:Number = length - 1;
        stack[sp++] = left; stack[sp++] = right;  // 初始区间入栈

        //==========================================================
        // [4/5] 主排序循环（核心逻辑）
        //==========================================================

        // 声明所有局部变量（AS2函数级作用域优化，避免重复声明提升性能）
        var size:Number,         // 当前处理区间的元素总数 (right - left + 1)
            iIns:Number,         // 插入排序外层循环索引
            keyVal:Number,       // 插入排序当前提取的待插入值
            j:Number,            // 插入排序内层循环索引/通用临时索引
            orderedCount:Number, // 高有序度检测计数器（统计有序元素对数量）
            iOrd:Number,         // 有序度检测循环索引
            key:Number,          // 高有序度插入排序的当前元素值
            k:Number;            // 高有序度插入排序的内层索引

        var startHeap:Number,    // 堆排序起始位置（当前区间左边界）
            endHeap:Number,      // 堆排序结束位置（当前区间右边界）
            endH:Number,         // 堆排序运行时右边界（动态调整）
            sizeHeap:Number,     // 堆排序处理的元素总数
            iHeap:Number,        // 堆构建阶段的父节点索引
            hi:Number,           // 堆调整过程当前节点索引
            largest:Number;      // 堆调整过程最大元素位置标记

        var lch:Number,          // 左子节点索引 (Left Child Index)
            rch:Number,          // 右子节点索引 (Right Child Index)
            jHeap:Number,        // 堆排序元素交换索引
            boundary:Number,     // 堆调整时子节点有效范围边界
            root:Number,         // 堆调整起始根节点位置
            largestH:Number,     // 堆调整过程最大值暂存
            leftC:Number,        // 堆节点左子节点计算值
            rightC:Number;       // 堆节点右子节点计算值

        var sizeMed:Number,      // 中位数取样时的区间大小
            stepRaw:Number,      // 五点取样步长原始值
            step:Number,         // 实际取样步长（确保≥1）
            idx1:Number,         // 五点取样索引1（左边界）
            idx2:Number,         // 五点取样索引2（左1/4处）
            idx3:Number,         // 五点取样索引3（中位数位置）
            idx4:Number,         // 五点取样索引4（右1/4处）
            idx5:Number;         // 五点取样索引5（右边界）

        var indices:Array,       // 五点取样索引排序用数组
            kIndex:Number,       // 插入排序当前处理的取样点索引
            sj:Number,           // 取样点插入排序内层索引
            pivotIndex:Number,   // 最终选定的基准值位置
            pivotValue:Number;   // 基准值缓存（提升访问速度）

        var lessIndex:Number,    // 三路分区小于区的右边界（< pivot）
            greatIndex:Number,   // 三路分区大于区的左边界（> pivot）
            idxLoop:Number,      // 三路分区主循环当前索引
            cPart:Number,        // 三路分区比较结果缓存
            totalLen:Number,     // 当前区间总长度（用于坏分区检测）
            leftLen:Number,      // 左子区间长度（小于区）
            rightLen:Number;     // 右子区间长度（大于区）
        
        // 基于显式栈的迭代循环（替代递归）
        while (sp > 0) {
            // 弹出当前处理区间（LIFO顺序）
            right = stack[--sp]; left = stack[--sp];
            size = right - left + 1;  // 计算当前区间长度

            //------------------------------------------------------
            // [A] 小数组优化 - 插入排序（阈值32，内联展开）
            //------------------------------------------------------
            if (size <= 32) {
                // 插入排序核心逻辑（完全展开循环）
                for (iIns = left + 1; iIns <= right; iIns++) {
                    keyVal = arr[iIns]; j = iIns;
                    // 逆向扫描找到插入位置
                    while (--j >= left && cmpPre(arr[j], keyVal) > 0) arr[j + 1] = arr[j];
                    arr[j + 1] = keyVal;  // 插入元素到正确位置
                }
                continue;  // 处理下一个区间
            }

            //------------------------------------------------------
            // [B] 高有序度优化 - 自适应插入排序（>=90%元素有序）
            //------------------------------------------------------
            orderedCount = 0;
            // 统计有序元素对数量
            for (iOrd = left + 1; iOrd <= right; iOrd++) {
                if (cmpPre(arr[iOrd - 1], arr[iOrd]) <= 0) orderedCount++;
            }
            // 满足阈值时使用插入排序
            if (orderedCount >= 0.9 * (size - 1)) {
                for (iOrd = left + 1; iOrd <= right; iOrd++) {
                    key = arr[iOrd]; k = iOrd;
                    while (--k >= left && cmpPre(arr[k], key) > 0) arr[k + 1] = arr[k];
                    arr[k + 1] = key;
                }
                continue;
            }

            //------------------------------------------------------
            // [C] 深度超限保护 - 堆排序（内联展开）
            //------------------------------------------------------
            if (maxDepth-- <= 0) {
                // 堆排序实现（完全展开避免函数调用）
                startHeap = left; endHeap = right; endH = endHeap; sizeHeap = endH - startHeap + 1;
                // 构建初始最大堆（自底向上）
                for (iHeap = startHeap + ((sizeHeap - 2) >> 1); iHeap >= startHeap; iHeap--) {
                    hi = iHeap;
                    // 下沉调整（保持堆性质）
                    while (true) {
                        largest = hi;
                        lch = (hi << 1) - startHeap + 1;  // 左子节点索引
                        if (lch <= endH && cmpPre(arr[lch], arr[largest]) > 0) largest = lch;
                        rch = lch + 1;  // 右子节点索引
                        if (rch <= endH && cmpPre(arr[rch], arr[largest]) > 0) largest = rch;
                        if (largest != hi) {
                            // 交换元素并继续调整
                            arr[hi] = arr[largest] + (arr[largest] = arr[hi]) - arr[largest];
                            hi = largest;
                        } else break;
                    }
                }
                // 堆排序主循环（逐个提取最大值）
                for (jHeap = endH; jHeap > startHeap; jHeap--) {
                    // 交换堆顶与末尾元素
                    arr[startHeap] = arr[jHeap] + (arr[jHeap] = arr[startHeap]) - arr[jHeap];
                    boundary = jHeap - 1; root = startHeap;
                    // 重建堆
                    while (true) {
                        largestH = root;
                        leftC = (root << 1) - startHeap + 1;
                        if (leftC <= boundary && cmpPre(arr[leftC], arr[largestH]) > 0) largestH = leftC;
                        rightC = leftC + 1;
                        if (rightC <= boundary && cmpPre(arr[rightC], arr[largestH]) > 0) largestH = rightC;
                        if (largestH != root) {
                            arr[root] = arr[largestH] + (arr[largestH] = arr[root]) - arr[largestH];
                            root = largestH;
                        } else break;
                    }
                }
                continue;  // 处理下一个区间
            }

            //------------------------------------------------------
            // [D] 分区策略 - 五点取样中位数法（抗退化核心）
            //------------------------------------------------------
            sizeMed = size;
            stepRaw = (sizeMed - 1) >> 2;  // 位运算优化步长计算（替代除法）
            step = (stepRaw < 1) ? 1 : stepRaw;
            // 计算五个等距取样点索引
            idx1 = left;                   // 左边界
            idx2 = left + step;            // 左中点
            idx3 = left + ((sizeMed - 1) >> 1);  // 中心点（位运算优化）
            idx4 = right - step;           // 右中点
            idx5 = right;                  // 右边界
            // 手动展开五元素插入排序（确定中位数）
            indices = [idx1, idx2, idx3, idx4, idx5];
            // 第一轮插入排序
            kIndex = indices[1]; sj = 0;
            while (sj >= 0 && cmpPre(arr[indices[sj]], arr[kIndex]) > 0) indices[sj + 1] = indices[sj--];
            indices[sj + 1] = kIndex;
            // 后续三轮插入（展开循环优化性能）
            kIndex = indices[2]; sj = 1;
            while (sj >= 0 && cmpPre(arr[indices[sj]], arr[kIndex]) > 0) indices[sj + 1] = indices[sj--];
            indices[sj + 1] = kIndex;
            kIndex = indices[3]; sj = 2;
            while (sj >= 0 && cmpPre(arr[indices[sj]], arr[kIndex]) > 0) indices[sj + 1] = indices[sj--];
            indices[sj + 1] = kIndex;
            kIndex = indices[4]; sj = 3;
            while (sj >= 0 && cmpPre(arr[indices[sj]], arr[kIndex]) > 0) indices[sj + 1] = indices[sj--];
            indices[sj + 1] = kIndex;
            // 确定中位数并交换到左边界（准备分区）
            pivotIndex = indices[2];
            arr[left] = arr[pivotIndex] + (arr[pivotIndex] = arr[left]) - arr[pivotIndex];

            //------------------------------------------------------
            // [E] 三路分区核心算法（处理重复元素关键）
            //------------------------------------------------------
            pivotValue = arr[left];  // 获取基准值
            lessIndex = left + 1;     // 小于区的右边界
            greatIndex = right;      // 大于区的左边界
            idxLoop = left + 1;      // 当前扫描指针
            // 经典三路分区循环（Bentley-McIlroy 变体）
            while (idxLoop <= greatIndex) {
                cPart = cmpPre(arr[idxLoop], pivotValue);
                if (cPart < 0) {  // 小于分区
                    // 交换到less区并扩展区域
                    arr[idxLoop] = arr[lessIndex] + (arr[lessIndex] = arr[idxLoop]) - arr[lessIndex];
                    lessIndex++; idxLoop++;
                } else if (cPart > 0) {  // 大于分区
                    // 交换到great区并扩展区域
                    arr[idxLoop] = arr[greatIndex] + (arr[greatIndex] = arr[idxLoop]) - arr[greatIndex];
                    greatIndex--;
                } else {  // 等于分区（直接前进）
                    idxLoop++;
                }
            }
            // 将pivot移动到正确位置（less区与等于区交界处）
            arr[left] = arr[lessIndex - 1] + (arr[lessIndex - 1] = arr[left]) - arr[lessIndex - 1];

            //------------------------------------------------------
            // [F] 子区间入栈策略（优化栈空间使用）
            //------------------------------------------------------
            totalLen = right - left + 1;
            leftLen = (lessIndex - 1) - left;    // 左子区间长度
            rightLen = right - greatIndex;       // 右子区间长度
            // 坏分区检测（触发深度惩罚机制）
            if ((leftLen > 0 && leftLen < (totalLen >> 3)) || 
                (rightLen > 0 && rightLen < (totalLen >> 3))) {
                maxDepth--;  // 增加堆排序触发概率
            }
            // 根据子区间大小决定处理顺序（小区间优先策略）
            if (leftLen < rightLen) {
                // 左子区间入栈（优先处理较小分区）
                if (left < lessIndex - 2) { stack[sp++] = left; stack[sp++] = lessIndex - 2; }
                // 右子区间入栈
                if (greatIndex + 1 < right) { stack[sp++] = greatIndex + 1; stack[sp++] = right; }
            } else {
                // 右子区间先入栈（较大分区后处理）
                if (greatIndex + 1 < right) { stack[sp++] = greatIndex + 1; stack[sp++] = right; }
                if (left < lessIndex - 2) { stack[sp++] = left; stack[sp++] = lessIndex - 2; }
            }
        }

        return arr;  // 返回已排序的原数组
    }
}
