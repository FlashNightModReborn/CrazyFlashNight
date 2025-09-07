import org.flashNight.naki.Sort.SortProfiler;

class org.flashNight.naki.Sort.PDQSortWithProfiler {
    
    /**
     * 带性能分析的PDQSort排序
     * 这是PDQSort的包装版本，用于性能分析
     */
    public static function sort(arr:Array, compareFunction:Function, profiler:SortProfiler):Array {
        var length:Number = arr.length;
        if (length <= 1) return arr;
        
        // 如果没有提供profiler，创建一个禁用的
        if (!profiler) {
            profiler = new SortProfiler();
            profiler.setEnabled(false);
        }
        
        // 重置计数器
        if (profiler.isEnabled()) {
            profiler.reset();
        }
        
        // 使用原始比较函数或默认数值比较
        var originalCmp:Function = compareFunction || function(a:Number, b:Number):Number { return a - b; };
        
        // 包装比较函数以计数
        var cmpPre:Function = function(a:Object, b:Object):Number {
            profiler.recordComparison();
            return originalCmp(a, b);
        };
        
        // 预排序检测
        var isSorted:Boolean = true, isReversed:Boolean = true, lastCmp:Number = 0;
        for (var i:Number = 1; i < length; i++) {
            lastCmp = cmpPre(arr[i-1], arr[i]);
            isSorted = isSorted && (lastCmp <= 0);
            isReversed = isReversed && (lastCmp >= 0);
            if (!(isSorted || isReversed)) break;
        }
        
        if (isSorted) return arr;
        
        if (isReversed) {
            var l:Number = 0, r:Number = length - 1;
            var temp:Object;
            do { 
                temp = arr[l]; 
                arr[l] = arr[r]; 
                arr[r] = temp;
                profiler.recordSwap();
            } while (++l < --r);
            return arr;
        }
        
        var maxDepth:Number = (2 * (Math.log(length) / Math.LN2)) | 0;
        
        // 栈结构
        var stack:Array = new Array(maxDepth + 8), sp:Number = 0;
        var left:Number = 0, right:Number = length - 1;
        stack[sp++] = left; stack[sp++] = right;
        
        // 更新栈深度
        profiler.updateStackDepth(sp / 2);
        
        // 声明所有局部变量
        var size:Number, iIns:Number, keyVal:Object, j:Number;
        var orderedCount:Number, iOrd:Number, key:Object, k:Number;
        var startHeap:Number, endHeap:Number, endH:Number, sizeHeap:Number;
        var iHeap:Number, hi:Number, largest:Number;
        var lch:Number, rch:Number, jHeap:Number, boundary:Number;
        var root:Number, largestH:Number, leftC:Number, rightC:Number;
        var sizeMed:Number, stepRaw:Number, step:Number;
        var idx1:Number, idx2:Number, idx3:Number, idx4:Number, idx5:Number;
        var indices:Array, kIndex:Number, sj:Number;
        var pivotIndex:Number, pivotValue:Object;
        var lessIndex:Number, greatIndex:Number, idxLoop:Number, cPart:Number;
        var totalLen:Number, leftLen:Number, rightLen:Number;
        var swapTemp:Object;
        
        while (sp > 0) {
            right = stack[--sp]; left = stack[--sp];
            size = right - left + 1;
            
            // 更新栈深度
            profiler.updateStackDepth(sp / 2);
            
            // 小数组插入排序
            if (size <= 32) {
                for (iIns = left + 1; iIns <= right; iIns++) {
                    keyVal = arr[iIns]; j = iIns;
                    while (--j >= left && cmpPre(arr[j], keyVal) > 0) {
                        arr[j + 1] = arr[j];
                        profiler.recordSwap();
                    }
                    arr[j + 1] = keyVal;
                }
                continue;
            }
            
            // 高有序度检测
            orderedCount = 0;
            for (iOrd = left + 1; iOrd <= right; iOrd++) {
                if (cmpPre(arr[iOrd - 1], arr[iOrd]) <= 0) orderedCount++;
            }
            if (orderedCount >= 0.9 * (size - 1)) {
                for (iOrd = left + 1; iOrd <= right; iOrd++) {
                    key = arr[iOrd]; k = iOrd;
                    while (--k >= left && cmpPre(arr[k], key) > 0) {
                        arr[k + 1] = arr[k];
                        profiler.recordSwap();
                    }
                    arr[k + 1] = key;
                }
                continue;
            }
            
            // 深度超限 - 堆排序
            if (maxDepth-- <= 0) {
                profiler.recordHeapsortCall();
                
                startHeap = left; endHeap = right; endH = endHeap; sizeHeap = endH - startHeap + 1;
                for (iHeap = startHeap + ((sizeHeap - 2) >> 1); iHeap >= startHeap; iHeap--) {
                    hi = iHeap;
                    while (true) {
                        largest = hi;
                        lch = (hi << 1) - startHeap + 1;
                        if (lch <= endH && cmpPre(arr[lch], arr[largest]) > 0) largest = lch;
                        rch = lch + 1;
                        if (rch <= endH && cmpPre(arr[rch], arr[largest]) > 0) largest = rch;
                        if (largest != hi) {
                            swapTemp = arr[hi];
                            arr[hi] = arr[largest];
                            arr[largest] = swapTemp;
                            profiler.recordSwap();
                            hi = largest;
                        } else break;
                    }
                }
                for (jHeap = endH; jHeap > startHeap; jHeap--) {
                    swapTemp = arr[startHeap];
                    arr[startHeap] = arr[jHeap];
                    arr[jHeap] = swapTemp;
                    profiler.recordSwap();
                    boundary = jHeap - 1; root = startHeap;
                    while (true) {
                        largestH = root;
                        leftC = (root << 1) - startHeap + 1;
                        if (leftC <= boundary && cmpPre(arr[leftC], arr[largestH]) > 0) largestH = leftC;
                        rightC = leftC + 1;
                        if (rightC <= boundary && cmpPre(arr[rightC], arr[largestH]) > 0) largestH = rightC;
                        if (largestH != root) {
                            swapTemp = arr[root];
                            arr[root] = arr[largestH];
                            arr[largestH] = swapTemp;
                            profiler.recordSwap();
                            root = largestH;
                        } else break;
                    }
                }
                continue;
            }
            
            // 记录分区操作
            profiler.recordPartition();
            
            // 五点取样中位数
            sizeMed = size;
            stepRaw = (sizeMed - 1) >> 2;
            step = (stepRaw < 1) ? 1 : stepRaw;
            idx1 = left;
            idx2 = left + step;
            idx3 = left + ((sizeMed - 1) >> 1);
            idx4 = right - step;
            idx5 = right;
            
            indices = [idx1, idx2, idx3, idx4, idx5];
            // 插入排序找中位数
            kIndex = indices[1]; sj = 0;
            while (sj >= 0 && cmpPre(arr[indices[sj]], arr[kIndex]) > 0) indices[sj + 1] = indices[sj--];
            indices[sj + 1] = kIndex;
            kIndex = indices[2]; sj = 1;
            while (sj >= 0 && cmpPre(arr[indices[sj]], arr[kIndex]) > 0) indices[sj + 1] = indices[sj--];
            indices[sj + 1] = kIndex;
            kIndex = indices[3]; sj = 2;
            while (sj >= 0 && cmpPre(arr[indices[sj]], arr[kIndex]) > 0) indices[sj + 1] = indices[sj--];
            indices[sj + 1] = kIndex;
            kIndex = indices[4]; sj = 3;
            while (sj >= 0 && cmpPre(arr[indices[sj]], arr[kIndex]) > 0) indices[sj + 1] = indices[sj--];
            indices[sj + 1] = kIndex;
            
            pivotIndex = indices[2];
            swapTemp = arr[left];
            arr[left] = arr[pivotIndex];
            arr[pivotIndex] = swapTemp;
            profiler.recordSwap();
            
            // 三路分区
            pivotValue = arr[left];
            lessIndex = left + 1;
            greatIndex = right;
            idxLoop = left + 1;
            
            while (idxLoop <= greatIndex) {
                cPart = cmpPre(arr[idxLoop], pivotValue);
                if (cPart < 0) {
                    swapTemp = arr[idxLoop];
                    arr[idxLoop] = arr[lessIndex];
                    arr[lessIndex] = swapTemp;
                    profiler.recordSwap();
                    lessIndex++; idxLoop++;
                } else if (cPart > 0) {
                    swapTemp = arr[idxLoop];
                    arr[idxLoop] = arr[greatIndex];
                    arr[greatIndex] = swapTemp;
                    profiler.recordSwap();
                    greatIndex--;
                } else {
                    idxLoop++;
                }
            }
            
            swapTemp = arr[left];
            arr[left] = arr[lessIndex - 1];
            arr[lessIndex - 1] = swapTemp;
            profiler.recordSwap();
            
            // 坏分区检测
            totalLen = right - left + 1;
            leftLen = (lessIndex - 1) - left;
            rightLen = right - greatIndex;
            
            if ((leftLen > 0 && leftLen < (totalLen >> 3)) || 
                (rightLen > 0 && rightLen < (totalLen >> 3))) {
                profiler.recordBadSplit();
                maxDepth--;
            }
            
            // 改进的处理顺序：只压大段，继续处理小段（tail-call优化）
            // 这确保栈深度永远不超过 log2(n)
            if (leftLen < rightLen) {
                // 左边较小，右边较大
                if (greatIndex + 1 < right) { 
                    stack[sp++] = greatIndex + 1; 
                    stack[sp++] = right; 
                }
                // 继续处理左边（小段），不入栈
                if (left < lessIndex - 2) {
                    right = lessIndex - 2;
                } else {
                    // 左段无效，继续处理栈中的下一个区间
                    continue;
                }
            } else {
                // 右边较小，左边较大
                if (left < lessIndex - 2) { 
                    stack[sp++] = left; 
                    stack[sp++] = lessIndex - 2; 
                }
                // 继续处理右边（小段），不入栈
                if (greatIndex + 1 < right) {
                    left = greatIndex + 1;
                } else {
                    // 右段无效，继续处理栈中的下一个区间
                    continue;
                }
            }
        }
        
        return arr;
    }
}