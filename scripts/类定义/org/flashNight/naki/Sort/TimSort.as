class org.flashNight.naki.Sort.TimSort {
    
    /**
     * TimSort 的最终优化版 (AS2)
     * - 严格遵循 TimSort 的堆栈不变量，确保正确性
     * - 使用预分配的临时数组和 run 栈，提升性能
     * - 保证稳定性，当元素相等时，优先选择左 run 的元素
     *
     * @param arr 要排序的数组
     * @param compareFunction 若为 null, 则使用默认的比较函数
     * @return 排好序的原数组 (就地修改)
     */
    public static function sort(arr:Array, compareFunction:Function):Array {
        var length:Number = arr.length;
        if (length <= 1) {
            return arr; // 长度<=1，直接返回
        }

        //----------------------------------------------------------
        // 0) 确定比较函数：若用户未提供，则使用默认的比较函数
        //----------------------------------------------------------
        var compare:Function = (compareFunction == null)
            ? function(a, b):Number { 
                if (a < b) return -1;
                if (a > b) return 1;
                return 0; 
              }
            : compareFunction;

        //----------------------------------------------------------
        // 1) 预检测：检查是否整体有序或整体逆序
        //----------------------------------------------------------
        var isSorted:Boolean = true;
        for (var iCheck:Number = 1; iCheck < length; iCheck++) {
            if (compare(arr[iCheck -1], arr[iCheck]) > 0) {
                isSorted = false;
                break;
            }
        }
        if (isSorted) {
            return arr; // 已整体有序，直接返回
        }

        var isReversed:Boolean = true;
        for (var jCheck:Number =1; jCheck < length; jCheck++) {
            if (compare(arr[jCheck -1], arr[jCheck]) <0 ) {
                isReversed = false;
                break;
            }
        }
        if (isReversed) {
            // 整体逆序，直接反转
            var lRev:Number =0;
            var rRev:Number = length -1;
            while (lRev < rRev) {
                var tempSwap:Object = arr[lRev];
                arr[lRev] = arr[rRev];
                arr[rRev] = tempSwap;
                lRev++;
                rRev--;
            }
            return arr;
        }

        //----------------------------------------------------------
        // 2) 设定最小 run 长度 MIN_RUN（常用 32）
        //----------------------------------------------------------
        var MIN_RUN:Number = 32;

        //----------------------------------------------------------
        // 3) 初始化模拟栈 + 临时数组
        //    - stackRuns用于存储 (start, end)，sp为栈指针
        //    - temp 数组大小预设为 length，避免动态扩容
        //----------------------------------------------------------
        var stackRuns:Array = new Array(2 * length); // [run1Start, run1End, run2Start, run2End, ...]
        var sp:Number =0; // 栈指针初始化为0

        var temp:Array = new Array(length); // 临时数组用于归并

        //----------------------------------------------------------
        // 4) 收集 run：从左到右扫描数组，找非降序（或非升序）区间
        //    - 若遇到降序 run，则翻转区间以升序
        //    - run 长度 < MIN_RUN 时进行插入排序以扩充
        //----------------------------------------------------------
        var startRun:Number =0;
        while (startRun < length) {
            var runStart:Number = startRun;
            var runEnd:Number = runStart +1; // 至少含1个元素

            // 检测单调性（包含重复元素时仍视为升序）
            if (runEnd < length) {
                if (compare(arr[runStart], arr[runEnd]) <=0 ) {
                    // 升序 run
                    while (runEnd < length -1 && compare(arr[runEnd], arr[runEnd +1]) <=0 ) {
                        runEnd++;
                    }
                } else {
                    // 降序 run
                    while (runEnd < length -1 && compare(arr[runEnd], arr[runEnd +1]) >0 ) {
                        runEnd++;
                    }
                    // 反转降序区间
                    var leftFlip:Number = runStart;
                    var rightFlip:Number = runEnd;
                    while (leftFlip < rightFlip) {
                        var tempSwap2:Object = arr[leftFlip];
                        arr[leftFlip] = arr[rightFlip];
                        arr[rightFlip] = tempSwap2;
                        leftFlip++;
                        rightFlip--;
                    }
                }
            }

            var currentRunSize:Number = runEnd - runStart +1;

            // 扩展小 run 到 MIN_RUN 使用插入排序
            if (currentRunSize < MIN_RUN) {
                var endBound:Number = (runStart + MIN_RUN -1 < length -1) ? (runStart + MIN_RUN -1) : (length -1);
                for (var iIns:Number = runStart +1; iIns <= endBound; iIns++) {
                    var keyVal:Object = arr[iIns];
                    var left:Number = runStart;
                    var right:Number = iIns;
                    // Binary search to find the insertion point
                    while (left < right) {
                        var mid:Number = (left + right) >> 1;
                        if (compare(arr[mid], keyVal) >0 ) {
                            right = mid;
                        } else {
                            left = mid +1;
                        }
                    }
                    // Shift elements to make space
                    for (var k:Number = iIns; k > left; k--) {
                        arr[k] = arr[k-1];
                    }
                    arr[left] = keyVal;
                }
                runEnd = endBound;
                currentRunSize = runEnd - runStart +1;
            }

            // 将该 run 入栈
            stackRuns[sp++] = runStart;
            stackRuns[sp++] = runEnd;

            // 检查并合并满足条件的 run
            sp = mergeInvariant(stackRuns, temp, compare, sp, arr);

            startRun = runEnd +1;
        }

        //----------------------------------------------------------
        // 5) 最终合并：反复合并栈中剩余的 runs，直到只剩一个 run
        //----------------------------------------------------------
        while (sp > 2) {
            sp = mergeInvariant(stackRuns, temp, compare, sp, arr);
            if (sp >2) {
                // 如果栈中仍有超过两个 run，强制合并栈顶两个 run
                var run2End:Number = stackRuns[sp -1];
                var run2Start:Number = stackRuns[sp -2];
                var run1End:Number = stackRuns[sp -3];
                var run1Start:Number = stackRuns[sp -4];
                sp -=4;
                doMerge(run1Start, run1End, run2Start, run2End, arr, temp, compare);
                stackRuns[sp++] = run1Start;
                stackRuns[sp++] = run2End;
            }
        }

        return arr; // 数组已整体有序
    }

    /**
     * Merge runs to maintain stack invariants
     * Invariant:
     *   |A| > |B| + |C|
     *   |B| > |C|
     * where A is the third last run, B is the second last, C is the last run
     * 
     * @param stackRuns Array containing runs as [start1, end1, start2, end2, ...]
     * @param temp Temporary array for merging
     * @param compare Comparison function
     * @param sp Stack pointer
     * @param arr The main array being sorted
     * @return Updated stack pointer
     */
    private static function mergeInvariant(stackRuns:Array, temp:Array, compare:Function, sp:Number, arr:Array):Number {
        while (sp >=4) { // 至少两个 run
            if (sp >=6) { // 至少三个 run
                var runXStart:Number = stackRuns[sp -6];
                var runXEnd:Number = stackRuns[sp -5];
                var runYStart:Number = stackRuns[sp -4];
                var runYEnd:Number = stackRuns[sp -3];
                var runZStart:Number = stackRuns[sp -2];
                var runZEnd:Number = stackRuns[sp -1];

                var sizeX:Number = runXEnd - runXStart +1;
                var sizeY:Number = runYEnd - runYStart +1;
                var sizeZ:Number = runZEnd - runZStart +1;

                // TimSort 合并条件: X ≤ Y + Z && Y ≤ Z
                if (sizeX <= sizeY + sizeZ && sizeY <= sizeZ) {
                    // 判断是否 X < Z 来决定合并 X & Y 或 Y & Z
                    if (sizeX < sizeZ) {
                        // 合并 runX 和 runY
                        sp -=4;
                        doMerge(runXStart, runXEnd, runYStart, runYEnd, arr, temp, compare);
                        stackRuns[sp++] = runXStart;
                        stackRuns[sp++] = runYEnd;
                    } else {
                        // 合并 runY 和 runZ
                        sp -=4;
                        doMerge(runYStart, runYEnd, runZStart, runZEnd, arr, temp, compare);
                        stackRuns[sp++] = runYStart;
                        stackRuns[sp++] = runZEnd;
                    }
                    continue; // 继续检查
                }
            }

            // 如果只有两个 run，检查 Y ≤ Z
            if (sp >=4) {
                var runYStart2:Number = stackRuns[sp -4];
                var runYEnd2:Number = stackRuns[sp -3];
                var runZStart2:Number = stackRuns[sp -2];
                var runZEnd2:Number = stackRuns[sp -1];

                var sizeY2:Number = runYEnd2 - runYStart2 +1;
                var sizeZ2:Number = runZEnd2 - runZStart2 +1;

                if (sizeY2 <= sizeZ2) {
                    // 合并 runY 和 runZ
                    sp -=4;
                    doMerge(runYStart2, runYEnd2, runZStart2, runZEnd2, arr, temp, compare);
                    stackRuns[sp++] = runYStart2;
                    stackRuns[sp++] = runZEnd2;
                    continue; // 继续检查
                }
            }

            break; // 不满足合并条件，退出
        }

        return sp;
    }

    /**
     * 合并两个 run 到 arr 中
     * - 左 run 拷贝到 temp，右 run 原地比较并合并
     * - 稳定排序：相等时优先放左 run 的元素
     * 
     * @param runAStart Start index of run A
     * @param runAEnd End index of run A
     * @param runBStart Start index of run B
     * @param runBEnd End index of run B
     * @param arr The main array being sorted
     * @param temp Temporary array for merging
     * @param compare Comparison function
     */
    private static function doMerge(
        runAStart:Number, runAEnd:Number,
        runBStart:Number, runBEnd:Number,
        arr:Array, temp:Array, compare:Function
    ):Void {
        if (runBStart < runAStart) {
            // Swap runs to ensure runA is on the left
            var tmpStart:Number = runAStart;
            var tmpEnd:Number = runAEnd;
            runAStart = runBStart;
            runAEnd = runBEnd;
            runBStart = tmpStart;
            runBEnd = tmpEnd;
        }

        var sizeA:Number = runAEnd - runAStart +1;
        var sizeB:Number = runBEnd - runBStart +1;

        // 拷贝 runA 到 temp
        for (var i:Number =0; i < sizeA; i++) {
            temp[i] = arr[runAStart +i];
        }

        var idxTemp:Number =0;
        var idxArr:Number = runAStart;
        var idxBPtr:Number = runBStart;
        var endA:Number = sizeA;
        var endB:Number = runBEnd +1;

        // 归并过程（稳定排序：相等时优先 temp）
        while (idxTemp < endA && idxBPtr < endB) {
            if (compare(temp[idxTemp], arr[idxBPtr]) <=0 ) {
                arr[idxArr++] = temp[idxTemp++];
            } else {
                arr[idxArr++] = arr[idxBPtr++];
            }
        }

        // 若左 run 还有剩余，直接复制到 arr
        while (idxTemp < endA) {
            arr[idxArr++] = temp[idxTemp++];
        }

        // 右 run 的剩余元素，已在 arr 中，无需复制
    }
}
