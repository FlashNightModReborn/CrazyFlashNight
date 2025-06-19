class org.flashNight.naki.Sort.TimSort {
    /**
     * 	ActionScript 2.0 标准 TimSort 实现
     * 	根据 Python 的 listsort.txt 规范进行重构和优化。
     *  
     *
     * 	特点:
     * 	- 严格的模块化设计，无代码重复。
     * 	- 遵循 Timsort 堆栈不变量，通过 mergeCollapse 和 mergeForceCollapse 维护。
     * 	- 优化合并策略 (mergeAt)，仅复制较小的 run 到临时数组。
     * 	- 动态计算 minRun，并使用插入排序扩展小 run。
     * 	- 保证排序稳定性。
     */
    
    // --- 私有常量 ---
    // 在 AS2 中没有真正的 private const, 我们用静态变量模拟
    private static var MIN_MERGE:Number = 32;

    // --- 公共主函数 ---

    /**
     * 对数组进行就地 TimSort 排序。
     * @param arr 要排序的数组。
     * @param compareFunction 比较函数，接收两个参数(a, b)，返回 a<b ? <0 : (a>b ? >0 : 0)。
     *                        若为 null，则使用默认的数字比较。
     * @return 排好序的原数组 (就地修改)。
     */
    public static function sort(arr:Array, compareFunction:Function):Array {
        var n:Number = arr.length;
        if (n < 2) {
            return arr;
        }

        // 如果未提供比较函数，使用默认函数
        var compare:Function = (compareFunction == null)
            ? function(a, b):Number { return a - b; }
            : compareFunction;

        // 1. 创建一个状态对象来传递给所有辅助函数，避免长参数列表
        var state:Object = new Object();
        state.arr = arr;
        state.compare = compare;
        state.runStack = new Array(); // 存储 run 的堆栈 [{base:Number, len:Number}, ...]
        
        // 2. 计算最小 run 长度
        state.minRun = _calculateMinRun(n);
        
        // 3. 预分配一个足够大的临时数组用于合并
        // 任何一次合并，我们只需要复制较小的 run，其大小最多为 n/2
        state.tempArray = new Array(Math.ceil(n / 2));

        // 4. 迭代数组，寻找 run 并合并
        var remaining:Number = n;
        var lo:Number = 0;
        while (remaining > 0) {
            // 找到下一个 run (如果是降序则反转)
            var runLen:Number = _countRunAndReverse(state, lo);

            // 如果 run 太短，使用插入排序扩展它
            if (runLen < state.minRun) {
                var force:Number = (remaining < state.minRun) ? remaining : state.minRun;
                _insertionSort(state, lo, lo + force - 1);
                runLen = force;
            }

            // 将 run 推入堆栈
            state.runStack.push({base: lo, len: runLen});
            
            // 检查并合并堆栈中的 run 以维持不变量
            _mergeCollapse(state);

            // 移动到下一个片区
            lo += runLen;
            remaining -= runLen;
        }

        // 5. 合并所有剩余的 run
        _mergeForceCollapse(state);
        
        return arr;
    }

    // --- 私有辅助函数 ---
    
    /**
     * 计算最优的 minRun 长度。
     * minRun 范围在 [16, 32] 之间 (对于 MIN_MERGE=32)。
     * 目标是使 n / minRun 约等于或略小于 2 的幂。
     */
    private static function _calculateMinRun(n:Number):Number {
        var r:Number = 0; // 记录 n 的二进制表示中被移掉的位
        while (n >= MIN_MERGE) {
            r |= (n & 1);
            n >>= 1;
        }
        return n + r;
    }

    /**
     * 从指定位置 lo 开始，查找一个连续的升序或降序序列 (run)。
     * 如果是降序，则将其原地反转。
     * @return run 的长度。
     */
    private static function _countRunAndReverse(state:Object, lo:Number):Number {
        var arr:Array = state.arr;
        var compare:Function = state.compare;
        var hi:Number = lo + 1;
        
        if (hi >= arr.length) {
            return 1;
        }

        // 确定 run 的方向
        if (compare(arr[lo], arr[hi++]) > 0) { // 降序
            while (hi < arr.length && compare(arr[hi - 1], arr[hi]) > 0) {
                hi++;
            }
            // 原地反转这个降序 run
            _reverseRange(arr, lo, hi - 1);
        } else { // 升序
            while (hi < arr.length && compare(arr[hi - 1], arr[hi]) <= 0) {
                hi++;
            }
        }
        
        return hi - lo;
    }

    /**
     * 对数组的指定范围 [lo, hi] 进行原地反转。
     */
    private static function _reverseRange(arr:Array, lo:Number, hi:Number):Void {
        while (lo < hi) {
            var t:Object = arr[lo];
            arr[lo++] = arr[hi];
            arr[hi--] = t;
        }
    }
    
    /**
     * 对数组的指定范围 [left, right] 使用插入排序。
     * 用于处理长度小于 minRun 的小数组。
     */
    private static function _insertionSort(state:Object, left:Number, right:Number):Void {
        var arr:Array = state.arr;
        var compare:Function = state.compare;

        for (var i:Number = left + 1; i <= right; i++) {
            var key:Object = arr[i];
            var j:Number = i - 1;
            while (j >= left && compare(arr[j], key) > 0) {
                arr[j + 1] = arr[j];
                j--;
            }
            arr[j + 1] = key;
        }
    }

    /**
     * 检查堆栈顶部的 run 是否违反 Timsort 不变量，如果违反则进行合并。
     * 不变量:
     * 1. len(C) > len(B) + len(A)
     * 2. len(B) > len(A)
     * (其中 A, B, C 是堆栈顶部的三个 run)
     */
    private static function _mergeCollapse(state:Object):Void {
        var stack:Array = state.runStack;
        while (stack.length > 1) {
            var n:Number = stack.length - 2; // 指向 run B
            
            // 如果存在 run C 且 len(C) <= len(B) + len(A)
            if (n > 0 && stack[n - 1].len <= stack[n].len + stack[n + 1].len) {
                if (stack[n - 1].len < stack[n + 1].len) {
                    _mergeAt(state, n - 1); // 合并 C 和 B
                } else {
                    _mergeAt(state, n); // 合并 B 和 A
                }
            } 
            // 如果 len(B) <= len(A)
            else if (stack[n].len <= stack[n + 1].len) {
                _mergeAt(state, n); // 合并 B 和 A
            } 
            // 满足不变量，退出
            else {
                break;
            }
        }
    }
    
    /**
     * 强制合并堆栈中所有剩余的 run，直到只剩一个。
     */
    private static function _mergeForceCollapse(state:Object):Void {
        var stack:Array = state.runStack;
        while (stack.length > 1) {
            var n:Number = stack.length - 2;
            // 优先合并较小的 run 对
            if (n > 0 && stack[n - 1].len < stack[n + 1].len) {
                 _mergeAt(state, n - 1);
            } else {
                 _mergeAt(state, n);
            }
        }
    }

    /**
     * 合并堆栈中索引为 i 和 i+1 的两个相邻 run。
     */
    private static function _mergeAt(state:Object, i:Number):Void {
        var stack:Array = state.runStack;
        var runA:Object = stack[i];
        var runB:Object = stack[i+1];

        // 更新堆栈：将两个 run 合并为一个
        stack[i] = {base: runA.base, len: runA.len + runB.len};
        stack.splice(i + 1, 1); // 移除旧的 runB

        // 确定哪个 run 更小，并将其复制到 tempArray
        // 这是关键优化：减少数据复制量
        var k:Number;
        if (runA.len <= runB.len) {
            for(k=0; k<runA.len; k++) {
                state.tempArray[k] = state.arr[runA.base + k];
            }
            _mergeLo(state, runA, runB);
        } else {
            for(k=0; k<runB.len; k++) {
                state.tempArray[k] = state.arr[runB.base + k];
            }
            _mergeHi(state, runA, runB);
        }
    }

    /**
     * 合并两个 run，其中 runA (较小者) 已被复制到 tempArray。
     */
    private static function _mergeLo(state:Object, runA:Object, runB:Object):Void {
        var arr:Array = state.arr;
        var compare:Function = state.compare;
        var temp:Array = state.tempArray;
        
        var dest:Number = runA.base;
        var ptr1:Number = 0;         // 指向 temp (runA)
        var ptr2:Number = runB.base; // 指向 arr (runB)
        
        var len1:Number = runA.len;
        var len2:Number = runB.len;

        while(ptr1 < len1 && ptr2 < runB.base + len2) {
            if (compare(temp[ptr1], arr[ptr2]) <= 0) {
                arr[dest++] = temp[ptr1++];
            } else {
                arr[dest++] = arr[ptr2++];
            }
        }
        
        // 复制 temp 中剩余的元素
        while(ptr1 < len1) {
            arr[dest++] = temp[ptr1++];
        }
    }
    
    /**
     * 合并两个 run，其中 runB (较小者) 已被复制到 tempArray。
     */
    private static function _mergeHi(state:Object, runA:Object, runB:Object):Void {
        var arr:Array = state.arr;
        var compare:Function = state.compare;
        var temp:Array = state.tempArray;
        
        var dest:Number = runB.base + runB.len - 1;
        var ptr1:Number = runA.base + runA.len - 1; // 指向 arr (runA)
        var ptr2:Number = runB.len - 1;             // 指向 temp (runB)
        
        while(ptr1 >= runA.base && ptr2 >= 0) {
            if (compare(arr[ptr1], temp[ptr2]) > 0) {
                arr[dest--] = arr[ptr1--];
            } else {
                arr[dest--] = temp[ptr2--];
            }
        }
        
        // 复制 temp 中剩余的元素
        while(ptr2 >= 0) {
            arr[dest--] = temp[ptr2--];
        }
    }
}